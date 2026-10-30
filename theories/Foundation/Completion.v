From Stdlib Require Import List NArith.
From Selvedge.Foundation Require Import Constructor OptionList Receiver RequestEnvelope.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.

(** Completion targets a fixed receiver address. The address is derived by
    reducing the receiver path; a declaration cannot route its terminal value
    to a different owner. *)
Class Addressed {state input} (path : Receiver.t state input) := {
 identity : N;
 fixed_address : forall input, Receiver.address path input = identity
}.
Arguments identity {state input path} {_}.
Arguments fixed_address {state input path} {_} _.
#[global] Hint Extern 2 (Addressed _) =>
 unshelve refine {| identity := _; fixed_address := _ |};
 [| intro; cbn; reflexivity] : typeclass_instances.

(** Only the selected phase may change. Record reception obtains the base from
    the receiver itself, so a caller cannot supply another job's frozen data. *)
Inductive slot (state phase : Type) : Type :=
| Direct : forall path : Receiver.t state phase, Addressed path -> slot state phase
| Field : forall row (path : Receiver.t state row), Addressed path ->
    forall get : row -> phase, SetterWf get -> slot state phase.
Arguments Direct {state phase}.
Arguments Field {state phase row}.
Definition direct {state phase} (path : Receiver.t state phase) `{Addressed _ _ path} :=
 Direct path H.
Definition field {state phase row} (path : Receiver.t state row) `{Addressed _ _ path}
 (get : row -> phase) `{SetterWf _ _ get} := Field path H get H0.

Definition observe {state phase} (selected : slot state phase) (before : state)
 : option (phase * (phase -> state)) :=
 match selected with
 | Direct path address =>
   match Receiver.read_at path (@identity _ _ path address) before with
   | Some current => Some (current,fun next => Receiver.install path next before)
   | None => None end
 | Field path address get law =>
   match Receiver.read_at path (@identity _ _ path address) before with
   | Some current => Some (get current,fun next => Receiver.install path
       (@set _ _ get (@set_wf _ _ get law) (fun _ => next) current) before)
   | None => None end
 end.
Definition read {state phase} (selected : slot state phase) before :=
 option_map fst (observe selected before).

(** These are correlation mechanisms, not a list of feature names. An envelope
    always requires its ticket. Owner reception explicitly stores an owned
    payload; nullary phases need only the receiver's own identity. *)
Inductive correlation : Type -> Type :=
| Ticket : forall payload, correlation (RequestEnvelope.t payload)
| Owner : forall payload, correlation (RequestEnvelope.owned payload)
| AtAddress : correlation unit.
Arguments Ticket {payload}.
Arguments Owner {payload}.
Definition coordinate {input} (mode : correlation input) : Type :=
 match mode with Ticket => N | Owner | AtAddress => unit end.
Definition matches {input} (mode : correlation input) : coordinate mode -> input -> bool :=
 match mode with
 | Ticket => fun ticket request => N.eqb ticket (RequestEnvelope.identity request)
 | Owner => fun _ _ => true
 | AtAddress => fun _ _ => true
 end.

(** Terminal constructors are disjoint from the pending constructor. This is
    computed at the declaration, not a per-feature preservation obligation. *)
Class Retired {input phase} (pending : input -> phase) `{Constructor.Case _ _ pending}
 (value : phase) : Prop := retired : Constructor.recognize pending value = None.
#[global] Hint Extern 2 (Retired _ _) => constructor; reflexivity : typeclass_instances.
Record terminal {input phase} (pending : input -> phase) `{Constructor.Case _ _ pending} := Terminal {
 outcome : phase;
 no_receiver : Constructor.recognize pending outcome = None
}.
Arguments outcome {input phase pending H}.
Arguments no_receiver {input phase pending H}.
Definition done {input phase pending} `{Constructor.Case input phase pending}
 (value : phase) `{closed : @Retired input phase pending H value} : terminal pending :=
 @Terminal input phase pending H value (@retired _ _ pending H value closed).

Definition candidate {phase input} (pending : input -> phase) `{Constructor.Case _ _ pending}
 (mode : correlation input) (address : coordinate mode) (current : phase) : option input :=
 match Constructor.recognize pending current with
 | Some request => if matches mode address request then Some request
   (* DEFENSE: A newer request can replace this ticket before its external
      completion reaches the kernel. *)
   else None
 (* DEFENSE: A duplicate completion or a completion after cancellation finds
    a phase that has already consumed this request. *)
 | None => None end.
Definition run {state phase input} (selected : slot state phase)
 (pending : input -> phase) `{Constructor.Case _ _ pending}
 (mode : correlation input) (address : coordinate mode)
 (finish : input -> terminal pending) (before : state) : bool * state :=
 match observe selected before with
 | Some (current,write) => match candidate pending mode address current with
   | Some request => (true,write (outcome (finish request)))
   | None => (false,before) end
 (* DEFENSE: A retained operation can be forgotten before a late completion. *)
 | None => (false,before) end.

Module Row.
(** Related fields may change atomically with the phase. Assignments name
    actual record projections; they cannot replace a whole world or registry. *)
Inductive assignment (row : Type) : Type :=
| Assign : forall field (get : row -> field), SetterWf get -> field -> assignment row.
Arguments Assign {row field}.
Definition assign {row field} (get : row -> field) `{SetterWf _ _ get} value := Assign get H value.
Definition apply_one {row} (change : assignment row) (current : row) :=
 match change with Assign get law value => @set _ _ get (@set_wf _ _ get law) (fun _ => value) current end.
Definition apply {row} (changes : list (assignment row)) current :=
 fold_left (fun row change => apply_one change row) changes current.
Record amendment (row : Type) {input phase} (pending : input -> phase) `{Constructor.Case _ _ pending} := Amend {
 assignments : list (assignment row);
 conclusion : terminal pending
}.
Arguments Amend {row input phase pending H}.
Arguments assignments {row input phase pending H}.
Arguments conclusion {row input phase pending H}.
Definition finish {row phase input pending view} (get : row -> phase) `{setter : SetterWf _ _ get}
 (change : @amendment row input phase pending view) current :=
 @set _ _ get (@set_wf _ _ get setter) (fun _ => outcome (conclusion change))
   (apply (assignments change) current).

(** The receipt retains the observed request and the selected row, rather than
    an independently supplied successor state. A later request is issued from
    [after]; the consumed request remains available for its unique continuation. *)
Record receipt {state row phase input} (path : Receiver.t state row) (location : Addressed path)
 (get : row -> phase) (setter : SetterWf get) (pending : input -> phase) (view : Constructor.Case pending)
 (mode : correlation input) (address : coordinate mode)
 (choose : row -> input -> option (@amendment row input phase pending view)) (before : state) := Receipt {
 previous : row;
 request : input;
 change : @amendment row input phase pending view;
 observed : Receiver.read_at path (@identity _ _ path location) before = Some previous;
 admitted : @candidate _ _ pending view mode address (get previous) = Some request;
 selected : choose previous request = Some change
}.
Arguments receipt {state row phase input} path {location} get {setter} pending {view} mode address choose before.
Arguments previous {state row phase input path location get setter pending view mode address choose before}.
Arguments request {state row phase input path location get setter pending view mode address choose before}.
Arguments change {state row phase input path location get setter pending view mode address choose before}.
Arguments observed {state row phase input path location get setter pending view mode address choose before}.
Arguments admitted {state row phase input path location get setter pending view mode address choose before}.
Arguments selected {state row phase input path location get setter pending view mode address choose before}.
Definition updated {state row phase input path location get setter pending view mode address choose before}
 (received : @receipt state row phase input path location get setter pending view mode address choose before) :=
 finish get (change received) (previous received).
Definition after {state row phase input path location get setter pending view mode address choose before}
 (received : @receipt state row phase input path location get setter pending view mode address choose before) :=
 Receiver.install path (updated received) before.
Definition consume {state row phase input} (path : Receiver.t state row) `{location : Addressed _ _ path}
 (get : row -> phase) `{setter : SetterWf _ _ get} (pending : input -> phase) `{view : Constructor.Case _ _ pending}
 (mode : correlation input) (address : coordinate mode)
 (choose : row -> input -> option (amendment row pending)) (before : state)
 : option (receipt path get pending mode address choose before) :=
 OptionList.observe (Receiver.read_at path (@identity _ _ path location) before)
   (fun current Observed =>
     OptionList.observe (candidate pending mode address (get current))
       (fun request Admitted => OptionList.observe (choose current request)
         (fun change Selected => Some
           (@Receipt state row phase input path location get setter pending view mode address choose before
             current request change Observed Admitted Selected)) (fun _ => None))
       (fun _ => None))
   (* DEFENSE: A retained operation can be forgotten before a late completion. *)
   (fun _ => None).
End Row.
