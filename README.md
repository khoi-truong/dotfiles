# dotfiles

[![Lint](https://github.com/khoi-truong/dotfiles/actions/workflows/lint.yml/badge.svg)](https://github.com/khoi-truong/dotfiles/actions/workflows/lint.yml)
[![Secrets](https://github.com/khoi-truong/dotfiles/actions/workflows/secrets.yml/badge.svg)](https://github.com/khoi-truong/dotfiles/actions/workflows/secrets.yml)

Personal macOS setup: zsh, git, Homebrew, mise, macOS defaults, and a
workspace for running coding agents (Claude Code, oh-my-pi, herdr).

- **macOS only**, Apple Silicon and Intel.
- **Idempotent** — every script is safe to re-run.
- **Modular** — each top-level directory is a module with its own `setup.sh`.

## Getting started

> [!IMPORTANT]
> Clone to `~/.dotfiles`. The path is hardcoded in `zsh/zshenv`; anywhere else
> will not work.

On a new machine:

1. Install the Xcode command line tools: `xcode-select --install`.
2. `git clone https://github.com/khoi-truong/dotfiles.git ~/.dotfiles && cd ~/.dotfiles`
3. `./setup.sh` — installs Homebrew, links dotfiles, runs the default modules
   (including `mise install` for the pinned runtimes). `macos/` asks for a
   computer name; leave it blank to keep the current one.
4. Sign in to the App Store, then re-run `sh brew/setup.sh` so the `mas`
   entries install.
5. Import the GPG key and trust it. Commits are signed (`commit.gpgSign =
   true`), so git refuses to commit until this is done. `git/setup.sh` has
   already written `gpg.program` and asked for `user.name`/`user.email`.
6. Unlock 1Password, `gh auth login`, then re-run `sh ai/setup.sh`. This writes
   `ai/env.local.zsh`, installs the herdr integrations, and installs each herdr
   plugin at its pinned tag — approve every manifest preview it prints.
7. Log in to Claude Code, omp and Copilot (their tokens are never versioned).
8. `./setup.sh --all` if this machine needs VS Code, Xcode or Terminal.app.

`setup.sh` installs Homebrew if missing, asks for `sudo` once, links the shell
dotfiles into `$HOME`, then runs each module's `setup.sh`:

```sh
./setup.sh              # default modules
./setup.sh --all        # default + opt-in modules
./setup.sh vscode git   # only the named modules, in the order given
./setup.sh --list       # show what's available
```

How files are linked, where secrets come from, and troubleshooting:
[Installation](docs/installation.md).

## What's inside

| Module | What it sets up | Default | Docs |
| --- | --- | :---: | --- |
| `zsh/` | Shell: antidote plugins, aliases, functions, cached inits | always | [Shell](docs/shell.md) |
| `git/` | gitconfig, gitleaks pre-commit hook, worktree helpers, delta, lazygit | ✓ | [Git](docs/git.md) |
| `gh/` | GitHub CLI settings and aliases | ✓ | [Git](docs/git.md#github-cli) |
| `brew/` | `Brewfile`: formulae, casks, fonts, App Store apps | ✓ | [Apps](docs/apps.md#homebrew) |
| `mise/` | Global runtime pins: python, node, ruby, go, java | ✓ | [Shell](docs/shell.md#runtimes-mise) |
| `macos/` | `defaults write` preferences | ✓ | [Apps](docs/apps.md#macos-preferences) |
| `gpg/` | `gpg.conf`, `gpg-agent.conf` (commit signing) | ✓ | [Git](docs/git.md#signing) |
| `iterm/` | iTerm2 preferences | ✓ | [Apps](docs/apps.md#iterm2) |
| `ai/` | Claude Code, oh-my-pi, Copilot CLI, herdr, shared skills | ✓ | [AI](docs/ai.md), [herdr](docs/herdr.md) |
| `misc/` | Small apps (Stats menu-bar monitor) | ✓ | [Apps](docs/apps.md#stats) |
| `vscode/` | Settings, keybindings, snippets, extensions | opt-in | [Apps](docs/apps.md#vs-code) |
| `xcode/` | Colour themes, file templates | opt-in | [Apps](docs/apps.md#xcode) |
| `terminal/` | Terminal.app theme | opt-in | [Apps](docs/apps.md#terminalapp) |
| `ssh/` `curl/` `tmux/` `vim/` | Single config files, linked by the root `setup.sh` | always | [Shell](docs/shell.md#tmux) |
| `lib/` `scripts/` | Shared shell helpers, CI scripts | — | [Contributing](docs/contributing.md) |

Opt-in modules need a GUI app that may not be installed, or only matter on some
machines.

## Everyday commands

| Command | Does |
| --- | --- |
| `update` | `brew upgrade` + `mise upgrade` (`--system` adds `softwareupdate`) |
| `reload` | Restart the login shell |
| `git wta <branch>` / `wt` | Add a worktree under `~/.worktrees` / jump to one with fzf |
| `git dft` | Structural diff with difftastic |
| `cc` / `ccd` | Claude Code on the Pro login / on DeepSeek |
| `omp` | oh-my-pi coding agent |
| `herdr` | Agent workspace manager (attach / reattach) |
| `ZSH_PROFILE=1 zsh -i -c exit` | Profile shell startup |

## Documentation

| Guide | Covers |
| --- | --- |
| [Installation](docs/installation.md) | Bootstrap internals, how files get linked, secrets, updating, troubleshooting |
| [Shell](docs/shell.md) | zsh load order, plugins, startup time, aliases, mise, tmux |
| [Git](docs/git.md) | Config, signing, hooks, worktrees, diff and review tools |
| [Apps](docs/apps.md) | Homebrew, macOS defaults, iTerm2, VS Code, Xcode, Stats |
| [AI tooling](docs/ai.md) | Claude Code providers, which model to use, quota routing, oh-my-pi, Copilot |
| [herdr](docs/herdr.md) | Agent workspace, keys, plugins, usage meters |
| [Agent teams](docs/agent-teams.md) | `team.sh`: agents in parallel worktrees, dispatch and collect |
| [Contributing](docs/contributing.md) | Workflow, script conventions, linting, CI |

## Principles

- **One version manager.** mise owns every language runtime.
- **Startup time is a feature.** The shell starts in about 350 ms; CI fails a
  warm start over 1.5 s.
- **Secrets never land in the repo.** Keys live in 1Password and are generated
  into gitignored files.
- **Dual-arch.** Paths key off `brew_prefix`, never a hardcoded Homebrew prefix.
