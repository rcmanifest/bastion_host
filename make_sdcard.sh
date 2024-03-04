#!/bin/bash
#This script creates a an sdcard for pi0w.
set -u

#Functions
single_step() 
{
	#Called from trap DEBUG
	{ set +x; } &> /dev/null
	if [ "$START_SINGLE_STEP" ]; then
		echo "Press enter to continue"
		read
	fi
	set -x
}
mypause()
{ 
	if [ ! -z $1 ];then
		echo "Paused at $1.  "
	fi
	echo "Hit any key to continue"
	read
}
wait_for_enter()
{
	echo "Press enter to continue"
	read a
}
enable_serial_boot_messages()
{
	# File paths
	CONFIG_FILE="$1/config.txt"
	CMDLINE_FILE="$1/cmdline.txt"

	# Enable UART in /boot/config.txt
	if grep -q "^enable_uart=1" "$CONFIG_FILE"; then
		echo "UART is already enabled in $CONFIG_FILE."
	else
		echo "Enabling UART in $CONFIG_FILE."
		echo "enable_uart=1" | sudo tee -a "$CONFIG_FILE" > /dev/null
	fi

	# Want boot messages on uart, check if 'quiet' exists in the cmdline.txt
	if grep -q "quiet" "$CMDLINE_FILE"; then
		echo "'quiet' found in $CMDLINE_FILE. Removing it..."
		# Remove 'quiet' and update the file
		sudo sed -i 's/ quiet//g' "$CMDLINE_FILE"
		echo "'quiet' has been removed."
	else
		echo "'quiet' is not present in $CMDLINE_FILE."
	fi
}
enable_ssh()
{
	sudo touch $1/ssh	
}
mount_partition()
{
	MNT_DIR=$1
	MNT_DIR=$(pwd)/"$MNT_DIR"
	PARTITION=$2

	#There can be several leftover loop mounts
	while  [ "$(df --output=target "$MNT_DIR" | tail -1)" = "$MNT_DIR" ] ; do
		sudo umount $MNT_DIR; 
	done

	mkdir -p $MNT_DIR
	# Get the start offset of the partition
	#fdisk -l displays the partitions as filename1 filename2 ....
	offset=$(fdisk -l "$IMG_FILENAME" | grep '^'$IMG_FILENAME"$2" | awk '{print $2 * 512}')
	
	# Check if offset was found
	if [ -z "$offset" ]; then
		echo "Error: Could not find offset for the partition."
		exit 1
	fi
	# Mount the partition
	sudo mount -o loop,offset=$offset "$IMG_FILENAME" "$MNT_DIR"
}
add_user()
{
	USER_NAME="bastion"
	USER_ID="2000"
	GROUP_ID="$USER_ID" # Typically the same as USER_ID for a new user
	PASSWORD_HASH="" #$6$xnoIzbJMjxXxBqLg$f5FStd1tyRXesyfiTXCBrgeQUAyMc7Q7QRwKDGCHFLF0VsBicRo8mWLzRP15xjD.LM0hOX0ODfakFPlUL9WiG.' # Password hash
	HOME_DIR="/" #/home/$USER_NAME"
	SHELL="/bin/bash"

	MOUNT_POINT=$1

	# Check if user already exists
	if grep -q "^$USER_NAME:" $MOUNT_POINT/etc/passwd; then
		echo "User $USER_NAME already exists in the image."
	else
		# Add user to /etc/passwd
		echo "$USER_NAME:x:$USER_ID:$GROUP_ID::${HOME_DIR}:${SHELL}" | sudo tee -a $MOUNT_POINT/etc/passwd

		# Add user to /etc/shadow
		TODAY=$(date +%s)
		SHADOW_ENTRY="$USER_NAME:$PASSWORD_HASH:$TODAY:0:99999:7:::"
		echo "$SHADOW_ENTRY" | sudo tee -a $MOUNT_POINT/etc/shadow

		# Create home directory
		#sudo mkdir -p $MOUNT_POINT${HOME_DIR}
		#sudo chown $USER_ID:$GROUP_ID $MOUNT_POINT${HOME_DIR}
		#sudo chmod 700 $MOUNT_POINT${HOME_DIR}

		#Add bastion to sudo group
		GROUP_NAME="sudo"
		# Check if the sudo group exists in the /etc/group file
		if ! grep -q "^$GROUP_NAME:" $MOUNT_POINT/etc/group; then
			echo "Group $GROUP_NAME does not exist in the image."
			exit 1
		fi

		# Check if bastion is already in the sudo group
		if grep -q "^$GROUP_NAME:.*:$USER_NAME" $MOUNT_POINT/etc/group; then
			echo "User $USER_NAME is already in the $GROUP_NAME group."
		else
			# Add bastion to the sudo group
			sudo sed -i "/^$GROUP_NAME:/ s/\$/,$USER_NAME/" $MOUNT_POINT/etc/group
			echo "User $USER_NAME added to the $GROUP_NAME group."
		fi

		echo "User $USER_NAME has been added to the disk image."
	fi
}
enable_gadget() 
{
	BOOT_MOUNT_PATH="$1"

	#Configure Boot Config
	if ! grep -q "^dtoverlay=dwc2" "$BOOT_MOUNT_PATH/config.txt"; then
		echo "dtoverlay=dwc2" | sudo tee -a  "$BOOT_MOUNT_PATH/config.txt"
	else
		echo "dwc2 already exists in config.txt"
	fi

	#Enable USB Ethernet Gadget in cmdline.txt
	# Caution: This step involves editing the cmdline.txt which is sensitive
	CMDLINE="$BOOT_MOUNT_PATH/cmdline.txt"
	if grep -q "modules-load=dwc2,g_ether" "$CMDLINE"; then
		echo "Ethernet gadget already enabled in cmdline.txt."
	else
		# Insert 'modules-load=dwc2,g_ether' after 'rootwait'
		sudo sed -i 's/rootwait/rootwait modules-load=dwc2,g_ether g_ether.dev_addr=12:22:33:44:55:66 g_ether.host_addr=16:22:33:44:55:66/' "$CMDLINE"
	fi

	echo "Ethernet gadget setup is complete."
}
configure_access_point() 
{
	# Install hostapd and dnsmasq
	run_in_chroot "apt-get update"
	run_in_chroot "apt-get install -y hostapd dnsmasq"

	# Stop services for configuration (they will run on boot)
	#run_in_chroot "systemctl stop hostapd"
	#run_in_chroot "systemctl stop dnsmasq"

	# Configure hostapd
	cat <<-EOF > tmp 
		interface=wlan0
		driver=nl80211
		ssid=benchy
		hw_mode=g
		channel=7
		wmm_enabled=0
		macaddr_acl=0
		auth_algs=1
		ignore_broadcast_ssid=0
		wpa=2
		wpa_passphrase=eryone1!
		wpa_key_mgmt=WPA-PSK
		wpa_pairwise=TKIP
		rsn_pairwise=CCMP
	EOF
	if [ -f "${ROOT_DIR}/etc/hostapd/hostapd.conf" ]; then
		sudo cp "${ROOT_DIR}/etc/hostapd/hostapd.conf" "${ROOT_DIR}/etc/hostapd/hostapd.conf.bak"
	fi
	sudo cp tmp "${ROOT_DIR}/etc/hostapd/hostapd.conf"
	rm tmp

	# Tell the system to use our hostapd.conf
	echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' | sudo tee -a "${ROOT_DIR}/etc/default/hostapd"

	# Configure dnsmasq
	cat <<-EOF > tmp 
		### wlan0 ###
		interface=wlan0
		dhcp-range=192.168.150.2,192.168.150.20,255.255.255.0,24h
	EOF
	
	sudo cp "${ROOT_DIR}/etc/dnsmasq.conf" "${ROOT_DIR}/etc/dnsmasq.conf.bak"
	sudo cp tmp "${ROOT_DIR}/etc/dnsmasq.conf"
	rm tmp

	# Configure network interfaces
	cat <<EOF > tmp 
auto wlan0
iface wlan0 inet static
	address 192.168.150.1
	netmask 255.255.255.0
	network 192.168.150.0
EOF
	sudo cp tmp "${ROOT_DIR}/etc/network/interfaces.d/wlan0"
	rm tmp

}

