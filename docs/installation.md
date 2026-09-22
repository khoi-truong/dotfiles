# Installation

The details behind the [getting-started steps in the README](../README.md#getting-started).

- [Bootstrap](#bootstrap)
- [How files get installed](#how-files-get-installed)
- [Secrets](#secrets)
- [Keeping up to date](#keeping-up-to-date)
- [Troubleshooting](#troubleshooting)

## Bootstrap

```sh
./setup.sh              # default modules
./setup.sh --all        # default + opt-in modules
./setup.sh vscode git   # only the named modules, in the order given
./setup.sh --list       # show what's available
```

`setup.sh`, in order:

1. Installs Homebrew if it is missing.
2. Asks for `sudo` once and keeps it alive, so `macos/` doesn't prompt mid-run.
3. Links `zsh/zshenv`, `zsh/zshrc`, `ssh/config`, `curl/curlrc`,
   `tmux/tmux.conf` and `vim/vimrc` into `$HOME`, and removes the redundant
   `~/.zsh_history`, `~/.zcompdump*` and `~/.zsh_sessions`.
4. Runs `<module>/setup.sh` for each module.

|             | Modules                                                  |
| ----------- | -------------------------------------------------------- |
| **default** | `git` `gh` `brew` `mise` `macos` `gpg` `iterm` `ai` `misc` |
| **opt-in**  | `vscode` `xcode` `terminal`                              |

Every module script also runs on its own, e.g. `bash git/setup.sh`.

## How files get installed

Two mechanisms, depending on whether the app reads a config file.

### Symlinks

The repo file is linked into place, so edits in the repo are live immediately.
`link` (in `lib/common.sh`) backs up any real file it would replace as
`<file>.dotfiles-backup`.

| Repo                                                    | Linked to                               |
| ------------------------------------------------------- | --------------------------------------- |
| `zsh/zshenv`, `zsh/zshrc`                               | `~/.zshenv`, `~/.zshrc`                 |
| `git/gitconfig`                                         | `~/.gitconfig`                          |
| `git/ignore`                                            | `~/.config/git/ignore`                  |
| `git/template/`                                         | `~/.config/git/template`                |
| `git/lazygit.yml`                                       | lazygit's Application Support dir       |
| `gh/config.yml`                                         | `~/.config/gh/config.yml`               |
| `ssh/config`                                            | `~/.ssh/config`                         |
| `curl/curlrc`, `tmux/tmux.conf`, `vim/vimrc`            | `~/.curlrc`, `~/.tmux.conf`, `~/.vimrc` |
| `mise/global.toml`                                      | `~/.config/mise/config.toml`            |
| `ai/claude/{settings.json,CLAUDE.md}`                   | `~/.claude/`                            |
| `ai/shared/skills/*`                                    | `~/.claude/skills/` (one link per skill) |
| `ai/omp/*`, `ai/shared/skills`                          | `~/.omp/agent/`                         |
| `ai/shared/rules/common.md`                             | `~/.omp/agent/AGENTS.md`                |
| `ai/copilot/*`                                          | `~/.copilot/`                           |
| `ai/herdr/config.toml`                                  | `~/.config/herdr/config.toml`           |
| `vscode/{settings,keybindings}.json`, `vscode/snippets` | VS Code user dir                        |
| `xcode/FontAndColorThemes/*`                            | `~/Library/Developer/Xcode/UserData/FontAndColorThemes/` |

### Preference redirection and copies

For apps with no dotfile, or ones that refuse a symlink:

| Module | Mechanism |
| --- | --- |
| `macos/` | A large `defaults write` script — see [Apps](apps.md#macos-preferences) |
| `iterm/` | iTerm2 loads preferences from this folder |
| `terminal/` | Theme imported through `osascript` |
| `gpg/` | Copied, not linked: gpg insists on a real `700` directory |
| `misc/stats/` | Plist imported with `defaults import` |

### Machine-local files

Never versioned; each is created by the module that needs it.

| File | Holds | Created by |
| --- | --- | --- |
| `zsh/local/` | Histories, zcompdump, plugin bundle, cached inits, `extra.zsh` | the shell |
| `~/.config/git/gitconfig.local` | `user.name`, `user.email`, arch-correct `gpg.program` | `git/setup.sh` |
| `ai/env.local.zsh` | API keys | `ai/setup.sh`, from 1Password |
| `ai/**/*.local*`, `ai/claude/settings.local.json` | Machine overrides | you |
| `~/.claude.json`, `~/.claude/.credentials.json`, `~/.config/github-copilot/apps.json`, `~/.omp/agent/agent.db` | Logins and OAuth tokens | logging in |

## Secrets

API keys live in one 1Password item. `ai/setup.sh` exports its concealed
fields into `ai/env.local.zsh` (gitignored, mode `600`), which
`ai/aliases.zsh` sources in every shell.

- **Add or rotate a key:** edit the 1Password item, re-run `sh ai/setup.sh`,
  and restart the tools that read it. The field label becomes the variable name
  verbatim.
- **Don't hand-edit `env.local.zsh`.** It is rewritten on every run.
- **Why not `op read` at launch?** It raises a biometric prompt, which an
  unattended agent pane cannot answer — it reads as a hung spawn.

1Password must be unlocked with CLI integration on, and `op` and `jq` must be
installed; otherwise the step is skipped with a warning and the old file kept.

## Keeping up to date

| Task | Command |
| --- | --- |
| Upgrade Homebrew and mise tools | `update` (`update --system` adds `softwareupdate`) |
| Record newly installed brew packages | `sh brew/update.sh`, then fold `Brewfile.generated` into `Brewfile` by hand |
| Record VS Code extensions | `bash vscode/update.sh` |
| Record Stats preferences | `bash misc/stats/update.sh` |
| Upgrade herdr | `brew upgrade herdr`, then `sh ai/setup.sh` — never `herdr update` |
| Rebuild zsh plugins | `touch zsh/zsh.plugins && exec zsh` |

## Troubleshooting

**A tool replaced my symlink with a real file.** Claude Code, iTerm's
cc-status installer and others rewrite `settings.json` in place. Re-running the
module backs the file up as `*.dotfiles-backup` and relinks; fold anything new
from the backup into the repo copy first.

**`ai/setup.sh` warns about a dangling symlink.** A file moved in the repo and
left a stale link in `~/.claude`, `~/.omp/agent`, `~/.copilot` or
`~/.config/herdr`. Delete it if you no longer need it.

**The shell is slow or prints errors.** Profile with
`ZSH_PROFILE=1 zsh -i -c exit`. Delete `zsh/local/init-*.zsh` to force the
cached inits to rebuild. See [Shell](shell.md).

**`git commit` fails with a gpg error.** The key isn't imported or trusted, or
`gpg.program` points at the other architecture's prefix — re-run
`bash git/setup.sh`.

**`ccd` exits with "empty API key".** `ai/env.local.zsh` is missing the key:
unlock 1Password and re-run `sh ai/setup.sh`.
