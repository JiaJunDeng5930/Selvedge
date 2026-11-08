# Business interaction

The interaction model defines the information a user can obtain, the decisions a
user can make, and the meaning of the service's feedback. The browser and CLI
choose how to present that information and collect input. Production dependency
checking rejects a transitive dependency from Interaction to Browser.

`Experience.Publication` supplies the Task and Project observations used by the
existing read commands, events and the published world. The board commands and
publication use the same card and agent facts from Features. `Experience.Read`
projects the published world into typed observations for the browser.
`ObjectDecisions` supplies object commands and their confirmation prompts.
`CardDecisions` describes positions and tasks that can be selected and
constructs command proposals for the browser's menu and drag-and-drop.

`Experience.Model`, `Experience.Activity` and `Experience.Observation` describe
editor subjects, facts, decisions, and their requirements. An `EditorContext`
provides the draft and the relevant observed resources. Each entry owns its
session and provides those observations. Typed draft fields, their edits and
command values use the shared declarations in `Submission` and
`Kernel.CommandDeclarations`.

`CommandAssessment` relates a proposed command to its owner, revision and world
sequence. `UserCommand` defines which commands are available to public callers
and interprets command receipts. The Kernel assesses and executes the command.
The service observes external prerequisites such as directory guidance at its
trusted submission boundary. [Requirements](../../requirements/README.md) bind
the shared functions to the browser and HTTP entry points.
