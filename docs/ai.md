# AI tooling

- [Layout](#layout)
- [Claude Code](#claude-code)
  - [Providers](#providers)
  - [Which to use](#which-to-use)
  - [Switching mid-task](#switching-mid-task)
  - [Deny guards](#deny-guards)
  - [Status line and quota routing](#status-line-and-quota-routing)
- [oh-my-pi](#oh-my-pi)
- [GitHub Copilot CLI](#github-copilot-cli)

The agents run inside [herdr](herdr.md); parallel agents in their own worktrees
are [agent teams](agent-teams.md).

## Layout

`ai/` is split by harness, with what they share in `ai/shared/`. Each harness
keeps its own model, provider and MCP config, since the formats differ.

| Path | Holds | Linked to |
| --- | --- | --- |
| `ai/shared/rules/common.md` | Global instructions every harness loads | imported by `ai/claude/CLAUDE.md`; `~/.omp/agent/AGENTS.md` |
| `ai/shared/skills/` | Agent Skills read by Claude Code and omp (`herdr-team`, `dispatchable-plan`, `github-actions`) | `~/.claude/skills/<name>`, `~/.omp/agent/skills` |
| `ai/claude/` | Claude Code settings, `CLAUDE.md`, launchers, status line, hooks | `~/.claude/` |
| `ai/omp/` | oh-my-pi config, models, MCP, commands | `~/.omp/agent/` |
| `ai/copilot/` | Copilot CLI settings and instructions | `~/.copilot/` |
| `ai/herdr/` | herdr config, plugins, `team.sh` | `~/.config/herdr/` |
| `ai/providers.toml` | Every credential and endpoint, one entry each | — |
| `ai/aliases.zsh` | Launchers and aliases, sourced by `zshrc` | — |
| `ai/env.local.zsh` | API keys, generated from 1Password (gitignored) | — |
| `ai/op.local.env` | `OP_ACCOUNT`, `OP_VAULT`, `OP_ITEM` for that item (gitignored) | — |

Skills are linked one directory at a time into `~/.claude/skills`, so skills
installed by plugins stay untouched. Keys are covered in
[Installation → Secrets](installation.md#secrets).

## Claude Code

### Providers

Claude Code can talk to any Anthropic-compatible API. `ai/claude/providers.zsh`
sets that up per process, so the Pro login and `~/.claude/settings.json` are
never touched.

| Command | Runs |
| --- | --- |
| `cc` / `ccc` / `ccr` | Pro (new, `--continue`, `--resume`), with every provider variable cleared |
| `ccd` / `ccdc` / `ccdr` | DeepSeek V4.1 Flash, same three forms |
| `claude-<name>` | Long form, generated for every enabled provider (`claude-deepseek`) |
| `cc-providers` | List configured providers |

**Adding a provider** is a `[provider.<name>]` entry in `ai/providers.toml` —
the one definition shared with [agent teams](agent-teams.md):

```toml
[provider.deepseek]
protocol = "anthropic"
url = "https://api.deepseek.com/anthropic"
key = "env:CLAUDE_CODE_DEEPSEEK_API_KEY"
models = { default = "deepseek-flash" }
ceiling = 4
launcher = { short = "ccd", label = "DS" }
```

- `key` is `env:VAR`, resolved from `ai/env.local.zsh`. Add the key to the
  1Password item and re-run `sh ai/setup.sh`. The script reads the item named
  by `OP_ACCOUNT`, `OP_VAULT` and `OP_ITEM` in `ai/op.local.env`; without
  that file it warns and skips.
- `launcher.short` adds the `X`/`Xc`/`Xr` commands; `label` is the status-line
  prefix.
- `ceiling` caps how many panes may spend the key at once.
- `enabled = false` keeps an entry (still linted) without generating
  commands. Kimi and OpenRouter are there, disabled.

The launcher commands are generated from the TOML into a cache
(`~/.cache/dotfiles/providers.zsh`), rebuilt when the file changes. A file that
doesn't parse keeps the last good cache and warns once. Check a new provider's
endpoint and model ids in its own docs first.

Each launch clears every variable any provider sets before exporting its own,
and refuses to start with an empty key — otherwise Claude Code silently falls
back to the Pro login. The status line prefixes the model with the label
(`DS·deepseek-flash`).

### Which to use

Pro costs quota; DeepSeek costs money, but Flash is cheap.

| Use DeepSeek (`ccd`) when a check catches mistakes | Use Pro (`cc`) when mistakes ship silently |
| --- | --- |
| Executing a written plan | Planning, architecture |
| Boilerplate, tests | API and schema design |
| Lint and CI fixes | Security |
| Exploration, docs | Pre-merge `/code-review` |
| | Debugging after one failed DeepSeek attempt |

- **Web research goes to omp**: Claude Code's web search doesn't work on other
  providers.
- **Privacy**: a DeepSeek session sends the code it reads to DeepSeek. Deny
  `.env` reads in private repos first.
- **Small tasks stay inline**: below the break-even, doing it on Pro costs less
  than the handover.

### Switching mid-task

Hand off through the plan file, not the transcript:

```sh
cc                                         # plan
ccd "execute .omc/plans/<task>.md"         # implement
cc                                         # review
```

Resuming across providers works in both directions, but `--continue` picks the
directory's latest session whichever provider ran it. Prefer `ccr`/`ccdr` and
pick the session you meant. Only single-turn sessions have been tested; a long
tool-heavy transcript is untried.

### Permissions

`ai/claude/settings.json` denies `sudo` (bare and with arguments), force-pushes
(`--force`/`-f` in any position, and `+refspec`), and Claude's file-tool and
common shell-reader access to of key files, `.env` files and the
credential files `~/.claude.json`, `~/.claude/.credentials.json`,
`~/.config/gh/hosts.yml` and `~/.config/github-copilot/apps.json`. Deny rules
don't reach a script that opens a file itself. Hook commands use `$HOME`, which
the shell expands at run time; `ai/setup.sh` drops the absolute-path duplicate
`herdr integration install` appends.

Tools that edit `settings.json` (Claude Code, iTerm's cc-status installer)
can replace the symlink with a real file. Re-running `ai/setup.sh` backs that
file up and relinks, and `link` warns with the target and the backup directory
(never the content). Diff the backup against `ai/claude/settings.json` and
fold in anything wanted; `scripts/restore.sh` undoes the run.

### Deny guards

The deny list is generated. `ai/profiles/policy.toml` is the source; edit it,
run `python3 scripts/gen-policy.py`, and commit both. The generator rewrites
only `.permissions.deny` in `ai/claude/settings.json` (JSON has no comments, so
this is the only mark that the list is generated) and
`ai/copilot/deny-tools.zsh`. `python3 scripts/gen-policy.py --check` writes
nothing and exits 1 on drift; CI (`lint.yml`) and `scripts/ci/lint-local.sh`
run it. It needs Python 3.11 for `tomllib`.
Add denies in `ai/profiles/policy.toml`, never in `settings.json`: the
generator drops hand-added and `/permissions`-added denies, and `--check` flags
them. Module discovery reads the working tree, so an untracked `foo/setup.sh`
makes a local `--check` stricter than CI.

| Policy entry | Renders |
| --- | --- |
| `[[command]]` `run`, no `flags` | `Bash(run)` and `Bash(run *)` |
| with `flags` | per flag, `Bash(run f*)` and `Bash(run * f*)` (flag in any position) |
| with `flags` and `targets` | per flag and target, the four spellings with and without `*` around the flag |
| `[[secret]]` | `Read(path)` plus a `Bash(reader *name*)` for every entry in `readers` |
| `[[read]]` | `Read(glob)` |
| `[[raw]]` | the rule verbatim, for what fits no shape |

Every `[[command]]` needs a one-line `why`; an optional `copilot` is a Copilot
`--deny-tool` spec. Runs of `*` collapse to one inside `Bash(...)` only, and
duplicates keep their first position. Setup scripts are discovered: every
top-level `*/setup.sh` gets a rule, so a new module is denied once the
generator is re-run (`--check` fails until then).

The Copilot wrapper, `ai/copilot/deny-tools.zsh`, is sourced from
`ai/aliases.zsh` and passes the `copilot` specs as `--deny-tool` flags. It
exists only in an interactive zsh: a `copilot` started by herdr or any other
process that does not source the shell config bypasses it.

`ai/claude/settings.json` also denies the commands AGENTS.md forbids without
being asked. Run them yourself with `!`:

- every form of a module's `setup.sh`: `./setup.sh`, `./*/setup.sh`,
  `<module>/setup.sh`, and `bash`, `sh`, `zsh`, `/bin/bash` or `/bin/sh`
  running one;
- `brew bundle*`, which includes `check`, `list` and `dump`;
- `mise install`/`i`, `mise use -g`/`--global` (flag in any position),
  `mise upgrade`/`up`, and the `u -g`/`u --global` shorthands;
- `defaults write` (also with a domain flag before it) and `defaults import`;
- force-pushes, including a bare `git push -f` (a trailing space-star pattern also
  matches the bare command).

`bash -n` or `sh -n` on a module's `setup.sh` is denied too, so syntax-check
those with `shellcheck`, which is not denied.

### Status line and quota routing

`ai/claude/statusline.sh` (the `statusLine` command) renders
[claude-hud](https://github.com/jarrodwatts/claude-hud), and feeds the payload
to two side branches. The status line is byte-identical with
or without them.

1. **usagebar** — Claude's 5h/7d rate-limit windows and prompt-cache expiry are
   reported nowhere else, so the payload goes to `usagebar statusline` for the
   [herdr sidebar meters](herdr.md#usage-meters). Skipped when the plugin
   binary is missing.
2. **`~/.claude/cache/pro-quota.json`** — the two windows, cached so the
   model can see them. `ai/claude/quota-advice.sh`, a `UserPromptSubmit` hook,
   reads the cache and injects a routing advisory:

   | Pro usage | Advice |
   | --- | --- |
   | 5h < 50% | Silent |
   | 5h ≥ 50% | Prefer `ccd` for mechanically checkable work |
   | 5h ≥ 75% | Reserve Pro for planning and review |
   | 7d ≥ 80% | Pro for decisions only; everything executable to `ccd`, research to `omp` |

   It only speaks inside a herdr pane (`HERDR_ENV=1`), where there are `ccd`
   and `omp` panes to route to. A `ccd` pane never writes the cache
   (`CC_PROVIDER` gates it), and a window past its `resets_at` counts as
   unknown, not as headroom.

**claude-hud** is a plugin; `settings.json` registers its marketplace and
enables `claude-hud@claude-hud`. Install it with
`claude plugin marketplace add jarrodwatts/claude-hud` and
`claude plugin install claude-hud@claude-hud` (or let the settings pull it in).
The wrapper runs the newest `dist/index.js` under
`~/.claude/plugins/cache/*/claude-hud/<version>/`, so an update needs no setup
step. Don't run `/hud install`: it rewrites the symlinked `settings.json`. It
needs Node 22.18 or newer (mise's global node). Without node or the plugin, or
if the HUD crashes or prints nothing, the wrapper prints `<model> <directory>`
instead (the provider label stands in for the model).

The layout is `ai/claude/claude-hud.json`, copied by `ai/setup.sh` to
`~/.claude/plugins/claude-hud/config.json`. It is a copy because claude-hud
opens that file with `O_NOFOLLOW` and reports a symlink as "can't be read".
`/hud` edits the copy, so fold changes you want back into the repo file; the
next `ai/setup.sh` backs the edited copy up and replaces it. It shows the model with its effort,
the project and git branch, the session name, a context bar, the
prompt-cache time, session duration, output speed, tools, compactions, the
skills and MCP servers used, agents and todos. Usage and weekly limits are
hidden. Context, cache and tools share one row, and the wrapper then tidies the HUD's rows:

```text
before  [Opus ◔ medium] │ proj git:(main) │ ⏱️  1h 23m │ out: 88.3 tok/s
        Context ▓▓▓░░ 36% │ Cache ⏱ until 03:00 PM │ ◐ Bash: ls | ✓ Read ×3
        Compactions: 2
after   [Opus ◔ medium] │ proj git:(main)
        Context ▓▓▓░░ 36% │ Cache until 03:00 PM │ ⏱️ 1h23m │ Compactions: 2 │ ⚡ 88.3 tok/s │ ◐ Bash │ 🔧 3
```

Duration, compactions and speed move onto the context row ahead of the tools,
tools collapse to the running names plus one total of finished calls, and
rows the HUD wrapped (a lone usage, cache or tools row) rejoin the context row.
Agent rows are left alone. The wrapper matches the HUD's v0.15.0 wording, so an
upgrade that rewords it only loses the tidying, never the line.

`ai/claude/hud-ctx-fix.mjs` sits in front of the HUD: it measures context use
against the 200k auto-compact window rather than the advertised 1M, and adds
the provider label to the model name.

The `claude` shell function (in `zsh/functions.zsh`) turns terminal echo off
during launch, so the terminal's replies to Claude's startup probes don't show
up as garbage around the logo.

## oh-my-pi

[oh-my-pi](https://omp.sh) (`omp`, a fork of pi) comes from the `can1357/tap`
Homebrew formula. It runs DeepSeek V4.1 Flash (`deepseek/deepseek-flash`) for
every role; for harder tasks raise the thinking level (`/model`,
`--thinking`, or `:max` on a role) rather than change the model.

| Command | Does |
| --- | --- |
| `omp` | New session |
| `ompc` | Continue the last session |
| `ompr` | Pick a session to resume |

**Config.** `ai/omp/` holds `config.yml` (settings), `models.yml`, `mcp.json`,
`APPEND_SYSTEM.md` and the `/commit`, `/pr` and `/explain` commands. Plan
mode, todos, handoff, `ask`, subagents (`task`), `web_search`, `/review`,
`/ci-green` and the `dark-gruvbox` theme are built in. `/settings` and
`/model` write `config.yml` through the symlink; review with `git diff`.
Logins, sessions and the key store (`agent.db`) stay in `~/.omp`.

**Key.** `models.yml` reads `$PI_CODING_AGENT_DEEPSEEK_API_KEY` from
`ai/env.local.zsh` — a separate key from Claude Code's, so either can be
rotated alone. To rotate: update 1Password, re-run `sh ai/setup.sh`, restart
omp. `--api-key` overrides it.

**Guardrails.** `config.yml` keeps the `yolo` approval mode and adds
`bash.patterns`:

- **Denied**: commands touching secret paths (`~/.ssh`, `~/.gnupg`,
  `~/.claude.json`, `ai/env.local.zsh`, `op read`, `gh auth token`, …).
- **Ask first**: recursive `rm`, `sudo`, installs, `defaults write`, running a
  `setup.sh`, force-push, history rewrites. Subagents have no UI, so they are
  refused instead.
- **`eval`** (Python/JS) always asks, since the patterns can't see its shells.
  Panes spawned by `team.sh` layer `ai/omp/executor.yml` on top, which allows
  it — an unattended executor can't answer a prompt.

> [!WARNING]
> This guards against model mistakes; it is not a sandbox. The rules match
> command text only (`$(…)`, variables and interpreter one-liners slip past),
> and the `read`/`grep` tools aren't restricted by path.

**MCP.** `ai/omp/mcp.json` defines GitHub (read-only, authenticated with
`gh auth token`) and Context7. `mcp.enableProjectConfig: false` ignores project
MCP files (`.mcp.json`, `.omp/mcp.json`, `.claude/`, …), whose commands a
cloned repo controls. omp still reads other project config, such as `.omp/`
settings, `AGENTS.md` and `.claude/commands`.

## GitHub Copilot CLI

The standalone `copilot` CLI, configured in `~/.copilot` from
`ai/copilot/settings.json` and `ai/copilot/copilot-instructions.md`. It isn't
in the Brewfile. Its OAuth token (`~/.config/github-copilot/apps.json`) is
never versioned.
