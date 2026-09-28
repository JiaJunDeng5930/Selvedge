import { eventForChange, eventForDrop } from './renderer.mjs';

// This adapter follows Better Codex's board layout and interactions. Native
// descriptors supply every card, group, action, permission and bound command.
// Its local state is limited to focus, disclosure, scrolling and an in-flight
// pointer gesture; there is no optimistic card/task store in the browser.
const make = (document, tag, className = '', text) => {
  const node = document.createElement(tag); node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
};
const text = (node, value = '') => { if (node.textContent !== String(value)) node.textContent = String(value); };
function reconcile(parent, children) {
  const retained = new Set(children);
  for (let index = 0; index < children.length; index++) {
    const child = children[index], previous = parent.children[index];
    if (previous === child) continue;
    if (parent.moveBefore && child.isConnected && parent.isConnected) parent.moveBefore(child, previous ?? null);
    else parent.insertBefore(child, previous ?? null);
  }
  for (const child of [...parent.children]) if (!retained.has(child)) child.remove();
}

const paths = {
  board: ['M3 5h18v14H3z', 'M9 5v14M15 5v14'],
  message: ['M4 4h16v12H8l-4 4V4Z'],
  folder: ['M3 6h7l2 2h9v12H3V6Z'],
  bot: ['M8 5h8l4 4v10H4V9l4-4Z', 'M9 12h.01M15 12h.01M9 16h6M12 2v3'],
  user: ['M16 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z', 'M4 21v-2a8 8 0 0 1 16 0v2'],
  users: ['M15 7a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z', 'M6 21v-3a6 6 0 0 1 12 0v3M19 5a3 3 0 0 1 0 6M21 21v-3'],
  plus: ['M12 5v14M5 12h14'], close: ['m6 6 12 12M18 6 6 18'],
  check: ['m5 12 4 4L19 6'], chevron: ['m7 10 5 5 5-5'],
  archive: ['M4 8h16v13H4V8ZM3 3h18v5H3zM9 12h6'],
  external: ['M14 3h7v7M10 14 21 3', 'M10 3H3v18h18v-7'],
  edit: ['m16 3 5 5-12 12H4v-5L16 3ZM13 6l5 5'],
  paperclip: ['m8 13 7-7a3 3 0 0 1 4 4L9 20a5 5 0 0 1-7-7L13 2', 'm5 15 10-10'],
  sparkles: ['m12 2 3 7 7 3-7 3-3 7-3-7-7-3 7-3 3-7Z'],
  filter: ['M4 7h16M7 12h10M10 17h4'],
  search: ['M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0ZM16 16l6 6'],
  more: ['M5 12h.01M12 12h.01M19 12h.01'],
  tag: ['M3 3h8l10 10-8 8L3 11V3ZM7 7h.01'],
  clock: ['M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0ZM12 6v6l4 2'],
  pin: ['m7 3 10 0-2 8 4 4H5l4-4-2-8ZM12 15v7'],
  play: ['m8 4 12 8-12 8V4Z'], trash: ['M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7M14 10v7'],
  restore: ['M4 10a8 8 0 1 1 1 9M4 4v6h6'], expand: ['M8 3H3v5M16 3h5v5M3 16v5h5M21 16v5h-5'],
};
export function boardIcon(document, name = '') {
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  for (const [key, value] of Object.entries({ viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor',
    'stroke-width': '1.6', 'stroke-linecap': 'round', 'stroke-linejoin': 'round', 'aria-hidden': 'true', focusable: 'false' })) svg.setAttribute(key, value);
  svg.classList.add('icon', 'board-icon');
  let strokes = paths[name];
  if (name.startsWith('status/')) {
    svg.dataset.tone = name.slice(7);
    strokes = ['M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z'];
    if (name.endsWith('/done')) strokes.push('m7 12 3 3 7-7');
    else if (name.endsWith('/in_progress')) strokes.push('M12 3v18');
    else if (name.endsWith('/blocked')) strokes.push('M12 7v6M12 17h.01');
    else if (name.endsWith('/in_review')) strokes.push('M8 12h8M12 8v8');
  } else if (name.startsWith('priority/')) {
    svg.dataset.priority = name.slice(9);
    strokes = ['M5 19v-5M10 19v-8M15 19V8M20 19V4'];
    if (name.endsWith('/none')) strokes = ['M5 12h14'];
  }
  for (const d of strokes ?? paths[name.startsWith('profile/') || name.startsWith('agent/') ? 'bot' : 'user']) {
    const path = document.createElementNS(svg.namespaceURI, 'path'); path.setAttribute('d', d); svg.append(path);
  }
  return svg;
}

