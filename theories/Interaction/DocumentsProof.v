From Stdlib Require Import List String Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json Numbers Utf8.
From Selvedge.Interaction Require Import Codec Identity Origin CodeSource DocumentState Documents.
From Selvedge.Interaction.Interactive Require Import Types.
From Selvedge.Interaction.Interactive Require Bounds.
Import ListNotations.

Theorem inherited_document_has_no_external_capability : forall context doc owner retained,
 find_document context owner retained=Some doc -> viewer doc<>producer(provenance doc) ->
 owning_task context owner retained=None.
Proof.
 intros context doc owner retained Found Different. unfold owning_task;rewrite Found.
 assert (N.eqb(viewer doc)(producer(provenance doc))=false) by (apply N.eqb_neq;exact Different).
 rewrite H. destruct (interactive_origin(provenance doc)),(complete doc);reflexivity.
Qed.
Theorem empty_namespace_has_no_external_capability : forall context owner retained,
 context_namespace context=""%string -> externally_allowed context owner retained=false.
Proof. intros context owner retained Empty;unfold externally_allowed;rewrite Empty;reflexivity. Qed.
Theorem generated_external_permission_requires_completed_producer : forall context doc,
 document_external context doc=true ->
 valid_namespace(context_namespace context)=true /\ complete doc=true /\ context_connected context=true /\
 viewer doc=producer(provenance doc) /\ mode(provenance doc)=InteractiveV1.
Proof.
 intros context doc Allowed. unfold document_external,external_allowed in Allowed.
 repeat rewrite Bool.andb_true_iff in Allowed.
 destruct Allowed as [[Namespace Complete] [[[Connected _] Same] Mode]].
 apply N.eqb_eq in Same. destruct(mode(provenance doc))eqn:ModeValue;try discriminate.
 repeat split;auto.
Qed.
Theorem closed_fence_cannot_reopen_or_change : forall namespace observation doc stamp retained previous,
 observation_valid namespace observation doc stamp retained=true ->
 In previous(document_observations stamp) ->
 observation_ordinal observation=fence_ordinal previous -> fence_closed previous=true ->
 observation_closed observation=true /\ observation_code observation=fence_code previous.
Proof.
 intros namespace observation doc stamp retained previous Accepted Member Ordinal Closed.
 unfold observation_valid in Accepted. apply andb_true_iff in Accepted as [_ Extends].
 apply forallb_forall with (x:=previous) in Extends;auto.
 unfold fence_extends in Extends. rewrite Ordinal,N.eqb_refl,Closed in Extends.
 simpl in Extends. apply andb_true_iff in Extends as [_ Extends].
 apply andb_true_iff in Extends as [ClosedNow Equal]. apply String.eqb_eq in Equal. auto.
Qed.
Theorem accepted_parser_prefix_never_regresses : forall namespace observation doc stamp retained,
 observation_valid namespace observation doc stamp retained=true ->
 (document_observed_prefix stamp <= document_observed_prefix(record_observation observation stamp))%nat.
Proof.
 intros namespace observation doc stamp retained Accepted.
 unfold observation_valid in Accepted. repeat rewrite andb_true_iff in Accepted.
 unfold record_observation,update_stamp;simpl.
 apply Nat.leb_le. tauto.
Qed.
Theorem accepted_observation_uses_registered_visible_document : forall context raw retained input next,
 observe_document context raw retained=Some(input,next) ->
 exists observation doc stamp,
 decode_observation raw=Some observation /\ In doc(visible_documents context retained) /\
 document_stamp (context_namespace context) doc retained=Some stamp /\
 observation_valid (context_namespace context) observation doc stamp retained=true /\
 input=SourceChanged (Owner (CodeSource.owner_key(code_identity(context_namespace context)doc(observation_ordinal observation))) (document_epoch stamp))
  (observation_code observation)(observation_closed observation)
  (if String.eqb(observation_prefix observation)(markdown doc)then document_ending stamp else Open)
  (document_external context doc).
