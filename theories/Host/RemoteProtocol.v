From Stdlib Require Import String List Bool Ascii NArith ZArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Programming Require Import Schema.
From Selvedge.Foundation Require Import Utf8 RemoteIdentity.
From Selvedge.Programming Require ArgumentDeclaration DeclarationFields.
From Selvedge.Foundation Require KeyedCollection.
Module D := ArgumentDeclaration.
Module F := DeclarationFields.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Open Scope list_scope.

(* JSON access remains at adapter boundaries; admitted protocol values below
   never recover their fields from the input object. *)
Definition get (source : json) (name : string) := match field name source with Some value => value | None => JNull end.
Definition str source name := match get source name with JString value => value | _ => "" end.
Definition num source name := match get source name with JNumber value => match parse_natural value with Some n=>n | None=>0 end | _=>0 end.
Definition number value := JNumber (show_natural value).
Definition items value := match value with JArray values=>values | _=>[] end.
Definition set source name value := match source with JObject fields=>JObject (set_field name value fields) | _=>source end.
Definition shape source names := D.check (D.Object (map (fun name => F.required name D.Any) names)) source.
Definition printable := D.printable.
Definition wire_length := D.utf16_length.
Definition bounded value maximum := D.check (D.Textual (D.PrintableUtf16 1 maximum)) value.
Definition controller value := D.check RemoteIdentity.controller_declaration value.

Definition identifier_declaration := D.Textual (D.PrintableUtf16 1 128).
Definition label_declaration := D.Textual (D.PrintableUtf16 1 80).
Definition receipt_id_declaration := D.Text (D.TextConstraints 1 D.maximum_natural 128 false false false None).
Definition epoch_declaration := D.SafeInteger 1 9007199254740991.
Definition version_declaration := D.SafeInteger 1 1.
Definition rpc_id_declaration := D.Union [identifier_declaration;D.SafeInteger (-9007199254740991) 9007199254740991].
Definition identifier := D.denote identifier_declaration.
Definition identifier_text (value : identifier) := proj1_sig value.
Definition receipt_id := D.denote receipt_id_declaration.
Definition receipt_id_text (value : receipt_id) := proj1_sig value.
Definition rpc_id := D.denote rpc_id_declaration.
Definition epoch_value (value : D.denote epoch_declaration) := Z.to_N (proj1_sig value).
Definition version_value : D.denote version_declaration := exist _ 1%Z eq_refl.
Definition positive value := D.check epoch_declaration value.

(** The two authority coordinates are admitted, stored, and forwarded together. *)
Definition authority_fields := [F.required "controller_id" RemoteIdentity.controller_declaration;
 F.required "grant_epoch" epoch_declaration].
Definition authority_declaration := D.Object authority_fields.
Definition wire_authority := D.denote authority_declaration.
Definition authority_to_fields (value : wire_authority) := proj1_sig value.
Definition authority_from_fields := F.construct authority_fields.
Definition authority_controller value := proj1_sig (fst (authority_to_fields value)).
Definition authority_epoch value := epoch_value (fst (snd (authority_to_fields value))).
Definition same_authority first second := String.eqb (authority_controller first) (authority_controller second) &&
 N.eqb (authority_epoch first) (authority_epoch second).
Definition authority_arguments (value : wire_authority) := value.
Definition decode_authority := D.decode authority_declaration.
Definition encode_authority := D.encode authority_declaration.

Module AuthorityEntry <: KeyedCollection.Entry.
 Definition t := wire_authority.
 Definition key := string.
 Definition key_of := authority_controller.
 Definition key_eq_dec := string_dec.
End AuthorityEntry.
Module AuthoritySet := KeyedCollection.Make AuthorityEntry.
Definition grant_limit (values : AuthoritySet.t) := N.of_nat (AuthoritySet.size values) <=? 64.
Definition grant_set := D.checked grant_limit.
Definition grant_values (value : grant_set) := AuthoritySet.values (proj1_sig value).
Definition no_grants : grant_set := exist _ AuthoritySet.empty eq_refl.
Definition admit_grants values := match AuthoritySet.admit values with
 | Some values => D.admit grant_limit values | None => None end.
