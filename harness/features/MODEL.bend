import Base
import ../../features/remote/MODEL.bend as Remote
import ../../features/remote/CODEC.bend as RemoteCodec
import ../../features/worktree/MODEL.bend as Worktree
import ../../features/worktree/CODEC.bend as WorktreeCodec
import ../../features/compaction/MODEL.bend as Compaction
import ../DOMAIN.bend as D
import ../../features/board/MODEL.bend as Board
import ../../features/board/CODEC.bend as BoardCodec
import ../../bendlib/json.bend as J
import ../../bendlib/component.bend as C
import ../../features/chatgpt/MODEL.bend as ChatGPT
import ../../features/chatgpt/CODEC.bend as ChatGPTCodec
import ../../features/task_graph/MODEL.bend as TaskGraph
import ../../features/task_graph/CODEC.bend as TaskGraphCodec
import ../tools/MODEL.bend as Tools
import ../tools/SYNTAX.bend as Native

# The empty product is the identity for adding further independent components.
# Only this assembly module selects their concrete state types and initializers.
def Rest() -> Data:
  Unit

def initial_rest() -> Rest():
  Unit{}

def RemoteModules() -> Data:
  C.Frame<Remote.State, Rest()>

def WorktreeModules() -> Data:
  C.Frame<Worktree.State, RemoteModules()>

def CompactionModules() -> Data:
  C.Frame<Compaction.State, WorktreeModules()>

def GraphModules() -> Data:
  C.Frame<TaskGraph.State, CompactionModules()>

def State() -> Data:
  C.Frame<Board.State, Modules()>

def Modules() -> Data:
  C.Frame<ChatGPT.State, GraphModules()>

def initial() -> State():
  C.Frame{Board.initial(), C.Frame{ChatGPT.initial(), C.Frame{TaskGraph.initial(), C.Frame{Compaction.initial(), C.Frame{Worktree.initial(), C.Frame{Remote.initial(), initial_rest()}}}}}}

def board(state: State()) -> Board.State:
  C.local(Board.State, Modules(), state)

def modules(state: State()) -> Modules():
  C.rest(Board.State, Modules(), state)

def rest(state: State()) -> Rest():
  C.rest(Remote.State, Rest(), C.rest(Worktree.State, RemoteModules(), C.rest(Compaction.State, WorktreeModules(), C.rest(TaskGraph.State, CompactionModules(), C.rest(ChatGPT.State, GraphModules(), C.rest(Board.State, Modules(), state))))))

def with_board(value: Board.State, state: State()) -> State():
  C.constructed_replacement(Board.State, Modules(), C.construct_replace(Board.State, Modules(), value, state))

def chatgpt(state: State()) -> ChatGPT.State:
  C.local(ChatGPT.State, GraphModules(), C.rest(Board.State, Modules(), state))

def with_chatgpt(value: ChatGPT.State, state: State()) -> State():
  C.map_rest(Board.State, Modules(), rest => C.constructed_replacement(ChatGPT.State, GraphModules(), C.construct_replace(ChatGPT.State, GraphModules(), value, rest)), state)

def with_rest(value: Rest(), state: State()) -> State():
  C.map_rest(Board.State, Modules(), modules => C.map_rest(ChatGPT.State, GraphModules(), graphs => C.map_rest(TaskGraph.State, CompactionModules(), compaction => C.map_rest(Compaction.State, WorktreeModules(), worktrees => C.map_rest(Worktree.State, RemoteModules(), remote => C.map_rest(Remote.State, Rest(), previous => value, remote), worktrees), compaction), graphs), modules), state)

def task_graph(state: State()) -> TaskGraph.State:
  C.local(TaskGraph.State, CompactionModules(), C.rest(ChatGPT.State, GraphModules(), C.rest(Board.State, Modules(), state)))

def with_task_graph(value: TaskGraph.State, state: State()) -> State():
  C.map_rest(Board.State, Modules(), modules => C.map_rest(ChatGPT.State, GraphModules(), graphs => C.constructed_replacement(TaskGraph.State, CompactionModules(), C.construct_replace(TaskGraph.State, CompactionModules(), value, graphs)), modules), state)

def compaction(state: State()) -> Compaction.State:
  C.local(Compaction.State, WorktreeModules(), C.rest(TaskGraph.State, CompactionModules(), C.rest(ChatGPT.State, GraphModules(), C.rest(Board.State, Modules(), state))))

def with_compaction(value: Compaction.State, state: State()) -> State():
  C.map_rest(Board.State, Modules(), modules => C.map_rest(ChatGPT.State, GraphModules(), graphs => C.map_rest(TaskGraph.State, CompactionModules(), compaction => C.constructed_replacement(Compaction.State, WorktreeModules(), C.construct_replace(Compaction.State, WorktreeModules(), value, compaction)), graphs), modules), state)

def worktree(state: State()) -> Worktree.State:
  C.local(Worktree.State, RemoteModules(), C.rest(Compaction.State, WorktreeModules(), C.rest(TaskGraph.State, CompactionModules(), C.rest(ChatGPT.State, GraphModules(), C.rest(Board.State, Modules(), state)))))

def with_worktree(value: Worktree.State, state: State()) -> State():
  C.map_rest(Board.State, Modules(), modules => C.map_rest(ChatGPT.State, GraphModules(), graphs => C.map_rest(TaskGraph.State, CompactionModules(), compaction => C.map_rest(Compaction.State, WorktreeModules(), worktrees => C.constructed_replacement(Worktree.State, RemoteModules(), C.construct_replace(Worktree.State, RemoteModules(), value, worktrees)), compaction), graphs), modules), state)


