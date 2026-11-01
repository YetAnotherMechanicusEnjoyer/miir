#!/usr/bin/env bash

#    __  ____ _
#   /  |/  (_|_)___
#  / /|_/ / / / __/
# /_/  /_/_/_/_/
# Keizaal Online / Vortex setup
# https://github.com/YetAnotherMechanicusEnjoyer/miir

set -Eeuo pipefail

readonly VORTEX_ICON_URL="https://raw.githubusercontent.com/Nexus-Mods/Vortex/master/assets/images/vortex.png"
readonly KEIZAAL_ICON_URL="https://keizaal.com/_next/image?url=%2Fi%2Fkeizaalonline.png&w=256&q=75"
readonly DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
readonly APPLICATIONS_DIR="${1:-$DATA_HOME/applications}"
readonly ICON_DIR="${MIIR_ICON_DIR:-$DATA_HOME/icons/miir}"
readonly PNG_SIGNATURE="89504e470d0a1a0a"

DISABLE_COLORS=false

_change_color_state() {
  if [ "$DISABLE_COLORS" = true ]; then
    C_DIM=""
    C_INFO=""
    C_WARN=""
    C_ERROR=""
    C_CYAN=""
    C_PATH=""
    C_YPATH=""
    C_RESET=""
    return
  fi

  C_DIM=$'\x1b[0;90m'
  C_INFO=$'\x1b[0;1;92m'
  C_WARN=$'\x1b[0;1;93m'
  C_ERROR=$'\x1b[0;1;91m'
  C_CYAN=$'\x1b[0;1;96m'
  C_PATH=$'\x1b[0;1;3;94m'
  C_YPATH=$'\x1b[0;1;3;93m'
  C_RESET=$'\x1b[0m'
}

[ -n "${NO_COLOR:-}" ] && DISABLE_COLORS=true
_change_color_state

_info() {
  echo -e "${C_DIM}:: ${C_INFO}INFO${C_RESET}${C_DIM} - $1${C_RESET}"
}

_warn() {
  echo -e "${C_DIM}:: ${C_WARN}WARN${C_RESET}${C_DIM} - $1${C_RESET}" >&2
}

_error() {
  echo -e "${C_DIM}:: ${C_ERROR}ERROR${C_RESET}${C_DIM} - $1${C_RESET}" >&2
}

_is_png() {
  local signature

  [[ -s "$1" ]] || return 1
  signature="$(od -An -N8 -tx1 "$1" | tr -d ' \n')"
  [[ "$signature" == "$PNG_SIGNATURE" ]]
}

_download_png() {
  local label="$1"
  local url="$2"
  local destination="$3"
  local temporary
  local signature

  if [[ "${MIIR_REFRESH_ICONS:-0}" != 1 ]] && _is_png "$destination"; then
    _info "Using cached ${C_PATH}${label}${C_DIM} icon."
    return 0
  fi

  temporary="$(mktemp "${destination}.XXXXXX")" || return 1

  _info "Downloading ${C_PATH}${label}${C_DIM} icon..."
  if ! curl --fail --location --silent --show-error \
    --retry 2 --connect-timeout 15 --max-time 120 \
    --output "$temporary" "$url"; then
    rm -f -- "$temporary"
    _error "Could not download ${C_PATH}${label}${C_DIM} icon."
    return 1
  fi

  if ! _is_png "$temporary"; then
    rm -f -- "$temporary"
    _error "The downloaded ${C_PATH}${label}${C_DIM} asset is not a PNG."
    return 1
  fi

  if ! mv -f -- "$temporary" "$destination"; then
    rm -f -- "$temporary"
    _error "Could not install ${C_PATH}${label}${C_DIM} icon."
    return 1
  fi
}

_set_desktop_icon() {
  local desktop_file="$1"
  local icon_path="$2"
  local temporary

  [[ ! -f "$desktop_file" ]] && _warn "Desktop entry not found: ${C_PATH}$desktop_file${C_DIM}." && return 1

  temporary="$(mktemp "${desktop_file}.XXXXXX")" || return 1

  if ! MIIR_ICON_PATH="$icon_path" awk '
    function flush_icon() {
      if (in_entry && !icon_written) {
        print "Icon=" ENVIRON["MIIR_ICON_PATH"]
        icon_written = 1
      }
    }
    /^\[Desktop Entry\]$/ {
      flush_icon()
      in_entry = 1
      found_entry = 1
      icon_written = 0
      print
      next
    }
    /^\[/ {
      flush_icon()
      in_entry = 0
      print
      next
    }
    in_entry && /^Icon=/ {
      if (!icon_written)
        print "Icon=" ENVIRON["MIIR_ICON_PATH"]
      icon_written = 1
      next
    }
    { print }
    END {
      flush_icon()
      if (!found_entry)
        exit 2
    }
  ' "$desktop_file" >"$temporary"; then
    rm -f -- "$temporary"
    _error "Could not update ${C_PATH}$desktop_file${C_DIM}."
    return 1
  fi

  if ! chmod --reference="$desktop_file" "$temporary" ||
    ! mv -f -- "$temporary" "$desktop_file"; then
    rm -f -- "$temporary"
    _error "Could not save ${C_PATH}$desktop_file${C_DIM}."
    return 1
  fi

  if command -v desktop-file-validate >/dev/null 2>&1; then
    if ! desktop-file-validate "$desktop_file"; then
      _warn "Desktop entry validation failed: $desktop_file."
      return 1
    fi
  fi

  _info "Applied icon to ${C_PATH}$(basename "$desktop_file")${C_DIM}."
}

main() {
  local failed=0
  local vortex_desktop="$APPLICATIONS_DIR/miir-vortex.desktop"
  local keizaal_desktop="$APPLICATIONS_DIR/keizaal-online.desktop"
  local vortex_icon="$ICON_DIR/vortex.png"
  local keizaal_icon="$ICON_DIR/keizaal.png"

  if ! command -v curl >/dev/null 2>&1; then
    _error "curl is required to download applicaton icons."
    return 1
  fi

  mkdir -p "$ICON_DIR" || {
    _error "Could not create icon directory: $ICON_DIR." && return 1
  }

  if [[ -f "$vortex_desktop" ]]; then
    if _download_png "Vortex" "$VORTEX_ICON_URL" "$vortex_icon"; then
      _set_desktop_icon "$vortex_desktop" "$vortex_icon" || failed=1
    else
      failed=1
    fi
  else
    _warn "Vortex desktop entry is absent. Skipping..."
  fi

  if [[ -f "$keizaal_desktop" ]]; then
    if _download_png "Keizaal Online" "$KEIZAAL_ICON_URL" "$keizaal_icon"; then
      _set_desktop_icon "$keizaal_desktop" "$keizaal_icon" || failed=1
    else
      failed=1
    fi
  else
    _warn "Keizaal desktop entry is absent. Skipping..."
  fi

  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APPLICATIONS_DIR" >/dev/null 2>&1 || true
  fi

  if ((failed != 0)); then
    _warn "One or more application icons could not be installed."
    return 1
  fi

  _info "Application icons are ready."
}

main "$@"
