import { element, icon, reconcile, setText } from './dom.mjs';
import { DesktopMenu, desktopFragment } from './desktop.mjs';
import { createDesktopScroll } from './vendor/desktop-scroll.mjs';

function actionItems(nodes, parent, context) {
  return nodes.flatMap(node => {
    const key = `${parent}/${node.key}`;
    if (node.kind === 'group') return actionItems(node.children, key, context);
    if (node.kind !== 'action') throw new TypeError(`Unsupported menu node: ${node.kind}`);
    return [{ key, domKey: key, label: node.label, disabled: !node.enabled,
      onSelect: () => Promise.resolve(context.dispatch(structuredClone(node.event))).catch(() => {}) }];
  });
}

export class ThreadSurface {
  constructor(document, context, key) {
    Object.assign(this, { context, key });
    const make = (tag, className, text) => element(document, tag, className, text);
    this.node = make('section', 'workspace');
    const header = make('header', 'thread-header');
    const heading = make('div', 'thread-heading');
    this.title = make('h2'); this.subtitle = make('p', 'thread-subtitle'); heading.append(this.title, this.subtitle);
    this.menu = new DesktopMenu(document, { accessibleLabel: 'Task actions', className: 'thread-actions',
      name: 'task-actions', iconOnly: true, icon: icon(document, 'more'), align: 'end' });
    this.toggle = make('button', 'icon-button'); this.toggle.type = 'button'; this.toggle.append(icon(document, 'panel'));
    this.toggle.setAttribute('aria-label', 'Task details'); this.toggle.title = 'Task details';

    // ThreadScrollLayout's measured overlay and spacer are part of its scroll
    // algorithm. A separate footer grid row does not have the same semantics.
    this.layout = make('div', 'thread-scroll-layout');
    this.scroll = make('div', 'thread-scroll'); this.scroll.tabIndex = 0; this.scroll.setAttribute('aria-label', 'Conversation');
    const content = make('div', 'thread-scroll-content');
    this.thread = make('div', 'thread'); this.timeline = make('div', 'thread-timeline'); this.live = make('div', 'live-streams');
    this.thread.append(this.timeline, this.live);
    const spacer = make('div', 'thread-footer-spacer'); spacer.setAttribute('aria-hidden', 'true');
    this.fade = desktopFragment(document, 'div', 'pointer-events-none absolute inset-x-0 bottom-0 z-0 h-full bg-gradient-to-t from-surface via-surface extension:from-surface-secondary extension:via-surface-secondary');
    this.fade.node.setAttribute('aria-hidden', 'true'); spacer.append(this.fade.scope);
    content.append(this.thread, spacer);
    this.compose = make('div', 'composer-dock'); this.compose.setAttribute('data-thread-scroll-footer', 'true');
    this.composerContent = make('div', 'composer-footer-content');
    this.bottom = make('button', 'scroll-bottom'); this.bottom.type = 'button'; this.bottom.hidden = true;
    this.bottom.append(icon(document, 'down')); this.bottom.setAttribute('aria-label', 'Scroll to latest output'); this.bottom.title = 'Scroll to latest output';
    const scrollControl = make('div', 'thread-scroll-control'); scrollControl.append(this.bottom);
    this.compose.append(scrollControl, this.composerContent);
    this.scroll.append(content, this.compose); this.layout.append(this.scroll);

    this.inspector = make('aside', 'inspector'); this.inspector.setAttribute('aria-label', 'Task details');
    this.inspector.id = `inspector-${encodeURIComponent(key)}`; this.toggle.setAttribute('aria-controls', this.inspector.id);
    const inspectorHeader = make('header', 'inspector-header');
    const close = make('button', 'icon-button'); close.type = 'button'; close.append(icon(document, 'close')); close.setAttribute('aria-label', 'Close task details');
    inspectorHeader.append(make('h2', '', 'Task details'), close); this.details = make('div', 'inspector-content'); this.inspector.append(inspectorHeader, this.details);
    header.append(heading, this.menu.node, this.toggle);
    this.node.append(header, this.layout, this.inspector);
    const setDetails = open => {
      this.inspector.hidden = !open; this.node.dataset.inspector = String(open);
      this.toggle.setAttribute('aria-expanded', String(open)); context.disclosures.set(`${key}/inspector`, open);
    };
    setDetails(context.disclosures.get(`${key}/inspector`) ?? false);
    this.toggle.onclick = () => setDetails(this.inspector.hidden);
    close.onclick = () => { setDetails(false); this.toggle.focus(); };
    this.scrolling = createDesktopScroll(this.scroll, this.thread, this.compose, this.bottom);
  }
  update(model, render) {
    this.scrolling.beforeUpdate();
    this.node.dataset.role = 'panel'; this.node.dataset.empty = String(model.task_id === null);
    setText(this.title, model.title); this.title.title = model.title;
    setText(this.subtitle, model.subtitle); this.subtitle.hidden = !model.subtitle; this.subtitle.title = model.subtitle;
    reconcile(this.timeline, model.timeline.map(child => render(child)));
    reconcile(this.composerContent, model.composer.map(child => render(child)));
    reconcile(this.details, model.details.map(child => render(child)));
    this.menu.update({ items: actionItems(model.actions, this.key, this.context) });
    this.menu.node.hidden = !model.actions.length;
    this.toggle.hidden = !model.details.length;
  }
  dispose() { this.scrolling.dispose(); this.menu.dispose(); this.fade.dispose(); }
}

