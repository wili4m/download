#!/bin/bash

# Author: Wiliam de Freitas <wdefreitas@equinix.com>
# Date: Feb 2026
# Description: vulKiller (aka vk) automates the installation of security updates
# on Linux servers (Debian, Ubuntu, CentOS, Oracle Linux, and Rocky Linux). The
# script detects available security patches, applies them, and generates CSV
# evidence reports showing package versions before and after the update process.

################################################################################
# Identification Variables
################################################################################

# Just the tool name for log purposes:
tool_name="vulkiller"

# The tool version:
tool_version="1.0.1"

# Determine the current OS:
current_os="$(cat /etc/os-release | grep -w ID | awk -F= '{print$2}' | sed -e 's/"//g')"

# Determine the current OS version:
version_os="$(cat /etc/os-release | grep -w VERSION_ID | awk -F= '{print$2}' | sed -e 's/"//g')"

################################################################################
# Modals Variables
################################################################################

# modal_reboot_after_update: true or false.
# If true, automatically reboots the server when a new kernel is installed.
# If false, only prints a recommendation for manual reboot.
modal_keep_temporary_files="true"

# modal_keep_temporary_files: true or false.
# If true, keeps temporary files generated during execution.
# If false, removes them after the script finishes.
modal_reboot_after_update="false"

# modal_update_all_packages: true or false.
# If true, updates all available packages, except those marked as "hold".
# If false, updates only packages with security fixes available.
modal_update_all_packages="true"

################################################################################
# Configuration Variables
################################################################################

# Directory where empty files named after packages are stored to prevent them from being updated
path_to_pkgs_hold="/etc/default/equinix/pkgs_hold"

# If the modal to reboot is enabled and a new kernel is installed, the variable will be set to 1.
reboot_needed=0

################################################################################
# Log and Reports Variables
################################################################################

# Define date in format YYYY-MM-DD to be used inside log registers:
date="$(date +%Y-%m-%d)"

# Current Year:
date_year=$(date +%Y)

# Current Month:
date_month=$(date +%m)

# Current Day:
date_day=$(date +%d)

# Define date in format YYYY_MM_DD to be used in file names::
date_name_files="${date_year}_${date_month}_${date_day}"

# Timestamp to be used as trace ID in logs:
traceid="$(date +%s)"

# Tool log path:
tool_log_path="/var/log/${tool_name}"

# Tool log file:
tool_log_file="${tool_log_path}/${tool_name}.log"

# Define a path to store temporary files and the evidences
reports_path="${tool_log_path}/reports/${date_year}/${date_month}/${date_day}"

# Server uptime:
server_uptime=$(printf "%02d" $(awk '{print int($1/86400)}' /proc/uptime))

case $server_uptime in
    00|01) uptime_desc="Day" ;;
    *) uptime_desc="Days" ;;
esac

uptime="$server_uptime $uptime_desc"

# Just a separator to make the log more readable:
bar="##########"

# Log levels:
INFO="INFO"
WARN="WARN"
ERROR="ERROR"

################################################################################
# Report Variables
################################################################################

# Define hostname with the format that can be used in file names (replace - and . with _):
hostname="$(hostname -f | sed -e "s/-/_/g" -e "s/\./_/g")"

# File for storing the list of available security updates. This is an evidence:
file_updates_available="${reports_path}/${date_name_files}_${traceid}_${hostname}_updates_available.csv"

# Define file for storing the evidence of the update process (packages that were updated with their old and new versions):
file_updates_performed="${reports_path}/${date_name_files}_${traceid}_${hostname}_updates_performed.csv"

# Only for RHEL and RHEL-Like. Temporary files for storing packages version before and after the update process:
file_pre_update="${reports_path}/${date_name_files}_${traceid}_${hostname}_packages_pre_update.txt"
file_post_update="${reports_path}/${date_name_files}_${traceid}_${hostname}_packages_post_update.txt"

################################################################################
# Functions
################################################################################

