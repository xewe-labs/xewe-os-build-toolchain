#!/usr/bin/env bash
# paths.sh — sourced by every build script; resolves locations independent of the caller's CWD.
#
# Layout inside a project (the project's setup.sh copies scripts/ and tools/ of this repo into build/):
#   <project>/                  PROJECT_ROOT_DEFAULT  (.ino, Config.h, src/)
#   <project>/build/            BUILD_ROOT = TOOLCHAIN_ROOT
#                               committed:  .gitignore, release_matrix.csv, required_libraries.txt, version_state
#                               installed:  scripts/, tools/
#                               generated:  libraries/, builds/, .venv/, build_config
#
# Override for other layouts:
#   XEWE_BUILD_ROOT=/path/to/build  XEWE_PROJECT_ROOT=/path/to/project

TOOLCHAIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_ROOT="${XEWE_BUILD_ROOT:-${TOOLCHAIN_ROOT}}"
PROJECT_ROOT_DEFAULT="$(cd "${BUILD_ROOT}/.." && pwd)"
PROJECT_ROOT_DEFAULT="${XEWE_PROJECT_ROOT:-${PROJECT_ROOT_DEFAULT}}"
BUILD_CONFIG_FILE="${BUILD_ROOT}/build_config"

require_build_config() {
  if [[ ! -f "${BUILD_CONFIG_FILE}" ]]; then
    echo "❌ ${BUILD_CONFIG_FILE} not found. Run build/scripts/<mac|linux>/setup.sh first." >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  source "${BUILD_CONFIG_FILE}"
}
