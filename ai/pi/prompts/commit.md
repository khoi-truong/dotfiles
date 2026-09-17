---
description: Commit staged changes with a Conventional Commits message
argument-hint: "[extra context]"
---
Write a commit for the staged changes (`git diff --cached`). If nothing is staged, show `git status --short` and ask what to stage.

- Subject: Conventional Commits (`type(scope): summary`), imperative, at most 50 characters.
- Body: why the change was made, wrapped at 72 columns. Omit it for trivial changes.
- No AI attribution of any kind: no `Co-Authored-By`, no "Generated with" line.
- Sign the commit (`git commit -S`). Never pass `--no-verify`.

Extra context: $@
