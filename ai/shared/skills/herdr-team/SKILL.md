---
name: herdr-team
description: >-
  Protocol for running coding agents in separate herdr panes, one git worktree
  each, coordinated through files on disk: one orchestrator the user talks to,
  N executors in worktrees, and ephemeral spec, research and review panes.
  Use when the work needs real process isolation — spawning or tearing down an
  agent pane, dispatching to an agent in another worktree, or collecting a
  handoff file. Fires
  on "herdr team", "spawn an executor", "worktree agent", "dispatch", "handoff",
  "team.sh". Not for in-process fan-out inside one pane: that is OMC's `/team`
  skill, which shares the word and nothing else.
---

# herdr agent team

One pane holds the user. Everything else is dispatched work.

**Two things are called "team" here.** OMC's `/team` skill fans out to
in-process subagents inside one pane; this one is panes — one agent per pane,
one git worktree each, state on disk. When either would work, reach for `/team`
first: this costs more and buys process isolation. The tell: `/team` is a
skill, this is `ai/herdr/team.sh`.

The protocol is the artifact; herdr is an implementation detail.
`references/protocol.md` holds the substrate-independent rules,
`references/herdr-adapter.md` the commands that implement them.

## Roster

A role earns a pane only if it needs a different provider, a different cwd, a
long life, or visibility. Everything else is an in-process subagent — critic,
architect and verifier always are; for fan-out inside one pane use OMC `/team`.

| Role | Pane | Provider (from `team.toml`) | Location |
| --- | --- | --- | --- |
| `orchestrator` | standing | `cc` | main checkout |
| `spec-<round>` | ephemeral | `cc` | main checkout |
| `res-<topic>` | ephemeral | `omp` | main checkout |
| `plan-<task>` | ephemeral | `cc` | main checkout |
| `exec-<run-suffix>-N` | 2 as shipped | `ccd` | one worktree each |
| `rev-<task>` | ephemeral | `cc` | the executor's worktree |

**The Provider column comes from `ai/herdr/team.toml`, not from this file.**
Each cell is that role's `profiles` there, and the pane names, lifetimes and
locations are its `prefix`, `lifetime` and `cwd`. The table is a reading of the
shipped file, not a second source of truth for it: renaming what a role
launches, or routing a kind of row to another role, is an edit to that file.
`team.sh config show` prints what this machine resolves, and `config show
--sources` names the layer every value came from.

**A suffix means there can be more than one of me.** `orchestrator` is bare
because it is singular, and the only standing role. There is no standing
`spec`: a spec or research round is spawned for that round, writes its
artifact, and settles. A long-lived planning pane's only asset is accumulated
context, which rule 5 already says to distrust.

Pool roles match by prefix, and two limits bound them — numbers in those files,
not here. **Per Run: a role's own `max_per_run`** (2 on `role.exec` and 1 on
`role.review` as shipped, and a role that states none — `spec`, `plan`,
`research` — is bounded by the credential's ceiling alone, which is why the
bound sits beside the role rather than in one global knob; `HERDR_TEAM_EXEC_CAP`
is the environment's word on the exec lane's number) — the discipline limit, so
one tab cannot take the machine, and the number a plan's width is read against. **Per provider,
across every Run: one credential's `ceiling` in `ai/providers.toml`** (4 as
shipped, and `HERDR_TEAM_PROVIDER_CAP` over every ceiling) — the resource
limit, because what is contended is auth: one DeepSeek key, one Pro login, and
every tab on the machine shares it. One machine-wide count of executors did
both jobs badly — a `cc` pane refused because two `ccd` panes are live is a
refusal with no resource behind it.

Executor names carry the Run's `hhmmss` as their suffix — a readability
convention, not an enforced one, so a status table spanning three orchestrators
reads as three groups.

## The five rules that matter

1. **Identity comes from the Dispatch**, never from an agent name or a pane
   title. Every prompt and every handoff carries its Run, Task and Dispatch id.
