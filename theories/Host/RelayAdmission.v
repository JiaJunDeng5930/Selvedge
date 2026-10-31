From Stdlib Require Import String Ascii List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema EnrollmentCredential.
From Selvedge.Foundation Require ArgumentDeclaration DeclarationFields.
From Selvedge.Host Require Import RemoteProtocol.
Module RP := RemoteProtocol.
Module D := ArgumentDeclaration.
Module F := DeclarationFields.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Inductive route := Health | Enrollment | Host | Pairing | Tickets | Control.
Inductive state := AwaitRequest | Routed (destination : route) (host_id : string).
Inductive observation :=
 | HttpRequest (protocol hostname path method : string) (local_test : bool) (query : list json)
 | Authorization (destination : route) (header : string)
 | JsonBody (destination : route) (body : json)
 | Content (media declared : string) (received : N).
Definition route_name value := match value with Health=>"health" | Enrollment=>"register"
 | Host=>"host" | Pairing=>"pair" | Tickets=>"tickets" | Control=>"control" end.
Definition read_route value := match value with "health"=>Some Health | "register"=>Some Enrollment
 | "host"=>Some Host | "pair"=>Some Pairing | "tickets"=>Some Tickets | "control"=>Some Control | _=>None end.
Definition ascii_between low high character :=
 let code:=N.of_nat (nat_of_ascii character) in (low <=? code) && (code <=? high).
Definition hex character := ascii_between 48 57 character || ascii_between 97 102 character || ascii_between 65 70 character.
Definition host_id_valid text :=
 let chars:=list_ascii_of_string text in
 Nat.eqb (List.length chars) 36 &&
 forallb (fun entry=>let '(index,character):=entry in
 if existsb (Nat.eqb index) [8%nat;13%nat;18%nat;23%nat] then Ascii.eqb character "-"
 else if Nat.eqb index 14 then ascii_between 49 56 character
 else if Nat.eqb index 19 then existsb (Ascii.eqb character) ["8"%char;"9"%char;"a"%char;"b"%char;"A"%char;"B"%char]
 else hex character) (combine (seq 0 (List.length chars)) chars).
Definition token_character character := ascii_between 48 57 character || ascii_between 65 90 character ||
 ascii_between 97 122 character || Ascii.eqb character "_" || Ascii.eqb character "-".
Definition wire_token text := Nat.eqb (String.length text) 43 && forallb token_character (list_ascii_of_string text).
Definition pairing_code text := (20 <=? N.of_nat (String.length text)) &&
 (N.of_nat (String.length text) <=? 128) && EnrollmentCredential.visible_ascii text.
Definition whitespace scalar := existsb (N.eqb scalar)
 [9;10;11;12;13;32;160;5760;8192;8193;8194;8195;8196;8197;8198;8199;8200;8201;8202;8232;8233;8239;8287;12288;65279].
Definition label_nonblank (value : D.denote RP.label_declaration) :=
 match Utf8.decode (proj1_sig value) with
 | Some scalars => existsb (fun scalar=>negb (whitespace scalar)) scalars | None=>false end.
Definition registration_fields := [F.required "host_id" (D.Value KText);F.required "host_token" (D.Value KText)].
Definition pairing_fields := [F.required "controller_token" (D.Value KText);F.required "label" RP.label_declaration].
Definition body_value destination : Type := match destination with
 | Enrollment => (D.checked host_id_valid * D.checked wire_token)%type
 | Pairing => (D.checked wire_token * D.checked label_nonblank)%type
 | Tickets => unit | _ => Empty_set end.
Definition decode_body destination source : option (body_value destination) := match destination with
 | Enrollment => match F.decode registration_fields source with
   | Some (id,(token,_)) => match D.admit host_id_valid id,D.admit wire_token token with
     | Some id,Some token => Some (id,token) | _,_ => None end
   | None => None end
 | Pairing => match F.decode pairing_fields source with
   | Some (token,(label,_)) => match D.admit wire_token token,D.admit label_nonblank label with
     | Some token,Some label => Some (token,label) | _,_ => None end
   | None => None end
 | Tickets => option_map (fun _ => tt) (F.decode [] source)
 | _ => None end.
Definition body_json destination : body_value destination -> json := match destination with
 | Enrollment => fun '(id,token) => D.encode (D.Object registration_fields)
     (F.construct registration_fields [!proj1_sig id;proj1_sig token!])
 | Pairing => fun '(token,label) => D.encode (D.Object pairing_fields)
     (F.construct pairing_fields [!proj1_sig token;proj1_sig label!])
 | Tickets => fun _ => JObject [] | _ => fun impossible => match impossible with end end.
Definition credential_valid destination credential := match destination with
 | Enrollment=>EnrollmentCredential.valid credential
 | Host | Tickets | Control=>wire_token credential
 | Pairing=>pairing_code credential | Health=>false end.
Definition credential_error destination := match destination with
 | Pairing=>"invalid_pairing_code" | Control=>"invalid_ticket" | _=>"unauthorized" end.
Inductive action := Reject (status : N) (code : string) | Dispatch (destination : route) (host_id : string)
 | Credential (destination : route) (value : D.checked (credential_valid destination)) | BodyAccepted (destination : route) (value : body_value destination) | ContentAccepted.

Definition authorize destination header :=
 if String.eqb (substring 0 7 header) "Bearer " then
 let value:=substring 7 (String.length header) header in
 match D.admit (credential_valid destination) value with
 | Some value => Credential destination value | None => Reject 401 (credential_error destination) end
 else Reject 401 (credential_error destination).
