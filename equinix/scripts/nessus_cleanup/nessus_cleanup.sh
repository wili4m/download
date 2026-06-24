#!/bin/bash

# Description: Nessus cleanup. Remove old files to keep the filesystem healthy and optimized.
# Author: wdefreitas@equinix.com
# Date: 2026/03/18

days_older="3"

func_help () {

    echo "${tool_name} --dry: Run script without change anything."
    echo "${tool_name} --run: Run the script deleting candidate files."
    exit 100

}

func_cleanup () {

    # Receive two values
    path=$1
    daemon=$2
    modal=$3

    # Remove old log files:
    case $modal in

        remove) find ${path}/logs/ -type f -mtime +${days_older} -exec rm -f {} \;
        ;;
        
        print) find ${path}/logs/ -type f -mtime +${days_older} -exec echo "Old Log File found (Candidate for deletion): {}" \;
        ;;
        
        *) echo "Unknown error." ; exit 1 ;;

    esac

    # Consider files older than 3 days:
    nessus_tmp_plugins_files=$(find $path -type f -iname plugins-*.db.* -mtime +${days_older} -exec ls {} \;)

    # Check if the var isn't empty:
    if [[ ! -z $nessus_tmp_plugins_files ]]; then

        # It's expected more than 1 file, for this reason we're using a loop:
        for file in $nessus_tmp_plugins_files; do

            # Check if it's a file:
            if [ -f $file ]; then

                case $modal in

                    remove) rm -f $file
                    ;;

                    print) echo "Old Plugin DB found (Candidate for deletion): $file"
                    ;;

                    *) echo "Unknown log file: $file" ;
                    exit 1
                    ;;

                esac

                # Determine if the daemon must be restarted:
                case $? in
                    0) restart_daemon="1" ;;
                esac

            fi

        done

        # Check if the deamon must be restart:
        if [[ "$restart_daemon" -eq "1" ]]; then

            # If yes, restart the daemon:
            echo "Daemon $daemon must be restarted"

        fi

    fi

}


if [ -z $1 ]; then
 
    func_help

else

    case $1 in

        --run) modal=remove ;;
        --dry) modal=print ;;
        *) echo "Invalid option"; exit 1 ;;
    
    esac

fi

################################################################
# For Nessus Server:
################################################################

# Remove plugins:
func_cleanup "/opt/nessus/var/nessus" "nessusd.service" "$modal"

################################################################
# For Nessus Agent:
################################################################

# Remove plugins:
func_cleanup "/opt/nessus_agent/var/nessus/" "nessusagent.service" "$modal"