2. **Report exactly once, even on failure.** A silent failure is a protocol
   defect, not an unlucky run. `outcome: succeeded` at `evidence: reported` is
   a claim, not a result.
3. **Absence is never evidence.** A timeout is a checkpoint. Read before
   retrying; only positive proof settles a Dispatch; retry is human-gated.
4. **Settle immediately, exactly once** — reuse, retain or release. "Decide
   later" is how six stale panes accumulate.
5. **State lives in files.** A transcript is never the source of truth. Write
   the handoff before compacting.

## Prohibitions

- Never auto-answer an approval dialog. `team.sh surface <name>` puts it in
  front of the human; answering happens in that pane, by them.
- Never read a transcript on the success path. Results travel by file; a read
  is a diagnostic for a blocked or stalled agent, capped at ~80 lines.
- Never put two agents in one directory. The substrate gives no isolation.
- Never poll. Blocking is `team.sh wait`, not a question asked on a timer; a
  subscription must be opened *before* dispatching, since they do not replay.
- Never let a plugin start an agent or pick its provider.
- Never let `loop` settle, retry or answer a dialog. It dispatches and waits;
  each of those three is a gate it returns at, for a human to take.

## Cost

Tiering is per stage, and the discriminator is verifiability, not price: the
cheap tier is safe wherever a command catches a wrong answer. The orchestrator
routes rather than judges, so it is never the most expensive thing running.
Table in `references/cost.md`.

A plan row names a profile when it has one, and `ai/herdr/team.toml`'s
`[[route]]` table places it otherwise — so which tier a row runs on is the route
table's answer rather than a name repeated here. What a row owes is
`tier_reason`, and the profile says whether it is owed: `requires_reason = true`
on `[profile.cc]` is what makes `plan lint` warn on a row that has a `verify`
and no reason, and what makes `spawn` refuse one. A task that shapes later work,
a spec, or a review is what that reason says; the question is answered by the
plan's author rather than by whoever is spawning under quota pressure.

The fallback is a line of that file too: `[fallback.ccd]` states
`to = ["cc"]`, `on = ["key-missing"]`, and
`guard = { credential = "anthropic-pro", quota_max_pct = 70 }`. So a `ccd`
spawn whose key is missing may fall back to `cc`, and only inside a bounded Pro
window: under 70% of the 5h window, read from the quota cache that credential's
block in `ai/providers.toml` names, fresh enough to describe the window it
names. Unknown is not headroom — a missing or stale cache is a gate for a
human, not a fallback. **`omp` is never that fallback**, and the same table
says so: `never = ["omp"]`, which `config lint` checks against the chain. It is
a different agent spending a DeepSeek key of its own (`ai/omp/models.yml`), so
it relieves nothing the fallback exists to relieve. Any fallback is written to
the pane record and to the Run's `.providers` note: `status` reads the record
back as `ccd→cc` — the profile it asked for, then the one it got — and `report`
lists it from the note, which outlives the pane `release` deletes.

## Reviewing a PR

Per PR, in this order:

1. **The `ccd` handoff is verified.** The executor wrote the branch and a
   handoff whose `commands:` names its row's `verify` at `exit: 0`; that is
   what licenses everything below it.
2. **`settle <exec> retain`.** The next step reads the diff, which lives in the
   executor's worktree, and `release` would refuse a worktree holding work that
   exists nowhere else anyway. The retain is the recorded decision that keeps
   it alive.
3. **A `cc` review.** `/code-review` inline when one read covers the diff, or a
   `rev-<task>` pane in the executor's worktree when the review is long enough
   to want its own context. Always `cc`: a `verify` cannot catch the bug a
   review is for, and a reviewer from another model family is a second opinion
   (`references/cost.md`).
4. **The human reads the diff in herdr-reviewr** and sends line comments into
   the retained executor's pane, which is what the retain in step 2 was for —
   the pane that wrote the branch is the one that answers the comments.
   herdr-reviewr is the human's review surface, not an agent: nothing here
   dispatches to it, it is not on the roster, and the reviewer in step 3 does
   not talk to it.
