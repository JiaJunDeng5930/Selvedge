From Stdlib Require Import String List Bool.
From Selvedge.Adapters Require Import Common.
Import ListNotations.
Open Scope string_scope.

Record reservation := Reservation { reservation_id : string; reservation_root : string;
 reservation_device : string; reservation_inode : string; reservation_repository : string }.
Definition reservation_json value := JObject [("id",JString value.(reservation_id));
 ("canonical_root",JString value.(reservation_root));("dev",JString value.(reservation_device));
 ("ino",JString value.(reservation_inode));("repository",JString value.(reservation_repository))].
Definition parse_reservation value : option reservation :=
 if is_object value && forallb (fun key => is_text (get value key) && negb (String.eqb (str value key) ""))
   ["id";"canonical_root";"dev";"ino";"repository"]
 then Some (Reservation (str value "id") (str value "canonical_root") (str value "dev") (str value "ino") (str value "repository"))
 else None.

(** The durable representation has one constructor per meaningful resource
    fact. Status text is admitted together with its evidence, never separately. *)
Inductive receipt_stage := UnreservedReceipt | ReservedReceipt (owner : reservation)
 | RegisteredReceipt (owner : reservation) | ReadyReceipt (owner : reservation)
 | ArchivedReceipt (owner : reservation) | ReleasedReceipt (owner : reservation)
 | UnresolvedReceipt (owner : reservation).
Definition decode_receipt_stage (source : json) : option receipt_stage :=
 let phase := str source "local_phase" in let status := str source "status" in
 match parse_reservation (get source "reservation") with
 | None=>if String.eqb phase "unreserved" && String.eqb status "creating" &&
     is_null (get source "reservation") then Some UnreservedReceipt else None
 | Some owner=>
   if String.eqb phase "reserved_unregistered" && String.eqb status "creating" then Some (ReservedReceipt owner)
   else if String.eqb phase "git_registered" && String.eqb status "creating" then Some (RegisteredReceipt owner)
   else if String.eqb phase "ready" && String.eqb status "ready" then Some (ReadyReceipt owner)
   else if String.eqb phase "ready" && String.eqb status "archived" then Some (ArchivedReceipt owner)
   else if String.eqb phase "released" && String.eqb status "released" then Some (ReleasedReceipt owner)
   else if String.eqb phase "needs_resolution" &&
     (String.eqb status "archiving" || String.eqb status "needs_resolution") then Some (UnresolvedReceipt owner)
   else None end.
Definition receipt_stage_valid source := match decode_receipt_stage source with Some _=>true | None=>false end.

Inductive intent := Create | Archive | RecoverCreate | RecoverArchive.
Inductive classification := Missing | OwnedEmpty | Registered | Conflict.
Inductive terminal := Released | CheckoutReady | CheckoutArchived.
Inductive action := Persist | Reserve | Register | Prepare | Classify | Release | Remove | Move | Observe | Finish.
Inductive phase :=
 | InitialPersistence (owner : option reservation)
 | Reserving
 | ReservationPersistence (owner : reservation)
 | Registering (owner : reservation)
 | RegistrationPersistence (owner : reservation)
 | Preparing (owner : reservation)
 | Classifying (owner : option reservation)
 | Releasing (owner : reservation)
 | Removing (owner : reservation)
 | Moving (owner : reservation)
 | Observing (owner : reservation)
 | TerminalPersistence (owner : reservation) (result : terminal)
 | Complete (owner : reservation) (result : terminal)
 | NeedsResolution (owner : option reservation).
Record state := State { operation : intent; metadata : json; current : phase }.
Inductive observation := Persisted | PersistenceFailed | Reserved (owner : reservation)
 | GitRegistered | Prepared (root workspace guidance : json)
 | Classified (value : classification) | Removed | Moved (root workspace : json)
 | Observed (root workspace guidance : json) | Failed.
