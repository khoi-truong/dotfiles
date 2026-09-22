# Apps

- [Homebrew](#homebrew)
- [macOS preferences](#macos-preferences)
- [iTerm2](#iterm2)
- [Terminal.app](#terminalapp)
- [VS Code](#vs-code)
- [Xcode](#xcode)
- [Stats](#stats)

## Homebrew

`brew/Brewfile` is the single source of truth, grouped by formulae, casks,
fonts and Mac App Store (`mas`) apps. Language runtimes are not in it; mise
owns them (see [Shell](shell.md#runtimes-mise)).

```sh
sh brew/setup.sh              # install
sh brew/setup.sh --cleanup    # install, then uninstall anything not listed
sh brew/update.sh             # dump what's installed, for reconciliation
```

> [!CAUTION]
> `--cleanup` uninstalls everything absent from the Brewfile. It asks for
> confirmation unless `--yes` or `$CI` is set. Treat Brewfile edits as
> consequential.

`brew/update.sh` writes `Brewfile.generated` rather than overwriting the
grouped `Brewfile`, so the comments survive; fold in the diff by hand.
`scripts/ci/check-brewfile.sh` rejects lines `brew bundle` would fail to load
and duplicate entries.

`mas` entries need an App Store sign-in first, so re-run `sh brew/setup.sh`
after signing in.

## macOS preferences

`macos/setup.sh` is a large `defaults write` script (lineage:
[mths.be/macos](https://mths.be/macos)). Highlights: forced Dark mode,
timezone `Asia/Ho_Chi_Minh`, and a prompt for the computer name
(`macos/set_computer_name.sh`; leave blank to keep the current one).

It needs `sudo`, closes System Settings first so it can't overwrite the
changes, and restarts Finder, Dock and the other affected apps at the end. It
deliberately has no `set -e`: one failed `defaults` call shouldn't abort the
rest.

## iTerm2

iTerm2 is pointed at `iterm/` through its "load preferences from a custom
folder" setting. iTerm writes the plist back there on quit, so changes show up
as repo diffs — commit them from the repo.

## Terminal.app

Opt-in (`./setup.sh terminal`); iTerm2 is the daily driver. Imports
`terminal/Gruvbox.terminal` through `osascript` and sets UTF-8 as the only
encoding.

## VS Code

Opt-in (`./setup.sh vscode`). Links `settings.json`, `keybindings.json` and
`snippets/` into the VS Code user directory, puts the bundled `code` CLI on
`$PATH`, installs the extensions in `vscode/extensions.vscode`, and creates the
editor `.venv` (with `uv`) that `pyrightconfig.json` points Pylance at. Skips
itself when VS Code isn't installed.

After installing or removing extensions, record them with
`bash vscode/update.sh`.

## Xcode

Opt-in (`./setup.sh xcode`).

- **Themes** — `Gruvbox` and `Spartan`, linked one file at a time into
  `~/Library/Developer/Xcode/UserData/FontAndColorThemes/` so Xcode's own
  themes in that folder stay visible.
- **File templates** — `RIBs` (RIB, unit tests, component extension) and
  `ModelMapping` (ObjectMapper).

## Stats

[Stats](https://github.com/exelban/stats), the menu-bar monitor, has its
preferences imported by `misc/stats/setup.sh` from
`misc/stats/eu.exelban.Stats.plist`. After changing settings in the app,
re-dump them with `bash misc/stats/update.sh`.

`misc/` runs every `misc/*/setup.sh`, so a new small app is a new
subdirectory.
