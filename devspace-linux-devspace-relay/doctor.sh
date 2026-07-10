#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"
load_config

failed=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; failed=1; }
command -v bash >/dev/null 2>&1 && pass "bash: $(command -v bash)" || fail "bash is missing"
[ -x "${NODE_DIR}/bin/node" ] && pass "local Node: $(${NODE_DIR}/bin/node -v)" || fail "local Node is missing"
devspace_bin="$(get_devspace_path)"; [ -n "${devspace_bin}" ] && pass "DevSpace: ${devspace_bin}" || fail "DevSpace is missing"
ngrok_bin="$(get_ngrok_path)"; [ -n "${ngrok_bin}" ] && pass "ngrok: $(${ngrok_bin} version)" || fail "ngrok is missing"
[ -n "${DEVSPACE_OAUTH_OWNER_TOKEN}" ] && pass "Owner password is configured" || fail "Owner password is missing"
[ -n "${NGROK_PUBLIC_URL}" ] && normalize_public_url "${NGROK_PUBLIC_URL}" >/dev/null && pass "NGROK_PUBLIC_URL is valid" || fail "NGROK_PUBLIC_URL is not configured"
IFS=',' read -r -a roots <<< "${DEVSPACE_ALLOWED_ROOTS}"
for root in "${roots[@]}"; do [ -d "${root}" ] && pass "Project root: ${root}" || fail "Missing project root: ${root}"; done
[ "${failed}" = "0" ] && echo "Doctor result: PASS" || { echo "Doctor result: FAIL"; exit 1; }
