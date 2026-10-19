#!/usr/bin/env bash

set -Eeuo pipefail

if (( $# == 0 )); then
    printf '用法：%s COMMAND [ARG ...]\n' "$0" >&2
    exit 64
fi

XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
XDG_STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"

export WECHAT_DEVTOOLS_RUNNER_VARIANT=staging
export WECHAT_DEVTOOLS_DATA_DIR="${WECHAT_DEVTOOLS_STAGING_DATA_DIR:-${XDG_DATA_HOME}/wechat-devtools-wine-flatpak-staging}"
export WECHAT_DEVTOOLS_STATE_DIR="${WECHAT_DEVTOOLS_STAGING_STATE_DIR:-${XDG_STATE_HOME}/wechat-devtools-wine-flatpak-staging}"
export WECHAT_DEVTOOLS_CACHE_DIR="${WECHAT_DEVTOOLS_STAGING_CACHE_DIR:-${XDG_CACHE_HOME}/wechat-devtools-wine-flatpak-staging}"

exec "$@"
