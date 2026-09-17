// Vendored from pi-coding-agent 0.85.1 examples/extensions/protected-paths.ts
// Differs from upstream: secret vs write-only paths, pi's path normalization, and read/search/bash checks.
/**
 * Protected Paths Extension
 *
 * Blocks tool access to protected paths.
 * Useful for preventing accidental modifications to sensitive files.
 * Paths are resolved the way pi resolves them and matched case-insensitively
 * (macOS filesystems are case-insensitive).
 *
 * - Secret paths are blocked for write, edit, read, grep, find, ls and bash.
 * - Write-only paths (.git/, node_modules/, the extension directories) are
 *   blocked for write and edit only.
 * - bash (and powershell) is checked token by token: path-like tokens always,
 *   and bare env-file names (ask, not block) only when that file exists in
 *   cwd. Write-only paths apply only to redirect targets, tee, sed -i /
 *   perl -i files, mv sources and mv/cp/install/ln destinations.
 *
 * Threat model: a guardrail against model mistakes, not a boundary against an
 * adversary. Known gaps: $(...) and backticks, interpreter one-liners,
 * relative paths after cd, directory searches (rg KEY ai/), curl, quoted paths
 * with spaces (~/.ssh/'my key'), and other ways of writing files. A commit
 * message naming a secret path without spaces is blocked.
 */

import { existsSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { type ExtensionAPI, isToolCallEventType } from "@earendil-works/pi-coding-agent";

// A leading ~/ is anchored at home; a trailing / protects the whole directory
// (and the directory itself). Entries starting with / match anywhere.
export const secretPaths = [
  "~/.dotfiles/ai/env.local.zsh",
  "~/.pi/agent/auth.json",
  "~/.pi/agent/trust.json",
  "~/.claude/.credentials.json",
  "~/.claude.json",
  "~/.config/github-copilot/apps.json",
  "~/.config/gh/hosts.yml",
  "~/.ssh/",
  "~/.gnupg/",
  "~/.aws/",
  "~/.docker/config.json",
  "~/.netrc",
  "~/.npmrc",
  "~/.git-credentials",
];

export const writeOnlyPaths = ["/.git/", "/node_modules/", "~/.dotfiles/ai/pi/extensions/", "~/.pi/agent/extensions/"];

const home = homedir().toLowerCase();
// realpathSync calls allowed per bash command; tokens past it ask instead.
const maxRealpaths = 256;

function isProtectedEnv(name: string): boolean {
  if (name === ".env") return true;
  return name.startsWith(".env.") && !/\.(example|sample|template)$/.test(name);
}

function key(p: string): string {
  return p.normalize("NFC").toLowerCase();
}

// Mirrors pi's resolveToCwd (dist/core/tools/path-utils.js:42-44 and
// dist/utils/paths.js normalizePath), which the package does not export.
// Re-check it on every pi bump.
export function normalizeToolPath(p: string, cwd: string): string {
  let s = p.replace(/[\u00A0\u2000-\u200A\u202F\u205F\u3000]/g, " ");
  if (s.startsWith("@")) s = s.slice(1);
  if (s === "~") s = homedir();
  else if (s.startsWith("~/")) s = join(homedir(), s.slice(2));
  else if (s.startsWith("file://")) {
    try {
      s = fileURLToPath(s);
    } catch {
      // Not a local file URL: leave it as a relative path.
    }
  }
  return resolve(cwd, s);
}

// Both the literal path and its symlink target, so ~/.ssh/config (linked into
// the dotfiles repo) and a link pointing at a protected file are both caught.
// For read, also the variants pi's resolveReadPath may open instead
// (path-utils.js:45-60): AM/PM narrow no-break space, NFD and curly quote.
export function candidates(abs: string, read = false): string[] {
  const paths = [abs];
  if (read) {
    const nfd = abs.normalize("NFD");
    paths.push(abs.replace(/ (AM|PM)\./gi, "\u202F$1."), nfd, abs.replace(/'/g, "\u2019"), nfd.replace(/'/g, "\u2019"));
  }
  const keys = new Set<string>();
  for (const p of paths) {
    keys.add(key(p));
    try {
      keys.add(key(realpathSync(p)));
    } catch {
      // New file: nothing to resolve.
    }
  }
  return [...keys];
}

function matches(abs: string, list: string[]): boolean {
  const dir = abs.endsWith("/") ? abs : abs + "/";
  return list.some((p) => {
    if (!p.startsWith("~")) return dir.includes(p);
    const anchored = home + p.slice(1);
    return anchored.endsWith("/") ? dir.startsWith(anchored) : abs === anchored;
  });
}

// abs is a lowercased key; a trailing / marks a directory.
export function isSecret(abs: string): boolean {
  return (!abs.endsWith("/") && isProtectedEnv(basename(abs))) || matches(abs, secretPaths);
}

export function isWriteProtected(abs: string): boolean {
  return matches(abs, writeOnlyPaths);
}

// Shell words that respect quotes ('', "", $''), grouped into simple commands
// (split at ; | & ( ) ` and newlines, but not in >&2, &>x or >|x), with
// comments and heredoc bodies removed. A quoted word or unquoted heredoc body
// that contains $( or ` is also read again as commands. Not a parser: when
// unsure (an unterminated quote or heredoc), it keeps the rest of the text as
// words rather than dropping it.
const substitution = /\$\(|`/;

function shellCommands(cmd: string): string[][] {
  const commands: string[][] = [[]];
  const nested: string[][] = [];
  const heredocs: { word: string; tabs: boolean; quoted: boolean }[] = [];
  // Terminators already missing from the rest of cmd, so each is looked for once.
  const missing = new Set<string>();
  let word = "";
  let inWord = false;
  let quote = "";
  let quoteStart = 0;
  let arith = 0; // depth of $(( )) / (( )), where << is a shift
  const endWord = () => {
    if (inWord) commands[commands.length - 1].push(word);
    // Each pass strips a layer of quoting, so this recursion shrinks.
    if (/\s/.test(word) && substitution.test(word)) nested.push(...shellCommands(word));
    word = "";
    inWord = false;
  };
  for (let i = 0; i < cmd.length; i++) {
    const c = cmd[i];
    if (quote) {
      if (c === quote.at(-1)) quote = "";
      else if (c === "\\" && quote !== "'" && i + 1 < cmd.length) word += cmd[++i];
      else word += c;
    } else if (c === "'" || c === '"' || (c === "$" && cmd[i + 1] === "'")) {
      quote = c === "$" ? cmd.slice(i, ++i + 1) : c;
      quoteStart = i;
      inWord = true;
    } else if (c === "\\" && i + 1 < cmd.length) {
      word += cmd[++i];
      inWord = true;
    } else if (c === "#" && !inWord) {
      const nl = cmd.indexOf("\n", i);
      i = (nl < 0 ? cmd.length : nl) - 1;
    } else if (/[;|&()`\n]/.test(c) && !(/[&|]/.test(c) && cmd[i - 1] === ">") && !(c === "&" && /[<>]/.test(cmd[i - 1] + cmd[i + 1]))) {
      endWord();
      commands.push([]);
      if ((c === "(" || c === ")") && cmd[i + 1] === c && (c === "(" || arith > 0)) {
        arith += c === "(" ? 1 : -1;
        i++;
      }
      if (c !== "\n") continue;
      // Skip each pending heredoc body up to its terminator. Without one, skip
      // nothing.
      let j = i + 1;
      for (const { word: end, tabs, quoted } of heredocs.splice(0)) {
        const bodyStart = j;
        const key = `${tabs}${end}`;
        for (let k = missing.has(key) ? cmd.length + 1 : j; k <= cmd.length; ) {
          const nl = cmd.indexOf("\n", k);
          const lineEnd = nl < 0 ? cmd.length : nl;
          const line = cmd.slice(k, lineEnd);
          if ((tabs ? line.replace(/^\t+/, "") : line) === end) {
            j = lineEnd + 1;
            break;
          }
          k = lineEnd + 1;
        }
        if (j === bodyStart) {
          missing.add(key);
          break;
        }
        const body = cmd.slice(bodyStart, j);
        if (!quoted && substitution.test(body)) nested.push(...shellCommands(body));
      }
      i = j - 1;
    } else if (/\s/.test(c)) {
      endWord();
    } else {
      // <<WORD, <<-WORD, <<'WORD', <<"WORD", but not the here-string <<<, a
      // shift like $((1<<2)), or a partly quoted word like <<E"OF".
      if (c === "<" && cmd[i + 1] === "<" && cmd[i - 1] !== "<" && arith === 0) {
        const m = /^<<(-?)[ \t]*(['"]?)([A-Za-z_][\w.-]*)\2(?=[\s;&|()<>]|$)/.exec(cmd.slice(i));
        if (m) heredocs.push({ word: m[3], tabs: m[1] === "-", quoted: m[2] !== "" });
      }
      word += c;
      inWord = true;
    }
  }
  if (quote) {
    // Unterminated: re-read everything after the quote as unquoted words.
    word = "";
    inWord = false;
    commands.push(...shellCommands(cmd.slice(quoteStart + 1)));
  }
  endWord();
  return [...commands, ...nested].filter((c) => c.length > 0);
}

