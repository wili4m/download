#!/bin/bash

# Script by: wdefreitas@equinix.com
# CVE-2026-46333

CVE="CVE-2026-46333"
ptrace_conf="/etc/sysctl.d/ptrace-restrict.conf"
kernel_parameter="kernel.yama.ptrace_scope"
md5sum_expected="e3d5b924bf9d62140148657c884a4dbb"

echo ">>> Operating System Information:"
echo "Distribution = $(cat /etc/os-release | grep -wE 'NAME' | cut -d= -f2 | sed -e "s/\"//g")"
echo "Version = $(cat /etc/os-release | grep -wE 'VERSION' | cut -d= -f2 | sed -e "s/\"//g")"
echo "Kernel Version = $(uname -r)"
echo "System Uptime = $(uptime | cut -d, -f1)"

function summary() {

    echo
    echo ">>> Mitigation Summary for $CVE:"
    echo "INFO: All mitigations have been applied successfully."
    echo
    echo "Current $kernel_parameter value in memory  : $(sysctl -n $kernel_parameter)"
    echo "Current $kernel_parameter value persistent : $ptrace_conf"
    echo

}

echo
#############################################################
echo ">>> Checking for Vulnerable ptrace_scope Value:"
#############################################################

# Get current ptrace_scope value
ptrace_scope=$(sysctl -n $kernel_parameter)

# If ptrace_scope return value 0, means the system is vulnerable:
case "$ptrace_scope" in
    0|1)
        echo "WARN: Vulnerable $kernel_parameter value detected: $ptrace_scope"

        # Change the ptrace_scope value to 2 in memory to restrict ptrace access immediately:
        echo
        echo ">>> Volatile Mitigation"
        echo "Setting ptrace_scope from $ptrace_scope to 2 to mitigate $CVE immediately..."

        sysctl -w $kernel_parameter=2 > /dev/null 2>&1

        # Verify that the ptrace_scope value was successfully updated in memory:
        if sysctl -n $kernel_parameter | grep -q "2"; then

            echo "OK."
            echo

        else

            echo "CRITICAL ERROR: Failed to update $kernel_parameter value in memory."
            exit 1

        fi

    ;;

    *)
        echo "Non-vulnerable $kernel_parameter value detected in memory: $ptrace_scope"
        ;;

esac

echo
#############################################################
echo ">>> Persistent Mitigation"
#############################################################

files_found=$(grep $kernel_parameter /etc/sysctl.d/* | cut -d: -f1)

# Check if any configuration files were found:
if [ -n "$files_found" ]; then

    # Create a loop to check each file:
    for file in $files_found; do

        # Check if file contain vulnerable ptrace_scope value:
        if grep $kernel_parameter ${file} | grep "0\|1" > /dev/null 2>&1; then

            curr_value=$(grep $kernel_parameter ${file} | grep "0\|1" | awk -F= '{print $2}' | tr -d ' ')

            echo "Found configuration file with vulnerable ${kernel_parameter}. File: ${file}. Value: ${curr_value}."
            echo "Updating $kernel_parameter value to 2 in ${file}..."

            # Change value 0 or 1 to 2:
            sed -i "/$kernel_parameter/s/=.*/= 2/g" $file

            # Check if the value was successfully updated to 2:
            case $? in

                0)
                    echo "OK. File $file updated successfully."
                    ptrace_conf="$(grep $kernel_parameter ${file})"
                    summary
                    ;;
                *)
                    echo "CRITICAL ERROR: Failed to update $kernel_parameter value in ${file}."
                    exit 1
                    ;;
            esac

        else

            echo "File ${file} already contains non-vulnerable $kernel_parameter value: $(cat ${file} | grep $kernel_parameter)"
            ptrace_conf="$(grep $kernel_parameter ${file})"
            summary
        fi

    done

else

    # If no configuration files were found, create a new one to persist the mitigation after reboots:
    echo "Creating $ptrace_conf to persist the mitigation after server reboots..."

    # Write the new ptrace_scope value to the configuration file:
    echo "$kernel_parameter = 2" > $ptrace_conf

    case $? in

        0)
            # Apply the new configuration to ensure the change takes effect immediately:
            sysctl --system > /dev/null 2>&1

            # Check if the ptrace_scope value was successfully updated to 2 after creating the configuration file:
            sysctl -n $kernel_parameter | grep -q "2"

            # Compare the expected ptrace_scope:
            if sysctl -n $kernel_parameter | grep -q "2"; then

                md5sum_received=$(md5sum $ptrace_conf | awk '{print $1}')

                case $md5sum_expected in
                    "$md5sum_received")
                        echo "MD5SUM expected: $md5sum_expected"
                        echo "MD5SUM received: $md5sum_received"
                        ptrace_conf="$(grep $kernel_parameter ${ptrace_conf})"
                        echo "OK"
                        summary
                        ;;
                    *)
                        echo "CRITICAL ERROR: Expected MD5SUM mismatch after creating $ptrace_conf configuration file."
                        exit 1
                        ;;
                esac
            else

                echo "CRITICAL ERROR: Failed to apply $kernel_parameter value change after creating configuration file."
                exit 1

            fi

        ;;

        *)
            echo "CRITICAL ERROR: Failed to create $ptrace_conf configuration file."
            exit 1
            ;;

    esac

fi