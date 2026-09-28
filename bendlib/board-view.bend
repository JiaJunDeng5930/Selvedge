import Base
import ../BOARD.bend as B
import ../MODEL.bend as M
import ../COMMANDS.bend as Commands
import ../PROJECTS.bend as Projects
import ../WORKSPACE.bend as Workspace
import ../REASONING.bend as Reasoning
import ./board-state.bend as S
import ./board-codec.bend as C
import ./board-navigation.bend as N
import ./board-filter.bend as F
import ./command-codec.bend as CommandsWire
import ./association-map.bend as Finite
import ./schema.bend as Schema
import ./json.bend as J
import ./tasks.bend as T

# Layout descriptors contain the authoritative labels, fields, enabled actions,
# filter result and revision-bound drop targets. The browser lays them out using
# the reference board design; it neither resolves commands nor edits the cursor.
def action(+key: String, +label: String, +icon: String, +event: M.ViewEvent, +enabled: Bool, +selected: Bool) -> J.Json:
  J.Object{[J.Field{"key", J.Text{key}}, J.Field{"label", J.Text{label}}, J.Field{"icon", J.Text{icon}},
    J.Field{"event", CommandsWire.event_json(event)}, J.Field{"enabled", J.Boolean{enabled}}, J.Field{"selected", J.Boolean{selected}}]}

def navigation(+key: String, +label: String, +icon: String, +event: B.Navigation, +selected: Bool) -> J.Json:
  action(key, label, icon, M.BoardEvent{event}, True{}, selected)

def command_action(+key: String, +label: String, +icon: String, +command: M.Command, +world: M.World) -> J.Json:
  action(key, label, icon, M.Submit{command}, Commands.admitted(Commands.resolve(command, world)), False{})

def board_action(+key: String, +label: String, +icon: String, +command: B.Command, +world: M.World) -> J.Json:
  command_action(key, label, icon, M.BoardCommand{command}, world)

def open_card(+id: Nat) -> J.Json:
  navigation("open/" ++ Nat.show(id), "打开任务", "open", B.OpenDialog{B.CardDialog{id}}, False{})

def open_conversation(+id: Maybe<&2, Nat>) -> J.Json:
  match id:
    case None{}: J.Null{}
    case Some{+id}: action("conversation/" ++ Nat.show(id), "打开会话", "external", M.SelectTask{Some{id}}, True{}, False{})

def field(+name: String, +label: String, +kind: String, +value: J.Json, +required: Bool, +enabled: Bool, +choices: +List<J.Json>) -> J.Json:
  J.Object{[J.Field{"name", J.Text{name}}, J.Field{"label", J.Text{label}}, J.Field{"kind", J.Text{kind}},
    J.Field{"value", value}, J.Field{"required", J.Boolean{required}}, J.Field{"enabled", J.Boolean{enabled}},
    J.Field{"choices", J.Array{choices}}, J.Field{"binding", J.Array{[J.Text{"command"}, J.Text{name}]}}]}

# Partial update commands intentionally omit untouched fields. The native form
# supplies concrete slots for its enabled bindings, so the generic browser never
# has to invent object members or send disabled execution inputs back as edits.
def binding_selected(include: Bool, +field: J.Json, rest: +List<J.Field>) -> +List<J.Field>:
  match include:
    case False{}: rest
    case True{}: J.Field{J.text(J.get(field, "name")), J.get(field, "value")} <> rest

def binding_field(+field: J.Json, +body: J.Json, rest: +List<J.Field>) -> +List<J.Field>:
  binding_selected(J.boolean(J.get(field, "enabled")) && Bool.not(C.present(body, J.text(J.get(field, "name")))), field, rest)

def binding_fields(fields: +List<J.Json>, +body: J.Json) -> +List<J.Field>:
  match fields:
    case Nil{}: Nil{}
    case Con{field, rest}: binding_field(field, body, binding_fields(rest, body))

def bound_command(body: J.Json, fields: +List<J.Json>) -> J.Json:
  match body:
    case J.Object{+members}: J.Object{List.append(&2, J.Field, members, binding_fields(fields, J.Object{members}))}
    case other: other

def form_event(command: M.Command, fields: +List<J.Json>) -> J.Json:
  J.Object{[J.Field{"type", J.Text{"submit"}}, J.Field{"command", bound_command(CommandsWire.command_json(command), fields)}]}

def form_changes(command: M.Command) -> J.Json:
  match command:
    case M.BoardCommand{B.SaveAgent{id, revision, B.AgentProfile{old, name, profile, reasoning, instructions, settings, concurrency}}}:
      J.Object{[J.Field{"profile", J.Object{[J.Field{"event", CommandsWire.event_json(M.SelectProfile{profile})},
        J.Field{"binding", J.Array{[J.Text{"profile"}]}}, J.Field{"reset_fields", J.Array{[J.Text{"reasoning"}]}}]}}]}
    case _: J.Object{Nil{}}

def form(+key: String, +title: String, +label: String, +command: M.Command, +fields: +List<J.Json>, +world: M.World) -> J.Json:
  J.Object{[J.Field{"key", J.Text{key}}, J.Field{"title", J.Text{title}}, J.Field{"label", J.Text{label}},
    J.Field{"event", form_event(command, fields)}, J.Field{"fields", J.Array{fields}}, J.Field{"changes", form_changes(command)},
    J.Field{"enabled", J.Boolean{Commands.admitted(Commands.resolve(command, world))}}]}

def board_form(+key: String, +title: String, +label: String, +command: B.Command, +fields: +List<J.Json>, +world: M.World) -> J.Json:
  form(key, title, label, M.BoardCommand{command}, fields, world)

def ordinary_choice(+allowed: Bool, +profile: M.Profile, +rest: +List<J.Json>) -> +List<J.Json>:
  match allowed profile:
    case True{} M.Profile{+key, provider, name, policy}: F.choice(key, key, "bot") <> rest
    case _ _: rest

