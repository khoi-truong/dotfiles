# Shell

- [Load order](#load-order)
- [Plugins](#plugins)
- [Startup time](#startup-time)
- [Machine-local state](#machine-local-state)
- [Aliases and functions](#aliases-and-functions)
- [Runtimes (mise)](#runtimes-mise)
- [tmux](#tmux)

## Load order

`~/.zshenv` → `~/.zshrc`, both symlinks into `zsh/`. `zshrc` sources, in order:

| # | File | Why here |
| --- | --- | --- |
| 1 | `zsh/env.zsh` | `$PATH` and toolchain env, built once, deduplicated with `typeset -U path` |
| 2 | `zsh/config.zsh` | Options, history, editor |
| 3 | `zsh/omz.zsh` | oh-my-zsh settings; must precede the plugin bundle |
| 4 | `zsh/local/plugins.zsh` | The generated antidote bundle |
| 5 | `zsh/aliases.zsh`, `zsh/aliases.macos.zsh`, `zsh/functions.zsh` | After plugins, so these win |
| 6 | mise, fzf, zoxide | Cached inits — see [Startup time](#startup-time) |
| 7 | `ai/aliases.zsh` → `ai/claude/providers.zsh` | After mise, whose `python3` regenerates the provider launcher cache |
| 8 | `zsh/local/extra.zsh` | Machine-local, gitignored |

Anything an installer wants to append to `~/.zshrc` belongs in
`zsh/local/extra.zsh` instead.

## Plugins

Managed by [antidote](https://getantidote.github.io/). `zsh/zsh.plugins` is the
list; `zsh/local/plugins.zsh` is the generated static bundle, rebuilt
automatically whenever the list is newer. The bundle and every plugin file it
sources are zcompiled once after each regeneration.

`oh-my-zsh.sh` itself is bypassed: antidote sources omz `lib/*.zsh` and the
theme directly.

After `antidote update`, a zsh upgrade, or to force a rebuild:

```sh
touch zsh/zsh.plugins && exec zsh
```

## Startup time

Roughly 350 ms. Profile it with:

```sh
ZSH_PROFILE=1 zsh -i -c exit
```

What keeps it there:

- **Cached inits.** mise, fzf and zoxide init scripts are cached in
  `zsh/local/init-*.zsh`, keyed by binary path and rebuilt when the binary or
  `zshrc` changes. The mise cache is also keyed on `$PATH`, the `MISE_*`
  variables and every mise config (and trust state) that applies to the
  current directory. A miserc bypasses it, and a nested shell inside a project
  usually misses and runs `mise activate` live. Delete the files to force a
  rebuild.
- **`compinit -C`**, rebuilding the dump only when it is over a day old or
  older than the plugin bundle or `env.zsh`.
- **One version manager.** mise replaced pyenv, rbenv, jenv, nvm and asdf,
  which together cost ~2.5 s of every start.

CI fails any change that pushes a warm start over 1.5 s.

## Machine-local state

`zsh/local/` is gitignored and holds the zsh, Python and Node REPL histories,
`lesshst`, the zcompdump, the generated bundle, the cached inits, and
`extra.zsh`.

## Aliases and functions

A selection; see `zsh/aliases*.zsh` and `zsh/functions.zsh` for the rest.

| Command | Does |
| --- | --- |
| `..`, `...`, `-` | Up one / two directories, back to the previous one |
| `dot`, `dl`, `dt` | `cd` to the dotfiles, Downloads, Desktop |
| `g` | `git` |
| `vim` | `nvim` |
| `reload` | `exec $SHELL -l` |
| `path` | Print `$PATH`, one entry per line |
| `ip`, `localip`, `ips` | Public IP, LAN IP, all addresses |
| `flush` | Flush the DNS cache |
| `c` | Copy stdin to the clipboard, without the trailing newline |
| `cleanup` | Delete `.DS_Store` files under the current directory |
| `update [--system]` | Upgrade Homebrew and mise; `--system` also runs `softwareupdate` |
| `mkd <dir>` | `mkdir -p` and `cd` into it |
| `urlencode`, `urldecode` | Percent-encode / decode a string |
| `wt [query]` | `cd` into one of the repo's worktrees, picked with fzf |
| `mitm`, `mitm-trust`, `curlm` | mitmproxy web UI, trust its CA, curl through it |

AI launchers (`cc`, `ccd`, `ompc`, …) are in [AI tooling](ai.md).

## Runtimes (mise)

[mise](https://mise.jdx.dev) is the only version manager. Never add a
`pyenv`/`rbenv`/`jenv`/`nvm`/`asdf` init hook back into the shell.

```sh
mise ls               # what's active
mise use -g node@22   # change a global pin
mise install          # install everything pinned in mise/global.toml
```

Global pins live in `mise/global.toml` (python, node, ruby, go, java, and the
Swift tooling), linked to `~/.config/mise/config.toml`. Per-project
`.python-version`, `.ruby-version`, `.nvmrc`, `.node-version`,
`.java-version`, `mise.toml` and `.tool-versions` files are honoured. mise
exports `JAVA_HOME` itself, so no JDK comes from Homebrew.

## tmux

`tmux/tmux.conf` predates [herdr](herdr.md), which now runs the agents. tmux is
for plain shells, ssh and anything herdr shouldn't own. Prefix is `C-a` (herdr
uses `ctrl+b`), and herdr's `allow_nested` is off, so don't nest the two.

| Binding | Action |
| --- | --- |
| `prefix \|` / `prefix -` | Split (keeps cwd) |
| `prefix Space` | Tile all panes |
| `prefix A` | Label the current pane (shown on its border) |
| `prefix S` | Toggle `synchronize-panes` — type into every pane at once |
| `prefix b` | Break a pane out to its own window |
| `prefix g` | Scratch shell in a popup |
| `prefix s` | Session switcher (one session per project) |

Plugins are managed by [tpm](https://github.com/tmux-plugins/tpm), which
bootstraps itself on first launch (sensible, vim-tmux-navigator, yank,
resurrect + continuum). `prefix I` installs or updates them.
