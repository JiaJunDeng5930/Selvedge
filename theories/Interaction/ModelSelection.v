From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain Codec Tasks.
Import ListNotations.
Open Scope string_scope.

Definition observed_profile world key :=
  match find (fun value => String.eqb (text_default "key" value "") key)
    (array_default "profiles" world) with
  | Some value => Codec.parse_profile value | None => None end.
Definition permitted world key effort :=
  match observed_profile world key with
  | Some value => match Tasks.selected_reasoning (Some effort) value with Some _ => true | None => false end
  | None => false end.
Definition valid_preference world value := permitted world (fst value) (snd value).
Definition selected_effort world key previous :=
  if permitted world key previous then previous else "default".
Definition preference_json (value : string * string) :=
  JObject [("profile", JString (fst value)); ("reasoning", JString (snd value))].
Definition decode_preference value :=
  match string_field "profile" value, string_field "reasoning" value with
  | Some profile, Some effort => Some (profile, effort) | _, _ => None end.
Definition reasoning_values world key :=
  match observed_profile world key with
  | Some profile => match profile_policy profile with
    | AdaptivePolicy _ => ["default"; "auto"]
    | FixedReasoning => match profile_reasoning_options profile with
      | [] => [] | values => "default" :: values end end
  | None => [] end.
