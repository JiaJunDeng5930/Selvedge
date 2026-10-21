From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Interaction Require Import Codec Identity Resource Services ApplicationState Navigation ObjectActions.
From Selvedge.Interaction Require CommandAssessment.
Import ListNotations.

Theorem available_native_action_has_current_admission_observation
  subject occurrence world s key caption command purpose :
 item_availability subject occurrence world s(MenuItem key caption(NativeCommand command purpose))=Available ->
 exists ticket request observation sequence,
  natural_field "sequence" world=Some sequence /\
  assessment_for subject(MenuItem key caption(NativeCommand command purpose))s=Some(Loaded ticket request observation) /\
  CommandAssessment.matches(CommandAssessment.MenuOwner subject key)occurrence sequence command request=true /\
  CommandAssessment.observed_owner observation=CommandAssessment.MenuOwner subject key /\
  CommandAssessment.observed_revision observation=occurrence /\
  CommandAssessment.observed_sequence observation=sequence /\
  CommandAssessment.observed_admission observation=CommandAssessment.Admitted.
Proof.
 unfold item_availability. destruct(Services.connected(service_state s));simpl;try discriminate.
 destruct(natural_field "sequence" world)as [sequence|]eqn:World;try discriminate.
 destruct(assessment_for subject(MenuItem key caption(NativeCommand command purpose))s)
   as [resource|]eqn:Resource;try discriminate.
 destruct resource as [|ticket request|ticket request observation|ticket request reason];try discriminate.
 2: { destruct(CommandAssessment.matches(item_owner subject(MenuItem key caption(NativeCommand command purpose)))occurrence sequence command request);discriminate. }
 destruct(CommandAssessment.matches(item_owner subject(MenuItem key caption(NativeCommand command purpose)))occurrence sequence command request&&
   CommandAssessment.current_owned(item_owner subject(MenuItem key caption(NativeCommand command purpose)))occurrence sequence observation)eqn:Current;try discriminate.
 apply Bool.andb_true_iff in Current as [Request Current].
 destruct(CommandAssessment.observed_admission observation)eqn:Admission;try discriminate.
 intros _. apply CommandAssessment.current_observation_retains_action_and_world in Current.
 destruct Current as [Owner [Revision Sequence]].
 exists ticket,request,observation,sequence. simpl in *. repeat split;auto.
Qed.

Theorem same_task_retains_both_actual_presentations s task :
 location(navigation_state s)=Conversation task ->
 side_task(navigation_state s)=Some task ->
 visible_task_views s=[PrimaryTask task;SideTask task].
Proof. intros Main Side. unfold visible_task_views. rewrite Main,Side. reflexivity. Qed.

Theorem current_acceptance_enables_native_action
  subject occurrence world s key caption command purpose ticket request observation sequence :
 Services.connected(service_state s)=true ->
 natural_field "sequence" world=Some sequence ->
 assessment_for subject(MenuItem key caption(NativeCommand command purpose))s=Some(Loaded ticket request observation) ->
 CommandAssessment.matches(CommandAssessment.MenuOwner subject key)occurrence sequence command request=true ->
 CommandAssessment.current_owned(CommandAssessment.MenuOwner subject key)occurrence sequence observation=true ->
 CommandAssessment.observed_admission observation=CommandAssessment.Admitted ->
 item_availability subject occurrence world s(MenuItem key caption(NativeCommand command purpose))=Available.
Proof.
 intros Connected World Resource Request Current Admission.
 unfold item_availability. rewrite Connected,World,Resource. simpl.
 unfold item_owner. simpl. rewrite Request,Current. simpl. rewrite Admission. reflexivity.
Qed.
