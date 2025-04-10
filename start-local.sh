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
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
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
  echo '  ______ _          _  _      '
  echo ' |  ____| |        | | (_)     '
  echo ' | |__  | | __ _ ___| |_ _  ___ '
  echo ' |  __| | |/ _` / __| __| |/ __|'
  echo ' | |____| | (_| \__ \ |_| | (__ '
  echo ' |______|_|\__,_|___/\__|_|\___|'
  echo '-------------------------------------------------'
  echo '🚀 Run Elasticsearch and Kibana for local testing'
  if [ "<span class="math-inline">fleet\_enabled" \= true \]; then
echo '\+ Fleet Server'
fi
echo '\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-'
echo
echo 'ℹ️  Do not use this script in a production environment'
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

  [ "$v1_major" -lt "$v2_major" ] && echo "lt" && return 0
  [ "$v1_major" -gt "$v2_major" ] && echo "gt" && return 0

  [ "$v1_minor" -lt "$v2_minor" ] && echo "lt" && return 0
  [ "$v1_minor" -gt "$v2_minor" ] && echo "gt" && return 0

  [ "$v1_patch" -lt "$v1_patch" ] && echo "lt" && return 0
  [ "$v1_patch" -gt "<span class="math-inline">v1\_patch" \] && echo "gt" && return 0
echo "eq"
\}
\# Wait for availability of Kibana
\# parameter\: timeout in seconds
wait\_for\_kibana\(\) \{
timeout\="</span>{1:-60}"
  echo "- Waiting for Kibana to be ready"
  echo
  start_time="<span class="math-inline">\(date \+%s\)"
until curl \-s \-I http\://localhost\:5601 \| grep \-q 'HTTP/1\.1 302 Found'; do
elapsed\_time\="</span>(($(date +%s) - start_time))"
    if [ "$elapsed_time" -ge "$timeout" ]; then
      error_msg="Error: Kibana timeout of ${timeout} sec"
      echo "$error_msg"
      if [ "<span class="math-inline">fleet\_enabled" \= true \]; then
generate\_error\_log "</span>{error_msg}" "${elasticsearch_container_name} ${kibana_container_name} <span class="math-inline">\{fleet\_server\_container\_name\} kibana\_settings"
else
generate\_error\_log "</span>{error_msg}" "${elasticsearch_container_name} <span class="math-inline">\{kibana\_container\_name\} kibana\_settings"
fi
cleanup
exit 1
fi
sleep 2
done
\}
\# Generates a random password with letters and numbers
\# parameter\: size of the password \(default is 8 characters\)
random\_password\(\) \{
LENGTH\="</span>{1:-8}"
  LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "${LENGTH}"
}

# Create an API key for Elasticsearch
# parameter 1: the Elasticsearch password
# parameter 2: name of the API key to generate
create_api_key() {
  es_password=$1
  name=<span class="math-inline">2
response\="</span>(curl -s -u "elastic:<span class="math-inline">\{es\_password\}" \-X POST http\://localhost\:9200/\_security/api\_key \-d "\{\\"name\\"\: \\"</span>{name}\"}" -H "Content-Type: application/json")"
  if [ -z "<span class="math-inline">response" \]; then
echo ""
else
api\_key\="</span>(echo "$response" | grep -Eo '"encoded":"[A-Za-z0-9+/=]+' | grep -Eo '[A-Za-z0-9+/=]+' | tail -n 1)"
    echo "$api_key"
  fi
}

# Check if a container is runnning
# parameter: the name of the container
check_container_running() {
  container_name=<span class="math-inline">1
containers\="</span>(docker ps --format '{{.Names}}')"
  if echo "<span class="math-inline">containers" \| grep \-q "^</span>{container_name}$"; then
    echo "The docker container '$container_name' is already running!"
    echo "You can have only one running at time."
    echo "To stop the container run the following command:"
    echo
    echo "docker stop $container_name"
    exit 1
  fi
}

# Check the available disk space in GB
# parameter: required size in GB
check_disk_space_gb() {
  required=<span class="math-inline">1
available\_gb\=</span>(($(df -k / | awk 'NR==2 {print $4}') / 1024 / 1024))
  if [ "$available_gb" -lt "$required" ]; then
    echo "Error: only ${available_gb} GB of disk space available; ${required} GB required for the installation"
    exit 1
  fi
}

