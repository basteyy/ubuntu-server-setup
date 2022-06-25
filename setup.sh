#!/bin/bash

set -e

function getCurrentDir() {
    local current_dir="${BASH_SOURCE%/*}"
    if [[ ! -d "${current_dir}" ]]; then current_dir="$PWD"; fi
    echo "${current_dir}"
}

function includeDependencies() {
    # shellcheck source=./setupLibrary.sh
    source "${current_dir}/setupLibrary.sh"
}

current_dir=$(getCurrentDir)
includeDependencies
output_file="output.log"

function main() {

  # Check Root
  if [[ $EUID -ne 0 ]]; then
     echo "This script must be run as root"
     exit 1
  fi

  # Update System?
  read -rp "Do you want to update the system (Recommended) [Y/N] " updateSystem

  if [[ $updateSystem == [nN] ]]; then
    echo "System not updated"
  elif [[ $updateSystem == [yY] ]]; then
    updateSystem
  else
    echo 'This is not a valid choice!'
    exit 1
  fi

  # Upgrade the system?
  read -rp "Do you want to upgrade the system (Recommended) [Y/N] " upgradeSystem

  if [[ $upgradeSystem == [nN] ]]; then
    echo "System not upgraded"
  elif [[ $upgradeSystem == [yY] ]]; then
    upgradeSystem
  else
    echo 'This is not a valid choice!'
    exit 1
  fi

  # Hostname
  read -rp "Input the hostname of the system [Required] " systemHostname

  # Validate domain name
  validate="^([a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]\.)+[a-zA-Z]{2,}$"

  # If user doesn't enter anything
  if [[ -z "$systemHostname" ]]; then
      echo "You must enter a domain"
  fi

  if [[ "$systemHostname" =~ $validate ]]; then
      updateHostname "${systemHostname}"
  else
      echo "Not valid $systemHostname name."
      exit 1
  fi

  # Set up webserver with nginx and lets encrypt?
  read -rp "Do you want to se tup the webserver (nginx, php, lets encrypt)? [Y/N]" webserver
  if [[ $webserver == [nN] ]]; then
    setupWebserver="n"
  elif [[ $webserver == [yY] ]]; then
    setupWebserver="y"

    #read -rp "Please select the ? [Y/N]" php_eight_two
    read -rp "Do you like to install PHP Version 8.1? [Y/N]" php_eight_one
    read -rp "Do you like to install PHP Version 8.0? [Y/N]" php_eight_null
    read -rp "Do you like to install PHP Version 7.4? [Y/N]" php_seven_four

  else
    echo 'This is not a valid choice!'
    exit 1
  fi

  # Create a new User?
  read -rp "Do you want to create a new non-root user? (Recommended) [Y/N] " createUser

  # Run setup functions
  trap cleanup EXIT SIGHUP SIGINT SIGTERM

  if [[ $createUser == [nN] ]]; then
      username=$(whoami)
      updateUserAccount "${username}"
  elif [[ $createUser == [yY] ]]; then
      read -rp "Enter the username of the new user account: " username
      addUserAccount "${username}"
  else
    echo 'This is not a valid choice!'
    exit 1
  fi

  read -rp $'Paste in the public SSH key for the new user:\n' sshKey
  echo 'Running setup script...'
  logTimestamp "${output_file}"

  exec 3>&1 >>"${output_file}" 2>&1

  disableSudoPassword "${username}"
  addSSHKey "${username}" "${sshKey}"
  changeSSHConfig
  setupUfw

  if [[ setupWebserver == [y] ]]; then
    installNginx
    installLetsEncrypt

    if [ [php_seven_four == [Yy]] || [php_eight_null == [Yy]] || [php_eight_one == [Yy]] ]; then
      installDefaultPhpThings
    fi

    ## Setup PHP
    if [ [php_eight_one == [Yy]] ]; then
      installPhpEightOne
    else
      echo 'PHP 8.1 is not installed'
    fi

    if [ [php_eight_null == [Yy]] ]; then
      installPhpEightNull
    else
      echo 'PHP 8.0 is not installed'
    fi

    if [ [php_seven_four == [Yy]] ]; then
      installPhpEightOne
    else
      echo 'PHP 7.4 is not installed'
    fi

    # Install composer in case a php version ins installed
    if [ [php_seven_four == [Yy]] || [php_eight_null == [Yy]] || [php_eight_one == [Yy]] ]; then
      installComposer
    else
      echo 'Composer is not installed, because no php version ins selected'
    fi

  fi

  if ! hasSwap; then
      setupSwap
  fi

  setupTimezone

  echo "Configuring System Time... " >&3
  configureNTP

  sudo service ssh restart

  cleanup

  echo "Setup Done! Log file is located at ${output_file}" >&3
}

function setupSwap() {
    createSwap
    mountSwap
    tweakSwapSettings "10" "50"
    saveSwapSettings "10" "50"
}

function hasSwap() {
    [[ "$(sudo swapon -s)" == *"/swapfile"* ]]
}

function cleanup() {
    if [[ -f "/etc/sudoers.bak" ]]; then
        revertSudoers
    fi
}

function logTimestamp() {
    local filename=${1}
    {
        echo "===================" 
        echo "Log generated on $(date)"
        echo "==================="
    } >>"${filename}" 2>&1
}

function setupTimezone() {
    echo -ne "Enter the timezone for the server (Default is 'Asia/Singapore'):\n" >&3
    read -r timezone
    if [ -z "${timezone}" ]; then
        timezone="Asia/Singapore"
    fi
    setTimezone "${timezone}"
    echo "Timezone is set to $(cat /etc/timezone)" >&3
}

main