# Function to check if a package is installed
is_package_installed() {
    dpkg -s "$1" &> /dev/null
    return $?
}
install_qemu()
{
	# List of packages to check
	packages=("qemu" "qemu-user-static" "binfmt-support")
	
	# Check each package
	for pkg in "${packages[@]}"; do
		if is_package_installed "$pkg"; then
			echo "Package '$pkg' is installed."
		else
			echo "Package '$pkg' is NOT installed."
			sudo apt-get install $pkg
		fi
	done
}
set_interface_names()
{
	echo "plug in the INTERNAL interface and enter the mac address:"
#	read MAC_ADDR_INT
	MAC_ADDR_INT=20:7b:d2:ac:ec:06 #debug remove

	echo "plug in the EXTERNAL interface and enter the mac address:"
	#read MAC_ADDR_EXT
	MAC_ADDR_EXT=20:7b:d2:ac:69:c8  #debug remove

	cat << EOF > tmp 
SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="$MAC_ADDR_EXT", NAME="$EXTERNAL_IFACE"
SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="$MAC_ADDR_INT", NAME="$INTERNAL_IFACE"
EOF
	sudo cp tmp "${ROOT_DIR}/etc/udev/rules.d/10-rename-network.rules"
	rm tmp

}
configure_usb_ethernet_interface()
{
	# Variables for network interfaces
	cat <<-EOF > tmp
	[Unit]
	Description=Run my script at first boot
	After=network.target
	
	[Service]
	Type=oneshot
	ExecStart=/runonce/iptables.sh
	ExecStartPost=/bin/systemctl disable firstboot.service
	
	[Install]
	WantedBy=multi-user.target
	EOF

	sudo cp tmp "${ROOT_DIR}/etc/systemd/system/firstboot.service"
	rm tmp

	run_in_chroot "systemctl enable firstboot.service"

	#Create iptables script
	cat <<-EOF > tmp
	#!/bin/bash
	
	# Flush existing rules
	iptables -F
	iptables -t nat -F
	iptables -t mangle -F
	iptables -X
	
	# Set default policies
	iptables -P INPUT DROP
	iptables -P FORWARD DROP
	iptables -P OUTPUT ACCEPT
	
	# Allow all loopback traffic
	iptables -A INPUT -i lo -j ACCEPT
	iptables -A OUTPUT -o lo -j ACCEPT
	
	#Allow connections on wlan0
	iptables -A INPUT -i wlan0 -j ACCEPT
	
	# Allow established and related connections
	iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
	iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
	
	# Allow all outgoing connections from the internal network
	iptables -A FORWARD -i $INTERNAL_IFACE -o $EXTERNAL_IFACE -j ACCEPT
	
	# Enable NAT for the internal network
	iptables -t nat -A POSTROUTING -o $EXTERNAL_IFACE -j MASQUERADE

	# Allow DHCP on eth_int
	iptables -A INPUT -i $INTERNAL_IFACE -p udp --dport 67:68 --sport 67:68 -j ACCEPT

	# Allow SSH access on the external interface (optional, remove if not needed)
	iptables -A INPUT -i $EXTERNAL_IFACE -p tcp --dport 2222 -j ACCEPT
	iptables -A INPUT -i wlan0 -p tcp --dport 4444 -j ACCEPT
	
	

	# Drop invalid packets
	iptables -A INPUT -m state --state INVALID -j DROP
	iptables -A FORWARD -m state --state INVALID -j DROP
	
	# Save the iptables rules (Debian/Ubuntu)
	iptables-save > /etc/iptables/rules.v4
	
	EOF

	sudo mkdir "${ROOT_DIR}/runonce"
	sudo cp tmp "${ROOT_DIR}/runonce/iptables.sh"
	sudo chmod +x "${ROOT_DIR}/runonce/iptables.sh"
	rm tmp

	# Make IP forwarding and iptables rules persistent
	echo "Making IP forwarding and iptables rules persistent..."
	run_in_chroot "echo net.ipv4.ip_forward=1 | sudo tee -a /etc/sysctl.conf"

	echo "Automating installation of ip-tables-persistent by using debconf"
	run_in_chroot "apt-get install -y debconf"
	run_in_chroot "echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections"
	run_in_chroot "echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections"

	run_in_chroot "apt-get install -y iptables-persistent"

}
##########################3
configure_internal_interface()
{
	# Define static IP configuration for $INTERNAL_IFACE
	DESIRED_IP="192.168.1.1"
	NETMASK="255.255.255.0"
	BROADCAST="192.168.1.255"

	echo "INTERNAL_IFACE=$INTERNAL_IFACE"

	# Configure dnsmasq
	#cat <<EOF > tmp
	cat <<-EOF > tmp
		# Set the interface for dnsmasq to listen on
		interface=$INTERNAL_IFACE

		# Specify the network range and lease time
		dhcp-range=192.168.1.10,192.168.1.100,255.255.255.0,24h

		# Set the default gateway
		dhcp-option=option:router,$DESIRED_IP

		# Set the DNS server (itself)
		dhcp-option=option:dns-server,$DESIRED_IP

		# Enable DHCP for IPv4
		dhcp-authoritative

		# Specify the broadcast address
		dhcp-option=28,$BROADCAST
	EOF
	cat tmp | sudo tee -a "$ROOT_DIR/etc/dnsmasq.conf"
	#sudo cp tmp "$ROOT_DIR"/etc/dnsmasq_eth_int.conf
	rm tmp

	# Assign static IP to $INTERNAL_IFACE
	# Check if the interface configuration already exists
	if grep -q "^iface $INTERNAL_IFACE inet" "$ROOT_DIR"/etc/network/interfaces; then
		echo "Interface $INTERNAL_IFACE configuration exists."
		echo "Please consider editing $ROOT_DIR/etc/network/interfaces manually to adjust the configuration."
		exit 1
	else
		# Add the new interface configuration
		echo -e "\n# Configuration for $INTERNAL_IFACE" | sudo tee -a "$ROOT_DIR"/etc/network/interfaces
		echo "auto $INTERNAL_IFACE" | sudo tee -a "$ROOT_DIR"/etc/network/interfaces
		echo "iface $INTERNAL_IFACE inet static" | sudo tee -a "$ROOT_DIR"/etc/network/interfaces
		echo "    address $DESIRED_IP" | sudo tee -a "$ROOT_DIR"/etc/network/interfaces
		echo "    netmask $NETMASK" | sudo tee -a "$ROOT_DIR"/etc/network/interfaces
		#echo "    dns-nameservers $DNS_SERVERS" | sudo tee -a "$ROOT_DIR"/etc/network/interfaces
		echo "Interface $INTERNAL_IFACE configured with static IP $DESIRED_IP."
	fi
}


