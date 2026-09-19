#!/usr/bin/env bash
# team.sh — the only thing that starts an agent for a herdr team.
#
# It exists because `herdr agent start --kind claude` execs the binary
# directly, which drops everything ai/claude/providers.zsh exports and
# silently bills the Pro plan. Every spawn here goes through
# `zsh -ic <wrapper>` instead, and the provider is asserted afterwards.
#
#   team.sh spawn <name> --branch <b> [--provider ccd|cc|omp]
#   team.sh status
#   team.sh collect [<run-id>]
#   team.sh settle <name> <reuse|retain|release>
#   team.sh teardown <name> [--force]
#
# See ai/shared/skills/herdr-team/ for the protocol these commands implement.
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "$0")/.." && pwd)}"
. "${DOTFILES}/lib/common.sh"
require_macos

HANDOFFS="${DOTFILES}/.omc/handoffs"
# Detection took ~4s in testing; 60s covers a cold start plus an `op read`.
DETECT_TIMEOUT=60

command -v herdr >/dev/null 2>&1 || die "herdr not found — see README."
command -v python3 >/dev/null 2>&1 || die "python3 not found (mise/global.toml pins it)."

# --- helpers ---------------------------------------------------------------

usage() {
  sed -n '9,13p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-1}"
}

# jget <python-expr> — evaluate against the JSON on stdin, bound to `d`.
jget() { python3 -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]) or "")' "$1"; }

valid_name() {
  printf '%s' "$1" | grep -qE '^[a-z][a-z0-9_-]{0,31}$'
}

# agent_field <name> <key> — empty when the agent does not exist.
agent_field() {
  herdr agent list 2>/dev/null | jget \
    "next((a.get('$2','') for a in d['result']['agents'] if a.get('name')=='$1'), '')"
}

worktree_path() {
  printf '%s-%s' "${DOTFILES}" "$(printf '%s' "$1" | tr / -)"
}

# --- spawn -----------------------------------------------------------------
# Runs the agent in the workspace's ROOT pane: `workspace create --env` only
# reaches that pane, not panes split from it afterwards.

