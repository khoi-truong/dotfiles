# Cost and speed

Most repos here are **private on the free plan**: 2,000 Actions minutes/month,
billed per job, **rounded up to the whole minute**, with OS multipliers. Public
repos are unmetered — but optimise anyway, because the same levers cut
wall-clock feedback time, and slow CI is its own tax.

Rules in rough order of impact.

## 1. Runner OS — the 10× lever

- **Linux only** unless you ship platform-specific code paths that fixtures
  can't cover. macOS bills **10×**, Windows **2×**. A 5-minute macOS job burns 50
  minutes of quota.
- Pin the version: `runs-on: ubuntu-24.04`, not `ubuntu-latest`. A runner-image
  rollover under `-latest` can silently lengthen every job and occasionally
  breaks tool availability.

## 2. Don't run the same work twice

- `on: [push]` + `on: pull_request` both fire on a PR branch → double billing.
  Use `on.push.branches: [main]` + `on.pull_request`. Feature branches then run
  once (PR), `main` once (merge).
- `concurrency:` with `cancel-in-progress: true` on every non-release workflow.
  A force-push mid-run kills the superseded run — saves the minutes _and_ frees
  the queue slot so the new push starts now.

  ```yaml
  concurrency:
    group: ${{ github.workflow }}-${{ github.ref }}
    cancel-in-progress: true
  ```

## 3. Filter aggressively — a docs PR should cost ~0

Two layers, both needed:

1. **Trigger level** — `paths-ignore` for the obvious:

   ```yaml
   on:
     pull_request:
       paths-ignore: ["**.md", "docs/**", "LICENSE", ".gitignore"]
   ```

2. **Job level** — `dorny/paths-filter` in a tiny `detect-changes` job, then
   `needs` + `if` on the expensive jobs:

   ```yaml
   jobs:
     detect-changes:
       runs-on: ubuntu-24.04
       timeout-minutes: 5
       outputs:
         go: ${{ steps.changed.outputs.go }}
         workflows: ${{ steps.changed.outputs.workflows }}
       steps:
         - uses: actions/checkout@v7
           with: { persist-credentials: false }
         - uses: dorny/paths-filter@<sha> # v4.0.3
           id: changed
           with:
             filters: |
               go: ['**/*.go', 'go.mod', 'go.sum', '.golangci.yml']
               workflows: ['.github/**']
     lint:
       needs: detect-changes
       if: needs.detect-changes.outputs.go == 'true'
       ...
   ```

Why not just `on.paths`? Because a required status check that never runs stays
**pending forever** and blocks merge. A `needs`-gated job that's skipped reports
**success**. So `on.paths` is safe only for non-required workflows; required
checks must use the job-level gate.

Filter granularly: the lint job keys on `**/*.go` + `.golangci.yml`; the
actionlint job keys on `.github/**`; pre-commit keys on its own config.

## 4. Skip draft PRs

```yaml
if: github.event.pull_request.draft == false
```

on the heavy jobs. Don't pay for CI on work-in-progress. Pair with
`on.pull_request.types: [..., ready_for_review]` so marking ready re-triggers.

## 5. Fewer, fatter jobs

Each job = a fresh runner boot + checkout + toolchain setup (~30–60s billed)
before any real work, billed rounded up to the minute. On a metered plan, 4
parallel jobs each re-doing setup can cost **more total minutes** than one
sequential job — parallelism buys wall-clock, not quota.

- Merge `vet` + `build` + `test` into one job.
- Keep `lint` / `govulncheck` / `actionlint` separate only because their path
  filters and caches differ and you want independent reporting.
- Never create a job whose body is just `needs:` + a 2-line script — inline it.
- Per workflow, pick the trade: **PR checks favour speed** (parallel), **nightly
  favours cost** (sequential).

## 6. Cache the build cache — biggest wall-clock win

A cold `go test` on a fresh runner recompiles the world (~2–4 min for a small
lib). Warm → seconds.

- `setup-go`'s built-in cache covers **modules only**. Add `actions/cache`
  explicitly for `~/.cache/go-build`:

  ```yaml
  - uses: actions/cache@v6
    with:
      path: ~/.cache/go-build
      key: ${{ runner.os }}-gobuild-${{ hashFiles('go.sum') }}-${{ github.sha }}
      restore-keys: |
        ${{ runner.os }}-gobuild-${{ hashFiles('go.sum') }}-
        ${{ runner.os }}-gobuild-
  ```

- `restore-keys` for partial hits so a dep bump doesn't cold-start.
- Same pattern for `~/.cache/golangci-lint` and `~/.cache/pre-commit`.
- Salt the key with a version you can bump to force a rebuild.

## 7. Fail fast — order cheap gates first

- Job ordering: cheap gates (`gofmt`, `vet`, `actionlint` — seconds) as `needs`
  predecessors of the slow job (`test` with `-race`). A formatting failure
  shouldn't wait on the race detector.
- Step ordering within a job: cheapest command first. `gofmt --diff` → `go vet`
  → `go build` → `go test`. First failure stops the job.
- `strategy.fail-fast: true` (the default) on any matrix — don't disable without
  a reason.
- No `continue-on-error: true` to paper over flake. Fix or delete the step.

## 8. Matrix discipline

- Only the versions you actually support. A Go library pinned to 1.26 tests on
  1.26 — not "current, previous, tip".
- Matrix multiplies billed minutes by the number of legs. A 3-OS × 3-version
  matrix on a 4-minute job = 36 minutes per run.

## 9. Schedule crons

- `schedule:` burns minutes on an idle repo. Nightly `govulncheck` at most;
  never hourly.
- Prefer `workflow_dispatch` + Dependabot alerts over polling crons.
- Scheduled runs on a fork or a repo with no recent activity get disabled by
  GitHub after 60 days — don't rely on them as the only signal.

## 10. Free-tier non-levers (don't bother)

- Merge queue (`merge_group`) — Team/Enterprise only.
- Larger runners — paid.
- Self-hosted runners to dodge quota — not worth the maintenance and security
  cost for a small library. If you ever do, `ephemeral` + hardened only.
