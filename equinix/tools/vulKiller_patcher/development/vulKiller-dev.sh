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

# Just the tool stage for information purposes:
tool_stage="dev"

# The tool version:
tool_version="1.3.0"

# Determines the current OS:
current_os="$(cat /etc/os-release | grep -w ID | awk -F= '{print$2}' | sed -e 's/"//g')"

# Determines the current OS version:
version_os="$(cat /etc/os-release | grep -w VERSION_ID | awk -F= '{print$2}' | sed -e 's/"//g')"

################################################################################
# Modals Variables
################################################################################
# modal_keep_report_files: true or false.
# If true, keeps report files generated during execution.
# If false, removes them after the script finishes.
modal_keep_report_files=true

# modal_reboot_after_update: true or false.
# If true, automatically reboots the server when a new kernel is installed.
# If false, only prints a recommendation for manual reboot.
modal_reboot_after_update=true

# modal_update_all_packages: true or false.
# If true, updates all available packages, except those marked as "hold".
# If false, updates only packages with security fixes available.
modal_update_all_packages=true

#modal_convert_server_time_to_brt: true or false
# If true, converts the server time to BRT when the locale is different from America/Sao_Paulo
# If false, ignores BRT and uses the locale in use by the server.
modal_convert_server_time_to_brt=true

# modal_force_reboot_after_update: true or false
# If true, forces the server to reboot after the update process, regardless of the reboot schedule
# if false, the server will only reboot if the reboot schedule allows it.
modal_force_reboot_after_update=true

# modal_ignore_held_packages: true or false
# If true, forces the update of all packages, regardless of the modal_update_all_packages setting
# if false, the update process will follow the modal_update_all_packages setting.
modal_ignore_held_packages=false
################################################################################
# General Variables:
################################################################################

# Server hostname:
hostname="$(hostname)"

# Directory where empty files named after packages are stored to prevent them from being updated
path_to_pkgs_hold="/etc/default/equinix/pkgs_hold"

# Minimum required disk space in MBs for /
readonly required_disk_space_mb_root=1024

# Minimum required disk space in MBs for /boot
readonly required_disk_space_mb_boot=100

# Minimum required disk space in MBs for /boot/efi
readonly required_disk_space_mb_boot_efi=100

# Minimum required disk space in MBs for /var
readonly required_disk_space_mb_var=1024

# Minimum required disk space in MBs for /usr
readonly required_disk_space_mb_usr=1024

# Minimum required disk space in MBs for /tmp
readonly required_disk_space_mb_tmp=512

################################################################################
# CPU/Memory and I/O Priority Variables:
################################################################################

# cpu_priority: high, balanced, or low
# extreme: not recommended for production environments.
# high: maintenance windows with low resource contention.
# balanced: default for most production environments.
# low: hosts with high resource contention (e.g. DB/HA nodes).
cpu_priority="high"

case "$cpu_priority" in

    extreme)
        func_log "$INFO" "Setting CPU and I/O priority to extreme." "both"
        renice -n -20 -p "$$" >/dev/null 2>&1 || true
        ionice -c 1 -n 0 -p "$$" >/dev/null 2>&1 || true
        ;;

    high)
        func_log "$INFO" "Setting CPU and I/O priority to high." "both"
        renice -n -15 -p "$$" >/dev/null 2>&1 || true
        ionice -c 2 -n 0 -p "$$" >/dev/null 2>&1 || true
        ;;

    balanced)
        func_log "$INFO" "Setting CPU and I/O priority to balanced." "both"
        renice -n -10 -p "$$" >/dev/null 2>&1 || true
        ionice -c 2 -n 4 -p "$$" >/dev/null 2>&1 || true
        ;;

    low)
        func_log "$INFO" "Setting CPU and I/O priority to low." "both"
        renice -n 0 -p "$$" >/dev/null 2>&1 || true
        ionice -c 3 -p "$$" >/dev/null 2>&1 || true
        ;;

    *)
        func_log "$WARN" "cpu_priority invalido: '$cpu_priority', usando balanced"
        renice -n 0 -p "$$" >/dev/null 2>&1 || true
        ionice -c 2 -n 4 -p "$$" >/dev/null 2>&1 || true
        ;;

esac

################################################################################
# Reboot Schedule Variables:
################################################################################

# Directory where empty files are stored to determine the reboot schedule:
path_to_reboot_schedule="/etc/default/equinix/reboot_schedule"

# If the modal to reboot is enabled and a new kernel is installed, the variable will be set to 1.
reboot_needed=0

# If there is an error in the schedule configuration, the the variable will be set to 1 to suspend the reboot.
reboot_aborted=0

# If there is a valid schedule for reboot, the variable will be set to 1.
reboot_scheduled=0

################################################################################
# Logs Variables
################################################################################

# Tool log path:
tool_log_path="/var/log/${tool_name}"

# Tool log file:
tool_log_file="${tool_log_path}/${tool_name}.log"

# Defines date in format YYYY-MM-DD to be used inside log registers:
date="$(date +%Y-%m-%d)"

# Current Year:
date_year=$(date +%Y)

# Current Month:
date_month=$(date +%m)

# Current Day:
date_day=$(date +%d)

# Timezone:
timezone="$(date +%z)"

# Server hour:
system_time=$(date +"%H%M")

# Created to compare server time with brasilia time
brazil_time="$(TZ='America/Sao_Paulo' date +"%H%M")"

# Defines date in format YYYY_MM_DD to be used in file names::
date_name_files="${date_year}_${date_month}_${date_day}"

# Timestamp to be used as trace ID in logs:
traceid="$(date +%s)"

# Gets the number of days the server has been up. Formats using decimal places.
server_uptime=$(printf "%02d" $(awk '{print int($1/86400)}' /proc/uptime))

# Concatenates the uptime and its description to be used in the log:
uptime="$server_uptime Day(s)"

# Just a separator to make the log more readable:
bar="##########"

# Log levels:
INFO="INFO"
WARN="WARN"
ERROR="ERROR"

################################################################################
# Report Variables
################################################################################

# Defines a path to store temporary files and the evidences
reports_path="${tool_log_path}/reports/${date_year}/${date_month}/${date_day}"

