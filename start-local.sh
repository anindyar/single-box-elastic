#!/bin/sh
# --------------------------------------------------------
# Run Elasticsearch, Kibana and Fleet Agent for local testing
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
#	http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
set -eu

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
        
      -withfleet)
        withfleet=true
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
  echo '  ______ _           _   _      '
  echo ' |  ____| |         | | (_)     '
  echo ' | |__  | | __ _ ___| |_ _  ___ '
  echo ' |  __| | |/ _` / __| __| |/ __|'
  echo ' | |____| | (_| \__ \ |_| | (__ '
  echo ' |______|_|\__,_|___/\__|_|\___|'
  echo '-------------------------------------------------'
  echo '🚀 Run Elasticsearch and Kibana for local testing'
  echo '-------------------------------------------------'
  echo 
  echo 'ℹ️  Do not use this script in a production environment'
  echo

  # Version
  version="0.9.0"

  # Folder name for the installation
  installation_folder="elastic-start-local"
  # API key name for Elasticsearch
  api_key_name="elastic-start-local"
  # Name of the error log
  error_log="error-start-local.log"
  # Minimum version for docker-compose
  min_docker_compose="1.29.0"
  # Elasticsearch container name
  elasticsearch_container_name="es-local-dev"
  # Kibana container name
  kibana_container_name="kibana-local-dev"
  # Fleet container name
  fleet_agent_container_name="fleet-agent-local-dev"
  # Fleet server name (when used)
  fleet_server_container_name="fleet-server-local-dev"
  # Minimum disk space required for docker images + services (in GB)
  min_disk_space_required=5
}

# Check for ARM64 architecture
is_arm64() {
  arch="$(uname -m)"
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
  echo "$1" | grep -E -q '^[0-9]+\.[0-9]+\.[0-9]+$'
}

# Get the latest stable version of Elasticsearch
# Note: It removes all the beta or candidate releases from the list
# but includes the GA releases (e.g. new major)
get_latest_version() {
  versions="$(curl -s "https://artifacts.elastic.co/releases/stack.json")"
  latest_version=$(echo "$versions" | awk -F'"' '/"version": *"/ {print $4}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+( GA)?$' | version_sort | tail -n 1)
  # Remove the GA prefix from the version, if present
  latest_version=$(echo "$latest_version" | awk '{ gsub(/ GA$/, "", $0); print }')

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

  echo "$latest_version"
}

