From Stdlib Require Import String List Bool NArith ZArith.
From Selvedge.Foundation Require Import Json Schema Arguments.
From Selvedge.Foundation Require ArgumentDeclaration.
Import ListNotations.
Module D := ArgumentDeclaration.

(** A projection is compiled from the declared syntax. The generated command
    constructor can only use a projection whose compilation succeeds. *)
Fixpoint alternatives {A : Set}
 (atomic : forall declaration, option (D.denote declaration -> A))
 (declaration : D.t) : option (D.denote declaration -> A) :=
 match declaration as declaration return option (D.denote declaration -> A) with
 | D.Reject => Some (fun impossible : D.denote D.Reject => match impossible with end)
 | D.Union choices =>
   (fix compile (choices : list D.t) : option (D.denote (D.Union choices) -> A) :=
    match choices as choices return option (D.denote (D.Union choices) -> A) with
    | [] => Some (fun impossible : D.denote (D.Union []) => match impossible with end)
    | first :: rest => match alternatives atomic first, compile rest with
      | Some head, Some tail => Some (fun value => match value with
        | inl value => head value | inr value => tail value end)
      | _, _ => None end
    end) choices
 | other => atomic other end.

Definition scalar (target : kind)
 (fallback : forall declaration, option (D.denote declaration -> Schema.denote target))
 (declaration : D.t) : option (D.denote declaration -> Schema.denote target) :=
 match declaration as declaration return option (D.denote declaration -> Schema.denote target) with
 | D.Const value => option_map (fun value _ => value) (Schema.decode_value target value)
 | D.Value source => match Schema.kind_eq_dec source target with
   | left same => Some (fun value => match same in _ = target return Schema.denote target with
     | eq_refl => value end)
   | right _ => fallback (D.Value source) end
 | other => fallback other end.

Fixpoint compile (target : kind) (declaration : D.t)
 : option (D.denote declaration -> Schema.denote target) :=
 alternatives (scalar target
   (match target as target return forall declaration,
     option (D.denote declaration -> Schema.denote target) with
   | KJson => fun declaration => Some (D.encode declaration)
   | KText => fun declaration => match declaration as declaration return
       option (D.denote declaration -> string) with
     | D.Textual format => Some (D.encode_text format)
     | D.Value (KEnum _ _) => Some (fun value => proj1_sig value)
     | _ => None end
   | KNatural => fun declaration => match declaration as declaration return
       option (D.denote declaration -> N) with
     | D.Natural _ _ | D.UnboundedNatural _ => Some (fun value => proj1_sig value)
     | _ => None end
   | KInteger => fun declaration => match declaration as declaration return
       option (D.denote declaration -> Z) with
     | D.SafeInteger _ _ => Some (fun value => proj1_sig value)
     | _ => None end
   | KBool | KDecimal | KEnum _ _ => fun _ => None
   | KArray element => fun declaration => match declaration as declaration return
       option (D.denote declaration -> list (Schema.denote element)) with
     | D.Array source => option_map (fun project => map project) (compile element source)
     | D.BoundedArray _ _ source => option_map
       (fun project values => map project (proj1_sig values)) (compile element source)
     | D.Value (KArray source) => option_map (fun project => map project)
       (compile element (D.Value source))
     | _ => None end
   | KOptional element => fun declaration => match declaration as declaration return
       option (D.denote declaration -> option (Schema.denote element)) with
     | D.Null => Some (fun _ => None)
     | D.Value (KOptional source) => option_map (fun project => option_map project)
       (compile element (D.Value source))
     | other => option_map (fun project value => Some (project value)) (compile element other)
     end
   end)) declaration.

Definition argument_value (argument : argument_spec) :=
 if argument_required argument then D.denote (type_declaration (argument_type_of argument))
 else option (D.denote (type_declaration (argument_type_of argument))).
Definition compile_field (field : field_spec) (argument : argument_spec)
 : option (argument_value argument -> field_value field) :=
 if String.eqb (field_name field) (argument_name argument) then
 match compile (field_representation field) (type_declaration (argument_type_of argument)) with
 | None => None
 | Some project =>
   match argument_required argument as required return
     option ((if required then D.denote (type_declaration (argument_type_of argument))
              else option (D.denote (type_declaration (argument_type_of argument)))) -> field_value field) with
   | true => Some project
   | false => match missing_value (field_representation field) with
     | Some absent => Some (fun value => match value with Some value => project value | None => absent end)
     | None => None end
   end
 end else None.
Definition compiled {A : Set} (result : option A) : D.present result = true -> A :=
 match result as result return D.present result = true -> A with
 | Some value => fun _ => value
 | None => fun impossible => False_rect _ (Bool.diff_false_true impossible) end.
Definition field (description : field_spec) (argument : argument_spec)
 (ready : D.present (compile_field description argument) = true) :=
 compiled (compile_field description argument) ready.
