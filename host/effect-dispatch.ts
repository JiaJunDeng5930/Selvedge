import { decodeEffect, type Effect } from './generated/model-schema.ts';
import { boundary } from './public/model-boundary.mjs';
import { naturalKey } from './public/json-tokens.mjs';

type Of<K extends Effect['kind']> = Extract<Effect, { kind: K }>;
type ImmediateKind = 'reset_model_session' | 'plugin_events' | 'cancel' | 'cancel_ticket' |
  'continue' | 'compaction_clock' | 'compaction_cancel' | 'chatgpt_cancel';
export type RunningEffect = Exclude<Effect, { kind: ImmediateKind }>;

export interface DispatchPrimitives {
  reset(effect: Of<'reset_model_session'>): void;
  notifyPlugins(effect: Of<'plugin_events'>): void;
  cancelTask(effect: Of<'cancel'>): void;
  cancelKey(effect: Of<'cancel_ticket' | 'compaction_cancel' | 'chatgpt_cancel'>): void;
  continue(): void;
  clock(effect: Of<'compaction_clock'>): void;
  start(effect: RunningEffect): void;
}
function unreachable(effect: never): never {
  throw new TypeError('Unregistered extracted effect');
}

/** Every admitted effect constructor has one physical interpreter. */
export function dispatchEffect(input: unknown, io: DispatchPrimitives): number {
  const effect = decodeEffect(input);
  switch (effect.kind) {
    case 'reset_model_session': io.reset(effect); return 0;
    case 'plugin_events': io.notifyPlugins(effect); return effect.events.length;
    case 'cancel': io.cancelTask(effect); return 0;
    case 'cancel_ticket': case 'compaction_cancel': case 'chatgpt_cancel': io.cancelKey(effect); return 0;
    case 'continue': io.continue(); return 0;
    case 'compaction_clock': io.clock(effect); return 0;
    case 'worktree_create': case 'worktree_archive': case 'observe_context': case 'chatgpt_exec':
    case 'board_text': case 'task_title': case 'approval': case 'reasoning': case 'context_scope':
    case 'context_measure': case 'context_compaction': case 'model': case 'hook': case 'after_hook':
    case 'tool': io.start(effect); return 0;
    default: return unreachable(effect);
  }
}

export interface PerformPrimitives {
  workspace(effect: Of<'worktree_create' | 'worktree_archive'>): Promise<void>;
  context(effect: Of<'observe_context'>): Promise<unknown>;
  chatgpt(effect: Of<'chatgpt_exec'>): Promise<unknown>;
  text(effect: Of<'board_text' | 'task_title'>): Promise<unknown>;
  approval(effect: Of<'approval'>): Promise<unknown>;
  reasoning(effect: Of<'reasoning'>): Promise<unknown>;
  compaction(effect: Of<'context_scope' | 'context_measure' | 'context_compaction'>): Promise<unknown>;
  model(effect: Of<'model'>): Promise<unknown>;
  hook(effect: Of<'hook'>): Promise<unknown>;
  afterHook(effect: Of<'after_hook'>): Promise<unknown>;
  tool(effect: Of<'tool'>): Promise<unknown>;
}
export type Performed = { kind: 'settled' } | { kind: 'completion'; input: unknown };
export async function performEffect(effect: Effect, io: PerformPrimitives): Promise<Performed> {
  let result: unknown;
  switch (effect.kind) {
    case 'worktree_create': case 'worktree_archive':
      await io.workspace(effect); return { kind: 'settled' };
    case 'observe_context': result = await io.context(effect); break;
    case 'chatgpt_exec': result = await io.chatgpt(effect); break;
    case 'board_text': case 'task_title': result = await io.text(effect); break;
    case 'approval': result = await io.approval(effect); break;
    case 'reasoning': result = await io.reasoning(effect); break;
    case 'context_scope': case 'context_measure': case 'context_compaction': result = await io.compaction(effect); break;
    case 'model': result = await io.model(effect); break;
    case 'hook': result = await io.hook(effect); break;
    case 'after_hook': result = await io.afterHook(effect); break;
    case 'tool': result = await io.tool(effect); break;
    case 'reset_model_session': case 'plugin_events': case 'cancel': case 'cancel_ticket':
    case 'continue': case 'compaction_clock': case 'compaction_cancel': case 'chatgpt_cancel':
      throw new TypeError('An immediate effect cannot run as an asynchronous operation');
    default: return unreachable(effect);
  }
  return { kind: 'completion', input: boundary('effect.completion', { effect, result }) };
}

export function compactionOperation(input: Of<'context_scope' | 'context_measure' | 'context_compaction'>): 'observe' | 'compact' {
  switch (input.kind) {
    case 'context_scope': case 'context_measure': return 'observe';
    case 'context_compaction': return 'compact';
    default: return unreachable(input);
  }
}
export function workspaceOperation(input: Of<'worktree_create' | 'worktree_archive'>): 'create' | 'archive' {
  switch (input.kind) {
    case 'worktree_create': return 'create';
    case 'worktree_archive': return 'archive';
    default: return unreachable(input);
  }
}
export function modelEffect(effect: Effect): Of<'model'> | undefined {
  return effect.kind === 'model' ? effect : undefined;
}
export function workspaceEffect(effect: Effect): Of<'worktree_create' | 'worktree_archive'> | undefined {
  return effect.kind === 'worktree_create' || effect.kind === 'worktree_archive' ? effect : undefined;
}

export function clockDelay(effect: Of<'compaction_clock'>, now: number): number {
  const remaining = BigInt(naturalKey(effect.deadline)) - BigInt(now);
  return remaining <= 0n ? 0 : Number(remaining > 2147483647n ? 2147483647n : remaining);
}
