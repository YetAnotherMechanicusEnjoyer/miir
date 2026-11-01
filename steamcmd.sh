#!/usr/bin/env bash

#    __  ____ _
#   /  |/  (_|_)___
#  / /|_/ / / / __/
# /_/  /_/_/_/_/
# Keizaal Online / Vortex setup
# https://github.com/YetAnotherMechanicusEnjoyer/miir

STEAMCMD_URL="https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"
STEAMCMD_DIR="${STEAMCMD_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/steamcmd}"
STEAMCMD_BIN="${STEAMCMD_BIN:-}"

STEAM_DEPOT="${STEAM_DEPOT:-${STEAMPATH:-$HOME/.local/share/Steam}/ubuntu12_32/steamapps/content/app_489830}"
SKYRIM_DIR="${SKYRIM_DIR:-${STEAMPATH:-$HOME/.local/share/Steam}/steamapps/common/Skyrim Special Edition}"

_steamcmd_set_wrapper() {
  local target="$1"
  local wrapper="$HOME/.local/bin/steamcmd"

  mkdir -p "${wrapper%/*}" || return 1
  printf '#!/usr/bin/env bash\nexec %q "$@"\n' "$target" >"$wrapper" || return 1
  chmod 755 "$wrapper" || return 1
  export PATH="$HOME/.local/bin:$PATH"
  export STEAMCMD_BIN="$wrapper"
}

_steamcmd_set_flatpak_wrapper() {
  local wrapper="$HOME/.local/bin/steamcmd"

  mkdir -p "${wrapper%/*}" || return 1
  cat >"$wrapper" <<'WRAPPER'
#!/usr/bin/env bash
exec flatpak run --command=steamcmd com.valvesoftware.Steam "$@"
WRAPPER
  chmod 755 "$wrapper" || return 1
  export PATH="$HOME/.local/bin:$PATH"
  export STEAMCMD_BIN="$wrapper"
}

