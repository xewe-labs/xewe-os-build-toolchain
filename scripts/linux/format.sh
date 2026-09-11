#!/usr/bin/env bash
# Forwarding stub: the shared implementation lives in ../mac.
exec "$(dirname "${BASH_SOURCE[0]}")/../mac/format.sh" "$@"
