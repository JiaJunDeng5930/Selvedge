From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json SequenceProofs.
From Selvedge.Kernel Require Import Compaction CompactionPlan ContextSelection.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Theorem an_unfinished_summary_keeps_every_unread_scalar : forall unread cursor carry width window reserve head tail usage remaining,
 skipn (N.to_nat width) unread = remaining -> remaining <> [] ->
 receive (CompactionState (PortableSource unread) cursor carry width window reserve)
  (JObject [("summary_text",JString (String head tail));("usage",usage)]) =
 Next (CompactionState (PortableSource remaining)
  (cursor + N.of_nat (List.length (firstn (N.to_nat width) unread))) (String head tail) width window reserve).
Proof.
 intros. unfold receive,receive_source. cbn. rewrite H. destruct remaining; [contradiction|].
 unfold chunk. rewrite take_equals_firstn. reflexivity.
Qed.
Theorem an_opaque_reply_cannot_finish_portable_work : forall unread cursor carry width window reserve scope items,
 receive (CompactionState (PortableSource unread) cursor carry width window reserve)
  (JObject [("format",JString "native");("scope",JString scope);("items",JArray items)]) =
 Failed "The compactor returned an empty continuation note".
Proof. reflexivity. Qed.
Theorem an_admitted_plan_fits_its_byte_allocation : forall value budget,
 transport_fits value budget = true -> plan_bytes value <= budget /\ has_transport_work value = true.
Proof.
 intros. apply andb_true_iff in H as [work fits]. apply N.leb_le in fits. auto.
Qed.
