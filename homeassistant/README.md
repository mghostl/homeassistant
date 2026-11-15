# Home Assistant Configuration

This directory is the repository source of truth for the YAML-based Home Assistant configuration.

Edit these files here first, then deploy them to the Raspberry Pi config directory:

```sh
/home/homeassistant/.homeassistant
```

Tracked files include:

- `configuration.yaml`
- `automations.yaml`
- `scripts.yaml`
- `scenes.yaml`
- `blueprints/**/*.yaml`
- `dashboards/**/*.yaml`
- `themes/`

## Stable Entity IDs

Automations should target named Home Assistant entities instead of generated device
registry IDs. Before deploying this config, rename the daily vacuum entity in Home
Assistant to `vacuum.roborock_qrevo_master` and keep that entity ID when re-pairing or
rebuilding the instance.

## Daily Vacuum Guard Rails

The daily vacuum automation checks every 30 minutes from 12:00 through 21:00 on
weekdays and starts at most once per day when:

- `input_boolean.daily_vacuum_enabled` is on
- The day is Monday through Friday
- `vacuum.roborock_qrevo_master` is `docked` or `idle`
- `sensor.roborock_qrevo_master_battery` is at least 30%

The automation waits for the vacuum to report `cleaning` before recording the
start date. Once that scheduled run returns to `docked` or `idle`, Home
Assistant records its completion date. A persistent notification is created if
the run never starts by 21:00, reports `error` or `unavailable` for five
minutes, or remains `cleaning` for over four hours. The four-hour check runs
every 15 minutes, so it remains effective after a Home Assistant restart.
Occupancy does not block cleaning. The enable helper restores its previous
state after restart unless an `initial` value is configured.

The `Vacuum` dashboard is defined in `dashboards/vacuum.yaml` and exposes
vacuum status, battery level, the last scheduled start and confirmed completion,
manual controls for start, pause, and return to base, and the
`input_boolean.daily_vacuum_enabled` schedule toggle.

The real `secrets.yaml` is intentionally ignored because it may contain credentials. Keep only secret names in `secrets.yaml.example`, and maintain the real values directly on the Raspberry Pi or in a private secret manager.

Secrets should be stored in Bitwarden folder `home assistant` as secure note `Home Assistant secrets.yaml`:

```sh
export BW_SESSION="$(bw unlock --raw)"
scripts/store-ha-secrets-bitwarden.sh
```

Deploy repository config to the Raspberry Pi with:

```sh
scripts/deploy-ha-config.sh
```

The SSH account needs `sudo` access. If a password is required, run the script
from a terminal and enter the Pi account password when prompted. Unattended runs
require passwordless `sudo`. Config transfers do not allocate a terminal; only
the remote deployment command requests one when a password is needed.

The deploy script tries
`lev@raspberrypi.local` first, waits up to five seconds, and then retries as
the Tailscale/MagicDNS host `lev@raspberrypi` if the `.local` host cannot be
reached. Override the LAN host, Tailscale host, or timeout with `HA_SSH_HOST`,
`HA_TAILSCALE_SSH_HOST`, and `HA_SSH_CONNECT_TIMEOUT`.

The deploy script stages the repo config on the Pi, validates it with Home Assistant's config checker, backs up the current managed YAML/config files, applies the changes, and restarts the `homeassistant` container.

After a deployment restart, it waits up to 120 seconds for the local Home Assistant
web endpoint to respond. If it does not, the script restores the managed YAML/config
backup and restarts the container again. Override the timeout, interval, or endpoint
with `HA_HEALTHCHECK_TIMEOUT`, `HA_HEALTHCHECK_INTERVAL`, and `HA_HEALTHCHECK_URL`.
This rollback protects repository-managed configuration only; it is not a replacement
for a full, off-device backup of `/home/homeassistant/.homeassistant`.

## Backups and maintenance

Configure encrypted automatic backups in Home Assistant under **Settings > System >
Backups**. Store a copy outside the Raspberry Pi (for example on network storage or
Home Assistant Cloud), retain the downloaded emergency kit separately, and verify a
restore before relying on it. The Container installation stores local backups in
`/home/homeassistant/.homeassistant/backups`, so backups kept only there will not
survive a failed SD card or Pi.

Keep Raspberry Pi OS, Docker, and Home Assistant current. Before an update, confirm
that a recent off-device backup completed successfully. To avoid unplanned firmware
changes, `scripts/bootstrap.sh` skips `rpi-update` by default; run it only for a
specific troubleshooting reason with `RPI_UPDATE=1 sudo bash bootstrap.sh`.

To validate without applying changes:

```sh
HA_VALIDATE_ONLY=1 scripts/deploy-ha-config.sh
```

Clear only the Home Assistant brand icon cache on the Raspberry Pi with:

```sh
ssh lev@raspberrypi.local 'bash -s' < scripts/clear-ha-cache.sh
```
