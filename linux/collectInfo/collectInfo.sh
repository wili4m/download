#!/bin/bash

# Script by wiliamjf@gmail.com
# Description: collect OS informations

generic_os_version() {

    os_name=$(cat /etc/os-release | grep -w ^NAME | sed -e "s/NAME=\"//g" -e "s/\"//g")
    os_version=$(cat /etc/os-release | grep -w ^VERSION | sed -e "s/VERSION=\"//g" -e "s/\"//g")
    os_release="$os_name $os_version"

}

# Identifies OS version:
debian_release="/etc/debian_version"
centos_release="/etc/centos-release"
ol_release="/etc/oracle-release"
rhel_release="/etc/redhat-release"

# Checking if it's Debian or Debian Like:
if [ -e $debian_release ]; then

    # Checking if it's a Debian-Like:
    if [ -e /etc/lsb-release ]; then

        os_description=$(cat /etc/lsb-release | grep -w ^DISTRIB_DESCRIPTION | sed -e "s/DISTRIB_DESCRIPTION=\"//g" -e "s/\"//g")

        if [ ! -z $os_description ]; then

            os_release="$os_description"

        fi

    else
 
        # Checking if it's Ubuntu for the second time:
        os_name=$(cat /etc/os-release | grep -w ^NAME | sed -e "s/NAME=\"//g" -e "s/\"//g")

        if [[ $(echo $os_name | grep -i ubuntu)]]; then

            generic_os_version()

    else

        # However, if it's not a Ubuntu, it's a Debian, so we'll collect just the release:
        os_release=$(cat $debian_release)

    fi

else

    # Verifies if it's a CentOS:
    if [ -e $centos_release ]; then

        # Collect the release:
        os_release=$(cat $centos_release)

    # Oracle Linux
    elif [ -e $ol_release ]; then

        os_release=$(cat $ol_release)

    # RHEL:
    elif [ -e $rhel_release ]; then

        os_release=$(cat $rhel_release)

    else

        # But if it's neigther, we'll just collect Name and Version:
        generic_os_version()

    fi

fi

# Se o SO nao pode ser identificado, printa saida do comando uname -o
if [ ! -z $os_release ]; then

    echo $os_release

else

    echo "Null"

fi