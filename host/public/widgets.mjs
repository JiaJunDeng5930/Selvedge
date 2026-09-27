import { eventForForm } from './renderer.mjs';
import { Markdown } from './markdown.mjs';

const surfaces = new WeakMap();
const element = (document, tag, className, text) => {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
};
const setText = (node, text) => { if (node.textContent !== text) node.textContent = text; };

// Unlike replaceChildren, a keyed splice doesn't detach unaffected editors,
// selections, disclosure widgets, or the stable prefix of a conversation.
function reconcile(parent, children) {
  const expected = new Set(children);
  for (const child of [...parent.childNodes]) if (!expected.has(child)) child.remove();
  for (let i = 0; i < children.length; i++) {
    if (parent.childNodes[i] !== children[i]) parent.insertBefore(children[i], parent.childNodes[i] ?? null);
  }
}

export function mount(root, tree, dispatch, options = {}) {
  const document = root.ownerDocument;
  let context = surfaces.get(root);
  if (!context) {
    context = { records: new Map(), drafts: new Map(), disclosures: new Map(), tabs: new Map() };
    surfaces.set(root, context);
  }
  Object.assign(context, options, { dispatch });
  const seen = new Set();
  let panel;
  let selected;
  const make = (tag, className, text) => element(document, tag, className, text);

  function record(model, key, create) {
    seen.add(key);
    let entry = context.records.get(key);
    if (entry && entry.kind !== model.kind) { entry.markdown?.dispose(); entry.node.remove(); entry = null; }
    if (!entry) {
      entry = create();
      Object.assign(entry, { kind: model.kind, key });
      entry.node.dataset.key = key;
      context.records.set(key, entry);
    }
    entry.model = model;
    return entry;
  }

  function field(form, descriptor) {
    const key = `${form.key}/${descriptor.name}`;
    let item = form.inputs.get(descriptor.name);
    if (item && item.kind !== descriptor.kind) { item.label.remove(); item = null; }
    if (!item) {
      const label = make('label', `field field-${descriptor.kind}`);
      const caption = make('span', 'field-label');
      let input;
      if (descriptor.kind === 'choice') input = make('select');
      else if (['multiline', 'json'].includes(descriptor.kind)) { input = make('textarea'); input.rows = 3; }
      else if (['integer', 'text'].includes(descriptor.kind)) {
        input = make('input'); input.type = descriptor.kind === 'integer' ? 'number' : 'text';
        if (descriptor.kind === 'integer') input.step = '1';
      } else throw new TypeError(`Unsupported field kind: ${descriptor.kind}`);
      input.id = encodeURIComponent(key);
      input.name = descriptor.name;
      input.addEventListener('input', () => context.drafts.set(key, input.value));
      input.addEventListener('keydown', event => {
        if (event.key === 'Enter' && (event.metaKey || event.ctrlKey) && !event.isComposing && event.keyCode !== 229) {
          event.preventDefault(); form.node.requestSubmit();
        }
      });
      label.append(caption, input);
      item = { label, caption, input, kind: descriptor.kind };
      form.inputs.set(descriptor.name, item);
    }
    setText(item.caption, descriptor.label);
    const input = item.input;
    input.required = descriptor.required;
    input.setAttribute('aria-label', descriptor.label);
    if (descriptor.kind === 'choice') {
      const signature = JSON.stringify(descriptor.choices);
      if (item.choices !== signature) {
        const choices = descriptor.choices.map(choice => {
          const option = make('option', '', choice.label); option.value = choice.value; return option;
        });
        reconcile(input, choices); item.choices = signature;
      }
    }
    const schema = descriptor.schema ?? {};
    if (descriptor.kind === 'integer') {
      if (schema.minimum !== undefined) input.min = String(schema.minimum);
      if (schema.maximum !== undefined) input.max = String(schema.maximum);
    }
    const value = context.drafts.get(key) ?? (descriptor.kind === 'json' ? JSON.stringify(descriptor.value) : String(descriptor.value ?? ''));
    if (input.value !== value) input.value = value;
    return item.label;
  }

  function draw(model, parent = '') {
    const key = `${parent}/${model.key}`;
    if (model.kind === 'action') {
      const entry = record(model, key, () => ({ node: make('button', 'action') }));
      const node = entry.node;
      node.type = 'button'; node.disabled = !model.enabled;
      setText(node, model.label);
      node.setAttribute('aria-current', String(model.selected));
      node.title = model.label;
      node.onclick = () => { if (entry.model.enabled) return Promise.resolve(context.dispatch(structuredClone(entry.model.event))).catch(() => {}); };
      if (model.selected && model.event?.type === 'select') selected = model.event.task_id;
      return node;
    }
    if (model.kind === 'text') {
      const entry = record(model, key, () => {
        const node = make('article', 'message');
        const title = make('h3', 'message-author'); const body = make('div', 'message-body');
        node.append(title, body); return { node, title, body };
      });
      entry.node.dataset.role = model.role;
      setText(entry.title, model.title);
      if (entry.text !== model.text) {
        entry.markdown?.dispose();
        if (model.role === 'assistant') {
          const adopted = context.takeMarkdown?.(model.text, selected);
          if (adopted) { entry.body.replaceChildren(adopted.root); entry.markdown = adopted; adopted.finish(); }
          else {
            const content = make('div', 'markdown'); entry.body.replaceChildren(content);
            entry.markdown = new Markdown(content, { smooth: false });
            entry.markdown.append(model.text); entry.markdown.finish();
          }
        } else setText(entry.body, model.text);
        entry.text = model.text;
      }
      return entry.node;
    }
    if (model.kind === 'value') {
      const entry = record(model, key, () => {
        const node = make('details', 'value-card'); const title = make('summary'); const body = make('pre');
        node.append(title, body); node.open = context.disclosures.get(key) ?? false;
        const entry = { node, title, body };
        node.addEventListener('toggle', () => {
          context.disclosures.set(key, node.open);
          if (node.open) setText(body, JSON.stringify(entry.model.value, null, 2));
        });
        return entry;
      });
      setText(entry.title, model.title);
      if (entry.node.open) setText(entry.body, JSON.stringify(model.value, null, 2));
      return entry.node;
    }
    if (model.kind === 'form') {
      const entry = record(model, key, () => {
        const node = make('form', 'widget-form'); const title = make('h3', 'form-title');
        const fieldset = make('fieldset'); const fields = make('div', 'fields');
        const footer = make('div', 'form-footer'); const hint = make('span', 'keyboard-hint', '⌘ / Ctrl + Enter');
        const button = make('button', 'primary'); button.type = 'submit';
        const error = make('p', 'form-error'); error.setAttribute('role', 'alert'); error.hidden = true;
        footer.append(hint, button); fieldset.append(fields, footer); node.append(title, fieldset, error);
        return { node, title, fieldset, fields, button, error, inputs: new Map(), pending: false };
      });
      setText(entry.title, model.title); setText(entry.button, model.label);
      entry.fieldset.disabled = !model.enabled; entry.button.disabled = entry.pending;
      reconcile(entry.fields, model.fields.map(descriptor => field(entry, descriptor)));
      for (const name of entry.inputs.keys()) if (!model.fields.some(descriptor => descriptor.name === name)) entry.inputs.delete(name);
      entry.node.onsubmit = async event => {
        event.preventDefault();
        if (!entry.model.enabled || entry.pending) return;
        entry.error.hidden = true;
        try {
          const values = Object.fromEntries([...entry.inputs].map(([name, item]) => [name, item.input.value]));
          const command = eventForForm(entry.model, values);
          entry.pending = true; entry.button.disabled = true;
          await context.dispatch(command, key, values);
        } catch (error) { entry.error.textContent = error.message; entry.error.hidden = false; }
        finally { entry.pending = false; entry.button.disabled = false; }
      };
      return entry.node;
    }
    if (model.kind !== 'group') throw new TypeError(`Unsupported presentation node: ${model.kind}`);
    if (model.role === 'panel') {
      const entry = record(model, key, () => {
        const node = make('section', 'workspace');
        const header = make('header', 'thread-header'); const title = make('h2');
        const toggle = make('button', 'quiet-button', 'Details'); toggle.type = 'button';
        const scroll = make('div', 'thread-scroll'); const thread = make('div', 'thread');
        const live = make('div', 'live-streams'); const compose = make('div', 'composer-dock');
        const inspector = make('aside', 'inspector'); inspector.hidden = true; inspector.setAttribute('aria-label', 'Task details');
        const bottom = make('button', 'scroll-bottom', '↓ Scroll to bottom'); bottom.type = 'button'; bottom.hidden = true;
        header.append(title, toggle); scroll.append(thread); node.append(header, scroll, compose, inspector, bottom);
        const entry = { node, title, toggle, scroll, thread, live, compose, inspector, bottom, follow: true };
        toggle.onclick = () => {
          inspector.hidden = !inspector.hidden; node.dataset.inspector = String(!inspector.hidden);
          toggle.setAttribute('aria-expanded', String(!inspector.hidden));
        };
        toggle.setAttribute('aria-expanded', 'false');
        scroll.addEventListener('scroll', () => { entry.follow = scroll.scrollHeight - scroll.scrollTop - scroll.clientHeight < 72; bottom.hidden = entry.follow; }, { passive: true });
        bottom.onclick = () => { entry.follow = true; scroll.scrollTop = scroll.scrollHeight; bottom.hidden = true; };
        if (typeof ResizeObserver !== 'undefined') {
          entry.observer = new ResizeObserver(() => { if (entry.follow) scroll.scrollTop = scroll.scrollHeight; });
          entry.observer.observe(thread);
        }
        return entry;
      });
      panel = entry;
      entry.node.dataset.role = model.role; setText(entry.title, model.title);
      const conversation = [], composers = [], details = [];
      for (const child of model.children) {
        const node = draw(child, key);
        if (['transcript', 'operations'].includes(child.role)) conversation.push(node);
        else if (child.role === 'compose') composers.push(node);
        else details.push(node);
      }
      reconcile(entry.thread, [...conversation, entry.live]);
      reconcile(entry.compose, composers); reconcile(entry.inspector, details);
      entry.toggle.hidden = !details.length;
      return entry.node;
    }
    if (model.role === 'compose') {
      const entry = record(model, key, () => ({ node: make('section', 'composer'), tabs: make('div', 'compose-tabs'), content: make('div'), buttons: new Map() }));
      entry.tabs.setAttribute('role', 'tablist'); entry.tabs.setAttribute('aria-label', model.title);
      const active = context.tabs.get(key) ?? model.children[0]?.key;
      const buttons = [], forms = [];
      for (const child of model.children) {
        const form = draw(child, key);
        const button = entry.buttons.get(child.key) ?? make('button', 'compose-tab');
        entry.buttons.set(child.key, button);
        setText(button, child.label ?? child.title);
        button.type = 'button'; button.setAttribute('role', 'tab'); button.setAttribute('aria-selected', String(child.key === active));
        form.hidden = child.key !== active;
        button.onclick = () => {
          context.tabs.set(key, child.key);
          for (let i = 0; i < forms.length; i++) {
            forms[i].hidden = model.children[i].key !== child.key;
            buttons[i].setAttribute('aria-selected', String(!forms[i].hidden));
          }
          form.querySelector('textarea, input')?.focus();
        };
        buttons.push(button); forms.push(form);
      }
      reconcile(entry.tabs, buttons); reconcile(entry.content, forms); reconcile(entry.node, [entry.tabs, entry.content]);
      return entry.node;
    }
    const entry = record(model, key, () => {
      const node = make(model.role === 'details' ? 'details' : model.role === 'navigation' ? 'nav' : 'section');
      const title = make(model.role === 'details' ? 'summary' : 'h2', 'group-title');
      const content = make('div', 'group-content'); node.append(title, content);
      if (model.role === 'details') {
        node.open = context.disclosures.get(key) ?? false;
        node.addEventListener('toggle', () => context.disclosures.set(key, node.open));
      }
      return { node, title, content };
    });
    entry.node.dataset.role = model.role; setText(entry.title, model.title); entry.title.hidden = !model.title;
    if (model.role === 'navigation') entry.node.setAttribute('aria-label', model.title);
    reconcile(entry.content, model.children.map(child => draw(child, key)));
    return entry.node;
  }

  reconcile(root, [draw(tree)]);
  for (const [key, entry] of context.records) if (!seen.has(key)) {
    entry.markdown?.dispose(); entry.observer?.disconnect(); context.records.delete(key);
  }
  return { liveRoot: panel?.live, selected, scrollToBottom: () => panel?.bottom.onclick(),
    showHistory: () => { if (panel) { panel.follow = false; panel.scroll.scrollTop = 0; } },
    dispose: () => { for (const entry of context.records.values()) { entry.markdown?.dispose(); entry.observer?.disconnect(); } surfaces.delete(root); },
  };
}