Proof.
 intros context raw retained input next Accepted. unfold observe_document in Accepted.
 destruct(decode_observation raw)as [observation|]eqn:Decoded;simpl in Accepted;try discriminate.
 destruct(find(fun doc=>String.eqb(observation_key observation)(key(context_namespace context)doc))(visible_documents context retained))as [doc|]eqn:Found;simpl in Accepted;try discriminate.
 destruct(document_stamp(context_namespace context)doc retained)as [stamp|]eqn:Stamp;simpl in Accepted;try discriminate.
 destruct(observation_valid(context_namespace context)observation doc stamp retained)eqn:Valid;try discriminate.
 inversion Accepted;subst. exists observation,doc,stamp. repeat split;auto.
 apply find_some in Found. tauto.
Qed.
Theorem accepted_external_source_is_completed_owned_output : forall context raw retained owner code closed ending next,
 observe_document context raw retained=Some(SourceChanged owner code closed ending true,next) ->
 exists doc,In doc(visible_documents context retained) /\ complete doc=true /\
 viewer doc=producer(provenance doc) /\ mode(provenance doc)=InteractiveV1.
Proof.
 intros context raw retained owner code closed ending next Accepted.
 apply accepted_observation_uses_registered_visible_document in Accepted.
 destruct Accepted as [observation [doc [stamp [_ [Member [_ [_ Input]]]]]]].
 inversion Input.
 assert (document_external context doc=true) as Allowed by congruence.
 apply generated_external_permission_requires_completed_producer in Allowed.
 exists doc. tauto.
Qed.

Theorem continuous_document_preserves_epoch_and_observation : forall namespace doc s prior,
 find(fun stamp=>String.eqb(key namespace doc)(document_identity stamp))(document_lifetimes s)=Some prior ->
 continuous_document prior doc=true ->
 exists tail,document_lifetimes(remember_document namespace doc s)=
  update_stamp(markdown doc)(if complete doc then Complete else Open)false false(document_observed_prefix prior)(document_observations prior)prior::tail.
Proof.
 intros namespace doc s prior Found Continuous.
 unfold remember_document. rewrite Found,Continuous.
 eexists. reflexivity.
Qed.
Theorem discontinuous_document_allocates_fresh_epoch : forall namespace doc s prior,
 find(fun stamp=>String.eqb(key namespace doc)(document_identity stamp))(document_lifetimes s)=Some prior ->
 continuous_document prior doc=false ->
 exists stamp tail,document_lifetimes(remember_document namespace doc s)=stamp::tail /\
 document_epoch stamp=retention_next_epoch(s) /\
 document_observed_prefix stamp=0%nat /\ document_observations stamp=[] /\
 retention_next_epoch(remember_document namespace doc s)=N.succ(retention_next_epoch(s)).
Proof.
 intros namespace doc s prior Found Discontinuous. unfold remember_document;rewrite Found,Discontinuous.
 do 2 eexists. repeat split;reflexivity.
Qed.
Theorem namespace_switch_preserves_epoch_allocator : forall namespace world s,
 retention_next_epoch(scoped_retention namespace world s)=retention_next_epoch(s).
Proof. intros;unfold scoped_retention;destruct(String.eqb namespace(retention_namespace(s)));reflexivity. Qed.
Definition live_retained stamp:=same_ending(document_ending stamp)Interrupted&&negb(document_archived stamp).
Definition live_count stamps:=List.length(filter live_retained stamps).
Definition archived_bytes stamps:=fold_right(fun stamp total=>if document_archived stamp then Nat.add(Utf8.byte_length(document_source stamp))total else total)0%nat stamps.

Theorem interrupted_session_bound : forall stamps counts total,
 (total<=Bounds.retained_per_session)%nat ->
 (total+live_count(bound_interrupted stamps counts total)<=Bounds.retained_per_session)%nat.
