import Base
import ../FEATURES.bend as F
import ./component.bend as C
import ./domain.bend as D
import ../BOARD.bend as B
import ../MODEL.bend as M
import ../PROJECTS.bend as Projects
import ../WORKSPACE.bend as Workspace
import ../REASONING.bend as Reasoning
import ./association-map.bend as Finite
import ./board-codec.bend as Codec
import ./json.bend as J
import ./schema.bend as Schema
import ./tasks.bend as T
import ./operations.bend as Ops

# Board/task relations are shared domain predicates. Neither the browser nor
# the effect interpreter maintains these associations or decides their locks.
def registry(world: M.World()) -> B.State:
  F.board(C.rest(D.State, F.State(), world))

def store(board: B.State, world: M.World()) -> M.World():
  C.map_rest(D.State, F.State(), state => F.with_board(board, state), world)

def entries(world: M.World()) -> +List<D.Task>:
  C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board} = world
  tasks

def profiles(world: M.World()) -> +List<D.Profile>:
  C.Frame{D.State{tasks, next_task, next_ticket, D.Environment{catalog, profiles, max_fork, max_descendants, project, plugins}, limits, projects}, +board} = world
  profiles

def task_id(world: M.World()) -> Nat:
  C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board} = world
  next_task

def ticket(world: M.World()) -> Nat:
  C.Frame{D.State{tasks, next_task, next_ticket, environment, limits, projects}, +board} = world
  next_ticket

def linked_task(id: Maybe<&2, Nat>, tasks: +List<D.Task>) -> Maybe<&2, D.Task>:
  match id:
    case None{}: None{}
    case Some{id}: T.find(tasks, id)

def task(+card: B.Card, world: M.World()) -> Maybe<&2, D.Task>:
  linked_task(B.task(card), entries(world))

def idle_phase(phase: D.Phase) -> Bool:
  match phase:
    case D.Idle{}: True{}
    case _: False{}

def busy_task(+task: D.Task) -> Bool:
  D.accepts_input(D.task_status(task)) &&
    (Bool.not(idle_phase(D.task_phase(task))) || D.operations_pending(D.task_operations(task)))

def busy(found: Maybe<&2, D.Task>) -> Bool:
  match found:
    case None{}: False{}
    case Some{task}: busy_task(task)

def mutable(+card: B.Card, +world: M.World()) -> Bool:
  Bool.not(B.archived(card)) && Bool.not(B.pending(B.enrichment(card))) && Bool.not(busy(task(card, world)))

def editing(+card: B.Card, world: M.World()) -> Bool:
  mutable(card, world) && B.unlinked(B.task(card))

def owns(expected: Nat, actual: Maybe<&2, Nat>) -> Bool:
  match actual:
    case None{}: False{}
    case Some{id}: Nat.is_eq(expected, id)

def task_used(cards: +List<Finite.Entry(B.Card)>, +id: Nat) -> Bool:
  match cards:
    case Nil{}: False{}
    case Con{(key, card), rest}: owns(id, B.task(card)) || task_used(rest, id)

def project_used(cards: +List<Finite.Entry(B.Card)>, +id: Nat) -> Bool:
  match cards:
    case Nil{}: False{}
    case Con{(key, card), rest}: owns(id, B.project(B.draft(card))) || project_used(rest, id)

def agent_owner(owner: B.Owner, id: Nat) -> Bool:
  match owner:
    case B.Agent{key}: Nat.is_eq(key, id)
    case _: False{}

def agent_used(cards: +List<Finite.Entry(B.Card)>, +id: Nat) -> Bool:
  match cards:
    case Nil{}: False{}
    case Con{(key, card), rest}: agent_owner(B.card_owner(B.draft(card)), id) || agent_used(rest, id)

def present(~T: Data, value: Maybe<&2, T>) -> Bool:
  match value:
    case None{}: False{}
    case Some{value}: True{}

def owner_valid(owner: B.Owner, state: B.State) -> Bool:
  match owner:
    case B.Profile{+key}: B.nonempty(key) && B.limited(key, 1024n)
    case B.Agent{id}: present(~B.AgentProfile, B.find_agent(state, id))
    case _: True{}

