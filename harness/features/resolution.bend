import Base
import ../../features/worktree/MODEL.bend as Worktree
import ../../bendlib/categories.bend as Categories
import ../DOMAIN.bend as D
import ../../bendlib/json.bend as J
import ../MODEL.bend as M
import ./MODEL.bend as F
import ../../features/board/MODEL.bend as B
import ../workspace/WORKSPACE.bend as Workspace
import ./operations.bend as O
import ../../features/board/resolution.bend as Board
import ../../features/chatgpt/MODEL.bend as ChatGPT
import ../workspace/PROJECTS.bend as Projects
import ../../features/chatgpt/STATE.bend as ChatGPTState
import ../../features/task_graph/MODEL.bend as G
import ./graph-state.bend as GraphState
import ../../bendlib/component.bend as C
import ../tasks/PROGRAM.bend as Tasks
import ./worktree-state.bend as WorktreeState

type Start is Data:
  Start{profile: D.Profile, reasoning: String, message: String, selection: Workspace.Selection}
  StartRefused{code: String, reason: String}
  InvalidStart{}

type Resolution is Data:
  Refuse{code: String, reason: String}
  Accept{operation: O.Operation}

type GraphNodes is Data:
  GraphNodes{nodes: +List<O.GraphNode>}
  GraphNodesRefused{code: String, reason: String}

def graph_prepend(node: O.GraphNode, result: GraphNodes) -> GraphNodes:
  match result:
    case GraphNodes{nodes}: GraphNodes{node <> nodes}
    case GraphNodesRefused{code, reason}: GraphNodesRefused{code, reason}

def graph_spawn(start: Start, key: String, rest: GraphNodes) -> GraphNodes:
  match start:
    case Start{profile, reasoning, message, selection}: graph_prepend(O.GraphSpawn{key, profile, reasoning, message, selection}, rest)
    case StartRefused{code, reason}: GraphNodesRefused{code, reason}
    case InvalidStart{}: GraphNodesRefused{"invalid_graph_start", "A graph node must resolve through ordinary task creation"}

def graph_existing(exists: Bool, key: String, id: Nat, rest: GraphNodes) -> GraphNodes:
  match exists:
    case True{}: graph_prepend(O.GraphExisting{key, id}, rest)
    case False{}: GraphNodesRefused{"task_not_found", "A graph node references a task that does not exist"}

def graph_nodes(~start: String -> String -> String -> J.Json -> @+world:M.World() -> Start,
  nodes: +List<G.Node>, +world: M.World()) -> GraphNodes:
  match nodes:
    case Nil{}: GraphNodes{Nil{}}
    case Con{G.Existing{key, +id}, rest}:
      graph_existing(GraphState.task_exists(Tasks.find(D.state_tasks(C.local(D.State, F.State(), world)), id)), key, id, graph_nodes(~start, rest, world))
    case Con{G.Spawn{key, profile, reasoning, message, settings}, rest}:
      graph_spawn(start(profile, reasoning, message, settings, world), key, graph_nodes(~start, rest, world))

def graph_install(nodes: GraphNodes, id: Nat, declaration: G.Declaration) -> Resolution:
  match nodes:
    case GraphNodes{nodes}: Accept{O.InstallGraph{id, declaration, nodes}}
    case GraphNodesRefused{code, reason}: Refuse{code, reason}

def graph_built(~start: String -> String -> String -> J.Json -> @+world:M.World() -> Start,
  declaration: G.Declaration, id: Nat, +world: M.World()) -> Resolution:
  G.Declaration{name, +nodes, rules} = declaration
  graph_install(graph_nodes(~start, nodes, world), id, G.Declaration{name, nodes, rules})

def graph_constructed(~start: String -> String -> String -> J.Json -> @+world:M.World() -> Start,
  constructed: Maybe<&1, Categories.Membership<G.Declaration, G.admissible>>, id: Nat, +world: M.World()) -> Resolution:
  match constructed:
    case None{}: Refuse{"invalid_task_graph", "The task graph declaration has invalid identifiers, references or bounds"}
    case Some{member}: graph_built(~start, G.constructed_declaration(member), id, world)

def graph_admitted(~start: String -> String -> String -> J.Json -> @+world:M.World() -> Start,
  allowed: Bool, id: Nat, +declaration: G.Declaration, +world: M.World()) -> Resolution:
  match allowed:
    case False{}: Refuse{"invalid_task_graph", "The task graph declaration is invalid or the graph limit has been reached"}
    case True{}: graph_constructed(~start, G.construct(declaration), id, world)

