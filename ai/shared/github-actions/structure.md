# Structure — factoring, github-script vs shell, versions, triggers

## Reuse and factoring

Don't abstract before the **third** copy. Two identical blocks is a
coincidence; three is a pattern. A 3-line duplicated `run:` is fine — abstraction
has a readability and indirection cost that a tiny duplication doesn't justify.

### Composite action vs reusable workflow

|          | Composite action (`.github/actions/<name>/action.yml`)       | Reusable workflow (`on: workflow_call`)                                          |
| -------- | ------------------------------------------------------------ | -------------------------------------------------------------------------------- |
| Shares   | A **sequence of steps** inside someone else's job            | **Whole jobs**, with their own runners                                           |
| Has      | `runs.using: composite`, `steps:`                            | `jobs:`, `runs-on:`, `strategy:`, job-level `permissions:`                       |
| Use when | Repeated setup/teardown steps (checkout + toolchain + cache) | Repeated _jobs_ across repos, or you need matrix / per-job permissions / fan-out |
| Lives    | In the repo that uses it (or a shared repo)                  | Usually a central `<owner>/.github` repo                                         |

Decision rule: **if you need `permissions:` or `strategy:` or a separate runner,
it's a reusable workflow. Otherwise it's a composite action.**

- Repeated steps within one repo → composite action (e.g. a `setup-go` action
  that does checkout + mise + cache).
- Repeated jobs across repos → reusable workflow in `<owner>/.github`, `uses:`d
  from each consumer. Only after the third repo needs it.
- Local composite actions are referenced as `./.github/actions/<name>` — the
  portable form. They ride the checked-out SHA, so they take **no version**.

## github-script vs shell

Default to **shell**. It's visible in the log, portable, and runnable locally.

Reach for `actions/github-script` only when the alternative is hand-rolling
`curl` against the GitHub API with `$GITHUB_TOKEN` — i.e. you need Octokit's
pagination/retry, or you need to read/manipulate the workflow context in JS
(labels, review state, comments).

- Never use `github-script` as a general scripting runtime. Parsing JSON, moving
  files, string munging → `jq` and shell.
- Anything over ~20 lines of JS → a real file (`node .github/scripts/foo.mjs`),
  committed, lintable, testable. Not a YAML heredoc.
- `set -euo pipefail` and `shell: bash` on any non-trivial `run:`.

## Action version pinning

| Action source                                         | Pin to                               | Why                                                                                                                                        |
| ----------------------------------------------------- | ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------ |
| Third-party (`dorny/paths-filter`, `goreleaser/*`, …) | Full commit SHA + `# vX.Y.Z` comment | A tag is mutable; a compromised or force-pushed tag runs arbitrary code with your token. Dependabot bumps the SHA and updates the comment. |
| `actions/*`, `github/*`                               | Major version tag (`@v7`)            | Trusted publisher; you want the patch stream.                                                                                              |
| Local `./.github/actions/*`                           | nothing                              | Rides the checked-out commit.                                                                                                              |
| Anything                                              | never `@main` / `@master` / branch   | Unpinned = unreviewed code on every run.                                                                                                   |

`zizmor`'s `unpinned-uses` audit enforces this; mirror the policy in
`.github/zizmor.yml` (`"*": hash-pin`, `"actions/*": ref-pin`).

## Trigger design

- Prefer explicit `on.push.branches: [main]` + `on.pull_request` over bare
  `on: [push]` (which fires on every branch and every tag).
- This pairing also avoids double runs: a PR branch would otherwise trigger both
  `push` and `pull_request`. With `push` limited to `main`, feature branches run
  once (via the PR), `main` runs once (on merge).
- `on.pull_request.types` — the default is `[opened, synchronize, reopened]`. Add
  `ready_for_review` if a job is gated on draft status. Add `edited` only for
  title/body linting (it's noisy otherwise).
- `workflow_dispatch` on anything you'd ever want to fire by hand (release,
  nightly, a manual re-run).
- `paths` / `paths-ignore` at the trigger level for cheap top-level skips; do the
  granular per-job filtering with `dorny/paths-filter` + `needs` (see
  cost-and-speed.md) so required status checks still report.
- `schedule:` — keep crons rare (nightly at most). See cost-and-speed.md.

## One workflow, one job — when to split vs merge

- **One responsibility per workflow file.** `test.yml`, `code-quality.yml`,
  `release.yml`, `pr-title.yml`. Don't cram unrelated triggers together.
- **Within a workflow**, merge steps into one job when they share a setup and
  run fast (`vet` + `build` + `test`). Split into separate jobs when they have
  different path filters, different caches, or you want them to fail/report
  independently (`lint`, `govulncheck`, `actionlint`). On the free plan, extra
  jobs cost extra runner-boot minutes — see cost-and-speed.md.
