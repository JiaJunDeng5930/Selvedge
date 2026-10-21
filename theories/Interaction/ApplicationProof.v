From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema.
From Selvedge.Interaction Require Import Codec Identity Resource Services Forms Speech Experience ExperienceAssessment ApplicationState ApplicationOps Input ApplicationCore.
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

Lemma retained_panels_have_live_menu_owners : forall world pending panel,
 ObjectActions.panel_retained world pending panel=true -> ObjectActions.menu_owner_live world panel=true.
Proof. intros world pending panel;destruct panel;simpl;auto. Qed.

Theorem refreshed_menu_owners_exist : forall world result,
 forallb(ObjectActions.menu_owner_live world)
   (layers(navigation_state(resulting_state(refresh_menu_ownership world result))))=true.
Proof.
 intros world result. unfold refresh_menu_ownership.
 destruct(forallb(ObjectActions.panel_retained world(confirmation_pending(resulting_state result)))
   (layers(navigation_state(resulting_state result))))eqn:Live.
 - pose proof(proj1(@forallb_forall ApplicationState.panel
     (ObjectActions.panel_retained world(confirmation_pending(resulting_state result)))
     (layers(navigation_state(resulting_state result))))Live)as AllLive.
   apply forallb_forall. intros panel Present.
   apply retained_panels_have_live_menu_owners with(pending:=confirmation_pending(resulting_state result)).
   now apply AllLive.
 - cbn [resulting_state with_navigation]. apply forallb_forall.
   intros panel Present. apply filter_In in Present as [_ Present].
   now apply retained_panels_have_live_menu_owners in Present.
Qed.

Theorem removed_project_closes_its_menu_and_focuses_main : forall world result project trigger,
 find_project project world=None ->
 layers(navigation_state(resulting_state result))=[ObjectActionsPanel(ProjectActions project)trigger] ->
 layers(navigation_state(resulting_state(refresh_menu_ownership world result)))=[] /\
 emitted(refresh_menu_ownership world result)=List.app(emitted result)[Focus "main"].
Proof.
 intros world result project trigger Missing Opened. unfold refresh_menu_ownership.
 assert (Dead:ObjectActions.panel_retained world(confirmation_pending(resulting_state result))
   (ObjectActionsPanel(ProjectActions project)trigger)=false).
 { unfold ObjectActions.panel_retained,ObjectActions.panel_live,ObjectActions.subject_live,ObjectActions.subject_value. now rewrite Missing. }
 rewrite Opened. cbn -[ObjectActions.panel_retained]. rewrite Dead. split;reflexivity.
Qed.

Theorem submitted_confirmation_waits_for_its_completion : forall world result command caption destination trigger feedback,
 confirmation_pending(resulting_state result)=true ->
 layers(navigation_state(resulting_state result))=[ApplicationState.Confirmation command caption destination trigger feedback] ->
 refresh_menu_ownership world result=result.
Proof.
 intros world result command caption destination trigger feedback Pending Opened.
 unfold refresh_menu_ownership. rewrite Pending,Opened. reflexivity.
Qed.

Lemma fold_left_preserves_observation : forall (A B C:Type)(operation:A->B->A)(observe:A->C),
 (forall value input,observe(operation value input)=observe value) ->
 forall inputs value,observe(fold_left operation inputs value)=observe value.
Proof.
 intros A B C operation observe Preserved inputs;induction inputs;intros value;simpl;auto.
 rewrite IHinputs;apply Preserved.
Qed.

Lemma draft_assessment_preserves_navigation : forall now world e result,
 navigation_state(resulting_state(refresh_editor_assessment now world e result))=
 navigation_state(resulting_state result).
Proof.
 intros now world e result. unfold refresh_editor_assessment.
 destruct(find_draft e(resulting_state result))as[d|];auto.
 destruct(draft_requirements d world(service_state(resulting_state result))(editor_pending e(resulting_state result)));auto.
 destruct(preparation_workspace d);auto. destruct(natural_field "sequence" world);auto.
 destruct(decode_command Selvedge.Kernel.Commands.command_specs
   (match e with Card _=>replace "observed_at"(JString(Numbers.show_natural now))(command d)|_=>command d end));reflexivity.
Qed.

