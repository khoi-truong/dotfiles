// Vendored from pi-coding-agent 0.85.1 examples/extensions/permission-gate.ts
/**
 * Permission Gate Extension
 *
 * Prompts for confirmation before running potentially dangerous bash commands.
 * Patterns checked: recursive rm, sudo, chmod/chown 777, plus the installs,
 * system settings and history rewrites the dotfiles CLAUDE.md forbids without
 * asking. Subagents have no UI, so these are blocked outright there.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  const dangerousPatterns = [
    // rm with any flag group containing r/R, or --recursive
    /\brm\s+(-\S+\s+)*(-\w*[rR]|--recursive)/,
    /\bsudo\b/i,
    /\b(chmod|chown)\b.*777/i,
    /\bbrew\s+(bundle(?!\s+(check|list)\b)|install|reinstall|uninstall|remove|upgrade)\b/i,
    /\bdefaults\s+(write|delete|import)\b/i,
    /\bmise\s+(use\b.*(\s-[a-z]*g|--global)|i\b|install|upgrade|up\b)/i,
    // Running a setup.sh (not reading or linting it)
    // (optional VAR=value, env/time/exec/command, sh -c/-x, but not sh -n)
    /(^|[;&|(]|\n)\s*(\w+=\S*\s+|(env|time|exec|command)\s+)*((ba|z)?sh(\s+-(?!n\b)\w+)*\s+)?["']?(\S*\/)?setup\.sh\b/m,
    // git subcommands, allowing global options such as -C <dir> before them
    /\bgit(\s+-\S+(\s+[^-\s]\S*)?)*\s+push\b.*(\s-\w*f|--force|\s\+\S+)/i,
    /\bgit(\s+-\S+(\s+[^-\s]\S*)?)*\s+reset\b.*--hard\b/i,
    /\bgit(\s+-\S+(\s+[^-\s]\S*)?)*\s+clean\b.*(\s-\w*f|--force)/i,
    /\bgit(\s+-\S+(\s+[^-\s]\S*)?)*\s+filter-branch\b/i,
  ];

  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName !== "bash") return undefined;

    const command = event.input.command as string;
    const isDangerous = dangerousPatterns.some((p) => p.test(command));

    if (isDangerous) {
      if (!ctx.hasUI) {
        // In non-interactive mode, block by default
        return { block: true, reason: "Dangerous command blocked (no UI for confirmation)" };
      }

      const choice = await ctx.ui.select(`⚠️ Dangerous command:\n\n  ${command}\n\nAllow?`, ["Yes", "No"]);

      if (choice !== "Yes") {
        return { block: true, reason: "Blocked by user" };
      }
    }

    return undefined;
  });
}
