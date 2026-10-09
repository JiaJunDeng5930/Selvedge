import Base
import ../../harness/DOMAIN.bend as D
import ../../bendlib/json.bend as J
import ../../bendlib/association-map.bend as Finite

# A card is planned work, not a disguised running task. Its optional task link
# names the existing task registry; it does not copy that task's execution state.
type Stage is Data:
  Backlog{}
  Todo{}
  InProgress{}
  InReview{}
  Completed{}
  Blocked{}

type Priority is Data:
  NoPriority{}
  Low{}
  Medium{}
  High{}
  Urgent{}

type Owner is Data:
  Unassigned{}
  Self{}
  Profile{key: String}
  Agent{id: Nat}

type Attachment is Data:
  Attachment{id: String, name: String, mime: String, path: String, bytes: U32}

type Draft is Data:
  Draft{title: String, description: String, stage: Stage, priority: Priority,
    owner: Owner, project: Maybe<&2, Nat>, labels: +List<String>, attachments: +List<Attachment>}

type Enrichment is Data:
  NoEnrichment{}
  Enriching{ticket: Nat, revision: Nat, retitle: Bool}
  EnrichmentFailed{reason: String}

type Card is Data:
  Card{revision: Nat, draft: Draft, task: Maybe<&2, Nat>, archived: Bool,
    created: U32, updated: U32, enrichment: Enrichment, start_error: String, pinned: Bool}

type AgentProfile is Data:
  AgentProfile{revision: Nat, name: String, profile: String, reasoning: String,
    instructions: String, settings: J.Json, concurrency: Nat}

type State is Data:
  State{cards: +List<Finite.Entry(Card)>, next_card: U32,
    agents: +List<Finite.Entry(AgentProfile)>, next_agent: U32,
    automatic: Bool, draft_profile: String}

type Patch is Data:
  Patch{title: Maybe<&2, String>, description: Maybe<&2, String>, stage: Maybe<&2, Stage>,
    priority: Maybe<&2, Priority>, owner: Maybe<&2, Owner>, project: Maybe<&2, Maybe<&2, Nat>>,
    labels: Maybe<&2, +List<String>>, attachments: Maybe<&2, +List<Attachment>>}

type Command is Data:
  Create{draft: Draft, now: U32, assist: Bool, draft_profile: String}
  Update{id: Nat, revision: Nat, patch: Patch, now: U32}
  MoveCard{id: Nat, revision: Nat, stage: Stage, before: Maybe<&2, Nat>, now: U32}
  Archive{id: Nat, revision: Nat, archived: Bool, now: U32}
  Delete{id: Nat, revision: Nat}
  Run{id: Nat, revision: Nat, now: U32}
  Link{id: Nat, revision: Nat, task: Nat, now: U32}
  Regenerate{id: Nat, revision: Nat, profile: String, now: U32}
  Pin{id: Nat, revision: Nat, pinned: Bool, now: U32}
  Settings{automatic: Bool, draft_profile: String}
  SaveAgent{id: Maybe<&2, Nat>, revision: Nat, agent: AgentProfile}
  DeleteAgent{id: Nat, revision: Nat}

type Query is Data:
  ListCards{}
  ReadCard{id: Nat}
  ListAgents{}

type Outcome is Data:
  Suggested{title: String, description: String}
  SuggestionFailed{reason: String}

# Navigation is an opaque observation cursor, not a second card registry.

type Filter is Data:
  Filter{view: String, search: String, status: +List<String>, priority: +List<String>,
    date: +List<String>, assignee: +List<String>, creator: +List<String>,
    project: +List<String>, label: +List<String>}

# Model observations.

def cards(state: State) -> +List<Finite.Entry(Card)>:
  State{cards, next_card, agents, next_agent, automatic, draft_profile} = state
  cards

def agents(state: State) -> +List<Finite.Entry(AgentProfile)>:
  State{cards, next_card, agents, next_agent, automatic, draft_profile} = state
  agents

def automatic(state: State) -> Bool:
  State{cards, next_card, agents, next_agent, automatic, draft_profile} = state
  automatic

def draft_profile(state: State) -> String:
  State{cards, next_card, agents, next_agent, automatic, draft_profile} = state
  draft_profile

