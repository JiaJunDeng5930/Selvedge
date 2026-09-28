import { writeFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import path from 'node:path';
import { modify, replaceOnce, replaceDefinition } from '../locality-support.mjs';
import { Kernel } from '../../host/kernel.mjs';

// This fixture extends a copy of the actual application. Only component-owned
// assembly files change; the old model, executor, codecs and proof tree freeze.
export const assemblyChanges = [
  'FEATURES.bend', 'bendlib/feature-operations.bend', 'bendlib/feature-resolution.bend',
  'bendlib/feature-spec.bend', 'bendlib/feature-execution.bend', 'bendlib/feature-laws.bend',
  'bendlib/feature-protocol.bend', 'bendlib/feature-codec.bend', 'bendlib/feature-state.bend',
  'bendlib/feature-ui.bend', 'bendlib/feature-view.bend',
];

function importing(source, relative, alias) {
  return source.replace('import Base\n', `import Base\nimport ${relative} as ${alias}\n`);
}

function clause(source, definition, branch) {
  const start = source.indexOf(`def ${definition}(`);
  if (start < 0) throw new Error(`Missing extension definition: ${definition}`);
  const match = /^  match [^\n]+:\n/m.exec(source.slice(start));
  if (!match) throw new Error(`Missing dispatch in ${definition}`);
  const insert = start + match.index + match[0].length;
  return source.slice(0, insert) + branch.trimEnd() + '\n' + source.slice(insert);
}

export async function extendCounter(directory) {
  const additions = {
    'COUNTER.bend': `import Base
import ./bendlib/component.bend as C
import ./bendlib/domain.bend as D
import ./bendlib/json.bend as J

type State is Data:
  State{value: Nat}

type Effect is Data:
  Notice{value: Nat}

def initial() -> State:
  State{0n}

def read(state: State) -> Nat:
  State{value} = state
  value

# Independent complete meaning: store the value, reply with it, emit one notice.
def required(+value: Nat, previous: State) -> C.Decision<State, Effect>:
  C.Decision{State{value}, D.success(J.nat(value)), [Notice{value}]}
`,
    'bendlib/counter-execution.bend': `import Base
import ../COUNTER.bend as Counter
import ./component.bend as C
import ./domain.bend as D
import ./json.bend as J

def saved(value: Nat, previous: Counter.State) -> Counter.State:
  Counter.State{value}

def set(+value: Nat, previous: Counter.State) -> C.Decision<Counter.State, Counter.Effect>:
  C.Decision{saved(value, previous), D.success(J.nat(value)), [Counter.Notice{value}]}
`,
    'bendlib/counter-assembly.bend': `import Base
import ../COUNTER.bend as Counter
import ../FEATURES.bend as F
import ../MODEL.bend as M
import ./component.bend as C
import ./domain.bend as D
import ./effects.bend as E
import ./json.bend as J

def state(world: M.World()) -> Counter.State:
  F.rest(C.rest(D.State, F.State(), world))

def effects(values: +List<Counter.Effect>) -> +List<M.Effect()>:
  match values:
    case Nil{}: Nil{}
    case Con{effect, rest}: E.FeatureEffect{F.CounterEffect{effect}} <> effects(rest)

def embed(decision: C.Decision<Counter.State, Counter.Effect>, world: M.World()) -> M.Decision():
  C.Decision{state, reply, emitted} = decision
  C.Frame{core, C.Frame{board, previous}} = world
  C.Decision{C.Frame{core, C.Frame{board, state}}, reply, effects(emitted)}

def observation(+world: M.World()) -> M.Decision():
  C.Decision{world, D.success(J.nat(Counter.read(state(world)))), Nil{}}
`,
    'bendlib/counter-view.bend': `import Base
import ../COUNTER.bend as Counter
import ./surface.bend as S
import ./json.bend as J

def panel(state: Counter.State, focus: Nat) -> S.Node:
  S.Value{"counter", "Independent counter", J.Object{[
    J.Field{"value", J.nat(Counter.read(state))}, J.Field{"focus", J.nat(focus)}]}}
`,
    'bendlib/counter-laws.bend': `import Base
import ../COUNTER.bend as Counter
import ../MODEL.bend as M
import ./component.bend as C
import ./counter-execution.bend as Actual
import ./counter-assembly.bend as Assembly

def local_meaning(+value: Nat, +state: Counter.State) ->
  {Actual.set(value, state) == Counter.required(value, state) : C.Decision<Counter.State, Counter.Effect>}:
  {==}

def full_meaning(+value: Nat, +world: M.World()) ->
  {Assembly.embed(Actual.set(value, Assembly.state(world)), world) == Assembly.embed(Counter.required(value, Assembly.state(world)), world) : M.Decision()}:
  Equal.cong(C.Decision<Counter.State, Counter.Effect>, M.Decision(), decision => Assembly.embed(decision, world),
    Actual.set(value, Assembly.state(world)), Counter.required(value, Assembly.state(world)), local_meaning(value, Assembly.state(world)))
`,
  };
  for (const [filename, source] of Object.entries(additions)) await writeFile(path.join(directory, filename), source);

  await modify(directory, 'FEATURES.bend', source => {
    let result = importing(source, './COUNTER.bend', 'Counter');
    result = replaceDefinition(result, 'Rest', 'def Rest() -> Data:\n  Counter.State');
    result = replaceDefinition(result, 'initial_rest', 'def initial_rest() -> Rest():\n  Counter.initial()');
    result = replaceDefinition(result, 'CursorRest', 'def CursorRest() -> Data:\n  Nat');
    result = replaceDefinition(result, 'initial_cursor_rest', 'def initial_cursor_rest() -> CursorRest():\n  0n');
    for (const [type, constructors] of [
      ['Effect', '  CounterEffect{effect: Counter.Effect}'],
      ['Command', '  CounterSet{value: Nat}'], ['Query', '  CounterRead{}'],
      ['CommandKind', '  CounterSetKind{}\n  CounterReadKind{}'],
      ['Navigation', '  CounterFocus{}'], ['Completion', '  CounterObserved{}'],
    ]) result = replaceOnce(result, `type ${type} is Data:\n`, `type ${type} is Data:\n${constructors}\n`);
    result = replaceDefinition(result, 'specs', `def specs(settings_schema: J.Json) -> +List<CommandSpec>:
  List.append(&2, CommandSpec, board_specs(BoardCodec.specs(settings_schema)),
    [CommandSpec{"counter_set", "Store the independent counter.", CounterSetKind{},
       D.command_schema([J.Field{"value", BoardCodec.integer_schema()}], [J.Text{"value"}])},
     CommandSpec{"counter_read", "Read the independent counter.", CounterReadKind{}, D.command_schema(Nil{}, Nil{})}])`);
    return result + `
def focus_counter(cursor: Cursor()) -> Cursor():
  C.Frame{board, previous} = cursor
  C.Frame{board, 1n}
`;
  });

  await modify(directory, 'bendlib/feature-operations.bend', source => source
    .replace('type Operation is Data:\n', 'type Operation is Data:\n  CounterSet{value: Nat}\n')
    .replace('type Event is Data:\n', 'type Event is Data:\n  CounterObserved{}\n'));
  await modify(directory, 'bendlib/feature-resolution.bend', source => clause(source, 'resolve',
    '    case F.CounterSet{value}: Accept{O.CounterSet{value}}'));

  for (const [filename, definition, step, implementation] of [
    ['feature-spec.bend', 'meaning', 'Counter.required', false],
    ['feature-execution.bend', 'realize', 'CounterActual.set', true],
  ]) await modify(directory, `bendlib/${filename}`, source => {
    let result = importing(importing(source, '../COUNTER.bend', 'Counter'), './counter-assembly.bend', 'CounterAssembly');
    if (implementation) result = importing(result, './counter-execution.bend', 'CounterActual');
    result = clause(result, definition, `    case O.CounterSet{value}: CounterAssembly.embed(${step}(value, CounterAssembly.state(world)), world)`);
    return clause(result, 'event', '    case O.CounterObserved{}: CounterAssembly.observation(world)');
  });

  await modify(directory, 'bendlib/feature-laws.bend', source => {
    let result = importing(source, './counter-laws.bend', 'CounterProof');
    result = clause(result, 'meaning', '    case O.CounterSet{value}: CounterProof.full_meaning(value, world)');
    return clause(result, 'event', '    case O.CounterObserved{}: {==}');
  });
  await modify(directory, 'bendlib/feature-protocol.bend', source => clause(source, 'resolve',
    '    case F.CounterObserved{}: Some{O.CounterObserved{}}'));

  await modify(directory, 'bendlib/feature-state.bend', source => {
    let result = importing(importing(source, '../COUNTER.bend', 'Counter'), './counter-assembly.bend', 'CounterAssembly');
    result = clause(result, 'query', '    case F.CounterRead{}: D.success(J.nat(Counter.read(CounterAssembly.state(world))))');
    result = clause(result, 'effect_ticket', '    case F.CounterEffect{effect}: None{}');
    return clause(result, 'effect_valid', '    case F.CounterEffect{Counter.Notice{value}}: Nat.is_eq(value, Counter.read(F.rest(state)))');
  });
  await modify(directory, 'bendlib/feature-ui.bend', source => {
    let result = clause(source, 'navigate', `    case F.CounterFocus{} M.ViewState{selected, after, tasks_after, profile, cursor}:
      M.ViewState{selected, after, tasks_after, profile, F.focus_counter(cursor)}`);
    return clause(result, 'submitted', '    case F.CounterSet{value} _: previous');
  });

  await modify(directory, 'bendlib/feature-view.bend', source => {
    let result = importing(importing(source, './counter-view.bend', 'CounterView'), './counter-assembly.bend', 'CounterAssembly');
    result = replaceOnce(result, '  screen_pane(threads, embedded, notices, Navigation.pane_of(F.board_cursor(cursor)), state, world, reply)',
      `  S.Group{"extension", "screen", "", [
    screen_pane(threads, embedded, notices, Navigation.pane_of(F.board_cursor(cursor)), state, world, reply),
    CounterView.panel(CounterAssembly.state(world), F.cursor_rest(cursor))]}`);
    return replaceOnce(result, '+state: M.ViewState, world: M.World(), reply: J.Json)',
      '+state: M.ViewState, +world: M.World(), reply: J.Json)')
      .replace('profile, cursor} = state', 'profile, +cursor} = state');
  });

  await modify(directory, 'bendlib/feature-codec.bend', source => {
    let result = importing(importing(source, '../COUNTER.bend', 'Counter'), './component.bend', 'C')
      .replace('def valid(kind: F.CommandKind, body: J.Json)', 'def valid(kind: F.CommandKind, +body: J.Json)');
    result = replaceDefinition(result, 'cursor_keys', 'def cursor_keys() -> +List<String>:\n  ["board", "counter"]');
    result = replaceDefinition(result, 'cursor_fields', `def cursor_fields(+cursor: F.Cursor()) -> +List<J.Field>:
  [J.Field{"board", Navigation.cursor_json(F.board_cursor(cursor))}, J.Field{"counter", J.nat(F.cursor_rest(cursor))}]`);
    result = replaceDefinition(result, 'cursor', `def cursor(+value: J.Json) -> F.Cursor():
  C.Frame{Navigation.cursor(J.get(value, "board"), Board.word(J.get(J.get(value, "board"), "now"))),
    J.natural_or(J.natural(J.get(value, "counter")), 0n)}`);
    result = replaceDefinition(result, 'valid_cursor', `def valid_cursor(+value: J.Json) -> Bool:
  Navigation.valid_cursor(J.get(value, "board")) && Shape.is_natural(J.get(value, "counter"))`);
    const cases = {
      command_json: '    case F.CounterSet{value}: J.Object{[J.Field{"op", J.Text{"counter_set"}}, J.Field{"value", J.nat(value)}]}',
      query_json: '    case F.CounterRead{}: J.Object{[J.Field{"op", J.Text{"counter_read"}}]}',
      event_json: '    case F.CounterFocus{}: J.Object{[J.Field{"type", J.Text{"counter"}}]}',
      construct: `    case F.CounterSetKind{}: M.FeatureCommand{F.CounterSet{J.natural_or(J.natural(J.get(body, "value")), 0n)}}
    case F.CounterReadKind{}: M.Observe{M.FeatureQuery{F.CounterRead{}}}`,
      valid: `    case F.CounterSetKind{}: Shape.object_keys(body, ["op", "value"]) && Schema.valid(Board.integer_schema(), J.get(body, "value"))
    case F.CounterReadKind{}: Shape.object_keys(body, ["op"])`,
      effect_json: '    case F.CounterEffect{Counter.Notice{value}}: J.Object{[J.Field{"kind", J.Text{"counter_notice"}}, J.Field{"value", J.nat(value)}]}',
      completion: '    case "counter_observed": counter_completion(Shape.object_keys(body, ["kind"]))',
      navigation: '    case "counter": navigation_valid(Shape.object_keys(event, ["type"]), F.CounterFocus{})',
    };
    for (const [name, branch] of Object.entries(cases)) result = clause(result, name, branch);
    const helper = `
def counter_completion(valid: Bool) -> Result<&2, &2, String, F.Completion>:
  match valid:
    case True{}: Done{F.CounterObserved{}}
    case False{}: Fail{"Malformed counter observation"}
`;
    return result.replace('def completion(', helper + '\ndef completion(');
  });
  return Object.keys(additions);
}

// Exercise the unchanged production entry and real transport. In-memory cursor
// checks alone miss state that is silently reset by decode/encode on each input.
export async function counterProbe(binary) {
  const kernel = new Kernel({ binary, timeout: 10_000 });
  const send = async input => (await kernel.request(input)).value;
  const command = body => send({ kind: 'command', command: body });
  const nodes = node => [node, ...(node.children ?? []).flatMap(nodes)];
  const counter = presentation => nodes(presentation.root).find(node => node.key === 'counter');
  try {
    await kernel.initialize();
    const malformed = await command({ op: 'counter_set', value: -1 });
    assert.equal(malformed.reply.ok, false);
    assert.deepEqual(malformed.effects, []);
    const saved = await command({ op: 'counter_set', value: 7 });
    assert.deepEqual(saved.reply, { ok: true, result: 7 });
    assert.equal(saved.durable, true);
    assert.deepEqual(saved.effects, [{ kind: 'counter_notice', value: 7 }]);
    const read = await command({ op: 'counter_read' });
    assert.deepEqual(read.reply, { ok: true, result: 7 });
    assert.deepEqual(read.effects, []);
    assert.equal(read.durable, false);
    const completed = await send({ kind: 'counter_observed' });
    assert.deepEqual(completed.reply, { ok: true, result: 7 });
    assert.deepEqual(completed.effects, []);
    let state = null;
    for (const event of [
      { type: 'counter' },
      { type: 'refresh' },
      { type: 'board', event: { action: 'search', query: 'preserve counter focus' } },
      { type: 'board', event: { action: 'pane', pane: 'board' } },
    ]) {
      const result = await send({ kind: 'ui', state, event });
      assert.equal(result.reply.ok, true, JSON.stringify(result.reply));
      assert.equal(result.durable, false);
      assert.deepEqual(result.effects, []);
      const presentation = result.reply.result.presentation;
      state = presentation.state;
      assert.equal(state.counter, 1, 'A real wire round trip must preserve the additional cursor');
      assert.deepEqual(counter(presentation)?.value, { value: 7, focus: 1 });
    }
    assert.equal(state.board.filter.search, 'preserve counter focus');
    const rejected = await send({ kind: 'ui', state: { ...state, counter: 'invalid' }, event: { type: 'refresh' } });
    assert.equal(rejected.reply.ok, false);
    assert.deepEqual(rejected.effects, []);
    assert.deepEqual((await command({ op: 'counter_read' })).reply, { ok: true, result: 7 });
  } finally {
    await kernel.close();
  }
}
