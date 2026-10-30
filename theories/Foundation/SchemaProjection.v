From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json Schema.
From Selvedge.Foundation Require ArgumentDeclaration ArgumentProjection.
Import ListNotations.

Inductive program (source : schema) : schema -> Set :=
| Empty : program source []
| Column : forall field rest, field_at source field -> program source rest -> program source (field :: rest).
Arguments Empty {source}.
Arguments Column {source field rest} _ _.

Fixpoint select {source} (target : field_spec) (choices : list (projection source))
 : option (field_at source target) := match choices with
 | [] => None
 | existT _ field position :: rest => match field_eq_dec field target with
   | left same => Some (match same in _ = target return field_at source target with eq_refl => position end)
   | right _ => select target rest end end.
Fixpoint compile source target : option (program source target) := match target with
 | [] => Some Empty
 | field :: rest => match select field (projections source),compile source rest with
   | Some position,Some remainder => Some (Column position remainder) | _,_ => None end end.

Class Available source target : Prop := {
 available : ArgumentDeclaration.present (compile source target) = true
}.
Arguments available {source target} {_}.
#[global] Hint Mode Available + + : typeclass_instances.
#[global] Hint Extern 0 (Available _ _) => constructor; reflexivity : typeclass_instances.
Definition declare source target `{Available source target} :=
 ArgumentProjection.compiled (compile source target) available.

Fixpoint apply {source target} (projection : program source target) (values : fields source) : fields target :=
 match projection in program _ target return fields target with
 | Empty => FNil | Column position rest => FCons (Schema.project position values) (apply rest values) end.
Fixpoint prefix {source target} (suffix : schema) (projection : program source target)
 : program (source ++ suffix)%list target := match projection in program _ target return program (source ++ suffix)%list target with
 | Empty => Empty | Column position rest => Column (extend_projection position suffix) (prefix suffix rest) end.

(** Host completion ingress may carry a recovered resource observation rather
    than the full request. Read only this same program's selected source fields. *)
Fixpoint read {source target} (projection : program source target) members : option (fields target) :=
 match projection in program _ target return option (fields target) with
 | Empty => Some FNil
 | @Column _ field _ _ rest => match decode_field field (lookup (field_name field) members),read rest members with
   | Some value,Some remainder => Some (FCons value remainder) | _,_ => None end end.