def next_card(state: State) -> U32:
  State{cards, next_card, agents, next_agent, automatic, draft_profile} = state
  next_card

def next_agent(state: State) -> U32:
  State{cards, next_card, agents, next_agent, automatic, draft_profile} = state
  next_agent

def find(state: State, id: Nat) -> Maybe<&2, Card>:
  Finite.find(~Card, cards(state), id)

def find_agent(state: State, id: Nat) -> Maybe<&2, AgentProfile>:
  Finite.find(~AgentProfile, agents(state), id)

def draft(card: Card) -> Draft:
  Card{revision, draft, task, archived, created, updated, enrichment, start_error, pinned} = card
  draft

def revision(card: Card) -> Nat:
  Card{revision, draft, task, archived, created, updated, enrichment, start_error, pinned} = card
  revision

def task(card: Card) -> Maybe<&2, Nat>:
  Card{revision, draft, task, archived, created, updated, enrichment, start_error, pinned} = card
  task

def archived(card: Card) -> Bool:
  Card{revision, draft, task, archived, created, updated, enrichment, start_error, pinned} = card
  archived

def created(card: Card) -> U32:
  Card{revision, draft, task, archived, created, updated, enrichment, start_error, pinned} = card
  created

def updated(card: Card) -> U32:
  Card{revision, draft, task, archived, created, updated, enrichment, start_error, pinned} = card
  updated

def enrichment(card: Card) -> Enrichment:
  Card{revision, draft, task, archived, created, updated, enrichment, start_error, pinned} = card
  enrichment

def start_error(card: Card) -> String:
  Card{revision, draft, task, archived, created, updated, enrichment, start_error, pinned} = card
  start_error

def pinned(card: Card) -> Bool:
  Card{revision, draft, task, archived, created, updated, enrichment, start_error, pinned} = card
  pinned

def agent_revision(agent: AgentProfile) -> Nat:
  AgentProfile{revision, name, profile, reasoning, instructions, settings, concurrency} = agent
  revision

def agent_name(agent: AgentProfile) -> String:
  AgentProfile{revision, name, profile, reasoning, instructions, settings, concurrency} = agent
  name

def agent_profile(agent: AgentProfile) -> String:
  AgentProfile{revision, name, profile, reasoning, instructions, settings, concurrency} = agent
  profile

def agent_reasoning(agent: AgentProfile) -> String:
  AgentProfile{revision, name, profile, reasoning, instructions, settings, concurrency} = agent
  reasoning

def agent_instructions(agent: AgentProfile) -> String:
  AgentProfile{revision, name, profile, reasoning, instructions, settings, concurrency} = agent
  instructions

def agent_settings(agent: AgentProfile) -> J.Json:
  AgentProfile{revision, name, profile, reasoning, instructions, settings, concurrency} = agent
  settings

def agent_concurrency(agent: AgentProfile) -> Nat:
  AgentProfile{revision, name, profile, reasoning, instructions, settings, concurrency} = agent
  concurrency

# Model birth and intended updates.

def initial() -> State:
  State{Nil{}, 0, Nil{}, 0, False{}, ""}

def with_pin(pinned: Bool, card: Card, now: U32) -> Card:
  Card{revision, draft, task, archived, created, updated, enrichment, start_error, previous} = card
  Card{1n+revision, draft, task, archived, created, now, enrichment, start_error, pinned}

def empty_filter() -> Filter:
  Filter{"all", "", Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}}

def stages() -> +List<Stage>:
  [Backlog{}, Todo{}, InProgress{}, InReview{}, Completed{}, Blocked{}]

def stage_name(stage: Stage) -> String:
  match stage:
    case Backlog{}: "backlog"
    case Todo{}: "todo"
    case InProgress{}: "in_progress"
    case InReview{}: "in_review"
    case Completed{}: "done"
    case Blocked{}: "blocked"

def stage_label(stage: Stage) -> String:
  match stage:
    case Backlog{}: "待规划"
    case Todo{}: "待办"
    case InProgress{}: "进行中"
    case InReview{}: "待审核"
    case Completed{}: "已完成"
    case Blocked{}: "已阻塞"

def stage(value: String) -> Stage:
  match value:
    case "backlog": Backlog{}
    case "in_progress": InProgress{}
    case "in_review": InReview{}
    case "done": Completed{}
    case "blocked": Blocked{}
    case _: Todo{}

