#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"
LOG_DIR="${SCRIPT_DIR}/logs"
RUN_DIR="${SCRIPT_DIR}/run"
TOOLS_DIR="${SCRIPT_DIR}/tools"
NODE_DIR="${TOOLS_DIR}/node"
NPM_PREFIX="${TOOLS_DIR}/npm-global"
NGROK_DIR="${TOOLS_DIR}/ngrok"

mkdir -p "${LOG_DIR}" "${RUN_DIR}" "${TOOLS_DIR}"

shell_quote() {
  local value="${1:-}"
  printf "'%s'" "$(printf '%s' "$value" | sed "s/'/'\\''/g")"
}

new_owner_token() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 24
  else
    LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom | head -c 48
    printf '\n'
  fi
}

ensure_config() {
  if [ -f "${CONFIG_FILE}" ]; then
    return
  fi

  local token
  token="$(new_owner_token)"
  cat > "${CONFIG_FILE}" <<EOF
# DevSpace Linux Kit ngrok configuration
# Separate multiple project roots with commas.
DEVSPACE_ALLOWED_ROOTS=$(shell_quote "$HOME")
DEVSPACE_PORT='7676'
DEVSPACE_OAUTH_OWNER_TOKEN=$(shell_quote "$token")
DEVSPACE_TOOL_MODE='minimal'
DEVSPACE_WIDGETS='full'
NGROK_PUBLIC_URL=''
NGROK_WEB_API='http://127.0.0.1:4040/api'
NGROK_STARTUP_TIMEOUT_SECONDS='30'
EOF
  chmod 600 "${CONFIG_FILE}"
}

load_config() {
  ensure_config
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
  export PATH="${NODE_DIR}/bin:${NPM_PREFIX}/bin:${PATH}"
}

save_config() {
  local roots="${1:?missing roots}"
  local port="${2:-7676}"
  local token="${3:-}"
  local tool_mode="${4:-minimal}"
  local widgets="${5:-full}"
  local public_url="${6:-}"
  local web_api="${7:-http://127.0.0.1:4040/api}"
  local timeout="${8:-30}"

  if [ -z "${token}" ]; then
    token="$(new_owner_token)"
  fi

  cat > "${CONFIG_FILE}" <<EOF
# DevSpace Linux Kit ngrok configuration
# Separate multiple project roots with commas.
DEVSPACE_ALLOWED_ROOTS=$(shell_quote "$roots")
DEVSPACE_PORT=$(shell_quote "$port")
DEVSPACE_OAUTH_OWNER_TOKEN=$(shell_quote "$token")
DEVSPACE_TOOL_MODE=$(shell_quote "$tool_mode")
DEVSPACE_WIDGETS=$(shell_quote "$widgets")
NGROK_PUBLIC_URL=$(shell_quote "$public_url")
NGROK_WEB_API=$(shell_quote "$web_api")
NGROK_STARTUP_TIMEOUT_SECONDS=$(shell_quote "$timeout")
EOF
  chmod 600 "${CONFIG_FILE}"
}

save_loaded_config() {
  save_config \
    "${DEVSPACE_ALLOWED_ROOTS}" \
    "${DEVSPACE_PORT}" \
    "${DEVSPACE_OAUTH_OWNER_TOKEN}" \
    "${DEVSPACE_TOOL_MODE}" \
    "${DEVSPACE_WIDGETS}" \
    "${NGROK_PUBLIC_URL}" \
    "${NGROK_WEB_API}" \
    "${NGROK_STARTUP_TIMEOUT_SECONDS}"
}

realpath_safe() {
  local path="${1:?missing path}"
  if command -v realpath >/dev/null 2>&1; then
    realpath "$path"
  elif command -v readlink >/dev/null 2>&1; then
    readlink -f "$path"
  else
    (cd "$path" && pwd -P)
  fi
}

is_running_pid() {
  local pid="${1:-}"
  [[ "${pid}" =~ ^[0-9]+$ ]] && kill -0 "$pid" >/dev/null 2>&1
}

