// Composite inputs retain drafts and upload state, not application policy.
const node = (document, tag, className, text) => {
  const element = document.createElement(tag);
  element.className = className;
  if (text !== undefined) element.textContent = text;
  return element;
};
const button = (document, label) => {
  const element = node(document, 'button', 'collection-button', label);
  element.type = 'button';
  return element;
};

export function collectionField(document, kind, context, changed, busy) {
  const root = node(document, 'div', `collection-input collection-${kind}`);
  const input = node(document, 'input', 'collection-value'); input.type = 'hidden';
  const list = node(document, 'div', 'collection-values');
  const editor = node(document, 'input', 'collection-editor');
  const error = node(document, 'p', 'form-error'); error.hidden = true; error.setAttribute('role', 'alert');
  root.append(input, list, editor, error);
  let enabled = true, signature, pending = 0, disposed = false, tagChoices = [], tagOptions;
  const resources = new Map();
  const read = () => JSON.parse(input.value || (kind === 'workspace' ? '{}' : '[]'));
  const save = value => { input.value = JSON.stringify(value); signature = undefined; changed(); update(input.value, enabled); };
  const fail = cause => { error.textContent = cause.message; error.hidden = false; };
  const reportBusy = difference => { pending += difference; busy(pending > 0); };
  let preview, previewBody, previewTitle, previewClose;

  async function show(file) {
    if (!context.readAttachment) return;
    error.hidden = true;
    try {
      const blob = await context.readAttachment(file.id);
      if (disposed) return;
      if (!resources.has(file.id)) resources.set(file.id, URL.createObjectURL(blob));
      const url = resources.get(file.id);
      if (!preview) {
        preview = node(document, 'dialog', 'attachment-preview');
        previewTitle = node(document, 'h2', '', file.name);
        previewClose = button(document, '关闭预览');
        previewClose.onclick = () => preview.close();
        previewBody = node(document, 'div', 'attachment-preview-body');
        preview.append(previewTitle, previewClose, previewBody); root.append(preview);
        preview.addEventListener('click', event => { if (event.target === preview) preview.close(); });
      }
      previewTitle.textContent = file.name;
      const content = [];
      // The server sniffs passive image formats. Other types stay downloads.
      if (['image/png', 'image/jpeg', 'image/gif', 'image/webp'].includes(blob.type)) {
        const image = node(document, 'img', 'attachment-image'); image.src = url; image.alt = file.name;
        content.push(image);
      } else content.push(node(document, 'p', '', '此类型不在页面中预览，请下载后查看。'));
      const download = node(document, 'a', 'attachment-download', '下载附件'); download.href = url; download.download = file.name;
      content.push(download); previewBody.replaceChildren(...content);
      if (!preview.open) preview.showModal();
      previewClose.focus();
    } catch (cause) { fail(cause); }
  }

  if (kind === 'attachments') {
    editor.type = 'file'; editor.multiple = true; editor.classList.add('attachment-file-picker');
    const upload = async files => {
      if (!enabled || editor.matches(':disabled') || disposed) return;
      error.hidden = true;
      reportBusy(files.length);
      for (const file of files) {
        try {
          if (!context.uploadAttachment) throw new Error('附件上传连接不可用');
          const attachment = await context.uploadAttachment(file);
          if (!disposed) {
            const values = read();
            if (!values.some(value => value.id === attachment.id)) save([...values, attachment]);
          }
        } catch (cause) { fail(cause); }
        finally { reportBusy(-1); }
      }
    };
    editor.addEventListener('change', () => { const files = [...editor.files]; editor.value = ''; void upload(files); });
    editor.addEventListener('attachment-files', event => { void upload(event.detail); });
  } else if (kind === 'tags') {
    editor.type = 'text'; editor.placeholder = '添加标签，按 Enter 确认';
    const picker = node(document, 'details', 'tag-picker board-popup');
    const summary = node(document, 'summary', 'choice-trigger', '标签 ⌄');
    summary.setAttribute('aria-label', '标签');
    const menu = node(document, 'div', 'board-menu tag-menu');
    tagOptions = node(document, 'div', 'tag-options');
    menu.append(editor, tagOptions); picker.append(summary, menu); root.insertBefore(picker, error);
    picker.addEventListener('toggle', () => { if (picker.open) editor.focus(); });
    picker.addEventListener('keydown', event => {
      if (event.key === 'Escape' && picker.open) { event.preventDefault(); event.stopPropagation(); picker.open = false; summary.focus(); }
    });
    editor.addEventListener('input', () => { for (const row of tagOptions.children) row.hidden = !row.textContent.toLocaleLowerCase().includes(editor.value.trim().toLocaleLowerCase()); });
    const add = () => {
      const text = editor.value.trim();
      if (text && enabled) { const tags = read(); if (!tags.includes(text)) save([...tags, text]); }
      editor.value = '';
    };
    editor.addEventListener('keydown', event => {
      if (event.key === 'Enter' && !event.isComposing) { event.preventDefault(); event.stopPropagation(); add(); }
    });
  } else if (kind === 'workspace') {
    editor.type = 'text'; editor.placeholder = '/absolute/path/to/project';
    const additional = node(document, 'textarea', 'workspace-additional');
    additional.placeholder = '其他工作区目录，每行一个（可选）'; additional.rows = 2;
    additional.setAttribute('aria-label', '其他工作区目录'); root.insertBefore(additional, error);
    const write = () => {
      const primary = editor.value.trim();
      const others = additional.value.split('\n').map(value => value.trim()).filter(Boolean);
      save({ roots: [...(primary ? [primary] : []), ...others], ...(primary ? { primary_root: primary } : {}) });
    };
    editor.addEventListener('input', write); additional.addEventListener('input', write);
    editor.additional = additional;
  } else throw new TypeError(`Unsupported composite input: ${kind}`);

  function update(value, available, choices = tagChoices) {
    tagChoices = choices;
    enabled = available; editor.disabled = !enabled; input.value = value;
    const stamp = JSON.stringify([value, enabled, choices]);
    if (stamp === signature) return;
    signature = stamp;
    const values = read();
    if (tagOptions) {
      tagOptions.replaceChildren(...choices.map(choice => {
        const row = button(document, choice.label); row.className = 'choice-option';
        row.setAttribute('role', 'checkbox'); row.setAttribute('aria-checked', String(values.includes(choice.value))); row.disabled = !enabled;
        row.hidden = !choice.label.toLocaleLowerCase().includes(editor.value.trim().toLocaleLowerCase());
        row.onclick = () => { const current = read(); save(current.includes(choice.value) ? current.filter(value => value !== choice.value) : [...current, choice.value]); editor.focus(); };
        return row;
      }));
    }
    if (kind === 'workspace') {
      const primary = values.primary_root ?? values.roots?.[0] ?? '';
      if (editor.value !== primary) editor.value = primary;
      const others = (values.roots ?? []).filter(value => value !== primary).join('\n');
      if (editor.additional.value !== others) editor.additional.value = others;
      editor.additional.disabled = !enabled; list.hidden = true; return;
    }
    list.replaceChildren(...values.map((value, index) => {
      const chip = node(document, 'span', 'collection-chip');
      if (kind === 'attachments') {
        const open = button(document, value.name); open.title = `${value.name} · ${value.bytes} bytes`;
        open.onclick = () => show(value); chip.append(open);
      } else chip.append(node(document, 'span', '', value));
      if (enabled) {
        const remove = button(document, '×'); remove.setAttribute('aria-label', `移除 ${kind === 'attachments' ? value.name : value}`);
        remove.onclick = () => save(read().filter((_, current) => current !== index)); chip.append(remove);
      }
      return chip;
    }));
  }
  return { root, input, editor, update, dispose() {
    disposed = true; if (preview?.open) preview.close();
    for (const url of resources.values()) URL.revokeObjectURL(url);
    resources.clear();
  } };
}
