import { boundary } from './public/model-boundary.mjs';
import { providerSession, requestProviderJSON, requestModel, responseBody } from './providers.mjs';
import { compactionSettings } from './config.mjs';
import { stringifyJson } from './codec.mjs';

function hasOpaqueContent(value) {
  if (value === null || typeof value !== 'object') return false;
  if (typeof value.encrypted_content === 'string' && value.encrypted_content.length) return true;
  return Object.values(value).some(hasOpaqueContent);
}

async function measured(session, request, limits, options, window_tokens) {
  const plaintext = !hasOpaqueContent(request);
  const bytes = Buffer.byteLength(stringifyJson(request));
  const plan = boundary('backend.compaction_measurement_plan', { scope: session.scope,
    bytes, limits, window_tokens, plaintext });
  if (plan.action === 'local') return plan;
  const body = boundary('backend.compaction_meter_request', { request });
  let response;
  try { response = await requestProviderJSON(session, '/input_tokens', body, limits, options); }
  catch (error) {
    const fallback = boundary('backend.compaction_meter_fallback', {
      status: error.status, code: error.provider_code, plaintext, bytes, scope: session.scope,
    });
    if (fallback.action !== 'local') throw error;
    return fallback;
  }
  return boundary('backend.compaction_meter_result', { response, scope: session.scope });
}

// Meter exactly the target-encoded request, including tools and opaque native
// items. Ciphertext byte or tokenizer length is never treated as input tokens.
export async function observeModelRequest(effect, config, home, limits, options = {}) {
  const session = await providerSession(effect, config, home, options);
  if (effect.scope_only || effect.kind === 'context_scope') return { scope: session.scope, now: Date.now() };
  const scope = boundary('backend.compaction_scope_changed', { effect, scope: session.scope });
  if (scope.scope_changed) return { ...scope, now: Date.now() };
  const request = boundary('backend.compaction_model_request', { effect, profile: session.profile });
  const settings = compactionSettings(config);
  const target = settings.targets.find(value => value.profile === effect.model.profile);
  const observation = await measured(session, request, limits, options, target.window_tokens);
  return { ...observation, window_tokens: target.window_tokens,
    output_reserve_tokens: target.output_reserve_tokens, now: Date.now() };
}

// A committed effect describes one call. Cursor advancement and another call's
// ticket belong to harness/compaction and the owning feature, never this loop.
export async function requestCompaction(effect, config, home, limits, options = {}) {
  const session = await providerSession(effect, config, home, options);
  const scope = boundary('backend.compaction_scope_changed', { effect, scope: session.scope });
  if (scope.scope_changed) return scope;
  const call = boundary('backend.compaction_effect', { effect });
  const encoded = responseBody(call, session.profile);
  const request = effect.plan.method === 'native'
    ? boundary('backend.compaction_request', { request: encoded })
    : boundary('backend.compaction_portable_request', { effect, request: encoded });
  const observation = await measured(session, request, limits, options, effect.plan.window_tokens);
  if (boundary('backend.compaction_budget', { ...observation, plan: effect.plan }) === 'resize') {
    return { action: 'resize' };
  }
  if (effect.plan.method === 'native') {
    let response;
    try { response = await requestProviderJSON(session, '/compact', request, limits, options); }
    catch (error) {
      const observation = boundary('backend.compaction_native_failure', {
        status: error.status, code: error.provider_code,
      });
      if (observation.action !== 'native_unavailable') throw error;
      return observation;
    }
    return boundary('backend.compaction_native_result', { response, scope: session.scope });
  }
  // requestModel performs the ordinary SSE transport and preserves its existing
  // header retry/cancellation behavior. The native plan prohibits tools.
  let usage;
  const items = await requestModel({ ...call, max_output_tokens: effect.plan.output_reserve_tokens }, config, home, limits,
    { ...options, signal: session.lifetime, onDelta: () => {}, onSnapshot: () => {}, onObservation: observation => { usage = observation.usage; } });
  return boundary('backend.compaction_summary_result', { items, scope: session.scope, usage, plan: effect.plan });
}
