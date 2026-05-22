#!/bin/bash

# Author: Wiliam de Freitas <wdefreitas@equinix.com>
# Date: Feb 2026

################################################################################
# Description
################################################################################
#   eqx-secpatcher automates the installation of security updates on Linux servers
#   (Debian, Ubuntu, CentOS, Oracle Linux, and Rocky Linux). The script detects
#   available security patches, applies them, and generates CSV evidence reports
#   showing package versions before and after the update process.

################################################################################
# Features
################################################################################
#   - Package hold list:
#       Packages listed in /etc/default/secpatcher/pkgs_hold/ are excluded from updates.
#   - Pre-update CSV:
#       Snapshot of all available security updates before execution.
#   - Post-update CSV:
#       Evidence report showing the previous and updated versions of patched packages.
#   - Kernel detection:
#       Automatically detects if a new kernel was installed during the update process.

################################################################################
# Modals
################################################################################
#   - modal_reboot_after_update:
#       If enabled, automatically reboots the server when a new kernel is installed.
#       If disabled, only prints a recommendation for manual reboot.
#   - modal_keep_temporary_files:
#       If enabled, keeps temporary files generated during execution.
#       If disabled, removes them after the script finishes.


#
# Variables:
# 

# Just the tool name for log purposes:
tool_name="vulkiller"

# The tool version:
tool_version="1.1"

# Determine the current OS by reading the /etc/os-release file and extracting the ID field:
current_os="$(cat /etc/os-release | grep -i -w ID | awk -F= '{print$2}' | sed -e 's/"//g')"

# Keep or remove temporary files created during script execution.
modal_keep_temporary_files=true

# Determine if the server will be rebooted after Kernel update.
modal_reboot_after_update=false

# Define a path to store temporary files and the evidences
files_path="/root"

# Directory where empty files named after packages are stored to prevent them from being updated
path_to_pkgs_hold="/etc/default/equinix/pkgs_hold"

# Just a separator to make the log more readable:
bar="##########"

# Tool log path:
tool_log_path="/var/log/${tool_name}"

# Tool log file:
tool_log_file="${tool_log_path}/${tool_name}.log"

# Define date in format YYYY-MM-DD to be used in file names and logs:
date="$(date +%Y-%m-%d)"

# Define hostname with the format that can be used in file names (replace - and . with _):
hostname="$(hostname -f | sed -e "s/-/_/g" -e "s/\./_/g")"

# File for storing the list of available security updates. This is an evidence:
file_updates_available="${files_path}/${hostname}_${date}_security_updates_available.csv"

# Define file for storing the evidence of the update process (packages that were updated with their old and new versions):
file_updates_performed="${files_path}/${hostname}_${date}_security_updates_performed.csv"

# Only for RHEL and RHEL-Like. Temporary files for storing packages version before and after the update process:
file_pre_update="${files_path}/${hostname}_${date}_packages_pre_update.txt"
file_post_update="${files_path}/${hostname}_${date}_packages_post_update.txt"

#
# Functions:
#

# Logs messages to file and stdout.
# stdout output is required for VRX collection, used for inventory purposes.
func_log() {

# Verifies if the directory exists:
if [ ! -d $tool_log_path ]; then

    # If not, create and configure it:
    mkdir -p $tool_log_path
    touch $tool_log_file
    chmod 644 $tool_log_file

fi

# Verifies if the log file exists: 
if [ -e $tool_log_file ]; then

    # If yes, spected to receive 2 arguments: $1 and $2
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S (%Z)')
    
    # Logging:
    echo "${timestamp} [${level}] ${message}" >> "${tool_log_file}"
    
    # Output:
    echo "[${level}] $message" 

fi

}

# Function to validate pre-update conditions:
func_validation_pre_update() {

    # Check if the script is run as root:
    if [ "$EUID" -ne 0 ]; then

        echo "ERROR: This script must be run as root. Please use sudo or switch to the root user."
        exit 1

    fi

}

