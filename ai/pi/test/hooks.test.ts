import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import permissionGate from "../extensions/permission-gate.ts";
import protectedPaths from "../extensions/protected-paths.ts";

type Result = { block?: boolean; reason?: string } | undefined;
type Handler = (event: unknown, ctx: unknown) => Promise<Result>;

// Collects the tool_call handler an extension registers through pi.on.
function load(extension: (pi: never) => void): Handler {
  let handler: Handler | undefined;
  extension({ on: (name: string, h: Handler) => name === "tool_call" && (handler = h) } as never);
  assert.ok(handler, "extension registers a tool_call handler");
  return handler;
}

const gate = load(permissionGate);
const paths = load(protectedPaths);

// A fake ctx that records prompts and answers select() with `answer`.
function ctx(cwd: string, hasUI: boolean, answer = "No") {
  const prompts: string[] = [];
  const notes: string[] = [];
  return {
    prompts,
    notes,
    cwd,
    hasUI,
    ui: {
      select: async (title: string) => (prompts.push(title), answer),
      notify: (message: string) => void notes.push(message),
    },
  };
}

const H = homedir();
const repo = `${H}/.dotfiles`;
const withEnv = mkdtempSync(join(tmpdir(), "hooks-env-"));
writeFileSync(join(withEnv, ".env"), "KEY=x\n");
after(() => rmSync(withEnv, { recursive: true, force: true }));
const bash = (command: string) => ({ toolName: "bash", input: { command } });

test("gate asks with a UI and blocks without one", async () => {
  const yes = ctx(repo, true, "Yes");
  assert.equal(await gate(bash("sudo true"), yes), undefined);
  assert.equal(yes.prompts.length, 1);

  const no = ctx(repo, true, "No");
  assert.deepEqual(await gate(bash("find . -delete"), no), { block: true, reason: "Blocked by user" });

  const headless = await gate(bash("git push --force"), ctx(repo, false));
  assert.equal(headless?.block, true);
  assert.match(headless?.reason ?? "", /no UI/);
});

test("gate ignores other tools and safe commands", async () => {
  const c = ctx(repo, true);
  assert.equal(await gate({ toolName: "write", input: { path: "sudo" } }, c), undefined);
  assert.equal(await gate(bash("git rm -r --cached x"), c), undefined);
  assert.equal(c.prompts.length, 0);
});

test("powershell commands are gated like bash", async () => {
  const c = ctx(repo, false);
  const ps = (command: string) => ({ toolName: "powershell", input: { command } });
  assert.match((await gate(ps("sudo true"), c))?.reason ?? "", /no UI/);
  assert.match((await paths(ps("cat ~/.ssh/id_ed25519"), c))?.reason ?? "", /protected path/);
  assert.equal(await paths(ps("cat README.md"), c), undefined);
});

// Bare env-file names ask rather than block; path-like secrets always block.
for (const command of ["echo .env >> .gitignore", "git rm --cached .env", "grep -rn .env src/", "cat .env"]) {
  test(`bare env name asks with a UI: ${command}`, async () => {
    const yes = ctx(withEnv, true, "Yes");
    assert.equal(await paths(bash(command), yes), undefined);
    assert.equal(yes.prompts.length, 1);
    assert.match(yes.prompts[0], /"\.env"/);

    const no = ctx(withEnv, true, "No");
    assert.deepEqual(await paths(bash(command), no), { block: true, reason: "Blocked by user" });

    const headless = await paths(bash(command), ctx(withEnv, false));
    assert.equal(headless?.block, true);
    assert.match(headless?.reason ?? "", /"\.env"/);
  });
}

test("path-like secrets block without asking and name the path", async () => {
  const c = ctx(repo, true, "Yes");
  const r = await paths(bash("cat ~/.ssh/id_ed25519"), c);
  assert.equal(r?.block, true);
  assert.match(r?.reason ?? "", /"~\/\.ssh\/id_ed25519"/);
  assert.ok(r?.reason?.includes(`${H.toLowerCase()}/.ssh/id_ed25519`));
  assert.equal(c.prompts.length, 0);
  assert.equal(c.notes.length, 1);
});

test("too many paths to realpath asks with a UI and blocks without one", async () => {
  const command = "ls " + Array.from({ length: 257 }, (_, i) => `d/f${i}`).join(" ");
  const c = ctx(repo, true, "No");
  assert.deepEqual(await paths(bash(command), c), { block: true, reason: "Blocked by user" });
  assert.match(c.prompts[0], /too many paths/);

  const headless = await paths(bash(command), ctx(repo, false));
  assert.equal(headless?.block, true);
  assert.match(headless?.reason ?? "", /too many paths/);

  // 256 is still within budget.
  const within = "ls " + Array.from({ length: 256 }, (_, i) => `d/f${i}`).join(" ");
  assert.equal(await paths(bash(within), ctx(repo, false)), undefined);
});

