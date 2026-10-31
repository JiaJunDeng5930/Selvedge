From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json Schema DeclarationRegistry.
From Selvedge.Kernel Require CallbackDeclarations.
Import ListNotations.
Open Scope string_scope.

(** A public input chooses one registered grammar. Its name is part of that
    grammar, and the receiver sees only values admitted by that grammar. *)
Inductive syntax :=
| Object (name : string) (body : schema)
    (distinct : unique_names ("kind" :: map field_name body) = true)
| Callback (description : CallbackDeclarations.callback_kind).
Definition name (form : syntax) := match form with
 | Object name _ _ => name
 | Callback description => CallbackDeclarations.callback_text description end.
Definition values (form : syntax) : Type := match form with
 | Object _ body _ => Schema.fields body
 | Callback description => CallbackDeclarations.decoded description end.
Definition admit (form : syntax) : json -> option (values form) := match form with
 | Object name body _ => fun source =>
   option_map (@Schema.tail (Field "kind" (KEnum name [])) body)
     (Schema.decode (Field "kind" (KEnum name []) :: body) source)
 | Callback description => CallbackDeclarations.decode description end.

Record t (A : Type) := Entry {
 language : syntax;
 receive : values language -> option A
}.
Arguments Entry {A}.
Arguments language {A}.
Arguments receive {A}.
Definition identity {A} (entry : t A) := name (language entry).
Definition object {A} name body (handle : Schema.fields body -> option A)
 `{DistinctNames ("kind" :: map field_name body)} : t A :=
 Entry (Object name body names_distinct) handle.
Definition callback {A} description
 (handle : CallbackDeclarations.decoded description -> option A) : t A :=
 Entry (Callback description) handle.
Definition map {A B} (change : A -> B) (entry : t A) : t B :=
 Entry (language entry) (fun fields => option_map change (receive entry fields)).
Definition decode_entry {A} (entry : t A) source :=
 match admit (language entry) source with
 | Some fields => receive entry fields | None => None end.
Definition selected {A} (entries : DeclarationRegistry.t (@identity A)) source :=
 match string_field "kind" source with
 | Some name => DeclarationRegistry.lookup name entries | None => None end.
Definition decode {A} (entries : DeclarationRegistry.t (@identity A)) source :=
 match selected entries source with
 | Some entry => decode_entry entry source | None => None end.
