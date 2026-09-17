import assert from "node:assert/strict";
import { test } from "node:test";
import { checkMcpCall } from "../extensions/mcp-guard.ts";

const exclusive = { PI_MCP_CONFIG_MODE: "exclusive" };

const cases: [string, unknown, NodeJS.ProcessEnv, boolean][] = [
  ["mcp", { tool: "github_get_me" }, exclusive, false],
  ["mcp", { search: "docs" }, { PI_MCP_CONFIG_MODE: " Exclusive " }, false],
  ["mcp", { connect: "context7" }, {}, true],
  ["mcp", { tool: "github_get_me" }, { PI_MCP_CONFIG_MODE: "merge" }, true],
  ["mcp", { action: "install", url: "https://example.com/mcp" }, exclusive, true],
  ["mcp", { action: " Install " }, exclusive, true],
  ["mcp", { action: "auth-start", server: "github" }, exclusive, false],
  ["mcpScript", { code: "1" }, exclusive, true],
  ["bash", { command: "ls" }, {}, false],
];

for (const [tool, input, env, blocked] of cases) {
  test(`${blocked ? "blocks" : "allows"} ${tool} ${JSON.stringify(input)} with ${JSON.stringify(env)}`, () => {
    assert.equal(checkMcpCall(tool, input, env)?.block ?? false, blocked);
  });
}
