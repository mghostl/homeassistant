#!/bin/bash

set -euo pipefail

CONTAINER_NAME="${HA_CONTAINER_NAME:-homeassistant}"
IMAGE="${HA_IMAGE:-ghcr.io/home-assistant/home-assistant:stable}"
CONFIG_DIR="${HA_CONFIG_DIR:-/home/homeassistant/.homeassistant}"
TIME_ZONE="${HA_TIME_ZONE:-Europe/Amsterdam}"
STARTUP_WAIT_SECONDS="${HA_STARTUP_WAIT_SECONDS:-45}"
RESTORE_ARCHIVE=""
RESTORE_ARCHIVE_EXPLICIT=0

if [ "$#" -gt 0 ]; then
    RESTORE_ARCHIVE="$1"
    RESTORE_ARCHIVE_EXPLICIT=1
elif [ -n "${HA_RESTORE_ARCHIVE:-}" ]; then
    RESTORE_ARCHIVE="$HA_RESTORE_ARCHIVE"
    RESTORE_ARCHIVE_EXPLICIT=1
fi

if [ "$(id -u)" -eq 0 ]; then
    SUDO=()
else
    SUDO=(sudo)
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is not installed. Run scripts/init.sh first."
    exit 1
fi

if docker info >/dev/null 2>&1; then
    DOCKER=(docker)
else
    DOCKER=("${SUDO[@]}" docker)
    "${DOCKER[@]}" info >/dev/null
fi

if [ -z "$RESTORE_ARCHIVE" ]; then
    for candidate in \
        /boot/firmware/rescue/homeassistant.tar.gz \
        /boot/rescue/homeassistant.tar.gz \
        /tmp/homeassistant-rescue.tar.gz; do
        if [ -f "$candidate" ]; then
            RESTORE_ARCHIVE="$candidate"
            break
        fi
    done
fi

echo "Preparing Home Assistant config directory: $CONFIG_DIR"
"${SUDO[@]}" mkdir -p "$(dirname "$CONFIG_DIR")"

CONFIG_HAS_FILES=0
if [ -d "$CONFIG_DIR" ] && [ -n "$("${SUDO[@]}" find "$CONFIG_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
    CONFIG_HAS_FILES=1
fi

if [ -n "$RESTORE_ARCHIVE" ] && [ "$RESTORE_ARCHIVE_EXPLICIT" -eq 0 ] && [ "$CONFIG_HAS_FILES" -eq 1 ]; then
    echo "Auto-detected restore archive, but $CONFIG_DIR already has data."
    echo "Skipping restore. Pass the archive path explicitly to force restore."
    RESTORE_ARCHIVE=""
fi

if [ -n "$RESTORE_ARCHIVE" ]; then
    if [ ! -f "$RESTORE_ARCHIVE" ]; then
        echo "Restore archive not found: $RESTORE_ARCHIVE"
        exit 1
    fi

    if [ "$CONFIG_HAS_FILES" -eq 1 ]; then
        BACKUP_PATH="/tmp/homeassistant-config-before-restore-$(date +%Y%m%d-%H%M%S).tar.gz"
        echo "Backing up existing config to $BACKUP_PATH"
        "${SUDO[@]}" tar -czf "$BACKUP_PATH" -C / "${CONFIG_DIR#/}"
    fi

    echo "Restoring Home Assistant config from $RESTORE_ARCHIVE"
    "${SUDO[@]}" tar -xzf "$RESTORE_ARCHIVE" -C /
else
    "${SUDO[@]}" mkdir -p "$CONFIG_DIR"
    echo "No restore archive found; starting with config directory $CONFIG_DIR"
fi

echo "Removing stale Home Assistant runtime lock if present"
"${SUDO[@]}" rm -f "$CONFIG_DIR/.ha_run.lock"

if "${DOCKER[@]}" ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo "Removing existing container: $CONTAINER_NAME"
    "${DOCKER[@]}" rm -f "$CONTAINER_NAME"
fi

echo "Pulling Home Assistant image: $IMAGE"
"${DOCKER[@]}" pull "$IMAGE"

echo "Starting Home Assistant Container"
"${DOCKER[@]}" run -d \
    --name "$CONTAINER_NAME" \
    --privileged \
    --cap-add=NET_ADMIN \
    --cap-add=NET_RAW \
    --restart=unless-stopped \
    -e "TZ=$TIME_ZONE" \
    -v "$CONFIG_DIR:/config" \
    -v /run/dbus:/run/dbus:ro \
    --network=host \
    "$IMAGE"

echo "Waiting ${STARTUP_WAIT_SECONDS}s for Home Assistant to start"
sleep "$STARTUP_WAIT_SECONDS"

"${DOCKER[@]}" ps --filter "name=^/${CONTAINER_NAME}$"

if command -v curl >/dev/null 2>&1; then
    if curl -fsS -o /dev/null --max-time 15 http://127.0.0.1:8123/; then
        echo "Home Assistant is responding on http://127.0.0.1:8123/"
    else
        echo "Home Assistant container is running, but the web UI is not ready yet."
        echo "Check logs with: docker logs -f $CONTAINER_NAME"
    fi
fi

HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
echo "Open Home Assistant at: http://${HOST_IP:-raspberrypi.local}:8123/"
echo "This is Home Assistant Container, so Supervisor and add-ons are not included."
