#!/bin/bash

# Script by: wdefreitas@equinix.com
# CVE-2026-43284
# CVE-2026-43500
# CVE-2026-46300

modules="esp4 esp6 rxrpc espintcp"
md5sum="3c52e2c0096c89c8170cc39f6c303e17"
separator="$(seq -s~ 1 50 | tr -d '[:digit:]')"

function main() {

    echo
    echo ">>> Checking and Disabling Vulnerable Kernel Modules:"
    echo

    # Check if any of the vulnerable kernel modules are currently loaded
    if lsmod | grep -E "$(echo $modules | sed "s/ /|/g")" > /dev/null 2>&1 ; then

        # List the vulnerable modules that are currently loaded
        for module in $modules; do

            if lsmod | grep -q "$module"; then

                echo "WARN = Module ${module} found loaded. Attempting to remove it..."

                # Attempt to remove the vulnerable module and report the result
                if rmmod $module > /dev/null 2>&1; then

                    run_drop_caches=true
                    echo "INFO = Module ${module} removed."

                else

                    echo "ERROR = Failed to remove module ${module}. Please check permissions and try again."
                    exit 1

                fi

            else

                echo "OK = Module ${module} not found in loaded modules."

            fi

        done

        if [ "$run_drop_caches" = true ]; then

            echo
            echo ">>> Dropping Caches to Ensure Modules are Unloaded:"
            echo

            sync
            nice -19 echo 3 > /proc/sys/vm/drop_caches

            case $? in

                0)
                    echo "INFO = Caches dropped successfully."
                    ;;
                *)
                    echo "ERROR = Error dropping caches."
                    exit 1
                    ;;
            esac
            echo

        fi

    else

        for module in $modules; do

            echo "- Module ${module} not loaded."

        done

    fi

}

function block_modules() {

    echo ">>> Checking and Blocking Vulnerable Kernel Modules:"
    echo
    # Create a blacklist file to prevent the vulnerable modules from loading
    blacklist="/etc/modprobe.d/dirty-frag-mitigation.conf"
    echo "install esp4 /bin/false" > "$blacklist"
    echo "install esp6 /bin/false" >> "$blacklist"
    echo "install rxrpc /bin/false" >> "$blacklist"
    echo "install espintcp /bin/false" >> "$blacklist"

    # Verify that the blacklist file was created successfully and contains the correct entries
    case "$?" in
        0)
            echo "INFO = Module blacklist created successfully."
            ;;
        *)
            echo "CRITICAL ERROR = Error creating blacklist file."
            exit 1
            ;;
    esac

    # Calculate the checksum of the blacklist file to verify its integrity
    checksum=$(md5sum "$blacklist" | awk '{print $1}')

    case "$checksum" in
        "$md5sum")
            echo -e "\nMD5SUM Expected: $md5sum"
            echo "MD5SUM Received: $checksum"
            exit 0
            ;;
        *)
            echo "CRITICAL ERROR = Error creating blacklist file: Expected MD5SUM mismatch."
            exit 1
            ;;
    esac

}

# Display the operating system information and kernel version

echo
echo ">>> Operating System Information:"
echo
echo "- Distribution = $(cat /etc/os-release | grep -wE 'NAME' | cut -d= -f2 | sed -e "s/\"//g")"
echo "- Version = $(cat /etc/os-release | grep -wE 'VERSION' | cut -d= -f2 | sed -e "s/\"//g")"
echo "- Kernel Version = $(uname -r)"
echo "- System Uptime = $(uptime | cut -d, -f1)"

block_modules
main
