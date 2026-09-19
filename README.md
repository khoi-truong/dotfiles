# dotfiles

Personal macOS configuration for `khoi`. Clone to `~/.dotfiles` — the path is
hardcoded in `zsh/zshenv`, so anywhere else will not work.

```sh
git clone https://github.com/khoi/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./setup.sh
```

Everything is macOS-only and idempotent: re-running any script is always safe.

## Bootstrap

```sh
./setup.sh              # default modules
./setup.sh --all        # default + opt-in modules
./setup.sh vscode git   # only the named modules, in the order given
./setup.sh --list       # show what's available
```

`setup.sh` installs Homebrew if missing, links the shell dotfiles into `$HOME`,
then runs each module's `setup.sh`.

|             | Modules                                                  |
| ----------- | -------------------------------------------------------- |
| **default** | `git` `brew` `mise` `macos` `gpg` `iterm` `ai` `misc`    |
| **opt-in**  | `vscode` `xcode` `terminal`                              |

The opt-in ones need a GUI app that may not be installed, or only matter on
some machines.

## How things get installed

Two mechanisms, depending on whether the app reads a config file.

**Symlinks** — the repo file is linked into `$HOME` or an app's support
directory, so edits in the repo are live immediately.

| Repo                                                    | Linked to                               |
| ------------------------------------------------------- | --------------------------------------- |
| `zsh/zshenv`, `zsh/zshrc`                               | `~/.zshenv`, `~/.zshrc`                 |
| `git/gitconfig`                                         | `~/.gitconfig`                          |
| `git/ignore`                                            | `~/.config/git/ignore`                  |
| `git/lazygit.yml`                                       | lazygit's Application Support dir       |
| `ssh/config`                                            | `~/.ssh/config`                         |
| `curl/curlrc`, `tmux/tmux.conf`, `vim/vimrc`            | `~/.curlrc`, `~/.tmux.conf`, `~/.vimrc` |
| `mise/global.toml`                                      | `~/.config/mise/config.toml`            |
| `ai/claude/*`                                           | `~/.claude/`                            |
| `ai/copilot/*`                                          | `~/.copilot/`                           |
| `ai/omp/*`, `ai/shared/skills`, `ai/shared/rules/common.md` (as `AGENTS.md`) | `~/.omp/agent/` |
| `ai/shared/skills/*`                                    | `~/.claude/skills/`                     |
| `ai/herdr/config.toml`                                  | `~/.config/herdr/config.toml`           |
| `vscode/{settings,keybindings}.json`, `vscode/snippets` | VS Code user dir                        |

`ai/` is split by harness (`claude/`, `omp/`, `copilot/`), with what they
share in `ai/shared/`: `rules/common.md`, the global instructions every harness
loads, and `skills/`, Agent Skills that Claude Code and omp both read. Each
harness keeps its own model/provider and MCP config, since the formats differ.

**Preference redirection** — for apps with no dotfile.

- `macos/setup.sh` is a large `defaults write` script (mathiasbynens lineage;
  timezone `Asia/Ho_Chi_Minh`, forced Dark mode). Needs sudo, and restarts
  Finder/Dock at the end.
- iTerm2 is pointed at `iterm/` via its "load preferences from a custom folder"
  setting. iTerm writes the plist back there on quit, so commit from the repo.
- Terminal.app imports its theme through `osascript`.
- `gpg/setup.sh` copies `gpg.conf` and a rendered `gpg-agent.conf` (arch-correct
  `pinentry-mac` path) into `~/.gnupg`. Copied, not symlinked — gpg insists on a
  real `700` directory. Keys and `trustdb` are never versioned.
- `git/template/` is linked to `~/.config/git/template` (`init.templateDir`), so
  every new clone gets a `pre-commit` hook that runs `gitleaks` on staged
  changes. Existing repos pick it up with `git init`; the hook skips itself
  when gitleaks is missing, and `--no-verify` bypasses it once.
  It also installs a `post-checkout` hook for worktrees: when
  `git worktree add` creates one, each path listed in the main checkout's
  `.worktreeclone` (e.g. `node_modules`, generated code) is cloned into it
  with APFS copy-on-write, so there is nothing to reinstall or regenerate.
  Claude Code's `--worktree` skips git hooks, so a `SessionStart` hook in
  `ai/claude/settings.json` runs the same script. Don't list virtualenvs;
  they embed absolute paths. `git wta <branch>` adds `../<repo>-<branch>`,
  `wt` jumps between worktrees with fzf, and `git tidy` prunes stale ones.