5. **Merge, then `settle <exec> release`.** The retain has nothing left to
   hold once the work is upstream, and a pane that keeps it is the stale pane
   rule 4 is about.

## Tooling

`ai/herdr/team.sh` — `run`, `spawn`, `dispatch`, `status`, `collect`, `wait`,
`loop`, `report`, `surface`, `plan`, `settle`, `teardown`, `config`;
`prefix+alt+t` shows the status table.
The script owns topology, this skill owns the protocol, and the flags and exit
codes are stated once, in `references/herdr-adapter.md`.

`config` is the verb for the settings themselves, and the settings are
`ai/herdr/team.toml` — the shipped file, then `ai/herdr/team.local.toml` beside
it for this machine. `config lint` says they resolve at all: a profile nothing
can launch, a fallback that cycles, a value that is not a key. `config doctor`
reports what is not an error (this shell's provider against the orchestrator's
role). `config show` prints the resolved keys, and `--sources` the layer each
value came from. `HERDR_TEAM_CONFIG=<file>` replaces every layer, which is the
way back from a local file that will not parse.

**A Run can work on a repo other than the dotfiles.** `run new --repo <path>`
binds every later `spawn`/`teardown`/`config` in that Run to it; a bare
`--repo` on a single `config` call does the same for one call. It must be
passed explicitly — `run new` never infers it from `$PWD` — and the default
with no `--repo` is the dotfiles checkout. `teardown` in a project repo only
removes the worktree (`worktree remove`/`worktree prune`); it never runs `git
tidy`, which is a dotfiles-only alias. The project's own `.config/herdr/*.toml`
is untrusted until `config trust` records the repo and a sha256 of both files;
`config trust` is not a security boundary against an agent that already has a
shell, since anything with a shell can edit the trust file directly. Also
watch `wta`: it names a worktree by the repo's basename, so two repos sharing
one collide under `~/.worktrees/`.

Only `team.sh` starts an agent: it is the only place that knows `cc` and `ccd`
are shell functions rather than binaries, which is what keeps work off the
wrong provider.

**Dispatch through it too, never by typing into a pane.** `dispatch` emits the
completion contract filled in from the current Run — hand-writing it is how ids
drift and handoffs go missing — and picks the lowest unused Dispatch id, the
never-reuse rule made mechanical rather than remembered. herdr rejects a
blocked agent before sending, so a dispatch can never answer an approval
dialog.

Two things the verb list does not say:

- **`release` refuses a worktree holding work that exists nowhere else**, since
  releasing would destroy it. The order is then `settle <name> retain`, push,
  `settle <name> release` — the retain being the recorded decision the release
  licenses.
- **The Run id lives in a file**, not in the transcript, and **one orchestrator
  pane is one Run** — a second tab driving a second plan mints its own Run and
  its own `D-01`. `run new --plan <plan.md>` links the plan's absolute path to
  the Run, so `run resolve <plan.md>` recovers the id once that file is gone:
  the plan path is the one identifier that survives compaction and pane death.
  Start a Run before dispatching, and a dead pane costs nothing.

**`team.sh loop --plan <plan.md>` is how a plan is run, and it needs no one
watching a pane.** It repeats one wave — `collect --plan`, dispatch what is
`ready`, `wait` — until the plan is complete or a gate returns, and writes the
Run's `report` on the way out however it ends. Each gate is a decision the loop
is forbidden to make, so it stops and names it instead — including a
provider's last seat, which it leaves for a human who is there to decide.

When a gate returns, the same wave by hand is the fallback: `collect --plan`
reports one row per task in the plan with an exit code saying what to do next,
`dispatch` sends it, `wait` blocks until one outstanding Dispatch settles and
says nothing about the outcome. Every one of these is scoped to **its own
Run**, so another tab's outstanding Dispatch can never end this Run's wait, and
none of them decides anything: nothing they do writes state or blocks a
dispatch.

The plan format is the `dispatchable-plan` skill's, and `team.sh plan lint
<plan.md>` checks a plan against it before anything is spawned.
