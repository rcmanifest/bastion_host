#!/bin/bash
#This script creates a an sdcard for pi0w.

#Functions
single_step() 
{
	#Called from trap DEBUG
	{ set +x; } &> /dev/null
	if [ "$START_SINGLE_STEP" ]; then
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
mount_partition()
{
	MNT_DIR=$1
	PARTITION=$2

	if [ "$(df --output=target "$MNT_DIR" | tail -1)" = "$MNT_DIR" ] ; then

	#if [ -d "$MNT_DIR" ]; then
		sudo umount $MNT_DIR; 
	fi
	mkdir -p $MNT_DIR
	# Get the start offset of the partition
	#fdisk -l displays the partitions as filename1 filename2 ....
	offset=$(fdisk -l "$IMG_FILENAME" | grep '^'$IMG_FILENAME"$2" | awk '{print $2 * 512}')
	
	# Check if offset was found
	if [ -z "$offset" ]; then
		echo "Error: Could not find offset for the second partition."
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
	PASSWORD_HASH='$6$xnoIzbJMjxXxBqLg$f5FStd1tyRXesyfiTXCBrgeQUAyMc7Q7QRwKDGCHFLF0VsBicRo8mWLzRP15xjD.LM0hOX0ODfakFPlUL9WiG.' # Password hash
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

customize_image()
{
	if [ -f $IMG_FILENAME ]; then
		rm -v "$IMG_FILENAME"
	fi
	
	echo "Decompressing image ..."
	xz --decompress --keep "$IMG_FILENAME".xz

	mount_partition boot 1
	enable_serial_boot_messages boot
	sudo umount boot

	mount_partition rootfs 2
	add_user rootfs
	sudo umount rootfs
}

display_command_line_options()
{
	echo "Command line options:"
	echo -e "\tDEBUG: sets -x"
	echo -e "\tF: force dd to use block device even if it is large"
	echo -e "\tSINGLE: single step"
}
parse_command_line_options()
{
	# Loop through each command line argument
	unset DEBUG
	unset FORCE
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

		if ! [ "$FORCE" ] ; then
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

TESTING=false
unset START_SINGLE_STEP

display_command_line_options
unset SINGLE	#Set START_SINGLE_STEP to a value where you want to start single stepping
parse_command_line_options $@

START_SINGLE_STEP=1
IMG_FILENAME=pi0w_os/2023-12-05-raspios-bullseye-armhf-lite.img
customize_image
get_sdcard

sudo dd if="$IMG_FILENAME" of=$device bs=1M status=progress status=progress conv=nocreat,fdatasync

if [ $? -eq 0 ]; then
	sync
	sleep 10
	echo "sdcard flashed successfully!"
else
	echo "sdcard flashing FAILED"
fi
date

