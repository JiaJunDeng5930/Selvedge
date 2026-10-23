From Stdlib Require Import String List Bool NArith.
Import ListNotations.
Open Scope string_scope.

(** Temporary activities own a focus occurrence, rather than a reusable DOM
    dialog name. Reopening the same activity must establish its focus again. *)
Inductive scope := Document | Temporary
  (identity initial restore fallback : string) (occurrence : option N).
Definition same_occurrence left right := match left, right with
  | None, None => true | Some a, Some b => N.eqb a b | _, _ => false end.
Definition changed previous current := match previous, current with
  | Document, Document => false
  | Temporary a _ _ _ x, Temporary b _ _ _ y =>
      negb (String.eqb a b && same_occurrence x y)
  | _, _ => true end.
Definition invalid_retained current eligible := match current with
  | Document => false | Temporary _ _ _ _ _ => negb eligible end.
Definition transition previous current eligible :=
  changed previous current || invalid_retained current eligible.
Definition initial current := match current with
  | Document => "page-heading" | Temporary _ target _ _ _ => target end.
Definition restore current := match current with
  | Document => "page-heading" | Temporary _ _ target _ _ => target end.

Record target_observation := ObserveTarget {
  target_key : string; target_aliases : list string; target_view : string
}.
Definition resolve requested preferred_view candidates : option string :=
  match find (fun candidate => String.eqb requested (target_key candidate)) candidates with
  | Some candidate => Some (target_key candidate)
  | None =>
      let aliases := filter (fun candidate =>
        existsb (String.eqb requested) (target_aliases candidate)) candidates in
      match find (fun candidate =>
        String.eqb preferred_view (target_view candidate)) aliases with
      | Some candidate => Some (target_key candidate)
      | None => option_map target_key (hd_error aliases)
      end
  end.

(* DEFENSE: responsive placement can remove a modal's original trigger. The
   owning activity supplies an explicit reachable return target in that case. *)
Definition resolve_return requested fallback preferred_view candidates :=
  match resolve requested preferred_view candidates with
  | Some key => Some key
  | None => resolve fallback preferred_view candidates
  end.
Definition cycle (backward : bool) (current : string) (targets : list string) : option string :=
  let ordered := if backward then rev targets else targets in
  let fix after remaining := match remaining with
    | [] => None
    | key :: rest => if String.eqb current key then hd_error rest else after rest
    end in
  match after ordered with Some key => Some key | None => hd_error ordered end.

Definition fallback current := match current with
 | Document=>"page-heading"|Temporary _ _ _ target _=>target end.

Definition same_scope left right := match left,right with
 |Document,Document=>true
 |Temporary a _ _ _ x,Temporary b _ _ _ y=>String.eqb a b && same_occurrence x y
 |_,_=>false end.
Definition retained_scope_target before current eligible := match current with
 |Temporary identity _ _ _ _=>
   if same_scope before current && negb eligible then identity else initial current
 |Document=>initial current end.
Definition top scopes := match rev scopes with current::_=>current|[]=>Document end.
Definition request previous current eligible : option(string*string) :=
 let before:=top previous in let after:=top current in
 if transition before after eligible then
 let returning:=match after with Document=>true|_=>existsb(same_scope after)previous end in
 if returning && changed before after then Some(restore before,
   match after with Document=>fallback before|_=>initial after end)
 else Some(retained_scope_target before after eligible,fallback after)
 else None.
