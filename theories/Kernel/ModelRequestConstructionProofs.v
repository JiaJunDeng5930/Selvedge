From Stdlib Require Import String List Bool NArith.
From Selvedge.Kernel Require Import Domain ModelRequest.
Import ListNotations.

Theorem a_frozen_model_has_a_canonical_selection : forall owner (choice : ModelRequest.frozen owner),
 ModelRequest.canonical owner (ModelRequest.model choice) (ModelRequest.base choice).
Proof. intros owner choice; exact (ModelRequest.selected_by_reasoning choice). Qed.

Theorem every_model_request_has_one_sent_phase : forall request,
 ModelRequest.request_activity request = AskingModel (ModelRequest.ticket request)
   (ModelRequest.callable request) (ModelRequest.mode request).
Proof. reflexivity. Qed.

Theorem capturing_history_preserves_the_selected_model : forall history request,
 ModelRequest.selection (ModelRequest.with_history history request) = ModelRequest.selection request /\
 ModelRequest.request_activity (ModelRequest.with_history history request) = ModelRequest.request_activity request.
Proof. intros; split; reflexivity. Qed.

Theorem choosing_context_preserves_the_selected_model : forall scope reserve request,
 ModelRequest.selection (ModelRequest.with_context scope reserve request) = ModelRequest.selection request /\
 ModelRequest.request_activity (ModelRequest.with_context scope reserve request) = ModelRequest.request_activity request /\
 ModelRequest.history (ModelRequest.with_context scope reserve request) = ModelRequest.history request.
Proof. intros; repeat split; reflexivity. Qed.

Lemma choosing_a_fixed_profile : forall owner source chosen,
 ModelRequest.Plans.next owner source = ModelRequest.Plans.Fixed chosen ->
 exists choice,
 ModelRequest.choose owner source = Some choice /\
 ModelRequest.model choice = chosen /\ ModelRequest.base choice = source.
Proof.
 intros owner source chosen Selected. unfold ModelRequest.choose.
 assert (General : forall planned (evidence : ModelRequest.Plans.next owner source = planned),
 planned = ModelRequest.Plans.Fixed chosen ->
 exists choice,
 (match planned as selected return ModelRequest.Plans.next owner source = selected -> option (ModelRequest.frozen owner) with
 | ModelRequest.Plans.Fixed model => fun evidence => Some (ModelRequest.freeze owner source model None evidence)
 | ModelRequest.Plans.Reuse model remaining => fun evidence => Some (ModelRequest.freeze owner source model (Some remaining) evidence)
 | ModelRequest.Plans.Evaluate => fun _ => None end evidence) = Some choice /\
 ModelRequest.model choice = chosen /\ ModelRequest.base choice = source).
 { intros [model|model remaining|] evidence Equal; try discriminate.
   inversion Equal; subst model. eexists; repeat split; reflexivity. }
 apply General; exact Selected.
Qed.

Lemma choosing_an_evaluator : forall owner source,
 ModelRequest.Plans.next owner source = ModelRequest.Plans.Evaluate ->
 ModelRequest.choose owner source = None.
Proof.
 intros owner source Selected. unfold ModelRequest.choose.
 assert (General : forall planned (evidence : ModelRequest.Plans.next owner source = planned),
 planned = ModelRequest.Plans.Evaluate ->
 (match planned as selected return ModelRequest.Plans.next owner source = selected -> option (ModelRequest.frozen owner) with
 | ModelRequest.Plans.Fixed model => fun evidence => Some (ModelRequest.freeze owner source model None evidence)
 | ModelRequest.Plans.Reuse model remaining => fun evidence => Some (ModelRequest.freeze owner source model (Some remaining) evidence)
 | ModelRequest.Plans.Evaluate => fun _ => None end evidence) = None).
 { intros [model|model remaining|] evidence Equal; try discriminate; reflexivity. }
 apply General; exact Selected.
Qed.

Lemma choosing_an_adaptive_lease : forall owner source chosen remaining,
 ModelRequest.Plans.next owner source = ModelRequest.Plans.Reuse chosen remaining ->
 exists choice,
 ModelRequest.choose owner source = Some choice /\
 ModelRequest.model choice = chosen /\
 ModelRequest.base choice = ModelRequest.Plans.generation owner chosen remaining source.
