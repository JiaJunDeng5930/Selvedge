From Stdlib Require Import String List Bool NArith.
From Selvedge.Kernel Require Import ToolArguments.
From Selvedge.Adapters Require Import Common Observation HostProcess.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition output_capacity (bytes : D.denote (D.Natural 4108 4294967295)) :=
 (proj1_sig bytes - 4096) / 12.
Definition requested_maximum (arguments : ToolArguments.bash_parameters) (limits : json) :=
 match ToolArguments.bash_maximum arguments with
 | Some value => Some (proj1_sig value)
 | None => option_map (@proj1_sig _ _) (D.decode (D.Natural 1 9007199254740991)
     (get limits "bash_default_output_length")) end.
Definition bash_arguments (source : json) :=
 match ToolArguments.decode_arguments Bash (get source "arguments") with
 | None => type_error "Malformed Bash effect"
 | Some arguments => let limits := get source "limits" in
   (* DEFENSE: IO resource observations supply limits independently of admitted tool arguments. *)
   match requested_maximum arguments limits,
     D.decode (D.Natural 1 9007199254740991) (get limits "bash_max_output_length"),
     D.decode (D.Natural 4108 4294967295) (get limits "tool_output_bytes") with
   | Some maximum,Some ceiling,Some bytes =>
     if maximum <=? proj1_sig ceiling then
     let transport := ToolArguments.bash_transport arguments in
     let '(columns,rows) := match Process.selected_size transport with
       | None => (number 80,number 24) | size => HostProcess.size_json size end in
     success (JObject [("command",JString (proj1_sig (ToolArguments.bash_command arguments)));
       ("timeout",match ToolArguments.bash_timeout arguments with
         Some value => number (proj1_sig value) | None => JNull end);
       ("maximum",number (N.min maximum (output_capacity bytes)));
       ("mode",HostProcess.mode_json (Process.transport_mode transport));("cols",columns);("rows",rows)])
     else type_error "Malformed Bash effect"
   | _,_,_ => type_error "Malformed Bash effect"
   end
 end.
Definition read_arguments (source : json) :=
 match ToolArguments.decode_arguments ReadProcess (get source "arguments") with
 | Some arguments => success (JObject [
     ("operation_id",number (proj1_sig (ToolArguments.read_operation arguments)));
     ("cursor",JString (decimal (proj1_sig (ToolArguments.read_cursor arguments))))])
 | None => type_error "Malformed process read" end.
Definition write_arguments (source : json) :=
 match ToolArguments.decode_arguments WriteProcess (get source "arguments") with
 | Some arguments => let '(columns,rows) := HostProcess.size_json (ToolArguments.write_size arguments) in
   success (JObject [("operation_id",number (proj1_sig (ToolArguments.write_operation arguments)));
     ("input",JString (match ToolArguments.write_input arguments with
       Some value => proj1_sig value | None => "" end));
     ("eof",JBool (match ToolArguments.write_eof arguments with Some value => value | None => false end));
     ("cols",columns);("rows",rows)])
 | None => type_error "Malformed process write" end.
Definition image_arguments (source : json) :=
 match ToolArguments.decode_arguments ReadImage (get source "arguments") with
 | Some arguments => success (JObject [("path",JString (proj1_sig (ToolArguments.image_path arguments)));
     ("detail",JString (match ToolArguments.image_detail arguments with Some value => proj1_sig value | None => "auto" end));
     ("timeout",number 30000);("maximum",number 10485760)])
 | None => type_error "Malformed image read effect" end.
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
