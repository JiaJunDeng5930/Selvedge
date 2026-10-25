From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common.
From Selvedge.Host Require Import Process.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition mode_json terminal := JString (match terminal with Pipe => "pipe" | Pty => "pty" end).
Definition mode_of source := if String.eqb (text source) "pty" then Pty else Pipe.
Definition failure_json reason := JObject [("code",JString reason.(failure_code));("message",JString reason.(failure_message))].
Definition failure_of source := Failure (str source "code") (str source "message").
Definition optional_failure source := if is_null source then None else Some (failure_of source).
Definition reason_json source := match source with None => JNull | Some reason => failure_json reason end.
Definition fail reason := Json.failure reason.(failure_code) reason.(failure_message).
Definition state_json current := JObject [("phase",JString
  (match current.(process_phase) with Draining => "draining" | other => public_status other end));
  ("stdin_open",JBool current.(stdin_open));("write_busy",JBool current.(write_busy));
  ("output_drained",JBool current.(output_drained));
  ("reason",reason_json current.(process_reason))].
Definition state_of source := State
  (if String.eqb (str source "phase") "starting" then Starting
   else if String.eqb (str source "phase") "running" then Running
   else if String.eqb (str source "phase") "draining" then Draining else Completed)
  (boolean_field source "stdin_open") (boolean_field source "write_busy")
  (boolean_field source "output_drained") (optional_failure (get source "reason")).
Definition event_of name :=
  if String.eqb name "started" then Started else if String.eqb name "exited" then ShellExited
  else if String.eqb name "drained" then OutputDrained else if String.eqb name "failed" then Failed
  else if String.eqb name "input_closed" then InputClosed
  else if String.eqb name "write_finished" then WriteFinished else Finished.
Definition tail_json current := JObject [("retained",number (N.of_nat current.(retained)));
  ("total",number current.(total))].
Definition tail_of source := Tail (N.to_nat (num source "retained")) (num source "total").
Definition append_plan capacity current added := JObject [("tail",tail_json (append_tail capacity current added));
  ("old_drop",number (N.of_nat (drop_old capacity current added)));
  ("new_drop",number (N.of_nat (drop_new capacity added)))].
Definition tail_snapshot current cursor :=
  let missing := omitted current cursor in
  JObject [("prefix",JString
    (if missing =? 0 then "" else String (Ascii.ascii_of_nat 10) "… [" ++ decimal missing ++
       " Unicode characters omitted] …" ++ String (Ascii.ascii_of_nat 10) ""));
    ("offset",number (read_offset current cursor));
    ("start_cursor",JString (decimal (read_start current cursor)));
    ("next_cursor",JString (decimal current.(total)));("omitted_characters",number missing)].
Definition entry_json entry := JObject [("key",JString entry.(entry_key));("mode",mode_json entry.(entry_mode));
  ("failure",reason_json entry.(entry_failure))].
Definition entry_of source := Entry (str source "key") (mode_of (get source "mode")) (optional_failure (get source "failure")).
Definition registry_json current := JObject [("entries",JArray (map entry_json current.(entries)));
  ("completed",JArray (map JString current.(completed)))].
Definition registry_of source := Registry (map entry_of (items (get source "entries"))) (map text (items (get source "completed"))).
Definition pending_snapshot entry := JObject
  ([("status",JString (match entry.(entry_failure) with None => "starting" | Some _ => "completed" end));
    ("mode",mode_json entry.(entry_mode));("output",JString "");("start_cursor",JString "0");
    ("next_cursor",JString "0");("omitted_characters",number 0)] ++
    match entry.(entry_failure) with None => [] | Some reason => [("completion",JObject
      [("error",JBool true);("exit_code",JNull);("signal",JNull);("reason",failure_json reason)])] end).
Definition completion_json result startup :=
  if negb (is_null result) then
    let value := get result "value" in
    [("completion",JObject ([("error",get result "error");("exit_code",get value "exit_code");
      ("signal",get value "signal")] ++ optional (has value "error") "reason" (get value "error") ++
      optional (has value "stdout_artifact") "stdout_artifact" (get value "stdout_artifact") ++
      optional (has value "stderr_artifact") "stderr_artifact" (get value "stderr_artifact")))]
  else if is_null startup then [] else [("completion",JObject
    [("error",JBool true);("exit_code",JNull);("signal",JNull);("reason",startup)])].
Definition ring_json current := JObject [("position",number (N.of_nat current.(ring_position)));
  ("length",number (N.of_nat current.(ring_length)));("total",number current.(ring_total))].
Definition ring_of source := ByteRing (N.to_nat (num source "position"))
  (N.to_nat (num source "length")) (num source "total").
Definition slice_json slice := JObject [("start",number (N.of_nat slice.(slice_start)));
  ("count",number (N.of_nat slice.(slice_count)));("offset",number (N.of_nat slice.(slice_offset)))].
Definition cleanup_step_json step := JString (match step with
  | TerminateEnvironment => "terminate_environment" | TerminateGroup => "terminate_group"
  | TerminateSession => "terminate_session" | CloseInput => "close_input" | ArmDrainDeadline => "arm_deadline" end).
Definition drain_step_json step := JString (match step with
  | CleanupProcess => "cleanup" | WaitSession => "wait_session" | WaitEnvironment => "wait_environment" | WaitOutput => "wait_output"
  | WaitOutputClose => "wait_output_close" | WaitInput => "wait_input"
  | MarkDrained => "mark_drained" | ClearDrainDeadline => "clear_deadline" end).
