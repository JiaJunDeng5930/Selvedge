import Base
import ../../bendlib/categories.bend as Categories
import ../../harness/features/MODEL.bend as F
import ../../bendlib/component.bend as C
import ../../harness/DOMAIN.bend as D
import ./MODEL.bend as B
import ../../harness/MODEL.bend as M
import ../../harness/workspace/WORKSPACE.bend as Workspace
import ./STATE.bend as S
import ../../bendlib/association-map.bend as Finite
import ../../harness/tasks/PROGRAM.bend as T

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
  RequestText{id: Nat, card: B.Card, profile: D.Profile, retitle: Bool, next: U32}

type Resolution is Data:
  Refuse{code: String, reason: String}
  Mutate{change: Change}
  Launch{id: Nat, card: B.Card, now: U32, agent: B.AgentProfile}

type UpdateRequest is Data:
  UpdateRequest{id: Nat, card: B.Card, patch: B.Patch, now: U32, world: M.World()}

type MoveRequest is Data:
  MoveRequest{id: Nat, card: B.Card, stage: B.Stage, before: Maybe<&2, Nat>, now: U32, world: M.World()}

type LinkRequest is Data:
  LinkRequest{id: Nat, card: B.Card, task_id: Nat, now: U32, world: M.World()}

type RemoveRequest is Data:
  RemoveRequest{id: Nat, card: B.Card, world: M.World()}

type UpdateAgentRequest is Data:
  UpdateAgentRequest{previous: B.AgentProfile, id: Nat, expected: Nat, agent: B.AgentProfile, next: U32}

type NewAgentRequest is Data:
  NewAgentRequest{agent: B.AgentProfile, world: M.World()}

type DeleteAgentRequest is Data:
  DeleteAgentRequest{agent: B.AgentProfile, id: Nat, expected: Nat, world: M.World()}

def provided(~T: Data, value: Maybe<&2, T>) -> Bool:
  match value:
    case None{}: False{}
    case Some{value}: True{}

def changes_execution(patch: B.Patch) -> Bool:
  B.Patch{title, description, stage, priority, owner, project, labels, attachments} = patch
  provided(~String, title) || provided(~String, description) || provided(~B.Owner, owner) ||
    provided(~Maybe<&2, Nat>, project) || provided(~+List<B.Attachment>, attachments)

def update_eligible(request: UpdateRequest) -> Bool:
  UpdateRequest{+id, +card, +patch, +now, +world} = request
  S.mutable(card, world) && (B.unlinked(B.task(card)) || Bool.not(changes_execution(patch))) &&
    S.draft_valid(B.patched(patch, B.draft(card)), world)

def update_category() -> UpdateRequest -> Type:
  Categories.holds(UpdateRequest, update_eligible)

def update_accepted(member: Categories.Membership<UpdateRequest, update_category()>) -> Resolution:
  Categories.Membership{request, evidence} = member
  UpdateRequest{+id, +card, +patch, +now, +world} = request
  Mutate{StoreCard{id, B.with_draft(B.patched(patch, B.draft(card)), card, now), B.next_card(S.registry(world))}}

def update_admitted(found: Maybe<&1, Categories.Membership<UpdateRequest, update_category()>>) -> Resolution:
  match found:
    case Some{member}: update_accepted(member)
    case None{}: Refuse{"card_locked", "The card is busy, archived or invalid. Execution inputs cannot be edited after a conversation is linked."}

def update_admission(request: UpdateRequest) -> Resolution:
  update_admitted(Categories.admit(UpdateRequest, update_eligible, request))

def update(id: Nat, +card: B.Card, +patch: B.Patch, now: U32, +world: M.World()) -> Resolution:
  update_admission(UpdateRequest{id, card, patch, now, world})

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

def move_position(before: Maybe<&2, Nat>, +id: Nat, stage: B.Stage, pinned: Bool, world: M.World()) -> Bool:
  match before:
    case None{}: True{}
    case Some{+target}: Bool.not(Nat.is_eq(id, target)) && move_target(B.find(S.registry(world), target), stage, pinned)

def move_eligible(request: MoveRequest) -> Bool:
  MoveRequest{+id, +card, +stage, +before, +now, +world} = request
  S.mutable(card, world) && move_position(before, id, stage, B.pinned(card), world)

def move_category() -> MoveRequest -> Type:
  Categories.holds(MoveRequest, move_eligible)

