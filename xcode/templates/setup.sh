#!/usr/bin/env bash
# Xcode file templates — run every templates/*/setup.sh.
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/../.." && pwd)}"
. "${DOTFILES}/lib/common.sh"
require_macos

CURRENT_DIR="$(module_dir)"

for script in "${CURRENT_DIR}"/*/setup.sh; do
  [ -f "${script}" ] || continue
  bash "${script}"
done

ok "Xcode templates installed."