def graph_update(~start: String -> String -> String -> J.Json -> @+world:M.World() -> Start,
  found: Maybe<&2, G.Graph>, id: Nat, +declaration: G.Declaration, world: M.World()) -> Resolution:
  match found:
    case None{}: Refuse{"task_graph_not_found", "The task graph does not exist"}
    case Some{graph}: graph_admitted(~start, True{}, id, declaration, world)

def graph_remove(found: Maybe<&2, G.Graph>, id: Nat) -> Resolution:
  match found:
    case None{}: Refuse{"task_graph_not_found", "The task graph does not exist"}
    case Some{graph}: Accept{O.DeleteGraph{id}}

def graph(~start: String -> String -> String -> J.Json -> @+world:M.World() -> Start, command: G.Command, +world: M.World()) -> Resolution:
  match command:
    case G.Create{+declaration}:
      graph_admitted(~start, G.capacity(GraphState.registry(world)), G.next(GraphState.registry(world)), declaration, world)
    case G.Update{+id, declaration}: graph_update(~start, G.find(GraphState.registry(world), id), id, declaration, world)
    case G.Delete{+id}: graph_remove(G.find(GraphState.registry(world), id), id)

def card_start(start: Start, id: Nat, card: B.Card, now: U32) -> Resolution:
  match start:
    case Start{profile, reasoning, message, selection}: Accept{O.StartCard{id, card, now, profile, reasoning, message, selection}}
    case StartRefused{code, reason}: Refuse{code, reason}
    case InvalidStart{}: Refuse{"invalid_card_start", "A board launch must resolve through ordinary task creation"}

def without_project(fields: +List<J.Field>) -> +List<J.Field>:
  match fields:
    case Nil{}: Nil{}
    case Con{J.Field{"project_id", value}, rest}: without_project(rest)
    case Con{field, rest}: field <> without_project(rest)

def with_project(project: Maybe<&2, Nat>, fields: +List<J.Field>) -> J.Json:
  match project:
    case None{}: J.Object{fields}
    case Some{id}: J.Object{J.Field{"project_id", J.nat(id)} <> fields}

def card_options(project: Maybe<&2, Nat>, options: J.Json) -> J.Json:
  match options:
    case J.Object{fields}: with_project(project, without_project(fields))
    case _: with_project(project, Nil{})

def board(~start: String -> String -> String -> J.Json -> @+world:M.World() -> Start, resolution: Board.Resolution, world: M.World()) -> Resolution:
  match resolution:
    case Board.Refuse{code, reason}: Refuse{code, reason}
    case Board.Mutate{change}: Accept{O.BoardChange{change}}
    case Board.Launch{+id, +card, now, +agent}:
      card_start(start(B.agent_profile(agent), B.agent_reasoning(agent), B.prompt(id, B.draft(card), B.agent_instructions(agent)),
        card_options(B.project(B.draft(card)), B.agent_settings(agent)), world), id, card, now)

def chatgpt(resolution: ChatGPT.Resolution) -> Resolution:
  match resolution:
    case ChatGPT.Refuse{code, reason}: Refuse{code, reason}
    case ChatGPT.Accept{change}: Accept{O.ChatGPTChange{change}}

def worktree_selected(has_primary: Bool, profile: D.Profile, reasoning: String, message: String, selection: Workspace.Selection) -> Resolution:
  match has_primary:
    case False{}: Refuse{"worktree_requires_git", "A worktree requires a primary workspace in a Git repository"}
    case True{}: Accept{O.StartWorktree{profile, reasoning, message, selection}}

def worktree_start(start: Start) -> Resolution:
  match start:
    case Start{profile, reasoning, message, +selection}:
      worktree_selected(D.nonempty(WorktreeState.selection_primary(selection)), profile, reasoning, message, selection)
    case StartRefused{code, reason}: Refuse{code, reason}
    case InvalidStart{}: Refuse{"invalid_worktree_start", "Worktree creation must resolve through ordinary task creation"}

def worktree_retry(allowed: Bool, id: Nat) -> Resolution:
  match allowed:
    case False{}: Refuse{"worktree_archive_not_retryable", "Only a failed worktree archive with a retained root can be retried"}
    case True{}: Accept{O.RetryWorktreeArchive{id}}

