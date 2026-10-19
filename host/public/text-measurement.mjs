function observedLength(style, property) {
  return Math.ceil(Number.parseFloat(style.getPropertyValue(property)));
}

export function createTextMeasurer(rootElement) {
  const document = rootElement.ownerDocument;
  const window = document.defaultView;

  return {
    measure(specs) {
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
          ]) probe.style.setProperty(property, String(value));
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
  };
}
