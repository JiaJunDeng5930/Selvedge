import Base
import ./MODEL.bend as W
import ../../harness/DOMAIN.bend as D
import ../../harness/workspace/WORKSPACE.bend as Workspace
import ../../bendlib/json.bend as J
import ../../bendlib/association-map.bend as Finite
import ../../harness/transport/wire-shape.bend as Shape

type EntryKind is Data:
  Write{}
  WorkspaceWrite{}
  ListKind{}
  ReadKind{}
  RetryArchiveKind{}

type Spec is Data:
  Spec{name: String, description: String, kind: EntryKind, schema: J.Json}

def create_schema(settings: J.Json) -> J.Json:
  D.command_schema([J.Field{"profile", D.string_schema("Configured model profile")},
    J.Field{"reasoning", D.string_schema("Reasoning effort")},
    J.Field{"message", D.content_schema("Initial user request")}, J.Field{"images", D.images_schema()}, J.Field{"settings", settings}],
    [J.Text{"profile"}])

def workspace_schema(settings: J.Json) -> J.Json:
  D.command_schema([J.Field{"backend", J.Object{[J.Field{"type", J.Text{"string"}}, J.Field{"enum", J.Array{[J.Text{"local"}, J.Text{"tencent_cvm"}]}}]}},
    J.Field{"profile", D.string_schema("Configured model profile")}, J.Field{"reasoning", D.string_schema("Reasoning effort")},
    J.Field{"message", D.content_schema("Initial user request")}, J.Field{"images", D.images_schema()}, J.Field{"settings", settings},
    J.Field{"work_id", D.task_id_schema()}], [J.Text{"backend"}, J.Text{"profile"}])

def backend_name(value: String) -> W.Backend:
  match value:
    case "tencent_cvm": W.TencentCvm{}
    case _: W.Local{}

def backend(value: J.Json) -> W.Backend:
  backend_name(J.text(value))

def task_schema() -> J.Json:
  D.command_schema([J.Field{"task_id", D.task_id_schema()}], [J.Text{"task_id"}])

def specs(+settings: J.Json) -> +List<Spec>:
  [Spec{"create_workspace_task", "Create a task after preparing a local worktree or a cloud environment.", WorkspaceWrite{}, workspace_schema(settings)},
   Spec{"create_worktree_task", "Create a task in a managed Git worktree before starting its execution.", Write{}, create_schema(settings)},
   Spec{"list_worktrees", "List managed task worktrees and their current operation state.", ListKind{}, D.command_schema(Nil{}, Nil{})},
   Spec{"read_worktree", "Read the managed worktree associated with one task.", ReadKind{}, task_schema()},
   Spec{"retry_worktree_archive", "Retry archiving a task worktree after an external archive failure.", RetryArchiveKind{}, task_schema()}]

def number(value: J.Json) -> Nat:
  J.natural_or(J.natural(value), 0n)

# The command boundary already admitted the declared schema.
def additional_constraints(kind: EntryKind, body: J.Json) -> Bool:
  True{}

def construct(kind: EntryKind, +body: J.Json) -> W.Command:
  match kind:
    case WorkspaceWrite{}: W.CreateWorkspace{backend(J.get(body, "backend")), J.text(J.get(body, "profile")),
      J.text_or(J.get(body, "reasoning"), "default"), D.user_content(J.get(body, "message"), J.get(body, "images")), J.get(body, "settings"), J.natural(J.get(body, "work_id"))}
    case RetryArchiveKind{}: W.RetryArchive{number(J.get(body, "task_id"))}
    case _: W.Create{J.text(J.get(body, "profile")), J.text_or(J.get(body, "reasoning"), "default"),
      D.user_content(J.get(body, "message"), J.get(body, "images")), J.get(body, "settings")}

def query(kind: EntryKind, body: J.Json) -> W.Query:
  match kind:
    case ReadKind{}: W.Read{number(J.get(body, "task_id"))}
    case _: W.ListWorktrees{}

def command(operation: String, fields: +List<J.Field>) -> J.Json:
  J.Object{J.Field{"op", J.Text{operation}} <> fields}

def settings_field(settings: J.Json, fields: +List<J.Field>) -> +List<J.Field>:
  match settings:
    case J.Null{}: fields
    case value: J.Field{"settings", value} <> fields

def work_field(work: Maybe<&2, Nat>) -> +List<J.Field>:
  match work:
    case None{}: Nil{}
    case Some{id}: [J.Field{"work_id", J.nat(id)}]

