#!/usr/bin/env bash

#    __  ____ _
#   /  |/  (_|_)___
#  / /|_/ / / / __/
# /_/  /_/_/_/_/
# Keizaal Online / Vortex setup
# https://github.com/YetAnotherMechanicusEnjoyer/miir

_desktop_quote() {
  local value="$1"

  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//%/%%}"
  printf '"%s"' "$value"
}

_write_vortex_launcher() {
  local launcher="$1"
  local protontricks_launch="$2"
  local vortex_exe="$3"

  {
    printf '#!/usr/bin/env bash\n'
    printf 'STEAM_DIR=%q\n' "$STEAMPATH"
    printf 'PROTONTRICKS_LAUNCH=%q\n' "$protontricks_launch"
    printf 'SKYRIM_APPID=%q\n' "$SKYRIM_APPID"
    printf 'VORTEX_EXE=%q\n' "$vortex_exe"
    cat <<'LAUNCHER'
export STEAM_DIR
exec "$PROTONTRICKS_LAUNCH" --appid "$SKYRIM_APPID" \
  "$VORTEX_EXE" --disable-gpu --no-sandbox "$@"
LAUNCHER
  } >"$launcher" || return 1

  chmod 755 "$launcher"
}

_write_nxm_handler() {
  local handler="$1"
  local protontricks_launch="$2"
  local vortex_exe="$3"

  {
    printf '#!/usr/bin/env bash\n'
    printf 'STEAM_DIR=%q\n' "$STEAMPATH"
    printf 'PROTONTRICKS_LAUNCH=%q\n' "$protontricks_launch"
    printf 'SKYRIM_APPID=%q\n' "$SKYRIM_APPID"
    printf 'VORTEX_EXE=%q\n' "$vortex_exe"
    cat <<'HANDLER'
set -u

if (($# != 1)); then
  printf 'Expected exactly one NXM URL.\n' >&2
  exit 2
fi

case "$1" in
  nxm://*) ;;
  *)
    printf 'Invalid NXM URL: %s\n' "$1" >&2
    exit 2
    ;;
esac

export STEAM_DIR
exec "$PROTONTRICKS_LAUNCH" --appid "$SKYRIM_APPID" \
  "$VORTEX_EXE" --disable-gpu --no-sandbox --install "$1"
HANDLER
  } >"$handler" || return 1

  chmod 755 "$handler"
}

_write_vortex_desktop() {
  local desktop="$1"
  local launcher="$2"

  {
    printf '[Desktop Entry]\n'
    printf 'Type=Application\n'
    printf 'Name=Vortex (Keizaal Online)\n'
    printf 'Exec=%s\n' "$(_desktop_quote "$launcher")"
    printf 'Terminal=false\n'
    printf 'Categories=Game;Utility;\n'
    printf 'StartupNotify=true\n'
  } >"$desktop"
}

_write_nxm_desktop() {
  local desktop="$1"
  local handler="$2"

  {
    printf '[Desktop Entry]\n'
    printf 'Type=Application\n'
    printf 'Name=Vortex NXM Handler (Keizaal Online)\n'
    printf 'NoDisplay=true\n'
    printf 'Exec=/usr/bin/env bash %s %%u\n' \
      "$(_desktop_quote "$handler")"
    printf 'MimeType=%s;\n' "$NXM_MIME"
    printf 'Terminal=false\n'
    printf 'StartupNotify=false\n'
  } >"$desktop"
}

_write_keizaal_launcher() {
  local launcher="$1"
  local protontricks_launch="$2"
  local keizaal_exe="$3"

  {
    printf '#!/usr/bin/env bash\n'
    printf 'STEAM_DIR=%q\n' "$STEAMPATH"
    printf 'PROTONTRICKS_LAUNCH=%q\n' "$protontricks_launch"
    printf 'SKYRIM_APPID=%q\n' "$SKYRIM_APPID"
    printf 'KEIZAAL_EXE=%q\n' "$keizaal_exe"
    cat <<'LAUNCHER'
export STEAM_DIR
exec "$PROTONTRICKS_LAUNCH" --appid "$SKYRIM_APPID" \
  "$KEIZAAL_EXE" "$@"
LAUNCHER
  } >"$launcher" || return 1

  chmod 755 "$launcher"
}

_write_keizaal_desktop() {
  local desktop="$1"
  local launcher="$2"

  {
    printf '[Desktop Entry]\n'
    printf 'Type=Application\n'
    printf 'Name=Keizaal Online\n'
    printf 'Exec=/usr/bin/env bash %s %%u\n' \
      "$(_desktop_quote "$launcher")"
    printf 'MimeType=%s;\n' "$KEIZAAL_MIME"
    printf 'Terminal=false\n'
    printf 'StartupNotify=false\n'
  } >"$desktop"
}

_mimeapps_set_default() {
  local file="$1"
  local mime_type="$2"
  local desktop_id="$3"
  local temporary

  mkdir -p "$(dirname "$file")" || return 1
  temporary="$(mktemp "${file}.miir.XXXXXX")" || return 1

  if [[ -f "$file" ]]; then
    if ! awk -v mime="$mime_type" -v app="$desktop_id" '
      function updated_value(old, count, ids, result, i) {
        result = app ";"
        count = split(old, ids, ";")
        for (i = 1; i <= count; i++) {
          if (ids[i] != "" && ids[i] != app)
            result = result ids[i] ";"
        }
        return result
      }
      /^\[[^]]+\]$/ {
        if (section == "[Default Applications]" && !written) {
          print mime "=" app ";"
          written = 1
        }
        section = $0
        if (section == "[Default Applications]")
          found_default = 1
        print
        next
      }
      section == "[Default Applications]" && index($0, mime "=") == 1 {
        old = substr($0, length(mime) + 2)
        print mime "=" updated_value(old)
        written = 1
        next
      }
      { print }
      END {
        if (section == "[Default Applications]" && !written) {
          print mime "=" app ";"
          written = 1
        }
        if (!found_default) {
          if (NR > 0)
            print ""
          print "[Default Applications]"
          print mime "=" app ";"
        }
      }
    ' "$file" >"$temporary"; then
      rm -f -- "$temporary"
      return 1
    fi
  else
    {
      printf '[Default Applications]\n'
      printf '%s=%s;\n' "$mime_type" "$desktop_id"
    } >"$temporary" || {
      rm -f -- "$temporary"
      return 1
    }
  fi

  chmod 644 "$temporary" || {
    rm -f -- "$temporary"
    return 1
  }
  mv -f -- "$temporary" "$file"
}