cmd_spawn() {
  local name="${1:-}" branch="" provider="ccd" skip_provider_check=0
  shift || true
  while [ $# -gt 0 ]; do
    case "$1" in
      --branch) branch="${2:-}"; shift 2 ;;
      --provider) provider="${2:-}"; shift 2 ;;
      --skip-provider-check) skip_provider_check=1; shift ;;
      *) die "spawn: unknown option $1" ;;
    esac
  done

  [ -n "$name" ] || usage
  valid_name "$name" || die "spawn: name must match [a-z][a-z0-9_-]{0,31}: $name"
  [ -n "$branch" ] || die "spawn: --branch is required"
  case "$provider" in cc | ccd | omp) ;; *) die "spawn: unknown provider $provider" ;; esac

  if [ -n "$(agent_field "$name" pane_id)" ]; then
    ok "agent ${name} already live — nothing to do"
    return 0
  fi

  local dir made_worktree=0
  dir="$(worktree_path "$branch")"
  if [ ! -d "$dir" ]; then
    info "creating worktree ${dir}"
    (cd "${DOTFILES}" && git wta "$branch") >/dev/null
    made_worktree=1
  fi
  # A worktree that starts dirty hands every later failure an ambiguous cause.
  [ -z "$(git -C "$dir" status --porcelain)" ] ||
    die "spawn: ${dir} is dirty — clean it before dispatching work there"

  # .omc/ is gitignored and a linked worktree's copy dies with the worktree,
  # so state and handoffs go to the main checkout.
  mkdir -p "${HANDOFFS}"

  local created ws pane
  created="$(herdr workspace create --cwd "$dir" --label "$name" --no-focus \
    --env "OMC_STATE_DIR=${DOTFILES}/.omc/state" \
    --env "HERDR_TEAM_HANDOFFS=${HANDOFFS}")"
  ws="$(printf '%s' "$created" | jget "d['result']['workspace']['workspace_id']")"
  # The agent must occupy the root pane: `--env` reaches that pane only, not
  # anything split from it later.
  pane="$(printf '%s' "$created" | jget "d['result']['root_pane']['pane_id']")"
  if [ -z "$ws" ] || [ -z "$pane" ]; then
    [ "$made_worktree" -eq 1 ] && git -C "${DOTFILES}" worktree remove --force "$dir" 2>/dev/null
    die "spawn: workspace create returned no workspace/pane id"
  fi

  # Undo everything this call created, so a failed spawn leaves no debris.
  spawn_rollback() {
    herdr workspace close "$ws" >/dev/null 2>&1 || true
    if [ "$made_worktree" -eq 1 ]; then
      git -C "${DOTFILES}" worktree remove --force "$dir" 2>/dev/null || true
      git -C "${DOTFILES}" branch -D "$branch" >/dev/null 2>&1 || true
    fi
  }

  # `pane run` types the command; it does NOT submit it. Without the Enter the
  # spawn hangs forever and looks exactly like a slow start.
  herdr pane run "$pane" "zsh -ic ${provider}" >/dev/null
  herdr pane send-keys "$pane" enter >/dev/null

  local waited=0
  while [ "$waited" -lt "$DETECT_TIMEOUT" ]; do
    if herdr agent list 2>/dev/null | grep -q "\"pane_id\":\"${pane}\""; then break; fi
    sleep 1
    waited=$((waited + 1))
  done
  if [ "$waited" -ge "$DETECT_TIMEOUT" ]; then
    spawn_rollback
    die "spawn: no agent detected in ${pane} after ${DETECT_TIMEOUT}s (1Password locked?)"
  fi

  herdr agent rename "$pane" "$name" >/dev/null

  # A fallback to the Pro login is silent and expensive, so it is fatal by
  # default. The marker is the status-line prefix cc_provider sets via
  # CC_PROVIDER_LABEL (ai/claude/providers.zsh) — only Claude Code wrappers
  # render one, so omp is exempt. It appears a beat after detection, and only
  # on the visible screen: the default `recent` source returns the scrollback
  # from before the launch.
  if [ "$provider" = "ccd" ] && [ "$skip_provider_check" -eq 0 ]; then
    local marker="DS·" found=0 tries=0
    while [ "$tries" -lt 20 ]; do
      if herdr agent read "$name" --source visible --lines 60 2>/dev/null |
        grep -qF "$marker"; then
        found=1
        break
      fi
      sleep 1
      tries=$((tries + 1))
    done
    if [ "$found" -eq 0 ]; then
      spawn_rollback
      die "spawn: ${name} never showed the '${marker}' status-line marker — it may have
     fallen back to the Pro login. Unlock 1Password and retry, or pass
     --skip-provider-check if you know the marker is absent by design."
    fi
  fi

  ok "${name} → ${pane} (${provider}) in ${dir}"
}

# --- status ----------------------------------------------------------------

cmd_status() {
  local agents_json
  agents_json="$(herdr agent list 2>/dev/null)"
  python3 - "$HANDOFFS" "$agents_json" <<'PY'
import glob, json, os, sys
handoffs = sys.argv[1]
d = json.loads(sys.argv[2])
agents = d["result"]["agents"]
if not agents:
    print("no agents")
else:
    w = max(len(a.get("name") or a["pane_id"]) for a in agents)
    for a in sorted(agents, key=lambda a: a["pane_id"]):
        print("%-*s  %-8s  %-8s  %s" % (
            w, a.get("name") or a["pane_id"], a["pane_id"],
            a.get("agent_status", "?"), a.get("cwd", "")))
pending = sorted(glob.glob(os.path.join(handoffs, "*.md")))
print("\n%d handoff(s) in %s" % (len(pending), handoffs))
for p in pending[-10:]:
    print("  " + os.path.basename(p))
PY
}

# --- collect ---------------------------------------------------------------
# Reads outcomes from the handoff files. Never from a transcript: an agent's
# pane is not the record of what it did.

