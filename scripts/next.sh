#!/usr/bin/env bash
set -eu -o pipefail

# TCTL has image fully-qualified versions (registry.address/image:tag) bundled into the binary at compile time
# We do not release the "-next" binaries to the customer-accessible registry, only to the tetrate-internal one
# This is a primitive script to sync those TSB "next" images to a provided container registry

ARCH=$(uname | awk '{print tolower($0)}')
TMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'tctl-tmpdir')  # first is for Linux, second is for MacOS
TMP_TCTL=${TMP_DIR}/tctl

usage() {
  echo "Usage: ${0} <DESTINATION_REGISTRY>" 1>&2;
  exit 1;
}
parseArg(){
    if [ $# -ne 1 ]; then
        echo "Exactly one destination registry argument required."
        usage
    fi
    DST_REGISTRY=$1
}

## Get the "-next" tctl
getTctl() {
    curl https://binaries.dl.tetrate.io/public/raw/versions/${ARCH}-amd64-next/tctl -o ${TMP_TCTL}
    chmod +x ${TMP_TCTL}
}

## sync the images to the registry from argv
syncImages() {
    ${TMP_TCTL} install image-sync --registry ${DST_REGISTRY} --source-registry gcr.io/tetrate-internal-containers
}

parseArg "$@"
getTctl
syncImages
