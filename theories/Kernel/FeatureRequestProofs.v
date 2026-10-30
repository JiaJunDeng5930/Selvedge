From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json Registry RegistryProofs OptionListProofs.
From Selvedge.Kernel Require Import Domain State TicketedRequest TaskScopeProofs.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.
Module S := TicketedRequest.Scoped.
Module F := Selvedge.Features.Domain.
Module C := Selvedge.Features.CompactionTypes.

Definition title_receiver owner ticket selected prompt value :=
 find (fun item => N.eqb owner (F.title_task item)) (F.feature_titles (world_features value)) =
 Some (F.TitleEntry owner (F.TitlePending (RequestEnvelope.Envelope ticket (selected, prompt)))).
Definition card_receiver owner ticket revision retitle value :=
 exists card, registry_at owner (F.board_cards (F.feature_board (world_features value))) = Some (Some card) /\
 F.card_enrichment card = F.Enriching (RequestEnvelope.Envelope ticket (revision, retitle)).
Definition connection_receiver identity job value :=
 find (fun item => N.eqb identity (fst item)) (F.sharing_jobs (F.feature_sharing (world_features value))) = Some (identity,job) /\
 F.job_state job = F.JobRunning.
Definition maintenance_receiver owner ticket value :=
 exists entry, find (fun item => N.eqb (fst item) owner)
   (C.maintenance_entries (F.feature_compaction (world_features value))) = Some (owner,entry) /\
 (match C.entry_measurement entry with C.Measuring expected _ _ => expected=ticket | _ => False end \/
  match C.entry_job entry with
  | C.Preparing expected _ _ _ | C.Compacting expected _ _ _ _ | C.Validating expected _ _ _ _ _ => expected=ticket
  | _ => False end).
Definition receiver_installed (request : effect) value := match request with
 | SuggestTitle owner (RequestEnvelope.Envelope ticket (selected, prompt)) => title_receiver owner ticket selected prompt value
 | SuggestCard owner (RequestEnvelope.Envelope ticket (revision, retitle)) _ _ _ => card_receiver owner ticket revision retitle value
 | RunConnectionJob (RequestEnvelope.Envelope identity job) => connection_receiver identity job value
 | MaintainContext (C.Scope owner ticket _) | MaintainContext (C.Measure owner ticket _ _ _)
 | MaintainContext (C.Compact owner ticket _ _ _ _) => maintenance_receiver owner ticket value
 | _ => False end.

Lemma put_title_installs : forall owner ticket selected prompt value,
 title_receiver owner ticket selected prompt (S.put_title owner (F.TitlePending (RequestEnvelope.Envelope ticket (selected, prompt))) value).
Proof. intros. unfold title_receiver,S.put_title. unfold with_features, Selvedge.Features.State.with_titles, set. cbn. now rewrite N.eqb_refl. Qed.
Lemma put_card_installs : forall owner ticket card retitle value,
 (owner <= N.of_nat (List.length (F.board_cards (F.feature_board (world_features value)))))%N ->
 card_receiver owner ticket (F.card_revision card) retitle
  (S.put_card owner (set F.card_enrichment (fun _ => F.Enriching (RequestEnvelope.Envelope ticket ((F.card_revision card), retitle))) card) value).
Proof.
 intros owner ticket card retitle value Bound. unfold card_receiver,S.put_card; unfold with_features, Selvedge.Features.State.with_board, set. cbn.
 exists (set F.card_enrichment (fun _ => F.Enriching (RequestEnvelope.Envelope ticket ((F.card_revision card), retitle))) card); split; [|reflexivity].
 destruct (N.eqb owner (N.of_nat (List.length (F.board_cards (F.feature_board (world_features value)))))) eqn:Append.
 - apply N.eqb_eq in Append; subst owner. apply registry_lookup_at_appended_index.
 - assert (owner < N.of_nat (List.length (F.board_cards (F.feature_board (world_features value)))))%N as Strict
     by (apply N.eqb_neq in Append; lia).
   destruct (registry_lookup_exists_below_length _ _ _ Strict) as [old Found].
   eapply registry_replace_selected; exact Found.
Qed.
Lemma put_connection_installs : forall identity job value,
 F.job_state job=F.JobRunning -> connection_receiver identity job (S.put_connection identity job value).
