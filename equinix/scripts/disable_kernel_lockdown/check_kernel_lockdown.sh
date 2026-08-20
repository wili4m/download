#!/bin/bash

# Description: This script checks if lockdown mode is enabled on the system.
# Script by: wdefreitas <wdefreitas@equinix.com>
# Date: 2026-08-07

grubd=/etc/default/grub.d

if command cat /proc/cmdline | xargs -n1 | grep lockdown 2>&1 >/dev/null; then

    # Check how many configuration files were found and handle accordingly
    case $(grep -Ri lockdown $grubd | cut -d: -f1 | wc -l) in

        0)
            lockdown_config=""
        ;;

        *)
            echo "Lockdown mode is enabled:"
            grep -Ri lockdown $grubd | cut -d: -f1
        ;;

   esac

else

    echo "Lockdown mode is not enabled"
    exit 0

fi