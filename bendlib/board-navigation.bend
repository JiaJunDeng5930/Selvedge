import Base
import ../BOARD.bend as B
import ./board-codec.bend as C
import ./json.bend as J
import ./schema.bend as Schema

# Stateless, replayable presentation observations. A filter never edits cards.
def pane_name(+pane: B.Pane) -> String:
  match pane:
    case B.ThreadsPane{}: "threads"
    case B.BoardPane{}: "board"
    case B.AgentsPane{}: "agents"
    case B.ProjectsPane{}: "projects"

def pane(+name: String) -> B.Pane:
  match name:
    case "board": B.BoardPane{}
    case "agents": B.AgentsPane{}
    case "projects": B.ProjectsPane{}
    case _: B.ThreadsPane{}

def pane_of(+cursor: B.Cursor) -> B.Pane:
  B.Cursor{pane, filter, dialog, keep_create, expanded, now} = cursor
  pane

def filter_of(+cursor: B.Cursor) -> B.Filter:
  B.Cursor{pane, filter, dialog, keep_create, expanded, now} = cursor
  filter

def dialog_of(+cursor: B.Cursor) -> B.Dialog:
  B.Cursor{pane, filter, dialog, keep_create, expanded, now} = cursor
  dialog

def keep_of(+cursor: B.Cursor) -> Bool:
  B.Cursor{pane, filter, dialog, keep_create, expanded, now} = cursor
  keep_create

def expanded_of(+cursor: B.Cursor) -> Bool:
  B.Cursor{pane, filter, dialog, keep_create, expanded, now} = cursor
  expanded

def now_of(+cursor: B.Cursor) -> U32:
  B.Cursor{pane, filter, dialog, keep_create, expanded, now} = cursor
  now

def with_now(+now: U32, +cursor: B.Cursor) -> B.Cursor:
  B.Cursor{pane, filter, dialog, keep_create, expanded, previous} = cursor
  B.Cursor{pane, filter, dialog, keep_create, expanded, now}

def with_dialog(+dialog: B.Dialog, +cursor: B.Cursor) -> B.Cursor:
  B.Cursor{pane, filter, previous, keep_create, expanded, now} = cursor
  B.Cursor{pane, filter, dialog, keep_create, expanded, now}

def with_filter(+filter: B.Filter, +cursor: B.Cursor) -> B.Cursor:
  B.Cursor{pane, previous, dialog, keep_create, expanded, now} = cursor
  B.Cursor{pane, filter, dialog, keep_create, expanded, now}

def with_pane(+pane: B.Pane, +cursor: B.Cursor) -> B.Cursor:
  B.Cursor{previous, filter, dialog, keep_create, expanded, now} = cursor
  B.Cursor{pane, filter, B.NoDialog{}, keep_create, False{}, now}

def retained_string(+keep: Bool, +value: String, +rest: +List<String>) -> +List<String>:
  match keep:
    case True{}: value <> rest
    case False{}: rest

def without(+values: +List<String>, +value: String) -> +List<String>:
  match values:
    case Nil{}: Nil{}
    case Con{+head, rest}:
      retained_string(Bool.not(String.eq(head, value)), head, without(rest, value))

def is_bool(+value: J.Json) -> Bool:
  match value:
    case J.Boolean{value}: True{}
    case _: False{}

def is_array(+value: J.Json) -> Bool:
  match value:
    case J.Array{values}: True{}
    case _: False{}

def toggled(+present: Bool, +value: String, +values: +List<String>) -> +List<String>:
  match present:
    case True{}: without(values, value)
    case False{}: value <> values

def toggle(+values: +List<String>, +value: String) -> +List<String>:
  toggled(Schema.contains(values, value), value, values)

def with_view(+view: String, +filter: B.Filter) -> B.Filter:
  B.Filter{old, search, status, priority, date, assignee, creator, project, label} = filter
  B.Filter{view, search, status, priority, date, assignee, creator, project, label}

def with_search(+search: String, +filter: B.Filter) -> B.Filter:
  B.Filter{view, old, status, priority, date, assignee, creator, project, label} = filter
  B.Filter{view, search, status, priority, date, assignee, creator, project, label}

