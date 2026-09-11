#!/usr/bin/env bash
# paths.sh — sourced by every build script; resolves locations independent of the caller's CWD.
#
# Layout inside a project:
#   <project>/                  PROJECT_ROOT  (.ino, Config.h, src/)
#   <project>/build/            BUILD_ROOT    (project data: release_matrix.csv, libraries/, builds/, build_config, .venv)
#   <project>/build/toolchain/  TOOLCHAIN_ROOT (this repo, vendored via git subtree)
#
# Override for other layouts:
#   XEWE_BUILD_ROOT=/path/to/build  XEWE_PROJECT_ROOT=/path/to/project

TOOLCHAIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_ROOT="${XEWE_BUILD_ROOT:-$(cd "${TOOLCHAIN_ROOT}/.." && pwd)}"
PROJECT_ROOT_DEFAULT="$(cd "${BUILD_ROOT}/.." && pwd)"
PROJECT_ROOT_DEFAULT="${XEWE_PROJECT_ROOT:-${PROJECT_ROOT_DEFAULT}}"
BUILD_CONFIG_FILE="${BUILD_ROOT}/build_config"

require_build_config() {
  if [[ ! -f "${BUILD_CONFIG_FILE}" ]]; then
    echo "❌ ${BUILD_CONFIG_FILE} not found. Run setup_build_environment.sh first." >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  source "${BUILD_CONFIG_FILE}"
}
