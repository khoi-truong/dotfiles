# Git

- [Configuration](#configuration)
- [Signing](#signing)
- [Hooks](#hooks)
- [Worktrees](#worktrees)
- [Aliases](#aliases)
- [Diff and review](#diff-and-review)

## Configuration

| File | Linked to |
| --- | --- |
| `git/gitconfig` | `~/.gitconfig` |
| `git/ignore` | `~/.config/git/ignore` (global ignore) |
| `git/template/` | `~/.config/git/template` (`init.templateDir`) |
| `git/lazygit.yml` | `~/Library/Application Support/lazygit/config.yml` |

`gitconfig` ends by including `~/.config/git/gitconfig.local`, which holds
everything machine-specific: `user.name`, `user.email` and `gpg.program`.
`git/setup.sh` rewrites `gpg.program` for the current architecture on every
run and asks for the name and email only when they are missing.

## Signing

Every commit is signed (`commit.gpgSign = true`), so git refuses to commit
until a key is imported and trusted.

`gpg/setup.sh` copies `gpg.conf` and a rendered `gpg-agent.conf` (with the
arch-correct `pinentry-mac` path) into `~/.gnupg`. They are copied, not linked,
because gpg insists on a real `700` directory. Keys and `trustdb` are never
versioned.

## Hooks

`init.templateDir` puts two hooks into every new clone. Existing repos pick
them up with `git init`, which never overwrites an existing hook.

| Hook | Does |
| --- | --- |
| `pre-commit` | Runs `gitleaks` on staged changes and blocks a commit that stages a secret. Skips with a warning when gitleaks is missing; `--no-verify` bypasses it once. |
| `post-checkout` | Seeds a new worktree: each path listed in the main checkout's `.worktreeclone` (e.g. `node_modules`, generated code) is cloned in with APFS copy-on-write, so there is nothing to reinstall. |

Claude Code's `--worktree` skips git hooks, so a `SessionStart` hook in
`ai/claude/settings.json` runs the same `post-checkout` script.

`.worktreeclone` takes one path per line, `#` comments allowed. Don't list
virtualenvs: they embed absolute paths.

## Worktrees

All worktrees live under `~/.worktrees/<repo>/<branch>` (`/` in the branch
becomes `-`).

```sh
git wta feat/x      # add ~/.worktrees/<repo>/feat-x, creating the branch if needed
wt                  # cd into one, picked with fzf
git wt              # list them
git wtrm <path>     # remove one
git tidy            # prune merged/gone branches and stale worktree records
```

**Why not beside the repo, or inside it?** One place rather than scattered
beside whichever checkout spawned them. Not inside the repo, where every tree
walk from the root (find, CI's lint globs, editor indexing) would see a full
copy per worktree, and `git clean -xdff` would delete them all, unpushed
commits included.

The repo name comes from `--git-common-dir`, so `git wta` behaves the same
from a subdirectory or from inside another worktree. herdr's `New worktree`
uses the same layout, so both routes land on one checkout — see
[herdr](herdr.md#worktrees).

## Aliases

Run `git aliases` for the full list.

| Alias | Does |
| --- | --- |
| `s` | Short status with branch |
| `l` | Graph log, last 20 |
| `amend` | Amend keeping the message; `amendp` also force-pushes with lease |
| `undo` | Undo the last commit, keep its changes staged |
| `fixup <sha>` | Fold staged changes into `<sha>` and autosquash |
| `reb <n>` | Interactive rebase of the last `n` commits |
| `tidy` | Delete merged and gone branches, prune worktrees |
| `wt`, `wta`, `wtrm` | Worktrees — see above |
| `dft` | Structural diff with difftastic |
| `fb <sha>` | Branches containing a commit |
| `fc <code>`, `fm <text>` | Find commits by code change / by message |

## Diff and review

| Tool | Used for |
| --- | --- |
| [delta](https://dandavison.github.io/delta/) | `git diff` pager: side-by-side, `n`/`N` between files. Only on a TTY, so a diff an agent captures stays plain text. |
| [difftastic](https://difftastic.wilfred.me.uk) | `git dft`: compares syntax trees, so a reindent or a moved function reads as no change. |
| lazygit | Staging and committing. `prefix+alt+g` opens it in a herdr popup. |
| herdr-reviewr | Line comments sent back to the agent — see [herdr](herdr.md#plugins). |

lazygit ignores `core.pager`, so `git/lazygit.yml` configures the renderers
again under `git.diffRenderers`; `|` cycles delta → difftastic →
`--color-words`. delta runs there with `--features=lazygit`, a
`[delta "lazygit"]` block in `git/gitconfig` that drops side-by-side and
`navigate` for the narrow panel and turns on clickable line numbers.

> [!TIP]
> Stage lines under delta, not difftastic. An external diff produces no patch
> for lazygit to apply.

The merge decision still goes through `/code-review` and a signed PR. The AI
review pass runs in its own session, separate from the one that wrote the
code.
