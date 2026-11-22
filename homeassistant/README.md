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

## MCP server

Use Home Assistant's built-in [Model Context Protocol integration](https://www.home-assistant.io/integrations/mcp_server/)
to let an AI client access Home Assistant. It works with this Container installation;
no additional Docker container or add-on is needed.

1. Open your Home Assistant instance as an administrator.
2. Go to **Settings > Devices & services > Add integration** and select
   **Model Context Protocol Server** (called **Model Context Protocol** in newer
   releases). Select **Assist** in the setup form on Home Assistant 2026.5.
3. Expose the intended entities under **Settings > Voice assistants > Expose**.
   Assist limits device access to those exposed entities.
4. Use the MCP endpoint `http://<home-assistant-host>:8123/api/mcp`.
   On newer releases, copy the URL from **Settings > System > AI** and configure
   the available tool sets there. Select **Device control** for device access,
   or enable **Read-only** to allow inspection only, when those options exist.
5. Add the copied URL to your MCP client and sign in with Home Assistant when
   prompted. The client must be able to reach the address: a local or Tailscale
   address works only for clients on that network. Cloud clients need a reachable
   external URL, such as Home Assistant Cloud.

Newer releases default to exposing all AI tool sets and requiring an administrator.
Review those options before connecting a client. Home Assistant 2026.5 instead
asks which API to expose during integration setup.

To verify the connection, list tools in the client and request the state of an
exposed entity before trying a device action.

This integration is managed through the UI, rather than `configuration.yaml`.
`scripts/deploy-ha-config.sh` does not enable it or copy its `.storage` state.
Keep client credentials and tokens out of this repository.

## Yandex devices