- Stats (menu bar monitor) has its prefs imported by `misc/stats/setup.sh` from
  `misc/stats/eu.exelban.Stats.plist`; re-dump with `bash misc/stats/update.sh`.

## Shell

`zshenv` → `zshrc`, which sources in this order:

1. `zsh/env.zsh` — `$PATH` and toolchain environment, built once and
   deduplicated with `typeset -U path`.
2. `zsh/config.zsh` — options, history, editor.
3. `zsh/omz.zsh` — oh-my-zsh settings; must precede the plugin bundle.
4. `zsh/local/plugins.zsh` — the antidote bundle.
5. `zsh/aliases.zsh`, `zsh/aliases.macos.zsh`, `zsh/functions.zsh`,
   `ai/aliases.zsh` (which sources `ai/claude/providers.zsh`) — after plugins,
   so these win.
6. mise, fzf, zoxide. Their init scripts are cached in `zsh/local/init-*.zsh`,
   keyed by binary path and rebuilt when the binary or `zshrc` changes (delete
   them to force a rebuild). The mise cache is also keyed on `$PATH`, the
   `MISE_*` variables and every mise config (and trust state) that applies to
   the current directory, so it rebuilds itself when any of those change. A
   miserc bypasses it, and a nested shell inside a project usually misses and
   runs `mise activate` live, as before.
7. `zsh/local/extra.zsh` — machine-local, gitignored.

