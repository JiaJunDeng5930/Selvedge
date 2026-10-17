import assert from 'node:assert/strict';
import http from 'node:http';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { compileJavaScript } from '../scripts/compile-javascript.mjs';
import { setTimeout as delay } from 'node:timers/promises';

const repository = fileURLToPath(new URL('../', import.meta.url));
const productionUI = new Map();

// A checked facade invokes the production UI against the HTTP-visible program.
export async function browserUI(t, { sourceAdmission = false } = {}) {
  const variant = sourceAdmission ? 'source' : 'runtime';
  if (!sourceAdmission && productionUI.has('source')) return productionUI.get('source');
  if (productionUI.has(variant)) return productionUI.get(variant);
  const ready = (async () => {
    await mkdir(path.join(repository, '.workpad'), { recursive: true });
    const directory = await mkdtemp(path.join(repository, '.workpad', 'ui-boundary-'));
    t.after(() => rm(directory, { recursive: true, force: true }));
    const entry = path.join(directory, 'fixture.bend');
    const output = path.join(directory, 'fixture.mjs');
    const modules = {
      ...(sourceAdmission ? {
        Controls: 'browser/controls/PROGRAM.bend', Web: 'browser/MODEL.bend', Shell: 'browser/controls/SHELL.bend', Design: 'browser/appearance/DESIGN.bend',
        Font: 'browser/appearance/FONT.bend', Typography: 'browser/appearance/TYPOGRAPHY.bend', Limit: 'browser/layout/natural-size.bend',
      } : {}),
      ...(sourceAdmission ? {} : { SurfaceProof: 'interaction/presentation/surface-proof.bend' }),
      ProductUI: 'interaction/MODEL.bend', Core: 'interaction/STATE.bend', CoreTypes: 'interaction/TYPES.bend', Services: 'interaction/services/MODEL.bend', E: 'interaction/session/MODEL.bend',
      U: 'interaction/INPUT.bend', View: 'interaction/presentation/MODEL.bend', InterfaceView: 'interaction/presentation/SURFACE.bend',
      ...(sourceAdmission ? { SurfaceProof: 'interaction/presentation/surface-proof.bend' } : {}),
      Identity: 'interaction/IDENTITY.bend', Cmd: 'harness/transport/command-codec.bend', J: 'bendlib/json.bend', M: 'harness/MODEL.bend',
    };
    // Ordinary UI clients need the surface provider; source authorship also needs the browser providers.
    const verificationImports = (sourceAdmission ? await readFile(path.join(repository, '.build/ui-verification.bend'), 'utf8') : '')
      .split('\n').filter(line => line.startsWith('import ../')).map(line => {
        const [, file, alias] = /^import \.\.\/(\S+) as (\S+)$/.exec(line);
        return `import ${path.relative(directory, path.join(repository, file))} as ${alias}`;
      }).join('\n');
    const imports = Object.entries(modules).map(([name, file]) =>
      `import ${path.relative(directory, path.join(repository, file))} as ${name}`).join('\n');
    await writeFile(entry, `import Base
${verificationImports}
${imports}

def state_of(decision: CoreTypes.Decision) -> CoreTypes.State:
  match decision:
    case CoreTypes.Decision{state, reply, runtime_effects, interaction_effects, service_effects, durable}: state

def selected(program: M.World(), task: Nat) -> CoreTypes.State:
  state_of(ProductUI.step(ProductUI.InterfaceInput{CoreTypes.ApplicationInput{E.UserInput{U.Activate{U.Navigate{U.Conversation{task}}}}}}, ProductUI.initial(program)))

def surface(program: M.World(), task: Nat) -> InterfaceView.Surface:
  ProductUI.observe(View.Capacity{True{}, False{}}, selected(program, task))

def authenticated_connection(decision: CoreTypes.Decision, task: Nat) -> Result<&2, &2, String, CoreTypes.State>:
  match decision:
    case CoreTypes.Decision{state, reply, runtime_effects, interaction_effects, service_effects, durable}:
      match service_effects:
        case Con{Services.Authenticate{ticket}, Nil{}}:
          connected = state_of(ProductUI.step(ProductUI.Authenticated{ticket, Done{Unit{}}}, state))
          Done{state_of(ProductUI.step(ProductUI.InterfaceInput{CoreTypes.ApplicationInput{E.UserInput{U.Activate{U.Navigate{U.Conversation{task}}}}}}, connected))}
        case _: Fail{"Expected exactly one authentication request"}

def authenticated(program: M.World(), task: Nat) -> Result<&2, &2, String, CoreTypes.State>:
  authenticated_connection(Core.step(CoreTypes.ServiceInput{Services.Connect{}}, ProductUI.initial(program)), task)

def surface_state(state: CoreTypes.State) -> InterfaceView.Surface:
  ProductUI.observe(View.Capacity{True{}, False{}}, state)

${sourceAdmission ? `# Fixture measurements answer each requested role independently; they do not bypass font admission.
def fixture_reference_advance(key: String) -> Nat:
  match key:
    case "@font/body": 8n
    case "@font/activity-primary": 7n
    case "@font/activity-support": 6n
    case _: 0n

def fixture_metric(specification: Typography.MeasurementSpec) -> Typography.Metric:
  Typography.MeasurementSpec{+key, text, family, size, height, weight, space, wrap, word_break, width, reference} = specification
  +advance: Nat = fixture_reference_advance(key)
  Typography.Metric{key, advance, advance, height, advance}

def fixture_metrics(specifications: +List<Typography.MeasurementSpec>) -> +List<Typography.Metric>:
  match specifications:
    case Nil{}: Nil{}
    case Con{specification, rest}: fixture_metric(specification) <> fixture_metrics(rest)

def fixture_font_received(plan: Font.Plan, specifications: +List<Typography.MeasurementSpec>, initial: Font.State) -> Font.State:
  Font.Plan{generation, requested} = plan
  Font.accept(initial, specifications, Font.Observation{generation, fixture_metrics(requested)})

def fixture_font() -> Font.State:
  +initial: Font.State = Font.begin(0n, 16000n)
  +specifications: +List<Typography.MeasurementSpec> = Font.activity_specifications(Limit.limit(), Font.scale(initial))
  fixture_font_received(Font.request(initial, specifications), specifications, initial)

def source_admission_parameters(parameters: Maybe<&2, Design.LayoutParameters>, surface: InterfaceView.Surface, capacity: View.Capacity, layers: +List<View.Layer>, +font: Font.State) -> Result<&2, &2, String, Shell.ShellAuthorship>:
  match parameters:
    case None{}: Fail{"Fixture font metrics exceed production layout size"}
    case Some{parameters}:
      +environment: Design.Environment = Design.Environment{Design.Viewport{602n, 664n}, False{}, 16000n}
      Done{Shell.source_supporting(Limit.limit(), Web.appearance_surface(surface, environment, font), parameters, capacity, layers, Nil{}, Typography.Presentation{Typography.Body{}, Typography.Regular{}, Font.scale(font)}, Controls.FullSupporting{})}

def source_admission_metrics(body: Maybe<&2, Typography.Metric>, activity: Maybe<&2, Font.ActivityMetrics>, +font: Font.State, surface: InterfaceView.Surface, capacity: View.Capacity, layers: +List<View.Layer>) -> Result<&2, &2, String, Shell.ShellAuthorship>:
  match body activity:
    case Some{body} Some{Font.ActivityMetrics{primary, support}}:
      source_admission_parameters(Design.parameters(Limit.limit(), Font.scale(font), body, primary, support), surface, capacity, layers, font)
    case _ _: Fail{"Fixture did not complete the requested production font measurements"}

def source_admission_surface(+surface: InterfaceView.Surface, capacity: View.Capacity) -> Result<&2, &2, String, Shell.ShellAuthorship>:
  InterfaceView.Surface{CoreTypes.Scene{View.Scene{navigation, main, +layers, arrangement, attention}, settings, transfers, preview, code, directory_picker}, base, overlays, scope} = surface
  +font: Font.State = fixture_font()
  source_admission_metrics(Font.body(font), Font.activity_metrics(font), font, surface, capacity, layers)

def source_admission(state: CoreTypes.State) -> Result<&2, &2, String, Shell.ShellAuthorship>:
  +capacity: View.Capacity = View.Capacity{True{}, False{}}
  source_admission_surface(ProductUI.observe(capacity, state), capacity)

` : ''}
def key(node: InterfaceView.Node) -> String:
  InterfaceView.Node{key, semantic, label, role, meaning, children} = node
  Identity.encode(key)

def requests(effects: +List<E.Effect>) -> List<&2, J.Json>:
  match effects:
    case Nil{}: Nil{}
    case Con{E.RequestCommand{command, completion}, rest}: Cmd.command_json(command) <> requests(rest)
    case Con{other, rest}: requests(rest)

def commands_of(decision: CoreTypes.Decision) -> Result<&2, &2, String, String>:
  match decision:
    case CoreTypes.Decision{state, reply, runtime_effects, interaction_effects, service_effects, durable}: J.show(J.Array{requests(interaction_effects)})

def activate_state(state: CoreTypes.State, key: String) -> CoreTypes.State:
  state_of(ProductUI.step(ProductUI.Element{View.Capacity{True{}, False{}}, key, InterfaceView.Press{}}, state))

def press_state(state: CoreTypes.State, key: String) -> Result<&2, &2, String, String>:
  commands_of(ProductUI.step(ProductUI.Element{View.Capacity{True{}, False{}}, key, InterfaceView.Press{}}, state))

def press(program: M.World(), task: Nat, key: String) -> Result<&2, &2, String, String>:
  commands_of(ProductUI.step(ProductUI.Element{View.Capacity{True{}, False{}}, key, InterfaceView.Press{}}, selected(program, task)))
`);
    await compileJavaScript({ entry, output, sourceRoot: repository,
      exports: { ...(sourceAdmission ? { source_admission: 'source_admission' } : {}), surface: 'surface', key: 'key', press: 'press', authenticated: 'authenticated', surface_state: 'surface_state', activate_state: 'activate_state', press_state: 'press_state' } });
    return import(pathToFileURL(output).href);
  })();
  productionUI.set(variant, ready);
  return ready;
}

