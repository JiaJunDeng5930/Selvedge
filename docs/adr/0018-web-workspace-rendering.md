# Web workspace and incremental rendering

The Web adapter retains the native presentation boundary from ADR 0014. This
change rearranges existing widgets and adds browser rendering mechanics; it does
not add a second task model or extend `UI.bend`.

The visual references were the Codex app, T3 Code and Alma: quiet task navigation,
a constrained reading column, an anchored composer and secondary details revealed
on demand. Their terminal, Git, file and other product features are not reproduced
where the native presentation has no corresponding widget. References:
https://openai.com/index/introducing-the-codex-app/,
https://t3.codes/, https://alma.now/.

Replacing the entire root on each commit previously lost DOM identity. The new
renderer reconciles native keys and updates only changed widget properties.
Local drafts, focus, disclosure, theme and scrolling remain presentation state.
The browser sends the supplied event template and field bindings unchanged in
meaning; native submission is still the authority for whether an action succeeds.

Streaming input has three independent states: the accumulated target, the paced
visible cursor, and the parser's stable/open structures. New text is batched in
time and appended into only the open structure. Stable nodes are not reparsed.
A shared display scheduler limits competing history-message work, while a worker
handles closed-block highlighting and math. This bounds ordinary incremental
work; it is not a formal hard-real-time guarantee for all browsers or inputs.

The host's authenticated delta transport now has explicit start, output index,
cancellation and post-commit end correlation. Those notices can render a
disposable preview, never a native message or an enabled action. The client
retires previews only after their settlement revision is reflected in a native
presentation. Exact settled text can reuse its DOM; other results use the native
projection. Lost connections discard uncommitted previews rather than inventing
missing text. No provider JSON roles or completion policy move into JavaScript.

This clarifies ADR 0014's committed-snapshot boundary: committed native snapshots
still exclusively determine task content and actions; a separately labelled,
non-authoritative transport preview does not replace them. No new proof claim
about browser DOM or upstream Markdown libraries is made. Browser mechanics,
adverse network input and formatting safety are checked by executable boundary
tests; Bend proof obligations remain attached to the production definitions.
