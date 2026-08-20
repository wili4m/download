#!/bin/bash

# Description: This script checks if lockdown mode is enabled on the system.
# and perform the deactivation followed by a reboot.
# Script by: wdefreitas <wdefreitas@equinix.com>
# Date: 2026-08-07

grubd=/etc/default/grub.d

if command cat /proc/cmdline | xargs -n1 | grep lockdown 2>&1 >/dev/null; then

    # Check how many configuration files were found and handle accordingly
    case $(grep -Ri lockdown $grubd | cut -d: -f1 | wc -l) in

        0)
            lockdown_config=""
        ;;

        1)
            # Determine the configuration file that contains the lockdown setting
            lockdown_config="$(grep -Ri lockdown $grubd | cut -d: -f1)"
        ;;

        *)
            echo "Multiple lockdown configuration files found."
            exit 1
        ;;

    esac

    if [ -n "$lockdown_config" ]; then

        date=$(date +%Y%m%d)

        echo "Lockdown mode is enabled in the configuration file: $lockdown_config"

        echo "Renaming the configuration file to disable lockdown mode..."
        mv "$lockdown_config" "${lockdown_config}.${date}.disabled"

        case $? in

            0)
                if [ -f "${lockdown_config}.${date}.disabled" ]; then
                    echo "Configuration file renamed successfully."
                else
                    echo "Failed to rename the configuration file. Please check permissions and try again."
                    exit 1
                fi
            ;;

            *)
                echo "Failed to disable lockdown mode. Please check permissions and try again."
                exit 1
            ;;

        esac

        echo -e "\nUpdating GRUB configuration...\n"
        update-grub

        case $? in

            0)
                echo -e "\nGRUB configuration updated successfully."
                echo "Rebooting the system to apply changes...\n"
                echo "shutdown -rf"
                exit 0

            ;;

            *)1
                echo -e "\nFailed to update GRUB configuration. Please check permissions and try again."
                exit 1
            ;;

        esac

    else

            echo "No lockdown configuration file found. Please check the /etc/default/grub.d directory and ensure that the lockdown setting is present."
            exit 1

    fi

else

    echo "Lockdown mode is not enabled"
    exit 0

fi