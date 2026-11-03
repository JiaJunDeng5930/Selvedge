import { countTokens } from 'gpt-tokenizer/encoding/o200k_base';
import { setTimeout as delay } from 'node:timers/promises';
import { stringifyJson } from './codec.mjs';
import { readText } from './network.mjs';
import { adaptivePolicy } from './reasoning-config.mjs';
import { boundary } from './public/model-boundary.mjs';

const evaluatorResponseBytes = boundary('evaluator.contract', {}).response_bytes;
const tokenizerOptions = { disallowedSpecial: new Set() };

function evaluatorOperation(operation, source) {
  return boundary(`evaluator.${operation}`, source);
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
  const evaluator = evaluatorOperation('request_admission', { effect: { model: effect.model }, config: publicConfig, policy, phase: 'lookup' });
  const key = process.env[evaluator.api_key_env];
  evaluatorOperation('request_admission', { evaluator, phase: 'credential',
    observation: { present: Boolean(key), whitespace: /\s/.test(key ?? '') } });
  const deadline = signal ? AbortSignal.any([signal, AbortSignal.timeout(evaluator.timeout_ms)]) : AbortSignal.timeout(evaluator.timeout_ms);
  const request = evaluatorOperation('request', { effect, evaluator, policy });
  const body = stringifyJson(request);
  evaluatorOperation('request_admission', { body, limits, phase: 'bytes' });
  evaluatorOperation('request_admission', { phase: 'tokens', observation: { tokens: countTokens(body, tokenizerOptions) } });
  let attempt = 0;
  for (;;) {
    const original = { evaluator, attempt };
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
      const source = { ...responseSource, phase: 'cancelled' };
      // Reading the header remains after cancellation and only for retry plans.
      const next = retryPlan({ ...source, retry_after: plan.after_cancel === 'retry' ? response.headers.get('retry-after') : null });
      await delay(next.milliseconds, undefined, { signal: deadline });
      attempt = next.next_attempt;
      continue;
    }
    const text = await readText(response.body, evaluatorResponseBytes);
    deadline.throwIfAborted();
    return evaluatorOperation('decision', { evaluator, policy, text });
  }
}
