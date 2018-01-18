#!/bin/bash

unknown_os ()
{
  echo "Unfortunately, your operating system distribution and version are not supported by this script."
  exit 1
}

curl_check ()
{
  echo "Checking for curl..."
  if command -v curl > /dev/null; then
    echo "Detected curl..."
  else
    echo "Installing curl..."
    apt-get install -q -y curl
  fi
}

lsb_release_check ()
{
  echo "Checking for lsb-release..."
  if command -v lsb_release > /dev/null; then
    echo "Detected lsb-release..."
  else
    echo "Installing lsb-release..."
    apt-get update
    apt-get install -q -y lsb-release
  fi
}

install_debian_keyring ()
{
  if [ "${os}" = "debian" ]; then
    echo "Installing debian-archive-keyring which is needed for installing "
    echo "apt-transport-https on many Debian systems."
    apt-get install -y debian-archive-keyring &> /dev/null
  fi
}

check_supported_os() {
  if [[ ! ( ( ( "${os}" = "debian" ) && ( ( "${dist}" = "jessie" ) || ( "${dist}" = "stretch" ) ) ) || ( ( ( "${os}" = "ubuntu" ) && ( ( "${dist}" = "xenial" ) || ( "${dist}" = "zesty" ) ) ) ) ) ]]; then
    unknown_os
  fi
}

detect_os ()
{
  if [[ ( -z "${os}" ) && ( -z "${dist}" ) ]]; then
    lsb_release_check
    # some systems dont have lsb-release yet have the lsb_release binary and
    # vice-versa
    if [ `which lsb_release 2>/dev/null` ]; then
      dist=`lsb_release -c | cut -f2`
      os=`lsb_release -i | cut -f2 | awk '{ print tolower($1) }'`
    
    elif [ -e /etc/lsb-release ]; then
      . /etc/lsb-release

      if [ "${ID}" = "raspbian" ]; then
        os=${ID}
        dist=`cut --delimiter='.' -f1 /etc/debian_version`
      else
        os=${DISTRIB_ID}
        dist=${DISTRIB_CODENAME}

        if [ -z "$dist" ]; then
          dist=${DISTRIB_RELEASE}
        fi
      fi

    elif [ -e /etc/debian_version ]; then
      # some Debians have jessie/sid in their /etc/debian_version
      # while others have '6.0.7'
      os=`cat /etc/issue | head -1 | awk '{ print tolower($1) }'`
      if grep -q '/' /etc/debian_version; then
        dist=`cut --delimiter='/' -f1 /etc/debian_version`
      else
        dist=`cut --delimiter='.' -f1 /etc/debian_version`
      fi

    else
      unknown_os
    fi
  fi

  if [ -z "$dist" ]; then
    unknown_os
  fi

  # remove whitespace from OS and dist name
  os="${os// /}"
  dist="${dist// /}"

  echo "Detected operating system as $os/$dist."
}

main ()
{
  detect_os
  check_supported_os
  curl_check

  # Need to first run apt-get update so that apt-transport-https can be
  # installed
  echo -n "Running apt-get update... "
  apt-get update &> /dev/null
  echo "done."

  # Install the debian-archive-keyring package on debian systems so that
  # apt-transport-https can be installed next
  install_debian_keyring

  echo -n "Installing apt-transport-https... "
  apt-get install -y apt-transport-https &> /dev/null
  echo "done."

  gpg_key_url="https://package.cryptoguru.org/${os}/gpgkey.asc"
  apt_source_path="/etc/apt/sources.list.d/cryptoguru.list"
  apt_preferences_path="/etc/apt/preferences.d/cryptoguru.pref"
  
  echo -n "Installing $apt_source_path... "
  # create an apt config file for this repository
  echo "
deb https://package.cryptoguru.org/${os}/${dist} ${dist} main
" > $apt_source_path
  echo "done."
  
  echo -n "Setting Top Priority $apt_preferences_path..."
  echo "
Package: *
Pin: origin package.cryptoguru.org
Pin-Priority: 1002
" > $apt_preferences_path
  echo "done."
  
  if [[ "${os}" = "debian" && "${dist}" = "jessie" ]]; then
    $(apt-cache -t ${dist}-backports search . &> /dev/null)
    REPO_CHECK=$?
    if [[ $REPO_CHECK -ne 0 ]]; then
      echo -n "Installing ${dist}-backports... "
      echo "
deb http://ftp.debian.org/debian ${dist}-backports main
" > /etc/apt/sources.list.d/backports.list
      echo "done."
    fi
    echo -n "Setting Top Priority for ca-certificates-java in ${dist}-backports..."
    echo "
Package: ca-certificates-java
Pin: release a=jessie-backports
Pin-Priority: 1001
" > $apt_preferences_path
    echo "done."
  fi

  echo -n "Importing gpg key... "
  # import the gpg key
  curl -L "${gpg_key_url}" 2> /dev/null | apt-key add - &>/dev/null
  # apt-key adv --keyserver keyserver.ubuntu.com --recv-keys C2AC0FF46676DB0C
  echo "done."

  echo -n "Running apt-get update... "
  # update apt on this system
  apt-get update &> /dev/null
  echo "done."

  echo
  echo "The repository is setup! You can now install packages."
}

main

