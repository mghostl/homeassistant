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
- `packages/**/*.yaml`
- `www/resource-breakdown-card.js`
- `themes/`

## Raspberry Pi monitoring

`raspberry-pi-sensors.yaml` defines seven read-only
[Command Line sensors](https://www.home-assistant.io/integrations/command_line/).
They use Python and `psutil` already bundled in Home Assistant Container; no
extra containers, packages, custom cards, or UI integration setup are required.
Deploy using `scripts/deploy-ha-config.sh`, which validates configuration,
backs up the managed files, and restarts Home Assistant.

The **Raspberry Pi** sidebar dashboard (`/dashboard-raspberry-pi/overview`)
has an Overview tab with gauges and 24-hour graphs, plus a History tab with
seven-day hourly statistics. History accumulates after deployment; the existing
recorder retains ten days and records these sensors. Gauge colors are visual
indicators, not notification automations.

| Entity | Measurement | Interval |
| --- | --- | --- |
| `sensor.raspberry_pi_cpu_usage` | Host CPU usage sampled over one second | 60 seconds |
| `sensor.raspberry_pi_cpu_temperature` | Raspberry Pi thermal zone 0, °C | 60 seconds |
| `sensor.raspberry_pi_memory_usage` | Host RAM usage | 60 seconds |
| `sensor.raspberry_pi_disk_usage` | Filesystem containing `/config`, percent used | 300 seconds |
| `sensor.raspberry_pi_disk_free` | Available space on that filesystem, GiB | 300 seconds |
| `sensor.raspberry_pi_load_5m` | Host five-minute load average | 60 seconds |
| `sensor.raspberry_pi_last_boot` | Host boot timestamp | 300 seconds |

The container reads host CPU, memory, load, and boot information through Linux
`/proc`, and temperature through `/sys`. Storage measures the host filesystem
bind-mounted at `/config`, rather than the container's writable image layer.
These values describe the Pi and all its workloads, rather than Home Assistant
alone. A different installation must expose the same thermal path and host
metrics. Keep these stable entity IDs if renaming sensors in the UI.

### Clickable process and service history

CPU and memory gauges open the **Resource breakdown** tab. Select a dot on the
CPU/memory chart to load the workload and process snapshot for that moment, or
use **Investigate a time** to select a minute from the last seven days.
**Show live** returns to current readings. Snapshot selection is shared between
dashboard sessions through Home Assistant helpers.

The breakdown groups all readable host processes by Docker container, systemd
service, or process name, including processes running outside Docker. It also
lists the top 20 individual processes by CPU or resident memory. Container names
are refreshed every five minutes; IDs are shown if Docker metadata is unavailable.
The PID is diagnostic only; workload history does not depend on it.

Copy this repository to the intended Raspberry Pi, then install the collector as
the normal SSH user (not root):

```sh
bash scripts/install-resource-monitor.sh
```

The installer requires host `python3-psutil` and an already enabled lingering user
session (`loginctl show-user "$USER" -p Linger`). It prints the necessary setup
command if either is missing. The user service starts at boot, samples every
60 seconds, and serves only read-only endpoints on `127.0.0.1:8766`. Home Assistant
Container must retain host networking to read them. The collector reads process
statistics and cgroups; it never collects command lines or environment variables.
It uses the SSH account's existing Docker access only to read container names.

Deploy Home Assistant configuration after installing the collector. The deployment
includes `packages/host_resources.yaml` and `www/resource-breakdown-card.js`. Local
dashboard JavaScript resources are declared in `configuration.yaml`; if adding
other custom cards, declare their resources there too. Other files in `www` are
preserved. Reload the dashboard after deployment to load its new card.

History starts when the collector is installed. Seven days of one-minute snapshots
are retained in `~/.local/share/ha-resource-monitor/history.sqlite3`; the chart
displays five-minute samples from the last 24 hours. CPU is averaged over the
sampling interval and normalized across all CPU cores. Processes that start and
exit between samples cannot be attributed. Memory uses RSS, which can double-count
shared pages; it does not reconcile exactly with host RAM usage, kernel memory, or
filesystem cache. Disk gauges still show total filesystem space, not file ownership.

Large process snapshots are excluded from Home Assistant's recorder; four compact
numeric sensors retain container/other-host CPU and RSS history there. The host
collector's database is outside Home Assistant backups. Stop collection with
`systemctl --user disable --now ha-resource-monitor.service`; this preserves history.
Inspect it with `systemctl --user status ha-resource-monitor.service` and
`journalctl --user -u ha-resource-monitor.service`.

Validation on Debian 13.5 / Home Assistant Container 2026.5.2 includes Python
history/attribution tests, JavaScript interaction tests, Home Assistant's config
checker, and live dashboard graph selection. Run Python checks on the Pi with
`python3-psutil` installed, and JavaScript checks locally with Node.js:

```sh
python3 -m unittest discover -s tests -v
node --test tests/resource-breakdown-card.test.cjs
bash -n scripts/install-resource-monitor.sh
bash -n scripts/deploy-ha-config.sh
```

### Resource alerts

`packages/resource_alerts.yaml` adds persistent Home Assistant notifications and
a **Resource alerts** status card on the Raspberry Pi Overview tab. Notifications
appear under the Home Assistant notification bell and link to the resource
breakdown. CPU alerts include the five busiest workloads at detection.

| Problem | Notify after | Clear after |
| --- | --- | --- |
| High temperature | Above 75 °C for 5 minutes | At or below 70 °C for 2 minutes |
| Storage warning | Above 85% used for 15 minutes | At or below 80% for 5 minutes |
| Storage critical | Above 95% used, at the next disk sample | Downgrade at or below 90% for 5 minutes; warning may remain |
| Low available memory | Below 5% available RAM for 10 minutes | At least 10% available for 5 minutes |
| Sustained CPU load | Above 90% for 15 minutes, using one-minute averages | At or below 75% for 5 minutes |
| Monitoring stopped | Last sample at least 3 minutes old, or missing source for 3 minutes | Fresh data for 1 minute |

Storage warning and critical share one notification ID; critical takes priority.
Other problems each have their own stable ID. Notifications update on problem or
severity transitions, rather than repeating every sample, and are dismissed after
confirmed recovery. Unavailable measurements do not dismiss existing alerts.
Manually dismissed notifications stay quiet until another transition or restart;
the status card continues to show the problem.

Home Assistant reconciles notifications 30 seconds after startup. Sustained-condition
and recovery timers restart when Home Assistant or template entities reload.
Status indicators may take up to five minutes to settle during their initial
recovery windows after startup.
Timestamp checks refresh each minute; storage sensors refresh every five minutes.
These alerts run inside Home Assistant; they do not provide phone push notifications
or detect an outage of Home Assistant itself.

`tests/test_resource_alerts.py` runs isolated integration checks inside the Home
Assistant image, including transient-spike suppression, storage severity changes,
workload context, unavailable sources, and notification recovery. Plain host Python
skips these tests when the Home Assistant runtime is absent.

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
