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

type Backend is Data:
  Local{}
  TencentCvm{}

def backend_name(backend: Backend) -> String:
  match backend:
    case Local{}: "local"
    case TencentCvm{}: "tencent_cvm"

def cloud(backend: Backend) -> Bool:
  match backend:
    case Local{}: False{}
    case TencentCvm{}: True{}

def same_backend(left: Backend, right: Backend) -> Bool:
  match left right:
    case Local{} Local{}: True{}
    case TencentCvm{} TencentCvm{}: True{}
    case _ _: False{}

type Worktree is Data:
  Worktree{source_root: String, root: Maybe<&2, String>, status: Status, message: String, target_primary: String, backend: Backend}

type State is Data:
  State{entries: +List<Finite.Entry(Worktree)>}

type Command is Data:
  Create{profile: String, reasoning: String, message: D.UserContent, settings: J.Json}
  CreateWorkspace{backend: Backend, profile: String, reasoning: String, message: D.UserContent, settings: J.Json, work: Maybe<&2, Nat>}
  RetryArchive{task_id: Nat}

type Query is Data:
  ListWorktrees{}
  Read{task_id: Nat}

type Effect is Data:
  CreateTree{task_id: Nat, source_root: String, workspace: D.Workspace, backend: Backend}
  ArchiveTree{task_id: Nat, source_root: String, root: String, backend: Backend}

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
  Worktree{source_root, root, status, message, target_primary, backend} = value
  source_root

def root(value: Worktree) -> Maybe<&2, String>:
  Worktree{source_root, root, status, message, target_primary, backend} = value
  root

def status(value: Worktree) -> Status:
  Worktree{source_root, root, status, message, target_primary, backend} = value
  status

def message(value: Worktree) -> String:
  Worktree{source_root, root, status, message, target_primary, backend} = value
  message

def target_primary(value: Worktree) -> String:
  Worktree{source_root, root, status, message, target_primary, backend} = value
  target_primary

def with_status(status: Status, message: String, value: Worktree) -> Worktree:
  Worktree{source_root, root, previous, reason, target_primary, backend} = value
  Worktree{source_root, root, status, message, target_primary, backend}

def with_target_primary(target_primary: String, value: Worktree) -> Worktree:
  Worktree{source_root, root, status, message, previous, backend} = value
  Worktree{source_root, root, status, message, target_primary, backend}

def backend(value: Worktree) -> Backend:
  Worktree{source_root, root, status, message, target_primary, backend} = value
  backend

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
