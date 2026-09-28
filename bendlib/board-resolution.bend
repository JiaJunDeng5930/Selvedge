import Base
import ../BOARD.bend as B
import ../MODEL.bend as M
import ../WORKSPACE.bend as Workspace
import ../PROJECTS.bend as Projects
import ../REASONING.bend as Reasoning
import ./board-state.bend as S
import ./board-codec.bend as Codec
import ./association-map.bend as Finite
import ./json.bend as J
import ./tasks.bend as T

# A resolution is either a refusal, a finite registry change, or a request to
# use the ordinary task-creation boundary. It grants no host-side scheduling.
type Change is Data:
  StoreCard{id: Nat, card: B.Card, next: U32}
  Relocate{id: Nat, card: B.Card, position: Nat}
  RemoveCard{id: Nat}
  ArchiveCard{id: Nat, card: B.Card, archived: Bool, now: U32}
  Configure{automatic: Bool, profile: String}
  StoreAgent{id: Nat, agent: B.AgentProfile, next: U32}
  RemoveAgent{id: Nat}
  RequestText{id: Nat, card: B.Card, profile: M.Profile, retitle: Bool, next: U32}

type Resolution is Data:
  Refuse{code: String, reason: String}
  Mutate{change: Change}
  Launch{id: Nat, card: B.Card, now: U32, agent: B.AgentProfile}

def require(valid: Bool, yes: Resolution, code: String, reason: String) -> Resolution:
  match valid:
    case True{}: yes
    case False{}: Refuse{code, reason}

def provided(~T: Data, value: Maybe<&2, T>) -> Bool:
  match value:
    case None{}: False{}
    case Some{value}: True{}

def changes_execution(patch: B.Patch) -> Bool:
  B.Patch{title, description, stage, priority, owner, project, labels, attachments} = patch
  provided(~String, title) || provided(~String, description) || provided(~B.Owner, owner) ||
    provided(~Maybe<&2, Nat>, project) || provided(~+List<B.Attachment>, attachments)

def update(id: Nat, +card: B.Card, +patch: B.Patch, now: U32, +world: M.World) -> Resolution:
  require(S.mutable(card, world) && (B.unlinked(B.task(card)) || Bool.not(changes_execution(patch))) &&
    S.draft_valid(B.patched(patch, B.draft(card)), world),
    Mutate{StoreCard{id, B.with_draft(B.patched(patch, B.draft(card)), card, now), B.next_card(S.registry(world))}},
    "card_locked", "The card is busy, archived or invalid. Execution inputs cannot be edited after a conversation is linked.")

def launch_agent(found: Maybe<&2, B.AgentProfile>, id: Nat, card: B.Card, now: U32) -> Resolution:
  match found:
    case None{}: Refuse{"agent_required", "Assign a configured endpoint or board agent before starting this card"}
    case Some{agent}: Launch{id, card, now, agent}

def move_target(found: Maybe<&2, B.Card>, stage: B.Stage, +pinned: Bool) -> Bool:
  match found:
    case None{}: False{}
    case Some{+card}:
      Bool.not(B.archived(card)) && String.eq(B.stage_name(stage), B.stage_name(B.card_stage(B.draft(card)))) &&
        ((pinned && B.pinned(card)) || (Bool.not(pinned) && Bool.not(B.pinned(card))))

def move_position(before: Maybe<&2, Nat>, +id: Nat, stage: B.Stage, pinned: Bool, world: M.World) -> Bool:
  match before:
    case None{}: True{}
    case Some{+target}: Bool.not(Nat.is_eq(id, target)) && move_target(B.find(S.registry(world), target), stage, pinned)

def move(+id: Nat, +card: B.Card, +stage: B.Stage, +before: Maybe<&2, Nat>, now: U32, +world: M.World) -> Resolution:
  require(S.mutable(card, world) && move_position(before, id, stage, B.pinned(card), world),
    Mutate{Relocate{id, B.with_draft(B.with_stage(stage, B.draft(card)), card, now),
      B.before_position(before, Finite.remove(~B.Card, B.cards(S.registry(world)), id))}},
    "invalid_card_move", "Refresh the board before moving: the card must be editable and the insertion target must remain in the destination column and pin group.")

def run(id: Nat, +card: B.Card, now: U32, +world: M.World) -> Resolution:
  require(S.runnable(card, world), launch_agent(S.agent(B.card_owner(B.draft(card)), world), id, card, now),
    "card_not_runnable", "The card already has a conversation, is locked, has no agent, or the assigned agent has reached its concurrency limit")

def link_found(found: Maybe<&2, M.Task>, id: Nat, +card: B.Card, +task_id: Nat, now: U32, +world: M.World) -> Resolution:
  match found:
    case None{}: Refuse{"task_not_found", "The conversation to link does not exist"}
    case Some{task}:
      require(S.mutable(card, world) && B.unlinked(B.task(card)) && Bool.not(S.task_used(B.cards(S.registry(world)), task_id)),
        Mutate{StoreCard{id, B.linked(task_id, card, now), B.next_card(S.registry(world))}},
        "conversation_already_linked", "A card can link one conversation, and a conversation can belong to only one card")

