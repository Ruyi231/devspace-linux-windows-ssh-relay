#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"
LOG_DIR="${SCRIPT_DIR}/logs"
RUN_DIR="${SCRIPT_DIR}/run"
TOOLS_DIR="${SCRIPT_DIR}/tools"
NODE_DIR="${TOOLS_DIR}/node"
NPM_PREFIX="${TOOLS_DIR}/npm-global"

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
# DevSpace Linux Relay Target configuration
# Separate multiple project roots with commas.
DEVSPACE_ALLOWED_ROOTS=$(shell_quote "$HOME")
DEVSPACE_PORT='7676'
DEVSPACE_OAUTH_OWNER_TOKEN=$(shell_quote "$token")
DEVSPACE_TOOL_MODE='minimal'
DEVSPACE_WIDGETS='full'
NGROK_PUBLIC_URL=''
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

  if [ -z "${token}" ]; then
    token="$(new_owner_token)"
  fi

  cat > "${CONFIG_FILE}" <<EOF
# DevSpace Linux Relay Target configuration
# Separate multiple project roots with commas.
DEVSPACE_ALLOWED_ROOTS=$(shell_quote "$roots")
DEVSPACE_PORT=$(shell_quote "$port")
DEVSPACE_OAUTH_OWNER_TOKEN=$(shell_quote "$token")
DEVSPACE_TOOL_MODE=$(shell_quote "$tool_mode")
DEVSPACE_WIDGETS=$(shell_quote "$widgets")
NGROK_PUBLIC_URL=$(shell_quote "$public_url")
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
    "${NGROK_PUBLIC_URL}"
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
    # The relay target launches DevSpace in its own process group. Do not search
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

get_devspace_path() {
  if [ -x "${NPM_PREFIX}/bin/devspace" ]; then
    printf '%s\n' "${NPM_PREFIX}/bin/devspace"
    return 0
  fi
  command -v devspace 2>/dev/null || true
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

local_mcp_status() {
  local port="${1:-7676}"
  curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://127.0.0.1:${port}/mcp" || true
}
