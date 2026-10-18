# Task titles

Owns background automatic task names independently of task execution and history.
Start with [MODEL.bend](MODEL.bend), [SPEC.bend](SPEC.bend) and
[CONTRACT.bend](CONTRACT.bend); [PROGRAM.bend](PROGRAM.bend) realizes the requests.
[STATE.bend](STATE.bend) binds the task registry and title observation to the
assembled world. [PROOF.bend](PROOF.bend) supplies complete-decision refinement.

The shared [title policy](../../harness/conversation/TITLE.bend) owns the Codex
defaults, UTF-8 input budget, output schema and Unicode normalization for both
conversations and board cards. The host interprets committed requests through
`host/task-text.mjs`; it does not choose when to generate a title.

**Settings → 标题生成** opens separate editable instructions for **Task 看板标题**
and **Agent 会话标题**. Each accepts up to 4096 UTF-8 bytes. JSON formatting,
single-line output and the 36-character limit remain system constraints. Restore
defaults updates the editor's draft; Save commits both fields. Cancel leaves saved
instructions unchanged. Settings survive service restart in the existing journal.

[CODEC.bend](CODEC.bend) publishes `read_title_settings` and
`configure_title_settings`. Updates require the observed settings revision;
conflicts refuse the whole write. Settings changes affect future generations and
preserve saved names, conversations and already-dispatched prompt snapshots.
Board cards and linked Agent conversations generate and retain independent names.

No separate setup is required for model tasks. ChatGPT account tasks prefer a
configured `gpt-5.6-luna` profile from the same account; other tasks use their own model connection.
Title requests do not inherit adaptive reasoning or task effort. Offline demo profiles keep request-derived
names. Board assistance keeps its explicitly selected drafting profile.

The prompt and normalization are adapted from the Apache-2.0
[Codex implementation](https://github.com/openai/codex/blob/ce0323f2f2d3b25e82806cd555237da3db4e1897/codex-rs/tui/src/app/thread_title.rs).