Proof.
 induction stamps as [|stamp rest IH];intros counts total Within;[change (total+0<=Bounds.retained_per_session)%nat;rewrite Nat.add_0_r;exact Within|].
 cbn [bound_interrupted]. fold(live_retained stamp).
 destruct(live_retained stamp)eqn:Live.
 - destruct(Nat.ltb total Bounds.retained_per_session&&Nat.ltb(count_for(document_viewer stamp)counts)Bounds.retained_per_task)eqn:Admit.
   + apply andb_true_iff in Admit as [Room _]. apply Nat.ltb_lt in Room.
     specialize(IH(increment_count(document_viewer stamp)counts)(S total)ltac:(lia)).
     unfold live_count in *. simpl. rewrite Live. simpl. lia.
   + specialize(IH counts total Within). unfold live_count in *;simpl.
     unfold live_retained,archive_stamp,update_stamp;simpl. rewrite andb_false_r. exact IH.
 - specialize(IH counts total Within). unfold live_count in *;simpl. rewrite Live. exact IH.
Qed.

Theorem archived_source_byte_bound : forall stamps bytes kept discarded,
 trim_archives stamps bytes=(kept,discarded) -> (bytes<=Bounds.retained_source_bytes)%nat ->
 (bytes+archived_bytes kept<=Bounds.retained_source_bytes)%nat.
Proof.
 induction stamps as [|stamp rest IH];intros bytes kept discarded Trim Within.
 - simpl in Trim;inversion Trim;subst;simpl;lia.
 - cbn [trim_archives]in Trim.
   destruct(document_archived stamp)eqn:Archived.
   + destruct(Nat.leb(bytes+Utf8.byte_length(document_source stamp))Bounds.retained_source_bytes)eqn:Room.
     * apply Nat.leb_le in Room.
       destruct(trim_archives rest(bytes+Utf8.byte_length(document_source stamp)))as [tail removed]eqn:Tail.
       inversion Trim;subst. specialize(IH _ _ _ Tail Room).
       unfold archived_bytes in *;simpl;rewrite Archived;lia.
     * destruct(trim_archives rest bytes)as [tail removed]eqn:Tail.
       inversion Trim;subst. exact(IH _ _ _ Tail Within).
   + destruct(trim_archives rest bytes)as [tail removed]eqn:Tail.
     inversion Trim;subst. specialize(IH _ _ _ Tail Within).
     unfold archived_bytes in *;simpl;rewrite Archived;exact IH.
Qed.

Lemma removing_rejected_member_shortens : forall(A:Type)(predicate:A->bool)value values,
 In value values -> predicate value=false ->
 (List.length(filter predicate values)<List.length values)%nat.
Proof.
 intros A predicate value values;induction values as [|head rest IH];intros Member Rejected;[contradiction|].
 destruct Member as [Same|Member].
 - subst head;simpl;rewrite Rejected. pose proof(filter_length_le predicate rest);lia.
 - simpl;destruct(predicate head);simpl;[specialize(IH Member Rejected)|pose proof(filter_length_le predicate rest)];lia.
Qed.
Theorem accepted_fence_count_bound : forall namespace doc stamp s observation,
 document_stamp namespace doc s=Some stamp ->
 eligible_fence namespace doc(observation_ordinal observation)s=true ->
 (List.length(document_observations stamp)<=Bounds.interactive_fences_per_document)%nat ->
 (List.length(document_observations(record_observation observation stamp))<=Bounds.interactive_fences_per_document)%nat.
Proof.
 intros namespace doc stamp s observation Found Eligible Within.
 unfold eligible_fence in Eligible;rewrite Found in Eligible.
 apply andb_true_iff in Eligible as [_ Eligible].
 unfold record_observation,update_stamp;simpl.
 destruct(existsb(N.eqb(observation_ordinal observation))(document_fences stamp))eqn:Exists.
 - apply existsb_exists in Exists as [ordinal [Member Same]].
   unfold document_fences in Member. apply in_map_iff in Member as [previous [Ordinal Member]].
   assert(N.eqb(observation_ordinal observation)(fence_ordinal previous)=true)as Equal by congruence.
   pose proof(removing_rejected_member_shortens document_fence
    (fun fence=>negb(N.eqb(observation_ordinal observation)(fence_ordinal fence)))previous(document_observations stamp)Member)as Shorter.
   cbn beta in Shorter. rewrite Equal in Shorter. specialize(Shorter eq_refl). lia.
 - simpl in Eligible;apply Nat.ltb_lt in Eligible.
   unfold document_fences in Eligible;rewrite length_map in Eligible.
   pose proof(filter_length_le(fun fence=>negb(N.eqb(observation_ordinal observation)(fence_ordinal fence)))(document_observations stamp)). lia.
