import Base
import ../BOARD.bend as B
import ../MODEL.bend as M
import ./board-state.bend as S
import ./board-resolution.bend as R
import ./board-codec.bend as Codec
import ./json.bend as J
import ./tasks.bend as T

# Interpreter for accepted registry changes. The host receives only its effects.
def card_result(id: Nat, revision: Nat) -> J.Json:
  J.Object{[J.Field{"card_id", J.nat(id)}, J.Field{"revision", J.nat(revision)}]}

def agent_result(id: Nat, revision: Nat) -> J.Json:
  J.Object{[J.Field{"agent_id", J.nat(id)}, J.Field{"revision", J.nat(revision)}]}

def respond(world: M.World, result: J.Json) -> M.Decision:
  M.Decision{world, M.success(result), Nil{}}

def save(+id: Nat, +card: B.Card, next: U32, +world: M.World) -> M.Decision:
  respond(S.store(B.put(id, card, S.registry(world), next), world), card_result(id, B.revision(card)))

def interrupt_found(needed: Bool, found: Maybe<&2, M.Task>, decision: M.Decision) -> M.Decision:
  match needed found decision:
    case True{} Some{+task} M.Decision{M.World{tasks, next_task, next_ticket, environment, limits, projects, board}, reply, effects}:
      M.Decision{M.World{T.replace(tasks, T.interrupt(task)), next_task, next_ticket, environment, limits, projects, board}, reply,
        List.append(&2, M.Effect, effects, [M.CancelTask{M.task_id(task)}])}
    case _ _ decision: decision

def archive(+id: Nat, +card: B.Card, +archived: Bool, now: U32, +world: M.World) -> M.Decision:
  interrupt_found(archived && S.busy(S.task(card, world)), S.task(card, world),
    save(id, B.set_archive(archived, card, now), B.next_card(S.registry(world)), world))

def request_text(+id: Nat, +card: B.Card, profile: M.Profile, +retitle: Bool, next: U32, world: M.World) -> M.Decision:
  M.World{tasks, next_task, +ticket, environment, limits, projects, board} = world
  M.Decision{M.World{tasks, next_task, 1n+ticket, environment, limits, projects,
    B.put(id, B.with_enrichment(B.Enriching{ticket, B.revision(card), retitle}, card), board, next)},
    M.success(card_result(id, B.revision(card))),
    [M.RequestBoardText{id, ticket, profile, B.drafting_prompt(retitle, B.draft(card)), retitle}]}

def change(change: R.Change, +world: M.World) -> M.Decision:
  match change:
    case R.StoreCard{id, card, next}: save(id, card, next, world)
    case R.Relocate{+id, +card, position}: respond(S.store(B.reposition(id, card, position, S.registry(world)), world), card_result(id, B.revision(card)))
    case R.RemoveCard{+id}: respond(S.store(B.remove(id, S.registry(world)), world), J.Object{[J.Field{"card_id", J.nat(id)}]})
    case R.ArchiveCard{id, card, archived, now}: archive(id, card, archived, now, world)
    case R.Configure{+automatic, +profile}: respond(S.store(B.settings(automatic, profile, S.registry(world)), world),
      J.Object{[J.Field{"automatic", J.Boolean{automatic}}, J.Field{"draft_profile", J.Text{profile}}]})
    case R.StoreAgent{+id, +agent, next}: respond(S.store(B.put_agent(id, agent, S.registry(world), next), world), agent_result(id, B.agent_revision(agent)))
    case R.RemoveAgent{+id}: respond(S.store(B.remove_agent(id, S.registry(world)), world), J.Object{[J.Field{"agent_id", J.nat(id)}]})
    case R.RequestText{id, card, profile, retitle, next}: request_text(id, card, profile, retitle, next, world)

# Called only after the existing accepted Start operation. The same atomic
# native decision contains task birth and the new card association.
def started(+id: Nat, +task_id: Nat, +card: B.Card, now: U32, decision: M.Decision) -> M.Decision:
  M.Decision{+world, ignored, effects} = decision
  M.Decision{S.store(B.put(id, B.linked(task_id, card, now), S.registry(world), B.next_card(S.registry(world))), world),
    M.success(J.Object{[J.Field{"card_id", J.nat(id)}, J.Field{"task_id", J.nat(task_id)}, J.Field{"revision", J.nat(1n+B.revision(card))}]}), effects}

def suggestion_draft(retitle: Bool, title: String, description: String, draft: B.Draft) -> B.Draft:
  match retitle draft:
    case True{} B.Draft{old_title, old_description, stage, priority, owner, project, labels, attachments}:
      B.Draft{title, old_description, stage, priority, owner, project, labels, attachments}
    case False{} B.Draft{old_title, old_description, stage, priority, owner, project, labels, attachments}:
      B.Draft{title, description, stage, priority, owner, project, labels, attachments}

def failed(reason: String, card: B.Card) -> B.Card:
  B.Card{revision, draft, task, archived, created, updated, previous, start_error, pinned} = card
  B.Card{1n+revision, draft, task, archived, created, updated, B.EnrichmentFailed{String.take(reason, 1000n)}, start_error, pinned}

def suggested(valid: Bool, draft: B.Draft, card: B.Card) -> B.Card:
  match valid:
    case False{}: failed("The drafting endpoint returned an empty or oversized title/description. The original request is preserved.", card)
    case True{}:
      B.Card{revision, previous, task, archived, created, updated, enrichment, start_error, pinned} = card
      B.Card{1n+revision, draft, task, archived, created, updated, B.NoEnrichment{}, start_error, pinned}

def complete(outcome: B.Outcome, retitle: Bool, +card: B.Card) -> B.Card:
  match outcome:
    case B.SuggestionFailed{reason}: failed(reason, card)
    case B.Suggested{title, description}:
      +draft = suggestion_draft(retitle, String.trim(title), description, B.draft(card))
      suggested(B.valid_draft(draft), draft, card)

def completed(id: Nat, card: B.Card, outcome: B.Outcome, retitle: Bool, +world: M.World) -> M.Decision:
  M.Decision{S.store(B.put(id, complete(outcome, retitle, card), S.registry(world), B.next_card(S.registry(world))), world),
    M.success(J.Object{[J.Field{"accepted", J.Boolean{True{}}}]}), Nil{}}

def failed_start(+id: Nat, +card: B.Card, reason: String, +world: M.World) -> M.World:
  S.store(B.put(id, B.start_failed(String.take(reason, 1000n), card), S.registry(world), B.next_card(S.registry(world))), world)
