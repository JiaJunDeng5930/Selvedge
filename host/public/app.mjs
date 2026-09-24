const $ = id => document.getElementById(id);
let token = new URLSearchParams(location.hash.slice(1)).get('token') || sessionStorage.getItem('selvedge-token') || '';
if (location.hash) history.replaceState(null, '', location.pathname);
let description;
let selected;
let page = 0;
let cursor = 0;
let eventController;
let refreshing = false;
let refreshAgain = false;
let taskSnapshot;

function error(message = '') { $('error').textContent = message; $('error').hidden = !message; }
function element(tag, text, className) {
  const node = document.createElement(tag);
  if (text !== undefined) node.textContent = text;
  if (className) node.className = className;
  return node;
}
async function api(route, body) {
  const response = await fetch(route, { method: body === undefined ? 'GET' : 'POST',
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body) });
  const value = await response.json();
  if (!response.ok || !value.ok) {
    if (response.status === 401) $('access').hidden = false;
    throw new Error(value.error?.message ?? `HTTP ${response.status}`);
  }
  return value.result;
}
const command = body => api('/api/commands', body);

function messageView(message) {
  const item = element('article', undefined, 'message');
  let role = message.role;
  let content = message.content;
  if (role === 'model_context') {
    if (content.type === 'message') {
      role = content.role;
      content = content.content.map(part => part.text ?? part.refusal ?? '').join('\n');
    } else {
      const disclosure = element('details');
      disclosure.append(element('summary', content.type === 'reasoning' ? 'Reasoning context retained' : 'Conversation context retained'));
      disclosure.append(element('p', content.summary?.map(part => part.text ?? '').join('\n') || 'Available to subsequent model calls.'));
      item.append(disclosure);
      return item;
    }
  }
  item.append(element('h3', role.replaceAll('_', ' ')));
  item.append(element(typeof content === 'string' ? 'div' : 'pre', typeof content === 'string' ? content : JSON.stringify(content, null, 2), typeof content === 'string' ? 'prose' : ''));
  return item;
}

async function refresh() {
  if (refreshing) { refreshAgain = true; return; }
  refreshing = true;
  try {
    do {
      refreshAgain = false;
      const state = await command({ op: 'list' });
      $('tasks').replaceChildren();
      for (const task of state.tasks) {
        const button = element('button', `Task ${task.id}`, 'task');
        button.setAttribute('aria-current', String(selected === task.id));
        button.append(element('small', `${task.status} · ${task.model}${task.parent === null ? '' : ` · parent ${task.parent}`}`));
        button.onclick = () => { selected = task.id; page = 0; $('stream').hidden = true; refresh().catch(showError); };
        $('tasks').append(button);
      }
      if (!state.tasks.length) $('tasks').append(element('p', 'No tasks yet.'));
      const oldProfile = $('profile').value;
      $('profile').replaceChildren(...state.profiles.map(profile => {
        const option = element('option', `${profile.key} · ${profile.name}`);
        option.value = profile.key;
        return option;
      }));
      if (state.profiles.some(profile => profile.key === oldProfile)) $('profile').value = oldProfile;
      $('controls').replaceChildren();
      $('new-settings').hidden = selected !== undefined;
      $('more').hidden = true;
      $('history').replaceChildren();
      taskSnapshot = undefined;
      if (selected === undefined) {
        $('title').textContent = 'Start a task';
        $('details').textContent = 'Choose a model profile and describe the work. The echo profile is an offline demonstration.';
        $('send').textContent = 'Start task';
        $('send').disabled = !state.profiles.length;
        $('message').disabled = false;
      } else {
        const result = await command({ op: 'read', task_id: selected, after: page, limit: 100 });
        taskSnapshot = result.task;
        $('title').textContent = `Task ${selected}`;
        $('details').textContent = `${result.task.status} · ${result.task.phase.replaceAll('_', ' ')} · ${result.task.model} · ${result.task.queued} queued`;
        for (const name of result.task.controls) {
          const button = element('button', name[0].toUpperCase() + name.slice(1));
          button.title = description.commands.find(spec => spec.name === name)?.description ?? name;
          button.onclick = () => command({ op: name, task_id: selected }).then(() => refresh()).catch(showError);
          $('controls').append(button);
        }
        $('history').replaceChildren(...result.messages.map(messageView));
        $('more').hidden = !result.has_more;
        $('more').textContent = 'Next history page';
        $('send').textContent = 'Send message';
        $('message').disabled = result.task.status === 'archived';
        $('send').disabled = result.task.status === 'archived';
        if (result.task.phase !== 'model_pending') { $('stream').hidden = true; $('stream').textContent = ''; }
      }
    } while (refreshAgain);
  } finally { refreshing = false; }
}

