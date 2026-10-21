From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema.
From Selvedge.Interaction Require Import Codec Resource Services CommandAssessment Identity.
From Selvedge.Interaction.Session Require Draft State.
From Selvedge.Interaction.Submission Require Parameters Values.
From Selvedge.Interaction.Experience Require Import Model Activity Observation.
Import ListNotations.
Open Scope string_scope.

(** A live candidate can be available only with the assessment issued for this
    action and current world.  Command comparison deliberately ignores the
    observed_at transport field, as in the canonical assessment contract. *)
Theorem available_admission_has_current_authority snapshot state owner revision command:
 admission snapshot state owner revision command=Available ->
 exists sequence ticket request observation,
  natural_field "sequence" snapshot=Some sequence /\
  find(Services.owned_assessment owner)(Services.command_assessments(State.service_state state))=
    Some(Loaded ticket request observation) /\
  CommandAssessment.matches owner revision sequence command request=true /\
  CommandAssessment.observed_owner observation=owner /\
  CommandAssessment.observed_revision observation=revision /\
  CommandAssessment.observed_sequence observation=sequence /\
  CommandAssessment.observed_admission observation=CommandAssessment.Admitted.
Proof.
 unfold admission.
 destruct(natural_field "sequence" snapshot)as[sequence|]eqn:Sequence;try discriminate.
 destruct(find(Services.owned_assessment owner)(Services.command_assessments(State.service_state state)))
  as[resource|]eqn:Found;try discriminate.
 destruct resource as[|ticket request|ticket request observation|ticket request reason];try discriminate.
 - destruct(CommandAssessment.matches owner revision sequence command request &&
    CommandAssessment.current_owned owner revision sequence observation)eqn:Current;try discriminate.
   destruct(CommandAssessment.observed_admission observation)eqn:Admitted;try discriminate.
   intros _. apply Bool.andb_true_iff in Current as[Matches Owned].
   apply CommandAssessment.current_observation_retains_action_and_world in Owned.
   destruct Owned as[Owner[Revision World]]. exists sequence,ticket,request,observation.
   repeat split;assumption.
 - destruct(CommandAssessment.matches owner revision sequence command request);discriminate.
Qed.

Theorem available_assignment_is_editable snapshot state e(assignment:assignment e):
 assignment_available snapshot state assignment=Available ->
 Parameters.editable e(subject_declaration(assignment_subject assignment))=true.
Proof.
 unfold assignment_available.
 destruct(assignment_shape_available snapshot state assignment)eqn:Shape;try discriminate.
 unfold assignment_shape_available in Shape. apply Bool.andb_true_iff in Shape.
 exact(fun _=>proj1 Shape).
Qed.

Theorem available_live_assignment_has_current_authority snapshot state e(assignment:assignment e):
 Parameters.live_configuration e(subject_declaration(assignment_subject assignment))=true ->
 assignment_available snapshot state assignment=Available ->
 exists command,
  Values.candidate_command snapshot(State.now state)(State.current_draft state e)assignment=Some command /\
  admission snapshot state(candidate_owner(assignment_subject assignment)
    (Schema.encode_value(subject_kind(assignment_subject assignment))(assignment_value assignment)))
    (Draft.revision(State.current_draft state e))command=Available.
Proof.
 intros Live. unfold assignment_available.
 destruct(assignment_shape_available snapshot state assignment);try discriminate.
 rewrite Live. destruct(Values.candidate_command snapshot(State.now state)(State.current_draft state e)assignment)
  as[command|]eqn:Command;try discriminate.
 intros Accepted. exists command. split;[reflexivity|exact Accepted].
Qed.

Theorem nonretained_focus_cannot_open_dependency e(activity:activity e)(subject:subject e)inspection:
 retained_subject activity subject=false ->
 view_for activity(Some subject)inspection=
 match activity with EditingActivity _ _ _=>CompoundView
 |_=>if inspection then InspectionView None else PrincipalView end.
Proof.
 intro Retained. destruct activity;unfold view_for;rewrite ?Retained;reflexivity.
Qed.

(** Committed approvals carry the captured reviewer, independent of later
    configured-catalog changes.  The execution entry reads this decoder. *)
Theorem frozen_approval_observation_ignores_catalog first second value:
 Session.Observation.parse_observed_approval first value=
 Session.Observation.parse_observed_approval second value.
Proof. reflexivity. Qed.
