From Stdlib Require Import String List Bool NArith.
From Selvedge.Kernel Require Import Domain ModelRequest.
Import ListNotations.

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
 (match planned as selected return ModelRequest.Plans.next owner source = selected -> option (ModelRequest.frozen owner source) with
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
 (match planned as selected return ModelRequest.Plans.next owner source = selected -> option (ModelRequest.frozen owner source) with
 | ModelRequest.Plans.Fixed model => fun evidence => Some (ModelRequest.freeze owner source model None evidence)
 | ModelRequest.Plans.Reuse model remaining => fun evidence => Some (ModelRequest.freeze owner source model (Some remaining) evidence)
 | ModelRequest.Plans.Evaluate => fun _ => None end evidence) = None).
 { intros [model|model remaining|] evidence Equal; try discriminate; reflexivity. }
 apply General; exact Selected.
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

(** Source indexing makes the selected model's authority a property of every
    frozen value, including after final history capture. *)
Theorem every_frozen_model_is_supported_by_its_frozen_profile :
 forall owner source (choice : ModelRequest.frozen owner source),
 supported_by_profile (ModelRequest.model choice) (task_current_profile (ModelRequest.base choice)).
Proof.
 intros owner source [model remaining Selected].
 cbn [ModelRequest.model ModelRequest.base ModelRequest.remaining].
 unfold ModelRequest.prepared; destruct remaining;
 change (supported_by_profile model (task_current_profile source));
 eapply canonical_selection_is_supported; exact Selected.
Qed.

Theorem captured_history_cannot_reselect_the_model : forall history request,
 supported_by_profile (ModelRequest.model (ModelRequest.selection request))
   (task_current_profile (ModelRequest.context_task (ModelRequest.with_history history request))).
Proof.
 intros history [owner source choice ticket callable mode original scope reserve].
 change (supported_by_profile (ModelRequest.model choice) (task_current_profile (ModelRequest.base choice))).
 apply every_frozen_model_is_supported_by_its_frozen_profile.
Qed.
