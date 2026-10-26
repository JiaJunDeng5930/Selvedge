From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

(** The transport supplies its live pending Promise identities as an observation.
    There is no independently maintained authority registry in the pure model. *)
Record rpc_state := RpcState {
  pending : list N;
  preparable : list N;
  materializing : list N;
  working : list N;
  next_id : N;
  failed : bool;
  closing : bool
}.
Definition contains (id : N) (ids : list N) : bool := existsb (N.eqb id) ids.
Definition retire (id : N) (ids : list N) : list N := filter (fun n => negb (N.eqb n id)) ids.
Fixpoint valid_coordinates (limit : N) (values : list json) : bool :=
  match values with
  | [] => true
  | value :: rest =>
    canonical_natural value && (0 <? nat_value value) && (nat_value value <? limit) &&
    negb (contains (nat_value value) (map nat_value rest)) && valid_coordinates limit rest
  end.
Definition decode_state (source : json) : option rpc_state :=
  let state := get source "state" in
  let n := get state "nextId" in
  let ps := get state "pending" in
  let preparing := get state "materializing" in
  let transforms := get state "preparable" in
  let work := get state "working" in
  if is_object source && is_text (get source "label") && is_text (get source "name") &&
     is_object state && is_array ps && is_array preparing && is_array transforms && is_array work &&
     canonical_natural n && (0 <? nat_value n) &&
     valid_coordinates (nat_value n) (items ps ++ items preparing) &&
     valid_coordinates (nat_value n) (items transforms) &&
     valid_coordinates (nat_value n) (items work) &&
     forallb (fun value => contains (nat_value value) (map nat_value (items ps))) (items transforms) &&
     forallb (fun value => contains (nat_value value) (map nat_value (items work))) (items preparing)
  then Some (RpcState (map nat_value (items ps)) (map nat_value (items transforms))
                      (map nat_value (items preparing)) (map nat_value (items work)) (nat_value n)
                      (truthy (get state "failure")) (boolean_field state "closing"))
  else None.

Record rpc_action := RpcAction {
  action_kind : string;
  action_pending : list N;
  action_preparable : list N;
  action_materializing : list N;
  action_next : N;
  action_payload : list (string * json)
}.
Definition unchanged (kind : string) (state : rpc_state) (payload : list (string * json)) :=
  RpcAction kind state.(pending) state.(preparable) state.(materializing) state.(next_id) payload.
Definition consume (kind : string) (state : rpc_state) (id : N) (payload : list (string * json)) :=
  RpcAction kind (retire id state.(pending)) (retire id state.(preparable))
    (retire id state.(materializing)) state.(next_id) (("id", number id)::payload).
Definition reserve_materialization (state : rpc_state) (id : N) (value : json) :=
  RpcAction "prepare" (retire id state.(pending)) (retire id state.(preparable))
    (id::state.(materializing)) state.(next_id) [("id",number id);("value",value)].
Definition encode_action (action : rpc_action) :=
  success (JObject ([("action", JString action.(action_kind));
                    ("nextPending", JArray (map number action.(action_pending)));
                    ("nextPreparable", JArray (map number action.(action_preparable)));
                    ("nextMaterializing", JArray (map number action.(action_materializing)));
                    ("nextId", number action.(action_next))] ++ action.(action_payload))).
Definition issued (state : rpc_state) (id : json) :=
  canonical_natural id && contains (nat_value id) state.(pending).
Definition correlate (state : rpc_state) (id : json) : option N :=
  if issued state id then Some (nat_value id) else None.
Definition label (source : json) := str source "label".
Definition name (source : json) := str source "name".
Definition request_message (state : rpc_state) (source : json) :=
  JObject ([("jsonrpc", JString "2.0"); ("id", number state.(next_id))] ++
    optional (has source "method") "method" (get source "method") ++
    optional (has source "params") "params" (get source "params")).
