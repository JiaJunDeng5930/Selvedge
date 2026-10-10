import { encode, decode, countTokens } from 'gpt-tokenizer/encoding/o200k_base';
import { setTimeout as delay } from 'node:timers/promises';
import { stringifyJson } from './codec.mjs';
import { readText } from './network.mjs';
import { adaptivePolicy } from './reasoning-config.mjs';
import { boundary, observeJson } from './public/model-boundary.mjs';

export const evaluatorLimits = Object.freeze({ tool_output_tokens: 1000, recent_calls: 6, request_tokens: 28_000,
  request_bytes: 2_100_000, response_bytes: 65_536, tokenizer: 'o200k_base' });
const tokenizerOptions = { disallowedSpecial: new Set() };
const omittedMiddle = '\n[Tool output preview: middle omitted]\n';

function evaluatorOperation(operation, source) {
  try { return boundary(`evaluator.${operation}`, source); }
  catch (error) {
    if (error.code === 'TypeError') throw new TypeError(error.message);
    if (error.code === 'RangeError') throw new RangeError(error.message);
    if (error.code === 'Error') throw new Error(error.message);
    throw error;
  }
}

// This is a local tokenizer budget, not a claim about Jev's private tokenizer.
export function outputTokens(text) {
  return text ? Math.max(countTokens(text, tokenizerOptions), countTokens(JSON.stringify(text), tokenizerOptions)) : 0;
}

function preview(text, budget, originalCost, originalEncoded) {
  const source = { text, budget, original_cost: originalCost, original_observation: observeJson(originalEncoded) };
  let tokens;
  let completion = { ...source }, completionKind = 'start';
  let state = evaluatorOperation('preview_start', completion);
  while (state.action !== 'done') {
    switch (state.action) {
      case 'marker':
        source.marker_cost = outputTokens(omittedMiddle);
        completion = { ...source };
        state = evaluatorOperation('preview_start', completion);
        break;
      case 'encode':
        tokens = encode(text, tokenizerOptions);
        source.token_count = tokens.length;
        completion = { ...source };
        state = evaluatorOperation('preview_start', completion);
        break;
      case 'decode': {
        const observation = { state, head: decode(tokens.slice(0, state.head_count)),
          tail: state.tail_count ? decode(tokens.slice(-state.tail_count)) : '' };
        completionKind = 'step';
        completion = { ...source, state, observation };
        state = evaluatorOperation('preview_step', completion);
        break;
      }
      case 'count':
        completionKind = 'step';
        completion = { ...source, state, observation: { state, text: state.text, cost: outputTokens(state.text) } };
        state = evaluatorOperation('preview_step', completion);
        break;
      default: throw new TypeError('Invalid evaluator preview plan');
    }
  }
  return { source, result: state, completion_kind: completionKind, completion };
}

function observedKind(value) {
  if (value === null) return 'null';
  if (typeof value === 'number' && !Number.isFinite(value)) return Number.isNaN(value) ? 'nan' : 'infinite';
  return typeof value;
}

function budgetConstruction(outputs, maximum) {
  // Observe the budget before touching outputs, retaining the original rejection
  // order without attempting to serialize undefined or nonfinite numbers.
  evaluatorOperation('budget_plan', { maximum: typeof maximum === 'number' && Number.isFinite(maximum) ? maximum : null, entries: [] });
  const entries = Array.from({ length: outputs.length }, (_, index) => {
    if (!(index in outputs)) return { index, absent: true, own_fields: [],
      text: { own: false, truthy: false, type: 'absent', encoded: null }, cost: 0 };
    const output = outputs[index];
    const text = output.text;
    return { index, own_fields: Reflect.ownKeys(Object(output)).map((name, field_index) => {
      const descriptor = Object.getOwnPropertyDescriptor(output, name);
      return { field_index, name: typeof name === 'symbol' ? { kind: 'symbol', description: JSON.stringify(name.description ?? null) } : { kind: 'string', encoded: JSON.stringify(name) },
        present: true, enumerable: descriptor.enumerable, type: Object.hasOwn(descriptor, 'value') ? observedKind(descriptor.value) : 'accessor' };
    }),
      text: { own: Object.hasOwn(output, 'text'), truthy: Boolean(text), type: observedKind(text),
        encoded: typeof text === 'string' ? JSON.stringify(text) : null }, cost: outputTokens(text) };
  });
  const source = { maximum, entries };
  const allocation = evaluatorOperation('budget_plan', source);
  const previews = entries.map((entry, index) => {
    const planned = allocation[index];
    if (entry.absent) return { index, original_cost: 0, budget: planned.budget, sent_tokens: 0,
      result: { action: 'done', text_action: 'original', text: null } };
    const output = outputs[index];
    const observed = planned.action === 'original' ? { result: { action: 'done', text_action: 'original', text: null } }
      : preview(output.text, planned.budget, outputTokens(output.text), entry.text.encoded);
    const text = observed.result.text_action === 'original' ? output.text : observed.result.text;
    return { ...observed, index, original_cost: entries[index].cost, budget: planned.budget,
      sent_tokens: outputTokens(text), selected_encoded: typeof text === 'string' ? JSON.stringify(text) : null,
      selected_observation: observed.result.text_action === 'preview' ? observeJson(JSON.stringify(text)) : null };
  });
  const construction = { ...source, allocation, previews };
  const plan = evaluatorOperation('budget_finish', construction);
  return { construction, plan, outputs: outputs.map((output, index) => ({ ...output,
    text: plan[index].text_action === 'original' ? output.text : plan[index].text, preview: plan[index].preview })) };
}

