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
}

# Memory Information
memory_info() {

    # Following code just for root privileges:
    #ddrs="$(echo -n $(dmidecode -t memory | grep "Size" | grep -v "No Module Installed" | grep GB | awk '{print$2}') | sed -e 's/ / + /g')"
    #memory=$(echo $ddrs | bc)

    # Get util memory reported by Kernel in GB with two decimal places: 
    memory=$(echo "scale=2; $(grep MemTotal /proc/meminfo | awk '{print $2}')/1024/1024" | bc)

}

# Vendor Information
vendor_info() {

    # Check if chassis_vendor returns any hardware manufacturer:
    if [[ $( cat /sys/class/dmi/id/chassis_vendor | grep "No Enclosure") ]]; then

        # If no, it means it's virtual machine:
        vendor=$(cat /sys/class/dmi/id/sys_vendor)

    else

        # If yes, get chassis/hardware vendor:
        vendor=$(cat /sys/class/dmi/id/chassis_vendor)

    fi

}

# Call functions
generic_os_version
cpu_info
memory_info
vendor_info

# Print collected information
echo "${hostname};${os_info};${cpu_model};${cores};${memory};${vendor};"