def ordinary_choices(+profiles: +List<M.Profile>) -> +List<J.Json>:
  match profiles:
    case Nil{}: Nil{}
    case Con{+profile, rest}: ordinary_choice(S.drafting_profile(profile), profile, ordinary_choices(rest))

def first_profile(+profiles: +List<M.Profile>) -> String:
  match profiles:
    case Nil{}: ""
    case Con{M.Profile{key, provider, name, policy}, rest}: key

def first_choice(+choices: +List<J.Json>) -> String:
  match choices:
    case Nil{}: ""
    case Con{choice, rest}: J.text(J.get(choice, "value"))

def use_preferred(+valid: Bool, +preferred: String, +fallback: String) -> String:
  match valid:
    case True{}: preferred
    case False{}: fallback

def drafting_profile(+world: M.World) -> String:
  +preferred = B.draft_profile(S.registry(world))
  use_preferred(S.ordinary(M.find_profile(S.profiles(world), preferred)), preferred, first_choice(ordinary_choices(S.profiles(world))))

def selected_profile(+preferred: String, +world: M.World) -> String:
  use_preferred(S.present(~M.Profile, M.find_profile(S.profiles(world), preferred)), preferred, first_profile(S.profiles(world)))

def fields_for_draft(+draft: B.Draft, +editable: Bool, +world: M.World) -> +List<J.Json>:
  B.Draft{title, description, stage, priority, owner, project, labels, attachments} = draft
  [field("status", "状态", "choice", J.Text{B.stage_name(stage)}, True{}, editable, F.stages(B.stages())),
   field("priority", "优先级", "choice", J.Text{B.priority_name(priority)}, True{}, editable, F.priority_choices()),
   field("assignee", "负责人", "choice", J.Text{B.owner_name(owner)}, True{}, editable, F.owners(world)),
   field("project", "项目", "choice", J.Text{C.id_text(project)}, False{}, editable, F.projects(world)),
   field("labels", "标签", "tags", J.Array{C.strings_json(labels)}, False{}, editable,
     F.label_choices(F.collect_labels(B.cards(S.registry(world)), Nil{}))),
   field("attachments", "附件", "attachments", J.Array{C.files_json(attachments)}, False{}, editable, Nil{})]

def create_fields(+assisted: Bool, +draft: B.Draft, +world: M.World) -> +List<J.Json>:
  match assisted:
    case False{}:
      field("title", "任务标题", "text", J.Text{""}, True{}, True{}, Nil{}) <>
        field("description", "描述（可选）", "multiline", J.Text{""}, False{}, True{}, Nil{}) <>
        fields_for_draft(draft, True{}, world)
    case True{}:
      field("description", "描述你希望智能体完成的任务…", "multiline", J.Text{""}, True{}, True{}, Nil{}) <>
        field("draft_profile", "生成标题和描述的模型", "choice", J.Text{drafting_profile(world)}, True{}, True{}, ordinary_choices(S.profiles(world))) <>
        fields_for_draft(draft, True{}, world)

def create_template(+assisted: Bool, +stage: B.Stage) -> B.Draft:
  match assisted:
    case True{}: B.Draft{"", "request", stage, B.NoPriority{}, B.Unassigned{}, None{}, Nil{}, Nil{}}
    case False{}: B.Draft{"title", "", stage, B.NoPriority{}, B.Unassigned{}, None{}, Nil{}, Nil{}}

def create_form(+stage: B.Stage, +assisted: Bool, +now: U32, +world: M.World) -> J.Json:
  board_form("board/create", "新建任务", "创建任务", B.Create{create_template(assisted, stage), now, assisted, drafting_profile(world)},
    create_fields(assisted, create_template(assisted, stage), world), world)

def drop_sources(+id: Nat, +card: B.Card, +now: U32, +world: M.World) -> J.Json:
  J.Object{[J.Field{"move", board_action("move", "移动任务", "move",
      B.Move{id, B.revision(card), B.card_stage(B.draft(card)), None{}, now}, world)},
    J.Field{"archive", board_action("archive", "归档", "archive", B.Archive{id, B.revision(card), True{}, now}, world)}]}

def drop_target(stage: B.Stage, before: Maybe<&2, Nat>) -> J.Json:
  J.Object{[J.Field{"source", J.Text{"move"}}, J.Field{"bindings", J.Array{[
    J.Object{[J.Field{"binding", J.Array{[J.Text{"command"}, J.Text{"status"}]}}, J.Field{"value", J.Text{B.stage_name(stage)}}]},
    J.Object{[J.Field{"binding", J.Array{[J.Text{"command"}, J.Text{"before_card"}]}}, J.Field{"value", J.Text{C.id_text(before)}}]}]}}]}

def priority_patch(+priority: B.Priority) -> B.Patch:
  B.Patch{None{}, None{}, None{}, Some{priority}, None{}, None{}, None{}, None{}}

def owner_patch(+owner: B.Owner) -> B.Patch:
  B.Patch{None{}, None{}, None{}, None{}, Some{owner}, None{}, None{}, None{}}

def project_patch(+project: Maybe<&2, Nat>) -> B.Patch:
  B.Patch{None{}, None{}, None{}, None{}, None{}, Some{project}, None{}, None{}}

def context_update(+category: String, +choice: J.Json) -> B.Patch:
  match category:
    case "priority": priority_patch(B.priority(J.text(J.get(choice, "value"))))
    case "assignee": owner_patch(B.owner(J.text(J.get(choice, "value"))))
    case "project": project_patch(C.optional_id(J.text(J.get(choice, "value"))))
    case _: B.stage_patch(B.stage(J.text(J.get(choice, "value"))))

