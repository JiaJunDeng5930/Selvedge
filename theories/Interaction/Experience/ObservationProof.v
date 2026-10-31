From Stdlib Require Import String Ascii List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Programming Require Import Schema.
From Selvedge.Kernel Require Workspace.
From Selvedge.Interaction Require Import Codec Resource Services CommandAssessment Identity.
From Selvedge.Interaction.Session Require Draft State.
From Selvedge.Interaction.Submission Require Parameters Values.
From Selvedge.Interaction.Experience Require Import Model Activity Observation.
Import ListNotations.
Open Scope string_scope.

Lemma directory_segment_separator prefix suffix previous segment:
 Model.directory_basename_from(prefix++"/"++suffix)previous segment=
 Model.directory_basename_from suffix(Model.directory_basename_from prefix previous segment)"".
Proof.
 revert previous segment. induction prefix as[|character rest IH];intros previous segment.
 - reflexivity.
 - cbn [String.append Model.directory_basename_from].
   destruct(Ascii.eqb character "/"%char);apply IH.
Qed.

Local Lemma directory_text_append_assoc first second third:
 (first++second)++third=first++(second++third).
Proof. induction first;simpl;congruence. Qed.

Lemma directory_named_segment suffix previous segment:
 List.Forall(fun character=>Ascii.eqb character "/"%char=false)(String.list_ascii_of_string suffix) ->
 suffix<>"" ->
 Model.directory_basename_from suffix previous segment=segment++suffix.
Proof.
 revert previous segment. induction suffix as[|character rest IH];intros previous segment Free Nonempty.
 - contradiction.
 - inversion Free as[|? ? NotSlash Rest];subst.
   cbn [Model.directory_basename_from]. rewrite NotSlash.
   destruct rest as[|next tail].
   + cbn [Model.directory_basename_from].
     destruct segment;simpl;reflexivity.
   + rewrite IH;[rewrite directory_text_append_assoc;reflexivity|exact Rest|discriminate].
Qed.

Theorem workspace_caption_uses_the_final_named_segment paths inherited prefix suffix:
 List.Forall(fun character=>Ascii.eqb character "/"%char=false)(String.list_ascii_of_string suffix) ->
 suffix<>"" ->
 Model.readable_text(Model.WorkspaceValue paths(Some(prefix++"/"++suffix))inherited)=suffix.
Proof.
 intros Free Nonempty.
 change(Model.directory_basename_from(prefix++"/"++suffix)(prefix++"/"++suffix)""=suffix).
 rewrite directory_segment_separator,directory_named_segment;[reflexivity|exact Free|exact Nonempty].
Qed.

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
 destruct(reviewer_assignment_reason snapshot(Draft.contents(State.current_draft state e))assignment);try discriminate.
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
 destruct(reviewer_assignment_reason snapshot(Draft.contents(State.current_draft state e))assignment);try discriminate.
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

(** The complete draft assessment retains every independently observed cause;
    presentation may choose attention without deleting the other causes. *)
Theorem blocked_draft_preserves_all_requirements snapshot state e first rest:
 draft_requirements snapshot state e=first::rest ->
 exists restrictions,assessment_obstructions(assessment_outcome(observe_assessment snapshot state e))=
  ((first::rest)++restrictions)%list.
Proof.
 intros Requirements. unfold observe_assessment,preliminary_assessment. rewrite Requirements.
 destruct(negb(Services.connected(State.service_state state)));cbn[assessment_outcome];
 try(eexists;reflexivity).
 destruct(Services.blocks e(State.service_state state));cbn[assessment_outcome];try(eexists;reflexivity).
 destruct(negb(Session.Observation.worktree_submission_allowed snapshot state(State.current_draft state e)));cbn[assessment_outcome];
 try(eexists;reflexivity).
 exists[]. rewrite app_nil_r. reflexivity.
Qed.

Theorem attention_is_an_actual_nonpassive_cause e(outcome:assessment_result e)cause:
 attention_obstruction outcome=Some cause ->
 In cause(assessment_obstructions outcome) /\
 obstruction_code cause<>"empty_message" /\ obstruction_code cause<>"pending".
