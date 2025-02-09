#!/bin/bash

set -eux

echo  "Install OS agent"

wget https://github.com/home-assistant/os-agent/releases/download/1.6.0/os-agent_1.6.0_linux_aarch64.deb
sudo dpkg -i os-agent_1.6.0_linux_aarch64.deb

echo "Install home assistant supervisor"

wget https://github.com/home-assistant/supervised-installer/releases/download/2.0.0/homeassistant-supervised.deb
sudo dpkg -i homeassistant-supervised.deb