check_requirements() {
  # Check the requirements
  check_disk_space_gb ${min_disk_space_required}
  if ! available "curl"; then
    echo "Error: curl command is required"
    echo "You can install it from https://curl.se/download.html."
    exit 1
  fi
  if ! available "grep"; then
    echo "Error: grep command is required"
    echo "You can install it from https://www.gnu.org/software/grep/."
    exit 1
  fi
  # Check for jq if fleet is enabled
  if [ "<span class="math-inline">fleet\_enabled" \= true \] && \! available "jq"; then
echo "Error\: jq command is required to setup Fleet Server"
echo "You can install it from https\://stedolan\.github\.io/jq/download/"
exit 1
fi
need\_wait\_for\_kibana\=true
\# Check for "docker compose" or "docker\-compose"
set \+e
if \! docker compose \>/dev/null 2\>&1; then
if \! available "docker\-compose"; then
if \! available "docker"; then
echo "Error\: docker command is required"
echo "You can install it from https\://docs\.docker\.com/engine/install/\."
exit 1
fi
echo "Error\: docker compose is required"
echo "You can install it from https\://docs\.docker\.com/compose/install/"
exit 1
fi
docker\="docker\-compose up \-d"
docker\_stop\="docker\-compose stop"
docker\_clean\="docker\-compose rm \-fsv"
docker\_remove\_volumes\="docker\-compose down \-v"
docker\_version\=</span>(docker-compose --version | head -n 1 | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+')
    if [ "$(compare_versions "$docker_version" "$min_docker_compose")" = "lt" ]; then
      echo "Unfortunately we don't support docker compose ${docker_version}. The minimum required version is <span class="math-inline">min\_docker\_compose\."
echo "You can migrate you docker compose from https\://docs\.docker\.com/compose/migrate/"
cleanup
exit 1
fi
else
docker\_stop\="docker compose stop"
docker\_clean\="docker compose rm \-fsv"
docker\_remove\_volumes\="docker compose down \-v"
docker\_version\=</span>(docker compose version | head -n 1 | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+')
    # --wait option has been introduced in 2.1.1+
    if [ "$(compare_versions "$docker_version" "2.1.0")" = "gt" ]; then
      docker="docker compose up --wait"
      need_wait_for_kibana=false
    else
      docker="docker compose up -d"
    fi
  fi
  set -e
}

check_installation_folder() {
  # Check if $installation_folder exists
  folder=$installation_folder
  if [ -d "<span class="math-inline">folder" \]; then
if \[ \-n "</span>(ls -A "<span class="math-inline">folder"\)" \]; then
echo "It seems you have already a start\-local installation in '</span>{folder}'."
      if [ -f "$folder/uninstall.sh" ]; then
        echo "I cannot proceed unless you uninstall it, using the following command:"
        echo "cd $folder && ./uninstall.sh"
      else
        echo "I did not find the uninstall.sh file, you need to proceed manually."
        if [ -f "$folder/docker-compose.yml" ] && [ -f "$folder/.env" ]; then
          echo "Execute the following commands:"
          echo "cd $folder"
          echo "$docker_clean"
          echo "$docker_remove_volumes"
          echo "cd .."
          echo "rm -rf $folder"
        fi
      fi
      exit 1
    fi
  fi
}

check_docker_services() {
  # Check for docker containers running
  check_container_running "$elasticsearch_container_name"
  check_container_running "$kibana_container_name"
  check_container_running "kibana_settings"
  if [ "$fleet_enabled" = true ]; then
    check_container_running "$fleet_server_container_name"
  fi
}

create_installation_folder() {
  # If $folder already exists, it is empty, see above
  if [ ! -d "$folder" ]; then
    mkdir $folder
  fi
  cd $folder
  folder_to_clean=<span class="math-inline">folder
\}
generate\_passwords\(\) \{
\# Generate random passwords
es\_password\="</span>(random_password)"
  if  [ -z "<span class="math-inline">\{esonly\:\-\}" \]; then
kibana\_password\="</span>(random_password)"
    kibana_encryption_key="<span class="math-inline">\(random\_password 32\)"
fi
\}
choose\_es\_version\(\) \{
if \[ \-z "</span>{es_version:-}" ]; then
    # Get the latest Elasticsearch version
    es_version="$(get_latest_version)"
  fi
}

create_env_file() {
  # Create the .env file
  cat > .env <<- EOM
ES_LOCAL_VERSION=$es_version
ES_LOCAL_CONTAINER_NAME=$elasticsearch_container_name
ES_LOCAL_PASSWORD=<span class="math-inline">es\_password
ES\_LOCAL\_PORT\=9200
ES\_LOCAL\_URL\=http\://localhost\:\\$\{ES\_LOCAL\_PORT\}
ES\_LOCAL\_HEAP\_INIT\=128m
ES\_LOCAL\_HEAP\_MAX\=2g
ES\_LOCAL\_DISK\_SPACE\_REQUIRED\=1gb
EOM
if  \[ \-z "</span>{esonly:-}" ]; then
    cat >> .env <<- EOM
KIBANA_LOCAL_CONTAINER_NAME=$kibana_container_name
KIBANA_LOCAL_PORT=5601
KIBANA_LOCAL_PASSWORD=$kibana_password
KIBANA_ENCRYPTION_KEY=$kibana_encryption_key
EOM
  fi

  if [ "$fleet_enabled" = true ]; then
    cat >> .env <<- EOM
FLEET_SERVER_CONTAINER_NAME=<span class="math-inline">fleet\_server\_container\_name
FLEET\_SERVER\_PORT\=8220
EOM
fi
\}
\# Create the start script \(start\.sh\)
\# including the license update if trial expired
create\_start\_file\(\) \{
today\=</span>(date +%s)
  expire=<span class="math-inline">\(\(today \+ 3600\*24\*30\)\)
cat \> start\.sh <<\-'EOM'
\#\!/bin/sh
\# Start script for start\-local
\# More information\: https\://github\.com/elastic/start\-local
set \-eu
SCRIPT\_DIR\="</span>(cd "$(dirname "<span class="math-inline">0"\)" && pwd\)"
cd "</span>{SCRIPT_DIR}"
today=<span class="math-inline">\(date \+%s\)
\. \./\.env
\# Check disk space
available\_gb\=</span>(($(df -k / | awk 'NR==2 {print <span class="math-inline">4\}'\) / 1024 / 1024\)\)
required\=</span>(echo "${ES_LOCAL_DISK_SPACE_REQUIRED}" | grep -Eo '[0-9]+')
if [ "$available_gb" -lt "$required" ]; then
  echo "----------------------------------------------------------------------------"
  echo "WARNING: Disk space is below the ${required} GB limit. Elasticsearch will be"
  echo "executed in read-only mode. Please free up disk space to resolve this issue."
  echo "----------------------------------------------------------------------------"
  echo "Press ENTER to confirm."
  read -r
fi
EOM
  if [ "<span class="math-inline">need\_wait\_for\_kibana" \= true \]; then
cat \>\> start\.sh <<\-'EOM'
wait\_for\_kibana\(\) \{
local timeout\="</span>{1:-60}"
  echo "- Waiting for Kibana to be ready"
  echo
  local start_time="<span class="math-inline">\(date \+%s\)"
until curl \-s \-I http\://localhost\:5601 \| grep \-q 'HTTP/1\.1 302 Found'; do
elapsed\_time\="</span>(($(date +%s) - start_time))"
    if [ "$elapsed_time" -ge "$timeout" ]; then
      echo "Error: Kibana timeout of <span class="math-inline">\{timeout\} sec"
exit 1
fi
sleep 2
done
\}
EOM
fi
cat \>\> start\.sh <<\- EOM
if \[ \-z "\\</span>{ES_LOCAL_LICENSE:-}" ] && [ "\$today" -gt $expire ]; then
  echo "---------------------------------------------------------------------"
  echo "The one-month trial period has expired. You can continue using the"
  echo "Free and open Basic license or request to extend the trial for"
  echo "another 30 days using this form:"
  echo "https://www.elastic.co/trialextension"
  echo "---------------------------------------------------------------------"
  echo "For more info about the license: https://www.elastic.co/subscriptions"
  echo
  echo "Updating the license..."
  <span class="math-inline">docker elasticsearch \>/dev/null 2\>&1
result\=\\$\(curl \-s \-X POST "\\$\{ES\_LOCAL\_URL\}/\_license/start\_basic?acknowledge\=true" \-H "Authorization\: ApiKey \\$\{ES\_LOCAL\_API\_KEY\}" \-o /dev/null \-w '%\{http\_code\}\\n'\)
if \[ "\\$result" \= "200" \]; then
echo "✅ Basic license successfully installed"
echo "ES\_LOCAL\_LICENSE\=basic" \>\> \.env
else
echo "Error\: I cannot update the license"
result\=\\$\(curl \-s \-X GET "\\$\{ES\_LOCAL\_URL\}" \-H "Authorization\: ApiKey \\</span>{ES_LOCAL_API_KEY}" -o /dev/null -w '%{http_code}\n')
    if [ "\$result" != "200" ]; then
      echo "Elasticsearch is not running."
    fi
    exit 1
  fi
  echo
fi
$docker
EOM

  if [ "<span class="math-inline">need\_wait\_for\_kibana" \= true \]; then
cat \>\> start\.sh <<\-'EOM'
wait\_for\_kibana 120
EOM
fi
chmod \+x start\.sh
\}
\# Create the stop script \(stop\.sh\)
create\_stop\_file\(\) \{
cat \> stop\.sh <<\-'EOM'
\#\!/bin/sh
\# Stop script for start\-local
\# More information\: https\://github\.com/elastic/start\-local
set \-eu
SCRIPT\_DIR\="</span>(cd "$(dirname "<span class="math-inline">0"\)" && pwd\)"
cd "</span>{SCRIPT_DIR}"
EOM

  cat >> stop.sh <<- EOM
<span class="math-inline">docker\_stop
EOM
chmod \+x stop\.sh
\}
\# Create the uninstall script \(uninstall\.sh\)
create\_uninstall\_file\(\) \{
cat \> uninstall\.sh <<\-'EOM'
\#\!/bin/sh
\# Uninstall script for start\-local
\# More information\: https\://github\.com/elastic/start\-local
set \-eu
SCRIPT\_DIR\="</span>(cd "$(dirname "$0")" && pwd)"

ask_confirmation() {
    echo "Do you want to continue? (yes/no)"
    read -r answer
    case "<span class="math-inline">answer" in
yes\|y\|Y\|Yes\|YES\)
return 0  \# true
;;
no\|n\|N\|No\|NO\)
return 1  \# false
;;
\*\)
echo "Please answer yes or no\."
ask\_confirmation  \# Ask again if the input is invalid
;;
esac
\}
cd "</span>{SCRIPT_DIR}"
if [ ! -e "docker-compose.yml" ]; then
  echo "Error: I cannot find the docker-compose.yml file"
  echo "I cannot uninstall start-local."