Record plan := Plan { next_state : state; actions : list action }.
Definition action_name value := match value with Persist=>"persist" | Reserve=>"local_reserve"
 | Register=>"local_create" | Prepare=>"local_prepare" | Classify=>"local_classify"
 | Release=>"local_release" | Remove=>"local_remove" | Move=>"local_archive"
 | Observe=>"local_observe" | Finish=>"finish" end.
Definition intent_name value := match value with Create=>"create" | Archive=>"archive"
 | RecoverCreate=>"recover_create" | RecoverArchive=>"recover_archive" end.
Definition recovering value := match value with RecoverCreate | RecoverArchive=>true | _=>false end.
Definition owner_of value := match value with
 | ReservationPersistence owner | Registering owner | RegistrationPersistence owner | Preparing owner
 | Releasing owner | Removing owner | Moving owner | Observing owner | TerminalPersistence owner _ | Complete owner _=>Some owner
 | InitialPersistence owner | Classifying owner | NeedsResolution owner=>owner | _=>None end.
Definition phase_name value := match value with InitialPersistence _=>"initial_persistence" | Reserving=>"reserving"
 | ReservationPersistence _=>"reservation_persistence" | Registering _=>"registering"
 | RegistrationPersistence _=>"registration_persistence" | Preparing _=>"preparing"
 | Classifying _=>"classifying" | Releasing _=>"releasing" | Removing _=>"removing"
 | Moving _=>"moving" | Observing _=>"observing" | TerminalPersistence _ _=>"terminal_persistence"
 | Complete _ _=>"complete" | NeedsResolution _=>"needs_resolution" end.
Definition terminal_name value := match value with Released=>"released" | CheckoutReady=>"ready" | CheckoutArchived=>"archived" end.
Definition change value phase actions := Plan (State value.(operation) value.(metadata) phase) actions.
Definition finish value phase := change value phase [Finish].
Definition unresolved value := finish value (NeedsResolution (owner_of value.(current))).
Definition acknowledge value owner result := change value (TerminalPersistence owner result) [Persist].
Definition install value root workspace guidance :=
 State value.(operation) (set (set (set value.(metadata) "root" root) "workspace" workspace) "guidance" guidance) value.(current).

(** Every physical action is selected here. In particular, recovery may observe
    an earlier move/release and persist its acknowledgement, but never repeat it. *)
Definition step (value : state) (event : observation) : plan :=
 match value.(current),event with
 | InitialPersistence owner,Persisted =>
   match value.(operation) with Create=>change value Reserving [Reserve]
   | _=>change value (Classifying owner) [Classify] end
 | InitialPersistence _,PersistenceFailed => unresolved value
 | Reserving,Reserved owner => change value (ReservationPersistence owner) [Persist]
 | Reserving,Failed => unresolved value
 | ReservationPersistence owner,Persisted => change value (Registering owner) [Register]
 | RegistrationPersistence owner,Persisted => change value (Preparing owner) [Prepare]
 | ReservationPersistence owner,PersistenceFailed
 | RegistrationPersistence owner,PersistenceFailed
 | Registering owner,Failed | Preparing owner,Failed => change value (Classifying (Some owner)) [Classify]
 | Registering owner,GitRegistered => change value (RegistrationPersistence owner) [Persist]
 | Preparing owner,Prepared root workspace guidance => acknowledge (install value root workspace guidance) owner CheckoutReady
 | Classifying owner,Classified Missing =>
   match owner with Some owner=>acknowledge value owner Released | None=>unresolved value end
 | Classifying (Some owner),Classified OwnedEmpty =>
   match value.(operation) with RecoverCreate | RecoverArchive=>unresolved value
   | _=>change value (Releasing owner) [Release] end
 | Classifying (Some owner),Classified Registered =>
   match value.(operation) with
   | Create=>change value (Removing owner) [Remove]
   | Archive=>change value (Moving owner) [Move]
   | RecoverCreate=>if String.eqb (str value.(metadata) "status") "ready"
       then change value (Observing owner) [Observe] else unresolved value
   | RecoverArchive=>change value (Observing owner) [Observe] end
 | Releasing owner,Removed | Removing owner,Removed => acknowledge value owner Released
 | Moving owner,Moved root workspace => acknowledge (install value root workspace JNull) owner CheckoutArchived
 | Observing owner,Observed root workspace guidance => acknowledge (install value root workspace guidance) owner
     (match value.(operation) with RecoverCreate=>CheckoutReady | _=>CheckoutArchived end)
 | TerminalPersistence owner CheckoutReady,PersistenceFailed =>
   match value.(operation) with Create=>change value (Classifying (Some owner)) [Classify]
   | _=>unresolved value end
 | TerminalPersistence owner result,Persisted => finish value (Complete owner result)
 | _,_ => unresolved value
 end.

