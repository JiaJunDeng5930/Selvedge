From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json Schema SequenceProofs.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Numbers ContextTypes Domain Codec State Tasks History
 Callbacks ContextSelection WorldInvariant.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition call_declaration (identity : string) (entry : message) :=
 match entry with FunctionCall invocation => String.eqb identity (call_id invocation) | _ => false end.
Definition call_result (identity : string) (entry : message) :=
 match entry with
 | FunctionOutput actual _ _ | OperationResult _ (Call actual _ _ _) _ _
 | ForkReceipt _ (Call actual _ _ _) _ => String.eqb actual identity
 | _ => false end.

Lemma unique_names_nodup : forall names,
 Schema.unique_names names = true <-> NoDup names.
Proof.
 induction names as [|name rest IH]; cbn [Schema.unique_names].
 - split; intro; constructor.
 - rewrite andb_true_iff, negb_true_iff, IH. split.
   + intros [Absent Unique]; constructor; [|exact Unique].
     intro Present. assert (existsb (String.eqb name) rest = true).
     { apply existsb_exists; exists name; split; [exact Present|apply String.eqb_refl]. }
     congruence.
   + intros Unique; inversion Unique; subst; split; [|assumption].
     destruct (existsb (String.eqb name) rest) eqn:Found; [|reflexivity].
     apply existsb_exists in Found as [actual [Present Equal]].
     apply String.eqb_eq in Equal; subst; contradiction.
Qed.

Lemma nodup_app_apart : forall (A : Type) (left right : list A) value,
 NoDup (left ++ right) -> In value left -> ~ In value right.
Proof. intros A left right value Unique; exact (proj2 (proj2 (distinct_app_parts A left right Unique)) value). Qed.

Lemma existsb_neutral_append : forall (A : Type) (observe : A -> bool) history suffix,
 Forall (fun entry => observe entry = false) suffix ->
 existsb observe (history ++ suffix) = existsb observe history.
Proof.
 intros A observe history suffix Neutral; rewrite existsb_app.
 assert (existsb observe suffix = false).
 { induction Neutral; cbn; [reflexivity|rewrite H, IHNeutral; reflexivity]. }
 rewrite H, orb_false_r; reflexivity.
Qed.

Lemma selected_context_keeps_call_observation : forall observe settings parent history,
 (forall change, observe (ContextObservation change) = false) ->
 (forall settings profile reasoning, observe (SettingsMessage settings profile reasoning) = false) ->
 existsb observe (Tasks.selected_context_history settings parent history) = existsb observe history.
Proof.
 intros observe settings parent history Context Settings.
 unfold Tasks.selected_context_history.
 destruct (Json.equal (settings_json settings) (settings_json (task_current_settings parent)) &&
  Json.equal (settings_guidance settings) (settings_guidance (task_current_settings parent))); [reflexivity|].
 set (removals := fold_right (fun snapshot rest =>
   if Tasks.context_selected (settings_workspace settings) (snapshot_key snapshot) then rest
   else ContextObservation (Remove (snapshot_key snapshot) (snapshot_revision snapshot)) :: rest)
   [] (ContextUpdates.bindings history)) in *.
 assert (Neutral : Forall (fun entry => observe entry = false) removals).
 { unfold removals; generalize (ContextUpdates.bindings history); intro bindings.
   induction bindings as [|snapshot rest IH]; cbn; [constructor|].
   destruct (Tasks.context_selected (settings_workspace settings) (snapshot_key snapshot)); [exact IH|].
   constructor; [apply Context|exact IH]. }
 destruct (Tasks.initial_project_guidance settings) as [snapshot|].
 - destruct (match ContextUpdates.find_snapshot (snapshot_key snapshot)
      (ContextUpdates.bindings (history ++ removals)) with
     | Some previous => Json.equal (Context.snapshot_json previous) (Context.snapshot_json snapshot)
     | None => false end).
   + rewrite existsb_neutral_append by (constructor; [apply Settings|constructor]).
     now apply existsb_neutral_append.
   + rewrite existsb_neutral_append by (constructor; [apply Settings|constructor]).
     rewrite existsb_neutral_append by (constructor; [apply Context|constructor]).
     now apply existsb_neutral_append.
 - rewrite existsb_neutral_append by (constructor; [apply Settings|constructor]).
   now apply existsb_neutral_append.