func_pkgs_to_avoid_update() {

    # Collect list of packages to avoid updateing (hold):
    if [ -d "$path_to_pkgs_hold" ]; then

    # Just a message to separate the update process in the log:
    log_level="INFO"
    log_msg="Verifying if there are packages to be held to avoid updates..."
    func_log "$log_level" "$log_msg" 
    echo ""
    
    # Just a message to separate the update process in the log:
    echo "${bar} Check core services to avoid updates ${bar}" 

    # List of packages to be held to avoid updating (hold).
    excludes="$(find /etc/default/equinix/pkgs_hold/ -maxdepth 1 -type f -printf '%f ' | sed 's/,$//')"

        # Check if the variable with the list of packages to be held is not empty:
        if [ -n "$excludes" ]; then

            # Printing the list of packages to be held:
            log_level="INFO"
            log_msg="Found packages to avoid updates: $excludes"
            func_log "$log_level" "$log_msg" 

            # Loop through each package in the list of packages to be held and check if it has a security update available:
            for pkg in $excludes ; do

                # Check if the package is in the list of available security updates:
                if grep -iw "$pkg" $file_updates_available > /dev/null ; then

                    case $current_os in

                        # Debian and Debian-like:
                        debian|ubuntu)
                            log_level=WARM
                            log_msg="Package $pkg has a security update available but will be held to avoid updating."
                            func_log "$log_level" "$log_msg" ;
                            packages_to_hold="${packages_to_hold} ${pkg}" ;
                            apt-mark hold $pkg 2> /dev/null ;;

                        # RHEL and RHEL-like:
                        rhel|centos|oracle|rocky)
                            log_level=WARM
                            log_msg="Package $pkg has a security update available but will be excluded from update."
                            func_log "$log_level" "$log_msg" ;
                            packages_to_hold="${packages_to_hold},${pkg}" ;;

                        # Unsupported OS:
                        *)  log_level=ERROR
                            log_msg="Unsupported OS for package hold. Please check the script."
                            func_log "$log_level" "$log_msg" ; exit 1 ;;
                    
                    esac

                else

                    # If the package is not in the list of available security updates, print a message indicating that it will not be held:
                    log_level=INFO
                    log_msg="Package $pkg does not have a security update available and will not be held."
                    func_log "$log_level" "$log_msg"

                fi

            done

        else

            # Just a message to separate the update process in the log:
            log_level=INFO
            log_msg="No packages marked to be held. All security updates will be applied."
            func_log "$log_level" "$log_msg"
            echo ""

        fi

    fi

    echo ""

}