Proof.
 intros owner source chosen remaining Selected. unfold ModelRequest.choose.
 assert (General : forall planned (evidence : ModelRequest.Plans.next owner source = planned),
 planned = ModelRequest.Plans.Reuse chosen remaining ->
 exists choice,
 (match planned as selected return ModelRequest.Plans.next owner source = selected -> option (ModelRequest.frozen owner) with
 | ModelRequest.Plans.Fixed model => fun evidence => Some (ModelRequest.freeze owner source model None evidence)
 | ModelRequest.Plans.Reuse model count => fun evidence => Some (ModelRequest.freeze owner source model (Some count) evidence)
 | ModelRequest.Plans.Evaluate => fun _ => None end evidence) = Some choice /\
 ModelRequest.model choice = chosen /\
 ModelRequest.base choice = ModelRequest.Plans.generation owner chosen remaining source).
 { intros [model|model count|] evidence Equal; try discriminate.
   inversion Equal; subst model count. eexists; repeat split; reflexivity. }
 apply General; exact Selected.
Qed.

Theorem a_captured_model_retains_its_original_selection_authority : forall history request,
 ModelRequest.canonical (ModelRequest.owner request)
   (ModelRequest.model (ModelRequest.selection (ModelRequest.with_history history request)))
   (ModelRequest.base (ModelRequest.selection (ModelRequest.with_history history request))).
Proof. intros; apply a_frozen_model_has_a_canonical_selection. Qed.

Theorem installing_a_running_model_request_uses_its_sent_phase : forall request phase operations,
 task_lifecycle (ModelRequest.base (ModelRequest.selection request)) = Running phase operations ->
 task_activity (ModelRequest.pending_task request) = ModelRequest.request_activity request.
Proof.
 intros [owner [model [contract profile settings lifecycle original queued lineage parent cursor consumed] Selection]
   ticket callable mode history scope reserve] phase operations Running.
 cbn in Running; subst lifecycle; reflexivity.
Qed.

Lemma generation_preserves_the_requested_profile : forall owner model remaining source,
 task_current_profile (ModelRequest.Plans.generation owner model remaining source) = task_current_profile source.
Proof.
 intros owner model remaining source.
 unfold ModelRequest.Plans.generation.
 repeat match goal with |- context [if ?condition then _ else _] => destruct condition end;
 destruct source; reflexivity.
Qed.

Lemma prepared_preserves_the_requested_profile : forall owner source model remaining,
 task_current_profile (ModelRequest.prepared owner source model remaining) = task_current_profile source.
Proof.
 intros; destruct remaining; [apply generation_preserves_the_requested_profile|reflexivity].
Qed.

Definition supported_by_profile (model requested : profile) : Prop :=
 match profile_policy requested with
 | FixedReasoning => model = requested
 | AdaptivePolicy policy => exists effort,
   ModelRequest.Plans.allowed policy effort = true /\ model = Codec.with_reasoning effort requested
 end.

Lemma canonical_selection_is_supported : forall owner source model remaining,
 ModelRequest.Plans.next owner source = ModelRequest.chosen_plan model remaining ->
 supported_by_profile model (task_current_profile source).
Proof.
 intros owner source model remaining Selected.
 unfold ModelRequest.Plans.next in Selected.
 unfold supported_by_profile.
 destruct (profile_policy (task_current_profile source)) as [|policy] eqn:Policy.
 - destruct remaining; inversion Selected; reflexivity.
 - destruct (ModelRequest.LeaseState.history_lease owner (task_history source)) as [|effort count];
   [destruct remaining; discriminate|].
   destruct (ModelRequest.Plans.allowed policy effort && (0 <? count)%N) eqn:Allowed;
   [|destruct remaining; discriminate].
   destruct remaining; inversion Selected; subst model.
   exists effort; split; [now apply andb_true_iff in Allowed as [Allowed _]|reflexivity].
Qed.

Theorem every_frozen_model_is_supported_by_its_frozen_profile : forall owner (choice : ModelRequest.frozen owner),
 supported_by_profile (ModelRequest.model choice) (task_current_profile (ModelRequest.base choice)).
