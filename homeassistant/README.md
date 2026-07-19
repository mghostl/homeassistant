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

The daily vacuum automation runs at 12:00 only when:

- `input_boolean.daily_vacuum_enabled` is on
- The day is Monday through Friday
- `vacuum.roborock_qrevo_master` is `docked` or `idle`
- `sensor.roborock_qrevo_master_battery` is at least 30%

The `zone.home` occupancy guard is present in `automations.yaml` but commented out
for now. The enable helper starts on by default after Home Assistant restarts.

The `Vacuum` dashboard is defined in `dashboards/vacuum.yaml` and exposes
vacuum status, battery level, the last daily routine run, manual controls for
start, pause, and return to base, and the `input_boolean.daily_vacuum_enabled`
schedule toggle.

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

The deploy script stages the repo config on the Pi, validates it with Home Assistant's config checker, backs up the current managed YAML/config files, applies the changes, and restarts the `homeassistant` container.

To validate without applying changes:

```sh
HA_VALIDATE_ONLY=1 scripts/deploy-ha-config.sh
```

Clear only the Home Assistant brand icon cache on the Raspberry Pi with:

```sh
ssh lev@raspberrypi.local 'bash -s' < scripts/clear-ha-cache.sh
```