def archive(id: Nat, +card: B.Card, archived: Bool, now: U32) -> Resolution:
  require(Bool.not(B.pending(B.enrichment(card))), Mutate{ArchiveCard{id, card, archived, now}},
    "card_locked", "Wait for the pending title/description request before archiving or restoring the card")

def remove(id: Nat, +card: B.Card, world: M.World) -> Resolution:
  require(Bool.not(B.pending(B.enrichment(card))) && Bool.not(S.busy(S.task(card, world))), Mutate{RemoveCard{id}},
    "card_locked", "Stop the running conversation and wait for pending drafting before deleting this card")

def profile_name(provided: String, configured: String) -> String:
  match provided:
    case "": configured
    case other: other

def suggest_profile(found: Maybe<&2, M.Profile>, id: Nat, card: B.Card, retitle: Bool, next: U32) -> Resolution:
  match found:
    case None{}: Refuse{"draft_profile_required", "Select a configured ordinary endpoint for title/description assistance"}
    case Some{+profile}:
      require(S.drafting_profile(profile), Mutate{RequestText{id, card, profile, retitle, next}},
        "draft_profile_invalid", "Title/description assistance is an independent tool-free request. Choose an ordinary endpoint, not an adaptive task endpoint.")

def suggest(id: Nat, card: B.Card, provided: String, retitle: Bool, +world: M.World, next: U32) -> Resolution:
  suggest_profile(M.find_profile(S.profiles(world), profile_name(provided, B.draft_profile(S.registry(world)))), id, card, retitle, next)

def regenerate(id: Nat, +card: B.Card, profile: String, now: U32, +world: M.World) -> Resolution:
  require(S.mutable(card, world),
    suggest(id, B.with_draft(B.draft(card), card, now), profile, True{}, world, B.next_card(S.registry(world))),
    "card_locked", "A running, archived or already-generating card cannot start another title request")

def title_or_request(title: String, description: String) -> String:
  match title:
    case "": String.take(String.trim(description), 120n)
    case other: other

def assisted_draft(draft: B.Draft) -> B.Draft:
  B.Draft{title, +description, stage, priority, owner, project, labels, attachments} = draft
  B.Draft{title_or_request(String.trim(title), description), description, stage, priority, owner, project, labels, attachments}

def initial_draft(assist: Bool, draft: B.Draft) -> B.Draft:
  match assist:
    case True{}: assisted_draft(draft)
    case False{}: draft

def create_kind(assist: Bool, id: Nat, card: B.Card, profile: String, +world: M.World) -> Resolution:
  match assist:
    case False{}: Mutate{StoreCard{id, card, U32.add(B.next_card(S.registry(world)), 1)}}
    case True{}: suggest(id, card, profile, False{}, world, U32.add(B.next_card(S.registry(world)), 1))

def create_checked(+draft: B.Draft, +now: U32, assist: Bool, profile: String, +world: M.World) -> Resolution:
  require(S.draft_valid(draft, world) &&
    Nat.is_lt(List.length(&2, Finite.Entry(B.Card), B.cards(S.registry(world))), 512n) &&
    U32.is_lt(B.next_card(S.registry(world)), 4294967295),
    create_kind(assist, U32.to_nat(B.next_card(S.registry(world))),
      B.Card{0n, draft, None{}, False{}, now, now, B.NoEnrichment{}, "", False{}}, profile, world),
    "invalid_card", "Provide a nonempty title or assisted request, valid project/assignee and bounded text/files. The board holds at most 512 cards.")

def modify(command: B.Command, +card: B.Card, +world: M.World) -> Resolution:
  match command:
    case B.Update{id, revision, patch, now}: update(id, card, patch, now, world)
    case B.Move{id, revision, stage, before, now}: move(id, card, stage, before, now, world)
    case B.Archive{id, revision, archived, now}: archive(id, card, archived, now)
    case B.Delete{id, revision}: remove(id, card, world)
    case B.Run{id, revision, now}: run(id, card, now, world)
    case B.Link{id, revision, +task, now}: link_found(T.find(S.entries(world), task), id, card, task, now, world)
    case B.Regenerate{id, revision, profile, now}: regenerate(id, card, profile, now, world)
    case B.Pin{id, revision, pinned, now}:
      require(S.mutable(card, world), Mutate{StoreCard{id, B.with_pin(pinned, card, now), B.next_card(S.registry(world))}},
        "card_locked", "A running, archived or generating card cannot be pinned or unpinned")
    case _: Refuse{"invalid_card_command", "This command does not target an existing card"}

def current(valid: Bool, command: B.Command, card: B.Card, world: M.World) -> Resolution:
  match valid:
    case False{}: Refuse{"card_conflict", "The card changed in another view or during execution. Refresh its current values before applying this edit."}
    case True{}: modify(command, card, world)

def with_card(found: Maybe<&2, B.Card>, expected: Nat, command: B.Command, world: M.World) -> Resolution:
  match found:
    case None{}: Refuse{"card_not_found", "The board card does not exist"}
    case Some{+card}: current(Nat.is_eq(expected, B.revision(card)), command, card, world)