Definition grants_declaration := D.Array authority_declaration.
Definition grants_arguments values : D.denote grants_declaration := map authority_arguments (grant_values values).
Definition grants_from_arguments (values : D.denote grants_declaration) :=
 admit_grants (map (fun value => authority_from_fields (proj1_sig value)) values).
Definition decode_grants source := match D.decode grants_declaration source with
 | Some values => grants_from_arguments values | None => None end.
Definition encode_grants value := D.encode grants_declaration (grants_arguments value).

(** Commands remain opaque to the relay. The operation is admitted while every
    member and every number spelling remains owned by the command boundary. *)
Definition operation_declaration := label_declaration.
Definition command_params_fields := [F.required "request_id" receipt_id_declaration;F.required "command" D.RawObject].
Definition request_fields method params := [F.required "id" rpc_id_declaration;
 F.required "method" (D.Const (JString method));F.required "params" params].
Definition command_request_fields := request_fields "command" (D.Object command_params_fields).
Definition snapshot_request_fields := request_fields "snapshot" (D.Object []).
Definition subscribe_request_fields := request_fields "subscribe" (D.Object []).
Definition unsubscribe_request_fields := request_fields "unsubscribe" (D.Object []).
Definition controller_request_declaration := D.Union (map D.Object
 [command_request_fields;snapshot_request_fields;subscribe_request_fields;unsubscribe_request_fields]).
Definition request_command_admitted (value : D.denote controller_request_declaration) := match value with
 | inl values => let params := proj1_sig (fst (snd (snd (proj1_sig values)))) in
     match lookup "op" (fst (snd params)) with
     | Some operation => D.check operation_declaration operation | None => false end
 | _ => true end.
Definition rpc_request := D.checked request_command_admitted.
Definition controller_request_arguments (value : rpc_request) := proj1_sig value.
Definition controller_request_from_arguments := D.admit request_command_admitted.
Definition decode_controller_request source := match D.decode controller_request_declaration source with
 | Some values => controller_request_from_arguments values | None => None end.
Definition encode_controller_request value := D.encode controller_request_declaration (controller_request_arguments value).

Definition diagnostic_declaration := D.Textual (D.PrintableUtf16 1 1024).
Definition error_fields := [F.required "code" label_declaration;F.required "message" diagnostic_declaration].
Definition result_fields := [F.required "id" rpc_id_declaration;F.required "result" D.Any].
Definition failure_fields := [F.required "id" rpc_id_declaration;F.required "error" (D.Object error_fields)].
Definition response_declaration := D.Union [D.Object result_fields;D.Object failure_fields].
Definition rpc_response := D.denote response_declaration.
Definition response_arguments (value : rpc_response) := value.
Definition response_from_arguments (value : D.denote response_declaration) := value.
Definition decode_response := D.decode response_declaration.
Definition encode_response := D.encode response_declaration.

Definition pairing_code_declaration := D.Textual (D.PrintableUtf16 20 128).
Definition pairing_fields := [F.required "code" pairing_code_declaration;F.required "expires_at" epoch_declaration].
Definition pairing_branch := F.declare "type" (JString "pairing") pairing_fields.
Definition pairing_declaration := F.branch_declaration pairing_branch.
Definition pairing_announcement := D.denote pairing_declaration.
Definition pairing_to_fields (value : pairing_announcement) := snd (proj1_sig value).
Definition pairing_from_fields := F.branch_arguments pairing_branch.
Definition pairing_code value := proj1_sig (fst (pairing_to_fields value)).
Definition pairing_expiry value := epoch_value (fst (snd (pairing_to_fields value))).
Definition pairing_arguments (value : pairing_announcement) := value.
Definition decode_pairing := D.decode pairing_declaration.
Definition encode_pairing := D.encode pairing_declaration.

Definition pairing_request_fields := [F.required "request_id" identifier_declaration;
 F.required "controller_id" RemoteIdentity.controller_declaration;F.required "label" label_declaration].
