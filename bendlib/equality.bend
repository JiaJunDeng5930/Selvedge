import Base
import ./json.bend as J
import ../MODEL.bend as M

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
      String.eq(a, b) && strings(rest_a, rest_b)
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
      String.eq(a, b) && json_go(p, rest)
    case 1n+p Con{Values{J.Text{a}, J.Text{b}}, rest}:
      String.eq(a, b) && json_go(p, rest)
    case 1n+p Con{Values{J.Array{a}, J.Array{b}}, rest}:
      json_go(p, Arrays{a, b} <> rest)
    case 1n+p Con{Values{J.Object{a}, J.Object{b}}, rest}:
      json_go(p, Objects{a, b} <> rest)
    case 1n+p Con{Arrays{Nil{}, Nil{}}, rest}: json_go(p, rest)
    case 1n+p Con{Arrays{Con{a, tail_a}, Con{b, tail_b}}, rest}:
      json_go(p, Values{a, b} <> Arrays{tail_a, tail_b} <> rest)
    case 1n+p Con{Objects{Nil{}, Nil{}}, rest}: json_go(p, rest)
    case 1n+p Con{Objects{Con{J.Field{key_a, a}, tail_a}, Con{J.Field{key_b, b}, tail_b}}, rest}:
      String.eq(key_a, key_b) && json_go(p, Values{a, b} <> Objects{tail_a, tail_b} <> rest)
    case _ _: False{}

def json(budget: Nat, left: J.Json, right: J.Json) -> Bool:
  json_go(budget, [Values{left, right}])

def project(left: M.ProjectContext, right: M.ProjectContext) -> Bool:
  match left right:
    case M.NoProject{} M.NoProject{}: True{}
    case M.ProjectContext{root_a, revision_a, text_a} M.ProjectContext{root_b, revision_b, text_b}:
      String.eq(root_a, root_b) && String.eq(revision_a, revision_b) && String.eq(text_a, text_b)
    case _ _: False{}

def model(left: M.Model, right: M.Model) -> Bool:
  match left right:
    case M.Model{M.Profile{key_a, provider_a, name_a}, reasoning_a, project_a}
         M.Model{M.Profile{key_b, provider_b, name_b}, reasoning_b, project_b}:
      String.eq(key_a, key_b) && String.eq(provider_a, provider_b) &&
        String.eq(name_a, name_b) && String.eq(reasoning_a, reasoning_b) && project(project_a, project_b)

def tool(budget: Nat, left: M.Tool, right: M.Tool) -> Bool:
  match left right:
    case M.Tool{name_a, description_a, schema_a, source_a} M.Tool{name_b, description_b, schema_b, source_b}:
      String.eq(name_a, name_b) && String.eq(description_a, description_b) &&
        M.source_same(source_a, source_b) && json(budget, schema_a, schema_b)

def tools(+budget: Nat, left: +List<M.Tool>, right: +List<M.Tool>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case Con{a, rest_a} Con{b, rest_b}:
      tool(budget, a, b) && tools(budget, rest_a, rest_b)
    case _ _: False{}

def contract(budget: Nat, left: M.Contract, right: M.Contract) -> Bool:
  match left right:
    case M.Contract{model_a, tools_a, fork_a, descendants_a} M.Contract{model_b, tools_b, fork_b, descendants_b}:
      model(model_a, model_b) && tools(budget, tools_a, tools_b) &&
        Nat.is_eq(fork_a, fork_b) && Nat.is_eq(descendants_a, descendants_b)

def call(budget: Nat, left: M.Call, right: M.Call) -> Bool:
  match left right:
    case M.Call{id_a, name_a, arguments_a} M.Call{id_b, name_b, arguments_b}:
      String.eq(id_a, id_b) && String.eq(name_a, name_b) && json(budget, arguments_a, arguments_b)

def message(budget: Nat, left: M.Message, right: M.Message) -> Bool:
  match left right:
    case M.UserMessage{a} M.UserMessage{b}: String.eq(a, b)
    case M.AssistantMessage{a} M.AssistantMessage{b}: String.eq(a, b)
    case M.FailureMessage{a} M.FailureMessage{b}: String.eq(a, b)
    case M.FunctionCall{a} M.FunctionCall{b}: call(budget, a, b)
    case M.FunctionOutput{id_a, a, error_a} M.FunctionOutput{id_b, b, error_b}:
      String.eq(id_a, id_b) && booleans(error_a, error_b) && json(budget, a, b)
    case M.ModelContext{a} M.ModelContext{b}: json(budget, a, b)
    case M.ContextCheckpoint{a} M.ContextCheckpoint{b}: String.eq(a, b)
    case _ _: False{}

def history(+budget: Nat, left: M.History, right: M.History) -> Bool:
  match left right:
    case M.EmptyHistory{} M.EmptyHistory{}: True{}
    case M.HistoryNode{previous_a, a} M.HistoryNode{previous_b, b}:
      message(budget, a, b) && history(budget, previous_a, previous_b)
    case _ _: False{}

def drop_history(count: Nat, history: M.History) -> M.History:
  match count history:
    case 0n history: history
    case 1n+p M.HistoryNode{previous, message}: drop_history(p, previous)
    case _ _: M.EmptyHistory{}

def history_extends(budget: Nat, +previous: M.History, +candidate: M.History) -> Bool:
  +before = M.history_length(previous)
  +after = M.history_length(candidate)
  Nat.is_le(before, after) && history(budget, previous, drop_history(Nat.sub(after, before), candidate))
