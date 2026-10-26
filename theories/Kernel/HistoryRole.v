From Stdlib Require Import String List.
From Selvedge.Kernel Require Import Domain.
Import ListNotations.
Open Scope string_scope.

(* Both provider projections eliminate this closed vocabulary. Adding a history
   role requires an explicit policy in every backend, including receipt-only
   roles which must not repeat an already committed user instruction. *)
Inductive kind := User | Assistant | Call | Result | Operation | Context | Hook |
  Data | Failure | Provider | Replacement | Transcript | Delegation.
Definition declarations : list (string * kind) := [
  ("user",User);("assistant",Assistant);("function_call",Call);
  ("function_output",Result);("operation_result",Operation);("task_context",Context);
  ("reasoning_record",Data);("tool_receipt",Data);("after_record",Data);("approval_record",Data);
  ("hook_record",Hook);("error",Failure);("model_context",Provider);("context_replacement",Replacement);
  ("speech_transcript",Transcript);("speech_delegation_receipt",Delegation)].
Definition parse name := option_map snd (find (fun declaration => String.eqb name (fst declaration)) declarations).

(* This exhaustive producer view is related to Codec.message_json by
   HistoryRoleProofs.codec_roles_follow_the_shared_projection_vocabulary. *)
Definition of_message (value : message) : option kind := match value with
 | InstructionMessage source _ => parse source
 | EnvironmentNotice _ | ReasoningConfigurationMessage _ | SettingsMessage _ _ _ |
   ContextObservation _ | SideConversationBirth _ _ _ => Some Context
 | UserMessage _ => Some User | AssistantMessage _ _ => Some Assistant
 | FunctionCall _ => Some Call | FunctionOutput _ _ _ | ForkReceipt _ _ _ => Some Result
 | OperationResult _ _ _ _ => Some Operation | FailureMessage _ => Some Failure
 | ReasoningRecord _ _ _ _ | ApprovalReceipt _ _ _ _ _ | ToolReceipt _ _ _ _ _ |
   AfterReceipt _ _ _ _ => Some Data
 | ModelContext _ _ => Some Provider | ContextReplacement _ => Some Replacement
 | SpeechTranscript _ _ _ _ _ _ => Some Transcript
 | SpeechDelegation _ _ _ _ _ => Some Delegation
 | HookReceipt _ _ _ _ => Some Hook
 end.
