#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/set_project.sh" "$@"
"${SCRIPT_DIR}/stop.sh" --quiet || true
exec "${SCRIPT_DIR}/start_relay_target.sh"
