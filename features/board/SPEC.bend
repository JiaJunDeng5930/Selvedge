import Base
import ../../bendlib/effects.bend as Effects
import ../../harness/features/MODEL.bend as F
import ../../bendlib/component.bend as C
import ../../harness/DOMAIN.bend as D
import ./MODEL.bend as B
import ../../harness/MODEL.bend as M
import ./resolution.bend as R
import ./STATE.bend as S
import ../../bendlib/json.bend as J
import ../../harness/tasks/PROGRAM.bend as T
import ../../bendlib/association-map.bend as Finite

# Complete observable equations for an accepted board operation. This module
# imports neither the production interpreter nor PROGRAM. In particular,
# archiving may cancel only its associated conversation, and title-only results
# cannot replace a description or authorize an unrelated generation.
def archive_result(+id: Nat, +card: B.Card, archived: Bool, now: U32, world: M.World()) -> M.Decision():
  C.Frame{+core, +board} = world
  C.Decision{C.Frame{core, F.with_board(B.put(id, B.set_archive(archived, card, now), F.board(board), B.next_card(F.board(board))), board)},
    D.success(J.Object{[J.Field{"card_id", J.nat(id)}, J.Field{"revision", J.nat(1n+B.revision(card))}]}), Nil{}}

def cancel_archived(archived: Bool, working: Bool, found: Maybe<&2, D.Task>, decision: M.Decision()) -> M.Decision():
  match archived working found decision:
    case True{} True{} Some{+task} C.Decision{C.Frame{+core, +board}, reply, effects}:
      C.Decision{C.Frame{D.with_state_tasks(T.replace(D.state_tasks(core), T.interrupt(task)), core), board}, reply,
        List.append(&2, M.Effect(), effects, [Effects.CancelTask{D.task_id(task)}])}
    case _ _ _ decision: decision

def reposition(+id: Nat, card: B.Card, +position: Nat, board: B.State) -> B.State:
  B.State{cards, next_card, agents, next_agent, automatic, draft_profile} = board
  +remaining = Finite.remove(~B.Card, cards, id)
  B.State{List.append(&2, Finite.Entry(B.Card), List.take(&2, Finite.Entry(B.Card), remaining, position),
    (id, card) <> List.drop(&2, Finite.Entry(B.Card), remaining, position)), next_card, agents, next_agent, automatic, draft_profile}

def change(change: R.Change, +world: M.World()) -> M.Decision():
  match change world:
    case R.StoreCard{+id, +card, next} C.Frame{+core, +board}:
      C.Decision{C.Frame{core, F.with_board(B.put(id, card, F.board(board), next), board)},
        D.success(J.Object{[J.Field{"card_id", J.nat(id)}, J.Field{"revision", J.nat(B.revision(card))}]}), Nil{}}
    case R.RemoveCard{+id} C.Frame{+core, +board}:
      C.Decision{C.Frame{core, F.with_board(B.remove(id, F.board(board)), board)},
        D.success(J.Object{[J.Field{"card_id", J.nat(id)}]}), Nil{}}
    case R.Relocate{+id, +card, position} _:
      C.Decision{S.store(reposition(id, card, position, S.registry(world)), world),
        D.success(J.Object{[J.Field{"card_id", J.nat(id)}, J.Field{"revision", J.nat(B.revision(card))}]}), Nil{}}
    case R.ArchiveCard{+id, +card, +archived, now} _:
      cancel_archived(archived, S.busy(S.task(card, world)), S.task(card, world), archive_result(id, card, archived, now, world))
    case R.Configure{+automatic, +profile} C.Frame{+core, +board}:
      C.Decision{C.Frame{core, F.with_board(B.settings(automatic, profile, F.board(board)), board)},
        D.success(J.Object{[J.Field{"automatic", J.Boolean{automatic}}, J.Field{"draft_profile", J.Text{profile}}]}), Nil{}}
    case R.StoreAgent{+id, +agent, next} C.Frame{+core, +board}:
      C.Decision{C.Frame{core, F.with_board(B.put_agent(id, agent, F.board(board), next), board)},
        D.success(J.Object{[J.Field{"agent_id", J.nat(id)}, J.Field{"revision", J.nat(B.agent_revision(agent))}]}), Nil{}}
    case R.RemoveAgent{+id} C.Frame{+core, +board}:
      C.Decision{C.Frame{core, F.with_board(B.remove_agent(id, F.board(board)), board)},
        D.success(J.Object{[J.Field{"agent_id", J.nat(id)}]}), Nil{}}
    case R.RequestText{+id, +card, profile, +retitle, next} C.Frame{+core, +board}:
      C.Decision{C.Frame{D.with_state_next_ticket(1n+D.state_next_ticket(core), core), F.with_board(B.put(id, B.with_enrichment(B.Enriching{D.state_next_ticket(core), B.revision(card), retitle}, card), F.board(board), next), board)},
        D.success(J.Object{[J.Field{"card_id", J.nat(id)}, J.Field{"revision", J.nat(B.revision(card))}]}),
        [Effects.FeatureEffect{F.RequestBoardText{id, D.state_next_ticket(core), profile, B.drafting_prompt(retitle, B.draft(card)), retitle}}]}

