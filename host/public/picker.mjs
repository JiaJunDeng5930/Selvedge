import { DesktopMenu } from './desktop.mjs';

// The select remains the form/validation boundary. The installed desktop's
// searchable radio menu provides the visible interaction without another
// keyboard, popover-positioning, or focus implementation.
export function choicePicker(document, select, visual) {
  const root = document.createElement('div'); root.className = 'choice-picker';
  select.classList.add('choice-native'); select.tabIndex = -1; select.setAttribute('aria-hidden', 'true');
  const menu = new DesktopMenu(document, { accessibleLabel: '', searchable: true, radio: true,
    name: 'choice', itemClassName: 'desktop-choice-option' });
  root.append(select, menu.node);
  let current;
  const update = descriptor => {
    current = descriptor;
    const selected = descriptor.choices.find(choice => choice.value === select.value);
    menu.update({ accessibleLabel: descriptor.label, label: selected?.label ?? descriptor.label,
      disabled: select.matches(':disabled'), value: select.value,
      items: descriptor.choices.map(choice => ({
        key: choice.value, label: choice.label, icon: choice.icon ? visual?.(choice.icon) : undefined,
        onSelect: () => {
          if (select.matches(':disabled')) return;
          select.value = choice.value;
          select.dispatchEvent(new Event('input', { bubbles: true }));
          select.dispatchEvent(new Event('change', { bubbles: true }));
          update(current);
        },
      })),
    });
  };
  const invalid = event => { event.preventDefault(); menu.trigger?.focus(); menu.show(); };
  select.addEventListener('invalid', invalid);
  return { root, update, dispose() { select.removeEventListener('invalid', invalid); menu.dispose(); } };
}
