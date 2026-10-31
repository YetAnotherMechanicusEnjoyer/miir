#!/usr/bin/env bash

declare -gA MIIR_PACKAGE_MAP
declare -ga PACKAGE_RESOLVED=()
declare -ga PACKAGE_MISSING=()

PACKAGE_MANAGER="${PACKAGE_MANAGER:-}"

_package_manager_detect() {
  local id=""
  local id_like=""
  local candidate
  local -a candidates=()

  if [[ -n "$PACKAGE_MANAGER" ]]; then
    command -v "$PACKAGE_MANAGER" >/dev/null 2>&1 && return 0
    _error "${C_PATH}$PACKAGE_MANAGER${C_DIM} is not installed."
    return 127
  fi

  if [[ -r "/etc/os-release" ]]; then
    . /etc/os-release
    id="${ID:-}"
    id_like="${ID_LIKE:-}"
  fi

  case "$id" in
  arch | artix | cachyos | endeavouros | garuda | manjaro)
    if ((EUID != 0)); then
      candidates=(yay pacman)
    else
      candidates=(pacman)
    fi
    ;;
  debian | ubuntu | linuxmint | pop | elementary | zorin | kali | raspbian)
    candidates=(apt-get apt)
    ;;
  fedora | nobara | rhel | centos | rocky | almalinux)
    candidates=(dnf yum)
    ;;
  alpine) candidates=(apk) ;;
  nixos) candidates=(nix) ;;
  esac

  if ((${#candidates[@]} == 0)); then
    case " $id_like " in
    *" arch "*)
      if ((EUID != 0)); then
        candidates=(yay pacman)
      else
        candidates=(pacman)
      fi
      ;;
    *" debian "*) candidates=(apt-get apt) ;;
    *" fedora "* | *" rhel "* | *" centos "*) candidates=(dnf yum) ;;
    esac
  fi

  if ((${#candidates[@]} == 0)); then
    candidates=(pacman apt-get apt dnf yum apk nix)
    if ((EUID != 0)); then
      candidates=(yay "${candidates[@]}")
    fi
  fi

  for candidate in "${candidates[@]}"; do
    _checkCommandExists "$candidate" && PACKAGE_MANAGER="$candidate" && return 0
  done

  _error "no supported package manager found."
  return 127
}

_package_resolve() {
  local logical key fallback mapped
  local -a resolved=()

  if (($# == 0)); then
    _warn "Usage: _package_resolve <package> [...]"
    return 2
  fi

  _package_manager_detect || return $?
  PACKAGE_RESOLVED=()

  for logical in "$@"; do
    key="${logical}|${PACKAGE_MANAGER}"
    mapped="${MIIR_PACKAGE_MAP[$key]-}"

    if [[ -z "$mapped" ]]; then
      fallback=""
      case "$PACKAGE_MANAGER" in
      yay) fallback="pacman" ;;
      pacman) fallback="yay" ;;
      apt-get) fallback="apt" ;;
      apt) fallback="apt-get" ;;
      dnf) fallback="yum" ;;
      yum) fallback="dnf" ;;
      esac

      if [[ -n "$fallback" ]]; then
        key="${logical}|${fallback}"
        mapped="${MIIR_PACKAGE_MAP[$key]-}"
      fi
    fi

    [[ -n "$mapped" ]] || mapped="$logical"
    read -r -a resolved <<<"$mapped"
    PACKAGE_RESOLVED+=("${resolved[@]}")
  done
  return 0
}

_nix_profile_has() {
  local profile="$1"
  local package="$2"

  awk -v pkg="$package" '
        BEGIN { found = 0; name = "" }
        /^Name:/ {
            name = $0
            sub(/^Name:[[:space:]]*/, "", name)
            if (name == pkg) found = 1
        }
        /^Flake attribute:/ {
            attr = $0
            sub(/^Flake attribute:[[:space:]]*/, "", attr)
            if (attr == pkg ||
                substr(attr, length(attr) - length(pkg) + 1) == "." pkg)
                found = 1
        }
        END { exit(found ? 0 : 1) }
    ' <<<"$profile"
}

_package_check() {
  local pkg status nix_profile="" installed

  if (($# == 0)); then
    _warn "Usage: _package_check <package> [...]"
    return 2
  fi

  _package_resolve "$@" || return $?
  PACKAGE_MISSING=()

  if [[ "$PACKAGE_MANAGER" == "nix" ]]; then
    if ! nix_profile=$(nix --extra-experimental-features \
      "nix-command flakes" profile list 2>/dev/null); then
      _error 'cannot read the Nix user profile.'
      return 2
    fi
  fi

  for pkg in "${PACKAGE_RESOLVED[@]}"; do
    installed=0
    case "$PACKAGE_MANAGER" in
    pacman | yay)
      if pacman -Q -- "$pkg" >/dev/null 2>&1; then
        installed=1
      fi
      ;;
    apt-get | apt)
      status=$(dpkg-query -W -f='${Status}' -- "$pkg" \
        2>/dev/null) || status=""
      if [[ "$status" == "install ok installed" ]]; then
        installed=1
      fi
      ;;
    dnf | yum)
      if rpm -q -- "$pkg" >/dev/null 2>&1; then
        installed=1
      fi
      ;;
    apk)
      if apk info -e -- "$pkg" >/dev/null 2>&1; then
        installed=1
      fi
      ;;
    nix)
      if _nix_profile_has "$nix_profile" "$pkg"; then
        installed=1
      fi
      ;;
    *)
      _error "unsupported manager: ${PACKAGE_MANAGER}"
      return 2
      ;;
    esac
    if ((installed == 0)); then
      PACKAGE_MISSING+=("$pkg")
    fi
  done

  ((${#PACKAGE_MISSING[@]} == 0))
}

_run_as_root() {
  if ((EUID == 0)); then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  elif command -v doas >/dev/null 2>&1; then
    doas "$@"
  else
    _error "${C_PATH}sudo${C_DIM} or ${C_PATH}doas${C_DIM} is required."
    return 127
  fi
}

_package_install() {
  local status pkg
  local -a packages=()
  local -a nix_packages=()

  if (($# == 0)); then
    _warn 'Usage: _package_install <package> [...]'
    return 2
  fi
  _package_manager_detect || return $?

  if _package_check "$@"; then
    return 0
  else
    status=$?
    ((status == 1)) || return "$status"
  fi

  packages=("${PACKAGE_MISSING[@]}")
  ((${#packages[@]} > 0)) || return 0

  case "$PACKAGE_MANAGER" in
  pacman)
    _run_as_root pacman -S --needed --noconfirm "${packages[@]}"
    ;;
  yay)
    if ((EUID == 0)); then
      _error "${C_PATH}yay${C_DIM} must not be run as root"
      return 2
    fi
    yay -S --needed --noconfirm "${packages[@]}"
    ;;
  apt-get)
    _run_as_root apt-get install -y --no-install-recommends \
      "${packages[@]}"
    ;;
  apt)
    _run_as_root apt install -y --no-install-recommends \
      "${packages[@]}"
    ;;
  dnf | yum)
    _run_as_root "$PACKAGE_MANAGER" install -y "${packages[@]}"
    ;;
  apk)
    _run_as_root apk add "${packages[@]}"
    ;;
  nix)
    for pkg in "${packages[@]}"; do
      nix_packages+=("nixpkgs#$pkg")
    done
    nix --extra-experimental-features "nix-command flakes" \
      profile install "${nix_packages[@]}"
    ;;
  *)
    _error "unsupported manager: $PACKAGE_MANAGER"
    return 2
    ;;
  esac
}
