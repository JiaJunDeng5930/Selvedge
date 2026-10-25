From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json TextJson.
From Selvedge.Kernel Require Import State Observation Limits.
Definition fits_json (value : json) :=
 N.leb (N.of_nat (String.length (TextJson.render_json value))) Limits.frame_bytes.
Definition fits (durable : bool) (value : decision) := fits_json (Observation.envelope durable value).
Definition deliver_with_status (durable : bool) (value : decision) (previous : world) :=
 if fits durable value then (true,value) else
 (false,reject "output_limit" "The complete decision exceeds the native output bound; no state change or effect was committed" previous).
Definition deliver (durable : bool) (value : decision) (previous : world) :=
 snd (deliver_with_status durable value previous).