def move_accepted(member: Categories.Membership<MoveRequest, move_category()>) -> Resolution:
  Categories.Membership{request, evidence} = member
  MoveRequest{+id, +card, +stage, +before, +now, +world} = request
  Mutate{Relocate{id, B.with_draft(B.with_stage(stage, B.draft(card)), card, now),
      B.before_position(before, Finite.remove(~B.Card, B.cards(S.registry(world)), id))}}

def move_admitted(found: Maybe<&1, Categories.Membership<MoveRequest, move_category()>>) -> Resolution:
  match found:
    case Some{member}: move_accepted(member)
    case None{}: Refuse{"invalid_card_move", "Refresh the board before moving: the card must be editable and the insertion target must remain in the destination column and pin group."}

def move_admission(request: MoveRequest) -> Resolution:
  move_admitted(Categories.admit(MoveRequest, move_eligible, request))

def move(+id: Nat, +card: B.Card, +stage: B.Stage, +before: Maybe<&2, Nat>, now: U32, +world: M.World()) -> Resolution:
  move_admission(MoveRequest{id, card, stage, before, now, world})

def run_eligible(world: M.World(), +card: B.Card) -> Bool:
  S.runnable(card, world)

def run_category(-world: M.World()) -> B.Card -> Type:
  Categories.holds(B.Card, (card => run_eligible(world, card)))

def run_accepted(+id: Nat, +now: U32, +world: M.World(), member: Categories.Membership<B.Card, run_category(world)>) -> Resolution:
  Categories.Membership{+card, evidence} = member
  launch_agent(S.agent(B.card_owner(B.draft(card)), world), id, card, now)

def run_admitted(+id: Nat, +now: U32, +world: M.World(), found: Maybe<&1, Categories.Membership<B.Card, run_category(world)>>) -> Resolution:
  match found:
    case Some{member}: run_accepted(id, now, world, member)
    case None{}: Refuse{"card_not_runnable", "The card already has a conversation, is locked, has no agent, or the assigned agent has reached its concurrency limit"}

def run_admission(+id: Nat, +now: U32, +world: M.World(), card: B.Card) -> Resolution:
  run_admitted(id, now, world, Categories.admit(B.Card, (card => run_eligible(world, card)), card))

def run(id: Nat, +card: B.Card, now: U32, +world: M.World()) -> Resolution:
  run_admission(id, now, world, card)

def link_eligible(request: LinkRequest) -> Bool:
  LinkRequest{+id, +card, +task_id, +now, +world} = request
  S.mutable(card, world) && B.unlinked(B.task(card)) && Bool.not(S.task_used(B.cards(S.registry(world)), task_id))

def link_category() -> LinkRequest -> Type:
  Categories.holds(LinkRequest, link_eligible)

def link_accepted(member: Categories.Membership<LinkRequest, link_category()>) -> Resolution:
  Categories.Membership{request, evidence} = member
  LinkRequest{+id, +card, +task_id, +now, +world} = request
  Mutate{StoreCard{id, B.linked(task_id, card, now), B.next_card(S.registry(world))}}

def link_admitted(found: Maybe<&1, Categories.Membership<LinkRequest, link_category()>>) -> Resolution:
  match found:
    case Some{member}: link_accepted(member)
    case None{}: Refuse{"conversation_already_linked", "A card can link one conversation, and a conversation can belong to only one card"}

def link_admission(request: LinkRequest) -> Resolution:
  link_admitted(Categories.admit(LinkRequest, link_eligible, request))

def link_found(found: Maybe<&2, D.Task>, id: Nat, +card: B.Card, +task_id: Nat, now: U32, +world: M.World()) -> Resolution:
  match found:
    case None{}: Refuse{"task_not_found", "The conversation to link does not exist"}
    case Some{task}:
      link_admission(LinkRequest{id, card, task_id, now, world})

def archive_eligible(+card: B.Card) -> Bool:
  Bool.not(B.pending(B.enrichment(card)))

def archive_category() -> B.Card -> Type:
  Categories.holds(B.Card, (card => archive_eligible(card)))

def archive_accepted(+id: Nat, +archived: Bool, +now: U32, member: Categories.Membership<B.Card, archive_category()>) -> Resolution:
  Categories.Membership{+card, evidence} = member
  Mutate{ArchiveCard{id, card, archived, now}}