Proof. intros. unfold connection_receiver,S.put_connection. unfold with_features, Selvedge.Features.State.with_sharing, set. cbn. rewrite N.eqb_refl. auto. Qed.
Lemma put_maintenance_installs : forall owner ticket source value observation,
 maintenance_receiver owner ticket
  (S.put_compaction owner (set C.entry_observation (fun _ => observation)
    (fst (S.maintenance_build owner ticket source))) value).
Proof.
 intros owner ticket source value observation. unfold maintenance_receiver,S.put_compaction. unfold with_features, Selvedge.Features.State.with_compaction, set. cbn. rewrite N.eqb_refl.
 eexists; split; [reflexivity|].
 destruct source as [input [purpose|] entry|input purpose candidate preview entry|
   input [purpose|] [[candidate preview]|] scope entry|input purpose target progress scope entry];
   cbn; unfold set; cbn; auto.
Qed.

(** The production interpreter has a receiver correspondence guarantee. Its
    conclusion inspects the installed domain receiver, rather than just the
    emitted effect's coordinate or an assumed successful validator result. *)
Theorem every_feature_request_has_its_installed_receiver : forall before (request : S.feature_plan before) emitted,
 In emitted (decision_effects (S.feature_issue request)) ->
 receiver_installed emitted (decision_world (S.feature_issue request)).
Proof.
 intros before [source Valid] emitted Member. unfold S.feature_issue,S.feature_issue_change,CommandResult.accept in *; cbn in *.
 destruct source as [owner selected prompt|owner card selected prompt retitle|job|owner request];
 cbn [S.feature_space allocate_identity next_identity S.feature_build S.feature_observation S.feature_evidence] in *.
 - destruct Member as [<-|[]]. apply put_title_installs.
 - destruct Member as [<-|[]]. apply put_card_installs.
   apply andb_true_iff in Valid as [Bound Scope]. now apply N.leb_le.
 - destruct Member as [<-|[]]. apply put_connection_installs.
   cbn [RequestEnvelope.input].
   cbn [S.feature_valid] in Valid. destruct (F.job_state job); try discriminate; reflexivity.
 - destruct (S.maintenance_build owner (world_next_ticket before) request) as [pending request_effect] eqn:Built.
   cbn in *. destruct Member as [<-|[]].
   pose proof (put_maintenance_installs owner (world_next_ticket before) request
     (with_ticket (N.succ (world_next_ticket before)) before)
     (C.entry_observation (S.maintenance_previous Valid))) as Installed.
   rewrite Built in Installed; cbn in Installed.
   destruct request as [input purpose entry|input purpose candidate preview entry|
     input purpose candidate scope entry|input purpose target progress scope entry];
   cbn [S.maintenance_build] in Built;
   repeat match goal with
   | H : context [match ?x with _ => _ end] |- _ => destruct x eqn:? end;
   inversion Built; subst; exact Installed.
Qed.

Theorem feature_requests_preserve_execution_frame : forall before (request : S.feature_plan before),
 let after:=decision_world (S.feature_issue request) in
 world_tasks after=world_tasks before /\ world_projects after=world_projects before /\
 world_environment after=world_environment before /\ world_sequence after=world_sequence before.
Proof.
 intros before [source Valid]; cbn. unfold S.feature_issue,S.feature_issue_change,CommandResult.accept; cbn.
 destruct source; cbn [S.feature_space allocate_identity next_identity S.feature_build S.feature_observation S.feature_evidence];
 try (repeat split; reflexivity).
 destruct (S.maintenance_build owner (world_next_ticket before) request); repeat split; reflexivity.
Qed.

Lemma admitted_maintenance_has_a_selected_plan : forall before owner request current
 (Found : find_task owner before = Some current),
 S.feature_valid before (S.MaintainRequest owner request) = true ->
 exists reference, S.maintenance_selected owner request before current Found = Some reference.
Proof.
 intros before owner request current Found Ready.
 cbn [S.feature_valid] in Ready; unfold S.maintenance_ready in Ready; rewrite Found in Ready.
 unfold S.maintenance_selected.
 eapply observe_cases; [intros entry Stored|intro Missing].
 - rewrite Stored in Ready; unfold S.maintenance_observed,S.boolean_admission.
   destruct (Bool.bool_dec _ true) as [Eligible|Refused]; [eexists; reflexivity|contradiction].
 - rewrite Missing in Ready; discriminate.
Qed.

Lemma maintenance_issue_retains_the_observed_entry : forall before (plan : S.feature_plan before) owner request,
 S.feature_intent plan = S.MaintainRequest owner request ->
 S.feature_observation plan = match S.compaction_entry owner before with
   | Some entry => C.entry_observation entry | None => None end.
Proof.
 intros before [source Evidence] owner request Same; cbn in Same; subst source.
 destruct Evidence as [current Found entry Stored Eligible]; cbn [S.feature_observation S.maintenance_previous].
 now rewrite Stored.
Qed.

Lemma resolved_maintenance_installs_its_exact_receiver : forall before (plan : S.feature_plan before) owner request,
 S.feature_intent plan = S.MaintainRequest owner request ->
 let issued:=S.feature_issue plan in let built:=S.maintenance_build owner (world_next_ticket before) request in
 find (fun item => N.eqb (fst item) owner)
  (C.maintenance_entries (F.feature_compaction (world_features (decision_world issued)))) =
  Some (owner,set C.entry_observation (fun _ => match S.compaction_entry owner before with
    | Some current => C.entry_observation current | None => None end) (fst built)) /\
 decision_effects issued=[MaintainContext (snd built)].
Proof.
 intros before plan owner request Intent.
 pose proof (maintenance_issue_retains_the_observed_entry before plan owner request Intent) as Observation.
 unfold S.feature_issue,S.feature_issue_change; rewrite Intent,Observation.
 cbn [CommandResult.accept S.feature_space allocate_identity next_identity S.feature_build].
 destruct (S.maintenance_build owner (world_next_ticket before) request) as [entry effect] eqn:Built.
 unfold S.put_compaction,with_features,Selvedge.Features.State.with_compaction,set.
 cbn. now rewrite N.eqb_refl.
Qed.

(** The typed production capability requires a ready resource and an actual
    completed context read. No supplied entry can manufacture that evidence. *)
Theorem maintenance_plan_has_observed_resource_admission :
 forall before (plan : S.feature_plan before) owner request,
 S.feature_intent plan = S.MaintainRequest owner request ->
 exists current entry input observed,
 find_task owner before = Some current /\
 S.compaction_entry owner before = Some entry /\
 C.entry_observation entry = Some observed /\
 S.resources_available current before = true /\
 S.capture_compatible input current before = true /\
 S.capture_compatible observed current before = true /\
 ContextSelection.history_extends (C.captured_history observed) (C.captured_history input) = true.
Proof.
 intros before [source Evidence] owner request Same; cbn in Same; subst source.
 destruct Evidence as [current Found entry Stored Admitted].
 apply andb_true_iff in Admitted as [Admitted Replacement].
 unfold S.maintenance_ready_from in Admitted.
 destruct (C.entry_observation entry) as [observed|] eqn:Observed; [|repeat rewrite andb_false_r in Admitted; discriminate].
 exists current, entry, (S.maintenance_input request), observed.
 repeat rewrite andb_true_iff in Admitted. repeat split; try assumption; tauto.
Qed.

Lemma maintenance_plans_meet_the_replacement_contract : forall before
 (plan : S.feature_plan before) owner request,
 S.feature_intent plan = S.MaintainRequest owner request ->
 S.maintenance_replacement_ready request = true.
Proof.
 intros before [source Evidence] owner request Same; cbn in Same; subst source.
 destruct Evidence as [current Found entry Stored Eligible].
 now apply andb_true_iff in Eligible as [_ Replacement].
Qed.

Theorem compaction_plans_own_a_closed_source_prefix :
 forall before (plan : S.feature_plan before) owner input purpose target progress scope entry,
 S.feature_intent plan = S.MaintainRequest owner
   (S.CompactRequest input purpose target progress scope entry) ->
 ContextSelection.closed_prefix (C.captured_history input) = true.
Proof.
 intros before plan owner input purpose target progress scope entry Same.
 exact (maintenance_plans_meet_the_replacement_contract before plan owner _ Same).
Qed.

Theorem validation_plans_own_a_closed_source_prefix :
 forall before (plan : S.feature_plan before) owner input purpose candidate preview entry,
 S.feature_intent plan = S.MaintainRequest owner
   (S.ValidationScopeRequest input purpose candidate preview entry) ->
 ContextSelection.closed_prefix (C.captured_history input) = true.
Proof.
 intros before plan owner input purpose candidate preview entry Same.
 exact (maintenance_plans_meet_the_replacement_contract before plan owner _ Same).
Qed.

Theorem maintenance_context_installs_the_exact_shared_ticket :
 forall before (request : S.maintenance_context_plan before),
 let target := S.maintenance_context_target request in
 let current := TaskScope.selected target in
 let owner := TaskScope.owner target in
 let ticket := world_next_ticket before in
 let issued := S.maintenance_observe request in
 find_task owner (decision_world issued) =
   Some (with_activity (ObservingContext ticket (List.length (task_history current))) current) /\
 (exists entry, S.compaction_entry owner (decision_world issued) = Some entry /\
   C.entry_job entry = C.AwaitingContext ticket (S.maintenance_context_purpose request)
     (match task_activity current with ReadyForModel => true | _ => false end)) /\
 decision_effects issued = [ObserveContext owner ticket current].
Proof.
 intros before request; cbn zeta.
 unfold S.maintenance_observe. cbn [allocate_identity next_identity decision_world decision_effects accept].
 split.
 - change (find_task (TaskScope.owner (S.maintenance_context_target request))
     (put_task (TaskScope.owner (S.maintenance_context_target request))
      (with_activity (ObservingContext (world_next_ticket before)
        (List.length (task_history (TaskScope.selected (S.maintenance_context_target request)))))
         (TaskScope.selected (S.maintenance_context_target request)))
      (with_ticket (N.succ (world_next_ticket before)) before)) =
     Some (with_activity (ObservingContext (world_next_ticket before)
        (List.length (task_history (TaskScope.selected (S.maintenance_context_target request)))))
         (TaskScope.selected (S.maintenance_context_target request)))).
   unfold find_task, put_task, with_tasks; cbn.
   eapply registry_replace_selected. exact (TaskScope.observed (S.maintenance_context_target request)).
 - split; [|reflexivity].
   unfold S.compaction_entry,S.put_compaction,with_features,Selvedge.Features.State.with_compaction,set; cbn.
   rewrite N.eqb_refl. eexists; split; reflexivity.
Qed.

Theorem maintenance_observation_uses_the_current_task : forall before
 (reference : TaskScope.task_reference before) purpose entry,
 S.can_observe_maintenance (TaskScope.selected reference) before = true ->
 S.maintenance_prefix_ready purpose (task_history (TaskScope.selected reference)) = true ->
 exists request, S.maintenance_context_selected reference purpose entry = Some request /\
   decision_effects (S.maintenance_observe request) =
     [ObserveContext (TaskScope.owner reference) (world_next_ticket before) (TaskScope.selected reference)].
Proof.
 intros before reference purpose entry Allowed Closed.
 unfold S.maintenance_context_selected,S.boolean_admission.
 destruct (Bool.bool_dec (S.maintenance_context_ready purpose (TaskScope.selected reference) before) true)
   as [Admitted|Refused].
 - eexists; split; reflexivity.
 - unfold S.maintenance_context_ready in Refused; rewrite Allowed,Closed in Refused; contradiction.
Qed.

Theorem unavailable_maintenance_observation_has_no_plan : forall before
 (reference : TaskScope.task_reference before) purpose entry,
 S.can_observe_maintenance (TaskScope.selected reference) before = false ->
 S.maintenance_context_selected reference purpose entry = None.
Proof.
 intros before reference purpose entry Unavailable.
 unfold S.maintenance_context_selected,S.boolean_admission.
 destruct (Bool.bool_dec (S.maintenance_context_ready purpose (TaskScope.selected reference) before) true)
   as [Admitted|Refused]; [|reflexivity].
 exfalso; unfold S.maintenance_context_ready in Admitted; rewrite Unavailable in Admitted; discriminate.
Qed.

Theorem an_open_summary_prefix_has_no_context_plan : forall before
 (reference : TaskScope.task_reference before) purpose entry,
 ContextSelection.closed_prefix (task_history (TaskScope.selected reference)) = false ->
 S.maintenance_context_selected reference (Some purpose) entry = None.
Proof.
 intros before reference purpose entry Open.
 unfold S.maintenance_context_selected,S.boolean_admission.
 destruct (Bool.bool_dec (S.maintenance_context_ready (Some purpose) (TaskScope.selected reference) before) true)
   as [Admitted|Refused]; [|reflexivity].
 exfalso; unfold S.maintenance_context_ready,S.maintenance_prefix_ready in Admitted.
 rewrite Open,andb_false_r in Admitted; discriminate.
Qed.
