# Worktrees

**One agent per directory, always.** herdr provides no file isolation; two
agents in one checkout will interleave edits.

## Layout

Worktrees live at `../<repo>-<branch>` via `git wta`, which is this repo's
convention (`git/gitconfig`, plus the `wt` fzf jumper and `git tidy`).

This **diverges from every comparable system** — OMC uses `.omc/worktrees/`,
the orcas use `.orca/…`. The divergence is deliberate: those helpers are worth
more than conformity. Recorded here so it reads as a choice, not an oversight.

Use `git wta`, not `herdr worktree create`, so `wt` and `git tidy` keep
working.

## Seeding

A `post-checkout` hook from `git/template/` clones every path listed in the
main checkout's `.worktreeclone` into the new worktree with APFS
copy-on-write, so there is nothing to reinstall. Claude Code's `--worktree`
skips git hooks, so a `SessionStart` hook in `ai/claude/settings.json` runs the
same script. Never list a virtualenv — they embed absolute paths.

## At creation: verify a clean baseline

A worktree that starts with a failing build hands every downstream failure an
ambiguous cause. `crew.sh spawn` refuses a worktree whose tree is already
dirty.

## At teardown: an explicit finish decision

Merge, open a PR, keep, or discard — never implicit. `crew.sh teardown` refuses
on a dirty tree or unpushed commits unless forced, prompts for the decision,
then closes the workspace, runs `git worktree remove` and `git tidy`.

## State that must outlive the worktree

`.omc/` is gitignored, and a linked worktree's `.omc/` is removed with the
worktree. So handoffs are written to the **main checkout's** `.omc/handoffs/`
as an absolute path, and `OMC_STATE_DIR` is exported into the workspace so OMC
state lands there too.

Because `workspace create --env` only reaches the **root pane**, the agent must
occupy that root pane — or `--env` must be repeated on the split.