Definition persisted_phase value := match value with
 | InitialPersistence None | Reserving=>"unreserved"
 | InitialPersistence (Some _)=>"needs_resolution"
 | ReservationPersistence _ | Registering _=>"reserved_unregistered"
 | RegistrationPersistence _ | Preparing _=>"git_registered"
 | TerminalPersistence _ Released | Complete _ Released=>"released"
 | TerminalPersistence _ _ | Complete _ _=>"ready"
 | _=>"needs_resolution" end.
Definition state_json value :=
 let phase := value.(current) in
 let base := set (set (set value.(metadata) "local_mode" (JString (intent_name value.(operation))))
   "local_control" (JString (phase_name phase))) "local_phase" (JString (persisted_phase phase)) in
 let base := set base "reservation" (match owner_of phase with Some owner=>reservation_json owner | None=>JNull end) in
 match phase with
 | TerminalPersistence _ result | Complete _ result=>set base "status" (JString (terminal_name result))
 | NeedsResolution _=>set base "status" (JString "needs_resolution")
 | _=>base end.
Definition encode_plan value := JObject [("state",state_json value.(next_state));
 ("effects",JArray (map (fun action=>JString (action_name action)) value.(actions)))].
Definition parse_intent source :=
 if String.eqb source "create" then Some Create else if String.eqb source "archive" then Some Archive
 else if String.eqb source "recover_create" then Some RecoverCreate
 else if String.eqb source "recover_archive" then Some RecoverArchive else None.
Definition parse_terminal source :=
 if String.eqb source "released" then Some Released else if String.eqb source "ready" then Some CheckoutReady
 else if String.eqb source "archived" then Some CheckoutArchived else None.
Definition decode_phase source owner : option phase :=
 let tag := str source "local_control" in
 if String.eqb tag "initial_persistence" then Some (InitialPersistence owner)
 else if String.eqb tag "reserving" then Some Reserving
 else if String.eqb tag "classifying" then Some (Classifying owner)
 else if String.eqb tag "needs_resolution" then Some (NeedsResolution owner)
 else match owner with None=>None | Some owner=>
 if String.eqb tag "reservation_persistence" then Some (ReservationPersistence owner)
 else if String.eqb tag "registering" then Some (Registering owner)
 else if String.eqb tag "registration_persistence" then Some (RegistrationPersistence owner)
 else if String.eqb tag "preparing" then Some (Preparing owner)
 else if String.eqb tag "releasing" then Some (Releasing owner)
 else if String.eqb tag "removing" then Some (Removing owner)
 else if String.eqb tag "moving" then Some (Moving owner)
 else if String.eqb tag "observing" then Some (Observing owner)
 else if String.eqb tag "terminal_persistence" then option_map (TerminalPersistence owner) (parse_terminal (str source "status"))
 else if String.eqb tag "complete" then option_map (Complete owner) (parse_terminal (str source "status"))
 else None end.
Definition decode_state source : option state :=
 match parse_intent (str source "local_mode"),decode_phase source (parse_reservation (get source "reservation")) with
 | Some intent,Some phase=>Some (State intent source phase) | _,_=>None end.
