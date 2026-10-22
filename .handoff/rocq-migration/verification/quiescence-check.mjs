import { Kernel } from '../../host/kernel.mjs';
const kernel = new Kernel();
try {
  await kernel.initialize();
  const event = async input => (await kernel.request(input)).value;
  const configured = await event({ kind: 'configure', profiles: ['fixture', 'fixture-alt'].map(key => ({ key, provider: 'openai', name: key, reasoning_options: null })), tools: [], plugins: [], max_fork: 4, max_descendants: 64, instructions: { configured: '', global: null } });
  if (!configured.reply.ok) throw Error(JSON.stringify(configured.reply));
  const command = command => event({ kind: 'command', command });
  const created = await command({ op: 'create_idle', profile: 'fixture' });
  if (!created.reply.ok) throw Error(JSON.stringify(created.reply));
  const task_id = created.reply.result.task_id;
  for (const cmd of [{ op: 'freeze', task_id }, { op: 'send', task_id, message: 'Retain this queued input.' }]) {
    const result = await command(cmd);
    if (!result.reply.ok) throw Error(JSON.stringify(result.reply));
  }
  const result = await command({ op: 'configure_task_execution', task_id, profile: 'fixture-alt' });
  console.log(JSON.stringify({ task_id, reconfiguration: result.reply }));
} finally { await kernel.close(); }
