#!/usr/bin/env bash
#
# Runs, on demand, the three checks `.github/workflows/lint.yml` runs — so a
# push costs twenty seconds to learn what CI would report twenty minutes later.
#
# Three of that workflow's checks and only these three: shellcheck over
# `scripts/ci/list-shell-scripts.sh`, `zsh -n` over the workflow's own file set,
# and editorconfig-checker with the workflow's exclude pattern. The rest of the
# workflow needs node, docker and pipx; these are the ones that fail on the
# edits that actually happen in this repo.
#
# A linter that is missing, or that cannot be downloaded, FAILS this script
# rather than being skipped quietly. A check that cannot fail is worse than no
# check, and a local run that is green while CI is red is worse than either.
#
# Where it differs from CI it is stricter, never looser: editorconfig-checker
# also sees untracked files you have not committed yet. Ignored paths (.omc/,
# .herdr/) are skipped exactly as a clean checkout skips them.
set -euo pipefail

EC_VERSION=v4.0.1
EC_BASE_URL="https://github.com/editorconfig-checker/editorconfig-checker/releases/download/${EC_VERSION}"

# Verbatim from the workflow's `ec` step. Markdown tables are hand-wrapped and
# don't align on multiples of 2 (see .markdownlint-cli2.jsonc MD013/MD060);
# gitconfig, plists and vendored Xcode templates use their own tab/format
# conventions.
EC_EXCLUDE='\.md$|\.plist$|\.xccolortheme$|\.terminal$|^git/gitconfig$|^xcode/templates/'

cd "$(git rev-parse --show-toplevel)"

# Echoes "<asset-suffix> <sha256>" for this machine, or returns 1 when v4.0.1
# published no build for it. The digests are the ones that release's own
# checksums.txt carries; the linux-amd64 one is the same digest the workflow
# pins inline, so a mismatch here would mean the two disagree about the binary.
ec_platform() {
  case "$(uname -s)" in
    Darwin)
      # A single universal binary covers both Apple arches — there is nothing
      # for `uname -m` to choose between here.
      printf 'darwin-all %s\n' 9ed547505176d7384e1fb861ecfdd13df8c15e37d4bbcc2bd40e52e81ab32176
      ;;
    Linux)
      case "$(uname -m)" in
        x86_64 | amd64) printf 'linux-amd64 %s\n' 90139c6ed52373c0acfc9deb2a07aa812e5184753afd4bc8252bf44eb4909155 ;;
        aarch64 | arm64) printf 'linux-arm64 %s\n' f162c749ade763ed4954de678ebb786c99431b9a615a964c284605e68dbbd3f9 ;;
        *) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    printf 'lint-local: neither sha256sum nor shasum is available to verify the download\n' >&2
    return 1
  fi
}

join_by() {
  local sep="$1" first=1 item
  shift
  for item in "$@"; do
    if [ "$first" -eq 1 ]; then
      first=0
    else
      printf '%s' "$sep"
    fi
    printf '%s' "$item"
  done
}

