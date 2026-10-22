# Work, task graphs, board cards and titles

These concepts describe different relationships. A Work owns an undertaking;
a task graph routes replies between Tasks; a board card represents planned work;
a generated title names a card or conversation. Linking two concepts does not
transfer their identity or give them a shared lifecycle.

## Work ownership and shared source

[Work.v](Work.v) resolves a Task's Work through its explicit association and
nearest associated ancestor. Creating a Work Task records the root association
in the same accepted decision as ordinary Task creation. Rejected creation
retains the original world and emits no creation effects.
The recorded root association cannot be transferred. A Task may have no Work;
its children inherit ownership without an additional membership write.
`read_current_task` takes no arguments and reports the nullable `work_id`.
`read_work` exposes the associated graph IDs. `create_work_task` may set
`create_worktree: true`; omission uses ordinary Task creation, and worktree
rejection retains the original world and emits no effects.

Shared UI source belongs to the Work. Tool callers supply no alternate Work ID:
their lineage determines the owner. Exact-context patches require the observed
revision. A successful patch stores its exact result, increments that revision
once and preserves Task/graph ownership and execution. Invalid UI language may
remain stored so that another Task can inspect and repair it. Patch admission
does not claim that the stored UI is a valid or useful interface.
`read_work_ui` and `apply_work_ui_patch` require a calling Task with a Work.
Patches address exactly `work-ui.dsl` and may contain at most 200000 characters;
the resulting source may contain at most 100000 characters. Both limits count
Unicode scalar values. [WorkUIPatch.v](WorkUIPatch.v) owns the exact-context patch
language; [WorkProofs.v](WorkProofs.v) binds the intended updates and ownership
preservation to the production functions.

## Declared handoffs

[TaskGraph.v](TaskGraph.v) accepts checked declarations before installation.
The same admission predicate serves parsed JSON and ordinary Gallina producers
such as `paired` and `compose`. Composition still requires admission: combining
two valid declarations can introduce duplicate keys or exceed graph bounds.
Task existence and Work membership depend on the current world and are checked
during installation. A failed node creation rolls back the whole installation.

Installed graphs route subsequent fresh plain assistant replies. Installation
does not replay history. Interactive output and replies containing tool calls
do not become handoffs. Each matching rule expands its actions in declaration
order; output expressions use the exact reply, literals keep their exact text,
and concatenation preserves fragment order. Graph registration order and rule
order determine the overall attempt order. Each attempt uses ordinary Task
input admission and records its outcome, including rejection by an archived
target or rejection of an empty expanded message. Cycles describe later Task
replies; they do not recursively execute Tasks inside a graph transition.

Open **Task graphs**, choose **New task graph**, and enter a declaration such
as the following, replacing `12` and `13` with existing Task identifiers. Use
**Edit task graph** to replace the declaration.

```json
{
  "name": "Adversarial handoff",
  "nodes": [
    {"key": "tests", "task_id": 12},
    {"key": "implementation", "task_id": 13}
  ],
  "rules": [{
    "key": "deliver-tests",
    "source": "tests",
    "actions": [{"target": "implementation", "message": {"kind": "output"}}]
  }]
}
```

The native tools are `create_task_graph`, `update_task_graph`,
`delete_task_graph`, `read_task_graph`, and `list_task_graphs`. Add `op` for a
command and `graph_id` for an update. The `describe` command exposes the current
command schemas; [TaskGraphDeclarations.v](TaskGraphDeclarations.v) owns the
nested declaration fields and their finite message schema.

An optional top-level `work_id` on creation scopes the graph to a Work. Existing
nodes must already belong to that Work; new Tasks join it in the same decision.
Updates retain the graph's Work. Deleting the graph leaves its Tasks and Work
intact. Omit `work_id` for an independent graph.

[TaskGraphSemantics.v](TaskGraphSemantics.v) states the message and ordered
action and registry meanings without referring to the production expander.
[TaskGraphProofs.v](TaskGraphProofs.v) connects those meanings to actual pending
deliveries, observes a fresh accepted reply and proves the actual dispatcher
adds the delivered input to an idle accepting Task. These positive obligations
exclude an implementation that always produces no deliveries. They do not
assert that an external model eventually answers, that its answer is correct,
or that a Task which rejects input will execute it.

## Planned work and independent names

[Board.v](Board.v) keeps card ordering, revision conflicts, eligibility,
concurrency and scheduling in Gallina. A card exists independently of a
conversation. Launching it freezes the execution request in an ordinary Task;
later role and Project changes affect future launches. Automatic scheduling
uses pinned groups first, descending priority within each group and saved card
order within a priority. The bounded pump requests continuation when work
remains. Filter categories intersect and selections within a category unite;
filtering changes the view rather than recording a card mutation.

An idle card may regenerate its own title after linking a conversation.
Generating or completing that request preserves its linked Task and that
conversation's title. Running, archived or already generating cards remain
locked. [TitleRuntime.v](TitleRuntime.v) freezes the selected profile and prompt
for each conversation-title request. Settings updates affect future requests;
saved names and dispatched snapshots survive. Correlated completions normalize
their result; stale completions leave the current request untouched. Interrupted
pending requests become failed requests during recovery rather than silently
being dispatched again.

## Executable and external boundaries

The feature runtime calls these transitions before the ordinary scheduler;
the extracted public packet entry consumes the same Gallina definitions.
The Rocq kernel checks the stated theorems. Extraction, OCaml/JavaScript
compilation and the host's execution of committed effects remain trusted.
Model quality, delivery of external callbacks and physical cancellation are
external observations, not conclusions of these proofs. Attachment bytes,
storage identity and the clock are observed by [board-files.mjs](../../host/board-files.mjs);
the host does not decide card eligibility, ownership or graph routing.
