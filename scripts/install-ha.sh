#!/bin/bash

set -eux

echo  "Install OS agent"

wget https://github.com/home-assistant/os-agent/releases/download/1.7.2/os-agent_1.7.2_linux_aarch64.deb
sudo dpkg -i os-agent_1.7.2_linux_aarch64.deb

echo "Install home assistant supervisor"

wget https://github.com/home-assistant/supervised-installer/releases/download/3.1.0/homeassistant-supervised.deb
sudo dpkg -i homeassistant-supervised.deb