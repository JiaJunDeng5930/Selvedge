/** Observe native geometry and the exact font specifications requested by Gallina. */
export function createPhysicalMeasurer({ surface, onChange }) {
  const document = surface.ownerDocument;
  const observed = new Set([surface]);
  const boxes = new WeakMap();
  const resize = new ResizeObserver(entries => {
    let changed = false;
    for (const { target, contentRect } of entries) {
      const signature = `${contentRect.width}/${contentRect.height}`;
      if (boxes.get(target) !== signature) {
        boxes.set(target, signature);
        changed = true;
      }
    }
    if (changed) onChange();
  });
  resize.observe(surface);
  // Root font preferences can change while every observed pixel-sized region
  // stays fixed. A rem-sized observation schedules the existing font receipt.
  const rootFontProbe = document.createElement('span');
  rootFontProbe.setAttribute('aria-hidden', 'true');
  Object.assign(rootFontProbe.style, { position: 'fixed', visibility: 'hidden',
    pointerEvents: 'none', inlineSize: '1rem', blockSize: '1rem' });
  document.body.append(rootFontProbe);
  resize.observe(rootFontProbe);
  const fontChange = () => onChange();
  document.fonts.addEventListener('loadingdone', fontChange);
  function viewport() {
    const box = surface.getBoundingClientRect();
    return {
      width: Math.floor(box.width), height: Math.floor(box.height),
      root_font_size_milli: Math.ceil(Number.parseFloat(getComputedStyle(document.documentElement).fontSize) * 1000),
    };
  }
  function refresh() {
    const current = new Set([surface, ...surface.querySelectorAll('[data-measure-region], [data-native-responsive-row]')]);
    for (const node of observed) if (!current.has(node)) { resize.unobserve(node); observed.delete(node); }
    for (const node of current) if (!observed.has(node)) { resize.observe(node); observed.add(node); }
  }
  function regions() {
    refresh();
    return [...surface.querySelectorAll('[data-measure-region]')].map(node => {
      const style = getComputedStyle(node);
      const horizontal = Number.parseFloat(style.paddingLeft) + Number.parseFloat(style.paddingRight);
      const vertical = Number.parseFloat(style.paddingTop) + Number.parseFloat(style.paddingBottom);
      return { key: node.dataset.measureRegion, width: Math.max(0, Math.floor(node.clientWidth - horizontal)),
        height: Math.max(0, Math.floor(node.clientHeight - vertical)) };
    });
  }
  function responsiveRows() {
    return [...surface.querySelectorAll('[data-native-responsive-row]')].map(row => {
      const rowStyle = getComputedStyle(row);
      const available = row.clientWidth - Number.parseFloat(rowStyle.paddingLeft) - Number.parseFloat(rowStyle.paddingRight);
      const children = [...row.children].filter(child => getComputedStyle(child).display !== 'none');
      const gap = Number.parseFloat(rowStyle.columnGap) * Math.max(0, children.length - 1);
      const nestedSupporting = [...row.querySelectorAll('[data-native-supporting-row]')];
      const preferred = (size, nestedForm) => {
        const forms = nestedSupporting.map(node => node.getAttribute('data-supporting-form'));
        if (nestedForm) nestedSupporting.forEach(node => node.setAttribute('data-supporting-form', nestedForm));
        const minima = size === 'min-content'
          ? children.flatMap(child => [...child.querySelectorAll('[data-native-minimum-inline], [data-native-compact-minimum-inline]')])
            .filter(node => node.hasAttribute('data-native-minimum-inline') ||
              node.closest('[data-supporting-form]')?.dataset.supportingForm === 'compact') : [];
        const previous = minima.map(node => node.style.cssText);
        let width = gap;
        try {
          // Single-line captions declare a shrinkable measured-advance floor;
          // their unbroken DOM text is still needed for the preferred width.
          minima.forEach(node => Object.assign(node.style, { flex: 'none',
            inlineSize: node.dataset.nativeMinimumInline ?? node.dataset.nativeCompactMinimumInline,
            maxInlineSize: node.dataset.nativeMinimumInline ?? node.dataset.nativeCompactMinimumInline }));
          for (const child of children) {
            const original = child.style.cssText;
            try {
              Object.assign(child.style, { flex: 'none', inlineSize: size, maxInlineSize: 'none' });
              width += child.getBoundingClientRect().width;
            } finally { child.style.cssText = original; }
          }
        } finally {
          minima.forEach((node, index) => { node.style.cssText = previous[index]; });
          if (nestedForm) nestedSupporting.forEach((node, index) => node.setAttribute('data-supporting-form', forms[index]));
        }
        return Math.ceil(width);
      };
      const observation = { key: row.dataset.nativeResponsiveRow,
        available: Math.max(0, Math.floor(available)), minimum: preferred('min-content') };
      // A parent row observes the declared compact child form as well. The
      // extracted layout chooses the form after assigning the residual slot.
      if (nestedSupporting.length) observation.nested_compact_minimum = preferred('min-content', 'compact');
      if (row.hasAttribute('data-native-supporting-row')) {
        const original = row.getAttribute('data-supporting-form');
        // Observe both declared forms on the actual controls, preserving the
        // constrained slot width and restoring the published representation.
        try {
          row.setAttribute('data-supporting-form', 'full');
          observation.full_preferred = preferred('max-content');
          row.setAttribute('data-supporting-form', 'compact');
          observation.compact_preferred = preferred('max-content');
          observation.compact_minimum = preferred('min-content');
        } finally { row.setAttribute('data-supporting-form', original); }
      }
      return observation;
    });
  }
  async function measure(specifications) {
    await document.fonts.ready;
    const probe = document.createElement('span');
    Object.assign(probe.style, { position: 'fixed', left: '-100000px', top: '0', visibility: 'hidden',
      pointerEvents: 'none', display: 'inline-block', whiteSpace: 'pre' });
    document.body.append(probe);
    try {
      const metrics = specifications.map(specification => {
        for (const { name, value } of specification.properties) probe.style.setProperty(name, value);
        probe.textContent = specification.sample;
        const box = probe.getBoundingClientRect();
        return { key: specification.key, height: Math.ceil(box.height), advance: Math.ceil(box.width) };
      });
      return { ...viewport(), metrics, regions: regions(), responsive_rows: responsiveRows() };
    } finally { probe.remove(); }
  }
  return { viewport, measure, refresh, regions, responsiveRows,
    dispose() { resize.disconnect(); rootFontProbe.remove(); document.fonts.removeEventListener('loadingdone', fontChange); observed.clear(); } };
}
