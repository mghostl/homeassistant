#!/bin/bash

set -euo pipefail

TAILSCALE_INSTALL_URL="${TAILSCALE_INSTALL_URL:-https://tailscale.com/install.sh}"
TAILSCALE_HOSTNAME="${TAILSCALE_HOSTNAME:-$(hostname)}"
TAILSCALE_AUTHKEY="${TAILSCALE_AUTHKEY:-}"
TAILSCALE_EXTRA_ARGS="${TAILSCALE_EXTRA_ARGS:-}"
TAILSCALE_UP="${TAILSCALE_UP:-auto}"

if [ "$(uname -s)" != "Linux" ]; then
    echo "This script must be run on Raspberry Pi OS or another Linux host."
    exit 1
fi

if [ "$(id -u)" -eq 0 ]; then
    SUDO=()
else
    SUDO=(sudo)
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "Installing curl"
    "${SUDO[@]}" apt-get update
    "${SUDO[@]}" apt-get install -y curl
fi

INSTALLER="$(mktemp)"
trap 'rm -f "$INSTALLER"' EXIT

echo "Downloading Tailscale installer"
curl -fsSL "$TAILSCALE_INSTALL_URL" -o "$INSTALLER"

echo "Installing or updating Tailscale"
"${SUDO[@]}" sh "$INSTALLER"

if command -v systemctl >/dev/null 2>&1; then
    echo "Starting tailscaled"
    "${SUDO[@]}" systemctl enable --now tailscaled
fi

echo "Installed Tailscale version:"
tailscale version

if [ "$TAILSCALE_UP" = "never" ]; then
    echo "Skipping tailscale up because TAILSCALE_UP=never."
    exit 0
fi

if tailscale status >/dev/null 2>&1; then
    echo "Tailscale is already authenticated."
    exit 0
fi

if [ -n "$TAILSCALE_AUTHKEY" ]; then
    echo "Authenticating Tailscale with provided auth key"
    # shellcheck disable=SC2086
    "${SUDO[@]}" tailscale up --auth-key="$TAILSCALE_AUTHKEY" --hostname="$TAILSCALE_HOSTNAME" $TAILSCALE_EXTRA_ARGS
else
    echo "Tailscale is installed but not authenticated."
    echo "Run this on the Raspberry Pi:"
    echo "  sudo tailscale up --hostname=$TAILSCALE_HOSTNAME"
    echo
    echo "For unattended setup, rerun with:"
    echo "  TAILSCALE_AUTHKEY=tskey-auth-... sudo -E bash scripts/install-tailscale.sh"
fi