def context_items(+choices: +List<J.Json>, +category: String, +id: Nat, +card: B.Card, +now: U32, +world: M.World) -> +List<J.Json>:
  match choices:
    case Nil{}: Nil{}
    case Con{+choice, rest}:
      board_action("set/" ++ category ++ "/" ++ J.text(J.get(choice, "value")), J.text(J.get(choice, "label")), J.text(J.get(choice, "icon")),
        B.Update{id, B.revision(card), context_update(category, choice), now}, world) <>
        context_items(rest, category, id, card, now, world)

def context_group(+label: String, +icon: String, +items: +List<J.Json>) -> J.Json:
  J.Object{[J.Field{"label", J.Text{label}}, J.Field{"icon", J.Text{icon}}, J.Field{"items", J.Array{items}}]}

def pin_label(+pinned: Bool) -> String:
  match pinned:
    case True{}: "取消置顶"
    case False{}: "置顶任务"

def archive_action(+archived: Bool, +id: Nat, +card: B.Card, +now: U32, +world: M.World) -> J.Json:
  match archived:
    case True{}: board_action("restore/" ++ Nat.show(id), "恢复", "restore", B.Archive{id, B.revision(card), False{}, now}, world)
    case False{}: board_action("archive/" ++ Nat.show(id), "归档", "archive", B.Archive{id, B.revision(card), True{}, now}, world)

def card_actions(+id: Nat, +card: B.Card, +now: U32, +world: M.World) -> +List<J.Json>:
  [board_action("pin/" ++ Nat.show(id), pin_label(B.pinned(card)), "pin", B.Pin{id, B.revision(card), Bool.not(B.pinned(card)), now}, world),
   board_action("run/" ++ Nat.show(id), "立即开始", "play", B.Run{id, B.revision(card), now}, world),
   board_action("regenerate/" ++ Nat.show(id), "重新生成标题", "sparkles", B.Regenerate{id, B.revision(card), drafting_profile(world), now}, world),
   archive_action(B.archived(card), id, card, now, world),
   action("delete/" ++ Nat.show(id), "删除任务…", "trash", M.BoardEvent{B.OpenDialog{B.DeleteDialog{id}}},
     Commands.admitted(Commands.resolve(M.BoardCommand{B.Delete{id, B.revision(card)}}, world)), False{})]

def card_context(+id: Nat, +card: B.Card, +now: U32, +world: M.World) -> +List<J.Json>:
  [context_group("状态", "status/todo", context_items(F.stages(B.stages()), "status", id, card, now, world)),
   context_group("优先级", "priority/none", context_items(F.priority_choices(), "priority", id, card, now, world)),
   context_group("负责人", "user", context_items(F.owners(world), "assignee", id, card, now, world)),
   context_group("项目", "folder", context_items(F.projects(world), "project", id, card, now, world))]

def preview(+text: String) -> String:
  String.take(String.trim(text), 280n)

def card_json(+id: Nat, +card: B.Card, +now: U32, +world: M.World) -> J.Json:
  J.Object{[J.Field{"key", J.Text{"card/" ++ Nat.show(id)}}, J.Field{"card_id", J.nat(id)}, J.Field{"revision", J.nat(B.revision(card))},
    J.Field{"identifier", J.Text{B.identifier(id)}}, J.Field{"title", J.Text{String.take(B.title(B.draft(card)), 160n)}},
    J.Field{"description", J.Text{preview(B.description(B.draft(card)))}}, J.Field{"status", J.Text{B.stage_name(B.card_stage(B.draft(card)))}},
    J.Field{"status_label", J.Text{B.stage_label(B.card_stage(B.draft(card)))}},
    J.Field{"priority", J.Text{B.priority_name(B.card_priority(B.draft(card)))}}, J.Field{"priority_label", J.Text{B.priority_label(B.card_priority(B.draft(card)))}},
    J.Field{"owner", J.Text{F.owner_label(B.card_owner(B.draft(card)), world)}}, J.Field{"owner_icon", J.Text{B.owner_name(B.card_owner(B.draft(card)))}},
    J.Field{"project", J.Text{F.project_label(B.project(B.draft(card)), world)}}, J.Field{"has_project", J.Boolean{S.present(~Nat, B.project(B.draft(card)))}},
    J.Field{"labels", J.Array{C.strings_json(B.labels(B.draft(card)))}}, J.Field{"pinned", J.Boolean{B.pinned(card)}},
    J.Field{"updated", J.Text{F.time_ago(now, B.updated(card))}}, J.Field{"activity", J.Text{S.activity(card, world)}},
    J.Field{"activity_label", J.Text{S.activity_label(S.activity(card, world))}}, J.Field{"open", open_card(id)},
    J.Field{"draggable", J.Boolean{S.mutable(card, world)}}, J.Field{"drops", drop_sources(id, card, now, world)},
    J.Field{"drop", drop_target(B.card_stage(B.draft(card)), Some{id})},
    J.Field{"context", navigation("context/" ++ Nat.show(id), "任务菜单", "more", B.OpenDialog{B.ContextDialog{id}}, False{})}]}

def cards_json(+cards: +List<Finite.Entry(B.Card)>, +now: U32, +world: M.World) -> +List<J.Json>:
  match cards:
    case Nil{}: Nil{}
    case Con{(id, card), rest}: card_json(id, card, now, world) <> cards_json(rest, now, world)

def column_json(+stage: B.Stage, +cards: +List<Finite.Entry(B.Card)>, +now: U32, +world: M.World) -> J.Json:
  J.Object{[J.Field{"key", J.Text{B.stage_name(stage)}}, J.Field{"label", J.Text{B.stage_label(stage)}},
    J.Field{"icon", J.Text{"status/" ++ B.stage_name(stage)}}, J.Field{"count", J.nat(List.length(&2, Finite.Entry(B.Card), cards))},
    J.Field{"add", navigation("new/" ++ B.stage_name(stage), "新建任务", "plus", B.OpenDialog{B.CreateDialog{stage, False{}}}, False{})},
    J.Field{"drop", drop_target(stage, None{})},
    J.Field{"cards", J.Array{cards_json(cards, now, world)}}]}

