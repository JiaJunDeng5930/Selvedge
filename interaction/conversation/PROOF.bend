import ./CONTRACT.bend as Rule
import Base
import ../IDENTITY.bend as Identity
import ./MODEL.bend as Actual
import ../session/MODEL.bend as E
import ../../harness/DOMAIN.bend as D
import ../../harness/conversation/PROOF.bend as History
import ../../harness/MODEL.bend as M
import ../../bendlib/json.bend as J
import ../presentation/PROGRAM.bend as InterfaceView
import ../STATE.bend as Core
import ../INPUT.bend as U
import ../../bendlib/stdlib.bend as Std
import ../../harness/transport/json-render-rules.bend as JsonRender
import ../../harness/transport/json-render-proof.bend as JsonRenderProof

def false_goal(P: Type, value: Bool) -> Type:
  match value:
    case False{}: Unit
    case True{}: P

def impossible(P: Type, evidence: {False{} == True{} : Bool}) -> P:
  Std.transport(Bool, False{}, (value => false_goal(P, value)), Unit{}, True{},
    Equal.sym(Bool, False{}, True{}, evidence))

def serialized_parameter_witness(+value: J.Json, witness: JsonRender.Completed(J.show(value))) -> Rule.RenderedParameter(value):
  (+text, +completed) = witness
  (text, (completed,
    Equal.cong(Result<&2, &2, String, String>, String, InterfaceView.approval_serialized,
      J.show(value), Done{text}, completed)))

def serialized_parameter_requirements(+value: J.Json, requirements: JsonRender.Requirements) -> Rule.RenderedParameter(value):
  JsonRender.Requirements{sufficient, render_complete, show_complete, _} = requirements
  serialized_parameter_witness(value, show_complete(value))

def serialized_parameter(+value: J.Json) -> Rule.RenderedParameter(value):
  serialized_parameter_requirements(value, JsonRender.evidence())

def request_context(+reviewer: D.ApprovalReviewer, id: Nat, call: D.Call, +context: D.TaskContext, task: Nat, world: M.World()) ->
  {Rule.request_context(Actual.decision(reviewer, id, call, context, task, world)) == context : D.TaskContext}:
  match reviewer:
    case D.HumanReviewer{}: {==}
    case D.ModelReviewer{profile}: {==}

def owning_context(reader: E.Reader, +task: D.Task, +world: M.World()) ->
  {Rule.timeline_decisions(Actual.timeline(reader, task, world)) ==
    Actual.decisions(D.task_operations(task), D.task_context(task), D.task_id(task), world) : +List<Actual.DecisionRequest>}:
  match reader:
    case E.Reader{generation, position, disclosures}: {==}

def serialized_parameter_result(+result: Result<&2, &2, String, String>) ->
  {InterfaceView.approval_serialized(result) == Rule.expected_serialized_parameter(result) : String}:
  match result:
    case Done{text}: {==}
    case Fail{reason}: {==}

def parameter(+value: J.Json) -> {InterfaceView.approval_value(value) == Rule.expected_parameter(value) : String}:
  match value:
    case J.Text{text}: {==}
    case J.Null{}: serialized_parameter_result(J.show(J.Null{}))
    case J.Boolean{value}: serialized_parameter_result(J.show(J.Boolean{value}))
    case J.Number{lexeme}: serialized_parameter_result(J.show(J.Number{lexeme}))
    case J.Array{items}: serialized_parameter_result(J.show(J.Array{items}))
    case J.Object{fields}: serialized_parameter_result(J.show(J.Object{fields}))

def argument_label(+name: String) -> {InterfaceView.approval_argument_label(name) == Rule.expected_argument_label(name) : String}:
  {==}

