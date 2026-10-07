import Base
import ./domain.bend as D
import ../BOARD.bend as B
import ./json.bend as J
import ./schema.bend as Schema

# The command descriptors, public wire and form vocabulary have one owner.
type WriteKind is Data:
  CreateKind{}
  UpdateKind{}
  MoveKind{}
  ArchiveKind{}
  RestoreKind{}
  DeleteKind{}
  RunKind{}
  LinkKind{}
  RegenerateKind{}
  PinKind{}
  SettingsKind{}
  SaveAgentKind{}
  DeleteAgentKind{}

type ReadKind is Data:
  CardsKind{}
  CardKind{}
  AgentsKind{}

type EntryKind is Data:
  Write{kind: WriteKind}
  Read{kind: ReadKind}

type Spec is Data:
  Spec{name: String, description: String, kind: EntryKind, schema: J.Json}

def text_schema() -> J.Json:
  J.Object{[J.Field{"type", J.Text{"string"}}]}

def integer_schema() -> J.Json:
  J.Object{[J.Field{"type", J.Text{"integer"}}, J.Field{"minimum", J.Number{"0"}}, J.Field{"maximum", J.Number{"4294967295"}}]}

def boolean_schema() -> J.Json:
  J.Object{[J.Field{"type", J.Text{"boolean"}}]}

def array_schema(items: J.Json) -> J.Json:
  J.Object{[J.Field{"type", J.Text{"array"}}, J.Field{"items", items}]}

def file_schema() -> J.Json:
  Schema.object([J.Field{"id", text_schema()}, J.Field{"name", text_schema()}, J.Field{"mime", text_schema()},
    J.Field{"path", text_schema()}, J.Field{"bytes", text_schema()}], [J.Text{"id"}])

def metadata_properties() -> +List<J.Field>:
  [J.Field{"title", text_schema()}, J.Field{"description", text_schema()}, J.Field{"status", text_schema()},
   J.Field{"priority", text_schema()}, J.Field{"assignee", text_schema()}, J.Field{"project", text_schema()},
   J.Field{"labels", array_schema(text_schema())}, J.Field{"attachments", array_schema(file_schema())}]

def stamped(properties: +List<J.Field>) -> +List<J.Field>:
  J.Field{"observed_at", text_schema()} <> properties

def command_schema(properties: +List<J.Field>, required: +List<J.Json>) -> J.Json:
  Schema.object(J.Field{"op", text_schema()} <> properties, J.Text{"op"} <> required)

def identity_properties() -> +List<J.Field>:
  [J.Field{"card_id", integer_schema()}, J.Field{"revision", integer_schema()}]

def identity_schema(extra: +List<J.Field>) -> J.Json:
  command_schema(stamped(List.append(&2, J.Field, identity_properties(), extra)), [J.Text{"card_id"}, J.Text{"revision"}])

