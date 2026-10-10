import Base
import ../submission/FIELDS.bend as OperationParameters
import ../IDENTITY.bend as Identity
import ./MODEL.bend as Actual
import ../session/MODEL.bend as E
import ../../harness/DOMAIN.bend as D
import ../../harness/tasks/PROGRAM.bend as Tasks
import ../../harness/conversation/CONTRACT.bend as Spec
import ../../harness/MODEL.bend as M
import ../../bendlib/json.bend as J
import ../presentation/PROGRAM.bend as InterfaceView
import ../INPUT.bend as U
import ../presentation/SURFACE.bend as SurfaceTypes
import ../TYPES.bend as InteractionTypes

def request_context(value: Actual.DecisionRequest) -> D.TaskContext:
  match value:
    case Actual.HumanDecision{operation, call, context, approve, deny, enabled}: context
    case Actual.AutomaticDecision{operation, call, context, reviewer}: context

def timeline_decisions(value: Actual.Timeline) -> +List<Actual.DecisionRequest>:
  Actual.Timeline{task, generation, groups, operations, decisions, reading, latest} = value
  decisions

def expected_serialized_parameter(result: Result<&2, &2, String, String>) -> String:
  match result:
    case Done{text}: text
    case Fail{reason}: "Serialization failed: " ++ reason

def expected_parameter(value: J.Json) -> String:
  match value:
    case J.Text{text}: text
    case other: expected_serialized_parameter(J.show(other))

def RenderedParameter(-value: J.Json) -> Type:
  Sigma<&2, &1, String, (text =>
    {J.show(value) == Done{text} : Result<&2, &2, String, String>} &
    {InterfaceView.approval_serialized(J.show(value)) == text : String})>

def expected_argument_label(name: String) -> String:
  OperationParameters.label(name)

