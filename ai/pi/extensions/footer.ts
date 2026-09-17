/**
 * Flat footer in the theme's palette, replacing pi's built-in one:
 *
 *   ◆ deepseek-flash · high │ ▰▰▰▱▱▱▱▱ 38%/1M │ cache 92% │ ↑1.2M ↓48k │ $0.041 │ 12m
 *   ~/.dotfiles  ⎇ main +2 ~3
 *   <extension statuses>
 *
 * Plain Unicode only, no Nerd Font glyphs. Interactive mode only.
 */

import { relative, sep } from "node:path";
import type { ExtensionAPI, ExtensionContext, ThemeColor } from "@earendil-works/pi-coding-agent";
import { truncateToWidth } from "@earendil-works/pi-tui";

const BAR_CELLS = 8;

function formatTokens(count: number): string {
  if (count < 1000) return `${count}`;
  if (count < 10_000) return `${(count / 1000).toFixed(1)}k`;
  if (count < 1_000_000) return `${Math.round(count / 1000)}k`;
  if (count < 10_000_000) return `${(count / 1_000_000).toFixed(1)}M`;
  return `${Math.round(count / 1_000_000)}M`;
}

function formatElapsed(ms: number): string {
  const minutes = Math.floor(ms / 60_000);
  if (minutes < 60) return `${minutes}m`;
  return `${Math.floor(minutes / 60)}h${`${minutes % 60}`.padStart(2, "0")}`;
}

function formatCwd(cwd: string): string {
  const home = process.env.HOME;
  if (!home) return cwd;
  const rel = relative(home, cwd);
  if (rel === "") return "~";
  if (rel === ".." || rel.startsWith(`..${sep}`) || rel.startsWith(sep)) return cwd;
  return `~${sep}${rel}`;
}

function oneLine(text: string): string {
  return text.replace(/[\r\n\t]/g, " ").replace(/ +/g, " ").trim();
}

interface GitCounts {
  untracked: number;
  changed: number;
}

async function readGitCounts(pi: ExtensionAPI, cwd: string): Promise<GitCounts | undefined> {
  const result = await pi.exec("git", ["--no-optional-locks", "status", "--porcelain"], { cwd, timeout: 2000 });
  if (result.code !== 0) return undefined;
  const counts = { untracked: 0, changed: 0 };
  for (const line of result.stdout.split("\n")) {
    if (line.startsWith("??")) counts.untracked++;
    else if (line) counts.changed++;
  }
  return counts;
}

export default function (pi: ExtensionAPI) {
  let git: GitCounts | undefined;
  let requestRender: (() => void) | undefined;

  const refreshGit = async (ctx: ExtensionContext) => {
    git = await readGitCounts(pi, ctx.cwd).catch(() => undefined);
    requestRender?.();
  };

  pi.on("session_start", async (_event, ctx) => {
    if (ctx.mode !== "tui") return;
    // Session age, so a resumed session keeps counting.
    const created = ctx.sessionManager.getHeader()?.timestamp;
    const startedAt = (created && Date.parse(created)) || Date.now();

    ctx.ui.setFooter((tui, theme, footerData) => {
      requestRender = () => tui.requestRender();
      const unsubscribe = footerData.onBranchChange(() => void refreshGit(ctx));
      const sepBar = theme.fg("dim", " │ ");

      const gitLine = (): string => {
        const parts = [theme.fg("mdLink", formatCwd(ctx.cwd))];
        const branch = footerData.getGitBranch();
        if (branch) {
          let gitText = theme.fg("success", `  ⎇ ${branch}`);
          if (git?.untracked) gitText += theme.fg("warning", ` +${git.untracked}`);
          if (git?.changed) gitText += theme.fg("warning", ` ~${git.changed}`);
          parts.push(gitText);
        }
        const name = pi.getSessionName();
        if (name) parts.push(theme.fg("dim", " · ") + theme.fg("muted", oneLine(name)));
        return parts.join("");
      };

      const modelLine = (): string => {
        let model = theme.fg("accent", `◆ ${ctx.model?.id ?? "no model"}`);
        if (ctx.model?.reasoning) {
          const level = pi.getThinkingLevel();
          const color = `thinking${level[0].toUpperCase()}${level.slice(1)}` as ThemeColor;
          model += theme.fg("dim", " · ") + theme.fg(color, level);
        }

        let input = 0;
        let output = 0;
        let cost = 0;
        let cacheHit: number | undefined;
        for (const entry of ctx.sessionManager.getEntries()) {
          let usage;
          if (entry.type === "message" && (entry.message.role === "assistant" || entry.message.role === "toolResult")) {
            usage = entry.message.usage;
            if (usage && entry.message.role === "assistant") {
              const prompt = usage.input + usage.cacheRead + usage.cacheWrite;
              cacheHit = prompt > 0 ? (usage.cacheRead / prompt) * 100 : undefined;
            }
          } else if (entry.type === "compaction" || entry.type === "branch_summary") {
            usage = entry.usage;
          }
          if (!usage) continue;
          input += usage.input;
          output += usage.output;
          cost += usage.cost.total;
        }

        const context = ctx.getContextUsage();
        const window = formatTokens(context?.contextWindow ?? ctx.model?.contextWindow ?? 0);
        const percent = context?.percent;
        let ctxText: string;
        if (percent == null) {
          ctxText = theme.fg("dim", `${"▱".repeat(BAR_CELLS)} ?/${window}`);
        } else {
          const filled = Math.min(BAR_CELLS, Math.round((percent / 100) * BAR_CELLS));
          const color: ThemeColor = percent > 90 ? "error" : percent > 70 ? "warning" : "success";
          ctxText =
            theme.fg(color, "▰".repeat(filled)) +
            theme.fg("dim", "▱".repeat(BAR_CELLS - filled)) +
            theme.fg(color, ` ${Math.round(percent)}%`) +
            theme.fg("muted", `/${window}`);
        }

        const parts = [model, ctxText];
        if (cacheHit !== undefined) parts.push(theme.fg("thinkingMedium", `cache ${Math.round(cacheHit)}%`));
        if (input || output) parts.push(theme.fg("muted", `↑${formatTokens(input)} ↓${formatTokens(output)}`));
        if (cost) parts.push(theme.fg("warning", `$${cost.toFixed(3)}`));
        parts.push(theme.fg("dim", formatElapsed(Date.now() - startedAt)));
        return parts.join(sepBar);
      };

      return {
        render(width: number): string[] {
          const lines = [modelLine(), gitLine()];
          const statuses = [...footerData.getExtensionStatuses()]
            .sort(([a], [b]) => a.localeCompare(b))
            .map(([, text]) => oneLine(text));
          if (statuses.length) lines.push(statuses.join(" "));
          return lines.map((line) => truncateToWidth(line, width, theme.fg("dim", "…")));
        },
        invalidate() {},
        dispose() {
          unsubscribe();
          requestRender = undefined;
        },
      };
    });

    await refreshGit(ctx);
  });

  pi.on("agent_settled", async (_event, ctx) => {
    if (ctx.mode === "tui") await refreshGit(ctx);
  });
}