def started(+id: Nat, +task_id: Nat, +card: B.Card, now: U32, decision: M.Decision()) -> M.Decision():
  C.Decision{C.Frame{+core, +board}, reply, effects} = decision
  C.Decision{C.Frame{core, F.with_board(B.put(id, B.linked(task_id, card, now), F.board(board), B.next_card(F.board(board))), board)},
    D.success(J.Object{[J.Field{"card_id", J.nat(id)}, J.Field{"task_id", J.nat(task_id)}, J.Field{"revision", J.nat(1n+B.revision(card))}]}), effects}

def failed(reason: String, card: B.Card) -> B.Card:
  B.Card{revision, draft, task, archived, created, updated, previous, start_error, pinned} = card
  B.Card{1n+revision, draft, task, archived, created, updated, B.EnrichmentFailed{String.take(reason, 1000n)}, start_error, pinned}

def accepted_draft(valid: Bool, title: String, description: String, card: B.Card) -> B.Card:
  match valid card:
    case False{} card: failed("The drafting endpoint returned an empty or oversized title/description. The original request is preserved.", card)
    case True{} B.Card{revision, B.Draft{old_title, old_description, stage, priority, owner, project, labels, attachments}, task, archived, created, updated, enrichment, start_error, pinned}:
      B.Card{1n+revision, B.Draft{title, description, stage, priority, owner, project, labels, attachments}, task, archived, created, updated, B.NoEnrichment{}, start_error, pinned}

def requested_draft(title: String, description: String, card: B.Card) -> B.Draft:
  B.Card{revision, B.Draft{old_title, old_description, stage, priority, owner, project, labels, attachments}, task, archived, created, updated, enrichment, start_error, pinned} = card
  B.Draft{title, description, stage, priority, owner, project, labels, attachments}

def selected_description(retitle: Bool, description: String, card: B.Card) -> String:
  match retitle:
    case True{}: B.description(B.draft(card))
    case False{}: description

def valid_suggestion(+title: String, +description: String, +card: B.Card) -> B.Card:
  accepted_draft(B.valid_draft(requested_draft(title, description, card)), title, description, card)

def complete(outcome: B.Outcome, retitle: Bool, +card: B.Card) -> B.Card:
  match outcome:
    case B.SuggestionFailed{reason}: failed(reason, card)
    case B.Suggested{title, description}: valid_suggestion(String.trim(title), selected_description(retitle, description, card), card)

def completed(id: Nat, card: B.Card, outcome: B.Outcome, retitle: Bool, world: M.World()) -> M.Decision():
  C.Frame{+core, +board} = world
  C.Decision{C.Frame{core, F.with_board(B.put(id, complete(outcome, retitle, card), F.board(board), B.next_card(F.board(board))), board)},
    D.success(J.Object{[J.Field{"accepted", J.Boolean{True{}}}]}), Nil{}}
