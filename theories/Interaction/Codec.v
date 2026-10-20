From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
Import ListNotations.
Open Scope string_scope.
Definition bind {A B} (v:option A) (f:A->option B) := match v with Some x => f x | None => None end.
Notation "x <- a ;; b" := (bind a (fun x => b)) (at level 100, a at next level, right associativity).
Definition natural (j:json) := match j with JNumber s => parse_natural s | _ => None end.
Definition natural_field name j := bind (field name j) natural.
Definition required name j := field name j.
Definition number (n:N) := JNumber (show_natural n).
Fixpoint traverse {A B} (f:A->option B) (xs:list A) : option(list B) :=
  match xs with [] => Some [] | x::xs => y <- f x ;; ys <- traverse f xs ;; Some(y::ys) end.
Definition list_field {A} (f:json->option A) name j := xs <- array_field name j ;; traverse f xs.
Definition object_fields (j:json) := match j with JObject fs => fs | _ => [] end.
Definition replace name value j := JObject (set_field name value (object_fields j)).
Definition value_or {A} (fallback:A) (x:option A) := match x with Some x => x | None => fallback end.
Definition text name j := value_or "" (string_field name j).
Definition items name j := value_or [] (array_field name j).
Definition flag name j := value_or false (bool_field name j).
