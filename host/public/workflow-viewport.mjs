const dateFormat = new Intl.DateTimeFormat('zh-CN', {
  month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23',
});

export function showWorkflowTimes(surface) {
  for (const time of surface.querySelectorAll('time[data-epoch-seconds]:not([datetime])')) {
    const date = new Date(Number(time.dataset.epochSeconds) * 1000);
    time.dateTime = date.toISOString();
    time.textContent = dateFormat.format(date);
  }
}

// The scene supplies workflow groups and target identities. All coordinates
// here belong to the browser viewport and never change a workflow definition.
export function installWorkflowViewport(surface) {
  const views = new WeakMap();
  const viewportSelector = '[data-workflow-canvas]';
  const inset = 16;
  const shortLandscape = matchMedia('(orientation: landscape) and (max-height: 480px)');
  const defaultThumbnailZoom = 0.85;
  const minThumbnailZoom = 0.5;
  const maxThumbnailZoom = 1.45;
  const clamp = scale => Math.max(0.06, Math.min(2.5, scale));
  let labels = new Set();
  let observedViewport;
  let expandedPreview;
  const labelObserver = new ResizeObserver(entries => {
    for (const { target } of entries) {
      const name = target.closest('[data-semantic-key="workflow-preview-name"]');
      const overflow = target.scrollHeight > target.clientHeight + 1;
      if (name) {
        name.toggleAttribute('data-workflow-overflow', overflow);
        name.tabIndex = overflow ? 0 : -1;
        if (overflow) name.setAttribute('aria-expanded', String(expandedPreview?.source === name));
        else {
          if (expandedPreview?.source === name) closePreview();
          name.removeAttribute('aria-expanded');
        }
      } else if (!target.parentElement.open) target.toggleAttribute('data-workflow-overflow', overflow);
    }
  });
  function closePreview(returnFocus = false) {
    if (!expandedPreview) return;
    const { viewport, source, previousScroll, revealedScroll } = expandedPreview;
    const restoreScroll = returnFocus && Math.abs(viewport.scrollTop - revealedScroll) <= 1;
    expandedPreview = undefined;
    source.setAttribute('aria-expanded', 'false');
    if (restoreScroll) viewport.scrollTop = previousScroll;
    if (returnFocus) source.focus({ preventScroll: restoreScroll });
  }
  function showPreviewName(source) {
    const detail = source.closest('[data-workflow-tile]').querySelector('[data-workflow-preview-detail]');
    const name = detail.querySelector('[data-workflow-full-name]');
    if (name.textContent !== source.title) name.textContent = source.title;
    return detail;
  }
  const viewportObserver = new ResizeObserver(entries => {
    for (const { target } of entries) {
      const workspace = target.closest('[data-workflow-workspace]');
      if (workspace && view(target).fitted) fit(workspace, view(target).frame === 'overview');
    }
  });

  function view(viewport) {
    let current = views.get(viewport);
    if (!current) {
      current = { x: inset, y: inset, scale: 1, target: '', drag: null, frame: null, fitted: false,
        thumbnailZoom: defaultThumbnailZoom };
      views.set(viewport, current);
    }
    return current;
  }

  function place(viewport, current) {
    viewport.style.setProperty('--workflow-x', `${current.x}px`);
    viewport.style.setProperty('--workflow-y', `${current.y}px`);
    viewport.style.setProperty('--workflow-scale', current.scale);
  }

  function showZoomLimits(workspace, current) {
    const overview = current.frame === 'overview';
    const limits = overview
      ? { in: current.thumbnailZoom >= maxThumbnailZoom, out: current.thumbnailZoom <= minThumbnailZoom }
      : { in: current.scale >= 2.5, out: current.scale <= 0.06 };
    for (const [direction, limit] of Object.entries(limits)) {
      const button = workspace.querySelector(`[data-workflow-zoom="${direction}"]`);
      button.disabled = limit;
      button.title = limit ? (direction === 'in' ? '已达放大上限' : '已达缩小下限') : button.getAttribute('aria-label');
    }
  }

  function zoom(viewport, current, multiplier, x, y) {
    const next = clamp(current.scale * multiplier);
    const ratio = next / current.scale;
    current.x = x - (x - current.x) * ratio;
    current.y = y - (y - current.y) * ratio;
    current.scale = next;
    current.fitted = false;
    place(viewport, current);
    showZoomLimits(viewport.closest('[data-workflow-workspace]'), current);
  }

  function fit(workspace, all = false) {
    const viewport = workspace.querySelector(viewportSelector);
    const picker = workspace.querySelector('[data-workflow-target]');
    const current = view(viewport);
    current.frame = all ? 'overview' : 'selected';
    current.fitted = true;
    workspace.dataset.workflowFrame = current.frame;
    const zoomRatio = current.thumbnailZoom / defaultThumbnailZoom;
    const compact = viewport.clientWidth <= 450;
    const tablet = viewport.clientWidth >= 550 && viewport.clientWidth <= 820;
    if (all) viewport.style.setProperty('--workflow-thumbnail-column', `${21.5 * zoomRatio}rem`);
    for (const tile of viewport.querySelectorAll('[data-workflow-tile]')) {
      const graph = tile.querySelector('[data-workflow-preview-body]').firstElementChild;
      if (all) {
        // Use the contents' extent: a positioned chart can be wider than the section's layout box.
        const widthLimit = (tile.clientWidth - inset) / graph.scrollWidth;
        const height = (compact ? 144 : 200) * zoomRatio;
        let scale = Math.min(current.thumbnailZoom, widthLimit, height / graph.scrollHeight);
        if (tablet) {
          const limit = Math.min(1.95, widthLimit, 360 / graph.scrollHeight);
          const base = Math.min(1.23, limit);
          const enlargement = (current.thumbnailZoom - defaultThumbnailZoom) / (maxThumbnailZoom - defaultThumbnailZoom);
          scale = enlargement < 0 ? base * zoomRatio : base + (limit - base) * enlargement;
        }
        tile.style.setProperty('--workflow-thumbnail-scale', scale);
        tile.style.setProperty('--workflow-thumbnail-left', `${(tile.clientWidth - scale * graph.scrollWidth) / 2}px`);
        tile.style.setProperty('--workflow-thumbnail-height', `${Math.ceil(scale * graph.scrollHeight) + 8}px`);
      }
    }
    if (all) {
      showZoomLimits(workspace, current);
      return;
    }
    closePreview();
    viewport.scrollTo({ top: 0, left: 0 });
    const group = viewport.querySelector(`[data-semantic-key="${CSS.escape(picker.value)}"]`);
    // DEFENSE: A world update can remove the selected workflow before its native change event is handled.
    if (!group) return;
    const width = viewport.clientWidth;
    const height = Math.min(viewport.clientHeight, innerHeight - viewport.getBoundingClientRect().top);
    const contentWidth = group.scrollWidth;
    const contentHeight = group.scrollHeight;
    const clearance = shortLandscape.matches ? inset / 2 : inset;
    current.scale = clamp(Math.min(1, (width - 2 * clearance) / contentWidth, (height - 2 * clearance) / contentHeight));
    current.x = Math.max(clearance, (width - contentWidth * current.scale) / 2) - group.offsetLeft * current.scale;
    current.y = clearance - group.offsetTop * current.scale;
    place(viewport, current);
    showZoomLimits(workspace, current);
  }
  function select(workspace, target) {
    const viewport = workspace.querySelector(viewportSelector);
    view(viewport).target = target;
    const picker = workspace.querySelector('[data-workflow-target]');
    const selection = picker.closest('[data-workflow-selection]');
    selection.querySelector('[data-workflow-selected-name]').textContent = picker.selectedOptions[0].textContent;
    selection.title = picker.selectedOptions[0].textContent;
    for (const group of workspace.querySelectorAll('[data-workflow-actions] [data-semantic-key^="workflow/"]')) {
      const hidden = group.dataset.semanticKey !== target;
      if (group.hidden !== hidden) group.hidden = hidden;
    }
    for (const tile of viewport.querySelectorAll('[data-workflow-tile]'))
      tile.toggleAttribute('data-workflow-selected', tile.dataset.workflowTile === target);
  }

  function open(workspace, target) {
    workspace.querySelector('[data-workflow-target]').value = target;
    select(workspace, target);
    fit(workspace);
  }

  function zoomFromCenter(viewport, direction) {
    zoom(viewport, view(viewport), direction === 'in' ? 1.25 : 0.8, viewport.clientWidth / 2, viewport.clientHeight / 2);
  }

  surface.addEventListener('change', event => {
    if (event.target.matches('[data-workflow-editor-jump]')) {
      const [kind, index] = event.target.value.split('/');
      if (!kind) return;
      const section = kind === 'node' ? 'workflow-node-editor' : 'workflow-connection-editor';
      const form = event.target.closest('form');
      const destination = form.querySelectorAll(`[data-semantic-key="${section}"]`)[Number(index)];
      const field = destination?.querySelector('input,select,textarea');
      // DEFENSE: A draft edit can remove the selected row before the native change arrives.
      if (field) {
        destination.scrollIntoView({ block: 'start', inline: 'nearest', behavior: 'instant' });
        field.focus({ preventScroll: true });
      }
      event.target.value = '';
      return;
    }
    if (!event.target.matches('[data-workflow-target]')) return;
    const workspace = event.target.closest('[data-workflow-workspace]');
    open(workspace, event.target.value);
  });
  surface.addEventListener('click', event => {
    const workspace = event.target.closest('[data-workflow-workspace]');
    if (!workspace) return;
    if (workspace.dataset.workflowFrame === 'overview') {
      if (event.target.closest('[data-workflow-close-name]')) {
        closePreview(true);
        return;
      }
      if (event.target.closest('[data-workflow-preview-detail]')) return;
      const nodeName = event.target.closest('[data-semantic-key="workflow-preview-name"][data-workflow-overflow]');
      if (nodeName) {
        if (expandedPreview?.source === nodeName) {
          closePreview(true);
          return;
        }
        closePreview();
        const detail = showPreviewName(nodeName);
        const viewport = nodeName.closest(viewportSelector);
        const previousScroll = viewport.scrollTop;
        nodeName.setAttribute('aria-expanded', 'true');
        detail.scrollIntoView({ block: 'nearest', inline: 'nearest', behavior: 'instant' });
        expandedPreview = { viewport, source: nodeName, previousScroll, revealedScroll: viewport.scrollTop };
        detail.focus({ preventScroll: true });
        return;
      }
      const target = event.target.closest('[data-workflow-open]');
      const preview = event.target.closest('[data-workflow-tile]');
      if (target || preview) {
        event.preventDefault();
        open(workspace, target?.dataset.workflowOpen ?? preview.dataset.workflowTile);
        workspace.querySelector('[data-workflow-target]').focus({ preventScroll: true });
        return;
      }
    }
    const button = event.target.closest('[data-workflow-zoom]');
    if (!button) return;
    const direction = button.dataset.workflowZoom;
    if (direction === 'fit' || direction === 'all') fit(workspace, direction === 'all');
    else {
      const viewport = workspace.querySelector(viewportSelector);
      if (workspace.dataset.workflowFrame === 'overview') {
        const current = view(viewport);
        current.thumbnailZoom = Math.min(maxThumbnailZoom, Math.max(minThumbnailZoom,
          current.thumbnailZoom * (direction === 'in' ? 1.25 : 0.8)));
        fit(workspace, true);
      } else zoomFromCenter(viewport, direction);
    }
  });
  surface.addEventListener('wheel', event => {
    const viewport = event.target.closest(viewportSelector);
    if (!viewport || viewport.closest('[data-workflow-frame="overview"]') || event.target.closest('details[open]')) return;
    event.preventDefault();
    const box = viewport.getBoundingClientRect();
    const units = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? viewport.clientHeight : 1;
    zoom(viewport, view(viewport), Math.exp(-event.deltaY * units / 400), event.clientX - box.left, event.clientY - box.top);
  }, { passive: false });
  surface.addEventListener('pointerdown', event => {
    const viewport = event.target.closest(viewportSelector);
    if (!viewport || viewport.closest('[data-workflow-frame="overview"]') ||
      event.button !== 0 || event.target.closest('button,a,input,select,textarea,details')) return;
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
    current.fitted = false;
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
    if (event.key === 'Escape' && expandedPreview) {
      closePreview(true);
      event.preventDefault();
      return;
    }
    const viewport = event.target;
    if (!viewport.matches(viewportSelector)) return;
    if (viewport.closest('[data-workflow-frame="overview"]') && event.key !== '0') return;
    const direction = { ArrowLeft: [70, 0], ArrowRight: [-70, 0], ArrowUp: [0, 70], ArrowDown: [0, -70] }[event.key];
    if (direction) {
      const current = view(viewport);
      current.x += direction[0];
      current.y += direction[1];
      current.fitted = false;
      place(viewport, current);
    } else if (event.key === '+' || event.key === '=') zoomFromCenter(viewport, 'in');
    else if (event.key === '-') zoomFromCenter(viewport, 'out');
    else if (event.key === '0') fit(viewport.closest('[data-workflow-workspace]'));
    else return;
    event.preventDefault();
  });
  surface.addEventListener('focusin', event => {
    const viewport = event.target.closest(viewportSelector);
    if (!viewport || viewport.closest('[data-workflow-frame="overview"]') ||
      event.target === viewport || !event.target.matches(':focus-visible')) return;
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
    current.fitted = false;
    place(viewport, current);
  });

  return () => {
    const workspace = surface.querySelector('[data-workflow-workspace]');
    // A page publication reconciles the detail's children before restoring the physical view.
    if (expandedPreview) {
      if (expandedPreview.source.isConnected) showPreviewName(expandedPreview.source);
      else expandedPreview = undefined;
    }
    const viewport = workspace?.querySelector(viewportSelector);
    if (viewport !== observedViewport) {
      if (observedViewport) viewportObserver.unobserve(observedViewport);
      if (viewport) viewportObserver.observe(viewport);
      observedViewport = viewport;
    }
    const nextLabels = new Set(workspace?.querySelectorAll(
      '[data-semantic-key="workflow-node-name"] > summary, [data-workflow-preview-text]') ?? []);
    for (const label of labels) if (!nextLabels.has(label)) labelObserver.unobserve(label);
    for (const label of nextLabels) if (!labels.has(label)) labelObserver.observe(label);
    labels = nextLabels;
    if (!workspace) return;
    const picker = workspace.querySelector('[data-workflow-target]');
    const current = view(viewport);
    if (Array.from(picker.options).some(option => option.value === current.target)) {
      if (picker.value !== current.target) picker.value = current.target;
      select(workspace, current.target);
      workspace.dataset.workflowFrame = current.frame;
      if (current.fitted) fit(workspace, current.frame === 'overview');
    } else {
      select(workspace, picker.value);
      fit(workspace);
    }
  };
}
