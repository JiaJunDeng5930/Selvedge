import { boundary } from './public/model-boundary.mjs';
import { decodeCloudReadinessAction, type JsonValue } from './generated/model-schema.ts';

/** The extracted controller chooses retries and deadlines; IO only supplies facts. */
export async function awaitCloudSsh(deadline: number, io: {
  now(): number;
  probe(timeout: number): Promise<{ exit_code: number; stderr: string }>;
  delay(milliseconds: number): Promise<void>;
}): Promise<void> {
  let observation: JsonValue = { kind: 'check', now: io.now() };
  for (;;) {
    const action = decodeCloudReadinessAction(boundary('control.resource.ssh', { deadline, observation }));
    switch (action.kind) {
      case 'probe': {
        const { exit_code, stderr } = await io.probe(Number(action.timeout));
        observation = { kind: 'result', now: io.now(), exit_code, stderr };
        break;
      }
      case 'delay':
        await io.delay(Number(action.milliseconds));
        observation = { kind: 'check', now: io.now() };
        break;
      case 'connected': return;
      // DEFENSE: A probe can exhaust the startup deadline or observe a missing required image program.
      case 'reject': throw new Error(action.message);
      default: { const unreachable: never = action; return unreachable; }
    }
  }
}
