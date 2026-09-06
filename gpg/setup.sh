#!/usr/bin/env bash
# gpg — install the declarative parts of ~/.gnupg.
#
# Copies (not symlinks — gpg is strict about ~/.gnupg being a real dir with
# 700/600 perms) gpg.conf and a rendered gpg-agent.conf. Keys, ownertrust and
# trustdb are never touched. common.conf (use-keyboxd etc.) is left alone.
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/.." && pwd)}"
. "${DOTFILES}/lib/common.sh"
require_macos

CURRENT_DIR="$(module_dir)"
GNUPGHOME="${HOME}/.gnupg"

info "Setting up gpg..."

PINENTRY="$(brew_prefix)/bin/pinentry-mac"
[ -x "${PINENTRY}" ] || warn "pinentry-mac not found at ${PINENTRY}; run \`brew install pinentry-mac\`."

mkdir -p "${GNUPGHOME}"
chmod 700 "${GNUPGHOME}"

install -m 600 "${CURRENT_DIR}/gpg.conf" "${GNUPGHOME}/gpg.conf"
ok "${GNUPGHOME}/gpg.conf"

sed "s|__PINENTRY__|${PINENTRY}|" "${CURRENT_DIR}/gpg-agent.conf.template" \
  >"${GNUPGHOME}/gpg-agent.conf"
chmod 600 "${GNUPGHOME}/gpg-agent.conf"
ok "${GNUPGHOME}/gpg-agent.conf (pinentry-program = ${PINENTRY})"

if command -v gpgconf >/dev/null 2>&1; then
  gpgconf --reload gpg-agent 2>/dev/null || true
fi
