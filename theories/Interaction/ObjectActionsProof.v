From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Interaction Require Import Codec Identity Resource Services ObjectActions.
From Selvedge.Interaction Require CommandAssessment.
From Selvedge.Interaction.Session Require State.
Open Scope string_scope.

(** A native operation becomes available only from an admission of that exact
    command at the current observation sequence and actual layer occurrence. *)
Theorem available_native_has_current_admission snapshot state subject value accepted :
 command value = Some accepted -> availability snapshot state subject value = Available ->
 Services.connected(State.service_state state)=true /\
 exists sequence ticket request observation,
  natural_field "sequence" snapshot=Some sequence /\
  assessment_for subject value state=Some(Loaded ticket request observation) /\
  CommandAssessment.matches(action_owner subject value)(assessment_revision state)sequence accepted request=true /\
  CommandAssessment.current_owned(action_owner subject value)(assessment_revision state)sequence observation=true /\
  CommandAssessment.observed_admission observation=CommandAssessment.Admitted.
Proof.
 intros Command AvailableNow. unfold availability in AvailableNow. rewrite Command in AvailableNow.
 destruct(Services.connected(State.service_state state))eqn:Connected;[|discriminate].
 destruct(natural_field "sequence" snapshot)as[sequence|]eqn:Sequence;[|discriminate].
 destruct(assessment_for subject value state)as[resource|]eqn:Resource;[|discriminate].
 destruct resource as[|ticket request|ticket request observation|ticket request reason];try discriminate.
 - destruct(CommandAssessment.matches(action_owner subject value)(assessment_revision state)sequence accepted request &&
     CommandAssessment.current_owned(action_owner subject value)(assessment_revision state)sequence observation)eqn:Current;[|discriminate].
   destruct(CommandAssessment.observed_admission observation)eqn:Admission;[|discriminate].
   apply andb_true_iff in Current. destruct Current as[RequestCurrent ObservationCurrent].
   split;[reflexivity|]. exists sequence,ticket,request,observation. repeat split;try reflexivity;assumption.
 - destruct(CommandAssessment.matches(action_owner subject value)(assessment_revision state)sequence accepted request);discriminate.
Qed.
