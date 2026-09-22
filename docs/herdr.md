# herdr

herdr is the workspace manager the coding agents run in: one workspace per
repository, one pane per agent, and a sidebar showing which agent is working,
blocked or done. herdr owns agent work; [tmux](shell.md#tmux) stays for plain
shells and ssh.

- [Keys](#keys)
- [Worktrees](#worktrees)
- [Install and upgrade](#install-and-upgrade)
- [Plugins](#plugins)
- [Usage meters](#usage-meters)

To run several agents in parallel worktrees, see [Agent teams](agent-teams.md).

> [!WARNING]
> Never run two agents in the same directory. herdr gives no file isolation:
> use `git wta <branch>` for parallel work and open the worktree as its own
> workspace.

## Keys

`prefix` is `ctrl+b` (tmux uses `C-a`, so they don't collide).

| Key | Action |
| --- | --- |
| `prefix+shift+1..9` | Switch to workspace (repo) N |
| `prefix+alt+1..9` | Focus agent row N |
| `prefix+shift+g` | New worktree |
| `prefix+shift+o` | Open worktree… (reuses an existing space) |
| `prefix+alt+g` | lazygit popup |
| `prefix+alt+t` | Agent team `status` popup |
| `ctrl+shift+u` | usagebar limits pane |
| `prefix+q` | Detach (`herdr` reattaches) |

`herdr server stop` is not a detach: it kills the pane processes.

Navigation is already two-dimensional (repo × agent row), so tabs go unused
and `hide_tab_bar_when_single_tab` hides the row. A second tab brings it back.

## Worktrees

A worktree *is* a workspace in herdr, so `New worktree` creates a checkout and
a space every time — a duplicate space when the branch already has one. Use
`Open worktree…` to reuse: it lists the repo's checkouts and focuses the space
an open one already has. herdr ships it unbound; `config.toml` binds it.

`[worktrees] directory` points at `~/.worktrees`, with the same
`<repo>/<branch with / as ->` layout as [`git wta`](git.md#worktrees), so both
routes to a branch land on one checkout.

## Install and upgrade

`ai/herdr/config.toml` is the only versioned part; logs, the socket, plugin
binaries and plugin state are machine-local.

`ai/setup.sh` installs the `claude`, `omp` and `copilot` integrations, which
report agent state through hooks instead of screen-scraping and make
`[session] resume_agents_on_restore` work. They write into
`ai/claude/settings.json` and `ai/copilot/settings.json` — symlinks into this
repo — so review `git diff` after running it.

Upgrade with `brew upgrade herdr`, never `herdr update`: Homebrew owns the
binary (`[update] version_check = false` silences the nag). Re-run
`sh ai/setup.sh` afterwards so the integrations migrate.

## Plugins

| Plugin | Does |
| --- | --- |
| herdr-plus | Worktree layouts, project picker |
| reviewr | Mark lines, comment, `s` sends the comments into the agent's pane |
| usagebar | Context, prompt-cache and provider-limit meters in the sidebar |

**Pinned list.** `ai/herdr/plugins.list` has one `<plugin id> <owner/repo>
<tag>` per line; `ai/setup.sh` installs each at its tag. Both id and repo are
needed: `config-dir` wants the id, `install` wants the repo, and they are
unrelated (`persiyanov/herdr-reviewr` is `persiyanov.reviewr`). The pin
matters: `herdr plugin` has no update command, and an unpinned install
re-fetches the default branch on every run.

**Config templates** under `ai/herdr/plugins/<plugin id>/` are linked into the
plugin's `herdr plugin config-dir` once it is installed.

**Bump a plugin:** edit its tag in `plugins.list`,
`herdr plugin uninstall <id>`, then re-run `sh ai/setup.sh`.

> [!IMPORTANT]
> First install stops for the manifest preview — never pass `--yes`. Plugins
> run unsandboxed as your user with your full environment.

Pane commands in the templates go through this repo's wrappers (`cc`, `ccd`,
`omp`), not `claude --dangerously-skip-permissions` as herdr-plus's README
shows — that unsets the provider environment and silently falls back to the
Pro login.

## Usage meters

usagebar's sidebar rows and keybindings live in `ai/herdr/config.toml`, not
the plugin's own config. Each agent row shows, top to bottom:

| Row | Shows |
| --- | --- |
| `workspace` | The agent (`team.sh` names the workspace after it) |
| `tab` | Its branch — on its own line, because herdr truncates the tail of a joined row, which is the part that tells branches apart |
| `terminal_title_stripped` | Claude Code's live summary of what it's doing — the only thing that tells two panes in one tab apart |
| `$provider · $limit` | Billing identity: `claude · 5h 60%` on a `cc` pane, `deepseek · Σ 425k $0.04` on a `ccd` pane |
| `$cache_*` | Prompt-cache hit rate, coloured by band: gruvbox yellow below 80%, red below 50% |

Claude's rate-limit windows and cache expiry reach usagebar through the
[status line](ai.md#status-line-and-quota-routing). That runs wherever Claude
runs, but the meters are sidebar rows: a session outside herdr only keeps the
cache warm for the next herdr pane.

The plugin path in `ai/claude/statusline.sh` is hardcoded but stable: herdr
installs to `<plugin id>-<first 12 hex of sha256(plugin id)>`, which survives
reinstalls and tag bumps. Confirm with
`herdr plugin list --plugin usagebar --json`.