**Plugins.** Managed by [antidote](https://getantidote.github.io/).
`zsh/zsh.plugins` is the list; `zsh/local/plugins.zsh` is the generated static
bundle, rebuilt automatically whenever the list is newer. The bundle and every
plugin file it sources are zcompiled once after each regeneration (`.zwc` next
to the source, in the gitignored cache). After `antidote update` or a zsh
upgrade, or to force a rebuild:

```sh
touch zsh/zsh.plugins && exec zsh
```

**Machine-local state.** `zsh/local/` is gitignored and holds the zsh, Python
and Node REPL histories, `lesshst`, the zcompdump, the generated bundle, and
`extra.zsh`. Anything an installer wants to append to `~/.zshrc` belongs in
`zsh/local/extra.zsh` instead.

**Startup time.** Roughly 350 ms. Profile it with:

```sh
ZSH_PROFILE=1 zsh -i -c exit
```

`oh-my-zsh.sh` is bypassed: antidote sources omz `lib/*.zsh` and the theme
directly, and zshrc runs `compinit -C`, rebuilding the dump when it is over a
day old or older than the plugin bundle or `env.zsh`.

## oh-my-pi

[oh-my-pi](https://omp.sh) (`omp`, a fork of pi) is installed from the
`can1357/tap` Homebrew formula, which ships arm64 and Intel builds and the zsh
completions. It runs DeepSeek V4.1 Flash (`deepseek/deepseek-flash`, in omp's
bundled catalog) for every role; for harder tasks, raise the thinking level
(`/model`, `--thinking`, or `:max` on a role) rather than change the model.
`ai/omp/models.yml` only supplies the key: omp reads it from 1Password
(`op read`, the `PI_CODING_AGENT` field of the "DeepSeek API Keys" note in
Private) the first time a request needs it and caches it for the process.
Rotate it in 1Password and restart omp. The 1Password app must be unlocked
with CLI integration on, and omp gives `op` 10 seconds, so approve the prompt
promptly. `--api-key` overrides it.

`ai/omp/` holds `config.yml` (settings), `models.yml`, `mcp.json`,
`APPEND_SYSTEM.md` and the `/commit`, `/pr` and `/explain` commands. Plan
mode, todos, handoff, `ask`, subagents (`task`), `web_search`, `/review` and
`/ci-green` are built in, as is the `dark-gruvbox` theme. `/settings` and
`/model` write `config.yml` through the symlink; review the result with
`git diff`. Logins, sessions and the key store (`agent.db`) stay in
`~/.omp`.

**Guardrails.** `config.yml` keeps the default `yolo` approval mode and adds
`bash.patterns`: commands touching secret paths (`~/.ssh`, `~/.gnupg`,
`~/.claude.json`, `ai/env.local.zsh`, `op read`, `gh auth token`, …) are
denied, and recursive `rm`, `sudo`, installs, `defaults write`, running a
`setup.sh`, force-push and history rewrites ask first. Those rules hold in
yolo mode, and subagents, which have no UI, are refused instead of asked.
`eval` (Python/JS) always asks, since the patterns don't see its shells. This
is a guardrail against model mistakes, not a sandbox: the rules match the
command text only (`$(…)`, variables and interpreter one-liners slip past),
and the `read`/`grep` tools are not restricted by path.

**MCP.** `ai/omp/mcp.json` defines GitHub, read-only and authenticated with
`gh auth token`, and Context7. `mcp.enableProjectConfig: false` ignores
project MCP files (`.mcp.json`, `.omp/mcp.json`, `.claude/`, …), whose
commands a cloned repo controls. omp does still read other project config,
such as `.omp/` settings, `AGENTS.md` and `.claude/commands`.

`ompc` continues the last session and `ompr` picks one to resume.

## Claude Code on other providers

Claude Code can talk to any Anthropic-compatible API. `ai/claude/providers.zsh`
(sourced by `ai/aliases.zsh`) sets that up per process, so the Pro login and
`~/.claude/settings.json` are never touched.

| Command | Runs |
| --- | --- |
| `cc` / `ccc` / `ccr` | Pro (new, `--continue`, `--resume`), with every provider variable cleared |
| `ccd` / `ccdc` / `ccdr` | DeepSeek V4.1 Flash, same three forms |
| `claude-deepseek` | Long form of `ccd` |
| `cc-providers` | List configured providers |

A provider is one `cc_provider` call at the bottom of the file:

```zsh
cc_provider deepseek \
  url=https://api.deepseek.com/anthropic \
  key=op://…/PI_CODING_AGENT \
  model=deepseek-flash label=DS short=ccd
```

`url`, `key` and `model` are required. `key` is an `op://` reference (read
when the command starts; 1Password must be unlocked) or `env:VAR`. `small`
sets the Sonnet, Haiku and subagent model (default `model`), `pro` enables
`--pro`, `label` is the status-line prefix (default: the name in capitals),
`short` adds the `X`/`Xc`/`Xr` commands, and `env.VAR=value` sets any extra
variable the provider needs. It always generates `claude-<name>`. Check a new
provider's endpoint and model ids in its own docs first.

Each launch clears every variable any provider sets before exporting its own,
and refuses to start with an empty key: otherwise Claude Code falls back to
the Pro login and the provider answers "Authentication Fails". The status
line prefixes the model with the label (`DS·deepseek-flash`). `--pro` is only
recognised as the first argument.

**Which to use.** Pro costs quota, DeepSeek costs money but Flash is cheap. If
tests, CI or a quick diff read will catch a wrong answer, use DeepSeek:
executing a written plan, boilerplate, tests, lint and CI fixes, exploration,
docs. If a mistake would ship silently or shape later work, use Pro:
planning, architecture, API and schema design, security, pre-merge
`/code-review`, and debugging after one failed DeepSeek attempt. Web
research goes to omp, since Claude Code's web search doesn't work on other
providers. A DeepSeek session sends the code it reads to DeepSeek, so deny
`.env` reads in private repos first.

**Switching mid-task.** Hand off through the plan file, not the transcript:
plan with `cc`, then `ccd "execute .omc/plans/<task>.md"`, then review with
`cc`. Resuming across providers works in both directions — a Pro session
continued under DeepSeek and the reverse each answered cleanly, with no
rejected thinking block — but `--continue` picks the directory's latest
session whichever provider ran it, so prefer `ccdr`/`ccr` and pick the session
you meant. Only single-turn sessions have been tested; a long tool-heavy
transcript is untried.

## herdr

herdr is the workspace manager the coding agents run in:
one workspace per repository, tabs for agents / dev server / tests, one pane per
agent, with a state sidebar showing which agent is working, blocked or done.
`prefix` is `ctrl+b` (tmux uses `C-a`, so the two don't collide). `prefix+q`
detaches and `herdr` reattaches — `herdr server stop` is different, it kills the
pane processes.

herdr owns agent work; tmux stays for plain shells and ssh. Never run two agents
in the same directory: herdr gives no file isolation, so use `git wta <branch>`
for parallel work and open the worktree as its own workspace.

`ai/herdr/config.toml` is the only versioned part. `~/.config/herdr/*.log`, the
socket, plugin binaries and plugin state are machine-local. `ai/setup.sh`
installs the `claude`, `omp` and `copilot` integrations, which report agent state
through hooks instead of screen-scraping and are what makes
`[session] resume_agents_on_restore` work. They write into
`ai/claude/settings.json` and `ai/copilot/settings.json`, which are symlinks into
this repo, so review `git diff` after running it.

Upgrade with `brew upgrade herdr`, never `herdr update` — Homebrew owns the
binary, and `[update] version_check = false` silences the nag. Re-run
`sh ai/setup.sh` afterwards so the integrations migrate.

**Plugins** are installed by `ai/setup.sh`, pinned to a release tag — the spec
list in its herdr block is the source of truth for the version. Once a plugin is
installed, the script links the versioned templates under
`ai/herdr/plugins/<plugin id>/` into its `herdr plugin config-dir`, and skips a
plugin that isn't installed. The pin is not decoration: `herdr plugin` has no
update command, and an unpinned install re-fetches the default branch, so
re-running the script would otherwise move a plugin to current HEAD.

First install still stops for the manifest preview — never `--yes` — because
plugins run unsandboxed as your user with your full environment; that is the
reason for the prompt, not for a manual install. To bump one, edit the tag in
`ai/setup.sh`, run `herdr plugin uninstall <id>`, then re-run the script. Pane
commands in those templates go through this repo's wrappers (`cc`, `ccd`, `omp`)
— not `claude --dangerously-skip-permissions` as herdr-plus's README shows,
which unsets the provider environment and silently falls back to the Pro login.

**Diff and review.** `git diff` pages through [delta](https://dandavison.github.io/delta/)
(side-by-side, `n`/`N` between files), and `git dft` runs a structural
[difftastic](https://difftastic.wilfred.me.uk) diff where a reindent or a moved
function reads as no change. delta is only used on a TTY, so a diff an agent
captures is still plain text. `prefix+alt+g` opens lazygit in a popup for staging
and committing; it ignores git's `core.pager`, so `git/lazygit.yml` configures
the same renderers again under `git.diffRenderers` and `|` cycles delta →
difftastic → `--color-words`. delta runs there with `--features=lazygit`, a
`[delta "lazygit"]` block in `git/gitconfig` that drops `navigate` and
side-by-side for the narrow panel and turns on clickable line numbers. Stage
lines under delta, not difftastic — an external diff produces no patch for
lazygit to apply. herdr-reviewr is the review surface: mark lines, comment,
`s` to send the comments into the agent's pane. The merge decision still goes
through `/code-review` and a signed PR — the AI review pass stays in its own
session, separate from the one that wrote the code.

**Agent teams.** `ai/herdr/team.sh` is the only thing that starts an agent for
a multi-pane run, because `herdr agent start` execs the binary directly and
drops what `ai/claude/providers.zsh` exports — Claude Code then falls back to
the Pro login silently. Every spawn goes through `zsh -ic <wrapper>` and the
provider is asserted afterwards.

```sh
ai/herdr/team.sh spawn exec-1 --branch feat/x   # worktree + workspace + agent
ai/herdr/team.sh status                         # roster and pending handoffs
ai/herdr/team.sh collect [<run-id>]             # outcomes from the handoffs
ai/herdr/team.sh settle <name> reuse|retain|release
ai/herdr/team.sh teardown <name> [--force]
```

`prefix+alt+t` opens `status` in a popup. One agent per worktree; agents report
outcomes by writing `.omc/handoffs/<task>-<dispatch>.md` in the **main**
checkout, never by leaving them in a transcript. The protocol the agents follow
lives in `ai/shared/skills/herdr-team/`, which is linked into `~/.claude/skills`
and `~/.omp/agent/skills` by `ai/setup.sh`.

## tmux

`tmux/tmux.conf` predates herdr and keeps the same shape — one pane per agent,
tiled and labelled, layouts that survive a reboot. herdr now runs the agents, so
tmux is for plain shells, ssh and anything herdr shouldn't own. Prefix is `C-a`,
and `[experimental] allow_nested` is off in herdr, so don't nest the two.

| Binding | Action |
| --- | --- |
| `prefix \|` / `prefix -` | split (keeps cwd) |
| `prefix Space` | tile all panes |
| `prefix A` | label the current pane (agent name, shown on its border) |
| `prefix S` | toggle `synchronize-panes` — type one prompt into every agent |
| `prefix b` | break a pane out to its own window |
| `prefix g` | scratch shell in a popup |
| `prefix s` | session switcher (one session per project) |

Plugins are managed by [tpm](https://github.com/tmux-plugins/tpm), which
bootstraps itself on first launch (sensible, vim-tmux-navigator, yank,
resurrect + continuum). `prefix I` installs/updates them.

## Runtimes

[mise](https://mise.jdx.dev) is the only version manager. It replaced pyenv,
rbenv, jenv, nvm and asdf, which together cost ~2.5 s of every shell start.

```sh
mise ls               # what's active
mise use -g node@22   # change a global pin
mise install          # install everything pinned in mise/global.toml
```

Global pins live in `mise/global.toml` (python, node, ruby, go, java, and the
Swift tooling). Per-project `.python-version`, `.ruby-version`, `.nvmrc`,
`.node-version` and `.java-version` files are honoured, as are `mise.toml` and
`.tool-versions`. mise exports `JAVA_HOME` on its own, so no JDK is installed
through Homebrew.

## Homebrew

`brew/Brewfile` is the single source of truth, grouped by formulae / casks /
fonts / mas.

```sh
sh brew/setup.sh              # install
sh brew/setup.sh --cleanup    # install, then uninstall anything not listed
sh brew/update.sh             # dump what's installed, for reconciliation
```

`--cleanup` is destructive and asks for confirmation. `brew/update.sh` writes
`Brewfile.generated` rather than overwriting the grouped `Brewfile`, so the
comment structure survives; fold in the diff by hand.

## Switching machines

Both architectures are supported: every path decision keys off
`$(uname -m) == arm64` → `/opt/homebrew`, otherwise `/usr/local`. Use
`brew_prefix` from `lib/common.sh` in new scripts rather than hardcoding
either.

On a new machine:

1. Install the Xcode command line tools: `xcode-select --install`.
2. `git clone https://github.com/khoi/dotfiles.git ~/.dotfiles && cd ~/.dotfiles`
3. `./setup.sh` — installs Homebrew, links dotfiles, runs the default modules.
4. `mise install` — reinstall the pinned runtimes (nothing is copied across).
5. Sign in to the App Store, then re-run `sh brew/setup.sh` so the `mas` entries
   install.
6. Import the GPG key and trust it — commits are signed
   (`commit.gpgSign = true`), so git will refuse to commit until this is done.
   `git/setup.sh` writes the correct `gpg.program` path for the architecture,
   asks for `user.name`/`user.email` if they are missing, and
   `gpg/setup.sh` installs `gpg.conf` / `gpg-agent.conf`.
7. `gh auth login`, then `sh ai/setup.sh` for the herdr integrations.
8. The herdr plugins are installed by `sh ai/setup.sh` (step 7), pinned to a
   release tag; approve the manifest preview it prints for each one. Plugins run
   unsandboxed, so that prompt stays manual.
9. `./setup.sh --all` if this machine needs VS Code or Xcode.

## Conventions

Each top-level directory is a self-contained module with a `setup.sh` that can
be run on its own. Scripts start with:

```sh
#!/usr/bin/env bash
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/.." && pwd)}"
. "${DOTFILES}/lib/common.sh"
require_macos
```

`lib/common.sh` provides `log`/`info`/`ok`/`warn`/`die`, `require_macos`,
`is_arm`, `brew_prefix`, `load_brew_shellenv`, `link` (idempotent symlink with
backup) and `module_dir`.

`.editorconfig` governs formatting: 2-space indent, LF, final newline, trimmed
trailing whitespace — except in `*.md` and `*.diff`. C-family and Python use 4
spaces; Makefiles use tabs. Markdown is linted per `.markdownlint-cli2.jsonc`.

There is no build or test suite; this repo is shell scripts and config files.
Verify changes with `bash -n` (or `shellcheck`) and `zsh -n`. CI runs on every
push to `main` and every pull request:

- `lint.yml` — `shellcheck -x`, `zsh -n`, markdownlint, editorconfig-checker,
  JSON and TOML validation, actionlint and zizmor.
- `secrets.yml` — a gitleaks scan of every pushed commit, with no path filter.
- `smoke.yml` — on macOS, when the shell config, `setup.sh`, `lib/` or a plist
  changed: lints the plists, then links the zsh config into a throwaway `HOME`
  and fails on any stderr output or a warm start over 1.5 s.
- `pr-title.yml` — Conventional Commits title; warns past 50 characters,
  fails past 72.

The path filters live in the reusable `_detect-changes.yml`; skipped jobs
report success, so they can be required checks.
