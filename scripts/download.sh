#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPT_DIR}/common.sh"

if [[ -f "${DEVTOOLS_INSTALLER_HOST}" ]]; then
    actual_sha256="$(sha256sum "${DEVTOOLS_INSTALLER_HOST}" | awk '{print $1}')"
    if [[ "${actual_sha256}" != "${DEVTOOLS_SHA256}" ]]; then
        mv "${DEVTOOLS_INSTALLER_HOST}" \
            "${DEVTOOLS_INSTALLER_HOST}.invalid.$(date +%s)"
    fi
fi

if [[ ! -f "${DEVTOOLS_INSTALLER_HOST}" ]]; then
    curl --fail --location --continue-at - --retry 20 --retry-all-errors \
        --retry-delay 5 --connect-timeout 30 \
        --output "${DEVTOOLS_INSTALLER_HOST}" "${DEVTOOLS_URL}"
fi

printf '%s  %s\n' "${DEVTOOLS_SHA256}" "${DEVTOOLS_INSTALLER_HOST}" | \
    sha256sum --check -