def command_json(value: W.Command) -> J.Json:
  match value:
    case W.Create{profile, reasoning, message, settings}:
      command("create_worktree_task", settings_field(settings, [J.Field{"profile", J.Text{profile}},
        J.Field{"reasoning", J.Text{reasoning}}, J.Field{"message", D.content_json(message)}]))
    case W.CreateWorkspace{backend, profile, reasoning, message, settings, work}:
      command("create_workspace_task", settings_field(settings, List.append(&2, J.Field,
        [J.Field{"backend", J.Text{W.backend_name(backend)}}, J.Field{"profile", J.Text{profile}},
          J.Field{"reasoning", J.Text{reasoning}}, J.Field{"message", D.content_json(message)}], work_field(work))))
    case W.RetryArchive{task_id}: command("retry_worktree_archive", [J.Field{"task_id", J.nat(task_id)}])

def query_json(value: W.Query) -> J.Json:
  match value:
    case W.ListWorktrees{}: command("list_worktrees", Nil{})
    case W.Read{task_id}: command("read_worktree", [J.Field{"task_id", J.nat(task_id)}])

def effect_json(value: W.Effect) -> J.Json:
  match value:
    case W.CreateTree{task_id, source_root, workspace, backend}:
      J.Object{[J.Field{"kind", J.Text{"worktree_create"}}, J.Field{"task_id", J.nat(task_id)},
        J.Field{"backend", J.Text{W.backend_name(backend)}}, J.Field{"source_root", J.Text{source_root}}, J.Field{"workspace", D.workspace_json(workspace)}]}
    case W.ArchiveTree{task_id, source_root, root, backend}:
      J.Object{[J.Field{"kind", J.Text{"worktree_archive"}}, J.Field{"task_id", J.nat(task_id)},
        J.Field{"backend", J.Text{W.backend_name(backend)}}, J.Field{"source_root", J.Text{source_root}}, J.Field{"root", J.Text{root}}]}

def optional_root(value: J.Json) -> Maybe<&2, String>:
  match value:
    case J.Text{root}: Some{root}
    case _: None{}

def root_shape(value: J.Json) -> Bool:
  match value:
    case J.Null{}: True{}
    case J.Text{root}: Workspace.valid_path(root)
    case _: False{}

