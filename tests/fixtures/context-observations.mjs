import assert from 'node:assert/strict';

export function contextChanges(page, type) {
  return page.messages.filter(item => item.role === 'task_context' && item.type === 'context_change')
    .map(item => ({ ...item.change, key: item.change.snapshot?.key ?? item.change.key }))
    .filter(change => change.key.type === type);
}

export function contextContent(changes, filename) {
  let content;
  for (const change of changes.filter(change => change.key.identity.path === filename)) {
    if (change.type === 'introduce') content = change.snapshot.value.fields.content;
    else if (change.type === 'remove') content = undefined;
    else if (change.type === 'amend') {
      const field = change.patch.fields.find(field => field.field === 'content');
      if (!field) continue;
      const characters = [...content];
      // Public context edits address Unicode code points in the previous content.
      for (const edit of [...field.edits].reverse()) {
        const removed = [...edit.removed];
        assert.equal(characters.slice(edit.start, edit.start + removed.length).join(''), edit.removed);
        characters.splice(edit.start, removed.length, ...edit.inserted);
      }
      content = characters.join('');
    }
  }
  return content;
}
