From Stdlib Require Import List Bool NArith.
From Selvedge.Foundation Require Import Constructor Focus Registry.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.

(** A receiver is a path through existing storage. Its address, reader and
    writer are interpretations of that path, never independent declarations. *)
Inductive t : Type -> Type -> Type :=
| Keyed : forall entry, (entry -> N) -> t (list entry) entry
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

Fixpoint address {state input} (selected : t state input) : input -> N :=
 match selected with
 | Keyed _ key => key
 | Indexed _ identity | Ordered _ identity => fun _ => identity
 | Field _ _ _ _ _ child | Focused _ _ _ _ child => address child
 | Inject _ _ _ constructor _ child => fun request => address child (constructor request)
 | InRecord _ _ _ _ child get law constructor _ base => fun request =>
     address child (@set _ _ get (@set_wf _ _ get law) (fun _ => constructor request) base)
 end.
Fixpoint positioned {state input} (selected : t state input) : state -> Prop :=
 match selected with
 | Keyed _ _ => fun _ => True
 | Indexed _ position => fun entries =>
     position = N.of_nat (List.length entries) \/ exists value, registry_at position entries = Some value
 | Ordered _ position => fun entries =>
     position = N.of_nat (List.length (fst entries)) \/ exists value, registry_at position (fst entries) = Some value
 | Field _ _ _ get _ child => fun before => positioned child (get before)
 | Focused _ _ _ focus child => fun before => positioned child (Focus.read focus before)
 | Inject _ _ _ _ _ child | InRecord _ _ _ _ child _ _ _ _ _ => positioned child
 end.
Fixpoint lookup {state input} (selected : t state input) : input -> state -> option input :=
 match selected with
 | Keyed _ key => fun request => find (fun item => N.eqb (key request) (key item))
 | Indexed _ position => fun _ => registry_at position
 | Ordered _ position => fun _ entries => registry_at position (fst entries)
 | Field _ _ _ get _ child => fun request before => lookup child request (get before)
 | Focused _ _ _ focus child => fun request before => lookup child request (Focus.read focus before)
 | Inject _ _ _ constructor view child => fun request before =>
     match lookup child (constructor request) before with
     | Some stored => @Constructor.project _ _ constructor view stored | None => None end
 | InRecord _ _ _ _ child get law constructor view base => fun request before =>
     match lookup child (@set _ _ get (@set_wf _ _ get law) (fun _ => constructor request) base) before with
     | Some stored => @Constructor.project _ _ constructor view (get stored) | None => None end
 end.
Fixpoint install {state input} (selected : t state input) : input -> state -> state :=
 match selected with
 | Keyed _ key => fun request entries =>
     request :: filter (fun item => negb (N.eqb (key request) (key item))) entries
 | Indexed _ position => put_at position
 | Ordered _ position => fun request entries => (put_at position request (fst entries),
     if existsb (N.eqb position) (snd entries) then snd entries else snd entries ++ [position])
 | Field _ _ _ get law child => fun request => @set _ _ get (@set_wf _ _ get law) (install child request)
 | Focused _ _ _ focus child => fun request => Focus.modify focus (install child request)
 | Inject _ _ _ constructor _ child => fun request => install child (constructor request)
 | InRecord _ _ _ _ child get law constructor _ base => fun request =>
     install child (@set _ _ get (@set_wf _ _ get law) (fun _ => constructor request) base)
 end.

(** A located receiver is obtained from an actual selected registry position or
    its append position. The compositional constructors transport that selection;
    protocol declarations never supply a bounds or key-consistency theorem. *)
Record located (state input : Type) (before : state) := Located {
 path : t state input;
 position : positioned path before
}.
Arguments Located {state input before}.
Arguments path {state input before}.
Arguments position {state input before}.

Module At.
Definition keyed {entry} (entries : list entry) (key : entry -> N) : located _ _ entries :=
 Located (Receiver.keyed key) I.
Definition appended {entry} (entries : list entry) : located _ _ entries :=
 Located (indexed (N.of_nat (List.length entries))) (or_introl eq_refl).
Definition existing {entry} (entries : list entry) identity value
 (Found : registry_at identity entries = Some value) : located _ _ entries :=
 Located (indexed identity) (or_intror (ex_intro _ value Found)).
Definition ordered_append {entry} (entries : list entry * list N) : located _ _ entries :=
 Located (ordered (N.of_nat (List.length (fst entries)))) (or_introl eq_refl).
Definition ordered_existing {entry} (entries : list entry * list N) identity value
 (Found : registry_at identity (fst entries) = Some value) : located _ _ entries :=
 Located (ordered identity) (or_intror (ex_intro _ value Found)).
Definition ordered_present {entry} (entries : list (option entry) * list N) identity value
 (Found : (match registry_at identity (fst entries) with Some found => found | None => None end) = Some value)
 : located _ (option entry) entries.
Proof.
 refine (Located (ordered identity) (or_intror _)).
 destruct (registry_at identity (fst entries)) as [stored|] eqn:Stored; [|discriminate].
 exists stored; reflexivity.
Defined.
Definition field {whole part input} (before : whole) (get : whole -> part)
 `{SetterWf whole part get} (selected : located part input (get before)) : located whole input before :=
 Located (Receiver.field get (path selected)) (position selected).
Definition focused {whole part input} (before : whole) (focus : Focus.t whole part)
 (selected : located part input (Focus.read focus before)) : located whole input before :=
 Located (Receiver.focused focus (path selected)) (position selected).
Definition inject {state input row before} (constructor : input -> row)
 `{Constructor.View input row constructor} (selected : located state row before) : located state input before :=
 Located (Receiver.inject constructor (path selected)) (position selected).
Definition in_record {state row field_type input before}
 (selected : located state row before) (get : row -> field_type) `{SetterWf row field_type get}
 (constructor : input -> field_type) `{Constructor.View input field_type constructor}
 (base : row) : located state input before :=
 Located (Receiver.in_record (path selected) get constructor base) (position selected).
End At.
