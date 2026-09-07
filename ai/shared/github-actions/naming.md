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

| Surface                        | Style                     | Rule                                                                                                                                             | Examples                                                                                                    |
| ------------------------------ | ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| Workflow `name`                | Declarative noun          | Category label, ≤3 words, Title Case. It's a heading, not a sentence.                                                                            | `Tests`, `Code quality`, `Release`, `PR title`                                                              |
| `run-name`                     | Declarative statement     | Only set it when the default (commit / PR title) is ambiguous about _which_ run this is. State the distinguishing fact.                          | `Release ${{ github.ref_name }}`, `PR title · ${{ github.event.pull_request.title }}`                       |
| Job key (the map key)          | kebab-case noun/verb      | This is the real id. Make it read naturally at `needs.<id>`. A job that _acts_ (detect, publish) may be a verb.                                  | `detect-changes` → `needs.detect-changes.outputs.go`; `lint`, `govulncheck`, `release`                     |
| Job `name` (optional)          | —                         | **Omit by default** and let the key show in the checks UI. Set it only when the key is genuinely cryptic. Never restate the tool (`golangci-lint`). | usually absent; `Unit tests` if the key were `ut`                                                        |
| Step `id`                      | kebab-case noun           | Name it after the step's **output**, not its action.                                                                                             | `id: changed` → `steps.changed.outputs.go` (not `id: filter`, not `id: run-paths-filter`)                   |
| **Check / gate step `name`**   | **`Verify` / `Check for`** | Verb-first, Sentence case. State the invariant after the verb so a red ✗ names the failure.                                                      | `Verify gofmt and goimports are clean`, `Verify go.mod is tidy`, `Check for known vulnerabilities`, `Check for lint findings`, `Run pre-commit hooks` |
| **Action step `name`**         | Imperative                | Setup / install / build / cache / publish / deploy — steps that change state. Sentence case, no trailing punctuation.                            | `Set up Go`, `Build`, `Cache golangci-lint`, `Create GitHub release`, `Warm the module proxy`               |
| Bare `run:` step               | _no name_                 | If the command is a one-liner and self-documenting (`go vet ./...`), don't add a name — it's noise. Name it only when multi-line or non-obvious. | `- run: go vet ./...`                                                                                       |
| Composite action `description` | Declarative, third person | GitHub's own convention ("Checks out your repository…"). One sentence, what it does.                                                             | `Provisions the mise toolchain and warms the Go module and build caches.`                                   |

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

The default run title is the commit subject (push) or PR title (pull_request),
which is usually the right label. Set `run-name` only where that's unhelpful:

- **release.yml** → `run-name: Release ${{ github.ref_name }}` (the tag is the
  point; the tagged commit's subject isn't).
- **pr-title.yml** → `run-name: 'PR title · ${{ github.event.pull_request.title }}'`
  (so the run list shows what was checked without drilling in).
- **test.yml / code-quality.yml** → leave unset. The push/PR title already names
  the change.

Keep it a single short line — it's a list-view label, not a description.

## Anti-patterns

- Lowercase step names (`no lint findings`, `gofmt is clean`) — GitHub renders
  `Running: <name>`; every other repo is Sentence case. Use `Check for lint
  findings`, `Verify gofmt is clean`.
- `name: golangci-lint` / `name: Run golangci-lint` on a step whose whole job is
  linting — restates the tool. Name it for the assertion: `Check for lint
  findings`.
- A job `name:` that just echoes the key (`lint` → `name: Lint`) or the tool
  (`name: golangci-lint`) — drop it, the key already shows.
- `id: step1`, `id: filter`, `id: s` — ids that don't survive a move. Name for
  the output (`id: changed`).
- `name: build-and-test-and-lint` job doing three things — split, or at least
  name the key `checks`.
- `run-name` that duplicates the workflow name (`run-name: Tests`) — adds a line,
  says nothing.
- Trailing punctuation or lowercase first word in step names (`Set up go.` /
  `set up Go`) — Sentence case, no period.