Definition decode_observation source : option observation :=
 let kind := str source "kind" in
 if String.eqb kind "persisted" then Some Persisted
 else if String.eqb kind "persistence_failed" then Some PersistenceFailed
 else if String.eqb kind "local_reserved" then option_map Reserved (parse_reservation (get source "reservation"))
 else if String.eqb kind "local_registered" then Some GitRegistered
 else if String.eqb kind "local_created" then Some (Prepared (get source "root") (get source "workspace") (get source "guidance"))
 else if String.eqb kind "local_archived" then Some (Moved (get source "root") (get source "workspace"))
 else if String.eqb kind "local_observed" then Some (Observed (get source "root") (get source "workspace") (get source "guidance"))
 else if String.eqb kind "local_removed" then Some Removed
 else if String.eqb kind "local_classified" then
   let tag := str source "classification" in
   option_map Classified (if String.eqb tag "released" then Some Missing
     else if String.eqb tag "owned_empty" then Some OwnedEmpty
     else if String.eqb tag "registered" then Some Registered
     else if String.eqb tag "conflict" then Some Conflict else None)
 else if String.eqb kind "local_failed" || String.eqb kind "local_remove_failed" then Some Failed else None.
Definition apply source event : option json :=
 match decode_state source,decode_observation event with
 | Some value,Some event=>Some (encode_plan (step value event)) | _,_=>None end.
Definition git_admitted (source : json) :=
 let root := get source "root" in
 negb (boolean_field source "root_symlink") && equal root (get source "canonical_root") &&
 equal root (get source "git_top_level") && boolean_field source "git_link_file" &&
 equal (get source "backlink") (JString (str source "root" ++ "/.git")).
(** A filesystem observation is evidence, not a cleanup command. Only a captured
    identity and an independent Git registration observation establish ownership. *)
Definition local_classification (source : json) :=
  let reservation := get source "reservation" in
  let observations := items (get source "entries") in
  let present := filter (fun entry => boolean_field entry "present") observations in
  let registered_at entry := existsb (fun registration => equal registration (JString ("worktree " ++ str entry "root")))
    (items (get entry "registrations")) in
  let registrations := filter registered_at observations in
  let owned_entry entry := boolean_field entry "directory" && equal (get entry "root") (get entry "canonical_root") &&
    equal (get entry "dev") (get reservation "dev") && equal (get entry "ino") (get reservation "ino") in
  JString (if is_null reservation then "conflict" else
    match present with
    | [] => if Nat.eqb (List.length registrations) 0 then "released" else "conflict"
    | [entry] => if owned_entry entry then
        if boolean_field entry "git_link" then
          if equal (get entry "repository_common_dir") (get entry "checkout_common_dir") &&
             Nat.eqb (List.length registrations) 1 && registered_at entry then "registered" else "conflict"
        else if negb (Nat.eqb (List.length registrations) 0) then "conflict"
        else if equal (get entry "root") (get reservation "canonical_root") && boolean_field entry "empty"
          then "owned_empty" else "conflict"
      else "conflict"
    | _ => "conflict"
    end).

Definition begin source :=
 let receipt := get source "receipt" in
 let intent := if String.eqb (str source "operation") "create" then Create
   else if String.eqb (str source "operation") "recover" then
     if boolean_field source "creating" then RecoverCreate else RecoverArchive
   else Archive in
 let owner := parse_reservation (get receipt "reservation") in
 let previous_status := str receipt "status" in
 let receipt := set receipt "status" (JString (match intent with Create=>"creating" | Archive=>"archiving" | _=>str receipt "status" end)) in
 let value := State intent receipt (Classifying owner) in
 encode_plan (match intent with Create=>change value (InitialPersistence None) [Persist]
 | Archive=>match owner,parse_terminal previous_status with
   Some owner,Some Released=>finish value (Complete owner Released)
   | Some owner,Some CheckoutArchived=>finish value (Complete owner CheckoutArchived)
   | None,_=>unresolved value
   | Some owner,_=>change value (InitialPersistence (Some owner)) [Persist] end
 | _=>change value (Classifying owner) [Classify] end).
