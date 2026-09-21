# Worktrees

## Layout

Worktrees live at `../<repo>-<branch>` via `git wta`, this repo's convention
(`git/gitconfig`, the `wt` fzf jumper, `git tidy`) — never `herdr worktree
create`, which those helpers would not see.

This **diverges from every comparable system** — OMC uses `.omc/worktrees/`,
the orcas `.orca/…` — deliberately: those helpers are worth more than
conformity.

## Seeding

A `post-checkout` hook from `git/template/` clones every path in the main
checkout's `.worktreeclone` with APFS copy-on-write, so nothing is reinstalled.
Claude Code's `--worktree` skips git hooks, so a `SessionStart` hook in
`ai/claude/settings.json` runs the same script. Never list a virtualenv: they
embed absolute paths.

## At creation: verify a clean baseline

A worktree that starts with a failing build gives every downstream failure an
ambiguous cause. `team.sh spawn` refuses an already-dirty tree.

## At teardown: an explicit finish decision

Merge, open a PR, keep, or discard — never implicit. `team.sh teardown` refuses
a dirty tree or unlanded work unless forced, prompts for the decision, then
closes the workspace and runs `git worktree remove` then `git tidy`.

Landed means nothing ahead of `@{u}` or, with no upstream, a merge into the
default branch changing nothing. Not a count: the forge deletes the head
branch on merge and a squash strands its commits, so counting refused every
merged worktree and taught `--force` on a guard that was right.

## State that must outlive the worktree

`.herdr/` and `.omc/` are gitignored and a linked worktree's copy of either
dies with it, so a spawn exports the state roots `herdr-adapter.md` lists,
pointing into the main checkout.