Definition pairing_request_declaration := D.Object pairing_request_fields.
Definition pairing_request := D.denote pairing_request_declaration.
Definition pairing_request_to_fields (value : pairing_request) := proj1_sig value.
Definition pairing_request_from_fields := F.construct pairing_request_fields.
Definition pairing_request_id value := identifier_text (fst (pairing_request_to_fields value)).
Definition pairing_request_controller value := proj1_sig (fst (snd (pairing_request_to_fields value))).
Definition pairing_request_label value := proj1_sig (fst (snd (snd (pairing_request_to_fields value)))).
Definition pairing_request_arguments (value : pairing_request) := value.
Definition decode_pairing_request := D.decode pairing_request_declaration.
Definition encode_pairing_request := D.encode pairing_request_declaration.

Definition version_fields := [F.required "version" version_declaration].
Definition routed_fields payload := F.required "connection_id" identifier_declaration :: payload.
Definition authorized_fields payload := routed_fields (authority_fields ++ payload).
Definition authorized_values payload id authority (values : F.values payload) : F.values (authorized_fields payload) :=
 (id,F.append authority_fields payload (authority_to_fields authority) values).
Definition hello_branch := F.declare "type" (JString "hello") version_fields.
Definition grants_frame_fields := [F.required "grants" grants_declaration].
Definition host_response_fields := routed_fields [F.required "response" response_declaration].
Definition host_event_fields := routed_fields [F.required "event" D.RawObject].
Definition host_grants_branch := F.declare "type" (JString "grants") grants_frame_fields.
Definition host_response_branch := F.declare "type" (JString "response") host_response_fields.
Definition host_event_branch := F.declare "type" (JString "event") host_event_fields.
Definition host_ping_branch := F.declare "type" (JString "ping") [].
Definition host_frame_declaration := D.Union (map F.branch_declaration
 [hello_branch;host_grants_branch;pairing_branch;host_response_branch;host_event_branch;host_ping_branch]).
Inductive host_frame : Type := HostHello | HostGrants (values : grant_set) | HostPairing (value : pairing_announcement)
 | HostResponse (id : identifier) (value : rpc_response) | HostEvent (id : identifier) (value : list (string * json)) | HostPing.
Definition host_frame_arguments value : D.denote host_frame_declaration := match value with
 | HostHello => inl (F.branch_arguments hello_branch [!version_value!])
 | HostGrants values => inr (inl (F.branch_arguments host_grants_branch [!grants_arguments values!]))
 | HostPairing value => inr (inr (inl (pairing_arguments value)))
 | HostResponse id value => inr (inr (inr (inl (F.branch_arguments host_response_branch [!id;response_arguments value!]))))
 | HostEvent id value => inr (inr (inr (inr (inl (F.branch_arguments host_event_branch [!id;value!])))))
 | HostPing => inr (inr (inr (inr (inr (inl (F.branch_arguments host_ping_branch tt)))))) end.
Definition host_frame_from_arguments (value : D.denote host_frame_declaration) : option host_frame := match value with
 | inl _ => Some HostHello
 | inr (inl values) => option_map HostGrants (grants_from_arguments (fst (snd (proj1_sig values))))
 | inr (inr (inl values)) => Some (HostPairing (pairing_from_fields (snd (proj1_sig values))))
 | inr (inr (inr (inl values))) => let values := snd (proj1_sig values) in Some (HostResponse (fst values) (response_from_arguments (fst (snd values))))
 | inr (inr (inr (inr (inl values)))) => let values := snd (proj1_sig values) in Some (HostEvent (fst values) (fst (snd values)))
 | inr (inr (inr (inr (inr (inl _))))) => Some HostPing
 | inr (inr (inr (inr (inr (inr impossible))))) => match impossible with end end.
Definition decode_host_frame source := match D.decode host_frame_declaration source with
 | Some values => host_frame_from_arguments values | None => None end.
Definition encode_host_frame value := D.encode host_frame_declaration (host_frame_arguments value).

