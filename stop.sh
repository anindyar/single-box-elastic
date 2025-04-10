#!/bin/sh
# Stop script for start-local
# More information: https://github.com/elastic/start-local
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${SCRIPT_DIR}"

. ./.env

if [ -n "${FLEET_SERVER_CONTAINER_NAME:-}" ]; then
  $docker_stop ${ES_LOCAL_CONTAINER_NAME} ${KIBANA_LOCAL_CONTAINER_NAME} ${FLEET_SERVER_CONTAINER_NAME}
else
  $docker_stop ${ES_LOCAL_CONTAINER_NAME} ${KIBANA_LOCAL_CONTAINER_NAME}
fi
