From Stdlib Require Import List Bool NArith.
From Selvedge.Interaction Require Input Identity.
From Selvedge.Generated Require Commands.
From Selvedge.Interaction.Session Require State Navigation.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.

Theorem editing_history_search_discards_previous_result state query project work:
 State.location(State.navigation_state state)=Identity.HistorySearch ->
 State.history_search(State.authoring_state
  (Navigation.result_state(Navigation.edit_search query project work state)))=
 State.Search query project work None None.
Proof.
 intro Location. unfold Navigation.edit_search. rewrite Location.
 reflexivity.
Qed.

Theorem submitted_history_search_uses_shared_bounded_query state after:
 State.location(State.navigation_state state)=Identity.HistorySearch ->
 let search:=State.history_search(State.authoring_state state)in
 let ticket:=State.next(State.authoring_state state)in
 Navigation.submit_search after state=
 Navigation.generated(Commands.Cmd_search_history(Commands.Build_search_history
  (State.keyword search)(State.project_filter search)(State.work_filter search)(Some after)(Some 20%N)))
  (State.SearchSubmission(State.keyword search)(State.project_filter search)(State.work_filter search)ticket)
  (Navigation.set_search(set State.search_latest(fun _=>Some ticket)search)state).
Proof. intro Location. unfold Navigation.submit_search. rewrite Location. reflexivity. Qed.

Lemma reader_for_task state task :
 State.reading_task(Navigation.reader_for state task)=task.
Proof.
 unfold Navigation.reader_for.
 destruct(find(fun reader=>N.eqb task(State.reading_task reader))(State.readers state))eqn:found.
 - apply find_some in found. destruct found as [_ owned].
   apply N.eqb_eq in owned. symmetry. exact owned.
 - reflexivity.
Qed.

Lemma selection_intent_invalidates_prior_generation state :
 N.eqb(State.generation(State.navigation_state state))
  (State.generation(State.navigation_state(Navigation.selection_intent state)))=false.
Proof.
 unfold Navigation.selection_intent,State.with_navigation. cbn.
 apply N.eqb_neq. apply N.neq_succ_diag_r.
Qed.

Theorem new_selection_intent_prevents_work_completion_selection snapshot state layer outcome :
 Navigation.outcome_success outcome=true ->
 Navigation.complete snapshot
  (State.WorkCreation(State.generation(State.navigation_state state))layer)outcome
  (Navigation.selection_intent state)=Some(Navigation.keep(Navigation.selection_intent state)).
Proof.
 intro Success. cbn[Navigation.complete]. rewrite Success. cbn.
 rewrite selection_intent_invalidates_prior_generation. reflexivity.
Qed.

Theorem new_selection_intent_prevents_side_completion_selection snapshot state parent layer trigger outcome :
 Navigation.outcome_success outcome=true ->
 Navigation.complete snapshot
  (State.SideCreation parent(State.generation(State.navigation_state state))layer trigger)outcome
  (Navigation.selection_intent state)=Some(Navigation.keep(Navigation.selection_intent state)).
Proof.
 intro Success. cbn[Navigation.complete]. rewrite Success. cbn.
 rewrite selection_intent_invalidates_prior_generation. reflexivity.
Qed.
Lemma reader_for_stored state reader :
 Navigation.reader_for(Navigation.store_reader reader state)(State.reading_task reader)=reader.
Proof.
 unfold Navigation.reader_for, Navigation.store_reader, State.with_readers.
 destruct state. cbn. rewrite N.eqb_refl. reflexivity.
Qed.
Theorem obsolete_read_timeline_preserves_session snapshot state task generation intent :
 Navigation.task_visible state task=false \/
 N.eqb generation(State.reader_generation(Navigation.reader_for state task))=false ->
 Navigation.step snapshot(Input.ReadTimeline task generation intent)state=Some(Navigation.keep state).
Proof.
 intros [invisible|obsolete]; cbn[Navigation.step];unfold Navigation.read_current.
 - rewrite invisible. reflexivity.
 - rewrite obsolete, andb_false_r. reflexivity.
Qed.
Theorem current_read_timeline_sets_position snapshot state task intent :
 Navigation.task_visible state task=true ->
 exists next,
 Navigation.step snapshot(Input.ReadTimeline task
   (State.reader_generation(Navigation.reader_for state task))intent)state=Some next /\
 State.reader_position(Navigation.reader_for(Navigation.result_state next)task)=intent.
Proof.
 intro visible. cbn[Navigation.step]. unfold Navigation.read_current.
 rewrite visible,N.eqb_refl. cbn.
 eexists. split;[reflexivity|]. cbn[Navigation.keep].
 set (reader:=set State.reader_position(fun _=>intent)(Navigation.reader_for state task)).
 assert(owned:State.reading_task reader=task).
 { unfold reader. cbn. apply reader_for_task. }
 change (State.reader_position(Navigation.reader_for(Navigation.store_reader reader state)task)=intent).
 rewrite <-owned,reader_for_stored. unfold reader. cbn. reflexivity.
Qed.
