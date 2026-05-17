#!/bin/bash

set -euo pipefail

HA_CONFIG_DIR="${HA_CONFIG_DIR:-/home/homeassistant/.homeassistant}"
HA_CONTAINER_NAME="${HA_CONTAINER_NAME:-homeassistant}"
HA_RESTART="${HA_RESTART:-1}"

if [ "$(uname -s)" != "Linux" ]; then
    echo "Run this script on the Raspberry Pi."
    exit 1
fi

if [ "$(id -u)" -eq 0 ]; then
    SUDO=()
else
    SUDO=(sudo)
fi

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    DOCKER=(docker)
else
    DOCKER=("${SUDO[@]}" docker)
fi

echo "Clearing Home Assistant brand icon cache"
"${SUDO[@]}" rm -rf "$HA_CONFIG_DIR/.cache/brands"

echo "Leaving Home Assistant state untouched:"
echo "  $HA_CONFIG_DIR/.storage"
echo "  $HA_CONFIG_DIR/home-assistant_v2.db"
echo "  $HA_CONFIG_DIR/backups"
echo "  $HA_CONFIG_DIR/secrets.yaml"

if [ "$HA_RESTART" = "1" ]; then
    echo "Restarting Home Assistant container: $HA_CONTAINER_NAME"
    "${DOCKER[@]}" restart "$HA_CONTAINER_NAME" >/dev/null
    echo "Home Assistant restarted."
else
    echo "HA_RESTART=0, so Home Assistant was not restarted."
fi
