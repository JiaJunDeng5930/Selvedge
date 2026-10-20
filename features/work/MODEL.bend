import Base
import ../../harness/DOMAIN.bend as D
import ../../bendlib/json.bend as J
import ../../bendlib/association-map.bend as Finite
import ./ui-patch.bend as Patch

type Work is Data:
  Work{name: String, ui_source: String, ui_revision: Nat}

type State is Data:
  State{works: +List<Finite.Entry(Work)>, roots: +List<Finite.Entry(Nat)>, graphs: +List<Finite.Entry(Nat)>, next: Nat}

type Command is Data:
  Create{name: String}
  Rename{id: Nat, name: String}
  ApplyUIPatch{caller: Maybe<&2, Nat>, patch: String, revision: Nat}
  CreateTask{work: Nat, profile: String, reasoning: String, message: D.UserContent, settings: J.Json, create_worktree: Bool}

type Query is Data:
  ListWorks{}
  ReadWork{id: Nat}
  ReadUI{caller: Maybe<&2, Nat>}

type Change is Data:
  Add{id: Nat, work: Work, next: Nat}
  Retitle{id: Nat, work: Work}
  UpdateUI{id: Nat, work: Work}

type Resolution is Data:
  Refuse{code: String, reason: String}
  Accept{change: Change}

def initial() -> State:
  State{Nil{}, Nil{}, Nil{}, 0n}

def works(state: State) -> +List<Finite.Entry(Work)>:
  State{works, roots, graphs, next} = state
  works

def roots(state: State) -> +List<Finite.Entry(Nat)>:
  State{works, roots, graphs, next} = state
  roots

def graphs(state: State) -> +List<Finite.Entry(Nat)>:
  State{works, roots, graphs, next} = state
  graphs

def next(state: State) -> Nat:
  State{works, roots, graphs, next} = state
  next

def name(work: Work) -> String:
  Work{name, source, revision} = work
  name

def ui_source(work: Work) -> String:
  Work{name, source, revision} = work
  source

def ui_revision(work: Work) -> Nat:
  Work{name, source, revision} = work
  revision

def with_ui(source: String, revision: Nat, work: Work) -> Work:
  Work{name, previous, previous_revision} = work
  Work{name, source, revision}

def find(state: State, id: Nat) -> Maybe<&2, Work>:
  Finite.find(~Work, works(state), id)

def root_owner(state: State, id: Nat) -> Maybe<&2, Nat>:
  Finite.find(~Nat, roots(state), id)

def graph_owner(state: State, id: Nat) -> Maybe<&2, Nat>:
  Finite.find(~Nat, graphs(state), id)

