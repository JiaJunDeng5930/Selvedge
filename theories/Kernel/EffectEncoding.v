From Selvedge.Kernel Require Import State ModelDeclarations.
From Selvedge.Features Require Import CompactionTypes.

(** Every executable constructor selects one public payload and callback declaration. *)
Definition declaration (value : State.effect) : ModelDeclarations.variant := match value with
 | ObserveContext _ _ _ => ModelDeclarations.observe_context
 | RequestModel _ => ModelDeclarations.request_model
 | RequestReasoning _ _ _ => ModelDeclarations.reasoning
 | ExecuteTool _ _ _ _ _ _ _ => ModelDeclarations.tool
 | RequestApproval _ _ _ _ _ => ModelDeclarations.approval
 | CheckTool _ _ _ _ _ => ModelDeclarations.hook
 | CheckResult _ _ _ _ _ _ _ => ModelDeclarations.after_hook
 | ResetModelSession _ => ModelDeclarations.reset_model_session
 | CancelTask _ => ModelDeclarations.cancel
 | CancelTicket _ _ => ModelDeclarations.cancel_ticket
 | ContinueScheduling => ModelDeclarations.continue
 | CreateWorktree _ _ _ _ => ModelDeclarations.worktree_create
 | ArchiveWorktree _ _ _ _ => ModelDeclarations.worktree_archive
 | SuggestTitle _ _ _ _ => ModelDeclarations.task_title
 | SuggestCard _ _ _ _ _ _ _ => ModelDeclarations.board_text
 | RunConnectionJob _ _ => ModelDeclarations.chatgpt_exec
 | CancelConnectionJob _ => ModelDeclarations.chatgpt_cancel
 | MaintainContext request => match request with
   | CompactionTypes.Scope _ _ _ => ModelDeclarations.context_scope
   | CompactionTypes.Measure _ _ _ _ _ => ModelDeclarations.context_measure
   | CompactionTypes.Compact _ _ _ _ _ _ => ModelDeclarations.context_compaction
   | CompactionTypes.ArmClock _ => ModelDeclarations.compaction_clock
   | CompactionTypes.Cancel _ _ => ModelDeclarations.compaction_cancel end
 end.
