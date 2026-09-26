(* Original association-list definitions and proof, not a reconstruction by
   project tactics. Boolean comparison supplies the relation by reflection. *)
Load "scripts/QuoteCertificate".
From ExtLib Require Import Data.Map.FMapAList.

Definition boolean_relation (K : Type) (same : K -> K -> bool) :=
  fun x y => same x y = true.
Definition boolean_decision (K : Type) (same : K -> K -> bool) :
  RelDec.RelDec (boolean_relation K same) := {| RelDec.rel_dec := same |}.
Definition boolean_correct (K : Type) (same : K -> K -> bool) :
  RelDec.RelDec_Correct (boolean_decision K same) :=
  @RelDec.Build_RelDec_Correct K (boolean_relation K same) (boolean_decision K same)
    (fun x y => conj (fun equality : same x y = true => equality) (fun equality : same x y = true => equality)).

Definition removal_absence (K V : Type) (same : K -> K -> bool) (entries : list (K * V)) (key : K) :
  alist_find (boolean_decision K same) key (alist_remove (boolean_decision K same) key entries) = None :=
  @remove_eq_alist K (boolean_relation K same) (boolean_decision K same) V (boolean_correct K same) entries key.

MetaRocq Run (export (@alist_find)).
MetaRocq Run (export (@alist_remove)).
MetaRocq Run (export (@List.filter)).
MetaRocq Run (export (@remove_eq_alist)).
MetaRocq Run (export (@removal_absence)).
MetaRocq Run (export (@boolean_relation)).
MetaRocq Run (export (@boolean_decision)).
MetaRocq Run (export (@boolean_correct)).
Print Assumptions alist_find.
Print Assumptions alist_remove.
Print Assumptions List.filter.
Print Assumptions remove_eq_alist.
Print Assumptions removal_absence.
Print Assumptions boolean_relation.
Print Assumptions boolean_decision.
Print Assumptions boolean_correct.
