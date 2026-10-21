From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json.
Import ListNotations.

Fixpoint select_field (key : string) (fields : list (string * json)) : option (json * list (string * json)) :=
  match fields with [] => None | (name,value)::rest =>
    if String.eqb key name then Some (value,rest) else
    match select_field key rest with Some (selected,remaining) => Some (selected,(name,value)::remaining) | None => None end end.
(** JSON object order is not a domain fact. Arrays and numeric lexemes retain
    their order and spelling; each field occurrence is consumed exactly once. *)
Fixpoint equivalent (lhs rhs : json) : bool := match lhs,rhs with
  | JArray lhs,JArray rhs => (fix values lhs rhs := match lhs,rhs with
    | [],[] => true | x::xs,y::ys => equivalent x y && values xs ys | _,_ => false end) lhs rhs
  | JObject lhs,JObject rhs => (fix fields lhs rhs := match lhs,rhs with
    | [],[] => true | (key,value)::rest,_ => match select_field key rhs with
      | Some (other,remaining) => equivalent value other && fields rest remaining | None => false end
    | _,_ => false end) lhs rhs
  | _,_ => equal lhs rhs end.