###################################
customize_image()
{
	BOOT_DIR=boot
	ROOT_DIR=rootfs
	EXTERNAL_IFACE="eth_ext"
	INTERNAL_IFACE="eth_int"

	if [ -f $IMG_FILENAME ]; then
		rm -v "$IMG_FILENAME"
	fi
	
	echo "Decompressing image ..."
	xz --decompress --keep "$IMG_FILENAME".xz

	mount_partition "$BOOT_DIR" 1

	echo "Enabling serial boot messages on $BOOT_DIR" 
	enable_serial_boot_messages "$BOOT_DIR"
	
	echo "Enabling ssh on $BOOT_DIR" 
	enable_ssh "$BOOT_DIR"

	echo "Enabling usb gadget on $BOOT_DIR" 
	enable_gadget "$BOOT_DIR"
	sync
	sudo umount "$BOOT_DIR"

	mount_partition "$ROOT_DIR" 2

	echo "Adding user to $ROOT_DIR"
	add_user "$ROOT_DIR"

	echo "Setting gadget ip address in dhcpcd.conf"
	set_gadget_ip_address "$ROOT_DIR"

	echo "Setting ssh ports in sshd_config"
	set_ssh_ports "$ROOT_DIR"

	# Check each mount point
	ROOT_DIR=$(pwd)/rootfs
	#check_mount "dev"
	#check_mount "sys"
	#check_mount "proc"
	#check_mount "dev/pts"

	echo "Installing qemu on host system in order to run chroot as arm"
	install_qemu

	sudo cp /usr/bin/qemu-arm-static "$ROOT_DIR"/usr/bin/

	echo "Generating udev rules for ethernet interfaces"
	set_interface_names
	
	echo "Creating iptables script, runonce service, and installing iptables"
	configure_usb_ethernet_interface

	echo "installing hostapd and dnsmasq.  Configuring wlan0 dnsmasq and ip address"
	configure_access_point
	
	echo "configure dnsmasq_eth_int. Set eth_int static ip"
	configure_internal_interface

	echo "Force user to enter new password on first login"
	run_in_chroot "sudo passwd -e bastion" 

	#sudo umount "$ROOT_DIR"/dev
	#sudo umount "$ROOT_DIR"/sys
	#sudo umount "$ROOT_DIR"/proc
	#sudo umount "$ROOT_DIR"/dev/pts
	sudo umount "$ROOT_DIR"
}

