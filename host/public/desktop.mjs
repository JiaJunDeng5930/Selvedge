import { React, createRoot, flushSync, DropdownMenu, Menu, ChevronDown } from './vendor/desktop-ui.mjs';

const h = React.createElement;
const roots = new Set();
let themeObserver;

function applyTheme(node) {
  if (node) node.dataset.theme = getComputedStyle(document.documentElement).colorScheme.includes('dark') ? 'dark' : 'light';
}

function registerTheme(node) {
  if (!themeObserver) {
    const refresh = () => { for (const root of roots) applyTheme(root); };
    themeObserver = new MutationObserver(refresh);
    themeObserver.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
    matchMedia('(prefers-color-scheme: dark)').addEventListener('change', refresh);
  }
  roots.add(node); applyTheme(node);
}

export function desktopFragment(document, tag, className) {
  const scope = document.createElement('div'); scope.className = 'codex-scope'; scope.style.display = 'contents';
  const node = document.createElement(tag); node.className = `codex-ui ${className}`;
  scope.append(node); registerTheme(node);
  return { scope, node, dispose() { roots.delete(node); } };
}

// Only the native descriptors and DOM ownership are adapted here. DropdownMenu,
// SearchInput, RadioItem, focus, dismissal and positioning are the installed
// Codex components, not local implementations of those interactions.
const NativeMenu = React.forwardRef(function NativeMenu({ owner, options }, ref) {
  const [open, setOpen] = React.useState(false);
  const [query, setQuery] = React.useState('');
  React.useImperativeHandle(ref, () => ({ close: () => setOpen(false), show: () => setOpen(true) }), []);
  const choose = item => {
    item.onSelect?.();
  };
  const entries = (options.items ?? []).filter(item => !options.searchable || item.label.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase()));
  const item = entry => entry.kind === 'label'
    ? h(Menu.SectionLabel, { key: entry.key }, entry.label)
    : entry.kind === 'separator'
      ? h(Menu.Separator, { key: entry.key })
      : h(options.radio ? Menu.RadioItem : Menu.Item, {
        key: entry.key, value: entry.key, disabled: entry.disabled,
        className: options.itemClassName, 'data-key': entry.domKey,
        icon: entry.icon ? h('span', { ref: node => { if (node && node.firstChild !== entry.icon) node.replaceChildren(entry.icon); } }) : undefined,
        'data-value': entry.key, onSelect: () => choose(entry),
      }, entry.label);
  const trigger = h('button', {
    type: 'button', disabled: options.disabled,
    className: 'flex shrink-0 cursor-interaction items-center gap-1 rounded-md px-2 py-1 text-sm text-default',
    'aria-label': options.accessibleLabel, title: options.accessibleLabel,
    'data-desktop-menu-trigger': '',
  }, options.iconOnly ? h('span', { ref: node => { if (node && options.icon && node.firstChild !== options.icon) node.replaceChildren(options.icon); } })
    : h(React.Fragment, null, h('span', { className: 'truncate' }, options.label), h(ChevronDown, { className: 'size-4 shrink-0 text-tertiary' })));
  return h(DropdownMenu, {
    open, onOpenChange: value => { setOpen(value); if (value) setQuery(''); },
    triggerButton: trigger, disabled: options.disabled,
    side: options.side ?? 'bottom', align: options.align ?? 'start',
    portalContainer: owner.portalContainer(),
    contentWidth: 'xs', contentClassName: 'codex-ui desktop-menu-content',
    contentRef: node => {
      if (owner.content) roots.delete(owner.content);
      owner.content = node;
      if (node) { node.dataset.desktopMenu = options.name ?? ''; registerTheme(node); }
    },
  }, options.searchable ? h(Menu.SearchInput, {
    value: query, onChange: event => setQuery(event.target.value),
    placeholder: `Search ${options.accessibleLabel}`, 'aria-label': `Search ${options.accessibleLabel}`,
  }) : null, options.radio
    ? h(Menu.RadioGroup, { value: options.value ?? '' }, entries.map(item))
    : entries.map(item));
});

export class DesktopMenu {
  constructor(document, options) {
    this.node = document.createElement('div');
    this.node.className = `codex-scope ${options.className ?? ''}`;
    this.node.style.display = 'contents';
    this.mount = document.createElement('div'); this.mount.className = 'codex-ui'; this.mount.style.display = 'contents';
    this.portal = document.createElement('div'); this.portal.className = 'codex-scope'; this.portal.style.display = 'contents';
    this.node.append(this.mount);
    this.ref = React.createRef();
    this.root = createRoot(this.mount);
    registerTheme(this.mount);
    this.update(options);
  }
  get trigger() { return this.node.querySelector('[data-desktop-menu-trigger]'); }
  get open() { return this.trigger?.getAttribute('aria-expanded') === 'true'; }
  portalContainer() {
    const container = this.node.closest('dialog[open]') ?? this.node.ownerDocument.body;
    if (this.portal.parentNode !== container) container.append(this.portal);
    return this.portal;
  }
  update(options) {
    this.options = { ...this.options, ...options };
    flushSync(() => this.root.render(h(NativeMenu, { owner: this, options: this.options, ref: this.ref })));
  }
  close() { this.ref.current?.close(); }
  show() { this.ref.current?.show(); }
  dispose() {
    roots.delete(this.mount); roots.delete(this.content);
    this.root.unmount();
    this.portal.remove();
  }
}