def archive_column(+count: Nat) -> J.Json:
  J.Object{[J.Field{"key", J.Text{"archive"}}, J.Field{"label", J.Text{"归档"}}, J.Field{"icon", J.Text{"archive"}},
    J.Field{"count", J.nat(count)}, J.Field{"cards", J.Array{Nil{}}},
    J.Field{"drop", J.Object{[J.Field{"source", J.Text{"archive"}}]}},
    J.Field{"open", navigation("archive", "查看归档任务", "archive", B.OpenDialog{B.ArchiveDialog{}}, False{})}]}

def columns(+stages: +List<B.Stage>, +cards: +List<Finite.Entry(B.Card)>, +now: U32, +world: M.World) -> +List<J.Json>:
  match stages:
    case Nil{}: [archive_column(List.length(&2, Finite.Entry(B.Card), F.archived(B.cards(S.registry(world)))))]
    case Con{+stage, rest}: column_json(stage, F.column(cards, B.stage_name(stage)), now, world) <> columns(rest, cards, now, world)

def filter_options(+choices: +List<J.Json>, +category: String, +selected: +List<String>) -> +List<J.Json>:
  match choices:
    case Nil{}: Nil{}
    case Con{+choice, rest}:
      navigation("filter/" ++ category ++ "/" ++ J.text(J.get(choice, "value")), J.text(J.get(choice, "label")), J.text(J.get(choice, "icon")),
        B.ToggleFilter{category, J.text(J.get(choice, "value"))}, Schema.contains(selected, J.text(J.get(choice, "value")))) <>
        filter_options(rest, category, selected)

def filter_group(+category: String, +label: String, +icon: String, +choices: +List<J.Json>, +filter: B.Filter) -> J.Json:
  J.Object{[J.Field{"key", J.Text{category}}, J.Field{"label", J.Text{label}}, J.Field{"icon", J.Text{icon}},
    J.Field{"count", J.nat(List.length(&2, String, F.values(category, filter)))},
    J.Field{"items", J.Array{filter_options(choices, category, F.values(category, filter))}}]}

def filter_groups(+filter: B.Filter, +world: M.World) -> +List<J.Json>:
  [filter_group("status", "状态", "status/todo", F.stages(B.stages()), filter),
   filter_group("priority", "优先级", "priority/none", F.priority_choices(), filter),
   filter_group("date", "更新时间", "clock", [F.choice("1", "最近 24 小时", "clock"), F.choice("7", "最近 7 天", "clock"), F.choice("30", "最近 30 天", "clock")], filter),
   filter_group("assignee", "负责人", "user", F.owners(world), filter),
   filter_group("creator", "创建人", "user", [F.choice("self", "我", "user")], filter),
   filter_group("project", "项目", "folder", F.projects(world), filter),
   filter_group("label", "标签", "tag", F.label_choices(F.collect_labels(B.cards(S.registry(world)), Nil{})), filter)]

def tabs(+selected: String, +working: Nat) -> +List<J.Json>:
  [navigation("view/all", "全部", "board", B.ChangeView{"all"}, String.eq(selected, "all")),
   navigation("view/assigned", "已分配", "users", B.ChangeView{"assigned"}, String.eq(selected, "assigned")),
   navigation("view/unassigned", "未分配", "user", B.ChangeView{"unassigned"}, String.eq(selected, "unassigned")),
   navigation("view/working", Nat.show(working) ++ " 个智能体工作中", "bot", B.ChangeView{"working"}, String.eq(selected, "working"))]

def toolbar(+filter: B.Filter, +world: M.World) -> J.Json:
  B.Filter{view, search, status, priority, date, assignee, creator, project, label} = filter
  J.Object{[J.Field{"tabs", J.Array{tabs(view, F.working(B.cards(S.registry(world)), world))}},
    J.Field{"search", J.Object{[J.Field{"value", J.Text{search}}, J.Field{"event", CommandsWire.event_json(M.BoardEvent{B.Search{""}})},
      J.Field{"binding", J.Array{[J.Text{"event"}, J.Text{"query"}]}}]}},
    J.Field{"automatic", J.Boolean{B.automatic(S.registry(world))}}, J.Field{"toggle_automatic",
      board_action("automatic", "自动", "toggle", B.Settings{Bool.not(B.automatic(S.registry(world))), B.draft_profile(S.registry(world))}, world)},
    J.Field{"create", navigation("new-card", "新建任务", "plus", B.OpenDialog{B.CreateDialog{B.Todo{}, False{}}}, False{})},
    J.Field{"create_project", navigation("new-project", "创建新项目", "folder", B.OpenDialog{B.ProjectDialog{None{}}}, False{})}]}

def navigation_actions(+selected: B.Pane) -> +List<J.Json>:
  [navigation("nav/threads", "会话", "message", B.ShowPane{B.ThreadsPane{}}, String.eq(N.pane_name(selected), "threads")),
   navigation("nav/board", "任务看板", "board", B.ShowPane{B.BoardPane{}}, String.eq(N.pane_name(selected), "board")),
   navigation("nav/projects", "项目", "folder", B.ShowPane{B.ProjectsPane{}}, String.eq(N.pane_name(selected), "projects")),
   navigation("nav/agents", "智能体", "bot", B.ShowPane{B.AgentsPane{}}, String.eq(N.pane_name(selected), "agents"))]