fi
if [ ! -e ".env" ]; then
  echo "Error: I cannot find the .env file"
  echo "I cannot uninstall start-local."
fi
echo "This script will uninstall start-local."
echo "All data will be deleted and cannot be recovered."
if ask_confirmation; then
EOM

  cat >> uninstall.sh <<- EOM
  $docker_clean
  <span class="math-inline">docker\_remove\_volumes
rm docker\-compose\.yml \.env uninstall\.sh start\.sh stop\.sh
echo "Start\-local successfully removed"
fi
EOM
chmod \+x uninstall\.sh
\}
create\_docker\_compose\_file\(\) \{
\# Create the docker\-compose\-yml file
cat \> docker\-compose\.yml <<\-'EOM'
services\:
elasticsearch\:
image\: docker\.elastic\.co/elasticsearch/elasticsearch\:</span>{ES_LOCAL_VERSION}
    container_name: <span class="math-inline">\{ES\_LOCAL\_CONTAINER\_NAME\}
volumes\:
\- dev\-elasticsearch\:/usr/share/elasticsearch/data
ports\:
\- 127\.0\.0\.1\:</span>{ES_LOCAL_PORT}:9200
    environment:
      - discovery.type=single-node
      - ELASTIC_PASSWORD=<span class="math-inline">\{ES\_LOCAL\_PASSWORD\}
\- xpack\.security\.enabled\=true
\- xpack\.security\.http\.ssl\.enabled\=false
\- xpack\.license\.self\_generated\.type\=trial
\- xpack\.ml\.use\_auto\_machine\_memory\_percent\=true
\- ES\_JAVA\_OPTS\=\-Xms</span>{ES_LOCAL_HEAP_INIT} -Xmx${ES_LOCAL_HEAP_MAX}
      - cluster.routing.allocation.disk.watermark.low=<span class="math-inline">\{ES\_LOCAL\_DISK\_SPACE\_REQUIRED\}
\- cluster\.routing\.allocation\.disk\.watermark\.high\=</span>{ES_LOCAL_DISK_SPACE_REQUIRED}
      - cluster.routing.allocation.disk.watermark.flood_stage=<span class="math-inline">\{ES\_LOCAL\_DISK\_SPACE\_REQUIRED\}
EOM
\# Fix for JDK AArch64 issue, see https\://bugs\.openjdk\.org/browse/JDK\-8345296
if is\_arm64; then
cat \>\> docker\-compose\.yml <<\-'EOM'
\- "\_JAVA\_OPTIONS\=\-XX\:UseSVE\=0"
EOM
fi
\# Fix for OCI issue on LXC, see https\://github\.com/elastic/start\-local/issues/27
if \! detect\_lxc; then
cat \>\> docker\-compose\.yml <<\-'EOM'
ulimits\:
memlock\:
soft\: \-1
hard\: \-1
EOM
fi
cat \>\> docker\-compose\.yml <<\-'EOM'
healthcheck\:
test\:
\[
"CMD\-SHELL",
"curl \-\-output /dev/null \-\-silent \-\-head \-\-fail \-u elastic\:</span>{ES_LOCAL_PASSWORD} http://elasticsearch:9200",
        ]
      interval: 10s
      timeout: 10s
      retries: 30

EOM

if  [ -z "<span class="math-inline">\{esonly\:\-\}" \]; then
cat \>\> docker\-compose\.yml <<\-'EOM'
kibana\_settings\:
depends\_on\:
elasticsearch\:
condition\: service\_healthy
image\: docker\.elastic\.co/elasticsearch/elasticsearch\:</span>{ES_LOCAL_VERSION}
    container_name: kibana_settings
    restart: 'no'
    command: >
      bash -c '
        echo "Setup the kibana_system password";
        start_time=$<span class="math-inline">\(date \+%s\);
timeout\=60;
until curl \-s \-u "elastic\:</span>{ES_LOCAL_PASSWORD}" -X POST http://elasticsearch:9200/_security/user/kibana_system/_password -d "{\"password\":\"${KIBANA_LOCAL_PASSWORD}\"}" -H "Content-Type: application/json" | grep -q "^{}"; do
          if [ <span class="math-block">\(\(</span>(date +%s) - $$start_time)) -ge $<span class="math-inline">timeout \]; then
echo "Error\: Elasticsearch timeout";
exit 1;
fi;
sleep 2;
done;
'
kibana\:
depends\_on\:
kibana\_settings\:
condition\: service\_completed\_successfully
image\: docker\.elastic\.co/kibana/kibana\:</span>{ES_LOCAL_VERSION}
    container_name: <span class="math-inline">\{KIBANA\_LOCAL\_CONTAINER\_NAME\}
volumes\:
\- dev\-kibana\:/usr/share/kibana/data
ports\:
\- 127\.0\.0\.1\:</span>{KIBANA_LOCAL_PORT}:5601
    environment:
      - SERVER_NAME=kibana
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
      - ELASTICSEARCH_USERNAME=kibana_system
      - ELASTICSEARCH_PASSWORD=<span class="math-inline">\{KIBANA\_LOCAL\_PASSWORD\}</4\>
\- XPACK\_ENCRYPTEDSAVEDOBJECTS\_ENCRYPTIONKEY\=</span>{KIBANA_ENCRYPTION_KEY}
      - ELASTICSEARCH_PUBLICBASEURL=http://localhost:${ES_LOCAL_PORT}
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "curl -s -I http://kibana:5601 | grep -q 'HTTP/1.1 302 Found'",
        ]
      interval: 10s
      timeout: 10s
      retries: 30

