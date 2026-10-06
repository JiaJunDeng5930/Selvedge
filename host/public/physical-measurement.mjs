import { decodeBendValue, observedNatNumber } from './bend-value.mjs';
import { Renderer, list } from './renderer.mjs';

function natural(value, name) {
  return observedNatNumber(typeof value === 'bigint' ? Number(value) : value, name);
}
function extent(value, name) {
  if (!Number.isFinite(value) || value < 0) throw new TypeError(`Invalid observed ${name}`);
  return natural(Math.ceil(value), name);
}
function origin(value, name) {
  if (!Number.isFinite(value)) throw new TypeError(`Invalid observed ${name}`);
  return natural(Math.max(0, Math.floor(value)), name);
}
function contentBox(node, window) {
  const style = window.getComputedStyle(node);
  const pixels = property => {
    const value = Number.parseFloat(style.getPropertyValue(property));
    if (!Number.isFinite(value) || value < 0) throw new Error(`Unavailable content ${property}`);
    return value;
  };
  const box = node.getBoundingClientRect();
  const horizontal = pixels('padding-left') + pixels('padding-right');
  const vertical = pixels('padding-top') + pixels('padding-bottom');
  return {
    width: Math.max(0, box.width - horizontal - pixels('border-left-width') - pixels('border-right-width')),
    height: Math.max(0, Math.max(box.height - pixels('border-top-width') - pixels('border-bottom-width'), node.scrollHeight) - vertical),
  };
}
function multilineContentHeight(owner, window) {
  const field = Array.from(owner.children).find(child =>
    child.localName === 'textarea' && child.hasAttribute('data-physical-field-content'));
  if (!field) return contentBox(owner, window).height;
  const scrollHeight = extent(field.scrollHeight, 'multiline content scroll height');
  const style = window.getComputedStyle(field);
  let padding = 0;
  for (const property of ['padding-top', 'padding-bottom']) {
    const value = Number.parseFloat(style.getPropertyValue(property));
    if (!Number.isFinite(value) || value < 0) throw new Error(`Unavailable multiline content ${property}`);
    padding += value;
  }
  return Math.max(0, scrollHeight - padding);
}
function sizeSignature(node) {
  const box = node.getBoundingClientRect();
  return `${box.width}:${box.height}:${node.scrollWidth}:${node.scrollHeight}`;
}

