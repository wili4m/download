#!/bin/bash

# Description: This script checks if SSSD or NSLCD is running and retrieves AD server info.
# Script by: Wiliam de Freitas <wdefreitas@equinix.com>
# Date: Jan 2026

# Flags to indicate if SSSD or NSLCD are enabled
sssd_is_enabled=0
nslcd_is_enabled=0

# Function to display AD server information
function print_ad_info() {

    echo -e $hello_message
    echo "AD Server: $ad_server"

}

# Function to retrieve and display AD domain information
function func_domain() {

    # Check if SSSD is enabled
    if [ $sssd_is_enabled -eq 1 ]; then

        hello_message="SSSD is running"
        # Extract AD server from SSSD configuration file
        ad_server=$(grep ad_server /etc/sssd/sssd.conf  | awk -F= '{print$2}' | sed -e 's/ //g')
        print_ad_info

    fi

    # Check if NSLCD is enabled
    if [ $nslcd_is_enabled -eq 1 ]; then

        hello_message="NSLCD is running"
        # Extract AD server from NSLCD configuration file
        ad_server=$(grep ^uri /etc/nslcd.conf | awk '{print $2}' | sed 's#.*://##')
        print_ad_info

    fi

}

# Check SSSD service status
if systemctl is-active --quiet sssd; then

    sssd_is_enabled=1
    func_domain

# If SSSD is not active, check NSLCD service status
elif systemctl is-active --quiet nslcd; then

    nslcd_is_enabled=1
    func_domain

# If no LDAP service is active, display error message
else

    echo "No LDAP connection here"

fi