Qed.

Lemma fork_receipt_keeps_call_observation : forall observe receipt history,
 observe receipt = false ->
 existsb observe (History.fork_receipt_history receipt history) = existsb observe history.
Proof.
 intros observe receipt history Neutral.
 unfold History.fork_receipt_history.
 destruct (rev history) as [|last rest] eqn:Last.
 - apply existsb_neutral_append; constructor; [exact Neutral|constructor].
 - destruct last; try (apply existsb_neutral_append; constructor; [exact Neutral|constructor]).
   assert (History : history = rev rest ++ [UserMessage parts]).
   { rewrite <- (rev_involutive history), Last; cbn; reflexivity. }
   rewrite History, !existsb_app; cbn. now rewrite Neutral.
Qed.

Lemma snapshot_keeps_pending_declarations : forall parent_id parent identity,
 existsb (call_declaration identity) (History.snapshot_operations parent_id parent) =
 existsb (call_declaration identity) (task_history parent).
Proof.
 intros; unfold History.snapshot_operations, History.close_operations.
 apply existsb_neutral_append.
 apply Forall_forall; intros entry Present; apply in_map_iff in Present as [operation [<- Present]].
 unfold History.interrupted_result, History.operation_result.
 destruct (operation_stage operation); destruct (operation_announced operation); reflexivity.
Qed.

Lemma snapshot_keeps_unowned_call_results : forall parent_id parent identity,
 ~ In identity (map (fun operation => call_id (operation_call operation)) (task_operations parent)) ->
 existsb (call_result identity) (History.snapshot_operations parent_id parent) =
 existsb (call_result identity) (task_history parent).
Proof.
 intros parent_id parent identity Apart; unfold History.snapshot_operations, History.close_operations.
 apply existsb_neutral_append.
 apply Forall_forall; intros entry Present; apply in_map_iff in Present as [operation [<- Present]].
 assert (Different : call_id (operation_call operation) <> identity).
 { intro Equal; apply Apart; apply in_map_iff; exists operation; auto. }
 apply String.eqb_neq in Different.
 unfold History.interrupted_result, History.operation_result.
 destruct (operation_stage operation); destruct (operation_announced operation);
 destruct (operation_call operation); cbn in Different |- *; exact Different.
Qed.

Definition native_child (parent_id owner start : N) (parent : task) (contents : option content)
 (settings : task_settings) (invocation : call) (remaining : list call) :=
 Tasks.fork_child_receipt (Tasks.AcceptedNativeFork invocation remaining) start owner invocation
  (Tasks.fork_child owner parent_id parent contents settings false).

(* Dispatch removes the executing invocation from the pending phase before the
   native action runs. Its identity remains distinct from the accepted suffix. *)
Record native_fork_certificate (invocation : call) (remaining : list call) (parent : task) : Prop :=
 NativeForkCertificate {
  native_pending_phase : WorldInvariant.phase_calls (task_activity parent) = remaining;
  native_invocation_apart : Forall (fun pending => call_id invocation <> call_id pending) remaining
 }.

Lemma checked_native_dispatch_certifies_remaining : forall source invocation remaining,
 WorldInvariant.phase_calls (task_activity source) = invocation :: remaining ->
 WorldInvariant.phase_valid source = true ->
 native_fork_certificate invocation remaining (with_activity (PendingCalls remaining) source).
Proof.
 intros source invocation remaining Phase Valid; constructor.
 - assert (Activity : task_activity (with_activity (PendingCalls remaining) source) = PendingCalls remaining).
   { destruct source as [contract profile settings lifecycle history queued lineage side cursor consumed].
     destruct lifecycle; try reflexivity.
     cbn [task_activity WorldInvariant.phase_calls] in Phase; discriminate. }
   now rewrite Activity.
 - unfold WorldInvariant.phase_valid in Valid; apply andb_true_iff in Valid as [Calls _].
   unfold WorldInvariant.calls_valid in Calls; rewrite Phase in Calls.
   apply andb_true_iff in Calls as [_ Unique]; apply unique_names_nodup in Unique.
   inversion Unique as [|? ? Apart Tail]; subst.
   apply Forall_forall; intros pending Present Equal; apply Apart.
   rewrite Equal; apply in_map; exact Present.
