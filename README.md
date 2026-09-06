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
| **default** | `git` `brew` `mise` `macos` `gpg` `iterm` `alfred` `ai` `misc` |
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
| `ssh/config`                                            | `~/.ssh/config`                         |
| `curl/curlrc`, `tmux/tmux.conf`, `vim/vimrc`            | `~/.curlrc`, `~/.tmux.conf`, `~/.vimrc` |
| `mise/global.toml`                                      | `~/.config/mise/config.toml`            |
| `ai/claude/*`                                           | `~/.claude/`                            |
| `ai/copilot/*`                                          | `~/.copilot/`                           |
| `vscode/{settings,keybindings}.json`, `vscode/snippets` | VS Code user dir                        |

**Preference redirection** — for apps with no dotfile.

- `macos/setup.sh` is a large `defaults write` script (mathiasbynens lineage;
  timezone `Asia/Ho_Chi_Minh`, forced Dark mode). Needs sudo, and restarts
  Finder/Dock at the end.
- iTerm2 is pointed at `iterm/` via its "load preferences from a custom folder"
  setting. iTerm writes the plist back there on quit, so commit from the repo.
- Alfred's `syncfolder` is set to `alfred/`.
- Terminal.app imports its theme through `osascript`.
- `gpg/setup.sh` copies `gpg.conf` and a rendered `gpg-agent.conf` (arch-correct
  `pinentry-mac` path) into `~/.gnupg`. Copied, not symlinked — gpg insists on a
  real `700` directory. Keys and `trustdb` are never versioned.
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
   `ai/aliases.zsh` — after plugins, so these win.
6. mise, fzf, zoxide.
7. `zsh/local/extra.zsh` — machine-local, gitignored.

**Plugins.** Managed by [antidote](https://getantidote.github.io/).
`zsh/zsh.plugins` is the list; `zsh/local/plugins.zsh` is the generated static
bundle, rebuilt automatically whenever the list is newer. To force a rebuild:

```sh
touch zsh/zsh.plugins && exec zsh
```

**Machine-local state.** `zsh/local/` is gitignored and holds history, the
zcompdump, the generated bundle, and `extra.zsh`. Anything an installer wants
to append to `~/.zshrc` belongs in `zsh/local/extra.zsh` instead.

**Startup time.** Roughly 350 ms. Profile it with:

```sh
ZSH_PROFILE=1 zsh -i -c exit
```

The two largest `zprof` entries — mise's hook and oh-my-zsh's library
sourcing — are inherent to those tools.

## tmux

`tmux/tmux.conf` is set up for running several Claude Code agents at once —
one agent per pane, tiled and labelled, with layouts that survive a reboot.
Prefix is `C-a`.

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
   `git/setup.sh` writes the correct `gpg.program` path for the architecture and
   `gpg/setup.sh` installs `gpg.conf` / `gpg-agent.conf`.
7. `gh auth login`, then `sh ai/setup.sh` for the Copilot CLI extension.
8. `./setup.sh --all` if this machine needs VS Code or Xcode.

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
Verify changes with `bash -n` (or `shellcheck`) and `zsh -n`.
