# Naming — workflows, jobs, steps, ids, run-name

The governing idea: **declarative by default, imperative only for things that
act.** A CI run is mostly a list of invariants being checked; when one goes red,
the name should read as the exact violation ("`go.mod is tidy` ✗" tells you
everything). Steps that genuinely _do_ something — set up a toolchain, build,
deploy — are shown by GitHub's UI as "Running: <name>", so an imperative verb
reads correctly there and a declarative phrase reads oddly.

## The table

| Surface                        | Style                     | Rule                                                                                                                                             | Examples                                                                                                    |
| ------------------------------ | ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------- |
| Workflow `name`                | Declarative noun          | Category label, ≤3 words, Title Case. It's a heading, not a sentence.                                                                            | `Tests`, `Code quality`, `Release`, `PR title`                                                              |
| `run-name`                     | Declarative statement     | Only set it when the default (commit / PR title) is ambiguous about _which_ run this is. State the distinguishing fact.                          | `Release ${{ github.ref_name }}`, `PR title · ${{ github.event.pull_request.title }}`                       |
| Job key (the map key)          | kebab-case noun           | This is the real id. Make it read naturally at the reference site.                                                                               | `detect-changes` → `needs.detect-changes.outputs.go`; `lint-actions`, `release`                             |
| Job `name` (optional)          | Declarative noun          | The column label in the checks UI. Often better to omit and let the key show. Set it only when the key is cryptic.                               | `Vulnerabilities`, `Unit tests`                                                                             |
| Step `id`                      | kebab-case noun           | Name it after the step's **output**, not its action.                                                                                             | `id: changed` → `steps.changed.outputs.go` (not `id: filter`, not `id: run-paths-filter`)                   |
| **Check / gate step `name`**   | **Declarative assertion** | State the invariant that must hold. A red ✗ then names the exact failure.                                                                        | `gofmt is clean`, `go.mod is tidy`, `no known vulnerabilities`, `no lint findings`, `pre-commit hooks pass` |
| **Action step `name`**         | Imperative                | Setup / install / build / cache / publish / deploy — steps that change state. Title Case, no trailing punctuation.                               | `Set up Go`, `Build`, `Cache golangci-lint`, `Create GitHub release`, `Warm the module proxy`               |
| Bare `run:` step               | _no name_                 | If the command is a one-liner and self-documenting (`go vet ./...`), don't add a name — it's noise. Name it only when multi-line or non-obvious. | `- run: go vet ./...`                                                                                       |
| Composite action `description` | Declarative, third person | GitHub's own convention ("Checks out your repository…"). One sentence, what it does.                                                             | `Installs the mise toolchain and warms the Go module and build caches.`                                     |

## Deciding: is this a check step or an action step?

Ask "if this step fails, is it because an **invariant was violated** or because a
**task errored**?"

- Invariant violated → check step → declarative assertion.
  `gofmt is clean`, `go.mod is tidy`, `no known vulnerabilities`,
  `generated code is up to date`, `no lint findings`.
- Task errored → action step → imperative.
  `Set up Go`, `Build`, `Run migrations`, `Publish package`.

`go vet` / `go build` / `go test` are borderline: they _run a task_ but you're
really asserting "it compiles" / "tests pass". Convention here: keep them
imperative (`Vet`, `Build`, `Run tests with race detector`) because they're
doing meaningful work and the imperative reads fine in the progress log. The
pure-assertion style is reserved for the fast boolean gates (fmt, tidy, vuln,
lint-clean).

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

- `name: Run golangci-lint` on a step whose whole job is linting — the job key
  already says `lint`; name the step for the assertion (`no lint findings`) or
  leave the `run:` bare.
- `id: step1`, `id: filter`, `id: s` — ids that don't survive a move. Name for
  the output.
- `name: build-and-test-and-lint` job doing three things — split, or at least
  name it `checks`.
- `run-name` that duplicates the workflow name (`run-name: Tests`) — adds a line,
  says nothing.
- Trailing punctuation or sentence case in step names (`Set up go.` / `set up
Go`) — Title Case, no period.
