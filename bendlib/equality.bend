import Base
import ../harness/DOMAIN.bend as D
import ../harness/reasoning/MODEL.bend as Reasoning
import ./json.bend as J
import ../harness/workspace/WORKSPACE.bend as Workspace

def char_equal(compared: (Char & Char) & Cmp) -> Bool:
  ((left, right), order) = compared
  Cmp.is_eq(order)

def string_equal_acc(left: String, right: String, same: Bool) -> Bool:
  match left right:
    case SNil{} SNil{}: same
    case SNil{} SCon{head, tail}: False{}
    case SCon{head, tail} SNil{}: False{}
    case SCon{a, rest_a} SCon{b, rest_b}:
      string_equal_acc(rest_a, rest_b, same && char_equal(Char.cmp(a, b)))

def string_equal(left: String, right: String) -> Bool:
  string_equal_acc(left, right, True{})

def booleans(left: Bool, right: Bool) -> Bool:
  match left right:
    case True{} True{}: True{}
    case False{} False{}: True{}
    case _ _: False{}

def naturals(left: +List<Nat>, right: +List<Nat>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case Con{a, rest_a} Con{b, rest_b}:
      Nat.is_eq(a, b) && naturals(rest_a, rest_b)
    case _ _: False{}

def strings(left: +List<String>, right: +List<String>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case Con{a, rest_a} Con{b, rest_b}:
      string_equal(a, b) && strings(rest_a, rest_b)
    case _ _: False{}

type Comparison is Data:
  Values{left: J.Json, right: J.Json}
  Arrays{left: +List<J.Json>, right: +List<J.Json>}
  Objects{left: +List<J.Field>, right: +List<J.Field>}

# JSON is nested through lists and fields. One work list avoids mutual recursion;
# exhaustion rejects a comparison rather than treating unchecked data as equal.
def json_go(fuel: Nat, pending: +List<Comparison>) -> Bool:
  match fuel pending:
    case _ Nil{}: True{}
    case 0n _: False{}
    case 1n+p Con{Values{J.Null{}, J.Null{}}, rest}: json_go(p, rest)
    case 1n+p Con{Values{J.Boolean{a}, J.Boolean{b}}, rest}:
      booleans(a, b) && json_go(p, rest)
    case 1n+p Con{Values{J.Number{a}, J.Number{b}}, rest}:
      string_equal(a, b) && json_go(p, rest)
    case 1n+p Con{Values{J.Text{a}, J.Text{b}}, rest}:
      string_equal(a, b) && json_go(p, rest)
    case 1n+p Con{Values{J.Array{a}, J.Array{b}}, rest}:
      json_go(p, Arrays{a, b} <> rest)
    case 1n+p Con{Values{J.Object{a}, J.Object{b}}, rest}:
      json_go(p, Objects{a, b} <> rest)
    case 1n+p Con{Arrays{Nil{}, Nil{}}, rest}: json_go(p, rest)
    case 1n+p Con{Arrays{Con{a, tail_a}, Con{b, tail_b}}, rest}:
      json_go(p, Values{a, b} <> Arrays{tail_a, tail_b} <> rest)
    case 1n+p Con{Objects{Nil{}, Nil{}}, rest}: json_go(p, rest)
    case 1n+p Con{Objects{Con{J.Field{key_a, a}, tail_a}, Con{J.Field{key_b, b}, tail_b}}, rest}:
      string_equal(key_a, key_b) && json_go(p, Values{a, b} <> Objects{tail_a, tail_b} <> rest)
    case _ _: False{}

def json(budget: Nat, left: J.Json, right: J.Json) -> Bool:
  json_go(budget, [Values{left, right}])

def project(left: D.ProjectContext, right: D.ProjectContext) -> Bool:
  match left right:
    case D.NoProject{} D.NoProject{}: True{}
    case D.ProjectContext{root_a, revision_a, text_a} D.ProjectContext{root_b, revision_b, text_b}:
      string_equal(root_a, root_b) && string_equal(revision_a, revision_b) && string_equal(text_a, text_b)
    case _ _: False{}

def model(left: D.Model, right: D.Model) -> Bool:
  match left right:
    case D.Model{D.Profile{key_a, provider_a, name_a, policy_a, options_a}, reasoning_a, project_a}
         D.Model{D.Profile{key_b, provider_b, name_b, policy_b, options_b}, reasoning_b, project_b}:
      string_equal(key_a, key_b) && string_equal(provider_a, provider_b) &&
        string_equal(name_a, name_b) && Reasoning.same(policy_a, policy_b) && D.reasoning_options_same(options_a, options_b) && string_equal(reasoning_a, reasoning_b) && project(project_a, project_b)

def tool(budget: Nat, left: D.Tool, right: D.Tool) -> Bool:
  match left right:
    case D.Tool{name_a, description_a, schema_a, source_a} D.Tool{name_b, description_b, schema_b, source_b}:
      string_equal(name_a, name_b) && string_equal(description_a, description_b) &&
        D.source_same(source_a, source_b) && json(budget, schema_a, schema_b)

def tools(+budget: Nat, left: +List<D.Tool>, right: +List<D.Tool>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case Con{a, rest_a} Con{b, rest_b}:
      tool(budget, a, b) && tools(budget, rest_a, rest_b)
    case _ _: False{}

def contract(+budget: Nat, left: D.Contract, right: D.Contract) -> Bool:
  match left right:
    case D.Contract{model_a, tools_a, fork_a, descendants_a, plugins_a, context_a} D.Contract{model_b, tools_b, fork_b, descendants_b, plugins_b, context_b}:
      json(budget, D.task_context_json(context_a), D.task_context_json(context_b)) && model(model_a, model_b) && tools(budget, tools_a, tools_b) &&
        Nat.is_eq(fork_a, fork_b) && Nat.is_eq(descendants_a, descendants_b) && json(budget, D.plugins_json(plugins_a), D.plugins_json(plugins_b))

# A branch may explicitly replace execution coordinates and their root guidance.
# Its model identity, tool definitions, plugin routes and resource bounds remain
# inherited. Existing tasks still use exact contract equality in retained().
def inherited_contract(+budget: Nat, left: D.Contract, right: D.Contract) -> Bool:
  D.Contract{D.Model{profile_a, reasoning_a, guidance_a}, tools_a, fork_a, descendants_a, plugins_a, context_a} = left
  D.Contract{D.Model{profile_b, reasoning_b, guidance_b}, tools_b, fork_b, descendants_b, plugins_b, context_b} = right
  Workspace.profile_same(profile_a, profile_b) && string_equal(reasoning_a, reasoning_b) && tools(budget, tools_a, tools_b) &&
    Nat.is_eq(fork_a, fork_b) && Nat.is_eq(descendants_a, descendants_b) && json(budget, D.plugins_json(plugins_a), D.plugins_json(plugins_b))

def call(budget: Nat, left: D.Call, right: D.Call) -> Bool:
  match left right:
    case D.Call{id_a, name_a, arguments_a} D.Call{id_b, name_b, arguments_b}:
      string_equal(id_a, id_b) && string_equal(name_a, name_b) && json(budget, arguments_a, arguments_b)

def message(+budget: Nat, left: D.Message, right: D.Message) -> Bool:
  match left right:
    case D.ForkResult{owner_a, id_a, branch_a} D.ForkResult{owner_b, id_b, branch_b}:
      Nat.is_eq(owner_a, owner_b) && string_equal(id_a, id_b) && Nat.is_eq(branch_a, branch_b)
    case D.HookRecord{owner_a, id_a, plugin_a, outcome_a} D.HookRecord{owner_b, id_b, plugin_b, outcome_b}:
      Nat.is_eq(owner_a, owner_b) && string_equal(id_a, id_b) && D.plugin_same(plugin_a, plugin_b) && json(budget, D.hook_json(outcome_a), D.hook_json(outcome_b))
    case D.ToolReceipt{owner_a, operation_a, call_a, a, error_a} D.ToolReceipt{owner_b, operation_b, call_b, b, error_b}:
      Nat.is_eq(owner_a, owner_b) && Nat.is_eq(operation_a, operation_b) && call(budget, call_a, call_b) && booleans(error_a, error_b) && json(budget, a, b)
    case D.AfterRecord{owner_a, operation_a, plugin_a, outcome_a} D.AfterRecord{owner_b, operation_b, plugin_b, outcome_b}:
      Nat.is_eq(owner_a, owner_b) && Nat.is_eq(operation_a, operation_b) && D.plugin_same(plugin_a, plugin_b) && json(budget, D.after_json(outcome_a), D.after_json(outcome_b))
    case D.ApprovalRecord{owner_a, operation_a, call_a, reviewer_a, outcome_a} D.ApprovalRecord{owner_b, operation_b, call_b, reviewer_b, outcome_b}:
      Nat.is_eq(owner_a, owner_b) && Nat.is_eq(operation_a, operation_b) && call(budget, call_a, call_b) &&
        json(budget, D.approval_reviewer_json(reviewer_a), D.approval_reviewer_json(reviewer_b)) &&
        json(budget, D.approval_outcome_json(outcome_a), D.approval_outcome_json(outcome_b))
    case D.UserMessage{a} D.UserMessage{b}: string_equal(a, b)
    case D.AssistantMessage{a} D.AssistantMessage{b}: string_equal(a, b)
    case D.FailureMessage{a} D.FailureMessage{b}: string_equal(a, b)
    case D.FunctionCall{a} D.FunctionCall{b}: call(budget, a, b)
    case D.FunctionOutput{id_a, a, error_a} D.FunctionOutput{id_b, b, error_b}:
      string_equal(id_a, id_b) && booleans(error_a, error_b) && json(budget, a, b)
    case D.OperationResult{ticket_a, id_a, tool_a, a, error_a} D.OperationResult{ticket_b, id_b, tool_b, b, error_b}:
      Nat.is_eq(ticket_a, ticket_b) && string_equal(id_a, id_b) && string_equal(tool_a, tool_b) &&
        booleans(error_a, error_b) && json(budget, a, b)
    case D.ModelContext{a} D.ModelContext{b}: json(budget, a, b)
    case D.ContextCheckpoint{a} D.ContextCheckpoint{b}: string_equal(a, b)
    case D.ReasoningRecord{oa, ea, ra, sa} D.ReasoningRecord{ob, eb, rb, sb}:
      Nat.is_eq(oa, ob) && string_equal(ea, eb) && Nat.is_eq(ra, rb) && booleans(sa, sb)
    case D.ConfigurationUpdate{a} D.ConfigurationUpdate{b}: string_equal(a, b)
    case _ _: False{}

def history(+budget: Nat, left: D.History, right: D.History) -> Bool:
  match left right:
    case D.EmptyHistory{} D.EmptyHistory{}: True{}
    case D.HistoryNode{previous_a, a} D.HistoryNode{previous_b, b}:
      message(budget, a, b) && history(budget, previous_a, previous_b)
    case _ _: False{}

def drop_history(count: Nat, history: D.History) -> D.History:
  match count history:
    case 0n history: history
    case 1n+p D.HistoryNode{previous, message}: drop_history(p, previous)
    case _ _: D.EmptyHistory{}

def history_extends(budget: Nat, +previous: D.History, +candidate: D.History) -> Bool:
  +before = D.history_length(previous)
  +after = D.history_length(candidate)
  Nat.is_le(before, after) && history(budget, previous, drop_history(Nat.sub(after, before), candidate))