def archive_admitted(+id: Nat, +archived: Bool, +now: U32, found: Maybe<&1, Categories.Membership<B.Card, archive_category()>>) -> Resolution:
  match found:
    case Some{member}: archive_accepted(id, archived, now, member)
    case None{}: Refuse{"card_locked", "Wait for the pending title/description request before archiving or restoring the card"}

def archive_admission(+id: Nat, +archived: Bool, +now: U32, card: B.Card) -> Resolution:
  archive_admitted(id, archived, now, Categories.admit(B.Card, (card => archive_eligible(card)), card))

def archive(id: Nat, +card: B.Card, archived: Bool, now: U32) -> Resolution:
  archive_admission(id, archived, now, card)

def remove_eligible(request: RemoveRequest) -> Bool:
  RemoveRequest{+id, +card, +world} = request
  Bool.not(B.pending(B.enrichment(card))) && Bool.not(S.busy(S.task(card, world)))

def remove_category() -> RemoveRequest -> Type:
  Categories.holds(RemoveRequest, remove_eligible)

def remove_accepted(member: Categories.Membership<RemoveRequest, remove_category()>) -> Resolution:
  Categories.Membership{request, evidence} = member
  RemoveRequest{+id, +card, +world} = request
  Mutate{RemoveCard{id}}

def remove_admitted(found: Maybe<&1, Categories.Membership<RemoveRequest, remove_category()>>) -> Resolution:
  match found:
    case Some{member}: remove_accepted(member)
    case None{}: Refuse{"card_locked", "Stop the running conversation and wait for pending drafting before deleting this card"}

def remove_admission(request: RemoveRequest) -> Resolution:
  remove_admitted(Categories.admit(RemoveRequest, remove_eligible, request))

def remove(id: Nat, +card: B.Card, world: M.World()) -> Resolution:
  remove_admission(RemoveRequest{id, card, world})

def profile_name(provided: String, configured: String) -> String:
  match provided:
    case "": configured
    case other: other

def suggest_profile_eligible(+profile: D.Profile) -> Bool:
  S.drafting_profile(profile)

def suggest_profile_category() -> D.Profile -> Type:
  Categories.holds(D.Profile, (profile => suggest_profile_eligible(profile)))

def suggest_profile_accepted(+id: Nat, +card: B.Card, +retitle: Bool, +next: U32, member: Categories.Membership<D.Profile, suggest_profile_category()>) -> Resolution:
  Categories.Membership{+profile, evidence} = member
  Mutate{RequestText{id, card, profile, retitle, next}}

def suggest_profile_admitted(+id: Nat, +card: B.Card, +retitle: Bool, +next: U32, found: Maybe<&1, Categories.Membership<D.Profile, suggest_profile_category()>>) -> Resolution:
  match found:
    case Some{member}: suggest_profile_accepted(id, card, retitle, next, member)
    case None{}: Refuse{"draft_profile_invalid", "Title/description assistance is an independent tool-free request. Choose an ordinary endpoint, not an adaptive task endpoint."}

def suggest_profile_admission(+id: Nat, +card: B.Card, +retitle: Bool, +next: U32, profile: D.Profile) -> Resolution:
  suggest_profile_admitted(id, card, retitle, next, Categories.admit(D.Profile, (profile => suggest_profile_eligible(profile)), profile))

def suggest_profile(found: Maybe<&2, D.Profile>, id: Nat, card: B.Card, retitle: Bool, next: U32) -> Resolution:
  match found:
    case None{}: Refuse{"draft_profile_required", "Select a configured ordinary endpoint for title/description assistance"}
    case Some{+profile}:
      suggest_profile_admission(id, card, retitle, next, profile)

def suggest(id: Nat, card: B.Card, provided: String, retitle: Bool, +world: M.World(), next: U32) -> Resolution:
  suggest_profile(D.find_profile(S.profiles(world), profile_name(provided, B.draft_profile(S.registry(world)))), id, card, retitle, next)

def regenerate_eligible(world: M.World(), +card: B.Card) -> Bool:
  S.mutable(card, world)

def regenerate_category(-world: M.World()) -> B.Card -> Type:
  Categories.holds(B.Card, (card => regenerate_eligible(world, card)))

def regenerate_accepted(+id: Nat, +profile: String, +now: U32, +world: M.World(), member: Categories.Membership<B.Card, regenerate_category(world)>) -> Resolution:
  Categories.Membership{+card, evidence} = member
  suggest(id, B.with_draft(B.draft(card), card, now), profile, True{}, world, B.next_card(S.registry(world)))

