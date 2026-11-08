From Stdlib Require Import String List NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Interaction Require Import Codec.
Open Scope string_scope.

Definition find_world collection identity value world :=
 find (fun item=>match natural_field identity item with Some found=>N.eqb value found|None=>false end)
   (items collection world).
Definition find_task task world := find_world "tasks" "id" task world.
Definition find_work work world := find_world "works" "work_id" work world.
Definition board_object collection id world :=
 board<-field "board" world;;
 find_world collection "id" id board.
Definition task_belongs work task world := match find_task task world with
 | None=>false
 | Some found=>match work with None=>true|Some work=>match natural_field "work_id" found with
     Some current=>N.eqb current work|None=>false end end end.
