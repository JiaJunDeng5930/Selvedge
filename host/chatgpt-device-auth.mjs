import { setTimeout as sleep } from 'node:timers/promises';
import { stringifyJson } from './codec.mjs';
import { readText } from './network.mjs';
import { boundary } from './public/model-boundary.mjs';

const contract = boundary('account.contract', {});

async function deviceReply(profile, plan, { signal, poll = false }) {
  const timeout = AbortSignal.timeout(profile.timeout_ms ?? contract.default.timeout_ms);
  const lifetime = signal ? AbortSignal.any([signal, timeout]) : timeout;
  let response;
  try {
    response = await fetch(plan.url, { method: 'POST', headers: { 'content-type': 'application/json' },
      body: stringifyJson(plan.body), signal: lifetime, redirect: 'error' });
  } catch {
    // DEFENSE: Fetch errors can contain transport details. Preserve caller cancellation and sanitize other failures.
    signal?.throwIfAborted();
    throw new Error('Could not reach ChatGPT device authorization');
  }
  if (!response.ok) {
    // DEFENSE: The protocol uses only the status of non-success responses.
    // Cancel the unused body without letting stream errors replace that status.
    await response.body?.cancel().catch(() => {});
  }
  if (boundary('account.device_status', { status: response.status, poll })) return null;
  try {
    return await readText(response.body, contract.maximum);
  } catch {
    // DEFENSE: Oversized, invalid UTF-8 or interrupted responses may contain device secrets.
    signal?.throwIfAborted();
    throw new Error('Invalid ChatGPT device authorization response');
  }
}

export async function requestDeviceCode(profile, { signal } = {}) {
  const issuer = new URL(profile.issuer).origin;
  const plan = boundary('account.device_request', { issuer });
  const text = await deviceReply(profile, plan, { signal });
  signal?.throwIfAborted();
  return boundary('account.device_challenge', { issuer, text });
}

function remainingPollTime(expiresAt) {
  const remaining = expiresAt - Date.now();
  // DEFENSE: A pending approval can expire while its request or delay is in flight.
  if (remaining <= 0) throw new DOMException('ChatGPT device authorization timed out', 'TimeoutError');
  return remaining;
}

export async function pollDeviceCode(profile, challenge, { signal, expiresAt }) {
  const issuer = new URL(profile.issuer).origin;
  const plan = boundary('account.device_poll_request', { issuer, challenge });
  const deadline = AbortSignal.timeout(remainingPollTime(expiresAt));
  const lifetime = signal ? AbortSignal.any([signal, deadline]) : deadline;
  for (;;) {
    lifetime.throwIfAborted();
    remainingPollTime(expiresAt);
    const text = await deviceReply(profile, plan, { signal: lifetime, poll: true });
    const remaining = remainingPollTime(expiresAt);
    lifetime.throwIfAborted();
    if (text !== null) {
      const authorization = boundary('account.device_authorization', { text });
      return { ...authorization, redirectUri: plan.redirectUri };
    }
    try {
      await sleep(Math.min(challenge.interval_ms, remaining), undefined, { signal: lifetime });
    } catch (error) {
      // DEFENSE: An expired or cancelled delay reports the signal's reason, as a pending fetch does.
      lifetime.throwIfAborted();
      throw error;
    }
  }
}
