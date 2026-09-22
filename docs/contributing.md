# Contributing

- [Workflow](#workflow)
- [Ground rules](#ground-rules)
- [Writing a module](#writing-a-module)
- [Formatting](#formatting)
- [Checking changes](#checking-changes)
- [CI](#ci)

## Workflow

- **Branch and PR for every change**; never commit to `main`.
- **Sign every commit** (`commit.gpgSign = true`). Don't rewrite history with
  `git filter-branch` — it strips signatures.
- **PR title** in Conventional Commits form, ≤ ~50 characters: it becomes the
  squash-merge subject. Put detail in the body, following
  `.github/PULL_REQUEST_TEMPLATE.md` (What / Why / Related / Verification).

## Ground rules

- **Don't break the shell.** `~/.zshrc` is a symlink into this repo, so a
  syntax error in `zsh/*.zsh` breaks every new terminal. Run `zsh -n` on every
  zsh file you touch, and test with an isolated `ZDOTDIR`.
- **Startup time is a feature.** Compare `ZSH_PROFILE=1 zsh -i -c exit` before
  and after any `zsh/` change. Anything that adds a subprocess to every shell
  start needs to justify itself.
- **One version manager.** mise owns python, node, ruby, go and java. No
  `pyenv`/`rbenv`/`jenv`/`nvm`/`asdf` init hooks.
- **Dual-arch.** Use `brew_prefix` from `lib/common.sh`; never hardcode
  `/opt/homebrew` or `/usr/local`.
- **Secrets never land in the repo.** Only declarative config is versioned;
  keys come from 1Password (see [Secrets](installation.md#secrets)).
- **Brewfile edits are consequential.** `brew bundle cleanup` uninstalls
  everything the file doesn't list.

`scripts/ci/check-rules.sh` enforces the prefix, version-manager and
credential rules with a grep.

## Writing a module

Each top-level directory is a self-contained module with a `setup.sh` that can
run on its own and is safe to re-run. Add it to `DEFAULT_MODULES` or
`OPTIONAL_MODULES` in the root `setup.sh`.

```sh
#!/usr/bin/env bash
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/.." && pwd)}"
. "${DOTFILES}/lib/common.sh"
require_macos
```

`lib/common.sh` provides:

| Helper | Does |
| --- | --- |
| `log`, `info`, `ok`, `warn`, `die` | Output |
| `require_macos`, `is_arm` | Platform checks |
| `brew_prefix`, `load_brew_shellenv` | Homebrew location, dual-arch |
| `link <src> <dst>` | Idempotent symlink; backs up a real file as `*.dotfiles-backup` |
| `module_dir` | The calling module's directory |

Document the module in the matching guide under `docs/` and add a row to the
README's module table.

## Formatting

`.editorconfig` governs formatting: 2-space indent, LF, final newline, trimmed
trailing whitespace (except in `*.md` and `*.diff`). C-family and Python use 4
spaces; Makefiles use tabs. Markdown is linted per `.markdownlint-cli2.jsonc`:
dash list markers, and a language on every fenced code block (`text` when
there isn't one).

## Checking changes

There is no build and no repo-wide test suite.

```sh
scripts/ci/lint-local.sh --quick   # shellcheck, zsh -n, editorconfig — no downloads
scripts/ci/lint-local.sh           # everything lint.yml and the Python job run
ai/herdr/tests/run.sh              # after touching ai/herdr/ or lib/
```

`lint-local.sh` fails, rather than skips, when a linter is missing, and is
stricter than CI: it also checks untracked files. The full run needs node and
`uv`.

## CI

Runs on every push to `main` and every pull request.

| Workflow | Runs |
| --- | --- |
| `lint.yml` | `shellcheck -x`, `zsh -n`, markdownlint, editorconfig-checker, JSON and TOML validation, actionlint, zizmor, the repo-rule scripts |
| `secrets.yml` | gitleaks over every pushed commit, no path filter |
| `smoke.yml` | macOS, when shell config, `setup.sh`, `lib/` or a plist changed: lints plists, links the zsh config into a throwaway `HOME`, fails on any stderr or a warm start over 1.5 s |
| `test.yml` | macOS, when `ai/herdr/` or `lib/` changed: the herdr suite with `HERDR_TESTS_STRICT=1`, plus the Python checks |
| `pr-title.yml` | Conventional Commits title; warns past 50 characters, fails past 72 |

Path filters live in the reusable `_detect-changes.yml`. Skipped jobs report
success, so they can be required checks. Dependabot keeps the pinned action
versions current. Before touching anything under `.github/`, read the
conventions in `ai/shared/skills/github-actions/references/`.
