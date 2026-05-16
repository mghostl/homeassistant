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

## Commit & Pull Request Guidelines

Recent commits use short imperative messages such as `Init HA` and `update HA configuration`; follow that style and keep each commit focused. Pull requests should describe the target hardware or OS version, list scripts changed, summarize manual validation, and mention any reboot, networking, Docker, or Home Assistant Supervisor impact. Include screenshots only when the visible Home Assistant result changes.

## Security & Configuration Tips

Do not commit private hostnames, SSH keys, tokens, Home Assistant secrets, or local `.homeassistant` configuration. Prefer placeholders in documentation and keep machine-specific values in local notes.
