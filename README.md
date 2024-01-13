# bastion_host

**Instructions to configure a bastion host
**

# Raspberry Pi Zero W Bastion Host Setup

This guide outlines the process of setting up a Raspberry Pi Zero W as a bastion host with two USB-to-Ethernet interfaces.

## Prerequisites

- Raspberry Pi Zero W
- 2 USB-to-Ethernet adapters
- MicroSD card (8GB or larger)
- Access to a computer for initial setup

## Raspberry Pi OS Setup

1. **Flash sdcard:**
<br>\#./make_sdcard.sh




2. **Flash the OS to MicroSD Card:** Use a tool like [balenaEtcher](https://www.balena.io/etcher/) to flash the downloaded image to your MicroSD card.

3. **Enable SSH:** To enable SSH on your Raspberry Pi, place an empty file named `ssh` (without any extension) in the boot partition of the MicroSD card.

4. **Insert MicroSD Card:** Insert the MicroSD card into your Raspberry Pi Zero W.

5. **Power Up:** Connect your Raspberry Pi to power and wait for it to boot.

## Network Configuration

1. **Connect Ethernet Adapters:** Connect the USB-to-Ethernet adapters to the Raspberry Pi.

2. **Identify Interfaces:** SSH into the Raspberry Pi and use the `ip a` command to identify the network interfaces.

3. **Configure Interfaces:**
    - Edit the `/etc/dhcpcd.conf` file to configure the interfaces.
    - Set the interface connected to the internal LAN with a static IP. Add the following lines:

    ```
    interface <INTERNAL_INTERFACE_NAME>
    static ip_address=192.168.2.1/24
    ```

4. **Restart Networking:** Restart the networking service with `sudo service dhcpcd restart`.

## SSH Configuration

1. **Install SSH (if not pre-installed):** `sudo apt-get install openssh-server`.

2. **Configure SSH:**
    - Edit `/etc/ssh/sshd_config`.
    - Change the port to 220022: `Port 220022`.
    - Restart SSH: `sudo service ssh restart`.

## Firewall Configuration

1. **Install UFW:** `sudo apt-get install ufw`.

2. **Configure UFW:**
    - Allow SSH: `sudo ufw allow 220022/tcp`.
    - Enable UFW: `sudo ufw enable`.

## Git Repository Setup

1. **Install Git:** `sudo apt-get install git`.

2. **Initialize Git Repository:**
    - `git init MyBastionHost`.
    - `cd MyBastionHost`.

3. **Add Submodule for Raspberry Pi OS:**
    - `git submodule add [URL_OF_RASPBERRY_PI_OS_REPO] rpi-os`.
    - Replace `[URL_OF_RASPBERRY_PI_OS_REPO]` with the Git repository URL of the Raspberry Pi OS (if available).

4. **Commit Changes:**
    - `git add .`.
    - `git commit -m "Initial commit"`.

5. **Push to Remote Repository (Optional):**
    - Create a repository on GitHub/GitLab/etc.
    - `git remote add origin [REMOTE_REPOSITORY_URL]`.
    - `git push -u origin master`.

## Conclusion

Your Raspberry Pi Zero W is now configured as a bastion host. Ensure regular updates and monitor logs for any unauthorized access attempts.