Fixpoint split_path text reversed := match text with
 | EmptyString=>[string_of_list_ascii (rev reversed)]
 | String character rest=>if Ascii.eqb character "/"
   then string_of_list_ascii (rev reversed)::split_path rest []
   else split_path rest (character::reversed) end.
Definition classify_path path := match split_path path [] with
 | ["";"health"]=>Some (Health,"")
 | ["";"v1";"hosts";"register"]=>Some (Enrollment,"")
 | ["";"v1";"hosts";host_id;operation]=>
   if host_id_valid host_id then match read_route operation with
   | Some Host=>Some (Host,host_id) | Some Pairing=>Some (Pairing,host_id)
   | Some Tickets=>Some (Tickets,host_id) | Some Control=>Some (Control,host_id) | _=>None end else None
 | _=>None end.
Definition route_admission protocol hostname path method local_test query :=
 if negb (String.eqb protocol "https:" || (local_test && String.eqb protocol "http:" &&
 existsb (String.eqb hostname) ["localhost";"127.0.0.1";"[::1]"])) then Reject 400 "https_required" else
 match classify_path path with
 | None=>Reject 404 "not_found"
 | Some (destination,host_id)=>
 let no_query:=Nat.eqb (List.length query) 0 in
 match destination with
 | Health=>if String.eqb method "GET" && no_query then Dispatch destination host_id else Reject 405 "method_not_allowed"
 | Enrollment=>if String.eqb method "POST" && no_query then Dispatch destination host_id else Reject 405 "method_not_allowed"
 | Control=>if String.eqb method "GET" && Nat.eqb (List.length query) 1 &&
  (match query with [JArray [JString "ticket";_]]=>true|_=>false end)
  then Dispatch destination host_id else Reject 400 "invalid_control_route"
 | _=>if negb no_query then Reject 400 "invalid_route_query" else
  if String.eqb method (match destination with Host=>"GET"|_=>"POST" end)
  then Dispatch destination host_id else Reject 405 "method_not_allowed"
 end end.
Definition lower_ascii character :=
 if ascii_between 65 90 character then ascii_of_nat (nat_of_ascii character + 32) else character.
Fixpoint skip_media_space text := match text with
 | String character rest=>if existsb (Ascii.eqb character) [" "%char;ascii_of_nat 9;ascii_of_nat 10;ascii_of_nat 13]
 then skip_media_space rest else text | _=>text end.
Definition json_content media :=
 let lowered:=string_of_list_ascii (map lower_ascii (list_ascii_of_string media)) in
 String.eqb (substring 0 16 lowered) "application/json" &&
 (String.eqb (substring 16 (String.length lowered) lowered) "" ||
  match skip_media_space (substring 16 (String.length lowered) lowered) with
  | EmptyString=>true | String character _=>Ascii.eqb character ";" end).
Definition maximum_body_bytes : N := 4096.
Definition step current event : state * list action :=
 match event with
 | HttpRequest protocol hostname path method local_test query=>
   let chosen:=route_admission protocol hostname path method local_test query in
   match chosen with Dispatch destination host_id=>(Routed destination host_id,[chosen]) | _=>(current,[chosen]) end
 | Authorization destination header=>(current,[authorize destination header])
 | JsonBody destination body=>(current,[match decode_body destination body with
   | Some value => BodyAccepted destination value
   | None => Reject 400 (match destination with Enrollment=>"invalid_registration"|Pairing=>"invalid_pairing_request"|_=>"invalid_ticket_request" end) end])
 | Content media declared received=>(current,[if negb (json_content media) then Reject 415 "invalid_request" else
   if (maximum_body_bytes <? received) || (match parse_natural declared with Some size=>maximum_body_bytes <? size|None=>false end)
   then Reject 413 "invalid_request" else ContentAccepted])

 end.
Definition action_json chosen := match chosen with
 | Reject status code=>JObject [("action",JString "reject");("status",number status);("code",JString code)]
 | Dispatch destination host_id=>JObject [("action",JString (route_name destination));("host_id",JString host_id)]
 | Credential _ value=>JObject [("accepted",JBool true);("credential",JString (proj1_sig value))]
 | BodyAccepted destination value=>body_json destination value | ContentAccepted=>number 0
 end.

Definition execute current event := match snd (step current event) with chosen::_=>action_json chosen | _=>JNull end.
Definition call operation source :=
 if String.eqb operation "control.remote.enrollment_credential" then
 JBool (match source with JString text=>EnrollmentCredential.valid text|_=>false end)
 else if String.eqb operation "control.remote.relay_route" then execute AwaitRequest
 (HttpRequest (str source "protocol") (str source "hostname") (str source "path") (str source "method")
 (equal (get source "local_test") (JBool true)) (items (get source "query")))
 else if String.eqb operation "control.remote.relay_content" then execute AwaitRequest
 (Content (str source "content_type") (str source "content_length") (num source "received_bytes"))
 else match read_route (str source "route") with
 | None=>action_json (Reject 404 "not_found")
 | Some destination=>
 if String.eqb operation "control.remote.relay_body" then execute AwaitRequest (JsonBody destination (get source "body"))
 else if String.eqb operation "control.remote.relay_credential" then execute AwaitRequest (Authorization destination (str source "header"))
 else JNull end.