def draft_valid(+draft: B.Draft, +world: M.World()) -> Bool:
  B.valid_draft(draft) && owner_valid(B.card_owner(draft), registry(world)) &&
    Projects.reference_valid(B.project(draft), Projects.registry(F.State(), world))

def pending_valid(state: B.Enrichment, version: Nat, next_ticket: Nat) -> Bool:
  match state:
    case B.Enriching{ticket, revision, retitle}: Nat.is_lt(ticket, next_ticket) && Nat.is_eq(revision, version)
    case B.EnrichmentFailed{reason}: B.limited(reason, 4096n)
    case _: True{}

def ticket_is(state: B.Enrichment, ticket: Nat) -> Bool:
  match state:
    case B.Enriching{expected, revision, retitle}: Nat.is_eq(expected, ticket)
    case _: False{}

def has_ticket(cards: +List<Finite.Entry(B.Card)>, +ticket: Nat) -> Bool:
  match cards:
    case Nil{}: False{}
    case Con{(id, card), rest}: ticket_is(B.enrichment(card), ticket) || has_ticket(rest, ticket)

def exclusive_pending(state: B.Enrichment, archived: Bool, rest: +List<Finite.Entry(B.Card)>) -> Bool:
  match state:
    case B.Enriching{ticket, revision, retitle}: Bool.not(archived) && Bool.not(has_ticket(rest, ticket))
    case _: True{}

def link_valid(id: Maybe<&2, Nat>, tasks: +List<D.Task>, rest: +List<Finite.Entry(B.Card)>) -> Bool:
  match id:
    case None{}: True{}
    case Some{+id}: present(~D.Task, T.find(tasks, id)) && Bool.not(task_used(rest, id))

def valid_cards(cards: +List<Finite.Entry(B.Card)>, +next: Nat, +world: M.World()) -> Bool:
  match cards:
    case Nil{}: True{}
    case Con{(+id, +card), +rest}:
      Nat.is_lt(id, next) && Bool.not(present(~B.Card, Finite.find(~B.Card, rest, id))) &&
        draft_valid(B.draft(card), world) && B.limited(B.start_error(card), 4096n) && link_valid(B.task(card), entries(world), rest) &&
        pending_valid(B.enrichment(card), B.revision(card), ticket(world)) && exclusive_pending(B.enrichment(card), B.archived(card), rest) &&
        valid_cards(rest, next, world)

def valid_agents(agents: +List<Finite.Entry(B.AgentProfile)>, +next: Nat) -> Bool:
  match agents:
    case Nil{}: True{}
    case Con{(+id, agent), +rest}: Nat.is_lt(id, next) && B.valid_agent(agent) &&
      Bool.not(present(~B.AgentProfile, Finite.find(~B.AgentProfile, rest, id))) && valid_agents(rest, next)

def valid(+world: M.World()) -> Bool:
  +board = registry(world)
  Nat.is_le(List.length(&2, Finite.Entry(B.Card), B.cards(board)), 512n) &&
    Nat.is_le(List.length(&2, Finite.Entry(B.AgentProfile), B.agents(board)), 64n) &&
    valid_cards(B.cards(board), U32.to_nat(B.next_card(board)), world) &&
    valid_agents(B.agents(board), U32.to_nat(B.next_agent(board))) && B.limited(B.draft_profile(board), 1024n)

def retained_link(previous: Maybe<&2, Nat>, next: Maybe<&2, Nat>) -> Bool:
  match previous:
    case None{}: True{}
    case Some{id}: owns(id, next)

def retained_card(found: Maybe<&2, B.Card>, +previous: B.Card) -> Bool:
  match found:
    case None{}: True{}
    case Some{+next}: Nat.is_le(B.revision(previous), B.revision(next)) && retained_link(B.task(previous), B.task(next))

def retained_cards(previous: +List<Finite.Entry(B.Card)>, +next: B.State) -> Bool:
  match previous:
    case Nil{}: True{}
    case Con{(id, card), rest}: retained_card(B.find(next, id), card) && retained_cards(rest, next)

