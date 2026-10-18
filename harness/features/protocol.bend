import Base
import ../../features/worktree/MODEL.bend as Worktree
import ../../bendlib/categories.bend as Categories
import ./MODEL.bend as F
import ../MODEL.bend as M
import ../../features/board/MODEL.bend as B
import ./operations.bend as O
import ./worktree-state.bend as WorktreeState
import ../../features/board/STATE.bend as State
import ../../features/chatgpt/MODEL.bend as ChatGPT
import ../../features/chatgpt/STATE.bend as ChatGPTState

def chatgpt(change: Maybe<&2, ChatGPT.Change>) -> Maybe<&2, O.ResolvedEvent>:
  match change:
    case None{}: None{}
    case Some{change}: Some{O.ChatGPTResult{change}}

def board_selected_callback(current: Bool, retitle: Bool) -> Maybe<&2, Bool>:
  match current:
    case True{}: Some{retitle}
    case False{}: None{}

def board_pending_callback(state: B.Enrichment, version: Nat, ticket: Nat) -> Maybe<&2, Bool>:
  match state:
    case B.Enriching{expected, revision, retitle}:
      board_selected_callback(Nat.is_eq(ticket, expected) && Nat.is_eq(version, revision), retitle)
    case _: None{}

def board_lease(state: B.Enrichment, archived: Bool, version: Nat, ticket: Nat) -> Maybe<&2, Bool>:
  match archived:
    case True{}: None{}
    case False{}: board_pending_callback(state, version, ticket)

def board_callback(current: Maybe<&2, Bool>, id: Nat, card: B.Card, outcome: B.Outcome) -> Maybe<&2, O.ResolvedEvent>:
  match current:
    case None{}: None{}
    case Some{retitle}: Some{O.BoardTextResult{id, card, outcome, retitle}}

def board_text(found: Maybe<&2, B.Card>, id: Nat, ticket: Nat, outcome: B.Outcome) -> Maybe<&2, O.ResolvedEvent>:
  match found:
    case None{}: None{}
    case Some{+card}: board_callback(board_lease(B.enrichment(card), B.archived(card), B.revision(card), ticket), id, card, outcome)

def resolve_calculation(completion: F.Completion, world: M.World()) -> Maybe<&2, O.ResolvedEvent>:
  match completion:
    case F.TitleCompleted{completion}: Some{O.TitleResult{completion}}
    case F.WorktreeCompleted{+completion}: WorktreeState.correlated(completion, world)
    case F.CompactionCompleted{completion}: Some{O.CompactionResult{completion}}
    case F.ChatGPTCompleted{+id, value, error}: chatgpt(ChatGPT.completion_value(ChatGPT.construct_completion(id, value, error, ChatGPTState.registry(world))))
    case F.BoardTextCompleted{+id, ticket, outcome}: board_text(B.find(State.registry(world), id), id, ticket, outcome)

type EventRequest is Data:
  EventRequest{completion: F.Completion, world: M.World()}

def event_resolution(request: EventRequest) -> Maybe<&2, O.ResolvedEvent>:
  EventRequest{completion, world} = request
  resolve_calculation(completion, world)

def ConstructedEvent() -> Type:
  Categories.Membership<Categories.Construction<EventRequest, Maybe<&2, O.ResolvedEvent>>,
    Categories.constructed_by(EventRequest, Maybe<&2, O.ResolvedEvent>, event_resolution)>

def construct_event(completion: F.Completion, world: M.World()) -> ConstructedEvent():
  Categories.construct(EventRequest, Maybe<&2, O.ResolvedEvent>, event_resolution, EventRequest{completion, world})


def event_value(member: ConstructedEvent()) -> Maybe<&2, O.ResolvedEvent>:
  Categories.Membership{Categories.Construction{request, result}, evidence} = member
  result

def resolve(completion: F.Completion, world: M.World()) -> Maybe<&2, O.ResolvedEvent>:
  event_value(construct_event(completion, world))
