#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

quiet=0
[ "${1:-}" = "--quiet" ] && quiet=1
stop_managed_process devspace "${quiet}"
[ "${quiet}" = "1" ] || echo "Stopped."
