From Stdlib Require Import NArith.
From Selvedge.Kernel Require Import Domain State.

Record task_reference (before : world) := TaskReference {
 owner : N;
 selected : task;
 observed : find_task owner before = Some selected
}.
Arguments owner {before}.
Arguments selected {before}.
Arguments observed {before}.
Definition select (id : N) (before : world) : option (task_reference before) :=
 match find_task id before as found return find_task id before = found -> option (task_reference before) with
 | Some current => fun evidence => Some (TaskReference before id current evidence)
 | None => fun _ => None end eq_refl.
