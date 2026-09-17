import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import subagentGuard, {
  checkSubagentCall,
  childExtensions,
  childExtensionsRegistered,
  externalAgents,
  registerChildExtensions,
} from "../extensions/subagent-guard.ts";

const dir = mkdtempSync(join(tmpdir(), "subagent-guard-"));
after(() => rmSync(dir, { recursive: true, force: true }));
for (const name of childExtensions) writeFileSync(join(dir, `${name}.ts`), "");

const cases: [unknown, boolean][] = [
  [{ agent: "scout", task: "find the parser" }, false],
  [{ agent: "worker", task: "fix it", async: true, model: "deepseek/deepseek-flash" }, false],
  [{ agent: "reviewer", task: "review", output: false, acceptance: "checked" }, false],
  [{ agent: "scout", task: "x", agentScope: "user" }, false],
  [{ action: "list" }, false],
  [{ action: "status", id: "abc" }, false],
  [{ action: "steer", id: "abc", message: "stop editing tests" }, false],
  [{ action: "create", config: { name: "x" } }, true],
  [{ action: "delete", agent: "planner" }, true],
  [{ action: "schedule.create", agent: "scout", task: "x", every: "1h" }, true],
  [{ action: "worktree.cleanup" }, true],
  [{ action: 1 }, true],
  [{ agent: "claude-code-writer", task: "x" }, true],
  [{ agent: " Codex-Exec ", task: "x" }, true],
  [{ agent: "scout", task: "x", machine: "box" }, true],
  [{ agent: "scout", task: "x", gate: "npm test" }, true],
  [{ agent: "scout", task: "x", acceptance: { level: "verified", verify: [{ id: "t", command: "rm -rf ~" }] } }, true],
  [{ agent: "scout", task: "x", acceptance: "verified" }, true],
  [{ agent: "scout", task: "x", output: "/Users/me/.pi/agent/settings.json" }, true],
  [{ agent: "scout", task: "x", agentScope: "both" }, true],
  [{ agent: "scout", task: "x", share: true }, true],
  [{ agent: "scout", task: "x", sessionDir: "/tmp" }, true],
  [{ agent: "scout", task: "x", runner: { type: "external-cli", command: "sh" } }, true],
  [{ workflowScript: "return await runs.run('a', { agent: 'scout', task: 'x' })" }, true],
  [{ workflow: "ci", args: { command: "make" } }, true],
  [{ chain: [{ agent: "scout", task: "x" }] }, true],
  [[], true],
  [null, true],
];

for (const [input, blocked] of cases) {
  test(`${blocked ? "blocks" : "allows"} subagent ${JSON.stringify(input)}`, () => {
    assert.equal(checkSubagentCall("subagent", input, true)?.block ?? false, blocked);
  });
}

test("forces user agent scope on allowed calls", () => {
  const input: Record<string, unknown> = { agent: "scout", task: "x" };
  assert.equal(checkSubagentCall("subagent", input, true), undefined);
  assert.equal(input.agentScope, "user");
});

test("blocks subagent when child extensions are not registered", () => {
  assert.equal(checkSubagentCall("subagent", { agent: "scout", task: "x" }, false)?.block, true);
});

test("ignores other tools", () => {
  assert.equal(checkSubagentCall("bash", { gate: "x" }, false), undefined);
});

test("registers child extensions per session until disposed", () => {
  assert.equal(childExtensionsRegistered("s1", dir), false);
  const dispose = registerChildExtensions("s1", dir);
  assert.equal(childExtensionsRegistered("s1", dir), true);
  assert.equal(childExtensionsRegistered("s2", dir), false);
  assert.throws(() => registerChildExtensions("s1", dir));
  const registry = (globalThis as Record<PropertyKey, unknown>)[
    Symbol.for("pi-subagents.required-child-extensions.v1")
  ] as { version: number; bySession: Map<string, { id: string; path: string }[]> };
  assert.equal(registry.version, 1);
  assert.deepEqual(registry.bySession.get("s1")?.map((e) => e.id), childExtensions);
  assert.ok(Object.isFrozen(registry.bySession.get("s1")));
  dispose();
  assert.equal(childExtensionsRegistered("s1", dir), false);
});

test("fails closed when an extension file is missing", () => {
  assert.throws(() => registerChildExtensions("s3", join(dir, "missing")));
  assert.equal(childExtensionsRegistered("s3", dir), false);
});

test("real child extension files exist", () => {
  const extensions = join(import.meta.dirname, "../extensions");
  const dispose = registerChildExtensions("s4", extensions);
  assert.equal(childExtensionsRegistered("s4", extensions), true);
  dispose();
});

test("extension registers for the session and blocks until then", async () => {
  const handlers = new Map<string, (event: unknown, ctx: unknown) => Promise<unknown>>();
  subagentGuard({ on: (name: string, h: never) => handlers.set(name, h) } as never);
  const ctx = { sessionManager: { getSessionId: () => "s5" }, ui: { notify: () => {} } };
  const call = { toolName: "subagent", input: { agent: "scout", task: "x" } };
  assert.equal(((await handlers.get("tool_call")!(call, ctx)) as { block?: boolean })?.block, true);
  await handlers.get("session_start")!({}, ctx);
  // getAgentDir() points at ~/.pi/agent, which may not be set up here.
  const registered = ((globalThis as Record<PropertyKey, unknown>)[
    Symbol.for("pi-subagents.required-child-extensions.v1")
  ] as { bySession: Map<string, unknown> }).bySession.has("s5");
  const result = (await handlers.get("tool_call")!(call, ctx)) as { block?: boolean } | undefined;
  assert.equal(result?.block ?? false, !registered);
  await handlers.get("session_shutdown")!({}, ctx);
  assert.equal(childExtensionsRegistered("s5", dir), false);
});

// A pi-subagents bump must re-check the registry key and the allowed fields.
test("settings pin pi-subagents and disable external CLI agents", () => {
  const settings = JSON.parse(readFileSync(join(import.meta.dirname, "../settings.json"), "utf8"));
  const pkg = settings.packages.find((p: { source?: string }) => p.source?.startsWith("npm:pi-subagents@"));
  assert.equal(pkg?.source, "npm:pi-subagents@0.68.0");
  for (const name of externalAgents) {
    assert.equal(settings.subagents.agentOverrides[name]?.disabled, true, name);
  }
});
