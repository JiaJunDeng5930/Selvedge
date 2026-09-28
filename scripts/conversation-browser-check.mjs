import assert from 'node:assert/strict';

// A geometry fixture in real Chrome, using the production scroll controller.
// It has no task state or model transport: those run in browser-check.mjs.
export async function checkConversationScroll(ui) {
  const { evaluate, call, wait } = ui;
  await call('Emulation.setDeviceMetricsOverride', { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false });
  await evaluate(`(async () => {
    const { ThreadSurface } = await import('/conversation.mjs');
    const surface = new ThreadSurface(document, { disclosures: new Map(), dispatch: () => Promise.resolve() }, 'scroll-probe');
    const host = surface.node;
    Object.assign(host.style, { position: 'fixed', left: '300px', top: '100px', width: '700px', height: '600px', zIndex: '100', background: 'var(--bg)' });
    const scroll = surface.scroll, latest = surface.bottom, content = surface.timeline;
    const footer = surface.composerContent; footer.style.height = '90px';
    const add = count => { for (let i = 0; i < count; i++) {
      const row = document.createElement('article'); row.className = 'message';
      row.style.height = '72px'; row.textContent = 'Geometry row ' + content.children.length; content.append(row);
    } };
    add(30); document.body.append(host);
    const controller = surface.scrolling;
    window.scrollProbe = { host, scroll, content, footer, latest, controller, add, surface };
    controller.end();
  })()`);
  try {
    const wheel = async deltaY => {
      const point = await evaluate(`(() => { const r = scrollProbe.scroll.getBoundingClientRect();
        return { x: r.x + r.width / 3, y: r.y + 80 }; })()`);
      await call('Input.dispatchMouseEvent', { type: 'mouseWheel', ...point, deltaX: 0, deltaY });
    };
    await wheel(-450);
    await wait('scrollProbe.scroll.scrollTop < -300');
    await evaluate(`new Promise(resolve => setTimeout(resolve, 150))`);
    const anchorTop = await evaluate(`(() => {
      const { scroll, content } = scrollProbe, bounds = scroll.getBoundingClientRect();
      scrollProbe.anchor = [...content.children].find(node => node.getBoundingClientRect().bottom > bounds.top + 1);
      return scrollProbe.anchor.getBoundingClientRect().top;
    })()`);
    await evaluate(`scrollProbe.add(8); scrollProbe.footer.style.height = '210px'`);
    await evaluate(`new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(resolve))))`);
    const afterGrowth = await evaluate('scrollProbe.anchor.getBoundingClientRect().top');
    assert.ok(Math.abs(afterGrowth - anchorTop) <= 1, `Reading moved by ${afterGrowth - anchorTop}px during content/footer growth`);
    assert.equal(await evaluate('scrollProbe.controller.following'), false);

    // Reaching the oldest row and continuing upward is still reader intent,
    // even when the browser has no further scroll event to deliver.
    await wheel(-10000);
    await wait('scrollProbe.scroll.scrollHeight - scrollProbe.scroll.clientHeight + scrollProbe.scroll.scrollTop < 1');
    await wheel(-100);
    const oldest = await evaluate('scrollProbe.content.firstElementChild.getBoundingClientRect().top');
    await evaluate('scrollProbe.add(3)');
    await evaluate(`new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(resolve))))`);
    assert.ok(Math.abs(await evaluate('scrollProbe.content.firstElementChild.getBoundingClientRect().top') - oldest) <= 1);

    const point = await evaluate(`(() => { const r = scrollProbe.latest.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 }; })()`);
    await call('Input.dispatchMouseEvent', { type: 'mousePressed', ...point, button: 'left', clickCount: 1 });
    await call('Input.dispatchMouseEvent', { type: 'mouseReleased', ...point, button: 'left', clickCount: 1 });
    await wait('scrollProbe.scroll.scrollTop === 0 && scrollProbe.latest.hidden');
    await evaluate(`scrollProbe.add(8); scrollProbe.footer.style.height = '90px'`);
    await evaluate(`new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(resolve))))`);
    assert.equal(await evaluate('scrollProbe.scroll.scrollTop'), 0);
    return 'reader anchor survives content/footer growth and oldest-page wheel; explicit latest resumes following';
  } catch (error) {
    const geometry = await evaluate(`(() => { const {scroll, content, footer, latest} = scrollProbe;
      const bounds = scroll.getBoundingClientRect(); const x = bounds.x + bounds.width / 2, y = bounds.y + bounds.height / 2;
      return { top: scroll.scrollTop, height: scroll.scrollHeight, viewport: scroll.clientHeight,
        first: content.firstElementChild.getBoundingClientRect().toJSON(), footer: footer.getBoundingClientRect().toJSON(),
        latest: latest.getBoundingClientRect().toJSON(), wheelTarget: document.elementFromPoint(x,y)?.outerHTML.slice(0,300) };
    })()`);
    console.error('Desktop scroll geometry:', geometry);
    throw error;
  } finally {
    await evaluate('scrollProbe.surface.dispose(); scrollProbe.host.remove(); delete window.scrollProbe');
  }
}
