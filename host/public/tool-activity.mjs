import { naturalKey } from './json-tokens.mjs';

/** Physical observations and motion for tool cards already admitted by the browser model. */
const collapsedDeck = ':is([data-task-process-toggle], [data-tool-group-toggle])[aria-expanded="false"]';
const face = '[data-task-history-call]:not([data-task-history-departure])';
const elapsed = '[data-tool-elapsed]';
const liveOutput = '[data-tool-live-output]';
const observationKey = (task, call) => JSON.stringify([String(task), call]);
const elementKey = element => observationKey(element.dataset.toolTask, element.dataset.toolIdentity);

export class ToolActivity {
  #observations = new Map();
  #times = new Set();
  #outputs = new Set();
  #observer;
  #clock;
  #motion;

  constructor(surface) {
    this.#motion = matchMedia('(prefers-reduced-motion: reduce)');
    this.#observer = new MutationObserver(records => this.#changed(records));
    this.#observer.observe(surface, { childList: true, subtree: true });
  }

  replace(values) {
    this.#observations.clear();
    for (const value of values) this.#store(value);
    this.#refresh();
  }

  observe(value) {
    this.#store(value);
    this.#refresh();
  }

  #store(value) {
    // DEFENSE: An incompatible remote event can lack a call or canonical task identity.
    if (typeof value?.call_id !== 'string') return;
    let task;
    try { task = naturalKey(value.task_id); }
    catch (error) {
      if (!(error instanceof TypeError)) throw error;
      return;
    }
    const key = observationKey(task, value.call_id);
    if (value.started_at === null) this.#observations.delete(key);
    else if (Number.isSafeInteger(value.started_at)) this.#observations.set(key, value);
  }

  #tick() {
    const now = Date.now();
    for (const node of this.#times) {
      const observation = this.#observations.get(elementKey(node));
      const text = observation ? `${(Math.max(0, now - observation.started_at) / 1000).toFixed(1)}s` : '';
      if (node.textContent !== text) node.textContent = text;
    }
  }

  #refresh() {
    for (const node of this.#outputs) {
      const output = this.#observations.get(elementKey(node))?.output;
      if (typeof output !== 'string' || output === node.textContent) continue;
      const scrollport = node.parentElement;
      const atEnd = scrollport.scrollHeight - scrollport.clientHeight - scrollport.scrollTop < 4;
      node.textContent = output;
      if (atEnd) scrollport.scrollTop = scrollport.scrollHeight;
    }
    this.#tick();
    if (this.#times.size && this.#clock === undefined) this.#clock = setInterval(() => this.#tick(), 100);
    if (!this.#times.size) {
      clearInterval(this.#clock);
      this.#clock = undefined;
    }
  }

  #track(node, present) {
    const apply = (members, selector) => {
      const change = value => present ? members.add(value) : members.delete(value);
      if (node.matches(selector)) change(node);
      for (const element of node.querySelectorAll(selector)) change(element);
    };
    if (node.hasAttribute('data-task-history-departure')) return;
    apply(this.#times, elapsed);
    apply(this.#outputs, liveOutput);
  }

  #changed(records) {
    const detached = new Set();
    const added = new Set();
    const outgoing = new Map();
    const incoming = new Map();
    const insertion = new Set();
    let repaint = false;
    for (const { target, removedNodes, addedNodes } of records) {
      if (removedNodes.length && !addedNodes.length && target.matches?.(`${liveOutput}, ${elapsed}`)) repaint = true;
      const deck = target.matches?.(collapsedDeck);
      for (const node of removedNodes) {
        if (node.nodeType !== 1) continue;
        detached.add(node);
        if (deck && node.matches(face)) outgoing.set(target, node);
      }
      for (const node of addedNodes) {
        if (node.nodeType !== 1) continue;
        added.add(node);
        if (deck && node.matches(face)) incoming.set(target, node);
        if (target.hasAttribute?.('data-task-history-body') && node.matches('[data-tool-call]')) insertion.add(node);
      }
    }
    if (detached.size || added.size || repaint) {
      for (const node of detached) this.#track(node, false);
      for (const node of added) if (node.isConnected) this.#track(node, true);
      this.#refresh();
    }
    if (this.#motion.matches) return;
    for (const [deck, current] of incoming) {
      const previous = outgoing.get(deck);
      if (!previous || !current.isConnected || deck.closest('[inert]') ||
          previous.dataset.taskHistoryCall === current.dataset.taskHistoryCall) continue;
      this.#slide(deck, previous, current);
    }
    for (const card of insertion) {
      if (!card.isConnected || detached.has(card) || card.closest('[inert]')) continue;
      card.animate([{ opacity: 0, transform: 'translateY(8px)' }, { opacity: 1, transform: 'translateY(0)' }],
        { duration: 285, easing: 'cubic-bezier(.22,.75,.3,1)' });
    }
  }

  #slide(deck, previous, current) {
    // The previous surface is a physical copy. Its events and controls belong only to the current keyed DOM.
    const leaving = previous.cloneNode(true);
    leaving.dataset.taskHistoryDeparture = '';
    leaving.inert = true;
    leaving.setAttribute('aria-hidden', 'true');
    deck.prepend(leaving);
    const motion = { duration: 340, easing: 'cubic-bezier(.3,.1,.25,1)' };
    const exit = leaving.animate([{ transform: 'translateY(0)' }, { transform: 'translateY(-105%)' }],
      { ...motion, fill: 'forwards' });
    current.animate([{ transform: 'translateY(105%)' }, { transform: 'translateY(0)' }], motion);
    exit.finished.then(() => leaving.remove(), () => leaving.remove());
  }

  dispose() {
    this.#observer.disconnect();
    clearInterval(this.#clock);
    this.#observations.clear();
    this.#times.clear();
    this.#outputs.clear();
  }
}
