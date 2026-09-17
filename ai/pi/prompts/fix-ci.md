---
description: Diagnose and fix the failing CI run for this branch
argument-hint: "[run-id]"
---
Target run: ${1:-the most recent failed run for the current branch}. To find
it, run `gh run list --limit 5 --branch` with the current branch name. Read
its failed job logs with `gh run view RUN_ID --log-failed`.

1. Identify the root cause, quoting the relevant log lines.
2. Reproduce it locally with the same command when possible.
3. Make the smallest fix and rerun the local check.
4. Summarise the cause and the fix. Do not push unless asked.
