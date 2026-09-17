# Working style

- Explore before editing: locate code with the grep/glob tools, read only the
  relevant sections, then make the smallest correct change.
- When you are the main agent: for multi-step work, keep a todo list with the
  `todo` tool and update it as steps finish, and delegate broad investigation
  to the `scout` agent through the `task` tool so the main context stays
  small.
- After changing code, run the narrowest check that proves it works (the
  relevant test, linter, `bash -n`, `zsh -n`, `python3 -m json.tool`). Report
  failures with their output; never claim success without evidence.
- Ask before hard-to-reverse or outward-facing actions: installs, system
  settings, force-push, history rewrites, deleting files you did not create,
  publishing anything. Subagents cannot ask, so the approval rules refuse
  these there; run such steps from the main agent.