// [tool, path, cwd, blocked]
const routing: [string, string | undefined, string, boolean][] = [
  ["read", "~/.aws/credentials", repo, true],
  ["grep", "~/.aws", repo, true],
  ["find", "~/.ssh", repo, true],
  ["ls", "~/.gnupg", repo, true],
  // A missing path means cwd.
  ["grep", undefined, `${H}/.ssh`, true],
  ["ls", undefined, repo, false],
  // Write-only paths stay readable.
  ["read", ".git/config", repo, false],
  ["grep", "node_modules", repo, false],
  ["find", "ai/pi/extensions", repo, false],
  ["ls", `${H}/.pi/agent/extensions`, repo, false],
  // Other tools are not checked.
  ["questionnaire", "~/.ssh/config", repo, false],
];

for (const [toolName, path, cwd, want] of routing) {
  test(`${toolName} ${path ?? "(no path)"} in ${cwd} → ${want ? "block" : "allow"}`, async () => {
    const c = ctx(cwd, true);
    const r = await paths({ toolName, input: path === undefined ? {} : { path } }, c);
    assert.equal(!!r?.block, want);
    if (want) {
      assert.ok(r?.reason?.includes(`"${path ?? "."}"`));
      assert.match(r?.reason ?? "", /matches \//);
      assert.equal(c.notes.length, 1);
    }
    assert.equal(c.prompts.length, 0);
  });
}

// Write/edit regression table: [cwd, path, blocked]. Every row matches the
// behavior before the split except those marked "changed".
const regression: [string, string, boolean][] = [
  [repo, "ai/env.local.zsh", true],
  [repo, "ai/env.local.zsh.example", false],
  [repo, "ai/pi/extensions/todo.ts", true],
  [repo, "ai/pi/extensions/plan-mode/index.ts", true],
  [repo, "ai/pi/settings.json", true],
  [repo, "ai/pi/models.json", true],
  [repo, "ai/pi/package.json", false],
  [repo, "ai/pi/test/hooks.test.ts", false],
  [repo, "README.md", false],
  [repo, "~/.ssh/config", true],
  [repo, "~/.SSH/Config", true],
  [repo, "~/.sshx", false],
  [repo, "~/.gnupg/gpg.conf", true],
  [repo, "~/.aws/credentials", true],
  [repo, "~/.netrc", true],
  [repo, "~/.npmrc", true],
  [repo, "~/.npmrc.bak", false],
  [repo, "~/.git-credentials", true],
  [repo, "~/.docker/config.json", true],
  [repo, "~/.docker/daemon.json", false],
  [repo, "~/.config/gh/hosts.yml", true],
  [repo, "~/.config/gh/config.yml", false],
  [repo, "~/.config/github-copilot/apps.json", true],
  [repo, "~/.claude.json", true],
  [repo, "~/.claude/.credentials.json", true],
  [repo, "~/.claude/settings.json", false],
  [repo, "~/.pi/agent/auth.json", true],
  [repo, "~/.pi/agent/trust.json", true],
  [repo, "~/.pi/agent/settings.json", true],
  [repo, "~/.pi/agent/models.json", true],
  [repo, "~/.pi/agent/models-store.json", false],
  [repo, "~/.pi/agent/extensions/x.ts", true],
  [repo, `${H}/.ssh/id_ed25519`, true],
  [repo, "/tmp/p/.env", true],
  [repo, "/tmp/p/.env.production", true],
  [repo, "/tmp/p/.env.sample", false],
  [repo, "/tmp/p/.env.template", false],
  [repo, "/tmp/p/.git/HEAD", true],
  [repo, "/tmp/p/.gitignore", false],
  [repo, "/tmp/p/node_modules/x/index.js", true],
  [repo, "/tmp/p/node_modules_old/x.js", false],
  [repo, "~", false],
  // changed: pi strips a leading @, so these reached the file unchecked.
  [repo, "@~/.ssh/config", true],
  [repo, "@.env", true],
  // changed: a protected directory itself now matches too.
  [repo, "ai/pi/extensions", true],
  [repo, "~/.ssh", true],
  // changed: file:// URLs resolve to the file.
  [repo, `file://${H}/.aws/credentials`, true],
];

for (const toolName of ["write", "edit"]) {
  for (const [cwd, path, want] of regression) {
    test(`${toolName} ${path} → ${want ? "block" : "allow"}`, async () => {
      const r = await paths({ toolName, input: { path } }, ctx(cwd, false));
      assert.equal(!!r?.block, want);
      if (want) assert.ok(r?.reason?.includes(`"${path}"`));
    });
  }
}
