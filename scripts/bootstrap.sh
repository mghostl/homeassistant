#!/bin/bash

set -eux

echo "Обновление списка пакетов и пакетов"
apt update
apt upgrade -y

echo "Обновление прошивки - только при необходимости!"
rpi-update

echo "Установка необходимых пакетов"
apt-get install -y jq wget curl udisks2 apparmor-utils libglib2.0-bin network-manager dbus systemd-journal-remote systemd-resolved

echo "Запуск Network Manager"
systemctl start NetworkManager
systemctl enable NetworkManager