Definition artifact_metadata source :=
  let ring := ring_of (get source "ring") in JObject
    [("path",get source "path");("revision",get source "revision");("bytes",number (N.of_nat ring.(ring_length)));
     ("total_bytes",number ring.(ring_total));("truncated",JBool (N.ltb (N.of_nat ring.(ring_length)) ring.(ring_total)));
     ("persisted",JBool (artifact_persisted (boolean_field source "capture_complete")
       (boolean_field source "file_synced") (boolean_field source "batch_synced") (boolean_field source "parent_synced")))].
Definition call operation source :=
  let current := state_of (get source "state") in
  let registry := registry_of (get source "registry") in
  let key := str source "key" in
  if String.eqb operation "control.process.ring_initial" then success (ring_json empty_ring)
  else if String.eqb operation "control.process.ring_append" then
    let capacity := N.to_nat (num source "capacity") in
    let added := N.to_nat (num source "count") in let ring := ring_of (get source "ring") in
    success (JObject [("ring",ring_json (append_ring capacity ring added));
      ("writes",JArray (map slice_json (ring_writes capacity ring added)))])
  else if String.eqb operation "control.process.ring_finish" then
    success (JArray (map slice_json (ring_slices (N.to_nat (num source "capacity")) (ring_of (get source "ring")))))
  else if String.eqb operation "control.process.artifact_metadata" then success (artifact_metadata source)
  else if String.eqb operation "control.process.cleanup_plan" then success (JObject
    [("steps",JArray (map cleanup_step_json cleanup_plan));("deadline_ms",number drain_deadline_ms)])
  else if String.eqb operation "control.process.drain_plan" then success (JArray (map drain_step_json drain_plan))
  else if String.eqb operation "control.process.registry_initial" then success (registry_json empty_registry)
  else if String.eqb operation "control.process.initial" then success (state_json initial)
  else if String.eqb operation "control.process.observe" then success (state_json (observe current (event_of (str source "event"))))
  else if String.eqb operation "control.process.stop" then
    let reason := if String.eqb (str source "event") "cancelled" then cancelled
      else if String.eqb (str source "event") "timeout" then
        Failure "command_timed_out" ("Command exceeded " ++ decimal (num source "timeout") ++ " milliseconds")
      else failure_of (get source "reason") in
    success (JObject [("state",state_json (with_reason current reason));("cleanup",JBool (active current))])
  else if String.eqb operation "control.process.reason" then success (state_json (with_reason current (failure_of (get source "reason"))))
  else if String.eqb operation "control.process.status" then success (JString (public_status current.(process_phase)))
  else if String.eqb operation "control.process.reserve_write" then
    match reserve_write current with inl reason => fail reason | inr next => success (state_json next) end
  else if String.eqb operation "control.process.admit_write" then
    match admit_write current (mode_of (get source "mode")) (boolean_field source "eof")
      (negb (is_null (get source "cols"))) (negb (is_null (get source "rows"))) with
    | Some reason => fail reason | None => success JNull end
  else if String.eqb operation "control.process.tail_initial" then success (tail_json empty_tail)
  else if String.eqb operation "control.process.output_append" then
    let previous := tail_of (get source "tail") in let combined := tail_of (get source "combined") in
      let capacity := N.to_nat (num source "capacity") in let count := N.to_nat (num source "count") in
      success (JObject [("tail",append_plan capacity previous count);
        ("combined",append_plan capacity combined count)])
  else if String.eqb operation "control.process.tail_read" then
    match parse_natural (str source "cursor") with
    | Some cursor => success (tail_snapshot (tail_of (get source "tail")) cursor)
    | None => type_error "Malformed process cursor observation" end
  else if String.eqb operation "control.process.snapshot" then success (JObject
    ([("status",JString (public_status current.(process_phase)));("mode",get source "mode")] ++
     object_fields (get source "output") ++ completion_json (get source "result") (get source "startup_error")))
  else if String.eqb operation "control.process.write_result" then
    match Utf8.scalar_count (str source "input") with
    | Some count => success (JObject ([("mode",get source "mode");("input_characters",number (N.of_nat count));
      ("eof",get source "eof")] ++ optional (negb (is_null (get source "cols"))) "cols" (get source "cols") ++
      optional (negb (is_null (get source "rows"))) "rows" (get source "rows")))
    | None => type_error "Malformed UTF-8 process input" end
  else if String.eqb operation "control.process.registry_register" then
    success (registry_json (register registry key (mode_of (get source "mode"))))
  else if String.eqb operation "control.process.registry_failed" then
    success (registry_json (failed registry key (failure_of (get source "reason"))))
  else if String.eqb operation "control.process.registry_complete" then success (JObject
    [("registry",registry_json (complete registry key));("retired",JArray (map JString (retired registry key)))])
  else if String.eqb operation "control.process.registry_lookup" then
    match lookup registry key with
    | Some entry => success (pending_snapshot entry)
    | None => Json.failure "unknown_process" "No retained Bash process exists for this task and operation_id" end
  else if String.eqb operation "control.process.registry_admit_write" then
    match lookup registry key with
    | Some entry => match entry.(entry_failure) with Some reason => fail reason | None => success JNull end
    | None => Json.failure "unknown_process" "No retained Bash process exists for this task and operation_id" end
  else err ("Unknown process control operation: " ++ operation).
