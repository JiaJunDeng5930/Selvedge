import assert from 'node:assert/strict';
import http from 'node:http';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { compileJavaScript } from '../scripts/compile-javascript.mjs';
import { setTimeout as delay } from 'node:timers/promises';

const repository = fileURLToPath(new URL('../', import.meta.url));
let productionUI;

// A checked facade invokes the production UI against the HTTP-visible program.
export async function browserUI(t) {
  return productionUI ??= (async () => {
    await mkdir(path.join(repository, '.workpad'), { recursive: true });
    const directory = await mkdtemp(path.join(repository, '.workpad', 'ui-boundary-'));
    t.after(() => rm(directory, { recursive: true, force: true }));
    const entry = path.join(directory, 'fixture.bend');
    const output = path.join(directory, 'fixture.mjs');
    const modules = {
      ProductUI: 'interaction/MODEL.bend', Core: 'interaction/STATE.bend', Services: 'interaction/services/MODEL.bend', E: 'interaction/session/MODEL.bend',
      U: 'interaction/INPUT.bend', View: 'interaction/presentation/MODEL.bend', InterfaceView: 'interaction/presentation/PROGRAM.bend',
      Identity: 'interaction/IDENTITY.bend', Cmd: 'harness/transport/command-codec.bend', J: 'bendlib/json.bend', M: 'harness/MODEL.bend',
    };
    const imports = Object.entries(modules).map(([name, file]) =>
      `import ${path.relative(directory, path.join(repository, file))} as ${name}`).join('\n');
    await writeFile(entry, `import Base
${imports}

def state_of(decision: Core.Decision) -> Core.State:
  match decision:
    case Core.Decision{state, reply, runtime_effects, interaction_effects, service_effects, durable}: state

def selected(program: M.World(), task: Nat) -> Core.State:
  state_of(ProductUI.step(ProductUI.InterfaceInput{Core.ApplicationInput{E.UserInput{U.Activate{U.Navigate{U.Conversation{task}}}}}}, ProductUI.initial(program)))

def surface(program: M.World(), task: Nat) -> InterfaceView.Surface:
  ProductUI.observe(View.Capacity{True{}, False{}}, selected(program, task))

def authenticated_connection(decision: Core.Decision, task: Nat) -> Result<&2, &2, String, Core.State>:
  match decision:
    case Core.Decision{state, reply, runtime_effects, interaction_effects, service_effects, durable}:
      match service_effects:
        case Con{Services.Authenticate{ticket, credential}, Nil{}}:
          connected = state_of(ProductUI.step(ProductUI.Authenticated{ticket, Done{Unit{}}}, state))
          Done{state_of(ProductUI.step(ProductUI.InterfaceInput{Core.ApplicationInput{E.UserInput{U.Activate{U.Navigate{U.Conversation{task}}}}}}, connected))}
        case _: Fail{"Expected exactly one authentication request"}

def authenticated(program: M.World(), task: Nat, credential: String) -> Result<&2, &2, String, Core.State>:
  entered = state_of(Core.step(Core.ServiceInput{Services.EnterCredential{credential}}, ProductUI.initial(program)))
  authenticated_connection(Core.step(Core.ServiceInput{Services.Connect{}}, entered), task)

def surface_state(state: Core.State) -> InterfaceView.Surface:
  ProductUI.observe(View.Capacity{True{}, False{}}, state)

def key(node: InterfaceView.Node) -> String:
  InterfaceView.Node{key, semantic, label, role, meaning, children} = node
  Identity.encode(key)

def requests(effects: +List<E.Effect>) -> List<&2, J.Json>:
  match effects:
    case Nil{}: Nil{}
    case Con{E.RequestCommand{command, completion}, rest}: Cmd.command_json(command) <> requests(rest)
    case Con{other, rest}: requests(rest)

def commands_of(decision: Core.Decision) -> Result<&2, &2, String, String>:
  match decision:
    case Core.Decision{state, reply, runtime_effects, interaction_effects, service_effects, durable}: J.show(J.Array{requests(interaction_effects)})

def press_state(state: Core.State, key: String) -> Result<&2, &2, String, String>:
  commands_of(ProductUI.step(ProductUI.Element{View.Capacity{True{}, False{}}, key, InterfaceView.Press{}}, state))

def press(program: M.World(), task: Nat, key: String) -> Result<&2, &2, String, String>:
  commands_of(ProductUI.step(ProductUI.Element{View.Capacity{True{}, False{}}, key, InterfaceView.Press{}}, selected(program, task)))
`);
    await compileJavaScript({ entry, output, sourceRoot: repository,
      exports: { surface: 'surface', key: 'key', press: 'press', authenticated: 'authenticated', surface_state: 'surface_state', press_state: 'press_state' } });
    return import(pathToFileURL(output).href);
  })();
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
