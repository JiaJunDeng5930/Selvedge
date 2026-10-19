/** Interpret the native policy without exposing opaque credentials to the model. */
export function interpretCredential(token, plan, duplicates) {
  // DEFENSE: Configured credentials can be missing, contain non-Bearer bytes, or repeat another connection's token.
  if (typeof token !== 'string' || token.length < plan.minimum || token.length > plan.maximum ||
      [...token].some(character => !plan.alphabet.includes(character)) ||
      (plan.distinct && duplicates?.has(token))) return null;
  if (plan.distinct) duplicates?.add(token);
  return Buffer.from(plan.prefix + token);
}