Use the [Yandex.Station community integration](https://github.com/AlexxIT/YandexStation)
to bring devices from **Home with Alice** (Дом с Алисой) into Home Assistant.
Supported speakers can use the local network. Other imported smart-home devices
use Yandex's cloud.

1. As a Home Assistant administrator, open **Settings > Marketplace** and
   install **Yandex.Station** by **AlexxIT**. If Home Assistant requests a
   restart, follow the prompt in **Settings > System > Repairs**.
2. Open the integration setup from Marketplace or go to **Settings > Devices
   & services > Add integration > Yandex.Station**. Choose **QR code**, scan it
   with the Yandex app signed into the account that owns the devices, and
   finish setup in Home Assistant.
3. In the **Yandex.Station** integration, open **Configure**. Under
   **Импортировать устройства УДЯ**, select the devices to import and save.
   Compare the list with **Settings > Devices & services > Devices** first
   and skip devices already connected through another integration. Check the
   entity states on the Yandex.Station integration page after saving.

Home Assistant stores the account link and selected devices on the running
instance. Marketplace manages the component in `custom_components`. Keep the
account token and `.storage` files out of Git.

The existing Recorder allowlist covers imported `sensor` and `binary_sensor`
entities. Verify those readings in **History** after they update. If a specific
switch, light, or speaker needs history, add its entity ID to `recorder.include`
and verify the result in **History**. Review **Settings > Voice assistants >
Expose** after import. Some new entities can be exposed automatically, including
switches and lights that Assist/MCP can control.

`packages/yandex.yaml` turns on the entrance light when the Yandex motion sensor
changes from `not_detected` to `detected`. Each new detection restarts the
two-minute countdown. Reconnecting with an old detection does not turn on the
light. Recorder tracks the motion sensor and the entrance light so both states
can be checked in **History**.

Every five minutes, the package also asks Yandex.Station to refresh unavailable
Aqara sensors and thermostats. It sends one status request per affected device.
Check the automation's **Traces** and the entity's **History** to see whether
Yandex returned a fresh state.

## Rooms dashboard

Open **Rooms** in the sidebar for entrance, living-room, and upstairs controls.
**Devices by room** lists household device pages from Home Assistant's area
assignments regardless of which integration supplied them. The dashboard groups
matching English and Russian room names for display. Assign new devices to a
room in **Settings > Areas, labels & zones** to include them in the directory.
The living-room Apple TV is included while its device has no area assignment.

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

## Network and Xiaomi routers

Open **Network** in the sidebar. The **Connection health** card on **Overview**
shows gateway reachability, the internet probe, and DNS resolution separately.
The other cards show round-trip latency, packet loss, and the Raspberry Pi's
Wi-Fi signal. **Routers** lists routers imported through Xiaomi Home
and displays available readings such as the connected-device count. Select a
router name to open its device page, or **Open router settings** for the
gateway's local administration page. The default gateway's model, hardware,
firmware, and country come from the router's public Xiaomi status endpoint
when it responds. **Run now** refreshes the gateway, internet, and DNS checks.
**History** shows the last 24 hours of the Pi's network measurements.
Home Assistant takes one sample per minute, sending three pings each to the
IPv4 default gateway and Cloudflare's `1.1.1.1`. The DNS check looks up
`example.com` with the Home Assistant container's configured DNS resolver.
Latency is the mean of the replies, and the Wi-Fi reading is the Pi's own
signal in dBm. The Pi's active default-route interface must expose a wireless
signal for that row to populate.

Install Xiaomi's [Xiaomi Home custom integration](https://github.com/XiaoMi/ha_xiaomi_home)
in `custom_components/xiaomi_home` using the official release for a new
installation, then restart Home Assistant. In **Settings > Devices & services >
Add integration**, choose **Xiaomi Home**, select the region used by the Mi Home
app, sign in with Xiaomi, and select the home and devices to import.
If the sign-in page returns to an unreachable `http://homeassistant.local:8123`,
edit the address in that same browser tab. Replace the scheme, hostname, and
port with the address you use to open this Home Assistant instance. Preserve
the entire `/api/webhook/…` path and query string, then press Enter and return
to the integration setup tab. [Xiaomi's redirect instructions](https://github.com/XiaoMi/ha_xiaomi_home/wiki/OAuth-2.0-login-when-Home-Assistant-URL-is-not-homeassistant.local%3A8123)

The gateway readings work with any router that answers ping. Router-wide
traffic and client lists require a compatible router integration. The
[UPnP/IGD integration](https://www.home-assistant.io/integrations/upnp/) can
provide WAN statistics if the router already advertises that service.

### Local router admin connection

[Network Info v1.8.0](https://github.com/Oose97/ha-network-info/releases/tag/v1.8.0)
can read client names, connection types, and wireless signal where the router
provides them. Install its `custom_components/network_info` directory in the
Home Assistant config directory and restart Home Assistant. In **Devices &
services > Add integration**, select **Network Info**. Confirm the local subnet,
set **Router brand** to **Xiaomi / MiWiFi**, and keep the external IP options
off for local-only monitoring. Enter the gateway's HTTPS address and the
router's web administration password in the Home Assistant setup form. The
default Xiaomi username is `admin`.

The **Clients** tab shows online clients from Network Info with their IP
addresses and connection types. It sorts clients with signal readings by
weakest signal first. **Scan now** requests a new Network Info client scan
outside the scheduled polling interval.

The network sensors are read-only and do not need Assist or MCP exposure to
populate the dashboard. Review imported Xiaomi entities before exposing them.

Verified on Debian 13 (Trixie) with Home Assistant Container 2026.11.2 using
`scripts/deploy-ha-config.sh`. The `/dashboard-network/history` route responded
and Home Assistant recorded the gateway, internet, and Wi-Fi measurements.

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

The `Vacuum` dashboard is defined in `dashboards/vacuum.yaml`. Its Controls tab
shows status, battery, the cleaning map, recent cleaning details, and the weekday
schedule alongside start, pause, and return-to-base controls. Settings includes
suction, cleaning and mop modes, dock controls, quiet hours, voice volume, and
child lock. Maintenance shows tank and error status, remaining service time, and
lifetime cleaning totals. If you re-pair the vacuum, verify the entity IDs in the
dashboard against the new device and dock entities.

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
