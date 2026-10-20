#!/usr/bin/env node
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { loadSettings } from '../src/client.mjs';
import { createServer } from '../src/server.mjs';

try {
  const server = createServer(await loadSettings());
  const transport = new StdioServerTransport();
  await server.connect(transport);
  const close = async () => { await server.close(); process.exitCode = 0; };
  process.once('SIGINT', close);
  process.once('SIGTERM', close);
// DEFENSE: Invalid local credentials or a failed stdio connection prevent MCP startup; report failure to the launching client.
} catch (error) {
  console.error(`Selvedge MCP: ${error.message}`);
  process.exitCode = 1;
}
