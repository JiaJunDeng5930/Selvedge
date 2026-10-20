From Stdlib Require Import String List NArith.
From Selvedge.Foundation Require Import Utf8.
Open Scope N_scope.

(** Browser and account protocols measure these limits in UTF-16 code units. *)
Definition utf16_units (text : string) : option N := match Utf8.decode text with
  | Some values => Some (fold_left (fun count code => count + if code <? 65536 then 1 else 2) values 0)
  | None => None end.