def text_array(values: +List<J.Json>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{value, rest}: J.is_text(value) && text_array(rest)

def roots_shape(value: J.Json) -> Bool:
  match value:
    case J.Array{values}: text_array(values)
    case _: False{}

def workspace(value: J.Json) -> D.Workspace:
  Workspace.read_workspace(value, D.Workspace{Nil{}, None{}})

def workspace_shape(+value: J.Json) -> Bool:
  Shape.object_keys(value, ["roots", "primary_root"]) && roots_shape(J.get(value, "roots")) &&
    J.is_text(J.get(value, "primary_root")) && Workspace.valid(workspace(value))

def guidance_shape(+value: J.Json) -> Bool:
  match value:
    case J.Null{}: True{}
    case value:
      Shape.object_keys(value, ["workspace", "path", "revision", "instructions"]) &&
        J.is_text(J.get(value, "workspace")) && J.is_text(J.get(value, "path")) && J.is_text(J.get(value, "revision")) &&
        J.is_text(J.get(value, "instructions"))

def guidance(value: J.Json, workspace: D.Workspace) -> D.ProjectContext:
  Workspace.read_guidance(value, workspace, D.NoProject{})

def created_success(+body: J.Json) -> Bool:
  Shape.object_keys(body, ["kind", "task_id", "ok", "root", "workspace", "guidance"]) &&
    J.is_text(J.get(body, "root")) && Workspace.valid_path(J.text(J.get(body, "root"))) &&
    workspace_shape(J.get(body, "workspace")) && guidance_shape(J.get(body, "guidance")) &&
    Workspace.valid_guidance(guidance(J.get(body, "guidance"), workspace(J.get(body, "workspace")))) &&
    Workspace.guidance_member(Workspace.primary(workspace(J.get(body, "workspace"))),
      guidance(J.get(body, "guidance"), workspace(J.get(body, "workspace"))))

def created_failure(+body: J.Json) -> Bool:
  Shape.object_keys(body, ["kind", "task_id", "ok", "root", "message"]) &&
    root_shape(J.get(body, "root")) && J.is_text(J.get(body, "message"))

def created_valid(ok: Bool, body: J.Json) -> Bool:
  match ok:
    case True{}: created_success(body)
    case False{}: created_failure(body)

def archived_valid(ok: Bool, +body: J.Json) -> Bool:
  match ok:
    case True{}: Shape.object_keys(body, ["kind", "task_id", "ok", "root"]) &&
      J.is_text(J.get(body, "root")) && Workspace.valid_path(J.text(J.get(body, "root")))
    case False{}: Shape.object_keys(body, ["kind", "task_id", "ok", "message"]) && J.is_text(J.get(body, "message"))

def checked(valid: Bool, value: W.Completion) -> Result<&2, &2, String, W.Completion>:
  match valid:
    case True{}: Done{value}
    case False{}: Fail{"Malformed worktree completion"}

def envelope(kind: String, +body: J.Json) -> Bool:
  J.same(J.get(body, "kind"), J.Text{kind}) && Shape.is_natural(J.get(body, "task_id")) &&
    Shape.is_bool(J.get(body, "ok"))

type CompletionName is Data:
  CompletionNameWorktreeCreated{}
  CompletionNameWorktreeArchived{}
  CompletionNameOther{}

def completion_discriminant(+value: String) -> CompletionName:
  Bool.pick(CompletionName, String.eq(value, "worktree_created"), CompletionNameWorktreeCreated{},
    Bool.pick(CompletionName, String.eq(value, "worktree_archived"), CompletionNameWorktreeArchived{},
    CompletionNameOther{}))

def completion_classified(kind: CompletionName, +body: J.Json) -> Result<&2, &2, String, W.Completion>:
  match kind:
    case CompletionNameWorktreeCreated{}: checked(envelope("worktree_created", body) && created_valid(J.boolean(J.get(body, "ok")), body),
      W.Created{number(J.get(body, "task_id")), J.boolean(J.get(body, "ok")), optional_root(J.get(body, "root")),
        workspace(J.get(body, "workspace")), guidance(J.get(body, "guidance"), workspace(J.get(body, "workspace"))),
        J.text(J.get(body, "message"))})
    case CompletionNameWorktreeArchived{}: checked(envelope("worktree_archived", body) && archived_valid(J.boolean(J.get(body, "ok")), body),
      W.ArchivedResult{number(J.get(body, "task_id")), J.boolean(J.get(body, "ok")),
        J.text(J.get(body, "root")), J.text(J.get(body, "message"))})
    case CompletionNameOther{}: Fail{"Unknown worktree completion"}

def completion(kind: String, +body: J.Json) -> Result<&2, &2, String, W.Completion>:
  completion_classified(completion_discriminant(kind), body)

def status_name(value: W.Status) -> String:
  match value:
    case W.Creating{}: "creating"
    case W.CreatingArchived{}: "creating_archived"
    case W.Ready{}: "ready"
    case W.CreateFailed{}: "create_failed"
    case W.Archiving{}: "archiving"
    case W.Archived{}: "archived"
    case W.ArchiveFailed{}: "archive_failed"

def entry_json(task_id: Nat, value: W.Worktree) -> J.Json:
  W.Worktree{source_root, root, status, message, target_primary, backend} = value
  J.Object{[J.Field{"task_id", J.nat(task_id)}, J.Field{"backend", J.Text{W.backend_name(backend)}}, J.Field{"source_root", J.Text{source_root}},
    J.Field{"root", D.optional_string(root)}, J.Field{"status", J.Text{status_name(status)}},
    J.Field{"message", J.Text{message}}, J.Field{"target_primary", J.Text{target_primary}}]}

def entry_items(values: +List<Finite.Entry(W.Worktree)>) -> +List<J.Json>:
  match values:
    case Nil{}: Nil{}
    case Con{(task_id, value), rest}: entry_json(task_id, value) <> entry_items(rest)

def found_entry(task_id: Nat, value: Maybe<&2, W.Worktree>) -> J.Json:
  match value:
    case None{}: D.failure("not_found", "Task worktree does not exist.")
    case Some{value}: D.success(entry_json(task_id, value))

def state_json(state: W.State) -> J.Json:
  J.Object{[J.Field{"worktrees", J.Array{entry_items(W.entries(state))}}]}

def query_reply(value: W.Query, state: W.State) -> J.Json:
  match value:
    case W.ListWorktrees{}: D.success(state_json(state))
    case W.Read{+task_id}: found_entry(task_id, W.lookup(task_id, state))
