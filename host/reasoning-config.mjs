// Pure admission belongs to the native configuration adapter. References retain
// original UTF-16 strings and opaque environment values at the host boundary.
import { boundary } from './public/model-boundary.mjs';

export function configurationObserver() {
  const originals = [];
  const units = value => Array.from({ length: value.length }, (_, index) => value.charCodeAt(index));
  function observe(value, { shallow = false, env = false } = {}) {
    const ref = originals.push(value) - 1;
    const kind = value === null ? 'null' : Array.isArray(value) ? 'array' : typeof value;
    const result = { ref, kind };
    if (shallow) return result;
    if (kind === 'string') result.units = units(value);
    if (kind === 'number' && Number.isFinite(value)) result.number = value;
    if (kind === 'boolean') result.boolean = value;
    if (kind === 'array') result.items = value.map(item => observe(item, { shallow: env }));
    if (kind === 'object') result.fields = Object.entries(value).map(([key, item]) => ({
      key: observe(key), value: observe(item, { shallow: env, env: key === 'env' }),
    }));
    return result;
  }
  function materialize(plan) {
    if (Object.hasOwn(plan, 'undefined')) return undefined;
    if (Object.hasOwn(plan, 'ref')) return originals[plan.ref];
    if (Object.hasOwn(plan, 'literal')) return plan.literal;
    if (Object.hasOwn(plan, 'array')) return plan.array.map(materialize);
    const base = Object.hasOwn(plan, 'base') ? originals[plan.base] : {};
    return { ...base, ...Object.fromEntries(plan.fields.map(field => [field.key, materialize(field.value)])) };
  }
  function execute(operation, source) {
    const plan = boundary(operation, source);
    // DEFENSE: Configuration files can contain invalid evaluator URLs, credentials or effort policies; native rejection materializes a diagnostic without exposing opaque env values.
    if (Object.hasOwn(plan, 'error')) {
      const message = plan.error.map(part => Object.hasOwn(part, 'ref') ? originals[part.ref] : part.literal).join('');
      throw plan.code === 'Error' ? new Error(message) : new TypeError(message);
    }
    return plan;
  }
  return { observe, materialize, execute };
}

export function evaluatorConnections(value = {}) {
  const observer = configurationObserver();
  const kind = value === null ? 'null' : Array.isArray(value) ? 'array' : typeof value;
  // Enumeration is an external observation. Later keys and values are withheld
  // until all policy and URL operations of the current entry have completed.
  const entries = kind === 'object' ? Object.entries(value) : [];
  const positions = observer.execute('config.evaluators', {
    kind, count: entries.length, positions: entries.map((_, index) => index),
  });
  const result = [];
  for (const position of positions) {
    const [key, source] = entries[position];
    const original = { name: observer.observe(key), entry: observer.observe(source) };
    const plan = observer.execute('config.evaluator_plan', original);
    const config = observer.materialize(plan);
    const url = new URL(config.endpoint);
    observer.execute('config.evaluator_entry', { ...original, plan, url: {
      protocol: url.protocol, hostname: url.hostname, username: url.username,
      password: url.password, hash: url.hash, search: url.search,
    } });
    result.push([key, Object.freeze(config)]);
  }
  return Object.freeze(Object.fromEntries(result));
}

export function adaptivePolicy(value) {
  const observer = configurationObserver();
  const source = observer.observe(value);
  const efforts = source.kind === 'object' ? value.efforts : undefined;
  const bytes = Array.isArray(efforts) ? efforts.map(effort =>
    typeof effort === 'string' ? Buffer.byteLength(effort) : null) : [];
  const plan = observer.execute('config.adaptive_policy', { value: source, bytes });
  const policy = observer.materialize(plan);
  if (policy === null) return null;
  return Object.freeze({ ...policy, efforts: Object.freeze(policy.efforts) });
}

/** Ordinary profile configuration: no task policy is implemented in discovery. */
export function accountAutoPreset(profile, descriptor) {
  const observer = configurationObserver();
  const plan = observer.execute('config.auto_preset', {
    profile: observer.observe(profile), descriptor: observer.observe(descriptor),
  });
  const selection = observer.materialize(plan);
  if (selection === undefined) return undefined;
  return Object.freeze({ ...profile, adaptive_reasoning: adaptivePolicy(selection) });
}
