From Stdlib Require Import String List NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain Codec HistoryRole.
Open Scope string_scope.

Theorem codec_roles_follow_the_shared_projection_vocabulary : forall project_call owner value,
 HistoryRole.parse (text_default "role" (Codec.message_json_with project_call owner value) "") =
 HistoryRole.of_message value.
Proof. intros project_call owner value;destruct value;reflexivity. Qed.
