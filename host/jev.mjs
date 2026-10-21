import { encode, decode, countTokens } from 'gpt-tokenizer/encoding/o200k_base';
import { setTimeout as delay } from 'node:timers/promises';
import { stringifyJson } from './codec.mjs';
import { readText } from './network.mjs';
import { adaptivePolicy } from './reasoning-config.mjs';
import { boundary } from './public/model-boundary.mjs';

const evaluatorContract = boundary('evaluator.contract', {});
const evaluatorToolOutputTokens = evaluatorContract.tool_output_tokens;
const evaluatorResponseBytes = evaluatorContract.response_bytes;
const tokenizerOptions = { disallowedSpecial: new Set() };

function evaluatorOperation(operation, source) {
  return boundary(`evaluator.${operation}`, source);
}

// This is a local tokenizer budget, not a claim about Jev's private tokenizer.
export function outputTokens(text) {
  return text ? Math.max(countTokens(text, tokenizerOptions), countTokens(JSON.stringify(text), tokenizerOptions)) : 0;
}

function preview(text, budget, originalCost) {
  const source = { text, budget, original_cost: originalCost };
  let tokens;
  let completion = { ...source }, completionKind = 'start';
  let state = evaluatorOperation('preview_start', completion);
  while (state.action !== 'done') {
    switch (state.action) {
      case 'marker':
        source.marker_cost = outputTokens(state.text);
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
    }
  }
  return { source, result: state, completion_kind: completionKind, completion };
}

function budgetConstruction(outputs, maximum) {
  const entries = outputs.map((output, index) => {
    const text = output.text;
    return { index, text: { truthy: Boolean(text), type: 'string', encoded: JSON.stringify(text) }, cost: outputTokens(text) };
  });
  const source = { maximum, entries };
  const allocation = evaluatorOperation('budget_plan', source);
  const previews = entries.map((entry, index) => {
    const planned = allocation[index];
    const output = outputs[index];
    const observed = planned.action === 'original' ? { result: { action: 'done', text_action: 'original', text: null } }
      : preview(output.text, planned.budget, outputTokens(output.text));
    const text = observed.result.text_action === 'original' ? output.text : observed.result.text;
    return { ...observed, index, original_cost: entries[index].cost, budget: planned.budget,
      sent_tokens: outputTokens(text), selected_encoded: JSON.stringify(text) };
  });
  const construction = { ...source, allocation, previews };
  const plan = evaluatorOperation('budget_finish', construction);
  return { construction, plan };
}

function contextConstruction(effect) {
  evaluatorOperation('context_select', { effect, phase: 'shape', observations: [] });
  const observations = effect.history.map((item, history_index) => ({
    history_index, content: item.content, text: stringifyJson(item.content) ?? '',
  }));
  const source = { effect, observations };
  const selected = evaluatorOperation('context_select', source);
  const budgeted = selected.recent_tool_calls.map(call => budgetConstruction(call.outputs, evaluatorToolOutputTokens));
  const construction = { ...source, selected, budgeted: budgeted.map(value => ({ construction: value.construction, plan: value.plan })) };
  return { construction, context: evaluatorOperation('context_finish', construction) };
}

export function decisionRequest(effect, evaluator) {
  const policy = adaptivePolicy(effect.model.adaptive_reasoning);
  // Reject invalid adaptive policy before constructing evaluator context.
  evaluatorOperation('request', { effect, evaluator, policy, phase: 'policy', context: null });
  const { context, construction } = contextConstruction(effect);
  return evaluatorOperation('request', { effect, evaluator, policy, context, context_construction: construction });
}

function retryPlan(source) {
  const plan = evaluatorOperation('retry', { ...source, now: Date.now() });
  // DEFENSE: An evaluator retry can exceed its attempt/deadline budget or return an excessive Retry-After; the admitted plan must fail visibly.
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
      // DEFENSE: Fetch can fail before evaluator response headers; only admitted connection failures receive the bounded same-provider retry.
      deadline.throwIfAborted();
      const plan = retryPlan({ ...original, phase: 'network', type_error: error instanceof TypeError });
      await delay(plan.milliseconds, undefined, { signal: deadline });
      attempt = plan.next_attempt;
      continue;
    }
    const responseSource = { ...original, phase: 'response', ok: response.ok, status: response.status };
    const plan = retryPlan(responseSource);
    // DEFENSE: Transient HTTP responses have unread bodies; cancel before an admitted retry delay, and surface permanent/exhausted failures.
    if (plan.action === 'cancel') {
      await response.body?.cancel();
      const source = { ...responseSource, phase: 'cancelled', plan };
      // Reading the header remains after cancellation and only for retry plans.
      const next = retryPlan({ ...source, retry_after: plan.after_cancel === 'retry' ? response.headers.get('retry-after') : null });
      await delay(next.milliseconds, undefined, { signal: deadline });
      attempt = next.next_attempt;
      continue;
    }
    const text = await readText(response.body, evaluatorResponseBytes);
    deadline.throwIfAborted();
    return evaluatorOperation('decision', { ...original, mode: 'parsed', text });
  }
}
