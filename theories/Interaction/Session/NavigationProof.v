From Stdlib Require Import List Bool NArith.
From Selvedge.Interaction Require Input.
From Selvedge.Interaction.Session Require State Navigation.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.

Lemma reader_for_task state task :
 State.reading_task(Navigation.reader_for state task)=task.
Proof.
 unfold Navigation.reader_for.
 destruct(find(fun reader=>N.eqb task(State.reading_task reader))(State.readers state))eqn:found.
 - apply find_some in found. destruct found as [_ owned].
   apply N.eqb_eq in owned. symmetry. exact owned.
 - reflexivity.
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
