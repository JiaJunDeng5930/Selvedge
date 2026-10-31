From Stdlib Require Import String List.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import ArgumentDeclaration Schema.
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

Definition project fields {result : Set} (handler : arguments fields result)
 (values : D.denote (D.OpenObject fields)) := apply fields handler (proj1_sig values).

(** The declaration determines each handler's argument types. Invocation decodes
    once and supplies those values; operations cannot reread an unchecked source. *)
Record operation := Operation {
 operation_name : string;
 operation_fields : list (string * bool * D.t);
 operation_run : arguments operation_fields json;
 operation_error : string;
 operation_names : Schema.DistinctNames (map (fun field => fst (fst field)) operation_fields)
}.
Definition diagnostic_method name fields handler message
 `{Schema.DistinctNames (map (fun field => fst (fst field)) fields)} :=
 Operation name fields handler message H.
