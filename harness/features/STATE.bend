import Base
import ../../features/worktree/MODEL.bend as Worktree
import ../../features/worktree/CODEC.bend as WorktreeCodec
import ./worktree-state.bend as WorktreeState
import ../../features/compaction/MODEL.bend as Compaction
import ../../features/compaction/STATE.bend as CompactionState
import ./MODEL.bend as F
import ../MODEL.bend as M
import ../../features/board/MODEL.bend as B
import ../workspace/WORKSPACE.bend as Workspace
import ../DOMAIN.bend as D
import ../../features/board/STATE.bend as Board
import ../../bendlib/association-map.bend as Finite
import ../../bendlib/equality.bend as Same
import ../../bendlib/json.bend as J
import ../../features/chatgpt/MODEL.bend as ChatGPT
import ../../features/chatgpt/STATE.bend as ChatGPTState
import ../../features/chatgpt/view.bend as ChatGPTView
import ../workspace/PROJECTS.bend as Projects
import ../../features/task_graph/MODEL.bend as TaskGraph
import ../../features/task_graph/CODEC.bend as TaskGraphCodec
import ./graph-state.bend as TaskGraphState

# State and resource obligations are assembled here. Adding a component must
# provide its own validity, evolution, recovery and effect-authority clauses.
def valid(+world: M.World()) -> Bool:
  WorktreeState.valid(world) && Board.valid(world) && ChatGPTState.valid(world) && TaskGraphState.valid(world) && CompactionState.valid(world)

def evolution(+previous: F.State(), +candidate: F.State()) -> Bool:
  WorktreeState.evolution(F.worktree(previous), F.worktree(candidate)) && Board.evolution(F.board(previous), F.board(candidate)) && Nat.is_le(ChatGPT.next(F.chatgpt(previous)), ChatGPT.next(F.chatgpt(candidate))) &&
    Nat.is_le(TaskGraph.next(F.task_graph(previous)), TaskGraph.next(F.task_graph(candidate))) && Compaction.evolution(F.compaction(previous), F.compaction(candidate))

def recover(+state: F.State()) -> F.State():
  F.with_compaction(Compaction.recover(F.compaction(state)), F.with_chatgpt(ChatGPT.recover(F.chatgpt(state)), F.with_board(Board.recover(F.board(state)), state)))

def project_used(+id: Nat, +world: M.World()) -> Bool:
  Board.project_used(B.cards(Board.registry(world)), id) || ChatGPT.project_used(ChatGPTState.registry(world), id)

def effective_worktree_reply(found: Maybe<&2, Finite.Entry(Worktree.Worktree)>) -> J.Json:
  match found:
    case None{}: D.failure("not_found", "Task worktree does not exist.")
    case Some{(owner, value)}: D.success(WorktreeCodec.entry_json(owner, value))

def worktree_query(query: Worktree.Query, +world: M.World()) -> J.Json:
  match query:
    case Worktree.ListWorktrees{}: WorktreeCodec.query_reply(query, WorktreeState.registry(world))
    case Worktree.Read{id}: effective_worktree_reply(WorktreeState.effective(id, world))

def query(query: F.Query, +world: M.World()) -> J.Json:
  match query:
    case F.WorktreeQuery{query}: worktree_query(query, world)
    case F.ChatGPTQuery{query}: ChatGPTView.query(query, ChatGPTState.registry(world), Projects.registry(F.State(), world))
    case F.BoardQuery{query}: Board.query(query, world)
    case F.TaskGraphQuery{query}: TaskGraphCodec.query_reply(query, TaskGraphState.registry(world))

def prepend_ticket(pending: B.Enrichment, rest: +List<Nat>) -> +List<Nat>:
  match pending:
    case B.Enriching{ticket, revision, retitle}: ticket <> rest
    case _: rest

def board_tickets(cards: +List<Finite.Entry(B.Card)>) -> +List<Nat>:
  match cards:
    case Nil{}: Nil{}
    case Con{(id, card), rest}: prepend_ticket(B.enrichment(card), board_tickets(rest))

def pending_tickets(+state: F.State()) -> +List<Nat>:
  List.append(&2, Nat, board_tickets(B.cards(F.board(state))), CompactionState.pending(Compaction.entries(F.compaction(state))))

def effect_ticket(effect: F.Effect) -> Maybe<&2, Nat>:
  match effect:
    case F.WorktreeEffect{effect}: None{}
    case F.CompactionEffect{effect}: CompactionState.effect_ticket(effect)
    case F.ChatGPTEffect{effect}: None{}
    case F.RequestBoardText{id, ticket, profile, prompt, retitle}: Some{ticket}

def configured_board_profile(found: Maybe<&2, D.Profile>, +profile: D.Profile) -> Bool:
  match found:
    case None{}: False{}
    case Some{configured}: Workspace.profile_same(profile, configured) && Board.drafting_profile(profile)

def board_request_observations(archived: Bool, enrichment: B.Enrichment, +card: B.Card, ticket: Nat, prompt: String, +retitle: Bool) -> Bool:
  match archived enrichment:
    case False{} B.Enriching{expected, revision, title_only}:
      Nat.is_eq(ticket, expected) && Nat.is_eq(B.revision(card), revision) && Same.booleans(retitle, title_only) &&
        String.eq(prompt, B.drafting_prompt(retitle, B.draft(card)))
    case _ _: False{}

def board_request(found: Maybe<&2, B.Card>, ticket: Nat, prompt: String, +retitle: Bool) -> Bool:
  match found:
    case Some{+card}: board_request_observations(B.archived(card), B.enrichment(card), card, ticket, prompt, retitle)
    case _: False{}

def effect_valid(effect: F.Effect, state: F.State(), profiles: +List<D.Profile>) -> Bool:
  match effect:
    case F.WorktreeEffect{effect}: WorktreeState.effect_valid(effect, F.worktree(state))
    case F.CompactionEffect{effect}: CompactionState.effect_valid(effect, F.compaction(state))
    case F.ChatGPTEffect{effect}: ChatGPT.effect_valid(effect, F.chatgpt(state))
    case F.RequestBoardText{id, ticket, D.Profile{+key, +provider, +name, +policy, options}, prompt, retitle}:
      configured_board_profile(D.find_profile(profiles, key), D.Profile{key, provider, name, policy, options}) &&
        board_request(B.find(F.board(state), id), ticket, prompt, retitle)

# Catalog changes invalidate request measurements atomically with Environment.
# No new dispatch can reuse a meter result from a different callable layout.
def reconfigure(+state: F.State()) -> F.State():
  F.with_compaction(Compaction.recover(F.compaction(state)), state)

def retained_tasks(tasks: +List<D.Task>, before: F.State(), after: F.State()) -> +List<D.Task>:
  WorktreeState.retained_tasks(tasks, before, after)

def control_allowed(request: D.Control, id: Nat, world: M.World()) -> Bool:
  WorktreeState.control_allowed(request, id, world)

def pending_task(id: Nat, world: M.World()) -> Bool:
  WorktreeState.pending(id, world)

def archived_task(id: Nat, decision: M.Decision()) -> M.Decision():
  WorktreeState.archived_decision(id, decision)

def execution_allowed(id: Nat, world: M.World()) -> Bool:
  WorktreeState.execution_allowed(id, world)

def workspace_available(workspace: D.Workspace, world: M.World()) -> Bool:
  WorktreeState.workspace_available(workspace, world)

def archive_allowed(id: Nat, world: M.World()) -> Bool:
  WorktreeState.archive_allowed(id, world)
