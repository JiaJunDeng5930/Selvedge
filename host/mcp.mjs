import { StdioRpc } from './stdio-rpc.mjs';
import { boundary } from './public/model-boundary.mjs';
import { storeImageContent } from './files.mjs';

/** MCP vocabulary over the shared transport; task policy remains in the extracted semantics. */
export class Mcp extends StdioRpc {
  #serverIcons = [];

  constructor(name, config, limits, { home } = {}) {
    super(name, config, limits, { label: 'MCP', timeoutMs: limits.mcp_timeout_ms });
    this.mediaHome = home;
    this.on('notification', message => { if (message.method === 'notifications/tools/list_changed') this.emit('toolsChanged'); });
  }

  async initialize() {
    const initialized = await this.request('initialize', boundary('plugin.mcp_initialize_request', {}));
    boundary('plugin.mcp_version', { initialized });
    this.#serverIcons = observeIcons(initialized.serverInfo?.icons);
    this.notify('notifications/initialized');
    return this.discover();
  }

  discover() {
    return discoverMcp({ name: this.name }, this.limits, this.timeoutMs, this.listPage.bind(this));
  }

  async listPage(cursor, options) {
    const page = await this.request('tools/list', cursor === undefined ? {} : { cursor }, options);
    return { page, serverIcons: this.#serverIcons };
  }

  callRaw(name, arguments_, options) {
    return this.request('tools/call', boundary('plugin.mcp_call_request', { name, arguments: arguments_ }), options);
  }

  async call(name, arguments_, options) {
    const value = await this.callRaw(name, arguments_, {
      ...options, prepareIncoming: (result, { signal }) => prepareMcpImages(result, this.mediaHome, signal),
    });
    return boundary('plugin.mcp_result', { result: value });
  }
}

export async function discoverMcp(route, limits, timeoutMs, listPage) {
  // DEFENSE: A server can keep returning empty pages with fresh cursors;
  // one deadline bounds the whole discovery, including those pages.
  const signal = AbortSignal.timeout(timeoutMs);
  let catalog = { tools: [] };
  do {
    const { page, serverIcons } = await listPage(catalog.nextCursor, { signal });
    const observed = Array.isArray(page?.tools) ? { ...page, tools: page.tools.map(tool => ({
      ...tool, icon_observations: observeIcons(tool?.icons),
    })) } : page;
    catalog = boundary('plugin.mcp_page', { ...route, page: observed, tools: catalog.tools,
      server_icons: serverIcons, limits });
  } while (catalog.nextCursor !== undefined);
  return catalog.tools;
}

export async function completeSharedMcp(result, home, signal) {
  return boundary('plugin.mcp_result', { result: await prepareMcpImages(result, home, signal) });
}

const jpegFrames = new Set([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf]);

function jpegSize(bytes) {
  let offset = 2;
  while (offset + 4 <= bytes.length && bytes[offset] === 0xff) {
    while (bytes[offset] === 0xff) offset++;
    const marker = bytes[offset++];
    // DEFENSE: Repeated marker bytes can end a malformed image. Scan and EOI end frame discovery.
    if (offset + 2 > bytes.length || marker === 0xda || marker === 0xd9) return null;
    const length = bytes.readUInt16BE(offset);
    // DEFENSE: A corrupt segment can have zero length or point outside the decoded bytes.
    if (length < 2 || offset + length > bytes.length) return null;
    if (jpegFrames.has(marker) && length >= 7) return [bytes.readUInt16BE(offset + 5), bytes.readUInt16BE(offset + 3)];
    offset += length;
  }
  return null;
}

function imageSize(bytes, mime) {
  if (mime === 'image/jpeg' || mime === 'image/jpg') return jpegSize(bytes);
  if (mime === 'image/png' && bytes.length >= 24 && bytes.toString('ascii', 12, 16) === 'IHDR')
    return [bytes.readUInt32BE(16), bytes.readUInt32BE(20)];
  return null;
}

function observeIcons(icons) {
  // DEFENSE: Icons are optional and the peer can send an invalid metadata shape.
  if (!Array.isArray(icons)) return [];
  return icons.flatMap(icon => {
    const source = icon?.src;
    // DEFENSE: Non-inline URLs have no bytes to observe on the stdio transport.
    const match = typeof source === 'string' && /^data:([^;,]+);base64,([a-zA-Z0-9+/=]+)$/.exec(source);
    if (!match) return [];
    const [, mime, encoded] = match;
    const bytes = Buffer.from(encoded, 'base64');
    const size = imageSize(bytes, mime);
    return size ? [{ src: source, mimeType: icon.mimeType, canonical: bytes.toString('base64') === encoded,
      prefix: Array.from(bytes.subarray(0, 12)), width: size[0], height: size[1] }] : [];
  });
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