func_help() {

    echo -e "Usage:\n"

    echo "The ${tool_name} was projected to run as part of an automated process."
    echo -e "For this reason, there are a limited options. Let's see the options:\n"

    echo ">>> Show this assistent: $0 -h"
    echo ">>> Simulate the update process: $0 --simulate"
    echo -e ">>> To run the update, no parameter is needed. Just run: $0\n"
    echo "Take care. Bye o/"
    exit 0

}

func_log() {

    # Verifies if the directory exists:
    if [ ! -d "$tool_log_path" ]; then

        # If not, create and configure it:
        mkdir -p "$tool_log_path"

        # Check if the directory was created successfully:
        if [ "$?" -ne 0 ]; then

            echo "ERROR: Failed to create log directory. Please check permissions and available disk space." >&2
            exit 1

        else

            touch "$tool_log_file"
            chmod 644 "$tool_log_file"

        fi

    fi

    if [ ! -d "$reports_path" ]; then

        # If the log file does not exist, create it:
        mkdir -p "$reports_path"

        # Check if the directory was created successfully:
        if [ "$?" -ne 0 ]; then

            echo "ERROR: Failed to create report directory. Please check permissions and available disk space." >&2
            exit 1

        fi

    fi

    # Verifies if the log file exists:
    if [ -e "$tool_log_file" ]; then

        # If yes, spected to receive 2 arguments: $1 and $2
        local level="$1"
        local message="$2"
        local log_mode="$3"
        local timestamp
        timestamp=$(date '+%Y-%m-%d %H:%M:%S (%Z)')

        case $log_mode in
            both)
                echo "[${timestamp}] [${traceid}] [${level}] ${message}" >> "${tool_log_file}" ;
                echo "[${level}] $message" ;;
            file)
                echo "[${timestamp}] [${traceid}] [${level}] ${message}" >> "${tool_log_file}" ;;
            screen)
                echo "[${level}] $message" ;;
            silent) ;;
            *)
                echo "Invalid or undefined log_mode value" ; exit 1 ;;
        esac

    fi

}

func_pkgs_to_avoid_update() {

    # Collect list of packages to avoid updateing (hold):
    if [ -d "$path_to_pkgs_hold" ]; then

    # Just a message to separate the update process in the log:
    func_log "$INFO" "Checking for packages to be held to avoid updates in $path_to_pkgs_hold directory." "both"

    # Just a message to separate the update process in the log:
    echo ""
    echo "${bar} Check core services to avoid updates ${bar}"

    # List of packages to be held to avoid updating (hold).
    excludes="$(find "$path_to_pkgs_hold" -maxdepth 1 -type f -printf '%f ' | sed 's/,$//')"

        # Check if the variable with the list of packages to be held is not empty:
        if [ -n "$excludes" ]; then

            # Printing the list of packages to be held:
            func_log "$INFO" "Found packages to avoid updates: $excludes" "both"

            # Loop through each package in the list of packages to be held and check if it has a security update available:
            for pkg in $excludes ; do

                # Check if the package is in the list of available security updates:
                if grep -iw "$pkg" "$file_updates_available" > /dev/null ; then

                    case $current_os in
                        # Debian and Debian-like:
                        debian|ubuntu)
                            func_log "$WARN" "Package $pkg has a security update available but will be held to avoid updating." "both"
                            packages_to_hold="${packages_to_hold} ${pkg}" ;
                            apt-mark hold "$pkg" 2> /dev/null ;;
                        # RHEL and RHEL-like:
                        rhel|centos|oracle|ol|rocky)
                            func_log "$WARN" "Package $pkg has a security update available but will be excluded from update." "both"
                            packages_to_hold="${packages_to_hold},${pkg}*" ;;
                        # Unsupported OS:
                        *)
                            func_log "$ERROR" "Unsupported OS for package hold. Please check the script." "both" ;
                            exit 1 ;;
                    esac

                else

                    # If the package is not in the list of available security updates, print a message indicating that it will not be held:
                    func_log "$INFO" "Package $pkg does not have a security update available and will not be held." "both"

                fi

            done

        else

            # Just a message to separate the update process in the log:
            func_log "$INFO" "No packages marked to be held. All security updates will be applied." "both" ; echo ""

        fi

    fi

}

