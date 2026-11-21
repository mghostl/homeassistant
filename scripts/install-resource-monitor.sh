#!/bin/bash

set -euo pipefail

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "$(uname -s)" != Linux ] || [ ! -f /etc/debian_version ]; then
    echo "Run this installer on the intended Debian/Raspberry Pi OS host."
    exit 1
fi

if ! /usr/bin/python3 -c 'import psutil' >/dev/null 2>&1; then
    echo "Install the host dependency first: sudo apt-get install python3-psutil"
    exit 1
fi

if [ "$(loginctl show-user "$USER" -p Linger --value)" != yes ]; then
    echo "Enable boot persistence first: sudo loginctl enable-linger $USER"
    exit 1
fi

echo "Installing host resource collector for $USER"
install -d -m 0700 "$HOME/.local/lib/ha-resource-monitor" "$HOME/.local/share/ha-resource-monitor"
install -d "$HOME/.config/systemd/user"
install -m 0644 "$SOURCE_DIR/scripts/monitor-host-resources.py" "$HOME/.local/lib/ha-resource-monitor/monitor-host-resources.py"
install -m 0644 "$SOURCE_DIR/monitoring/ha-resource-monitor.service" "$HOME/.config/systemd/user/ha-resource-monitor.service"
systemctl --user daemon-reload
systemctl --user enable ha-resource-monitor.service
systemctl --user restart ha-resource-monitor.service
echo "Collector installed; read-only metrics available at http://127.0.0.1:8766/latest"