const redirect = /^(\d*[<>]+[&|]?|&>)/;
// Commands that run another command: their options that take a separate
// value, and how many plain arguments come before the command.
const wrappers = new Map<string, { opts: RegExp; args?: number }>([
  ["sudo", { opts: /^(-[ugCDprtTUR]|--(user|group|close-from|chdir|host|other-user|prompt|role|type|command-timeout))$/ }],
  ["doas", { opts: /^-[uC]$/ }],
  ["env", { opts: /^(-[uCS]|--(unset|chdir|split-string))$/ }],
  ["xargs", { opts: /^(-[IdEaLnPs]|--(arg-file|delimiter|max-args|max-procs|max-chars|process-slot-var))$/ }],
  ["time", { opts: /^(-[fo]|--(format|output))$/ }],
  ["exec", { opts: /^-a$/ }],
  ["nice", { opts: /^(-n|--adjustment)$/ }],
  ["timeout", { opts: /^(-[sk]|--(signal|kill-after))$/, args: 1 }],
  ["stdbuf", { opts: /^-[ioe]$/ }],
  ["command", { opts: /^$/ }],
  ["nohup", { opts: /^$/ }],
]);

// Indexes of the words a simple command writes to: redirect targets, tee
// arguments, sed -i / perl -i files, mv sources and the destination of mv, cp,
// install and ln. Other arguments are never treated as writes.
function writeTargets(words: string[]): Set<number> {
  const targets = new Set<number>();
  const args: number[] = [];
  let name = "";
  let op = "";
  let wrapper: { opts: RegExp; args?: number } | undefined;
  let skip = false;
  let positional = 0;
  words.forEach((word, i) => {
    const prefix = op ? "" : (redirect.exec(word)?.[0] ?? "");
    if (op || prefix) {
      const o = op || prefix;
      const rest = word.slice(prefix.length);
      op = rest ? "" : o;
      // >&2 and >&- duplicate or close a descriptor; they are not files.
      if (rest && o.includes(">") && !(o.endsWith("&") && /^(\d+|-)$/.test(rest))) targets.add(i);
    } else if (name) {
      args.push(i);
    } else if (skip) {
      skip = false;
    } else if (wrapper && word.startsWith("-")) {
      skip = wrapper.opts.test(word);
    } else if (positional > 0) {
      positional--;
    } else if (wrappers.has(basename(word))) {
      wrapper = wrappers.get(basename(word));
      positional = wrapper?.args ?? 0;
    } else if (!/^[A-Za-z_]\w*=/.test(word)) {
      name = basename(word);
    }
  });

  const plain = args.filter((i) => !words[i].startsWith("-"));
  if (name === "tee") {
    for (const i of plain) targets.add(i);
  } else if (["mv", "cp", "install", "ln"].includes(name)) {
    if (name === "mv") for (const i of plain) targets.add(i);
    const t = args.findIndex((i) => /^(-t|--target-directory)(=|$)/.test(words[i]));
    const dest = t < 0 ? plain.at(-1) : words[args[t]].includes("=") ? args[t] : args[t + 1];
    if (dest !== undefined) targets.add(dest);
  } else if ((name === "sed" || name === "perl") && args.some((i) => /^(-[a-zA-Z]*i|--in-place)/.test(words[i]))) {
    // Without -e/-f, the first plain argument is the script.
    let script = true;
    const files: number[] = [];
    for (let k = 0; k < args.length; k++) {
      const w = words[args[k]];
      if (/^(-[a-zA-Z]*[ef]|--expression|--file)(=|$)/.test(w)) {
        script = false;
        if (!w.includes("=")) k++;
      } else if (!w.startsWith("-")) {
        files.push(args[k]);
      }
    }
    for (const i of files.slice(script ? 1 : 0)) targets.add(i);
  }
  return targets;
}

