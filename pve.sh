#!/bin/bash
# Optimized Proxmox VE Installation Script with USTC Mirror Option
# Source: https://github.com/dahai0401/pve
# Updated: 2025-02-26

########## Color Output Functions ##########
_red() { echo -e "\033[31m\033[01m$@\033[0m"; }
_green() { echo -e "\033[32m\033[01m$@\033[0m"; }
_yellow() { echo -e "\033[33m\033[01m$@\033[0m"; }
_blue() { echo -e "\033[36m\033[01m$@\033[0m"; }
reading() { read -rp "$(_green "$1")" "$2"; }
export DEBIAN_FRONTEND=noninteractive

# Set UTF-8 locale
utf8_locale=$(locale -a 2>/dev/null | grep -i -m 1 -E "UTF-8|utf8")
if [[ -n "$utf8_locale" ]]; then
    export LC_ALL="$utf8_locale"
    export LANG="$utf8_locale"
    export LANGUAGE="$utf8_locale"
fi

########## Basic System Checks ##########
if [ "$(id -u)" != "0" ]; then
    _red "This script must be run as root."
    exit 1
fi

if dpkg -l | grep -q 'proxmox-ve'; then
    _green "Proxmox VE is already installed. Exiting."
    exit 1
fi

########## Ask User for Location ##########
reading "Are you in China? (y/n): " location_choice
if [[ "$location_choice" =~ ^[Yy]$ ]]; then
    _green "Using USTC mirror for better speed in China."
    use_ustc=true
else
    _green "Using default Proxmox and Debian sources."
    use_ustc=false
fi

########## Configure APT Sources ##########
if [ "$use_ustc" = true ]; then
    # Backup existing sources
    cp /etc/apt/sources.list /etc/apt/sources.list.bak

    # Use USTC mirror
    cat <<EOF > /etc/apt/sources.list
deb https://mirrors.ustc.edu.cn/debian/ bookworm main contrib non-free non-free-firmware
deb https://mirrors.ustc.edu.cn/debian/ bookworm-updates main contrib non-free non-free-firmware
deb https://mirrors.ustc.edu.cn/debian/ bookworm-backports main contrib non-free non-free-firmware
deb https://mirrors.ustc.edu.cn/debian-security bookworm-security main
EOF

    cat <<EOF > /etc/apt/sources.list.d/ceph.list
deb https://mirrors.ustc.edu.cn/proxmox/debian/ceph-quincy bookworm no-subscription
EOF

    cat <<EOF > /etc/apt/sources.list.d/pve-enterprise.list
deb https://mirrors.ustc.edu.cn/proxmox/debian bookworm pve-no-subscription
EOF

    # Ensure the enterprise list does not use a paid subscription
    sed -i 's/^deb/#deb/g' /etc/apt/sources.list.d/pve-enterprise.list

    # Update GPG keys
    wget -qO- https://mirrors.ustc.edu.cn/proxmox/debian/proxmox-release-bookworm.gpg | tee /etc/apt/trusted.gpg.d/proxmox-release.gpg >/dev/null
fi

########## Install Required Packages ##########
apt-get update -y && apt-get upgrade -y
install_package() {
    local package_name=$1
    if ! command -v "$package_name" >/dev/null 2>&1; then
        apt-get install -y "$package_name" --allow-downgrades --allow-remove-essential --allow-change-held-packages
        if [ $? -ne 0 ]; then
            _red "Failed to install $package_name. Exiting."
            exit 1
        fi
    fi
}

install_package wget
install_package curl
install_package sudo
install_package iproute2
install_package dnsutils
install_package net-tools
install_package lsb-release
install_package ethtool
install_package chrony

########## Set System Time ##########
systemctl stop ntpd 2>/dev/null || true
systemctl stop chronyd 2>/dev/null || true
chronyd -q
systemctl start chronyd

########## Configure Hostname ##########
reading "Enter a new hostname (default: pve): " new_hostname
new_hostname=${new_hostname:-pve}
hostnamectl set-hostname "$new_hostname"
echo "$new_hostname" > /etc/hostname
sed -i "/127.0.0.1/c\127.0.0.1 localhost $new_hostname" /etc/hosts
if ! grep -q "::1 localhost" /etc/hosts; then
    echo "::1 localhost" >> /etc/hosts
fi

########## Add Proxmox VE Repository ##########
if [ "$use_ustc" = false ]; then
    version=$(lsb_release -cs)
    echo "deb http://download.proxmox.com/debian/pve $version pve-no-subscription" > /etc/apt/sources.list.d/pve.list
    wget -qO- http://download.proxmox.com/debian/proxmox-release-$version.gpg | tee /etc/apt/trusted.gpg.d/proxmox-release.gpg >/dev/null
    apt-get update -y
fi

########## Install Proxmox VE ##########
install_package proxmox-ve
install_package postfix
install_package open-iscsi

########## Configure Networking ##########
interface=$(ip -o -4 route show to default | awk '{print $5}')
ipv4_address=$(ip -o -4 addr show dev $interface | awk '{print $4}' | cut -d'/' -f1)
ipv4_gateway=$(ip route | awk '/default/ {print $3}')

cat <<EOF > /etc/network/interfaces
auto lo
iface lo inet loopback

auto vmbr0
iface vmbr0 inet static
    address $ipv4_address
    gateway $ipv4_gateway
    bridge_ports $interface
    bridge_stp off
    bridge_fd 0
EOF

systemctl restart networking

########## Installation Complete ##########
_green "Installation complete! Access Proxmox VE at: https://$ipv4_address:8006/"
_green "Login with your root credentials."
exit 0
