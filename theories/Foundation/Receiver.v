From Stdlib Require Import List Bool NArith.
From Selvedge.Foundation Require Import Constructor Focus Registry.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.

(** A receiver is a path through existing storage. Its address, reader and
    writer are interpretations of that path, never independent declarations. *)
Inductive t : Type -> Type -> Type :=
| Keyed : forall entry, N -> (entry -> N) -> t (list entry) entry
| Indexed : forall entry, N -> t (list entry) entry
| Ordered : forall entry, N -> t (list entry * list N) entry
| Field : forall whole part input (get : whole -> part),
    SetterWf get -> t part input -> t whole input
| Focused : forall whole part input,
    Focus.t whole part -> t part input -> t whole input
| Inject : forall state input row (constructor : input -> row),
    Constructor.View constructor -> t state row -> t state input
| InRecord : forall state row field_type input,
    t state row -> forall get : row -> field_type, SetterWf get ->
    forall constructor : input -> field_type, Constructor.View constructor -> row -> t state input.

Definition keyed {entry} := Keyed entry.
Definition indexed {entry} := Indexed entry.
Definition ordered {entry} := Ordered entry.
Definition field {whole part input} (get : whole -> part) `{SetterWf whole part get}
 (selected : t part input) := Field whole part input get H selected.
Definition focused {whole part input} (focus : Focus.t whole part)
 (selected : t part input) := Focused whole part input focus selected.
Definition inject {state input row} (constructor : input -> row) `{Constructor.View input row constructor}
 (selected : t state row) := Inject state input row constructor H selected.
Definition in_record {state row field_type input}
 (selected : t state row) (get : row -> field_type) `{SetterWf row field_type get}
 (constructor : input -> field_type) `{Constructor.View input field_type constructor}
 (base : row) := InRecord state row field_type input selected get H constructor H0 base.

Definition put_at {entry} (position : N) (value : entry) (entries : list entry) :=
 if N.eqb position (N.of_nat (List.length entries)) then entries ++ [value]
 else replace position value entries.

Fixpoint address {state input} (selected : t state input) : N :=
 match selected with
 | Keyed _ identity _ | Indexed _ identity | Ordered _ identity => identity
 | Field _ _ _ _ _ child | Focused _ _ _ _ child => address child
 | Inject _ _ _ _ _ child | InRecord _ _ _ _ child _ _ _ _ _ => address child
 end.
Fixpoint available {state input} (selected : t state input) : input -> state -> bool :=
 match selected with
 | Keyed _ identity key => fun request _ => N.eqb identity (key request)
 | Indexed _ position => fun _ entries => N.leb position (N.of_nat (List.length entries))
 | Ordered _ position => fun _ entries => N.leb position (N.of_nat (List.length (fst entries)))
 | Field _ _ _ get _ child => fun request before => available child request (get before)
 | Focused _ _ _ focus child => fun request before => available child request (Focus.read focus before)
 | Inject _ _ _ constructor _ child => fun request => available child (constructor request)
 | InRecord _ _ _ _ child get law constructor _ base =>
     fun request => available child (@set _ _ get (@set_wf _ _ get law) (fun _ => constructor request) base)
 end.
Fixpoint lookup {state input} (selected : t state input) : state -> option input :=
 match selected with
 | Keyed _ identity key => find (fun item => N.eqb identity (key item))
 | Indexed _ position => registry_at position
 | Ordered _ position => fun entries => registry_at position (fst entries)
 | Field _ _ _ get _ child => fun before => lookup child (get before)
 | Focused _ _ _ focus child => fun before => lookup child (Focus.read focus before)
 | Inject _ _ _ constructor view child => fun before =>
     match lookup child before with
     | Some stored => @Constructor.project _ _ constructor view stored | None => None end
 | InRecord _ _ _ _ child get _ constructor view _ => fun before =>
     match lookup child before with
     | Some stored => @Constructor.project _ _ constructor view (get stored) | None => None end
 end.
Fixpoint install {state input} (selected : t state input) : input -> state -> state :=
 match selected with
 | Keyed _ identity key => fun request entries =>
     request :: filter (fun item => negb (N.eqb identity (key item))) entries
 | Indexed _ position => put_at position
 | Ordered _ position => fun request entries => (put_at position request (fst entries),
     if existsb (N.eqb position) (snd entries) then snd entries else snd entries ++ [position])
 | Field _ _ _ get law child => fun request => @set _ _ get (@set_wf _ _ get law) (install child request)
 | Focused _ _ _ focus child => fun request => Focus.modify focus (install child request)
 | Inject _ _ _ constructor _ child => fun request => install child (constructor request)
 | InRecord _ _ _ _ child get law constructor _ base => fun request =>
     install child (@set _ _ get (@set_wf _ _ get law) (fun _ => constructor request) base)
 end.