def priorities() -> +List<Priority>:
  [NoPriority{}, Low{}, Medium{}, High{}, Urgent{}]

def priority_name(priority: Priority) -> String:
  match priority:
    case NoPriority{}: "none"
    case Low{}: "low"
    case Medium{}: "medium"
    case High{}: "high"
    case Urgent{}: "urgent"

def priority_label(priority: Priority) -> String:
  match priority:
    case NoPriority{}: "无"
    case Low{}: "低"
    case Medium{}: "中"
    case High{}: "高"
    case Urgent{}: "紧急"

def priority_rank(priority: Priority) -> Nat:
  match priority:
    case NoPriority{}: 0n
    case Low{}: 1n
    case Medium{}: 2n
    case High{}: 3n
    case Urgent{}: 4n

def priority(value: String) -> Priority:
  match value:
    case "low": Low{}
    case "medium": Medium{}
    case "high": High{}
    case "urgent": Urgent{}
    case _: NoPriority{}

def owner_name(owner: Owner) -> String:
  match owner:
    case Unassigned{}: "none"
    case Self{}: "self"
    case Profile{key}: "profile/" ++ key
    case Agent{id}: "agent/" ++ Nat.show(id)

def agent_owner(id: Maybe<&2, Nat>) -> Owner:
  match id:
    case None{}: Unassigned{}
    case Some{id}: Agent{id}

def named_owner(profile: Bool, +name: String) -> Owner:
  match profile:
    case True{}: Profile{String.drop(name, 8n)}
    case False{}: agent_owner(Nat.read(String.drop(name, 6n)))

def owner(+name: String) -> Owner:
  match name:
    case "none": Unassigned{}
    case "self": Self{}
    case _: named_owner(String.starts_with(name, "profile/"), name)

def assigned(owner: Owner) -> Bool:
  match owner:
    case Unassigned{}: False{}
    case _: True{}

def automatic_owner(owner: Owner) -> Bool:
  match owner:
    case Profile{key}: True{}
    case Agent{id}: True{}
    case _: False{}

def same_owner(left: Owner, right: Owner) -> Bool:
  String.eq(owner_name(left), owner_name(right))

def pending(enrichment: Enrichment) -> Bool:
  match enrichment:
    case Enriching{ticket, revision, retitle}: True{}
    case _: False{}

def title(draft: Draft) -> String:
  Draft{title, description, stage, priority, owner, project, labels, attachments} = draft
  title

def description(draft: Draft) -> String:
  Draft{title, description, stage, priority, owner, project, labels, attachments} = draft
  description

def card_stage(draft: Draft) -> Stage:
  Draft{title, description, stage, priority, owner, project, labels, attachments} = draft
  stage

def card_priority(draft: Draft) -> Priority:
  Draft{title, description, stage, priority, owner, project, labels, attachments} = draft
  priority

def card_owner(draft: Draft) -> Owner:
  Draft{title, description, stage, priority, owner, project, labels, attachments} = draft
  owner

def project(draft: Draft) -> Maybe<&2, Nat>:
  Draft{title, description, stage, priority, owner, project, labels, attachments} = draft
  project

def labels(draft: Draft) -> +List<String>:
  Draft{title, description, stage, priority, owner, project, labels, attachments} = draft
  labels

def attachments(draft: Draft) -> +List<Attachment>:
  Draft{title, description, stage, priority, owner, project, labels, attachments} = draft
  attachments

def position_step(found: Bool, rest: Nat) -> Nat:
  match found:
    case True{}: 0n
    case False{}: 1n+rest

def card_position(+id: Nat, entries: +List<Finite.Entry(Card)>) -> Nat:
  match entries:
    case Nil{}: 0n
    case Con{(key, card), rest}: position_step(Nat.is_eq(id, key), card_position(id, rest))

def before_position(before: Maybe<&2, Nat>, entries: +List<Finite.Entry(Card)>) -> Nat:
  match before:
    case None{}: List.length(&2, Finite.Entry(Card), entries)
    case Some{id}: card_position(id, entries)

# The association list also records manual order. Ordinary updates replace
# their existing slot; only an explicit move changes that slot.