def regenerate_admitted(+id: Nat, +profile: String, +now: U32, +world: M.World(), found: Maybe<&1, Categories.Membership<B.Card, regenerate_category(world)>>) -> Resolution:
  match found:
    case Some{member}: regenerate_accepted(id, profile, now, world, member)
    case None{}: Refuse{"card_locked", "A running, archived or already-generating card cannot start another title request"}

def regenerate_admission(+id: Nat, +profile: String, +now: U32, +world: M.World(), card: B.Card) -> Resolution:
  regenerate_admitted(id, profile, now, world, Categories.admit(B.Card, (card => regenerate_eligible(world, card)), card))

def regenerate(id: Nat, +card: B.Card, profile: String, now: U32, +world: M.World()) -> Resolution:
  regenerate_admission(id, profile, now, world, card)

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

def create_kind(assist: Bool, id: Nat, card: B.Card, profile: String, +world: M.World()) -> Resolution:
  match assist:
    case False{}: Mutate{StoreCard{id, card, U32.add(B.next_card(S.registry(world)), 1)}}
    case True{}: suggest(id, card, profile, False{}, world, U32.add(B.next_card(S.registry(world)), 1))

def create_eligible(+world: M.World(), +draft: B.Draft) -> Bool:
  S.draft_valid(draft, world) &&
    Nat.is_lt(List.length(&2, Finite.Entry(B.Card), B.cards(S.registry(world))), 512n) &&
    U32.is_lt(B.next_card(S.registry(world)), 4294967295)

def create_category(-world: M.World()) -> B.Draft -> Type:
  Categories.holds(B.Draft, (draft => create_eligible(world, draft)))

def create_accepted(+now: U32, +assist: Bool, +profile: String, +world: M.World(), member: Categories.Membership<B.Draft, create_category(world)>) -> Resolution:
  Categories.Membership{+draft, evidence} = member
  create_kind(assist, U32.to_nat(B.next_card(S.registry(world))),
      B.Card{0n, draft, None{}, False{}, now, now, B.NoEnrichment{}, "", False{}}, profile, world)

def create_admitted(+now: U32, +assist: Bool, +profile: String, +world: M.World(), found: Maybe<&1, Categories.Membership<B.Draft, create_category(world)>>) -> Resolution:
  match found:
    case Some{member}: create_accepted(now, assist, profile, world, member)
    case None{}: Refuse{"invalid_card", "Provide a nonempty title or assisted request, valid project/assignee and bounded text/files. The board holds at most 512 cards."}

def create_admission(+now: U32, +assist: Bool, +profile: String, +world: M.World(), draft: B.Draft) -> Resolution:
  create_admitted(now, assist, profile, world, Categories.admit(B.Draft, (draft => create_eligible(world, draft)), draft))

def create_checked(+draft: B.Draft, +now: U32, assist: Bool, profile: String, +world: M.World()) -> Resolution:
  create_admission(now, assist, profile, world, draft)

def pin_eligible(world: M.World(), +card: B.Card) -> Bool:
  S.mutable(card, world)

def pin_category(-world: M.World()) -> B.Card -> Type:
  Categories.holds(B.Card, (card => pin_eligible(world, card)))

def pin_accepted(+id: Nat, +pinned: Bool, +now: U32, +world: M.World(), member: Categories.Membership<B.Card, pin_category(world)>) -> Resolution:
  Categories.Membership{+card, evidence} = member
  Mutate{StoreCard{id, B.with_pin(pinned, card, now), B.next_card(S.registry(world))}}

def pin_admitted(+id: Nat, +pinned: Bool, +now: U32, +world: M.World(), found: Maybe<&1, Categories.Membership<B.Card, pin_category(world)>>) -> Resolution:
  match found:
    case Some{member}: pin_accepted(id, pinned, now, world, member)
    case None{}: Refuse{"card_locked", "A running, archived or generating card cannot be pinned or unpinned"}

def pin_admission(+id: Nat, +pinned: Bool, +now: U32, +world: M.World(), card: B.Card) -> Resolution:
  pin_admitted(id, pinned, now, world, Categories.admit(B.Card, (card => pin_eligible(world, card)), card))