func_perform_update() {

    # Verifies the modal to determine if will perform general update or just security updates:
    case $modal_update_all_packages in

        # General updates:
        True|true|TRUE)

            func_log "$INFO" "Performing $update_level Update." "both" ; echo "" ;

                # In this case, there are packages to be held.
                case $current_os in

                    ###########################################
                    # General update for Debian and Debian-like
                    ###########################################

                    debian|ubuntu)

                        # At this point, if there are packages to be held, they are already marked as held on APT. So, it is not
                        # necessary to filter those packages. Even if we run a general upgrade, those packages will not be affected.

                        # General update with or without held packages for Debian and Debian-like:
                        export DEBIAN_FRONTEND=noninteractive
                        apt upgrade "$schrodinger_update" -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

                        case $? in
                            0) update_status="Success" ;;
                            *) update_status="Failed" ;;
                        esac

                        #
                        # Check if there are packages held to be unheld:
                        #

                        if [ -n "$packages_to_hold" ]; then

                            # Just a message to separate the update process in the log:
                            echo "${bar} Unhold packages ${bar}"

                            # Unmark the packages that were held.
                            apt-mark unhold $packages_to_hold 2> /dev/null

                        fi

                    ;;

                    #######################################
                    # General update for RHEL and RHEL-like
                    #######################################

                    rhel|centos|oracle|ol|rocky)

                        # Check if there are packages to be held to avoid updates:
                        if [ -n "$packages_to_hold" ]; then

                            # General update with held packages for RHEL and RHEL-like:
                            yum update "$schrodinger_update" "--exclude=$packages_to_hold"

                            case $? in
                                0) update_status="Success" ;;
                                *) update_status="Failed" ;;
                            esac

                        else

                            # General update without held packages for RHEL and RHEL-like:
                            yum update "$schrodinger_update"

                            case $? in
                                0) update_status="Success" ;;
                                *) update_status="Failed" ;;
                            esac

                        fi

                    ;;

                    *)
                        # If the OS is not supported, log an error message and exit:
                        func_log "$ERROR" "Unsupported OS: $current_os. Please check the configuration." "both" ;
                        exit 1
                    ;;

                esac

            ;;

        # Security updates only:
        False|false|FALSE)

            func_log "$INFO" "Performing $update_level Update." "both" ; echo "" ;

            # In this case, there are packages to be held.
            case $current_os in

                ###########################################
                # Security Update for Debian and Debian-like
                ###########################################

                debian|ubuntu)

                    # Check if there are packages to be held to avoid updates:
                    if [ -n "$packages_to_hold" ]; then

                        # Security Update with held packages for Debian and Debian-like:
                        export DEBIAN_FRONTEND=noninteractive
                        apt install "$schrodinger_update" -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
                        $(apt list --upgradable 2>/dev/null | grep -i sec | cut -d/ -f1 | grep ^[a-z] | grep -vFf <(ls "$path_to_pkgs_hold") | tr '\n' ' ')

                        case $? in
                            0) update_status="Success" ;;
                            *) update_status="Failed" ;;
                        esac

                        # Just a message to separate the update process in the log:
                        echo "${bar} Unhold packages ${bar}"

                        # Unmark the packages that were held to avoid updating, so they can receive updates in the future when they have security updates available:
                        apt-mark unhold $packages_to_hold 2> /dev/null

                    else

                        # Security Update without held packages for Debian and Debian-like:
                        export DEBIAN_FRONTEND=noninteractive
                        apt install "$schrodinger_update" -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
                        $(apt list --upgradable 2>/dev/null | grep -i sec | cut -d/ -f1 | grep ^[a-z])

                        case $? in
                            0) update_status="Success" ;;
                            *) update_status="Failed" ;;
                        esac

                    fi

                ;;

                rhel|centos|oracle|ol|rocky)

                    if [ -n "$packages_to_hold" ]; then

                        # Security Update with held packages for RHEL and RHEL-like:
                        yum update --security "$schrodinger_update" "--exclude=$packages_to_hold"

                        case $? in
                            0) update_status="Success" ;;
                            *) update_status="Failed" ;;
                        esac

                    else

                        # Security Update without held packages for RHEL and RHEL-like:
                        yum update --security "$schrodinger_update"

                        case $? in
                            0) update_status="Success" ;;
                            *) update_status="Failed" ;;
                        esac

                    fi

                ;;

                *)
                    # If the OS is not supported, log an error message and exit:
                    func_log "$ERROR" "Unsupported OS: $current_os. Please check the configuration." "both" ;
                    exit 1
                ;;
            esac

        ;;

        *)
            func_log "$ERROR" "Invalid value for modal_update_all_packages: ${modal_update_all_packages}. Please check the configuration." "both" ;
            exit 1

        ;;

    esac

    case $update_status in

        # If the update process was successful, print a message indicating that the security update was completed successfully:
        Success)

            case $schrodinger_update in
                --simulate|--assumeno)
                    func_log "$INFO" "Simulation mode enabled. No packages were actually updated, so no evidence of updated packages will be collected." "both" ;
                    echo "" ;
                    exit 0
                ;;
            esac

            func_log "$INFO" "$update_level update process completed successfully." "both" ; echo "" ;
        ;;

        # If the update process failed, print an error message and exit:
        Failed)
            func_log "$ERROR" "$update_level update failed due to dependency issues or package conflicts. Check logs for details." "both" ; echo ""
        ;;

        # This case should never happen, but it's here just in case to catch any unexpected error during the update process:
        *)
            func_log "$ERROR" "$update_level update encountered an unexpected error. Please check the logs for more details." "both" ; echo ""
        ;;
    esac

}

