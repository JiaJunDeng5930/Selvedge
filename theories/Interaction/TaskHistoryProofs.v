From Stdlib Require Import List.
From Selvedge.Interaction Require Import TaskHistory.
Import ListNotations.

Local Definition step_entries item := match item with
 | Commentary message => [message]
 | Tools first rest => map invocation_entry (first :: rest)
 | Supporting first rest => first :: rest end.
Local Definition section_entries item := match item with
 | Speech message => [message]
 | Process _ steps _ => flat_map step_entries steps end.
Local Definition event_entries (event : option (entry + activity)) := match event with
 | Some (inl message) => [message]
 | Some (inr activity) => [activity_entry activity]
 | None => [] end.

Local Lemma prepend_step_keeps_anchor : forall item tail,
 flat_map step_entries (prepend_step item tail) = activity_entry item :: flat_map step_entries tail.
Proof.
 intros item [|next tail]; [now destruct item|now destruct item, next].
Qed.

Local Lemma prepend_section_keeps_anchor : forall event tail,
 flat_map section_entries (prepend_section event tail) =
 event_entries event ++ flat_map section_entries tail.
Proof.
 intros [[message|item]|] tail; try reflexivity.
 destruct tail as [|[message|identity steps ended] tail];
   cbn [prepend_section section_entries flat_map event_entries];
   rewrite prepend_step_keeps_anchor; reflexivity.
Qed.

(** The history's visible anchors stay in chronological order. A result shown
    inside an invocation changes its details, but does not supply its anchor. *)
Theorem grouping_preserves_visible_history_positions : forall history operations,
 let entries := indexed 0 history in
 let calls := fold_left index_entry entries (fold_left index_operation operations (Calls.empty evidence)) in
 flat_map section_entries (project history operations) =
 flat_map (fun item => event_entries (visible calls item)) entries.
Proof.
 intros history operations entries calls.
 unfold project; fold entries calls.
 clearbody calls entries. induction entries as [|item rest IH]; [reflexivity|].
 cbn [fold_right flat_map]. rewrite prepend_section_keeps_anchor, IH. reflexivity.
Qed.

(** A result processor can change a tool outcome. Matching outcomes require
    one disclosure, while a changed outcome leaves the original receipt usable. *)
Theorem an_execution_receipt_is_disclosed_only_if_distinct_from_the_result :
 forall item id before result receipt,
 settled_result before = Some result -> execution_receipt before = Some receipt ->
 invocation_result (present_call item id before) = Some result /\
 invocation_receipt (present_call item id before) =
   (if same_outcome result receipt then None else Some receipt).
Proof.
 intros item id before result receipt Settled Received.
 unfold present_call. rewrite Settled, Received. split; reflexivity.
Qed.
