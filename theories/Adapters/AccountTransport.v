From Stdlib Require Import String NArith.
From Selvedge.Adapters Require Import Common.
Open Scope N_scope.

(** Account catalog and audio transport share the same refresh decision. *)
Definition catalog_transport (source : json) :=
  success (JString (if equal (get source "status") (number 401) then "refresh"
    else if boolean_field source "ok" then "success" else "failure")).