func_print_evidence() {

    # Collect a list of packages that were updated:
    case $current_os in

        debian|ubuntu)
            # Creates the CSV file to register the list of updated packages:
            echo "Package Name ; Old version ; New version" > "$file_updates_performed" ;

            # Collect the list of updated packages:
            current_packages=$(grep "$date" /var/log/apt/history.log -A4 | grep Upgrade | sed -e "s/Upgrade: //g" -e "s/),/)|/g" \
            | xargs -d'|' -n1 | sed -e "/^$/d" | awk '{print$1 " ; "$2" ; "$3}' | sed -e "s/(//g" -e "s/)//g" -e "s/,//g" | cut -d\; -f1)

            # Collect the list of current versions (before update) of packages:
            current_packages_version=$(grep "$date" /var/log/apt/history.log -A4 | grep Upgrade | sed -e "s/Upgrade: //g" -e "s/),/)|/g" \
            | xargs -d'|' -n1 | sed -e "/^$/d" | awk '{print$1 " ; "$2" ; "$3}' | sed -e "s/(//g" -e "s/)//g" -e "s/,//g" | cut -d\; -f2)

            # Collect the list of new versions (after update) of packages:
            new_packages_version=$(grep "$date" /var/log/apt/history.log -A4 | grep Upgrade | sed -e "s/Upgrade: //g" -e "s/),/)|/g" \
            | xargs -d'|' -n1 | sed -e "/^$/d" | awk '{print$1 " ; "$2" ; "$3}' | sed -e "s/(//g" -e "s/)//g" -e "s/,//g" | cut -d\; -f3)

            # Update CSV file with the list of packages that were updated, with their old and new versions:
            paste -d';' <(echo "$current_packages") <(echo "$current_packages_version") <(echo "$new_packages_version") >> "$file_updates_performed"

            # Variable to register in logs the package names, old versions, and new version:
            consolidated_list=$(paste -d',' <(echo "$current_packages") <(echo "$current_packages_version") <(echo "$new_packages_version") | paste -sd';' -)

            # Register the list of updated packages into the log file:
            func_log "$INFO" "The following packages were successfully updated" "file"
            func_log "$INFO" "$consolidated_list" "file"

            ;;

        rhel|centos|oracle|ol|rocky)

            # Collect the list of updated packages:
            current_packages=$(grep "$date" /var/log/dnf.rpm.log | grep -w Upgraded | awk -F "Upgraded:" '{print$2}' | sort | sed -e "s/ //g")

            # Collect the list of new versions (after update) of packages:
            new_packages_version=$(grep "$date" /var/log/dnf.rpm.log | grep -w Upgrade | awk -F "Upgrade:" '{print$2}' | sort | sed -e "s/ //g")

            # Update CSV file with the list of packages that were updated, with their old and new versions:
            paste -d';' <(echo "$current_packages") <(echo "$new_packages_version") >> "$file_updates_performed"

            # Register the list of updated packages into the log file:
            func_log "$INFO" "The following packages were successfully updated: `echo $new_packages_version`" "both"

            ;;

    esac

    if $(wc -l "$file_updates_performed" | grep -w ^"1" > /dev/null) ; then

        # Display a message indicating that no security updates were applied and exit:
        func_log "$INFO" "No security updates were applied on this system." "both" ; echo ""

        # If the modal to keep temporary files is set to true, change to false to allow the cleanup:
        if [ "$modal_keep_temporary_files" = "true" ] ; then

            # Change the variable to false to allow the cleanup of temporary files:
            modal_keep_temporary_files="false"

        fi
        func_cleanup
        exit 0

    else

        # Print packages with security updates available:
        echo ""
        echo "${bar} Here is the CSV file with all the security updates available before the update process: ${bar}"
        echo ""
        cat "$file_updates_available"
        echo ""

        # Print the evidence of the update process:
        echo "${bar} Here is the CSV file with all the evidence of the update process: ${bar}"
        echo ""
        cat "$file_updates_performed"
        echo ""

    fi

}