# Downloads, verifies and caches the checker, then echoes the binary's path.
# Nothing lands in a system location: the tarball and the extracted binary both
# live under $TMPDIR, keyed by version and asset so a version bump cannot pick
# up a stale binary. The digest is re-checked on every run, not just the first,
# because a cache is not evidence.
ensure_ec() {
  local platform asset want cache tarball binary got
  if ! platform="$(ec_platform)"; then
    printf 'lint-local: v%s publishes no build for %s/%s\n' \
      "$EC_VERSION" "$(uname -s)" "$(uname -m)" >&2
    return 1
  fi
  asset="${platform%% *}"
  want="${platform##* }"

  cache="${TMPDIR:-/tmp}"
  cache="${cache%/}/dotfiles-lint-local"
  if ! mkdir -p "$cache"; then
    printf 'lint-local: cannot create cache directory %s\n' "$cache" >&2
    return 1
  fi
  tarball="$cache/editorconfig-checker-${EC_VERSION}-${asset}.tar.gz"
  binary="$cache/editorconfig-checker-${EC_VERSION}-${asset}"

  if [ ! -f "$tarball" ]; then
    # stderr: this function's stdout is its return value, the binary's path.
    printf 'lint-local: fetching editorconfig-checker %s (%s)\n' "$EC_VERSION" "$asset" >&2
    if ! curl -fsSL --retry 2 -o "${tarball}.part" \
      "${EC_BASE_URL}/editorconfig-checker-${asset}.tar.gz"; then
      rm -f "${tarball}.part"
      printf 'lint-local: could not download editorconfig-checker %s\n' "$EC_VERSION" >&2
      return 1
    fi
    mv "${tarball}.part" "$tarball"
  fi

  if ! got="$(sha256_file "$tarball")"; then
    return 1
  fi
  if [ "$got" != "$want" ]; then
    rm -f "$tarball" "$binary"
    printf 'lint-local: editorconfig-checker %s (%s) failed its checksum\n' "$EC_VERSION" "$asset" >&2
    printf 'lint-local:   expected %s\n' "$want" >&2
    printf 'lint-local:   got      %s\n' "$got" >&2
    return 1
  fi

  if [ ! -x "$binary" ]; then
    if ! tar -xzf "$tarball" -C "$cache" editorconfig-checker; then
      printf 'lint-local: could not extract editorconfig-checker from %s\n' "$tarball" >&2
      return 1
    fi
    mv "$cache/editorconfig-checker" "$binary"
    chmod +x "$binary"
  fi

  printf '%s\n' "$binary"
}

check_shellcheck() {
  local -a files=()
  while IFS= read -r file; do
    files+=("$file")
  done < <(scripts/ci/list-shell-scripts.sh)

  if [ "${#files[@]}" -eq 0 ]; then
    printf 'lint-local: no shell scripts found to check\n'
    return 0
  fi
  if ! command -v shellcheck >/dev/null 2>&1; then
    printf 'lint-local: shellcheck is not installed, so %d script(s) went unchecked\n' \
      "${#files[@]}" >&2
    return 1
  fi
  shellcheck -x "${files[@]}"
}

check_zsh() {
  local -a files=() bad=()
  local file
  while IFS= read -r file; do
    files+=("$file")
  done < <(git ls-files '*.zsh' 'zsh/zshrc' 'zsh/zshenv')

  if [ "${#files[@]}" -eq 0 ]; then
    printf 'lint-local: no zsh files found to check\n'
    return 0
  fi
  if ! command -v zsh >/dev/null 2>&1; then
    printf 'lint-local: zsh is not installed, so %d file(s) went unchecked\n' \
      "${#files[@]}" >&2
    return 1
  fi

  # One invocation per file, deliberately. `zsh -n a.zsh b.zsh` parses only
  # a.zsh and hands b.zsh to it as $1 — so the workflow's single
  # `zsh -n "${files[@]}"` step checks one file and silently ignores the rest.
  # This loop is the check that step means to run.
  for file in "${files[@]}"; do
    if ! zsh -n "$file"; then
      bad+=("$file")
    fi
  done
  if [ "${#bad[@]}" -ne 0 ]; then
    printf 'lint-local: %d zsh file(s) failed to parse\n' "${#bad[@]}" >&2
    return 1
  fi
}

check_editorconfig() {
  local binary
  if ! binary="$(ensure_ec)"; then
    printf 'lint-local: editorconfig-checker unavailable — refusing to report a pass\n' >&2
    return 1
  fi
  # `ec` walks the tree and honours .gitignore, so the state directories that
  # exist only on a working copy (.omc/, .herdr/) are skipped the way a clean
  # checkout skips them. It does still check untracked files that are not
  # ignored, which is stricter than CI and never looser.
  "$binary" -exclude "$EC_EXCLUDE"
}

main() {
  local -a failed=()
  local name
  for name in shellcheck zsh editorconfig; do
    printf '\n==> %s\n' "$name"
    if ! "check_$name"; then
      failed+=("$name")
    fi
  done

  printf '\n'
  if [ "${#failed[@]}" -ne 0 ]; then
    printf 'lint-local: FAILED — %s\n' "$(join_by ', ' "${failed[@]}")"
    return 1
  fi
  printf 'lint-local: all checks passed\n'
}

main "$@"
