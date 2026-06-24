#!/bin/bash

# Script by: wdefreitas@equinix.com
# CVE-2026-43284
# CVE-2026-43500
# CVE-2026-46300

modules="esp4 esp6 rxrpc espintcp"

cat /etc/os-release | grep -wE 'NAME|VERSION' | cut -d= -f2 | sed -e "s/\"//g" ; uname -r

if lsmod | grep -E "$(echo $modules | sed "s/ /|/g")" > /dev/null 2>&1 ; then

    echo "Vulnerable kernel module(s) detected."

    for module in $modules; do
        if lsmod | grep -q "$module"; then
            echo "- Found module ${module}."
        fi
    done

    exit 1

else

    echo "No vulnerable kernel modules detected."
    exit 0

fi