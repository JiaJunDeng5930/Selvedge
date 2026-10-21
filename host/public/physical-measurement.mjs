/** Observe available CSS pixels; native CSS owns intrinsic measurement and allocation. */
export function createPhysicalMeasurer({ surface, onChange }) {
  let extent = null;
  const resize = new ResizeObserver(entries => {
    const { width, height } = entries[0].contentRect;
    if (extent?.width === width && extent?.height === height) return;
    extent = { width, height };
    onChange();
  });
  resize.observe(surface);
  return {
    viewport() {
      const box = surface.getBoundingClientRect();
      // Available pixels round down, requested minima round up, so allocation never gains fictitious space.
      return { width: Math.floor(box.width) };
    },
    dispose() { resize.disconnect(); },
  };
}