# File for storing the list of available security updates. This is an evidence:
report_updates_available="${reports_path}/${date_name_files}_${traceid}_${hostname}_updates_available.csv"

# Defines file for storing the evidence of the update process (packages that were updated with their old and new versions):
report_updates_performed="${reports_path}/${date_name_files}_${traceid}_${hostname}_updates_performed.csv"

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

        # Checks if the directory was created successfully:
        if [ "$?" -ne 0 ]; then

            # If the directory was not created successfully, print an error message and exit:
            echo "ERROR: Failed to create log directory. Please check permissions and available disk space." >&2
            exit 1

        else

            # If the log file does not exist, create it:
            touch "$tool_log_file"
            chmod 644 "$tool_log_file"

        fi

    fi

    if [ ! -d "$reports_path" ]; then

        # If the log file does not exist, create it:
        mkdir -p "$reports_path"

        # Checks if the directory was created successfully:
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

                # Prints the log message to the screen and appends it to the log file:
                echo "[${timestamp}] [${traceid}] [${level}] ${message}" >> "${tool_log_file}" ;
                echo "[${level}] $message"

            ;;

            file)

                # Appends the log message to the log file:
                echo "[${timestamp}] [${traceid}] [${level}] ${message}" >> "${tool_log_file}"

            ;;

            screen)

                # Prints the log message to the screen:
                echo "[${level}] $message"

            ;;

            silent) ;;

            *)
                echo "Invalid or undefined log_mode value" ; exit 1 ;;
        esac

    fi

}

func_pkgs_to_avoid_update() {

    # Collects list of packages to avoid updateing (hold):
    if [ -d "$path_to_pkgs_hold" ]; then

        # Just a message to separate the update process in the log:
        echo ""
        echo "${bar} Checking core services ${bar}"

        # Just a message to separate the update process in the log:
        func_log "$INFO" "Checking for packages to be held to avoid updates in $path_to_pkgs_hold directory." "both"

        # Lists of packages to be held to avoid updating (hold).
        excludes="$(find "$path_to_pkgs_hold" -maxdepth 1 -type f -printf '%f ' | sed 's/,$//')"

        # Checks if the variable with the list of packages to be held is not empty:
        if [ -n "$excludes" ]; then

            # This variable is used to determine whether the server has only held packages remaining for the upgrade process.
            excludes_count="$(find "$path_to_pkgs_hold" -maxdepth 1 -type f | wc -l)"

            # Printing the list of packages to be held:
            func_log "$INFO" "Found packages to avoid updates: $excludes" "both"

            # Loop through each package in the list of packages to be held and check if it has a security update available:
            for pkg_check in $excludes ; do

                # Checks if the package is in the list of available security updates:
                if grep -iw "$pkg_check" "$report_updates_available" > /dev/null ; then

                    func_log "$WARN" "Package $pkg_check: update available but held back ($tool_name hold policy)." "both"

                else

                    func_log "$WARN" "Package $pkg_check: no update available but remains held back ($tool_name hold policy)." "both"

                fi

            done

            for pkg_hold in $excludes ; do

                case $current_os in

                    # Debian and Debian-like:
                    debian|ubuntu)
                        packages_to_hold="${packages_to_hold} ${pkg_hold}*" ;
                        apt-mark hold "$pkg_hold" 2> /dev/null ;;

                    # RHEL and RHEL-like:
                    rhel|centos|oracle|ol|rocky)
                        packages_to_hold="${packages_to_hold},${pkg_hold}" ;;

                    # Unsupported OS:
                    *)
                        func_log "$ERROR" "Unsupported OS for package hold. Please check the script." "both" ;
                        exit 1 ;;

                    esac

            done

        else

            # Just a message to separate the update process in the log:
            func_log "$INFO" "No packages marked to be held." "both" ; echo ""

        fi

    fi

}

func_perform_update() {

    echo ""
    echo "$bar Starting Update Process ${bar}"

    # Verifies the modal to determine if will perform general update or just security updates:
    case $modal_update_all_packages in

        # General updates:
        True|true|TRUE)

            func_log "$INFO" "Package update process initiated." "both" ; echo "" ;

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
                        # Checks if there are packages held to be unheld:
                        #

                        if [ -n "$packages_to_hold" ]; then

                            # Just a message to separate the update process in the log:
                            echo "${bar} Unhold packages ${bar}"

                            # Unmark the packages that were held.
                            apt-mark unhold "$packages_to_hold" 2> /dev/null

                        fi

                    ;;

                    #######################################
                    # General update for RHEL and RHEL-like
                    #######################################

                    rhel|centos|oracle|ol|rocky)

                        # Checks if there are packages to be held to avoid updates:
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

                ############################################
                # Security Update for Debian and Debian-like
                ############################################

                debian|ubuntu)

                    # Checks if there are packages to be held to avoid updates:
                    if [ -n "$packages_to_hold" ]; then

                        # Security Update with held packages for Debian and Debian-like:
                        export DEBIAN_FRONTEND=noninteractive
                        apt install "$schrodinger_update" -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
                        $(apt list --upgradable 2>/dev/null | grep -i sec | cut -d/ -f1 | grep "^[a-z]" | grep -vFf <(ls "$path_to_pkgs_hold") | tr '\n' ' ')

                        case $? in
                            0) update_status="Success" ;;
                            *) update_status="Failed" ;;
                        esac

                        # Just a message to separate the update process in the log:
                        echo ""
                        echo "${bar} Unhold packages ${bar}"

                        # Unmark the packages that were held to avoid updating, so they can receive updates in the future when they have security updates available:
                        apt-mark unhold "$packages_to_hold" 2> /dev/null

                    else

                        # Security Update without held packages for Debian and Debian-like:
                        export DEBIAN_FRONTEND=noninteractive
                        apt install "$schrodinger_update" -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
                        $(apt list --upgradable 2>/dev/null | grep -i sec | cut -d/ -f1 | grep "^[a-z]")

                        case $? in
                            0) update_status="Success" ;;
                            *) update_status="Failed" ;;
                        esac

                    fi

                ;;

                ############################################
                # Security Update for Redhat and Redhat-like
                ############################################

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

            # This is a important concept: schrodinger_update is set to --simulate (Debian) or --assumeno
            # (Red Hat) when the script runs with --simulate; otherwise, it is "-y".

            case $schrodinger_update in

                --simulate|--assumeno)

                    echo ""
                    func_log "$INFO" "Simulation mode enabled. No packages were updated." "both" ;
                    echo "" ;
                    exit 0
                ;;

            esac

            echo ""
            func_log "$INFO" "Update process completed." "both" ; echo "" ;

        ;;

        # If the update process failed, print an error message and exit:
        Failed)

            case $schrodinger_update in

                --simulate|--assumeno)

                    echo ""
                    func_log "$INFO" "Simulation mode enabled. No packages were updated." "both" ;
                    echo "" ;
                    exit 0
                ;;

            esac

            echo ""
            func_log "$ERROR" "Update process failed due to package dependency issues or conflicts. Check the logs for detailed information." "both" ; echo ""
        ;;

        # This case should never happen, but it's here just in case to catch any unexpected error during the update process:
        *)
            func_log "$ERROR" "Update process failed due to an unexpected error. Please review the logs for more details." "both" ; echo ""
        ;;
    esac

}

