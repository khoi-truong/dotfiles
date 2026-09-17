---
description: Push the branch and open a pull request
argument-hint: "[extra context]"
---
Open a pull request for the current branch with `gh pr create`.

1. Refuse if the current branch is the default branch.
2. Summarise `git log --oneline main..HEAD` and `git diff main...HEAD --stat`.
3. Title: Conventional Commits form, at most 50 characters.
4. Body: what changed and why, then how it was verified. No AI attribution.
5. Push with `git push -u origin HEAD`, then create the PR and print its URL.

Extra context: $@
