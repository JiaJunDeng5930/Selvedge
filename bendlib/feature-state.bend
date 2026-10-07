import Base
import ../FEATURES.bend as F
import ../MODEL.bend as M
import ../BOARD.bend as B
import ../WORKSPACE.bend as Workspace
import ./domain.bend as D
import ./board-state.bend as Board
import ./association-map.bend as Finite
import ./equality.bend as Same
import ./json.bend as J
import ../CHATGPT.bend as ChatGPT
import ./chatgpt-state.bend as ChatGPTState
import ./chatgpt-view.bend as ChatGPTView
import ../PROJECTS.bend as Projects

# State and resource obligations are assembled here. Adding a component must
# provide its own validity, evolution, recovery and effect-authority clauses.
def valid(+world: M.World()) -> Bool:
  Board.valid(world) && ChatGPTState.valid(world)

def evolution(+previous: F.State(), +candidate: F.State()) -> Bool:
  Board.evolution(F.board(previous), F.board(candidate)) && Nat.is_le(ChatGPT.next(F.chatgpt(previous)), ChatGPT.next(F.chatgpt(candidate)))

def recover(+state: F.State()) -> F.State():
  F.with_chatgpt(ChatGPT.recover(F.chatgpt(state)), F.with_board(Board.recover(F.board(state)), state))

def project_used(+id: Nat, +world: M.World()) -> Bool:
  Board.project_used(B.cards(Board.registry(world)), id) || ChatGPT.project_used(ChatGPTState.registry(world), id)

def query(query: F.Query, +world: M.World()) -> J.Json:
  match query:
    case F.ChatGPTQuery{query}: ChatGPTView.query(query, ChatGPTState.registry(world), Projects.registry(F.State(), world))
    case F.BoardQuery{query}: Board.query(query, world)

def prepend_ticket(pending: B.Enrichment, rest: +List<Nat>) -> +List<Nat>:
  match pending:
    case B.Enriching{ticket, revision, retitle}: ticket <> rest
    case _: rest

def board_tickets(cards: +List<Finite.Entry(B.Card)>) -> +List<Nat>:
  match cards:
    case Nil{}: Nil{}
    case Con{(id, card), rest}: prepend_ticket(B.enrichment(card), board_tickets(rest))

def pending_tickets(state: F.State()) -> +List<Nat>:
  board_tickets(B.cards(F.board(state)))

def effect_ticket(effect: F.Effect) -> Maybe<&2, Nat>:
  match effect:
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
    case F.ChatGPTEffect{effect}: ChatGPT.effect_valid(effect, F.chatgpt(state))
    case F.RequestBoardText{id, ticket, D.Profile{+key, +provider, +name, +policy, options}, prompt, retitle}:
      configured_board_profile(D.find_profile(profiles, key), D.Profile{key, provider, name, policy, options}) &&
        board_request(B.find(F.board(state), id), ticket, prompt, retitle)