Qed.

Lemma native_child_keeps_remaining_open : forall parent_id owner start parent contents settings invocation remaining pending,
 native_fork_certificate invocation remaining parent ->
 WorldInvariant.phase_valid parent = true ->
 WorldInvariant.operations_valid parent_id parent = true ->
 In pending remaining ->
 WorldInvariant.call_open (task_history (native_child parent_id owner start parent contents settings invocation remaining))
   (Domain.recovery_call pending) = true.
Proof.
 intros parent_id owner start parent contents settings invocation remaining pending Certificate PhaseValid Operations Present.
 destruct Certificate as [Phase Separate].
 unfold WorldInvariant.phase_valid in PhaseValid.
 apply andb_true_iff in PhaseValid as [Calls _]. rewrite Phase in Calls.
 unfold WorldInvariant.calls_valid in Calls; apply andb_true_iff in Calls as [Open Unique].
 assert (Different : call_id invocation <> call_id pending).
 { apply Forall_forall with (x:=pending) in Separate; assumption. }
 unfold WorldInvariant.operations_valid in Operations.
 repeat rewrite andb_true_iff in Operations.
 destruct Operations as [[_ AllUnique] _]. rewrite Phase in AllUnique.
 apply unique_names_nodup in AllUnique.
 assert (Apart : ~ In (call_id pending) (map (fun operation => call_id (operation_call operation)) (task_operations parent))).
 { eapply nodup_app_apart; [exact AllUnique|apply in_map; exact Present]. }
 apply forallb_forall with (x:=pending) in Open; [|exact Present].
 unfold WorldInvariant.call_open, Callbacks.call_known, ContextSelection.has_output in Open |- *.
 change (existsb (call_declaration (call_id pending)) (task_history parent) &&
   negb (existsb (call_result (call_id pending)) (task_history parent)) = true) in Open.
 unfold native_child, Tasks.fork_child_receipt, Tasks.fork_child, Tasks.fork_child_history,
   with_history, with_activity; cbv [set]; cbn [task_history].
 change (existsb (call_declaration (call_id pending))
   (History.fork_receipt_history (ForkReceipt owner invocation (N.succ (owner - start)))
    (Tasks.selected_context_history settings parent (History.snapshot_operations parent_id parent) ++
      Tasks.optional_input contents)) &&
  negb (existsb (call_result (call_id pending))
   (History.fork_receipt_history (ForkReceipt owner invocation (N.succ (owner - start)))
    (Tasks.selected_context_history settings parent (History.snapshot_operations parent_id parent) ++
      Tasks.optional_input contents))) = true).
 rewrite !fork_receipt_keeps_call_observation.
 2: destruct invocation; cbn [call_result] in *; now apply String.eqb_neq.
 2: reflexivity.
 assert (Neutral : forall observe, (forall parts, observe (UserMessage parts) = false) ->
   existsb observe (Tasks.selected_context_history settings parent (History.snapshot_operations parent_id parent) ++
     Tasks.optional_input contents) =
   existsb observe (Tasks.selected_context_history settings parent (History.snapshot_operations parent_id parent))).
 { intros observe User. apply existsb_neutral_append.
   destruct contents; cbn [Tasks.optional_input]; [constructor; [apply User|constructor]|constructor]. }
 rewrite !Neutral by (intros; reflexivity).
 rewrite !selected_context_keeps_call_observation by reflexivity.
 rewrite snapshot_keeps_pending_declarations, snapshot_keeps_unowned_call_results by exact Apart.
 exact Open.
Qed.

Lemma recovery_keeps_call_names : forall remaining,
 map call_id (map Domain.recovery_call remaining) = map call_id remaining.
Proof. induction remaining; cbn; congruence. Qed.

Lemma native_child_activity : forall parent_id owner start parent contents settings invocation remaining,
 task_activity (native_child parent_id owner start parent contents settings invocation remaining) =
 match remaining with [] => WantsModel | _ => PendingCalls (map Domain.recovery_call remaining) end.
Proof.
 intros; unfold native_child, Tasks.fork_child_receipt, Tasks.fork_child,
   with_activity, with_history; cbv [set]; reflexivity.
