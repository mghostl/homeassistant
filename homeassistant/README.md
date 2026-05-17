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
- `themes/`

The real `secrets.yaml` is intentionally ignored because it may contain credentials. Keep only secret names in `secrets.yaml.example`, and maintain the real values directly on the Raspberry Pi or in a private secret manager.

Secrets should be stored in Bitwarden folder `home assistant` as secure note `Home Assistant secrets.yaml`:

```sh
export BW_SESSION="$(bw unlock --raw)"
scripts/store-ha-secrets-bitwarden.sh
```

After copying config changes to the Pi, restart Home Assistant:

```sh
docker restart homeassistant
```