export type BashPath = { token: string; abs: string; bare: boolean; write: boolean };

// Tokens worth checking: write targets, path-like tokens (with /, or starting
// with ~, $HOME or ${HOME}) and bare env-file names that exist in cwd. Tokens
// with whitespace (messages, scripts) and non-file URLs are skipped. abs is
// resolved but not lowercased or realpath'd.
export function bashPathTokens(cmd: string, cwd: string): BashPath[] {
  const out: BashPath[] = [];
  for (const words of shellCommands(cmd)) {
    const targets = writeTargets(words);
    words.forEach((word, i) => {
      // Redirect prefixes (2>x, &>x, >>x, <x), then --flag=value / VAR=value.
      // Lists like -v ~/.aws:/root/.aws or src=a,dst=b are checked per item.
      const unprefixed = word.replace(redirect, "");
      if (/\s/.test(unprefixed) || /^(?!file:)[a-z][\w+.-]*:\/\//i.test(unprefixed)) return;
      const write = targets.has(i);
      const items = unprefixed.startsWith("file:") ? [unprefixed] : unprefixed.split(/[:,]/);
      for (const item of items) {
        const token = item.replace(/^(-{1,2}[\w-]+|[A-Za-z_]\w*)=/, "");
        if (!token) continue;
        const expanded = token.replace(/^(\$HOME|\$\{HOME\})(?=\/|$)/, homedir());
        if (write || expanded.includes("/") || expanded.startsWith("~")) {
          const abs = normalizeToolPath(expanded, cwd);
          out.push({ token, abs: token.endsWith("/") && abs !== "/" ? abs + "/" : abs, bare: false, write });
        } else if (isProtectedEnv(basename(token).toLowerCase())) {
          const abs = resolve(cwd, token);
          if (existsSync(abs)) out.push({ token, abs, bare: true, write });
        }
      }
    });
  }
  return out;
}

type Verdict = { path: string; ask: boolean; why: string };

function checkBash(cmd: string, cwd: string): Verdict | undefined {
  let budget = maxRealpaths;
  let ask: Verdict | undefined;
  for (const t of bashPathTokens(cmd, cwd)) {
    if (t.bare) {
      ask ??= { path: t.token, ask: true, why: "names an env file" };
      continue;
    }
    const hits = (p: string) => isSecret(p) || (t.write && isWriteProtected(p));
    const lexical = key(t.abs);
    if (hits(lexical)) return { path: t.token, ask: false, why: `matches ${lexical}` };
    if (budget-- <= 0) {
      ask ??= { path: t.token, ask: true, why: "has too many paths to check" };
      continue;
    }
    const hit = candidates(t.abs).find(hits);
    if (hit) return { path: t.token, ask: false, why: `matches ${hit}` };
  }
  return ask;
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, ctx) => {
    if (isToolCallEventType("bash", event) || isToolCallEventType("powershell", event)) {
      const { command } = event.input;
      const verdict = checkBash(command, ctx.cwd);
      if (!verdict) return undefined;
      const reason = `Command touches protected path "${verdict.path}" (${verdict.why})`;
      if (verdict.ask && ctx.hasUI) {
        const choice = await ctx.ui.select(`⚠️ ${reason}:\n\n  ${command}\n\nAllow?`, ["Yes", "No"]);
        return choice === "Yes" ? undefined : { block: true, reason: "Blocked by user" };
      }
      if (ctx.hasUI) ctx.ui.notify(reason, "warning");
      return { block: true, reason };
    }

    const writes = isToolCallEventType("write", event) || isToolCallEventType("edit", event);
    if (
      !writes &&
      !isToolCallEventType("read", event) &&
      !isToolCallEventType("grep", event) &&
      !isToolCallEventType("find", event) &&
      !isToolCallEventType("ls", event)
    ) {
      return undefined;
    }

    // grep, find and ls default to cwd.
    const path = event.input.path ?? ".";
    const hit = candidates(normalizeToolPath(path, ctx.cwd), event.toolName === "read").find(
      (p) => isSecret(p) || (writes && isWriteProtected(p)),
    );
    if (hit) {
      if (ctx.hasUI) {
        ctx.ui.notify(`Blocked ${event.toolName} of protected path: ${path}`, "warning");
      }
      return { block: true, reason: `Path "${path}" is protected (matches ${hit})` };
    }

    return undefined;
  });
}