export function budgetOutputs(outputs, maximum = evaluatorLimits.tool_output_tokens) {
  return budgetConstruction(outputs, maximum).outputs;
}

function contextConstruction(effect) {
  evaluatorOperation('context_select', { effect, phase: 'shape', observations: [] });
  const observations = Array.isArray(effect.history) ? effect.history.map((item, history_index) => ({
    history_index, content: item.content, text: stringifyJson(item.content) ?? '',
  })) : [];
  const source = { effect, observations };
  const selected = evaluatorOperation('context_select', source);
  const budgeted = selected.recent_tool_calls.map(call => budgetConstruction(call.outputs, evaluatorLimits.tool_output_tokens));
  const construction = { ...source, selected, budgeted: budgeted.map(value => ({ construction: value.construction, plan: value.plan })) };
  return { construction, context: evaluatorOperation('context_finish', construction) };
}

export function decisionContext(effect) {
  return contextConstruction(effect).context;
}

export function decisionRequest(effect, evaluator) {
  const policy = adaptivePolicy(effect.model.adaptive_reasoning);
  // Native policy admission precedes context work, as in the original API.
  evaluatorOperation('request', { effect, evaluator, policy, phase: 'policy', context: null });
  const { context, construction } = contextConstruction(effect);
  return evaluatorOperation('request', { effect, evaluator, policy, context, context_construction: construction });
}

export function validateDecision(reply, evaluator, policy) {
  return evaluatorOperation('decision', { reply, evaluator, policy });
}

function retryPlan(source) {
  let plan = evaluatorOperation('retry', source);
  switch (plan.action) {
    case 'observe_numeric':
    case 'observe_date': {
      let date, now;
      const milliseconds = plan.action === 'observe_numeric' ? Number(source.retry_after) * 1000
        : (date = Date.parse(source.retry_after)) - (now = Date.now());
      plan = evaluatorOperation('retry', { ...source, phase: 'observed', observation: {
        retry_after: source.retry_after, attempt: source.attempt, kind: plan.action,
        date: Number.isFinite(date) ? date : null, now: now ?? null,
        finite: Number.isFinite(milliseconds), milliseconds: Number.isFinite(milliseconds) ? milliseconds : null,
        minus_limit: String(milliseconds - 5000), minus_floor: String(milliseconds - 100),
      } });
      break;
    }
  }
  if (plan.action === 'fail') throw new Error(plan.error);
  return plan;
}

/** The host performs one already-committed observation, never selects a lease. */
export async function requestReasoning(effect, config, limits, { signal } = {}) {
  signal?.throwIfAborted();
  const policy = adaptivePolicy(effect.model.adaptive_reasoning);
  const publicConfig = { reasoning_evaluators: config.reasoning_evaluators,
    profiles: Object.fromEntries(Object.entries(config.profiles).map(([name, profile]) => [name, { provider: profile.provider }])) };
  const admitted = { effect, config: publicConfig, limits, policy };
  const evaluator = evaluatorOperation('request_admission', { ...admitted, phase: 'lookup' });
  const key = process.env[evaluator.api_key_env];
  evaluatorOperation('request_admission', { ...admitted, evaluator, phase: 'credential',
    observation: { present: Boolean(key), whitespace: /\s/.test(key ?? '') } });
  const deadline = signal ? AbortSignal.any([signal, AbortSignal.timeout(evaluator.timeout_ms)]) : AbortSignal.timeout(evaluator.timeout_ms);
  const request = decisionRequest(effect, evaluator);
  const body = stringifyJson(request);
  const bytes = Buffer.byteLength(body);
  evaluatorOperation('request_admission', { ...admitted, evaluator, request, body, phase: 'bytes', observation: { body, bytes } });
  evaluatorOperation('request_admission', { ...admitted, evaluator, request, body, phase: 'tokens', observation: { body, bytes, tokens: countTokens(body, tokenizerOptions) } });
  let attempt = 0;
  for (;;) {
    const original = { ...admitted, evaluator, request, attempt };
    retryPlan({ ...original, phase: 'attempt' });
    deadline.throwIfAborted();
    let response;
    try {
      response = await fetch(evaluator.endpoint, { method: 'POST', body, redirect: 'error', signal: deadline,
        headers: { 'content-type': 'application/json', accept: 'application/json', authorization: `Bearer ${key}` } });
    } catch (error) {
      deadline.throwIfAborted();
      const plan = retryPlan({ ...original, phase: 'network', type_error: error instanceof TypeError });
      await delay(plan.milliseconds, undefined, { signal: deadline });
      attempt = plan.next_attempt;
      continue;
    }
    const responseSource = { ...original, phase: 'response', ok: response.ok, status: response.status };
    const plan = retryPlan(responseSource);
    if (plan.action === 'cancel') {
      await response.body?.cancel();
      const source = { ...responseSource, phase: 'cancelled', plan };
      // Reading the header remains after cancellation and only for retry plans.
      const next = retryPlan({ ...source, retry_after: plan.after_cancel === 'retry' ? response.headers.get('retry-after') : null });
      await delay(next.milliseconds, undefined, { signal: deadline });
      attempt = next.next_attempt;
      continue;
    }
    let text, observation;
    try {
      text = await readText(response.body, evaluatorLimits.response_bytes);
      observation = observeJson(text);
      if (observation.error) throw new SyntaxError(observation.error);
    } catch { deadline.throwIfAborted(); throw new Error('Jev returned an invalid or oversized JSON response'); }
    deadline.throwIfAborted();
    return evaluatorOperation('decision', { ...original, mode: 'parsed', text, observation });
  }
}
