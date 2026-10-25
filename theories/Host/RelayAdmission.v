From Stdlib Require Import String Ascii List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers EnrollmentCredential.
From Selvedge.Host Require Import RemoteProtocol RemoteRelaySession.
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
Inductive action := Reject (status : N) (code : string) | Dispatch (destination : route) (host_id : string)
 | Credential (value : string) | BodyAccepted | ContentAccepted.

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
Definition label_valid body := match get body "label" with
 | JString text => bounded (JString text) 80 &&
 (match Utf8.decode text with Some scalars=>existsb (fun scalar=>negb (whitespace scalar)) scalars|None=>false end)
 | _=>false end.
Definition body_valid destination body := match destination with
 | Enrollment=>shape body ["host_id";"host_token"] && host_id_valid (str body "host_id") && wire_token (str body "host_token")
 | Pairing=>shape body ["controller_token";"label"] && wire_token (str body "controller_token") && label_valid body
 | Tickets=>shape body [] | _=>false end.
Definition credential_valid destination credential := match destination with
 | Enrollment=>EnrollmentCredential.valid credential
 | Host | Tickets | Control=>wire_token credential
 | Pairing=>pairing_code credential | Health=>false end.
Definition credential_error destination := match destination with
 | Pairing=>"invalid_pairing_code" | Control=>"invalid_ticket" | _=>"unauthorized" end.
Definition authorize destination header :=
 if String.eqb (substring 0 7 header) "Bearer " then
 let value:=substring 7 (String.length header) header in
 if credential_valid destination value then Credential value else Reject 401 (credential_error destination)
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
 | JsonBody destination body=>(current,[if body_valid destination body then BodyAccepted else
   Reject 400 (match destination with Enrollment=>"invalid_registration"|Pairing=>"invalid_pairing_request"|_=>"invalid_ticket_request" end)])
 | Content media declared received=>(current,[if negb (json_content media) then Reject 415 "invalid_request" else
   if (maximum_body_bytes <? received) || (match parse_natural declared with Some size=>maximum_body_bytes <? size|None=>false end)
   then Reject 413 "invalid_request" else ContentAccepted])

 end.
Definition action_json chosen := match chosen with
 | Reject status code=>JObject [("action",JString "reject");("status",number status);("code",JString code)]
 | Dispatch destination host_id=>JObject [("action",JString (route_name destination));("host_id",JString host_id)]
 | Credential value=>JObject [("accepted",JBool true);("credential",JString value)]
 | BodyAccepted=>JBool true | ContentAccepted=>number 0
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
 else if String.eqb operation "control.remote.relay_disconnect" then RemoteRelaySession.disconnect source
 else match read_route (str source "route") with
 | None=>action_json (Reject 404 "not_found")
 | Some destination=>
 if String.eqb operation "control.remote.relay_body" then execute AwaitRequest (JsonBody destination (get source "body"))
 else if String.eqb operation "control.remote.relay_credential" then execute AwaitRequest (Authorization destination (str source "header"))
 else JNull end.