Definition relay_ready_branch := F.declare "type" (JString "ready") version_fields.
Definition controller_open_fields := authorized_fields [].
Definition relay_request_fields := authorized_fields [F.required "request" controller_request_declaration].
Definition controller_close_fields := routed_fields [].
Definition relay_pair_request_branch := F.declare "type" (JString "pair_request") pairing_request_fields.
Definition controller_open_branch := F.declare "type" (JString "controller_open") controller_open_fields.
Definition relay_request_branch := F.declare "type" (JString "request") relay_request_fields.
Definition controller_close_branch := F.declare "type" (JString "controller_close") controller_close_fields.
Definition relay_pong_branch := F.declare "type" (JString "pong") [].
Definition relay_frame_declaration := D.Union (map F.branch_declaration
 [relay_ready_branch;relay_pair_request_branch;controller_open_branch;relay_request_branch;controller_close_branch;relay_pong_branch]).
Inductive relay_frame : Set := RelayReady | RelayPairRequest (value : pairing_request)
 | RelayControllerOpen (id : identifier) (authority : wire_authority)
 | RelayRequest (id : identifier) (authority : wire_authority) (request : rpc_request)
 | RelayControllerClose (id : identifier) | RelayPong.
Definition relay_frame_arguments value : D.denote relay_frame_declaration := match value with
 | RelayReady => inl (F.branch_arguments relay_ready_branch [!version_value!])
 | RelayPairRequest value => inr (inl (F.branch_arguments relay_pair_request_branch (pairing_request_to_fields value)))
 | RelayControllerOpen id authority => inr (inr (inl (F.branch_arguments controller_open_branch
   (authorized_values [] id authority tt))))
 | RelayRequest id authority request => inr (inr (inr (inl (F.branch_arguments relay_request_branch
   (authorized_values [F.required "request" controller_request_declaration] id authority [!controller_request_arguments request!])))))
 | RelayControllerClose id => inr (inr (inr (inr (inl (F.branch_arguments controller_close_branch [!id!])))))
 | RelayPong => inr (inr (inr (inr (inr (inl (F.branch_arguments relay_pong_branch tt)))))) end.
Definition relay_frame_from_arguments (value : D.denote relay_frame_declaration) : option relay_frame := match value with
 | inl _ => Some RelayReady
 | inr (inl values) => Some (RelayPairRequest (pairing_request_from_fields (snd (proj1_sig values))))
 | inr (inr (inl values)) => let values := snd (proj1_sig values) in
   Some (RelayControllerOpen (fst values) (authority_from_fields (snd values)))
 | inr (inr (inr (inl values))) => let values := snd (proj1_sig values) in
   let '(authority,request) := F.split authority_fields [F.required "request" controller_request_declaration] (snd values) in
   option_map (RelayRequest (fst values) (authority_from_fields authority)) (controller_request_from_arguments (fst request))
 | inr (inr (inr (inr (inl values)))) => Some (RelayControllerClose (fst (snd (proj1_sig values))))
 | inr (inr (inr (inr (inr (inl _))))) => Some RelayPong
 | inr (inr (inr (inr (inr (inr impossible))))) => match impossible with end end.
Definition decode_relay_frame source := match D.decode relay_frame_declaration source with
 | Some values => relay_frame_from_arguments values | None => None end.
Definition encode_relay_frame value := D.encode relay_frame_declaration (relay_frame_arguments value).

Definition controller_ready_fields := version_fields ++ authority_fields.
Definition controller_event_fields := [F.required "event" D.RawObject].
Definition controller_ready_branch := F.declare "type" (JString "ready") controller_ready_fields.
Definition controller_event_branch := F.declare "type" (JString "event") controller_event_fields.
Definition controller_frame_declaration := D.Union [F.branch_declaration controller_ready_branch;
 F.branch_declaration controller_event_branch;response_declaration].
Definition controller_frame := D.denote controller_frame_declaration.
Definition decode_controller_frame := D.decode controller_frame_declaration.
Definition encode_controller_frame := D.encode controller_frame_declaration.