def expected_fields(fields: List<&2, J.Field>, +index: Nat, +parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match fields:
    case Nil{}: Nil{}
    case Con{J.Field{name, value}, rest}:
      SurfaceTypes.Node{Identity.Part{parent, "argument/" ++ Nat.show(index)}, "argument/" ++ Nat.show(index),
        expected_argument_label(name), SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{expected_parameter(value)}, Nil{}} <>
        expected_fields(rest, (index + 1n : Nat), parent)

def expected_arguments(arguments: J.Json, +parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match arguments:
    case J.Object{fields}: expected_fields(fields, 0n, parent)
    case other: [SurfaceTypes.Node{Identity.Part{parent, "arguments"}, "arguments", "Arguments", SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{expected_parameter(other)}, Nil{}}]

def expected_directory(context: D.TaskContext, +parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  D.TaskContext{D.Workspace{roots, primary}, sandbox, approval, project} = context
  match primary:
    case None{}: Nil{}
    case Some{path}: [SurfaceTypes.Node{Identity.Part{parent, "default-directory"}, "default-directory", "Default working directory", SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{path}, Nil{}}]

def expected_metadata(call: D.Call, context: D.TaskContext, +parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  D.Call{id, name, arguments} = call
  SurfaceTypes.Node{Identity.Part{parent, "tool"}, "tool", "Tool", SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{name}, Nil{}} <>
    List.append(&2, SurfaceTypes.Node, expected_arguments(arguments, parent), expected_directory(context, parent))

def reviewer_name(reviewer: D.Profile) -> String:
  D.Profile{key, provider, name, reasoning, options} = reviewer
  name

def audit_message(message: D.Message) -> Bool:
  match message:
    case D.UserMessage{text}: False{}
    case D.AssistantMessage{text}: False{}
    case D.ModelContext{value}: False{}
    case _: True{}

# Comparison reflexivity is needed to bind a reader's choice to its own group.

def activity_presentation(values: +List<Actual.VisibleGroup>) -> Bool & String:
  match values:
    case Con{Actual.VisibleActivity{id, attention, expanded, summary, audit, expand, collapse}, rest}: (expanded, summary)
    case _: (False{}, "")

# A deliberate collapse leaves the real failure title in the persistent summary.

def first_identity(values: +List<Actual.Group>) -> Maybe<&2, Nat>:
  match values:
    case Nil{}: None{}
    case Con{Actual.Speech{id, speaker, text, source}, rest}: Some{id}
    case Con{Actual.Activity{id, attention, entries}, rest}: Some{id}

type Requirements is Type:
  Requirements{
    request_context: @+reviewer:D.ApprovalReviewer -> @id:Nat -> @call:D.Call -> @+context:D.TaskContext -> @task:Nat -> @world:M.World() ->
      {request_context(Actual.decision(reviewer, id, call, context, task, world)) == context : D.TaskContext},
    owning_context: @reader:E.Reader -> @+task:D.Task -> @+world:M.World() ->
      {timeline_decisions(Actual.timeline(reader, task, world)) ==
        Actual.decisions(D.task_operations(task), D.task_context(task), D.task_id(task), world) : +List<Actual.DecisionRequest>},
    approval_metadata: @+call:D.Call -> @+context:D.TaskContext -> @+parent: Identity.Key ->
      {InterfaceView.approval_metadata(call, context, parent) == expected_metadata(call, context, parent) : +List<SurfaceTypes.Node>},
    serialized_parameter: @+value:J.Json -> RenderedParameter(value),
    human_decision: @+operation:Nat -> @call:D.Call -> @context:D.TaskContext -> @+approve:U.Input -> @+deny:U.Input -> @+enabled:Bool -> @+parent: Identity.Key -> @+state:InteractionTypes.State ->
      {InterfaceView.approvals([Actual.HumanDecision{operation, call, context, approve, deny, enabled}], parent, state) ==
        [SurfaceTypes.Node{Identity.Entity{parent, "approval", Nat.show(operation)}, "approval/" ++ Nat.show(operation), "Approval required", SurfaceTypes.Approval{}, SurfaceTypes.Region{}, List.append(&2, SurfaceTypes.Node, InterfaceView.approval_metadata(call, context, Identity.Entity{parent, "approval", Nat.show(operation)}),
            [InterfaceView.user_action(Identity.Entity{parent, "approval", Nat.show(operation)}, "approve", "Approve once", approve, enabled, state),
             InterfaceView.user_action(Identity.Entity{parent, "approval", Nat.show(operation)}, "deny", "Deny", deny, enabled, state)])}] : +List<SurfaceTypes.Node>},
    automatic_decision: @+operation:Nat -> @call:D.Call -> @context:D.TaskContext -> @+reviewer:D.Profile -> @+parent: Identity.Key -> @state:InteractionTypes.State ->
      {InterfaceView.approvals([Actual.AutomaticDecision{operation, call, context, reviewer}], parent, state) ==
        [SurfaceTypes.Node{Identity.Entity{parent, "approval", Nat.show(operation)}, "approval/" ++ Nat.show(operation), "Automatic review", SurfaceTypes.Approval{}, SurfaceTypes.Region{}, List.append(&2, SurfaceTypes.Node, InterfaceView.approval_metadata(call, context, Identity.Entity{parent, "approval", Nat.show(operation)}),
            [SurfaceTypes.Node{Identity.Part{Identity.Entity{parent, "approval", Nat.show(operation)}, "reviewer"}, "reviewer", "Reviewer model", SurfaceTypes.Content{},
              SurfaceTypes.ReadOnly{reviewer_name(reviewer)}, Nil{}}])}] : +List<SurfaceTypes.Node>},
    approval_detail: @+task:Nat -> @+operation:Nat -> @+call:D.Call -> @+reviewer:D.ApprovalReviewer -> @+outcome:D.ApprovalOutcome ->
      {Actual.audit_detail(D.ApprovalRecord{task, operation, call, reviewer, outcome}) ==
        Actual.json_detail(J.show(Tasks.message_json(D.ApprovalRecord{task, operation, call, reviewer, outcome}))) : String},
    audit_classification: @+message:D.Message -> @+index:Nat -> @+tail:+List<Actual.Group> -> @is_audit:{audit_message(message) == True{} : Bool} ->
      {Actual.prepend(message, index, tail) == Actual.prepend_audit(index, Actual.audit_failed(message), message, tail) : +List<Actual.Group>},
    disclosure: @+group:Nat -> @seen:Nat -> @+choice:Bool -> @+attention:Maybe<&2, Nat> -> @+rest:+List<E.Disclosure> ->
      {Actual.expanded(E.Disclosure{group, seen, choice} <> rest, group, attention) == choice : Bool},
    collapsed_attention: @+group:Nat -> @seen:Nat -> @+attention:Maybe<&2, Nat> -> @+entries:+List<Actual.Audit> -> @task:Nat -> @+index:Nat -> @+message:D.Message ->
      @observed:{Actual.latest_failure(entries) == Some{Actual.Audit{index, message}} : Maybe<&2, Actual.Audit>} ->
      {activity_presentation(Actual.visible([Actual.Activity{group, attention, entries}], task,
        [E.Disclosure{group, seen, False{}}])) ==
        (False{}, "Failure: " ++ Actual.audit_title(message) ++ " · " ++ Nat.show(List.length(&2, Actual.Audit, entries)) ++ " events") : Bool & String},
    newest_failure: @+entries:+List<Actual.Audit> -> @+index:Nat -> @+message:D.Message -> @+failed:{Actual.audit_failed(message) == True{} : Bool} ->
      {Actual.latest_failure(List.append(&2, Actual.Audit, entries, [Actual.Audit{index, message}])) == Some{Actual.Audit{index, message}} : Maybe<&2, Actual.Audit>},
    identity: @+index:Nat -> @+failed:Bool -> @+message:D.Message -> @+suffix:+List<D.Message> -> @more:+List<D.Message> ->
      {first_identity(Actual.prepend_audit(index, failed, message,
        Actual.groups(List.append(&2, D.Message, suffix, more), (index + 1n : Nat)))) ==
        first_identity(Actual.prepend_audit(index, failed, message, Actual.groups(suffix, (index + 1n : Nat)))) : Maybe<&2, Nat>},
    history: @+messages:+List<D.Message> -> @+offset:Nat ->
      {Spec.sources(Actual.groups(messages, offset)) == messages : +List<D.Message>},
    visible_history: @+groups:+List<Actual.Group> -> @+task:Nat -> @+disclosures:+List<E.Disclosure> ->
      {Spec.visible_sources(Actual.visible(groups, task, disclosures)) == Spec.sources(groups) : +List<D.Message>},
    text: @+messages:+List<D.Message> -> @+offset:Nat -> @task:Nat -> @disclosures:+List<E.Disclosure> ->
      Spec.visible_text_agreement(Actual.visible(Actual.groups(messages, offset), task, disclosures))
  }

law evidence:
  Requirements
