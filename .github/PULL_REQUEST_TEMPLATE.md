<!--
Title: Conventional Commits, <= ~50 chars. It becomes the squash-merge
subject, so anything longer is truncated to "...".
-->

## What

<!-- The change, in a sentence or two. -->

## Why

<!-- The problem it solves or the reason it's worth doing. -->

## Verification

<!-- Delete rows that don't apply. -->

- [ ] `bash -n` / `shellcheck` on touched shell scripts
- [ ] `zsh -n` on touched `zsh/*.zsh`
- [ ] Startup time compared: `ZSH_PROFILE=1 zsh -i -c exit` (before / after)
- [ ] Re-ran the affected module's `setup.sh` (idempotent)
- [ ] `markdownlint-cli2` clean
