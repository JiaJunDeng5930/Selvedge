From Selvedge.Programming Require DecisionComposition.
From Selvedge.Programming Require InputRoute.
From Selvedge.Programming Require CommitPacket.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json TextJson.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import Numbers Domain Codec State Inputs InputDecoder Queries CommandExecution
 Callbacks HookCallbacks Scheduler Recovery Observation Notifications Delivery Limits.
From Selvedge.Kernel Require Import CommandHandlers ForkCommit.
From Selvedge.Kernel Require CreationCommit NativeForkCommit TerminalSettlement.
From Selvedge.Kernel Require DeferredCommit.
From Selvedge.Kernel Require BoardCommit ConnectionCommit CompactionCommit TitleCommit RequestDelivery.
From Selvedge.Features Require Import Runtime.
From Selvedge.Features Require Board BoardFacts.
From Selvedge.Interaction Require UserCommand.
From Selvedge.Interaction.Experience Require Publication.
Import ListNotations.
Open Scope string_scope.
Definition initial := State.initial.
Definition world_json := Publication.world_json.
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
 | None => CommandHandlers.execute command context value
 end.
Definition card_save_consequence (command:Selvedge.Generated.Commands.command) (result:decision) := match command with
 |Cmd_create_card _|Cmd_update_card _=>
  match UserCommand.feedback_of (decision_reply result) with
  |Some (UserCommand.Accepted reply)=>
   match natural_field "card_id" reply with
   |Some id=>Board.save_consequence id (decision_world result)|None=>None end
  |_=>None end
 |_=>None end.
(* Assess against the worker's authoritative immutable world. The hypothetical
   decision is discarded: no world, scheduler work or IO effect is committed. *)
Definition assess (source : json) (value : world) : json :=
 let '(candidate,consequence) := match Selvedge.Generated.Commands.admit (value_or_null "command" source) with
 | Some admitted => let command:=Selvedge.Generated.Commands.admitted_value admitted in
   let result:=execute_domain command None value in
   (decision_reply result,card_save_consequence command result)
 | None => (State.failure "invalid_input" (InputDecoder.command_diagnostic (value_or_null "command" source)),None)
 end in
 let '(admitted, refusal) := UserCommand.assessment candidate in
 JObject [("editor",value_or_null "editor" source);("revision",value_or_null "revision" source);
   ("sequence",number (world_sequence value));("admitted",JBool admitted);
   ("refusal",refusal);("card_save_consequence",match consequence with
   |Some value=>JString(BoardFacts.save_consequence_name value)|None=>JNull end)].
Definition schedule_command (command : Selvedge.Generated.Commands.command) (value : world) (result : decision) :=
 if command_schedules command result then Selvedge.Features.Runtime.after_transition value result else result.
Definition execute_command (command : Selvedge.Generated.Commands.command) (context : option Tasks.native_call) (value : world) :=
 schedule_command command value (execute_domain command context value).
Definition mutation_transition (command : Selvedge.Generated.Commands.command)
 (run : option Tasks.native_call -> world -> decision) (value : world) :=
 let result := schedule_command command value (run None value) in
 (true,command_schedules command result,Some (UserCommand command),result).
Definition core_transition (source : Inputs.input) (value : world) :=
 match source with
 | UserCommand command => execute_command command None value
 | Configure environment =>
   let result := Selvedge.Features.Runtime.reconfigure (with_environment environment value) in
   Decision (decision_world result) (success JNull) (decision_effects result)
 | ContextCompleted id ticket observations diagnostic => Selvedge.Features.Runtime.after_context_transition value (Some (id,ticket))
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
Definition input_route := (Inputs.input + (world -> bool * bool * decision))%type.
Definition input_routes := DeclarationRegistry.declare (@InputRoute.identity input_route)
 (List.map (InputRoute.map (@inl Inputs.input (world -> bool * bool * decision))) InputDecoder.inputs ++
  List.map (InputRoute.map (@inr Inputs.input (world -> bool * bool * decision)))
    (Selvedge.Features.Runtime.completion_inputs execute_domain)).
Definition decode := InputRoute.decode input_routes.
Definition core_input (decoded : option input_route) := match decoded with
 | Some (inl input) => Some input | _ => None end.
Definition transition_decoded (decoded : option input_route) (source : json) (value : world)
 : bool * bool * option Inputs.input * decision :=
 match decoded with
 | Some (inl (UserCommand command)) => match CommandHandlers.interpret command false with
   | CommandHandlers.Observation run => (false,false,Some (UserCommand command),Decision value (run None value) [])
   | CommandHandlers.Mutation run => mutation_transition command run value end
 | Some (inl input) => (true,match input with Configure _ => false | _ => true end,Some input,core_transition input value)
 | Some (inr complete) =>
   let '(durable,schedules,result) := complete value in
   (durable,schedules,None,if schedules then Selvedge.Features.Runtime.after_transition value result else result)
 | None => (false,false,None,reject "invalid_input"
     (match InputRoute.selected input_routes source with
      | Some entry => InputDecoder.diagnostic entry source
      | None => "Unknown input kind or malformed domain callback" end) value)
 end.
Definition callback_input (source : option Inputs.input) :=
 match source with
 | Some (UserCommand _) | Some (Configure _) | Some Recover | Some Continue => false
 | _ => true end.
Definition preparation (schedules : bool) (source : option Inputs.input) : DecisionComposition.transformation :=
 if schedules then
   if callback_input source then RequestDelivery.deferral
   else RequestDelivery.scheduling execute_command Selvedge.Features.Runtime.can_schedule_task
 else fun _ value effects => (value,effects).
Definition prepare schedules source := DecisionComposition.transform (preparation schedules source).
Definition manual_fork_input (decoded : option Inputs.input) : option Selvedge.Generated.Commands.fork_payload :=
 match decoded with
 | Some (UserCommand (Selvedge.Generated.Commands.Cmd_fork request)) => Some request
 | _ => None
 end.
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
Definition select_change (decoded : option Inputs.input) (value : world)
 (ordinary : unit -> bool * bool * option Inputs.input * decision) : CommitPacket.selected :=
 match manual_fork_input decoded with
 | Some request => ForkCommit.select request value
 | None => match CreationCommit.input decoded with
 | Some request => CreationCommit.select request value
 | None => match deferred_candidate decoded value with
 | Some (input,candidate) => DeferredCommit.select true (Some input) value candidate
 | None =>
 let '(durable,schedules,input,result) := ordinary tt in
 DeferredCommit.select durable input value (prepare schedules input result)
 end end end.
(** The actual interpretation separates observation from mutation before any
    transaction selector can run. An observation supplies only its reply;
    world, effects and durability are fixed by this shared construction. *)
Definition select (source : json) (value : world) : CommitPacket.selected :=
 let received := decode source in
 match received with
 | Some (inl (UserCommand command)) => match CommandHandlers.interpret command false with
   | CommandHandlers.Observation run =>
     DeferredCommit.select false (Some (UserCommand command)) value (Decision value (run None value) [])
   | CommandHandlers.Mutation run =>
     select_change (Some (UserCommand command)) value (fun _ => mutation_transition command run value)
   end
 | _ => select_change (core_input received) value (fun _ => transition_decoded received source value)
 end.
Definition packet (source : json) (value : world) : world * json :=
 if N.leb (N.of_nat (String.length (TextJson.render_json source))) Limits.frame_bytes then
 CommitPacket.finalize value (select source value)
 else (value,Observation.envelope false (reject "invalid_input" "The complete input exceeds the native frame bound" value)).