func_perform_update() {

    # Perform the update only in packages with security fixes, excluding the ones in the hold list:
    log_level=INFO
    log_msg="Performing security update..."
    func_log "$log_level" "$log_msg"
    echo ""

    # Just a message to separate the update process in the log:
    echo "${bar} Update process ${bar}"

    if [ -n "$packages_to_hold" ]; then

        case $current_os in

            debian|ubuntu)
                export DEBIAN_FRONTEND=noninteractive
                apt install -y \
                -o Dpkg::Options::="--force-confdef" \
                -o Dpkg::Options::="--force-confold" \
                $(apt list --upgradable 2>/dev/null | grep -i sec | cut -d/ -f1 | grep ^[a-z] | grep -vFf <(ls $path_to_pkgs_hold) | tr '\n' ' ') ;

                case $? in
                    0) update_status="Success" ;;
                    *) update_status="Failed" ;;
                esac

                # Unmark the packages that were held:
                if [ -n "$packages_to_hold" ]; then

                    # Just a message to separate the update process in the log:
                    echo "${bar} Unhold packages ${bar}"

                    # Unmark the packages that were held to avoid updating, so they can receive updates in the future when they have security updates available:
                    apt-mark unhold $packages_to_hold 2> /dev/null

                fi
                ;;

            rhel|centos|oracle|rocky)
                yum update --security -y --exclude=$packages_to_hold > /dev/null 2>&1 ;
                
                case $? in
                    0) update_status="Success" ;;
                    *) update_status="Failed" ;;
                esac
                ;;

        esac

    else

        case $current_os in

            debian|ubuntu)
                export DEBIAN_FRONTEND=noninteractive
                apt install -y \
                -o Dpkg::Options::="--force-confdef" \
                -o Dpkg::Options::="--force-confold" \
                $(apt list --upgradable 2>/dev/null | grep -i sec | cut -d/ -f1 | grep ^[a-z]) ;
                echo ""

                case $? in
                    0) update_status="Success" ;;
                    *) update_status="Failed" ;;
                esac
                
                # Unmark the packages that were held:
                if [ -n "$packages_to_hold" ]; then

                    # Just a message to separate the update process in the log:
                    echo "${bar} Unhold packages ${bar}"

                    # Unmark the packages that were held to avoid updating, so they can receive updates in the future when they have security updates available:
                    apt-mark unhold $packages_to_hold 2> /dev/null
                    echo ""

                fi
                ;;

            rhel|centos|oracle|rocky)
                yum update --security -y ;
            
                case $? in
                    0) update_status="Success" ;;
                    *) update_status="Failed" ;;
                esac
                ;;

        esac

    fi

    echo ""

    case $update_status in

        # If the update process was successful, print a message indicating that the security update was completed successfully:
        Success)
            log_level=INFO
            log_msg="Security update process completed successfully."
            func_log "$log_level" "$log_msg" ;
            exit 0;;
        
        # If the update process failed, print an error message and exit:
        Failed) 
            log_level=ERROR
            log_msg="Security update process failed. Please check the logs for more details."
            func_log "$log_level" "$log_msg" ; 
            exit 1 ;;

        # This case should never happen, but it's here just in case to catch any unexpected error during the update process:
        *)
            log_level=ERROR
            log_msg="Unexpected error during the update process. Please check the logs for more details."
            func_log "$log_level" "$log_msg" ; 
            exit 1 ;;
    esac
    
}

func_print_evidence() {

    # Collect a list of packages that were updated:
    case $current_os in

        debian|ubuntu)
            echo "Package Name ; Old version ; New version" > $file_updates_performed ;
            grep $date /var/log/apt/history.log -A4 | grep Upgrade | sed -e "s/Upgrade: //g" -e "s/),/)|/g" | \ 
            xargs -d'|' -n1 | sed -e "/^$/d" | awk '{print$1 " ; "$2" ; "$3}' | sed -e "s/(//g" -e "s/)//g" -e "s/,//g" >> $file_updates_performed ;;
    
        rhel|centos|oracle|rocky)
            # Collect the list of packages with security updates available before the update process:
            grep $date /var/log/dnf.rpm.log | grep -w Upgraded | awk -F "Upgraded:" '{print$2}' | sort | sed -e "s/ //g" > $file_pre_update ;

            # Collect the list of packages that were updated after the update process:
            grep $date /var/log/dnf.rpm.log | grep -w Upgrade | awk -F "Upgrade:" '{print$2}' | sort | sed -e "s/ //g" > $file_post_update ;

            # Create a CSV file with the list of packages that were updated, with their old and new versions:
            echo "Old version ; New version" > $file_updates_performed ;
            paste -d ';' $file_pre_update $file_post_update >> $file_updates_performed ;;

    esac

    if [ -z $file_updates_performed ]; then

        log_level=INFO
        log_msg="No security updates were applied on this system."
        func_log "$log_level" "$log_msg"
        echo ""
        exit 0

    else
    
        # Print packages with security updates available:
        echo ""
        echo "${bar} Here is the CSV file with all the security updates available before the update process: ${bar}"
        echo ""
        cat $file_updates_available
        echo ""

        # Print the evidence of the update process:
        echo "${bar} Here is the CSV file with all the evidence of the update process: ${bar}"
        echo ""
        cat $file_updates_performed
        echo ""

    fi

}

