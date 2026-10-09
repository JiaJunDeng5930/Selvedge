import Base
import ../../harness/MODEL.bend as M
import ../../harness/COMMANDS.bend as Commands
import ../../harness/DOMAIN.bend as D
import ../../harness/tasks/PROGRAM.bend as Tasks
import ../../harness/conversation/PROGRAM.bend as Content
import ../INPUT.bend as U
import ../session/MODEL.bend as E
import ../../bendlib/json.bend as J

type Speaker is Data:
  UserSpeech{}
  AssistantSpeech{}

type Audit is Data:
  Audit{occurrence: Nat, message: D.Message}

type AuditKind is Data:
  ToolInvocation{}
  ToolResult{}
  Reasoning{}
  ContextChange{}
  PermissionDecision{}
  Diagnostic{}
  TaskRelation{}

type AuditFace is Data:
  AuditFace{occurrence: Nat, kind: AuditKind, title: String, source: D.Message}

type Group is Data:
  Speech{identity: Nat, speaker: Speaker, text: String, source: D.Message}
  Activity{identity: Nat, attention: Maybe<&2, Nat>, entries: +List<Audit>}

type VisibleGroup is Data:
  VisibleSpeech{identity: Nat, speaker: Speaker, text: String, source: D.Message}
  VisibleActivity{identity: Nat, attention: Maybe<&2, Nat>, expanded: Bool,
    summary: String, audit: +List<AuditFace>, expand: U.Input, collapse: U.Input}

type DecisionRequest is Data:
  HumanDecision{operation: Nat, call: D.Call, context: D.TaskContext, approve: U.Input, deny: U.Input, enabled: Bool}
  AutomaticDecision{operation: Nat, call: D.Call, context: D.TaskContext, reviewer: D.Profile}

type LiveOperation is Data:
  LiveOperation{id: Nat, body: D.OperationBody, cancel: U.Input, cancellable: Bool}

type Timeline is Data:
  Timeline{task: Nat, generation: Nat, groups: +List<VisibleGroup>, operations: +List<LiveOperation>,
    decisions: +List<DecisionRequest>, reading: U.ReadingIntent,
    return_to_latest: Maybe<&2, U.Input>}

type Identity is Data:
  Identity{task: Nat, generation: Nat}

def identity(timeline: Timeline) -> Identity:
  Timeline{task, generation, groups, operations, decisions, reading, return_to_latest} = timeline
  Identity{task, generation}

def failure_occurrence(failed: Bool, index: Nat) -> Maybe<&2, Nat>:
  match failed:
    case True{}: Some{index}
    case False{}: None{}

