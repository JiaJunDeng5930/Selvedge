import Base
import ../BOARD.bend as B
import ../MODEL.bend as M
import ./board-resolution.bend as R
import ./board-state.bend as S
import ./json.bend as J
import ./tasks.bend as T
import ./association-map.bend as Finite

# Complete observable equations for an accepted board operation. This module
# imports neither the production interpreter nor PROGRAM. In particular,
# archiving may cancel only its associated conversation, and title-only results
# cannot replace a description or authorize an unrelated generation.
def archive_result(+id: Nat, +card: B.Card, archived: Bool, now: U32, world: M.World) -> M.Decision:
  M.World{tasks, next_task, next_ticket, environment, limits, projects, +board} = world
  M.Decision{M.World{tasks, next_task, next_ticket, environment, limits, projects,
    B.put(id, B.set_archive(archived, card, now), board, B.next_card(board))},
    M.success(J.Object{[J.Field{"card_id", J.nat(id)}, J.Field{"revision", J.nat(1n+B.revision(card))}]}), Nil{}}

def cancel_archived(archived: Bool, working: Bool, found: Maybe<&2, M.Task>, decision: M.Decision) -> M.Decision:
  match archived working found decision:
    case True{} True{} Some{+task} M.Decision{M.World{tasks, next_task, next_ticket, environment, limits, projects, board}, reply, effects}:
      M.Decision{M.World{T.replace(tasks, T.interrupt(task)), next_task, next_ticket, environment, limits, projects, board}, reply,
        List.append(&2, M.Effect, effects, [M.CancelTask{M.task_id(task)}])}
    case _ _ _ decision: decision

def change(change: R.Change, +world: M.World) -> M.Decision:
  match change world:
    case R.StoreCard{+id, +card, next} M.World{tasks, next_task, next_ticket, environment, limits, projects, board}:
      M.Decision{M.World{tasks, next_task, next_ticket, environment, limits, projects, B.put(id, card, board, next)},
        M.success(J.Object{[J.Field{"card_id", J.nat(id)}, J.Field{"revision", J.nat(B.revision(card))}]}), Nil{}}
    case R.RemoveCard{+id} M.World{tasks, next_task, next_ticket, environment, limits, projects, board}:
      M.Decision{M.World{tasks, next_task, next_ticket, environment, limits, projects, B.remove(id, board)},
        M.success(J.Object{[J.Field{"card_id", J.nat(id)}]}), Nil{}}
    case R.Relocate{+id, +card, +position} M.World{tasks, next_task, next_ticket, environment, limits, projects,
      B.State{cards, next_card, agents, next_agent, automatic, draft_profile}}:
      +remaining = Finite.remove(~B.Card, cards, id)
      M.Decision{M.World{tasks, next_task, next_ticket, environment, limits, projects,
        B.State{List.append(&2, Finite.Entry(B.Card), List.take(&2, Finite.Entry(B.Card), remaining, position),
          (id, card) <> List.drop(&2, Finite.Entry(B.Card), remaining, position)), next_card, agents, next_agent, automatic, draft_profile}},
        M.success(J.Object{[J.Field{"card_id", J.nat(id)}, J.Field{"revision", J.nat(B.revision(card))}]}), Nil{}}
    case R.ArchiveCard{+id, +card, +archived, now} _:
      cancel_archived(archived, S.busy(S.task(card, world)), S.task(card, world), archive_result(id, card, archived, now, world))
    case R.Configure{+automatic, +profile} M.World{tasks, next_task, next_ticket, environment, limits, projects, board}:
      M.Decision{M.World{tasks, next_task, next_ticket, environment, limits, projects, B.settings(automatic, profile, board)},
        M.success(J.Object{[J.Field{"automatic", J.Boolean{automatic}}, J.Field{"draft_profile", J.Text{profile}}]}), Nil{}}
    case R.StoreAgent{+id, +agent, next} M.World{tasks, next_task, next_ticket, environment, limits, projects, board}:
      M.Decision{M.World{tasks, next_task, next_ticket, environment, limits, projects, B.put_agent(id, agent, board, next)},
        M.success(J.Object{[J.Field{"agent_id", J.nat(id)}, J.Field{"revision", J.nat(B.agent_revision(agent))}]}), Nil{}}
    case R.RemoveAgent{+id} M.World{tasks, next_task, next_ticket, environment, limits, projects, board}:
      M.Decision{M.World{tasks, next_task, next_ticket, environment, limits, projects, B.remove_agent(id, board)},
        M.success(J.Object{[J.Field{"agent_id", J.nat(id)}]}), Nil{}}
    case R.RequestText{+id, +card, profile, +retitle, next} M.World{tasks, next_task, +ticket, environment, limits, projects, board}:
      M.Decision{M.World{tasks, next_task, 1n+ticket, environment, limits, projects,
        B.put(id, B.with_enrichment(B.Enriching{ticket, B.revision(card), retitle}, card), board, next)},
        M.success(J.Object{[J.Field{"card_id", J.nat(id)}, J.Field{"revision", J.nat(B.revision(card))}]}),
        [M.RequestBoardText{id, ticket, profile, B.drafting_prompt(retitle, B.draft(card)), retitle}]}

def started(+id: Nat, +task_id: Nat, +card: B.Card, now: U32, decision: M.Decision) -> M.Decision:
  M.Decision{M.World{tasks, next_task, next_ticket, environment, limits, projects, +board}, reply, effects} = decision
  M.Decision{M.World{tasks, next_task, next_ticket, environment, limits, projects, B.put(id, B.linked(task_id, card, now), board, B.next_card(board))},
    M.success(J.Object{[J.Field{"card_id", J.nat(id)}, J.Field{"task_id", J.nat(task_id)}, J.Field{"revision", J.nat(1n+B.revision(card))}]}), effects}

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

def completed(id: Nat, card: B.Card, outcome: B.Outcome, retitle: Bool, world: M.World) -> M.Decision:
  M.World{tasks, next_task, next_ticket, environment, limits, projects, +board} = world
  M.Decision{M.World{tasks, next_task, next_ticket, environment, limits, projects,
    B.put(id, complete(outcome, retitle, card), board, B.next_card(board))},
    M.success(J.Object{[J.Field{"accepted", J.Boolean{True{}}}]}), Nil{}}
