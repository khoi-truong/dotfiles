---
description: Review the current diff for bugs, risk and simplification
argument-hint: "[base-ref]"
---
Review the changes on this branch against `${1:-main}` (`git diff ${1:-main}...HEAD` plus any uncommitted changes from `git diff HEAD`).

Report only real problems, most severe first, each with `file:line`, the concrete failure scenario, and a suggested fix:

- Correctness bugs and unhandled edge cases
- Security issues (secrets, injection, unsafe permissions)
- Missing or weak verification
- Code that can be deleted or simplified without changing behaviour

Do not edit files. If nothing survives scrutiny, say so.