func_reboot_server() {

    # Get the default kernel in GRUB.
    grub_default_kernel=$(grep -E "^GRUB_DEFAULT=" /etc/default/grub | cut -d= -f2 | tr -d '"')

    # Check if the default kernel in GRUB is set to 0, which means the first entry in the GRUB menu.
    if [ "$grub_default_kernel" == "0" ]; then

        # Get the currently running kernel version
        current_running_kernel="$(uname -r)"

        # Get the default kernel version from GRUB.
        current_default_kernel=$(grep menuentry /boot/grub/grub.cfg  | grep -v recovery | grep with | awk '{print$6}' | sed -e "s/'//g" | head -n1)

        # Check if the currently running kernel is different from the default kernel in GRUB, which means that a new kernel was
        # installed and the server needs to be rebooted to apply the new kernel and all security fixes:
        if [ "$current_running_kernel" != "$current_default_kernel" ]; then

            # Check if the modal to reboot the server after the update process is set to true or false:
            if [ "$modal_reboot_after_update" = true ]; then

                # Print a message indicating that the server will be rebooted to apply the new kernel and all security fixes:
                echo "$bar Checking Kernel Version $bar"
                log_level=INFO
                log_msg="Kernel default differs from running kernel. Reboot scheduled to apply new kernel and security fixes."
                func_log "$log_level" "$log_msg"
                echo ""

                # Reboot the server immediately:
                shutdown -rf +30 "Rebooting to apply new kernel and security fixes. Please save your work and log out."

            else

                echo "$bar Checking Kernel Version $bar"
                log_level=INFO
                log_msg="Kernel default differs from running kernel. Auto-reboot is disabled, but manual reboot is highly recommended to apply the new kernel and security fixes."
                func_log "$log_level" "$log_msg"
                echo ""

            fi

        fi

    fi

}

func_cleanup() {

    if [ "$modal_keep_temporary_files" = true ]; then
        
        log_level=INFO
        log_msg="The temporary files created during this update are being kept due to $tool_name configuration."
        func_log "$log_level" "$log_msg"

        if [ -f $file_updates_available ] ; then
            log_level=INFO
            log_msg="File with the list of available security updates: $file_updates_available"
            func_log "$log_level" "$log_msg"
        fi
        
        if [ -f $file_updates_performed ] ; then
            log_level=INFO
            log_msg="File with the evidence of packages that were updated with their old and new versions: $file_updates_performed"
            func_log "$log_level" "$log_msg"            
        fi

        if [ -f $file_pre_update ] ; then
            log_level=INFO
            log_msg="Only for RHEL and RHEL-like. Temporary file for storing packages version before the update: $file_pre_update"
            func_log "$log_level" "$log_msg"
        fi

        if [ -f $file_post_update ] ; then
            log_level=INFO
            log_msg="Only for RHEL and RHEL-like. Temporary file for storing packages version after the update: $file_post_update"
            func_log "$log_level" "$log_msg"
        fi

        echo ""

    else 

        # Remove temporary files:
        if [ -f $file_updates_available ] ; then
            rm -f $file_updates_available
        fi

        if [ -f $file_pre_update ] ; then
            rm -f $file_pre_update
        fi

        if [ -f $file_post_update ] ; then
            rm -f $file_post_update
        fi
        
        if [ -f $file_updates_performed ] ; then
            rm -f $file_updates_performed
        fi

    fi

}

#
# The Script starts here:
#

# First, lets verify if the system meets the pre-update conditions:
func_validation_pre_update

# The following information are printed to show on VRX logs of processes
log_level=INFO
log_msg="Starting security update for server: ${hostname}"
func_log "$log_level" "$log_msg"

# Printing and Logging Tool Informations:
echo ""
echo "${bar} Tool Information ${bar}"
log_level=INFO
log_msg="Tool Name: ${tool_name}"
func_log "$log_level" "$log_msg"

log_level=INFO
log_msg="Tool Version: ${tool_version}"
func_log "$log_level" "$log_msg"
echo ""

# Displaying OS Informations:
echo "$bar Current System Information $bar"

log_level=INFO
log_msg="Current OS: ${current_os}"
func_log "$log_level" "$log_msg"

log_level=INFO
log_msg="Current Date: ${date}"
func_log "$log_level" "$log_msg"

# Start Time variable will be displayed in the end of the process:
start_time=$(date +%T)

