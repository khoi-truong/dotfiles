import { realpathSync } from "node:fs";
import { join } from "node:path";
import { type ExtensionAPI, getAgentDir } from "@earendil-works/pi-coding-agent";

// pi-subagents runs children in-process without the ambient extensions, so
// this registers our guards as extensions every child must load, and limits
// the subagent tool to plain agent runs: no host commands (gate, acceptance
// verify, workflows), no external CLIs or remote machines, no agent or
// schedule changes, and no project agent config, which a cloned repo controls.

type Verdict = { block: true; reason: string } | undefined;
type Snapshot = ReadonlyArray<Readonly<{ id: string; path: string }>>;
type Registry = { version: 1; bySession: Map<string, Snapshot> };

// pi-subagents 0.68.0 src/shared/required-child-extensions.ts reads this key.
const registryKey = Symbol.for("pi-subagents.required-child-extensions.v1");

export const childExtensions = ["permission-gate", "protected-paths", "subagent-guard"];

const allowedKeys = new Set([
  "agent", "task", "action", "capabilities", "id", "runId", "index", "childId",
  "view", "lines", "topic", "message", "mode", "steeringRecovery", "async",
  "timeoutMs", "maxRuntimeMs", "checkpointBeforeDeadlineMs", "toolTimeoutMs",
  "toolBudget", "usageBudget", "agentScope", "cwd", "artifacts",
  "includeProgress", "context", "control", "output", "outputMode", "skill",
  "model", "outputSchema", "chatProgress", "isolation", "worktree", "baseRef",
  "acceptance",
]);

// Read-only or run-control actions; everything else changes agents,
// schedules, worktrees or panes.
const allowedActions = new Set([
  "list", "get", "models", "status", "guide", "doctor", "children.list",
  "lane.status", "refine.show", "resume", "steer", "stop", "interrupt", "dismiss",
]);

// Accepted without a verify command; the object form can run one.
const allowedAcceptance = new Set(["auto", "attested", "checked"]);

export const externalAgents = [
  "claude-code", "claude-code-writer", "codex-exec", "codex-exec-writer",
  "cursor-agent", "cursor-agent-writer",
];

function registry(): Registry {
  const root = globalThis as Record<PropertyKey, unknown>;
  const existing = root[registryKey] as Registry | undefined;
  if (existing?.version === 1 && existing.bySession instanceof Map) return existing;
  if (existing !== undefined) throw new Error("unsupported pi-subagents child extension registry");
  const created: Registry = { version: 1, bySession: new Map() };
  root[registryKey] = created;
  return created;
}

export function childExtensionPaths(dir: string): string[] {
  return childExtensions.map((name) => realpathSync(join(dir, `${name}.ts`)));
}

// Returns a dispose function. Throws if the session already has extensions.
export function registerChildExtensions(sessionId: string, dir: string): () => void {
  const store = registry();
  if (store.bySession.has(sessionId)) throw new Error(`child extensions already registered for ${sessionId}`);
  const paths = childExtensionPaths(dir);
  const snapshot: Snapshot = Object.freeze(
    childExtensions.map((id, i) => Object.freeze({ id, path: paths[i] })),
  );
  store.bySession.set(sessionId, snapshot);
  return () => {
    if (store.bySession.get(sessionId) === snapshot) store.bySession.delete(sessionId);
  };
}

export function childExtensionsRegistered(sessionId: string, dir: string): boolean {
  const snapshot = registry().bySession.get(sessionId);
  if (!snapshot) return false;
  const registered = new Set(snapshot.map((e) => e.path));
  return childExtensionPaths(dir).every((p) => registered.has(p));
}

export function checkSubagentCall(tool: string, input: unknown, registered: boolean): Verdict {
  if (tool !== "subagent") return undefined;
  if (!registered) {
    return { block: true, reason: "subagent is blocked: the permission gate is not registered for child runs" };
  }
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    return { block: true, reason: "subagent input must be an object" };
  }
  const params = input as Record<string, unknown>;
  const unknown = Object.keys(params).filter((k) => !allowedKeys.has(k));
  if (unknown.length) {
    return {
      block: true,
      reason: `subagent fields not allowed here: ${unknown.join(", ")}. Run one agent per call with agent and task; use async: true and several calls for parallel work`,
    };
  }
  const { action, agent, agentScope, output, acceptance } = params;
  if (action !== undefined && !(typeof action === "string" && allowedActions.has(action))) {
    return { block: true, reason: `subagent action ${String(action)} is disabled; edit agents in ai/pi/agents instead` };
  }
  if (typeof agent === "string" && externalAgents.includes(agent.trim().toLowerCase())) {
    return { block: true, reason: `${agent} runs an external CLI outside the permission gate` };
  }
  if (agentScope !== undefined && agentScope !== "user") {
    return { block: true, reason: "only user agents are allowed; project agent config is not trusted" };
  }
  if (output !== undefined && typeof output !== "boolean") {
    return { block: true, reason: "subagent output paths are disabled; the child's result is returned to you" };
  }
  if (acceptance !== undefined && acceptance !== false && !allowedAcceptance.has(acceptance as string)) {
    return { block: true, reason: "acceptance may only be auto, attested, checked or false" };
  }
  params.agentScope = "user";
  return undefined;
}

export default function (pi: ExtensionAPI) {
  const dir = join(getAgentDir(), "extensions");
  let dispose: (() => void) | undefined;

  pi.on("session_start", async (_event, ctx) => {
    dispose?.();
    dispose = undefined;
    try {
      dispose = registerChildExtensions(ctx.sessionManager.getSessionId(), dir);
    } catch (e) {
      ctx.ui.notify(`subagent-guard: ${e instanceof Error ? e.message : String(e)}`, "error");
    }
  });

  pi.on("session_shutdown", async () => {
    dispose?.();
    dispose = undefined;
  });

  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName !== "subagent") return undefined;
    let registered = false;
    try {
      registered = childExtensionsRegistered(ctx.sessionManager.getSessionId(), dir);
    } catch {
      // A missing extension file means children would run unguarded.
    }
    return checkSubagentCall(event.toolName, event.input, registered);
  });
}
