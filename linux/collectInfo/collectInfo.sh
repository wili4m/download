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
    
    # Get util memory reported by Kernel in GB with two decimal places: 
    memory=$(free -m | grep Mem | awk '{print$2}')
    swap=$(free -m | grep Swap | awk '{print$2}')

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

disk_info() {

    # Get disk information using lsblk or df (to be implemented)
    disks="$(echo -n `df -h | grep ^/dev | awk '{print$1}' | while read a; do df -h $a | grep ^/dev | awk '{print$1","$2","$5","$6}'; done`)"
}

network_info() {
    # Get list of listening TCP ports (IPv4 and IPv6):

    # Using netstat:
    if [ -e "/usr/bin/netstat" ]; then

        got_v4_ports=$(netstat -tuln4 | grep tcp | awk '{print$4}' | cut -d: -f2)
        got_v6_ports=$(echo -n `netstat -tuln6 | grep tcp | awk '{print$4}' | cut -d: -f2)

    # Using ss:
    elif [ -e "/usr/bin/ss" ]; then

        got_v4_ports=$(ss -tuln4p | grep tcp | awk '{print$5}' | cut -d: -f2)
        got_v6_ports=$(ss -tuln6 | grep tcp | awk '{print$4}' | cut -d: -f2)

    # Using /proc/net/tcp and /proc/net/tcp6:
    else

       got_v4_ports=$(awk 'NR>1 && $4=="0A" {split($2,a,":"); print strtonum("0x"a[2])}' /proc/net/tcp)
       got_v6_ports=$(awk 'NR>1 && $4=="0A" {split($2,a,":"); print strtonum("0x"a[2])}' /proc/net/tcp6)

    fi

    # Convert space-separated ports into comma-separated:
    tcp_v4_ports=$(echo $got_v4_ports | sed -e 's/ /,/g') 
    tcp_v6_ports=$(echo $got_v4_ports | sed -e 's/ /,/g') 

}

# Call functions
generic_os_version
vendor_info
cpu_info
memory_info
disk_info
network_info

# Print collected information

echo -e "\nFrom the left, we have the following information:\n
* Hostname;
* OS Information;
* CPU Model;
* Number of CPU Cores;
* Memory in MB;
* Vendor (Hypervisor or Manufactorer).\n"

echo "${hostname};${os_info};${cpu_model};${cores};${memory};${disks};${tcp_v4_ports};${tcp_v6_ports}${vendor};"