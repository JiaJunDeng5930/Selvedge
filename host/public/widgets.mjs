import { eventForForm, eventForChange } from './renderer.mjs';
import { Markdown } from './markdown.mjs';
import { collectionField } from './collection-fields.mjs';
import { choicePicker } from './picker.mjs';
import { BoardSurface, boardNavigation, boardIcon } from './board.mjs';
import { element, setText, icon, reconcile } from './dom.mjs';
import { ThreadSurface, ComposerSurface, ActivitySurface, createThreadLink } from './conversation.mjs';

const surfaces = new WeakMap();

function resizeEditor(input) {
  if (!input.isConnected || !input.getClientRects().length) return;
  input.style.height = 'auto';
  input.style.height = `${Math.min(240, Math.max(56, input.scrollHeight))}px`;
}

function disposeRecord(entry) {
  entry.markdown?.dispose(); entry.dispose?.();
  for (const item of entry.inputs?.values() ?? []) { item.collection?.dispose(); item.picker?.dispose(); }
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
    if (entry && entry.kind !== model.kind) { disposeRecord(entry); entry.node.remove(); entry = null; }
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
    const key = `${form.draftKey}/${descriptor.name}`;
    let item = form.inputs.get(descriptor.name);
    if (item && item.kind !== descriptor.kind) { item.collection?.dispose(); item.picker?.dispose(); item.label.remove(); item = null; context.drafts.delete(key); }
    if (!item) {
      const composite = ['tags', 'attachments', 'workspace'].includes(descriptor.kind);
      const customChoice = ['choice', 'integer-choice', 'profile-choice'].includes(descriptor.kind);
      const label = make(composite || customChoice ? 'div' : 'label', `field field-${descriptor.kind}`);
      const caption = make('span', 'field-label');
      let input, collection;
      if (composite) {
        collection = collectionField(document, descriptor.kind, context,
          () => context.drafts.set(key, input.value),
          pending => {
            form.uploading ??= new Set();
            if (pending) form.uploading.add(key); else form.uploading.delete(key);
            form.button.disabled = !!form.uploading.size || form.pending || form.updating || !form.model.enabled;
          });
        input = collection.input;
      } else if (['choice', 'integer-choice', 'profile-choice'].includes(descriptor.kind)) input = make('select');
      else if (['multiline', 'json'].includes(descriptor.kind)) { input = make('textarea'); input.rows = 3; }
      else if (descriptor.kind === 'boolean') { input = make('input'); input.type = 'checkbox'; }
      else if (['integer', 'text'].includes(descriptor.kind)) {
        input = make('input'); input.type = descriptor.kind === 'integer' ? 'number' : 'text';
        if (descriptor.kind === 'integer') input.step = '1';
      } else throw new TypeError(`Unsupported field kind: ${descriptor.kind}`);
      input.id = encodeURIComponent(key);
      input.name = descriptor.name;
      input.addEventListener('input', () => {
        if (descriptor.kind === 'boolean') input.value = String(input.checked);
        context.drafts.set(key, input.value);
        if (form.composer && descriptor.kind === 'multiline') resizeEditor(input);
      });
      input.addEventListener('change', async () => {
        context.drafts.set(key, input.value);
        const change = form.model.changes?.[descriptor.name];
        if (!change || form.updating || form.pending || !form.model.enabled) return;
        form.error.hidden = true;
        try {
          const event = eventForChange(change, input.value);
          for (const name of change.reset_fields ?? []) {
            if (!form.model.fields.some(field => field.name === name)) throw new TypeError('Unknown dependent field');
            context.drafts.delete(`${form.draftKey}/${name}`);
          }
          form.updating = true; form.fieldset.disabled = true; form.button.disabled = true;
          await context.dispatch(event);
        } catch (error) { form.error.textContent = error.message; form.error.hidden = false; }
        finally {
          form.updating = false; form.fieldset.disabled = !form.model.enabled;
          form.button.disabled = form.pending || !form.model.enabled;
          if (document.activeElement === document.body && input.isConnected) input.focus();
        }
      });
      input.addEventListener('keydown', event => {
        const send = form.composer && descriptor.kind === 'multiline' && !event.shiftKey && !event.altKey;
        if (event.key === 'Enter' && (send || ((event.metaKey || event.ctrlKey) && !event.shiftKey)) && !event.isComposing && event.keyCode !== 229) {
          event.preventDefault(); form.node.requestSubmit();
        }
      });
      const picker = input.tagName === 'SELECT' ? choicePicker(document, input, form.board ? value => boardIcon(document, value) : undefined) : undefined;
      label.append(caption, collection?.root ?? picker?.root ?? input);
      label.dataset.field = descriptor.name;
      item = { label, caption, input, collection, picker, kind: descriptor.kind };
      form.inputs.set(descriptor.name, item);
    }
    setText(item.caption, descriptor.label);
    const input = item.input;
    input.required = descriptor.required;
    input.disabled = descriptor.enabled === false;
    input.setAttribute('aria-label', descriptor.label);
    input.title = descriptor.label;
    input.placeholder = form.board || (form.composer && descriptor.kind === 'multiline') ? descriptor.label : '';
    if (['choice', 'integer-choice', 'profile-choice'].includes(descriptor.kind)) {
      const signature = JSON.stringify(descriptor.choices);
      if (item.choices !== signature) {
        const choices = descriptor.choices.map(choice => {
          const option = make('option', '', choice.label); option.value = choice.value; return option;
        });
        reconcile(input, choices); item.choices = signature;
      }
      if (context.drafts.has(key) && !descriptor.choices.some(choice => choice.value === context.drafts.get(key))) context.drafts.delete(key);
    }
    const schema = descriptor.schema ?? {};
    if (descriptor.kind === 'integer') {
      if (schema.minimum !== undefined) input.min = String(schema.minimum);
      if (schema.maximum !== undefined) input.max = String(schema.maximum);
    }
    const value = context.drafts.get(key) ?? (['json', 'tags', 'attachments', 'workspace'].includes(descriptor.kind) ? JSON.stringify(descriptor.value) : String(descriptor.value ?? ''));
    if (input.value !== value) input.value = value;
    if (descriptor.kind === 'boolean') { input.checked = value === 'true'; input.required = false; }
    if (item.collection) {
      item.collection.editor.setAttribute('aria-label', descriptor.label);
      item.collection.update(value, descriptor.enabled !== false && form.model.enabled, descriptor.choices ?? []);
    }
    item.picker?.update(descriptor);
    if (form.composer && descriptor.kind === 'multiline') requestAnimationFrame(() => resizeEditor(input));
    return item.label;
  }

  function draw(model, parent = '', parentRole = '', options = {}) {
    const key = `${parent}/${options.key ?? model.key}`;
    if (model.kind === 'thread') {
      selected = model.task_id ?? undefined;
      const entry = record(model, key, () => {
        const thread = new ThreadSurface(document, context, key);
        return { node: thread.node, thread, dispose: () => thread.dispose() };
      });
      panel = entry.thread;
      entry.thread.update(model, (child, role = '') => draw(child, key, role));
      return entry.node;
    }
    if (model.kind === 'thread-link') {
      const entry = record(model, key, () => createThreadLink(document));
      setText(entry.title, model.title);
      entry.node.dataset.action = model.key; entry.node.dataset.state = model.state;
      entry.node.setAttribute('aria-current', String(model.selected));
      entry.node.setAttribute('aria-label', `${model.title} · ${model.state} · ${model.subtitle}`);
      entry.node.title = `${model.title}\n${model.state} · ${model.subtitle}`;
      entry.node.onclick = () => Promise.resolve(context.dispatch(structuredClone(entry.model.event))).catch(() => {});
      return entry.node;
    }
    if (model.kind === 'composer') {
      const entry = record(model, key, () => {
        const composer = new ComposerSurface(document, context, key);
        return { node: composer.node, composer, dispose: () => composer.dispose() };
      });
      entry.composer.update(model, (form, options) => draw(form, key, 'composer', options), child => draw(child, key, 'composer-actions'));
      return entry.node;
    }
    if (model.kind === 'activity') {
      const entry = record(model, key, () => {
        const activity = new ActivitySurface(document, context, key);
        return { node: activity.node, activity };
      });
      entry.activity.update(model, model.children.map(child => draw(child, key, 'activity')));
      return entry.node;
    }
    if (model.kind === 'composition') {
      const entry = record(model, key, () => {
        if (model.role === 'board-navigation') return { node: make('div', 'board-navigation') };
        if (model.role !== 'task-board') throw new TypeError(`Unsupported composition: ${model.role}`);
        const board = new BoardSurface(document, context);
        return { node: board.node, board, dispose: () => board.dispose() };
      });
      if (model.role === 'board-navigation') boardNavigation(entry.node, model.properties.actions, context);
      else {
        selected = model.properties.active_task ?? undefined;
        entry.board.update(model.properties,
          form => draw({ ...form, kind: 'form' }, key, 'board-form'),
          model.children.map(child => draw(child, key, 'board-conversation')));
      }
      return entry.node;
    }
    if (model.kind === 'action') {
      const entry = record(model, key, () => {
        const node = make('button', 'action'); const label = make('span', 'action-label'); const mark = icon(document, 'new');
        node.append(mark, label); return { node, label, mark };
      });
      const node = entry.node;
      node.type = 'button'; node.disabled = !model.enabled;
      setText(entry.label, model.label); entry.mark.toggleAttribute('hidden', model.key !== 'new');
      node.dataset.action = model.key;
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
        const editor = make('div', 'form-editor'); const controls = make('div', 'form-controls');
        const options = make('details', 'form-options'); const summary = make('summary', 'icon-button');
        const optionFields = make('div', 'form-option-fields');
        summary.append(icon(document, 'settings')); summary.setAttribute('aria-label', 'Additional task settings'); summary.title = 'Additional task settings';
        options.append(summary, optionFields);
        options.open = context.disclosures.get(`${key}/options`) ?? false;
        options.addEventListener('toggle', () => context.disclosures.set(`${key}/options`, options.open));
        options.addEventListener('keydown', event => { if (event.key === 'Escape' && options.open) { event.stopPropagation(); options.open = false; summary.focus(); } });
        const footer = make('div', 'form-footer'); const hint = make('span', 'keyboard-hint', '⌘ / Ctrl + Enter');
        const button = make('button', 'primary'); button.type = 'submit';
        const buttonLabel = make('span', 'submit-label'); const buttonIcon = icon(document, 'up'); button.append(buttonIcon, buttonLabel);
        const error = make('p', 'form-error'); error.setAttribute('role', 'alert'); error.hidden = true;
        footer.append(controls, hint, button); editor.append(fields, footer); fieldset.append(editor); node.append(title, fieldset, error);
        node.addEventListener('invalid', event => { if (optionFields.contains(event.target)) options.open = true; }, true);
        return { node, title, fieldset, fields, controls, options, optionFields, button, buttonLabel, buttonIcon, error, inputs: new Map(), pending: false };
      });
      entry.composer = parentRole === 'composer';
      entry.board = parentRole === 'board-form';
      entry.draftKey = options.draftKey ?? key;
      entry.node.dataset.key = `${parent}/${model.key}`;
      entry.node.dataset.layout = entry.composer ? 'composer' : 'form';
      setText(entry.title, model.title); setText(entry.buttonLabel, model.label);
      entry.button.setAttribute('aria-label', model.label); entry.button.title = entry.composer ? `${model.label} (Enter)` : model.label;
      entry.buttonIcon.toggleAttribute('hidden', !entry.composer);
      entry.fieldset.disabled = !model.enabled || entry.updating; entry.button.disabled = entry.pending || entry.updating || !!entry.uploading?.size || !model.enabled;
      const main = [], controls = [], optionFields = [];
      for (const descriptor of model.fields) {
        const label = field(entry, descriptor);
        if (!entry.composer || descriptor.kind === 'multiline') main.push(label);
        else if (descriptor.kind === 'json') optionFields.push(label);
        else controls.push(label);
      }
      reconcile(entry.fields, main); reconcile(entry.optionFields, optionFields);
      entry.options.hidden = !optionFields.length;
      reconcile(entry.controls, [...(options.leadingControls ?? []), ...controls, entry.options, ...(options.trailingControls ?? [])]);
      for (const name of entry.inputs.keys()) if (!model.fields.some(descriptor => descriptor.name === name)) {
        entry.inputs.get(name).collection?.dispose(); entry.inputs.get(name).picker?.dispose(); entry.inputs.delete(name);
      }
      entry.node.onsubmit = async event => {
        event.preventDefault();
        if (!entry.model.enabled || entry.pending || entry.updating || entry.uploading?.size) return;
        entry.error.hidden = true;
        let accepted = false;
        try {
          const values = Object.fromEntries([...entry.inputs].map(([name, item]) => [name, item.input.value]));
          const command = eventForForm(entry.model, values);
          entry.pending = true; entry.button.disabled = true;
          await context.dispatch(command, entry.draftKey, values, () => entry.model.retain_fields);
          accepted = true;
        } catch (error) {
          entry.error.textContent = error.message; entry.error.hidden = false;
          if (error instanceof SyntaxError && entry.optionFields.childElementCount) entry.options.open = true;
        }
        finally {
          entry.pending = false; entry.button.disabled = entry.updating || !!entry.uploading?.size || !entry.model.enabled;
          if (accepted && entry.node.isConnected && entry.model.retain_fields?.length) {
            entry.node.querySelector('input:not([type=hidden]):not(.choice-native):not([type=file]), textarea')?.focus();
          }
        }
      };
      return entry.node;
    }
    if (model.kind !== 'group') throw new TypeError(`Unsupported presentation node: ${model.kind}`);
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
    reconcile(entry.content, model.children.map(child => draw(child, key, model.role)));
    return entry.node;
  }

  reconcile(root, [draw(tree)]);
  for (const [key, entry] of context.records) if (!seen.has(key)) {
    disposeRecord(entry);
    context.records.delete(key);
  }
  return { liveRoot: panel?.live, selected, scrollToBottom: () => panel?.scrolling.end(),
    showHistory: () => panel?.scrolling.start(),
    dispose: () => { for (const entry of context.records.values()) disposeRecord(entry); surfaces.delete(root); },
  };
}
