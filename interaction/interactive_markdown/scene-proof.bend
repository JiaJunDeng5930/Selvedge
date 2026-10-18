import Base
import ./TYPES.bend as UI
import ./SOURCES.bend as Sources
import ./SCENE.bend as Scene
import ./EXPRESSION.bend as Expression
import ../../bendlib/json.bend as J
import ../../bendlib/stdlib.bend as Std
import ../../harness/DOMAIN.bend as D
import ../../harness/MODEL.bend as Harness
import ../../harness/conversation/PROGRAM.bend as Conversation
import ../presentation/SURFACE.bend as Surface

def first(values: +List<J.Json>) -> J.Json:
  match values:
    case Nil{}: J.Null{}
    case Con{value, rest}: value

# A human is awaited exactly while an authoritative task operation is pending
# human approval. Granted, executing and model-reviewed operations do not count.
def pending_human_approval(operation: D.Operation()) -> Bool:
  match operation:
    case (id, D.OperationBody{call, announced, D.ApprovalPending{D.HumanReviewer{}}}): True{}
    case _: False{}

def human_approval_stage(+id: Nat, +call: D.Call, +announced: Bool, +stage: D.OperationStage) ->
  {Sources.operation_human(stage) == pending_human_approval((id, D.OperationBody{call, announced, stage})) : Bool}:
  match stage:
    case D.Executing{}: {==}
    case D.ApprovalPending{D.HumanReviewer{}}: {==}
    case D.ApprovalPending{D.ModelReviewer{profile}}: {==}
    case D.ApprovalGranted{reviewer}: {==}
    case D.ElevatedExecuting{ticket, reviewer}: {==}
    case D.ResultPending{ticket, plugin, pending, value, error}: {==}

def awaiting_authoritative_human(+operations: +List<D.Operation()>) ->
  {Sources.awaiting_human(operations) == List.any(~&2, ~D.Operation(), ~pending_human_approval, operations) : Bool}:
  match operations:
    case Nil{}: {==}
    case Con{(id, D.OperationBody{+call, +announced, +stage}), +rest}:
      Equal.trans(Bool, Sources.awaiting_human((id, D.OperationBody{call, announced, stage}) <> rest),
        pending_human_approval((id, D.OperationBody{call, announced, stage})) || Sources.awaiting_human(rest),
        List.any(~&2, ~D.Operation(), ~pending_human_approval, (id, D.OperationBody{call, announced, stage}) <> rest),
        Equal.cong(Bool, Bool, (current => current || Sources.awaiting_human(rest)),
          Sources.operation_human(stage), pending_human_approval((id, D.OperationBody{call, announced, stage})),
          human_approval_stage(id, call, announced, stage)),
        Equal.cong(Bool, Bool, (remaining => pending_human_approval((id, D.OperationBody{call, announced, stage})) || remaining),
          Sources.awaiting_human(rest), List.any(~&2, ~D.Operation(), ~pending_human_approval, rest),
          awaiting_authoritative_human(rest)))

def task_awaiting_human(+task: D.Task) ->
  {J.get(Sources.task_value(Some{task}), "awaitingHuman") ==
    J.Boolean{List.any(~&2, ~D.Operation(), ~pending_human_approval, D.task_operations(task))} : J.Json}:
  Equal.cong(Bool, J.Json, (waiting => J.Boolean{waiting}),
    Sources.awaiting_human(D.task_operations(task)),
    List.any(~&2, ~D.Operation(), ~pending_human_approval, D.task_operations(task)),
    awaiting_authoritative_human(D.task_operations(task)))

type SourceRequirements is Type:
  SourceRequirements{
    working_fact: @+task:D.Task ->
      {J.get(Sources.task_value(Some{task}), "working") == J.Boolean{Conversation.working(D.task_phase(task), D.task_operations(task))} : J.Json},
    status_fact: @+task:D.Task ->
      {J.get(Sources.task_value(Some{task}), "statusLabel") == J.Text{Conversation.status(task)} : J.Json},
    approval_fact: @+task:D.Task ->
      {J.get(Sources.task_value(Some{task}), "awaitingHuman") == J.Boolean{List.any(~&2, ~D.Operation(), ~pending_human_approval, D.task_operations(task))} : J.Json},
    missing_task: {Sources.task_value(None{}) == J.Null{} : J.Json},
    missing_graph: @id:Nat -> @world:Harness.World() -> @sequence:Nat -> @fresh:Bool ->
      {Sources.graph_observation(None{}, id, world, sequence, fresh) == Sources.source_handle("missing", fresh, sequence, J.Null{}) : J.Json},
    field_identity: @+identity:UI.Identity -> @occurrence:Nat -> @tag:String -> @attrs:J.Json -> @binding:UI.Binding -> @children:+List<UI.ExpandedNode> ->
      {Scene.event(UI.ExpandedNode{identity, occurrence, tag, attrs, binding, children}) == UI.EventIdentity{identity, occurrence} : UI.EventIdentity}}

