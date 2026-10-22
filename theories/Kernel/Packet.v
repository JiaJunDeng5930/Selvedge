From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json TextJson.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import Numbers Domain Codec State Inputs InputDecoder Queries CommandExecution
 Callbacks HookCallbacks Scheduler Recovery Observation Notifications Delivery Limits WorldInvariant.
From Selvedge.Features Require Import Runtime.
Import ListNotations.
Open Scope string_scope.
Definition initial := State.initial.
Definition world_json := Observation.world_json.
Definition query (command : Selvedge.Generated.Commands.command) (caller : option N) (value : world) :=
 match Queries.answer command value with Some reply => Some reply | None => Selvedge.Features.Runtime.query command caller value end.
Definition command_schedules (command : Selvedge.Generated.Commands.command) (result : decision) :=
 bool_default "ok" (decision_reply result) false &&
 match command with
 | Selvedge.Generated.Commands.Cmd_create_idle _ | Selvedge.Generated.Commands.Cmd_record_speech_transcript _ => false
 | Selvedge.Generated.Commands.Cmd_accept_speech_delegation _ => negb (bool_default "replayed" (value_or_null "result" (decision_reply result)) false)
 | _ => Selvedge.Features.Runtime.schedules command end.
Definition execute_domain (command : Selvedge.Generated.Commands.command) (caller : option N) (value : world) : decision :=
 match query command caller value with
 | Some reply => Decision value reply []
 | None => match Selvedge.Features.Runtime.guard_command command caller value with
   | Some refused => refused
   | None =>
     let result := match Selvedge.Features.Runtime.command command caller value with
     | Some result => result | None => match CommandExecution.execute command caller value with
       | Some result => result
       | None => reject "unknown_command" "The command has no domain interpreter" value end end in
     Selvedge.Features.Runtime.guard_result value result
   end
 end.
(* Assess against the worker's authoritative immutable world. The hypothetical
   decision is discarded: no world, scheduler work or IO effect is committed. *)
Definition assess (source : json) (value : world) : json :=
 let candidate := match Selvedge.Generated.Commands.decode (value_or_null "command" source) with
 | Some command => decision_reply (execute_domain command None value)
 | None => State.failure "invalid_input" "Malformed input for the declared protocol"
 end in
 let admitted := bool_default "ok" candidate false in
 JObject [("editor",value_or_null "editor" source);("revision",value_or_null "revision" source);
   ("sequence",number (world_sequence value));("admitted",JBool admitted);
   ("refusal",if admitted then JNull else value_or_null "error" candidate)].
Definition execute_command (command : Selvedge.Generated.Commands.command) (caller : option N) (value : world) :=
 let result := execute_domain command caller value in
 if command_schedules command result then Selvedge.Features.Runtime.after_transition value result else result.
Definition core_transition (source : input) (value : world) :=
 match source with
 | UserCommand command => execute_command command None value
 | Configure environment => accept (JObject [("configured",JBool true)]) (with_environment environment value) []
 | ContextCompleted id ticket observations diagnostic => Selvedge.Features.Runtime.after_transition value
   (Callbacks.context_completed id ticket observations diagnostic value)
 | ModelCompleted id ticket ModelContextLimit => Selvedge.Features.Runtime.after_transition value (Selvedge.Features.Runtime.model_context_limit id ticket value)
 | ModelCompleted id ticket outcome => Selvedge.Features.Runtime.after_transition value (Callbacks.model_completed id ticket outcome value)
 | ReasoningCompleted id ticket outcome => Selvedge.Features.Runtime.after_transition value (Callbacks.reasoning_completed id ticket outcome value)
 | ToolCompleted id ticket result error => Selvedge.Features.Runtime.after_transition value (Callbacks.tool_completed id ticket result error value)
 | HookCompleted id ticket outcome => Selvedge.Features.Runtime.after_transition value (HookCallbacks.hook_completed id ticket outcome value)
 | AfterCompleted id operation ticket outcome => Selvedge.Features.Runtime.after_transition value (HookCallbacks.after_completed id operation ticket outcome value)
 | ApprovalCompleted id ticket outcome => Selvedge.Features.Runtime.after_transition value (Callbacks.approval_completed id ticket outcome value)
 | Recover => Selvedge.Features.Runtime.after_transition value (Recovery.recover (Selvedge.Features.Runtime.recover value))
 | Continue => Selvedge.Features.Runtime.after_transition value (accept JNull value [])
 end.
Definition transition (source : json) (value : world) : bool * bool * option input * decision :=
 match InputDecoder.decode source with
 | Some (UserCommand command) => match query command None value with
   | Some reply => (false,false,Some (UserCommand command),Decision value reply [])
   | None => let result := execute_command command None value in
     (true,command_schedules command result,Some (UserCommand command),result) end
 | Some input => (true,match input with Configure _ => false | _ => true end,Some input,core_transition input value)
 | None => if InputDecoder.owns_kind source then
     (false,false,None,reject "invalid_input" "Malformed input for the declared protocol" value)
   else match Selvedge.Features.Runtime.completion execute_domain source value with
     | Some (durable,schedules,result) => (durable,schedules,None,if schedules then Selvedge.Features.Runtime.after_transition value result else result)
     | None => (false,false,None,reject "invalid_input" "Unknown input kind or malformed domain callback" value)
     end
 end.
Definition admit (durable : bool) (source : option input) (before : world) (result : decision) :=
 Delivery.deliver durable (WorldInvariant.validate before (Notifications.decorate durable source before result)) before.
Definition packet (source : json) (value : world) : world * json :=
 if N.leb (N.of_nat (String.length (TextJson.render_json source))) Limits.frame_bytes then
 let '(durable,schedules,input,result) := transition source value in
 let result := if schedules then Selvedge.Features.Runtime.finish (Scheduler.run execute_command Selvedge.Features.Runtime.can_schedule_task result) else result in
 let result := admit durable input value result in
 let committed := if durable then with_sequence (N.succ (world_sequence value)) (decision_world result)
   else decision_world result in
 (committed,Observation.envelope durable result)
 else (value,Observation.envelope false (reject "invalid_input" "The complete input exceeds the native frame bound" value)).
