#!/bin/bash

# Author: Wiliam de Freitas <wdefreitas@equinix.com>
# Date: May 2026

# Description: DSU (Detect System Uptime) is a script that checks the server uptime and determines if a reboot is needed based on a predefined threshold.
# The script can be used as part of a larger automation process to ensure servers are rebooted when necessary to maintain optimal performance and security.

# Just the tool name for log purposes:
tool_name="detect_uptime"

# Amount of days of uptime to trigger the reboot:
uptime_threshold_days="30"

function detect_uptime() {

    # Get the server uptime in seconds:
    uptime_seconds=$(cat /proc/uptime 2>/dev/null | awk '{print int($1)}' || echo "")

    if [ -n "$uptime_seconds" ]; then

        # Convert uptime to human-readable format:
        uptime_human=$(date -u -d @"$uptime_seconds" +"%j days, %H hours, %M minutes, and %S seconds." 2>/dev/null || echo "")
        uptime_days=$(echo "$uptime_human" | awk -F' days, ' '{print $1}' 2>/dev/null || echo "0")

        if [ "$uptime_days" -gt "$uptime_threshold_days" ]; then

            # Mark the server as pending reboot because of uptime:
            reboot_needed_by_uptime=1

        fi

    else

        # Did not get the uptime, so we cannot determine if a reboot is needed:
        echo "Unable to determine server uptime."

    fi

}

# Call the function to detect uptime and determine if a reboot is needed:
detect_uptime

# Check if a reboot is needed due to the system uptime:
case $reboot_needed_by_uptime in

    1) # Uptime exceeds the threshold, so we recommend a reboot:

        echo "Uptime: $uptime_human"
        echo "Status: Reboot required. Uptime exceeds ${uptime_threshold_days}-day threshold."
        exit 1
    ;;

    *) # Uptime is within acceptable limits, so no reboot is needed:

        echo "Uptime: $uptime_human"
        echo "Status: No reboot needed."
        exit 0
    ;;

esac