import { timingSafeEqual } from 'node:crypto';

function object(value, keys, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value) || Object.keys(value).some(key => !keys.includes(key))) {
    throw new TypeError(`Invalid ${label}`);
  }
}

/** Transport configuration only. Project membership and operation policy live in CHATGPT.bend. */
export function connectionConfig(value = { connections: {} }) {
  object(value, ['connections'], 'ChatGPT plugin configuration');
  const entries = value.connections;
  if (!entries || typeof entries !== 'object' || Array.isArray(entries) || Object.keys(entries).length > 32) {
    throw new TypeError('ChatGPT plugin connections must be an object with at most 32 entries');
  }
  return { connections: Object.fromEntries(Object.entries(entries).map(([id, settings]) => {
    if (!/^(0|[1-9][0-9]{0,9})$/.test(id) || Number(id) > 0xffffffff) throw new TypeError('Invalid ChatGPT connection ID');
    object(settings, ['token_env', 'project_ids', 'sandbox'], `ChatGPT connection ${id}`);
    if (typeof settings.token_env !== 'string' || !/^[A-Za-z_][A-Za-z0-9_]*$/.test(settings.token_env)) {
      throw new TypeError('Each ChatGPT connection needs a token_env name');
    }
    if (!Array.isArray(settings.project_ids) || settings.project_ids.length > 32 ||
        settings.project_ids.some(project => !Number.isSafeInteger(project) || project < 0 || project > 0xffffffff) ||
        new Set(settings.project_ids).size !== settings.project_ids.length) throw new TypeError('Invalid ChatGPT project_ids');
    const sandbox = settings.sandbox ?? { mode: 'workspace-write', network_access: false };
    object(sandbox, ['mode', 'network_access'], 'ChatGPT sandbox');
    if (!['workspace-write', 'read-only'].includes(sandbox.mode) || typeof sandbox.network_access !== 'boolean') {
      throw new TypeError('A ChatGPT connection requires an explicit restricted sandbox mode and network_access');
    }
    return [id, { token_env: settings.token_env, project_ids: [...settings.project_ids], sandbox: { ...sandbox } }];
  })) };
}

export function connectionGrants(config) {
  return Object.entries(config?.connections ?? {}).map(([id, settings]) => ({
    connection_id: Number(id), project_ids: settings.project_ids, sandbox: settings.sandbox,
  }));
}

/** Credentials never enter the native model, SQLite journal, MCP output, or shell environment. */
export function connectionCredentials(config, env = process.env) {
  const seen = new Set();
  return new Map(Object.entries(config?.connections ?? {}).map(([id, settings]) => {
    const token = env[settings.token_env];
    if (typeof token !== 'string' || !/^[A-Za-z0-9_-]{32,256}$/.test(token) || seen.has(token)) {
      throw new Error(`ChatGPT connection ${id} needs a distinct 32–256 character base64url token in ${settings.token_env}`);
    }
    seen.add(token);
    return [id, Buffer.from(`Bearer ${token}`)];
  }));
}

export function connectionAuthorized(credentials, id, authorization) {
  const expected = credentials.get(id);
  const supplied = Buffer.from(typeof authorization === 'string' ? authorization : '');
  return expected !== undefined && expected.length === supplied.length && timingSafeEqual(expected, supplied);
}

const routes = {
  list_projects: ['chatgpt_projects', []],
  get_project: ['chatgpt_project', ['project_id']],
  exec: ['chatgpt_exec', ['project_id', 'request_id', 'command', 'timeout_ms', 'max_output_length']],
  get_operation: ['chatgpt_operation', ['project_id', 'operation_id']],
  list_operations: ['chatgpt_operations', ['project_id']],
  cancel_operation: ['chatgpt_cancel', ['project_id', 'operation_id']],
  forget_operation: ['chatgpt_forget', ['project_id', 'operation_id']],
};

/** No arbitrary commands, completion envelopes, Workspace overrides or caller identities cross this route. */
export function connectionCommand(connection, body) {
  object(body, ['tool', 'arguments'], 'ChatGPT tool envelope');
  if (typeof body.tool !== 'string' || !Object.hasOwn(routes, body.tool)) throw new TypeError('Unknown ChatGPT tool');
  const [op, keys] = routes[body.tool];
  const args = body.arguments;
  object(args, keys, 'ChatGPT tool arguments');
  if (body.tool === 'exec') return {
    op, connection_id: connection, project_id: args.project_id, request_id: args.request_id,
    arguments: { command: args.command, timeout_ms: args.timeout_ms ?? 120_000, max_output_length: args.max_output_length ?? 4096 },
  };
  return { op, ...args, connection_id: connection };
}
