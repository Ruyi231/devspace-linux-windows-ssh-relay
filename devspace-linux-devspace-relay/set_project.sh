#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"
load_config

[ "$#" -gt 0 ] || { echo "Usage: ./set_project.sh /path/to/project [another/project]" >&2; exit 1; }
roots=()
for path in "$@"; do
  [ -d "${path}" ] || { echo "ERROR: Directory does not exist: ${path}" >&2; exit 1; }
  roots+=("$(realpath_safe "${path}")")
done
joined="$(IFS=,; echo "${roots[*]}")"
DEVSPACE_ALLOWED_ROOTS="${joined}"
save_loaded_config
echo "Saved project roots: ${joined}"
