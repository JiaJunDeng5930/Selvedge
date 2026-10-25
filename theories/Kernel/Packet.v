From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json TextJson.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import Numbers Domain Codec State Inputs InputDecoder Queries CommandExecution
 Callbacks HookCallbacks Scheduler Recovery Observation Notifications Delivery Limits WorldInvariant.
From Selvedge.Kernel Require Import CommitAdmission CommandHandlers ForkCommit.
From Selvedge.Kernel Require CreationCommit NativeForkCommit TerminalSettlement DeferredCommit
 BoardCommit ConnectionCommit CompactionCommit TitleCommit.
From Selvedge.Features Require Import Runtime.
Import ListNotations.
Open Scope string_scope.
Definition initial := State.initial.
Definition world_json := Observation.world_json.
Definition query := CommandHandlers.query.
Definition command_schedules (command : Selvedge.Generated.Commands.command) (result : decision) :=
 bool_default "ok" (decision_reply result) false &&
 match command with
 | Selvedge.Generated.Commands.Cmd_create_idle _ | Selvedge.Generated.Commands.Cmd_record_speech_transcript _ => false
 | Selvedge.Generated.Commands.Cmd_accept_speech_delegation _ => negb (bool_default "replayed" (value_or_null "result" (decision_reply result)) false)
 | _ => Selvedge.Features.Runtime.schedules command end.
Definition execute_domain (command : Selvedge.Generated.Commands.command) (context : option Tasks.native_call) (value : world) : decision :=
 let caller := option_map Tasks.native_owner context in
 match query command caller value with
 | Some reply => Decision value reply []
 | None => match Selvedge.Features.Runtime.guard_command command caller value with
   | Some refused => refused
   | None =>
     let result := CommandHandlers.execute command context value in
     Selvedge.Features.Runtime.guard_result value result
   end
 end.
(* Assess against the worker's authoritative immutable world. The hypothetical
   decision is discarded: no world, scheduler work or IO effect is committed. *)
Definition assess (source : json) (value : world) : json :=
 let candidate := match Selvedge.Generated.Commands.decode (value_or_null "command" source) with
 | Some command => decision_reply (execute_domain command None value)
 | None => State.failure "invalid_input" (InputDecoder.command_diagnostic (value_or_null "command" source))
 end in
 let admitted := bool_default "ok" candidate false in
 JObject [("editor",value_or_null "editor" source);("revision",value_or_null "revision" source);
   ("sequence",number (world_sequence value));("admitted",JBool admitted);
   ("refusal",if admitted then JNull else value_or_null "error" candidate)].
Definition execute_command (command : Selvedge.Generated.Commands.command) (context : option Tasks.native_call) (value : world) :=
 let result := execute_domain command context value in
 if command_schedules command result then Selvedge.Features.Runtime.after_transition value result else result.
Definition core_transition (source : Inputs.input) (value : world) :=
 match source with
 | UserCommand command => execute_command command None value
 | Configure environment => accept (JObject [("configured",JBool true)])
   (Selvedge.Features.Runtime.reconfigure (with_environment environment value)) []
 | ContextCompleted id ticket observations diagnostic => Selvedge.Features.Runtime.after_transition value
   (Callbacks.context_completed id ticket observations diagnostic value)
 | ModelCompleted id ticket outcome => Selvedge.Features.Runtime.after_transition value (Callbacks.model_completed id ticket outcome value)
 | ReasoningCompleted id ticket outcome => Selvedge.Features.Runtime.after_transition value (Callbacks.reasoning_completed id ticket outcome value)
 | ToolCompleted id ticket result error => Selvedge.Features.Runtime.after_transition value (Callbacks.tool_completed id ticket result error value)
 | HookCompleted id ticket outcome => Selvedge.Features.Runtime.after_transition value (HookCallbacks.hook_completed id ticket outcome value)
 | AfterCompleted id operation ticket outcome => Selvedge.Features.Runtime.after_transition value (HookCallbacks.after_completed id operation ticket outcome value)
 | ApprovalCompleted id ticket outcome => Selvedge.Features.Runtime.after_transition value (Callbacks.approval_completed id ticket outcome value)
 | Recover => Selvedge.Features.Runtime.after_transition value (Recovery.recover (Selvedge.Features.Runtime.recover value))
 | Continue => Selvedge.Features.Runtime.after_transition value (accept JNull value [])
 end.