def fields(+values: List<&2, J.Field>, +index: Nat, +parent: Identity.Key) ->
  {InterfaceView.approval_fields(values, index, parent) == Rule.expected_fields(values, index, parent) : +List<InterfaceView.Node>}:
  match values:
    case Nil{}: {==}
    case Con{J.Field{+name, +value}, +rest}:
      +key = "argument/" ++ Nat.show(index)
      Equal.trans(+List<InterfaceView.Node>,
        InterfaceView.approval_fields(J.Field{name, value} <> rest, index, parent),
        InterfaceView.approval_fact(parent, key, Rule.expected_argument_label(name), Rule.expected_parameter(value)) <>
          InterfaceView.approval_fields(rest, (index + 1n : Nat), parent),
        Rule.expected_fields(J.Field{name, value} <> rest, index, parent),
        Equal.trans(+List<InterfaceView.Node>,
          InterfaceView.approval_fields(J.Field{name, value} <> rest, index, parent),
          InterfaceView.approval_fact(parent, key, Rule.expected_argument_label(name), InterfaceView.approval_value(value)) <>
            InterfaceView.approval_fields(rest, (index + 1n : Nat), parent),
          InterfaceView.approval_fact(parent, key, Rule.expected_argument_label(name), Rule.expected_parameter(value)) <>
            InterfaceView.approval_fields(rest, (index + 1n : Nat), parent),
          Equal.cong(String, +List<InterfaceView.Node>, label => InterfaceView.approval_fact(parent, key, label, InterfaceView.approval_value(value)) <>
            InterfaceView.approval_fields(rest, (index + 1n : Nat), parent),
            InterfaceView.approval_argument_label(name), Rule.expected_argument_label(name), argument_label(name)),
          Equal.cong(String, +List<InterfaceView.Node>, text => InterfaceView.approval_fact(parent, key, Rule.expected_argument_label(name), text) <>
            InterfaceView.approval_fields(rest, (index + 1n : Nat), parent),
            InterfaceView.approval_value(value), Rule.expected_parameter(value), parameter(value))),
        Equal.cong(+List<InterfaceView.Node>, +List<InterfaceView.Node>, tail =>
          InterfaceView.approval_fact(parent, key, Rule.expected_argument_label(name), Rule.expected_parameter(value)) <> tail,
          InterfaceView.approval_fields(rest, (index + 1n : Nat), parent), Rule.expected_fields(rest, (index + 1n : Nat), parent),
          fields(rest, (index + 1n : Nat), parent)))

def arguments(+value: J.Json, +parent: Identity.Key) ->
  {InterfaceView.approval_arguments(value, parent) == Rule.expected_arguments(value, parent) : +List<InterfaceView.Node>}:
  match value:
    case J.Object{values}: fields(values, 0n, parent)
    case J.Null{}:
      Equal.cong(String, +List<InterfaceView.Node>, text => [InterfaceView.approval_fact(parent, "arguments", "Arguments", text)],
        InterfaceView.approval_value(J.Null{}), Rule.expected_parameter(J.Null{}), parameter(J.Null{}))
    case J.Boolean{value}:
      Equal.cong(String, +List<InterfaceView.Node>, text => [InterfaceView.approval_fact(parent, "arguments", "Arguments", text)],
        InterfaceView.approval_value(J.Boolean{value}), Rule.expected_parameter(J.Boolean{value}), parameter(J.Boolean{value}))
    case J.Number{lexeme}:
      Equal.cong(String, +List<InterfaceView.Node>, text => [InterfaceView.approval_fact(parent, "arguments", "Arguments", text)],
        InterfaceView.approval_value(J.Number{lexeme}), Rule.expected_parameter(J.Number{lexeme}), parameter(J.Number{lexeme}))
    case J.Text{text}:
      Equal.cong(String, +List<InterfaceView.Node>, text => [InterfaceView.approval_fact(parent, "arguments", "Arguments", text)],
        InterfaceView.approval_value(J.Text{text}), Rule.expected_parameter(J.Text{text}), parameter(J.Text{text}))
    case J.Array{items}:
      Equal.cong(String, +List<InterfaceView.Node>, text => [InterfaceView.approval_fact(parent, "arguments", "Arguments", text)],
        InterfaceView.approval_value(J.Array{items}), Rule.expected_parameter(J.Array{items}), parameter(J.Array{items}))

def directory(+context: D.TaskContext, +parent: Identity.Key) ->
  {InterfaceView.approval_directory(context, parent) == Rule.expected_directory(context, parent) : +List<InterfaceView.Node>}:
  D.TaskContext{D.Workspace{roots, primary}, sandbox, approval, project} = context
  match primary:
    case None{}: {==}
    case Some{path}: {==}

def metadata(+call: D.Call, +context: D.TaskContext, +parent: Identity.Key) ->
  {InterfaceView.approval_metadata(call, context, parent) == Rule.expected_metadata(call, context, parent) : +List<InterfaceView.Node>}:
  D.Call{+id, +name, +values} = call
  Equal.trans(+List<InterfaceView.Node>,
    InterfaceView.approval_metadata(D.Call{id, name, values}, context, parent),
    InterfaceView.approval_fact(parent, "tool", "Tool", name) <>
      List.append(&2, InterfaceView.Node, Rule.expected_arguments(values, parent), InterfaceView.approval_directory(context, parent)),
    Rule.expected_metadata(D.Call{id, name, values}, context, parent),
    Equal.cong(+List<InterfaceView.Node>, +List<InterfaceView.Node>, items => InterfaceView.approval_fact(parent, "tool", "Tool", name) <>
      List.append(&2, InterfaceView.Node, items, InterfaceView.approval_directory(context, parent)),
      InterfaceView.approval_arguments(values, parent), Rule.expected_arguments(values, parent), arguments(values, parent)),
    Equal.cong(+List<InterfaceView.Node>, +List<InterfaceView.Node>, items => InterfaceView.approval_fact(parent, "tool", "Tool", name) <>
      List.append(&2, InterfaceView.Node, Rule.expected_arguments(values, parent), items),
      InterfaceView.approval_directory(context, parent), Rule.expected_directory(context, parent), directory(context, parent)))

