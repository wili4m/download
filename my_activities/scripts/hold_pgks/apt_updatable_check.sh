#!/bin/bash

# Author: gcamposjunior@equinix.com
# Date: 05/2026
# Description: 
#   Lists open TCP/UDP ports, identifies processes (PID),
#   resolves the executing binary, and show which Debian
#   package the binary belongs to.



GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
RESET="\e[0m"

# Fetch all open TCP/UDP ports and extract associated PIDs
ss -tulpn | grep pid= | \
grep -o 'pid=[0-9]*' | cut -d= -f2 | sort -u | \

# For each PID found
while read -r pid; do

    # Get the real path of the binary executed by the process
    bin=$(readlink -f /proc/$pid/exe 2>/dev/null)

    # If the binary does not exist,
    # skip and move to the next PID
    [ -z "$bin" ] && continue

    # Check which Debian package installed this binary
    # dpkg -S searches for the file in the installed package database
    pkg=$(dpkg -S "$bin" 2>/dev/null | head -n1 | cut -d: -f1)

    # Display the process PID
    echo -e "PID: $pid"

    # Display the full path of the binary
    echo -e "BIN: $bin"

    # Check if the binary belongs to an installed package
    if [ -n "$pkg" ]; then

        # If it belongs, display the package name
        echo -e "PACOTE: $pkg"

        # Indicate that the package exists in the system
        echo -e "${GREEN}STATUS: PACOTE EXISTE${RESET}"

    else

        # If no associated package is found
        echo -e "PACOTE: -"

        # May indicate a manually installed binary
        echo -e "${RED}STATUS: NAO ENCONTRADO${RESET}"

    fi

    echo -e "${YELLOW}------------------------${RESET}"

done