def with_stage(stage: Stage, draft: Draft) -> Draft:
  Draft{title, description, old, priority, owner, project, labels, attachments} = draft
  Draft{title, description, stage, priority, owner, project, labels, attachments}

def put(+id: Nat, card: Card, state: State, next: U32) -> State:
  State{+cards, previous, agents, next_agent, automatic, draft_profile} = state
  +position = card_position(id, cards)
  State{List.append(&2, Finite.Entry(Card), List.take(&2, Finite.Entry(Card), cards, position),
    (id, card) <> List.drop(&2, Finite.Entry(Card), cards, 1n+position)), next, agents, next_agent, automatic, draft_profile}

def reposition(+id: Nat, card: Card, +position: Nat, state: State) -> State:
  State{cards, next_card, agents, next_agent, automatic, draft_profile} = state
  +remaining = Finite.remove(~Card, cards, id)
  State{List.append(&2, Finite.Entry(Card), List.take(&2, Finite.Entry(Card), remaining, position),
    (id, card) <> List.drop(&2, Finite.Entry(Card), remaining, position)), next_card, agents, next_agent, automatic, draft_profile}

def remove(id: Nat, state: State) -> State:
  State{cards, next_card, agents, next_agent, automatic, draft_profile} = state
  State{Finite.remove(~Card, cards, id), next_card, agents, next_agent, automatic, draft_profile}

def put_agent(+id: Nat, agent: AgentProfile, state: State, next: U32) -> State:
  State{cards, next_card, agents, previous, automatic, draft_profile} = state
  State{cards, next_card, (id, agent) <> Finite.remove(~AgentProfile, agents, id), next, automatic, draft_profile}

def remove_agent(id: Nat, state: State) -> State:
  State{cards, next_card, agents, next_agent, automatic, draft_profile} = state
  State{cards, next_card, Finite.remove(~AgentProfile, agents, id), next_agent, automatic, draft_profile}

def settings(automatic: Bool, draft_profile: String, state: State) -> State:
  State{cards, next_card, agents, next_agent, old, previous} = state
  State{cards, next_card, agents, next_agent, automatic, draft_profile}

def with_cards(cards: +List<Finite.Entry(Card)>, state: State) -> State:
  State{old, next_card, agents, next_agent, automatic, draft_profile} = state
  State{cards, next_card, agents, next_agent, automatic, draft_profile}

def with_draft(draft: Draft, card: Card, now: U32) -> Card:
  Card{revision, old, task, archived, created, previous, enrichment, start_error, pinned} = card
  Card{1n+revision, draft, task, archived, created, now, enrichment, start_error, pinned}

def linked(id: Nat, card: Card, now: U32) -> Card:
  Card{revision, draft, old, archived, created, previous, enrichment, start_error, pinned} = card
  Card{1n+revision, with_stage(InProgress{}, draft), Some{id}, archived, created, now, enrichment, "", pinned}

def set_archive(archived: Bool, card: Card, now: U32) -> Card:
  Card{revision, draft, task, old, created, previous, enrichment, start_error, pinned} = card
  Card{1n+revision, draft, task, archived, created, now, NoEnrichment{}, start_error, pinned}

def with_enrichment(enrichment: Enrichment, card: Card) -> Card:
  Card{revision, draft, task, archived, created, updated, old, start_error, pinned} = card
  Card{revision, draft, task, archived, created, updated, enrichment, start_error, pinned}

def start_failed(reason: String, card: Card) -> Card:
  Card{revision, draft, task, archived, created, updated, enrichment, old, pinned} = card
  Card{1n+revision, with_stage(Blocked{}, draft), task, archived, created, updated, enrichment, reason, pinned}

def retained(~T: Data, option: Maybe<&2, T>, previous: T) -> T:
  match option:
    case None{}: previous
    case Some{value}: value

def patched(patch: Patch, draft: Draft) -> Draft:
  Patch{title, description, stage, priority, owner, project, labels, attachments} = patch
  Draft{old_title, old_description, old_stage, old_priority, old_owner, old_project, old_labels, old_attachments} = draft
  Draft{retained(~String, title, old_title), retained(~String, description, old_description),
    retained(~Stage, stage, old_stage), retained(~Priority, priority, old_priority), retained(~Owner, owner, old_owner),
    retained(~Maybe<&2, Nat>, project, old_project), retained(~+List<String>, labels, old_labels),
    retained(~+List<Attachment>, attachments, old_attachments)}