# Detect if running on LXC container
detect_lxc() {
    # Check /proc/1/environ for LXC container identifier
    if grep -qa "container=lxc" /proc/1/environ 2>/dev/null; then
      return 0
    fi
    # Check /proc/self/cgroup for LXC references
    if grep -q "lxc" /proc/self/cgroup 2>/dev/null; then
      return 0
    fi
    # Check for LXC in /sys/fs/cgroup
    if grep -q "lxc" /sys/fs/cgroup/* 2>/dev/null; then  
      return 0
    fi
    # Use systemd-detect-virt if available
    if command -v systemd-detect-virt >/dev/null 2>&1; then
      if [ "$(systemd-detect-virt)" = "lxc" ]; then
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
      echo "Distribution: $(cat /etc/redhat-release)"
  elif [ -n "${OSTYPE+x}" ]; then
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
      $docker_remove_volumes >/dev/null 2>&1
    fi
    cd ..
    rm -rf "${folder_to_clean}"
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
    error_file="./../$error_log"
  fi
  if [ -n "${msg}" ]; then
    echo "${msg}" > "$error_file"
  fi
  { 
    echo "Start-local version: ${version}"
    echo "Docker engine: $(docker --version)"
    echo "Docker compose: ${docker_version}"
    get_os_info
  } >> "$error_file" 
  for service in $docker_services; do
    echo "-- Logs of service ${service}:" >> "$error_file"
    docker logs "${service}" >> "$error_file" 2> /dev/null
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
  set -- $v1; v1_major=${1:-0}; v1_minor=${2:-0}; v1_patch=${3:-0}
  IFS='.'
  # shellcheck disable=SC2086
  set -- $v2; v2_major=${1:-0}; v2_minor=${2:-0}; v2_patch=${3:-0}
  IFS="$original_ifs"

  [ "$v1_major" -lt "$v2_major" ] && echo "lt" && return 0
  [ "$v1_major" -gt "$v2_major" ] && echo "gt" && return 0

  [ "$v1_minor" -lt "$v2_minor" ] && echo "lt" && return 0
  [ "$v1_minor" -gt "$v2_minor" ] && echo "gt" && return 0

  [ "$v1_patch" -lt "$v2_patch" ] && echo "lt" && return 0
  [ "$v1_patch" -gt "$v2_patch" ] && echo "gt" && return 0

  echo "eq"
}

# Wait for availability of Kibana
# parameter: timeout in seconds
wait_for_kibana() {
  timeout="${1:-60}"
  echo "- Waiting for Kibana to be ready"
  echo
  start_time="$(date +%s)"
  until curl -s -I http://localhost:5601 | grep -q 'HTTP/1.1 302 Found'; do
    elapsed_time="$(($(date +%s) - start_time))"
    if [ "$elapsed_time" -ge "$timeout" ]; then
      error_msg="Error: Kibana timeout of ${timeout} sec"
      echo "$error_msg"
      generate_error_log "${error_msg}" "${elasticsearch_container_name} ${kibana_container_name} kibana_settings"
      cleanup
      exit 1
    fi
    sleep 2
  done
}

# Configure Fleet Server in Kibana
# parameter: elastic password
configure_fleet_server() {
  es_password=$1
  echo "- Configuring Fleet Server"
  echo
  
  # Wait for Kibana to be fully ready
  sleep 10
  
  # Login to Kibana to get a session cookie
  cookies=$(curl -s -c - -X POST -H "Content-Type: application/json" -H "kbn-xsrf: true" \
    -d "{\"username\":\"elastic\",\"password\":\"${es_password}\"}" \
    http://localhost:5601/api/security/v1/login | grep -o "sid=[^;]*")
  
  if [ -z "$cookies" ]; then
    echo "Error: Could not authenticate with Kibana"
    return 1
  fi
  
  # Check if Fleet settings already exist
  fleet_exists=$(curl -s -X GET -H "kbn-xsrf: true" -H "Cookie: $cookies" \
    http://localhost:5601/api/fleet/settings | grep -c "\"isReady\":true")
  
  if [ "$fleet_exists" -eq 1 ]; then
    echo "✅ Fleet is already configured"
    return 0
  fi
  
  # Set Fleet configuration
  fleet_setup=$(curl -s -X POST -H "Content-Type: application/json" -H "kbn-xsrf: true" -H "Cookie: $cookies" \
    -d "{\"fleet_server_hosts\":[\"http://fleet-server:8220\"]}" \
    http://localhost:5601/api/fleet/setup)
  
  if echo "$fleet_setup" | grep -q '"isInitialized":true'; then
    echo "✅ Fleet setup successful"
  else
    echo "Error: Fleet setup failed"
    echo "$fleet_setup"
    return 1
  fi
  
  return 0
}

# Create a Fleet enrollment token for agents
# parameter: elastic password
create_fleet_token() {
  es_password=$1
  echo "- Creating Fleet enrollment token"
  
  # Login to Kibana to get a session cookie
  cookies=$(curl -s -c - -X POST -H "Content-Type: application/json" -H "kbn-xsrf: true" \
    -d "{\"username\":\"elastic\",\"password\":\"${es_password}\"}" \
    http://localhost:5601/api/security/v1/login | grep -o "sid=[^;]*")
  
  if [ -z "$cookies" ]; then
    echo "Error: Could not authenticate with Kibana"
    return ""
  fi
  
  # Get default policy ID
  policy_id=$(curl -s -X GET -H "kbn-xsrf: true" -H "Cookie: $cookies" \
    http://localhost:5601/api/fleet/agent_policies | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
  
  if [ -z "$policy_id" ]; then
    echo "Error: Could not get default policy ID"
    return ""
  fi
  
  # Create enrollment token for the policy
  token_response=$(curl -s -X POST -H "Content-Type: application/json" -H "kbn-xsrf: true" -H "Cookie: $cookies" \
    -d "{\"policy_id\":\"$policy_id\"}" \
    http://localhost:5601/api/fleet/enrollment-api-keys)
  
  token=$(echo "$token_response" | grep -o '"api_key":"[^"]*"' | cut -d'"' -f4)
  
  if [ -z "$token" ]; then
    echo "Error: Could not create enrollment token"
    return ""
  fi
  
  echo "✅ Fleet enrollment token created"
  echo "$token"
}

# Generates a random password with letters and numbers
# parameter: size of the password (default is 8 characters)
random_password() {
  LENGTH="${1:-8}"
  LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "${LENGTH}"
}

# Create an API key for Elasticsearch
# parameter 1: the Elasticsearch password
# parameter 2: name of the API key to generate
create_api_key() {
  es_password=$1
  name=$2
  response="$(curl -s -u "elastic:${es_password}" -X POST http://localhost:9200/_security/api_key -d "{\"name\": \"${name}\"}" -H "Content-Type: application/json")"
  if [ -z "$response" ]; then
    echo ""
  else
    api_key="$(echo "$response" | grep -Eo '"encoded":"[A-Za-z0-9+/=]+' | grep -Eo '[A-Za-z0-9+/=]+' | tail -n 1)"
    echo "$api_key"
  fi
}

# Check if a container is runnning
# parameter: the name of the container
check_container_running() {
  container_name=$1
  containers="$(docker ps --format '{{.Names}}')"
  if echo "$containers" | grep -q "^${container_name}$"; then
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
  required=$1
  available_gb=$(($(df -k / | awk 'NR==2 {print $4}') / 1024 / 1024))
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
  need_wait_for_kibana=true
  # Check for "docker compose" or "docker-compose"
  set +e
  if ! docker compose >/dev/null 2>&1; then
    if ! available "docker-compose"; then
      if ! available "docker"; then
        echo "Error: docker command is required"
        echo "You can install it from https://docs.docker.com/engine/install/."
        exit 1
      fi
      echo "Error: docker compose is required"
      echo "You can install it from https://docs.docker.com/compose/install/"
      exit 1
    fi
    docker="docker-compose up -d"
    docker_stop="docker-compose stop"
    docker_clean="docker-compose rm -fsv"
    docker_remove_volumes="docker-compose down -v"
    docker_version=$(docker-compose --version | head -n 1 | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+')
    if [ "$(compare_versions "$docker_version" "$min_docker_compose")" = "lt" ]; then
      echo "Unfortunately we don't support docker compose ${docker_version}. The minimum required version is $min_docker_compose."
      echo "You can migrate you docker compose from https://docs.docker.com/compose/migrate/"
      cleanup
      exit 1
    fi 
  else
    docker_stop="docker compose stop"
    docker_clean="docker compose rm -fsv"
    docker_remove_volumes="docker compose down -v"
    docker_version=$(docker compose version | head -n 1 | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+')
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
  if [ -d "$folder" ]; then
    if [ -n "$(ls -A "$folder")" ]; then
      echo "It seems you have already a start-local installation in '${folder}'."
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
  if [ -n "${withfleet:-}" ]; then
    check_container_running "$fleet_agent_container_name"
    check_container_running "$fleet_server_container_name"
  fi
}

create_installation_folder() {
  # If $folder already exists, it is empty, see above
  if [ ! -d "$folder" ]; then 
    mkdir $folder
  fi
  cd $folder
  folder_to_clean=$folder
}

generate_passwords() {
  # Generate random passwords
  es_password="$(random_password)"
  if  [ -z "${esonly:-}" ]; then
    kibana_password="$(random_password)"
    kibana_encryption_key="$(random_password 32)"
  fi
}

choose_es_version() {
  if [ -z "${es_version:-}" ]; then
    # Get the latest Elasticsearch version
    es_version="$(get_latest_version)"
  fi
}

create_env_file() {
  # Create the .env file
  cat > .env <<- EOM
ES_LOCAL_VERSION=$es_version
ES_LOCAL_CONTAINER_NAME=$elasticsearch_container_name
ES_LOCAL_PASSWORD=$es_password
ES_LOCAL_PORT=9200
ES_LOCAL_URL=http://localhost:\${ES_LOCAL_PORT}
ES_LOCAL_HEAP_INIT=128m
ES_LOCAL_HEAP_MAX=2g
ES_LOCAL_DISK_SPACE_REQUIRED=1gb
EOM

  if  [ -z "${esonly:-}" ]; then
    cat >> .env <<- EOM
KIBANA_LOCAL_CONTAINER_NAME=$kibana_container_name
KIBANA_LOCAL_PORT=5601
KIBANA_LOCAL_PASSWORD=$kibana_password
KIBANA_ENCRYPTION_KEY=$kibana_encryption_key
EOM

    if [ -n "${withfleet:-}" ]; then
      cat >> .env <<- EOM
FLEET_SERVER_CONTAINER_NAME=$fleet_server_container_name
FLEET_AGENT_CONTAINER_NAME=$fleet_agent_container_name
FLEET_SERVER_PORT=8220
EOM
    fi
  fi
}

# Create the start script (start.sh)
# including the license update if trial expired
create_start_file() {
  today=$(date +%s)
  expire=$((today + 3600*24*30))

  cat > start.sh <<-'EOM'
#!/bin/sh
# Start script for start-local
# More information: https://github.com/elastic/start-local
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${SCRIPT_DIR}"
today=$(date +%s)
. ./.env
# Check disk space
available_gb=$(($(df -k / | awk 'NR==2 {print $4}') / 1024 / 1024))
required=$(echo "${ES_LOCAL_DISK_SPACE_REQUIRED}" | grep -Eo '[0-9]+')
if [ "$available_gb" -lt "$required" ]; then
  echo "----------------------------------------------------------------------------"
  echo "WARNING: Disk space is below the ${required} GB limit. Elasticsearch will be"
  echo "executed in read-only mode. Please free up disk space to resolve this issue."
  echo "----------------------------------------------------------------------------"
  echo "Press ENTER to confirm."
  read -r
fi
EOM
  if [ "$need_wait_for_kibana" = true ]; then
    cat >> start.sh <<-'EOM'
wait_for_kibana() {
  local timeout="${1:-60}"
  echo "- Waiting for Kibana to be ready"
  echo
  local start_time="$(date +%s)"
  until curl -s -I http://localhost:5601 | grep -q 'HTTP/1.1 302 Found'; do
    elapsed_time="$(($(date +%s) - start_time))"
    if [ "$elapsed_time" -ge "$timeout" ]; then
      echo "Error: Kibana timeout of ${timeout} sec"
      exit 1
    fi
    sleep 2
  done
}

EOM
  fi

  cat >> start.sh <<- EOM
if [ -z "\${ES_LOCAL_LICENSE:-}" ] && [ "\$today" -gt $expire ]; then
  echo "---------------------------------------------------------------------"
  echo "The one-month trial period has expired. You can continue using the"
  echo "Free and open Basic license or request to extend the trial for"
  echo "another 30 days using this form:"
  echo "https://www.elastic.co/trialextension"
  echo "---------------------------------------------------------------------"
  echo "For more info about the license: https://www.elastic.co/subscriptions"
  echo
  echo "Updating the license..."
  $docker elasticsearch >/dev/null 2>&1
  result=\$(curl -s -X POST "\${ES_LOCAL_URL}/_license/start_basic?acknowledge=true" -H "Authorization: ApiKey \${ES_LOCAL_API_KEY}" -o /dev/null -w '%{http_code}\n')
  if [ "\$result" = "200" ]; then
    echo "✅ Basic license successfully installed"
    echo "ES_LOCAL_LICENSE=basic" >> .env
  else 
    echo "Error: I cannot update the license"
    result=\$(curl -s -X GET "\${ES_LOCAL_URL}" -H "Authorization: ApiKey \${ES_LOCAL_API_KEY}" -o /dev/null -w '%{http_code}\n')
    if [ "\$result" != "200" ]; then
      echo "Elasticsearch is not running."
    fi
    exit 1
  fi
  echo
fi
$docker
EOM

  if [ "$need_wait_for_kibana" = true ]; then
    cat >> start.sh <<-'EOM'
wait_for_kibana 180
EOM
  fi
  
  # Add Fleet token renewal if Fleet is enabled
  if [ -n "${withfleet:-}" ]; then
    cat >> start.sh <<-'EOM'

# If fleet enrollment token exists, check and renew if needed
if [ -f ".fleet_token" ]; then
  echo "- Checking Fleet enrollment token"
  
  # Login to Kibana
  cookies=$(curl -s -c - -X POST -H "Content-Type: application/json" -H "kbn-xsrf: true" \
    -d "{\"username\":\"elastic\",\"password\":\"${ES_LOCAL_PASSWORD}\"}" \
    http://localhost:5601/api/security/v1/login | grep -o "sid=[^;]*")
  
  if [ -z "$cookies" ]; then
    echo "Warning: Could not check Fleet enrollment token"
  else
    # Verify token is still valid
    token=$(cat .fleet_token)
    policy_id=$(curl -s -X GET -H "kbn-xsrf: true" -H "Cookie: $cookies" \
      http://localhost:5601/api/fleet/agent_policies | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    token_valid=$(curl -s -X POST -H "Content-Type: application/json" -H "Authorization: ApiKey $token" \
      http://localhost:8220/api/fleet/agents/checkin -d "{\"events\":[]}" -o /dev/null -w '%{http_code}\n')
    
    if [ "$token_valid" != "200" ]; then
      echo "- Renewing Fleet enrollment token"
      # Create new token
      token_response=$(curl -s -X POST -H "Content-Type: application/json" -H "kbn-xsrf: true" -H "Cookie: $cookies" \
        -d "{\"policy_id\":\"$policy_id\"}" \
        http://localhost:5601/api/fleet/enrollment-api-keys)
      
      new_token=$(echo "$token_response" | grep -o '"api_key":"[^"]*"' | cut -d'"' -f4)
      
      if [ -n "$new_token" ]; then
        echo "$new_token" > .fleet_token
        echo "✅ Fleet enrollment token renewed"
      fi
    else
      echo "✅ Fleet enrollment token is valid"
    fi
  fi
fi
EOM
  fi
  
  chmod +x start.sh
}

# Create the stop script (stop.sh)
create_stop_file() {
  cat > stop.sh <<-'EOM'
#!/bin/sh
# Stop script for start-local
# More information: https://github.com/elastic/start-local
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${SCRIPT_DIR}"
EOM

  cat >> stop.sh <<- EOM
$docker_stop
EOM
  chmod +x stop.sh
}

# Create the uninstall script (uninstall.sh)
create_uninstall_file() {

  cat > uninstall.sh <<-'EOM'
#!/bin/sh
# Uninstall script for start-local
# More information: https://github.com/elastic/start-local
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ask_confirmation() {
    echo "Do you want to continue? (yes/no)"
    read -r answer
    case "$answer" in
        yes|y|Y|Yes|YES)
            return 0  # true
            ;;
        no|n|N|No|NO)
            return 1  # false
            ;;
        *)
            echo "Please answer yes or no."
            ask_confirmation  # Ask again if the input is invalid
            ;;
    esac
}

cd "${SCRIPT_DIR}"
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
  $docker_remove_volumes
  rm -f docker-compose.yml .env uninstall.sh start.sh stop.sh .fleet_token
  echo "Start-local successfully removed"
fi
EOM
  chmod +x uninstall.sh
}

create_docker_compose_file() {
  # Create the docker-compose-yml file
  cat > docker-compose.yml <<-'EOM'
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:${ES_LOCAL_VERSION}
    container_name: ${ES_LOCAL_CONTAINER_NAME}
    volumes:
      - dev-elasticsearch:/usr/share/elasticsearch/data
    ports:
      - 127.0.0.1:${ES_LOCAL_PORT}:9200
    environment:
      - discovery.type=single-node
      - ELASTIC_PASSWORD=${ES_LOCAL_PASSWORD}
      - xpack.security.enabled=true
      - xpack.security.http.ssl.enabled=false
      - xpack.license.self_generated.type=trial
      - xpack.ml.use_auto_machine_memory_percent=true
      - ES_JAVA_OPTS=-Xms${ES_LOCAL_HEAP_INIT} -Xmx${ES_LOCAL_HEAP_MAX}
      - cluster.routing.allocation.disk.watermark.low=${ES_LOCAL_DISK_SPACE_REQUIRED}
      - cluster.routing.allocation.disk.watermark.high=${ES_LOCAL_DISK_SPACE_REQUIRED}
      - cluster.routing.allocation.disk.watermark.flood_stage=${ES_LOCAL_DISK_SPACE_REQUIRED}
EOM
  
  # Fix for JDK AArch64 issue, see https://bugs.openjdk.org/browse/JDK-8345296
  if is_arm64; then
  cat >> docker-compose.yml <<-'EOM'
      - "_JAVA_OPTIONS=-XX:UseSVE=0"
EOM
  fi

  # Fix for OCI issue on LXC, see https://github.com/elastic/start-local/issues/27
  if ! detect_lxc; then
  cat >> docker-compose.yml <<-'EOM'
    ulimits:
      memlock:
        soft: -1
        hard: -1
EOM
  fi

  cat >> docker-compose.yml <<-'EOM'
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "curl --output /dev/null --silent --head --fail -u elastic:${ES_LOCAL_PASSWORD} http://elasticsearch:9200",
        ]
      interval: 10s
      timeout: 10s
      retries: 30

EOM

if  [ -z "${esonly:-}" ]; then
  cat >> docker-compose.yml <<-'EOM'
  kibana_settings:
    depends_on:
      elasticsearch:
        condition: service_healthy
    image: docker.elastic.co/elasticsearch/elasticsearch:${ES_LOCAL_VERSION}
    container_name: kibana_settings
    restart: 'no'
    command: >
      bash -c '
        echo "Setup the kibana_system password";
        start_time=$(date +%s);
        timeout=60;
        until curl -s -u "elastic:${ES_LOCAL_PASSWORD}" -X POST http://elasticsearch:9200/_security/user/kibana_system/_password -d "{\"password\":\"${KIBANA_LOCAL_PASSWORD}\"}" -H "Content-Type: application/json" | grep -q "^{}"; do
          if [ $(($(date +%s) - $start_time)) -ge $timeout ]; then
            echo "Error: Elasticsearch timeout";
            exit 1;
          fi;
          sleep 2;
        done;
      '

  kibana:
    depends_on:
      kibana_settings:
        condition: service_completed_successfully
    image: docker.elastic.co/kibana/kibana:${ES_LOCAL_VERSION}
    container_name: ${KIBANA_LOCAL_CONTAINER_NAME}
    volumes:
      - dev-kibana:/usr/share/kibana/data
    ports:
      - 127.0.0.1:${KIBANA_LOCAL_PORT}:5601
    environment:
      - SERVER_NAME=kibana
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
      - ELASTICSEARCH_USERNAME=kibana_system
      - ELASTICSEARCH_PASSWORD=${KIBANA_LOCAL_PASSWORD}
      - XPACK_ENCRYPTEDSAVEDOBJECTS_ENCRYPTIONKEY=${KIBANA_ENCRYPTION_KEY}
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

  # Add Fleet Server and Agent if requested
  if [ -n "${withfleet:-}" ]; then
  cat >> docker-compose.yml <<-'EOM'
  fleet_server:
    depends_on:
      kibana:
        condition: service_healthy
    image: docker.elastic.co/beats/elastic-agent:${ES_LOCAL_VERSION}
    container_name: ${FLEET_SERVER_CONTAINER_NAME}
    ports:
      - 127.0.0.1:${FLEET_SERVER_PORT}:8220
    volumes:
      - fleet-server-data:/usr/share/elastic-agent
    user: root
    environment:
      - FLEET_SERVER_ENABLE=true
      - FLEET_SERVER_ELASTICSEARCH_HOST=http://elasticsearch:9200
      - FLEET_SERVER_ELASTICSEARCH_USERNAME=elastic
      - FLEET_SERVER_ELASTICSEARCH_PASSWORD=${ES_LOCAL_PASSWORD}
      - FLEET_SERVER_SERVICE_TOKEN=
      - FLEET_SERVER_POLICY_ID=fleet-server-policy
      - FLEET_URL=https://fleet-server:8220
      - KIBANA_FLEET_SETUP=true
      - KIBANA_HOST=http://kibana:5601
      - ELASTICSEARCH_HOST=http://elasticsearch:9200
      - ELASTICSEARCH_USERNAME=elastic
      - ELASTICSEARCH_PASSWORD=${ES_LOCAL_PASSWORD}
      - FLEET_SERVER_INSECURE_HTTP=true
      - FLEET_SERVER_HOST=0.0.0.0
    command: >
      bash -c '
        set -e;
        sleep 10;
        until curl -s -f -u "elastic:${ES_LOCAL_PASSWORD}" http://elasticsearch:9200/_cat/indices; do
          echo "Waiting for Elasticsearch...";
          sleep 2;
        done;
        until curl -s -f http://kibana:5601/api/status; do
          echo "Waiting for Kibana...";
          sleep 2;
        done;
        echo "Starting Fleet Server...";
        elastic-agent install --force --insecure \
          --url=http://kibana:5601 \
          --enrollment-token=$(curl -s -X POST \
            -u "elastic:${ES_LOCAL_PASSWORD}" \
            -H "kbn-xsrf: true" \
            -H "Content-Type: application/json" \
            "http://kibana:5601/api/fleet/setup" | grep -o "\\"serviceTokenId\\":\\"[^\\"]*\\"" | cut -d\\"  -f4) \
          --fleet-server-es=http://elasticsearch:9200 \
          --fleet-server-service-token= \
          --fleet-server-policy=fleet-server-policy \
          --fleet-server-host=0.0.0.0 \
          --fleet-server-port=8220 \
          --fleet-server-insecure-http;
      '
    healthcheck:
      test:
        [
          "CMD-SHELL",
          "curl -s http://localhost:8220/api/status | grep -q 'HEALTHY'",
        ]
      interval: 10s
      timeout: 10s
      retries: 20

  fleet_agent:
    depends_on:
      fleet_server:
        condition: service_healthy
    image: docker.elastic.co/beats/elastic-agent:${ES_LOCAL_VERSION}
    container_name: ${FLEET_AGENT_CONTAINER_NAME}
    volumes:
      - fleet-agent-data:/usr/share/elastic-agent
    user: root
    privileged: true
    environment:
      - FLEET_ENROLLMENT_TOKEN=
      - FLEET_URL=http://fleet-server:8220
      - FLEET_INSECURE=true
    command: >
      bash -c '
        set -e;
        sleep 15;
        echo "Setting up Fleet Agent...";
        # Create default policy if needed
        es_resp=$(curl -s -u "elastic:${ES_LOCAL_PASSWORD}" "http://elasticsearch:9200/_cat/indices");
        echo "ES Indices: $es_resp";
        
        # Log in to Kibana for session
        cookies=$(curl -s -c - -X POST -H "Content-Type: application/json" -H "kbn-xsrf: true" \
          -d "{\\"username\\":\\"elastic\\",\\"password\\":\\"${ES_LOCAL_PASSWORD}\\"}" \
          http://kibana:5601/api/security/v1/login | grep -o "sid=[^;]*");
        
        if [ -z "$cookies" ]; then
          echo "Error: Could not authenticate with Kibana";
          exit 1;
        fi

        # Check if Fleet is ready
        fleet_ready=false;
        retry_count=0;
        while [ "$fleet_ready" = false ] && [ $retry_count -lt 20 ]; do
          fleet_status=$(curl -s -X GET -H "kbn-xsrf: true" -H "Cookie: $cookies" \
            http://kibana:5601/api/fleet/agents/setup);
          echo "Fleet setup status: $fleet_status";
          
          if echo "$fleet_status" | grep -q "\\"isReady\\":true"; then
            fleet_ready=true;
          else
            retry_count=$((retry_count + 1));
            sleep 5;
          fi
        done;
        
        if [ "$fleet_ready" = false ]; then
          echo "Error: Fleet is not ready after multiple attempts";
          exit 1;
        fi

        # Get the default policy ID
        policy_id=$(curl -s -X GET -H "kbn-xsrf: true" -H "Cookie: $cookies" \
          http://kibana:5601/api/fleet/agent_policies | grep -o "\\"id\\":\\"\\"[^\\"]*\\"" | head -1 | cut -d\\"  -f4);
        
        if [ -z "$policy_id" ]; then
          echo "Error: Could not get default policy ID";
          exit 1;
        fi
        
        echo "Default policy ID: $policy_id";
        
        # Create enrollment token
        token_response=$(curl -s -X POST -H "Content-Type: application/json" -H "kbn-xsrf: true" -H "Cookie: $cookies" \
          -d "{\\"policy_id\\":\\"$policy_id\\"}" \
          http://kibana:5601/api/fleet/enrollment-api-keys);
        
        enrollment_token=$(echo "$token_response" | grep -o "\\"api_key\\":\\"\\"[^\\"]*\\"" | cut -d\\"  -f4);
        
        if [ -z "$enrollment_token" ]; then
          echo "Error: Could not create enrollment token";
          exit 1;
        fi
        
        echo "Token: $enrollment_token";
        echo "$enrollment_token" > /tmp/fleet_token;
        
        # Save token for future use
        cat /tmp/fleet_token > /usr/share/elastic-agent/fleet_token;
        
        # Install the agent
        elastic-agent install --url=http://fleet-server:8220 \
          --enrollment-token=$enrollment_token \
          --insecure \
          --force;
          
        # Keep container running
        sleep infinity;
      '

EOM
  fi
fi

  cat >> docker-compose.yml <<-'EOM'
volumes:
  dev-elasticsearch:
EOM

if  [ -z "${esonly:-}" ]; then
  cat >> docker-compose.yml <<-'EOM'
  dev-kibana:
EOM

  if [ -n "${withfleet:-}" ]; then
  cat >> docker-compose.yml <<-'EOM'
  fleet-server-data:
  fleet-agent-data:
EOM
  fi
fi
}