def requirements() -> SourceRequirements:
  SourceRequirements{
    task => {==}, task => {==}, task_awaiting_human, {==},
    id => world => sequence => fresh => {==},
    identity => occurrence => tag => attrs => binding => children => {==}}


# Accessible chart data retains the displayed input order and both original
# field values. In particular, a.b means the same nested path here as it does
# in declaration admission and plotted values.
def chart_fact_values(nodes: +List<Surface.Node>) -> +List<String>:
  match nodes:
    case Nil{}: Nil{}
    case Con{Surface.Node{key, semantic, label, role, Surface.Fact{value}, children}, rest}: value <> chart_fact_values(rest)
    case Con{other, rest}: chart_fact_values(rest)

def chart_accessible_value(+row: J.Json, +owner: UI.ExpandedNode) -> String:
  Scene.scalar_text(Expression.path_field(row, J.text(J.get(Scene.attributes(owner), "x")))) ++ ": " ++
    Scene.scalar_text(Expression.path_field(row, J.text(J.get(Scene.attributes(owner), "y"))))

type ChartSummaryContext is Data:
  ChartSummaryContext{owner: UI.ExpandedNode, values: +List<String>}

def chart_summary_step(row: J.Json, context: ChartSummaryContext) -> ChartSummaryContext:
  match context:
    case ChartSummaryContext{+owner, values}:
      ChartSummaryContext{owner, chart_accessible_value(row, owner) <> values}

def chart_summary_values(context: ChartSummaryContext) -> +List<String>:
  ChartSummaryContext{owner, values} = context
  values

def chart_required_values(rows: +List<J.Json>, owner: UI.ExpandedNode) -> +List<String>:
  chart_summary_values(List.foldr(~&2, ~J.Json, ~ChartSummaryContext, ~chart_summary_step, rows, ChartSummaryContext{owner, Nil{}}))

def chart_summary_fold(+rows: +List<J.Json>, +owner: UI.ExpandedNode, +index: Nat) ->
  {List.foldr(~&2, ~J.Json, ~ChartSummaryContext, ~chart_summary_step, rows, ChartSummaryContext{owner, Nil{}}) ==
    ChartSummaryContext{owner, chart_fact_values(Scene.chart_summaries(rows, owner, index))} : ChartSummaryContext}:
  match rows:
    case Nil{}: {==}
    case Con{+row, +rest}:
      Equal.cong(ChartSummaryContext, ChartSummaryContext, (context => chart_summary_step(row, context)),
        List.foldr(~&2, ~J.Json, ~ChartSummaryContext, ~chart_summary_step, rest, ChartSummaryContext{owner, Nil{}}),
        ChartSummaryContext{owner, chart_fact_values(Scene.chart_summaries(rest, owner, 1n+index))}, chart_summary_fold(rest, owner, 1n+index))

def chart_accessible_order(+rows: +List<J.Json>, +owner: UI.ExpandedNode, +index: Nat) ->
  {chart_fact_values(Scene.chart_summaries(rows, owner, index)) == chart_required_values(rows, owner) : +List<String>}:
  Equal.sym(+List<String>, chart_required_values(rows, owner), chart_fact_values(Scene.chart_summaries(rows, owner, index)),
    Equal.cong(ChartSummaryContext, +List<String>, chart_summary_values,
      List.foldr(~&2, ~J.Json, ~ChartSummaryContext, ~chart_summary_step, rows, ChartSummaryContext{owner, Nil{}}),
      ChartSummaryContext{owner, chart_fact_values(Scene.chart_summaries(rows, owner, index))}, chart_summary_fold(rows, owner, index)))

type ChartSummaryRequirements is Type:
  ChartSummaryRequirements{
    original_values_in_order: @+rows:+List<J.Json> -> @+owner:UI.ExpandedNode -> @+index:Nat ->
      {chart_fact_values(Scene.chart_summaries(rows, owner, index)) == chart_required_values(rows, owner) : +List<String>}}

def chart_summary_requirements() -> ChartSummaryRequirements:
  ChartSummaryRequirements{chart_accessible_order}
