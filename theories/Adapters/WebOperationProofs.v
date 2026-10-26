From Stdlib Require Import String Ascii List Bool.
From Selvedge.Adapters Require Import WebCommon Web Api.

(** These observations interpret the actual operation table. Public behavior
    proofs retain their domain requirements without restating its dispatcher. *)
Definition declared_admission name source := match Web.select_operation name with
 | Some operation => base_source source && Web.operation_source operation source | None => false end.
Definition declared_handler name source := match Web.select_operation name with
 | Some operation => Web.operation_run operation source | None => err "Unknown Web model operation" end.
Lemma admitted_call_uses_declared_handler : forall name source,
 declared_admission name source = true -> Web.call name source = declared_handler name source.
Proof.
 intros name source Admitted; unfold declared_admission,declared_handler,Web.call in *.
 destruct (Web.select_operation name); [now rewrite Admitted|discriminate].
Qed.
Lemma successful_call_has_its_declared_admission_and_result : forall name source value,
 Web.call name source = success value ->
 declared_admission name source = true /\ declared_handler name source = success value.
Proof.
 intros name source value Accepted; unfold declared_admission,declared_handler,Web.call in *.
 destruct (Web.select_operation name) as [operation|]; [|discriminate].
 destruct (base_source source && Web.operation_source operation source); [auto|discriminate].
Qed.

Ltac reduce_web_declaration :=
 cbn [declared_admission declared_handler Web.select_operation Web.operations find
   Web.operation_name Web.operation_source Web.operation_run String.eqb Ascii.eqb Bool.eqb].
Tactic Notation "admit_web" "using" tactic3(admission) :=
 lazymatch goal with
 | |- Api.call ?name ?source = ?result =>
   change (Web.call name source = result);
   rewrite (admitted_call_uses_declared_handler name source);
   [reduce_web_declaration | reduce_web_declaration; admission]
 end.
Tactic Notation "observe_web" hyp(accepted) "as" ident(admission) :=
 lazymatch type of accepted with
 | Api.call ?name ?source = _ =>
   let body := fresh "Handler" in
   pose proof (successful_call_has_its_declared_admission_and_result name source _ accepted) as [admission body];
   clear accepted; rename body into accepted;
   cbn [declared_admission declared_handler Web.select_operation Web.operations find
     Web.operation_name Web.operation_source Web.operation_run String.eqb Ascii.eqb Bool.eqb] in admission,accepted
 end.
