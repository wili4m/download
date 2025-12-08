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

    # Check if OS info is empty
    if [ -z $os_info ]; then

        echo "OS not identified"
    
    fi

}

# Checking if it's Debian or Debian Like:
if [ -e $debian_release ]; then

    # Check if it's a Debian-Like system
    if [ -e "$lsb_release" ]; then

        os_description="$(cat $lsb_release | grep -w ^DISTRIB_DESCRIPTION | sed -e "s/DISTRIB_DESCRIPTION=\"//g" -e "s/\"//g")"

        # Check if OS description is not empty
        if [[ ! -z $os_description ]]; then

            report_os_version="$os_description"

        fi

        else
 
        # Check if it's Ubuntu for the second time
        os_name=$(cat $os_release | grep -w ^NAME | sed -e "s/NAME=\"//g" -e "s/\"//g")

        # Check if the OS name contains Ubuntu
        if [[ $(echo $os_name | grep -i ubuntu) ]]; then            generic_os_version

        # If it's not Ubuntu, it's a Debian distribution
   	 else

            # Collect just the Debian release information
            report_os_version=$(cat $debian_release)

        fi

    fi

else

    # Check if it's a CentOS system
    if [ -e $centos_release ]; then

        # Collect the CentOS release information
        report_os_version=$(cat $centos_release)

    # Check if it's an Oracle Linux system
    elif [ -e $ol_release ]; then

        report_os_version=$(cat $ol_release)

    # Check if it's a Red Hat Enterprise Linux system
    elif [ -e $rhel_release ]; then

        report_os_version=$(cat $rhel_release)

    # If none of the above OS types were detected
    else

        # Collect generic OS Name and Version information
        generic_os_version

    fi

fi

# Check if OS version information was successfully collected
if [[ ! -z $report_os_version ]]; then

    echo $report_os_version

# If OS information was not collected, use generic method
else
        generic_os_version

fi