_steamcmd_find_system_binary() {
  local candidate

  candidate="$(command -v steamcmd 2>/dev/null || true)"
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  for candidate in /usr/games/steamcmd /usr/bin/steamcmd; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

_steamcmd_install_tarball() {
  local archive

  if ! command -v curl >/dev/null 2>&1 ||
    ! command -v tar >/dev/null 2>&1; then
    _error "${C_PATH}curl${C_DIM} and ${C_PATH}tar${C_DIM} are required."
    return 127
  fi
  archive="$(mktemp)" || return 1
  if ! curl --fail --location --retry 3 \
    "$STEAMCMD_URL" --output "$archive"; then
    rm -f "$archive"
    return 1
  fi
  if ! tar -tzf "$archive" >/dev/null; then
    _error "downloaded SteamCMD archive is invalid."
    rm -f "$archive"
    return 1
  fi
  mkdir -p "$STEAMCMD_DIR" || {
    rm -f "$archive"
    return 1
  }
  if ! tar -xzf "$archive" -C "$STEAMCMD_DIR"; then
    rm -f "$archive"
    return 1
  fi
  rm -f "$archive"
  chmod 755 "$STEAMCMD_DIR/steamcmd.sh" || return 1
  _steamcmd_set_wrapper "$STEAMCMD_DIR/steamcmd.sh"
}

_steamcmd_enable_arch_multilib() {
  local conf="/etc/pacman.conf"

  if grep -Eq '^[[:space:]]*\[multilib\]' "$conf"; then
    if ! awk '
            /^\[multilib\]/ { inside=1; next }
            /^\[/ { inside=0 }
            inside && /^[[:space:]]*Include[[:space:]]*=/ { found=1 }
            END { exit(found ? 0 : 1) }
        ' "$conf"; then
      _sudo sed -i \
        '/^[[:space:]]*\[multilib\]/a Include = /etc/pacman.d/mirrorlist' \
        "$conf"
    fi
    return 0
  fi
  if grep -Eq '^[[:space:]]*#\[multilib\]' "$conf"; then
    _sudo sed -i \
      '/^[[:space:]]*#\[multilib\]/,/^[[:space:]]*#Include = \/etc\/pacman.d\/mirrorlist/ s/^[[:space:]]*#//' \
      "$conf"
  else
    printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' |
      _sudo tee -a "$conf" >/dev/null
  fi
}

_steamcmd_enable_debian_nonfree() {
  local file
  local changed=0
  local -a list_files=()
  local -a source_files=()

  [[ -f /etc/apt/sources.list ]] && list_files+=(/etc/apt/sources.list)
  for file in /etc/apt/sources.list.d/*.list; do
    [[ -f "$file" ]] && list_files+=("$file")
  done
  for file in /etc/apt/sources.list.d/*.sources; do
    [[ -f "$file" ]] && source_files+=("$file")
  done

  for file in "${source_files[@]}"; do
    grep -qE '^URIs:.*debian\.(org|net)' "$file" || continue
    if ! grep -qE '^Components:.*[[:space:]]non-free([[:space:]]|$)' "$file"; then
      _sudo cp -an "$file" "$file.miir.bak" || return 1
      _sudo sed -i -E \
        '/^Components:/ { /[[:space:]]non-free([[:space:]]|$)/! s/$/ non-free/; }' \
        "$file" || return 1
      changed=1
    fi
  done

  for file in "${list_files[@]}"; do
    grep -qE '^[[:space:]]*deb(-src)?[[:space:]].*debian\.(org|net)' \
      "$file" || continue
    if ! grep -qE '^[[:space:]]*deb(-src)?[[:space:]].*[[:space:]]non-free([[:space:]]|$)' \
      "$file"; then
      _sudo cp -an "$file" "$file.miir.bak" || return 1
      _sudo sed -i -E \
        '/^[[:space:]]*deb(-src)?[[:space:]].*debian\.(org|net)/ { /[[:space:]]non-free([[:space:]]|$)/! s/[[:space:]]*$/ non-free/; }' \
        "$file" || return 1
      changed=1
    fi
  done

  if ((changed == 0)); then
    if grep -RqsE '^Components:.*[[:space:]]non-free([[:space:]]|$)|^[[:space:]]*deb(-src)?[[:space:]].*[[:space:]]non-free([[:space:]]|$)' \
      /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
      return 0
    fi
    _error "could not enable Debian non-free repositories. Add the "non-free" component to your Debian sources."
    return 1
  fi
}

_steamcmd_install_apt() {
  local distro="$1"

  if ! dpkg --print-foreign-architectures | grep -qx i386; then
    _sudo dpkg --add-architecture i386 || return 1
  fi

  if [[ "$distro" == "ubuntu" || "$distro" == "linuxmint" ||
    "$distro" == "pop" || "$distro" == "zorin" ||
    "$distro" == "elementary" ]]; then
    _sudo apt-get update || return 1
    if ! command -v add-apt-repository >/dev/null 2>&1; then
      _sudo apt-get install -y software-properties-common || return 1
    fi
    _sudo add-apt-repository -y multiverse || return 1
  else
    _steamcmd_enable_debian_nonfree || return 1
  fi

  _sudo apt-get update || return 1
  _info "SteamCMD may display Valve's license agreement during installation."
  _sudo apt-get install -y steamcmd:i386 || return 1

  local bin
  bin="$(_steamcmd_find_system_binary)" || {
    _error "steamcmd was installed but its binary was not found."
    return 1
  }
  _steamcmd_set_wrapper "$bin"
}

_steamcmd_install_arch() {
  _steamcmd_enable_arch_multilib || return 1

  if command -v yay >/dev/null 2>&1; then
    yay -Syu --needed steamcmd || return 1
    local bin
    bin="$(_steamcmd_find_system_binary)" || return 1
    _steamcmd_set_wrapper "$bin"
  else
    _info "Updating package databases and installing 32-bit runtime."
    _sudo pacman -Syu --needed curl tar lib32-gcc-libs || return 1
    _steamcmd_install_tarball
  fi
}

_steamcmd_install_fedora() {
  local manager="dnf"

  command -v dnf >/dev/null 2>&1 || manager="yum"
  _sudo "$manager" install -y \
    curl tar ca-certificates glibc.i686 libstdc++.i686 libgcc.i686 || return 1
  _steamcmd_install_tarball
}

_steamcmd_install_alpine() {
  if ! command -v flatpak >/dev/null 2>&1; then
    _sudo apk add flatpak || return 1
  fi
  flatpak remote-add --user --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo || return 1
  flatpak install --user -y flathub com.valvesoftware.Steam || return 1
  _steamcmd_set_flatpak_wrapper
}

_steamcmd_install_nix() {
  NIXPKGS_ALLOW_UNFREE=1 nix \
    --extra-experimental-features 'nix-command flakes' \
    --impure profile install nixpkgs#steamcmd || return 1

  local bin
  bin="$(_steamcmd_find_system_binary)" ||
    bin="$HOME/.nix-profile/bin/steamcmd"
  [[ -x "$bin" ]] || {
    _error "steamcmd was installed but is not in ${C_PATH}PATH${C_DIM}."
    return 1
  }
  _steamcmd_set_wrapper "$bin"
}

_steamcmd_install() {
  local distro=""
  local arch="$(uname -m)"

  if ((EUID == 0)); then
    _error "run ${C_YPATH}Miir${C_DIM} as a regular user, not root."
    return 2
  fi
  if [[ "$arch" != "x86_64" ]]; then
    _error "SteamCMD installer currently supports x86_64 only."
    return 2
  fi
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    distro="${ID:-}"
  fi

  case "$distro" in
  arch | artix | cachyos | endeavouros | garuda | manjaro)
    _steamcmd_install_arch
    ;;
  debian | ubuntu | linuxmint | pop | zorin | elementary)
    _steamcmd_install_apt "$distro"
    ;;
  fedora | nobara | rhel | centos | rocky | almalinux)
    _steamcmd_install_fedora
    ;;
  alpine)
    _steamcmd_install_alpine
    ;;
  nixos)
    _steamcmd_install_nix
    ;;
  *)
    _error "unsupported distribution: $distro"
    return 2
    ;;
  esac || return $?

  if [[ -z "$STEAMCMD_BIN" ]]; then
    _error "SteamCMD installation did not provide a command."
    return 1
  fi
  _info "SteamCMD installed successfully: ${C_PATH}$STEAMCMD_BIN${C_DIM}"
  "$STEAMCMD_BIN" +quit
}

_steam_download_depot() {
  local appid="$1"
  local depotid="$2"
  local manifestid="$3"
  local destination="${4:-}"

  if ! command -v steamcmd >/dev/null 2>&1; then
    _error "${C_PATH}steamcmd${C_DIM} is not installed."
    return 127
  fi

  if [[ ! "$appid" =~ ^[0-9]+$ ||
    ! "$depotid" =~ ^[0-9]+$ ||
    ! "$manifestid" =~ ^[0-9]+$ ]]; then
    _error "invalid Steam depot identifiers."
    return 2
  fi

  _info "Downloading depot ${C_PATH}$depotid${C_DIM} for app ${C_PATH}$appid${C_DIM} from manifest ${C_PATH}$manifestid${C_DIM} to ${C_PATH}$destination${C_DIM}..."

  local -a cmd=(steamcmd)

  cmd+=(+login "$STEAM_USER")
  if [[ -n "$destination" ]]; then
    cmd+=(+download_depot "$appid" "$depotid"
      "$manifestid" "$destination")
  else
    cmd+=(+download_depot "$appid" "$depotid" "$manifestid")
  fi
  cmd+=(+quit)

  "${cmd[@]}"
}

_steam_depot_merge() {
  local depot_dir="$1"
  local skyrim_dir="$2"

  [[ ! -d "$depot_dir" ]] && _error "Depot not found: ${C_PATH}$depot_dir" && return 1
  [[ ! -d "$skyrim_dir" ]] && _error "Skyrim not found: ${C_PATH}$skyrim_dir" && return 1

  _info "Copying ${C_PATH}${depot_dir}${C_DIM} to ${C_PATH}${skyrim_dir}${C_DIM}..."
  cp -a -- "$depot_dir/." "$skyrim_dir/" || {
    _error "Failed to merge depot ${C_PATH}$depot_dir"
    return 1
  }
}

_steam_downgrade_needed() {
  local state="$1"
  local expected="$2"
  local executable="$SKYRIM_DIR/SkyrimSE.exe"
  local checksum
  local stored_expected
  local stored_checksum

  [[ ! -f "$executable" ]] && _error "SkyrimSE.exe not found." && return 2

  checksum=$(cksum <"$executable") || {
    _error "During: ${C_CYAN}cksum <\"$executable\"${C_DIM}."
    return 2
  }

  [[ ! -f "$state" ]] && return 0

  stored_expected=$(sed -n '1,3p' "$state")
  stored_checksum=$(sed -n '4p' "$state")

  [[ "$stored_expected" != "$expected" ]] && return 0
  [[ "$stored_checksum" != "$checksum" ]] && return 0

  return 1
}

_steamcmd_downgrade_keizaal() {
  local state="$SKYRIM_DIR/.miir-depot-state"
  local expected="489831:8442952117333549665
489832:8042843504692938467
489833:1914580699073641964"
  local checksum
  local depot

  if _steam_downgrade_needed "$state" "$expected"; then
    :
  else
    local status=$?

    [[ "$status" -eq 1 ]] && _info "Downgrade already applied." && return 0

    _error "Fetching if downgrade is needed (status: $status)."
    return "$status"
  fi

  for depot in \
    "489831:8442952117333549665" \
    "489832:8042843504692938467" \
    "489833:1914580699073641964"; do
    IFS=: read -r depot_id manifest_id <<<"$depot"

    _steam_download_depot "489830" "$depot_id" "$manifest_id" || return 1
  done

  for depot in 489831 489832 489833; do
    _steam_depot_merge "$STEAM_DEPOT/depot_$depot" "$SKYRIM_DIR" || return 1
  done

  checksum=$(cksum <"$SKYRIM_DIR/SkyrimSE.exe") || return 1

  {
    printf '%s\n' "$expected"
    printf '%s\n' "$checksum"
  } >"$state.tmp" || return 1

  mv -- "$state.tmp" "$state" || return 1

  _info "Downgrade completed successfully!"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo -e "\x1b[0;90m:: \x1b[0;1;91mERROR\x1b[0;90m - Script must be run via \x1b[0;1;3;93mMiir\x1b[0;90m.\x1b[0m"
  exit 1
fi