def evolution(+previous: B.State, +next: B.State) -> Bool:
  U32.is_le(B.next_card(previous), B.next_card(next)) && U32.is_le(B.next_agent(previous), B.next_agent(next)) &&
    retained_cards(B.cards(previous), next)

def pin_group(pinned: Bool, entry: Finite.Entry(B.Card)) -> Bool:
  match pinned:
    case True{}:
      (id, card) = entry
      B.pinned(card)
    case False{}:
      (id, card) = entry
      Bool.not(B.pinned(card))

def priority_group(rank: Nat, entry: Finite.Entry(B.Card)) -> Bool:
  (id, card) = entry
  Nat.is_eq(rank, B.priority_rank(B.card_priority(B.draft(card))))

def by_priority(+entries: +List<Finite.Entry(B.Card)>) -> +List<Finite.Entry(B.Card)>:
  List.append(&2, Finite.Entry(B.Card), List.filter(~Finite.Entry(B.Card), (entry => priority_group(4n, entry)), entries),
    List.append(&2, Finite.Entry(B.Card), List.filter(~Finite.Entry(B.Card), (entry => priority_group(3n, entry)), entries),
      List.append(&2, Finite.Entry(B.Card), List.filter(~Finite.Entry(B.Card), (entry => priority_group(2n, entry)), entries),
        List.append(&2, Finite.Entry(B.Card), List.filter(~Finite.Entry(B.Card), (entry => priority_group(1n, entry)), entries),
          List.filter(~Finite.Entry(B.Card), (entry => priority_group(0n, entry)), entries)))))

def display_cards(+state: B.State) -> +List<Finite.Entry(B.Card)>:
  List.append(&2, Finite.Entry(B.Card), List.filter(~Finite.Entry(B.Card), (entry => pin_group(True{}, entry)), B.cards(state)),
    List.filter(~Finite.Entry(B.Card), (entry => pin_group(False{}, entry)), B.cards(state)))

def queued_cards(+state: B.State) -> +List<Finite.Entry(B.Card)>:
  List.append(&2, Finite.Entry(B.Card),
    by_priority(List.filter(~Finite.Entry(B.Card), (entry => pin_group(True{}, entry)), B.cards(state))),
    by_priority(List.filter(~Finite.Entry(B.Card), (entry => pin_group(False{}, entry)), B.cards(state))))

def drafting_profile(profile: D.Profile) -> Bool:
  D.Profile{key, provider, name, policy} = profile
  Bool.not(String.eq(provider, "echo")) && Bool.not(Reasoning.automatic(policy))

def ordinary(found: Maybe<&2, D.Profile>) -> Bool:
  match found:
    case None{}: False{}
    case Some{profile}: drafting_profile(profile)

def draft_profile_valid(+name: String, world: M.World()) -> Bool:
  String.is_empty(name) || ordinary(D.find_profile(profiles(world), name))

def count(yes: Bool, rest: Nat) -> Nat:
  match yes:
    case True{}: 1n+rest
    case False{}: rest

def active_for(cards: +List<Finite.Entry(B.Card)>, +owner: B.Owner, +world: M.World()) -> Nat:
  match cards:
    case Nil{}: 0n
    case Con{(id, +card), rest}:
      count(B.same_owner(B.card_owner(B.draft(card)), owner) && busy(task(card, world)), active_for(rest, owner, world))

def agent(owner: B.Owner, world: M.World()) -> Maybe<&2, B.AgentProfile>:
  match owner:
    case B.Unassigned{}: None{}
    case B.Self{}: None{}
    case B.Profile{+key}: Some{B.AgentProfile{0n, key, key, "default", "", J.Object{Nil{}}, 1n}}
    case B.Agent{id}: B.find_agent(registry(world), id)

def available_capacity(found: Maybe<&2, B.AgentProfile>, active: Nat) -> Bool:
  match found:
    case None{}: False{}
    case Some{B.AgentProfile{revision, name, profile, reasoning, instructions, settings, capacity}}: Nat.is_lt(active, capacity)

