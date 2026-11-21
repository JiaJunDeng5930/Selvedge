From Stdlib Require FSets.FMapAVL Structures.OrderedTypeEx.
From Stdlib Require Import String List NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Interaction Require Import Codec.
Open Scope string_scope.

Module IdMap := FMapAVL.Make OrderedTypeEx.N_as_OT.
(* First observations have the same precedence as find_world. *)
Definition index_world collection identity world :=
 fold_right (fun item index=>match natural_field identity item with
 |Some id=>IdMap.add id item index|None=>index end)
 (IdMap.empty json) (items collection world).
Definition indexed_lookup collection identity world :=
 let index:=index_world collection identity world in fun id=>IdMap.find id index.
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
