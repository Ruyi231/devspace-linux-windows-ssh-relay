#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
load_config
[ -n "${NGROK_PUBLIC_URL}" ] || { echo "ERROR: Run ./set_relay_public_url.sh https://your-domain.ngrok-free.dev first." >&2; exit 1; }
IFS=',' read -r -a roots <<< "${DEVSPACE_ALLOWED_ROOTS}"
for root in "${roots[@]}"; do [ -d "${root}" ] || { echo "ERROR: Missing project root: ${root}" >&2; exit 1; }; done
devspace_bin="$(get_devspace_path)"
[ -n "${devspace_bin}" ] || { echo "ERROR: Run ./install.sh first." >&2; exit 1; }
"${SCRIPT_DIR}/stop.sh" --quiet || true
echo "[1/1] Starting Linux DevSpace relay target..."
: > "${LOG_DIR}/devspace.log"
(
  export HOST=127.0.0.1 PORT="${DEVSPACE_PORT}"
  export DEVSPACE_ALLOWED_ROOTS DEVSPACE_OAUTH_OWNER_TOKEN DEVSPACE_TOOL_MODE DEVSPACE_WIDGETS
  export DEVSPACE_PUBLIC_BASE_URL="${NGROK_PUBLIC_URL}"
  export DEVSPACE_ALLOWED_HOSTS="${NGROK_PUBLIC_URL#https://}"
  export DEVSPACE_TRUST_PROXY=1 DEVSPACE_LOG_FORMAT=pretty
  if command -v setsid >/dev/null 2>&1; then exec setsid "${devspace_bin}" serve; fi
  exec "${devspace_bin}" serve
) > "${LOG_DIR}/devspace.log" 2>&1 &
pid=$!
echo "${pid}" > "${RUN_DIR}/devspace.pid"
ready=0
for _ in $(seq 1 30); do
  if grep -q 'devspace listening on' "${LOG_DIR}/devspace.log" && [ "$(local_mcp_status "${DEVSPACE_PORT}")" = 401 ]; then
    ready=1
    break
  fi
  sleep 1
done
if [ "${ready}" != 1 ]; then
  echo "ERROR: DevSpace did not bind successfully. The port may already be in use." >&2
  cat "${LOG_DIR}/devspace.log" >&2
  exit 1
fi
echo "Linux DevSpace is ready at 127.0.0.1:${DEVSPACE_PORT}"
echo "Owner password: ${DEVSPACE_OAUTH_OWNER_TOKEN}"