def runnable(+card: B.Card, +world: M.World()) -> Bool:
  +owner = B.card_owner(B.draft(card))
  mutable(card, world) && B.unlinked(B.task(card)) && B.automatic_owner(owner) &&
    available_capacity(agent(owner, world), active_for(B.cards(registry(world)), owner, world))

def latest_failure(history: D.History) -> Bool:
  match history:
    case D.EmptyHistory{}: False{}
    case D.HistoryNode{previous, D.FailureMessage{text}}: True{}
    case D.HistoryNode{previous, D.UserMessage{text}}: False{}
    case D.HistoryNode{previous, D.AssistantMessage{text}}: False{}
    case D.HistoryNode{previous, D.ModelContext{value}}: False{}
    case D.HistoryNode{previous, other}: latest_failure(previous)

def awaiting(operations: +List<D.Operation()>) -> Bool:
  match operations:
    case Nil{}: False{}
    case Con{(id, D.OperationBody{call, announced, D.ApprovalPending{reviewer}}), rest}: True{}
    case Con{operation, rest}: awaiting(rest)

def activity_flags(approval: Bool, working: Bool, failed: Bool) -> String:
  match approval working failed:
    case True{} _ _: "awaiting_approval"
    case _ True{} _: "working"
    case _ _ True{}: "failed"
    case _ _ _: "completed"

def task_activity(+task: D.Task) -> String:
  match task:
    case D.Task{id, lineage, contract, D.Archived{}, history, queued, phase, operations, notified}: "archived"
    case D.Task{id, lineage, contract, D.Stopped{}, history, queued, D.Idle{}, Nil{}, notified}: "interrupted"
    case D.Task{id, lineage, contract, D.Frozen{}, history, queued, phase, operations, notified}: "paused"
    case D.Task{id, lineage, contract, status, history, queued, D.ReasoningPending{ticket, revision}, operations, notified}: "evaluating"
    case D.Task{id, lineage, contract, status, history, queued, D.SummaryPending{ticket, resume}, operations, notified}: "compacting"
    case _: activity_flags(awaiting(D.task_operations(task)), busy_task(task), latest_failure(D.task_history(task)))

def activity_task(found: Maybe<&2, D.Task>, queued: Bool) -> String:
  match found queued:
    case Some{task} _: task_activity(task)
    case None{} True{}: "queued"
    case None{} False{}: "not_started"

def activity_enrichment(state: B.Enrichment, +card: B.Card, +world: M.World()) -> String:
  match state:
    case B.Enriching{ticket, revision, retitle}: "generating"
    case B.EnrichmentFailed{reason}: "draft_failed"
    case _:
      activity_task(task(card, world), B.automatic(registry(world)) && B.ready(card))

def activity(+card: B.Card, world: M.World()) -> String:
  activity_enrichment(B.enrichment(card), card, world)

def activity_label(activity: String) -> String:
  match activity:
    case "generating": "生成中"
    case "draft_failed": "生成失败"
    case "queued": "排队中"
    case "working": "工作中"
    case "evaluating": "评估推理等级"
    case "compacting": "整理上下文"
    case "awaiting_approval": "等待授权"
    case "completed": "已完成"
    case "failed": "运行失败"
    case "interrupted": "已中断"
    case "paused": "已暂停"
    case "archived": "会话已归档"
    case _: "未开始"

def synchronized_stage(working: Bool, failed: Bool, previous: B.Stage) -> B.Stage:
  match working failed previous:
    case True{} _ _: B.InProgress{}
    case False{} True{} B.InProgress{}: B.Blocked{}
    case False{} False{} B.InProgress{}: B.InReview{}
    case _ _ previous: previous

def stage_changed(same: Bool, stage: B.Stage, +card: B.Card) -> B.Card:
  match same:
    case True{}: card
    case False{}: B.with_draft(B.with_stage(stage, B.draft(card)), card, B.updated(card))

def sync_task(found: Maybe<&2, D.Task>, +card: B.Card) -> B.Card:
  match found:
    case None{}: card
    case Some{+task}:
      +stage = synchronized_stage(busy_task(task), latest_failure(D.task_history(task)), B.card_stage(B.draft(card)))
      stage_changed(String.eq(B.stage_name(stage), B.stage_name(B.card_stage(B.draft(card)))), stage, card)