Definition notification_message (source : json) :=
  JObject ([("jsonrpc", JString "2.0")] ++
    optional (has source "method") "method" (get source "method") ++
    optional (has source "params") "params" (get source "params")).
Definition reject_action (state : rpc_state) (id : N) (message : string) :=
  consume "reject" state id [("error", JString message)].
Definition response (state : rpc_state) (source message : json) (id : N) : rpc_action :=
  if Bool.eqb (has message "result") (has message "error")
  then reject_action state id (label source ++ " response must have exactly one of result or error")
  else if has message "result"
  then if contains id state.(preparable) then reserve_materialization state id (get message "result")
    else consume "resolve" state id [("value",get message "result")]
  else let error := get message "error" in
    if is_object error then
      if has error "message" then
        match as_string (get error "message") with
        | Some text => reject_action state id (label source ++ " " ++ name source ++ ": " ++ text)
        | None => reject_action state id ("Malformed " ++ label source ++ " error response")
        end
      else reject_action state id (label source ++ " " ++ name source ++ ": request failed")
    else reject_action state id ("Malformed " ++ label source ++ " error response").
Definition peer_message (state : rpc_state) (source message : json) (method : string) :=
  if has message "id" then
    unchanged "write" state [("message", JObject
      ([("jsonrpc",JString "2.0");("id",get message "id")] ++
        if String.eqb method "ping" then [("result",JObject [])]
        else [("error",JObject [("code",JNumber "-32601");
                  ("message",JString "Client method is not supported")])]))]
  else unchanged "notify" state [("message",message)].
Definition message (state : rpc_state) (source : json) : json :=
  let message := get source "message" in
  (* DEFENSE: Stdio peers can send values other than JSON-RPC 2.0 objects. *)
  if is_object message && String.eqb (str message "jsonrpc") "2.0" then
    encode_action (match as_string (get message "method") with
      | Some method => peer_message state source message method
      | None => match correlate state (get message "id") with
        | Some id => response state source message id
        | None => unchanged "ignore" state []
        end
      end)
  else err ("Malformed " ++ label source ++ " JSON-RPC message").
Definition request (state : rpc_state) (source : json) : json :=
  if boolean_field source "aborted" then encode_action (unchanged "abort" state [])
  else if state.(failed) then encode_action (unchanged "external_failure" state [])
  (* Retired response tokens retain their physical capacity until their
     interpreter has actually stopped; cancellation cannot bypass this bound. *)
  else if N.of_nat (List.length (state.(pending) ++ state.(working))) <? num source "maxPending" then
    (* DEFENSE: A long-lived connection can exhaust exact JavaScript request ids. *)
    if state.(next_id) <? 9007199254740991 then
      encode_action (RpcAction "request" (state.(pending) ++ [state.(next_id)])
        (if boolean_field source "prepare" then state.(preparable) ++ [state.(next_id)] else state.(preparable))
        state.(materializing)
        (N.succ state.(next_id)) [("id",number state.(next_id));
          ("message",request_message state source)])
    else err (label source ++ " request identity exhausted")
  else err (label source ++ " request queue is full").
Definition write (state : rpc_state) (source : json) : json :=
  if state.(failed) then encode_action (unchanged "external_failure" state [])
  else if state.(closing) then err (label source ++ " " ++ name source ++ " is closed")
  else if num source "bytes" <=? num source "frameLimit" then
    if num source "queuedBytes" + num source "bytes" <=? 2 * num source "frameLimit"
    then encode_action (unchanged "write" state [("message",get source "message")])
    else err (label source ++ " outbound queue is full")
  else failure "range" (label source ++ " request exceeds frame limit").
Definition cancellation (state : rpc_state) (source : json) (id : N) (timeout : bool) :=
  let reason := if timeout then "Deadline exceeded" else "Client cancelled" in
  let error := if timeout
    then label source ++ " request timed out after " ++ diagnostic (get source "timeoutMs") ++
      " milliseconds; its external outcome may be unknown"
    else label source ++ " request cancelled" in
  consume "cancel" state id [("error",JString error);
    ("externalReason",JBool (negb timeout && boolean_field source "externalReason"));
    ("message", JObject [("jsonrpc",JString "2.0");
      ("method",JString "notifications/cancelled");
      ("params",JObject [("requestId",number id);("reason",JString reason)])])].
