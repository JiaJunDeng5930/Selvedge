From Stdlib Require Import List NArith.
From Selvedge.Foundation Require IndexedRegistry.
From Selvedge.Kernel Require Import Domain.
Open Scope N_scope.

Record t := ProjectTable {
 rows : IndexedRegistry.t project;
 live : N;
 order : N
}.
Definition empty := ProjectTable IndexedRegistry.empty 0 0.
Definition lookup id table := IndexedRegistry.lookup id (rows table).
Definition next table := IndexedRegistry.next (rows table).
Definition contents table := IndexedRegistry.contents (rows table).
Definition next_order table := N.succ (order table).
Definition live_row count value := if project_deleted value then count else N.succ count.
Definition retired_row count value := if project_deleted value then count else N.pred count.
Definition append value table := ProjectTable (IndexedRegistry.append value (rows table))
 (live_row (live table) value) (N.max (order table) (project_order value)).
Definition put id value table := match lookup id table with
 | None => table
 | Some old => ProjectTable (IndexedRegistry.put id value (rows table))
   (live_row (retired_row (live table) old) value) (N.max (order table) (project_order value))
 end.
Definition from_list values := fold_left (fun current value => append value current) values empty.