function action(document, model, context, className = 'board-button', onError = () => {}) {
  const button = make(document, 'button', className); button.type = 'button';
  const label = make(document, 'span');
  button.append(boardIcon(document, model.icon), label);
  button.update = value => {
    button.model = value; button.disabled = !value.enabled; button.dataset.action = value.key;
    button.setAttribute('aria-label', value.label); button.title = value.label;
    button.setAttribute('aria-pressed', String(!!value.selected)); text(label, value.label);
  };
  button.update(model);
  button.onclick = async event => {
    event.stopPropagation();
    if (!button.model.enabled) return;
    try { await context.dispatch(structuredClone(button.model.event)); }
    catch (error) { onError(error); }
  };
  return button;
}

const navigationNodes = new WeakMap();
export function boardNavigation(root, models, context) {
  let nodes = navigationNodes.get(root);
  if (!nodes) { nodes = new Map(); navigationNodes.set(root, nodes); }
  const children = models.map(model => {
    let button = nodes.get(model.key);
    if (!button) { button = action(root.ownerDocument, model, context, 'board-nav-item'); nodes.set(model.key, button); }
    button.update(model); button.setAttribute('aria-current', model.selected ? 'page' : 'false'); return button;
  });
  reconcile(root, children);
}

export class BoardSurface {
  constructor(document, context) {
    this.document = document; this.context = context; this.parts = new Map(); this.cards = new Map();
    this.controller = new AbortController(); this.key = undefined; this.disposed = false;
    this.node = make(document, 'section', 'board-application');
    this.sidebar = make(document, 'nav', 'board-sidebar'); this.sidebar.dataset.role = 'navigation';
    this.sidebar.setAttribute('aria-label', '工作区');
    this.main = make(document, 'section', 'board-workspace');
    this.toolbar = make(document, 'header', 'board-toolbar');
    this.body = make(document, 'div', 'board-body');
    this.error = make(document, 'p', 'board-error'); this.error.hidden = true; this.error.setAttribute('role', 'alert');
    this.main.append(this.toolbar, this.error, this.body);
    this.modal = make(document, 'dialog', 'board-dialog');
    this.modal.setAttribute('aria-modal', 'true');
    this.modalHead = make(document, 'header', 'board-dialog-head');
    this.modalTitle = make(document, 'h2', 'board-dialog-title');
    this.modalTitle.id = 'board-dialog-title'; this.modal.setAttribute('aria-labelledby', this.modalTitle.id);
    this.modalControls = make(document, 'div', 'board-dialog-controls');
    this.modalHead.append(this.modalTitle, this.modalControls);
    this.modalBody = make(document, 'div', 'board-dialog-body');
    this.modal.append(this.modalHead, this.modalBody);
    this.node.append(this.sidebar, this.main, this.modal);
    this.modal.addEventListener('cancel', event => { event.preventDefault(); this.invoke(this.properties?.dialog?.close); });
    this.modal.addEventListener('pointerdown', event => { this.backdropDown = event.target === this.modal; });
    this.modal.addEventListener('click', event => {
      if (event.target === this.modal && this.backdropDown) {
        const rect = this.modal.getBoundingClientRect();
        if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) this.invoke(this.properties?.dialog?.close);
      }
    });
    document.addEventListener('pointerdown', event => {
      for (const popup of this.node.querySelectorAll('.board-popup[open]')) if (!popup.contains(event.target)) popup.open = false;
    }, { signal: this.controller.signal });
    this.node.addEventListener('keydown', event => {
      if (event.key !== 'Escape') return;
      if (this.drag) { event.preventDefault(); event.stopPropagation(); this.endDrag(); return; }
      const popup = event.target.closest('.board-popup[open]');
      if (popup) { event.preventDefault(); event.stopPropagation(); popup.open = false; popup.querySelector('summary').focus(); }
    });
  }

  part(key, create) {
    this.seen.add(key);
    if (!this.parts.has(key)) this.parts.set(key, create());
    return this.parts.get(key);
  }
  fail(error) { text(this.error, error.message); this.error.hidden = false; }
  async invoke(model) {
    if (!model?.enabled) return;
    try { await this.context.dispatch(structuredClone(model.event)); }
    catch (error) { this.fail(error); }
  }
  button(model, key, className = 'board-button') {
    if (!model) return null;
    const button = this.part(`action/${key ?? model.key}`, () => action(this.document, model, this.context, className, error => this.fail(error)));
    button.update(model); button.className = className; return button;
  }
  label(key, value, className = '') {
    const label = this.part(`label/${key}`, () => make(this.document, 'span', className)); text(label, value); return label;
  }
  popup(key, label, items, icon = 'chevron') {
    const entry = this.part(`popup/${key}`, () => {
      const node = make(this.document, 'details', 'board-popup');
      const summary = make(this.document, 'summary', 'board-button');
      const caption = make(this.document, 'span'); summary.append(boardIcon(this.document, icon), caption);
      const menu = make(this.document, 'div', 'board-menu'); node.append(summary, menu);
      return { node, summary, caption, menu };
    });
    text(entry.caption, label); entry.summary.setAttribute('aria-label', label);
    reconcile(entry.menu, items.filter(Boolean)); return entry.node;
  }

  update(properties, form, conversation) {
    this.properties = properties; this.seen = new Set(); this.renderForm = form;
    this.node.dataset.pane = properties.pane; this.error.hidden = true;
    boardNavigation(this.sidebar, properties.navigation, this.context);
    if (properties.body?.toolbar) this.drawBoard(properties.body);
    else this.drawRows(properties.body ?? {});
    this.drawDialog(properties.dialog, conversation);
    for (const key of this.parts.keys()) if (!this.seen.has(key)) {
      this.parts.get(key).dispose?.(); this.parts.delete(key);
    }
    const cardKeys = new Set((properties.body?.columns ?? []).flatMap(column => column.cards.map(card => card.key)));
    for (const key of this.cards.keys()) if (!cardKeys.has(key)) this.cards.delete(key);
  }

  drawBoard(body) {
    const toolbar = body.toolbar;
    const tabs = this.part('toolbar/tabs', () => make(this.document, 'div', 'board-tabs'));
    const tools = this.part('toolbar/tools', () => make(this.document, 'div', 'board-toolbar-tools'));
    const working = toolbar.tabs.find(model => model.key === 'view/working');
    reconcile(tabs, toolbar.tabs.filter(model => model !== working).map(model => this.button(model, `tab/${model.key}`)));
    const search = this.part('toolbar/search', () => {
      const input = make(this.document, 'input', 'board-search'); input.type = 'search';
      input.placeholder = '搜索任务'; input.setAttribute('aria-label', '搜索任务');
      input.addEventListener('input', () => {
        clearTimeout(this.searchTimer);
        const value = input.value;
        this.searchTimer = setTimeout(() => {
          this.searchTimer = undefined;
          this.context.dispatch(eventForChange(this.properties.body.toolbar.search, value)).catch(error => this.fail(error));
        }, 180);
      });
      return input;
    });
    if (this.document.activeElement !== search && !this.searchTimer && search.value !== toolbar.search.value) search.value = toolbar.search.value;
    const groups = body.filter_groups.map(group => this.popup(`filters/${group.key}`, `${group.label}${group.count ? ` · ${group.count}` : ''}`,
      group.items.map(item => this.button(item, item.key, 'board-menu-item')), group.icon));
    groups.push(this.button(body.clear_filters, 'filter/clear', 'board-menu-item'));
    const filter = this.popup('filters', body.filter_count ? `${body.filter_count} 个筛选` : '筛选', groups, 'filter');
    const automatic = this.button(toolbar.toggle_automatic, 'toolbar/automatic', 'board-button board-automatic');
    automatic.dataset.on = String(toolbar.automatic); automatic.setAttribute('role', 'switch'); automatic.setAttribute('aria-checked', String(toolbar.automatic));
    const split = this.part('toolbar/split', () => make(this.document, 'div', 'board-create-split'));
    reconcile(split, [this.button(toolbar.create, 'toolbar/create', 'board-button board-primary'),
      this.popup('create-more', '更多创建选项', [this.button(toolbar.create_project, 'toolbar/create-project', 'board-menu-item')])]);
    reconcile(tools, [this.button(working, 'toolbar/working', 'board-button board-working'), search, filter, automatic, split].filter(Boolean));
    reconcile(this.toolbar, [tabs, tools]);
    const columns = body.columns.map(column => this.drawColumn(column));
    const lanes = this.part('board/lanes', () => make(this.document, 'div', 'board-lanes'));
    reconcile(lanes, columns); reconcile(this.body, [lanes]); this.lanes = lanes;
  }

  drawColumn(column) {
    const entry = this.part(`column/${column.key}`, () => {
      const node = make(this.document, 'section', 'board-column'); node.dataset.status = column.key;
      const header = make(this.document, 'header', 'board-column-head');
      const title = make(this.document, 'h2', 'board-column-title');
      title.append(boardIcon(this.document, column.icon));
      const label = make(this.document, 'span'), count = make(this.document, 'span', 'board-count');
      title.append(label, count);
      const controls = make(this.document, 'div', 'board-column-controls');
      const cards = make(this.document, 'div', 'board-cards'); header.append(title, controls); node.append(header, cards);
      return { node, label, count, controls, cards };
    });
    entry.node.dropModel = column.drop; text(entry.label, column.label); text(entry.count, column.count);
    entry.node.setAttribute('aria-label', `${column.label} · ${column.count}`);
    reconcile(entry.controls, [this.button(column.add ?? column.open, `column/${column.key}`, 'board-button board-icon-only')].filter(Boolean));
    reconcile(entry.cards, column.cards.map(card => this.drawCard(card)));
    if (column.open && !column.cards.length) reconcile(entry.cards, [this.button(column.open, 'archive/hint', 'board-archive-target')]);
    return entry.node;
  }

  drawCard(card) {
    let entry = this.cards.get(card.key);
    if (!entry) {
      const node = make(this.document, 'article', 'board-card'); node.tabIndex = 0; node.setAttribute('role', 'button');
      const top = make(this.document, 'div', 'board-card-top');
      const identity = make(this.document, 'span', 'board-card-identity'), activity = make(this.document, 'span', 'board-card-activity');
      const menu = make(this.document, 'button', 'board-card-menu'); menu.type = 'button'; menu.append(boardIcon(this.document, 'more'));
      top.append(identity, activity, menu);
      const title = make(this.document, 'h3', 'board-card-title'), description = make(this.document, 'p', 'board-card-description');
      const chips = make(this.document, 'div', 'board-chips'), footer = make(this.document, 'footer', 'board-card-footer');
      const owner = make(this.document, 'span', 'board-card-owner'), updated = make(this.document, 'span', 'board-card-updated');
      footer.append(owner, updated); node.append(top, title, description, chips, footer);
      entry = { node, identity, activity, menu, title, description, chips, owner, updated };
      node.onclick = event => { if (!event.target.closest('button') && Date.now() > (this.suppressClick ?? 0)) this.invoke(entry.model.open); };
      node.onkeydown = event => {
        if (event.target !== node) return;
        if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); this.invoke(entry.model.open); }
        if (event.key === 'ContextMenu' || (event.key === 'F10' && event.shiftKey)) { event.preventDefault(); this.contextPoint = null; this.invoke(entry.model.context); }
      };
      node.oncontextmenu = event => { event.preventDefault(); this.contextPoint = { x: event.clientX, y: event.clientY }; this.invoke(entry.model.context); };
      menu.onclick = event => {
        event.stopPropagation(); const rect = menu.getBoundingClientRect();
        this.contextPoint = { x: rect.left, y: rect.bottom }; this.invoke(entry.model.context);
      };
      node.ondragstart = event => event.preventDefault();
      node.onpointerdown = event => this.startPointer(event, entry);
      this.cards.set(card.key, entry);
    }
    entry.model = card; entry.node.dataset.card = card.key; entry.node.dataset.activity = card.activity;
    entry.node.draggable = card.draggable;
    entry.node.setAttribute('aria-label', `${card.identifier} · ${card.title}`);
    entry.menu.title = card.context.label; entry.menu.setAttribute('aria-label', `${card.identifier} · ${card.context.label}`); entry.menu.disabled = !card.context.enabled;
    const signature = JSON.stringify(card);
    if (entry.signature !== signature) {
      entry.identity.replaceChildren(boardIcon(this.document, `priority/${card.priority}`), make(this.document, 'span', '', card.identifier));
      if (card.pinned) entry.identity.append(boardIcon(this.document, 'pin'));
      entry.identity.title = card.priority_label;
      text(entry.activity, card.activity_label); entry.activity.title = card.activity_label;
      text(entry.title, card.title); text(entry.description, card.description); entry.description.hidden = !card.description;
      entry.chips.replaceChildren(...[...(card.has_project ? [card.project] : []), ...card.labels].map(value => make(this.document, 'span', 'board-chip', value)));
      entry.owner.replaceChildren(boardIcon(this.document, card.owner_icon), make(this.document, 'span', '', card.owner));
      text(entry.updated, `更新于 ${card.updated}`); entry.signature = signature;
    }
    return entry.node;
  }

  drawRows(body) {
    const heading = this.part('rows/title', () => make(this.document, 'h1', 'board-page-title')); text(heading, body.title);
    reconcile(this.toolbar, [heading, this.button(body.create, 'rows/create', 'board-button board-primary')].filter(Boolean));
    const rows = (body.rows ?? []).map(row => {
      const entry = this.part(`row/${row.key}`, () => {
        const node = make(this.document, 'article', 'board-entity');
        const title = make(this.document, 'h2'), detail = make(this.document, 'p', 'board-entity-detail');
        const controls = make(this.document, 'div', 'board-entity-actions'); node.append(title, detail, controls);
        return { node, title, detail, controls };
      });
      text(entry.title, row.name);
      text(entry.detail, row.workspace ? `${row.workspace.primary_root ?? row.workspace.roots?.join(' · ') ?? ''} · ${row.cards} 个任务` :
        `${row.profile} · ${row.reasoning} · ${row.active} / ${row.concurrency}`);
      reconcile(entry.controls, ['open', 'edit', 'delete'].map(name => this.button(row[name], `${row.key}/${name}`)).filter(Boolean));
      return entry.node;
    });
    if (body.settings) rows.push(this.renderForm(body.settings));
    const list = this.part('rows/list', () => make(this.document, 'div', 'board-entities')); reconcile(list, rows); reconcile(this.body, [list]);
  }

  drawDialog(model, conversation) {
    if (!model) {
      if (this.modal.open) this.modal.close();
      if (this.key) {
        const previous = this.returnFocus; this.key = undefined;
        queueMicrotask(() => { if (previous?.isConnected) previous.focus(); else this.toolbar.querySelector('button')?.focus(); });
      }
      this.modalBody.replaceChildren(); return;
    }
    const changed = this.key !== model.key;
    if (!this.key) this.returnFocus = this.document.activeElement;
    this.key = model.key; this.modal.dataset.kind = model.kind; this.modal.dataset.expanded = String(!!model.expanded);
    text(this.modalTitle, model.identifier ? `${model.identifier}${model.kind === 'card' ? ` · ${model.title}` : ''}` : model.title ?? model.notice);
    reconcile(this.modalControls, [this.button(model.open_conversation, 'dialog/conversation', 'board-button board-icon-only'),
      this.button(model.expand, 'dialog/expand', 'board-button board-icon-only'), this.button(model.close, 'dialog/close', 'board-button board-icon-only')].filter(Boolean));
    const content = [];
    if (model.description) content.push(this.label('dialog/description', model.description, 'board-dialog-description'));
    if (model.notice) content.push(this.label('dialog/notice', model.notice, 'board-dialog-notice'));
    if (model.execution_notice) content.push(this.label('dialog/execution', model.execution_notice, 'board-dialog-notice'));
    if (model.form) {
      const form = this.renderForm(model.form);
      if (model.kind === 'create' || model.kind === 'card') this.decorateEditor(form, model);
      content.push(form);
    }
    if (model.link_form) content.push(this.renderForm(model.link_form));
    if (model.open) content.push(this.button(model.open, 'dialog/open', 'board-menu-item'));
    if (model.groups) for (const group of model.groups) content.push(this.popup(`context/${group.label}`, group.label,
      group.items.map(item => this.button(item, `context/${item.key}`, 'board-menu-item')), group.icon));
    if (model.rows) for (const row of model.rows) {
      const entry = this.part(`archive/${row.identifier}`, () => make(this.document, 'div', 'board-archive-row'));
      reconcile(entry, [this.label(`archive/${row.identifier}`, `${row.identifier} · ${row.title}`),
        ...['open', 'restore', 'delete'].map(name => this.button(row[name], `archive/${row.identifier}/${name}`)).filter(Boolean)]); content.push(entry);
    }
    if (model.actions) {
      const actions = this.part('dialog/actions', () => make(this.document, 'div', 'board-detail-actions'));
      reconcile(actions, model.actions.map(item => this.button(item, `detail/${item.key}`, model.kind === 'context' ? 'board-menu-item' : 'board-button'))); content.push(actions);
    }
    if (model.confirm) content.push(this.button(model.confirm, 'dialog/confirm', 'board-button board-danger'));
    if (conversation.length) {
      const linked = this.part('dialog/linked', () => make(this.document, 'section', 'board-linked-conversation'));
      reconcile(linked, conversation); content.push(linked);
    }
    reconcile(this.modalBody, content);
    queueMicrotask(() => {
      if (this.disposed || !this.node.isConnected || !this.properties.dialog) return;
      if (!this.modal.open) this.modal.showModal();
      if (model.kind === 'context' && this.contextPoint) {
        const rect = this.modal.getBoundingClientRect();
        this.modal.style.left = `${Math.max(8, Math.min(this.contextPoint.x, innerWidth - rect.width - 8))}px`;
        this.modal.style.top = `${Math.max(8, Math.min(this.contextPoint.y, innerHeight - rect.height - 8))}px`;
      } else { this.modal.style.removeProperty('left'); this.modal.style.removeProperty('top'); }
      if (changed) (this.modalBody.querySelector('input:not([type=hidden]):not(:disabled), textarea:not(:disabled), button:not(:disabled), summary') ?? this.modalControls.querySelector('button'))?.focus();
    });
  }

  decorateEditor(form, model) {
    form.dataset.boardEditor = 'true';
    const footer = form.querySelector('.form-footer');
    const tools = this.part('dialog/footer-tools', () => make(this.document, 'div', 'board-editor-tools'));
    const file = form.querySelector('input[type=file]');
    const actions = [];
    if (file) {
      const attach = this.part('dialog/attach', () => {
        const button = make(this.document, 'button', 'board-button board-icon-only board-attach');
        button.type = 'button'; button.append(boardIcon(this.document, 'paperclip'));
        button.setAttribute('aria-label', '添加附件'); button.title = '添加附件'; return button;
      });
      attach.disabled = file.matches(':disabled'); attach.onclick = () => file.click(); actions.push(attach);
      // Files from explicit paste/drop gestures use the same authenticated
      // upload path as the picker. Text pastes retain normal editor behavior.
      if (!form.dataset.attachmentGestures) {
        const receive = files => {
          const target = form.querySelector('input[type=file]');
          if (!target || target.matches(':disabled')) return false;
          target.dispatchEvent(new CustomEvent('attachment-files', { detail: [...files] })); return true;
        };
        form.addEventListener('paste', event => {
          if (event.clipboardData?.files.length && receive(event.clipboardData.files)) event.preventDefault();
        });
        form.addEventListener('dragover', event => { if (event.dataTransfer?.types.includes('Files')) event.preventDefault(); });
        form.addEventListener('drop', event => {
          if (event.dataTransfer?.files.length && receive(event.dataTransfer.files)) { event.preventDefault(); event.stopPropagation(); }
        });
        form.dataset.attachmentGestures = 'true';
      }
    }
    const spacer = this.part('dialog/footer-spacer', () => make(this.document, 'span', 'board-editor-spacer')); actions.push(spacer);
    for (const mode of model.modes ?? []) if (!mode.selected) actions.push(this.button(mode, mode.key));
    if (model.toggle_keep_create) {
      const keep = this.button(model.toggle_keep_create, 'dialog/keep', 'board-button board-keep');
      keep.setAttribute('role', 'checkbox'); keep.setAttribute('aria-checked', String(model.keep_create)); actions.push(keep);
    }
    reconcile(tools, actions);
    if (tools.parentElement !== footer) footer.insertBefore(tools, footer.firstChild);
  }

  startPointer(event, entry) {
    if (event.button !== 0 || !entry.model.draggable || event.target.closest('button, input, a')) return;
    this.endDrag();
    const gesture = { pointer: event.pointerId, startX: event.clientX, startY: event.clientY, x: event.clientX, y: event.clientY,
      source: structuredClone(entry.model), node: entry.node, touch: event.pointerType === 'touch', active: false, abort: new AbortController() };
    this.drag = gesture;
    const begin = () => {
      if (this.drag !== gesture || gesture.active) return;
      gesture.active = true; entry.node.setPointerCapture(event.pointerId); entry.node.classList.add('is-dragging');
      const rect = entry.node.getBoundingClientRect(); gesture.offsetX = gesture.startX - rect.left; gesture.offsetY = gesture.startY - rect.top;
      gesture.ghost = entry.node.cloneNode(true); gesture.ghost.classList.add('board-drag-ghost'); gesture.ghost.style.width = `${rect.width}px`;
      gesture.ghost.removeAttribute('tabindex'); gesture.ghost.setAttribute('aria-hidden', 'true'); this.document.body.append(gesture.ghost);
      this.moveGhost(gesture);
    };
    if (gesture.touch) gesture.timer = setTimeout(begin, 260);
    this.document.addEventListener('pointermove', move => {
      if (move.pointerId !== gesture.pointer) return;
      gesture.x = move.clientX; gesture.y = move.clientY;
      const distance = Math.hypot(gesture.x - gesture.startX, gesture.y - gesture.startY);
      if (!gesture.active) {
        if (gesture.touch && distance > 9) { this.endDrag(); return; }
        if (!gesture.touch && distance > 5) begin();
      }
      if (gesture.active) { move.preventDefault(); this.moveGhost(gesture); }
    }, { passive: false, signal: gesture.abort.signal });
    this.document.addEventListener('pointerup', up => {
      if (up.pointerId !== gesture.pointer) return;
      const target = this.dropPlacement(up.clientX, up.clientY, gesture.source);
      if (gesture.active && target) {
        try { this.context.dispatch(eventForDrop(gesture.source, target.model)).catch(error => this.fail(error)); }
        catch (error) { this.fail(error); }
      }
      if (gesture.active) this.suppressClick = Date.now() + 350;
      this.endDrag();
    }, { signal: gesture.abort.signal });
    this.document.addEventListener('pointercancel', () => this.endDrag(), { signal: gesture.abort.signal });
  }
  dropPlacement(x, y, source) {
    const column = this.document.elementFromPoint(x, y)?.closest('.board-column');
    if (!column || !this.node.contains(column)) return null;
    if (column.dropModel?.source !== 'move') return { column, model: column.dropModel };
    for (const node of column.querySelectorAll('.board-card')) {
      const candidate = this.cards.get(node.dataset.card)?.model;
      if (!candidate || candidate.key === source.key || candidate.pinned !== source.pinned) continue;
      const rect = node.getBoundingClientRect();
      if (y < rect.top + rect.height / 2) return { column, before: node, model: candidate.drop };
    }
    return { column, model: column.dropModel };
  }
  moveGhost(gesture) {
    if (!gesture.ghost) return;
    gesture.ghost.style.transform = `translate(${gesture.x - gesture.offsetX}px, ${gesture.y - gesture.offsetY}px) rotate(1deg)`;
    const target = this.dropPlacement(gesture.x, gesture.y, gesture.source);
    for (const column of this.node.querySelectorAll('.board-column')) column.classList.toggle('is-drop-target', column === target?.column);
    for (const card of this.node.querySelectorAll('.board-card')) card.classList.toggle('is-drop-before', card === target?.before);
    const cards = target?.column.querySelector('.board-cards');
    if (cards) {
      const rect = cards.getBoundingClientRect();
      if (gesture.y > rect.bottom - 45) cards.scrollTop += 14;
      else if (gesture.y < rect.top + 45) cards.scrollTop -= 14;
    }
    if (this.lanes) {
      const rect = this.lanes.getBoundingClientRect();
      if (gesture.x > rect.right - 55) this.lanes.scrollLeft += 18;
      else if (gesture.x < rect.left + 55) this.lanes.scrollLeft -= 18;
    }
  }
  endDrag() {
    if (!this.drag) return;
    clearTimeout(this.drag.timer); this.drag.abort.abort(); this.drag.node.classList.remove('is-dragging'); this.drag.ghost?.remove();
    if (this.drag.node.hasPointerCapture?.(this.drag.pointer)) this.drag.node.releasePointerCapture(this.drag.pointer);
    for (const column of this.node.querySelectorAll('.is-drop-target')) column.classList.remove('is-drop-target');
    for (const card of this.node.querySelectorAll('.is-drop-before')) card.classList.remove('is-drop-before');
    this.drag = undefined;
  }
  dispose() {
    this.disposed = true; clearTimeout(this.searchTimer); this.endDrag(); this.controller.abort();
    if (this.modal.open) this.modal.close(); this.parts.clear(); this.cards.clear();
  }
}
