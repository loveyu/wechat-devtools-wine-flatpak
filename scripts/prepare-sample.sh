#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPT_DIR}/common.sh"

SAMPLE_DIR="${WORKSPACE_DIR}/wine-flatpak-smoke"
mkdir -p "${SAMPLE_DIR}"
cp -a "${PROJECT_DIR}/fixtures/miniprogram/." "${SAMPLE_DIR}/"
printf '%s\n' "${SAMPLE_DIR}"
printf 'Z:%s\n' "$(printf '%s' "${SAMPLE_DIR}" | tr '/' '\\')" > \
    "${STATE_DIR}/sample.windows-path"
