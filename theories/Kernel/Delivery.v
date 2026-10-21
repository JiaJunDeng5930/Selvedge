From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json TextJson.
From Selvedge.Kernel Require Import State Observation Limits.
Definition fits (durable : bool) (value : decision) :=
 N.leb (N.of_nat (String.length (TextJson.render_json (Observation.envelope durable value)))) Limits.frame_bytes.
Definition deliver (durable : bool) (value : decision) (previous : world) :=
 if fits durable value then value else
 reject "output_limit" "The complete decision exceeds the native output bound; no state change or effect was committed" previous.
