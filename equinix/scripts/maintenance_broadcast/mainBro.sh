#!/bin/bash

# Description: This script sends broadcast maintenance message in both Portuguese and English when the specified maintenance time is reached.
# Author: Wiliam de Freitas <wdefreitas@equinix.com>
# Date: 2026-08-11

# Determine the maintenance time (in HH:MM format)
maintenance_time="10:00"

# Define the maintenance messages in both languages
message_pt="Manutencao programada para as 10:00. Por favor, salve seu trabalho e saia do sistema."
message_eng="Scheduled maintenance at 10:00. Please save your work and log out of the system."

# Flags to control message sending
send_message_pt=true
send_message_en=true

# Check if message sending is enabled for either language
if [ "$send_message_pt" = false ] && [ "$send_message_en" = false ]; then

    exit 0

else

    # Loop until the maintenance time is reached
    while true; do

        current_time=$(date +%H:%M)

        if [ "$current_time" = "$maintenance_time" ]; then
            break
        fi

        if [ "$send_message_pt" = true ]; then
            echo -e "$message_pt"
        fi

        if [ "$send_message_en" = true ]; then
            echo -e "$message_eng"
        fi

        sleep 60

    done

fi