func_print_evidence() {

    case $schrodinger_update in
    --simulate|--assumeno)
        func_log "$INFO" "Simulation mode enabled. Any change has been performed." "both" ;
        echo ""
        exit 0
    ;;
    esac

    # Collect a list of packages that were updated:
    case $current_os in

        debian|ubuntu)

            # Creates the CSV file to register the list of updated packages:
            echo "Package Name ; Old version ; New version" > "$report_updates_performed" ;

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
            paste -d';' <(echo "$current_packages") <(echo "$current_packages_version") <(echo "$new_packages_version") >> "$report_updates_performed"

            # Variable to register in logs the package names, old versions, and new version:
            consolidated_list=$(paste -d',' <(echo "$current_packages") <(echo "$current_packages_version") <(echo "$new_packages_version") | paste -sd';' -)

            # Register the list of updated packages into the log file:
            func_log "$INFO" "The following packages were successfully updated" "file"
            func_log "$INFO" "$consolidated_list" "file"

            ;;

        rhel|centos|oracle|ol|rocky)

            # Creates the CSV file to register the list of updated packages:
            echo "Package old version ; Package new version" > "$report_updates_performed" ;

            # Collect the list of updated packages:
            current_packages=$(grep "$date" /var/log/dnf.rpm.log | grep -w Upgraded | awk -F "Upgraded:" '{print$2}' | sort | sed -e "s/ //g")

            # Collect the list of new versions (after update) of packages:
            new_packages_version=$(grep "$date" /var/log/dnf.rpm.log | grep -w Upgrade | awk -F "Upgrade:" '{print$2}' | sort | sed -e "s/ //g")

            # Update CSV file with the list of packages that were updated, with their old and new versions:
            paste -d';' <(echo "$current_packages") <(echo "$new_packages_version") >> "$report_updates_performed"

            # Register the list of updated packages into the log file:
            func_log "$INFO" "The following packages were successfully updated: `echo $new_packages_version`" "both"

            ;;

    esac

    # Validates variable to determine if any package was updated:
    if [ -n "$new_packages_version" ]; then

        # Sets the variable with the count of packages that were updated:
        updates_performed_count="$(echo $new_packages_version | xargs -n1 | wc -l)"

    else

        # If no packages were updated, set the count to 0:
        updates_performed_count=0

    fi

    echo "$bar Update Results ${bar}"

    # If updates_performed_count is greater than or equal to 1, it means that there are updates available.
    if [ "$updates_performed_count" -ge "1" ]; then

        # Print packages with security updates available:
        echo ""
        echo "${bar} Here is the CSV file with all the security updates available before the update process: ${bar}"
        echo ""
        cat "$report_updates_available"
        echo ""

        # Print the evidence of the update process:
        echo "${bar} Here is the CSV file with all the evidence of the update process: ${bar}"
        echo ""
        cat "$report_updates_performed"
        echo ""

    else

        # Display a message indicating that no security updates were applied and exit:
        func_log "$INFO" "No updates were applied on this system." "both"

        # If the modal to keep report files is set to true, change to false to allow the cleanup:
        if [ "$modal_keep_report_files" = "true" ] ; then

            # Change the variable to false to allow the cleanup of report files:
            modal_keep_report_files="false"

        fi

        # Call the function to cleanup temporary files and exit the script:
        func_cleanup
        exit 0

    fi

}

