#!/bin/bash

set -x -v

EXPORT_CONTAINER="${1}"
IMAGE_ID="${2}"

usage() {
    cat <<EOF

    Usage:
    ${0} <export container> <uuid for cloud image>

EOF

if [[ -z "${EXPORT_CONTAINER}" ]] || [[ -z "${IMAGE_ID}" ]]; then
  usage
  exit 1
fi

# Setup the endpoint to interact with
EXPORT_IMAGE_ENDPOINT="https://${OS_REGION_NAME}.images.api.rackspacecloud.com/v2/${OS_TENANT_NAME}"

# This section simply retrieves the TOKEN
TOKEN=`curl https://identity.api.rackspacecloud.com/v2.0/tokens -X POST -d '{ "auth":{"RAX-KSKEY:apiKeyCredentials": { "username":"'${OS_USERNAME}'", "apiKey": "'${OS_PASSWORD}'" }} }' -H "Content-type: application/json" |  python -mjson.tool | grep -A5 token | grep id | cut -d '"' -f4`

# Request the export of the image to the container
curl -X POST "$EXPORT_IMAGE_ENDPOINT/tasks" \
      -H "X-Auth-Token: ${TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{\"type\": \"export\", \"input\": {\"image_uuid\": \"${IMAGE_ID}\", \"receiving_swift_container\": \"${EXPORT_CONTAINER}\"}}" |\
      python -mjson.tool

