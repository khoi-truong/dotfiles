# CLAUDE.md

`README.md` is canonical for layout and installation. Read it first, and keep
it updated when the structure changes.

@README.md

## Rules

- **Never run system-mutating commands without being asked.** That means
  `./setup.sh`, any module's `setup.sh`, `brew bundle`, `brew bundle cleanup`,
  `mise use -g`, `mise install`, and anything using `defaults write` or `sudo`.
  Make the file changes and let the user apply them.
- **`brew bundle cleanup` uninstalls everything absent from the Brewfile.**
  Treat edits to `brew/Brewfile` as consequential.
- **Don't break the shell.** `~/.zshrc` is a symlink into this repo, so a
  syntax error in `zsh/*.zsh` breaks every new terminal. Run `zsh -n` on every
  zsh file you touch, and prefer testing with an isolated
  `ZDOTDIR` over the live config.
- **Verify shell scripts** with `shellcheck` when available, otherwise
  `bash -n`. There is no build or test suite.
- **Startup time is a feature.** Before and after any `zsh/` change, compare
  `ZSH_PROFILE=1 zsh -i -c exit`. Anything that adds a subprocess to every
  shell start needs to justify itself.
- **One version manager.** mise owns python, node, ruby, go and java. Never
  add a `pyenv`/`rbenv`/`jenv`/`nvm`/`asdf` init hook back into the shell.
- **Dual-arch.** Use `brew_prefix` from `lib/common.sh`; never hardcode
  `/opt/homebrew` or `/usr/local`.
- **Secrets never land in the repo.** `~/.claude.json`,
  `~/.claude/.credentials.json` and `~/.config/github-copilot/apps.json` hold
  credentials. Only declarative config is versioned under `ai/`.