def worktree_archive_available(allowed: Bool, resolution: Resolution) -> Resolution:
  match allowed:
    case True{}: resolution
    case False{}: Refuse{"worktree_in_use", "This worktree is shared by other tasks. Archive those tasks before archiving its owner."}

def worktree(~start: String -> String -> String -> J.Json -> @+world:M.World() -> Start, command: Worktree.Command, +world: M.World()) -> Resolution:
  match command:
    case Worktree.Create{profile, reasoning, message, settings}: worktree_start(start(profile, reasoning, message, settings, world))
    case Worktree.RetryArchive{+id}: worktree_archive_available(WorktreeState.archive_allowed(id, world), worktree_retry(WorktreeState.retry_allowed(id, world), id))

def resolve_calculation(~start: String -> String -> String -> J.Json -> @+world:M.World() -> Start, command: F.Command, +world: M.World()) -> Resolution:
  match command:
    case F.WorktreeCommand{command}: worktree(~start, command, world)
    case F.ChatGPTCommand{command}: chatgpt(ChatGPT.resolve(command, ChatGPTState.registry(world), Projects.registry(F.State(), world)))
    case F.BoardCommand{command}: board(~start, Board.change_resolution(Board.construct_command(command, world)), world)
    case F.TaskGraphCommand{command}: graph(~start, command, world)

def native_start_allowed(start: Start, settings: J.Json, +caller: D.Task, +world: M.World()) -> Bool:
  match start:
    case Start{profile, reasoning, message, Workspace.Selection{context, guidance}}:
      Projects.native_creation_settings(settings, context, D.task_context(caller),
        D.state_environment(C.local(D.State, F.State(), world)), Projects.registry(F.State(), world))
    case _: True{}

def native_nodes(~start: String -> String -> String -> J.Json -> @+world:M.World() -> Start,
  nodes: +List<G.Node>, +caller: D.Task, +world: M.World()) -> Bool:
  match nodes:
    case Nil{}: True{}
    case Con{G.Existing{key, id}, rest}: native_nodes(~start, rest, caller, world)
    case Con{G.Spawn{key, profile, reasoning, message, +settings}, rest}:
      native_start_allowed(start(profile, reasoning, message, settings, world), settings, caller, world) && native_nodes(~start, rest, caller, world)

def native_declaration(~start: String -> String -> String -> J.Json -> @+world:M.World() -> Start,
  declaration: G.Declaration, caller: D.Task, world: M.World()) -> Bool:
  G.Declaration{name, nodes, rules} = declaration
  native_nodes(~start, nodes, caller, world)

def native_admissible(~start: String -> String -> String -> J.Json -> @+world:M.World() -> Start,
  caller: D.Task, command: F.Command, world: M.World()) -> Bool:
  match command:
    case F.TaskGraphCommand{G.Create{declaration}}: native_declaration(~start, declaration, caller, world)
    case F.TaskGraphCommand{G.Update{id, declaration}}: native_declaration(~start, declaration, caller, world)
    case _: True{}

type CommandRequest is Data:
  CommandRequest{command: F.Command, world: M.World()}

def command_resolution(~start: String -> String -> String -> J.Json -> @+world:M.World() -> Start, request: CommandRequest) -> Resolution:
  CommandRequest{command, world} = request
  resolve_calculation(~start, command, world)

def ConstructedCommand(~start: String -> String -> String -> J.Json -> @+world:M.World() -> Start) -> Type:
  Categories.Membership<Categories.Construction<CommandRequest, Resolution>,
    Categories.constructed_by(CommandRequest, Resolution, command_resolution(~start))>

def construct_command(~start: String -> String -> String -> J.Json -> @+world:M.World() -> Start, command: F.Command, world: M.World()) -> ConstructedCommand(~start):
  Categories.construct(CommandRequest, Resolution, command_resolution(~start), CommandRequest{command, world})


def command_value(~start: String -> String -> String -> J.Json -> @+world:M.World() -> Start, member: ConstructedCommand(~start)) -> Resolution:
  Categories.Membership{Categories.Construction{request, result}, evidence} = member
  result

def resolve(~start: String -> String -> String -> J.Json -> @+world:M.World() -> Start, command: F.Command, +world: M.World()) -> Resolution:
  command_value(~start, construct_command(~start, command, world))