Definition retirement (state : rpc_state) (source : json) : json :=
  let id := get source "id" in
  if canonical_natural id && contains (nat_value id) (state.(pending) ++ state.(materializing)) then
    let timeout := String.eqb (str source "reason") "timeout" in
    (* DEFENSE: Timeout text must come from a canonical nonnegative clock observation. *)
    if timeout && negb (canonical_natural (get source "timeoutMs"))
    then err "Malformed RPC deadline observation"
    else encode_action (cancellation state source (nat_value id) timeout)
  else encode_action (unchanged "ignore" state []).
Definition prepared (state : rpc_state) (source : json) : json :=
  let id := get source "id" in
  (* DEFENSE: Timeout, cancellation and process close can retire an admitted
     materialization while its physical file operation is still finishing. *)
  if canonical_natural id && contains (nat_value id) state.(materializing) then
    if boolean_field source "ok" then encode_action (consume "resolve" state (nat_value id) [("value",get source "value")])
    else encode_action (reject_action state (nat_value id)
      (label source ++ " " ++ name source ++ ": " ++ str source "error"))
  else encode_action (unchanged "ignore" state []).
Definition lifecycle (state : rpc_state) (source : json) :=
  let failing := String.eqb (str source "event") "failure" in
  if (if failing then state.(failed) else state.(closing))
  then encode_action (unchanged "ignore" state [])
  else encode_action (RpcAction (if failing then "fail" else "close") [] [] [] state.(next_id)
    [("retired",JArray (map number (state.(pending) ++ state.(materializing))));
     ("error",JString (label source ++ " connection closed"))]).
Definition exit (state : rpc_state) (source : json) :=
  let signal := get source "signal" in let code := get source "code" in
  let code_valid := match code with JNull | JNumber _ => true | _ => false end in
  let signal_valid := match signal with JNull | JString _ => true | _ => false end in
  (* DEFENSE: Process termination observations have nullable numeric code and textual signal. *)
  if has source "code" && has source "signal" && code_valid && signal_valid then
    if state.(closing) then encode_action (unchanged "ignore" state [])
    else encode_action (unchanged "fail" state [("error",JString
      (label source ++ " " ++ name source ++ " exited (" ++
        diagnostic (match signal with JNull => code | _ => signal end) ++ ")"))])
  else err "Malformed RPC exit observation".
Definition call (operation : string) (source : json) : json :=
  (* DEFENSE: Hosts must supply a valid live pending map before any allocation or settlement. *)
  match decode_state source with
  | None => err "Malformed RPC state observation"
  | Some state =>
    if String.eqb operation "rpc.available" then success (JBool (negb state.(failed) && negb state.(closing)))
    else if String.eqb operation "rpc.request" then request state source
    else if String.eqb operation "rpc.notification" then encode_action (unchanged "write" state [("message",notification_message source)])
    else if String.eqb operation "rpc.write" then write state source
    else if String.eqb operation "rpc.frame" then
      if num source "bytes" <=? num source "frameLimit" then encode_action (unchanged "read" state [])
      else err (label source ++ " frame exceeds limit")
    else if String.eqb operation "rpc.message" then message state source
    else if String.eqb operation "rpc.prepared" then prepared state source
    else if String.eqb operation "rpc.finish" then encode_action
      (match correlate state (get source "id") with
       | None => unchanged "ignore" state []
       | Some id => consume "finish" state id [] end)
    else if String.eqb operation "rpc.retire" then retirement state source
    else if String.eqb operation "rpc.lifecycle" then lifecycle state source
    else if String.eqb operation "rpc.exit" then exit state source
    else err ("Unknown host model operation: " ++ operation)
  end.