EOM
fi

  if [ "<span class="math-inline">fleet\_enabled" \= true \]; then
cat \>\> docker\-compose\.yml <<\-'EOM'
fleet\-server\:
image\: docker\.elastic\.co/beats/elastic\-agent\:</span>{ES_LOCAL_VERSION}
    container_name: <span class="math-inline">\{FLEET\_SERVER\_CONTAINER\_NAME\}
depends\_on\:
elasticsearch\:
condition\: service\_healthy
kibana\:
condition\: service\_started
ports\:
\- 127\.0\.0\.1\:</span>{FLEET_SERVER_PORT}:8220
    environment:
      - FLEET_SERVER_MODE=fleet-server
      - FLEET_SERVER_ELASTICSEARCH_HOSTS=http://elasticsearch:9200
      - FLEET_SERVER_KIBANA_HOSTS=http://kibana:5601
      - FLEET_SERVER_ENROLLMENT_TOKEN=<span class="math-inline">\{FLEET\_ENROLLMENT\_TOKEN\}
\- ELASTIC\_PASSWORD\=</span>{ES_LOCAL_PASSWORD}
    volumes:
      - dev-fleet-server:/usr/share/elastic-agent/data
EOM
  fi

  cat >> docker-compose.yml <<-'EOM'
volumes:
  dev-elasticsearch:
EOM

if  [ -z "${esonly:-}" ]; then
  cat >> docker-compose.yml <<-'EOM'
  dev-kibana:
EOM
fi

  if [ "<span class="math-inline">fleet\_enabled" \= true \]; then
cat \>\> docker\-compose\.yml <<\-'EOM'
dev\-fleet\-server\:
EOM
fi
\}
print\_steps\(\) \{
if  \[ \-z "</span>{esonly:-}" ]; then
    echo "⌛️ Setting up Elasticsearch and Kibana v${es_version}..."
  else
    echo "⌛️ Setting up Elasticsearch v${es_
