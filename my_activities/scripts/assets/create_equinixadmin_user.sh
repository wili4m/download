#!/bin/bash

# Description: This script creates the equinixadmin user with sudo privileges.
# Script by: Wiliam de Freitas <wdefreitas@equinix>
# Date: Jan 2026

# default username:
username='equinixadmin'

# user password: to generate the hashed, use the following command:
# mkpasswd -m sha-512 'Senha'
password='hash sha512 da senha'

# Identify sudo group:
if grep ^%wheel /etc/sudoers > /dev/null ; then

   # wheel group is used in RHEL/CentOS
    sudo_group="wheel"

elif grep ^%sudo /etc/sudoers > /dev/null ; then

   # sudo group is used in Debian/Ubuntu
    sudo_group="sudo"

else

   # default sudo group not found
    echo "[Error]: Unable to identify the sudo group."
    exit 1

fi

# Verify if user already exists:
if grep $username /etc/passwd > /dev/null ; then

   # Check if user is already in sudo group
   if id $username | grep $sudo_group > /dev/null ; then

      # User already exists and is in sudo group
      echo "[Info]: Username "$username" already exists and is already a member of the "$sudo_group" group."
      exit 1

   else
      
      # Add existing user to sudo group
      usermod -a -G $sudo_group $username

   fi

else

   # Create the user and add to sudo group:
    useradd $username -d /home/${username} -s /bin/bash -G $sudo_group

   # Check if user creation was successful:
    case $? in

      # User creation successful:
      0) echo "[Success]: User $username has been successfuly created";
         echo -e "$(id $username)\n";;

      # User creation failed:
      *) echo "[Error]: Failed to create user $username"; exit 1;;
    esac

    # Set user password:
    echo "${username}:${password}" | chpasswd
    usermod --password $password $username

fi