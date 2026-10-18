import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { callTool } from './client.mjs';
import { boundary } from '../generated/model-boundary.mjs';

export function createServer(config) {
  const server = new McpServer({ name: 'selvedge', version: '0.1.0' }, {
    instructions: boundary('plugin.instructions', {}),
  });
  for (const tool of boundary('plugin.tools', {})) {
    server.registerTool(tool.name, {
      title: tool.title, description: tool.description,
      inputSchema: z.fromJSONSchema(tool.inputSchema), annotations: tool.annotations,
    }, async (args, extra) => {
      try {
        return await callTool(config, tool.remote, args, { signal: extra.signal });
      } catch {
        return boundary('plugin.connection_failure', {});
      }
    });
  }
  return server;
}
