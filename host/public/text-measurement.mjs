const stringFields = ['key', 'text', 'reference_text', 'fontFamily', 'whiteSpace', 'overflowWrap', 'wordBreak'];

function length(value, name) {
  if (!Number.isSafeInteger(value) || value < 0) throw new TypeError(`Invalid text measurement ${name}`);
  return value;
}

function validate(spec) {
  if (!spec || typeof spec !== 'object') throw new TypeError('Invalid text measurement specification');
  for (const field of stringFields) {
    if (typeof spec[field] !== 'string') throw new TypeError(`Invalid text measurement ${field}`);
  }
  for (const field of ['fontFamily', 'whiteSpace', 'overflowWrap', 'wordBreak']) {
    if (!spec[field].trim()) throw new TypeError(`Empty text measurement ${field}`);
  }
  length(spec.fontSize, 'fontSize');
  length(spec.lineHeight, 'lineHeight');
  if (spec.available_width !== null) length(spec.available_width, 'available_width');
  if (typeof spec.fontWeight === 'number') length(spec.fontWeight, 'fontWeight');
  else if (typeof spec.fontWeight !== 'string' || !spec.fontWeight.trim()) {
    throw new TypeError('Invalid text measurement fontWeight');
  }
}

function observedLength(style, property) {
  const raw = style.getPropertyValue(property).trim();
  if (!/^(?:\d+(?:\.\d*)?|\.\d+)px$/.test(raw)) {
    throw new TypeError(`Unavailable text measurement ${property}: ${raw}`);
  }
  const measured = Number(raw.slice(0, -2));
  const rounded = Math.ceil(measured);
  if (!Number.isFinite(measured) || measured < 0 || !Number.isSafeInteger(rounded)) {
    throw new TypeError(`Invalid observed text measurement ${property}`);
  }
  return rounded;
}

function suppliedStyle(style, property, value) {
  style.setProperty(property, String(value));
  if (!style.getPropertyValue(property)) throw new TypeError(`Invalid text measurement style ${property}`);
}

export function createTextMeasurer(rootElement) {
  if (!rootElement?.ownerDocument || typeof rootElement.appendChild !== 'function') {
    throw new TypeError('Text measurement requires a root element');
  }
  const document = rootElement.ownerDocument;
  const window = document.defaultView;
  let disposed = false;

  return {
    measure(specs) {
      if (disposed) throw new Error('Text measurer is disposed');
      if (!Array.isArray(specs)) throw new TypeError('Text measurement requires specifications');
      for (const spec of specs) validate(spec);
      if (!rootElement.isConnected || !window?.getComputedStyle) {
        throw new Error('Text measurement requires an attached document');
      }
      if (specs.length === 0) return [];
      const batch = document.createDocumentFragment();
      const container = document.createElement('div');
      container.setAttribute('aria-hidden', 'true');
      container.setAttribute('inert', '');
      container.style.cssText = 'position:fixed;left:0;top:0;visibility:hidden;pointer-events:none;isolation:isolate;display:block;margin:0;padding:0;border:0;box-sizing:content-box;';
      try {
        const specimens = specs.map(spec => {
          const probe = document.createElement('div');
          probe.style.cssText = 'display:block;margin:0;padding:0;border:0;box-sizing:content-box;min-width:0;max-width:none;min-height:0;max-height:none;height:auto;';
          for (const [property, value] of [
            ['font-family', spec.fontFamily], ['font-size', `${spec.fontSize}px`],
            ['line-height', `${spec.lineHeight}px`], ['font-weight', spec.fontWeight],
            ['white-space', spec.whiteSpace], ['overflow-wrap', spec.overflowWrap],
            ['word-break', spec.wordBreak],
          ]) suppliedStyle(probe.style, property, value);
          probe.textContent = spec.text;
          probe.style.width = 'min-content';
          const preferred = probe.cloneNode(true);
          preferred.style.width = 'max-content';
          const constrained = spec.available_width === null ? preferred : probe.cloneNode(true);
          if (spec.available_width !== null) constrained.style.width = `${spec.available_width}px`;
          const reference = preferred.cloneNode(true);
          reference.textContent = spec.reference_text;
          container.appendChild(probe);
          container.appendChild(preferred);
          if (constrained !== preferred) container.appendChild(constrained);
          container.appendChild(reference);
          return { spec, minimum: probe, preferred, constrained, reference };
        });
        batch.appendChild(container);
        rootElement.appendChild(batch);
        // Keep every specimen attached and unchanged throughout the used-size reads.
        return specimens.map(({ spec, minimum, preferred, constrained, reference }) => {
          const minimum_width = observedLength(window.getComputedStyle(minimum), 'width');
          const preferred_width = observedLength(window.getComputedStyle(preferred), 'width');
          const constrained_height = observedLength(window.getComputedStyle(constrained), 'height');
          const reference_advance = observedLength(window.getComputedStyle(reference), 'width');
          return { key: spec.key, minimum_width, preferred_width, constrained_height, reference_advance };
        });
      } finally {
        container.remove();
      }
    },
    invalidate() {
      if (disposed) throw new Error('Text measurer is disposed');
    },
    dispose() { disposed = true; },
  };
}
