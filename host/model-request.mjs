import { boundary } from './public/model-boundary.mjs';
import { setTimeout as delay } from 'node:timers/promises';

// Transport supplies the raw header and current time; the extracted semantics computes delays.
function retryObservation(policy, attempt, response, error, errorPresent, signal) {
  const header = response?.headers.get('retry-after') ?? null;
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
    now: Date.now(),
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
