import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";
import { test } from "node:test";

// Replaces the manual diff -w before a pi bump: re-copy the examples, then
// update every pin below together.
const root = join(import.meta.dirname, "..");
const pi = join(root, "node_modules/@earendil-works/pi-coding-agent");
const extensions = join(root, "extensions");
const read = (p: string) => readFileSync(p, "utf8");

// Vendored files that differ from pi's examples only by the header line.
const unmodified = [
  "handoff.ts",
  "questionnaire.ts",
  "titlebar-spinner.ts",
  "plan-mode/index.ts",
  "plan-mode/utils.ts",
  "subagent/agents.ts",
];

// Like diff -w: whitespace inside lines is ignored, lines are not.
const lines = (src: string) => src.replace(/\n$/, "").split("\n").map((l) => l.replace(/\s+/g, ""));

for (const file of unmodified) {
  test(`${file} matches the bundled example`, () => {
    const vendored = lines(read(join(extensions, file))).slice(1);
    assert.deepEqual(vendored, lines(read(join(pi, "examples/extensions", file))));
  });
}

const version = read(join(pi, "package.json")).match(/"version":\s*"([^"]+)"/)?.[1];

test("package.json pins the installed pi version", () => {
  const pkg = JSON.parse(read(join(root, "package.json")));
  assert.ok(version);
  assert.equal(pkg.devDependencies["@earendil-works/pi-coding-agent"], version);
});

test("mise pins the installed pi version", () => {
  const mise = read(join(root, "../../mise/global.toml"));
  assert.equal(mise.match(/^"npm:@earendil-works\/pi-coding-agent"\s*=\s*"([^"]+)"/m)?.[1], version);
});

// Written for this repo, not copied from pi's examples.
const own = ["footer.ts"];
const vendored = readdirSync(extensions, { recursive: true, encoding: "utf8" }).filter(
  (f) => f.endsWith(".ts") && !own.includes(f),
);

test("every extension is vendored", () => {
  assert.deepEqual(vendored.sort(), [
    "handoff.ts",
    "notify.ts",
    "permission-gate.ts",
    "plan-mode/index.ts",
    "plan-mode/utils.ts",
    "protected-paths.ts",
    "questionnaire.ts",
    "subagent/agents.ts",
    "subagent/index.ts",
    "titlebar-spinner.ts",
    "todo.ts",
  ]);
});

for (const file of vendored) {
  test(`${relative(root, join(extensions, file))} names the installed pi version`, () => {
    const header = read(join(extensions, file)).split("\n", 1)[0];
    assert.equal(header, `// Vendored from pi-coding-agent ${version} examples/extensions/${file}`);
  });
}
