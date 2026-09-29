import Base
import ./feature-operations.bend as FeatureOps
import ./feature-protocol.bend as FeatureProtocol
import ../FEATURES.bend as Features
import ../BOARD.bend as B
import ../MODEL.bend as M
import ../UI.bend as UI
import ./board.bend as Actual
import ./board-spec.bend as Spec
import ./board-resolution.bend as R
import ./json.bend as J

# These equalities cover the entire decision, including cancellation, tickets,
# replies and ordered effects. Specifications never import the interpreter.
law change_meaning:
  for +change: R.Change
  for +world: M.World()
  {Actual.change(change, world) == Spec.change(change, world) : M.Decision()}

law birth_meaning:
  for +id: Nat
  for +task: Nat
  for +card: B.Card
  for +now: U32
  for +decision: M.Decision()
  {Actual.started(id, task, card, now, decision) == Spec.started(id, task, card, now, decision) : M.Decision()}

law text_meaning:
  for +outcome: B.Outcome
  for +retitle: Bool
  for +card: B.Card
  {Actual.complete(outcome, retitle, card) == Spec.complete(outcome, retitle, card) : B.Card}

law completion_meaning:
  for +id: Nat
  for +card: B.Card
  for +outcome: B.Outcome
  for +retitle: Bool
  for +world: M.World()
  {Actual.completed(id, card, outcome, retitle, world) == Spec.completed(id, card, outcome, retitle, world) : M.Decision()}

type BoardBoundary is Type:
  BoardBoundary{
    changes: @+change:R.Change -> @+world:M.World() ->
      {Actual.change(change, world) == Spec.change(change, world) : M.Decision()},
    birth: @+id:Nat -> @+task:Nat -> @+card:B.Card -> @+now:U32 -> @+decision:M.Decision() ->
      {Actual.started(id, task, card, now, decision) == Spec.started(id, task, card, now, decision) : M.Decision()},
    settlement: @+id:Nat -> @+card:B.Card -> @+outcome:B.Outcome -> @+retitle:Bool -> @+world:M.World() ->
      {Actual.completed(id, card, outcome, retitle, world) == Spec.completed(id, card, outcome, retitle, world) : M.Decision()},
    archived_callback: @pending:B.Enrichment -> @revision:Nat -> @ticket:Nat ->
      {FeatureProtocol.board_lease(pending, True{}, revision, ticket) == None{} : Maybe<&2, Bool>},
    unissued_callback: @revision:Nat -> @ticket:Nat ->
      {FeatureProtocol.board_lease(B.NoEnrichment{}, False{}, revision, ticket) == None{} : Maybe<&2, Bool>},
    callback_identity: @+expected:Nat -> @+revision:Nat -> @+retitle:Bool -> @+current:Nat -> @+ticket:Nat ->
      {FeatureProtocol.board_lease(B.Enriching{expected, revision, retitle}, False{}, current, ticket) ==
        FeatureProtocol.board_selected_callback(Nat.is_eq(ticket, expected) && Nat.is_eq(current, revision), retitle) : Maybe<&2, Bool>},
    callback_dispatch: @+id:Nat -> @+card:B.Card -> @+ticket:Nat -> @+outcome:B.Outcome ->
      {FeatureProtocol.board_text(Some{card}, id, ticket, outcome) ==
        FeatureProtocol.board_callback(FeatureProtocol.board_lease(B.enrichment(card), B.archived(card), B.revision(card), ticket), id, card, outcome) : Maybe<&2, FeatureOps.Event>},
    title_only: @title:String -> @description:String -> @+draft:B.Draft ->
      {B.description(Actual.suggestion_draft(True{}, title, description, draft)) == B.description(draft) : String}
  }

law board_boundary:
  BoardBoundary
