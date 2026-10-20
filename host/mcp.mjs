import { StdioRpc } from './stdio-rpc.mjs';
import { boundary } from './public/model-boundary.mjs';
import { storeImageContent } from './files.mjs';

/** MCP vocabulary over the shared transport; task policy remains in the extracted semantics. */
export class Mcp extends StdioRpc {
  constructor(name, config, limits, { home } = {}) {
    super(name, config, limits, { label: 'MCP', timeoutMs: limits.mcp_timeout_ms,
      prepareIncoming: message => prepareMcpImages(message, home) });
    this.on('notification', message => { if (message.method === 'notifications/tools/list_changed') this.emit('toolsChanged'); });
  }

  async initialize() {
    const initialized = await this.request('initialize', boundary('plugin.mcp_initialize_request', {}));
    boundary('plugin.mcp_version', { initialized });
    this.notify('notifications/initialized');
    return this.discover();
  }

  async discover() {
    let catalog = { tools: [], cursors: [], done: false };
    while (!catalog.done) {
      const page = await this.request('tools/list', catalog.nextCursor === undefined ? {} : { cursor: catalog.nextCursor });
      catalog = boundary('plugin.mcp_page', { name: this.name, page, tools: catalog.tools,
        cursors: catalog.cursors, limits: this.limits });
    }
    return catalog.tools;
  }

  async call(name, arguments_, options) {
    const value = await this.request('tools/call', boundary('plugin.mcp_call_request', { name, arguments: arguments_ }), options);
    return boundary('plugin.mcp_result', { result: value });
  }
}

// Decode and freeze opaque media before the RPC adapter inspects the JSON envelope.
async function prepareMcpImages(message, home) {
  if (message?.jsonrpc !== '2.0' || !Object.hasOwn(message, 'id') || !Array.isArray(message.result?.content)) return message;
  try {
    const content = await Promise.all(message.result.content.map(async part => {
      if (part?.type !== 'image') return part;
      // DEFENSE: An MCP server can return malformed base64 in its declared image content.
      if (typeof part.data !== 'string') throw new TypeError('MCP image data must be base64 text');
      const bytes = Buffer.from(part.data, 'base64');
      if (bytes.toString('base64') !== part.data) throw new TypeError('MCP image data must use canonical base64');
      return storeImageContent(home, 'mcp-image', bytes);
    }));
    return { ...message, result: { ...message.result, content } };
  } catch (error) {
    // DEFENSE: Invalid or unwritable MCP image data is this call's RPC failure, never a successful text-only tool result.
    return { jsonrpc: message.jsonrpc, id: message.id, error: { code: -32603, message: error.message } };
  }
}
