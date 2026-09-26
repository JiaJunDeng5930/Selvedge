(* Export existing kernel proof terms, not tactic reconstructions. Regeneration
   requires Rocq and MetaRocq; the normal Bend build checks the saved certificates. *)
Load "scripts/QuoteCertificate".
From Stdlib Require Import Lists.List.
From Stdlib Require Import Arith.PeanoNat.
From Stdlib Require Import Bool.Bool.
MetaRocq Run (export (@list_ind)).
MetaRocq Run (export (@List.app_nil_r)).
MetaRocq Run (export (@List.app_assoc)).
MetaRocq Run (export (@List.fold_left_app)).
MetaRocq Run (export (@List.map_app)).
MetaRocq Run (export (@List.map_map)).
MetaRocq Run (export (@List.map_id)).
MetaRocq Run (export (@nat_ind)).
MetaRocq Run (export (@Nat.iter_swap_gen)).
MetaRocq Run (export (@Nat.iter_add)).
MetaRocq Run (export (@Nat.iter_ind)).
MetaRocq Run (export (@Bool.orb_assoc)).
MetaRocq Run (export (@Bool.orb_comm)).
MetaRocq Run (export (@Bool.orb_diag)).
MetaRocq Run (export (@Bool.orb_false_l)).
MetaRocq Run (export (@Bool.orb_false_r)).
MetaRocq Run (export (@Bool.orb_true_r)).
Print Assumptions list_ind.
Print Assumptions nat_ind.
Print Assumptions List.app_nil_r.
Print Assumptions List.app_assoc.
Print Assumptions List.fold_left_app.
Print Assumptions List.map_app.
Print Assumptions List.map_map.
Print Assumptions List.map_id.
Print Assumptions Nat.iter_swap_gen.
Print Assumptions Nat.iter_add.
Print Assumptions Nat.iter_ind.
Print Assumptions Bool.orb_assoc.
Print Assumptions Bool.orb_comm.
Print Assumptions Bool.orb_diag.
Print Assumptions Bool.orb_false_l.
Print Assumptions Bool.orb_false_r.
Print Assumptions Bool.orb_true_r.
