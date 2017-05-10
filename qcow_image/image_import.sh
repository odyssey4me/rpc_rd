#!/bin/bash

VHD_NOTES=${3:-Ubuntu 16.04.2 LTS prepared for RPC deployment}
IMPORT_CONTAINER=${1:rpc-gating-images}
VHD_FILENAME=${2:-ubuntu-16.04.2-server-cloudimg-amd64-disk1.vhd}

export IMPORT_IMAGE_ENDPOINT=https://${OS_REGION_NAME}.images.api.rackspacecloud.com/v2/${OS_TENANT_NAME}

# This section simply retrieves the TOKEN
export TOKEN=`curl https://identity.api.rackspacecloud.com/v2.0/tokens -X POST -d '{ "auth":{"RAX-KSKEY:apiKeyCredentials": { "username":"'${OS_USERNAME}'", "apiKey": "'${OS_PASSWORD}'" }} }' -H "Content-type: application/json" |  python -mjson.tool | grep -A5 token | grep id | cut -d '"' -f4`

curl -X POST "$IMPORT_IMAGE_ENDPOINT/tasks" \
      -H "X-Auth-Token: $TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"type\":\"import\",\"input\":{\"image_properties\":{\"name\":\"$VHD_NOTES\"},\"import_from\":\"$IMPORT_CONTAINER/$VHD_FILENAME\"}}" |\
      python -mjson.tool
