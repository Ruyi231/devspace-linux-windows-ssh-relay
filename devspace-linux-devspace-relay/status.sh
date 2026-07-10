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

echo "================ DevSpace ngrok Kit Status ================"
show_process ngrok
show_process devspace
echo
echo "Config:"
echo "  DEVSPACE_ALLOWED_ROOTS=${DEVSPACE_ALLOWED_ROOTS}"
echo "  DEVSPACE_PORT=${DEVSPACE_PORT}"
echo "  NGROK_PUBLIC_URL=${NGROK_PUBLIC_URL:-<not configured>}"
echo
actual_url=""
if [ -f "${RUN_DIR}/ngrok.pid" ] && is_running_pid "$(tr -d '[:space:]' < "${RUN_DIR}/ngrok.pid")"; then
  actual_url="$(get_ngrok_endpoint "${NGROK_WEB_API}")"
fi
echo "URLs:"
echo "  Configured Public Base URL: ${NGROK_PUBLIC_URL:-<not configured>}"
echo "  Actual ngrok URL:           ${actual_url:-<not running>}"
echo "  GPT / MCP Connector URL:    ${NGROK_PUBLIC_URL:+${NGROK_PUBLIC_URL}/mcp}"
if [ -n "${actual_url}" ] && [ "${actual_url}" = "${NGROK_PUBLIC_URL}" ]; then
  echo "  URL consistency:            MATCH"
elif [ -n "${actual_url}" ]; then
  echo "  URL consistency:            MISMATCH"
else
  echo "  URL consistency:            NOT RUNNING"
fi
echo
echo "Local check: http://127.0.0.1:${DEVSPACE_PORT}/mcp -> HTTP $(local_mcp_status "${DEVSPACE_PORT}")"
echo "Logs: ${LOG_DIR}/ngrok.log and ${LOG_DIR}/devspace.log"
echo "==========================================================="