def agent_revised(revision: Nat, agent: B.AgentProfile) -> B.AgentProfile:
  B.AgentProfile{previous, name, profile, reasoning, instructions, settings, concurrency} = agent
  B.AgentProfile{revision, name, profile, reasoning, instructions, settings, concurrency}

def agent_selection(result: Result<&2, &2, String, Workspace.Selection>) -> Bool:
  match result:
    case Fail{reason}: False{}
    case Done{selection}: True{}

def agent_settings(found: Maybe<&2, M.Profile>, agent: B.AgentProfile, +world: M.World) -> Bool:
  match found:
    case None{}: False{}
    case Some{+profile}:
      B.AgentProfile{revision, name, key, +reasoning, instructions, settings, concurrency} = agent
      M.World{tasks, next_task, next_ticket, M.Environment{catalog, profiles, max_fork, max_descendants, +guidance, plugins}, limits, projects, board} = world
      Reasoning.permitted(M.profile_reasoning(profile), Reasoning.selection(reasoning, M.profile_reasoning(profile))) &&
        agent_selection(Workspace.resolve(settings, Workspace.defaults(guidance), guidance, profile, profiles))

def agent_valid(+agent: B.AgentProfile, +world: M.World) -> Bool:
  B.AgentProfile{revision, name, key, reasoning, instructions, settings, concurrency} = agent
  B.valid_agent(agent) && agent_settings(M.find_profile(S.profiles(world), key), agent, world)

def store_agent(id: Nat, agent: B.AgentProfile, next: U32) -> Resolution:
  Mutate{StoreAgent{id, agent, next}}

def update_agent(found: Maybe<&2, B.AgentProfile>, id: Nat, +expected: Nat, agent: B.AgentProfile, next: U32) -> Resolution:
  match found:
    case None{}: Refuse{"agent_not_found", "The board agent no longer exists"}
    case Some{previous}:
      require(Nat.is_eq(expected, B.agent_revision(previous)), store_agent(id, agent_revised(1n+expected, agent), next),
        "agent_conflict", "This board agent changed. Refresh its current settings before editing.")

def save_agent_id(id: Maybe<&2, Nat>, expected: Nat, agent: B.AgentProfile, +world: M.World) -> Resolution:
  match id:
    case None{}:
      require(U32.is_lt(B.next_agent(S.registry(world)), 4294967295) &&
        Nat.is_lt(List.length(&2, Finite.Entry(B.AgentProfile), B.agents(S.registry(world))), 64n),
        store_agent(U32.to_nat(B.next_agent(S.registry(world))), agent_revised(0n, agent), U32.add(B.next_agent(S.registry(world)), 1)),
        "agent_limit", "The board holds at most 64 reusable agents")
    case Some{+id}: update_agent(B.find_agent(S.registry(world), id), id, expected, agent, B.next_agent(S.registry(world)))

def delete_agent(found: Maybe<&2, B.AgentProfile>, +id: Nat, expected: Nat, world: M.World) -> Resolution:
  match found:
    case None{}: Refuse{"agent_not_found", "The board agent no longer exists"}
    case Some{agent}:
      require(Nat.is_eq(expected, B.agent_revision(agent)) && Bool.not(S.agent_used(B.cards(S.registry(world)), id)),
        Mutate{RemoveAgent{id}}, "agent_in_use", "Refresh the agent and unassign its remaining cards before deleting it")

def resolve(+command: B.Command, +world: M.World) -> Resolution:
  match command:
    case B.Create{draft, now, +assist, profile}: create_checked(initial_draft(assist, draft), now, assist, profile, world)
    case B.Settings{automatic, +profile}:
      require(S.draft_profile_valid(profile, world), Mutate{Configure{automatic, profile}},
        "draft_profile_invalid", "The board drafting profile must name a configured ordinary endpoint or be empty")
    case B.SaveAgent{id, revision, +agent}:
      require(agent_valid(agent, world), save_agent_id(id, revision, agent, world),
        "invalid_agent", "Check the agent's name, endpoint, reasoning effort, sandbox/approval settings and concurrency (1–64)")
    case B.DeleteAgent{+id, revision}: delete_agent(B.find_agent(S.registry(world), id), id, revision, world)
    case B.Update{+id, +revision, patch, now}: with_card(B.find(S.registry(world), id), revision, command, world)
    case B.Move{+id, +revision, stage, before, now}: with_card(B.find(S.registry(world), id), revision, command, world)
    case B.Archive{+id, +revision, archived, now}: with_card(B.find(S.registry(world), id), revision, command, world)
    case B.Delete{+id, +revision}: with_card(B.find(S.registry(world), id), revision, command, world)
    case B.Run{+id, +revision, now}: with_card(B.find(S.registry(world), id), revision, command, world)
    case B.Link{+id, +revision, task, now}: with_card(B.find(S.registry(world), id), revision, command, world)
    case B.Regenerate{+id, +revision, profile, now}: with_card(B.find(S.registry(world), id), revision, command, world)
    case B.Pin{+id, +revision, pinned, now}: with_card(B.find(S.registry(world), id), revision, command, world)
