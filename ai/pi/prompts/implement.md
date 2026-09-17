---
description: Full implementation workflow - scout gathers context, planner creates plan, worker implements
---
Run these steps one at a time with the subagent tool, one agent per call, and wait for each result:

1. Call the "scout" agent to find all code relevant to: $@
2. Call the "planner" agent to create an implementation plan for "$@". Put the scout's full result in its task.
3. Call the "worker" agent to implement the plan. Put the planner's full result in its task.
