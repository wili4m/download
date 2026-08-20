#!/bin/bash

###############################################################################
# Nessus Agent Upgrade Script
#
# Downloads and installs a specific Nessus Agent version according to the
# operating system detected on the host.
#
# To obtain the package IDs and checksums:
# 1. Access the Tenable Downloads page.
# 2. Download the package for the target operating system.
# 3. Open your browser download history.
# 4. Right-click the downloaded file and copy its download URL.
# 5. The numeric ID is the value present after "/downloads/" in the URL.
# 6. The MD5 checksum is available on the download page.
###############################################################################

# Target Nessus Agent version.
expected_agent_version="11.2.1"

###############################################################################
# Package metadata
###############################################################################

# Debian
debian_id=29279
debian_md5="28e517eb6b4e7592bc54b6b3a60ceb8b"

# Ubuntu
ubuntu_id=29288
ubuntu_md5="fe8d3e2c1c563faed9bf0c2cad0500d2"

# RHEL 8 based distributions
rhel8_id=29281
rhel8_md5="e262dd349fbcb64b88d0b2eb8fd3f2b2"

# RHEL 9 based distributions
rhel9_id=29283
rhel9_md5="86aa36b1a705bb4dbd53e2738c68c309"

###############################################################################
# System information
###############################################################################

# Nessus CLI binary path.
nessuscli="/opt/nessus_agent/sbin/nessuscli"

# Temporary download location.
download_dir="/var/tmp"

# Detect operating system.
current_os="$(. /etc/os-release && echo "$ID")"

# Detect operating system major version.
version_id="$(. /etc/os-release && echo "$VERSION_ID" | cut -d. -f1)"

# Get currently installed Nessus Agent version.
cur_agent_version="$($nessuscli -v | awk '/^Nessuscli/ {print $4}')"

###############################################################################
# Exit if the target version is already installed.
###############################################################################

if [ "$cur_agent_version" = "$expected_agent_version" ]; then
    echo "INFO: No action needed. Version ${expected_agent_version} is already installed."
    exit 0
fi

###############################################################################
# Select package information according to OS.
###############################################################################

case "$current_os" in

    debian)

        download_id="$debian_id"
        package_md5="$debian_md5"
        pkg_mgr="apt"
        package_name="nessus_agent.deb"

    ;;

    ubuntu)

        download_id="$ubuntu_id"
        package_md5="$ubuntu_md5"
        pkg_mgr="apt"
        package_name="nessus_agent.deb"

    ;;

    rhel|ol|oracle|rocky)

        if [ "$version_id" -eq 8 ]; then

            download_id="$rhel8_id"
            package_md5="$rhel8_md5"
            pkg_mgr="dnf"
            package_name="nessus_agent.rpm"

        elif [ "$version_id" -eq 9 ]; then

            download_id="$rhel9_id"
            package_md5="$rhel9_md5"
            pkg_mgr="dnf"
            package_name="nessus_agent.rpm"

        else

            echo "ERROR: Unsupported RHEL-based version detected (${version_id})."
            exit 1

        fi

    ;;

    *)

        echo "ERROR: Unsupported operating system (${current_os})."
        exit 1

    ;;

esac

###############################################################################
# Ensure curl is available.
###############################################################################

if ! command -v curl >/dev/null 2>&1; then

    echo "INFO: curl not found. Installing..."

    $pkg_mgr install curl -y

    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to install curl."
        exit 1
    fi

fi

###############################################################################
# Build package download URL.
###############################################################################

download_url="https://www.tenable.com/downloads/api/v1/public/pages/nessus-agents/downloads/${download_id}/download?i_agree_to_tenable_license_agreement=true"

###############################################################################
# Output execution details.
###############################################################################

echo "OS Vendor:              ${current_os}"
echo "OS Version:             ${version_id}"
echo "Download ID:            ${download_id}"
echo "Expected MD5:           ${package_md5}"
echo "Package Manager:        ${pkg_mgr}"
echo "Current Agent Version:  ${cur_agent_version}"
echo "Target Agent Version:   ${expected_agent_version}"
echo "Download URL:           ${download_url}"

echo
echo "Starting upgrade process..."
echo

###############################################################################
# Download package.
###############################################################################

curl -fsSL "${download_url}" -o "${download_dir}/${package_name}"

if [ $? -ne 0 ]; then
    echo "ERROR: Package download failed."
    exit 1
fi

###############################################################################
# Verify package exists.
###############################################################################

if [ ! -f "${download_dir}/${package_name}" ]; then
    echo "ERROR: Downloaded package not found."
    exit 1
fi

# Full path of downloaded package.
new_nessus_agent="${download_dir}/${package_name}"

###############################################################################
# Validate package checksum.
###############################################################################

echo "Validating package checksum..."

md5_nessus_agent="$(md5sum "${new_nessus_agent}" | awk '{print $1}')"

if [ "$md5_nessus_agent" != "$package_md5" ]; then

    echo "ERROR: Package checksum validation failed."
    echo "Expected:   ${package_md5}"
    echo "Calculated: ${md5_nessus_agent}"

    exit 1

fi

echo "Checksum validation successful."

###############################################################################
# Install package.
###############################################################################

echo "Installing Nessus Agent ${expected_agent_version}..."

$pkg_mgr install "${new_nessus_agent}" -y

if [ $? -ne 0 ]; then
    echo "ERROR: Package installation failed."
    exit 1
fi

###############################################################################
# Restart Nessus Agent service.
###############################################################################

echo "Stopping Nessus Agent service..."
systemctl stop nessusagent >/dev/null 2>&1

sleep 5

echo "Starting Nessus Agent service..."
systemctl start nessusagent >/dev/null 2>&1

sleep 5

###############################################################################
# Validate installed version.
###############################################################################

new_agent_version="$($nessuscli -v | grep Nessus | awk '{print$4}')"

if [ "$new_agent_version" = "$expected_agent_version" ]; then

    echo "INFO: Nessus Agent successfully upgraded."
    echo "Installed version: ${new_agent_version}"
    rm -f "${new_nessus_agent}"

    exit 0

else

    echo "WARN: Upgrade completed but installed version differs from expected."
    echo "Expected: ${expected_agent_version}"
    echo "Installed: ${new_agent_version}"

    exit 1

fi