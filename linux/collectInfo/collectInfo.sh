#!/bin/bash

# Script by wiliamjf@gmail.com
# Description: collect OS informations

# Identifies OS version:
debian_release="/etc/debian_version"
centos_release="/etc/centos-release"
rhel_release="/etc/redhat-release"
ol_release="/etc/oracle-release"
lsb_release="/etc/lsb-release"
os_release="/etc/os-release"

generic_os_version() {

    os_name="$(cat $os_release | grep -w ^NAME | sed -e "s/NAME=\"//g" -e "s/\"//g")"
    os_version="$(cat $os_release | grep -w ^VERSION | sed -e "s/VERSION=\"//g" -e "s/\"//g")"
    os_info="$os_name $os_version"

    # Check if OS info is empty
    if [[ -z $os_info ]]; then

        os_info="OS not identified"

    fi

}

cpu_model() {

    cpu_info="$(cat /proc/cpuinfo | grep -m 1 'model name' | sed -e 's/model name[[:space:]]*:[[:space:]]*//g')"

}

generic_os_version
cpu_model

echo "${os_info} ; ${cpu_info}"