Qed.


Lemma count_for_filter_other : forall task viewer counts,
 task<>viewer ->
 count_for task(filter(fun entry=>negb(N.eqb viewer(fst entry)))counts)=count_for task counts.
Proof.
 intros task viewer counts Different. unfold count_for.
 induction counts as [|[id count]rest IH];[reflexivity|].
 cbn. destruct(N.eqb viewer id)eqn:Removed;cbn.
 - destruct(N.eqb task id)eqn:Matches;auto.
   apply N.eqb_eq in Removed,Matches;congruence.
 - cbn. destruct(N.eqb task id);auto.
Qed.
Lemma count_for_increment : forall task viewer counts,
 count_for task(increment_count viewer counts)=
 if N.eqb task viewer then S(count_for task counts)else count_for task counts.
Proof.
 intros task viewer counts. unfold increment_count.
 unfold count_for at 1;cbn. destruct(N.eqb task viewer)eqn:Same;[apply N.eqb_eq in Same;subst;reflexivity|].
 apply N.eqb_neq in Same. apply count_for_filter_other;exact Same.
Qed.
Definition task_live_count task stamps:=List.length(filter(fun stamp=>live_retained stamp&&N.eqb task(document_viewer stamp))stamps).
Theorem interrupted_task_bound : forall stamps task counts total,
 (count_for task counts<=Bounds.retained_per_task)%nat ->
 (count_for task counts+task_live_count task(bound_interrupted stamps counts total)<=Bounds.retained_per_task)%nat.
Proof.
 induction stamps as [|stamp rest IH];intros task counts total Within.
 - change (count_for task counts+0<=Bounds.retained_per_task)%nat;rewrite Nat.add_0_r;exact Within.
 - cbn [bound_interrupted];fold(live_retained stamp).
   destruct(live_retained stamp)eqn:Live.
   + destruct(Nat.ltb total Bounds.retained_per_session&&Nat.ltb(count_for(document_viewer stamp)counts)Bounds.retained_per_task)eqn:Admit.
     * apply andb_true_iff in Admit as [_ Room];apply Nat.ltb_lt in Room.
       destruct(N.eqb task(document_viewer stamp))eqn:Same.
       -- assert((count_for task(increment_count(document_viewer stamp)counts)<=Bounds.retained_per_task)%nat)as NextRoom.
          {rewrite count_for_increment,Same. apply N.eqb_eq in Same;subst task;lia. }
          specialize(IH task(increment_count(document_viewer stamp)counts)(S total)NextRoom).
          rewrite count_for_increment,Same in IH.
          unfold task_live_count in *;cbn;rewrite Live,Same;cbn;lia.
       -- assert((count_for task(increment_count(document_viewer stamp)counts)<=Bounds.retained_per_task)%nat)as NextRoom.
          {rewrite count_for_increment,Same;exact Within. }
          specialize(IH task(increment_count(document_viewer stamp)counts)(S total)NextRoom).
          rewrite count_for_increment,Same in IH.
          unfold task_live_count in *;cbn;rewrite Live,Same;cbn;exact IH.
     * specialize(IH task counts total Within). unfold task_live_count in *;cbn.
       unfold live_retained,archive_stamp,update_stamp;cbn;rewrite andb_false_r;exact IH.
   + specialize(IH task counts total Within). unfold task_live_count in *;cbn;rewrite Live;cbn;exact IH.
Qed.