def specs(task_settings: J.Json) -> +List<Spec>:
  [Spec{"create_card", "Capture planned work without starting a task; assisted creation requests a separate bounded title/description suggestion.", Write{CreateKind{}},
     command_schema(stamped(List.append(&2, J.Field, metadata_properties(), [J.Field{"assisted", boolean_schema()}, J.Field{"draft_profile", text_schema()}])), Nil{})},
   Spec{"update_card", "Update only named card fields, guarded by the observed card revision. Execution inputs remain frozen after linking a task.", Write{UpdateKind{}}, identity_schema(metadata_properties())},
   Spec{"move_card", "Move a revision-bound card before another card, or to the end when before_card is empty. Preserve the relative order of other cards.", Write{MoveKind{}},
     identity_schema([J.Field{"status", text_schema()}, J.Field{"before_card", text_schema()}])},
   Spec{"archive_card", "Archive a card and interrupt its active execution. Its stage and linked task history are retained.", Write{ArchiveKind{}}, identity_schema(Nil{})},
   Spec{"restore_card", "Restore an archived card to its retained stage without replaying its execution.", Write{RestoreKind{}}, identity_schema(Nil{})},
   Spec{"delete_card", "Delete an idle card, not its linked task or conversation.", Write{DeleteKind{}}, identity_schema(Nil{})},
   Spec{"run_card", "Start the assigned agent exactly once, freezing the current project and agent execution settings.", Write{RunKind{}}, identity_schema(Nil{})},
   Spec{"link_card", "Attach an existing unlinked conversation to a card without creating or replaying a task.", Write{LinkKind{}}, identity_schema([J.Field{"task_id", integer_schema()}])},
   Spec{"regenerate_card_title", "Request a revision-correlated title suggestion; retain the description, assignments and task link.", Write{RegenerateKind{}}, identity_schema([J.Field{"draft_profile", text_schema()}])},
   Spec{"pin_card", "Pin or unpin an idle card. Pinned cards precede other cards in both the board and automatic dispatch queue.", Write{PinKind{}}, identity_schema([J.Field{"pinned", boolean_schema()}])},
   Spec{"board_settings", "Configure automatic dispatch and the independent ordinary profile used for drafting.", Write{SettingsKind{}},
     command_schema([J.Field{"automatic", boolean_schema()}, J.Field{"draft_profile", text_schema()}], [J.Text{"automatic"}, J.Text{"draft_profile"}])},
   Spec{"save_board_agent", "Create or edit a reusable board role; blank agent means create. Existing task contracts are never rewritten.", Write{SaveAgentKind{}},
     command_schema([J.Field{"agent", text_schema()}, J.Field{"revision", integer_schema()}, J.Field{"name", text_schema()},
       J.Field{"profile", text_schema()}, J.Field{"reasoning", text_schema()}, J.Field{"instructions", text_schema()},
       J.Field{"settings", task_settings}, J.Field{"concurrency", integer_schema()}],
       [J.Text{"agent"}, J.Text{"revision"}, J.Text{"name"}, J.Text{"profile"}, J.Text{"reasoning"}, J.Text{"instructions"}, J.Text{"concurrency"}])},
   Spec{"delete_board_agent", "Delete an unused board role without deleting its endpoint configuration.", Write{DeleteAgentKind{}},
     command_schema([J.Field{"agent_id", integer_schema()}, J.Field{"revision", integer_schema()}], [J.Text{"agent_id"}, J.Text{"revision"}])},
   Spec{"list_cards", "Observe the card registry, automatic-dispatch setting and independent drafting profile.", Read{CardsKind{}}, command_schema(Nil{}, Nil{})},
   Spec{"read_card", "Observe one card and its current execution capabilities.", Read{CardKind{}}, command_schema([J.Field{"card_id", integer_schema()}], [J.Text{"card_id"}])},
   Spec{"list_board_agents", "Observe reusable board roles and their current configured endpoints.", Read{AgentsKind{}}, command_schema(Nil{}, Nil{})}]

def present(+value: J.Json, name: String) -> Bool:
  match value:
    case J.Object{fields}: Schema.exists(fields, name)
    case _: False{}

def number(value: J.Json) -> Nat:
  J.natural_or(J.natural(value), 0n)

def word(value: J.Json) -> U32:
  B.retained(~U32, U32.read(J.text(value)), 0)

def word_json(value: U32) -> J.Json:
  J.Text{U32.show(value)}

def strings(values: +List<J.Json>) -> +List<String>:
  match values:
    case Nil{}: Nil{}
    case Con{J.Text{text}, rest}: text <> strings(rest)
    case Con{other, rest}: strings(rest)

def optional_id(text: String) -> Maybe<&2, Nat>:
  Nat.read(text)

def id_text(id: Maybe<&2, Nat>) -> String:
  match id:
    case None{}: ""
    case Some{id}: Nat.show(id)

def valid_id(+text: String) -> Bool:
  String.is_empty(text) || Schema.valid(integer_schema(), J.Number{text})

def valid_owner(+name: String) -> Bool:
  String.eq(name, "none") || String.eq(name, "self") ||
    (String.starts_with(name, "profile/") && D.nonempty(String.drop(name, 8n)) && B.limited(name, 1024n)) ||
    (String.starts_with(name, "agent/") && D.nonempty(String.drop(name, 6n)) && valid_id(String.drop(name, 6n)))

def optional_enum(value: J.Json, options: +List<String>) -> Bool:
  match value:
    case J.Null{}: True{}
    case J.Text{text}: Schema.contains(options, text)
    case _: False{}

def optional_identity(value: J.Json) -> Bool:
  match value:
    case J.Null{}: True{}
    case J.Text{text}: valid_id(text)
    case _: False{}

def optional_owner(value: J.Json) -> Bool:
  match value:
    case J.Null{}: True{}
    case J.Text{text}: valid_owner(text)
    case _: False{}