def preferred_owner(found: Maybe<&2, Nat>, inherited: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match found:
    case Some{id}: Some{id}
    case None{}: inherited

def lineage_owner(+state: State, lineage: +List<Nat>) -> Maybe<&2, Nat>:
  match lineage:
    case Nil{}: None{}
    case Con{id, rest}: preferred_owner(root_owner(state, id), lineage_owner(state, rest))

def task_owner_found(found: Maybe<&2, Nat>, state: State, lineage: +List<Nat>) -> Maybe<&2, Nat>:
  preferred_owner(found, lineage_owner(state, lineage))

def task_owner(+state: State, id: Nat, lineage: +List<Nat>) -> Maybe<&2, Nat>:
  task_owner_found(root_owner(state, id), state, lineage)

def associate_task_found(found: Maybe<&2, Nat>, work: Maybe<&2, Work>, +id: Nat, owner: Nat, state: State) -> State:
  match found work:
    case None{} Some{value}:
      State{works, roots, graphs, next} = state
      State{works, List.append(&2, Finite.Entry(Nat), roots, [(id, owner)]), graphs, next}
    case _ _: state

def associate_task(+id: Nat, +owner: Nat, +state: State) -> State:
  associate_task_found(root_owner(state, id), find(state, owner), id, owner, state)

def associate_graph_found(found: Maybe<&2, Nat>, work: Maybe<&2, Work>, +id: Nat, owner: Nat, state: State) -> State:
  match found work:
    case None{} Some{value}:
      State{works, roots, graphs, next} = state
      State{works, roots, List.append(&2, Finite.Entry(Nat), graphs, [(id, owner)]), next}
    case _ _: state

def associate_graph(+id: Nat, +owner: Nat, +state: State) -> State:
  associate_graph_found(graph_owner(state, id), find(state, owner), id, owner, state)

def dissociate_graph(+id: Nat, state: State) -> State:
  State{works, roots, graphs, next} = state
  State{works, roots, Finite.remove(~Nat, graphs, id), next}

def present(~V: Data, found: Maybe<&2, V>) -> Bool:
  match found:
    case None{}: False{}
    case Some{value}: True{}

def valid_name(+value: String) -> Bool:
  Bool.not(String.eq(value, "")) && Nat.is_le(J.utf8_length(value), 4096n)

def valid_works(values: +List<Finite.Entry(Work)>, +next: Nat) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{(+id, +value), +rest}: Nat.is_lt(id, next) && valid_name(name(value)) && Nat.is_le(String.length(ui_source(value)), 100000n) && Nat.is_le(ui_revision(value), 4294967295n) &&
      Bool.not(present(~Work, Finite.find(~Work, rest, id))) && valid_works(rest, next)

def valid_owners(values: +List<Finite.Entry(Nat)>, +works: +List<Finite.Entry(Work)>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{(+id, owner), +rest}: Nat.is_le(id, 4294967295n) && present(~Work, Finite.find(~Work, works, owner)) &&
      Bool.not(present(~Nat, Finite.find(~Nat, rest, id))) && valid_owners(rest, works)

def valid(+state: State) -> Bool:
  Nat.is_le(next(state), 4294967295n) && valid_works(works(state), next(state)) &&
    valid_owners(roots(state), works(state)) && valid_owners(graphs(state), works(state))

def default_name(+id: Nat, value: String) -> String:
  match value:
    case "": "Work #" ++ Nat.show(id)
    case _: value

def create_valid(accepted: Bool, +id: Nat, name: String) -> Resolution:
  match accepted:
    case False{}: Refuse{"invalid_name", "Work names must contain between 1 and 4096 UTF-8 bytes."}
    case True{}: Accept{Add{id, Work{name, "", 0n}, 1n+id}}

def create_available(available: Bool, +id: Nat, +name: String) -> Resolution:
  match available:
    case False{}: Refuse{"capacity", "No more Work identifiers are available."}
    case True{}: create_valid(valid_name(name), id, name)

def rename_valid(accepted: Bool, id: Nat, name: String, +previous: Work) -> Resolution:
  match accepted:
    case False{}: Refuse{"invalid_name", "Work names must contain between 1 and 4096 UTF-8 bytes."}
    case True{}: Accept{Retitle{id, Work{name, ui_source(previous), ui_revision(previous)}}}

def rename_found(found: Maybe<&2, Work>, id: Nat, +name: String) -> Resolution:
  match found:
    case None{}: Refuse{"not_found", "Work does not exist."}
    case Some{previous}: rename_valid(valid_name(name), id, name, previous)

def resolve(command: Command, +state: State) -> Resolution:
  match command:
    case Create{name}: create_available(Nat.is_lt(next(state), 4294967295n), next(state), default_name(next(state), name))
    case Rename{+id, name}: rename_found(find(state, id), id, name)
    case ApplyUIPatch{caller, patch, revision}:
      Refuse{"task_call_required", "Edit the shared UI through a Task tool call."}
    case CreateTask{work, profile, reasoning, message, settings, create_worktree}:
      Refuse{"task_creation_boundary", "Create Work Tasks through the harness feature operation."}

def work_json(id: Nat, work: Work) -> J.Json:
  J.Object{[J.Field{"work_id", J.nat(id)}, J.Field{"name", J.Text{name(work)}}]}


def ui_json(id: Nat, +work: Work) -> J.Json:
  J.Object{[J.Field{"work_id", J.nat(id)}, J.Field{"source", J.Text{ui_source(work)}},
    J.Field{"revision", J.nat(ui_revision(work))}]}

def patched_source(result: Result<&2, &2, String, String>, id: Nat, +previous: Work) -> Resolution:
  match result:
    case Fail{reason}: Refuse{"invalid_patch", reason}
    case Done{source}: Accept{UpdateUI{id, with_ui(source, 1n+ui_revision(previous), previous)}}

def patch_revision(matches: Bool, id: Nat, patch: String, +previous: Work) -> Resolution:
  match matches:
    case False{}: Refuse{"revision_conflict", "The Work UI changed. Read its current source and revision before applying another patch."}
    case True{}: patched_source(Patch.apply(ui_source(previous), patch), id, previous)

def patch_available(available: Bool, +id: Nat, patch: String, +revision: Nat, +previous: Work) -> Resolution:
  match available:
    case False{}: Refuse{"capacity", "No more Work UI revisions are available."}
    case True{}: patch_revision(Nat.is_eq(revision, ui_revision(previous)), id, patch, previous)

def patch_found(found: Maybe<&2, Work>, id: Nat, patch: String, revision: Nat) -> Resolution:
  match found:
    case None{}: Refuse{"work_not_found", "The Work does not exist."}
    case Some{+previous}: patch_available(Nat.is_lt(ui_revision(previous), 4294967295n), id, patch, revision, previous)
