// Independent evaluator connections, endpoint policies and login convenience.
// Task state and leases belong exclusively to the native transition.
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const name = value => typeof value === 'string' && /^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$/.test(value);
const variable = value => typeof value === 'string' && /^[A-Za-z_][A-Za-z0-9_]*$/.test(value);

function fields(value, allowed, label) {
  if (!object(value) || Object.keys(value).some(key => !allowed.includes(key))) throw new TypeError(`Invalid ${label} configuration fields`);
}

const connections = Object.freeze({
  vercel: { model: 'typesafe-ai/jev', endpoint: 'https://ai-gateway.vercel.sh/v1/evaluate' },
  typesafe: { model: 'jev-latest', endpoint: 'https://api.typesafe.ai/v1/systemone' },
  openrouter: { model: 'typesafe/jev-1.13', endpoint: 'https://openrouter.ai/api/alpha/decisions' },
});

export function evaluatorConnections(value = {}) {
  if (!object(value) || Object.keys(value).length > 32) throw new TypeError('reasoning_evaluators must be a bounded object');
  return Object.freeze(Object.fromEntries(Object.entries(value).map(([key, source]) => {
    if (!name(key)) throw new TypeError('Invalid reasoning evaluator name');
    fields(source, ['provider', 'model', 'endpoint', 'api_key_env', 'timeout_ms', 'max_attempts'], 'reasoning evaluator');
    const provider = source.provider ?? 'vercel';
    if (!Object.hasOwn(connections, provider)) throw new TypeError('Unknown Jev API provider');
    const config = { provider, ...connections[provider], api_key_env: 'JEV_API_KEY', timeout_ms: 30_000, max_attempts: 3, ...source };
    if (!name(config.model) || !variable(config.api_key_env)) throw new TypeError('Invalid evaluator model or API-key environment variable');
    const url = new URL(config.endpoint);
    if (url.username || url.password || url.hash || url.search || !['http:', 'https:'].includes(url.protocol) ||
        (url.protocol === 'http:' && !['localhost', '127.0.0.1', '[::1]'].includes(url.hostname))) {
      throw new TypeError('The evaluator endpoint requires HTTPS except on loopback, without embedded credentials');
    }
    if (!Number.isSafeInteger(config.timeout_ms) || config.timeout_ms < 100 || config.timeout_ms > 120_000 ||
        !Number.isSafeInteger(config.max_attempts) || config.max_attempts < 1 || config.max_attempts > 3) {
      throw new TypeError('Invalid evaluator deadline or same-provider retry bound');
    }
    return [key, Object.freeze(config)];
  })));
}

export function adaptivePolicy(value) {
  if (value === undefined || value === null || value === false) return null;
  fields(value, ['evaluator', 'efforts', 'baseline', 'transport', 'max_lease'], 'adaptive reasoning');
  const policy = { max_lease: 10, ...value };
  if (!name(policy.evaluator) || !Array.isArray(policy.efforts) || !policy.efforts.length || policy.efforts.length > 16 ||
      policy.efforts.some(effort => !name(effort) || effort === 'auto' || Buffer.byteLength(effort) > 64) ||
      new Set(policy.efforts).size !== policy.efforts.length || !policy.efforts.includes(policy.baseline) ||
      !['configuration_update', 'request_effort'].includes(policy.transport) ||
      !Number.isSafeInteger(policy.max_lease) || policy.max_lease < 1 || policy.max_lease > 10) {
    throw new TypeError('Adaptive reasoning requires an evaluator, distinct actual efforts, a supported baseline, transport, and a lease bound of 1..10');
  }
  return Object.freeze({ ...policy, efforts: Object.freeze([...policy.efforts]) });
}

/** Ordinary profile configuration: no task policy is implemented in discovery. */
export function accountAutoPreset(profile, descriptor) {
  if (descriptor.slug !== 'gpt-6-astra') return undefined;
  const efforts = [...new Set(descriptor.supported_reasoning_levels.map(level => level.effort))];
  if (!efforts.length || efforts.includes('auto')) return undefined;
  const baseline = efforts.includes(descriptor.default_reasoning_level) ? descriptor.default_reasoning_level : efforts[0];
  return Object.freeze({ ...profile, adaptive_reasoning: adaptivePolicy({
    evaluator: 'jev', efforts, baseline, transport: 'configuration_update', max_lease: 10,
  }) });
}

export function accountConnection(profile) {
  return Object.fromEntries(['provider', 'endpoint', 'auth_file', 'issuer', 'client_id', 'timeout_ms']
    .filter(key => Object.hasOwn(profile, key)).map(key => [key, profile[key]]));
}