function showError(reason) { error(reason.message); }
function populateCommand() {
  const spec = description.commands.find(value => value.name === $('command-name').value);
  $('command-description').textContent = spec.description;
  $('command-fields').replaceChildren();
  for (const [name, field] of Object.entries(spec.schema.properties)) {
    if (name === 'op') continue;
    const label = element('label', `${name}${spec.schema.required?.includes(name) ? ' *' : ''}`);
    const input = element(field.type === 'array' ? 'textarea' : 'input');
    input.name = name;
    input.dataset.type = field.type;
    input.required = spec.schema.required?.includes(name) ?? false;
    input.placeholder = field.description ?? (field.type === 'array' ? 'JSON array' : '');
    if (name === 'task_id' && selected !== undefined) input.value = String(selected);
    if (name === 'profile') input.value = $('profile').value;
    label.append(input);
    $('command-fields').append(label);
  }
}

async function watch(signal) {
  while (!signal.aborted) {
    try {
      const response = await fetch(`/api/events?after=${cursor}`, { headers: { authorization: `Bearer ${token}` }, signal });
      if (!response.ok) throw new Error(`Event connection failed (${response.status})`);
      $('connection').textContent = 'Connected';
      const reader = response.body.pipeThrough(new TextDecoderStream()).getReader();
      let pending = '';
      try {
        for (;;) {
          const { value, done } = await reader.read();
          if (done) break;
          pending += value;
          let end;
          while ((end = pending.indexOf('\n\n')) >= 0) {
            const frame = pending.slice(0, end);
            pending = pending.slice(end + 2);
            const data = frame.split('\n').find(line => line.startsWith('data: '));
            if (!data) continue;
            const event = JSON.parse(data.slice(6));
            if (event.type === 'commit') { cursor = event.sequence; await refresh(); }
            else if (event.type === 'delta' && event.task_id === selected) {
              if ($('stream').dataset.ticket !== String(event.ticket)) $('stream').textContent = '';
              $('stream').dataset.ticket = String(event.ticket);
              $('stream').hidden = false;
              $('stream').textContent += event.text;
            } else if (['fatal', 'diagnostic'].includes(event.type)) error(event.message);
          }
        }
      } finally { await reader.cancel().catch(() => {}); }
    } catch (reason) { if (signal.aborted) return; $('connection').textContent = 'Reconnecting…'; }
    await new Promise(resolve => { const timer = setTimeout(resolve, 1500); signal.addEventListener('abort', () => { clearTimeout(timer); resolve(); }, { once: true }); });
  }
}

async function connect() {
  if (!token) { $('access').hidden = false; $('connection').textContent = 'Access token required'; return; }
  description = await api('/api/describe');
  sessionStorage.setItem('selvedge-token', token);
  $('access').hidden = true;
  error();
  $('command-name').replaceChildren(...description.commands.map(spec => { const option = element('option', spec.name); option.value = spec.name; return option; }));
  populateCommand();
  await refresh();
  eventController?.abort();
  eventController = new AbortController();
  watch(eventController.signal).catch(showError);
}

$('connect').onclick = () => { token = $('token').value.trim(); connect().catch(showError); };
$('new-task').onclick = () => { selected = undefined; page = 0; $('stream').hidden = true; refresh().catch(showError); $('message').focus(); };
$('more').onclick = () => { page += 100; refresh().catch(showError); };
$('composer').onsubmit = async event => {
  event.preventDefault(); error();
  $('send').disabled = true;
  try {
    const result = await command(selected === undefined
      ? { op: 'create', profile: $('profile').value, reasoning: $('reasoning').value, message: $('message').value }
      : { op: 'send', task_id: selected, message: $('message').value });
    selected = result.task_id;
    $('message').value = '';
    await refresh();
  } catch (reason) { showError(reason); }
  finally { $('send').disabled = taskSnapshot?.status === 'archived'; }
};
$('show-commands').onclick = () => { if (!description) return; populateCommand(); $('commands').showModal(); };
$('close-commands').onclick = () => $('commands').close();
$('command-name').onchange = populateCommand;
$('command-form').onsubmit = async event => {
  event.preventDefault();
  try {
    const body = { op: $('command-name').value };
    for (const input of $('command-fields').querySelectorAll('[name]')) {
      if (!input.value && !input.required) continue;
      body[input.name] = input.dataset.type === 'string' ? input.value : JSON.parse(input.value);
    }
    $('command-result').textContent = JSON.stringify(await command(body), null, 2);
    await refresh();
  } catch (reason) { $('command-result').textContent = reason.message; }
};
connect().catch(showError);
