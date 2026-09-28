import Base
import ./bendlib/component.bend as C
import ./bendlib/domain.bend as D
import ./WORKSPACE.bend as W
import ./bendlib/json.bend as J
import ./bendlib/association-map.bend as Finite

# Projects are an organizational finite map. Their workspace is a birth default,
# not a mutable reference held by a task's execution contract.
def registry(-StateRest: Data, world: C.Frame<D.State, StateRest>) -> D.Projects:
  C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +rest} = world
  projects

def entries(registry: D.Projects) -> +List<Finite.Entry(D.Project)>:
  D.Projects{entries, next_id} = registry
  entries

def next_id(registry: D.Projects) -> Nat:
  D.Projects{entries, next_id} = registry
  U32.to_nat(next_id)

def next_word(registry: D.Projects) -> U32:
  D.Projects{entries, next_id} = registry
  next_id

def count(registry: D.Projects) -> Nat:
  List.length(&2, Finite.Entry(D.Project), entries(registry))

def find(registry: D.Projects, id: Nat) -> Maybe<&2, D.Project>:
  Finite.find(~D.Project, entries(registry), id)

def missing(found: Maybe<&2, D.Project>) -> Bool:
  match found:
    case None{}: True{}
    case Some{project}: False{}

def valid_project(project: D.Project) -> Bool:
  D.Project{+name, +workspace, +guidance} = project
  D.nonempty(name) && Nat.is_le(J.utf8_length(name), 256n) && W.valid(workspace) &&
    W.valid_guidance(guidance) && W.guidance_member(W.primary(workspace), guidance)

def valid_entries(entries: +List<Finite.Entry(D.Project)>, +next_id: Nat) -> Bool:
  match entries:
    case Nil{}: True{}
    case Con{(+id, project), +rest}:
      Nat.is_lt(id, next_id) && valid_project(project) && missing(Finite.find(~D.Project, rest, id)) && valid_entries(rest, next_id)

def valid(registry: D.Projects) -> Bool:
  D.Projects{+entries, next_id} = registry
  Nat.is_le(List.length(&2, Finite.Entry(D.Project), entries), 256n) &&
    valid_entries(entries, U32.to_nat(next_id))

def reference_valid(id: Maybe<&2, Nat>, registry: D.Projects) -> Bool:
  match id:
    case None{}: True{}
    case Some{id}: Bool.not(missing(find(registry, id)))

def tasks_bound(tasks: +List<D.Task>, +registry: D.Projects) -> Bool:
  match tasks:
    case Nil{}: True{}
    case Con{task, rest}: reference_valid(W.project_id(D.task_context(task)), registry) && tasks_bound(rest, registry)

def owns(expected: Nat, actual: Maybe<&2, Nat>) -> Bool:
  match actual:
    case None{}: False{}
    case Some{id}: Nat.is_eq(expected, id)

def counted(yes: Bool, rest: Nat) -> Nat:
  match yes:
    case True{}: 1n+rest
    case False{}: rest

def task_count(tasks: +List<D.Task>, +id: Nat) -> Nat:
  match tasks:
    case Nil{}: 0n
    case Con{task, rest}: counted(owns(id, W.project_id(D.task_context(task))), task_count(rest, id))

def projected(+id: Nat, project: D.Project, tasks: +List<D.Task>) -> J.Json:
  D.Project{name, D.Workspace{roots, primary}, guidance} = project
  J.Object{[J.Field{"project_id", J.nat(id)}, J.Field{"name", J.Text{name}},
    J.Field{"root_count", J.nat(List.length(&2, String, roots))}, J.Field{"primary_root", D.optional_string(primary)},
    J.Field{"task_count", J.nat(task_count(tasks, id))}]}

def summaries(entries: +List<Finite.Entry(D.Project)>, +tasks: +List<D.Task>) -> +List<J.Json>:
  match entries:
    case Nil{}: Nil{}
    case Con{(id, project), rest}: projected(id, project, tasks) <> summaries(rest, tasks)

def detail(id: Nat, found: Maybe<&2, D.Project>) -> J.Json:
  match found:
    case None{}: D.failure("project_not_found", "The project does not exist")
    case Some{D.Project{name, workspace, guidance}}:
      D.success(J.Object{[J.Field{"project_id", J.nat(id)}, J.Field{"name", J.Text{name}},
        J.Field{"workspace", D.workspace_json(workspace)}, J.Field{"guidance", D.project_json(guidance)}]})

def selected(found: Maybe<&2, D.Project>, id: Nat, base: D.TaskContext) -> Result<&2, &2, String, W.Selection>:
  match found:
    case None{}: Fail{"The selected project does not exist"}
    case Some{D.Project{name, workspace, guidance}}:
      D.TaskContext{previous, sandbox, approval, old_id} = base
      Done{W.Selection{D.TaskContext{workspace, sandbox, approval, Some{id}}, guidance}}

def select_id(id: Maybe<&2, Nat>, base: D.TaskContext, registry: D.Projects) -> Result<&2, &2, String, W.Selection>:
  match id:
    case None{}: Fail{"Invalid project identity"}
    case Some{+id}: selected(find(registry, id), id, base)

def select(value: J.Json, base: D.TaskContext, guidance: D.ProjectContext, +registry: D.Projects) -> Result<&2, &2, String, W.Selection>:
  match value:
    case J.Null{}: Done{W.Selection{base, guidance}}
    case J.Number{text}: select_id(Nat.read(text), base, registry)
    case _: Fail{"A project identity must be a nonnegative integer"}

def put(+id: Nat, project: D.Project, registry: D.Projects, next_id: U32) -> D.Projects:
  D.Projects{entries, previous_id} = registry
  D.Projects{(id, project) <> Finite.remove(~D.Project, entries, id), next_id}

def remove(id: Nat, registry: D.Projects) -> D.Projects:
  D.Projects{entries, next_id} = registry
  D.Projects{Finite.remove(~D.Project, entries, id), next_id}

def store(-StateRest: Data, registry: D.Projects, world: C.Frame<D.State, StateRest>) -> C.Frame<D.State, StateRest>:
  C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, previous}, +rest} = world
  C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, registry}, rest}

def rename(name: Maybe<&2, String>, fallback: String) -> String:
  match name:
    case None{}: fallback
    case Some{name}: name

def proposal(name: Maybe<&2, String>, +workspace: J.Json, +guidance: J.Json, previous: D.Project) -> D.Project:
  D.Project{previous_name, previous_workspace, previous_guidance} = previous
  +workspace = W.read_workspace(workspace, previous_workspace)
  D.Project{rename(name, previous_name), workspace, W.read_guidance(guidance, workspace, previous_guidance)}