def remote(state: State()) -> Remote.State:
  C.local(Remote.State, Rest(), C.rest(Worktree.State, RemoteModules(), C.rest(Compaction.State, WorktreeModules(), C.rest(TaskGraph.State, CompactionModules(), C.rest(ChatGPT.State, GraphModules(), C.rest(Board.State, Modules(), state))))))

def with_remote(value: Remote.State, state: State()) -> State():
  C.map_rest(Board.State, Modules(), modules => C.map_rest(ChatGPT.State, GraphModules(), graphs => C.map_rest(TaskGraph.State, CompactionModules(), compaction => C.map_rest(Compaction.State, WorktreeModules(), worktrees => C.map_rest(Worktree.State, RemoteModules(), remote => C.constructed_replacement(Remote.State, Rest(), C.construct_replace(Remote.State, Rest(), value, remote)), worktrees), compaction), graphs), modules), state)

type Effect is Data:
  WorktreeEffect{effect: Worktree.Effect}
  CompactionEffect{effect: Compaction.Effect}
  ChatGPTEffect{effect: ChatGPT.Effect}
  RequestBoardText{card_id: Nat, ticket: Nat, profile: D.Profile, prompt: String, retitle: Bool}

type Command is Data:
  RemoteCommand{command: Remote.Admin}
  WorktreeCommand{command: Worktree.Command}
  ChatGPTCommand{command: ChatGPT.Command}
  BoardCommand{command: Board.Command}
  TaskGraphCommand{command: TaskGraph.Command}

type Query is Data:
  RemoteStatus{}
  WorktreeQuery{query: Worktree.Query}
  ChatGPTQuery{query: ChatGPT.Query}
  BoardQuery{query: Board.Query}
  TaskGraphQuery{query: TaskGraph.Query}

type CommandKind is Data:
  RemoteKind{kind: RemoteCodec.AdminKind}
  WorktreeKind{kind: WorktreeCodec.EntryKind}
  ChatGPTKind{kind: ChatGPTCodec.EntryKind}
  BoardKind{kind: BoardCodec.EntryKind}
  TaskGraphKind{kind: TaskGraphCodec.EntryKind}

type Completion is Data:
  WorktreeCompleted{completion: Worktree.Completion}
  CompactionCompleted{completion: Compaction.Completion}
  ChatGPTCompleted{operation: Nat, value: J.Json, error: Bool}
  BoardTextCompleted{card_id: Nat, ticket: Nat, outcome: Board.Outcome}

type CommandSpec is Data:
  CommandSpec{name: String, description: String, kind: CommandKind, schema: J.Json}

def board_specs(specs: +List<BoardCodec.Spec>) -> +List<CommandSpec>:
  match specs:
    case Nil{}: Nil{}
    case Con{BoardCodec.Spec{name, description, kind, schema}, rest}:
      CommandSpec{name, description, BoardKind{kind}, schema} <> board_specs(rest)

def chatgpt_specs(specs: +List<ChatGPTCodec.Spec>) -> +List<CommandSpec>:
  match specs:
    case Nil{}: Nil{}
    case Con{ChatGPTCodec.Spec{name, description, kind, schema}, rest}:
      CommandSpec{name, description, ChatGPTKind{kind}, schema} <> chatgpt_specs(rest)

def task_graph_specs(specs: +List<TaskGraphCodec.Spec>) -> +List<CommandSpec>:
  match specs:
    case Nil{}: Nil{}
    case Con{TaskGraphCodec.Spec{name, description, kind, schema}, rest}:
      CommandSpec{name, description, TaskGraphKind{kind}, schema} <> task_graph_specs(rest)

def task_graph_tools(specs: +List<TaskGraphCodec.Spec>) -> +List<D.Tool>:
  match specs:
    case Nil{}: Nil{}
    case Con{TaskGraphCodec.Spec{+name, description, kind, schema}, rest}:
      List.append(&2, D.Tool, Tools.catalog_entry(Tools.Request{name, description, Native.Feature{name, schema}}), task_graph_tools(rest))

def native_catalog(settings_schema: J.Json) -> +List<D.Tool>:
  task_graph_tools(TaskGraphCodec.specifications(settings_schema))

def worktree_specs(specs: +List<WorktreeCodec.Spec>) -> +List<CommandSpec>:
  match specs:
    case Nil{}: Nil{}
    case Con{WorktreeCodec.Spec{name, description, kind, schema}, rest}:
      CommandSpec{name, description, WorktreeKind{kind}, schema} <> worktree_specs(rest)

def remote_specs(specs: +List<RemoteCodec.Spec>) -> +List<CommandSpec>:
  match specs:
    case Nil{}: Nil{}
    case Con{RemoteCodec.Spec{name, description, kind, schema}, rest}:
      CommandSpec{name, description, RemoteKind{kind}, schema} <> remote_specs(rest)

def specs(+settings_schema: J.Json) -> +List<CommandSpec>:
  List.append(&2, CommandSpec, worktree_specs(WorktreeCodec.specs(settings_schema)), List.append(&2, CommandSpec, board_specs(BoardCodec.specs(settings_schema)),
    List.append(&2, CommandSpec, chatgpt_specs(ChatGPTCodec.specs()), List.append(&2, CommandSpec, task_graph_specs(TaskGraphCodec.specifications(settings_schema)), remote_specs(RemoteCodec.specs())))))

# Global input consumers use these classifications without inspecting feature
# cases. Local administration never advances runnable task work.
def schedules(command: Command) -> Bool:
  match command:
    case RemoteCommand{command}: False{}
    case _: True{}

def root_environment(command: Command) -> Bool:
  match command:
    case WorktreeCommand{Worktree.Create{profile, reasoning, message, settings}}: True{}
    case TaskGraphCommand{TaskGraph.Create{declaration}}: True{}
    case TaskGraphCommand{TaskGraph.Update{id, declaration}}: True{}
    case _: False{}
