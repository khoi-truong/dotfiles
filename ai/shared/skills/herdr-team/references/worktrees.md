# Worktrees

## Layout

Worktrees live at `../<repo>-<branch>` via `git wta`, this repo's convention
(`git/gitconfig`, plus the `wt` fzf jumper and `git tidy`) — never
`herdr worktree create`, which those helpers would not see.

This **diverges from every comparable system**: OMC uses `.omc/worktrees/`, the
orcas use `.orca/…`. The divergence is deliberate — those helpers are worth
more than conformity — and recorded here so it reads as a choice, not an
oversight.

## Seeding

A `post-checkout` hook from `git/template/` clones every path listed in the
main checkout's `.worktreeclone` into the new worktree with APFS
copy-on-write, so there is nothing to reinstall. Claude Code's `--worktree`
skips git hooks, so a `SessionStart` hook in `ai/claude/settings.json` runs the
same script. Never list a virtualenv: they embed absolute paths.

## At creation: verify a clean baseline

A worktree that starts with a failing build hands every downstream failure an
ambiguous cause. `team.sh spawn` refuses a worktree whose tree is already
dirty.

## At teardown: an explicit finish decision

Merge, open a PR, keep, or discard — never implicit. `team.sh teardown` refuses
on a dirty tree or unpushed commits unless forced, prompts for the decision,
then closes the workspace and runs `git worktree remove` and `git tidy`.

## State that must outlive the worktree

`.herdr/` and `.omc/` are both gitignored, and a linked worktree's copy of
either is removed with the worktree — so a spawn exports the state roots
`herdr-adapter.md` lists, pointing into the main checkout, where `memory.md`
says the handoffs go.
