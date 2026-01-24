#!/bin/bash

set -e

echo "Обновление списка пакетов и пакетов"
apt update
apt upgrade -y

echo "Обновление прошивки - только при необходимости!"
rpi-update

echo "Установка необходимых пакетов"
apt-get install -y jq wget curl udisks2 apparmor-utils libglib2.0-bin network-manager dbus systemd-journal-remote systemd-resolved vim

echo "Запуск Network Manager"
systemctl start NetworkManager
systemctl enable NetworkManager

echo "Дополнительные настройки для устранения ошибок в НА" 

FILE="/boot/firmware/cmdline.txt"
PARAMS="systemd.unified_cgroup_hierarchy=false lsm=apparmor"

# Добавляем параметры, если их ещё нет
if ! grep -q "systemd.unified_cgroup_hierarchy" "$FILE"; then
    sudo sed -i "1s|$| $PARAMS|" "$FILE"
    echo "Параметры добавлены."
else
    echo "Параметры уже присутствуют."
fi