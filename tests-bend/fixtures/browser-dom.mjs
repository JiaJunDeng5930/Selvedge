import * as Bend from '/public/generated/browser-model.mjs';
import * as Model from '/boundary.mjs';
import { Renderer } from '/public/renderer.mjs';
import { createPhysicalMeasurer } from '/public/physical-measurement.mjs';
import { createTextMeasurer } from '/public/text-measurement.mjs';
import { editorKeyboard } from '/public/keyboard.mjs';
import { appearanceObservation, persistAppearance } from '/public/appearance.mjs';

const value = ($, fields = {}) => ({ $, ...fields });
const list = items => items.reduceRight((tail, head) => value('Con', { head, tail }), value('Nil'));
const property = (name, item) => value('browser/document/MODEL.Property', { name, value: item });
const properties = entries => list(Object.entries(entries).map(([name, item]) => property(name, item)));
const text = item => value('browser/document/MODEL.Text', { value: item });
const element = (key, tag, attributes = {}, styles = {}, events = [], children = []) => value('browser/document/MODEL.Element', {
  key, tag, attributes: properties(attributes), styles: properties(styles), events: list(events), children: list(children),
});
const check = (condition, message) => { if (!condition) throw new Error(message); };

async function run() {
  const root = document.getElementById('surface');
  const nativeInputs = [];
  const activations = [];
  const renderer = new Renderer(root, {
    fieldSessionInitial: Bend.field_session_initial,
    fieldSessionStep: Bend.field_session_step,
    event: binding => {
      if (binding.$.endsWith('.Activate')) activations.push(binding.key);
      else nativeInputs.push(binding.$);
    },
    codeKey: Bend.code_dom_key, codeSource() {}, changed() {},
  });
  const doc = (canonical, disabled = false) => value('browser/document/MODEL.Document', {
    title: 'Native browser boundary',
    root: element('application', 'main', {}, { width: '360px', padding: '16px' }, [], [
      element('editor', 'textarea', { value: canonical, 'aria-label': 'Native editor' }, { width: '220px', height: '70px' }, [value('browser/document/MODEL.EditText', { key: 'editor' })]),
      element('action', 'button', { type: 'button', 'aria-label': 'Native action', disabled: String(disabled) }, { display: 'block', width: '100px', height: '36px' }, [value('browser/document/MODEL.Activate', { key: 'action' })], [text('Action')]),
      element('slot', 'div'),
      value('browser/document/MODEL.Portal', { key: 'portal', target: 'slot', children: list([element('portal-child', 'span', {}, {}, [], [text('Portal content')])]) }),
      value('browser/document/MODEL.TargetProperties', { key: 'target-style', target: 'action', attributes: properties({ 'data-executed-target': 'true' }), styles: properties({ 'border-radius': '7px' }) }),
    ]),
  });
  renderer.render(doc('abcdef'), 1n);
  const editor = renderer.target('editor');
  const button = renderer.target('action');
  editor.focus(); editor.setSelectionRange(1, 3, 'forward');
  renderer.render(doc('abcdefgh'), 2n);
  check(renderer.target('editor') === editor, 'Keyed editor was replaced');
  check(document.activeElement === editor, 'Reconciliation lost native focus');
  check(editor.value === 'abcdefgh' && editor.selectionStart === 1 && editor.selectionEnd === 3, 'Canonical replacement lost the native selection');
  check(renderer.target('slot').textContent === 'Portal content', 'Portal did not reach its native target');
  check(button.dataset.executedTarget === 'true' && getComputedStyle(button).borderRadius === '7px', 'TargetProperties did not reach CSSOM/attributes');
  button.click(); check(activations.length === 1, 'Native activation did not reach its declared binding');
  renderer.render(doc('abcdefgh', true), 2n);
  check(button.disabled, 'Disabled source did not reach the native control property');
  button.click(); check(activations.length === 1, 'A disabled native control still dispatched activation');
  renderer.render(doc('abcdefgh'), 2n);
  check(!button.disabled, 'Removing disabled source did not restore the native control property');
  const rectangle = button.getBoundingClientRect();
  check(rectangle.width === 100 && rectangle.height === 36, 'Authored dimensions did not reach physical geometry');
  check(document.elementFromPoint(rectangle.left + 50, rectangle.top + 18) === button, 'The declared button does not own its hit target');
  button.focus(); check(document.activeElement === button, 'Native focus did not reach the declared action');

  editor.dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true }));
  editor.value = 'unfinished composition';
  editor.dispatchEvent(new InputEvent('input', { bubbles: true, isComposing: true }));
  renderer.render(doc('server canonical'), 3n);
  editor.dispatchEvent(new CompositionEvent('compositionend', { bubbles: true }));
  editor.dispatchEvent(new InputEvent('input', { bubbles: true }));
  check(nativeInputs.length === 0 && editor.value === 'server canonical', 'Superseded native composition escaped canonical synchronization');
  editor.dispatchEvent(new KeyboardEvent('keydown', { key: 'a', keyCode: 65, bubbles: true }));
  editor.value = 'new user input'; editor.dispatchEvent(new InputEvent('input', { bubbles: true }));
  check(nativeInputs.length === 1, 'A fresh native edit did not resume after composition was superseded');

  const delivered = [];
  editor.addEventListener('keydown', event => editorKeyboard(event, Model.native_editor_key, input => delivered.push(input)));
  const composing = new KeyboardEvent('keydown', { key: 'Enter', keyCode: 13, isComposing: true, bubbles: true, cancelable: true });
  editor.dispatchEvent(composing);
  check(delivered.length === 0 && !composing.defaultPrevented, 'Native isComposing was lost before compiled normalization');
  const ime = new KeyboardEvent('keydown', { key: 'Enter', keyCode: 229, bubbles: true, cancelable: true });
  editor.dispatchEvent(ime);
  check(delivered.length === 0 && !ime.defaultPrevented, 'IME confirmation was intercepted as submission');
  const enter = new KeyboardEvent('keydown', { key: 'Enter', keyCode: 13, bubbles: true, cancelable: true });
  editor.dispatchEvent(enter);
  check(delivered.length === 1 && enter.defaultPrevented, 'Ordinary native Enter did not follow the compiled keyboard decision');
  const shifted = new KeyboardEvent('keydown', { key: 'Enter', keyCode: 13, shiftKey: true, bubbles: true, cancelable: true });
  editor.dispatchEvent(shifted);
  check(delivered.length === 2 && delivered[1].shift && !shifted.defaultPrevented, 'Native Shift or default handling was lost before compiled normalization');

  const presentation = value('browser/appearance/TYPOGRAPHY.Presentation', {
    tier: value('browser/appearance/TYPOGRAPHY.Body'), emphasis: value('browser/appearance/TYPOGRAPHY.Regular'), scale: value('browser/appearance/TYPOGRAPHY.Scale', { additional_milli: 0n }),
  });
  const request = value('browser/layout/CONTENT.Request', {
    generation: 7n, key: 'measured-content', purpose: value('browser/layout/CONTENT.AtWidth', { width: 60n }),
    value: value('browser/layout/CONTENT.Value', { font: presentation,
      node: value('browser/document/SOURCE.Text', {
        key: value('interaction/IDENTITY.Place', { path: 'physical-text' }), value: 'one two three four five',
        font: value('browser/document/SOURCE.InheritFont'), wrapping: value('browser/appearance/TYPOGRAPHY.WrapWords'),
      }),
    }), native_roots: list([]), native_policies: list([]),
  });
  const job = value('browser/layout/physical-plan.Job', { request, roots: list([]), mode: value('browser/layout/physical-plan.Measure') });
  const measurer = createPhysicalMeasurer({ surface: root, bend: Bend, onChange() {} });
  const receipt = JSON.parse(await measurer.measure(value('browser/layout/physical-plan.Awaiting', { generation: 7n, first: job, remaining: list([]) })));
  const measurement = receipt.measurements[0];
  check(measurement.key === request.key && measurement.width === 60, 'Physical receipt lost request identity or constrained width');
  check(measurement.minimum_width > 0 && measurement.preferred_width >= measurement.minimum_width && measurement.content_height > 20 && measurement.reference_advance > 0, 'Actual font/wrapping geometry was not measured');
  measurer.dispose();
  const textMeasurer = createTextMeasurer(root);
  const metric = textMeasurer.measure([{ key: 'font', text: 'one two three', reference_text: '0', fontFamily: 'monospace', fontSize: 14, lineHeight: 20, fontWeight: 400,
    whiteSpace: 'pre-wrap', overflowWrap: 'normal', wordBreak: 'normal', available_width: 40 }])[0];
  check(metric.reference_advance > 0 && metric.constrained_height > 20, 'CSSOM text measurement did not preserve wrapped font geometry');
  textMeasurer.dispose();

  persistAppearance(localStorage, value('interaction/services/MODEL.DarkAppearance'));
  const restored = new Promise((resolve, reject) => {
    const listener = event => {
      if (event.origin !== location.origin || event.data?.kind !== 'restored-appearance') return;
      window.removeEventListener('message', listener);
      if (event.data.appearance !== 'DarkAppearance') reject(new Error('A fresh browsing context lost stored appearance'));
      else resolve();
    };
    window.addEventListener('message', listener);
  });
  const frame = document.createElement('iframe'); frame.src = '/storage'; document.body.append(frame);
  await restored;
  check(appearanceObservation(localStorage).stored.value === 'DarkAppearance', 'Browser storage observation lost its value');
  frame.remove(); renderer.dispose();
  return { renderer: true, composition: true, keyboard: true, focus: true, geometry: true, measurement: true, storage: true };
}

run().then(result => {
  document.getElementById('result').textContent = JSON.stringify({ ok: true, result });
}).catch(error => {
  document.getElementById('result').textContent = JSON.stringify({ ok: false, error: error.stack ?? String(error) });
});
