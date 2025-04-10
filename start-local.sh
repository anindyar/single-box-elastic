#!/bin/bash
# --------------------------------------------------------
# Run Elasticsearch and Kibana for local testing
# Note: do not use this script in a production environment
# --------------------------------------------------------
#
# Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
# or more contributor license agreements. See the NOTICE file distributed with
# this work for additional information regarding copyright
# ownership. Elasticsearch B.V. licenses this file to you under
# the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
set -eu

fleet_enabled=false

parse_args() {
  # Parse the script parameters
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -v)
        # Check that there is another argument for the version
        if [ $# -lt 2 ]; then
          echo "Error: -v requires a version value (eg. -v 8.17.0)"
          exit 1
        fi
        es_version="$2"
        shift 2
        ;;

      -esonly)
        esonly=true
        shift
        ;;

      -fleet)
        fleet_enabled=true
        shift
        ;;

      --)
        # End of options; shift and exit the loop
        shift
        break
        ;;

      -*)
        # Unknown or unsupported option
        echo "Error: Unknown option '$1'"
        exit 1
        ;;

      *)
        # We've hit a non-option argument; stop parsing options
        break
        ;;
    esac
  done
}

startup() {
  echo
  echo '  ______ _           _   _      '
  echo ' |  ____| |         | | (_)     '
  echo ' | |__  | | __ _ ___| |_ _  ___ '
  echo ' |  __| | |/ _` / __| __| |/ __|'
  echo ' | |____| | (_| \__ \ |_| | (__ '
  echo ' |______|_|\__,_|___/\__|_|\___|'
  echo '-------------------------------------------------'
  echo '🚀 Run Elasticsearch and Kibana for local testing'
  if [ "<span class="math-inline">fleet\_enabled" \= true \]; then
echo '\+ Fleet Server'
fi
echo '\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-'
echo
echo 'ℹ️  Do not use this script in a production environment'
echo
\# Version
version\="0\.8\.1"
\# Folder name for the installation
installation\_folder\="elastic\-start\-local"
\# API key name for Elasticsearch
api\_key\_name\="elastic\-start\-local"
\# Name of the error log
error\_log\="error\-start\-local\.log"
\# Minimum version for docker\-compose
min\_docker\_compose\="1\.29\.0"
\# Elasticsearch container name
elasticsearch\_container\_name\="es\-local\-dev"
\# Kibana container name
kibana\_container\_name\="kibana\-local\-dev"
\# Fleet Server container name
fleet\_server\_container\_name\="fleet\-server\-local"
\# Minimum disk space required for docker images \+ services \(in GB\)
min\_disk\_space\_required\=5
\}
\# Check for ARM64 architecture
is\_arm64\(\) \{
arch\="</span>(uname -m)"
  if [ "$arch" = "arm64" ] || [ "$arch" = "aarch64" ]; then
    return 0 # Return 0 (true)
  else
    return 1 # Return 1 (false)
  fi
}

# Alternative to sort -V, which is not available in BSD-based systems (e.g., macOS)
version_sort() {
  awk -F'.' '
  {
      printf("%d %d %d %s\n", $1, $2, $3, $0)
  }' | sort -n -k1,1 -k2,2 -k3,3 | awk '{print $4}'
}

# Function to check if the format is a valid semantic version (major.minor.patch)
is_valid_version() {
  echo "<span class="math-inline">1" \| grep \-E \-q '^\[0\-9\]\+\\\.\[0\-9\]\+\\\.\[0\-9\]\+</span>'
}

# Get the latest stable version of Elasticsearch
# Note: It removes all the beta or candidate releases from the list
# but includes the GA releases (e.g. new major)
get_latest_version() {
  versions="<span class="math-inline">\(curl \-s "https\://artifacts\.elastic\.co/releases/stack\.json"\)"
latest\_version\=</span>(echo "$versions" | awk -F'"' '/"version": *"/ {print <span class="math-inline">4\}' \| grep \-E '^\[0\-9\]\+\\\.\[0\-9\]\+\\\.\[0\-9\]\+\( GA\)?</span>' | version_sort | tail -n 1)
  # Remove the GA prefix from the version, if present
  latest_version=$(echo "<span class="math-inline">latest\_version" \| awk '\{ gsub\(/ GA</span>/, "", $0); print }')

  # Check if the latest version is empty
  if [ -z "$latest_version" ]; then
    echo "Error: the latest Elasticsearch version is empty"
    exit 1
  fi
  # Check if the latest version is valid
  if ! is_valid_version "$latest_version"; then
    echo "Error: {$latest_version} is not a valid Elasticsearch stable version"
    exit 1
  fi

  echo "<span class="math-inline">latest\_version"
\}
\# Detect if running on LXC container
detect\_lxc\(\) \{
\# Check /proc/1/environ for LXC container identifier
if grep \-qa "container\=lxc" /proc/1/environ 2\>/dev/null; then
return 0
fi
\# Check /proc/self/cgroup for LXC references
if grep \-q "lxc" /proc/self/cgroup 2\>/dev/null; then
return 0
fi
\# Check for LXC in /sys/fs/cgroup
if grep \-q "lxc" /sys/fs/cgroup/\* 2\>/dev/null; then
return 0
fi
\# Use systemd\-detect\-virt if available
if command \-v systemd\-detect\-virt \>/dev/null 2\>&1; then
if \[ "</span>(systemd-detect-virt)" = "lxc" ]; then
        return 0
      fi
    fi
    return 1
}

