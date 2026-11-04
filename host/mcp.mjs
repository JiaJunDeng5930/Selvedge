import { StdioRpc } from './stdio-rpc.mjs';
import { boundary } from './public/model-boundary.mjs';
import { storeImageContent } from './files.mjs';

/** MCP vocabulary over the shared transport; task policy remains in the extracted semantics. */
export class Mcp extends StdioRpc {
  constructor(name, config, limits, { home } = {}) {
    super(name, config, limits, { label: 'MCP', timeoutMs: limits.mcp_timeout_ms });
    this.mediaHome = home;
    this.on('notification', message => { if (message.method === 'notifications/tools/list_changed') this.emit('toolsChanged'); });
  }

  async initialize() {
    const initialized = await this.request('initialize', boundary('plugin.mcp_initialize_request', {}));
    boundary('plugin.mcp_version', { initialized });
    this.notify('notifications/initialized');
    return this.discover();
  }

  async discover() {
    // DEFENSE: A server can keep returning empty pages with fresh cursors;
    // one deadline bounds the whole discovery, including those pages.
    const signal = AbortSignal.timeout(this.timeoutMs);
    let catalog = { tools: [], done: false };
    while (!catalog.done) {
      const page = await this.request('tools/list', catalog.nextCursor === undefined ? {} : { cursor: catalog.nextCursor }, { signal });
      catalog = boundary('plugin.mcp_page', { name: this.name, page, tools: catalog.tools, limits: this.limits });
    }
    return catalog.tools;
  }

  async call(name, arguments_, options) {
    const value = await this.request('tools/call', boundary('plugin.mcp_call_request', { name, arguments: arguments_ }), {
      ...options, prepareIncoming: (result, { signal }) => prepareMcpImages(result, this.mediaHome, signal),
    });
    return boundary('plugin.mcp_result', { result: value });
  }
}

// Only an admitted tools/call response can hold this RPC materialization token.
// Decode every opaque byte string and admit the complete plan before any write.
async function prepareMcpImages(result, home, signal) {
  signal.throwIfAborted();
  const parts = Array.isArray(result?.content) ? result.content : [];
  const decoded = new Map();
  const observations = parts.map((part, index) => {
    if (part?.type !== 'image' || typeof part.data !== 'string') return null;
    const bytes = Buffer.from(part.data, 'base64');
    decoded.set(index, bytes);
    return { canonical: bytes.toString('base64') === part.data,
      prefix: Array.from(bytes.subarray(0, 12)) };
  });
  const plan = boundary('plugin.mcp_media_plan', { result, observations });
  if (!plan.indices.length) return result;
  const content = [...parts];
  for (const index of plan.indices) {
    signal.throwIfAborted();
    content[index] = await storeImageContent(home, 'mcp-image', decoded.get(index), 'auto', { signal });
  }
  return { ...result, content };
}