func_convert_time_to_brt() {

    local system_minutes brazil_minutes reboot_minutes diff_server_time_to_brazil_time

    # Convert hours to minutes and use base 10 to format values:
    # Eg.: 0133 = 1 * 60 + 33 = 93 minutes
    system_minutes=$((10#${system_time:0:2} * 60 + 10#${system_time:2:2}))
    brazil_minutes=$((10#${brazil_time:0:2} * 60 + 10#${brazil_time:2:2}))
    reboot_minutes=$((10#${reboot_time:0:2} * 60 + 10#${reboot_time:2:2}))

    # Subtract system_minutes from brazil_minutes:
    # Ex.: (system_minutes = 01h:33 = 93 minutes) - (brazil_minutes = 22h:33 or 1353 min) = -1260
    diff_server_time_to_brazil_time=$((system_minutes - brazil_minutes))

    # Checks if the result is a negative value:
    if (( diff_server_time_to_brazil_time < 0 )); then

        # Normalize the value to a positive value adding add 1440 min (24 hours) to avoid issues:
        # Ex.: -1260 + 1440 = 180 min (3 hours)
        diff_server_time_to_brazil_time=$((diff_server_time_to_brazil_time + 1440))

    fi

    # Sums the reboot min and diff_server_time_to_brazil_time:
    # Ex.: *reboot_minutes = 01h:00 = 60 min) + 180 min = 240 min
    reboot_minutes=$((reboot_minutes + diff_server_time_to_brazil_time))

    # Applies the difference to the desired reboot time (specified in BRT)
    # and uses modulo 1440 to keep the result within a valid day.
    # E.g.: (reboot=01:00 -> 60 min) + 180 min = 240 min -> 04:00
    reboot_minutes=$((reboot_minutes % 1440))

    # Converts back the resultant minutes to hours:
    # Exemplo:
    # 240 min -> 04:00 -> 0400

    converted_time_to_reboot=$(printf "%02d%02d" $((reboot_minutes / 60)) $((reboot_minutes % 60)))

}

func_reboot_server() {

    if [ "$modal_reboot_after_update" = "false" ]; then

        func_log "$INFO" "The modal to reboot the server after update is disabled. No reboot check will be performed." "both"
        return 0

    fi

    echo ""
    echo "${bar} Reboot Policy ${bar}"

    # Start to verify if the server needs to be rebooted by checking if a new kernel was installed.
    case $current_os in

        # Debian and Debian-like distributions have a specific file that is created when a new kernel is installed:
        debian|ubuntu)

            if [ -f /var/run/reboot-required ] || [ -f /var/run/reboot-required.pkgs ]; then
                reboot_needed=1

            else

                # Detect the current kernel in execution:
                curr_kernel="$(uname -r)"

                # Detect the default kernel version based on the last version.
                default_kernel="$(dpkg -l 'linux-image-[0-9]*' 2>/dev/null \
                    | awk '/^ii/ {sub(/^linux-image-/, "", $2); print $2}' \
                    | sort -V | tail -n1)"

                # If kernel version mismatch, mark the server to be rebooted:
                if [[ -n "$default_kernel" && "$curr_kernel" != "$default_kernel" ]]; then

                    reboot_needed=1

                fi

            fi

        ;;

        # Red Hat Enterprise Linux and CentOS have a specific tool for managing kernel versions:
        rhel|centos|oracle|ol|rocky)

            if command -v grubby >/dev/null 2>&1; then

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

            # If grubby is not available, the script will check the installation date of the latest kernel and compare it with the last system boot date:
            else

                # Check the installation date of the latest kernel:
                date_kernel_installation=$(rpm -q --last kernel 2>/dev/null | head -1 | awk '{print $2, $3, $4, $5, $6}')

                # Check the server uptime:
                date_last_system_boot=$(uptime -s 2>/dev/null || who -b | awk '{print $3, $4}')

                # Ensures variables is not empty:
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
        func_log "$INFO" "A system reboot is required to apply the new kernel and security updates." "both"

        if [ "$modal_force_reboot_after_update" = "true" ]; then

            func_log "$INFO" "The modal to force reboot after update is enabled. The server will be rebooted immediately." "both"

        else

            # Check if directory for reboot schedule exists:
            if [ ! -d "$path_to_reboot_schedule" ]; then

                # If not, create it:
                mkdir -p "$path_to_reboot_schedule"

            else

                # Count the number of files in the reboot schedule directory:
                reboot_time_schedule_count=$(find "$path_to_reboot_schedule" -maxdepth 1 -type f -name '[0-2][0-9][0-5][0-9]' | wc -l)

                # Regex explanation:
                # Expect file name format: HHMM. So, there are only 4 characteres in the file name.
                # The first character can be 0, 1 or 2 to represent the tens of hours.
                # The second one can be 0 to 9 if the first is 0 or 1.
                # The third one can be 0 to 5 to represent the tens of minutes.
                # The fourth one can be 0 to 9 to represent the units of minutes.
                # Eg: 0000 = valid. Represents 00:00 (midnight)
                # Eg: 2319 = valid. Represents 23:19 (11:19 PM)
                # Eg: 2560 = invalid. Represents 25:60 (invalid time). It will be detected in the validation step below.

                case "$reboot_time_schedule_count" in

                    # If there is no file, the server will be rebooted immediately:
                    0)
                        func_log "$INFO" "This server does not have a reboot schedule configured." "both"
                        reboot_scheduled=0
                    ;;

                    # If there is one file, creates new variables to parameterize the reboot schedule:
                    1)
                        func_log "$INFO" "Reboot schedule configuration detected. Validating..." "both"

                        # Specify the file format using regex:
                        reboot_time_schedule="${path_to_reboot_schedule}/[0-2][0-9][0-5][0-9]"

                        # Verifies if the reboot schedule file exists:
                        if [ -f $reboot_time_schedule ]; then

                            # Extract the hour from file name (just two first characters):
                            reboot_time_schedule_hour="$(basename ${reboot_time_schedule} | cut -c1-2)"

                            # Extract the minute from file name (just two last characters):
                            reboot_time_schedule_min="$(basename ${reboot_time_schedule} | cut -c3-4)"

                            # Validates if the hour is between 00 and 23 and if the minute is between 00 and 59:
                            if [ "$reboot_time_schedule_hour" -ge 24 ] || [ "$reboot_time_schedule_min" -ge 60 ]; then

                                # If hour is equal or bigger than 24, or if minute is equal or bigger than 60, reports errors and aborts the reboot:
                                func_log "$ERROR" "Validation failed. Invalid time schedule format. Please check the files in $path_to_reboot_schedule directory." "both"
                                reboot_aborted=1

                            else

                                if [ "$modal_convert_server_time_to_brt" = "true" ]; then

                                    func_log "$INFO" "Checking: The system is using a time zone ($(date "+%Z %z")) other than BRT." "both"

                                    if [[ "$system_time" != "$brazil_time" ]]; then

                                        func_log "$INFO" "Checking: Calculating the restart time based on BRT..." "both"

                                        reboot_time="${reboot_time_schedule_hour}${reboot_time_schedule_min}"

                                        #func_log "$INFO" "Confirmed: Schedule reboot time (BRT -0300): ${reboot_time_schedule_hour}:${reboot_time_schedule_min}" "both"

                                        func_convert_time_to_brt
                                        #echo $converted_time_to_reboot

                                        # Extract the hour from file name (just two first characters):
                                        reboot_time_schedule_hour_brt="$(basename ${converted_time_to_reboot} | cut -c1-2)"

                                        # Extract the minute from file name (just two last characters):
                                        reboot_time_schedule_min_brt="$(basename ${converted_time_to_reboot} | cut -c3-4)"

                                        #func_log "$INFO" "Confirmed: Schedule reboot time ($(date "+%Z %z")): ${reboot_time_schedule_hour_brt}:${reboot_time_schedule_min_brt}" "both"
                                        func_log "$INFO" "Confirmed: Restart time at ${reboot_time_schedule_hour_brt}:${reboot_time_schedule_min_brt} ($(date "+%Z %z")), (${reboot_time_schedule_hour}:${reboot_time_schedule_min} BRT)." "both"


                                        recalculated_time=1

                                    else

                                        func_log "$INFO" "Confirmed: The server is configured with the BRT timezone." "both"


                                    fi

                                else

                                    func_log "$INFO" "Confirmed: The restart policy will use the server timezone as a reference." "both"

                                fi

                                # If the validation is successful, mark the server to reboot respecting the schedule:
                                reboot_scheduled=1

                            fi

                        else

                            # If not, log an error message and abort the reboot:
                            func_log "$ERROR" "Invalid scheduled file format detected in ${path_to_reboot_schedule}. The reboot will not be performed." "both"
                            reboot_aborted=1


                        fi

                    ;;

                    # If there are more than one file, the reboot will be aborted to avoid conflicts:
                    *)
                        func_log "$ERROR" "Multiple schedules found in ${path_to_reboot_schedule}. The reboot will not be performed." "both"
                        reboot_aborted=1
                    ;;

                esac

            fi

        fi

        # Schrodinger because it can be a simulation or an automatic update. It depends if parameter "--simulate" was received.
        case $schrodinger_update in
            --simulate|--assumeno)
                func_log "$INFO" "Simulation mode enabled. The server would be rebooted, but the reboot will not be performed." "both" ;
                echo ""
                exit 0
            ;;

            *)

                if [ "$reboot_aborted" -eq 1 ]; then

                    func_log "$ERROR" "Reboot aborted due to invalid schedule or multiple schedules found. Please check the files in $path_to_reboot_schedule directory." "both"

                else

                    func_log "$INFO" "Scheduling the reboot..." "both" ;


                    case $reboot_scheduled in
                        0)

                            # Schedule the reboot and send a broadcast to all logged in users:
                            shutdown -r +5 "The server will reboot to apply the new kernel/security fixes. Please save your work and log out." 2> /dev/null

                            if [ -f "/run/systemd/shutdown/scheduled" ]; then

                                # Check the reboot date:
                                reboot_scheduled="$(grep ^USEC= /run/systemd/shutdown/scheduled | cut -d= -f2)"
                                reboot_scheduled_human_readable="$(date -d "@$((reboot_scheduled / 1000000))" '+%Y-%m-%d %H:%M:%S %Z')"

                                func_log "$INFO" "Reboot confirmed. Server reboot scheduled for ${reboot_scheduled_human_readable}." "both"

                            else

                                func_log "$ERROR" "Failed to schedule the reboot. Please check the system logs for more details." "both"

                            fi

                        ;;

                        1)

                            # Schedule the reboot respecting the schedule and send a broadcast to all logged in users:
                            #shutdown -rf ${reboot_time_schedule_hour}:${reboot_time_schedule_min} "The server will reboot to apply the new kernel/security fixes. Please save your work and log out." 2> /dev/null

                            if [ "$recalculated_time" == 1 ]; then

                                    # Performing the reboot schedule command:
                                    shutdown -r ${reboot_time_schedule_hour_brt}:${reboot_time_schedule_min_brt} "Server reboot at ${reboot_time_schedule_hour_brt}:${reboot_time_schedule_min_brt}\
                                    for kernel update. Save your work and log off." 2> /dev/null

                                    if [ -f "/run/systemd/shutdown/scheduled" ]; then
                                        # Check the reboot date:
                                        reboot_scheduled="$(grep ^USEC= /run/systemd/shutdown/scheduled | cut -d= -f2)"
                                        reboot_scheduled_human_readable="$(date -d "@$((reboot_scheduled / 1000000))" '+%Y-%m-%d %H:%M:%S %Z')"
                                        func_log "$INFO" "Reboot confirmed. Server reboot scheduled for ${reboot_scheduled_human_readable} (${reboot_time_schedule_hour}:${reboot_time_schedule_min} BRT)." "both"

                                    else

                                        failed_to_schedule=1

                                    fi

                            else

                                    shutdown -r ${reboot_time_schedule_hour}:${reboot_time_schedule_min} "Server reboot at ${reboot_time_schedule_hour}:${reboot_time_schedule_min}\
                                    for kernel update. Save your work and log off." 2> /dev/null

                                    if [ -f "/run/systemd/shutdown/scheduled" ]; then

                                        # Check the reboot date:
                                        reboot_scheduled="$(grep ^USEC= /run/systemd/shutdown/scheduled | cut -d= -f2)"
                                        reboot_scheduled_human_readable="$(date -d "@$((reboot_scheduled / 1000000))" '+%Y-%m-%d %H:%M:%S %Z')"
                                        func_log "$INFO" "Reboot confirmed. Server reboot scheduled for ${reboot_scheduled_human_readable}." "both"

                                    else

                                        failed_to_schedule=1

                                    fi

                            fi

                            if [ "$failed_to_schedule" == 1 ]; then

                                func_log "$ERROR" "Failed to schedule the reboot. Please check if dbus is running and/or the system logs for more details." "both"
                                exit 1

                            fi


                        ;;

                    esac

                fi
            ;;

        esac

    else

        # If the server does not need to be rebooted, log a message indicating that no reboot is required:
        func_log "$INFO" "No reboot is required." "both"

    fi

}

