import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { DatabaseSync } from 'node:sqlite';
import { setTimeout as delay } from 'node:timers/promises';
import path from 'node:path';
import { Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer, shellQuote, taskIdle } from './support.mjs';

function credentials(t) {
  const name = 'SELVEDGE_CODING_FIXTURE_KEY';
  const previous = process.env[name];
  process.env[name] = 'local-fixture-only';
  t.after(() => { if (previous === undefined) delete process.env[name]; else process.env[name] = previous; });
  return name;
}

const call = (id, name, args) => [{ type: 'function_call', call_id: id, name, arguments: JSON.stringify(args) }];
const answer = text => [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text }] }];
const output = (body, id) => JSON.parse(body.input.find(item => item.type === 'function_call_output' && item.call_id === id).output);

test('coding loop reads, writes, edits, tests, compacts, and restarts through committed native effects', { timeout: 15_000 }, async t => {
  const directory = await home(t);
  const api_key_env = credentials(t);
  await writeFile(path.join(directory, 'math.mjs'), 'export const add = (a, b) => a - b;\n');
  const model = await responsesServer(t, async (body, index) => {
    const database = new DatabaseSync(path.join(directory, 'journal.sqlite'), { readOnly: true });
    const decision = JSON.parse(database.prepare('SELECT decision FROM journal ORDER BY seq DESC LIMIT 1').get().decision);
    database.close();
    assert.ok(decision.effects.some(effect => ['model', 'summary'].includes(effect.kind)), 'request must follow the committed intent');
    switch (index) {
      case 0:
        assert.match(body.instructions, /AGENTS\.md/);
        assert.equal(body.parallel_tool_calls, true);
        assert.equal(body.tools.some(tool => ['read_file', 'write_file', 'edit_file'].includes(tool.name)), false);
        return call('read-source', 'bash', { command: 'cat math.mjs' });
      case 1:
        assert.match(output(body, 'read-source').value.stdout, /a - b/);
        return call('write-test', 'bash', { command: "cat > check.mjs <<'SELVEDGE_TEST'\n" +
          "import assert from 'node:assert/strict';\nimport { add } from './math.mjs';\nassert.equal(add(2, 3), 5);\nconsole.log('one assertion passed');\nSELVEDGE_TEST" });
      case 2:
        assert.equal(output(body, 'write-test').is_error, false);
        return call('edit-source', 'bash', { command: `${shellQuote(process.execPath)} --input-type=module -e ${shellQuote(
          "import {readFileSync,writeFileSync} from 'node:fs'; const p='math.mjs'; const s=readFileSync(p,'utf8'); if(s.split('a - b').length!==2) throw Error('ambiguous edit'); writeFileSync(p,s.replace('a - b','a + b'));"
        )}` });
      case 3:
        assert.equal(output(body, 'edit-source').is_error, false);
        return call('test-code', 'bash', { command: `${shellQuote(process.execPath)} check.mjs && printf 'ran\n' >> executions` });
      case 4:
        assert.equal(output(body, 'test-code').is_error, false);
        assert.match(output(body, 'test-code').value.stdout, /one assertion passed/);
        assert.equal(await readFile(path.join(directory, 'math.mjs'), 'utf8'), 'export const add = (a, b) => a + b;\n');
        return answer('Implemented addition; the actual Node assertion passed.');
      case 5:
        assert.equal(body.tool_choice, 'none');
        assert.deepEqual(body.tools, []);
        assert.match(body.instructions, /Summarize this task/);
        return answer('math.mjs addition fixed. check.mjs verified add(2, 3) = 5. No unfinished side effects.');
      case 6:
        assert.match(body.input[0].content, /Project context snapshot/);
        assert.match(body.input[1].content, /Task continuation summary/);
        assert.match(body.input[1].content, /addition fixed/);
        assert.equal(body.input.some(item => item.content === 'Fix the addition bug and run a real test.'), false);
        return answer('Continuing from the preserved checkpoint.');
      default: throw new Error(`Unexpected model request ${index}`);
    }
  });
  const config = validateConfig({ ...defaultConfig, profiles: { fixture: {
    provider: 'responses', model: 'fixture', endpoint: model.endpoint, api_key_env,
  } } });
  let service = await Service.open({ home: directory, cwd: directory, config });
  t.after(() => service.close());
  await service.command({ op: 'create', profile: 'fixture', message: 'Fix the addition bug and run a real test.' });
  const completed = await taskIdle(service);
  assert.equal(completed.messages.filter(message => message.role === 'function_output').length, 4);
  assert.deepEqual(model.failures, []);
  assert.equal((await service.command({ op: 'compact', task_id: 0 })).reply.ok, true);
  const compacted = await taskIdle(service);
  assert.equal(compacted.messages.at(-1).role, 'context_summary');
  await service.close();
  service = await Service.open({ home: directory, cwd: directory, config });
  assert.deepEqual((await taskIdle(service)).messages, compacted.messages);
  assert.equal(model.requests.length, 6);
  await service.command({ op: 'send', task_id: 0, message: 'Continue without rerunning the test.' });
  await taskIdle(service);
  assert.deepEqual(model.failures, []);
  assert.equal(model.requests.length, 7);
  assert.equal(await readFile(path.join(directory, 'executions'), 'utf8'), 'ran\n');
});

test('interrupt kills a live Bash process without archiving or accepting its late result', { timeout: 10_000 }, async t => {
  const directory = await home(t);
  const api_key_env = credentials(t);
  const model = await responsesServer(t, (_, index) => index === 0
    ? call('long-command', 'bash', { command: 'printf "%s" "$$" > child.pid; exec sleep 60' })
    : answer('Resumed without repeating the interrupted command.'));
  const config = validateConfig({ ...defaultConfig, profiles: { fixture: {
    provider: 'responses', model: 'fixture', endpoint: model.endpoint, api_key_env,
  } } });
  const service = await Service.open({ home: directory, cwd: directory, config });
  t.after(() => service.close());
  await service.command({ op: 'create', profile: 'fixture', message: 'Run the long command.' });
  let pid;
  const deadline = Date.now() + 3000;
  while (!pid && Date.now() < deadline) {
    try { pid = Number(await readFile(path.join(directory, 'child.pid'), 'utf8')); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
    if (!pid) await delay(10);
  }
  assert.ok(Number.isSafeInteger(pid) && pid > 0);
  process.kill(pid, 0);
  assert.equal((await service.command({ op: 'interrupt', task_id: 0 })).reply.ok, true);
  const stopped = await taskIdle(service);
  assert.equal(stopped.task.status, 'stopped');
  assert.equal(stopped.messages.find(message => message.role === 'function_output').content.error.code, 'outcome_unknown');
  let gone = false;
  while (!gone && Date.now() < deadline) {
    try { process.kill(pid, 0); await delay(10); }
    catch (error) { if (error.code !== 'ESRCH') throw error; gone = true; }
  }
  assert.equal(gone, true, 'the owned process group must be terminated');
  await service.command({ op: 'send', task_id: 0, message: 'Resume.' });
  const resumed = await taskIdle(service);
  assert.equal(resumed.task.status, 'active');
  assert.equal(resumed.messages.filter(message => message.role === 'function_output').length, 1);
  assert.equal(model.requests.length, 2);
  assert.deepEqual(model.failures, []);
});