func_reboot_server() {

    case $current_os in

        debian|ubuntu)

            if [ -f /var/run/reboot-required ] || [ -f /var/run/reboot-required.pkgs ]; then
                reboot_needed=1
            fi

        ;;

        rhel|centos|oracle|ol|rocky)

            if which grubby > /dev/null 2>&1; then

                # Check the current kernel version:
                current_kernel=$(uname -r 2>/dev/null || echo "")

                # Check the default kernel version:
                latest_kernel=$(rpm -q --last kernel 2>/dev/null | head -1 | awk '{print$1}' | sed -e 's/kernel-//g' || echo "")

                # Compares the current kernel version with the one configured as the default
                if [ -n "$current_kernel" ] && [ -n "$latest_kernel" ]; then

                    # If the version is different, mark the server as pending reboot:
                    if [ "$current_kernel" != "$latest_kernel" ]; then

                        reboot_needed=1

                    fi

                fi

            else

                # Check the installation date of the latest kernel:
                date_kernel_installation=$(rpm -q --last kernel 2>/dev/null | head -1 | awk '{print $2, $3, $4, $5, $6}')

                # Check the server uptime:
                date_last_system_boot=$(uptime -s 2>/dev/null || who -b | awk '{print $3, $4}')

                # Ensure if the variables were not empty:
                if [ -n "$date_kernel_installation" ] && [ -n "$date_last_system_boot" ]; then

                    # Convert dates to timestamps for comparison:
                    timestamp_kernel=$(date -d "$date_kernel_installation" +%s 2>/dev/null || echo 0)
                    timestamp_boot=$(date -d "$date_last_system_boot" +%s 2>/dev/null || echo 0)

                    # If the latest kernel was installed after the last system boot, mark the server as pending reboot:
                    if [ "$timestamp_kernel" -gt "$timestamp_boot" ]; then

                        reboot_needed=1

                    fi

                fi

            fi

        ;;

    esac

    if [ "$reboot_needed" -eq 1 ]; then

        # Log a message indicating that the server will be rebooted to apply the new kernel and security fixes:
        func_log "$INFO" "The server must be rebooted to apply the new kernel and security fixes." "both" ; echo ""

        case $schrodinger_update in
            --simulate|--assumeno)
                func_log "$INFO" "Simulation mode enabled. The server would be restarted, but the restart will not be performed." "both" ;
                echo ""
                exit 0
            ;;

            *)
                # Schedule the reboot and send a broadcast to all logged in users:
                shutdown -rf +1 "Rebooting the system in 1 minute to apply new kernel and security fixes. Please save your work and log out."
            ;;

        esac

    fi

}

