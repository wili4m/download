#!/bin/bash

# Script by wiliamjf@gmail.com
# Description: collect OS informations

# Get server hostname:
hostname=$(hostname -f)

# Identifies OS version:
os_release="/etc/os-release"

# Generic Function to get OS version
generic_os_version() {

    os_name="$(cat $os_release | grep -w ^NAME | sed -e "s/NAME=\"//g" -e "s/\"//g")"
    os_version="$(cat $os_release | grep -w ^VERSION | sed -e "s/VERSION=\"//g" -e "s/\"//g")"
    os_info="$os_name $os_version"

    # Check if OS info is empty
    if [[ -z $os_info ]]; then

        os_info="OS not identified"

    fi

}

# CPU Information
cpu_info() {

    cpu_model="$(cat /proc/cpuinfo | grep -m 1 'model name' | sed -e 's/model name[[:space:]]*:[[:space:]]*//g')"
    cores=$(nproc)
    memory_info=$(free -h | grep Mem | awk '{print $2}')
}

# Memory Information
memory_info() {

    ddrs="$(echo -n $(dmidecode -t memory | grep "Size" | grep -v "No Module Installed" | grep GB | awk '{print$2}') | sed -e 's/ / + /g')"
    memory=$(echo $ddrs | bc)

}

vendor_info() {

    if [[ $( cat /sys/class/dmi/id/chassis_vendor | grep "No Enclosure") ]]; then

        vendor=$(cat /sys/class/dmi/id/sys_vendor)

    else

        vendor=$(cat /sys/class/dmi/id/chassis_vendor)

    fi

}

# Call functions
generic_os_version
cpu_info
memory_info
vendor_info

# Print collected information
echo "${hostname} ; ${os_info} ; ${cpu_model}; ${cores}; ${memory}; ${vendor};"