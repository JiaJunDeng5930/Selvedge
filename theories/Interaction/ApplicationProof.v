From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema.
From Selvedge.Interaction Require Import Codec Identity Resource Services Forms Speech ApplicationState ApplicationOps Input ApplicationCore.
Import ListNotations.
Open Scope string_scope.

Lemma ensure_preserves_services : forall e world s d s',
  ensure e world s=Some(d,s') -> ApplicationState.service_state s'=ApplicationState.service_state s.
Proof.
 intros e world s d s' H. unfold ensure in H.
 destruct(find_draft e s)as [existing|]eqn:Found.
 - unfold bind in H. destruct(prepare_existing existing world s)eqn:Prepared;try discriminate.
   inversion H;reflexivity.
 - unfold bind in H. destruct(initialize_for e world s)eqn:Initialized;try discriminate.
   inversion H;subst;reflexivity.
Qed.

(** These conclusions bind the operation the public interaction entry executes,
    including the effects that the browser will interpret. *)
Theorem disconnected_submit_emits_no_command : forall now e world s,
 connected(ApplicationState.service_state s)=false -> emitted(submit now e world s)=[].
Proof.
 intros now e world s Disconnected. unfold submit.
 destruct(ensure e world s)as [[d s']|]eqn:Ensured;simpl;auto.
 destruct(editor_pending e s');simpl;auto.
 pose proof(ensure_preserves_services _ _ _ _ _ Ensured)as Same.
 unfold obstruction,service_obstruction. rewrite Same,Disconnected. reflexivity.
Qed.
Theorem disconnected_public_submission_emits_no_effect : forall now e world s result,
 connected(ApplicationState.service_state s)=false ->
 local_step now(Input.Submit e)world s=Some result -> emitted result=[].
Proof.
 intros now e world s result Disconnected Entered. simpl in Entered.
 destruct(layers(navigation_state s))as[|panel rest].
 - inversion Entered;subst;now apply disconnected_submit_emits_no_command.
 - destruct panel as [owner trigger|kind subject trigger|command caption destination trigger].
   + inversion Entered;subst;now apply disconnected_submit_emits_no_command.
   + destruct(String.eqb kind "property_source");inversion Entered;subst;simpl;auto.
     now apply disconnected_submit_emits_no_command.
   + inversion Entered;subst;now apply disconnected_submit_emits_no_command.
Qed.
Theorem accepted_command_is_exactly_queued : forall command purpose s,
 let ticket:=next(authoring_state s)in
 emitted(queue_command command purpose s)=[Execute ticket command].
Proof. reflexivity. Qed.
Theorem edited_draft_survives_older_completion : forall snapshot outcome s current,
 find_draft(owner snapshot)s=Some current -> revision current<>revision snapshot -> settle_draft snapshot outcome s=s.
Proof.
 intros snapshot outcome s current Found Changed. unfold settle_draft. rewrite Found.
 destruct(N.eqb(revision current)(revision snapshot))eqn:Same;auto.
 apply N.eqb_eq in Same;congruence.
Qed.
Theorem unrelated_authentication_completion_is_ignored : forall s ticket current result,
 Services.connection s=Loading current tt -> current<>ticket ->
 Services.service_state(auth_result ticket result s)=s /\ service_effects(auth_result ticket result s)=[].
Proof.
 intros s ticket current result Found Other. unfold auth_result;rewrite Found.
 destruct(N.eqb ticket current)eqn:Same;simpl;auto.
 apply N.eqb_eq in Same;congruence.
Qed.
Theorem cancelled_dictation_rejects_late_transcript : forall s ticket text,
 current s=Idle -> Speech.speech_state(speech_step(Transcribed ticket text)s)=s /\ transcript(speech_step(Transcribed ticket text)s)=None.
Proof. intros. unfold speech_step. rewrite H;auto. Qed.

Theorem invalid_workspace_observation_emits_no_effect : forall world ticket observation s,
 admit_directories observation=None -> emitted(directories_completed world ticket(inr observation)s)=[].
Proof.
 intros world ticket observation s Invalid. unfold directories_completed.
 destruct(find(fun p=>N.eqb ticket(preparation_ticket p))(preparations(service_state s)))as[pending|];simpl;auto.
 set (clean:=with_services(forget_preparation ticket(service_state s))s).
 destruct(find_draft(owner(preparation_draft pending))clean)as[current|];simpl;auto.
 destruct(N.eqb(revision current)(revision(preparation_draft pending)));simpl;auto.
 destruct(editor_pending(owner(preparation_draft pending))clean);simpl;auto.
 destruct(obstruction world(forget_preparation ticket(service_state s))(preparation_draft pending));simpl;auto.
 rewrite Invalid. reflexivity.
Qed.

Theorem old_configuration_receipt_preserves_navigation : forall snapshot captured accepted outcome world s,
 captured<>generation(navigation_state s) ->
 navigation_state(resulting_state(complete_purpose(ConfigurationSubmission snapshot captured)accepted outcome world s))=
 navigation_state s.
Proof.
 intros snapshot captured accepted outcome world s Changed.
 assert (Old:N.eqb captured(generation(navigation_state s))=false)by(now apply N.eqb_neq).
 cbn [complete_purpose]. rewrite Old, Bool.andb_false_r. simpl.
 destruct(find_draft(owner snapshot)s);simpl.
 all: destruct(completion_success outcome);simpl;auto.
 all: unfold remember_accepted_model.
 all: destruct(string_field "profile"(encode_command accepted))as[profile|];destruct(string_field "reasoning"(encode_command accepted))as[effort|];simpl;auto.
 all: unfold remember_model;destruct(ModelSelection.valid_preference world(profile,effort));reflexivity.
Qed.
