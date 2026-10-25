import { boundary } from './public/model-boundary.mjs';
import { decodeCloudReadinessAction, decodeCloudReadinessTransition, type JsonValue } from './generated/model-schema.ts';

/** The extracted controller chooses retries and deadlines; IO only supplies facts. */
export async function awaitCloudSsh(deadline: number, io: {
  now(): number;
  probe(timeout: number): Promise<{ exit_code: number; stderr: string }>;
  delay(milliseconds: number): Promise<void>;
}): Promise<void> {
  let state: JsonValue = { phase: 'probe', deadline };
  let observation: JsonValue = { kind: 'begin', now: io.now() };
  for (;;) {
    const plan = decodeCloudReadinessTransition(boundary('control.resource.ssh', { state, observation }));
    state = plan.state;
    for (const raw of plan.actions) {
      const action = decodeCloudReadinessAction(raw);
      switch (action.kind) {
        case 'probe': {
          const result = await io.probe(Number(action.timeout));
          observation = { kind: 'result', now: io.now(), ...result };
          break;
        }
        case 'delay':
          await io.delay(Number(action.milliseconds));
          observation = { kind: 'wake', now: io.now() };
          break;
        case 'connected': return;
        // DEFENSE: A probe can exhaust the startup deadline or observe a missing required image program.
        case 'reject': throw new Error(action.message);
        default: { const unreachable: never = action; return unreachable; }
      }
    }
  }
}
