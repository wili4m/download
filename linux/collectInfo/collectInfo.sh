#!/bin/bash

# Script by wiliamjf@gmail.com
# Description: collect OS informations

# Get server hostname:
hostname=$(hostname -f)

# Identifies OS version:
os_release="/etc/os-release"

# Check Topia/VRX status:
check_topia() {

    # Check if Topia/VRX agent is running:
    topia="$(pgrep topiad)"

    if [[ ! -z $topia ]]; then

        # If running, set VRX status as running:
        vrx_status="VRX_is_running"

    else

        # If not running, set VRX status as not running:
        vrx_status="VRX_not_running"

    fi

}

# Generic Function to get OS version:
generic_os_version() {

    # Get OS name and version from os-release file:
    os_name="$(cat $os_release | grep -w ^NAME | sed -e "s/NAME=\"//g" -e "s/\"//g")"
    os_version="$(cat $os_release | grep -w ^VERSION | sed -e "s/VERSION=\"//g" -e "s/\"//g")"
    os_info="$os_name $os_version"

    # Check if OS info is empty:
    if [[ -z $os_info ]]; then

        os_info="OS not identified"

    fi

}

# Vendor Information:
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

# CPU Information:
cpu_info() {

    cpu_model="$(cat /proc/cpuinfo | grep -m 1 'model name' | sed -e 's/model name[[:space:]]*:[[:space:]]*//g')"
    cores=$(nproc)
}

# Memory Information:
memory_info() {

    # Following code just for root privileges:
    #ddrs="$(echo -n $(dmidecode -t memory | grep "Size" | grep -v "No Module Installed" | grep GB | awk '{print$2}') | sed -e 's/ / + /g')"
    #memory=$(echo $ddrs | bc)
    
    # Get util memory reported by Kernel in GB with two decimal places: 
    memory=$(free -m | grep Mem | awk '{print$2}')
    swap=$(free -m | grep Swap | awk '{print$2}')

}

# Disk Information:
disk_info() {

    # Get disk information using lsblk or df (to be implemented):
    disks="$(echo -n `df -h | grep ^/dev | awk '{print$1}' | while read a; do df -h $a | grep ^/dev | awk '{print$1","$2","$5","$6}'; done`)"
}

# Network Information:
network_info() {

    # Get list of listening TCP ports IPv4:
    if [ -e "/proc/net/tcp" ]; then

       got_v4_ports=$(awk 'NR>1 && $4=="0A" {split($2,a,":"); print strtonum("0x"a[2])}' /proc/net/tcp)
       tcp_v4_ports=$(echo $got_v4_ports | sed -e 's/ /,/g') 

    else

        tcp_v4_ports="none"

    fi

    # Get list of listening TCP ports IPv6:
    if [ -e "/proc/net/tcp6" ]; then

       got_v6_ports=$(awk 'NR>1 && $4=="0A" {split($2,a,":"); print strtonum("0x"a[2])}' /proc/net/tcp6)
       tcp_v6_ports=$(echo $got_v6_ports | sed -e 's/ /,/g')

    else

        tcp_v6_ports="none"

    fi

}

# Call functions:
check_topia
generic_os_version
vendor_info
cpu_info
memory_info
disk_info
network_info

# Print collected information:

echo -e "\nFrom the left, we have the following information:\n
* Hostname;
* VRX Status;
* OS Information;
* Vendor (Hypervisor or Manufactorer)
* CPU Model;
* Number of CPU Cores;
* Memory in MB;
* Ports TCPv4 listening;
* Ports TCPv6 listening.\n"

# Print all information in a single line separated by semicolons (CSV format):
echo "${hostname};${vrx_status};${os_info};${vendor};${cpu_model};${cores};${memory};${disks};tcp_v4:${tcp_v4_ports};tcp_v6:${tcp_v6_ports};"