export class ComposerSurface {
  constructor(document, context, key) {
    Object.assign(this, { document, context, key });
    this.node = element(document, 'section', 'composer');
    this.content = element(document, 'div', 'composer-content');
    this.mode = new DesktopMenu(document, { accessibleLabel: 'Message intent', className: 'compose-mode',
      name: 'message-intent', side: 'top', radio: true, itemClassName: 'compose-tab' });
    this.hint = element(document, 'p', 'composer-hint');
    this.actions = element(document, 'div', 'composer-actions');
    this.node.append(this.content, this.hint);
  }
  update(model, render, renderAction) {
    this.model = model; this.render = render;
    this.node.setAttribute('aria-label', model.title);
    setText(this.hint, model.hint); this.hint.hidden = !model.hint;
    this.mode.node.hidden = model.forms.length < 2;
    reconcile(this.actions, model.actions.map(renderAction));
    const remembered = this.context.tabs.get(this.key);
    this.active = model.forms.find(form => form.key === remembered)?.key ?? model.forms.find(form => form.enabled)?.key ?? model.forms[0]?.key;
    this.renderActive();
  }
  renderActive() {
    const form = this.model.forms.find(form => form.key === this.active);
    if (!form) { reconcile(this.content, []); return; }
    this.mode.update({ label: form.label, value: this.active, items: this.model.forms.map(choice => ({
      key: choice.key, label: choice.title, disabled: !choice.enabled,
      onSelect: () => { this.active = choice.key; this.context.tabs.set(this.key, choice.key); this.renderActive(); },
    })) });
    const node = this.render(form, { key: 'editor', draftKey: this.model.draft_key,
      leadingControls: [this.mode.node], trailingControls: [this.actions] });
    reconcile(this.content, [node]);
  }
  dispose() { this.mode.dispose(); }
}

export class ActivitySurface {
  constructor(document, context, key) {
    Object.assign(this, { context, key });
    this.node = element(document, 'details', 'activity-card');
    const summary = element(document, 'summary', 'activity-summary');
    this.mark = element(document, 'span', 'activity-mark'); this.mark.append(icon(document, 'activity'));
    this.title = element(document, 'span', 'activity-title'); this.state = element(document, 'span', 'activity-state');
    summary.append(this.mark, this.title, this.state, icon(document, 'chevron'));
    this.body = element(document, 'div', 'activity-body'); this.node.append(summary, this.body);
    summary.addEventListener('click', () => { this.userToggle = true; });
    this.node.addEventListener('toggle', () => {
      if (this.userToggle) { context.disclosures.set(this.disclosureKey, this.node.open); this.userToggle = false; }
    });
  }
  update(model, children) {
    this.disclosureKey = `${this.key}/${model.state}`;
    this.node.dataset.state = model.state;
    setText(this.title, model.title);
    setText(this.state, { running: 'In progress', waiting: 'Waiting', complete: 'Completed', failed: 'Failed', information: '' }[model.state] ?? '');
    this.node.open = this.context.disclosures.get(this.disclosureKey) ?? ['waiting', 'failed'].includes(model.state);
    reconcile(this.body, children);
  }
}

export function createThreadLink(document) {
  const node = element(document, 'button', 'thread-link'); node.type = 'button';
  const state = element(document, 'span', 'thread-link-state'); state.setAttribute('aria-hidden', 'true');
  const title = element(document, 'span', 'thread-link-title'); node.append(state, title);
  return { node, title };
}
