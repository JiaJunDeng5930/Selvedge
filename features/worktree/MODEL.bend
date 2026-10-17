import Base
import ../../harness/DOMAIN.bend as D
import ../../bendlib/json.bend as J
import ../../bendlib/association-map.bend as Finite

type Status is Data:
  Creating{}
  CreatingArchived{}
  Ready{}
  CreateFailed{}
  Archiving{}
  Archived{}
  ArchiveFailed{}

type Worktree is Data:
  Worktree{source_root: String, root: Maybe<&2, String>, status: Status, message: String, target_primary: String}

type State is Data:
  State{entries: +List<Finite.Entry(Worktree)>}

type Command is Data:
  Create{profile: String, reasoning: String, message: String, settings: J.Json}
  RetryArchive{task_id: Nat}

type Query is Data:
  ListWorktrees{}
  Read{task_id: Nat}

type Effect is Data:
  CreateTree{task_id: Nat, source_root: String, workspace: D.Workspace}
  ArchiveTree{task_id: Nat, source_root: String, root: String}

type Completion is Data:
  Created{task_id: Nat, ok: Bool, root: Maybe<&2, String>, workspace: D.Workspace, guidance: D.ProjectContext, message: String}
  ArchivedResult{task_id: Nat, ok: Bool, root: String, message: String}

def initial() -> State:
  State{Nil{}}

def entries(state: State) -> +List<Finite.Entry(Worktree)>:
  State{entries} = state
  entries

def lookup(task_id: Nat, state: State) -> Maybe<&2, Worktree>:
  Finite.find(~Worktree, entries(state), task_id)

def put(+task_id: Nat, value: Worktree, state: State) -> State:
  State{(task_id, value) <> Finite.remove(~Worktree, entries(state), task_id)}

def source_root(value: Worktree) -> String:
  Worktree{source_root, root, status, message, target_primary} = value
  source_root

def root(value: Worktree) -> Maybe<&2, String>:
  Worktree{source_root, root, status, message, target_primary} = value
  root

def status(value: Worktree) -> Status:
  Worktree{source_root, root, status, message, target_primary} = value
  status

def message(value: Worktree) -> String:
  Worktree{source_root, root, status, message, target_primary} = value
  message

def target_primary(value: Worktree) -> String:
  Worktree{source_root, root, status, message, target_primary} = value
  target_primary

def with_status(status: Status, message: String, value: Worktree) -> Worktree:
  Worktree{source_root, root, previous, reason, target_primary} = value
  Worktree{source_root, root, status, message, target_primary}

def with_target_primary(target_primary: String, value: Worktree) -> Worktree:
  Worktree{source_root, root, status, message, previous} = value
  Worktree{source_root, root, status, message, target_primary}

def pending(status: Status) -> Bool:
  match status:
    case Creating{}: True{}
    case CreatingArchived{}: True{}
    case Archiving{}: True{}
    case _: False{}

def archivable(status: Status) -> Bool:
  match status:
    case Ready{}: True{}
    case CreateFailed{}: True{}
    case ArchiveFailed{}: True{}
    case _: False{}
