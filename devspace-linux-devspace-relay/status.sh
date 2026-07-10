#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"
load_config

show_process() {
  local name="$1" pid_file="${RUN_DIR}/$1.pid" pid=""
  if [ ! -f "${pid_file}" ]; then echo "${name}: not running"; return; fi
  pid="$(tr -d '[:space:]' < "${pid_file}" 2>/dev/null || true)"
  if is_running_pid "${pid}"; then echo "${name}: running, pid=${pid}"; else echo "${name}: stale pid file (${pid})"; fi
}

echo "================ Linux DevSpace Relay Status ================"
show_process devspace
echo
echo "Config:"
echo "  DEVSPACE_ALLOWED_ROOTS=${DEVSPACE_ALLOWED_ROOTS}"
echo "  DEVSPACE_PORT=${DEVSPACE_PORT}"
echo "  NGROK_PUBLIC_URL=${NGROK_PUBLIC_URL:-<not configured>}"
echo
echo "URLs:"
echo "  Windows ngrok Public Base URL: ${NGROK_PUBLIC_URL:-<not configured>}"
echo "  GPT / MCP Connector URL:       ${NGROK_PUBLIC_URL:+${NGROK_PUBLIC_URL}/mcp}"
echo
echo "Local check: http://127.0.0.1:${DEVSPACE_PORT}/mcp -> HTTP $(local_mcp_status "${DEVSPACE_PORT}")"
echo "Logs: ${LOG_DIR}/devspace.log"
echo "==========================================================="