case $current_os in

    # Debian and Debian-like:
    debian|ubuntu)

        # Update APT cache:
        log_level=INFO
        log_msg="Updating APT Cache..."
        func_log "$log_level" "$log_msg"

        apt update -qq > /dev/null 2>&1

        case $? in
            0)
            log_level=INFO
            log_msg="APT cache updated successfully."
            func_log "$log_level" "$log_msg" ;
            echo "" ;;

            *) echo "" ;
            log_level=ERROR
            log_msg="Failed to update APT cache. Please check your network connection and try again."
            func_log "$log_level" "$log_msg" ; exit 1 ;;
        esac

        # Collect the list of available security updates and save it to a file:
        echo "Package;Current Version;Available Version" > $file_updates_available
        apt list --upgradable 2> /dev/null | grep -i sec | grep -iv listing | awk '{print$1" ; "$6" ; "$2}' | sed -e "s/]//g" >> $file_updates_available ;;


    # RHEL and RHEL-like:
    rhel)
        # Verify if the system is registered with Red Hat Subscription Manager:
        if subscription-manager identity 2>&1 | grep -i "system is not yet registered" > /dev/null ; then

            # If the system is not registered, print an error message and exit:
            log_level=ERROR
            log_msg="This RHEL system is not registered with Red Hat Subscription Manager. Please register the system to access security updates."
            func_log "$log_level" "$log_msg"
            exit 1

        fi

        # Create a CSV file with the list of available security updates:
        echo "Advisory (Errata);Type;Package" > $file_updates_available
        yum updateinfo --list --security | grep ^R | sed -e "/^RH/s/ /;/g" -e "s/;;/;/g" >> $file_updates_available
        
        ;;

    centos|oracle|rocky)
        # Create a CSV file with the list of available security updates:
        echo "Advisory (Errata);Type;Package" > $file_updates_available
        yum updateinfo --list --security | grep ^R | sed -e "/^RH/s/ /;/g" -e "s/;;/;/g" >> $file_updates_available ;
        ;;

    # Unsupported OS:
    *)  log_level=ERROR
        log_msg="Unsupported OS. This script supports only Debian/Ubuntu and RHEL/CentOS/Oracle Linux/Rocky Linux distributions."
        func_log "$log_level" "$log_msg" ; exit 1 ;;

esac

echo ""
echo "$bar Checking for security updates $bar"

log_level=INFO
log_msg="Checking for available security updates."
func_log "$log_level" "$log_msg"

# Check if there are any security updates available by counting the number of lines in the file (excluding the header):
if wc -l $file_updates_available | grep -w ^"1" > /dev/null ; then

    # Display a message indicating that no security updates are available and exit:
    log_level=INFO
    log_msg="No security updates are available for this system."
    func_log "$log_level" "$log_msg"

    # If the modal to keep temporary files is set to true, change to false to allow the cleanup:
    if [ $modal_keep_temporary_files = true ] ; then

        # Change the variable to false to allow the cleanup of temporary files:
        modal_keep_temporary_files=false

    fi

    func_cleanup
    echo ""
    exit 0

else

    # Call function to collect list of packages to check if the package have security updates available:
    func_pkgs_to_avoid_update

    # Perform the update only in packages with security fixes, excluding the ones in the hold list:
    func_perform_update
    
    # Print the evidence of the update process:
    func_print_evidence

    # Cleanup temporary files:
    func_cleanup

    # Check if the server needs to be rebooted to apply the new kernel and all security fixes, and reboot if necessary:
    func_reboot_server

    echo ""
    echo "$bar Finished ${bar}"
    log_level=INFO
    log_msg="Update Status: Completed."
    func_log "$log_level" "# $log_msg"
    
    log_level=INFO
    log_msg="Started: ${start_time} (`date +%Z`)"
    func_log "$log_level" "# $log_msg"

    log_level=INFO
    log_msg="Finished: $(date +%T) (`date +%Z`)"
    func_log "$log_level" "# $log_msg"

    log_level=INFO
    log_msg="Packages Updated: $(wc -l $file_updates_performed | awk '{print$1-2}')"
    func_log "$log_level" "# $log_msg"
    echo ""
    
fi