def sync_allowed(allowed: Bool, card: B.Card, found: Maybe<&2, D.Task>) -> B.Card:
  match allowed:
    case True{}: sync_task(found, card)
    case False{}: card

def synchronize_cards(cards: +List<Finite.Entry(B.Card)>, +world: M.World()) -> +List<Finite.Entry(B.Card)>:
  match cards:
    case Nil{}: Nil{}
    case Con{(id, +card), rest}:
      (id, sync_allowed(Bool.not(B.archived(card)) && Bool.not(B.pending(B.enrichment(card))), card, task(card, world))) <>
        synchronize_cards(rest, world)

def synchronize(+world: M.World()) -> M.World():
  store(B.with_cards(synchronize_cards(B.cards(registry(world)), world), registry(world)), world)

def recovered_pending(pending: Bool, card: B.Card) -> B.Card:
  match pending:
    case False{}: card
    case True{}:
      B.Card{revision, draft, task, archived, created, updated, enrichment, start_error, pinned} = card
      B.Card{1n+revision, draft, task, archived, created, updated,
        B.EnrichmentFailed{"The service restarted during drafting. Review the saved request and explicitly retry; no paid drafting request was replayed."}, start_error, pinned}

def recovered(cards: +List<Finite.Entry(B.Card)>) -> +List<Finite.Entry(B.Card)>:
  match cards:
    case Nil{}: Nil{}
    case Con{(id, +card), rest}: (id, recovered_pending(B.pending(B.enrichment(card)), card)) <> recovered(rest)

def recover(+state: B.State) -> B.State:
  B.with_cards(recovered(B.cards(state)), state)

def capabilities(+card: B.Card, +world: M.World()) -> J.Json:
  J.Object{[J.Field{"edit", J.Boolean{editing(card, world)}}, J.Field{"metadata", J.Boolean{mutable(card, world)}},
    J.Field{"drag", J.Boolean{mutable(card, world)}}, J.Field{"run", J.Boolean{runnable(card, world)}},
    J.Field{"archive", J.Boolean{Bool.not(B.archived(card)) && Bool.not(B.pending(B.enrichment(card)))}},
    J.Field{"restore", J.Boolean{B.archived(card)}}, J.Field{"delete", J.Boolean{Bool.not(B.pending(B.enrichment(card))) && Bool.not(busy(task(card, world)))}}]}

def card_json(+id: Nat, +card: B.Card, +world: M.World()) -> J.Json:
  J.Object{List.append(&2, J.Field, Codec.card_fields(id, card),
    [J.Field{"activity", J.Text{activity(card, world)}}, J.Field{"capabilities", capabilities(card, world)}])}

def cards_json(cards: +List<Finite.Entry(B.Card)>, +world: M.World()) -> +List<J.Json>:
  match cards:
    case Nil{}: Nil{}
    case Con{(id, card), rest}: card_json(id, card, world) <> cards_json(rest, world)

def agents_json(agents: +List<Finite.Entry(B.AgentProfile)>) -> +List<J.Json>:
  match agents:
    case Nil{}: Nil{}
    case Con{(id, agent), rest}: J.Object{J.Field{"agent_id", J.nat(id)} <> Codec.agent_fields(agent)} <> agents_json(rest)

def read(found: Maybe<&2, B.Card>, id: Nat, world: M.World()) -> J.Json:
  match found:
    case None{}: D.failure("card_not_found", "The board card does not exist")
    case Some{card}: D.success(card_json(id, card, world))

def query(query: B.Query, +world: M.World()) -> J.Json:
  match query:
    case B.ListCards{}: D.success(J.Object{[J.Field{"cards", J.Array{cards_json(B.cards(registry(world)), world)}},
      J.Field{"automatic", J.Boolean{B.automatic(registry(world))}}, J.Field{"draft_profile", J.Text{B.draft_profile(registry(world))}}]})
    case B.ReadCard{+id}: read(B.find(registry(world), id), id, world)
    case B.ListAgents{}: D.success(J.Array{agents_json(B.agents(registry(world)))})
