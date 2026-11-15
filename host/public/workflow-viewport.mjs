// The scene supplies workflow groups and target identities. All coordinates
// here belong to the browser viewport and never change a workflow definition.
export function installWorkflowViewport(surface) {
  const views = new WeakMap();
  const viewportSelector = '[data-workflow-canvas]';
  const inset = 16;
  const clamp = scale => Math.max(0.2, Math.min(2.5, scale));

  function view(viewport) {
    let current = views.get(viewport);
    if (!current) {
      current = { x: inset, y: inset, scale: 1, drag: null };
      views.set(viewport, current);
    }
    return current;
  }

  function place(viewport, current) {
    viewport.style.setProperty('--workflow-x', `${current.x}px`);
    viewport.style.setProperty('--workflow-y', `${current.y}px`);
    viewport.style.setProperty('--workflow-scale', current.scale);
  }

  function zoom(viewport, current, multiplier, x, y) {
    const next = clamp(current.scale * multiplier);
    const ratio = next / current.scale;
    current.x = x - (x - current.x) * ratio;
    current.y = y - (y - current.y) * ratio;
    current.scale = next;
    place(viewport, current);
  }

  function fit(workspace) {
    const viewport = workspace.querySelector(viewportSelector);
    const picker = workspace.querySelector('[data-workflow-target]');
    const group = viewport.querySelector(`[data-semantic-key="${CSS.escape(picker.value)}"]`);
    // DEFENSE: A world update can remove the selected workflow before its native change event is handled.
    if (!group) return;
    const current = view(viewport);
    const width = viewport.clientWidth;
    const height = viewport.clientHeight;
    current.scale = clamp(Math.min(1, (width - 2 * inset) / group.offsetWidth, (height - 2 * inset) / group.offsetHeight));
    current.x = Math.max(inset, (width - group.offsetWidth * current.scale) / 2) - group.offsetLeft * current.scale;
    current.y = Math.max(inset, (height - group.offsetHeight * current.scale) / 2) - group.offsetTop * current.scale;
    place(viewport, current);
  }

  function zoomFromCenter(viewport, direction) {
    zoom(viewport, view(viewport), direction === 'in' ? 1.25 : 0.8, viewport.clientWidth / 2, viewport.clientHeight / 2);
  }

  surface.addEventListener('change', event => {
    if (event.target.matches('[data-workflow-target]')) fit(event.target.closest('[data-workflow-workspace]'));
  });
  surface.addEventListener('click', event => {
    const button = event.target.closest('[data-workflow-zoom]');
    if (!button) return;
    const workspace = button.closest('[data-workflow-workspace]');
    const direction = button.dataset.workflowZoom;
    if (direction === 'fit') fit(workspace);
    else zoomFromCenter(workspace.querySelector(viewportSelector), direction);
  });
  surface.addEventListener('wheel', event => {
    const viewport = event.target.closest(viewportSelector);
    if (!viewport || event.target.closest('details[open]')) return;
    event.preventDefault();
    const box = viewport.getBoundingClientRect();
    const units = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? viewport.clientHeight : 1;
    zoom(viewport, view(viewport), Math.exp(-event.deltaY * units / 400), event.clientX - box.left, event.clientY - box.top);
  }, { passive: false });
  surface.addEventListener('pointerdown', event => {
    const viewport = event.target.closest(viewportSelector);
    if (!viewport || event.button !== 0 || event.target.closest('button,a,input,select,textarea,details')) return;
    const current = view(viewport);
    if (current.drag) return;
    current.drag = { id: event.pointerId, x: event.clientX - current.x, y: event.clientY - current.y };
    viewport.setPointerCapture(event.pointerId);
    viewport.toggleAttribute('data-panning', true);
  });
  surface.addEventListener('pointermove', event => {
    const viewport = event.target.closest(viewportSelector);
    const current = views.get(viewport);
    if (current?.drag?.id !== event.pointerId) return;
    current.x = event.clientX - current.drag.x;
    current.y = event.clientY - current.drag.y;
    place(viewport, current);
  });
  surface.addEventListener('lostpointercapture', event => {
    const viewport = event.target.closest(viewportSelector);
    const current = views.get(viewport);
    if (current?.drag?.id !== event.pointerId) return;
    current.drag = null;
    viewport.removeAttribute('data-panning');
  });
  surface.addEventListener('keydown', event => {
    const viewport = event.target;
    if (!viewport.matches(viewportSelector)) return;
    const direction = { ArrowLeft: [70, 0], ArrowRight: [-70, 0], ArrowUp: [0, 70], ArrowDown: [0, -70] }[event.key];
    if (direction) {
      const current = view(viewport);
      current.x += direction[0];
      current.y += direction[1];
      place(viewport, current);
    } else if (event.key === '+' || event.key === '=') zoomFromCenter(viewport, 'in');
    else if (event.key === '-') zoomFromCenter(viewport, 'out');
    else if (event.key === '0') fit(viewport.closest('[data-workflow-workspace]'));
    else return;
    event.preventDefault();
  });
  surface.addEventListener('focusin', event => {
    const viewport = event.target.closest(viewportSelector);
    if (!viewport || event.target === viewport) return;
    const bounds = viewport.getBoundingClientRect();
    const target = event.target.getBoundingClientRect();
    const adjustment = (start, end, first, last) =>
      first < start + inset ? start + inset - first : last > end - inset ? end - inset - last : 0;
    const x = adjustment(bounds.left, bounds.right, target.left, target.right);
    const y = adjustment(bounds.top, bounds.bottom, target.top, target.bottom);
    if (!x && !y) return;
    const current = view(viewport);
    current.x += x;
    current.y += y;
    place(viewport, current);
  });
}