func_cleanup() {

    if [ "$modal_keep_temporary_files" = "true" ]; then

        func_log "$INFO" "The temporary files created during this update are being kept due to $tool_name configuration." "both"

        if [ -f "$file_updates_available" ] ; then
            func_log "$INFO" "File with the list of available security updates: $file_updates_available" "both"
        fi

        if [ -f "$file_updates_performed" ] ; then
            func_log "$INFO" "File with the evidence of packages that were updated with their old and new versions: $file_updates_performed" "both"
        fi

        if [ -f "$file_pre_update" ] ; then
            func_log "$INFO" "Only for RHEL and RHEL-like. Temporary file for storing packages version before the update: $file_pre_update" "both"
        fi

        if [ -f "$file_post_update" ] ; then
            func_log "$INFO" "Only for RHEL and RHEL-like. Temporary file for storing packages version after the update: $file_post_update" "both"
        fi

        echo ""

    else

        # Remove temporary files:
        if [ -f "$file_updates_available" ] ; then

            if file "$file_updates_available" | grep -i text > /dev/null 2>&1; then

                func_log "$INFO" "Removing file: $file_updates_available" "both"
                rm -f "$file_updates_available"

            else

                func_log "$WARN" "File $file_updates_available is not a text file. Skipping removal." "both"

            fi

        fi

        if [ -f "$file_pre_update" ] ; then

            if file "$file_pre_update" | grep -i text > /dev/null 2>&1; then

                func_log "$INFO" "Removing file: $file_pre_update" "both"
                rm -f "$file_pre_update"

            else

                func_log "$WARN" "File $file_pre_update is not a text file. Skipping removal." "both"

            fi

        fi

        if [ -f "$file_post_update" ] ; then

            if file "$file_post_update" | grep -i text > /dev/null 2>&1; then

                func_log "$INFO" "Removing file: $file_post_update" "both"
                rm -f "$file_post_update"

            else

                func_log "$WARN" "File $file_post_update is not a text file. Skipping removal." "both"

            fi

        fi

        if [ -f "$file_updates_performed" ] ; then

            if file "$file_updates_performed" | grep -i text > /dev/null 2>&1; then

                func_log "$INFO" "Removing file: $file_updates_performed" "both"
                rm -f "$file_updates_performed"

            else

                func_log "$WARN" "File $file_updates_performed is not a text file. Skipping removal." "both"

            fi

        fi

    fi

}

################################################################################
# Starting the script
################################################################################

# Check if the script is running as root:
if [ "$EUID" -ne 0 ]; then

    # If not, returns error message to user:
    # It's not possible, nor even necessary, to use func_log because there is required root privs
    echo "ERROR: This script must be run as root. Please use sudo or switch to the root user."
    exit 1

fi

# Option to simulate the update process without actually applying the updates:
if [ ! -z "$1" ]; then
    case $1 in
        --simulate)

            INFO="SIMULATION"

            case $current_os in
                debian|ubuntu)
                    schrodinger_update="--simulate"
                ;;
                rhel|centos|oracle|ol|rocky)
                    schrodinger_update="--assumeno"
                ;;
            esac
        ;;
        *)
            func_help
        ;;
    esac
else
    schrodinger_update="-y"
fi

# Important: this script is designed to run via VRX. To collect evidence, some information
# must be printed to stdout. When log_mode is set to "both", the log_level and log_msg
# values are written to both stdout and the local log file.

log_mode="both"
log_level=INFO

# Starting message with the server hostname:

if [ "$modal_update_all_packages" == true ]; then

    update_level="GENERAL"

else

    update_level="SECURITY"

fi

func_log "$INFO" "Starting $update_level update for server: ${hostname}" "both" ; echo ""

