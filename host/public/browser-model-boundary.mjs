import { browserCall } from './generated/browser-model.mjs';
import { interactionCall } from './generated/interaction-model.mjs';
import { invoke } from './model-boundary.mjs';

export const browser = (operation, source) => invoke(browserCall, operation, source);
export const interaction = (operation, source = null) => invoke(interactionCall, operation, source);
