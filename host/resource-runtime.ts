import { decodeLocalResourceTransition, decodeCloudResourceTransition, type JsonValue } from './generated/model-schema.ts';

type State = JsonValue;
type Transition = (state: State, observation: JsonValue) => unknown;
type Result = { receipt: State; errors: Error[] };
interface LocalPrimitives {
  persist(state: State): Promise<void>;
  local_reserve(state: State): Promise<JsonValue>;
  local_create(state: State): Promise<JsonValue>;
  local_prepare(state: State): Promise<JsonValue>;
  local_classify(state: State): Promise<JsonValue>;
  local_release(state: State): Promise<JsonValue>;
  local_remove(state: State): Promise<JsonValue>;
  local_archive(state: State): Promise<JsonValue>;
  local_observe(state: State): Promise<JsonValue>;
}

/** The decoded action selects one physical primitive; its acknowledgement is
 * admitted by the phase-specific Gallina controller before another IO starts. */
export async function runLocalResourceController(initial: unknown, transition: Transition, io: LocalPrimitives): Promise<Result> {
  let plan = decodeLocalResourceTransition(initial);
  const errors: Error[] = [];
  for (;;) {
    const { state, action } = plan;
    let observation: JsonValue;
    if (action === 'finish') return { receipt: state, errors };
    try {
      switch (action) {
        case 'persist': await io.persist(state); observation = { kind: 'persisted' }; break;
        case 'local_reserve': observation = await io.local_reserve(state); break;
        case 'local_create': observation = await io.local_create(state); break;
        case 'local_prepare': observation = await io.local_prepare(state); break;
        case 'local_classify': observation = await io.local_classify(state); break;
        case 'local_release': observation = await io.local_release(state); break;
        case 'local_remove': observation = await io.local_remove(state); break;
        case 'local_archive': observation = await io.local_archive(state); break;
        case 'local_observe': observation = await io.local_observe(state); break;
        default: { const unreachable: never = action; throw new TypeError(`Unknown local resource primitive: ${unreachable}`); }
      }
    } catch (error) {
      errors.push(error instanceof Error ? error : new Error(String(error)));
      observation = { kind: action === 'persist' ? 'persistence_failed' : 'local_failed' };
    }
    plan = decodeLocalResourceTransition(transition(state, observation));
  }
}

interface CloudPrimitives {
  persist(state: State): Promise<void>;
  allocate(state: State): Promise<JsonValue>;
  prepare(state: State): Promise<JsonValue>;
  credentials(state: State): Promise<JsonValue>;
  scan(state: State): Promise<JsonValue>;
  terminate(state: State): Promise<JsonValue>;
}
export async function runCloudResourceController(initial: unknown, transition: Transition, io: CloudPrimitives) {
  let plan = decodeCloudResourceTransition(initial);
  const errors: string[] = [];
  for (;;) {
    const { state, action } = plan;
    // DEFENSE: An observation with no transition from the current cloud phase grants no physical action.
    if (action == null) throw new TypeError('Cloud resource observation did not select an action');
    let observation: JsonValue;
    if (action === 'finish') return { receipt: state, errors };
    try {
      switch (action) {
        case 'persist': await io.persist(state); observation = { kind: 'persisted' }; break;
        case 'allocate': observation = await io.allocate(state); break;
        case 'prepare': observation = await io.prepare(state); break;
        case 'credentials': observation = await io.credentials(state); break;
        case 'scan': observation = await io.scan(state); break;
        case 'terminate': observation = await io.terminate(state); break;
        default: { const unreachable: never = action; throw new TypeError(`Unknown cloud resource primitive: ${unreachable}`); }
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      switch (action) {
        case 'persist': errors.push(`Could not persist cloud resource: ${message}`); observation = { kind: 'persistence_failed' }; break;
        case 'allocate': errors.push(`Allocation outcome unknown: ${message}`); observation = { kind: 'allocation_failed' }; break;
        case 'prepare': errors.push(`Cloud preparation failed: ${message}`); observation = { kind: 'preparation_failed' }; break;
        case 'credentials': errors.push(`Cloud recovery needs credentials: ${message}`); observation = { kind: 'credentials_failed' }; break;
        case 'scan': errors.push(`Cloud allocation reconciliation incomplete: ${message}`); observation = { kind: 'scan_failed' }; break;
        case 'terminate': errors.push(`Cloud destruction failed: ${message}`); observation = { kind: 'termination_failed' }; break;
        default: throw error;
      }
    }
    plan = decodeCloudResourceTransition(transition(state, observation));
  }
}
