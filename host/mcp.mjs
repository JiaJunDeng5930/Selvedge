import { StdioRpc } from './stdio-rpc.mjs';
import { stringifyJson } from './codec.mjs';

const supportedVersions = new Set(['2024-11-05', '2025-03-26', '2025-06-18', '2025-11-25']);
const normalize = name => name.replace(/[^A-Za-z0-9_]/g, '_');

/** MCP vocabulary over the shared transport; task policy remains in Bend. */
export class Mcp extends StdioRpc {
  constructor(name, config, limits) {
    super(name, config, limits, { label: 'MCP', timeoutMs: limits.mcp_timeout_ms });
    this.on('notification', message => { if (message.method === 'notifications/tools/list_changed') this.emit('toolsChanged'); });
  }

  async initialize() {
    const initialized = await this.request('initialize', {
      protocolVersion: '2025-11-25', capabilities: {}, clientInfo: { name: 'selvedge-bend', version: '0.1.0' },
    });
    if (!supportedVersions.has(initialized?.protocolVersion)) throw new Error('MCP server selected an unsupported protocol version');
    this.notify('notifications/initialized');
    return this.discover();
  }

  async discover() {
    const tools = [];
    const cursors = new Set();
    const names = new Set();
    let cursor;
    let size = 0;
    do {
      const page = await this.request('tools/list', cursor === undefined ? {} : { cursor });
      if (!Array.isArray(page?.tools)) throw new Error('MCP tools/list did not return tools');
      for (const tool of page.tools) {
        if (typeof tool.name !== 'string' || !tool.name || !tool.inputSchema || typeof tool.inputSchema !== 'object' || Array.isArray(tool.inputSchema)) {
          throw new Error('MCP returned an invalid tool definition');
        }
        if (tool.execution?.taskSupport === 'required') throw new Error(`MCP tool ${tool.name} requires unsupported task-mode execution`);
        const name = `mcp__${normalize(this.name)}__${normalize(tool.name)}`;
        if (names.has(name)) throw new Error(`MCP tool name collision: ${name}`);
        names.add(name);
        const entry = { name, description: tool.description || `Call ${this.name}/${tool.name}`, schema: tool.inputSchema, server: this.name, remote: tool.name };
        size += Buffer.byteLength(stringifyJson(entry));
        tools.push(entry);
        if (tools.length > this.limits.mcp_catalog_tools || size > this.limits.frame_bytes) throw new Error('MCP catalog exceeds limits');
      }
      cursor = page.nextCursor;
      if (cursor !== undefined && (typeof cursor !== 'string' || cursors.has(cursor))) throw new Error('MCP returned an invalid or repeated pagination cursor');
      if (cursor !== undefined) cursors.add(cursor);
    } while (cursor !== undefined);
    return tools;
  }

  async call(name, arguments_, options) {
    const value = await this.request('tools/call', { name, arguments: arguments_ }, options);
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('MCP returned a malformed tool result');
    return { value, error: value.isError === true };
  }
}
