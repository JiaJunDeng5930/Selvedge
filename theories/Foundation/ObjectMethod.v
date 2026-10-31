From Stdlib Require Import String List.
From Selvedge.Foundation Require Import Json ArgumentDeclaration.
Import ListNotations.
Module D := ArgumentDeclaration.

(** An object method consumes the declaration's values directly. Required fields
    are values; optional fields retain presence. There is no raw JSON handler
    which could discard an admitted field and read the source a second time. *)
Fixpoint arguments (fields : list (string * bool * D.t)) (result : Set) : Set :=
 match fields with
 | [] => result
 | (_,required,declaration)::rest =>
   (if required then D.denote declaration else option (D.denote declaration)) -> arguments rest result
 end.
Fixpoint apply {result : Set} (fields : list (string * bool * D.t))
 : arguments fields result -> D.object_values fields -> result :=
 match fields as fields return arguments fields result -> D.object_values fields -> result with
 | [] => fun result _ => result
 | (_,required,declaration)::rest => fun handler values => apply rest (handler (fst values)) (snd values)
 end.
Definition invoke {result : Set} fields (handler : arguments fields result) source :=
 option_map (fun values => apply fields handler (proj1_sig values)) (D.decode (D.OpenObject fields) source).