Lemma trim_archives_preserves_unarchived_predicate : forall predicate stamps bytes kept discarded,
 (forall stamp,document_archived stamp=true -> predicate stamp=false) ->
 trim_archives stamps bytes=(kept,discarded) ->
 List.length(filter predicate kept)=List.length(filter predicate stamps).
Proof.
 intros predicate stamps;induction stamps as [|stamp rest IH];intros bytes kept discarded Inactive Trim.
 - inversion Trim;reflexivity.
 - cbn [trim_archives]in Trim.
   destruct(document_archived stamp)eqn:Archived.
   + pose proof(Inactive stamp Archived)as Live.
     destruct(Nat.leb(bytes+Utf8.byte_length(document_source stamp))Bounds.retained_source_bytes).
     * destruct(trim_archives rest(bytes+Utf8.byte_length(document_source stamp)))as [tail removed]eqn:Tail.
       inversion Trim;subst. specialize(IH _ _ _ Inactive Tail). cbn;rewrite Live;exact IH.
     * destruct(trim_archives rest bytes)as [tail removed]eqn:Tail.
       inversion Trim;subst. specialize(IH _ _ _ Inactive Tail). cbn;rewrite Live;exact IH.
   + destruct(trim_archives rest bytes)as [tail removed]eqn:Tail.
     inversion Trim;subst. specialize(IH _ _ _ Inactive Tail). cbn.
     destruct(predicate stamp);cbn;congruence.
Qed.
Theorem trim_archives_preserves_live_count : forall stamps bytes kept discarded,
 trim_archives stamps bytes=(kept,discarded) -> live_count kept=live_count stamps.
Proof.
 intros. unfold live_count. eapply trim_archives_preserves_unarchived_predicate;[|eauto].
 intros stamp Archived. unfold live_retained;rewrite Archived;apply andb_false_r.
Qed.
Theorem trim_archives_preserves_task_live_count : forall stamps task bytes kept discarded,
 trim_archives stamps bytes=(kept,discarded) -> task_live_count task kept=task_live_count task stamps.
Proof.
 intros. unfold task_live_count. eapply trim_archives_preserves_unarchived_predicate;[|eauto].
 intros stamp Archived. unfold live_retained;rewrite Archived,andb_false_r;reflexivity.
Qed.

Theorem synchronized_retention_respects_limits : forall context lagged s,
 let stamps:=document_lifetimes(synchronize_documents context lagged s)in
 (live_count stamps<=Bounds.retained_per_session)%nat /\
 (forall task,(task_live_count task stamps<=Bounds.retained_per_task)%nat) /\
 (archived_bytes stamps<=Bounds.retained_source_bytes)%nat.
Proof.
 intros context lagged s. unfold synchronize_documents.
 cbn zeta.
 match goal with
 | |- context[trim_archives ?stamps 0%nat]=>
   destruct(trim_archives stamps 0%nat)as [kept discarded]eqn:Trim
 end.
 change ((live_count kept<=Bounds.retained_per_session)%nat /\
 (forall task,(task_live_count task kept<=Bounds.retained_per_task)%nat) /\
 (archived_bytes kept<=Bounds.retained_source_bytes)%nat).
 split.
 - rewrite(trim_archives_preserves_live_count _ _ _ _ Trim).
   exact(interrupted_session_bound _ [] 0%nat(Nat.le_0_l _)).
 - split.
   + intros task. rewrite(trim_archives_preserves_task_live_count _ task _ _ _ Trim).
     exact(interrupted_task_bound _ task [] 0%nat(Nat.le_0_l _)).
   + pose proof(archived_source_byte_bound _ _ _ _ Trim(Nat.le_0_l _))as Bound. exact Bound.
Qed.

Theorem decoded_retention_uses_fresh_allocator : forall encoded r,
 decode_retention encoded=Some r ->
 forall stamp,In stamp(retention_documents r) -> (document_epoch stamp<retention_next_epoch r)%N.
