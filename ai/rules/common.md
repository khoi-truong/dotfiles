# Global working preferences

- Be concise. No preamble/postamble, no "Great question", no recap of what I
  just said.
- Answer first, then briefly justify only if non-obvious.
- Prefer editing existing code over adding new; smallest correct diff.
- Delete dead code outright rather than commenting it out or leaving a
  tombstone comment explaining what used to be there. Git history is the
  record.
- Don't create docs/README/summary files unless asked.
- Never add AI attribution to commits or PRs: no `Co-Authored-By: Claude`,
  no `Claude-Session:` trailer, no "Generated with Claude Code" line, no
  mention of Claude/AI anywhere in commit messages or PR descriptions.
- Use `/clear`-sized units of work: stop and report rather than sprawling.
- Be token-aware: don't re-read files already in context, don't spawn
  subagents for work that can be done inline, keep exploration proportional
  to the task.
- GitHub Actions: when creating, editing, or reviewing anything under
  `.github/` (workflow or composite-action YAML), first read and apply the
  conventions in `~/.dotfiles/ai/shared/github-actions/` — `naming.md`,
  `structure.md`, `security.md`, `cost-and-speed.md`. Settled decisions, not
  suggestions.
