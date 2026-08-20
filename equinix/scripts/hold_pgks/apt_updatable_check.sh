#!/bin/bash

# Author: gcamposjunior@equinix.com
# Date: 05/2026
# Description:
#   Lists open TCP/UDP ports, identifies processes (PID),
#   resolves the executing binary, and shows which package
#   the binary belongs to.

GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
RESET="\e[0m"

source /etc/os-release

get_package_owner() {
    local binary="$1"
    local pkg

    case "${ID_LIKE:-$ID}" in
        *debian*)
            pkg=$(dpkg -S "$binary" 2>/dev/null | head -n1 | cut -d: -f1)
            ;;
        *rhel*|*fedora*)
            pkg=$(rpm -qf "$binary" 2>/dev/null)

            if [[ "$pkg" == file\ *\ is\ not\ owned\ by\ any\ package ]]; then
                pkg=""
            fi
            ;;
        *)
            pkg=""
            ;;
    esac

    echo "$pkg"
}

ss -tulpn | grep pid= | \
grep -o 'pid=[0-9]*' | cut -d= -f2 | sort -u | \
while read -r pid; do

    bin=$(readlink -f "/proc/$pid/exe" 2>/dev/null)

    [ -z "$bin" ] && continue

    pkg=$(get_package_owner "$bin")

    echo -e "PID: $pid"
    echo -e "BIN: $bin"

    if [ -n "$pkg" ]; then
        echo -e "PACKAGE: $pkg"
        echo -e "${GREEN}STATUS: PACKAGE FOUND${RESET}"
    else
        echo -e "PACKAGE: -"
        echo -e "${RED}STATUS: NOT FOUND${RESET}"
    fi

    echo -e "${YELLOW}------------------------${RESET}"

done