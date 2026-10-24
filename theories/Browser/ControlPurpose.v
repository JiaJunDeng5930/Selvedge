From Stdlib Require Import String Bool NArith.
From Selvedge.Features Require BoardFilter.
From Selvedge.Interaction Require CodeBlock.
From Selvedge.Interaction.Submission Require Fields.

(** Native control intent is derived once from the actual action at publication.
    It carries the original control grammar; it is not another action registry. *)
Inductive purpose :=
| MessageSubmission | NamedAction | CreateItem | EditItem | ForkTask | CompactTask | ProjectTaskCreation
| WorkCreation
| OpenCardDetails (card : N)
| ProjectDisclosure (project : N)
| NavigateTo (symbol : string)
| MoreActions (expanded : bool)
| OpenPanel (symbol : string) (menu expanded : bool)
| ApplicationSettings (expanded : bool) | GlobalDestinations (expanded : bool)
| ChooseValue (expanded : bool) | WorkspacePicker (expanded : bool)
| SelectedOption (checked : bool)
| BoardFilterChoice (category : BoardFilter.category) (value : string)
| Dismiss
| StopExecution | PauseExecution | ResumeExecution | InterruptExecution | AbortOperation
| ApprovalDecision (allow : bool) | DeleteItem | ArchiveItem (archived : bool)
| PinItem (pinned : bool) | AutomaticScheduling (enabled : bool) | Regenerate
| CopyCode (state : CodeBlock.copy_state) | WrapCode (enabled : bool)
| ShowActivity (expanded : bool) | Latest | ToggleNavigation (expanded : bool)
| ResetDefaults | RemoveValue | RetryTransfer | PreviewFile | DownloadFile
| Connect (connecting : bool) (failure : option string).

Definition toggle_widget (field:Fields.field)(observation:Fields.observed) :=
 match field with Fields.NetworkAccess|Fields.AssistedCapture=>true
 |_=>match observation with Fields.ToggleValue _=>true|_=>false end end.