def change_filter(+category: String, +value: String, +filter: B.Filter) -> B.Filter:
  match category filter:
    case "status" B.Filter{view, search, status, priority, date, assignee, creator, project, label}:
      B.Filter{view, search, toggle(status, value), priority, date, assignee, creator, project, label}
    case "priority" B.Filter{view, search, status, priority, date, assignee, creator, project, label}:
      B.Filter{view, search, status, toggle(priority, value), date, assignee, creator, project, label}
    case "date" B.Filter{view, search, status, priority, date, assignee, creator, project, label}:
      B.Filter{view, search, status, priority, toggle(date, value), assignee, creator, project, label}
    case "assignee" B.Filter{view, search, status, priority, date, assignee, creator, project, label}:
      B.Filter{view, search, status, priority, date, toggle(assignee, value), creator, project, label}
    case "creator" B.Filter{view, search, status, priority, date, assignee, creator, project, label}:
      B.Filter{view, search, status, priority, date, assignee, toggle(creator, value), project, label}
    case "project" B.Filter{view, search, status, priority, date, assignee, creator, project, label}:
      B.Filter{view, search, status, priority, date, assignee, creator, toggle(project, value), label}
    case "label" B.Filter{view, search, status, priority, date, assignee, creator, project, label}:
      B.Filter{view, search, status, priority, date, assignee, creator, project, toggle(label, value)}
    case _ filter: filter

def cleared_filter(+filter: B.Filter) -> B.Filter:
  B.Filter{view, search, status, priority, date, assignee, creator, project, label} = filter
  with_search(search, with_view(view, B.empty_filter()))

def navigate(+event: B.Navigation, +cursor: B.Cursor) -> B.Cursor:
  match event:
    case B.ShowPane{pane}: with_pane(pane, cursor)
    case B.ChangeView{view}: with_filter(with_view(view, filter_of(cursor)), cursor)
    case B.Search{query}: with_filter(with_search(query, filter_of(cursor)), cursor)
    case B.ToggleFilter{category, value}: with_filter(change_filter(category, value, filter_of(cursor)), cursor)
    case B.ClearFilters{}: with_filter(cleared_filter(filter_of(cursor)), cursor)
    case B.OpenDialog{dialog}: with_dialog(dialog, cursor)
    case B.KeepCreating{enabled}:
      B.Cursor{pane, filter, dialog, keep_create, expanded, now} = cursor
      B.Cursor{pane, filter, dialog, enabled, expanded, now}
    case B.ExpandDialog{expanded}:
      B.Cursor{pane, filter, dialog, keep_create, previous, now} = cursor
      B.Cursor{pane, filter, dialog, keep_create, expanded, now}

def dialog_json(+dialog: B.Dialog) -> J.Json:
  match dialog:
    case B.NoDialog{}: J.Object{[J.Field{"kind", J.Text{"none"}}]}
    case B.CreateDialog{stage, assisted}: J.Object{[J.Field{"kind", J.Text{"create"}}, J.Field{"status", J.Text{B.stage_name(stage)}}, J.Field{"assisted", J.Boolean{assisted}}]}
    case B.CardDialog{id}: J.Object{[J.Field{"kind", J.Text{"card"}}, J.Field{"id", J.nat(id)}]}
    case B.ArchiveDialog{}: J.Object{[J.Field{"kind", J.Text{"archive"}}]}
    case B.AgentDialog{id}: J.Object{[J.Field{"kind", J.Text{"agent"}}, J.Field{"id", J.Text{C.id_text(id)}}]}
    case B.ProjectDialog{id}: J.Object{[J.Field{"kind", J.Text{"project"}}, J.Field{"id", J.Text{C.id_text(id)}}]}
    case B.DeleteDialog{id}: J.Object{[J.Field{"kind", J.Text{"delete"}}, J.Field{"id", J.nat(id)}]}
    case B.ContextDialog{id}: J.Object{[J.Field{"kind", J.Text{"context"}}, J.Field{"id", J.nat(id)}]}

def dialog(+kind: String, +value: J.Json) -> B.Dialog:
  match kind:
    case "create": B.CreateDialog{B.stage(J.text(J.get(value, "status"))), J.boolean(J.get(value, "assisted"))}
    case "card": B.CardDialog{C.number(J.get(value, "id"))}
    case "archive": B.ArchiveDialog{}
    case "agent": B.AgentDialog{C.optional_id(J.text(J.get(value, "id")))}
    case "project": B.ProjectDialog{C.optional_id(J.text(J.get(value, "id")))}
    case "delete": B.DeleteDialog{C.number(J.get(value, "id"))}
    case "context": B.ContextDialog{C.number(J.get(value, "id"))}
    case _: B.NoDialog{}

def filter_json(+filter: B.Filter) -> J.Json:
  B.Filter{view, search, status, priority, date, assignee, creator, project, label} = filter
  J.Object{[J.Field{"view", J.Text{view}}, J.Field{"search", J.Text{search}}, J.Field{"status", J.Array{C.strings_json(status)}},
    J.Field{"priority", J.Array{C.strings_json(priority)}}, J.Field{"date", J.Array{C.strings_json(date)}}, J.Field{"assignee", J.Array{C.strings_json(assignee)}},
    J.Field{"creator", J.Array{C.strings_json(creator)}}, J.Field{"project", J.Array{C.strings_json(project)}}, J.Field{"label", J.Array{C.strings_json(label)}}]}