def valid_clock(value: J.Json) -> Bool:
  match value:
    case J.Null{}: True{}
    case J.Text{+text}: String.eq(U32.show(word(J.Text{text})), text)
    case _: False{}

def metadata_valid(+body: J.Json) -> Bool:
  optional_enum(J.get(body, "status"), ["backlog", "todo", "in_progress", "in_review", "done", "blocked"]) &&
    optional_enum(J.get(body, "priority"), ["none", "low", "medium", "high", "urgent"]) &&
    optional_owner(J.get(body, "assignee")) && optional_identity(J.get(body, "project")) && valid_clock(J.get(body, "observed_at"))

def valid(kind: EntryKind, +body: J.Json) -> Bool:
  match kind:
    case Write{CreateKind{}}: metadata_valid(body)
    case Write{UpdateKind{}}: metadata_valid(body)
    case Write{MoveKind{}}: present(body, "status") && metadata_valid(body) && optional_identity(J.get(body, "before_card"))
    case Write{SaveAgentKind{}}: optional_identity(J.get(body, "agent"))
    case Write{LinkKind{}}: present(body, "task_id") && valid_clock(J.get(body, "observed_at"))
    case Write{PinKind{}}: present(body, "pinned") && valid_clock(J.get(body, "observed_at"))
    case _: valid_clock(J.get(body, "observed_at"))

def file(+value: J.Json) -> B.Attachment:
  B.Attachment{J.text(J.get(value, "id")), J.text(J.get(value, "name")), J.text(J.get(value, "mime")),
    J.text(J.get(value, "path")), word(J.get(value, "bytes"))}

def files(values: +List<J.Json>) -> +List<B.Attachment>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: file(value) <> files(rest)

def file_json(file: B.Attachment) -> J.Json:
  B.Attachment{id, name, mime, path, bytes} = file
  J.Object{[J.Field{"id", J.Text{id}}, J.Field{"name", J.Text{name}}, J.Field{"mime", J.Text{mime}},
    J.Field{"path", J.Text{path}}, J.Field{"bytes", word_json(bytes)}]}

def files_json(files: +List<B.Attachment>) -> +List<J.Json>:
  match files:
    case Nil{}: Nil{}
    case Con{file, rest}: file_json(file) <> files_json(rest)

def draft(+body: J.Json) -> B.Draft:
  B.Draft{J.text(J.get(body, "title")), J.text(J.get(body, "description")), B.stage(J.text(J.get(body, "status"))),
    B.priority(J.text(J.get(body, "priority"))), B.owner(B.retained(~String, J.optional_text(J.get(body, "assignee")), "none")),
    optional_id(J.text(J.get(body, "project"))), strings(J.items(J.get(body, "labels"))), files(J.items(J.get(body, "attachments")))}

def draft_fields(draft: B.Draft) -> +List<J.Field>:
  B.Draft{title, description, stage, priority, owner, project, labels, attachments} = draft
  [J.Field{"title", J.Text{title}}, J.Field{"description", J.Text{description}}, J.Field{"status", J.Text{B.stage_name(stage)}},
   J.Field{"priority", J.Text{B.priority_name(priority)}}, J.Field{"assignee", J.Text{B.owner_name(owner)}},
   J.Field{"project", J.Text{id_text(project)}}, J.Field{"labels", J.Array{J.text_items(labels)}}, J.Field{"attachments", J.Array{files_json(attachments)}}]

def draft_json(draft: B.Draft) -> J.Json:
  J.Object{draft_fields(draft)}

def optional(~T: Data, present: Bool, value: T) -> Maybe<&2, T>:
  match present:
    case True{}: Some{value}
    case False{}: None{}

def patch(+body: J.Json) -> B.Patch:
  B.Patch{J.optional_text(J.get(body, "title")), J.optional_text(J.get(body, "description")),
    optional(~B.Stage, present(body, "status"), B.stage(J.text(J.get(body, "status")))),
    optional(~B.Priority, present(body, "priority"), B.priority(J.text(J.get(body, "priority")))),
    optional(~B.Owner, present(body, "assignee"), B.owner(J.text(J.get(body, "assignee")))),
    optional(~Maybe<&2, Nat>, present(body, "project"), optional_id(J.text(J.get(body, "project")))),
    optional(~+List<String>, present(body, "labels"), strings(J.items(J.get(body, "labels")))),
    optional(~+List<B.Attachment>, present(body, "attachments"), files(J.items(J.get(body, "attachments"))))}