# Printing tool informations:
echo "${bar} Tool Information ${bar}"
func_log "$INFO" "Tool Name          : ${tool_name}" "both"
func_log "$INFO" "Tool Version       : ${tool_version}" "both"
echo ""

# Displaying OS Informations:
echo "$bar Current System Information $bar"
func_log "$INFO" "Current OS         : ${current_os}" "both"
func_log "$INFO" "Current OS Version : ${version_os}" "both"
func_log "$INFO" "Current Date       : ${date}" "both"
func_log "$INFO" "Server Uptime      : ${uptime}" "both"

# Start Time variable will be displayed in the end of the process:
start_time=$(date +%T)

case $current_os in

    # Debian and Debian-like:
    debian|ubuntu)

        # Update APT cache:
        func_log "$INFO" "Updating APT Cache..." "both"

        apt update -qq > /dev/null 2>&1

        case $? in
            0)
                func_log "$INFO" "APT Cache updated successfully." "both" ; echo ""
            ;;

            *)
                echo "" ;
                func_log "$ERROR" "One or more repositories failed. Process aborted." "both" ;
                exit 1
            ;;
        esac

        # Collect the list of available security updates and save it to a file:
        echo "Package;Current Version;Available Version" > "$file_updates_available"

        if [ "$modal_update_all_packages" == true ]; then

            apt list --upgradable 2> /dev/null | grep -iv listing | awk '{print$1" ; "$6" ; "$2}' | sed -e "s/]//g" >> "$file_updates_available"

        else

            apt list --upgradable 2> /dev/null | grep -i sec | grep -iv listing | awk '{print$1" ; "$6" ; "$2}' | sed -e "s/]//g" >> "$file_updates_available"

        fi
    ;;

    # RHEL and RHEL-like:
    rhel|centos|oracle|ol|rocky)

        if [ "$current_os" == "rhel" ]; then

            # Verify if the system is registered with Red Hat Subscription Manager:
            if subscription-manager identity 2>&1 | grep -i "system is not yet registered" > /dev/null ; then

                # If the system is not registered, print an error message and exit:
                func_log "$ERROR" "This RHEL system is not registered with Red Hat Subscription Manager. Please register the system to access updates." "both"
                exit 1

            fi

        fi

        # Create a CSV file with the list of available security updates:
        echo "Advisory (Errata);Package" > "$file_updates_available"

        if [ "$modal_update_all_packages" == true ]; then

            yum updateinfo --list | grep -v ^Last | awk '{print$1" ; "$3}' >> "$file_updates_available"

        else

            yum updateinfo --list --security | grep ^R | awk '{print$1" ; "$3}' >> "$file_updates_available"

        fi
    ;;

    # Unsupported OS:
    *)
        func_log "$ERROR" "Unsupported OS. This script supports only Debian/Ubuntu and RHEL/CentOS/Oracle Linux/Rocky Linux distributions." "both" ;
        exit 1
    ;;

esac

echo "$bar Checking for $update_level updates $bar"

func_log "$INFO" "Checking for available security updates." "both"

# Check if there are any security updates available by counting the number of lines in the file (excluding the header):
if wc -l "$file_updates_available" | grep -w ^"1" > /dev/null ; then

    # Display a message indicating that no security updates are available and exit:
    func_log "$INFO" "No security updates are available for this system." "both"

    # If the modal to keep temporary files is set to true, change to false to allow the cleanup:
    if [ "$modal_keep_temporary_files" = "true" ] ; then

        # Change the variable to false to allow the cleanup of temporary files:
        modal_keep_temporary_files="false"

    fi

    func_cleanup
    exit 0

