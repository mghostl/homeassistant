#!/bin/bash

set -euo pipefail

SOURCE_DIR="${SOURCE_DIR:-homeassistant}"
HA_SSH_HOST="${HA_SSH_HOST:-lev@raspberrypi.local}"
HA_CONFIG_DIR="${HA_CONFIG_DIR:-/home/homeassistant/.homeassistant}"
HA_CONTAINER_NAME="${HA_CONTAINER_NAME:-homeassistant}"
HA_IMAGE="${HA_IMAGE:-ghcr.io/home-assistant/home-assistant:stable}"
HA_TIME_ZONE="${HA_TIME_ZONE:-Europe/Amsterdam}"
HA_BACKUP_DIR="${HA_BACKUP_DIR:-/tmp}"
HA_RESTART="${HA_RESTART:-1}"
HA_VALIDATE_ONLY="${HA_VALIDATE_ONLY:-0}"

if [ ! -d "$SOURCE_DIR" ]; then
    echo "Source directory not found: $SOURCE_DIR"
    exit 1
fi

for command_name in ssh tar; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Missing required command: $command_name"
        exit 1
    fi
done

TOP_LEVEL_FILES=()
while IFS= read -r -d '' file; do
    rel_path="${file#"$SOURCE_DIR"/}"
    case "$rel_path" in
        secrets.yaml | secrets.yml | secrets.yaml.example | secrets.yml.example)
            ;;
        *)
            TOP_LEVEL_FILES+=("$rel_path")
            ;;
    esac
done < <(find "$SOURCE_DIR" -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' \) -print0)

MANAGED_PATHS=("${TOP_LEVEL_FILES[@]}")
for dir_name in blueprints themes packages; do
    if [ -d "$SOURCE_DIR/$dir_name" ]; then
        MANAGED_PATHS+=("$dir_name")
    fi
done

if [ "${#MANAGED_PATHS[@]}" -eq 0 ]; then
    echo "No deployable Home Assistant config found in $SOURCE_DIR"
    exit 1
fi

echo "Deploying Home Assistant config from $SOURCE_DIR to $HA_SSH_HOST:$HA_CONFIG_DIR"
echo "Managed paths:"
printf '  %s\n' "${MANAGED_PATHS[@]}"

REMOTE_STAGE="$(ssh "$HA_SSH_HOST" 'mktemp -d /tmp/ha-config-deploy.XXXXXX')"

cleanup() {
    ssh "$HA_SSH_HOST" "sudo rm -rf '$REMOTE_STAGE'" >/dev/null 2>&1 || true
}
trap cleanup EXIT

ssh "$HA_SSH_HOST" "mkdir -p '$REMOTE_STAGE/source'"

tar -C "$SOURCE_DIR" \
    --exclude='.gitkeep' \
    --exclude='secrets.yaml' \
    --exclude='secrets.yml' \
    --exclude='secrets.yaml.example' \
    --exclude='secrets.yml.example' \
    --exclude='README.md' \
    -czf - "${MANAGED_PATHS[@]}" |
    ssh "$HA_SSH_HOST" "tar -xzf - -C '$REMOTE_STAGE/source'"

ssh "$HA_SSH_HOST" bash -s -- \
    "$REMOTE_STAGE" \
    "$HA_CONFIG_DIR" \
    "$HA_CONTAINER_NAME" \
    "$HA_IMAGE" \
    "$HA_TIME_ZONE" \
    "$HA_BACKUP_DIR" \
    "$HA_RESTART" \
    "$HA_VALIDATE_ONLY" <<'REMOTE_SCRIPT'
set -euo pipefail

REMOTE_STAGE="$1"
CONFIG_DIR="$2"
CONTAINER_NAME="$3"
DEFAULT_IMAGE="$4"
TIME_ZONE="$5"
BACKUP_DIR="$6"
RESTART="$7"
VALIDATE_ONLY="$8"

SOURCE_DIR="$REMOTE_STAGE/source"
VALIDATION_DIR="$REMOTE_STAGE/validation"

if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is not installed on the Raspberry Pi."
    exit 1
fi

if docker info >/dev/null 2>&1; then
    DOCKER=(docker)
else
    DOCKER=(sudo docker)
    "${DOCKER[@]}" info >/dev/null
fi

sudo test -d "$CONFIG_DIR"

echo "Building temporary validation config"
sudo mkdir -p "$VALIDATION_DIR"
sudo tar -C "$CONFIG_DIR" \
    --exclude='./home-assistant_v2.db' \
    --exclude='./home-assistant_v2.db-*' \
    --exclude='./backups' \
    --exclude='./*.log' \
    --exclude='./*.log.*' \
    --exclude='./tts' \
    -cf - . |
    sudo tar -C "$VALIDATION_DIR" -xf -
sudo cp -a "$SOURCE_DIR/." "$VALIDATION_DIR/"
sudo rm -f "$VALIDATION_DIR/secrets.yaml.example" "$VALIDATION_DIR/secrets.yml.example" "$VALIDATION_DIR/README.md"

IMAGE="$("${DOCKER[@]}" inspect --format '{{.Config.Image}}' "$CONTAINER_NAME" 2>/dev/null || true)"
if [ -z "$IMAGE" ]; then
    IMAGE="$DEFAULT_IMAGE"
fi

echo "Validating config with image: $IMAGE"
"${DOCKER[@]}" run --rm \
    --network=host \
    -e "TZ=$TIME_ZONE" \
    -v "$VALIDATION_DIR:/config" \
    -v /run/dbus:/run/dbus:ro \
    "$IMAGE" \
    python -m homeassistant --script check_config -c /config

if [ "$VALIDATE_ONLY" = "1" ]; then
    echo "Validation passed. HA_VALIDATE_ONLY=1, so nothing was deployed."
    exit 0
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_PATH="$BACKUP_DIR/homeassistant-config-before-deploy-$TIMESTAMP.tar.gz"
sudo mkdir -p "$BACKUP_DIR"

EXISTING_PATHS=()
for path in configuration.yaml automations.yaml scripts.yaml scenes.yaml blueprints themes packages; do
    if [ -e "$CONFIG_DIR/$path" ]; then
        EXISTING_PATHS+=("$path")
    fi
done

if [ "${#EXISTING_PATHS[@]}" -gt 0 ]; then
    echo "Backing up current managed config to $BACKUP_PATH"
    sudo tar -C "$CONFIG_DIR" -czf "$BACKUP_PATH" "${EXISTING_PATHS[@]}"
fi

echo "Applying repository config"
while IFS= read -r -d '' file; do
    target="$CONFIG_DIR/$(basename "$file")"
    sudo install -m 0644 "$file" "$target"
done < <(find "$SOURCE_DIR" -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' \) -print0)

for dir_name in blueprints themes packages; do
    if [ -d "$SOURCE_DIR/$dir_name" ]; then
        sudo rm -rf "$CONFIG_DIR/$dir_name"
        sudo cp -a "$SOURCE_DIR/$dir_name" "$CONFIG_DIR/$dir_name"
    fi
done

sudo rm -f "$CONFIG_DIR/secrets.yaml.example" "$CONFIG_DIR/secrets.yml.example" "$CONFIG_DIR/README.md"

if [ "$RESTART" = "1" ]; then
    echo "Restarting Home Assistant container: $CONTAINER_NAME"
    "${DOCKER[@]}" restart "$CONTAINER_NAME" >/dev/null
    echo "Home Assistant restarted."
else
    echo "HA_RESTART=0, so Home Assistant was not restarted."
fi
REMOTE_SCRIPT

echo "Deployment completed."
