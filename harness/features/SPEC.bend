import Base
import ../../features/titles/SPEC.bend as Titles
import ./remote.bend as RemoteState
import ./worktree-spec.bend as WorktreeSpec
import ../../features/compaction/SPEC.bend as Compaction
import ../DOMAIN.bend as D
import ../MODEL.bend as M
import ../workspace/WORKSPACE.bend as Workspace
import ./operations.bend as O
import ../../features/board/SPEC.bend as Board
import ../../features/board/STATE.bend as State
import ../../features/chatgpt/SPEC.bend as ChatGPT
import ../../features/chatgpt/STATE.bend as ChatGPTState
import ./graph-spec.bend as TaskGraph
import ../../features/work/SPEC.bend as Work
import ../../features/work/MODEL.bend as WorkModel
import ./work-state.bend as WorkState
import ./MODEL.bend as F
import ../../bendlib/component.bend as C
import ../../bendlib/json.bend as J

def work_birth(accepted: Bool, work: Nat, task: Nat, original: M.World(), decision: M.Decision()) -> M.Decision():
  match accepted decision:
    case False{} C.Decision{world, reply, effects}: C.Decision{original, reply, Nil{}}
    case True{} C.Decision{+world, reply, effects}:
      C.Decision{WorkState.store(WorkModel.associate_task(task, work, WorkState.registry(world)), world), reply, effects}

def work_created(work: Nat, task: Nat, original: M.World(), decision: M.Decision()) -> M.Decision():
  C.Decision{world, +reply, effects} = decision
  work_birth(J.boolean(J.get(reply, "ok")), work, task, original, C.Decision{world, reply, effects})

# The caller supplies the independent task-creation specification. The
# executable assembler supplies its implementation to feature-execution.
def meaning(~spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(), operation: O.Operation, +world: M.World()) -> M.Decision():
  match operation:
    case O.WorkChange{change}: WorkState.embed(Work.meaning(change, WorkState.registry(world)), world)
    case O.StartWorkTask{work, profile, reasoning, message, selection}:
      work_created(work, D.state_next_task(C.local(D.State, F.State(), world)), world, spawn(profile, reasoning, message, selection, world))
    case O.StartWorkWorktree{work, profile, reasoning, message, selection}:
      work_created(work, D.state_next_task(C.local(D.State, F.State(), world)), world,
        WorktreeSpec.start(~spawn, profile, reasoning, message, selection, world))
    case O.ConfigureTitles{prompts}: Titles.configure(prompts, world)
    case O.RemoteChange{change}: RemoteState.embed(change, world)
    case O.StartWorktree{profile, reasoning, message, selection}: WorktreeSpec.start(~spawn, profile, reasoning, message, selection, world)
    case O.RetryWorktreeArchive{id}: WorktreeSpec.retry_archive(id, world)
    case O.ChatGPTChange{change}: ChatGPTState.embed(ChatGPT.meaning(change, ChatGPTState.registry(world)), world)
    case O.BoardChange{change}: Board.change(change, world)
    case O.StartCard{id, card, now, profile, reasoning, message, selection}:
      Board.started(id, State.task_id(world), card, now, spawn(profile, reasoning, message, selection, world))
    case O.InstallGraph{id, work, declaration, nodes}: TaskGraph.install(~spawn, id, work, declaration, nodes, world)
    case O.DeleteGraph{id}: TaskGraph.remove(id, world)

def event(event: O.ResolvedEvent, +world: M.World()) -> M.Decision():
  match event:
    case O.TitleResult{completion}: Titles.complete(completion, world)
    case O.WorktreeResult{completion}: WorktreeSpec.complete(completion, world)
    case O.CompactionResult{completion}: Compaction.meaning(Compaction.resolve(completion, world), world)
    case O.ChatGPTResult{change}: ChatGPTState.embed(ChatGPT.meaning(change, ChatGPTState.registry(world)), world)
    case O.BoardTextResult{id, card, outcome, retitle}: Board.completed(id, card, outcome, retitle, world)

def react(~send: Nat -> String -> @+world:M.World() -> M.Decision(), source: Nat, output: String, world: M.World()) -> M.Decision():
  TaskGraph.react(~send, source, output, world)

def react_outputs(~send: Nat -> String -> @+world:M.World() -> M.Decision(), source: Nat, outputs: +List<String>, world: M.World()) -> M.Decision():
  TaskGraph.react_outputs(~send, source, outputs, world)
