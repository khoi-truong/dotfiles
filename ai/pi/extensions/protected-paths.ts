// Vendored from pi-coding-agent 0.85.1 examples/extensions/protected-paths.ts
/**
 * Protected Paths Extension
 *
 * Blocks write and edit operations to protected paths.
 * Useful for preventing accidental modifications to sensitive files.
 * Paths are resolved against the cwd and matched case-insensitively (macOS
 * filesystems are case-insensitive). Only the write/edit tools are checked;
 * bash can still reach these files.
 */

import { realpathSync } from "node:fs";
import { homedir } from "node:os";
import { basename, resolve } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const home = homedir().toLowerCase();

// Absolute path prefixes (a trailing / protects the whole directory).
const protectedPrefixes = [
  "~/.dotfiles/ai/env.local.zsh",
  "~/.dotfiles/ai/pi/extensions/",
  "~/.pi/agent/auth.json",
  "~/.pi/agent/trust.json",
  "~/.pi/agent/extensions/",
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
].map((p) => home + p.slice(1));

// Path segments protected anywhere.
const protectedSegments = ["/.git/", "/node_modules/"];

function isProtectedEnv(name: string): boolean {
  if (name === ".env") return true;
  return name.startsWith(".env.") && !/\.(example|sample|template)$/.test(name);
}

// Both the literal path and its symlink target, so ~/.ssh/config (linked into
// the dotfiles repo) and a link pointing at a protected file are both caught.
function candidates(cwd: string, input: string): string[] {
  const expanded = input.startsWith("~/") ? homedir() + input.slice(1) : input;
  const abs = resolve(cwd, expanded);
  const paths = [abs.toLowerCase()];
  try {
    paths.push(realpathSync(abs).toLowerCase());
  } catch {
    // New file: nothing to resolve.
  }
  return paths;
}

function isProtected(abs: string): boolean {
  return (
    isProtectedEnv(basename(abs)) ||
    protectedSegments.some((s) => abs.includes(s)) ||
    protectedPrefixes.some((p) => (p.endsWith("/") ? abs.startsWith(p) : abs === p))
  );
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName !== "write" && event.toolName !== "edit") {
      return undefined;
    }

    const path = event.input.path as string;
    if (candidates(ctx.cwd, path).some(isProtected)) {
      if (ctx.hasUI) {
        ctx.ui.notify(`Blocked write to protected path: ${path}`, "warning");
      }
      return { block: true, reason: `Path "${path}" is protected` };
    }

    return undefined;
  });
}
