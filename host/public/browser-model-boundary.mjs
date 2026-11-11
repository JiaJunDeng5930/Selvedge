import { browserCall } from './generated/browser-model.mjs';
import { interactionCall, prepareInteraction, preparedInteractionCall, publishNativePicker } from './generated/interaction-model.mjs';
import { invoke, unwrapResult } from './model-boundary.mjs';
import { numberFromJsonToken, stringifyJson } from './json-tokens.mjs';

export const browser = (operation, source) => invoke(browserCall, operation, source);

const preparedOperations = new Set(['step', 'observe', 'accepts_element']);
let prepared = null;

export function presentNativePicker(state, world, environment, generation, ops) {
  if (prepared?.state !== state || prepared.world !== world || prepared.environment !== environment) return null;
  return publishNativePicker(stringifyJson({ generation }), prepared.token, numberFromJsonToken, ops);
}

export function interaction(operation, source = null) {
  if (!preparedOperations.has(operation)) return invoke(interactionCall, operation, source);
  const { state, world, environment, ...request } = source ?? {};
  // The app replaces state, world and physical environment snapshots as whole values.
  // Publication receipts and native inputs vary independently of those snapshots.
  const token = prepared && prepared.state === state && prepared.world === world && prepared.environment === environment
    ? prepared.token : prepareInteraction(stringifyJson({ state, world, environment }));
  // DEFENSE: An invalid snapshot needs the canonical error for the requested operation.
  if (token === null) return invoke(interactionCall, operation, source);
  const [envelope, nextToken] = preparedInteractionCall(operation, stringifyJson(request), token, numberFromJsonToken);
  const value = unwrapResult(envelope);
  prepared = { state: operation === 'step' ? value.state : state, world, environment, token: nextToken };
  return value;
}
