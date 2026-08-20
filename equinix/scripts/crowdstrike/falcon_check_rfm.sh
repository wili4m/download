#!/bin/bash

# Description: script to detect if the system is running in reduced functionality mode
# Script by: wdefreitas@equinix.com

kernel=$(uname -r)
bar() {

	local text=$1

	echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
	echo "$text"

}

bar "$(hostname -f)"
bar "$(uname -a)"

if [ -f "/opt/CrowdStrike/falconctl" ]; then

	bar "$(/opt/CrowdStrike/falconctl -g --version)"

	if command /opt/CrowdStrike/falconctl -g --rfm-state | grep -i true > /dev/null ; then

		bar "$(/opt/CrowdStrike/falconctl -g --rfm-state)"

		bar "$(/opt/CrowdStrike/falconctl -g --rfm-history)"

		echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
		/opt/CrowdStrike/falcon-kernel-check -k $kernel
		echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
		exit 1

	else


		bar "$(/opt/CrowdStrike/falconctl -g --rfm-state)"
		exit 0

	fi

else

	echo "Falcon not detected"
	exit 1

fi