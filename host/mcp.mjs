import { StdioRpc } from './stdio-rpc.mjs';
import { boundary } from './public/model-boundary.mjs';

/** MCP vocabulary over the shared transport; task policy remains in Bend. */
export class Mcp extends StdioRpc {
  constructor(name, config, limits) {
    super(name, config, limits, { label: 'MCP', timeoutMs: limits.mcp_timeout_ms });
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