func_cleanup() {

    if [ "$modal_keep_report_files" = "true" ]; then

        func_log "$INFO" "Report files were created during this update due to $tool_name configuration." "both"

        if [ -f "$report_updates_available" ] ; then
            func_log "$INFO" "Pre-update report: $report_updates_available" "both"
        fi

        if [ -f "$report_updates_performed" ] ; then
            func_log "$INFO" "Pos-update report: $report_updates_performed" "both"
        fi

        echo ""

    else

        # Remove report files:
        if [ -f "$report_updates_available" ] ; then

            # Verifies if the file is a text file before attempting to remove it:
            if file "$report_updates_available" | grep -i text > /dev/null 2>&1; then

                # If the file is a text file, log an info message and remove it:
                func_log "$INFO" "Removing file: $report_updates_available" "both"
                rm -f "$report_updates_available"

            else

                # If the file is not a text file, log a warning message and skip the removal:
                func_log "$WARN" "File $report_updates_available is not a text file. Skipping removal." "both"

            fi

        fi

        # Checks if the file exists before attempting to remove it:
        if [ -f "$report_updates_performed" ] ; then

            # Verifies if the file is a text file before attempting to remove it:
            if file "$report_updates_performed" | grep -i text > /dev/null 2>&1; then

                # If the file is a text file, log an info message and remove it:
                func_log "$INFO" "Removing file: $report_updates_performed" "both"
                rm -f "$report_updates_performed"

            else

                # If the file is not a text file, log a warning message and skip the removal:
                func_log "$WARN" "File $report_updates_performed is not a text file. Skipping removal." "both"

            fi

        fi

    fi

}

