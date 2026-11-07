import type { DomainNatural } from './generated/model-schema.ts';
import type { RunningEffect } from './effect-dispatch.ts';
import { naturalKey } from './public/json-tokens.mjs';
import type { dispatchControlResult } from './model-api.ts';

declare const handleBrand: unique symbol;
export type EffectHandle = Readonly<{ generation: DomainNatural; [handleBrand]: true }>;
type ControlResult = ReturnType<typeof dispatchControlResult>;
type Outcome = 'input_limit' | 'output_limit' | 'rejected' | 'uncertain';
type Control = (observation: unknown) => ControlResult;
export interface ActiveEffect {
  effect: RunningEffect;
  controller: AbortController;
  handle: EffectHandle;
  promise: Promise<unknown>;
}
export interface CommitResult {
  reply: { ok: true; result: unknown } | { ok: false; error: { code: string; message: string } };
}

/** Install the complete active record before the interpreter can observe it. */
export function launchEffect(control: Control, active: Map<string, ActiveEffect>, effect: RunningEffect,
  run: (handle: EffectHandle, signal: AbortSignal) => Promise<unknown>): Promise<unknown> {
  const generation = control({ kind: 'launch', effect }).starts[0];
  // DEFENSE: Startup reconciliation may reach a dispatcher retired by a journal failure.
  if (generation === undefined) return Promise.reject(new Error('Effect dispatcher is retired'));
  const handle = { generation } as EffectHandle;
  const key = naturalKey(generation);
  const controller = new AbortController();
  // The microtask cannot execute run until its rejecting promise is installed.
  const promise = Promise.resolve().then(() => run(handle, controller.signal)).finally(() => {
    control({ kind: 'complete', generation: handle.generation });
    active.delete(key);
  });
  active.set(key, { effect, controller, handle, promise });
  return promise;
}

/** The Dispatch model owns admission, one reduced retry, and handle retirement. */
export async function settleEffect(control: Control, handle: EffectHandle, initial: unknown,
  execute: (input: unknown) => Promise<CommitResult>, failure: () => Promise<unknown> | unknown,
  classifyError: (error: unknown) => Outcome): Promise<CommitResult> {
  let input = initial;
  for (;;) {
    let result: CommitResult | undefined;
    let error: unknown;
    let outcome: Outcome;
    try {
      result = await execute(input);
      // A successful journal acknowledgement remains accepted even if shutdown has begun.
      if (result.reply.ok) return result;
      outcome = result.reply.error.code === 'output_limit' ? 'output_limit' : 'rejected';
    } catch (caught) {
      error = caught;
      outcome = classifyError(caught);
    }
    const actions = control({ kind: 'settlement', generation: handle.generation, outcome });
    if (actions.retryFailure) {
      input = await failure();
      continue;
    }
    // DEFENSE: A rejected reduced callback or an unknown commit cannot produce a second completion.
    throw error ?? new Error(result?.reply.ok === false
      ? `Effect settlement rejected: ${result.reply.error.message}` : 'Effect settlement was retired');
  }
}
