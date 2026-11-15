#!/bin/bash

set -euo pipefail

ARGON_INSTALL_URL="${ARGON_INSTALL_URL:-https://download.argon40.com/argon1.sh}"
DOCKER_INSTALL_URL="${DOCKER_INSTALL_URL:-https://get.docker.com}"

if [ "$(id -u)" -eq 0 ]; then
    SUDO=()
else
    SUDO=(sudo)
fi

download_installer() {
    local url="$1"
    local installer

    installer="$(mktemp)"
    curl --fail --show-error --silent --location --proto '=https' --tlsv1.2 \
        "$url" -o "$installer"
    printf '%s\n' "$installer"
}

ARGON_INSTALLER=""
DOCKER_INSTALLER=""
trap 'rm -f "$ARGON_INSTALLER" "$DOCKER_INSTALLER"' EXIT

ARGON_INSTALLER="$(download_installer "$ARGON_INSTALL_URL")"
DOCKER_INSTALLER="$(download_installer "$DOCKER_INSTALL_URL")"

echo "Installing Argon support"
"${SUDO[@]}" bash "$ARGON_INSTALLER"

echo "Installing Docker"
"${SUDO[@]}" sh "$DOCKER_INSTALLER"