# Function to check if the specified path is a mount point:
func_check_mount_points() {

    local path="$1"
    [ "$(df -P "$path" 2>/dev/null | awk 'NR==2 {print $6}')" = "$path" ]

}

# Function to check if the specified path has enough available space.
# It receives the path and the required space in MB, but checks the available space in KB to avoid rounding issues.
func_check_mount_space_mb() {

    local path="$1"
    local required_mb="$2"
    local required_kb
    local available_kb
    local available_mb

    required_kb=$(( required_mb * 1024 ))
    available_kb="$(df -Pk "$path" | awk 'NR==2 {print $4}')"
    available_mb=$(( available_kb / 1024 ))

    # Guard: fail loudly if threshold was not provided (catches typos/unset vars)
    if [ -z "$required_mb" ]; then
        func_log "$ERROR" "check_mount_space_mb called for $path without a threshold value. Check variable names." "both"
        exit 1
    fi

    if [ "$available_kb" -lt "$required_kb" ]; then

        #available_mb=$(( available_kb / 1024 ))

        func_log "$INFO" "Disk space validation failed on $path. Available=${available_kb}KB (${available_mb}MB) Threshold=${required_kb}KB (${required_mb}MB)" "both"
        disk_space_ok=false
        partition="$path"

    else

        #available_mb=$(( available_kb / 1024 ))
        func_log "$INFO" "Free disk space meets the configured threshold: Disk=${path}. Available=${available_kb}KB (${available_mb}MB). Threshold=${required_kb}KB (${required_mb}MB)" "both"

    fi
}

################################################################################
# Starting the script
################################################################################

# Check if the script is running as root:
if [ "$EUID" -ne 0 ]; then

    # If not, returns error message to user:
    # It's not possible, nor even necessary, to use func_log because there is required root privs
    func_log "$ERROR" "This script must be run as root. Please use sudo or switch to the root user." "both"
    exit 1

else

    # Execution control:
    lock_file="/run/${tool_name}.lock"
    exec 9>>"$lock_file"

    if ! flock -n 9; then
        func_log "$ERROR" "another $tool_name instance is already running." "both"
        func_log "$INFO" "PID(s): $(echo -n `lsof $lock_file | awk '{print$2}' | grep ^[0-9]`)" "both"
        exit 1
    fi

fi

# Option to simulate the update process without actually applying the updates:
if [ ! -z "$1" ]; then

    # Checks if the first argument is --simulate, -v, or -h. If not, print the help message and exit:
    case $1 in

        # If the first argument is --simulate:
        --simulate)

            # Sets the INFO variable to "SIMULATION" to indicate that the script is running in simulation mode:
            INFO="SIMULATION"

            # Verifies the current OS to set the appropriate option for simulating the update process without actually applying the updates:
            case $current_os in

                # For Debian and Debian-like distributions, set the schrodinger_update variable to "--simulate":
                debian|ubuntu)
                    schrodinger_update="--simulate"
                ;;

                # For RHEL and RHEL-like distributions, set the schrodinger_update variable to "--assumeno":
                rhel|centos|oracle|ol|rocky)
                    schrodinger_update="--assumeno"
                ;;

            esac
        ;;

        # If the first argument is -v, -V, or --version:
        -v|-V|--version)

            # Prints the tool name, version, and release stage to stdout and exits:
            echo "$tool_name version $tool_version (release stage: $tool_stage)"
            exit 0
        ;;

        # If the first argument is -h, -H, or --help:
        -h|-H|--help)
            func_help
        ;;

        *)
            func_help
        ;;
    esac
else

    # If no arguments are provided, set the schrodinger_update variable to "-y" to automatically confirm the update process:
    schrodinger_update="-y"
fi

# Important: this script is designed to run via VRX. To collect evidence, some information
# must be printed to stdout. When log_mode is set to "both", the log_level and log_msg
# values are written to both stdout and the local log file.

log_mode="both"
log_level=INFO

# Starting message with the server hostname:

if [ "$modal_update_all_packages" == true ]; then

    # If the modal_update_all_packages is set to true, the script will perform a general update, which includes both security and non-security updates.
    # In this case, the update_level variable is set to "GENERAL" to indicate that the update process will include all available updates for the system.
    update_level="General"

else

    # If the modal_update_all_packages is set to false, the script will perform a security update, which includes only security updates.
    # In this case, the update_level variable is set to "SECURITY" to indicate
    update_level="Security"

fi

# Print the starting message with the server hostname and the update level:
func_log "$INFO" "Starting ${tool_name}..." "both" ; echo ""

# Printing tool informations:
echo "${bar} Tool Information ${bar}"
func_log "$INFO" "Tool Name           : ${tool_name}" "both"
func_log "$INFO" "Tool Version        : ${tool_version}" "both"
func_log "$INFO" "Tool Release Stage  : ${tool_stage}" "both"
func_log "$INFO" "Modal Update Level  : ${update_level}" "both"
func_log "$INFO" "Modal Reboot Server : ${modal_reboot_after_update}" "both"
func_log "$INFO" "Modal Keep Reports  : ${modal_keep_report_files}" "both"
echo ""

# Displaying OS Informations:
echo "$bar Current System Information $bar"
func_log "$INFO" "Server Hostname     : ${hostname}" "both"
func_log "$INFO" "Current OS          : ${current_os}" "both"
func_log "$INFO" "Current OS Version  : ${version_os}" "both"
func_log "$INFO" "Current Date Time   : ${date_name_files}" "both"
#func_log "$INFO" "Current Hour        : ${full_hour}" "both"
func_log "$INFO" "Server Uptime       : ${uptime}" "both"
echo ""


