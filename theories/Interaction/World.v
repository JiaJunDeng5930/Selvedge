From Stdlib Require FSets.FMapAVL Structures.OrderedTypeEx.
From Stdlib Require Import String List NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Interaction Require Import Codec.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

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
Definition task_slots world :=
 match bind (field "tasks" world) (field "slots") with
 | Some (JArray _ as slots) => Some slots
 | _ => None end.
Definition task_levels : nat := 8.

Fixpoint task_slot_rows depth value : list json :=
 match depth with
 | O => if is_object value then [value] else []
 | S rest => flat_map (task_slot_rows rest) (value_or [] (as_array value))
 end.
Definition task_rows world :=
 match task_slots world with
 | Some slots => Some (task_slot_rows task_levels slots)
 | None => array_field "tasks" world end.

Fixpoint task_at_slot depth (id : N) source : option json :=
 match depth with
 | O => match natural_field "id" source with
   | Some owner => if N.eqb id owner then Some source else None
   | None => None end
 | S rest =>
   let digit := N.to_nat (N.land (N.shiftr id (4 * N.of_nat rest)) 15) in
   rows <- as_array source;; row <- nth_error rows digit;; task_at_slot rest id row end.
Definition find_task task world :=
 match task_slots world with
 | Some slots => task_at_slot task_levels task slots
 | None => find_world "tasks" "id" task world end.

Fixpoint paired_rows (before after : list json) : list (json * json) :=
 match before, after with
 | [], _ => map (fun row => (JNull, row)) after
 | _, [] => map (fun row => (row, JNull)) before
 | old :: prior, fresh :: next => (old, fresh) :: paired_rows prior next end.
Fixpoint changed_slots depth before after : list (json * json) :=
 if same_reference before after then [] else
 match depth with
 | O => [(before, after)]
 | S rest => flat_map (fun '(old, fresh) => changed_slots rest old fresh)
     (paired_rows (value_or [] (as_array before)) (value_or [] (as_array after))) end.
Definition changed_task_rows before after :=
 match task_slots before, task_slots after with
 | Some old, Some current => changed_slots task_levels old current
 | _, _ => paired_rows (value_or [] (task_rows before)) (value_or [] (task_rows after))
 end.
Definition find_work work world := find_world "works" "work_id" work world.
Definition board_object collection id world :=
 board<-field "board" world;;
 find_world collection "id" id board.
Definition task_belongs work task world := match find_task task world with
 | None=>false
 | Some found=>match work with None=>true|Some work=>match natural_field "work_id" found with
     Some current=>N.eqb current work|None=>false end end end.
