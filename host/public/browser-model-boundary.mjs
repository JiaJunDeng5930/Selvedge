import { browserCall } from './generated/browser-model.mjs';
import { interactionCall, prepareInteraction, rebaseInteraction, preparedInteractionCall, publishNativePicker, publishNativeStream } from './generated/interaction-model.mjs';
import { invoke, numberText, unwrapResult } from './model-boundary.mjs';
import { numberFromJsonToken, parseJson, stringifyJson } from './json-tokens.mjs';

export const browser = (operation, source) => invoke(browserCall, operation, source);

const preparedOperations = new Set(['step', 'observe', 'accepts_element']);
let prepared = null;
const structuredJson = value => parseJson(stringifyJson(value));

export function presentNative(mode, state, world, environment, generation, ops) {
  if (prepared?.state !== state || prepared.world !== world || prepared.environment !== environment) return null;
  const publish = mode === 'stream' ? publishNativeStream : publishNativePicker;
  return publish(stringifyJson({ generation }), prepared.token, numberFromJsonToken, ops);
}

export function interaction(operation, source = null) {
  if (!preparedOperations.has(operation)) return invoke(interactionCall, operation, source);
  const { state, world, environment, ...request } = source ?? {};
  // The app replaces state, world and physical environment snapshots as whole values.
  // Publication receipts and native inputs vary independently of those snapshots.
  let token;
  if (prepared && prepared.state === state) {
    token = prepared.world === world && prepared.environment === environment
      ? prepared.token : rebaseInteraction(structuredJson({ world, environment }), prepared.token, numberText);
  } else {
    token = prepareInteraction(structuredJson({ state, world, environment }), numberText);
  }
  // DEFENSE: An invalid snapshot needs the canonical error for the requested operation.
  if (token === null) return invoke(interactionCall, operation, source);
  const [envelope, nextToken] = preparedInteractionCall(operation, structuredJson(request), token, numberText, numberFromJsonToken);
  const value = unwrapResult(envelope);
  prepared = { state: operation === 'step' ? value.state : state, world, environment, token: nextToken };
  return value;
}