def modify(command: B.Command, +card: B.Card, +world: M.World()) -> Resolution:
  match command:
    case B.Update{id, revision, patch, now}: update(id, card, patch, now, world)
    case B.MoveCard{id, revision, stage, before, now}: move(id, card, stage, before, now, world)
    case B.Archive{id, revision, archived, now}: archive(id, card, archived, now)
    case B.Delete{id, revision}: remove(id, card, world)
    case B.Run{id, revision, now}: run(id, card, now, world)
    case B.Link{id, revision, +task, now}: link_found(T.find(D.state_tasks(C.local(D.State, F.State(), world)), task), id, card, task, now, world)
    case B.Regenerate{id, revision, profile, now}: regenerate(id, card, profile, now, world)
    case B.Pin{id, revision, pinned, now}:
      pin_admission(id, pinned, now, world, card)
    case _: Refuse{"invalid_card_command", "This command does not target an existing card"}

def current_eligible(expected: Nat, card: B.Card) -> Bool:
  Nat.is_eq(expected, B.revision(card))

def current_category(-expected: Nat) -> B.Card -> Type:
  Categories.holds(B.Card, current_eligible(expected))

def current_accepted(-expected: Nat, command: B.Command, member: Categories.Membership<B.Card, current_category(expected)>, world: M.World()) -> Resolution:
  Categories.Membership{card, evidence} = member
  modify(command, card, world)

def current_admitted(-expected: Nat, command: B.Command, found: Maybe<&1, Categories.Membership<B.Card, current_category(expected)>>, world: M.World()) -> Resolution:
  match found:
    case None{}: Refuse{"card_conflict", "The card changed in another view or during execution. Refresh its current values before applying this edit."}
    case Some{member}: current_accepted(expected, command, member, world)

def current(+expected: Nat, command: B.Command, card: B.Card, world: M.World()) -> Resolution:
  current_admitted(expected, command, Categories.admit(B.Card, current_eligible(expected), card), world)
def with_card(found: Maybe<&2, B.Card>, expected: Nat, command: B.Command, world: M.World()) -> Resolution:
  match found:
    case None{}: Refuse{"card_not_found", "The board card does not exist"}
    case Some{+card}: current(expected, command, card, world)

def agent_revised(revision: Nat, agent: B.AgentProfile) -> B.AgentProfile:
  B.AgentProfile{previous, name, profile, reasoning, instructions, settings, concurrency} = agent
  B.AgentProfile{revision, name, profile, reasoning, instructions, settings, concurrency}

def agent_selection(result: Result<&2, &2, String, Workspace.Selection>) -> Bool:
  match result:
    case Fail{reason}: False{}
    case Done{selection}: True{}

def agent_environment(+profile: D.Profile, +agent: B.AgentProfile, environment: D.Environment) -> Bool:
  D.Environment{catalog, profiles, max_fork, max_descendants, +guidance, plugins} = environment
  D.profile_permitted(profile, D.profile_selection(B.agent_reasoning(agent), profile)) &&
    agent_selection(Workspace.resolve(B.agent_settings(agent), Workspace.defaults(guidance), guidance, profile, profiles))

def agent_settings(found: Maybe<&2, D.Profile>, agent: B.AgentProfile, +world: M.World()) -> Bool:
  match found:
    case None{}: False{}
    case Some{+profile}: agent_environment(profile, agent, D.state_environment(C.local(D.State, F.State(), world)))

def agent_valid(+agent: B.AgentProfile, +world: M.World()) -> Bool:
  B.AgentProfile{revision, name, key, reasoning, instructions, settings, concurrency} = agent
  B.valid_agent(agent) && agent_settings(D.find_profile(S.profiles(world), key), agent, world)

def store_agent(id: Nat, agent: B.AgentProfile, next: U32) -> Resolution:
  Mutate{StoreAgent{id, agent, next}}

def update_agent_eligible(request: UpdateAgentRequest) -> Bool:
  UpdateAgentRequest{+previous, +id, +expected, +agent, +next} = request
  Nat.is_eq(expected, B.agent_revision(previous))

def update_agent_category() -> UpdateAgentRequest -> Type:
  Categories.holds(UpdateAgentRequest, update_agent_eligible)

def update_agent_accepted(member: Categories.Membership<UpdateAgentRequest, update_agent_category()>) -> Resolution:
  Categories.Membership{request, evidence} = member
  UpdateAgentRequest{+previous, +id, +expected, +agent, +next} = request
  store_agent(id, agent_revised(1n+expected, agent), next)

