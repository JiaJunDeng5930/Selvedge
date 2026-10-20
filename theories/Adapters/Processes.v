From Stdlib Require Import String List Bool NArith.
From Selvedge.Kernel Require Import ToolArguments.
From Selvedge.Adapters Require Import Common Observation.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition default_null (value fallback : json) := if is_null value then fallback else value.
Definition positive (value : json) := bound value 1 9007199254740991.
Definition output_capacity (limits : json) := (num limits "tool_output_bytes" - 4096) / 12.
Definition bash_arguments (source : json) :=
  let arguments := get source "arguments" in let limits := get source "limits" in
  let maximum := default_null (get arguments "max_output_length") (get limits "bash_default_output_length") in
  (* DEFENSE: IO resource observations can have invalid limits independently of admitted tool arguments. *)
  if ToolArguments.valid_arguments Bash arguments && positive (get limits "bash_max_output_length") &&
     bound (get limits "tool_output_bytes") 4108 4294967295 && (0 <? output_capacity limits) &&
     positive maximum && (nat_value maximum <=? num limits "bash_max_output_length")
  then success (JObject [("timeout",get arguments "timeout_ms");
    ("maximum",number (N.min (nat_value maximum) (output_capacity limits)));
    ("mode",JString (ToolArguments.defaulted_mode arguments));
    ("cols",default_null (get arguments "cols") (number 80));
    ("rows",default_null (get arguments "rows") (number 24))])
  else type_error "Malformed Bash effect".
Definition read_arguments (source : json) :=
  let arguments := get source "arguments" in
  if ToolArguments.valid_arguments ReadProcess arguments
  then success (JObject [("operation_id",get arguments "operation_id");
    ("cursor",default_null (get arguments "cursor") (JString "0"))])
  else type_error "Malformed process read".
Definition write_arguments (source : json) :=
  let arguments := get source "arguments" in
  if ToolArguments.valid_arguments WriteProcess arguments
  then success (JObject [("operation_id",get arguments "operation_id");
    ("input",default_null (get arguments "input") (JString ""));
    ("eof",default_null (get arguments "eof") (JBool false));
    ("cols",get arguments "cols");("rows",get arguments "rows")])
  else type_error "Malformed process write".
Definition image_arguments (source : json) :=
  let arguments := get source "arguments" in
  if ToolArguments.valid_arguments ReadImage arguments
  then success (JObject [("path",get arguments "path");
    ("detail",default_null (get arguments "detail") (JString "auto"));
    ("timeout",number 30000);("maximum",number 10485760)])
  else type_error "Malformed image read effect".
Definition artifact (name : string) (output value : json) :=
  optional (boolean_field output "truncated" && negb (is_null value)) name value.
Definition process_value (source : json) :=
  let out := get source "out" in let err := get source "err" in
  JObject ([("mode",get source "mode");("start_cursor",get source "start_cursor");
    ("next_cursor",get source "next_cursor");("omitted_characters",get source "omitted_characters");
    ("exit_code",get source "exitCode");("signal",get source "exitSignal");
    ("stdout",get out "text");("stderr",get err "text");
    ("stdout_truncated",get out "truncated");("stderr_truncated",get err "truncated");
    ("stdout_bytes",get out "total_bytes");("stderr_bytes",get err "total_bytes");
    ("stdout_omitted_characters",get out "omitted_characters");("stderr_omitted_characters",get err "omitted_characters")] ++
    artifact "stdout_artifact" out (get source "outArtifact") ++
    artifact "stderr_artifact" err (get source "errArtifact")).
Definition exit_message (source : json) :=
  let signal := get source "exitSignal" in
  if is_null signal || equal signal (JString "") then "Command exited with status " ++ diagnostic (get source "exitCode")
  else "Command ended with signal " ++ diagnostic signal.
Definition termination_reason (source : json) :=
  let reason := get source "reason" in
  if is_null reason then
    if equal (get source "exitCode") (number 0) && is_null (get source "exitSignal") then JNull
    else JObject [("code",JString "command_failed");("message",JString (exit_message source))]
  else reason.
Definition process_result (source : json) :=
  let reason := termination_reason source in let value := process_value source in
  if is_null reason then JObject [("value",value);("error",JBool false)]
  else JObject [("value",set value "error" reason);("error",JBool true)].
