#!/usr/bin/env bash
set -euo pipefail

# format.sh — thin forwarder to the Python orchestrator
# (<toolchain>/tools/code_formatter/format.py).
#   ./format.sh [--check] [path ...]
# With no paths, formats <project>/src. --check exits 1 if anything would change.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/paths.sh"
TOOLS_DIR="${TOOLCHAIN_ROOT}/tools/code_formatter"
export XEWE_PROJECT_ROOT="${PROJECT_ROOT_DEFAULT}"

if command -v python3 >/dev/null 2>&1; then
  PY="python3"
elif command -v python >/dev/null 2>&1; then
  PY="python"
else
  echo "python not found on PATH." >&2
  exit 1
fi

exec "$PY" "${TOOLS_DIR}/format.py" "$@"
