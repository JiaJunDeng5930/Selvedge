/** Interpret the native policy without exposing opaque credentials to the model. */
export function interpretCredential(token, plan, duplicates) {
  if (!plan || plan.operation !== 'base64url-bearer' ||
      !Number.isSafeInteger(plan.minimum) || !Number.isSafeInteger(plan.maximum) ||
      plan.minimum < 0 || plan.maximum < plan.minimum || typeof plan.alphabet !== 'string' ||
      typeof plan.distinct !== 'boolean' || typeof plan.prefix !== 'string') {
    throw new TypeError('Unsupported opaque credential plan');
  }
  if (typeof token !== 'string' || token.length < plan.minimum || token.length > plan.maximum ||
      [...token].some(character => !plan.alphabet.includes(character)) ||
      (plan.distinct && duplicates?.has(token))) return null;
  if (plan.distinct) duplicates?.add(token);
  return Buffer.from(plan.prefix + token);
}
