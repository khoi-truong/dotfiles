/**
 * MCP Guard Extension
 *
 * Keeps pi-mcp-adapter to the servers in ~/.pi/agent/mcp.json.
 * PI_MCP_CONFIG_MODE=exclusive (set in ai/aliases.zsh) makes the adapter skip
 * project .mcp.json and .pi/mcp.json, which could otherwise start any command
 * a cloned repo names. Without it, MCP tools are blocked. Also blocks the
 * model-driven server install (it writes mcp.json) and mcpScript (node:vm is
 * not a sandbox; mcp.json turns it off too).
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

type Verdict = { block: true; reason: string } | undefined;

export function checkMcpCall(tool: string, input: unknown, env: NodeJS.ProcessEnv): Verdict {
  if (tool === "mcpScript") return { block: true, reason: "mcpScript is disabled" };
  if (tool !== "mcp") return undefined;
  if (env.PI_MCP_CONFIG_MODE?.trim().toLowerCase() !== "exclusive") {
    return { block: true, reason: "MCP is blocked: PI_MCP_CONFIG_MODE=exclusive is not set, so project MCP configs would load" };
  }
  const action = (input as { action?: unknown } | undefined)?.action;
  if (typeof action === "string" && action.trim().toLowerCase() === "install") {
    return { block: true, reason: "Installing MCP servers is disabled; edit ai/pi/mcp.json instead" };
  }
  return undefined;
}

export default function (pi: ExtensionAPI) {
  // Read once at load, before the adapter could have picked up project configs.
  const env = { PI_MCP_CONFIG_MODE: process.env.PI_MCP_CONFIG_MODE };
  pi.on("tool_call", async (event) => checkMcpCall(event.toolName, event.input, env));
}
