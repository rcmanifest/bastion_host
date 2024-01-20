#!/bin/bash
set -e
set -x

# Ethernet address to search for
target_mac="16:22:33:44:55:66"

# Static IP to assign
static_ip="10.0.0.2/24"  # /24 is the subnet mask equivalent to 255.255.255.0

# Find the device with the given MAC address
target_device=$(ip link | grep -B1 "$target_mac" | head -n1 | awk '{print $2}' | tr -d ':')

if [ -z "$target_device" ]; then
    echo "No device with MAC address $target_mac found."
    exit 1
fi

echo "Found device: $target_device"

# Set the device down
sudo ip link set dev "$target_device" down
echo "Sleeping ..."
sleep 5

# Assign the static IP
set +e
sudo ip addr add $static_ip dev "$target_device"
set -e

# Bring the device up
sudo ip link set dev "$target_device" up
echo "Sleeping ..."
sleep 5

echo "Device $target_device is configured with IP $static_ip"
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no bastion@10.0.0.1