echo "$bar System requirements $bar"

#func_log "$INFO" "Checking for available $update_level updates." "both"
func_log "$INFO" "Initiating update evaluation..." "both"

##############################################
# Verifies if the system have disk available #
##############################################

#func_log "$INFO" "Checking for available $update_level updates." "both"
func_log "$INFO" "Checking: Disk threshold requirements..." "both"

# Collect current disk available in MBs:
func_check_mount_space_mb "/" "$required_disk_space_mb_var"
func_check_mount_points "/boot" && func_check_mount_space_mb "/boot" "$required_disk_space_mb_boot"
func_check_mount_points "/boot/efi" && func_check_mount_space_mb "/boot/efi" "$required_disk_space_mb_boot_efi"
func_check_mount_points "/var"  && func_check_mount_space_mb "/var" "$required_disk_space_mb_var"
func_check_mount_points "/usr"  && func_check_mount_space_mb "/usr" "$required_disk_space_mb_usr"
func_check_mount_points "/tmp"  && func_check_mount_space_mb "/tmp" "$required_disk_space_mb_tmp"

if [ "$disk_space_ok" = false ]; then

    func_log "$ERROR" "Failed: Disk space does not meet the threshold criteria." "both"
    exit 1

else

    func_log "$INFO" "Confirmed: Disk requirements meet the thresholds." "both"

fi

echo ""
echo "$bar Repository Instructions $bar"

func_log "$INFO" "Retrieving repository metadata." "both"

# Start Time variable will be displayed in the end of the process:
start_time=$(date +%T)

# Only on Ubuntu: Disable Phased Updates on Ubuntu Server.
case $current_os in

    # Ubuntu uses phased updates to gradually roll out selected package upgrades. As a result, some
    # packages may be reported as available by APT while remaining temporarily unavailable for
    # installation on a given host. To avoid false-positive update notifications, this tool excludes
    # packages that are deferred due to update phasing.

    ubuntu)

        # Phasing disable config file:
        disable_phased_file="/etc/apt/apt.conf.d/99-Phased-Updates"

        func_log "$INFO" "Checking: Disabled phasing packages..." "both"

        # Check if the file exists:
        if [ -f "$disable_phased_file" ]; then

            # Gets the content md5sum:
            check_phased_file=$(md5sum $disable_phased_file | awk '{print$1}')

        fi

        # If the file does not exists or the md5sum not matches, create/update the file:
        if [ ! -f "$disable_phased_file" ] || [ "$check_phased_file" != "6336f541a3056efb621f2dbe884d8b18" ]; then

            # If not, recreates the file content:
            echo 'APT::Get::Always-Include-Phased-Updates "true";' > $disable_phased_file
            func_log "$INFO" "Confirmed: Phasing packages were disabled." "both"

        else

            func_log "$INFO" "Confirmed: Phasing packages already disabled." "both"

        fi

esac

# Update APT cache:
case $current_os in

    # Debian and Debian-like:
    debian|ubuntu)

        # Update APT cache:
        func_log "$INFO" "Checking: APT Cache Update..." "both"
        apt update -qq > /dev/null 2>&1

        # Checks the exit status of the apt update command to determine if it was successful or not:
        case $? in
            0)
                func_log "$INFO" "Confirmed: APT Cache successfully updated." "both"
            ;;

            *)
                echo "" ;
                func_log "$ERROR" "One or more repositories failed. Process aborted." "both" ;
                exit 1
            ;;
        esac

        # Collect the list of available security updates and save it to a file:
        echo "Package;Current Version;Available Version" > "$report_updates_available"

        # Checks if the modal_update_all_packages variable is set to true or false to determine whether to list all available updates or only security updates:
        if [ "$modal_update_all_packages" == true ]; then

            # Lists all available updates, excluding the "Listing..." line, and formats the output to include the package name, current version, and available
            # version. The output is then appended to the file specified by the variable $report_updates_available:
            apt list --upgradable 2> /dev/null | grep -iv listing | awk '{print$1" ; "$6" ; "$2}' | sed -e "s/]//g" >> "$report_updates_available"

        else

            # Lists only security updates, excluding the "Listing..." line, and formats the output to include the package name, current version, and available
            # version. The output is then appended to the file specified by the variable $report_updates_available:
            apt list --upgradable 2> /dev/null | grep -i sec | grep -iv listing | awk '{print$1" ; "$6" ; "$2}' | sed -e "s/]//g" >> "$report_updates_available"

        fi
    ;;

    # RHEL and RHEL-like:
    rhel|centos|oracle|ol|rocky)

        # If the current OS is RHEL, verify if the system is registered with Red Hat Subscription Manager before proceeding with the update process:
        if [ "$current_os" == "rhel" ]; then

            # Verify if the system is registered with Red Hat Subscription Manager:
            if subscription-manager identity 2>&1 | grep -i "system is not yet registered" > /dev/null ; then

                # If the system is not registered, print an error message and exit:
                func_log "$ERROR" "This RHEL system is not registered with Red Hat Subscription Manager. Please register the system to access updates." "both"
                exit 1

            fi

        fi

        # Create a CSV file with the list of available security updates:
        echo "Advisory (Errata);Package" > "$report_updates_available"

        # If modal update all packages is enabled, list all update available:
        if [ "$modal_update_all_packages" == true ]; then

            # Lists all available updates, excluding the "Last" line, and formats the output to include the advisory (errata) and package name.
            # The output is then appended to the file specified by the variable $report_updates_available:
            yum updateinfo --list | grep -v ^Last | awk '{print$1" ; "$3}' >> "$report_updates_available"

        else

            # Verifies the current OS to determine the appropriate command for listing available security updates:
            case $current_os in

                # Lists only security updates, excluding the "Last" line, and formats the output to include the advisory (errata) and package name:

                rhel|centos|rocky)
                    # Take all security update available for RHEL systems:
                    yum updateinfo --list --security | grep ^R | awk '{print$1" ; "$3}' >> "$report_updates_available"
                ;;

                oracle|ol)
                    # Take all security updates availble for OEL systems:
                    yum updateinfo --list --security | grep ^E | awk '{print$1" ; "$3}' >> "$report_updates_available"
                ;;

            esac

        fi


    ;;

    # Unsupported OS:
    *)
        func_log "$ERROR" "Unsupported OS. This script supports only Debian/Ubuntu and RHEL/CentOS/Oracle Linux/Rocky Linux distributions." "both" ;
        exit 1
    ;;

