From Stdlib Require Import String List NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain Codec HistoryRole.
Open Scope string_scope.

Theorem codec_roles_follow_the_shared_projection_vocabulary : forall project_call owner value,
 HistoryRole.parse (text_default "role" (Codec.message_json_with project_call owner value) "") =
 match value with
 | InstructionMessage source _ => parse source
 | EnvironmentNotice _ | ReasoningConfigurationMessage _ | SettingsMessage _ _ _ |
   ContextObservation _ | SideConversationBirth _ _ _ => Some Context
 | UserMessage _ => Some User | AssistantMessage _ _ => Some Assistant
 | FunctionCall _ => Some Call | FunctionOutput _ _ _ | ForkReceipt _ _ _ => Some Result
 | OperationResult _ _ _ _ => Some Operation | FailureMessage _ => Some Failure
 | ReasoningRecord _ _ _ _ | ApprovalReceipt _ _ _ _ | ToolReceipt _ _ _ _ _ |
   AfterReceipt _ _ _ _ => Some Data
 | ModelContext _ _ => Some Provider | ContextReplacement _ => Some Replacement
 | SpeechTranscript _ _ _ _ _ _ => Some Transcript
 | SpeechDelegation _ _ _ _ _ => Some Delegation
 | HookReceipt _ _ _ _ => Some Hook
 end.
Proof. intros project_call owner value;destruct value;reflexivity. Qed.