cmd_collect() {
  local run="${1:-}"
  python3 - "$HANDOFFS" "$run" <<'PY'
import glob, os, sys
handoffs, run = sys.argv[1], sys.argv[2]
rows, bad = [], []
for path in sorted(glob.glob(os.path.join(handoffs, "*.md"))):
    lines = open(path, encoding="utf-8").read().splitlines()
    if not lines or lines[0].strip() != "---":
        bad.append((os.path.basename(path), "no frontmatter")); continue
    meta = {}
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if ":" in line:
            k, v = line.split(":", 1)
            meta[k.strip()] = v.strip()
    if run and meta.get("run") != run:
        continue
    missing = [k for k in ("run", "task", "dispatch", "outcome", "evidence") if k not in meta]
    if missing:
        bad.append((os.path.basename(path), "missing " + ",".join(missing))); continue
    rows.append(meta)
if not rows and not bad:
    print("no handoffs" + (" for run %s" % run if run else "")); sys.exit(0)
for m in rows:
    print("%-12s %-6s %-6s %-9s %-9s %s" % (
        m["run"], m["task"], m["dispatch"], m["outcome"],
        m.get("evidence", "-"), m.get("cause", "") or ""))
for name, why in bad:
    print("MALFORMED %s (%s)" % (name, why))
# An unreadable handoff is a failed Dispatch, not a missing one.
sys.exit(1 if bad else 0)
PY
}

# --- settle ----------------------------------------------------------------
# Reuse, retain or release. There is no fourth option, and no Dispatch is left
# unsettled.

cmd_settle() {
  local name="${1:-}" decision="${2:-}"
  [ -n "$name" ] && [ -n "$decision" ] || usage
  valid_name "$name" || die "settle: bad agent name: ${name}"
  local pane
  pane="$(agent_field "$name" pane_id)"
  [ -n "$pane" ] || die "settle: no live agent named ${name}"
  case "$decision" in
    reuse | retain | release) ;;
    *) die "settle: decision must be reuse, retain or release" ;;
  esac

  # One source id for the whole team, one token: a pane allows 32 distinct
  # metadata sources for its lifetime and never releases a slot.
  herdr pane report-metadata "$pane" --source herdr-team \
    --token "settle=${decision}" >/dev/null ||
    warn "settle: could not label ${pane} (the decision still stands)"

  case "$decision" in
    reuse) ok "${name} settled: reuse (${pane})" ;;
    retain) ok "${name} settled: retain for inspection (${pane})" ;;
    release)
      # Release means the pane goes back to the pool, so it runs the same
      # guards as teardown rather than a second, weaker path.
      ok "${name} settled: release (${pane})"
      cmd_teardown "$name"
      ;;
  esac
}

# --- teardown --------------------------------------------------------------

cmd_teardown() {
  local name="${1:-}" force=0
  shift || true
  [ "${1:-}" = "--force" ] && force=1
  [ -n "$name" ] || usage
  valid_name "$name" || die "teardown: bad agent name: ${name}"

  local cwd ws
  cwd="$(agent_field "$name" cwd)"
  ws="$(agent_field "$name" workspace_id)"
  [ -n "$ws" ] || die "teardown: no live agent named ${name}"

  if [ "$force" -eq 0 ] && [ -n "$cwd" ] && [ -d "$cwd" ]; then
    [ -z "$(git -C "$cwd" status --porcelain)" ] ||
      die "teardown: ${cwd} has uncommitted changes — commit them or pass --force"
    if git -C "$cwd" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
      [ -z "$(git -C "$cwd" log --oneline '@{u}..HEAD')" ] ||
        die "teardown: ${cwd} has unpushed commits — push them or pass --force"
    else
      die "teardown: ${cwd} has no upstream — push the branch or pass --force"
    fi
  fi

  herdr workspace close "$ws" >/dev/null
  if [ -n "$cwd" ] && [ "$cwd" != "${DOTFILES}" ]; then
    if [ "$force" -eq 1 ]; then
      git -C "${DOTFILES}" worktree remove --force "$cwd" 2>/dev/null ||
        warn "worktree remove failed for ${cwd} — remove it by hand"
    else
      git -C "${DOTFILES}" worktree remove "$cwd" 2>/dev/null ||
        warn "worktree remove failed for ${cwd} — remove it by hand"
    fi
  fi
  git -C "${DOTFILES}" tidy >/dev/null 2>&1 || true
  ok "${name} torn down"
}

# --- dispatch --------------------------------------------------------------

case "${1:-}" in
  spawn) shift; cmd_spawn "$@" ;;
  status) shift; cmd_status "$@" ;;
  collect) shift; cmd_collect "$@" ;;
  settle) shift; cmd_settle "$@" ;;
  teardown) shift; cmd_teardown "$@" ;;
  -h | --help | help) usage 0 ;;
  *) usage ;;
esac