/** Observe compiled primitive documents in an isolated production renderer. */
export function createPhysicalMeasurer({ surface, bend, onChange }) {
  if (!surface?.ownerDocument || !bend?.probe_document || !bend?.probe_target_keys) {
    throw new TypeError('Physical measurement requires a surface and compiled probe helpers');
  }
  const document = surface.ownerDocument;
  const window = document.defaultView;
  let revision = 0;
  let disposed = false;
  let container = null;
  let controller = new AbortController();
  let active = false;
  let frame = null;
  const probes = new Map();
  const cancellation = () => new DOMException('Physical measurement cancelled', 'AbortError');
  function current(captured) {
    if (disposed || captured !== revision) throw cancellation();
    if (!surface.isConnected || !container?.isConnected) throw new Error('Physical probe is detached');
  }
  async function wait(promise, captured) {
    const signal = controller.signal;
    let abort;
    try {
      const cancelled = new Promise((_, reject) => {
        abort = () => reject(cancellation());
        signal.addEventListener('abort', abort, { once: true });
        if (signal.aborted) abort();
      });
      const result = await Promise.race([promise, cancelled]);
      current(captured);
      return result;
    } finally { signal.removeEventListener('abort', abort); }
  }
  function destroyContainer() {
    if (frame !== null) window.cancelAnimationFrame(frame);
    frame = null;
    for (const probe of probes.values()) {
      probe.observer?.disconnect(); probe.renderer.dispose(); probe.root.remove();
    }
    probes.clear(); container?.remove(); container = null;
  }
  function ensureContainer() {
    if (!surface.isConnected || !document.body?.isConnected || !window?.getComputedStyle) {
      throw new Error('Physical measurement requires an attached document');
    }
    const scope = surface.matches('.native-application') ? surface : surface.querySelector('.native-application') ?? surface;
    if (container && !container.isConnected) destroyContainer();
    if (container) { container.className = scope.className; return; }
    container = document.createElement('div');
    container.className = scope.className;
    container.setAttribute('aria-hidden', 'true');
    container.setAttribute('inert', '');
    container.style.cssText = 'position:fixed;left:0;top:0;visibility:hidden;pointer-events:none;display:block;margin:0;padding:0;border:0;min-width:0;max-width:none;min-height:0;max-height:none;height:auto;box-sizing:content-box;';
    // NOTE: Body owns probes independently of renderer reconciliation; root theme and explicit probe fonts preserve their context.
    document.body.appendChild(container);
  }
  function changed(probe) {
    if (!probe.content || !probe.baseline || active || disposed) return;
    const signature = sizeSignature(probe.content);
    if (signature === probe.baseline) return;
    probe.baseline = signature;
    if (!onChange || frame !== null) return;
    const captured = revision;
    frame = window.requestAnimationFrame(() => {
      frame = null;
      if (!disposed && captured === revision && !active) onChange();
    });
  }
  function getProbe(request, width) {
    const identity = JSON.stringify([natural(request.generation, 'request generation'), request.key, width]);
    let probe = probes.get(identity);
    if (probe) return probe;
    const root = document.createElement('div');
    root.style.cssText = 'display:block;margin:0;padding:0;border:0;min-width:0;max-width:none;min-height:0;max-height:none;height:auto;box-sizing:content-box;';
    container.appendChild(root);
    probe = { root, content: null, baseline: null, observer: null };
    probe.renderer = new Renderer(root, {
      event() {},
      codeKey: (source, ordinal) => bend.code_key(source, ordinal),
      codeSource() {},
      changed: () => changed(probe),
    }, { isolated: true });
    if (window.ResizeObserver) probe.observer = new window.ResizeObserver(() => changed(probe));
    probes.set(identity, probe);
    return probe;
  }
  function imposeWidth(node, width) {
    if (window.getComputedStyle(node).display === 'inline') node.style.display = 'inline-block';
    node.style.boxSizing = 'content-box';
    node.style.minWidth = '0'; node.style.maxWidth = 'none';
    node.style.width = typeof width === 'number' ? `${width}px` : width;
  }
  function referenceAdvance(node) {
    const glyph = document.createElement('span');
    const style = window.getComputedStyle(node);
    glyph.style.cssText = 'position:absolute;display:inline-block;width:max-content;margin:0;padding:0;border:0;white-space:pre;';
    for (const property of ['font-family', 'font-size', 'font-weight', 'font-style', 'font-stretch', 'font-variant', 'font-feature-settings', 'font-variation-settings', 'font-kerning', 'letter-spacing', 'text-transform']) {
      glyph.style.setProperty(property, style.getPropertyValue(property));
    }
    glyph.textContent = '0';
    container.appendChild(glyph);
    try {
      const advance = extent(glyph.getBoundingClientRect().width, 'reference advance');
      if (!advance) throw new Error('Unavailable positive reference advance');
      return advance;
    } finally { glyph.remove(); }
  }
  function cancel() {
    revision++;
    controller.abort(); controller = new AbortController();
    destroyContainer();
  }
  return {
    async measure(rawPlan) {
      if (disposed) throw cancellation();
      if (active) throw new Error('A physical measurement batch is already active');
      const plan = decodeBendValue(rawPlan);
      if (plan?.$ !== 'Awaiting') throw new TypeError('Physical measurement requires an Awaiting plan');
      const generation = natural(plan.generation, 'plan generation');
      const jobs = [plan.first, ...list(plan.remaining)];
      const captured = revision;
      active = true;
      try {
        ensureContainer();
        if (!document.fonts?.ready) throw new Error('Document font readiness is unavailable');
        await wait(document.fonts.ready, captured);
        const measurements = []; const targets = [];
        for (const job of jobs) {
          current(captured);
          const request = job?.request;
          if (!request || typeof request.key !== 'string' || natural(request.generation, 'request generation') !== generation) {
            throw new TypeError('Physical job does not belong to the plan generation');
          }
          const purpose = request.purpose;
          if (!['Natural', 'AtWidth'].includes(purpose?.$) || !['Measure', 'TargetsOnly'].includes(job.mode?.$)) throw new TypeError('Invalid physical probe job');
          const width = purpose.$ === 'Natural' ? null : natural(purpose.width, 'requested width');
          if (job.mode.$ === 'TargetsOnly' && width === null) throw new TypeError('Native target measurement requires AtWidth');
          const probe = getProbe(request, width);
          probe.baseline = null;
          probe.renderer.render(bend.probe_document(job));
          const content = probe.renderer.ownedTarget(request.key);
          if (probe.content !== content) {
            probe.observer?.disconnect(); probe.content = content; probe.observer?.observe(content);
          }
          imposeWidth(content, width === null ? 'max-content' : width);
          if (!await wait(probe.renderer.whenSettled(), captured)) throw cancellation();
          await wait(document.fonts.ready, captured);
          // Rendering settlement replays Bend styles; apply the physical input after that replay.
          imposeWidth(content, width === null ? 'max-content' : width);
          if (job.mode.$ === 'Measure') {
            imposeWidth(content, 'min-content');
            const minimum = extent(contentBox(content, window).width, 'minimum width');
            imposeWidth(content, 'max-content');
            const preferred = extent(contentBox(content, window).width, 'preferred width');
            imposeWidth(content, width === null ? 'max-content' : width);
            measurements.push({ key: request.key, width, minimum_width: minimum, preferred_width: preferred,
              content_height: extent(multilineContentHeight(content, window), 'content height'), reference_advance: referenceAdvance(content) });
          }
          if (width !== null) {
            for (const target of list(bend.probe_target_keys(request))) {
              if (typeof target !== 'string') throw new TypeError('Invalid canonical native target key');
              const box = probe.renderer.targetBounds(target, content);
              targets.push({ owner_key: request.key, width, target, left: origin(box.left, 'target left'), top: origin(box.top, 'target top'),
                target_width: extent(box.width, 'target width'), target_height: extent(box.height, 'target height') });
            }
          }
          probe.baseline = sizeSignature(content);
        }
        current(captured);
        return JSON.stringify({ measurements, targets });
      } finally { active = false; }
    },
    cancel,
    dispose() { if (!disposed) { disposed = true; cancel(); } },
  };
}
