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

    print $os_info

    if [ -z $os_info ]; then
        echo "OS not identified"
    fi

}

# Checking if it's Debian or Debian Like:
if [ -e $debian_release ]; then

    # Checking if it's a Debian-Like:
    if [ -e "$lsb_release" ]; then

        os_description="$(cat $lsb_release | grep -w ^DISTRIB_DESCRIPTION | sed -e "s/DISTRIB_DESCRIPTION=\"//g" -e "s/\"//g")"

        if [[ ! -z $os_description ]]; then

            report_os_version="$os_description"

        fi

    else
 
        # Checking if it's Ubuntu for the second time:
        os_name=$(cat $os_release | grep -w ^NAME | sed -e "s/NAME=\"//g" -e "s/\"//g")

        if [[ $(echo $os_name | grep -i ubuntu) ]]; then

            generic_os_version

   	 else

            # However, if it's not a Ubuntu, it's a Debian, so we'll collect just the release:
            report_os_version=$(cat $debian_release)

        fi

    fi

else

    # Verifies if it's a CentOS:
    if [ -e $centos_release ]; then

        # Collect the release:
        report_os_version=$(cat $centos_release)

    # Oracle Linux
    elif [ -e $ol_release ]; then

        report_os_version=$(cat $ol_release)

    # RHEL:
    elif [ -e $rhel_release ]; then

        report_os_version=$(cat $rhel_release)

    else

        # But if it's neigther, we'll just collect Name and Version:
        generic_os_version

    fi

fi

# Se o SO nao pode ser identificado, printa saida do comando uname -o
if [[ ! -z $report_os_version ]]; then

    echo $report_os_version

else
        generic_os_version

fi