def detail_fields(+draft: B.Draft, +mutable: Bool, +editable: Bool, +world: M.World) -> +List<J.Json>:
  B.Draft{title, description, stage, priority, owner, project, labels, attachments} = draft
  [field("title", "任务标题", "text", J.Text{title}, True{}, editable, Nil{}),
   field("description", "描述", "multiline", J.Text{description}, False{}, editable, Nil{}),
   field("status", "状态", "choice", J.Text{B.stage_name(stage)}, True{}, mutable, F.stages(B.stages())),
   field("priority", "优先级", "choice", J.Text{B.priority_name(priority)}, True{}, mutable, F.priority_choices()),
   field("assignee", "负责人", "choice", J.Text{B.owner_name(owner)}, True{}, editable, F.owners(world)),
   field("project", "项目", "choice", J.Text{C.id_text(project)}, False{}, editable, F.projects(world)),
   field("labels", "标签", "tags", J.Array{C.strings_json(labels)}, False{}, mutable,
     F.label_choices(F.collect_labels(B.cards(S.registry(world)), Nil{}))),
   field("attachments", "附件", "attachments", J.Array{C.files_json(attachments)}, False{}, editable, Nil{})]

def detail_form(+id: Nat, +card: B.Card, +now: U32, +world: M.World) -> J.Json:
  board_form("board/edit/" ++ Nat.show(id), "任务详情", "保存修改",
    B.Update{id, B.revision(card), B.stage_patch(B.card_stage(B.draft(card))), now},
    detail_fields(B.draft(card), S.mutable(card, world), S.editing(card, world), world), world)

def task_option(+available: Bool, +task: M.Task, +rest: +List<J.Json>) -> +List<J.Json>:
  match available:
    case False{}: rest
    case True{}: F.choice(Nat.show(M.task_id(task)), "#" ++ Nat.show(M.task_id(task)) ++ " · " ++ M.status_name(M.task_status(task)), "message") <> rest

def link_options(+tasks: +List<M.Task>, +cards: +List<Finite.Entry(B.Card)>) -> +List<J.Json>:
  match tasks:
    case Nil{}: Nil{}
    case Con{+task, rest}: task_option(Bool.not(S.task_used(cards, M.task_id(task))), task, link_options(rest, cards))

def linked_form_options(+choices: +List<J.Json>, +id: Nat, +card: B.Card, +now: U32, +world: M.World) -> J.Json:
  match choices:
    case Nil{}: J.Null{}
    case Con{+first, rest}:
      board_form("board/link/" ++ Nat.show(id), "关联已有会话", "关联会话",
        B.Link{id, B.revision(card), C.number(J.Number{J.text(J.get(first, "value"))}), now},
        [field("task_id", "会话", "integer-choice", J.get(first, "value"), True{}, True{}, first <> rest)], world)

def link_form(+eligible: Bool, +id: Nat, +card: B.Card, +now: U32, +world: M.World) -> J.Json:
  match eligible:
    case False{}: J.Null{}
    case True{}: linked_form_options(link_options(S.entries(world), B.cards(S.registry(world))), id, card, now, world)

def enrichment_notice(+enrichment: B.Enrichment) -> String:
  match enrichment:
    case B.NoEnrichment{}: ""
    case B.Enriching{ticket, revision, retitle}: "正在生成。原始请求已保存；本次生成完成前不能编辑或移动任务。"
    case B.EnrichmentFailed{reason}: reason

def execution_notice(+linked: Bool, +busy: Bool) -> String:
  match linked busy:
    case _ True{}: "智能体正在运行。可以在会话中追加消息、请求中断或处理授权；归档会中断当前运行。"
    case True{} False{}: "此任务已关联会话。执行时的描述、附件、负责人和项目保持不变；可以更新状态、优先级和标签，或在会话中继续工作。"
    case False{} False{}: ""

def close_action() -> J.Json:
  navigation("dialog/close", "关闭", "close", B.OpenDialog{B.NoDialog{}}, False{})

def expand_action(+expanded: Bool) -> J.Json:
  navigation("dialog/expand", "切换全屏", "expand", B.ExpandDialog{Bool.not(expanded)}, expanded)

def missing_dialog(+kind: String, +reason: String) -> J.Json:
  J.Object{[J.Field{"kind", J.Text{kind}}, J.Field{"notice", J.Text{reason}}, J.Field{"close", close_action()}]}

def detail_dialog(+found: Maybe<&2, B.Card>, +id: Nat, +cursor: B.Cursor, +world: M.World) -> J.Json:
  match found:
    case None{}: missing_dialog("missing", "任务已经被删除。")
    case Some{+card}:
      J.Object{[J.Field{"kind", J.Text{"card"}}, J.Field{"key", J.Text{"board/card/" ++ Nat.show(id)}},
        J.Field{"identifier", J.Text{B.identifier(id)}}, J.Field{"revision", J.nat(B.revision(card))},
        J.Field{"title", J.Text{B.title(B.draft(card))}}, J.Field{"project", J.Text{F.project_label(B.project(B.draft(card)), world)}},
        J.Field{"expanded", J.Boolean{N.expanded_of(cursor)}}, J.Field{"close", close_action()}, J.Field{"expand", expand_action(N.expanded_of(cursor))},
        J.Field{"notice", J.Text{enrichment_notice(B.enrichment(card)) ++ B.start_error(card)}},
        J.Field{"execution_notice", J.Text{execution_notice(Bool.not(B.unlinked(B.task(card))), S.busy(S.task(card, world)))}},
        J.Field{"activity", J.Text{S.activity(card, world)}}, J.Field{"activity_label", J.Text{S.activity_label(S.activity(card, world))}},
        J.Field{"task_id", J.optional_nat(B.task(card))}, J.Field{"open_conversation", open_conversation(B.task(card))},
        J.Field{"form", detail_form(id, card, N.now_of(cursor), world)},
        J.Field{"link_form", link_form(S.editing(card, world), id, card, N.now_of(cursor), world)},
        J.Field{"actions", J.Array{card_actions(id, card, N.now_of(cursor), world)}}]}