def optional_field(value: Maybe<&2, J.Json>, name: String, rest: +List<J.Field>) -> +List<J.Field>:
  match value:
    case None{}: rest
    case Some{value}: J.Field{name, value} <> rest

def mapped(~T: Data, f: @value:T -> J.Json, option: Maybe<&2, T>) -> Maybe<&2, J.Json>:
  match option:
    case None{}: None{}
    case Some{value}: Some{f(value)}

def patch_fields(patch: B.Patch) -> +List<J.Field>:
  B.Patch{title, description, stage, priority, owner, project, labels, attachments} = patch
  optional_field(mapped(~String, (v => J.Text{v}), title), "title",
    optional_field(mapped(~String, (v => J.Text{v}), description), "description",
      optional_field(mapped(~B.Stage, (v => J.Text{B.stage_name(v)}), stage), "status",
        optional_field(mapped(~B.Priority, (v => J.Text{B.priority_name(v)}), priority), "priority",
          optional_field(mapped(~B.Owner, (v => J.Text{B.owner_name(v)}), owner), "assignee",
            optional_field(mapped(~Maybe<&2, Nat>, (v => J.Text{id_text(v)}), project), "project",
              optional_field(mapped(~+List<String>, (v => J.Array{J.text_items(v)}), labels), "labels",
                optional_field(mapped(~+List<B.Attachment>, (v => J.Array{files_json(v)}), attachments), "attachments", Nil{}))))))))

def agent(+body: J.Json) -> B.AgentProfile:
  B.AgentProfile{number(J.get(body, "revision")), J.text(J.get(body, "name")), J.text(J.get(body, "profile")),
    J.text(J.get(body, "reasoning")), J.text(J.get(body, "instructions")), J.get(body, "settings"), number(J.get(body, "concurrency"))}

def construct_fields(kind: WriteKind, +body: J.Json, +id: Nat, +revision: Nat, +now: U32) -> B.Command:
  match kind:
    case CreateKind{}: B.Create{draft(body), now, J.boolean(J.get(body, "assisted")), J.text(J.get(body, "draft_profile"))}
    case UpdateKind{}: B.Update{id, revision, patch(body), now}
    case MoveKind{}: B.MoveCard{id, revision, B.stage(J.text(J.get(body, "status"))), optional_id(J.text(J.get(body, "before_card"))), now}
    case ArchiveKind{}: B.Archive{id, revision, True{}, now}
    case RestoreKind{}: B.Archive{id, revision, False{}, now}
    case DeleteKind{}: B.Delete{id, revision}
    case RunKind{}: B.Run{id, revision, now}
    case LinkKind{}: B.Link{id, revision, number(J.get(body, "task_id")), now}
    case RegenerateKind{}: B.Regenerate{id, revision, J.text(J.get(body, "draft_profile")), now}
    case PinKind{}: B.Pin{id, revision, J.boolean(J.get(body, "pinned")), now}
    case SettingsKind{}: B.Settings{J.boolean(J.get(body, "automatic")), J.text(J.get(body, "draft_profile"))}
    case SaveAgentKind{}: B.SaveAgent{optional_id(J.text(J.get(body, "agent"))), revision, agent(body)}
    case DeleteAgentKind{}: B.DeleteAgent{number(J.get(body, "agent_id")), revision}

def construct(kind: WriteKind, +body: J.Json) -> B.Command:
  construct_fields(kind, body, number(J.get(body, "card_id")), number(J.get(body, "revision")), word(J.get(body, "observed_at")))

def query(kind: ReadKind, body: J.Json) -> B.Query:
  match kind:
    case CardsKind{}: B.ListCards{}
    case CardKind{}: B.ReadCard{number(J.get(body, "card_id"))}
    case AgentsKind{}: B.ListAgents{}

def identity_fields(id: Nat, revision: Nat, now: U32) -> +List<J.Field>:
  [J.Field{"card_id", J.nat(id)}, J.Field{"revision", J.nat(revision)}, J.Field{"observed_at", word_json(now)}]

def command(op: String, fields: +List<J.Field>) -> J.Json:
  J.Object{J.Field{"op", J.Text{op}} <> fields}

