#!/bin/bash

# Description: This script monitors SWAP usage and moves caches from SWAP to RAM if usage exceeds a defined threshold.
# Author: Wiliam de Freitas <wdefreitas@equinix.com>
# Date: Jan 2026

tool_name="health-check"

# Define SWAP usage threshold percentage:
swap_threshold="69.99"

# Get SWAP total and used values in MB:
swap_total=$(free -m | grep Swap | awk '{print$2}')

function logger_function {
  logger -t $tool_name "$log_message"
}

# Check if SWAP is configured on the system:
if [ "$swap_total" -ne 0 ]; then

    # Get SWAP total and used values in MB:
    swap_used=$(free -m | grep Swap | awk '{print$3}')

    # Calculate SWAP usage percentage:
    swap_percent=$(awk "BEGIN {printf \"%.2f\", ($swap_used/$swap_total)*100}")

    # Log SWAP usage check initiation:
    log_message="Starting to check SWAP usage..."
    logger_function

    # Compare SWAP usage percentage with the defined threshold:
    if [[ "$swap_percent" > "$swap_threshold" ]]; then

      # Get available memory in MB to determine if caches can be moved from SWAP to RAM:
      mem_free=$(free -m | grep Mem | awk '{print$7}')

      # Check if available memory is greater than used SWAP:
      if [ "$mem_free" -gt $swap_used ]; then

        # Log SWAP usage exceeding threshold and initiation of moving caches from SWAP to RAM:
        log_message="SWAP usage is at ${swap_percent}% (${swap_used}MB), which exceeds the threshold of ${swap_threshold}%. Starting to move caches from SWAP to RAM."
        logger_function

        # Log initiation of moving caches from SWAP to RAM:
        swapoff -a

        # Check the exit status of the swapoff command and log the result:
        case $? in
          0)  log_message="SWAP caches successfully moved to Memory." ;
              logger_function ;
              swapon -a ;;

          *)  log_message="Failed to move caches from SWAP to RAM, or SWAP could not be re-enabled." ;
              logger_function ; exit 1;;
        esac

      else

        # Log insufficient free memory to move caches from SWAP to RAM:
        log_message="Insufficient available memory (${mem_free}MB) to move caches from SWAP to RAM. Current SWAP usage is at ${swap_percent}% (${swap_used}MB)."
        logger_function

      fi

    else

      # Log SWAP usage is within acceptable limits:
      logger -t $tool_name "SWAP usage is at ${swap_percent}% (${swap_used}MB), which is above the threshold of ${swap_threshold}%."

    fi

fi