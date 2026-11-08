From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json.
Import ListNotations.
Open Scope string_scope.

(** Commands for trusted speech observations are produced by their live
    upstream sessions. Public inputs use the same rule at every entry. *)
Definition public_operation_allowed (operation : string) :=
 negb (existsb (String.eqb operation)
   ["record_speech_transcript"; "accept_speech_delegation"]).

Inductive feedback := Accepted (result : json) | Refused (diagnostic : json).

Definition feedback_of (reply : json) : option feedback :=
 match bool_field "ok" reply with
 | Some true => option_map Accepted (field "result" reply)
 | Some false => option_map Refused (field "error" reply)
 | None => None
 end.

Definition accepted (reply : json) : bool :=
 match feedback_of reply with Some (Accepted _) => true | _ => false end.
Definition result (reply : json) : option json :=
 match feedback_of reply with Some (Accepted value) => Some value | _ => None end.
Definition refusal (reply : json) : json :=
 match feedback_of reply with Some (Refused diagnostic) => diagnostic | _ => reply end.