esac

echo ""
echo "$bar Update Process $bar"

func_log "$INFO" "Checking: Available updates..." "both"


# Verifies the current OS to determine the appropriate command for calculating the total size of available updates:
case $current_os in

    # Verify the update size for debian and debian-like systems:
    debian|ubuntu)

        # Verifies if the modal_update_all_packages is enabled:
        if [ "$modal_update_all_packages" == true ]; then

            # Calculate the total size of available updates in KBs for Debian and Debian-like systems (General update):
            # Note: Installed-Size is already reported in KB by apt-cache.
            update_size_kb=$(apt list --upgradable 2>/dev/null \
            | awk -F/ '/upgradable/ {print $1}' \
            | xargs -r apt-cache show --no-all-versions 2>/dev/null | grep '^Installed-Size:' \
            | awk '{sum+=$2} END {if (sum>0) print sum}')

        else

            # Calculate the total size of available updates in KBs for Debian and Debian-like systems (Security update):
            update_size_kb=$(apt list --upgradable 2>/dev/null \
            | awk -F/ '/security.*upgradable/ {print $1}' \
            | xargs -r apt-cache show --no-all-versions 2>/dev/null | grep '^Installed-Size:' \
            | awk '{sum+=$2} END {if (sum>0) print sum}')

        fi ;;

    # Verify update size for rhel and rhel-like systems:
    rhel|centos|oracle|ol|rocky)

        # Verifies if the modal_update_all_packages is enabled:
        if [ "$modal_update_all_packages" == true ]; then

            # Calculate the total size of available updates in KBs for Red Hat and Red Hat-like systems (General update):
            update_size_kb=$(yum update --assumeno 2>/dev/null \
            | grep '^Total download size:' \
            | cut -d: -f2 \
            | awk '{val=$1; unit=$2} /[0-9]/ {if (unit=="k") printf "%d\n", val; else if (unit=="M") printf "%d\n", val*1024; else if (unit=="G") printf "%d\n", val*1024*1024; else printf "%d\n", val/1024}')

        else

            # Calculate the total size of available updates in KBs for Red Hat and Red Hat-like systems (Security update):
            update_size_kb=$(yum update --security --assumeno 2>/dev/null \
            | grep '^Total download size:' \
            | cut -d: -f2 \
            | awk '{val=$1; unit=$2} /[0-9]/ {if (unit=="k") printf "%d\n", val; else if (unit=="M") printf "%d\n", val*1024; else if (unit=="G") printf "%d\n", val*1024*1024; else printf "%d\n", val/1024}')

        fi ;;

esac

# If variable is empty, it means that there are no updates available.
if [ -z "$update_size_kb" ]; then

    case $modal_reboot_after_update in

        True|true|TRUE)

            func_log "$INFO" "No updates are available." "both"
            func_reboot_server
            echo ""

        ;;

        False|false|FALSE)

            func_log "$INFO" "No updates are available. However, the pending reboot check was skipped due to the current tool configuration." "both" ;

            if [ "$modal_keep_report_files" = "true" ] ; then
                modal_keep_report_files="false"
            fi

            func_cleanup
            exit 0

        ;;

        *)
            func_log "$INFO" "No updates are available." "both"
            func_log "$WARN" "Alert: Modal modal_reboot_after_update is misconfigured." "both"
            exit 0
        ;;

    esac

    if [ "$modal_keep_report_files" = "true" ] ; then

        modal_keep_report_files="false"

    fi

    func_cleanup
    exit 0

else

    func_log "$INFO" "Confirmed: Updates are available for this system." "both"
    func_log "$INFO" "Checking: Disk requirements for the update..." "both"

    target_mount="$(df -P "/usr" | awk 'NR==2 {print $6}')"
    disk_available_kb="$(df -Pk "/usr" | awk 'NR==2 {print $4}')"

    # Convert available disk space (MB) to KB for a precise comparison:
    # disk_available_kb=$(( disk_available * 1024 ))

    # Convert update size to MB (rounded up) for human-readable logging only:
    disk_available_mb=$(( disk_available_kb / 1024 ))
    update_size_mb=$(( (update_size_kb + 1023) / 1024 ))

    # Compare available disk space and the update size, both in KB:
    if [ "$disk_available_kb" -gt "$update_size_kb" ]; then

        func_log "$INFO" "Confirmed: Disk space is OK on ${target_mount}: Available: ${disk_available_kb} KB (${disk_available_mb} MB) | Required: ${update_size_kb} KB (~${update_size_mb} MB)." "both"

    else

        func_log "$ERROR" "Insufficient disk space to proceed with the update. Available: ${disk_available_kb} KB (${disk_available_mb} MB) | Required: ${update_size_kb} KB (~${update_size_mb} MB)." "both"
        exit 1

    fi

fi

if [ "$modal_ignore_held_packages" == true ]; then

    func_log "$INFO" "All packages will be updated, including held packages." "both"

else

    # Call function to collect list of packages to check if the package have security updates available:
    func_pkgs_to_avoid_update

fi

# Perform the update only in packages with security fixes, excluding the ones in the hold list:
func_perform_update

# Print the evidence of the update process:
func_print_evidence

# Cleanup report files:
func_cleanup

# Check if the modal to reboot the server after the update process is set to true or false:
if [ "$modal_reboot_after_update" = "true" ]; then

    # Check if the server needs to be rebooted to apply the new kernel and all security fixes, and reboot if necessary:
    func_reboot_server

fi

echo ""
echo "$bar Finished ${bar}"
func_log "$INFO" "Execution process   : Completed" "both"
func_log "$INFO" "Status              : $update_status" "both"
func_log "$INFO" "Started             : ${date} ${start_time} $timezone" "both"
func_log "$INFO" "Finished            : ${date} $(date +%T) $timezone" "both"
func_log "$INFO" "Packages Updated    : $updates_performed_count" "both"
func_log "$INFO" "Update Size         : ~${update_size_mb} MB" "both"