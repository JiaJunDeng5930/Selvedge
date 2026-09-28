import Base
import ./MODEL.bend as M
import ./WORKSPACE.bend as W
import ./bendlib/json.bend as J
import ./bendlib/association-map.bend as Finite

# Projects are an organizational finite map. Their workspace is a birth default,
# not a mutable reference held by a task's execution contract.
def registry(world: M.World) -> M.Projects:
  M.World{tasks, next_task, next_ticket, environment, limits, projects, board} = world
  projects

def entries(registry: M.Projects) -> +List<Finite.Entry(M.Project)>:
  M.Projects{entries, next_id} = registry
  entries

def next_id(registry: M.Projects) -> Nat:
  M.Projects{entries, next_id} = registry
  U32.to_nat(next_id)

def next_word(registry: M.Projects) -> U32:
  M.Projects{entries, next_id} = registry
  next_id

def count(registry: M.Projects) -> Nat:
  List.length(&2, Finite.Entry(M.Project), entries(registry))

def find(registry: M.Projects, id: Nat) -> Maybe<&2, M.Project>:
  Finite.find(~M.Project, entries(registry), id)

def missing(found: Maybe<&2, M.Project>) -> Bool:
  match found:
    case None{}: True{}
    case Some{project}: False{}

def valid_project(project: M.Project) -> Bool:
  M.Project{+name, +workspace, +guidance} = project
  M.nonempty(name) && Nat.is_le(J.utf8_length(name), 256n) && W.valid(workspace) &&
    W.valid_guidance(guidance) && W.guidance_member(W.primary(workspace), guidance)

def valid_entries(entries: +List<Finite.Entry(M.Project)>, +next_id: Nat) -> Bool:
  match entries:
    case Nil{}: True{}
    case Con{(+id, project), +rest}:
      Nat.is_lt(id, next_id) && valid_project(project) && missing(Finite.find(~M.Project, rest, id)) && valid_entries(rest, next_id)

def valid(registry: M.Projects) -> Bool:
  M.Projects{+entries, next_id} = registry
  Nat.is_le(List.length(&2, Finite.Entry(M.Project), entries), 256n) &&
    valid_entries(entries, U32.to_nat(next_id))

def reference_valid(id: Maybe<&2, Nat>, registry: M.Projects) -> Bool:
  match id:
    case None{}: True{}
    case Some{id}: Bool.not(missing(find(registry, id)))

def tasks_bound(tasks: +List<M.Task>, +registry: M.Projects) -> Bool:
  match tasks:
    case Nil{}: True{}
    case Con{task, rest}: reference_valid(W.project_id(M.task_context(task)), registry) && tasks_bound(rest, registry)

def owns(expected: Nat, actual: Maybe<&2, Nat>) -> Bool:
  match actual:
    case None{}: False{}
    case Some{id}: Nat.is_eq(expected, id)

def counted(yes: Bool, rest: Nat) -> Nat:
  match yes:
    case True{}: 1n+rest
    case False{}: rest

def task_count(tasks: +List<M.Task>, +id: Nat) -> Nat:
  match tasks:
    case Nil{}: 0n
    case Con{task, rest}: counted(owns(id, W.project_id(M.task_context(task))), task_count(rest, id))

def projected(+id: Nat, project: M.Project, tasks: +List<M.Task>) -> J.Json:
  M.Project{name, M.Workspace{roots, primary}, guidance} = project
  J.Object{[J.Field{"project_id", J.nat(id)}, J.Field{"name", J.Text{name}},
    J.Field{"root_count", J.nat(List.length(&2, String, roots))}, J.Field{"primary_root", M.optional_string(primary)},
    J.Field{"task_count", J.nat(task_count(tasks, id))}]}

def summaries(entries: +List<Finite.Entry(M.Project)>, +tasks: +List<M.Task>) -> +List<J.Json>:
  match entries:
    case Nil{}: Nil{}
    case Con{(id, project), rest}: projected(id, project, tasks) <> summaries(rest, tasks)

def detail(id: Nat, found: Maybe<&2, M.Project>) -> J.Json:
  match found:
    case None{}: M.failure("project_not_found", "The project does not exist")
    case Some{M.Project{name, workspace, guidance}}:
      M.success(J.Object{[J.Field{"project_id", J.nat(id)}, J.Field{"name", J.Text{name}},
        J.Field{"workspace", M.workspace_json(workspace)}, J.Field{"guidance", M.project_json(guidance)}]})

def selected(found: Maybe<&2, M.Project>, id: Nat, base: M.TaskContext) -> Result<&2, &2, String, W.Selection>:
  match found:
    case None{}: Fail{"The selected project does not exist"}
    case Some{M.Project{name, workspace, guidance}}:
      M.TaskContext{previous, sandbox, approval, old_id} = base
      Done{W.Selection{M.TaskContext{workspace, sandbox, approval, Some{id}}, guidance}}

def select_id(id: Maybe<&2, Nat>, base: M.TaskContext, registry: M.Projects) -> Result<&2, &2, String, W.Selection>:
  match id:
    case None{}: Fail{"Invalid project identity"}
    case Some{+id}: selected(find(registry, id), id, base)

def select(value: J.Json, base: M.TaskContext, guidance: M.ProjectContext, +registry: M.Projects) -> Result<&2, &2, String, W.Selection>:
  match value:
    case J.Null{}: Done{W.Selection{base, guidance}}
    case J.Number{text}: select_id(Nat.read(text), base, registry)
    case _: Fail{"A project identity must be a nonnegative integer"}

def put(+id: Nat, project: M.Project, registry: M.Projects, next_id: U32) -> M.Projects:
  M.Projects{entries, previous_id} = registry
  M.Projects{(id, project) <> Finite.remove(~M.Project, entries, id), next_id}

def remove(id: Nat, registry: M.Projects) -> M.Projects:
  M.Projects{entries, next_id} = registry
  M.Projects{Finite.remove(~M.Project, entries, id), next_id}

def store(registry: M.Projects, world: M.World) -> M.World:
  M.World{tasks, next_task, next_ticket, environment, limits, previous, board} = world
  M.World{tasks, next_task, next_ticket, environment, limits, registry, board}

def rename(name: Maybe<&2, String>, fallback: String) -> String:
  match name:
    case None{}: fallback
    case Some{name}: name

def proposal(name: Maybe<&2, String>, +workspace: J.Json, +guidance: J.Json, previous: M.Project) -> M.Project:
  M.Project{previous_name, previous_workspace, previous_guidance} = previous
  +workspace = W.read_workspace(workspace, previous_workspace)
  M.Project{rename(name, previous_name), workspace, W.read_guidance(guidance, workspace, previous_guidance)}
