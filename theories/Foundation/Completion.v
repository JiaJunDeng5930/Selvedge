From Stdlib Require Import NArith.
From Selvedge.Foundation Require Import Constructor Receiver RequestEnvelope.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.

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
    always requires its ticket; a unit pending constructor is addressed by the
    receiver's own identity. *)
Inductive correlation : Type -> Type :=
| Ticket : forall payload, correlation (RequestEnvelope.t payload)
| AtAddress : correlation unit.
Arguments Ticket {payload}.
Definition coordinate {input} (mode : correlation input) : Type :=
 match mode with Ticket => N | AtAddress => unit end.
Definition matches {input} (mode : correlation input) : coordinate mode -> input -> bool :=
 match mode with
 | Ticket => fun ticket request => N.eqb ticket (RequestEnvelope.identity request)
 | AtAddress => fun _ _ => true
 end.

(** Terminal constructors are disjoint from the pending constructor. This is
    computed at the declaration, not a per-feature preservation obligation. *)
Class Retired {input phase} (pending : input -> phase) `{Constructor.View _ _ pending}
 (value : phase) : Prop := retired : Constructor.project pending value = None.
#[global] Hint Extern 2 (Retired _ _) => constructor; reflexivity : typeclass_instances.
Record terminal {input phase} (pending : input -> phase) `{Constructor.View _ _ pending} := Terminal {
 outcome : phase;
 no_receiver : Constructor.project pending outcome = None
}.
Arguments outcome {input phase pending H}.
Arguments no_receiver {input phase pending H}.
Definition done {input phase pending} `{Constructor.View input phase pending}
 (value : phase) `{closed : @Retired input phase pending H value} : terminal pending :=
 @Terminal input phase pending H value (@retired _ _ pending H value closed).

Definition run {state phase input} (selected : slot state phase)
 (pending : input -> phase) `{Constructor.View _ _ pending}
 (mode : correlation input) (address : coordinate mode)
 (finish : input -> terminal pending) (before : state) : bool * state :=
 match observe selected before with
 | Some (current,write) => match Constructor.project pending current with
   | Some request => if matches mode address request
       then (true,write (outcome (finish request)))
       (* DEFENSE: A newer request can replace this ticket before its external
          completion reaches the kernel. *)
       else (false,before)
   (* DEFENSE: A duplicate completion or a completion after cancellation finds
      a phase that has already consumed this request. *)
   | None => (false,before) end
 (* DEFENSE: A retained operation can be forgotten before a late completion. *)
 | None => (false,before) end.