def audit_classification(+message: D.Message, +index: Nat, +tail: +List<Actual.Group>, is_audit: {Rule.audit_message(message) == True{} : Bool}) ->
  {Actual.prepend(message, index, tail) == Actual.prepend_audit(index, Actual.audit_failed(message), message, tail) : +List<Actual.Group>}:
  match message:
    case D.UserMessage{text}: impossible({Actual.prepend(D.UserMessage{text}, index, tail) == Actual.prepend_audit(index, Actual.audit_failed(D.UserMessage{text}), D.UserMessage{text}, tail) : +List<Actual.Group>}, is_audit)
    case D.AssistantMessage{text}: impossible({Actual.prepend(D.AssistantMessage{text}, index, tail) == Actual.prepend_audit(index, Actual.audit_failed(D.AssistantMessage{text}), D.AssistantMessage{text}, tail) : +List<Actual.Group>}, is_audit)
    case D.ModelContext{value}: impossible({Actual.prepend(D.ModelContext{value}, index, tail) == Actual.prepend_audit(index, Actual.audit_failed(D.ModelContext{value}), D.ModelContext{value}, tail) : +List<Actual.Group>}, is_audit)
    case D.FunctionCall{call}: {==}
    case D.FunctionOutput{call_id, value, error}: {==}
    case D.OperationResult{ticket, call_id, tool, value, error}: {==}
    case D.FailureMessage{text}: {==}
    case D.ContextCheckpoint{summary}: {==}
    case D.ReasoningRecord{owner, effort, remaining, sampling}: {==}
    case D.ConfigurationUpdate{effort}: {==}
    case D.HookRecord{task_id, call_id, plugin, outcome}: {==}
    case D.ToolReceipt{task_id, operation_id, call, value, error}: {==}
    case D.AfterRecord{task_id, operation_id, plugin, outcome}: {==}
    case D.ApprovalRecord{task_id, operation_id, call, reviewer, outcome}: {==}
    case D.ForkResult{task_id, call_id, branch}: {==}

# Comparison reflexivity is needed to bind a reader's choice to its own group.
def same_group(+group: Nat) -> {Nat.is_eq(group, group) == True{} : Bool}:
  match group:
    case 0n: {==}
    case 1n+previous: same_group(previous)

def explicit_disclosure(+group: Nat, seen: Nat, +choice: Bool,
  +attention: Maybe<&2, Nat>, +rest: +List<E.Disclosure>) ->
  {Actual.expanded(E.Disclosure{group, seen, choice} <> rest, group, attention) == choice : Bool}:
  Equal.cong(Bool, Bool,
    hit => Actual.choose_expanded(hit, choice, Actual.expanded(rest, group, attention)),
    Nat.is_eq(group, group), True{}, same_group(group))

def failure_summary(+entries: +List<Actual.Audit>, +index: Nat, +message: D.Message,
  observed: {Actual.latest_failure(entries) == Some{Actual.Audit{index, message}} : Maybe<&2, Actual.Audit>}) ->
  {Actual.activity_summary(entries) ==
    "Failure: " ++ Actual.audit_title(message) ++ " · " ++ Nat.show(List.length(&2, Actual.Audit, entries)) ++ " events" : String}:
  Equal.cong(Maybe<&2, Actual.Audit>, String,
    failure => Actual.summarized_activity(failure, entries),
    Actual.latest_failure(entries), Some{Actual.Audit{index, message}}, observed)

def last_failure(+entries: +List<Actual.Audit>, +index: Nat, +message: D.Message,
  +failed: {Actual.audit_failed(message) == True{} : Bool}) ->
  {Actual.latest_failure(List.append(&2, Actual.Audit, entries, [Actual.Audit{index, message}])) ==
    Some{Actual.Audit{index, message}} : Maybe<&2, Actual.Audit>}:
  match entries:
    case Nil{}:
      Equal.cong(Bool, Maybe<&2, Actual.Audit>,
        flag => Actual.failure_candidate(flag, Actual.Audit{index, message}),
        Actual.audit_failed(message), True{}, failed)
    case Con{Actual.Audit{head_index, +head_message}, +rest}:
      Equal.cong(Maybe<&2, Actual.Audit>, Maybe<&2, Actual.Audit>,
        later => Actual.prefer_failure(later, Actual.failure_candidate(Actual.audit_failed(head_message), Actual.Audit{head_index, head_message})),
        Actual.latest_failure(List.append(&2, Actual.Audit, rest, [Actual.Audit{index, message}])),
        Some{Actual.Audit{index, message}}, last_failure(rest, index, message, failed))