def filter(+value: J.Json) -> B.Filter:
  B.Filter{J.text(J.get(value, "view")), J.text(J.get(value, "search")), C.strings(J.items(J.get(value, "status"))),
    C.strings(J.items(J.get(value, "priority"))), C.strings(J.items(J.get(value, "date"))), C.strings(J.items(J.get(value, "assignee"))),
    C.strings(J.items(J.get(value, "creator"))), C.strings(J.items(J.get(value, "project"))), C.strings(J.items(J.get(value, "label")))}

def cursor_json(+cursor: B.Cursor) -> J.Json:
  B.Cursor{pane, filter, dialog, keep_create, expanded, now} = cursor
  J.Object{[J.Field{"pane", J.Text{pane_name(pane)}}, J.Field{"filter", filter_json(filter)}, J.Field{"dialog", dialog_json(dialog)},
    J.Field{"keep_create", J.Boolean{keep_create}}, J.Field{"expanded", J.Boolean{expanded}}, J.Field{"now", C.word_json(now)}]}

def cursor(+value: J.Json, +now: U32) -> B.Cursor:
  match value:
    case J.Null{}: with_now(now, B.cursor())
    case _: B.Cursor{pane(J.text(J.get(value, "pane"))), filter(J.get(value, "filter")), dialog(J.text(J.get(J.get(value, "dialog"), "kind")), J.get(value, "dialog")),
      J.boolean(J.get(value, "keep_create")), J.boolean(J.get(value, "expanded")), now}

def event_json(+event: B.Navigation) -> J.Json:
  match event:
    case B.ShowPane{pane}: J.Object{[J.Field{"action", J.Text{"pane"}}, J.Field{"pane", J.Text{pane_name(pane)}}]}
    case B.ChangeView{view}: J.Object{[J.Field{"action", J.Text{"view"}}, J.Field{"view", J.Text{view}}]}
    case B.Search{query}: J.Object{[J.Field{"action", J.Text{"search"}}, J.Field{"query", J.Text{query}}]}
    case B.ToggleFilter{category, value}: J.Object{[J.Field{"action", J.Text{"filter"}}, J.Field{"category", J.Text{category}}, J.Field{"value", J.Text{value}}]}
    case B.ClearFilters{}: J.Object{[J.Field{"action", J.Text{"clear"}}]}
    case B.OpenDialog{dialog}: J.Object{[J.Field{"action", J.Text{"dialog"}}, J.Field{"dialog", dialog_json(dialog)}]}
    case B.KeepCreating{enabled}: J.Object{[J.Field{"action", J.Text{"keep_create"}}, J.Field{"enabled", J.Boolean{enabled}}]}
    case B.ExpandDialog{expanded}: J.Object{[J.Field{"action", J.Text{"expand"}}, J.Field{"expanded", J.Boolean{expanded}}]}

def event(+action: String, +value: J.Json) -> B.Navigation:
  match action:
    case "pane": B.ShowPane{pane(J.text(J.get(value, "pane")))}
    case "view": B.ChangeView{J.text(J.get(value, "view"))}
    case "search": B.Search{J.text(J.get(value, "query"))}
    case "filter": B.ToggleFilter{J.text(J.get(value, "category")), J.text(J.get(value, "value"))}
    case "dialog": B.OpenDialog{dialog(J.text(J.get(J.get(value, "dialog"), "kind")), J.get(value, "dialog"))}
    case "keep_create": B.KeepCreating{J.boolean(J.get(value, "enabled"))}
    case "expand": B.ExpandDialog{J.boolean(J.get(value, "expanded"))}
    case _: B.ClearFilters{}

def exact(+value: J.Json, +names: +List<String>) -> Bool:
  match value:
    case J.Object{+fields}: Nat.is_eq(List.length(&2, J.Field, fields), List.length(&2, String, names)) && Schema.keywords(fields, names, Nil{})
    case _: False{}

def valid_dialog(+kind: String, +value: J.Json) -> Bool:
  match kind:
    case "none": exact(value, ["kind"])
    case "archive": exact(value, ["kind"])
    case "create": exact(value, ["kind", "status", "assisted"]) && is_bool(J.get(value, "assisted")) &&
      Schema.contains(["backlog", "todo", "in_progress", "in_review", "done", "blocked"], J.text(J.get(value, "status")))
    case "card": exact(value, ["kind", "id"]) && Schema.valid(C.integer_schema(), J.get(value, "id"))
    case "delete": exact(value, ["kind", "id"]) && Schema.valid(C.integer_schema(), J.get(value, "id"))
    case "context": exact(value, ["kind", "id"]) && Schema.valid(C.integer_schema(), J.get(value, "id"))
    case "agent": exact(value, ["kind", "id"]) && J.is_text(J.get(value, "id")) && C.valid_id(J.text(J.get(value, "id")))
    case "project": exact(value, ["kind", "id"]) && J.is_text(J.get(value, "id")) && C.valid_id(J.text(J.get(value, "id")))
    case _: False{}