# Get linux distribution
get_os_info() {
  if [ -f /etc/os-release ]; then
      # Most modern Linux distributions have this file
      . /etc/os-release
      echo "Distribution: $NAME"
      echo "Version: $VERSION"
  elif [ -f /etc/lsb-release ]; then
      # For older distributions using LSB (Linux Standard Base)
      . /etc/lsb-release
      echo "Distribution: $DISTRIB_ID"
      echo "Version: $DISTRIB_RELEASE"
  elif [ -f /etc/debian_version ]; then
      # For Debian-based distributions without os-release or lsb-release
      echo "Distribution: Debian"
      echo "Version: $(cat /etc/debian_version)"
  elif [ -f /etc/redhat-release ]; then
      # For Red Hat-based distributions
      echo "Distribution: <span class="math-inline">\(cat /etc/redhat\-release\)"
elif \[ \-n "</span>{OSTYPE+x}" ]; then
    if [ "${OSTYPE#darwin}" != "$OSTYPE" ]; then
        # macOS detection
        echo "Distribution: macOS"
        echo "Version: $(sw_vers -productVersion)"
    elif [ "$OSTYPE" = "cygwin" ] || [ "$OSTYPE" = "msys" ] || [ "$OSTYPE" = "win32" ]; then
        # Windows detection in environments like Git Bash, Cygwin, or MinGW
        echo "Distribution: Windows"
        echo "Version: $(cmd.exe /c ver | tr -d '\r')"
    elif [ "$OSTYPE" = "linux-gnu" ] && uname -r | grep -q "Microsoft"; then
        # Windows Subsystem for Linux (WSL) detection
        echo "Distribution: Windows (WSL)"
        echo "Version: $(uname -r)"
    fi
  else
      echo "Unknown operating system"
  fi
  if [ -f /proc/version ]; then
    # Check if running on WSL2 or WSL1 for Microsoft
    if grep -q "WSL2" /proc/version; then
      echo "Running on WSL2"
    elif grep -q "microsoft" /proc/version; then
      echo "Running on WSL1"
    fi
  fi
}

# Check if a command exists
available() { command -v "$1" >/dev/null; }

# Revert the status, removing containers, volumes, network and folder
cleanup() {
  if [ -d "./../$folder_to_clean" ]; then
    if [ -f "docker-compose.yml" ]; then
      $docker_clean >/dev/null 2>&1
      <span class="math-inline">docker\_remove\_volumes \>/dev/null 2\>&1
fi
cd \.\.
rm \-rf "</span>{folder_to_clean}"
  fi
}

# Generate the error log
# parameter 1: error message
# parameter 2: the container names to retrieve, separated by comma
generate_error_log() {
  msg="$1"
  docker_services="$2"
  error_file="$error_log"
  if [ -d "./../$folder_to_clean" ]; then
    error_file="./../<span class="math-inline">error\_log"
fi
if \[ \-n "</span>{msg}" ]; then
    echo "${msg}" > "$error_file"
  fi
  {
    echo "Start-local version: ${version}"
    echo "Docker engine: $(docker --version)"
    echo "Docker compose: ${docker_version}"
    get_os_info
  } >> "$error_file"
  for service in $docker_services; do
    echo "-- Logs of service ${service}:" >> "<span class="math-inline">error\_file"
docker logs "</span>{service}" >> "$error_file" 2> /dev/null
  done
  echo "An error log has been generated in ${error_log} file."
  echo "If you need assistance, open an issue at https://github.com/elastic/start-local/issues"
}

# Compare versions
# parameter 1: version to compare
# parameter 2: version to compare
compare_versions() {
  v1=$1
  v2=$2

  original_ifs="$IFS"
  IFS='.'
  # shellcheck disable=SC2086
  set -- <span class="math-inline">v1; v1\_major\=</span>{1:-0}; v1_minor=<span class="math-inline">\{2\:\-0\}; v1\_patch\=</span>{3:-0}
  IFS='.'
  # shellcheck disable=SC2086
  set -- <span class="math-inline">v2; v2\_major\=</span>{1:-0}; v2_minor=<span class="math-inline">\{2\:\-0\}; v2\_patch\=</span>{3:-0}
  IFS="$original_ifs"

  [ "$v1_major" -lt "$v2_major" ] && echo
