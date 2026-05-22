#!/bin/bash

database="/opt/gwcli/db/gwcli.db"

if [[ $1 == "db" ]]; then

    echo -e "\nSelect the option\n"

    echo "1) Update servers list"
    echo -e "2) Update users credentials\n"

    read -p "Option: " option

    case $option in
        1)
            echo ""
            sqlite3 $database "SELECT * from servers"
            echo ""

            echo "Inform the number (ID) of the server you want to update:"
            read -p "Server ID: " server_id

            if sqlite3 $database "SELECT * from servers WHERE id = $server_id" > /dev/null 2>&1; then

                echo -e "\nWhich value do you want to update?"
                echo "1) FQDN"
                echo "2) Hostname"
                echo -e "3) AD\n"
                read -p "Option: " update_option

                case $update_option in
                    1)
                        current_value=$(sqlite3 $database "SELECT fqdn from servers WHERE id = $server_id")
                        echo -e "\nCurrent value for column FQDN: $current_value"
                        ;;
                    2)
                        current_value=$(sqlite3 $database "SELECT hostname from servers WHERE id = $server_id")
                        echo -e "\nCurrent value for column Hostname: $current_value"
                        ;;
                    3)
                        current_value=$(sqlite3 $database "SELECT ad from servers WHERE id = $server_id")
                        echo -e "\nCurrent value for column AD: $current_value"
                        ;;
                    *)
                        echo "Invalid option. Please select 1, 2 or 3."
                        exit 1
                        ;;
                esac

                echo -e "\nInform the new value:"
                read -p "New value: " new_value

                echo -e "\nConfirmation:"

                echo "Server ID: $server_id"
                echo "Current Value: $current_value"
                echo "New AD: $new_value"

                echo -e "\nIs this information correct? (y/n)"
                read -p "Option: " confirmation

                case $confirmation in
                    y|Y)
                        case $update_option in
                            1)
                                sqlite3 $database "UPDATE servers SET fqdn = '$new_value' WHERE id = $server_id"
                                echo -e "\nFQDN updated successfully."
                                ;;
                            2)
                                sqlite3 $database "UPDATE servers SET hostname = '$new_value' WHERE id = $server_id"
                                echo -e "\nHostname updated successfully."
                                ;;
                            3)
                                sqlite3 $database "UPDATE servers SET ad = '$new_value' WHERE id = $server_id"
                                echo -e "\nAD updated successfully."
                                ;;
                        esac
                        ;;
                    n|N)
                        echo -e "\nUpdate cancelled."
                        exit 0
                        ;;
                    *)
                        echo -e "\nInvalid option. Please select y or n."
                        exit 1
                        ;;
                esac

            else
                echo -e "\nServer with ID $server_id not found. Exiting."
                exit 1
            fi
            # Command to update servers list goes here
            ;;
        2)
            echo -e "\nUpdating users credentials..."
            # Command to update users credentials goes here
            ;;
        *)
            echo -e "\nInvalid option. Please select 1 or 2."
            exit 1
            ;;
     esac

fi