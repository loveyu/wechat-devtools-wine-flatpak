#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPT_DIR}/common.sh"

INSTANCE_FILE="${STATE_DIR}/flatpak.instance"
if [[ -s "${INSTANCE_FILE}" ]]; then
    instance_id="$(<"${INSTANCE_FILE}")"
    flatpak kill "${instance_id}" 2>/dev/null || true
fi