Qed.

Lemma native_child_operations : forall parent_id owner start parent contents settings invocation remaining,
 task_operations (native_child parent_id owner start parent contents settings invocation remaining) = [].
Proof.
 intros; unfold native_child, Tasks.fork_child_receipt, Tasks.fork_child,
   with_activity, with_history; cbv [set]; reflexivity.
Qed.

Lemma native_remaining_calls_valid : forall parent_id owner start parent contents settings invocation remaining,
 native_fork_certificate invocation remaining parent ->
 WorldInvariant.phase_valid parent = true ->
 WorldInvariant.operations_valid parent_id parent = true ->
 WorldInvariant.calls_valid
  (task_history (native_child parent_id owner start parent contents settings invocation remaining))
  (map Domain.recovery_call remaining) = true.
Proof.
 intros parent_id owner start parent contents settings invocation remaining Certificate PhaseValid Operations.
 unfold WorldInvariant.calls_valid; apply andb_true_iff; split.
 - apply forallb_forall; intros pending Present.
   apply in_map_iff in Present as [original [<- Present]].
   eapply native_child_keeps_remaining_open; eassumption.
 - rewrite recovery_keeps_call_names.
   unfold WorldInvariant.phase_valid in PhaseValid.
   apply andb_true_iff in PhaseValid as [Calls _].
   destruct Certificate as [Phase _]; rewrite Phase in Calls.
   unfold WorldInvariant.calls_valid in Calls.
   now apply andb_true_iff in Calls as [_ Unique].
Qed.

(* Accepted calls remain open in the child because snapshots close only operation
   identities, and the source invariant separates those from pending identities. *)
Theorem every_native_child_has_valid_execution_state :
 forall parent_id owner start parent contents settings invocation remaining,
 native_fork_certificate invocation remaining parent ->
 WorldInvariant.phase_valid parent = true ->
 WorldInvariant.operations_valid parent_id parent = true ->
 let child := native_child parent_id owner start parent contents settings invocation remaining in
 WorldInvariant.phase_valid child = true /\
 WorldInvariant.checked_phase owner child = true /\
 WorldInvariant.operations_valid owner child = true.
Proof.
 intros parent_id owner start parent contents settings invocation remaining Certificate PhaseValid Operations child.
 pose proof (native_remaining_calls_valid parent_id owner start parent contents settings invocation remaining
   Certificate PhaseValid Operations) as Calls.
 change (WorldInvariant.calls_valid (task_history child) (map Domain.recovery_call remaining) = true) in Calls.
 assert (Activity : task_activity child = match remaining with
   [] => WantsModel | _ => PendingCalls (map Domain.recovery_call remaining) end).
 { apply native_child_activity. }
 assert (NoOperations : task_operations child = []).
 { apply native_child_operations. }
 unfold WorldInvariant.phase_valid, WorldInvariant.checked_phase, WorldInvariant.operations_valid.
 rewrite Activity, NoOperations.
 destruct remaining as [|first rest]; cbn [WorldInvariant.phase_calls].
 - repeat split; reflexivity.
 - split.
   + rewrite Calls; reflexivity.
   + split; [reflexivity|].
   unfold WorldInvariant.calls_valid in Calls.
   apply andb_true_iff in Calls as [_ Unique].
   rewrite app_nil_r, Unique; reflexivity.
Qed.


Corollary legal_parent_gives_every_native_child_valid_execution_state :
 forall before parent_id owner start parent contents settings invocation remaining,
 WorldInvariant.task_valid parent_id parent before = true ->
 native_fork_certificate invocation remaining parent ->
 let child := native_child parent_id owner start parent contents settings invocation remaining in
 WorldInvariant.phase_valid child = true /\
 WorldInvariant.checked_phase owner child = true /\
 WorldInvariant.operations_valid owner child = true.
Proof.
 intros before parent_id owner start parent contents settings invocation remaining Valid Certificate.
 unfold WorldInvariant.task_valid in Valid.
 repeat match goal with
 | H : _ && _ = true |- _ => apply andb_true_iff in H as [? ?]
 end.
 apply every_native_child_has_valid_execution_state; assumption.
Qed.