function linkedNodes(list) {
  const result = [];
  while (list?.$ === 'Con') {
    result.push(list.head);
    list = list.tail;
  }
  assert.equal(list?.$, 'Nil');
  return result;
}

export function surfaceNodes(surface) {
  const visit = node => [node, ...linkedNodes(node.children).flatMap(visit)];
  return [...linkedNodes(surface.base), ...linkedNodes(surface.overlays)].flatMap(visit);
}

export async function home(t) {
  const directory = await mkdtemp(path.join(tmpdir(), 'selvedge-service-test-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  return directory;
}

export async function taskIdle(service, taskId = 0) {
  const deadline = Date.now() + 5000;
  let page;
  do {
    const result = await service.command({ op: 'read', task_id: taskId });
    assert.equal(result.reply.ok, true);
    page = result.reply.result;
    if (page.task.phase === 'idle' && page.task.operations.length === 0) return page;
    await delay(10);
  } while (Date.now() < deadline);
  throw new Error(`Task did not settle: ${JSON.stringify(page)}`);
}

export async function responsesServer(t, respond) {
  const requests = [];
  const failures = [];
  const server = http.createServer((request, response) => {
    void (async () => {
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      requests.push(body);
      const output = await respond(body, requests.length - 1, request);
      response.writeHead(200, { 'content-type': 'text/event-stream' });
      response.write(`data: ${JSON.stringify({ type: 'response.output_text.delta', delta: '处理中 😀' })}\r\n\r\n`);
      response.end(`data: ${JSON.stringify({ type: 'response.completed', response: { status: 'completed', output } })}\r\n\r\n`);
    })().catch(error => {
      failures.push(error);
      response.writeHead(500);
      response.end('fixture failure');
    });
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  t.after(() => {
    // NOTE: The pinned Bun runtime also stops the server in this call.
    server.closeAllConnections();
  });
  return { endpoint: `http://127.0.0.1:${server.address().port}/responses`, requests, failures };
}

export function shellQuote(value) {
  return `'${value.replaceAll("'", "'\\''")}'`;
}