def context_dialog(+found: Maybe<&2, B.Card>, +id: Nat, +now: U32, +world: M.World) -> J.Json:
  match found:
    case None{}: missing_dialog("missing", "任务已经被删除。")
    case Some{+card}:
      J.Object{[J.Field{"kind", J.Text{"context"}}, J.Field{"key", J.Text{"context/" ++ Nat.show(id)}},
        J.Field{"identifier", J.Text{B.identifier(id)}}, J.Field{"close", close_action()}, J.Field{"open", open_card(id)},
        J.Field{"groups", J.Array{card_context(id, card, now, world)}}, J.Field{"actions", J.Array{card_actions(id, card, now, world)}},
        J.Field{"open_conversation", open_conversation(B.task(card))}]}

def delete_dialog(+found: Maybe<&2, B.Card>, +id: Nat, +world: M.World) -> J.Json:
  match found:
    case None{}: missing_dialog("missing", "任务已经被删除。")
    case Some{+card}:
      J.Object{[J.Field{"kind", J.Text{"delete"}}, J.Field{"key", J.Text{"delete/" ++ Nat.show(id)}},
        J.Field{"title", J.Text{"删除 " ++ B.identifier(id) ++ "？"}}, J.Field{"description", J.Text{"这会删除看板卡片，不会删除已关联会话及其历史。"}},
        J.Field{"close", navigation("delete/cancel", "取消", "close", B.OpenDialog{B.CardDialog{id}}, False{})},
        J.Field{"confirm", board_action("delete/confirm", "删除任务", "trash", B.Delete{id, B.revision(card)}, world)}]}

def archive_rows(+entries: +List<Finite.Entry(B.Card)>, +now: U32, +world: M.World) -> +List<J.Json>:
  match entries:
    case Nil{}: Nil{}
    case Con{(+id, +card), rest}:
      J.Object{[J.Field{"identifier", J.Text{B.identifier(id)}}, J.Field{"title", J.Text{String.take(B.title(B.draft(card)), 160n)}},
        J.Field{"updated", J.Text{F.time_ago(now, B.updated(card))}}, J.Field{"open", open_card(id)},
        J.Field{"restore", board_action("restore/" ++ Nat.show(id), "恢复", "restore", B.Archive{id, B.revision(card), False{}, now}, world)},
        J.Field{"delete", action("delete/" ++ Nat.show(id), "删除", "trash", M.BoardEvent{B.OpenDialog{B.DeleteDialog{id}}},
          Commands.admitted(Commands.resolve(M.BoardCommand{B.Delete{id, B.revision(card)}}, world)), False{})}]} <> archive_rows(rest, now, world)

def archive_dialog(+cursor: B.Cursor, +world: M.World) -> J.Json:
  J.Object{[J.Field{"kind", J.Text{"archive"}}, J.Field{"key", J.Text{"board/archive"}}, J.Field{"title", J.Text{"归档任务"}},
    J.Field{"close", close_action()}, J.Field{"rows", J.Array{archive_rows(F.archived(S.display_cards(S.registry(world))), N.now_of(cursor), world)}}]}

def retained_creation(keep: Bool, form: J.Json) -> J.Json:
  match keep form:
    case True{} J.Object{fields}: J.Object{J.Field{"retain_fields", J.Array{[J.Text{"status"}, J.Text{"priority"},
      J.Text{"assignee"}, J.Text{"project"}, J.Text{"labels"}, J.Text{"draft_profile"}]}} <> fields}
    case _ other: other

def creation_notice(assisted: Bool) -> String:
  match assisted:
    case False{}: ""
    case True{}: "所选生成模型将整理标题和描述；任务执行使用所选负责人。未分配的任务不会自动执行。"

def create_dialog(+stage: B.Stage, +assisted: Bool, +cursor: B.Cursor, +world: M.World) -> J.Json:
  J.Object{[J.Field{"kind", J.Text{"create"}}, J.Field{"key", J.Text{"board/create"}}, J.Field{"title", J.Text{"新建任务"}},
    J.Field{"assisted", J.Boolean{assisted}}, J.Field{"expanded", J.Boolean{N.expanded_of(cursor)}}, J.Field{"close", close_action()},
    J.Field{"expand", expand_action(N.expanded_of(cursor))}, J.Field{"keep_create", J.Boolean{N.keep_of(cursor)}},
    J.Field{"toggle_keep_create", navigation("create/keep", "继续创建", "check", B.KeepCreating{Bool.not(N.keep_of(cursor))}, N.keep_of(cursor))},
    J.Field{"modes", J.Array{[navigation("create/manual", "切换到手动", "edit", B.OpenDialog{B.CreateDialog{stage, False{}}}, Bool.not(assisted)),
      navigation("create/assisted", "切换到智能体", "sparkles", B.OpenDialog{B.CreateDialog{stage, True{}}}, assisted)]}},
    J.Field{"form", retained_creation(N.keep_of(cursor), create_form(stage, assisted, N.now_of(cursor), world))},
    J.Field{"notice", J.Text{creation_notice(assisted)}}]}

def current_effort(+found: Maybe<&2, M.Profile>, +previous: String) -> String:
  match found:
    case None{}: previous
    case Some{profile}: Reasoning.selection(previous, M.profile_reasoning(profile))

def effort_choices(+found: Maybe<&2, M.Profile>) -> +List<J.Json>:
  match found:
    case Some{M.Profile{key, provider, name, Reasoning.Adaptive{evaluator, efforts, baseline, transport, maximum}}}:
      [F.choice("auto", "Auto", "sparkles")]
    case _: Nil{}

def effort_kind(+found: Maybe<&2, M.Profile>) -> String:
  match found:
    case Some{M.Profile{key, provider, name, Reasoning.Adaptive{evaluator, efforts, baseline, transport, maximum}}}: "choice"
    case _: "text"

def editable_settings_fields(fields: +List<J.Field>) -> +List<J.Field>:
  match fields:
    case Nil{}: Nil{}
    case Con{J.Field{"guidance", value}, rest}: editable_settings_fields(rest)
    case Con{field, rest}: field <> editable_settings_fields(rest)

