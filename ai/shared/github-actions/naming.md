# Naming — workflows, jobs, steps, ids, run-name

The governing idea: **every step name is verb-first and Sentence case** — this
is the near-universal community convention and it matches GitHub's own UI, which
renders a running step as "Running: <name>". Within that, carry the distinction
between _checking an invariant_ and _doing work_ through the **verb you pick**,
not through casing or phrasing:

- Asserting something holds → `Verify …` / `Check for …`.
  A red ✗ on `Verify gofmt is clean` names the exact violation.
- Doing work (setup, build, cache, publish, deploy) → `Set up …`, `Build`,
  `Cache …`, `Publish …`, `Run …`.

Do **not** use lowercase declarative names (`gofmt is clean`, `no lint
findings`) — they read as typos in review and collide with the "Running: …" UI.

## The table

| Surface                        | Style                      | Rule                                                                                                                                                                                                                 | Examples                                                                                                                                              |
| ------------------------------ | -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Workflow `name`                | Declarative noun           | Category label, ≤3 words, Title Case. It's a heading, not a sentence.                                                                                                                                                | `Tests`, `Code quality`, `Release`, `PR title`                                                                                                        |
| `run-name`                     | Declarative statement      | Prefix with the workflow name so the combined "All workflows" list stays legible — otherwise every workflow's rows read identically (commit subject × N). `"${{ github.workflow }} · <distinguishing fact>"`.        | `"${{ github.workflow }} · ${{ github.event.pull_request.title \|\| github.event.head_commit.message }}"`, `Release ${{ github.ref_name }}`           |
| Job key (the map key)          | kebab-case noun/verb       | This is the real id. Make it read naturally at `needs.<id>`. A job that _acts_ (detect, publish) may be a verb.                                                                                                      | `detect-changes` → `needs.detect-changes.outputs.go`; `lint`, `govulncheck`, `release`                                                                |
| Job `name`                     | Verb-first, Sentence case  | **Name every job** — the moment one job is named, an unnamed job shows its raw key next to it and the checks column looks broken. Say what the job does, don't restate the bare tool. The key stays the `needs:` id. | `Detect changed paths`, `Lint Go code`, `Scan for vulnerabilities`, `Build and test`, `Quality gate`                                                  |
| Step `id`                      | kebab-case noun            | Name it after the step's **output**, not its action.                                                                                                                                                                 | `id: changed` → `steps.changed.outputs.go` (not `id: filter`, not `id: run-paths-filter`)                                                             |
| **Check / gate step `name`**   | **`Verify` / `Check for`** | Verb-first, Sentence case. State the invariant after the verb so a red ✗ names the failure.                                                                                                                          | `Verify gofmt and goimports are clean`, `Verify go.mod is tidy`, `Check for known vulnerabilities`, `Check for lint findings`, `Run pre-commit hooks` |
| **Action step `name`**         | Imperative                 | Setup / install / build / cache / publish / deploy — steps that change state. Sentence case, no trailing punctuation.                                                                                                | `Set up Go`, `Build`, `Cache golangci-lint`, `Create GitHub release`, `Warm the module proxy`                                                         |
| Bare `run:` step               | _no name_                  | If the command is a one-liner and self-documenting (`go vet ./...`), don't add a name — it's noise. Name it only when multi-line or non-obvious.                                                                     | `- run: go vet ./...`                                                                                                                                 |
| Composite action `description` | Declarative, third person  | GitHub's own convention ("Checks out your repository…"). One sentence, what it does.                                                                                                                                 | `Provisions the mise toolchain and warms the Go module and build caches.`                                                                             |

## Marking a workflow as reusable-only

A `workflow_call`-only file lives in the same `.github/workflows/` folder as the
triggered ones and there is **no official GitHub convention** to set it apart.
Signals that actually work, in order:

1. **`on:` has `workflow_call` as its only key** — this is the real marker;
   actionlint and every reader keys off it. Don't give it `push`/`pull_request`.
2. **A one-line header comment**: `# Reusable (workflow_call only). Called by
test.yml and check-code-quality.yml.`
3. **Filename prefix**, if the folder has several: a leading underscore
   (`_detect-changes.yml`) is the most common community choice and sorts them to
   the top. Local `./.github/workflows/_x.yml` calls are unaffected by the old
   cross-repo "underscore not found" bug, but if in doubt use `reusable-`.
   Don't invent a private prefix nobody recognises (`wc-`, `lib-`).

