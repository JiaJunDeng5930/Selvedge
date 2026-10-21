From Stdlib Require Import String List Bool NArith Ascii.
From Selvedge.Foundation Require Import Json Numbers Utf8.
From Selvedge.Adapters Require Import Common ProviderCatalog RetryAfter.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition base_delay source := nat_value (nth (N.to_nat (num source "attempt"))
  (items (get (get source "policy") "delays_ms")) JNull).
Definition header_delay source : option decimal_delay :=
  let header := get source "retry_after" in if is_null header then None else
  parse_retry_after (text header) (num source "now").
Definition chosen_delay source := match header_delay source with
  | Some value => maximum_delay (base_delay source) value | None => integer_delay (base_delay source) end.
Definition attempt_available source := N.ltb (num source "attempt")
  (N.of_nat (List.length (items (get (get source "policy") "delays_ms")))).
Definition retry_action name cancel := success (JObject [("action",JString name);("cancel",JBool cancel)]).
Definition retry_failure message cancel cause := success (JObject [("action",JString "fail");
  ("cancel",JBool cancel);("cause",JBool cause);("message",JString message)]).
Definition continue source cancel milliseconds := success (JObject [
  ("action",JString "retry");("cancel",JBool cancel);("delay_ms",number (timer_milliseconds milliseconds));
  ("notice",JObject [("attempt",number (num source "attempt" + 1));
    ("delay_ms",number (timer_milliseconds milliseconds));("status",get source "status")])]).
Definition retry source :=
  if boolean_field source "error_present" then
    if boolean_field source "aborted" then retry_action "abort" false
    else if boolean_field source "isTypeError" && attempt_available source
      then continue source false (integer_delay (base_delay source))
      else retry_failure "Model connection failed" false true
  else if negb (boolean_field source "response_present") then continue source false (integer_delay (base_delay source))
  else if contains (items (get (get source "policy") "statuses")) (get source "status") && attempt_available source then
    (* DEFENSE: An explicit Retry-After can exceed the configured retry budget. *)
    if match header_delay source with Some value => delay_exceeds_integer value
        (num (get source "policy") "max_retry_after_ms") | None => false end
    then retry_failure ("Model request failed with HTTP " ++ display_field source "status" ++
      "; Retry-After exceeds the retry budget") true false
    else continue source true (chosen_delay source)
  else retry_action "stop" false.
