# Task graph

Task graphs compose existing Tasks through declared output handlers. Graph nodes
retain Task identifiers; Task settings, execution and message queues stay owned
by the harness.

Start with [MODEL.bend](MODEL.bend) for the public vocabulary and checked
declaration constructors, [SPEC.bend](SPEC.bend) for admission requirements, and
[PROGRAM.bend](PROGRAM.bend) for registry changes and message expansion.
[CODEC.bend](CODEC.bend) owns the public JSON surface. [CONTRACT.bend](CONTRACT.bend)
and [PROOF.bend](PROOF.bend) bind the domain properties to production functions.

Open **Task graphs** in the UI, choose **New task graph**, and paste a declaration
such as the following. Replace `12` and `13` with actual existing Task IDs. After
installation, subsequent normal text replies from `tests` are sent to
`implementation` through the ordinary Task message operation. Use **Edit task
graph** to replace the declaration.

```json
{
  "name": "Adversarial handoff",
  "nodes": [
    {"key": "tests", "task_id": 12},
    {"key": "implementation", "task_id": 13}
  ],
  "rules": [
    {
      "key": "deliver-tests",
      "source": "tests",
      "actions": [
        {"target": "implementation", "message": {"kind": "output"}}
      ]
    }
  ]
}
```

The native tools are `create_task_graph`, `update_task_graph`,
`delete_task_graph`, `read_task_graph`, and `list_task_graphs`. The `describe`
command exposes their current command schemas; add `op` to the declaration for
command input, and `graph_id` when updating.

`create_task_graph` accepts an optional top-level `work_id`. Existing nodes in a
Work graph must already belong to that Work; newly created nodes join it in the
same committed decision. Updates retain the graph's Work. Deleting a graph leaves
its Tasks and Work intact. Omit `work_id` for an independent graph.

Ordinary Bend functions build declarations. A new arrangement of existing
capabilities requires a new construction, rather than a new interpreter case.
In [MODEL.bend](MODEL.bend), `paired(name, tests, implementation, rule, message)`
builds a two-node handoff, `compose(name, left, right)` joins declarations, and
`construct(declaration)` checks admission before the declaration is used.
The feature assembly resolves newly created Task references, installs the whole
declaration before scheduling, and interprets matched deliveries through the
ordinary Task message operation. This module does not execute Tasks or host
effects.

Read [harness feature composition](../../harness/features/README.md) for atomic
installation, accepted-reply integration and the complete decision contract.