def latest_attention(later: Maybe<&2, Nat>, earlier: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match later:
    case Some{id}: Some{id}
    case None{}: earlier

# Identity comes from the first audit occurrence. Attention comes from the most
# recent failure. Explicit disclosure choices remain owned by the reader.

def prepend_audit(+index: Nat, failed: Bool, message: D.Message, tail: +List<Group>) -> +List<Group>:
  match tail:
    case Con{Activity{id, attention, entries}, rest}:
      Activity{index, latest_attention(attention, failure_occurrence(failed, index)), Audit{index, message} <> entries} <> rest
    case rest: Activity{index, failure_occurrence(failed, index), [Audit{index, message}]} <> rest

def approval_failed(outcome: D.ApprovalOutcome) -> Bool:
  match outcome:
    case D.ApprovalAllowed{reason}: False{}
    case _: True{}

def hook_failed(outcome: D.HookOutcome) -> Bool:
  match outcome:
    case D.DenyTool{reason}: True{}
    case D.HookFailure{reason}: True{}
    case _: False{}

def after_failed(outcome: D.AfterOutcome) -> Bool:
  match outcome:
    case D.DenyResult{reason}: True{}
    case D.AfterFailure{reason}: True{}
    case _: False{}

def audit_failed(message: D.Message) -> Bool:
  match message:
    case D.FailureMessage{text}: True{}
    case D.FunctionOutput{id, value, error}: error
    case D.OperationResult{ticket, id, tool, value, error}: error
    case D.ToolReceipt{task, operation, call, value, error}: error
    case D.ApprovalRecord{task, operation, call, reviewer, outcome}: approval_failed(outcome)
    case D.HookRecord{task, call, plugin, outcome}: hook_failed(outcome)
    case D.AfterRecord{task, operation, plugin, outcome}: after_failed(outcome)
    case _: False{}

def provider_speech(is_assistant: Bool, index: Nat, +value: J.Json, tail: +List<Group>) -> +List<Group>:
  match is_assistant:
    case True{}: Speech{index, AssistantSpeech{}, Content.content_parts(J.items(J.get(value, "content"))), D.ModelContext{value}} <> tail
    case False{}: prepend_audit(index, audit_failed(D.ModelContext{value}), D.ModelContext{value}, tail)

def provider_group(kind: Content.ContextKind, index: Nat, +value: J.Json, tail: +List<Group>) -> +List<Group>:
  match kind:
    case Content.SpeechContext{}: provider_speech(String.eq(J.text(J.get(value, "role")), "assistant"), index, value, tail)
    case _: prepend_audit(index, audit_failed(D.ModelContext{value}), D.ModelContext{value}, tail)

def prepend(message: D.Message, index: Nat, tail: +List<Group>) -> +List<Group>:
  match message:
    case D.UserMessage{+text}: Speech{index, UserSpeech{}, text, D.UserMessage{text}} <> tail
    case D.AssistantMessage{+text}: Speech{index, AssistantSpeech{}, text, D.AssistantMessage{text}} <> tail
    case D.ModelContext{+value}: provider_group(Content.context_kind(J.text(J.get(value, "type"))), index, value, tail)
    case +other: prepend_audit(index, audit_failed(other), other, tail)

def audit_kind(message: D.Message) -> AuditKind:
  match message:
    case D.FunctionCall{call}: ToolInvocation{}
    case D.FunctionOutput{id, value, error}: ToolResult{}
    case D.OperationResult{ticket, id, tool, value, error}: ToolResult{}
    case D.ToolReceipt{task, operation, call, value, error}: ToolResult{}
    case D.FailureMessage{text}: Diagnostic{}
    case D.ReasoningRecord{owner, effort, remaining, sampling}: Reasoning{}
    case D.HookRecord{task, call, plugin, outcome}: PermissionDecision{}
    case D.ApprovalRecord{task, operation, call, reviewer, outcome}: PermissionDecision{}
    case D.AfterRecord{task, operation, plugin, outcome}: ToolResult{}
    case D.ForkResult{task, call, branch}: TaskRelation{}
    case _: ContextChange{}

def call_name(call: D.Call) -> String:
  D.Call{id, name, arguments} = call
  name

def audit_title(message: D.Message) -> String:
  match message:
    case D.FunctionCall{call}: call_name(call)
    case D.FunctionOutput{id, value, error}: "Tool output"
    case D.OperationResult{ticket, id, tool, value, error}: tool
    case D.ToolReceipt{task, operation, call, value, error}: call_name(call)
    case D.FailureMessage{text}: text
    case D.ReasoningRecord{owner, effort, remaining, sampling}: "Reasoning: " ++ effort
    case D.HookRecord{task, call, plugin, outcome}: "Tool permission check"
    case D.ApprovalRecord{task, operation, call, reviewer, outcome}: "Approval: " ++ D.approval_decision(outcome)
    case D.AfterRecord{task, operation, plugin, outcome}: "Tool result processing"
    case D.ForkResult{task, call, branch}: "Task fork"
    case D.ContextCheckpoint{summary}: "Context compacted"
    case D.ConfigurationUpdate{effort}: "Reasoning changed to " ++ effort
    case D.ModelContext{value}: "Model activity"
    case _: "Conversation event"

def audit_faces(entries: +List<Audit>) -> +List<AuditFace>:
  match entries:
    case Nil{}: Nil{}
    case Con{Audit{index, +message}, rest}: AuditFace{index, audit_kind(message), audit_title(message), message} <> audit_faces(rest)

def failure_candidate(failed: Bool, entry: Audit) -> Maybe<&2, Audit>:
  match failed:
    case True{}: Some{entry}
    case False{}: None{}

def prefer_failure(later: Maybe<&2, Audit>, earlier: Maybe<&2, Audit>) -> Maybe<&2, Audit>:
  match later:
    case Some{entry}: Some{entry}
    case None{}: earlier

def latest_failure(entries: +List<Audit>) -> Maybe<&2, Audit>:
  match entries:
    case Nil{}: None{}
    case Con{Audit{+index, +message}, rest}:
      prefer_failure(latest_failure(rest), failure_candidate(audit_failed(message), Audit{index, message}))

def operation_count(entries: +List<Audit>) -> Nat:
  match entries:
    case Nil{}: 0n
    case Con{Audit{index, D.FunctionCall{call}}, rest}: (1n + operation_count(rest) : Nat)
    case Con{other, rest}: operation_count(rest)

def current_activity(entries: +List<Audit>) -> String:
  match entries:
    case Nil{}: "Activity"
    case Con{Audit{index, message}, Nil{}}: audit_title(message)
    case Con{entry, rest}: current_activity(rest)

def summarized_activity(failure: Maybe<&2, Audit>, +entries: +List<Audit>) -> String:
  match failure:
    case Some{Audit{index, message}}:
      "Failure: " ++ audit_title(message) ++ " · " ++ Nat.show(List.length(&2, Audit, entries)) ++ " events"
    case None{}: current_activity(entries) ++ " · " ++ Nat.show(operation_count(entries)) ++ " operations"

def activity_summary(+entries: +List<Audit>) -> String:
  summarized_activity(latest_failure(entries), entries)

def json_detail(result: Result<&2, &2, String, String>) -> String:
  match result:
    case Done{text}: text
    case Fail{reason}: "Unable to display JSON: " ++ reason

def result_detail(error: Bool, value: J.Json) -> String:
  match error:
    case True{}: "Error\n" ++ json_detail(J.show(value))
    case False{}: "Result\n" ++ json_detail(J.show(value))

def audit_detail(message: D.Message) -> String:
  match message:
    case D.FunctionCall{D.Call{id, name, arguments}}: name ++ "\n" ++ json_detail(J.show(arguments))
    case D.FunctionOutput{id, value, error}: result_detail(error, value)
    case D.OperationResult{ticket, id, tool, value, error}: tool ++ "\n" ++ result_detail(error, value)
    case D.ToolReceipt{task, operation, D.Call{id, name, arguments}, value, error}: name ++ "\n" ++ result_detail(error, value)
    case D.ApprovalRecord{task, operation, call, reviewer, outcome}: json_detail(J.show(Tasks.message_json(D.ApprovalRecord{task, operation, call, reviewer, outcome})))
    case D.HookRecord{task, call, plugin, outcome}: json_detail(J.show(D.hook_json(outcome)))
    case D.AfterRecord{task, operation, plugin, outcome}: json_detail(J.show(D.after_json(outcome)))
    case D.FailureMessage{text}: text
    case D.ContextCheckpoint{summary}: summary
    case D.ModelContext{value}: json_detail(J.show(value))
    case other: audit_title(other)

def groups(messages: +List<D.Message>, +index: Nat) -> +List<Group>:
  match messages:
    case Nil{}: Nil{}
    case Con{message, rest}: prepend(message, index, groups(rest, (index + 1n : Nat)))

def attention_key(attention: Maybe<&2, Nat>) -> Nat:
  match attention:
    case None{}: 0n
    case Some{id}: (id + 1n : Nat)

def has_attention(attention: Maybe<&2, Nat>) -> Bool:
  match attention:
    case None{}: False{}
    case Some{id}: True{}

def choose_expanded(hit: Bool, value: Bool, fallback: Bool) -> Bool:
  match hit:
    case True{}: value
    case False{}: fallback

def expanded(disclosures: +List<E.Disclosure>, +group: Nat, +attention: Maybe<&2, Nat>) -> Bool:
  match disclosures:
    case Nil{}: has_attention(attention)
    case Con{E.Disclosure{id, seen, value}, rest}:
      choose_expanded(Nat.is_eq(id, group), value, expanded(rest, group, attention))

def visible(groups: +List<Group>, +task: Nat, +disclosures: +List<E.Disclosure>) -> +List<VisibleGroup>:
  match groups:
    case Nil{}: Nil{}
    case Con{Speech{id, speaker, text, source}, rest}: VisibleSpeech{id, speaker, text, source} <> visible(rest, task, disclosures)
    case Con{Activity{+id, +attention, +entries}, rest}:
      VisibleActivity{id, attention, expanded(disclosures, id, attention), activity_summary(entries), audit_faces(entries),
        U.SetDisclosure{task, id, attention_key(attention), True{}}, U.SetDisclosure{task, id, attention_key(attention), False{}}} <> visible(rest, task, disclosures)

def permitted(command: Maybe<&2, M.Command>, world: M.World()) -> Bool:
  match command:
    case None{}: False{}
    case Some{command}: Commands.admitted(Commands.resolve(command, world))

def decision(reviewer: D.ApprovalReviewer, +id: Nat, call: D.Call, context: D.TaskContext, +task: Nat, world: M.World()) -> DecisionRequest:
  match reviewer:
    case D.HumanReviewer{}: HumanDecision{id, call, context,
      U.Activate{U.ReviewApproval{task, id, True{}, ""}}, U.Activate{U.ReviewApproval{task, id, False{}, ""}},
      permitted(U.direct_command(U.ReviewApproval{task, id, True{}, ""}), world)}
    case D.ModelReviewer{profile}: AutomaticDecision{id, call, context, profile}

def decisions(operations: +List<D.Operation()>, +context: D.TaskContext, +task: Nat, +world: M.World()) -> +List<DecisionRequest>:
  match operations:
    case Nil{}: Nil{}
    case Con{(id, D.OperationBody{call, announced, D.ApprovalPending{reviewer}}), rest}: decision(reviewer, id, call, context, task, world) <> decisions(rest, context, task, world)
    case Con{operation, rest}: decisions(rest, context, task, world)

def operations(entries: +List<D.Operation()>, +task: Nat, +world: M.World()) -> +List<LiveOperation>:
  match entries:
    case Nil{}: Nil{}
    case Con{(+id, body), rest}: LiveOperation{id, body, U.Activate{U.CancelOperation{task, id}},
      permitted(U.direct_command(U.CancelOperation{task, id}), world)} <> operations(rest, task, world)

def latest(reading: U.ReadingIntent, task: Nat, generation: Nat) -> Maybe<&2, U.Input>:
  match reading:
    case U.FollowLatest{}: None{}
    case U.ReadHistory{}: Some{U.ReadTimeline{task, generation, U.FollowLatest{}}}

def timeline(reader: E.Reader, +task: D.Task, +world: M.World()) -> Timeline:
  E.Reader{+generation, +position, disclosures} = reader
  Timeline{D.task_id(task), generation, visible(groups(D.history_messages(D.task_history(task), Nil{}), 0n), D.task_id(task), disclosures),
    operations(D.task_operations(task), D.task_id(task), world), decisions(D.task_operations(task), D.task_context(task), D.task_id(task), world), position, latest(position, D.task_id(task), generation)}
