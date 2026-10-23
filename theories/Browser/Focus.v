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
Definition top scopes := match rev scopes with current::_=>current|[]=>Document end.
Definition request previous current eligible : option(string*string) :=
 let before:=top previous in let after:=top current in
 if transition before after eligible then
 let returning:=match after with Document=>true|_=>existsb(same_scope after)previous end in
 if returning && changed before after then Some(restore before,
   match after with Document=>fallback before|_=>initial after end)
 else Some(initial after,fallback after)
 else None.

(** A loading activity initially focuses its root. When its input arrives, only
    that root may hand focus on; a user's intervening choice keeps ownership. *)
Definition root_handoff previous current focused := match previous,current,focused with
 |Temporary identity old_initial _ _ _,Temporary _ new_initial _ _ _,Some key=>
  same_scope previous current && String.eqb old_initial identity &&
  String.eqb key old_initial && negb(String.eqb old_initial new_initial)
 |_,_,_=>false end.

Definition observed_request previous current eligible focused_before focused_after :=
 match request previous current eligible with
 |Some target=>Some target
 |None=>let before:=top previous in let after:=top current in
  if root_handoff before after focused_after then Some(initial after,fallback after)
  else match after,focused_before,focused_after with
  |Document,Some key,None=>Some(key,key)
  |_,_,_=>None end
 end.
