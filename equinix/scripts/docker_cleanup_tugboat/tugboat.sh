#!/bin/bash

# Description: This script searches for large files in the Docker containers directory. If any large files
# are found, it attempts to clean them up by truncating them to zero size.
# Author: Wiliam de Freitas <wdefreitas@equinix.com>
# Date: Oct 2026

tool_name="tugboat"
path_docker="/var/lib/docker/containers"
files_found=0
threshold="100M"  # Threshold for large files (100MB)

# Function to log messages in the system log:
function log_message() {

    # Receive the message as an argument:
    local message="$1"
    # Log the message with the tool name as the tag:
    logger -t "$tool_name" "$message"

}

function cleaning_up() {

    # Receive the file path as an argument:
    local file="$1"

    # Truncate the file to zero size:
    truncate -s 0 "$file"

    # Check if the truncation was successful and log the result:
    if [ $? -eq 0 ]; then

        log_message "Successfully cleaned up: $file"

    else

        log_message "Failed to clean up: $file"

    fi

}

# Log the start of the search for large files:
message="Searching for large files in ${path_docker}..."
log_message "$message"

# For logging purposes, search for files larger than 100MB in the specified directory and log their paths and sizes:
for file in $(find "$path_docker" -type f -size +${threshold}); do

    log_message "Large file found: $file ($(du -h "$file" | cut -f1))"

    # Increment the count of large files found:
    ((files_found++))

done

# Log the total number of large files found and initiate cleanup if any were found:
if [ $files_found -eq 0 ]; then

    log_message "No large files found in ${path_docker}."

else

    # Log the total number of large files found and start the cleanup process:
    log_message "Total large files found: $files_found"

    # Log the start of the cleanup process:
    log_message "Starting cleanup of large files..."

    # Iterate through each large file found and call the cleanup function:
    for file in $(find "$path_docker" -type f -size +${threshold}); do

        cleaning_up "$file"

    done

fi