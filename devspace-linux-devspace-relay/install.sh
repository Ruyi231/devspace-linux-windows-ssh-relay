#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

need_sudo() {
  [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1
}

run_package_manager() {
  if need_sudo; then
    sudo "$@"
  else
    "$@"
  fi
}

install_basic_packages() {
  echo "[1/5] Checking basic packages..."
  local missing=0
  for command_name in bash curl git tar xz; do
    command -v "${command_name}" >/dev/null 2>&1 || missing=1
  done
  if [ "${missing}" = "0" ]; then
    echo "      bash/curl/git/tar/xz are available."
    return
  fi

  if command -v apt-get >/dev/null 2>&1; then
    run_package_manager apt-get update
    run_package_manager apt-get install -y bash curl git ca-certificates tar xz-utils
  elif command -v dnf >/dev/null 2>&1; then
    run_package_manager dnf install -y bash curl git ca-certificates tar xz
  elif command -v yum >/dev/null 2>&1; then
    run_package_manager yum install -y bash curl git ca-certificates tar xz
  elif command -v apk >/dev/null 2>&1; then
    run_package_manager apk add --no-cache bash curl git ca-certificates tar xz
  else
    echo "ERROR: Please install bash, curl, git, tar and xz, then rerun this script." >&2
    exit 1
  fi
}

download_file() {
  local url="${1:?missing URL}"
  local destination="${2:?missing destination}"
  local attempt
  for attempt in 1 2 3 4; do
    rm -f "${destination}"
    echo "      Download attempt ${attempt}/4"
    if curl -fL --retry 3 --retry-delay 2 --connect-timeout 30 --max-time 300 -o "${destination}" "${url}"; then
      [ -s "${destination}" ] && return 0
    fi
    sleep "${attempt}"
  done
  echo "ERROR: Download failed: ${url}" >&2
  return 1
}

node_is_compatible() {
  local node_bin="${1:?missing node path}"
  [ -x "${node_bin}" ] || return 1
  "${node_bin}" -e '
const [major, minor] = process.versions.node.split(".").map(Number);
process.exit(((major > 22 || (major === 22 && minor >= 19)) && major < 27) ? 0 : 1);
' >/dev/null 2>&1
}

linux_node_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'x64\n' ;;
    aarch64|arm64) printf 'arm64\n' ;;
    *) echo "ERROR: Unsupported Linux architecture: $(uname -m)" >&2; return 1 ;;
  esac
}

install_node() {
  echo "[2/5] Checking local Node.js..."
  local node_bin="${NODE_DIR}/bin/node"
  if node_is_compatible "${node_bin}"; then
    echo "      Node $(${node_bin} -v) is OK: ${node_bin}"
    return
  fi

  local arch version archive_name url temp_dir extracted
  arch="$(linux_node_arch)"
  version="$( (curl -fsSL --max-time 30 https://nodejs.org/dist/index.json || true) | grep -oE '"version":"v24\.[0-9]+\.[0-9]+"' | head -n 1 | cut -d '"' -f 4)"
  if [ -z "${version}" ]; then
    echo "ERROR: Could not resolve a Node.js 24 release from nodejs.org." >&2
    exit 1
  fi
  archive_name="node-${version}-linux-${arch}.tar.xz"
  url="https://nodejs.org/dist/${version}/${archive_name}"
  temp_dir="$(mktemp -d)"
  extracted="${temp_dir}/node-${version}-linux-${arch}"
  echo "      Downloading local Node.js ${version}..."
  if ! download_file "${url}" "${temp_dir}/${archive_name}" || ! tar -xJf "${temp_dir}/${archive_name}" -C "${temp_dir}" || [ ! -x "${extracted}/bin/node" ]; then
    rm -rf "${temp_dir}"
    echo "ERROR: Node.js archive download or extraction failed." >&2
    exit 1
  fi
  rm -rf "${NODE_DIR}"
  mv "${extracted}" "${NODE_DIR}"
  rm -rf "${temp_dir}"
  node_is_compatible "${NODE_DIR}/bin/node" || { echo "ERROR: Local Node.js version is invalid." >&2; exit 1; }
  echo "      Node $(${NODE_DIR}/bin/node -v) installed locally."
}

install_devspace() {
  echo "[3/5] Installing DevSpace CLI..."
  local npm_bin="${NODE_DIR}/bin/npm"
  [ -x "${npm_bin}" ] || { echo "ERROR: npm was not installed with local Node.js." >&2; exit 1; }
  "${npm_bin}" install -g --prefix "${NPM_PREFIX}" @waishnav/devspace
  local devspace_bin
  devspace_bin="$(get_devspace_path)"
  [ -n "${devspace_bin}" ] || { echo "ERROR: DevSpace CLI was not found after npm install." >&2; exit 1; }
  echo "      DevSpace installed: ${devspace_bin}"
  "${devspace_bin}" --version
}

linux_ngrok_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'amd64\n' ;;
    aarch64|arm64) printf 'arm64\n' ;;
    *) echo "ERROR: Unsupported Linux architecture: $(uname -m)" >&2; return 1 ;;
  esac
}

install_ngrok() {
  echo "[4/5] Installing ngrok..."
  local ngrok_bin="${NGROK_DIR}/ngrok"
  if [ -x "${ngrok_bin}" ]; then
    echo "      ngrok already exists: $(${ngrok_bin} version)"
    return
  fi

  local arch url temp_dir archive extracted
  arch="$(linux_ngrok_arch)"
  url="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-${arch}.tgz"
  temp_dir="$(mktemp -d)"
  archive="${temp_dir}/ngrok.tgz"
  echo "      Downloading the current official ngrok Linux build..."
  if ! download_file "${url}" "${archive}" || ! tar -xzf "${archive}" -C "${temp_dir}"; then
    rm -rf "${temp_dir}"
    echo "ERROR: ngrok archive download or extraction failed." >&2
    exit 1
  fi
  extracted="$(find "${temp_dir}" -type f -name ngrok -perm -u+x -print -quit)"
  if [ -z "${extracted}" ]; then
    rm -rf "${temp_dir}"
    echo "ERROR: ngrok archive did not contain an executable." >&2
    exit 1
  fi
  mkdir -p "${NGROK_DIR}"
  install -m 0755 "${extracted}" "${ngrok_bin}"
  rm -rf "${temp_dir}"
  echo "      $(${ngrok_bin} version)"
}

initialize_config() {
  echo "[5/5] Creating config.env..."
  ensure_config
  echo "      Config file: ${CONFIG_FILE}"
  echo
  echo "Install complete. Next steps:"
  echo "  1) Configure ngrok:  ./setup_ngrok.sh"
  echo "  2) Set project root: ./set_project.sh /path/to/your/project"
  echo "  3) Start service:    ./start.sh"
  echo
  echo "Owner password is saved in: ${CONFIG_FILE}"
  echo "Do not share config.env with others."
}

install_basic_packages
install_node
load_config
install_devspace
echo "[4/5] Skipping ngrok; the Windows relay owns the public tunnel."
initialize_config
