---
name: github-actions
description: >-
  Opinionated conventions and decision rules for authoring, reviewing, and
  refactoring GitHub Actions workflows and composite actions. Use this whenever
  touching anything under .github/ — creating or editing a workflow or action
  YAML, naming jobs/steps/ids, wiring triggers, pinning action versions,
  choosing between a composite action and a reusable workflow, deciding
  github-script vs shell, tightening permissions, or cutting CI cost and
  runtime. Fires on "github actions", "workflow", "CI YAML", ".github/workflows",
  "reusable workflow", "composite action", "actionlint", "zizmor", even when the
  user doesn't explicitly ask for "conventions".
---

# GitHub Actions conventions

House rules for CI YAML. These are **decisions already made** — apply them
without re-litigating. They exist because the defaults and the copy-paste
patterns floating around the web optimise for neither cost, speed, nor
readability, and most repos here run on the **private free plan (2,000
min/month)** where wasted minutes are real money and slow feedback is real
friction.

When a rule below would be the same for anyone on earth, it's just GitHub's
docs — follow the doc. What's captured here is the stuff that's a _choice_.

## Non-negotiables checklist

Run this against every workflow you write or review:

- [ ] Top-level `permissions: {}`; each job re-grants only what it needs, `read` unless it writes.
- [ ] Every `job` has `runs-on` pinned to a version (`ubuntu-24.04`, never `-latest` for anything reproducibility- or release-sensitive) and a tight `timeout-minutes`.
- [ ] `concurrency:` group on every workflow, keyed by `${{ github.workflow }}-${{ github.ref }}`; `cancel-in-progress: true` except release/deploy.
- [ ] Third-party actions pinned to a full commit SHA with a `# vX.Y.Z` comment. `actions/*` and `github/*` may use a major tag. Local `./.github/actions/*` take no version.
- [ ] `actions/checkout` with `persist-credentials: false`.
- [ ] No `${{ github.event.* }}` (PR title, branch, commit message, issue body) interpolated into a `run:` block — pass via `env:` and reference `"$VAR"`.
- [ ] Toolchain versions live in the task runner config (`mise.toml`), never in workflow YAML.
- [ ] `run:` blocks stay under ~15 lines; longer logic goes to a committed, lintable script (`scripts/ci/*.sh`) or the task runner.
- [ ] The CI job is a thin wrapper over a locally-runnable target (`mise run ci`) — "what CI does" lives in the repo, not the YAML.
- [ ] Workflows are static-analysed in CI (`actionlint` + `zizmor`).
- [ ] Two-layer path filtering wherever a job is skippable (see cost-and-speed.md).
- [ ] One responsibility per workflow file; the file is named after it (`test.yml`, `release.yml`).

## Reference files

Read the one that matches the decision in front of you:

| File                           | When to read                                                                                                                                        |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `references/naming.md`         | Naming or renaming a workflow, job, step, id, or `run-name`; choosing a step-name verb (`Verify`/`Check for` vs `Set up`/`Build`); writing a composite action `description`. |
| `references/structure.md`      | Factoring repeated CI code; composite action vs reusable workflow; `github-script` vs shell; action version pinning; trigger design.                |
| `references/security.md`       | Setting `permissions`; handling secrets, tokens, or fork PRs; `pull_request_target` / `workflow_run`; anything that touches untrusted input.        |
| `references/cost-and-speed.md` | Cutting billed minutes or wall-clock time; runner OS choice; path filtering; caching; job granularity; matrix; schedule crons.                      |

## The one-line version of each reference

So you know whether you even need to open them:

- **naming**: every step name verb-first, Sentence case. Gates get `Verify …` / `Check for …` (`Verify gofmt is clean`, `Check for known vulnerabilities`); state-changing steps get plain imperative (`Set up Go`, `Build`). Never lowercase (`no lint findings`). Name every job (Sentence case, says what it does) — all or none, never a mix. `run-name` prefixed with `${{ github.workflow }} · …` so the combined "All workflows" list is legible. Reusable-only workflow: mark it by `on: workflow_call` alone + a header comment; optional leading-underscore filename if the folder is crowded. change detection: one reusable workflow (`detect-changes.yml`, `workflow_call`, no checkout), not a composite action; filter keys are one lowercase concern token (`go`, `ci`); expose `<key>` + `<key>-files` outputs.
- **structure**: don't abstract before the third copy. Composite action = shared _steps_; reusable workflow = shared _jobs_ (needs `permissions`/`strategy`). Shell by default; `github-script` only to avoid hand-rolled Octokit. SHA-pin third-party actions.
- **security**: deny by default, grant per job. Untrusted input goes through `env:`, never string-interpolated. Prefer `GITHUB_TOKEN`; avoid `pull_request_target` unless you truly need secrets on fork PRs, and never run PR code in that context.
- **cost-and-speed**: Linux only (macOS bills 10×). Don't run `push` + `pull_request` on the same branch. Filter aggressively so a docs PR costs ~0. Cache the build cache for wall-clock. Cheap gates first so failures surface fast.
