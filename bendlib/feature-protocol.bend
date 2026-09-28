import Base
import ../FEATURES.bend as F
import ../MODEL.bend as M
import ../BOARD.bend as B
import ./feature-operations.bend as O
import ./board-state.bend as State

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

def board_callback(current: Maybe<&2, Bool>, id: Nat, card: B.Card, outcome: B.Outcome) -> Maybe<&2, O.Event>:
  match current:
    case None{}: None{}
    case Some{retitle}: Some{O.BoardTextResult{id, card, outcome, retitle}}

def board_text(found: Maybe<&2, B.Card>, id: Nat, ticket: Nat, outcome: B.Outcome) -> Maybe<&2, O.Event>:
  match found:
    case None{}: None{}
    case Some{+card}: board_callback(board_lease(B.enrichment(card), B.archived(card), B.revision(card), ticket), id, card, outcome)

def resolve(completion: F.Completion, world: M.World()) -> Maybe<&2, O.Event>:
  match completion:
    case F.BoardTextCompleted{+id, ticket, outcome}: board_text(B.find(State.registry(world), id), id, ticket, outcome)
