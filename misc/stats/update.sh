#!/usr/bin/env bash
# Dump the live Stats preferences back into the repo, for reconciliation.
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/../.." && pwd)}"
. "${DOTFILES}/lib/common.sh"
require_macos

CURRENT_DIR="$(module_dir)"
PLIST="${CURRENT_DIR}/eu.exelban.Stats.plist"

defaults export eu.exelban.Stats "${PLIST}"
# Drop the per-install remote-monitoring pairing ID — machine-specific, not
# something to publish.
/usr/libexec/PlistBuddy -c "Delete :remote_id" \
  -c "Delete :remote_tokens_migrated_to_keychain" "${PLIST}" 2>/dev/null || true
plutil -convert xml1 "${PLIST}"
ok "wrote ${PLIST#"${DOTFILES}"/}"
