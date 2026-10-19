import { boundary } from './public/model-boundary.mjs';
import { setTimeout as delay } from 'node:timers/promises';

// Numeric observations preserve fractional values and non-finite conversion
// results as text; Bend selects the applicable branch and the final delay.
function retryObservation(policy, attempt, response, error, errorPresent, signal) {
  const header = response?.headers.get('retry-after') ?? null;
  const number = Number(header);
  const numericMilliseconds = number * 1000;
  const date = Date.parse(header);
  const now = Date.now();
  const elapsed = date - now;
  const base = policy.delays_ms[attempt];
  return {
    limits: policy, policy, attempt,
    response_present: response !== undefined,
    status: response?.status ?? null,
    retry_after: header,
    error_present: errorPresent,
    error: { name: error?.name, message: error?.message },
    isTypeError: error instanceof TypeError,
    aborted: signal.aborted,
    abort_reason: { name: signal.reason?.name, message: signal.reason?.message },
    now,
    arithmetic: {
      number: String(number), numeric_ms: String(numericMilliseconds),
      date: String(date), date_minus_now: String(elapsed), base: String(base),
      numeric_minus_budget: String(numericMilliseconds - policy.max_retry_after_ms),
      date_minus_budget: String(elapsed - policy.max_retry_after_ms),
      numeric_minus_base: String(numericMilliseconds - base),
      date_minus_base: String(elapsed - base),
    },
  };
}

// One attempt observes transport; native retry construction determines the
// action. An exposed SSE stream never enters this headers-only executor again.
export async function requestHeaders(send, policy, signal, onRetry) {
  for (let attempt = 0; ; attempt++) {
    signal.throwIfAborted();
    let response;
    let error;
    let errorPresent = false;
    try { response = await send(); }
    // DEFENSE: Fetch can reject before headers on connection failure or cancellation; the native policy admits only bounded pre-stream retries.
    catch (observed) { error = observed; errorPresent = true; }
    const step = boundary('backend.retry', retryObservation(policy, attempt, response, error, errorPresent, signal));
    if (step.cancel) await response.body?.cancel();
    switch (step.action) {
      case 'stop': return response;
      // DEFENSE: Cancellation while fetching must terminate this request before any retry delay.
      case 'abort': signal.throwIfAborted(); break;
      // DEFENSE: Permanent errors, exhausted attempts and excessive Retry-After must surface as request failures.
      case 'fail':
        if (step.cause) throw new Error(step.message, { cause: error });
        throw new Error(step.message);
      case 'retry':
        // DEFENSE: Only observed connection failures and the committed transient HTTP status policy can reach an abortable retry.
        onRetry(step.notice);
        await delay(step.delay_ms, undefined, { signal });
        break;
    }
  }
}

export function prepareModelRequest(effect) {
  return boundary('backend.prepare', effect);
}
