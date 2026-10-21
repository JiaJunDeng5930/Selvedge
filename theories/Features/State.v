From Stdlib Require Import List NArith.
From Selvedge.Features Require Import Domain.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.

Definition with_board (replacement : board) (value : state) :=
 set feature_board (fun _=>replacement) value.
Definition with_works (replacement : list work) (value : state) :=
 set feature_works (fun _=>replacement) value.
Definition with_task_owners (replacement : list (N*N)) (value : state) :=
 set feature_task_owners (fun _=>replacement) value.
Definition with_graph_owners (replacement : list (N*N)) (value : state) :=
 set feature_graph_owners (fun _=>replacement) value.
Definition with_graphs (replacement : list (option task_graph)) (value : state) :=
 set feature_graphs (fun _=>replacement) value.
Definition with_worktrees (replacement : list worktree) (value : state) :=
 set feature_worktrees (fun _=>replacement) value.
Definition with_remote (replacement : remote) (value : state) :=
 set feature_remote (fun _=>replacement) value.
Definition with_sharing (replacement : connection_state) (value : state) :=
 set feature_sharing (fun _=>replacement) value.
Definition with_titles (replacement : list title_entry) (value : state) :=
 set feature_titles (fun _=>replacement) value.
Definition with_title_settings (replacement : title_settings) (value : state) :=
 set feature_title_settings (fun _=>replacement) value.
Definition with_compaction (replacement : CompactionTypes.state) (value : state) :=
 set feature_compaction (fun _=>replacement) value.