def editable_settings(settings: J.Json) -> J.Json:
  match settings:
    case J.Object{fields}: J.Object{editable_settings_fields(fields)}
    case other: other

def agent_form(+id: Maybe<&2, Nat>, +agent: B.AgentProfile, +preferred: String, +world: M.World) -> J.Json:
  B.AgentProfile{+revision, +name, +profile, +reasoning, +instructions, +settings, +concurrency} = agent
  +selected = selected_profile(use_preferred(B.nonempty(preferred), preferred, profile), world)
  +effort = current_effort(M.find_profile(S.profiles(world), selected), reasoning)
  board_form("board/agent/" ++ C.id_text(id), "智能体设置", "保存智能体",
    B.SaveAgent{id, revision, B.AgentProfile{revision, use_preferred(B.nonempty(name), name, "agent"), selected, effort, instructions, settings, concurrency}},
    [field("name", "名称", "text", J.Text{name}, True{}, True{}, Nil{}),
     field("profile", "模型端点", "profile-choice", J.Text{selected}, True{}, True{}, F.profile_choices(S.profiles(world))),
     field("reasoning", "推理等级", effort_kind(M.find_profile(S.profiles(world), selected)), J.Text{effort}, True{}, True{}, effort_choices(M.find_profile(S.profiles(world), selected))),
     field("instructions", "角色和执行说明", "multiline", J.Text{instructions}, False{}, True{}, Nil{}),
     field("concurrency", "最大并发任务数", "integer", J.nat(concurrency), True{}, True{}, Nil{}),
     field("settings", "工作区、沙箱与授权设置", "json", editable_settings(settings), True{}, True{}, Nil{})], world)

def existing_agent(+found: Maybe<&2, B.AgentProfile>, +id: Maybe<&2, Nat>, +preferred: String, +world: M.World) -> J.Json:
  match found:
    case None{}: missing_dialog("missing", "智能体已经被删除。")
    case Some{agent}:
      J.Object{[J.Field{"kind", J.Text{"agent"}}, J.Field{"key", J.Text{"board/agent/" ++ C.id_text(id)}},
        J.Field{"title", J.Text{"智能体设置"}}, J.Field{"close", close_action()}, J.Field{"form", agent_form(id, agent, preferred, world)},
        J.Field{"notice", J.Text{"修改只影响将来启动的任务；已经开始的任务继续使用被冻结的执行配置。卡片项目覆盖角色设置中的 project_id。"}}]}

def agent_dialog(+id: Maybe<&2, Nat>, +preferred: String, +world: M.World) -> J.Json:
  match id:
    case None{}: existing_agent(Some{B.AgentProfile{0n, "", first_profile(S.profiles(world)), "default", "", J.Object{Nil{}}, 1n}}, None{}, preferred, world)
    case Some{+id}: existing_agent(B.find_agent(S.registry(world), id), Some{id}, preferred, world)

def agent_rows(+agents: +List<Finite.Entry(B.AgentProfile)>, +world: M.World) -> +List<J.Json>:
  match agents:
    case Nil{}: Nil{}
    case Con{(+id, B.AgentProfile{+revision, name, profile, reasoning, instructions, settings, concurrency}), rest}:
      J.Object{[J.Field{"key", J.Text{"agent/" ++ Nat.show(id)}}, J.Field{"name", J.Text{name}}, J.Field{"profile", J.Text{profile}},
        J.Field{"reasoning", J.Text{reasoning}}, J.Field{"instructions", J.Text{preview(instructions)}}, J.Field{"concurrency", J.nat(concurrency)},
        J.Field{"active", J.nat(S.active_for(B.cards(S.registry(world)), B.Agent{id}, world))},
        J.Field{"edit", navigation("agent/edit/" ++ Nat.show(id), "编辑", "edit", B.OpenDialog{B.AgentDialog{Some{id}}}, False{})},
        J.Field{"delete", board_action("agent/delete/" ++ Nat.show(id), "删除", "trash", B.DeleteAgent{id, revision}, world)}]} <> agent_rows(rest, world)

def project_environment(environment: M.Environment) -> M.Project:
  M.Environment{catalog, profiles, max_fork, max_descendants, +guidance, plugins} = environment
  M.Project{"", Workspace.default_workspace(guidance), guidance}

def project_defaults(world: M.World) -> M.Project:
  project_environment(Commands.settings(world))

def project_command(+id: Maybe<&2, Nat>, +name: String, +workspace: J.Json) -> M.Command:
  match id:
    case None{}: M.CreateProject{name, workspace, J.Null{}}
    case Some{id}: M.UpdateProject{id, Some{name}, workspace, J.Null{}}

def project_form(+id: Maybe<&2, Nat>, +project: M.Project, +world: M.World) -> J.Json:
  M.Project{+name, +workspace, guidance} = project
  form("board/project/" ++ C.id_text(id), "项目设置", "保存项目",
    project_command(id, use_preferred(B.nonempty(name), name, "project"), M.workspace_json(workspace)),
    [field("name", "项目名称", "text", J.Text{name}, True{}, True{}, Nil{}),
     field("workspace", "项目目录", "workspace", M.workspace_json(workspace), True{}, True{}, Nil{})], world)

def found_project(+found: Maybe<&2, M.Project>, +id: Maybe<&2, Nat>, +world: M.World) -> J.Json:
  match found:
    case None{}: missing_dialog("missing", "项目已经被删除。")
    case Some{project}:
      J.Object{[J.Field{"kind", J.Text{"project"}}, J.Field{"key", J.Text{"board/project/" ++ C.id_text(id)}},
        J.Field{"title", J.Text{"项目设置"}}, J.Field{"close", close_action()}, J.Field{"form", project_form(id, project, world)},
        J.Field{"notice", J.Text{"目录在提交时由服务器验证并读取 AGENTS.md。项目修改只影响后续执行；已有会话的工作区不变。"}}]}

