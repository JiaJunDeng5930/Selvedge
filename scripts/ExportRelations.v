(* Existing relation theory, followed by explicit theorem applications. There
   are no project inductions or tactic reconstructions in these applications. *)
Load "scripts/QuoteCertificate".
From Stdlib Require Import Relations.Relation_Definitions Relations.Relation_Operators Relations.Operators_Properties.

Definition closure_map (A B : Type) (R : relation A) (S : relation B)
  (f : A -> B)
  (one : forall x y, R x y -> clos_refl_trans B S (f x) (f y))
  (x y : A) (path : clos_refl_trans A R x y) :
  clos_refl_trans B S (f x) (f y) :=
  clos_refl_trans_ind A R
    (fun x y => clos_refl_trans B S (f x) (f y)) one
    (fun x => rt_refl B S (f x))
    (fun x y z _ left _ right => rt_trans B S (f x) (f y) (f z) left right)
    x y path.

Definition closure_invariant (A : Type) (R : relation A) (P : A -> Prop)
  (one : forall x y, P x -> R x y -> P y)
  (x y : A) (path : clos_refl_trans A R x y) (seed : P x) : P y :=
  clos_refl_trans_ind_left A R x P seed
    (fun y z _ valid edge => one y z valid edge) y path.

MetaRocq Run (export (@relation)).
MetaRocq Run (export (@inclusion)).
MetaRocq Run (export (@clos_refl_trans_ind)).
MetaRocq Run (export (@clos_refl_trans_ind_left)).
MetaRocq Run (export (@clos_rt_is_preorder)).
MetaRocq Run (export (@clos_rt_idempotent)).
MetaRocq Run (export (@closure_map)).
MetaRocq Run (export (@closure_invariant)).
Print Assumptions relation.
Print Assumptions inclusion.
Print Assumptions clos_refl_trans_ind.
Print Assumptions clos_refl_trans_ind_left.
Print Assumptions clos_rt_is_preorder.
Print Assumptions clos_rt_idempotent.
Print Assumptions closure_map.
Print Assumptions closure_invariant.