display_command_line_options()
{
	echo "Command line options:"
	echo -e "\tDEBUG: sets -x"
	echo -e "\tFORCE: force dd to use block device even if it is large"
	echo -e "\tSINGLE: single step"
}
parse_command_line_options()
{
	# Loop through each command line argument
	unset DEBUG
	FORCE=0
	for arg in "$@"
	do
		if [ "$arg" = "SINGLE" ]; then
			echo "SINGLE mode is set."
			SINGLE=1
			trap '{ single_step; } > output.txt' DEBUG
		fi

		if [ "$arg" = "DEBUG" ]; then
		echo "DEBUG mode is set."
		DEBUG=1
		set -x
		fi

		if [ "$arg" = "FORCE" ]; then
		echo "FORCE mode is set."
		FORCE=1
		fi
	done

}
get_sdcard()
{
	if ! $TESTING; then
		echo "Please insert the sdcard to be flashed"
		wait_for_enter
		lsblk
		echo "Enter the full path of the sdcard device (eg. /dev/sxx)"
		read device
		if ! echo "$device" | grep -q "/dev/"  ; then
			echo "the full path must contain /dev/"
			exit 1
		fi
		disk_size=`lsblk -b --output SIZE -n -d $device`
		disk_size=$((disk_size/1024/1024))
		echo "Disk size is $disk_size MB"

		if ! [ $FORCE -eq 1 ] ; then
			if [ $disk_size -gt 65000  ]; then
				echo "This disk is larger than a typical sd card"
				echo "You don't want to dd to your hard drive!"
				echo "Please run again with FORCE"
				exit 2
			fi
		fi
		#Unmount all partitions
		set +e
		for i in {1..10}
		do
			echo "Unmounting $device$i"
			sudo umount $device$i
		done
	else
		echo "---------- In test mode  ----------"
	fi
}
###################
#Script execution starts here
set -o functrace	#enables single stepping inside functions
set -e

cscope -b -R *.sh

TESTING=false
unset START_SINGLE_STEP

display_command_line_options
unset SINGLE	#Set START_SINGLE_STEP to a value where you want to start single stepping
parse_command_line_options $@

IMG_FILENAME=pi0w_os/2023-12-05-raspios-bullseye-armhf-lite.img
customize_image
get_sdcard

sudo dd if="$IMG_FILENAME" of=$device bs=1M status=progress status=progress conv=nocreat,fdatasync

if [ $? -eq 0 ]; then
	echo "sdcard flashed successfully!"
else
	echo "sdcard flashing FAILED"
fi


