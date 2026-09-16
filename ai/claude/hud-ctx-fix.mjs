#!/usr/bin/env node
// Statusline stdin shim: recompute context_window.used_percentage against the
// effective auto-compact window (200k) instead of the advertised 1M ceiling,
// unless the session is genuinely past the 200k boundary. Keeps the OMC HUD
// ctx bar aligned with the point where Claude Code actually starts compacting.
// Lives in dotfiles so plugin updates cannot clobber it.

let raw = "";
process.stdin.setEncoding("utf8");
for await (const chunk of process.stdin) raw += chunk;

try {
  const d = JSON.parse(raw);
  const cw = d.context_window;
  if (cw && cw.context_window_size > 200_000 && d.exceeds_200k_tokens !== true) {
    const eff = 200_000;
    const used =
      (cw.current_usage?.input_tokens ?? 0) +
        (cw.current_usage?.cache_creation_input_tokens ?? 0) +
        (cw.current_usage?.cache_read_input_tokens ?? 0) ||
      cw.total_input_tokens ||
      Math.round(((cw.used_percentage ?? 0) / 100) * cw.context_window_size);
    const pct = Math.min(100, Math.max(0, Math.round((used / eff) * 100)));
    cw.context_window_size = eff;
    cw.used_percentage = pct;
    cw.remaining_percentage = 100 - pct;
  }
  process.stdout.write(JSON.stringify(d));
} catch {
  process.stdout.write(raw); // never break the statusline
}