def archive_name(archived: Bool) -> String:
  match archived:
    case True{}: "archive_card"
    case False{}: "restore_card"

def agent_fields(agent: B.AgentProfile) -> +List<J.Field>:
  B.AgentProfile{revision, name, profile, reasoning, instructions, settings, concurrency} = agent
  [J.Field{"revision", J.nat(revision)}, J.Field{"name", J.Text{name}}, J.Field{"profile", J.Text{profile}},
   J.Field{"reasoning", J.Text{reasoning}}, J.Field{"instructions", J.Text{instructions}},
   J.Field{"settings", settings}, J.Field{"concurrency", J.nat(concurrency)}]

def command_json(input: B.Command) -> J.Json:
  match input:
    case B.Create{draft, now, assist, profile}:
      command("create_card", List.append(&2, J.Field, draft_fields(draft),
        [J.Field{"observed_at", word_json(now)}, J.Field{"assisted", J.Boolean{assist}}, J.Field{"draft_profile", J.Text{profile}}]))
    case B.Update{id, revision, patch, now}:
      command("update_card", List.append(&2, J.Field, identity_fields(id, revision, now), patch_fields(patch)))
    case B.MoveCard{id, revision, stage, before, now}: command("move_card",
      J.Field{"status", J.Text{B.stage_name(stage)}} <> J.Field{"before_card", J.Text{id_text(before)}} <> identity_fields(id, revision, now))
    case B.Archive{id, revision, archived, now}: command(archive_name(archived), identity_fields(id, revision, now))
    case B.Delete{id, revision}: command("delete_card", identity_fields(id, revision, 0))
    case B.Run{id, revision, now}: command("run_card", identity_fields(id, revision, now))
    case B.Link{id, revision, task, now}: command("link_card", J.Field{"task_id", J.nat(task)} <> identity_fields(id, revision, now))
    case B.Regenerate{id, revision, profile, now}: command("regenerate_card_title", J.Field{"draft_profile", J.Text{profile}} <> identity_fields(id, revision, now))
    case B.Pin{id, revision, pinned, now}: command("pin_card", J.Field{"pinned", J.Boolean{pinned}} <> identity_fields(id, revision, now))
    case B.Settings{automatic, profile}: command("board_settings", [J.Field{"automatic", J.Boolean{automatic}}, J.Field{"draft_profile", J.Text{profile}}])
    case B.SaveAgent{id, revision, agent}: command("save_board_agent", J.Field{"agent", J.Text{id_text(id)}} <> agent_fields(agent))
    case B.DeleteAgent{id, revision}: command("delete_board_agent", [J.Field{"agent_id", J.nat(id)}, J.Field{"revision", J.nat(revision)}])

def query_json(query: B.Query) -> J.Json:
  match query:
    case B.ListCards{}: command("list_cards", Nil{})
    case B.ReadCard{id}: command("read_card", [J.Field{"card_id", J.nat(id)}])
    case B.ListAgents{}: command("list_board_agents", Nil{})

def enrichment_json(state: B.Enrichment) -> J.Json:
  match state:
    case B.NoEnrichment{}: J.Object{[J.Field{"status", J.Text{"idle"}}]}
    case B.Enriching{ticket, revision, retitle}: J.Object{[J.Field{"status", J.Text{"running"}}, J.Field{"ticket", J.nat(ticket)},
      J.Field{"revision", J.nat(revision)}, J.Field{"retitle", J.Boolean{retitle}}]}
    case B.EnrichmentFailed{reason}: J.Object{[J.Field{"status", J.Text{"failed"}}, J.Field{"reason", J.Text{reason}}]}

def card_fields(+id: Nat, card: B.Card) -> +List<J.Field>:
  B.Card{revision, draft, task, archived, created, updated, enrichment, start_error, pinned} = card
  List.append(&2, J.Field, [J.Field{"card_id", J.nat(id)}, J.Field{"identifier", J.Text{B.identifier(id)}},
    J.Field{"revision", J.nat(revision)}, J.Field{"task_id", J.optional_nat(task)}, J.Field{"archived", J.Boolean{archived}},
    J.Field{"created_at", word_json(created)}, J.Field{"updated_at", word_json(updated)}, J.Field{"enrichment", enrichment_json(enrichment)},
    J.Field{"start_error", J.Text{start_error}}, J.Field{"pinned", J.Boolean{pinned}}], draft_fields(draft))
