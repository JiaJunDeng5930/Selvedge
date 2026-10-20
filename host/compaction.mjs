import { boundary } from './public/model-boundary.mjs';
import { providerSession, prepareModelRequest, requestProviderJSON, requestProviderSSE, responseBody } from './providers.mjs';
import { compactionSettings } from './config.mjs';

async function measured(session, prepared, limits, options, window_tokens) {
  const { request, bytes } = prepared;
  const plan = boundary('backend.compaction_measurement_plan', { scope: session.scope, profile: session.profile,
    request, bytes, limits, window_tokens });
  if (plan.action === 'local') return plan;
  const body = boundary('backend.compaction_meter_request', { request });
  let response;
  try { response = await requestProviderJSON(session, '/input_tokens', await prepareModelRequest(body, session.home, limits), limits, options); }
  catch (error) {
    // DEFENSE: A Responses endpoint can reject the optional input_tokens route; native admission permits a UTF-8 bound only for readable requests.
    const fallback = boundary('backend.compaction_meter_fallback', {
      status: error.status, code: error.provider_code, request, bytes, scope: session.scope,
    });
    // DEFENSE: Authentication, network and non-route failures must not be hidden by a local token estimate.
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
  // DEFENSE: Credential/account rotation between selection and observation invalidates the old opaque context consumer.
  if (scope.scope_changed) return { ...scope, now: Date.now() };
  const request = boundary('backend.compaction_model_request', { effect, profile: session.profile });
  const settings = compactionSettings(config);
  const target = settings.targets.find(value => value.profile === effect.model.profile);
  const observation = await measured(session, await prepareModelRequest(request, home, limits), limits, options, target.window_tokens);
  return { ...observation, window_tokens: target.window_tokens,
    output_reserve_tokens: target.output_reserve_tokens, now: Date.now() };
}

// A committed effect describes one call. Cursor advancement and another call's
// ticket belong to harness/compaction and the owning feature, never this loop.
export async function requestCompaction(effect, config, home, limits, options = {}) {
  const session = await providerSession(effect, config, home, options);
  const scope = boundary('backend.compaction_scope_changed', { effect, scope: session.scope });
  // DEFENSE: Compaction cannot submit a previously selected opaque window after its credential/account consumer changes.
  if (scope.scope_changed) return scope;
  const call = boundary('backend.compaction_effect', { effect });
  const encoded = responseBody(call, session.profile);
  const request = effect.plan.method === 'native'
    ? boundary('backend.compaction_request', { request: encoded })
    : boundary('backend.compaction_portable_request', { effect, request: encoded });
  const prepared = await prepareModelRequest(request, home, limits);
  const observation = await measured(session, prepared, limits, options, effect.plan.window_tokens);
  if (boundary('backend.compaction_budget', { ...observation, plan: effect.plan }) === 'resize') {
    return { action: 'resize' };
  }
  if (effect.plan.method === 'native') {
    let response;
    try { response = await requestProviderJSON(session, '/compact', prepared, limits, options); }
    catch (error) {
      // DEFENSE: A Responses endpoint may omit the native compact route; the native feature can then select portable rebuilding explicitly.
      const observation = boundary('backend.compaction_native_failure', {
        status: error.status, code: error.provider_code,
      });
      // DEFENSE: Failures other than an admitted unsupported route remain compaction errors rather than requesting another method.
      if (observation.action !== 'native_unavailable') throw error;
      return observation;
    }
    return boundary('backend.compaction_native_result', { response, scope: session.scope });
  }
  // Dispatch the measured bytes through the same session. The native portable
  // request already fixes its output reserve and prohibits tools.
  let usage;
  const items = await requestProviderSSE(session, call, prepared, limits,
    { ...options, onDelta: () => {}, onObservation: observation => { usage = observation.usage; } });
  return boundary('backend.compaction_summary_result', { items, scope: session.scope, usage, plan: effect.plan });
}