Definition transition_decoded (decoded : option Inputs.input) (source : json) (value : world)
 : bool * bool * option Inputs.input * decision :=
 match decoded with
 | Some (UserCommand command) => match query command None value with
   | Some reply => (false,false,Some (UserCommand command),Decision value reply [])
   | None => let result := execute_command command None value in
     (true,command_schedules command result,Some (UserCommand command),result) end
 | Some input => (true,match input with Configure _ => false | _ => true end,Some input,core_transition input value)
 | None => if InputDecoder.owns_kind source then
     (false,false,None,reject "invalid_input" (InputDecoder.diagnostic source) value)
   else match Selvedge.Features.Runtime.completion execute_domain source value with
     | Some (durable,schedules,result) => (durable,schedules,None,if schedules then Selvedge.Features.Runtime.after_transition value result else result)
     | None => (false,false,None,reject "invalid_input" "Unknown input kind or malformed domain callback" value)
     end
 end.
Definition transition (source : json) (value : world) :=
 transition_decoded (InputDecoder.decode source) source value.
Definition admit_with_status := DeferredCommit.admit_with_status.
Definition admit (durable : bool) (source : option Inputs.input) (raw_source : json)
 (before : world) (result : decision) := snd (admit_with_status durable source raw_source before result).
Definition manual_fork_input (decoded : option Inputs.input) : option Selvedge.Generated.Commands.fork_payload :=
 match decoded with
 | Some (UserCommand (Selvedge.Generated.Commands.Cmd_fork request)) => Some request
 | _ => None
 end.
Definition manual_fork (source : json) := manual_fork_input (InputDecoder.decode source).
Definition native_fork_input (decoded : option Inputs.input) (value : world) :=
 match decoded with Some input => NativeForkCommit.resolve input value | None => None end.
Definition terminal_settlement_input (decoded : option Inputs.input) (value : world) :=
 match decoded with Some input => TerminalSettlement.resolve input value | None => None end.
Definition deferred_candidate (decoded : option Inputs.input) (value : world)
 : option (Inputs.input * decision) :=
 match BoardCommit.input decoded with
 | Some request => Some (UserCommand (Selvedge.Generated.Commands.Cmd_create_card request), BoardCommit.candidate request value)
 | None => match ConnectionCommit.input decoded with
 | Some request => Some (UserCommand (Selvedge.Generated.Commands.Cmd_chatgpt_exec request), ConnectionCommit.candidate request value)
 | None => match decoded with
 | Some (UserCommand (Selvedge.Generated.Commands.Cmd_compact request)) =>
   Some (UserCommand (Selvedge.Generated.Commands.Cmd_compact request), CompactionCommit.candidate request value)
 | _ => match native_fork_input decoded value with
 | Some accepted => Some (Continue, NativeForkCommit.candidate accepted)
 | None => match TitleCommit.input decoded value with
 | Some accepted => Some (Continue, TitleCommit.candidate accepted)
 | None => match terminal_settlement_input decoded value with
 | Some accepted => Some (TerminalSettlement.source accepted, TerminalSettlement.candidate accepted)
 | None => None
 end end end end end end.
Definition packet (source : json) (value : world) : world * json :=
 if N.leb (N.of_nat (String.length (TextJson.render_json source))) Limits.frame_bytes then
 let decoded := InputDecoder.decode source in
 match manual_fork_input decoded with
 | Some request => ForkCommit.packet request value
 | None => match CreationCommit.input decoded with
 | Some request => CreationCommit.packet request value
 | None => match deferred_candidate decoded value with
 | Some (input,candidate) => DeferredCommit.packet (Some input) source value candidate
 | None =>
 let '(durable,schedules,input,result) := transition_decoded decoded source value in
 let result := if schedules then Selvedge.Features.Runtime.finish (Scheduler.run execute_command Selvedge.Features.Runtime.can_schedule_task result) else result in
 let '(admitted,result) := admit_with_status durable input source value result in
 let committed := if durable then with_sequence (N.succ (world_sequence value)) (decision_world result)
   else decision_world result in
 (committed,Notifications.envelope durable admitted input value result)
 end end end
 else (value,Observation.envelope false (reject "invalid_input" "The complete input exceeds the native frame bound" value)).
