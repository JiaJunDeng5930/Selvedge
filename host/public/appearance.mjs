import { bendValue, bendTag } from './bend-value.mjs';

export function appearanceObservation(storage) {
  const stored = storage.getItem('selvedge-appearance');
  return bendValue('interaction/MODEL.AppearanceRestored', {
    stored: stored === null ? bendValue('None') : bendValue('Some', { value: stored }),
  });
}

export function persistAppearance(storage, appearance) {
  storage.setItem('selvedge-appearance', bendTag(appearance));
}