Keep the workflow `name:` a plain noun like any other — the caller's job name is
what shows in the checks UI, not this.

## paths-filter / change detection

When more than one workflow path-gates its jobs, put `dorny/paths-filter` in a
**reusable workflow** (`.github/workflows/detect-changes.yml`, `on: workflow_call`)
— not inline, not a composite action. Callers get one line:

```yaml
detect-changes:
  uses: ./.github/workflows/detect-changes.yml
```

Why reusable workflow, not composite action: the change detector needs its own
`permissions:` and is already a standalone job — structure.md's rule puts it in
the reusable-workflow column. A composite action also can't share the job-level
`outputs:` block, so every caller would still re-map all the outputs by hand; a
reusable workflow declares `workflow_call.outputs` once and callers read
`needs.detect-changes.outputs.<key>` with zero plumbing.

- **Filter key** = one lowercase token for the _area of concern_ that decides
  which jobs run, not the file extension or the tool: `go`, `openapi`, `ci` —
  not `golang`, `yaml-files`, `actionlint`.
- **Two outputs per key**: `<key>` (a `'true'`/`'false'` string) and `<key>-files`
  (changed paths; `list-files: shell` on the step). Branch on `<key>`; act on the
  diff with `<key>-files`.
- Run the filter step on `pull_request` only (`if: github.event_name ==
'pull_request'`) — it reads the changed-file list from the API, so **no
  checkout**. On push, `<key>` collapses to `'true'` via `github.event_name !=
'pull_request' || steps.filter.outputs.<key> == 'true'` and `<key>-files` is
  empty. A git-based push diff needs a full fetch and breaks on force-push.
- Fold the detector's own path (`.github/workflows/detect-changes.yml`) into the
  `go`/relevant filters so changing it re-runs those jobs.

## Deciding: is this a check step or an action step?

Ask "if this step fails, is it because an **invariant was violated** or because a
**task errored**?"

- Invariant violated → `Verify …` / `Check for …`.
  `Verify gofmt is clean`, `Verify go.mod is tidy`, `Check for known
vulnerabilities`, `Verify generated code is up to date`, `Check for lint
findings`.
- Task errored → plain imperative.
  `Set up Go`, `Build`, `Run migrations`, `Publish package`.

`go vet` / `go build` / `go test` are borderline: they _run a task_ but you're
really asserting "it compiles" / "tests pass". Convention here: keep them plain
imperative (`Vet`, `Build`, `Run tests with race detector`) because they do
meaningful work and read fine in the progress log. Reserve `Verify` / `Check
for` for the fast boolean gates (fmt, tidy, vuln, lint-clean).

## run-name

The default run title is the commit subject (push) or PR title (pull_request).
Per-workflow that reads fine, but the combined **Actions → "All workflows"** list
interleaves every workflow's runs, so three workflows on one commit render three
identical bold rows. Fix: prefix every `run-name` with the workflow name.

- **CI workflows** (`test.yml`, `check-code-quality.yml`, `check-pr-title.yml`) →
  `run-name: "${{ github.workflow }} · ${{ github.event.pull_request.title || github.event.head_commit.message }}"`
  (drop the `|| head_commit` half on `pull_request`-only workflows).
- **release.yml** → `run-name: Release ${{ github.ref_name }}` (the tag is the
  point; the tagged commit's subject isn't).

Keep it a single short line — it's a list-view label, not a description.

## Anti-patterns

- Lowercase step names (`no lint findings`, `gofmt is clean`) — GitHub renders
  `Running: <name>`; every other repo is Sentence case. Use `Check for lint
findings`, `Verify gofmt is clean`.
- `name: golangci-lint` / `name: Run golangci-lint` on a step whose whole job is
  linting — restates the tool. Name it for the assertion: `Check for lint
findings`.
- A job `name:` that just echoes the key (`lint` → `name: Lint`) or the bare
  tool (`name: golangci-lint`) — say what it does: `Lint Go code`.
- Naming _some_ jobs in a workflow but not others — the checks column then mixes
  Sentence-case names with raw kebab keys. All or none; prefer all.
- `id: step1`, `id: filter`, `id: s` — ids that don't survive a move. Name for
  the output (`id: changed`).
- `name: build-and-test-and-lint` job doing three things — split, or at least
  name the key `checks`.
- `run-name` that duplicates the workflow name (`run-name: Tests`) — adds a line,
  says nothing.
- Trailing punctuation or lowercase first word in step names (`Set up go.` /
  `set up Go`) — Sentence case, no period.