def audit_identity(+index: Nat, failed: Bool, message: D.Message, tail: +List<Actual.Group>) ->
  {Rule.first_identity(Actual.prepend_audit(index, failed, message, tail)) == Some{index} : Maybe<&2, Nat>}:
  match tail:
    case Nil{}: {==}
    case Con{Actual.Speech{id, speaker, text, source}, rest}: {==}
    case Con{Actual.Activity{id, attention, entries}, rest}: {==}

# The oldest audit occurrence owns the run even after its suffix grows.

def automatic_decision(+operation: Nat, call: D.Call, context: D.TaskContext, +reviewer: D.Profile, +parent: Identity.Key, state: Core.State) ->
  {InterfaceView.approvals([Actual.AutomaticDecision{operation, call, context, reviewer}], parent, state) ==
        [InterfaceView.Node{Identity.Entity{parent, "approval", Nat.show(operation)}, "approval/" ++ Nat.show(operation), "Automatic review", InterfaceView.Approval{}, InterfaceView.Region{}, List.append(&2, InterfaceView.Node, InterfaceView.approval_metadata(call, context, Identity.Entity{parent, "approval", Nat.show(operation)}),
            [InterfaceView.Node{Identity.Part{Identity.Entity{parent, "approval", Nat.show(operation)}, "reviewer"}, "reviewer", "Reviewer model", InterfaceView.Content{},
              InterfaceView.ReadOnly{Rule.reviewer_name(reviewer)}, Nil{}}])}] : +List<InterfaceView.Node>}:
  match reviewer:
    case D.Profile{key, provider, name, reasoning, options}: {==}

def Rule.evidence():
  Rule.Requirements{
    reviewer => id => call => context => task => world => request_context(reviewer, id, call, context, task, world),
    reader => task => world => owning_context(reader, task, world),
    call => context => parent => metadata(call, context, parent),
    value => serialized_parameter(value),
    operation => call => context => approve => deny => enabled => parent => state => {==},
    operation => call => context => reviewer => parent => state => automatic_decision(operation, call, context, reviewer, parent, state),
    task => operation => call => reviewer => outcome => {==},
    message => index => tail => is_audit => audit_classification(message, index, tail, is_audit),
    group => seen => choice => attention => rest => explicit_disclosure(group, seen, choice, attention, rest),
    +group => seen => +attention => +entries => task => +index => +message => observed =>
      Equal.trans(Bool & String,
        Rule.activity_presentation(Actual.visible([Actual.Activity{group, attention, entries}], task, [E.Disclosure{group, seen, False{}}])),
        (False{}, Actual.activity_summary(entries)),
        (False{}, "Failure: " ++ Actual.audit_title(message) ++ " · " ++ Nat.show(List.length(&2, Actual.Audit, entries)) ++ " events"),
        Equal.cong(Bool, Bool & String, expanded => (expanded, Actual.activity_summary(entries)),
          Actual.expanded([E.Disclosure{group, seen, False{}}], group, attention), False{},
          explicit_disclosure(group, seen, False{}, attention, Nil{})),
        Equal.cong(String, Bool & String, summary => (False{}, summary), Actual.activity_summary(entries),
          "Failure: " ++ Actual.audit_title(message) ++ " · " ++ Nat.show(List.length(&2, Actual.Audit, entries)) ++ " events",
          failure_summary(entries, index, message, observed)))
    ,
    entries => index => message => failed => last_failure(entries, index, message, failed),
    +index => +failed => +message => +suffix => more =>
      Equal.trans(Maybe<&2, Nat>,
        Rule.first_identity(Actual.prepend_audit(index, failed, message, Actual.groups(List.append(&2, D.Message, suffix, more), (index + 1n : Nat)))),
        Some{index}, Rule.first_identity(Actual.prepend_audit(index, failed, message, Actual.groups(suffix, (index + 1n : Nat)))),
        audit_identity(index, failed, message, Actual.groups(List.append(&2, D.Message, suffix, more), (index + 1n : Nat))),
        Equal.sym(Maybe<&2, Nat>, Rule.first_identity(Actual.prepend_audit(index, failed, message, Actual.groups(suffix, (index + 1n : Nat)))),
          Some{index}, audit_identity(index, failed, message, Actual.groups(suffix, (index + 1n : Nat)))))
    ,
    messages => offset => History.grouped_history(messages, offset),
    groups => task => disclosures => History.visible_history(groups, task, disclosures),
    messages => offset => task => disclosures => History.observed_text(messages, offset, task, disclosures)
  }
