From Stdlib Require Import String List.
Import ListNotations.
Open Scope string_scope.

Fixpoint longest_name (names : list string) : string :=
 match names with
 | [] => ""
 | name :: rest =>
   let longest := longest_name rest in
   if Nat.leb (String.length name) (String.length longest) then longest else name
 end.

(* A nonempty prefix makes this longer than every name already in use. *)
Definition fresh_name (prefix : string) (names : list string) : string :=
 prefix ++ longest_name names.