def valid_values(+values: +List<J.Json>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{J.Text{value}, rest}: B.limited(value, 1024n) && valid_values(rest)
    case _: False{}

def valid_filter_list(+value: J.Json) -> Bool:
  is_array(value) && Nat.is_le(List.length(&2, J.Json, J.items(value)), 32n) && valid_values(J.items(value))

def filter_lists(+names: +List<String>, +value: J.Json) -> Bool:
  match names:
    case Nil{}: True{}
    case Con{name, rest}: valid_filter_list(J.get(value, name)) && filter_lists(rest, value)

def valid_filter(+value: J.Json) -> Bool:
  exact(value, ["view", "search", "status", "priority", "date", "assignee", "creator", "project", "label"]) &&
    Schema.contains(["all", "assigned", "unassigned", "working"], J.text(J.get(value, "view"))) &&
    J.is_text(J.get(value, "search")) && B.limited(J.text(J.get(value, "search")), 1024n) &&
    filter_lists(["status", "priority", "date", "assignee", "creator", "project", "label"], value)

def valid_cursor(+value: J.Json) -> Bool:
  exact(value, ["pane", "filter", "dialog", "keep_create", "expanded", "now"]) &&
    Schema.contains(["threads", "board", "agents", "projects"], J.text(J.get(value, "pane"))) && valid_filter(J.get(value, "filter")) &&
    valid_dialog(J.text(J.get(J.get(value, "dialog"), "kind")), J.get(value, "dialog")) &&
    is_bool(J.get(value, "keep_create")) && is_bool(J.get(value, "expanded")) && C.valid_clock(J.get(value, "now"))

def valid_event(+action: String, +value: J.Json) -> Bool:
  match action:
    case "pane": exact(value, ["action", "pane"]) && Schema.contains(["threads", "board", "agents", "projects"], J.text(J.get(value, "pane")))
    case "view": exact(value, ["action", "view"]) && Schema.contains(["all", "assigned", "unassigned", "working"], J.text(J.get(value, "view")))
    case "search": exact(value, ["action", "query"]) && J.is_text(J.get(value, "query")) && B.limited(J.text(J.get(value, "query")), 1024n)
    case "filter": exact(value, ["action", "category", "value"]) && J.is_text(J.get(value, "value")) && B.limited(J.text(J.get(value, "value")), 1024n) &&
      Schema.contains(["status", "priority", "date", "assignee", "creator", "project", "label"], J.text(J.get(value, "category")))
    case "dialog": exact(value, ["action", "dialog"]) && valid_dialog(J.text(J.get(J.get(value, "dialog"), "kind")), J.get(value, "dialog"))
    case "keep_create": exact(value, ["action", "enabled"]) && is_bool(J.get(value, "enabled"))
    case "expand": exact(value, ["action", "expanded"]) && is_bool(J.get(value, "expanded"))
    case "clear": exact(value, ["action"])
    case _: False{}

def after_create(+keep: Bool, +stage: B.Stage, +assisted: Bool) -> B.Dialog:
  match keep:
    case True{}: B.CreateDialog{stage, assisted}
    case False{}: B.NoDialog{}

def after_command(+command: B.Command, +reply: J.Json, +cursor: B.Cursor) -> B.Cursor:
  match command:
    case B.Create{draft, now, assist, profile}:
      with_dialog(after_create(keep_of(cursor), B.card_stage(draft), assist), cursor)
    case B.Update{id, revision, patch, now}: with_dialog(B.NoDialog{}, cursor)
    case B.Archive{id, revision, True{}, now}: with_dialog(B.NoDialog{}, cursor)
    case B.Delete{id, revision}: with_dialog(B.NoDialog{}, cursor)
    case B.SaveAgent{id, revision, agent}: with_pane(B.AgentsPane{}, cursor)
    case B.DeleteAgent{id, revision}: with_pane(B.AgentsPane{}, cursor)
    case _: cursor

def dismiss_context(+cursor: B.Cursor) -> B.Cursor:
  match cursor:
    case B.Cursor{pane, filter, B.ContextDialog{id}, keep_create, expanded, now}:
      B.Cursor{pane, filter, B.NoDialog{}, keep_create, expanded, now}
    case other: other

def submitted(+ok: Bool, +command: B.Command, +reply: J.Json, +cursor: B.Cursor) -> B.Cursor:
  match ok:
    case True{}: after_command(command, reply, dismiss_context(cursor))
    case False{}: cursor

def project_submitted(+ok: Bool, +cursor: B.Cursor) -> B.Cursor:
  match ok:
    case True{}: with_pane(B.ProjectsPane{}, cursor)
    case False{}: cursor
