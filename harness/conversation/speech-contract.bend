import Base
import ../DOMAIN.bend as D
import ../MODEL.bend as M
import ../COMMANDS.bend as Commands
import ../PROGRAM.bend as Program
import ../tasks/PROGRAM.bend as Tasks
import ../tasks/CONTRACT.bend as TaskRequirements
import ../features/MODEL.bend as Features
import ../protocol/COMMIT.bend as Commit
import ../../bendlib/component.bend as Component
import ../../bendlib/json.bend as J
import ./speech.bend as Speech

law transcript_changes_only_history:
  for session: String
  for item: String
  for speaker: D.SpeechSpeaker
  for completion: D.SpeechCompletion
  for text: String
  for id: Nat
  for lineage: +List<Nat>
  for contract: D.Contract
  for current: D.ExecutionConfiguration
  for status: D.Status
  for history: D.History
  for queued: +List<String>
  for phase: D.Phase
  for operations: +List<D.Operation()>
  for notified: Bool
  {Speech.record(session, item, speaker, completion, text,
      D.Task{id, lineage, contract, current, status, history, queued, phase, operations, notified}) ==
    D.Task{id, lineage, contract, current, status,
      D.HistoryNode{history, D.SpeechTranscript{id, session, item, speaker, completion, text}}, queued, phase, operations, notified} : D.Task}

law transcript_committed_operation:
  for +task: D.Task
  for +session: String
  for +item: String
  for speaker: D.SpeechSpeaker
  for completion: D.SpeechCompletion
  for text: String
  for world: M.World()
  {Program.realize_calculation(Commands.RecordSpeech{task, session, item, speaker, completion, text}, world) ==
    Component.Decision{Tasks.update_world(Features.State(), Speech.record(session, item, speaker, completion, text, task), world),
      D.success(Speech.transcript_result(D.task_id(task), session, item, False{})), Nil{}} : M.Decision()}

law transcript_never_schedules:
  for id: Nat
  for session: String
  for item: String
  for speaker: String
  for completion: String
  for text: String
  for decision: M.Decision()
  {M.input_mode(M.UserCommand{M.RecordSpeechTranscript{id, session, item, speaker, completion, text}}) == M.UpdateOnly{} : M.InputMode} &
  {Commit.schedules(M.UserCommand{M.RecordSpeechTranscript{id, session, item, speaker, completion, text}}, decision) == False{} : Bool}

law idle_creation_never_schedules:
  for profile: String
  for reasoning: String
  for settings: J.Json
  for work: Maybe<&2, Nat>
  for tree: Bool
  for decision: M.Decision()
  {M.input_mode(M.UserCommand{M.CreateIdle{profile, reasoning, settings, work, tree}}) == M.UpdateOnly{} : M.InputMode} &
  {Commit.schedules(M.UserCommand{M.CreateIdle{profile, reasoning, settings, work, tree}}, decision) == False{} : Bool}

law delegation_send_is_ordinary_input:
  for +session: String
  for +identity: String
  for +text: String
  for +task: D.Task
  {Speech.accepted(session, identity, "send", text, task) ==
    D.append_message(D.SpeechDelegationReceipt{D.task_id(task), session, identity, "send", text}, Tasks.receive(text, task)) : D.Task}

law delegation_steer_is_ordinary_input:
  for +session: String
  for +identity: String
  for +text: String
  for +task: D.Task
  {Speech.accepted(session, identity, "steer", text, task) ==
    D.append_message(D.SpeechDelegationReceipt{D.task_id(task), session, identity, "steer", text}, Tasks.steer(text, task)) : D.Task}

law delegation_send_committed_operation:
  for +task: D.Task
  for +session: String
  for +identity: String
  for message: String
  for world: M.World()
  {Program.realize_calculation(Commands.DelegateSpeech{task, session, identity, "send", message}, world) ==
    Component.Decision{Tasks.update_world(Features.State(),
      D.append_message(D.SpeechDelegationReceipt{D.task_id(task), session, identity, "send", message}, Tasks.receive(message, task)), world),
      D.success(Speech.delegation_result(D.task_id(task), session, identity, False{})), Nil{}} : M.Decision()}

law replay_changes_nothing:
  for result: J.Json
  for world: M.World()
  {Program.realize_calculation(Commands.ReplaySpeech{result}, world) == Component.Decision{world, D.success(result), Nil{}} : M.Decision()}

law idle_initial_history_has_no_input:
  for +instructions: D.InitialInstructions
  for +project: D.ProjectContext
  for +profile: D.Profile
  for +reasoning: String
  for tools: +List<D.Tool>
  for max_fork: Nat
  for max_descendants: Nat
  for plugins: +List<D.Plugin>
  for +context: D.TaskContext
  for +history: D.History
  {D.initial_contract_history(instructions, project,
    D.Contract{D.Model{profile, reasoning}, tools, max_fork, max_descendants, plugins, context}, history) ==
    TaskRequirements.initial_idle_history(instructions, project, context, profile, reasoning, history) : D.History}

law replayed_delegation_never_schedules:
  for id: Nat
  for +session: String
  for +identity: String
  for text: String
  for mode: String
  for world: M.World()
  {Commit.schedules(M.UserCommand{M.AcceptSpeechDelegation{id, session, identity, text, mode}},
    Component.Decision{world, D.success(Speech.delegation_result(id, session, identity, True{})), Nil{}}) == False{} : Bool}