def update_agent_admitted(found: Maybe<&1, Categories.Membership<UpdateAgentRequest, update_agent_category()>>) -> Resolution:
  match found:
    case Some{member}: update_agent_accepted(member)
    case None{}: Refuse{"agent_conflict", "This board agent changed. Refresh its current settings before editing."}

def update_agent_admission(request: UpdateAgentRequest) -> Resolution:
  update_agent_admitted(Categories.admit(UpdateAgentRequest, update_agent_eligible, request))

def update_agent(found: Maybe<&2, B.AgentProfile>, id: Nat, +expected: Nat, agent: B.AgentProfile, next: U32) -> Resolution:
  match found:
    case None{}: Refuse{"agent_not_found", "The board agent no longer exists"}
    case Some{previous}:
      update_agent_admission(UpdateAgentRequest{previous, id, expected, agent, next})

def new_agent_eligible(request: NewAgentRequest) -> Bool:
  NewAgentRequest{+agent, +world} = request
  U32.is_lt(B.next_agent(S.registry(world)), 4294967295) &&
        Nat.is_lt(List.length(&2, Finite.Entry(B.AgentProfile), B.agents(S.registry(world))), 64n)

def new_agent_category() -> NewAgentRequest -> Type:
  Categories.holds(NewAgentRequest, new_agent_eligible)

def new_agent_accepted(member: Categories.Membership<NewAgentRequest, new_agent_category()>) -> Resolution:
  Categories.Membership{request, evidence} = member
  NewAgentRequest{+agent, +world} = request
  store_agent(U32.to_nat(B.next_agent(S.registry(world))), agent_revised(0n, agent), U32.add(B.next_agent(S.registry(world)), 1))

def new_agent_admitted(found: Maybe<&1, Categories.Membership<NewAgentRequest, new_agent_category()>>) -> Resolution:
  match found:
    case Some{member}: new_agent_accepted(member)
    case None{}: Refuse{"agent_limit", "The board holds at most 64 reusable agents"}

def new_agent_admission(request: NewAgentRequest) -> Resolution:
  new_agent_admitted(Categories.admit(NewAgentRequest, new_agent_eligible, request))

def save_agent_id(id: Maybe<&2, Nat>, expected: Nat, agent: B.AgentProfile, +world: M.World()) -> Resolution:
  match id:
    case None{}:
      new_agent_admission(NewAgentRequest{agent, world})
    case Some{+id}: update_agent(B.find_agent(S.registry(world), id), id, expected, agent, B.next_agent(S.registry(world)))

def delete_agent_eligible(request: DeleteAgentRequest) -> Bool:
  DeleteAgentRequest{+agent, +id, +expected, +world} = request
  Nat.is_eq(expected, B.agent_revision(agent)) && Bool.not(S.agent_used(B.cards(S.registry(world)), id))

def delete_agent_category() -> DeleteAgentRequest -> Type:
  Categories.holds(DeleteAgentRequest, delete_agent_eligible)

def delete_agent_accepted(member: Categories.Membership<DeleteAgentRequest, delete_agent_category()>) -> Resolution:
  Categories.Membership{request, evidence} = member
  DeleteAgentRequest{+agent, +id, +expected, +world} = request
  Mutate{RemoveAgent{id}}

def delete_agent_admitted(found: Maybe<&1, Categories.Membership<DeleteAgentRequest, delete_agent_category()>>) -> Resolution:
  match found:
    case Some{member}: delete_agent_accepted(member)
    case None{}: Refuse{"agent_in_use", "Refresh the agent and unassign its remaining cards before deleting it"}

def delete_agent_admission(request: DeleteAgentRequest) -> Resolution:
  delete_agent_admitted(Categories.admit(DeleteAgentRequest, delete_agent_eligible, request))

def delete_agent(found: Maybe<&2, B.AgentProfile>, +id: Nat, expected: Nat, world: M.World()) -> Resolution:
  match found:
    case None{}: Refuse{"agent_not_found", "The board agent no longer exists"}
    case Some{agent}:
      delete_agent_admission(DeleteAgentRequest{agent, id, expected, world})

def settings_eligible(world: M.World(), +profile: String) -> Bool:
  S.draft_profile_valid(profile, world)

def settings_category(-world: M.World()) -> String -> Type:
  Categories.holds(String, (profile => settings_eligible(world, profile)))

