import { bendValue, bendTag } from './bend-value.mjs';

export function appearanceObservation(storage) {
  let stored = null;
  try { stored = storage.getItem('selvedge-appearance'); } catch {}
  return bendValue('interaction/MODEL.AppearanceRestored', {
    stored: stored === null ? bendValue('None') : bendValue('Some', { value: stored }),
  });
}

export function persistAppearance(storage, appearance) {
  storage.setItem('selvedge-appearance', bendTag(appearance));
}
