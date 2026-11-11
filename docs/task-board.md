# Card board

Open **卡片看板** in the sidebar to plan and track cards across projects. The
sidebar's **对话范围** selects the conversations shown in the sidebar. The six
board stages are 待规划, 待办, 进行中, 待审核, 已完成 and 已阻塞, with a separate
archive target. Each stage has a card count and wraps to fit the available width.

## Create and organize

Use **新建卡片** or a stage's plus button. Enter a title/description, then choose
status, priority, assignee, project and labels in the property menus. Menus are
searchable and keyboard-accessible. **创建后继续添加** keeps the dialog open and
retains selected parameters while clearing submitted content. **用模型整理标题和描述**
enables assisted creation. Normal creation and successful edits close the dialog.

Assign **我**, a configured endpoint for ordinary execution, or leave the card
unassigned.

Drag a card into another stage or before another card in its current stage.
An active linked Task keeps its card in progress; same-column ordering remains available.
Submission rechecks the source revision. Escape cancels a gesture. Context actions
include pinning, metadata changes, execution, title regeneration, archive/restore
and deletion. Choose **移动卡片** in the card menu to search for a destination.
Choose **关联对话** on a card to select an existing conversation, or assign the
card to a model and choose **启动对话** in the card menu. The selector explains
choices unavailable for the current card.

Toolbar tabs, search and filters narrow the view. **执行中的卡片** counts the
cards with an active linked conversation under the current search and filters.
Enable **自动** for automatic execution. Choose **打开对话** on a linked card to
append input, handle approvals or interrupt execution in that conversation.

## Assistance and files

Assisted creation uses a separately selected ordinary profile to organize the
request into a title and description. This request has no tools. Its profile is
separate from the execution assignee; quality and availability depend on that
endpoint. Explicit offline echo and adaptive task profiles are not drafting
profiles.
**Settings → Conversation titles → Edit title prompts** edits **Task title prompt**
for board cards independently of **Conversation title prompt**. Both retain the shared
schema and normalization. Linked conversations generate their own names;
renaming a card preserves its conversation's title. A linked card can regenerate
its board title while its Task runs. Other metadata changes preserve that request;
explicit title or description edits supersede it, so its late result cannot
overwrite the edit. Restore an archived card before editing or generating a title.

Each title instruction accepts up to 4096 UTF-8 bytes of nonempty text.
Restore defaults changes the draft prompts. Save commits the title settings
together at their observed revision. A revision conflict or editor dismissal
leaves the saved settings in place. Saved settings survive service restart and
apply to future requests. Existing titles and already-dispatched requests are
preserved.

**Conversation title model** selects a configured model connection for future
conversation titles. Automatic mode prefers a configured `gpt-5.6-luna` profile from
the Task's ChatGPT account when available, then uses the Task's own model
connection. In automatic mode, explicitly configured offline echo profiles
retain request-derived names. A selected connection that is no longer
available also leaves the request-derived name in place. Title requests use
the provider's default reasoning independently of the Task's effort and
adaptive evaluator. The shared prompt and Unicode normalization are adapted
from the Apache-2.0
[Codex implementation](https://github.com/openai/codex/blob/ce0323f2f2d3b25e82806cd555237da3db4e1897/codex-rs/tui/src/app/thread_title.rs).

Use the paperclip, paste files into the editor, or drop files onto the form.
Uploads use authenticated storage. Cards support at most four attachments, with
a 10 MiB per-file limit. Supported passive images can be previewed; other files
are downloaded. Submission waits for uploads. Stored references are checked
again at the service boundary; arbitrary local paths cannot substitute for uploads.

Use `bun host/cli.mjs describe` for the live API fields. The authoritative board
command declarations are in [Commands.v](../theories/Kernel/Commands.v);
[Board.v](../theories/Features/Board.v) owns their board behavior.

`bun run check` checks the production proofs and build boundaries;
`bun run test` runs the focused runtime and host integration suite.