def settings_accepted(+automatic: Bool, +world: M.World(), member: Categories.Membership<String, settings_category(world)>) -> Resolution:
  Categories.Membership{+profile, evidence} = member
  Mutate{Configure{automatic, profile}}

def settings_admitted(+automatic: Bool, +world: M.World(), found: Maybe<&1, Categories.Membership<String, settings_category(world)>>) -> Resolution:
  match found:
    case Some{member}: settings_accepted(automatic, world, member)
    case None{}: Refuse{"draft_profile_invalid", "The board drafting profile must name a configured ordinary endpoint or be empty"}

def settings_admission(+automatic: Bool, +world: M.World(), profile: String) -> Resolution:
  settings_admitted(automatic, world, Categories.admit(String, (profile => settings_eligible(world, profile)), profile))

def save_agent_eligible(world: M.World(), +agent: B.AgentProfile) -> Bool:
  agent_valid(agent, world)

def save_agent_category(-world: M.World()) -> B.AgentProfile -> Type:
  Categories.holds(B.AgentProfile, (agent => save_agent_eligible(world, agent)))

def save_agent_accepted(+id: Maybe<&2, Nat>, +revision: Nat, +world: M.World(), member: Categories.Membership<B.AgentProfile, save_agent_category(world)>) -> Resolution:
  Categories.Membership{+agent, evidence} = member
  save_agent_id(id, revision, agent, world)

def save_agent_admitted(+id: Maybe<&2, Nat>, +revision: Nat, +world: M.World(), found: Maybe<&1, Categories.Membership<B.AgentProfile, save_agent_category(world)>>) -> Resolution:
  match found:
    case Some{member}: save_agent_accepted(id, revision, world, member)
    case None{}: Refuse{"invalid_agent", "Check the agent's name, endpoint, reasoning effort, sandbox/approval settings and concurrency (1–64)"}

def save_agent_admission(+id: Maybe<&2, Nat>, +revision: Nat, +world: M.World(), agent: B.AgentProfile) -> Resolution:
  save_agent_admitted(id, revision, world, Categories.admit(B.AgentProfile, (agent => save_agent_eligible(world, agent)), agent))

def resolve(+command: B.Command, +world: M.World()) -> Resolution:
  match command:
    case B.Create{draft, now, +assist, profile}: create_checked(initial_draft(assist, draft), now, assist, profile, world)
    case B.Settings{automatic, +profile}:
      settings_admission(automatic, world, profile)
    case B.SaveAgent{id, revision, +agent}:
      save_agent_admission(id, revision, world, agent)
    case B.DeleteAgent{+id, revision}: delete_agent(B.find_agent(S.registry(world), id), id, revision, world)
    case B.Update{+id, +revision, patch, now}: with_card(B.find(S.registry(world), id), revision, command, world)
    case B.MoveCard{+id, +revision, stage, before, now}: with_card(B.find(S.registry(world), id), revision, command, world)
    case B.Archive{+id, +revision, archived, now}: with_card(B.find(S.registry(world), id), revision, command, world)
    case B.Delete{+id, +revision}: with_card(B.find(S.registry(world), id), revision, command, world)
    case B.Run{+id, +revision, now}: with_card(B.find(S.registry(world), id), revision, command, world)
    case B.Link{+id, +revision, task, now}: with_card(B.find(S.registry(world), id), revision, command, world)
    case B.Regenerate{+id, +revision, profile, now}: with_card(B.find(S.registry(world), id), revision, command, world)
    case B.Pin{+id, +revision, pinned, now}: with_card(B.find(S.registry(world), id), revision, command, world)

# Capturing the source world keeps the calculated resolution attached to its request.
type CommandRequest is Data:
  CommandRequest{command: B.Command, world: M.World()}

def request_resolution(request: CommandRequest) -> Resolution:
  CommandRequest{command, world} = request
  resolve(command, world)

def ConstructedCommand() -> Type:
  Categories.Membership<Categories.Construction<CommandRequest, Resolution>,
    Categories.constructed_by(CommandRequest, Resolution, request_resolution)>

def construct_command(command: B.Command, world: M.World()) -> ConstructedCommand():
  Categories.construct(CommandRequest, Resolution, request_resolution, CommandRequest{command, world})

def change_resolution(member: ConstructedCommand()) -> Resolution:
  Categories.Membership{Categories.Construction{request, result}, evidence} = member
  result
