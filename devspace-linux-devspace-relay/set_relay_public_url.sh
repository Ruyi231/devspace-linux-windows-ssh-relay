#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"
load_config
url="${1:-}"
[[ "${url}" =~ ^https://[^/?#]+$ ]] || { echo "Usage: ./set_relay_public_url.sh https://your-domain.ngrok-free.dev" >&2; exit 1; }
NGROK_PUBLIC_URL="${url%/}"
save_loaded_config
echo "Saved Windows relay public URL: ${NGROK_PUBLIC_URL}"
