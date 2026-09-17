import assert from "node:assert/strict";
import { mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import protectedPaths from "../extensions/protected-paths.ts";

type Handler = (event: unknown, ctx: unknown) => Promise<{ block?: boolean } | undefined>;
let handler: Handler | undefined;
protectedPaths({ on: (_: string, h: Handler) => (handler = h) } as never);

// Headless, so anything that would ask is blocked.
async function blocked(toolName: string, input: Record<string, string>, cwd: string): Promise<boolean> {
  const r = await handler!({ toolName, input }, { cwd, hasUI: false });
  return !!r?.block;
}

const H = homedir();
const repo = `${H}/.dotfiles`;
const noEnv = mkdtempSync(join(tmpdir(), "pp-noenv-"));
const withEnv = mkdtempSync(join(tmpdir(), "pp-env-"));
writeFileSync(join(withEnv, ".env"), "KEY=x\n");
// Only the curly-quote variant exists, and it links to a secret.
symlinkSync(join(withEnv, ".env"), join(withEnv, "a\u2019b"));
after(() => {
  for (const dir of [noEnv, withEnv]) rmSync(dir, { recursive: true, force: true });
});

// [cwd, path, blocked]: the 14 write cases from the original scratchpad harness.
const legacy: [string, string, boolean][] = [
  [`${H}/.dotfiles/ai`, "env.local.zsh", true],
  [`${H}/.claude`, ".credentials.json", true],
  [`${H}/.pi/agent`, "auth.json", true],
  [`${H}/.pi/agent`, "trust.json", true],
  [`${H}/.dotfiles`, "ai/pi/extensions/permission-gate.ts", true],
  [`${H}/.dotfiles`, "~/.ssh/config", true],
  ["/tmp/p", ".ENV", true],
  ["/tmp/p", ".env.local", true],
  ["/tmp/p", "sub/.git/config", true],
  ["/tmp/p", ".env.example", false],
  ["/tmp/p", ".envrc", false],
  ["/tmp/p", "src/vite.env.d.ts", false],
  [`${H}/.dotfiles`, "ai/pi/settings.json", true],
  [`${H}/.dotfiles`, "ai/env.local.zsh.example", false],
];

test("legacy table is complete", () => {
  assert.equal(legacy.length, 14);
});

for (const [cwd, path, want] of legacy) {
  test(`write ${path} in ${cwd} → ${want ? "block" : "allow"}`, async () => {
    assert.equal(await blocked("write", { path }, cwd), want);
  });
}

// [tool, path or command, cwd, blocked]
const rows: [string, string, string, boolean][] = [
  // block
  ["bash", "cat ~/.pi/agent/auth.json", repo, true],
  ["bash", "grep KEY ai/env.local.zsh", repo, true],
  ["bash", "cat ~/.SSH/id_ed25519", repo, true],
  ["bash", "ls ~/.ssh", repo, true],
  ["bash", "tar czf x.tgz $HOME/.aws", repo, true],
  ["bash", 'cat "$HOME/.aws/credentials"', repo, true],
  ["bash", "cat ${HOME}/.aws/credentials", repo, true],
  ["bash", "cat <~/.ssh/id_ed25519", repo, true],
  ["bash", "cat < ~/.ssh/id_ed25519", repo, true],
  ["bash", "tool --key-file=~/.ssh/id_ed25519", repo, true],
  ["bash", "echo x 2>~/.ssh/x", repo, true],
  ["bash", "echo x &>~/.aws/x", repo, true],
  ["bash", "echo key >>~/.ssh/authorized_keys", repo, true],
  ["bash", "cat .env", withEnv, true],
  ["bash", "cat < .env", withEnv, true],
  ["bash", "echo x 2>.env", withEnv, true],
  ["bash", "echo x &>.env", withEnv, true],
  ["bash", "cat <<EOF > ~/.ssh/authorized_keys\nkey\nEOF", repo, true],
  ["bash", "cat <<'EOF' | tee ~/.aws/credentials\nx\nEOF", repo, true],
  ["bash", "cat <<EOF\nhello\nEOF\ncat ~/.ssh/id_ed25519", repo, true],
  ["bash", "cat <<-EOF\n\thello\n\tEOF\ncat ~/.ssh/id_ed25519", repo, true],
  // A here-string is not a heredoc: nothing after it is skipped.
  ["bash", "cat <<< x; cat ~/.ssh/id_ed25519", repo, true],
  ["bash", "cat <<< x\ncat ~/.ssh/id_ed25519", repo, true],
  ["bash", `echo ${Array.from({ length: 70 }, (_, i) => `f${i}`).join(" ")} ~/.ssh/id_ed25519`, repo, true],
  ["read", "a'b", withEnv, true],
  ["read", "~/.ssh/config", repo, true],
  ["read", "@~/.ssh/config", repo, true],
  ["read", "~/.ssh", repo, true],
  ["read", "file://" + H + "/.ssh/config", repo, true],
  ["grep", "~/.aws", repo, true],
  ["find", "~/.gnupg", repo, true],
  ["ls", "~/.ssh", repo, true],
  ["write", "@~/.ssh/config", repo, true],
  ["write", ".git/config", repo, true],
  ["write", "ai/pi/extensions/todo.ts", repo, true],
  ["edit", "~/.pi/agent/models.json", repo, true],
  ["edit", "node_modules/x/index.js", repo, true],
  // allow
  ["read", "node_modules/x/index.d.ts", repo, false],
  ["bash", "cat .git/HEAD", repo, false],
  ["read", "ai/pi/extensions/todo.ts", repo, false],
  ["read", "ai/pi/models.json", repo, false],
  ["read", ".git/config", repo, false],
  ["bash", "ls node_modules", repo, false],
  ["bash", "cat README.md", repo, false],
  ["read", "ai/env.local.zsh.example", repo, false],
  ["read", "~", repo, false],
  ["ls", "~", repo, false],
  ["bash", "git diff ai/env.local.zsh.example", repo, false],
  ["bash", "git diff ~/.dotfiles/README.md", repo, false],
  ["bash", "ls ~", repo, false],
  ["bash", "grep -rn .env src/", noEnv, false],
  // The quoted sed script is path-like, but resolves to <cwd>/s/x/.env/: a
  // directory, not an env file.
  ["bash", "sed 's/x/.env/' file", withEnv, false],
  // Heredoc bodies are skipped.
  ["bash", "cat <<EOF\n~/.ssh/id_ed25519\nEOF", repo, false],
  ["bash", "cat <<-'EOF'\n\t~/.ssh/id_ed25519\n\tEOF\ncat ~/.ssh/id_ed25519", repo, true],
  // When unsure, the tokenizer checks the rest of the text.
  ["bash", "cat <<EOF\ncat ~/.ssh/id_ed25519", repo, true],
  ["bash", "cat <<E\"OF\"\nhi\nEOF\ncat ~/.ssh/id_ed25519", repo, true],
  ["bash", "echo 'x\ncat ~/.ssh/id_ed25519", repo, true],
  // Comments, $'' quotes and arithmetic do not hide what follows.
  ["bash", "ls # don't\ncat ~/.ssh/id_ed25519", repo, true],
  ["bash", "cat <<EOF # it's\nx\nEOF\ncat ~/.ssh/id_ed25519", repo, true],
  ["bash", "echo $'\\'' ; cat ~/.ssh/id_ed25519 #'", repo, true],
  ["bash", "echo $((x<<y))\ncat ~/.ssh/id_ed25519", repo, true],
  ["bash", "echo a#b ~/.ssh/id_ed25519", repo, true],
  ["bash", "ls # <<EOF\ncat ~/.ssh/id_ed25519\nEOF", repo, true],
  ["bash", "echo $((x<<y))\ncat ~/.ssh/id_ed25519\ny", repo, true],
  ["bash", "cat <<E\"OF\"\ncat ~/.ssh/id_ed25519\nE", repo, true],
  ["bash", "ls # see ~/.ssh/id_ed25519", repo, false],
  // A shift or a quoted << is not a heredoc.
  ["bash", "echo $((1<<2))\ncat ~/.ssh/id_ed25519", repo, true],
  ["bash", 'echo "<<EOF"\ncat ~/.aws/credentials', repo, true],
  // Messages and URLs are not paths.
  ["bash", "git commit -m '~/.ssh/config: tweak'", repo, false],
  ["bash", "curl -O https://example.com/app/.env", repo, false],
  ["bash", "cat file:///Users/x/.ssh/id_ed25519".replace("/Users/x", H), repo, true],
  // Writes to write-only paths: redirects, tee, sed -i / perl -i, and the
  // destination of mv, cp, install and ln.
  ["bash", "cat > ai/pi/extensions/x.ts", repo, true],
  ["bash", "echo x >>ai/pi/extensions/x.ts", repo, true],
  ["bash", "echo x 2> .git/x", repo, true],
  ["bash", "echo x &>node_modules/x", repo, true],
  ["bash", "echo x >& ai/pi/extensions/x.ts", repo, true],
  ["bash", "echo x | tee -a ai/pi/extensions/x.ts", repo, true],
  ["bash", "echo x | sudo tee .git/config >/dev/null", repo, true],
  ["bash", "sed -i '' 's/a/b/' ai/pi/extensions/todo.ts", repo, true],
  ["bash", "sed -i -e 's/a/b/' .git/config", repo, true],
  ["bash", "perl -pi -e 's/a/b/' .git/config", repo, true],
  ["bash", "mv x ai/pi/extensions/x.ts", repo, true],
  ["bash", "cp x .git/config", repo, true],
  ["bash", "cp -t .git/ x y", repo, true],
  ["bash", "cp --target-directory=.git/hooks evil", repo, true],
  ["bash", "mv .git/config /tmp/x", repo, true],
  ["bash", "echo x >| .git/hooks/pre-commit", repo, true],
  ["bash", "env -i tee .git/hooks/pre-commit", repo, true],
  ["bash", "sudo -u root tee .git/hooks/pre-commit", repo, true],
  ["bash", "sudo -n tee .git/hooks/pre-commit", repo, true],
  ["bash", "sudo --user root tee .git/x", repo, true],
  ["bash", "nice -n 5 tee .git/hooks/x", repo, true],
  ["bash", "timeout -s KILL 5 cp x .git/hooks/y", repo, true],
  ["bash", "stdbuf -o L tee .git/x", repo, true],
  ["bash", "docker run -v ~/.aws:/root/.aws img", repo, true],
  ["bash", "docker run --mount type=bind,source=~/.aws,target=/x img", repo, true],
  ["bash", "ls | xargs -I{} cp {} .git/hooks/", repo, true],
  ["bash", "xargs -n 1 cp x .git/hooks/", repo, true],
  ["bash", "sed --expression=s/a/b/ -i .git/config", repo, true],
  ["bash", "sed --in-place -e s/a/b/ .git/config", repo, true],
  ["bash", "install -m 644 x node_modules/x", repo, true],
  ["bash", "ln -s x ai/pi/extensions/y.ts", repo, true],
  ["bash", "echo x > .env", noEnv, true],
  // Reads and other commands may name write-only paths.
  ["bash", "cat .git/HEAD", repo, false],
  ["bash", "ls node_modules", repo, false],
  ["bash", "git add .", repo, false],
  ["bash", "npm install", repo, false],
  ["bash", "cp ai/pi/extensions/todo.ts /tmp/x.ts", repo, false],
  ["bash", "sed -i '' 's/a/b/' ai/pi/settings.json", repo, true],
  ["bash", "echo {} > ~/.pi/agent/models.json", repo, true],
  ["bash", "cat ai/pi/models.json", repo, false],
  ["edit", "ai/pi/web-search.json", repo, true],
  ["bash", "echo {} > ~/.pi/agent/web-search.json", repo, true],
  ["bash", "cat ai/pi/web-search.json", repo, false],
  ["bash", "sed 's/.git/x/' .git/config", repo, false],
  ["bash", "sed -n 1p .git/config > /tmp/x", repo, false],
  ["bash", "sed -i '' 's/a/b/' README.md", repo, false],
  ["bash", "cp -r node_modules/x dist/", repo, false],
  ["bash", "npm ci 2>&1 | tail", repo, false],
  ["bash", "sudo -n cat .git/config", repo, false],
  ["bash", "echo x >&2 2>&-", `${repo}/.git`, false],
  ["bash", "sed -i 's,/.git/,x,' README.md", repo, false],
  // Pinned gaps (guardrail, not a sandbox):
  // command substitution that builds the path is not modeled...
  ["bash", "cat $(printf '%s/.ssh/id_ed25519' ~)", repo, false],
  ["bash", "cat `echo x`", repo, false],
  // ...but a literal path inside $(...) is still a token, so this one is caught.
  ["bash", "cat $(echo ~/.ssh/id_ed25519)", repo, true],
  // ...including inside double quotes, backticks and unquoted heredoc bodies.
  ["bash", 'echo "$(cat ~/.ssh/id_ed25519)"', repo, true],
  ["bash", 'k="$(cat "$HOME/.ssh/id_ed25519")"', repo, true],
  ["bash", 'echo "`cat ~/.ssh/id_ed25519`"', repo, true],
  ["bash", "cat <<EOF\n$(cat ~/.ssh/id_ed25519)\nEOF", repo, true],
  ["bash", "cat <<'EOF'\n$(cat ~/.ssh/id_ed25519)\nEOF", repo, false],
  ["bash", "git commit -m \"$(cat <<'EOF'\nfix: don't read x\nEOF\n)\"", repo, false],
  // Only the cd target is caught; the relative id_ed25519 alone would pass.
  ["bash", "cd ~/.ssh && cat id_ed25519", repo, true],
  ["bash", "cat id_ed25519", repo, false],
  // The quoted interpreter source is one token that resolves under cwd.
  ["bash", `python3 -c "open('${H}/.ssh/id')"`, repo, false],
  // Directory searches are not expanded.
  ["bash", "rg KEY ai/", repo, false],
  // Quoted paths with spaces are skipped, and a message naming a secret path
  // without spaces is blocked.
  ["bash", "cat ~/.ssh/'my key'", repo, false],
  ["bash", "git commit -m '~/.ssh/config'", repo, true],
  // Writes not modeled as redirects, tee, sed -i or mv/cp destinations.
  ["bash", "dd of=ai/pi/extensions/x.ts", repo, false],
  ["write", ".env", noEnv, true],
];

for (const [tool, arg, cwd, want] of rows) {
  test(`${tool} ${JSON.stringify(arg)} → ${want ? "block" : "allow"}`, async () => {
    const input: Record<string, string> = tool === "bash" ? { command: arg } : { path: arg };
    assert.equal(await blocked(tool, input, cwd), want);
  });
}

test("many heredocs are scanned in linear time", async () => {
  const start = performance.now();
  assert.equal(await blocked("bash", { command: "cat <<A\n".repeat(12000) }, repo), false);
  assert.ok(performance.now() - start < 1000);
});
