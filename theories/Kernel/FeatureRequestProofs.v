From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json Registry RegistryProofs.
From Selvedge.Kernel Require Import Domain State TicketedRequest.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.
Module S := TicketedRequest.Scoped.
Module F := Selvedge.Features.Domain.
Module C := Selvedge.Features.CompactionTypes.

Definition title_receiver owner ticket selected prompt value :=
 find (fun item => N.eqb owner (F.title_task item)) (F.feature_titles (world_features value)) =
 Some (F.TitleEntry owner (F.TitlePending ticket selected prompt)).
Definition card_receiver owner ticket revision retitle value :=
 exists card, registry_at owner (F.board_cards (F.feature_board (world_features value))) = Some (Some card) /\
 F.card_enrichment card = F.Enriching ticket revision retitle.
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
 | SuggestTitle owner ticket selected prompt => title_receiver owner ticket selected prompt value
 | SuggestCard owner ticket revision _ _ _ retitle => card_receiver owner ticket revision retitle value
 | RunConnectionJob identity job => connection_receiver identity job value
 | MaintainContext (C.Scope owner ticket _) | MaintainContext (C.Measure owner ticket _ _ _)
 | MaintainContext (C.Compact owner ticket _ _ _ _) => maintenance_receiver owner ticket value
 | _ => False end.

Lemma put_title_installs : forall owner ticket selected prompt value,
 title_receiver owner ticket selected prompt (S.put_title owner (F.TitlePending ticket selected prompt) value).
Proof. intros. unfold title_receiver,S.put_title. unfold with_features, Selvedge.Features.State.with_titles, set. cbn. now rewrite N.eqb_refl. Qed.
Lemma put_card_installs : forall owner ticket card retitle value,
 (owner <= N.of_nat (List.length (F.board_cards (F.feature_board (world_features value)))))%N ->
 card_receiver owner ticket (F.card_revision card) retitle
  (S.put_card owner (set F.card_enrichment (fun _ => F.Enriching ticket (F.card_revision card) retitle) card) value).
Proof.
 intros owner ticket card retitle value Bound. unfold card_receiver,S.put_card; unfold with_features, Selvedge.Features.State.with_board, set. cbn.
 exists (set F.card_enrichment (fun _ => F.Enriching ticket (F.card_revision card) retitle) card); split; [|reflexivity].
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
Lemma put_maintenance_installs : forall owner ticket source value,
 maintenance_receiver owner ticket
  (S.put_compaction owner (fst (S.maintenance_build owner ticket source)) value).
Proof.
 intros owner ticket source value. unfold maintenance_receiver,S.put_compaction. unfold with_features, Selvedge.Features.State.with_compaction, set. cbn. rewrite N.eqb_refl.
 eexists; split; [reflexivity|].
 destruct source as [input [purpose|] entry|input [purpose|] [[candidate preview]|] scope entry|input purpose target progress scope entry]; cbn; unfold set; cbn; auto.
Qed.

(** The production interpreter has a receiver correspondence guarantee. Its
    conclusion inspects the installed domain receiver, rather than just the
    emitted effect's coordinate or an assumed successful validator result. *)
Theorem every_feature_request_has_its_installed_receiver : forall before (request : S.feature_plan before) emitted,
 In emitted (decision_effects (S.feature_issue request)) ->
 receiver_installed emitted (decision_world (S.feature_issue request)).
Proof.
 intros before [source Valid] emitted Member. unfold S.feature_issue in *; cbn in *.
 destruct source as [owner selected prompt|owner card selected prompt retitle|job|owner request];
 cbn [S.feature_space allocate_identity next_identity S.feature_build] in *.
 - destruct Member as [<-|[]]. apply put_title_installs.
 - destruct Member as [<-|[]]. apply put_card_installs. now apply N.leb_le.
 - destruct Member as [<-|[]]. apply put_connection_installs.
   cbn [S.feature_valid] in Valid. destruct (F.job_state job); try discriminate; reflexivity.
 - destruct (S.maintenance_build owner (world_next_ticket before) request) as [pending request_effect] eqn:Built.
   cbn in *. destruct Member as [<-|[]].
   pose proof (put_maintenance_installs owner (world_next_ticket before) request
     (with_ticket (N.succ (world_next_ticket before)) before)) as Installed.
   rewrite Built in Installed; cbn in Installed.
   destruct request as [input purpose entry|input purpose candidate scope entry|input purpose target progress scope entry];
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
 intros before [source Valid]; cbn. unfold S.feature_issue; cbn.
 destruct source; cbn [S.feature_space allocate_identity next_identity S.feature_build];
 try (repeat split; reflexivity).
 destruct (S.maintenance_build owner (world_next_ticket before) request); repeat split; reflexivity.
Qed.

Theorem every_resolved_feature_request_has_its_installed_receiver : forall source before emitted,
 In emitted (decision_effects (S.feature_run source before)) ->
 receiver_installed emitted (decision_world (S.feature_run source before)).
Proof.
 intros source before emitted Member. unfold S.feature_run,S.feature_with_reply in *.
 destruct (S.feature source before) as [request|]; [|contradiction].
 eapply every_feature_request_has_its_installed_receiver; exact Member.
Qed.

Theorem every_responded_feature_request_has_its_installed_receiver : forall reply source before emitted,
 In emitted (decision_effects (S.feature_with_reply reply source before)) ->
 receiver_installed emitted (decision_world (S.feature_with_reply reply source before)).
Proof.
 intros reply source before emitted Member. unfold S.feature_with_reply in *.
 destruct (S.feature source before) as [request|]; [|contradiction].
 eapply every_feature_request_has_its_installed_receiver; exact Member.
Qed.

Theorem maintenance_request_installs_its_exact_receiver : forall before owner request,
 let issued:=S.feature_run (S.MaintainRequest owner request) before in
 let built:=S.maintenance_build owner (world_next_ticket before) request in
 find (fun item => N.eqb (fst item) owner)
  (C.maintenance_entries (F.feature_compaction (world_features (decision_world issued)))) =
  Some (owner,fst built) /\
 decision_effects issued=[MaintainContext (snd built)].
Proof.
 intros before owner request.
 unfold S.feature_run,S.feature_with_reply,S.feature,S.feature_valid.
 cbn [S.feature_issue S.feature_intent S.feature_space allocate_identity next_identity S.feature_build].
 destruct (S.maintenance_build owner (world_next_ticket before) request) as [entry effect] eqn:Built.
 unfold S.put_compaction,with_features,Selvedge.Features.State.with_compaction,set.
 cbn. rewrite Built. cbn. unfold S.FS.with_compaction,with_features,with_ticket,set. cbn. now rewrite N.eqb_refl.
Qed.
