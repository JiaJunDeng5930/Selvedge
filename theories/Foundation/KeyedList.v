From Stdlib Require Import List Bool.

(* The entry relation observes the first retained value at the old entry's key.
   Keys and value projections belong to the domain; the traversal is shared. *)
Definition retains {Entry Key Value : Type} (key : Entry -> Key)
 (lookup : Key -> list Entry -> option Value) (relation : Entry -> option Value -> bool)
 (before after : list Entry) :=
 forallb (fun previous => relation previous (lookup (key previous) after)) before.