Proof.
 intros encoded r Decoded.
 unfold decode_retention in Decoded.
 destruct(string_field "namespace" encoded)as [namespace|]eqn:Namespace;cbn in Decoded;try discriminate.
 destruct(natural_field "next_epoch" encoded)as [next_epoch|]eqn:Next;cbn in Decoded;try discriminate.
 destruct(list_field(decode_document_lifetime namespace)"documents"encoded)as [documents|]eqn:Documents;cbn in Decoded;try discriminate.
 destruct(list_field(fun j=>match j with JArray[a;b]=>a<-natural a;;b<-natural b;;Some(a,b)|_=>None end)"discarded"encoded)as [discarded|]eqn:Discarded;cbn in Decoded;try discriminate.
 destruct(valid_retention(Retention namespace next_epoch documents discarded))eqn:Valid;try discriminate.
 inversion Decoded;subst. intros stamp Member.
 unfold valid_retention in Valid. apply andb_true_iff in Valid as [_ All].
 apply forallb_forall with (x:=stamp)in All;auto.
 unfold valid_document_lifetime in All. repeat rewrite andb_true_iff in All.
 apply N.ltb_lt. tauto.
Qed.
Theorem source_identity_is_derived : forall namespace viewer origin epoch source ending archived revealed observed fences,
 document_identity(DocumentLifetime namespace viewer origin epoch source ending archived revealed observed fences)=
 content_key namespace viewer origin.
Proof. reflexivity. Qed.

Theorem remember_epoch_allocator_never_decreases : forall namespace doc s,
 (retention_next_epoch(s)<=retention_next_epoch(remember_document namespace doc s))%N.
Proof.
 intros;unfold remember_document.
 destruct(find(fun stamp=>String.eqb(key namespace doc)(document_identity stamp))(document_lifetimes s))as [prior|];
 [destruct(continuous_document prior doc)|];cbn;[apply N.le_refl|apply N.le_succ_diag_r|apply N.le_succ_diag_r].
Qed.
Lemma fold_remember_epoch_monotone : forall namespace docs s,
 (retention_next_epoch(s)<=retention_next_epoch(fold_left(fun current doc=>remember_document namespace doc current)docs s))%N.
Proof.
 intros namespace docs;induction docs as [|doc rest IH];intros s;cbn;[apply N.le_refl|].
 eapply N.le_trans;[apply remember_epoch_allocator_never_decreases|apply IH].
Qed.
Theorem replacement_epoch_exceeds_decoded_owners : forall namespace doc s prior encoded,
 decode_retention encoded=Some(s) ->
 find(fun stamp=>String.eqb(key namespace doc)(document_identity stamp))(document_lifetimes s)=Some prior ->
 continuous_document prior doc=false ->
 exists replacement tail,document_lifetimes(remember_document namespace doc s)=replacement::tail /\
 (forall old,In old(document_lifetimes s) -> (document_epoch old<document_epoch replacement)%N).
Proof.
 intros namespace doc s prior encoded Decoded Found Discontinuous.
 destruct(discontinuous_document_allocates_fresh_epoch namespace doc s prior Found Discontinuous)as [replacement [tail [Result [Epoch _]]]].
 exists replacement,tail;split;[exact Result|].
 intros old Member. rewrite Epoch. eapply decoded_retention_uses_fresh_allocator;[exact Decoded|exact Member].
Qed.
Theorem synchronized_epoch_allocator_never_decreases : forall context lagged s,
 (retention_next_epoch(s)<=retention_next_epoch(synchronize_documents context lagged s))%N.
Proof.
 intros context lagged s. unfold synchronize_documents;cbn zeta.
 match goal with
 | |- context[trim_archives ?stamps 0%nat]=>
   destruct(trim_archives stamps 0%nat)as [kept discarded]eqn:Trim
 end.
 match goal with
 | |- context[fold_left(fun(current:retention)(doc:document)=>remember_document (context_namespace context) doc current)?docs ?initial]=>
   pose proof(fold_remember_epoch_monotone (context_namespace context) docs initial)as Progress
 end.
 rewrite namespace_switch_preserves_epoch_allocator in Progress. exact Progress.
Qed.
