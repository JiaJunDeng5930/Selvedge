From Stdlib Require Import String List NArith Numbers.DecimalString.
From Selvedge.Foundation Require Import Json.
From Selvedge.Foundation Require Export Numbers.
Open Scope N_scope.

Definition number_text := Selvedge.Foundation.Numbers.show_natural.
Definition number (value : N) : json := JNumber (number_text value).
Definition natural (value : json) : option N :=
 match value with JNumber source => Selvedge.Foundation.Numbers.parse_natural source | _ => None end.
Definition natural_field (key : string) (value : json) : option N :=
  match field key value with Some n => natural n | None => None end.

From Selvedge.Foundation Require Export Registry.