else

    ##############################################
    # Verifies if the system have disk available #
    ##############################################

    # Collect current disk available in MBs:
    disk_available=$(df --output=avail -BM / | tail -1 | sed -e 's/M//')

    case $current_os in

        # Verifiy the update size for debian and debian-like systems:
        debian|ubuntu)

            if [ "$modal_update_all_packages" == true ]; then

                update_size=$(apt list --upgradable 2>/dev/null \
                | awk -F/ '/upgradable/ {print $1}' \
                | xargs apt-cache show --no-all-versions 2>/dev/null | grep '^Installed-Size:' \
                | awk '{sum+=$2} END {print int(sum/1024)}')

            else

                update_size=$(apt list --upgradable 2>/dev/null \
                | awk -F/ '/security.*upgradable/ {print $1}' \
                | xargs apt-cache show --no-all-versions 2>/dev/null | grep '^Installed-Size:' \
                | awk '{sum+=$2} END {print int(sum/1024)}')

            fi ;;

        # Verify update size for rhel and rhel-like systems:
        rhel|centos|oracle|ol|rocky)

            if [ "$modal_update_all_packages" == true ]; then

                update_size=$(yum update --assumeno 2>/dev/null \
                | grep '^Total download size:' \
                | cut -d: -f2 \
                | awk '{val=$1; unit=$2} /[0-9]/ {if (unit=="k") print int(val/1024); else if (unit=="G") print int(val*1024); else print int(val)}')

            else

                update_size=$(yum update --security --assumeno 2>/dev/null \
                | grep '^Total download size:' \
                | cut -d: -f2 \
                | awk '{val=$1; unit=$2} /[0-9]/ {if (unit=="k") print int(val/1024); else if (unit=="G") print int(val*1024); else print int(val)}')

            fi ;;

    esac

    if [ -z "$update_size" ]; then

        case $modal_reboot_after_update in

            True|true|TRUE)

                func_log "$INFO" "No updates available." "both"
                func_log "$INFO" "Checking if the server needs to be rebooted." "both"
                func_reboot_server
                echo ""

            ;;

            False|false|FALSE)

                func_log "$INFO" "No updates available, but a system reboot may be required." "both" ;

                # If the modal to keep temporary files is set to true, change to false to allow the cleanup:
                if [ "$modal_keep_temporary_files" = "true" ] ; then

                    # Change the variable to false to allow the cleanup of temporary files:
                    modal_keep_temporary_files="false"

                fi

                func_cleanup
                exit 0

            ;;

            *)
                func_log "$INFO" "No updates available." "both"
                func_log "$WARN" "Alert: Modal modal_reboot_after_update is misconfigured." "both"
                exit 0
            ;;

        esac

        # If the modal to keep temporary files is set to true, change to false to allow the cleanup:
        if [ "$modal_keep_temporary_files" = "true" ] ; then

            # Change the variable to false to allow the cleanup of temporary files:
            modal_keep_temporary_files="false"

        fi

        func_cleanup
        exit 0

    else

        # Compare size of disk available and the update size:
        if [ "$disk_available" -gt "$update_size" ]; then

            func_log "$INFO" "Sufficient disk space available to proceed with the update. Available: ${disk_available} MB | Required: ${update_size} MB." "both"

        else

            func_log "$ERROR" "Insufficient disk space to proceed with the update. Available: ${disk_available} MB | Required: ${update_size} MB." "both"
            exit 1

        fi

    fi

    # Call function to collect list of packages to check if the package have security updates available:
    func_pkgs_to_avoid_update

    # Perform the update only in packages with security fixes, excluding the ones in the hold list:
    func_perform_update

    # Print the evidence of the update process:
    func_print_evidence

    # Cleanup temporary files:
    func_cleanup

    # Check if the modal to reboot the server after the update process is set to true or false:
    if [ "$modal_reboot_after_update" = "true" ]; then

        # Check if the server needs to be rebooted to apply the new kernel and all security fixes, and reboot if necessary:
        func_reboot_server

    fi

    echo ""
    echo "$bar Finished ${bar}"
    func_log "$INFO" "Update Status: Completed." "both"
    func_log "$INFO" "Started: ${date} ${start_time} (`date +%Z`)" "both"
    func_log "$INFO" "Finished: ${date} $(date +%T) (`date +%Z`)" "both"

    #func_log "$INFO" "Packages Updated: $(wc -l "$file_updates_performed" | awk '{print$1-1}')" "both"
    func_log "$INFO" "Packages Updated: $(echo $new_packages_version | xargs -n1 | wc -l)" "both"

fi