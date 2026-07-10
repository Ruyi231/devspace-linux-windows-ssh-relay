#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"
load_config

port="${DEVSPACE_PORT}"
roots="${DEVSPACE_ALLOWED_ROOTS}"
owner_token="${DEVSPACE_OAUTH_OWNER_TOKEN}"
public_url="${NGROK_PUBLIC_URL}"

[ -n "${public_url}" ] || { echo "ERROR: NGROK_PUBLIC_URL is empty. Run ./setup_ngrok.sh first." >&2; exit 1; }
public_url="$(normalize_public_url "${public_url}")"

if [ -z "${owner_token}" ] || [ "${#owner_token}" -lt 16 ]; then
  owner_token="$(new_owner_token)"
  DEVSPACE_OAUTH_OWNER_TOKEN="${owner_token}"
  save_loaded_config
fi

IFS=',' read -r -a root_list <<< "${roots}"
for root in "${root_list[@]}"; do
  [ -d "${root}" ] || { echo "ERROR: Allowed project root does not exist: ${root}" >&2; exit 1; }
done

ngrok_bin="$(get_ngrok_path)"
devspace_bin="$(get_devspace_path)"
[ -n "${ngrok_bin}" ] || { echo "ERROR: ngrok was not found. Run ./install.sh first." >&2; exit 1; }
[ -n "${devspace_bin}" ] || { echo "ERROR: DevSpace was not found. Run ./install.sh first." >&2; exit 1; }

"${SCRIPT_DIR}/stop.sh" --quiet || true

echo "[1/3] Starting DevSpace..."
: > "${LOG_DIR}/devspace.log"
(
  export HOST="127.0.0.1"
  export PORT="${port}"
  export DEVSPACE_ALLOWED_ROOTS="${roots}"
  export DEVSPACE_PUBLIC_BASE_URL="${public_url}"
  export DEVSPACE_OAUTH_OWNER_TOKEN="${owner_token}"
  export DEVSPACE_TOOL_MODE="${DEVSPACE_TOOL_MODE}"
  export DEVSPACE_WIDGETS="${DEVSPACE_WIDGETS}"
  export DEVSPACE_TRUST_PROXY="1"
  export DEVSPACE_LOG_FORMAT="pretty"
  if command -v setsid >/dev/null 2>&1; then
    exec setsid "${devspace_bin}" serve
  fi
  exec "${devspace_bin}" serve
) > "${LOG_DIR}/devspace.log" 2>&1 &
devspace_pid=$!
echo "${devspace_pid}" > "${RUN_DIR}/devspace.pid"

for _ in $(seq 1 60); do
  if ! is_running_pid "${devspace_pid}"; then
    echo "ERROR: DevSpace failed to start. Log:" >&2
    cat "${LOG_DIR}/devspace.log" >&2 || true
    exit 1
  fi
  status="$(local_mcp_status "${port}")"
  if [ "${status}" = "401" ] || [ "${status}" = "200" ] || [ "${status}" = "405" ]; then
    break
  fi
  sleep 1
done
status="$(local_mcp_status "${port}")"
if [ "${status}" != "401" ] && [ "${status}" != "200" ] && [ "${status}" != "405" ]; then
  echo "ERROR: DevSpace did not answer on 127.0.0.1:${port}." >&2
  cat "${LOG_DIR}/devspace.log" >&2 || true
  exit 1
fi

echo "[2/3] Starting ngrok..."
clear_ngrok_proxy_environment
: > "${LOG_DIR}/ngrok.log"
if command -v setsid >/dev/null 2>&1; then
  setsid "${ngrok_bin}" http "127.0.0.1:${port}" --url "${public_url}" > "${LOG_DIR}/ngrok.log" 2>&1 &
else
  "${ngrok_bin}" http "127.0.0.1:${port}" --url "${public_url}" > "${LOG_DIR}/ngrok.log" 2>&1 &
fi
ngrok_pid=$!
echo "${ngrok_pid}" > "${RUN_DIR}/ngrok.pid"

if ! actual_url="$(wait_ngrok_endpoint "${ngrok_pid}" "${NGROK_WEB_API}" "${NGROK_STARTUP_TIMEOUT_SECONDS}")"; then
  echo "ERROR: ngrok failed to start. Log:" >&2
  cat "${LOG_DIR}/ngrok.log" >&2 || true
  "${SCRIPT_DIR}/stop.sh" --quiet || true
  exit 1
fi
actual_url="$(normalize_public_url "${actual_url}")"
if [ "${actual_url}" != "${public_url}" ]; then
  echo "ERROR: ngrok URL mismatch. Expected ${public_url}, got ${actual_url}." >&2
  "${SCRIPT_DIR}/stop.sh" --quiet || true
  exit 1
fi

write_current_env "${public_url}" "${roots}" "${port}"
echo "[3/3] Done."
echo
echo "================ DevSpace ngrok Connection Info ================"
echo "Public Base URL:"
echo "  ${public_url}"
echo
echo "GPT / MCP Connector URL:"
echo "  ${public_url}/mcp"
echo
echo "Owner password:"
echo "  ${owner_token}"
echo
echo "Allowed project roots:"
echo "  ${roots}"
echo
echo "Log files:"
echo "  ngrok:    ${LOG_DIR}/ngrok.log"
echo "  DevSpace: ${LOG_DIR}/devspace.log"
echo
echo "Stop service: ./stop.sh"
echo "==============================================================="
