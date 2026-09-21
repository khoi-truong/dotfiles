#!/usr/bin/env bash
#
# Runs, on demand, `.github/workflows/lint.yml` and the Python job in
# `.github/workflows/test.yml` — so a push costs twenty seconds to learn what CI
# would report twenty minutes later.
#
#   scripts/ci/lint-local.sh            every check in those two workflows
#   scripts/ci/lint-local.sh --quick    the three that need no download
#
# `--quick` is shellcheck over `scripts/ci/list-shell-scripts.sh`, `zsh -n`
# over the workflow's own file set, and editorconfig-checker: the three that
# fail on the edits that actually happen in this repo. The full run adds
# markdownlint-cli2, actionlint, zizmor, the two repo-rule scripts and the four
# Python checks, and needs node and uv; a runner has them, a laptop may not.
#
# A linter that is missing, or that cannot be downloaded, FAILS this script
# rather than being skipped quietly. A check that cannot fail is worse than no
# check, and a local run that is green while CI is red is worse than either.
#
# Where it differs from CI it is stricter, never looser: editorconfig-checker
# also sees untracked files, and the rule scripts read the working tree rather
# than the last commit — check-rules.sh over tracked files plus untracked ones
# that are not gitignored (its credential rule is index-only by design), and
# check-brewfile.sh over the file on disk — so an edit you have not committed is
# checked here and is not in a CI run of a commit that predates it. Ignored
# paths (.omc/, .herdr/) are skipped exactly as a clean checkout skips them.
#
# Every pin below is the one its workflow uses — lint.yml's for the shell, zsh,
# markdown, editorconfig, actionlint and zizmor checks, test.yml's for the four
# Python ones — and this file's steps mirror those files' steps. Bump them
# together: these files are the only places these tools are named, and a version
# that disagrees is a green local run that CI then fails.
set -euo pipefail

# Mirrors the pins in .github/workflows/lint.yml.
MARKDOWNLINT_CLI2_VERSION=0.23.2
# Upstream actionlint 1.7.12, which lint.yml runs from the digest-pinned
# `rhysd/actionlint:1.7.12` image. actionlint itself is not on PyPI — `uvx
# actionlint@1.7.12` does not resolve — so this is the wrapper package that
# carries the release binary, whose version is the upstream one plus the
# wrapper's own release number. `--from` is required because the package and
# the executable it provides are named differently.
ACTIONLINT_PY_VERSION=1.7.12.24
ZIZMOR_VERSION=1.30.1

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

# A tool that is absent is a failure, not a skip — see the header. `$1` is the
# binary, `$2` names the check in the message.
require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'lint-local: %s is not installed, so the %s check did not run\n' \
      "$1" "$2" >&2
    return 1
  fi
}

# The two repo-rule scripts are bash, so they are run rather than reimplemented.
# A missing script fails the same way a missing binary does: bash exits 127.
check_rules() {
  bash scripts/ci/check-rules.sh
}

check_brewfile() {
  bash scripts/ci/check-brewfile.sh
}

check_markdown() {
  local -a files=()
  local file
  # The workflow's file set, and the same pinned version.
  while IFS= read -r file; do
    files+=("$file")
  done < <(git ls-files '*.md')

  if [ "${#files[@]}" -eq 0 ]; then
    printf 'lint-local: no markdown files found to check\n'
    return 0
  fi
  require_tool npx markdownlint || return 1
  npx --yes "markdownlint-cli2@${MARKDOWNLINT_CLI2_VERSION}" "${files[@]}"
}

check_actionlint() {
  require_tool uvx actionlint || return 1
  # actionlint-py ships actionlint but not shellcheck. With none on PATH,
  # actionlint skips that pass silently; CI's `docker://rhysd/actionlint` image
  # always has one, so the skip would make this run looser than CI — the one
  # thing this script promises not to be. Refusing is the only safe answer: the
  # findings it would have produced are invisible either way.
  if ! command -v shellcheck >/dev/null 2>&1; then
    printf 'lint-local: actionlint needs shellcheck on PATH, or it silently\n' >&2
    printf 'lint-local: skips its shellcheck pass and reports less than CI does\n' >&2
    return 1
  fi
  # No path argument, so actionlint finds .github/workflows from the repository
  # root — the same thing the `docker://rhysd/actionlint` step does in CI.
  uvx --from "actionlint-py@${ACTIONLINT_PY_VERSION}" actionlint -color
}

check_zizmor() {
  require_tool uvx zizmor || return 1
  uvx "zizmor@${ZIZMOR_VERSION}" --persona=regular .github/workflows
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
  # a.zsh and hands b.zsh to it as $1, so a single call checks one file and
  # silently ignores the rest. The workflow's step loops the same way.
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

# The four Python checks test.yml's `python` job runs, in that job's order —
# cheapest first, and the two ruff passes ahead of the two that read every file.
#
# `uvx` is where the three versions are pinned, and they are the versions that
# job uses. The runner installs uv itself first (`pipx install uv==…`), because
# it has no mise; that pin is the one thing here and there that does not match,
# and it is uv's own version rather than a tool's, so there is nothing for this
# file to mirror.
#
# From `ai/herdr`, in a subshell: all three read `pyproject.toml` from the
# directory they are run in, and that is where it is. From the repo root none of
# them finds it — `ruff` falls back to its defaults and checks the whole tree,
# `mypy` has no target to check, and `pytest` collects without `lib/` on the
# path. Each of those fails for its own reason instead of the real one, which is
# a red run that names the wrong thing.
check_python() {
  require_tool uvx python || return 1
  (
    cd ai/herdr || exit 1
    # `--with pytest` because the tests import it: an unresolved import leaves
    # every `pytest.mark.parametrize` untyped, and the test function under it
    # with it. `ai/herdr/pyproject.toml` deliberately carries no
    # `ignore_missing_imports` for pytest — the fix is here, not there.
    uvx ruff@0.16.8 check . &&
      uvx ruff@0.16.8 format --check . &&
      uvx --with pytest==9.1.1 mypy@2.3.1 --strict &&
      uvx pytest@9.1.1
  )
}

main() {
  local -a checks=() failed=()
  local name

  case "${1:-}" in
    --quick)
      checks=(shellcheck zsh editorconfig)
      ;;
    '')
      # Cheapest first, so a rule violation does not wait on three downloads;
      # the order matches lint.yml's step order within each job. `python` is the
      # one check from another workflow, so it is placed by that rule rather than
      # by step order: it is not free either — uvx fetches three tools the first
      # time — but uv caches what it fetches, and this run already needs uv for
      # actionlint and zizmor, so it goes after the four checks that fetch
      # nothing and before the three that fetch more.
      checks=(rules brewfile shellcheck zsh editorconfig python markdown actionlint zizmor)
      ;;
    *)
      printf 'lint-local: unknown option: %s\n' "$1" >&2
      printf 'usage: lint-local.sh [--quick]\n' >&2
      return 2
      ;;
  esac

  for name in "${checks[@]}"; do
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
