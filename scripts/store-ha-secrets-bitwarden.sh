#!/bin/bash

set -euo pipefail

HA_SSH_HOST="${HA_SSH_HOST:-lev@raspberrypi.local}"
HA_SECRETS_PATH="${HA_SECRETS_PATH:-/home/homeassistant/.homeassistant/secrets.yaml}"
BW_FOLDER_NAME="${BW_FOLDER_NAME:-home assistant}"
BW_ITEM_NAME="${BW_ITEM_NAME:-Home Assistant secrets.yaml}"
BW_SYNC="${BW_SYNC:-1}"

for command_name in bw jq ssh; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Missing required command: $command_name"
        exit 1
    fi
done

if [ -z "${BW_SESSION:-}" ]; then
    echo "BW_SESSION is not set."
    echo "Run: export BW_SESSION=\"\$(bw unlock --raw)\""
    exit 1
fi

BW_STATUS="$(bw status | jq -r '.status')"
if [ "$BW_STATUS" != "unlocked" ]; then
    echo "Bitwarden vault is not unlocked. Current status: $BW_STATUS"
    echo "Run: export BW_SESSION=\"\$(bw unlock --raw)\""
    exit 1
fi

if [ "$BW_SYNC" != "0" ]; then
    echo "Syncing Bitwarden vault"
    bw sync >/dev/null
fi

printf -v HA_SECRETS_PATH_QUOTED "%q" "$HA_SECRETS_PATH"
echo "Reading Home Assistant secret keys from $HA_SSH_HOST"
SECRETS_CONTENT="$(ssh -t "$HA_SSH_HOST" "sudo cat $HA_SECRETS_PATH_QUOTED")"

if [ -z "$SECRETS_CONTENT" ]; then
    echo "Home Assistant secrets file is empty: $HA_SECRETS_PATH"
    exit 1
fi

SECRET_KEYS="$(printf '%s\n' "$SECRETS_CONTENT" | awk -F: '/^[[:space:]]*[A-Za-z0-9_ -]+:/ { key=$1; sub(/^[[:space:]]+/, "", key); print key }')"

FOLDER_ID="$(
    bw list folders --search "$BW_FOLDER_NAME" |
        jq -r --arg name "$BW_FOLDER_NAME" 'map(select(.name == $name)) | first | .id // empty'
)"

if [ -z "$FOLDER_ID" ]; then
    echo "Creating Bitwarden folder: $BW_FOLDER_NAME"
    FOLDER_ID="$(
        bw get template folder |
            jq --arg name "$BW_FOLDER_NAME" '.name = $name' |
            bw encode |
            bw create folder |
            jq -r '.id'
    )"
else
    echo "Using Bitwarden folder: $BW_FOLDER_NAME"
fi

EXISTING_ITEM_ID="$(
    bw list items --search "$BW_ITEM_NAME" --folderid "$FOLDER_ID" |
        jq -r --arg name "$BW_ITEM_NAME" 'map(select(.name == $name)) | first | .id // empty'
)"

UPDATED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
ITEM_NOTES="$(
    printf 'Home Assistant secrets.yaml\n'
    printf 'Source: %s:%s\n' "$HA_SSH_HOST" "$HA_SECRETS_PATH"
    printf 'Updated: %s\n\n' "$UPDATED_AT"
    printf '%s\n' "$SECRETS_CONTENT"
)"

if [ -n "$EXISTING_ITEM_ID" ]; then
    echo "Updating Bitwarden secure note: $BW_ITEM_NAME"
    ITEM_ID="$(
        bw get item "$EXISTING_ITEM_ID" |
            jq \
                --arg folder_id "$FOLDER_ID" \
                --arg notes "$ITEM_NOTES" \
                '.folderId = $folder_id
                 | .type = 2
                 | .secureNote = {"type": 0}
                 | .notes = $notes' |
            bw encode |
            bw edit item "$EXISTING_ITEM_ID" |
            jq -r '.id'
    )"
else
    echo "Creating Bitwarden secure note: $BW_ITEM_NAME"
    ITEM_ID="$(
        bw get template item |
            jq \
                --arg name "$BW_ITEM_NAME" \
                --arg folder_id "$FOLDER_ID" \
                --arg notes "$ITEM_NOTES" \
                '.name = $name
                 | .folderId = $folder_id
                 | .type = 2
                 | .secureNote = {"type": 0}
                 | .notes = $notes' |
            bw encode |
            bw create item |
            jq -r '.id'
    )"
fi

echo "Stored Home Assistant secrets in Bitwarden item: $ITEM_ID"
echo "Secret keys stored:"
printf '%s\n' "$SECRET_KEYS" | sed 's/^/- /'

if [ "$BW_SYNC" != "0" ]; then
    bw sync >/dev/null || true
fi
