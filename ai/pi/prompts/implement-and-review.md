---
description: Worker implements, reviewer reviews, worker applies feedback
---
Run these steps one at a time with the subagent tool, one agent per call, and wait for each result:

1. Call the "worker" agent to implement: $@
2. Call the "reviewer" agent to review that implementation. Put the worker's full result in its task.
3. Call the "worker" agent to apply the review feedback. Put the reviewer's full result in its task.
