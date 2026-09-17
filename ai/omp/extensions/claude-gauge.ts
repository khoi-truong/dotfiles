// Composer shape: the built-in "claude" layout (full-width rules, ❯ gutter,
// status bar docked bottom-left) with the context gauge on the top rule.
//
// omp only renders the context gauge for a composer whose `statusAttachment`
// is "top-border" or "top-band"; "claude" uses "top-rule-chip", which docks
// only the right status group and has no gauge path. Every other field here
// mirrors packages/tui/src/components/composer/claude.ts, so the prompt looks
// unchanged — the top rule just carries the full status line plus the gauge
// instead of a right-aligned chip.
//
// The gauge needs a context segment on one side and a non-context segment on
// the other (statusLine.leftSegments / rightSegments); it strips the context
// segment it renders inline, so `context_pct` is not duplicated.
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import type { ComposerStyle } from "@oh-my-pi/pi-tui";

const claudeGauge: ComposerStyle = {
  id: "dotfiles/claude-gauge",
  sideBorders: false,
  verticalChrome: 2,
  statusAttachment: "top-border",
  bottomBar: "left",
  bottomBarGap: false,
  defaultPromptGutter: "❯ ",
  defaultPaddingX: () => 0,
  sideChromeWidth: (paddingX) => paddingX,
  renderTop({ box, width, borderColor, topBorder }) {
    if (!topBorder) return borderColor(box.horizontal.repeat(width));
    // The gauge is rendered at this style's top-border width, which is the full
    // row width because sideChromeWidth is 0 — let it own the row. A leading
    // rule only appears if the host ever hands back a shorter line.
    if (topBorder.width >= width) return topBorder.content;
    return borderColor(box.horizontal.repeat(width - topBorder.width)) + topBorder.content;
  },
  renderRow: ({ gutter, text, pad }) => [gutter + text + pad],
  renderBottom: ({ box, width, borderColor }) => borderColor(box.horizontal.repeat(width)),
};

export default function (pi: ExtensionAPI): void {
  pi.registerComposerShape({
    label: "Claude Code + Context Gauge",
    description: "Claude Code rules with the context gauge on the top rule",
    style: claudeGauge,
  });
}
