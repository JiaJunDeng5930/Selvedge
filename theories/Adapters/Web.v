From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import WebCommon WebResources WebStream WebStore WebHistory WebContinuation BackendRequests.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition objects source names := forallb (fun name => is_object (get source name)) names.
Definition arrays source names := forallb (fun name => is_array (get source name)) names.
Definition strings source names := forallb (fun name => is_text (get source name)) names.
Definition any_source (source : json) := true.
Definition effect_source source := is_object (get source "effect").
Definition records_source source := arrays source ["records"] && forallb retirement_valid (items (get source "records")).
Definition metadata_source source := arrays source ["rows"] && strings source ["new_identity"] && Json.is_bool (get source "created").
Definition existing_metadata_source source := arrays source ["rows"] && strings source ["new_identity"] && same (get source "created") (JBool false).
Definition frame_source source := is_object (get source "frame") && is_text (get (get source "frame") "data").
Definition continuation_source source := same (get (get (position source) "value") "position") (get source "receipt_position") &&
  objects source ["effect";"request";"limits"] && is_array (get (get source "effect") "history") &&
  is_array (get (get source "request") "history") && is_array (get source "tools").
Definition stream_source source := let state := get source "state" in is_object state &&
  strings state ["pending";"name"] && is_array (get state "data") && forallb is_text (items (get state "data")) &&
  natural (get state "size") && Json.is_bool (get state "after_cr") &&
  strings source ["chunk"] && natural (get source "maximum") && Json.is_bool (get source "eof").
Definition options source := let model := eq (get source "effect") "kind" "model" in
  success (JObject [("snapshots",JBool model);("receipt",JBool model);("stages",number 2)]).
Definition contract source := success (JObject (("model",get (get (get source "effect") "model") "name")::
  (subset (get source "request") ["instructions"] ++ [("tools",get source "tools")]))).

(* A protocol operation is declared once with its boundary admission and pure
   interpreter. There is no second handler or host implementation to keep in sync. *)
Record operation := Operation { operation_name : string; operation_source : json -> bool; operation_run : json -> json }.
Definition operations := [
  Operation "web.messages" (fun source => arrays source ["history"]) WebHistory.messages;
  Operation "web.tools" (fun source => effect_source source &&
    (negb (eq (get source "effect") "kind" "model") || is_array (get (get source "effect") "tools"))) WebHistory.tools;
  Operation "web.resource" any_source WebResources.resource;
  Operation "web.failure" (fun source => objects source ["record"]) WebResources.failure_result;
  Operation "web.event" frame_source (WebResources.event false);
  Operation "web.store_identify" (fun source => objects source ["record";"current"]) WebStore.store_identify;
  Operation "web.store_finish" (fun source => objects source ["record";"current";"response"]) WebStore.store_finish;
  Operation "web.store_reject" (fun source => objects source ["record"]) WebStore.store_reject;
  Operation "web.store_retire" (fun source => objects source ["record"]) WebStore.store_retire;
  Operation "web.store_prepare" (fun source => objects source ["request"] &&
    is_object (get (get source "request") "body") && strings source ["new_key"]) WebStore.store_prepare;
  Operation "web.retire_existing" (fun source => arrays source ["records"] && strings source ["owner"] && existing_metadata_source source) WebStore.retire_existing;
  Operation "web.continuation" continuation_source (WebContinuation.continuation BackendRequests.structured_text);
  Operation "web.receipt" WebContinuation.receipt_source WebContinuation.receipt;
  Operation "web.sse_step" stream_source WebStream.sse_step;
  Operation "web.http" (fun source => objects source ["record"] && natural (get source "status")) WebResources.http;
  Operation "web.commit" any_source WebResources.commit;
  Operation "web.request_bounds" any_source WebResources.request_bounds;
  Operation "web.owner" effect_source WebCommon.owner;
  Operation "web.headers" any_source WebStream.headers;
  Operation "web.recovery" any_source WebStore.recovery;
  Operation "web.recovery_result" any_source WebStore.recovery_result;
  Operation "web.retained" (fun source => objects source ["record"]) WebResources.retained;
  Operation "web.decode" (fun source => strings source ["text"]) (fun source => decode_provider_text (str source "text"));
  Operation "web.settle" (fun source => objects source ["resource";"effect"] && arrays source ["deferred"]) WebContinuation.settle;
  Operation "web.cancel_owner" any_source WebStore.cancel_owner;
  Operation "web.position" (fun source => effect_source source && is_array (get (get source "effect") "history")) WebCommon.position;
  Operation "web.contract" (fun source => objects source ["effect";"request"] && arrays source ["tools"]) contract;
  Operation "web.store_metadata" metadata_source WebStore.store_metadata;
  Operation "web.frame" frame_source WebResources.frame;
  Operation "web.event_header" frame_source (WebResources.event true);
  Operation "web.recovery_shape" any_source WebStore.recovery_shape;
  Operation "web.recovery_connection" any_source WebStore.recovery_connection;
  Operation "web.options" effect_source options;
  Operation "web.invocation" (fun source => objects source ["effect";"profile";"body"] &&
    strings source ["owner"] && natural (get source "stage") && Json.is_bool (get source "reset")) WebStore.invocation;
  Operation "web.cancellation" any_source WebStore.cancellation;
  Operation "web.store_latest" (fun source => records_source source && strings source ["owner"]) WebStore.store_latest;
  Operation "web.exchange_start" any_source WebStore.exchange_start;
  Operation "web.exchange_result" any_source WebStore.exchange_result;
  Operation "web.catch" any_source WebStore.catch;
  Operation "web.http_json" (fun source => objects source ["response"] &&
    Json.is_bool (get (get source "response") "ok") && natural (get (get source "response") "status") && strings source ["text"]) WebResources.http_json;
  Operation "web.reset_session" (fun source => natural (get source "task_id") && records_source source && existing_metadata_source source) WebStore.reset_session
].
Definition select_operation name := find (fun operation => String.eqb name operation.(operation_name)) operations.
Definition call name source := match select_operation name with
  | None => err ("Unknown Web model operation: " ++ name)
  | Some operation =>
    (* DEFENSE: HTTP, stream chunks and persisted receipts are external inputs;
       malformed Unicode, operation fields and retirement states are rejected. *)
    if base_source source && operation.(operation_source) source then operation.(operation_run) source
    else err (if String.eqb name "web.reset_session" then "Invalid ChatGPT Web reset source" else "Invalid ChatGPT Web JSON source") end.
