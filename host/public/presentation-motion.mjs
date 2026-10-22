/** Lifecycle observation for the finite motion vocabulary authored by the extracted model. */
export class PresentationMotion {
  constructor(root) {
    this.root = root;
    this.nodes = new Set();
    this.visible = new WeakMap();
    this.reduced = matchMedia('(prefers-reduced-motion: reduce)');
    this.refresh = this.refresh.bind(this);
    this.observer = new IntersectionObserver(entries => {
      for (const entry of entries) this.visible.set(entry.target, entry.isIntersecting);
      this.refresh();
    });
    this.reduced.addEventListener('change', this.refresh);
    document.addEventListener('visibilitychange', this.refresh);
  }
  refresh() {
    const current = new Set(this.root.querySelectorAll('[data-interactive-motion]'));
    const modal = this.root.querySelector('dialog:modal');
    for (const node of this.nodes) if (!current.has(node)) this.observer.unobserve(node);
    for (const node of current) {
      if (!this.nodes.has(node)) this.observer.observe(node);
      const disabled = this.reduced.matches || document.visibilityState !== 'visible'
        || this.visible.get(node) === false || this.root.dataset.sourcesFresh === 'false'
        || Boolean(node.closest('[hidden],[aria-hidden="true"],[inert]')) || Boolean(modal && !modal.contains(node));
      node.dataset.motionPaused = String(disabled);
    }
    this.nodes = current;
  }
  dispose() {
    this.observer.disconnect();
    this.reduced.removeEventListener('change', this.refresh);
    document.removeEventListener('visibilitychange', this.refresh);
    this.nodes.clear();
  }
}