stop_managed_process() {
  local name="${1:?missing name}"
  local quiet="${2:-0}"
  local pid_file="${RUN_DIR}/${name}.pid"
  local pid=""

  if [ ! -f "${pid_file}" ]; then
    [ "${quiet}" = "1" ] || echo "${name}: no pid file."
    return 0
  fi

  pid="$(tr -d '[:space:]' < "${pid_file}" 2>/dev/null || true)"
  if is_running_pid "${pid}"; then
    [ "${quiet}" = "1" ] || echo "Stopping ${name} pid=${pid}..."
    # start.sh launches each service in its own process group. Do not search
    # for or stop unrelated processes by name.
    kill -TERM -- "-${pid}" 2>/dev/null || kill -TERM "${pid}" 2>/dev/null || true
    for _ in $(seq 1 20); do
      is_running_pid "${pid}" || break
      sleep 0.2
    done
    if is_running_pid "${pid}"; then
      [ "${quiet}" = "1" ] || echo "Force stopping ${name} pid=${pid}..."
      kill -KILL -- "-${pid}" 2>/dev/null || kill -KILL "${pid}" 2>/dev/null || true
    fi
  else
    [ "${quiet}" = "1" ] || echo "${name}: pid is not running."
  fi
  rm -f "${pid_file}"
}

get_ngrok_path() {
  if [ -x "${NGROK_DIR}/ngrok" ]; then
    printf '%s\n' "${NGROK_DIR}/ngrok"
    return 0
  fi
  command -v ngrok 2>/dev/null || true
}

get_devspace_path() {
  if [ -x "${NPM_PREFIX}/bin/devspace" ]; then
    printf '%s\n' "${NPM_PREFIX}/bin/devspace"
    return 0
  fi
  command -v devspace 2>/dev/null || true
}

clear_ngrok_proxy_environment() {
  # Free ngrok accounts cannot run an agent through an HTTP/S proxy.
  unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy
}

normalize_public_url() {
  local url="${1:-}"
  url="${url%/}"
  if [[ ! "${url}" =~ ^https://[^/?#]+$ ]]; then
    echo "ERROR: NGROK_PUBLIC_URL must be an HTTPS origin only, for example https://example.ngrok-free.dev" >&2
    return 1
  fi
  printf '%s\n' "${url}"
}

get_ngrok_endpoint() {
  local api_base="${1:-http://127.0.0.1:4040/api}"
  local json=""
  json="$(curl -fsS --max-time 3 "${api_base}/endpoints" 2>/dev/null || true)"
  if [ -z "${json}" ]; then
    json="$(curl -fsS --max-time 3 "${api_base}/tunnels" 2>/dev/null || true)"
  fi
  [ -n "${json}" ] || return 0
  node -e '
let input = "";
process.stdin.on("data", chunk => input += chunk);
process.stdin.on("end", () => {
  try {
    const data = JSON.parse(input);
    const candidates = [...(data.endpoints || []), ...(data.tunnels || [])];
    const endpoint = candidates.find(item => typeof item.public_url === "string" && item.public_url.startsWith("https://"));
    if (endpoint) process.stdout.write(endpoint.public_url.replace(/\/$/, ""));
  } catch {}
});
' <<< "${json}"
}

wait_ngrok_endpoint() {
  local pid="${1:?missing pid}"
  local api_base="${2:-http://127.0.0.1:4040/api}"
  local timeout="${3:-30}"
  local attempts=$((timeout * 2))
  local url=""

  for _ in $(seq 1 "${attempts}"); do
    if ! is_running_pid "${pid}"; then
      echo "ERROR: ngrok exited before exposing an endpoint." >&2
      return 1
    fi
    url="$(get_ngrok_endpoint "${api_base}")"
    if [ -n "${url}" ]; then
      printf '%s\n' "${url}"
      return 0
    fi
    sleep 0.5
  done
  echo "ERROR: ngrok did not expose an endpoint within ${timeout} seconds." >&2
  return 1
}

local_mcp_status() {
  local port="${1:-7676}"
  curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://127.0.0.1:${port}/mcp" || true
}

write_current_env() {
  local public_url="${1:?missing public URL}"
  local roots="${2:?missing roots}"
  local port="${3:?missing port}"
  cat > "${RUN_DIR}/current.env" <<EOF
PUBLIC_BASE_URL=$(shell_quote "${public_url}")
MCP_URL=$(shell_quote "${public_url}/mcp")
DEVSPACE_ALLOWED_ROOTS=$(shell_quote "${roots}")
DEVSPACE_PORT=$(shell_quote "${port}")
EOF
}
