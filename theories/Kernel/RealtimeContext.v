From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Schema.
From Selvedge.Programming Require ArgumentDeclaration.
From Selvedge.Kernel Require Import Numbers.
Import ListNotations.
Open Scope string_scope.

Inductive source := CurrentTime | TaskElapsedTime.
Definition defaults := [CurrentTime; TaskElapsedTime].
Definition name (value : source) :=
 match value with CurrentTime => "current_time" | TaskElapsedTime => "task_elapsed_time" end.
Definition sources_json (values : list source) := JArray (map (fun value => JString (name value)) values).
Definition source_kind := KArray (KEnum (name CurrentTime) [name TaskElapsedTime]).
Definition declaration := ArgumentDeclaration.Value source_kind.
Definition from_names (values : list string) :=
 filter (fun source => existsb (String.eqb (name source)) values) defaults.

Definition from_values (values : ArgumentDeclaration.denote declaration) :=
 from_names (map (fun value => proj1_sig value) values).
Definition parse_sources value := option_map from_values (ArgumentDeclaration.decode declaration value).

Definition reading (now started : N) (current : string) (value : source) :=
 match value with
 | CurrentTime => "Current time (UTC): " ++ current
 | TaskElapsedTime => "Time since task start: " ++ Numbers.number_text (N.sub now started) ++ " ms"
 end.
Definition observed_text (sources observation : json) : option string :=
 match parse_sources sources, natural_field "now" observation,
       natural_field "started_at" observation, field "current_time" observation with
 | Some (first :: rest), Some now, Some started, Some (JString current) =>
   Some (String.concat "
" (map (reading now started current) (first :: rest)))
 | _,_,_,_ => None end.
