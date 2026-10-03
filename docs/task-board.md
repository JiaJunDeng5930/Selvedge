# Task board

Open **任务看板** in the sidebar. The six stages are 待规划, 待办, 进行中, 待审核,
已完成 and 阻塞, with a separate archive target. A card is saved work, not an
automatically created conversation.

## Create and organize

Use **新建任务** or a column's plus button. Enter a title/description, then choose
status, priority, assignee, project and labels in the property menus. Menus are
searchable and keyboard-accessible. **继续创建** keeps the dialog open and retains
selected parameters while clearing submitted content. The mode switch selects
manual or assisted creation. Normal creation and successful edits close the dialog.

Unassigned cards do not run. Assign **我** for manual work, an endpoint for
ordinary execution, or a reusable role from **智能体**. Roles specify endpoint,
reasoning, instructions, execution settings and concurrency. Role/project edits
affect future launches, not existing frozen task contracts.

Drag a card into another stage or before another card in its current stage.
Pinned cards form the leading group. Submission rechecks the source revision and
destination. Escape cancels a gesture. Context actions include pinning, metadata
changes, execution, title regeneration, archive/restore and deletion. Deleting a
card does not delete its linked task history.

Toolbar tabs, search and filters narrow the view without recording work commands.
**自动** enables native dispatch of eligible assigned cards, subject to priority
and role concurrency. Open an executed card to follow its linked conversation,
append input, handle approvals or interrupt execution through the existing task UI.

## Assistance and files

Assisted creation uses a separately selected ordinary profile to organize the
request into a title and description. This request has no tools. Its profile is
separate from the execution assignee; quality and availability depend on that
endpoint. The offline demo and adaptive task profiles are not drafting profiles.

Use the paperclip, paste files into the editor, or drop files onto the form.
Uploads use authenticated storage. Cards support at most four attachments, with
a 10 MiB per-file limit. Supported passive images can be previewed; other files
are downloaded. Submission waits for uploads. Stored references are checked
again at the service boundary; arbitrary local paths cannot substitute for uploads.

Use `bun host/cli.mjs describe` for the live API fields. The authoritative board
command definitions are in [board-codec.bend](../bendlib/board-codec.bend).

`bun run test` runs the proof/host boundary suite.
Architecture, reference attribution and proof bindings are in
[ADR 0022](adr/0022-native-task-board.md).
