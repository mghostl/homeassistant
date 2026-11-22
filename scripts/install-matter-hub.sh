#!/bin/bash

set -euo pipefail
umask 077

container=homeassistant-matter-hub
image=ghcr.io/riddix/home-assistant-matter-hub:2.0.60
state_dir="$HOME/.local/state/homeassistant-matter-hub"
settings="$state_dir/config/settings.json"
ha_url=http://127.0.0.1:8123

if [[ "${1:-}" == --set-token && $# -eq 1 ]]; then
    if [[ ! -t 0 || ! -f "$settings" ]]; then
        echo "Run this option in a terminal after installing Matter Hub." >&2
        exit 1
    fi

    read -r -s -p "Paste the Home Assistant access token for Matter Hub: " token
    printf '\n'
    if [[ ! "$token" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]; then
        echo "The input did not look like a Home Assistant access token." >&2
        exit 1
    fi

    # Pass the token through stdin so it stays out of process arguments.
    printf '%s\n' "$token" | docker exec -i homeassistant python3 -c '
import asyncio
import sys

from aiohttp import ClientSession, ClientTimeout

async def check():
    async with ClientSession(timeout=ClientTimeout(total=8)) as session:
        async with session.ws_connect("http://127.0.0.1:8123/api/websocket") as socket:
            await socket.receive_json()
            await socket.send_json({"type": "auth", "access_token": sys.stdin.readline().strip()})
            if (await socket.receive_json()).get("type") != "auth_ok":
                raise SystemExit("Home Assistant rejected the token.")

asyncio.run(check())
'

    printf '%s\n' "$token" | python3 -c '
import json
import os
from pathlib import Path
import sys
from tempfile import NamedTemporaryFile

settings = Path(sys.argv[1])
data = json.loads(settings.read_text())
data["home-assistant-access-token"] = sys.stdin.readline().strip()
with NamedTemporaryFile(mode="w", dir=settings.parent, delete=False) as stream:
    staged = Path(stream.name)
    try:
        json.dump(data, stream)
        stream.flush()
        os.fsync(stream.fileno())
        staged.replace(settings)
    finally:
        staged.unlink(missing_ok=True)
' "$settings"
    unset token
    echo "The Pi saved the validated token for Matter Hub."
    docker restart "$container" >/dev/null
    echo "Matter Hub is starting."
    exit 0
fi

if [[ $# -ne 0 ]]; then
    echo "Usage: $0 [--set-token]" >&2
    exit 2
fi

if ! docker inspect --type container homeassistant >/dev/null 2>&1; then
    echo "Run this on the Pi that hosts the Home Assistant container." >&2
    exit 1
fi

if docker inspect --type container "$container" >/dev/null 2>&1; then
    echo "Matter Hub is already installed. Use --set-token to update its credential."
    exit 0
fi

lan_interface=$(ip -4 route show default | awk '
    {for (i=1; i<NF; i++) if ($i=="dev" && $(i+1)!="tailscale0") {print $(i+1); exit}}
')
if [[ -z "$lan_interface" ]]; then
    echo "Could not find the Pi's LAN interface." >&2
    exit 1
fi

mkdir -p -m 700 "$state_dir/config" "$state_dir/data"
if [[ ! -e "$settings" ]]; then
    python3 - "$settings" "$ha_url" "$lan_interface" <<'PY'
import json
from pathlib import Path
import sys

settings = Path(sys.argv[1])
with settings.open("x") as stream:
    json.dump({
        "home-assistant-url": sys.argv[2],
        "storage-location": "/data",
        "http-port": 8482,
        "http-ip-whitelist": ["127.0.0.1", "::1"],
        "mdns-network-interface": sys.argv[3],
    }, stream)
PY
fi

if ! docker image inspect "$image" >/dev/null 2>&1; then
    docker pull "$image"
fi
docker create \
    --name "$container" \
    --restart unless-stopped \
    --network host \
    --user "$(id -u):$(id -g)" \
    --cap-drop ALL \
    --security-opt no-new-privileges:true \
    --mount "type=bind,source=$state_dir/config,target=/matter-config,readonly" \
    --mount "type=bind,source=$state_dir/data,target=/data" \
    "$image" home-assistant-matter-hub start --config /matter-config/settings.json >/dev/null

echo "Matter Hub is staged. Use --set-token to connect it to Home Assistant."