Theorem preflight_retains_only_live_menu_owners : forall now world result,
 forallb(ObjectActions.menu_owner_live world)
   (layers(navigation_state(resulting_state(refresh_preflight now world result))))=true.
Proof.
 intros now world result. unfold refresh_preflight.
 set (owned:=refresh_menu_ownership world result).
 set (clean:=fold_left(fun s draft=>match owner draft with
   |Execution task=>if existsb(fun panel=>match panel with ActivityPanel e _ _ _ _=>same_editor e(Execution task)|_=>false end)
       (layers(navigation_state s))then s else discard_editor(Execution task)s
   |_=>s end)(drafts(authoring_state(resulting_state owned)))(resulting_state owned)).
 assert (NavigationClean:navigation_state clean=navigation_state(resulting_state owned)).
 { unfold clean. apply fold_left_preserves_observation.
   intros s d. destruct(owner d);try reflexivity.
   destruct(existsb _ _);reflexivity. }
 change (forallb(ObjectActions.menu_owner_live world)
   (layers(navigation_state(resulting_state(fold_left
     (fun current e=>refresh_editor_assessment now world e current)
     (visible_editors clean)(Result clean(emitted owned)(reply owned))))))=true).
 rewrite (fold_left_preserves_observation ApplicationOps.result editor navigation
   (fun current e=>refresh_editor_assessment now world e current)
   (fun current=>navigation_state(resulting_state current))).
 - cbn [resulting_state]. rewrite NavigationClean. apply refreshed_menu_owners_exist.
 - intros current e;apply draft_assessment_preserves_navigation.
Qed.

(** These conclusions bind the operation the public interaction entry executes,
    including the effects that the browser will interpret. *)
Theorem disconnected_submit_emits_no_command : forall now e trigger world s,
 connected(ApplicationState.service_state s)=false -> emitted(submit now e trigger world s)=[].
Proof.
 intros now e trigger world s Disconnected. unfold submit.
 destruct(negb(editor_can_submit e));simpl;auto.
 destruct(ensure e world s)as [[d s']|]eqn:Ensured;simpl;auto.
 pose proof(ensure_preserves_services _ _ _ _ _ Ensured)as Same.
 unfold assess_draft,action_requirements,draft_requirements,service_requirements,require_editor.
 rewrite Same,Disconnected. reflexivity.
Qed.
Theorem disconnected_public_submission_emits_no_effect : forall now e trigger world s result,
 connected(ApplicationState.service_state s)=false ->
 local_step now(Input.Submit e trigger)world s=Some result -> emitted result=[].
Proof.
 intros now e trigger world s result Disconnected Entered. simpl in Entered.
 destruct(source_view_active s);inversion Entered;subst;simpl;auto.
 now apply disconnected_submit_emits_no_command.
Qed.
Theorem directory_ready_submission_requests_its_observation : forall now e trigger world s d prepared workspace,
 editor_can_submit e=true -> ensure e world s=Some(d,prepared) ->
 action_requirements d world(ApplicationState.service_state prepared)(editor_pending e prepared)=[] ->
 ExperienceAssessment.preparation_workspace d=Some workspace ->
 emitted(submit now e trigger world s)=
 [Service(ObserveDirectories(next_ticket(ApplicationState.service_state prepared))workspace(owner d))].
Proof.
 intros now e trigger world s d prepared workspace Submittable Ensured Ready Workspace.
 unfold submit. rewrite Submittable,Ensured.
 unfold assess_draft. rewrite Ready,Workspace. reflexivity.
Qed.
Theorem ended_connection_fails_owned_inflight_upload : forall s reason ticket request,
 In(Resource.Loading ticket request)(uploads s) ->
 In(Resource.Failed ticket request reason)(uploads(Services.service_state(end_connection reason s))).
Proof.
 intros s reason ticket request Owned. unfold end_connection;cbn.
 change (In ((fun r:Resource.resource upload_request attachment=>match r with
   |Resource.Loading ticket request=>Resource.Failed ticket request reason|_=>r end)(Resource.Loading ticket request))
   (map(fun r:Resource.resource upload_request attachment=>match r with
   |Resource.Loading ticket request=>Resource.Failed ticket request reason|_=>r end)(uploads s))).
 now apply in_map.
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