def project_dialog(+id: Maybe<&2, Nat>, +world: M.World) -> J.Json:
  match id:
    case None{}: found_project(Some{project_defaults(world)}, None{}, world)
    case Some{+id}: found_project(Projects.find(Projects.registry(world), id), Some{id}, world)

def project_card_count(+cards: +List<Finite.Entry(B.Card)>, +id: Nat) -> Nat:
  match cards:
    case Nil{}: 0n
    case Con{(key, card), rest}: S.count(S.owns(id, B.project(B.draft(card))), project_card_count(rest, id))

def project_rows(+projects: +List<Finite.Entry(M.Project)>, +world: M.World) -> +List<J.Json>:
  match projects:
    case Nil{}: Nil{}
    case Con{(+id, M.Project{name, workspace, guidance}), rest}:
      J.Object{[J.Field{"key", J.Text{"project/" ++ Nat.show(id)}}, J.Field{"name", J.Text{name}},
        J.Field{"workspace", M.workspace_json(workspace)}, J.Field{"tasks", J.nat(Projects.task_count(S.entries(world), id))},
        J.Field{"cards", J.nat(project_card_count(B.cards(S.registry(world)), id))},
        J.Field{"open", navigation("project/board/" ++ Nat.show(id), "查看看板", "board", B.ToggleFilter{"project", Nat.show(id)}, False{})},
        J.Field{"edit", navigation("project/edit/" ++ Nat.show(id), "编辑", "edit", B.OpenDialog{B.ProjectDialog{Some{id}}}, False{})},
        J.Field{"delete", command_action("project/delete/" ++ Nat.show(id), "删除", "trash", M.DeleteProject{id}, world)}]} <> project_rows(rest, world)

def settings_form(+world: M.World) -> J.Json:
  board_form("board/settings", "看板设置", "保存设置", B.Settings{B.automatic(S.registry(world)), B.draft_profile(S.registry(world))},
    [field("automatic", "自动派发已分配的待办任务", "boolean", J.Boolean{B.automatic(S.registry(world))}, True{}, True{}, Nil{}),
     field("draft_profile", "标题和描述生成模型", "choice", J.Text{B.draft_profile(S.registry(world))}, False{}, True{},
       F.choice("", "创建时选择", "bot") <> ordinary_choices(S.profiles(world)))], world)

def dialog(+dialog: B.Dialog, +cursor: B.Cursor, +preferred: String, +world: M.World) -> J.Json:
  match dialog:
    case B.NoDialog{}: J.Null{}
    case B.CreateDialog{stage, assisted}: create_dialog(stage, assisted, cursor, world)
    case B.CardDialog{+id}: detail_dialog(B.find(S.registry(world), id), id, cursor, world)
    case B.ContextDialog{+id}: context_dialog(B.find(S.registry(world), id), id, N.now_of(cursor), world)
    case B.DeleteDialog{+id}: delete_dialog(B.find(S.registry(world), id), id, world)
    case B.ArchiveDialog{}: archive_dialog(cursor, world)
    case B.AgentDialog{id}: agent_dialog(id, preferred, world)
    case B.ProjectDialog{id}: project_dialog(id, world)

def dialog_task(+found: Maybe<&2, B.Card>) -> Maybe<&2, Nat>:
  match found:
    case None{}: None{}
    case Some{card}: B.task(card)

def active_task(+dialog: B.Dialog, +world: M.World) -> Maybe<&2, Nat>:
  match dialog:
    case B.CardDialog{id}: dialog_task(B.find(S.registry(world), id))
    case _: None{}

def board_body(+cursor: B.Cursor, +world: M.World) -> J.Json:
  J.Object{[J.Field{"toolbar", toolbar(N.filter_of(cursor), world)},
    J.Field{"filter_groups", J.Array{filter_groups(N.filter_of(cursor), world)}}, J.Field{"filter_count", J.nat(F.count(N.filter_of(cursor)))},
    J.Field{"clear_filters", navigation("filters/clear", "清除筛选", "close", B.ClearFilters{}, False{})},
    J.Field{"columns", J.Array{columns(B.stages(), F.filtered(S.display_cards(S.registry(world)), N.filter_of(cursor), N.now_of(cursor), world), N.now_of(cursor), world)}}]}

def page(+pane: B.Pane, +cursor: B.Cursor, +world: M.World) -> J.Json:
  match pane:
    case B.BoardPane{}: board_body(cursor, world)
    case B.AgentsPane{}:
      J.Object{[J.Field{"title", J.Text{"智能体"}}, J.Field{"rows", J.Array{agent_rows(B.agents(S.registry(world)), world)}},
        J.Field{"create", navigation("agents/new", "新建智能体", "plus", B.OpenDialog{B.AgentDialog{None{}}}, False{})},
        J.Field{"settings", settings_form(world)}]}
    case B.ProjectsPane{}:
      J.Object{[J.Field{"title", J.Text{"项目"}}, J.Field{"rows", J.Array{project_rows(Projects.entries(Projects.registry(world)), world)}},
        J.Field{"create", navigation("projects/new", "新建项目", "plus", B.OpenDialog{B.ProjectDialog{None{}}}, False{})}]}
    case _: J.Null{}

def screen(+cursor: B.Cursor, +preferred: String, +world: M.World) -> J.Json:
  J.Object{[J.Field{"pane", J.Text{N.pane_name(N.pane_of(cursor))}}, J.Field{"navigation", J.Array{navigation_actions(N.pane_of(cursor))}},
    J.Field{"body", page(N.pane_of(cursor), cursor, world)}, J.Field{"dialog", dialog(N.dialog_of(cursor), cursor, preferred, world)},
    J.Field{"active_task", J.optional_nat(active_task(N.dialog_of(cursor), world))}]}