Proof.
 intros owner [model snapshot [source [remaining [Selected Prepared]]]]. cbn in *; subst snapshot.
 rewrite prepared_preserves_the_requested_profile.
 eapply canonical_selection_is_supported; exact Selected.
Qed.

Theorem captured_history_cannot_reselect_the_model : forall history request,
 supported_by_profile (ModelRequest.model (ModelRequest.selection request))
   (task_current_profile (ModelRequest.context_task (ModelRequest.with_history history request))).
Proof.
 intros history [owner choice ticket callable mode original scope reserve].
 change (supported_by_profile (ModelRequest.model choice) (task_current_profile (ModelRequest.base choice))).
 apply every_frozen_model_is_supported_by_its_frozen_profile.
Qed.

Definition execution_identity (source : task) :=
 (task_contract source,task_current_profile source,task_current_settings source,
  task_lineage source,task_side_parent source,task_side_cursor source).
Lemma generation_preserves_execution_identity : forall owner model remaining source,
 execution_identity (ModelRequest.Plans.generation owner model remaining source) = execution_identity source.
Proof.
 intros owner model remaining source. unfold ModelRequest.Plans.generation.
 repeat match goal with |- context [if ?condition then _ else _] => destruct condition end;
 destruct source; reflexivity.
Qed.
Lemma choosing_preserves_execution_identity : forall owner source choice,
 ModelRequest.choose owner source = Some choice ->
 execution_identity (ModelRequest.base choice) = execution_identity source.
Proof.
 intros owner source choice Found. unfold ModelRequest.choose in Found.
 assert (General : forall planned (evidence : ModelRequest.Plans.next owner source = planned),
 (match planned as selected return ModelRequest.Plans.next owner source = selected -> option (ModelRequest.frozen owner) with
 | ModelRequest.Plans.Fixed model => fun evidence => Some (ModelRequest.freeze owner source model None evidence)
 | ModelRequest.Plans.Reuse model remaining => fun evidence => Some (ModelRequest.freeze owner source model (Some remaining) evidence)
 | ModelRequest.Plans.Evaluate => fun _ => None end evidence) = Some choice ->
 execution_identity (ModelRequest.base choice) = execution_identity source).
 { intros [model|model remaining|] evidence Equal; inversion Equal; subst; cbn.
   - reflexivity.
   - apply generation_preserves_execution_identity. }
 eapply General; exact Found.
Qed.
Lemma pending_preserves_execution_identity : forall request,
 execution_identity (ModelRequest.pending_task request) =
 execution_identity (ModelRequest.base (ModelRequest.selection request)).
Proof.
 intros [owner [model [contract profile settings lifecycle original queued lineage parent cursor consumed] Selected]
   ticket callable mode history scope reserve]. destruct lifecycle; reflexivity.
Qed.

Lemma a_chosen_model_is_bound_to_the_actual_source : forall owner source choice,
 ModelRequest.choose owner source = Some choice ->
 exists model remaining,
 ModelRequest.Plans.next owner source = ModelRequest.chosen_plan model remaining /\
 ModelRequest.model choice = model /\
 ModelRequest.base choice = ModelRequest.prepared owner source model remaining.
Proof.
 intros owner source choice Found. unfold ModelRequest.choose in Found.
 assert (General : forall planned (evidence : ModelRequest.Plans.next owner source = planned),
 (match planned as selected return ModelRequest.Plans.next owner source = selected -> option (ModelRequest.frozen owner) with
 | ModelRequest.Plans.Fixed model => fun evidence => Some (ModelRequest.freeze owner source model None evidence)
 | ModelRequest.Plans.Reuse model remaining => fun evidence => Some (ModelRequest.freeze owner source model (Some remaining) evidence)
 | ModelRequest.Plans.Evaluate => fun _ => None end evidence) = Some choice ->
 exists model remaining,
 ModelRequest.Plans.next owner source = ModelRequest.chosen_plan model remaining /\
 ModelRequest.model choice = model /\
 ModelRequest.base choice = ModelRequest.prepared owner source model remaining).
 { intros [model|model remaining|] evidence Equal; inversion Equal; subst.
   - exists model,None; repeat split; try reflexivity; exact evidence.
   - exists model,(Some remaining); repeat split; try reflexivity; exact evidence. }
 eapply General; exact Found.
Qed.
