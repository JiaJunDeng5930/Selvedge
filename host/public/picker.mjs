// A searchable presentation for native choices. The select remains the form's
// value and dispatches the same input/change events as a conventional control.
export function choicePicker(document, select, visual = () => null) {
  const root = document.createElement('span'); root.className = 'choice-picker';
  const trigger = document.createElement('button'); trigger.type = 'button'; trigger.className = 'choice-trigger';
  trigger.setAttribute('role', 'combobox'); trigger.setAttribute('aria-haspopup', 'listbox');
  const mark = document.createElement('span'), label = document.createElement('span'), chevron = document.createElement('span'); chevron.textContent = '⌄';
  mark.className = 'choice-mark'; trigger.append(mark, label, chevron);
  const menu = document.createElement('div'); menu.className = 'choice-menu'; menu.popover = 'manual';
  const search = document.createElement('input'); search.type = 'search'; search.className = 'choice-search';
  const options = document.createElement('div'); options.className = 'choice-options'; options.setAttribute('role', 'listbox');
  menu.append(search, options);
  select.classList.add('choice-native'); select.tabIndex = -1; select.setAttribute('aria-hidden', 'true');
  root.append(select, trigger, menu);
  const controller = new AbortController();
  let current, signature, expanded = false;
  function close(focus = false) {
    if (expanded) menu.hidePopover();
    expanded = false; trigger.setAttribute('aria-expanded', 'false');
    if (focus && trigger.isConnected) trigger.focus();
  }
  function visible() { return [...options.children].filter(node => !node.hidden); }
  function filter() {
    const query = search.value.trim().toLocaleLowerCase();
    for (const option of options.children) option.hidden = !option.textContent.toLocaleLowerCase().includes(query);
  }
  function position() {
    const rect = trigger.getBoundingClientRect(), view = document.defaultView;
    const width = Math.min(320, view.innerWidth - 24);
    const height = Math.min(310, view.innerHeight - 24);
    menu.style.width = `${Math.max(Math.min(rect.width, width), Math.min(220, width))}px`;
    menu.style.maxHeight = `${height}px`;
    menu.style.left = `${Math.max(12, Math.min(rect.left, view.innerWidth - width - 12))}px`;
    menu.style.top = `${rect.bottom + height > view.innerHeight ? Math.max(12, rect.top - height) : rect.bottom + 4}px`;
  }
  function open() {
    if (trigger.disabled || select.matches(':disabled')) return;
    search.value = ''; filter(); position(); menu.showPopover(); expanded = true;
    trigger.setAttribute('aria-expanded', 'true'); search.focus();
  }
  trigger.onclick = () => expanded ? close() : open();
  trigger.onkeydown = event => {
    if (['ArrowDown', 'ArrowUp'].includes(event.key)) { event.preventDefault(); open(); visible()[event.key === 'ArrowUp' ? visible().length - 1 : 0]?.focus(); }
  };
  search.addEventListener('input', filter);
  menu.addEventListener('keydown', event => {
    if (event.isComposing) return;
    const rows = visible(), index = rows.indexOf(document.activeElement);
    if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); close(true); }
    else if (['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) {
      event.preventDefault();
      const next = event.key === 'Home' ? 0 : event.key === 'End' ? rows.length - 1 :
        (index + (event.key === 'ArrowDown' ? 1 : -1) + rows.length) % rows.length;
      rows[next]?.focus();
    } else if (event.key === 'Enter' && event.target === search) { event.preventDefault(); rows[0]?.click(); }
    else if (event.key === 'Tab') close();
  });
  document.addEventListener('pointerdown', event => { if (!root.contains(event.target)) close(); }, { signal: controller.signal });
  document.defaultView.addEventListener('resize', () => close(), { signal: controller.signal });
  select.addEventListener('invalid', event => { event.preventDefault(); trigger.focus(); open(); });
  function update(descriptor) {
    current = descriptor;
    const selected = descriptor.choices.find(choice => choice.value === select.value);
    label.textContent = selected?.label ?? descriptor.label;
    const image = selected?.icon && visual(selected.icon); mark.replaceChildren(...(image ? [image] : [])); mark.hidden = !image;
    trigger.setAttribute('aria-label', descriptor.label); trigger.title = descriptor.label;
    trigger.disabled = select.disabled; trigger.setAttribute('aria-expanded', String(expanded));
    search.placeholder = `搜索${descriptor.label}`; search.setAttribute('aria-label', search.placeholder);
    options.id = `${select.id}/options`; trigger.setAttribute('aria-controls', options.id);
    const next = JSON.stringify(descriptor.choices);
    if (signature !== next) {
      options.replaceChildren(...descriptor.choices.map(choice => {
        const button = document.createElement('button'); button.type = 'button'; button.className = 'choice-option';
        button.setAttribute('role', 'option'); button.dataset.value = choice.value;
        const image = choice.icon && visual(choice.icon), text = document.createElement('span'); text.textContent = choice.label;
        if (image) button.append(image); button.append(text);
        button.onclick = () => {
          if (select.matches(':disabled')) return;
          select.value = choice.value;
          select.dispatchEvent(new Event('input', { bubbles: true }));
          select.dispatchEvent(new Event('change', { bubbles: true }));
          update(current); close(true);
        };
        return button;
      })); signature = next;
    }
    for (const option of options.children) option.setAttribute('aria-selected', String(option.dataset.value === select.value));
    if (trigger.disabled) close();
  }
  return { root, update, dispose() { close(); controller.abort(); } };
}
