import Base
import ../../harness/MODEL.bend as M
import ../../harness/COMMANDS.bend as Commands
import ../../bendlib/json.bend as J

type State is Data:
  State{query: String, project: Maybe<&2, Nat>, work: Maybe<&2, Nat>, result: Maybe<&2, J.Json>}

type Edit is Data:
  Write{query: String}
  Choose{project: Bool, value: String}

type Choice is Data:
  Choice{value: String, label: String}

def initial() -> State: State{"", None{}, None{}, None{}}

def keyword(state: State) -> String:
  State{query, project, work, result} = state
  query

def project(state: State) -> Maybe<&2, Nat>:
  State{query, project, work, result} = state
  project

def work(state: State) -> Maybe<&2, Nat>:
  State{query, project, work, result} = state
  work

def result(state: State) -> Maybe<&2, J.Json>:
  State{query, project, work, result} = state
  result

def selected(value: Maybe<&2, Nat>) -> String:
  match value:
    case None{}: ""
    case Some{id}: Nat.show(id)

def write(query: String, state: State) -> State:
  State{old, project, work, result} = state
  State{query, project, work, None{}}

def choose(project_scope: Bool, +value: String, +state: State) -> State:
  match project_scope:
    case True{}:
      State{query, project, work, result} = state
      State{query, Nat.read(value), work, None{}}
    case False{}:
      State{query, project, work, result} = state
      State{query, project, Nat.read(value), None{}}

def submit(+after: Nat, state: State, world: M.World()) -> State:
  State{+query, +project, +work, result} = state
  State{query, project, work, Some{Commands.query(M.Search{query, project, work, after, 20n}, world)}}

def edit(change: Edit, +state: State) -> State:
  match change:
    case Write{query}: write(query, state)
    case Choose{project, value}: choose(project, value, state)
