#!/bin/bash

# Author: Wiliam de Freitas <wdefreitas@equinix.com>
# Date: May 2026
# Description: vulKiller (aka vk) automates the installation of security updates
# on Linux servers (Debian, Ubuntu, CentOS, Oracle Linux, and Rocky Linux). The
# script detects available security patches, applies them, and generates CSV
# evidence reports showing package versions before and after the update process.

################################################################################
# Identification Variables
################################################################################

# Just the tool name for log purposes:
tool_name="detect_uptime"

# The tool version:
tool_version="0.1.0"

# Amount of days of uptime to trigger the reboot:
uptime_threshold_days=30

# These variables are used to control the decision:
reboot_needed_by_uptime=0
reboot_needed_by_kernel=0

# Modal to enable system uptime detection:
modal_detect_uptime=1

# Modal to enable kernel update detection:
modal_detect_kernel=1

# Modal to enable server reboot when uptime reaches threshold and or a new kernel is detected:
modal_reboot_server=0

# Determine the current OS:
current_os="$(cat /etc/os-release | grep -w ID | awk -F= '{print$2}' | sed -e 's/"//g')"

function detect_kernel_update() {

    case $current_os in

        debian|ubuntu)

            if [ -f /var/run/reboot-required ] || [ -f /var/run/reboot-required.pkgs ]; then
                reboot_needed_by_kernel=1
            fi

        ;;

        rhel|centos|oracle|ol|rocky)

            if which grubby > /dev/null 2>&1; then

                # Check the current kernel version:
                current_kernel=$(uname -r 2>/dev/null || echo "")

                # Check the default kernel version:
                latest_kernel=$(rpm -q --last kernel 2>/dev/null | head -1 | awk '{print$1}' | sed -e 's/kernel-//g' || echo "")

                # Compares the current kernel version with the one configured as the default
                if [ -n "$current_kernel" ] && [ -n "$latest_kernel" ]; then

                    # If the version is different, mark the server as pending reboot:
                    if [ "$current_kernel" != "$latest_kernel" ]; then

                        reboot_needed_by_kernel=1

                    fi

                fi

            else

                # Check the installation date of the latest kernel:
                date_kernel_installation=$(rpm -q --last kernel 2>/dev/null | head -1 | awk '{print $2, $3, $4, $5, $6}')

                # Check the server uptime:
                date_last_system_boot=$(uptime -s 2>/dev/null || who -b | awk '{print $3, $4}')

                # Ensure if the variables were not empty:
                if [ -n "$date_kernel_installation" ] && [ -n "$date_last_system_boot" ]; then

                    # Convert dates to timestamps for comparison:
                    timestamp_kernel=$(date -d "$date_kernel_installation" +%s 2>/dev/null || echo 0)
                    timestamp_boot=$(date -d "$date_last_system_boot" +%s 2>/dev/null || echo 0)

                    # If the latest kernel was installed after the last system boot, mark the server as pending reboot:
                    if [ "$timestamp_kernel" -gt "$timestamp_boot" ]; then

                        reboot_needed_by_kernel=1

                    fi

                fi

            fi

        ;;

    esac

    case $reboot_needed_by_kernel in

        1) echo "A new kernel version is configured as default and the server needs to be rebooted to apply security fixes."
        *) echo "No new kernel version has been installed since the last reboot."

    esac

}

function detect_uptime() {

    # Get the server uptime in seconds:
    uptime_seconds=$(cat /proc/uptime 2>/dev/null | awk '{print int($1)}' || echo "")

    if [ -n "$uptime_seconds" ]; then

        # Convert uptime to human-readable format:
        uptime_human=$(date -u -d @"$uptime_seconds" +"%j days, %H hours, %M minutes, and %S seconds" 2>/dev/null || echo "")
        uptime_days=$(echo "$uptime_human" | awk -F' days, ' '{print $1}' 2>/dev/null || echo "0")

        if [ "$uptime_days" -gt "$uptime_threshold_days" ]; then

            reboot_needed_by_uptime=1

        fi

        echo "Server Uptime: $uptime_human"

    else

        echo "Unable to determine server uptime."

    fi

}