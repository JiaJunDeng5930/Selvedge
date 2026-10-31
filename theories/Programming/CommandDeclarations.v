From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Schema Arguments.
From Selvedge.Kernel Require Import Commands.
From Selvedge.Programming Require Import CommandFields.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

(** The public and observed languages share one field declaration. A host
    observation has no slot in the public interpretation. Callers supply the
    declarations and handlers interpreted below. *)
Definition command_arguments (observed : bool) (declaration : Commands.command_declaration) :=
 let wire := Commands.declared_wire declaration in let name := wire_name wire in
 Commands.command_argument name (Field "op" (KEnum name [])) ::
 map (fun field => field_argument observed field
   (Commands.command_argument name (field_shape field)))
   (filter (fun field => observed || negb (field_host_observed field)) (wire_fields wire)).
Definition command_schema (declaration : Commands.command_declaration) :=
 Arguments.json_schema (command_arguments false declaration).
Fixpoint invocation (observed : bool) (declarations : list Commands.command_declaration) : Set :=
 match declarations with [] => Empty_set | declaration :: rest =>
 (Arguments.parsed_arguments (command_arguments observed declaration) + invocation observed rest)%type end.
Fixpoint decode_invocation (observed : bool) (declarations : list Commands.command_declaration)
 (name : string) (source : json) : option (invocation observed declarations) :=
 match declarations as declarations return option (invocation observed declarations) with
 | [] => None
 | declaration :: rest =>
   if String.eqb name (wire_name (Commands.declared_wire declaration))
   then option_map inl (Arguments.decode_arguments (command_arguments observed declaration) source)
   else option_map inr (decode_invocation observed rest name source)
 end.
Fixpoint encode_invocation (observed : bool) (declarations : list Commands.command_declaration)
 : invocation observed declarations -> json :=
 match declarations as declarations return invocation observed declarations -> json with
 | [] => fun impossible => match impossible with end
 | declaration :: rest => fun value => match value with
   | inl value => Arguments.encode_arguments (command_arguments observed declaration) value
   | inr value => encode_invocation observed rest value end
 end.
Fixpoint interpretations (observed : bool) (declarations : list Commands.command_declaration) (A : Type) : Type :=
 match declarations with [] => unit | declaration :: rest =>
 ((Arguments.parsed_arguments (command_arguments observed declaration) -> A) * interpretations observed rest A)%type end.
Fixpoint interpret {A : Type} (observed : bool) (declarations : list Commands.command_declaration)
 : interpretations observed declarations A -> invocation observed declarations -> A :=
 match declarations as declarations return
   interpretations observed declarations A -> invocation observed declarations -> A with
 | [] => fun _ impossible => match impossible with end
 | declaration :: rest => fun handlers value => match value with
   | inl value => fst handlers value | inr value => interpret observed rest (snd handlers) value end
 end.
