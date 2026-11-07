From Stdlib Require Import String List.
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
