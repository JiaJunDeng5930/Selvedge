import { naturalKey } from './codec.mjs';
import { boundary } from './public/model-boundary.mjs';
import { observeMarkdownSearchBlocks } from './public/markdown-fence-observation.mjs';

export function browserHistoryReply(command, { program, reply }) {
  if (command.op !== 'search_history' || !reply.ok) return reply;
  // The result and the history in the same journal reply share the original message indices.
  const tasks = new Map(program.tasks.map(task => [naturalKey(task.id), task]));
  const hits = reply.result.hits.map(hit => {
    if (hit.kind === 'title') return hit;
    const message = tasks.get(naturalKey(hit.task.id)).history[naturalKey(hit.message_index)];
    const text = boundary('browser.history_text', { message });
    const blocks = observeMarkdownSearchBlocks(text);
    return { ...hit, preview: boundary('browser.history_preview', { query: command.query, blocks }) };
  });
  return { ...reply, result: { ...reply.result, hits } };
}
