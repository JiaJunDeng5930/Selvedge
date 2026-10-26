From Stdlib Require Import NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import State Inputs Notifications.

(** Admission selects a complete outcome before journal finalization. Birth
    transactions use their construction proofs and output budget; other
    transactions use the world and authority admission pipeline. Neither
    route runs scheduling while advancing the journal or rendering a receipt. *)
Record selected := Selected {
 selected_durable : bool;
 selected_admitted : bool;
 selected_source : option input;
 selected_decision : decision
}.
Definition choose (durable : bool) (source : option input) (outcome : bool * decision) :=
 Selected durable (fst outcome) source (snd outcome).
Definition finalize (before : world) (chosen : selected) : world * json :=
 let result := selected_decision chosen in
 (if selected_durable chosen
  then with_sequence (N.succ (world_sequence before)) (decision_world result)
  else decision_world result,
  Notifications.envelope (selected_durable chosen) (selected_admitted chosen)
    (selected_source chosen) before result).

(** Consumers lift a property of the selected outcome once, rather than
    reopening each transaction's delivery and journal branches. *)
Theorem finalize_preserves : forall (P : world -> Prop) before chosen,
 (forall value sequence, P value -> P (with_sequence sequence value)) ->
 P (decision_world (selected_decision chosen)) -> P (fst (finalize before chosen)).
Proof.
 intros P before [durable admitted source result] Cursor Holds.
 destruct durable; cbn [finalize selected_durable selected_decision fst]; auto.
Qed.
Theorem finalize_has_its_selected_receipt : forall before chosen,
 snd (finalize before chosen) =
 Notifications.envelope (selected_durable chosen) (selected_admitted chosen)
   (selected_source chosen) before (selected_decision chosen).
Proof. intros before []; reflexivity. Qed.
Theorem a_durable_packet_advances_the_cursor : forall before chosen,
 selected_durable chosen = true ->
 world_sequence (fst (finalize before chosen)) = N.succ (world_sequence before).
Proof. intros before [durable admitted source result] Durable; cbn in Durable; subst durable; reflexivity. Qed.
