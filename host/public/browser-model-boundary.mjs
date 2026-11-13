import { browserCall, publishBrowserDocument } from './generated/browser-model.mjs';
import { interactionCall, prepareInteraction, rebaseInteraction, preparedInteractionCall,
  publishNativeDocument, publishNativeRegion, publishNativeStream } from './generated/interaction-model.mjs';
import { invoke, numberText, unwrapResult } from './model-boundary.mjs';
import { numberFromJsonToken, parseJson, stringifyJson } from './json-tokens.mjs';

export const browser = (operation, source) => invoke(browserCall, operation, source);
export const presentBrowserDocument = (operation, source, ops) =>
  publishBrowserDocument(operation, stringifyJson(source), numberFromJsonToken, ops);

const preparedOperations = new Set(['step', 'accepts_element', 'update_session', 'restore_update_session']);
const nativePresentations = { document: publishNativeDocument, region: publishNativeRegion, stream: publishNativeStream };
let prepared = null;
const structuredJson = value => parseJson(stringifyJson(value));

export function presentNative(mode, state, world, environment, generation, ops) {
  const token = prepareSnapshot(state, world, environment);
  if (token === null) return null;
  const output = nativePresentations[mode](stringifyJson({ generation }), token, numberFromJsonToken, ops);
  if (output?.token) output.commit = () => { prepared = { state, world, environment, token: output.token }; };
  return output;
}

function prepareSnapshot(state, world, environment) {
  // The app replaces state, world and physical environment snapshots as whole values.
  // Publication receipts and native inputs vary independently of those snapshots.
  if (prepared && prepared.state === state) {
    return prepared.world === world && prepared.environment === environment
      ? prepared.token : rebaseInteraction(structuredJson({ world, environment }), prepared.token, numberText);
  }
  return prepareInteraction(structuredJson({ state, world, environment }), numberText);
}

export function interaction(operation, source = null) {
  if (!preparedOperations.has(operation)) return invoke(interactionCall, operation, source);
  const { state, world, environment, ...request } = source ?? {};
  const token = prepareSnapshot(state, world, environment);
  // DEFENSE: An invalid snapshot needs the canonical error for the requested operation.
  if (token === null) return invoke(interactionCall, operation, source);
  const [envelope, nextToken] = preparedInteractionCall(operation, structuredJson(request), token, numberText, numberFromJsonToken);
  const value = unwrapResult(envelope);
  const current = operation === 'step' ? value.state : operation === 'restore_update_session' ? value : state;
  prepared = { state: current, world, environment, token: nextToken };
  return value;
}