Proof.
 unfold attention_obstruction,passive_obstruction. intros Found.
 apply find_some in Found as[Member Active]. split;[exact Member|].
 apply Bool.negb_true_iff in Active. apply Bool.orb_false_iff in Active as[Empty Pending].
 apply String.eqb_neq in Empty. apply String.eqb_neq in Pending. auto.
Qed.

Theorem observed_property_retains_complete_help snapshot state e kind value:
 observe_property snapshot state e kind=Some value ->
 property_help value=property_help_text snapshot state value.
Proof.
 unfold observe_property. destruct(Model.admit_subject e(Parameters.name(property_field kind)))as[subject|];cbn;try discriminate.
 intros Same. inversion Same. subst. unfold property_help_text,property_source_description.
 reflexivity.
Qed.

Theorem unavailable_model_retains_saved_profile_and_effort snapshot e(subject:subject e)key effort:
 profile_for_subject snapshot subject key=None ->
 recognition_information snapshot subject(Fields.ModelValue key effort)=
 PresentInformation(SummaryValue subject(Model.TextValue("Missing model "++key)))
   (related_summary(e:=e)Fields.ReasoningEffort(Model.TextValue effort)).
Proof. intros Missing. unfold recognition_information. rewrite Missing. reflexivity. Qed.

Theorem a_field_diagnostic_is_not_masked_by_an_unrelated_first_cause
 e(subject:subject e)(first:obstruction e)rest:
 obstruction_matches_subject subject first=false ->
 field_obstruction subject(PreparationBlocked first rest)=
 option_map obstruction_message(find(fun cause=>negb(passive_obstruction cause)&&
   obstruction_matches_subject subject cause)rest).
Proof.
 intros Unrelated. unfold field_obstruction,assessment_obstructions.
 cbn [find]. rewrite Unrelated,Bool.andb_false_r. reflexivity.
Qed.

Theorem message_text_belongs_to_the_message_draft task (subject:Model.subject(Identity.Message task)):
 Model.subject_declaration subject=Fields.MessageText ->
 Model.subject_object subject=Model.MessageDraftObject task.
Proof. intro Field. unfold Model.subject_object. rewrite Field. reflexivity. Qed.

Theorem message_delivery_belongs_to_the_message_draft task (subject:Model.subject(Identity.Message task)):
 Model.subject_declaration subject=Fields.DeliveryIntent ->
 Model.subject_object subject=Model.MessageDraftObject task.
Proof. intro Field. unfold Model.subject_object. rewrite Field. reflexivity. Qed.

Theorem choosing_primary_preserves_admitted_workspace workspace primary :
 Selvedge.Kernel.Workspace.valid_workspace workspace=true ->
 Selvedge.Kernel.Workspace.valid_workspace(Values.choose_primary workspace primary)=true.
Proof.
 intros Valid. unfold Values.choose_primary.
 destruct primary as[path|];[|exact Valid].
 destruct(existsb(String.eqb path)(Selvedge.Kernel.Domain.workspace_roots workspace))eqn:Member;[|exact Valid].
 unfold Selvedge.Kernel.Workspace.valid_workspace in *.
 apply Bool.andb_true_iff in Valid as[Roots Previous].
 apply Bool.andb_true_iff. split;[exact Roots|].
 unfold Selvedge.Kernel.Workspace.valid_selection in *.
 apply Bool.andb_true_iff in Previous as[Unique _].
 apply Bool.andb_true_iff. split;[exact Unique|exact Member].
Qed.

Theorem existing_graph_draft_keeps_owner graph declaration parsed left_work right_work revision feedback entry selection :
 Draft.owner(Draft.Draft revision(Draft.TaskGraphBody(Some graph)declaration parsed left_work)feedback entry selection)=
 Draft.owner(Draft.Draft revision(Draft.TaskGraphBody(Some graph)declaration parsed right_work)feedback entry selection).
Proof. reflexivity. Qed.
