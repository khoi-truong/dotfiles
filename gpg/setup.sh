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

[ -d "${GNUPGHOME}" ] || mkdir -m 700 "${GNUPGHOME}"
chmod 700 "${GNUPGHOME}"

CAND="$(mktemp -d)"
trap 'rm -rf "${CAND}"' EXIT
cp "${CURRENT_DIR}/gpg.conf" "${CAND}/gpg.conf"
sed "s|__PINENTRY__|${PINENTRY}|" "${CURRENT_DIR}/gpg-agent.conf.template" >"${CAND}/gpg-agent.conf"

changed=()
for name in gpg.conf gpg-agent.conf; do
  dest="${GNUPGHOME}/${name}"
  if [ -f "${dest}" ] && cmp -s "${CAND}/${name}" "${dest}"; then
    ok "${dest} (unchanged)"
    continue
  fi
  if [ -f "${dest}" ]; then
    diff -u "${dest}" "${CAND}/${name}" || true
  else
    diff -u /dev/null "${CAND}/${name}" || true
  fi
  changed+=("${name}")
done

if [ "${#changed[@]}" -eq 0 ]; then
  exit 0
fi

if [ -t 0 ]; then
  printf 'Write these GPG changes? [y/N] '
  read -r answer || answer=''
  case "${answer}" in
    y | Y | yes | YES | Yes) ;;
    *)
      log "GPG configuration unchanged"
      exit 0
      ;;
  esac
fi

for name in "${changed[@]}"; do
  install -m 600 "${CAND}/${name}" "${GNUPGHOME}/${name}"
  ok "${GNUPGHOME}/${name}"
done

if command -v gpgconf >/dev/null 2>&1; then
  gpgconf --reload gpg-agent 2>/dev/null || true
fi
