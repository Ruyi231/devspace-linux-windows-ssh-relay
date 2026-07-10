#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"
load_config

public_url_argument=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --public-url)
      [ "$#" -ge 2 ] || { echo "ERROR: --public-url needs a value." >&2; exit 1; }
      public_url_argument="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: ./setup_ngrok.sh [--public-url https://your-domain.ngrok-free.dev]"
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

ngrok_bin="$(get_ngrok_path)"
[ -n "${ngrok_bin}" ] || { echo "ERROR: ngrok was not found. Run ./install.sh first." >&2; exit 1; }
clear_ngrok_proxy_environment

stop_temp_ngrok() {
  local pid="${1:-}"
  if is_running_pid "${pid}"; then
    kill -TERM "${pid}" 2>/dev/null || true
    sleep 0.5
    is_running_pid "${pid}" && kill -KILL "${pid}" 2>/dev/null || true
  fi
}

echo "[1/4] Checking ngrok..."
"${ngrok_bin}" version

echo "[2/4] ngrok authtoken"
echo "      Paste your ngrok authtoken. It is sent to ngrok only and is not written to this Kit."
read -r -s -p "      Authtoken (press Enter to keep the existing one): " authtoken
echo
if [ -n "${authtoken}" ]; then
  "${ngrok_bin}" config add-authtoken "${authtoken}" >/dev/null
fi
unset authtoken

echo "[3/4] Checking ngrok config..."
"${ngrok_bin}" config check

if [ -n "${public_url_argument}" ]; then
  NGROK_PUBLIC_URL="$(normalize_public_url "${public_url_argument}")"
  save_loaded_config
elif [ -z "${NGROK_PUBLIC_URL}" ]; then
  echo "[4/4] Detecting your assigned ngrok URL..."
  setup_log="${LOG_DIR}/ngrok-setup.log"
  : > "${setup_log}"
  "${ngrok_bin}" http "127.0.0.1:${DEVSPACE_PORT}" > "${setup_log}" 2>&1 &
  temporary_pid=$!
  detected_url=""
  if detected_url="$(wait_ngrok_endpoint "${temporary_pid}" "${NGROK_WEB_API}" "${NGROK_STARTUP_TIMEOUT_SECONDS}")"; then
    NGROK_PUBLIC_URL="$(normalize_public_url "${detected_url}")"
    save_loaded_config
  else
    stop_temp_ngrok "${temporary_pid}"
    cat "${setup_log}" >&2 || true
    exit 1
  fi
  stop_temp_ngrok "${temporary_pid}"
else
  NGROK_PUBLIC_URL="$(normalize_public_url "${NGROK_PUBLIC_URL}")"
  save_loaded_config
fi

configured_url="${NGROK_PUBLIC_URL}"
echo "      Configured public URL: ${configured_url}"
echo "      Verifying that ngrok can reuse this URL..."
verify_log="${LOG_DIR}/ngrok-verify.log"
: > "${verify_log}"
"${ngrok_bin}" http "127.0.0.1:${DEVSPACE_PORT}" --url "${configured_url}" > "${verify_log}" 2>&1 &
verify_pid=$!
actual_url=""
if ! actual_url="$(wait_ngrok_endpoint "${verify_pid}" "${NGROK_WEB_API}" "${NGROK_STARTUP_TIMEOUT_SECONDS}")"; then
  stop_temp_ngrok "${verify_pid}"
  cat "${verify_log}" >&2 || true
  exit 1
fi
stop_temp_ngrok "${verify_pid}"

actual_url="$(normalize_public_url "${actual_url}")"
if [ "${actual_url}" != "${configured_url}" ]; then
  echo "ERROR: ngrok did not reuse the configured URL." >&2
  echo "Actual: ${actual_url}" >&2
  echo "Set your assigned Dev Domain with: ./setup_ngrok.sh --public-url https://your-domain.ngrok-free.dev" >&2
  exit 1
fi

echo
echo "ngrok setup complete."
echo "Public Base URL:"
echo "  ${configured_url}"
echo "GPT / MCP Connector URL:"
echo "  ${configured_url}/mcp"
echo
echo "Next: ./start.sh"