_register_mime_association() {
  local mime_type="$1"
  local desktop_file="$2"
  local desktop_id
  local desktop_value
  local desktop
  local -a desktop_values=()
  local -a desktop_parts=()
  local -A seen_desktops=()
  local failed=false

  desktop_id="$(basename "$desktop_file")"

  if ! xdg-mime default "$desktop_id" "$mime_type"; then
    _warn "xdg-mime could not set ${C_PATH}$mime_type${C_DIM}."
    failed=true
  fi

  _mimeapps_set_default "$XDG_CONFIG_DIR/mimeapps.list" \
    "$mime_type" "$desktop_id" || {
    _warn "Could not update the user MIME associations."
    failed=true
  }

  desktop_values+=("${XDG_CURRENT_DESKTOP:-}")
  desktop_values+=("${XDG_SESSION_DESKTOP:-}")
  desktop_values+=("${DESKTOP_SESSION:-}")
  [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] &&
    desktop_values+=("Hyprland")

  for desktop_value in "${desktop_values[@]}"; do
    IFS=: read -r -a desktop_parts <<<"$desktop_value"
    for desktop in "${desktop_parts[@]}"; do
      desktop="${desktop,,}"
      [[ "$desktop" =~ ^[a-z0-9_-]+$ ]] || continue
      [[ -n "${seen_desktops[$desktop]:-}" ]] && continue
      seen_desktops[$desktop]=1

      _mimeapps_set_default \
        "$XDG_CONFIG_DIR/${desktop}-mimeapps.list" \
        "$mime_type" "$desktop_id" || {
        _warn "Could not update ${C_PATH}${desktop}-mimeapps.list${C_DIM}."
        failed=true
      }
    done
  done

  if _check_command update-desktop-database; then
    update-desktop-database "$APPLICATIONS_DIR" \
      >/dev/null 2>&1 || true
  fi

  [[ "$failed" == false ]]
}

_verify_mime_association() {
  local mime_type="$1"
  local desktop_id="$2"
  local current

  current="$(xdg-mime query default "$mime_type" 2>/dev/null)" || return 1
  [[ "$current" == "$desktop_id" ]]
}

_setup_nxm_association() {
  local desktop_file="$1"
  local desktop_id

  desktop_id="$(basename "$desktop_file")"
  _register_mime_association "$NXM_MIME" "$desktop_file" || true

  if ! _verify_mime_association "$NXM_MIME" "$desktop_id"; then
    _warn "NXM handler verification failed."
    _info "Retrying the user-level MIME association..."
    _register_mime_association "$NXM_MIME" "$desktop_file" || true
  fi

  if ! _verify_mime_association "$NXM_MIME" "$desktop_id"; then
    local current
    current="$(xdg-mime query default "$NXM_MIME" 2>/dev/null || true)"
    _error "Could not select Miir's NXM handler. Current handler: " \
      "${C_PATH}${current:-none}${C_DIM}."
    _info "Check ${C_PATH}$XDG_CONFIG_DIR/*mimeapps.list${C_DIM}."
    return 1
  fi

  _info "NXM links are routed to Vortex in Skyrim's Proton prefix."
}

_setup_keizaal_association() {
  local desktop_file="$1"
  local desktop_id

  desktop_id="$(basename "$desktop_file")"
  if ! _register_mime_association "$KEIZAAL_MIME" "$desktop_file"; then
    _warn "Could not fully register ${C_PATH}skyrim-rp://${C_DIM}."
  fi
  if ! _verify_mime_association "$KEIZAAL_MIME" "$desktop_id"; then
    _warn "Keizaal URL handler could not be verified."
  fi
}
