#!/usr/bin/env bash

MIIR_PACKAGE_MAP["protontricks|pacman"]="protontricks"
MIIR_PACKAGE_MAP["protontricks|yay"]="protontricks"
MIIR_PACKAGE_MAP["protontricks|apt"]="protontricks"
MIIR_PACKAGE_MAP["protontricks|apt-get"]="protontricks"
MIIR_PACKAGE_MAP["protontricks|dnf"]="protontricks"
MIIR_PACKAGE_MAP["protontricks|yum"]="protontricks"
MIIR_PACKAGE_MAP["protontricks|apk"]="protontricks"
MIIR_PACKAGE_MAP["protontricks|nix"]="protontricks"

_dependency_install() {
  local pkg="$1"
  if ! _package_check "$pkg"; then
    _info "Installing ${C_PATH}$pkg${C_DIM}..."
    _package_install "$pkg"
  fi
  _info "${C_PATH}$pkg${C_DIM} is installed!"
}

_dependency_handle() {
  local pkgs=("$@")
  _package_resolve "${pkgs[@]}"
  for pkg in "${PACKAGE_RESOLVED[@]}"; do
    _dependency_install "$pkg"
  done
}
