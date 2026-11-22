# Repository Guidelines

## Project Structure & Module Organization

This repository documents and automates a Raspberry Pi Home Assistant setup. The main entry point is `README.md`, which describes the device requirements and step-by-step installation flow. Shell scripts live in `scripts/`: `bootstrap.sh` prepares Raspberry Pi OS packages and boot parameters, `init.sh` installs Argon and Docker prerequisites, and `install-ha.sh` installs Home Assistant OS Agent and Supervisor packages. Screenshots and other visual references belong in `imgs/`. Keep generated local files, host artifacts, and IDE state out of version control.

## Build, Test, and Development Commands

There is no application build pipeline. Validate shell changes locally before copying scripts to the Raspberry Pi:

```sh
bash -n scripts/bootstrap.sh
bash -n scripts/init.sh
bash -n scripts/install-ha.sh
```

Use the documented deployment flow from `README.md` when testing on hardware:

```sh
scp scripts/bootstrap.sh lev@raspberrypi.local:~/bootstrap.sh
ssh lev@raspberrypi.local -t 'sudo bash bootstrap.sh'
```

Run scripts only on the intended Raspberry Pi target; they install packages, modify boot configuration, and start system services.

## Coding Style & Naming Conventions

Write scripts for Bash and start them with `#!/bin/bash`. Prefer `set -e` or `set -eux` for install scripts so failures are visible. Use lowercase, hyphenated script names such as `install-ha.sh`. Keep commands explicit and readable, one major operation per block. Quote variables and paths, especially when editing files such as `/boot/firmware/cmdline.txt`. Match the existing concise progress `echo` style when adding setup steps.

## Testing Guidelines

No automated test framework is configured. At minimum, run `bash -n` on every changed script. If available, also run `shellcheck scripts/*.sh` and address actionable warnings. For hardware validation, record the Raspberry Pi OS version, the command run, and the resulting Home Assistant URL or error output. Update `README.md` when setup behavior changes.

## Home Assistant Recorder Coverage

`recorder.include` is an allowlist: once it is configured, every entity outside
its included domains, globs, or entity IDs has no history, dashboard graphs, or
long-term statistics. This repository records the `sensor` and `binary_sensor`
domains, while excluding high-churn Roborock entities.

When adding or changing an integration, explicitly decide which of its entities
need history, graphs, alerts, or long-term statistics. Add the relevant domain,
glob, or entity ID to `recorder.include` when it is not already covered, and add
high-frequency or noisy entities to `recorder.exclude`. Validate the result in
Home Assistant's History view after deployment; do not assume a live entity is
being persisted.

## Available Home Assistant MCP

The Home Assistant MCP integration is available to connected clients. It can
read real-time context for exposed entities, filtering by entity name, domain,
or area. Use that read-only context first to confirm the current state before
any conditional device action.

Available device actions include generic on/off controls, vacuum start,
return-to-base, and area cleaning, media playback and volume controls, timers,
to-do lists, and Assist-satellite broadcasts. These actions operate only on
entities exposed to Assist/MCP; exposure is configured in Home Assistant's UI
and must be treated as the access boundary. Do not assume that an entity,
automation, helper, or integration is accessible simply because it exists in
the repository or appears in the Home Assistant UI.

Use MCP for inspection and explicitly requested live actions. Do not use it to
deploy YAML, modify Home Assistant configuration, or make broad state changes.
For any new integration, confirm its intended MCP exposure and whether its
entities are safe for read-only inspection or device control.

## Alexa and Matter

`homeassistant/packages/alexa.yaml` sends Roborock and Raspberry Pi alerts to
the Echo through the Alexa Devices integration. Use the existing notification
IDs and resource thresholds when extending those alerts.

Route Alexa voice commands to Home Assistant through the local Matter Hub
Docker container. Use `scripts/install-matter-hub.sh` and the setup steps in `README.md`.
Keep the Matter Hub management interface behind the SSH port forward and use
exact Home Assistant entity IDs when configuring device filters. The Roborock
uses a dedicated Server Mode device. The Samsung TV uses a separate bridge
with an On/Off Plug-In Unit mapping for power control.

Matter pairing and Assist/MCP exposure are configured independently. Verify
the Matter device type, controller pairing, and a voice command before
reporting that Alexa control works. Keep access tokens, pairing codes, and
Matter fabric data out of Git.

## Commit & Pull Request Guidelines

Recent commits use short imperative messages such as `Init HA` and `update HA configuration`; follow that style and keep each commit focused. Pull requests should describe the target hardware or OS version, list scripts changed, summarize manual validation, and mention any reboot, networking, Docker, or Home Assistant Supervisor impact. Include screenshots only when the visible Home Assistant result changes.

## Security & Configuration Tips

Do not commit private hostnames, SSH keys, tokens, Home Assistant secrets, or local `.homeassistant` configuration. Prefer placeholders in documentation and keep machine-specific values in local notes.
