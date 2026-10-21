From Stdlib Require Import String Bool NArith.
From Selvedge.Interaction Require CodeBlock.
From Selvedge.Interaction.Submission Require Fields.

(** Native control intent is derived once from the actual action at publication.
    It carries the original control grammar; it is not another action registry. *)
Inductive purpose :=
| MessageSubmission | NamedAction | CreateItem | EditItem | ProjectTaskCreation
| WorkCreation
| OpenCardDetails (card : N)
| NavigateTo (symbol : string)
| MoreActions (expanded : bool)
| OpenPanel (symbol : string) (menu expanded : bool)
| ChooseValue (expanded : bool) | WorkspacePicker (expanded : bool)
| SelectedOption (checked : bool) | Dismiss
| StopExecution | PauseExecution | ResumeExecution | InterruptExecution | AbortOperation
| ApprovalDecision (allow : bool) | DeleteItem | ArchiveItem (archived : bool)
| PinItem (pinned : bool) | AutomaticScheduling (enabled : bool) | Regenerate
| CopyCode (state : CodeBlock.copy_state) | WrapCode (enabled : bool)
| ShowActivity (expanded : bool) | Latest | ToggleNavigation (expanded : bool)
| ResetDefaults | RemoveValue | RetryTransfer | PreviewFile | DownloadFile
| Connect (connecting : bool).

Definition toggle_widget (field:Fields.field)(observation:Fields.observed) :=
 match field with Fields.NetworkAccess|Fields.AssistedCapture=>true
 |_=>match observation with Fields.ToggleValue _=>true|_=>false end end.