def stage_patch(stage: Stage) -> Patch:
  Patch{None{}, None{}, Some{stage}, None{}, None{}, None{}, None{}, None{}}

def limited(+text: String, maximum: Nat) -> Bool:
  Nat.is_le(J.utf8_length(text), maximum) && Bool.not(String.contains(text, SCon{Chr{0}, SNil{}}))

def valid_labels(labels: +List<String>) -> Bool:
  match labels:
    case Nil{}: True{}
    case Con{+label, rest}: D.nonempty(label) && limited(label, 128n) && valid_labels(rest)

def valid_attachment(attachment: Attachment) -> Bool:
  Attachment{+id, +name, mime, +path, bytes} = attachment
  Nat.is_eq(String.length(id), 64n) && D.nonempty(name) && limited(name, 256n) && limited(mime, 128n) &&
    String.starts_with(path, "/") && limited(path, 4096n) && U32.is_le(bytes, 10485760)

def valid_attachments(files: +List<Attachment>) -> Bool:
  match files:
    case Nil{}: True{}
    case Con{file, rest}: valid_attachment(file) && valid_attachments(rest)

def valid_draft(draft: Draft) -> Bool:
  Draft{+title, description, stage, priority, owner, project, +labels, +attachments} = draft
  D.nonempty(title) && limited(title, 2000n) && limited(description, 400000n) &&
    Nat.is_le(List.length(&2, String, labels), 32n) && valid_labels(labels) &&
    Nat.is_le(List.length(&2, Attachment, attachments), 4n) && valid_attachments(attachments)

def valid_agent(agent: AgentProfile) -> Bool:
  AgentProfile{revision, +name, +profile, +reasoning, instructions, settings, +concurrency} = agent
  D.nonempty(name) && limited(name, 160n) && D.nonempty(profile) && limited(profile, 1024n) &&
    D.nonempty(reasoning) && limited(reasoning, 64n) && limited(instructions, 100000n) &&
    Nat.is_le(1n, concurrency) && Nat.is_le(concurrency, 64n)

def unlinked(task: Maybe<&2, Nat>) -> Bool:
  match task:
    case None{}: True{}
    case Some{id}: False{}

def drafting_complete(enrichment: Enrichment) -> Bool:
  match enrichment:
    case NoEnrichment{}: True{}
    case _: False{}

def awaiting_agent(stage: Stage) -> Bool:
  match stage:
    case Todo{}: True{}
    case InProgress{}: True{}
    case _: False{}

def ready(+card: Card) -> Bool:
  Bool.not(archived(card)) && unlinked(task(card)) && drafting_complete(enrichment(card)) &&
    awaiting_agent(card_stage(draft(card))) && automatic_owner(card_owner(draft(card)))

def attachment_prompt(files: +List<Attachment>) -> String:
  match files:
    case Nil{}: ""
    case Con{Attachment{id, name, mime, path, bytes}, rest}:
      "\n- " ++ name ++ ": " ++ path ++ attachment_prompt(rest)

def prompt(id: Nat, draft: Draft, instructions: String) -> String:
  Draft{title, description, stage, priority, owner, project, labels, attachments} = draft
  instructions ++ "\n\nBoard card SV-" ++ Nat.show(1n+id) ++ ": " ++ title ++ "\n\n" ++ description ++
    "\n\nAttached files (read only when needed):" ++ attachment_prompt(attachments)

def identifier(id: Nat) -> String:
  "SV-" ++ Nat.show(1n+id)

def drafting_instruction(retitle: Bool) -> String:
  match retitle:
    case True{}: "Return only a JSON object with a concise title (at most 120 characters) and description. Improve the title without claiming the work has been performed; the supplied description will be preserved unchanged."
    case False{}: "Return only a JSON object with a concise title (at most 120 characters) and a clear actionable description. Preserve the user's requirements, language and constraints. Do not perform the work, invent requirements, or claim completion."

def drafting_prompt(retitle: Bool, draft: Draft) -> String:
  Draft{title, description, stage, priority, owner, project, labels, attachments} = draft
  drafting_instruction(retitle) ++ "\n\nTitle/request preview:\n" ++ title ++ "\n\nOriginal user request:\n" ++ description
