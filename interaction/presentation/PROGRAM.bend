import Base
import ../submission/FIELDS.bend as OperationParameters
import ../IDENTITY.bend as Identity
import ../submission/MODEL.bend as Receipt
import ../../harness/MODEL.bend as M
import ../../harness/COMMANDS.bend as Commands
import ../../features/board/MODEL.bend as B
import ../../harness/workspace/PROJECTS.bend as Projects
import ../../harness/features/MODEL.bend as F
import ../../harness/reasoning/MODEL.bend as Reasoning
import ../../harness/DOMAIN.bend as D
import ../../features/board/STATE.bend as Board
import ../../features/board/filter.bend as BoardFilter
import ../../bendlib/json.bend as J
import ../../harness/transport/schema.bend as Schema
import ../STATE.bend as Core
import ../session/MODEL.bend as E
import ../INPUT.bend as U
import ./MODEL.bend as V
import ./COMPOSITION.bend as Composition
import ../conversation/MODEL.bend as Conversation
import ../submission/field-options.bend as FieldOptions
import ../services/MODEL.bend as Services
import ../conversation/CODE.bend as Code
import ../conversation/OUTPUT.bend as Live
import ../services/CONTEXT.bend as Context
import ../../bendlib/association-map.bend as Finite
import ./SURFACE.bend as SurfaceTypes
import ../TYPES.bend as InteractionTypes
import ./VIEW.bend as View

def node_key(node: SurfaceTypes.Node) -> String:
  SurfaceTypes.Node{key, semantic, label, role, meaning, children} = node
  Identity.encode(key)

def node_role(node: SurfaceTypes.Node) -> SurfaceTypes.Role:
  SurfaceTypes.Node{key, semantic, label, role, meaning, children} = node
  role

def node_label(node: SurfaceTypes.Node) -> String:
  SurfaceTypes.Node{key, semantic, label, role, meaning, children} = node
  label

# Content and interaction are two projections of one observation. Keys in the
# interaction tree identify the actual controls, fields and owning regions.
# Intrinsic declarations in content are never a second activation authority.

def receipt_notice(receipt: Receipt.Receipt) -> SurfaceTypes.Node:
  Receipt.Receipt{ticket, origin, code, message} = receipt
  SurfaceTypes.Node{Identity.Entity{Identity.Place{"@browser"}, "receipt", Nat.show(ticket)}, "operation-receipt", "Operation failed", SurfaceTypes.Alert{}, SurfaceTypes.ReadOnly{code ++ ": " ++ message}, Nil{}}

def receipt_join(nested_result: (Bool & +List<SurfaceTypes.Node>), following_result: (Bool & +List<SurfaceTypes.Node>), original_rest: +List<SurfaceTypes.Node>, key: Identity.Key, semantic: String, label: String, role: SurfaceTypes.Role, meaning: SurfaceTypes.Meaning) -> (Bool & +List<SurfaceTypes.Node>):
  (found, nested) = nested_result
  match found:
    case True{}:
      (True{}, SurfaceTypes.Node{key, semantic, label, role, meaning, nested} <> original_rest)
    case False{}:
      (following_found, following) = following_result
      (following_found, SurfaceTypes.Node{key, semantic, label, role, meaning, nested} <> following)

def receipt_search(nodes: +List<SurfaceTypes.Node>, +receipt: Receipt.Receipt) -> (Bool & +List<SurfaceTypes.Node>):
  match nodes:
    case Nil{}: (False{}, Nil{})
    case Con{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.PageContext{conversation}, children}, rest}:
      (True{}, SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.PageContext{conversation}, receipt_notice(receipt) <> children} <> rest)
    case Con{SurfaceTypes.Node{key, semantic, label, role, meaning, children}, +rest}:
      receipt_join(receipt_search(children, receipt), receipt_search(rest, receipt), rest, key, semantic, label, role, meaning)

def receipt_surface(result: (Bool & +List<SurfaceTypes.Node>), content: InteractionTypes.Scene, overlays: +List<SurfaceTypes.Node>, scope: Maybe<&2, String>) -> SurfaceTypes.Surface:
  (found, nodes) = result
  SurfaceTypes.Surface{content, nodes, overlays, scope}

def receipt_surface_search(surface: SurfaceTypes.Surface, value: Receipt.Receipt) -> SurfaceTypes.Surface:
  SurfaceTypes.Surface{content, base, overlays, scope} = surface
  receipt_surface(receipt_search(base, value), content, overlays, scope)

def with_receipt(surface: SurfaceTypes.Surface, receipt: Maybe<&2, Receipt.Receipt>) -> SurfaceTypes.Surface:
  match receipt:
    case None{}: surface
    case Some{value}: receipt_surface_search(surface, value)

def region(parent: Identity.Key, +identity: String, label: String, role: SurfaceTypes.Role, children: +List<SurfaceTypes.Node>) -> SurfaceTypes.Node:
  SurfaceTypes.Node{Identity.Part{parent, identity}, identity, label, role, SurfaceTypes.Region{}, children}

def dialog_actions(parent: Identity.Key, children: +List<SurfaceTypes.Node>) -> SurfaceTypes.Node:
  region(parent, "@actions", "Actions", SurfaceTypes.DialogActions{}, children)

def action_role(prominence: V.Prominence) -> SurfaceTypes.Role:
  match prominence:
    case V.Primary{}: SurfaceTypes.PrimaryButton{}
    case V.Destructive{}: SurfaceTypes.DestructiveButton{}
    case V.Secondary{}: SurfaceTypes.Button{}

def action(parent: Identity.Key, control: InteractionTypes.Control) -> SurfaceTypes.Node:
  InteractionTypes.Control{+identity, label, prominence, input, availability} = control
  SurfaceTypes.Node{Identity.Part{parent, identity}, identity, label, action_role(prominence), SurfaceTypes.Activate{input, availability}, Nil{}}

def replace_role(node: SurfaceTypes.Node, role: SurfaceTypes.Role) -> SurfaceTypes.Node:
  SurfaceTypes.Node{key, semantic, label, old_role, meaning, children} = node
  SurfaceTypes.Node{key, semantic, label, role, meaning, children}

def selected_node(selected: Bool, node: SurfaceTypes.Node) -> SurfaceTypes.Node:
  match selected:
    case True{}: replace_role(node, SurfaceTypes.SelectedButton{})
    case False{}: node

def declared_panel_toggle_layers(parent: Identity.Key, control: InteractionTypes.Control, panel: U.Panel, layers: +List<E.Layer>) -> SurfaceTypes.Node:
  InteractionTypes.Control{+identity, label, prominence, input, availability} = control
  SurfaceTypes.Node{Identity.Part{parent, identity}, identity, label, action_role(prominence),
    SurfaceTypes.PanelToggle{E.panel_present(layers, E.panel_target(panel)), input, availability}, Nil{}}

def declared_panel_toggle(parent: Identity.Key, control: InteractionTypes.Control, panel: U.Panel, state: InteractionTypes.State) -> SurfaceTypes.Node:
  +observed_application = Core.application(state)
  +observed_session = E.session(observed_application)
  layers = E.layers(observed_session)
  declared_panel_toggle_layers(parent, control, panel, layers)

def declared(parent: Identity.Key, +declaration: V.ControlDeclaration, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  match declaration:
    case V.ControlDeclaration{identity, label, prominence, U.Activate{U.TogglePanel{+panel, trigger}}, availability}:
      declared_panel_toggle(parent, Core.control(state,
        V.ControlDeclaration{identity, label, prominence, U.Activate{U.TogglePanel{panel, trigger}}, availability}), panel, state)
    case other: action(parent, Core.control(state, other))

def controls(values: +List<V.ControlDeclaration>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{control, rest}: declared(parent, control, state) <> controls(rest, parent, state)

def availability(enabled: Bool) -> V.Availability:
  match enabled:
    case True{}: V.Available{}
    case False{}: V.Unavailable{"Unavailable in the current state"}

def product_action(parent: Identity.Key, identity: String, label: String, input: InteractionTypes.Input, enabled: Bool) -> SurfaceTypes.Node:
  action(parent, InteractionTypes.Control{identity, label, V.Secondary{}, input, availability(enabled)})

def user_action(parent: Identity.Key, identity: String, label: String, input: U.Input, enabled: Bool, state: InteractionTypes.State) -> SurfaceTypes.Node:
  declared(parent, V.ControlDeclaration{identity, label, V.Secondary{}, input, availability(enabled)}, state)

def more(+subject: U.Subject, parent: Identity.Key, state: InteractionTypes.State) -> SurfaceTypes.Node:
  declared(parent, View.control("more/" ++ U.subject_key(subject), "More actions",
    U.OpenPanel{U.ObjectActions{subject}, "more/" ++ U.subject_key(subject)}), state)

def task_entries(entries: +List<V.TaskEntry>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match entries:
    case Nil{}: Nil{}
    case Con{V.TaskEntry{+id, title, +status, +selected, open}, rest}:
      SurfaceTypes.Node{Identity.Entity{parent, "task", Nat.show(id)}, "task-row", "", SurfaceTypes.Section{}, SurfaceTypes.TaskRow{id, status, selected},
        [selected_node(selected, declared(Identity.Entity{parent, "task", Nat.show(id)}, open, state)),
         SurfaceTypes.Node{Identity.Part{Identity.Entity{parent, "task", Nat.show(id)}, "status"}, "task-status", "Task status", SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{View.task_status_label(status)}, Nil{}}]} <> task_entries(rest, parent, state)

def disclosed_tasks(expanded: Bool, tasks: +List<V.TaskEntry>, parent: Identity.Key, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match expanded:
    case False{}: Nil{}
    case True{}: task_entries(tasks, parent, state)

def project_entries(entries: +List<V.ProjectEntry>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match entries:
    case Nil{}: Nil{}
    case Con{V.ProjectEntry{+id, name, workspace, +selected, +expanded, tasks, open, create, toggle, more}, rest}:
      SurfaceTypes.Node{Identity.Entity{parent, "project", Nat.show(id)}, "project-group", "", SurfaceTypes.Section{}, SurfaceTypes.ProjectGroup{id, selected, expanded},
        region(Identity.Entity{parent, "project", Nat.show(id)}, "actions", "", SurfaceTypes.Section{},
          [declared(Identity.Entity{parent, "project", Nat.show(id)}, toggle, state), selected_node(selected, declared(Identity.Entity{parent, "project", Nat.show(id)}, open, state)),
           declared(Identity.Entity{parent, "project", Nat.show(id)}, create, state), declared(Identity.Entity{parent, "project", Nat.show(id)}, more, state)]) <>
        disclosed_tasks(expanded, tasks, Identity.Entity{parent, "project", Nat.show(id)}, state)} <> project_entries(rest, parent, state)

def same_route(left: U.Route, right: U.Route) -> Bool:
  match left right:
    case U.Start{} U.Start{}: True{}
    case U.Conversation{left} U.Conversation{right}: Nat.is_eq(left, right)
    case U.ProjectHome{left} U.ProjectHome{right}: Nat.is_eq(left, right)
    case U.ProjectCollection{} U.ProjectCollection{}: True{}
    case U.TaskBoard{} U.TaskBoard{}: True{}
    case U.AgentCollection{} U.AgentCollection{}: True{}
    case _ _: False{}

def is_start_route(route: U.Route) -> Bool:
  match route:
    case U.Start{}: True{}
    case _: False{}

def navigation_action_selected(+route: U.Route, input: U.Input) -> Bool:
  match input:
    case U.Activate{U.Navigate{target}}: same_route(route, target)
    case U.Activate{U.BeginTask{None{}}}: is_start_route(route)
    case _: False{}

def selected_declaration(+route: U.Route, +parent: Identity.Key, declaration: V.ControlDeclaration, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  V.ControlDeclaration{identity, label, prominence, +input, availability} = declaration
  selected_node(navigation_action_selected(route, input), declared(parent, declaration, state))

def selected_controls(+route: U.Route, +values: +List<V.ControlDeclaration>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: selected_declaration(route, parent, value, state) <> selected_controls(route, rest, parent, state)

def navigation_contents(expanded: Bool, +route: U.Route, create: V.ControlDeclaration, destinations: +List<V.ControlDeclaration>, projects: +List<V.ProjectEntry>, tasks: +List<V.TaskEntry>, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match expanded:
    case False{}: Nil{}
    case True{}:
      selected_declaration(route, Identity.Place{"/navigation"}, create, state) <> List.append(&2, SurfaceTypes.Node, selected_controls(route, destinations, Identity.Place{"/navigation"}, state),
        List.append(&2, SurfaceTypes.Node, project_entries(projects, Identity.Place{"/navigation"}, state), task_entries(tasks, Identity.Place{"/navigation"}, state)))

def navigation(view: V.Navigation, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  V.Navigation{expanded, create, destinations, projects, tasks, toggle} = view
  +observed_application = Core.application(state)
  +observed_session = E.session(observed_application)
  +route = E.route(observed_session)
  navigation = E.navigation(observed_session)
  +header: SurfaceTypes.Node = SurfaceTypes.Node{Identity.Part{Identity.Place{"/navigation"}, "header"}, "navigation-header", "Selvedge", SurfaceTypes.NavigationHeader{}, SurfaceTypes.Region{},
    [declared(Identity.Place{"/navigation"}, toggle, state)]}
  SurfaceTypes.Node{Identity.Place{"/navigation"}, "navigation", "Navigation", SurfaceTypes.Navigation{}, SurfaceTypes.Region{}, header <>
    navigation_contents(expanded, route, create, destinations, projects, tasks, state)}

def observed_field(found: Maybe<&2, U.Draft>, field: OperationParameters.Field, world: M.World()) -> OperationParameters.Observed:
  match found:
    case None{}: OperationParameters.NotApplicable{}
    case Some{U.Draft{revision, body, feedback, directory_entry}}: OperationParameters.observed(body, field, world)

def field_value(state: InteractionTypes.State, editor: U.Editor, field: OperationParameters.Field) -> OperationParameters.Observed:
  +observed_application = Core.application(state)
  world = E.program(observed_application)
  +observed_session = E.session(observed_application)
  drafts = E.drafts(observed_session)
  observed_field(E.find_draft(drafts, editor), field, world)

def attachment_nodes(files: +List<B.Attachment>, +editor: U.Editor, +parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match files:
    case Nil{}: Nil{}
    case Con{B.Attachment{+id, +name, mime, path, bytes}, rest}:
      SurfaceTypes.Node{Identity.Entity{parent, "attachment", id}, id, name, SurfaceTypes.Section{}, SurfaceTypes.Region{}, [product_action(Identity.Entity{parent, "attachment", id}, "preview", "Preview " ++ name, InteractionTypes.ServiceInput{Services.OpenPreview{B.Attachment{id, name, mime, path, bytes}, Identity.encode(Identity.Part{Identity.Entity{parent, "attachment", id}, "preview"})}}, True{}),
         product_action(Identity.Entity{parent, "attachment", id}, "remove", "Remove " ++ name, InteractionTypes.RemoveAttachment{editor, id}, True{})]} <> attachment_nodes(rest, editor, parent)

def transfer_controls(+ticket: Nat, value: Services.Transfer, +parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match value:
    case Services.Uploading{editor, file}:
      [product_action(parent, "cancel-upload/" ++ Nat.show(ticket), "Cancel upload", InteractionTypes.ServiceInput{Services.CancelUpload{ticket}}, True{})]
    case Services.UploadFailed{editor, file, reason}:
      [product_action(parent, "retry-upload/" ++ Nat.show(ticket), "Retry upload", InteractionTypes.ServiceInput{Services.RetryUpload{ticket}}, True{}),
       product_action(parent, "cancel-upload/" ++ Nat.show(ticket), "Remove failed upload", InteractionTypes.ServiceInput{Services.CancelUpload{ticket}}, True{})]

def transfer_node(owned: Bool, ticket: Nat, value: Services.Transfer, parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match owned:
    case False{}: Nil{}
    case True{}: transfer_controls(ticket, value, parent)

def transfer_nodes(values: +List<Finite.Entry(Services.Transfer)>, +editor: U.Editor, +parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{(ticket, +value), rest}:
      List.append(&2, SurfaceTypes.Node, transfer_node(U.same_editor(Services.transfer_editor(value), editor), ticket, value, parent), transfer_nodes(rest, editor, parent))

def files_observed(value: OperationParameters.Observed) -> +List<B.Attachment>:
  match value:
    case OperationParameters.AttachmentsValue{files}: files
    case _: Nil{}

def file_field(+editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  +observed_services = Core.services(state)
  +access = Services.access(observed_services)
  +transfers = Services.transfers(observed_services)
  SurfaceTypes.Node{Identity.Part{parent, "add"}, "attachment/add", "Add attachment", SurfaceTypes.Field{}, SurfaceTypes.ReceiveFile{editor, Services.connected(access)}, Nil{}} <>
    List.append(&2, SurfaceTypes.Node, attachment_nodes(files_observed(field_value(state, editor, OperationParameters.CardAttachments{})), editor, parent), transfer_nodes(transfers, editor, parent))

def workspace_value(value: Context.WorkspaceValue) -> D.Workspace:
  match value:
    case Context.InheritedWorkspace{value}: value
    case Context.EnteredWorkspace{value}: value

def context_workspace(value: Context.Preview) -> Maybe<&2, D.Workspace>:
  match value:
    case Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}: Some{workspace_value(workspace)}
    case _: None{}

def workspace_observed(value: OperationParameters.Observed) -> Maybe<&2, D.Workspace>:
  match value:
    case OperationParameters.WorkspaceValue{workspace}: Some{workspace}
    case OperationParameters.ContextValue{value}: context_workspace(value)
    case _: None{}

def directory_primary_controls(primary: Bool, control: V.ControlDeclaration, parent: Identity.Key, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match primary:
    case True{}: [SurfaceTypes.Node{Identity.Part{parent, "primary"}, "directory/primary", "Primary working directory", SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{"Primary working directory"}, Nil{}}]
    case False{}: [declared(parent, control, state)]

def directory_node(value: V.WorkspaceRoot, parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  V.WorkspaceRoot{+path, +primary, choose, remove} = value
  +key : Identity.Key = Identity.Entity{parent, "directory", path}
  SurfaceTypes.Node{key, "directory/" ++ path, path, SurfaceTypes.Content{}, SurfaceTypes.DirectoryRow{path, primary},
    List.append(&2, SurfaceTypes.Node, directory_primary_controls(primary, choose, key, state), [declared(key, remove, state)])}

def directory_root_nodes(roots: +List<V.WorkspaceRoot>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match roots:
    case Nil{}: Nil{}
    case Con{root, rest}: directory_node(root, parent, state) <> directory_root_nodes(rest, parent, state)

def directory_controls(controls: V.WorkspaceControls, parent: Identity.Key, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  V.WorkspaceControls{identity, roots, inherit} = controls
  directory_root_nodes(roots, parent, state)

def directory_values(found: Maybe<&2, D.Workspace>, +editor: U.Editor, parent: Identity.Key, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match found:
    case None{}: Nil{}
    case Some{workspace}: directory_controls(View.workspace_controls(workspace, editor, None{}), parent, state)

def draft_directory(found: Maybe<&2, U.Draft>) -> String:
  match found:
    case None{}: ""
    case Some{draft}: U.directory_entry(draft)

def pending_directory(state: InteractionTypes.State, editor: U.Editor) -> String:
  +observed_application = Core.application(state)
  +observed_session = E.session(observed_application)
  drafts = E.drafts(observed_session)
  draft_directory(E.find_draft(drafts, editor))

def directory_can_confirm(found: Maybe<&2, U.Draft>) -> Bool:
  match found:
    case None{}: False{}
    case Some{draft}: U.can_confirm_directory(draft)

def directory_ready(state: InteractionTypes.State, editor: U.Editor) -> Bool:
  +observed_application = Core.application(state)
  +observed_session = E.session(observed_application)
  drafts = E.drafts(observed_session)
  directory_can_confirm(E.find_draft(drafts, editor))

def directory_confirm(+editor: U.Editor, parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  user_action(parent, "workspace/confirm", "Add folder", U.EditDraft{editor, U.ConfirmDirectory{}}, directory_ready(state, editor), state)

def browse_workspace(workspace: Maybe<&2, D.Workspace>) -> String:
  match workspace:
    case None{}: ""
    case Some{D.Workspace{roots, primary}}:
      match primary:
        case Some{path}: path
        case None{}: ""

def browse_start_empty(empty: Bool, entered: String, +editor: U.Editor, state: InteractionTypes.State) -> String:
  match empty:
    case False{}: entered
    case True{}: browse_workspace(workspace_observed(field_value(state, editor, OperationParameters.WorkspaceDirectories{})))

def browse_start(+editor: U.Editor, +state: InteractionTypes.State) -> String:
  +entered = pending_directory(state, editor)
  browse_start_empty(String.is_empty(entered), entered, editor, state)

def application_of(state: InteractionTypes.State) -> E.Application:
  application = Core.application(state)
  application

def directory_browse(+editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  product_action(parent, "workspace/browse", "Browse folders",
    InteractionTypes.ServiceInput{Services.OpenDirectoryPicker{editor, browse_start(editor, state), Identity.encode(Identity.Part{parent, "workspace/browse"})}},
    Core.accepts_directory(editor, application_of(state)))

def field_children(field: OperationParameters.Field, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match field:
    case OperationParameters.CardAttachments{}: file_field(editor, parent, state)
    case OperationParameters.WorkspaceDirectories{}:
      SurfaceTypes.Node{Identity.Part{parent, "instruction"}, "workspace/instruction", "Enter a directory path to add it. Listed directories define the workspace; choose the primary working directory.", SurfaceTypes.Content{},
        SurfaceTypes.ReadOnly{"Enter a directory path to add it. Listed directories define the workspace; choose the primary working directory."}, Nil{}} <>
      SurfaceTypes.Node{Identity.Part{parent, "add"}, "workspace/add", "Add working directory", SurfaceTypes.Field{}, SurfaceTypes.EnterDirectory{editor, pending_directory(state, editor)}, Nil{}} <>
      directory_confirm(editor, parent, state) <>
      directory_browse(editor, parent, state) <>
        directory_values(workspace_observed(field_value(state, editor, OperationParameters.WorkspaceDirectories{})), editor, parent, state)
    case _: Nil{}

def policy_entry(policy: Reasoning.Policy) -> OperationParameters.Entry:
  match policy:
    case Reasoning.Fixed{}: OperationParameters.SingleLine{}
    case _: OperationParameters.DisplayOnly{}

def profile_effort_entry(profile: D.Profile) -> OperationParameters.Entry:
  match profile:
    case D.Profile{key, provider, name, Reasoning.Fixed{}, Some{options}}: OperationParameters.Choice{}
    case D.Profile{key, provider, name, policy, options}: policy_entry(policy)

def effort_entry(profile: Maybe<&2, D.Profile>) -> OperationParameters.Entry:
  match profile:
    case None{}: OperationParameters.DisplayOnly{}
    case Some{profile}: profile_effort_entry(profile)

def field_entry(field: OperationParameters.Field, entry: OperationParameters.Entry, value: OperationParameters.Observed, world: M.World()) -> OperationParameters.Entry:
  match field value:
    case OperationParameters.ReasoningEffort{} OperationParameters.ModelValue{profile, effort}: effort_entry(D.find_profile(Commands.configured(Commands.settings(world)), profile))
    case _ _: entry

def actual_entry(field: OperationParameters.Field, entry: OperationParameters.Entry, value: OperationParameters.Observed, state: InteractionTypes.State) -> OperationParameters.Entry:
  +observed_application = Core.application(state)
  world = E.program(observed_application)
  field_entry(field, entry, value, world)

def entry_choices(entry: OperationParameters.Entry, field: OperationParameters.Field, value: OperationParameters.Observed, groups: +List<V.InputGroup>) -> +List<OperationParameters.ChoiceValue>:
  match entry:
    case OperationParameters.Choice{}: FieldOptions.choices(field, value, groups)
    case OperationParameters.MultipleChoices{}: FieldOptions.choices(field, value, groups)
    case _: Nil{}

def field_node(+field: OperationParameters.FieldScene, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State, groups: +List<V.InputGroup>) -> SurfaceTypes.Node:
  OperationParameters.FieldScene{+field, label, entry} = field
  +observed = field_value(state, editor, field)
  +resolved_entry = actual_entry(field, entry, observed, state)
  SurfaceTypes.Node{Identity.Part{parent, OperationParameters.key(field)}, OperationParameters.key(field), label, SurfaceTypes.Field{}, SurfaceTypes.Edit{editor, field, resolved_entry, observed, entry_choices(resolved_entry, field, observed, groups)}, field_children(field, editor, Identity.Part{parent, OperationParameters.key(field)}, state)}

def configuration(body: U.Body) -> Maybe<&2, Context.Configuration>:
  match body:
    case U.NewTask{message, profile, effort, config}: Some{config}
    case U.Agent{id, revision, name, profile, effort, instructions, config, concurrency}: Some{config}
    case U.Fork{task, count, messages, config}: Some{config}
    case _: None{}

def draft_configuration(draft: Maybe<&2, U.Draft>) -> Maybe<&2, Context.Configuration>:
  match draft:
    case None{}: None{}
    case Some{U.Draft{revision, body, feedback, directory_entry}}: configuration(body)

def reset_fields(field: OperationParameters.Field, workspace: Maybe<&2, D.Workspace>, sandbox: Maybe<&2, D.Sandbox>, approval: Maybe<&2, Context.ApprovalChoice>) -> Maybe<&2, Context.Change>:
  match field workspace sandbox approval:
    case OperationParameters.WorkspaceDirectories{} Some{value} _ _: Some{Context.UseDefaultWorkspace{}}
    case OperationParameters.SandboxMode{} _ Some{value} _: Some{Context.UseDefaultSandbox{}}
    case OperationParameters.ApprovalPolicy{} _ _ Some{value}: Some{Context.UseDefaultApproval{}}
    case _ _ _ _: None{}

def reset_change(config: Context.Configuration, field: OperationParameters.Field) -> Maybe<&2, Context.Change>:
  Context.Configuration{origin, workspace, sandbox, approval} = config
  reset_fields(field, workspace, sandbox, approval)

def reset_control(change: Maybe<&2, Context.Change>, editor: U.Editor, field: OperationParameters.Field, label: String, parent: Identity.Key, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match change:
    case None{}: Nil{}
    case Some{change}: [user_action(parent, "default/" ++ OperationParameters.key(field), "Use defaults for " ++ label, U.EditDraft{editor, U.ConfigureContext{change}}, True{}, state)]

def configured_reset(config: Maybe<&2, Context.Configuration>, editor: U.Editor, +field: OperationParameters.Field, label: String, parent: Identity.Key, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match config:
    case None{}: Nil{}
    case Some{value}: reset_control(reset_change(value, field), editor, field, label, parent, state)

def field_resets(+field: OperationParameters.FieldScene, +editor: U.Editor, parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  OperationParameters.FieldScene{+field, label, entry} = field
  +observed_application = Core.application(state)
  +observed_session = E.session(observed_application)
  +drafts = E.drafts(observed_session)
  configured_reset(draft_configuration(E.find_draft(drafts, editor)), editor, field, label, parent, state)

def fields(values: +List<OperationParameters.FieldScene>, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State, +groups: +List<V.InputGroup>) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{+field, rest}: field_node(field, editor, parent, state, groups) <> List.append(&2, SurfaceTypes.Node, field_resets(field, editor, parent, state), fields(rest, editor, parent, state, groups))

def sections(values: +List<OperationParameters.Section>, +editor: U.Editor, +parent: Identity.Key, +ordinal: Nat, +state: InteractionTypes.State, +groups: +List<V.InputGroup>) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{OperationParameters.Section{title, entries}, rest}:
      SurfaceTypes.Node{Identity.Entity{parent, "section", Nat.show(ordinal)}, "section/" ++ Nat.show(ordinal), title, SurfaceTypes.Section{}, SurfaceTypes.Region{}, fields(entries, editor, Identity.Entity{parent, "section", Nat.show(ordinal)}, state, groups)} <>
        sections(rest, editor, parent, (ordinal + 1n : Nat), state, groups)

def feedback_nodes(+parent: Identity.Key, feedback: U.Feedback) -> +List<SurfaceTypes.Node>:
  match feedback:
    case U.Rejected{revision, +reason}: [SurfaceTypes.Node{Identity.Part{parent, "feedback"}, "submission-feedback", "Submission failed", SurfaceTypes.Alert{}, SurfaceTypes.ReadOnly{reason}, Nil{}}]
    case _: Nil{}

def editor(view: Maybe<&2, V.EditorScene>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match view:
    case None{}: Nil{}
    case Some{V.EditorScene{identity, revision, groups, structure, submit, feedback, pending}}:
      List.append(&2, SurfaceTypes.Node, sections(structure, identity, parent, 0n, state, groups), List.append(&2, SurfaceTypes.Node, feedback_nodes(parent, feedback), [dialog_actions(parent, [declared(parent, submit, state)])]))

def composer_control_resolved(subject: V.ComposerSubject, parent: Identity.Key, control: InteractionTypes.Control) -> SurfaceTypes.Node:
  InteractionTypes.Control{+identity, label, prominence, input, availability} = control
  SurfaceTypes.Node{Identity.Part{parent, identity}, identity, label, action_role(prominence), SurfaceTypes.ComposerAction{subject, input, availability}, Nil{}}

def composer_control(parent: Identity.Key, value: V.ComposerControl, state: InteractionTypes.State) -> SurfaceTypes.Node:
  V.ComposerControl{subject, declaration} = value
  composer_control_resolved(subject, parent, Core.control(state, declaration))

def composer_controls(values: +List<V.ComposerControl>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{control, rest}: composer_control(parent, control, state) <> composer_controls(rest, parent, state)

def composer_choices(footer: +List<V.ComposerControl>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match footer:
    case Nil{}: Nil{}
    case Con{first, rest}:
      [region(parent, "choices", "Choices", SurfaceTypes.Toolbar{}, composer_controls(first <> rest, parent, state))]

def composer_actions(footer: +List<V.ComposerControl>, submit: V.ControlDeclaration, +parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  region(parent, "actions", "Actions", SurfaceTypes.ComposerActions{},
    List.append(&2, SurfaceTypes.Node, composer_choices(footer, parent, state), [declared(parent, submit, state)]))

def expected_composer_choices(footer: +List<V.ComposerControl>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match footer:
    case Nil{}: Nil{}
    case Con{first, rest}:
      [SurfaceTypes.Node{Identity.Part{parent, "choices"}, "choices", "Choices", SurfaceTypes.Toolbar{}, SurfaceTypes.Region{}, composer_controls(first <> rest, parent, state)}]

def expected_composer_actions(footer: +List<V.ComposerControl>, submit: V.ControlDeclaration, +parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  SurfaceTypes.Node{Identity.Part{parent, "actions"}, "actions", "Actions", SurfaceTypes.ComposerActions{}, SurfaceTypes.Region{},
    List.append(&2, SurfaceTypes.Node, expected_composer_choices(footer, parent, state), [declared(parent, submit, state)])}

def expected_composer(view: Maybe<&2, V.ComposerScene>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match view:
    case None{}: Nil{}
    case Some{V.ComposerScene{+identity, revision, message, footer, context, submit, feedback, pending}}:
      +key : Identity.Key = Identity.Entity{parent, "composer", U.editor_key(identity)}
      [SurfaceTypes.Node{key, "composer/" ++ U.editor_key(identity), "Message", SurfaceTypes.Composer{}, SurfaceTypes.Region{},
        field_node(OperationParameters.FieldScene{OperationParameters.MessageText{}, "Message", OperationParameters.Multiline{}}, identity, key, state, Nil{}) <>
          List.append(&2, SurfaceTypes.Node, feedback_nodes(key, feedback), [expected_composer_actions(footer, submit, key, state)])}]

def composer(view: Maybe<&2, V.ComposerScene>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match view:
    case None{}: Nil{}
    case Some{V.ComposerScene{+identity, revision, message, footer, context, submit, feedback, pending}}:
      +composer_key : Identity.Key = Identity.Entity{parent, "composer", U.editor_key(identity)}
      [SurfaceTypes.Node{Identity.Entity{parent, "composer", U.editor_key(identity)}, "composer/" ++ U.editor_key(identity), "Message", SurfaceTypes.Composer{}, SurfaceTypes.Region{}, field_node(OperationParameters.FieldScene{OperationParameters.MessageText{}, "Message", OperationParameters.Multiline{}}, identity, composer_key, state, Nil{}) <>
          List.append(&2, SurfaceTypes.Node, feedback_nodes(composer_key, feedback), [composer_actions(footer, submit, composer_key, state)])}]

def approval_fact(+parent: Identity.Key, +key: String, +label: String, text: String) -> SurfaceTypes.Node:
  SurfaceTypes.Node{Identity.Part{parent, key}, key, label, SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{text}, Nil{}}

def approval_serialized(result: Result<&2, &2, String, String>) -> String:
  match result:
    case Done{text}: text
    case Fail{reason}: "Serialization failed: " ++ reason

def approval_value(value: J.Json) -> String:
  match value:
    case J.Text{text}: text
    case other: approval_serialized(J.show(other))

def approval_argument_label(name: String) -> String:
  OperationParameters.label(name)

def approval_fields(fields: List<&2, J.Field>, +index: Nat, +parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match fields:
    case Nil{}: Nil{}
    case Con{J.Field{name, value}, rest}:
      approval_fact(parent, "argument/" ++ Nat.show(index), approval_argument_label(name), approval_value(value)) <>
        approval_fields(rest, (index + 1n : Nat), parent)

def approval_arguments(arguments: J.Json, parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match arguments:
    case J.Object{fields}: approval_fields(fields, 0n, parent)
    case other: [approval_fact(parent, "arguments", "Arguments", approval_value(other))]

def approval_directory(context: D.TaskContext, parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  D.TaskContext{D.Workspace{roots, primary}, sandbox, approval, project} = context
  match primary:
    case None{}: Nil{}
    case Some{path}: [approval_fact(parent, "default-directory", "Default working directory", path)]

def approval_metadata(call: D.Call, context: D.TaskContext, +parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  D.Call{id, name, arguments} = call
  approval_fact(parent, "tool", "Tool", name) <>
    List.append(&2, SurfaceTypes.Node, approval_arguments(arguments, parent), approval_directory(context, parent))

def approval_reviewer(reviewer: D.Profile, parent: Identity.Key) -> SurfaceTypes.Node:
  D.Profile{key, provider, name, reasoning, options} = reviewer
  approval_fact(parent, "reviewer", "Reviewer model", name)

def approvals(values: +List<Conversation.DecisionRequest>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Conversation.HumanDecision{+operation, call, context, approve, deny, +enabled}, rest}:
      SurfaceTypes.Node{Identity.Entity{parent, "approval", Nat.show(operation)}, "approval/" ++ Nat.show(operation), "Approval required", SurfaceTypes.Approval{}, SurfaceTypes.Region{}, List.append(&2, SurfaceTypes.Node, approval_metadata(call, context, Identity.Entity{parent, "approval", Nat.show(operation)}),
          [user_action(Identity.Entity{parent, "approval", Nat.show(operation)}, "approve", "Approve once", approve, enabled, state),
           user_action(Identity.Entity{parent, "approval", Nat.show(operation)}, "deny", "Deny", deny, enabled, state)])} <> approvals(rest, parent, state)
    case Con{Conversation.AutomaticDecision{+operation, call, context, reviewer}, rest}:
      SurfaceTypes.Node{Identity.Entity{parent, "approval", Nat.show(operation)}, "approval/" ++ Nat.show(operation), "Automatic review", SurfaceTypes.Approval{}, SurfaceTypes.Region{}, List.append(&2, SurfaceTypes.Node, approval_metadata(call, context, Identity.Entity{parent, "approval", Nat.show(operation)}),
          [approval_reviewer(reviewer, Identity.Entity{parent, "approval", Nat.show(operation)})])} <> approvals(rest, parent, state)

def disclosure_label(expanded: Bool) -> String:
  match expanded:
    case True{}: "Collapse activity"
    case False{}: "Expand activity"

def disclosure_input(expanded: Bool, expand: U.Input, collapse: U.Input) -> U.Input:
  match expanded:
    case True{}: collapse
    case False{}: expand

def application(state: InteractionTypes.State) -> E.Application:
  +application = Core.application(state)
  application

def code_region(value: Code.Scene, +parent: Identity.Key) -> SurfaceTypes.Node:
  Code.Scene{+identity, literal, wrap, copy, +enabled, controls} = value
  SurfaceTypes.Node{Code.ui_identity(identity), Code.key(identity), "Code", SurfaceTypes.CodeBlock{}, SurfaceTypes.CodeFacts{Code.Scene{identity, literal, wrap, copy, enabled, controls}},
    [product_action(Code.ui_identity(identity), "copy", "Copy code", InteractionTypes.ApplicationInput{E.ContentInput{identity, Code.Copy{}}}, enabled),
     product_action(Code.ui_identity(identity), "wrap", "Toggle word wrap", InteractionTypes.ApplicationInput{E.ContentInput{identity, Code.ToggleWrap{}}}, True{})]}

def code_node(owned: Bool, value: Code.Scene, parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match owned:
    case False{}: Nil{}
    case True{}: [code_region(value, parent)]

def code_nodes(values: +List<Code.Scene>, +source: Code.Source, +parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Code.Scene{+identity, literal, wrap, copy, enabled, controls}, rest}:
      List.append(&2, SurfaceTypes.Node, code_node(Code.belongs(identity, source), Code.Scene{identity, literal, wrap, copy, enabled, controls}, parent), code_nodes(rest, source, parent))

def speaker_role(speaker: Conversation.Speaker) -> SurfaceTypes.Role:
  match speaker:
    case Conversation.UserSpeech{}: SurfaceTypes.UserMessage{}
    case Conversation.AssistantSpeech{}: SurfaceTypes.AssistantMessage{}

def groups(values: +List<Conversation.VisibleGroup>, +task: Nat, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Conversation.VisibleSpeech{+id, speaker, text, source}, rest}:
      SurfaceTypes.Node{Identity.Entity{parent, "message", Nat.show(id)}, "message/" ++ Nat.show(id), "Message", speaker_role(speaker), SurfaceTypes.RichText{Code.Message{task, id}, text}, code_nodes(Core.code_scenes(application(state)), Code.Message{task, id}, Identity.Entity{parent, "message", Nat.show(id)})} <> groups(rest, task, parent, state)
    case Con{Conversation.VisibleActivity{+id, attention, +expanded, summary, audit, expand, collapse}, rest}:
      SurfaceTypes.Node{Identity.Entity{parent, "activity", Nat.show(id)}, "activity/" ++ Nat.show(id), summary, SurfaceTypes.Activity{}, SurfaceTypes.ActivityContent{expanded, audit},
        [user_action(Identity.Entity{parent, "activity", Nat.show(id)}, "disclosure", disclosure_label(expanded), disclosure_input(expanded, expand, collapse), True{}, state)]} <> groups(rest, task, parent, state)

def latest(input: Maybe<&2, U.Input>, parent: Identity.Key, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match input:
    case None{}: Nil{}
    case Some{input}: [user_action(parent, "latest", "Return to latest", input, True{}, state)]

def operations(values: +List<Conversation.LiveOperation>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Conversation.LiveOperation{id, body, cancel, enabled}, rest}:
      user_action(parent, "cancel/" ++ Nat.show(id), "Cancel operation", cancel, enabled, state) <> operations(rest, parent, state)

def approval_queue(values: +List<Conversation.DecisionRequest>, +parent: Identity.Key, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case other: [region(parent, "pending-decisions", "Pending approvals", SurfaceTypes.ApprovalQueue{}, approvals(other, Identity.Part{parent, "pending-decisions"}, state))]

def live_parts(parts: +List<Live.Part>, +task: Nat, +operation: Nat, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match parts:
    case Nil{}: Nil{}
    case Con{Live.Part{+index, text}, rest}:
      SurfaceTypes.Node{Identity.Entity{parent, "part", Nat.show(index)}, "stream/part/" ++ Nat.show(index), "Agent output", SurfaceTypes.Content{}, SurfaceTypes.RichText{Code.StreamingPart{task, operation, index}, text}, code_nodes(Core.code_scenes(application(state)), Code.StreamingPart{task, operation, index}, Identity.Entity{parent, "part", Nat.show(index)})} <> live_parts(rest, task, operation, parent, state)

def live_outputs(outputs: +List<Live.Output>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match outputs:
    case Nil{}: Nil{}
    case Con{Live.Output{task, +operation, parts}, rest}:
      SurfaceTypes.Node{Identity.Entity{parent, "stream", Nat.show(operation)}, "stream/" ++ Nat.show(operation), "Agent output", SurfaceTypes.Content{}, SurfaceTypes.Region{}, live_parts(parts, task, operation, Identity.Entity{parent, "stream", Nat.show(operation)}, state)} <> live_outputs(rest, parent, state)

def project(view: V.ProjectScene, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  V.ProjectScene{id, name, workspace, guidance, tasks, actions} = view
  region(parent, "heading", name, SurfaceTypes.Heading{}, controls(actions, Identity.Part{parent, "heading"}, state)) <> task_entries(tasks, parent, state)

def projects(values: +List<V.ProjectScene>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  +observed_application = Core.application(state)
  +world = E.program(observed_application)
  +session = E.session(observed_application)
  +route = E.route(session)
  +navigation = E.navigation(session)
  project_entries(View.project_entries(Projects.entries(Projects.registry(F.State(), world)), Commands.entries(world), route, View.active_project(route, session, world), navigation), parent, state)

def project_collection_entries(values: +List<V.ProjectScene>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}:
      [SurfaceTypes.Node{Identity.Part{Identity.Part{parent, "projects"}, "empty"}, "projects/empty", "", SurfaceTypes.Content{},
        SurfaceTypes.ReadOnly{"Create a project to group tasks and choose default working folders."}, Nil{}}]
    case Con{first, rest}: projects(Con{first, rest}, parent, state)

def placement_target(stage: B.Stage, before: Maybe<&2, Nat>) -> String:
  match before:
    case None{}: Identity.encode(Identity.Part{Identity.Place{"/main"}, B.stage_name(stage)})
    case Some{id}: Identity.encode(Identity.Entity{Identity.Part{Identity.Place{"/main"}, B.stage_name(stage)}, "card", Nat.show(id)})

def placement_control(target: String, control: InteractionTypes.Control) -> SurfaceTypes.Placement:
  InteractionTypes.Control{identity, label, prominence, input, availability} = control
  SurfaceTypes.Placement{target, label, input, availability}

def placements_at(values: +List<V.MoveDestination>, +id: Nat, +revision: Nat, +now: U32, +world: M.World(), +state: InteractionTypes.State) -> +List<SurfaceTypes.Placement>:
  match values:
    case Nil{}: Nil{}
    case Con{V.MoveDestination{+stage, +before, label, availability}, rest}:
      placement_control(placement_target(stage, before), Core.control(state, View.board_control("move", label, B.MoveCard{id, revision, stage, before, now}, world))) <> placements_at(rest, id, revision, now, world, state)

def placements(values: +List<V.MoveDestination>, id: Nat, revision: Nat, +state: InteractionTypes.State) -> +List<SurfaceTypes.Placement>:
  +observed_application = Core.application(state)
  world = E.program(observed_application)
  +observed_session = E.session(observed_application)
  +now = E.now(observed_session)
  placements_at(values, id, revision, now, world, state)

def archive_placement(archived: Bool, id: Nat, revision: Nat, +state: InteractionTypes.State) -> +List<SurfaceTypes.Placement>:
  match archived:
    case True{}: Nil{}
    case False{}:
      +observed_application = Core.application(state)
      +world = E.program(observed_application)
      +observed_session = E.session(observed_application)
      +now = E.now(observed_session)
      [placement_control(Identity.encode(Identity.Part{Identity.Place{"/main"}, "archive-destination"}), Core.control(state, View.board_control("archive", "归档任务", B.Archive{id, revision, True{}, now}, world)))]

def card(view: V.CardScene, +parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  V.CardScene{+id, +value, open, actions, linked, destinations, candidates} = view
  +observed_application = Core.application(state)
  world = E.program(observed_application)
  +observed_session = E.session(observed_application)
  +now = E.now(observed_session)
  +key : Identity.Key = Identity.Entity{parent, "card", Nat.show(id)}
  +face : V.CardFace = View.card_face(id, value, now, world)
  +offered : +List<SurfaceTypes.Placement> = List.append(&2, SurfaceTypes.Placement, placements(destinations, id, B.revision(value), state), archive_placement(B.archived(value), id, B.revision(value), state))
  SurfaceTypes.Node{key, "card/" ++ Nat.show(id), B.title(B.draft(value)), SurfaceTypes.Card{}, SurfaceTypes.CardContent{face},
    [declared(key, open, state), more(U.CardSubject{id}, key, state),
      SurfaceTypes.Node{Identity.part(key, "movement"), "card/" ++ Nat.show(id) ++ "/movement", "Move " ++ B.title(B.draft(value)), SurfaceTypes.Field{}, SurfaceTypes.MovableCard{offered, face}, Nil{}}]}

def cards(values: +List<V.CardScene>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: card(value, parent, state) <> cards(rest, parent, state)

def board_lane(+stage: B.Stage, +parent: Identity.Key, count: Nat, +children: +List<SurfaceTypes.Node>) -> SurfaceTypes.Node:
  +key : Identity.Key = Identity.Part{parent, B.stage_name(stage)}
  SurfaceTypes.Node{key, B.stage_name(stage), B.stage_label(stage), SurfaceTypes.Section{}, SurfaceTypes.BoardLane{stage, count}, children}

def columns(values: +List<V.BoardColumn>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{V.BoardColumn{+stage, +entries, create}, rest}:
      +key : Identity.Key = Identity.Part{parent, B.stage_name(stage)}
      +lane_children: +List<SurfaceTypes.Node> = List.append(&2, SurfaceTypes.Node, [declared(key, create, state)], cards(entries, key, state))
      +lane: SurfaceTypes.Node = board_lane(stage, parent, List.length(&2, V.CardScene, entries), lane_children)
      lane <> columns(rest, parent, state)

def project_fact(+key: Identity.Key, +label: String, text: String) -> SurfaceTypes.Node:
  SurfaceTypes.Node{key, Identity.encode(key), label, SurfaceTypes.Content{}, SurfaceTypes.Fact{text}, Nil{}}

def agent_observation(+id: Nat, +value: B.AgentProfile, edit: V.ControlDeclaration, +parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  +name = B.agent_name(value)
  profile = B.agent_profile(value)
  reasoning = B.agent_reasoning(value)
  instructions = B.agent_instructions(value)
  concurrency = B.agent_concurrency(value)
  +observed_application = Core.application(state)
  +world = E.program(observed_application)
  +key : Identity.Key = Identity.Entity{parent, "agent", Nat.show(id)}
  SurfaceTypes.Node{Identity.Entity{parent, "agent", Nat.show(id)}, "agent/" ++ Nat.show(id), name, SurfaceTypes.Section{}, SurfaceTypes.Region{}, [project_fact(Identity.Part{key, "profile"}, "模型", profile), project_fact(Identity.Part{key, "reasoning"}, "推理", reasoning),
     project_fact(Identity.Part{key, "instructions"}, "指令", instructions), project_fact(Identity.Part{key, "concurrency"}, "并发上限", Nat.show(concurrency)),
     project_fact(Identity.Part{key, "active"}, "工作中", Nat.show(Board.active_for(B.cards(Board.registry(world)), B.Agent{id}, world))),
     declared(key, edit, state), more(U.AgentSubject{id}, key, state)]}

def agents(values: +List<V.AgentScene>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{V.AgentScene{+id, value, edit, remove}, rest}:
      agent_observation(id, value, edit, parent, state) <> agents(rest, parent, state)

def page_region(+parent: Identity.Key, +part: Composition.Region, position: Composition.Position, children: +List<SurfaceTypes.Node>) -> SurfaceTypes.Node:
  +name = Composition.region_name(part)
  SurfaceTypes.Node{Identity.Part{Identity.Part{parent, "region"}, name}, name, "", SurfaceTypes.Section{}, SurfaceTypes.PageRegion{part, position}, children}

def page_composer(+input: Maybe<&2, V.ComposerScene>, +parent: Identity.Key, +owner: Identity.Key, +state: InteractionTypes.State, +position: Composition.Position) -> +List<SurfaceTypes.Node>:
  match input:
    case None{}: Nil{}
    case Some{scene}: [page_region(parent, Composition.ComposerInput{}, position, composer(Some{scene}, owner, state))]

def page_latest(+input: Maybe<&2, U.Input>, +parent: Identity.Key, +owner: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match input:
    case None{}: Nil{}
    case Some{value}: [page_region(parent, Composition.LatestAction{}, Composition.DockPosition{}, latest(Some{value}, owner, state))]

def page_approvals(+values: +List<Conversation.DecisionRequest>, +parent: Identity.Key, +owner: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{first, rest}: [page_region(parent, Composition.ApprovalDecisions{}, Composition.DockPosition{}, approval_queue(first <> rest, owner, state))]

def task_page_fields(+id: Nat, +title: String, page_timeline: Conversation.Timeline, previews: +List<Live.Output>, input: Maybe<&2, V.ComposerScene>, actions: V.TaskActions, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  Conversation.Timeline{task, generation, groups_value, live, decisions, reading, return_latest} = page_timeline
  V.TaskActions{detail, overflow} = actions
  +owner : Identity.Key = Identity.Entity{parent, "task", Nat.show(id)}
  page_region(parent, Composition.ConversationTitle{}, Composition.HeadingPosition{},
    [region(owner, "heading", title, SurfaceTypes.Heading{}, Nil{})]) <>
  page_region(parent, Composition.TaskActions{}, Composition.HeadingPosition{},
    [declared(Identity.Part{owner, "heading"}, detail, state), more(U.TaskSubject{id}, Identity.Part{owner, "heading"}, state)]) <>
  page_region(parent, Composition.TimelineContent{}, Composition.BodyPosition{},
    [region(owner, "timeline", "Conversation", SurfaceTypes.Timeline{},
      List.append(&2, SurfaceTypes.Node, groups(groups_value, id, Identity.Part{owner, "timeline"}, state),
        List.append(&2, SurfaceTypes.Node, live_outputs(previews, owner, state), operations(live, owner, state))))]) <>
  List.append(&2, SurfaceTypes.Node, page_latest(return_latest, parent, owner, state),
    List.append(&2, SurfaceTypes.Node, page_approvals(decisions, parent, owner, state), page_composer(input, parent, owner, state, Composition.DockPosition{})))

def task_page(value: V.TaskScene, parent: Identity.Key, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  V.TaskScene{id, title, status, context, page_timeline, previews, input, details, actions} = value
  task_page_fields(id, title, page_timeline, previews, input, actions, parent, state)

def workspace_roots(values: +List<String>) -> String:
  match values:
    case Nil{}: ""
    case Con{value, Nil{}}: value
    case Con{value, rest}: value ++ "\n" ++ workspace_roots(rest)

def workspace_primary(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: ""
    case Some{text}: text

def guidance_text(value: D.ProjectContext) -> String:
  match value:
    case D.NoProject{}: "No project guidance"
    case D.ProjectContext{workspace, revision, instructions}: instructions

def project_page(value: V.ProjectScene, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  V.ProjectScene{id, +name, D.Workspace{roots, primary}, guidance, tasks, actions} = value
  [page_region(parent, Composition.ProjectTitle{}, Composition.HeadingPosition{}, [region(parent, "heading", name, SurfaceTypes.Heading{}, Nil{})]),
   page_region(parent, Composition.ProjectActions{}, Composition.HeadingPosition{}, controls(actions, Identity.Part{parent, "heading"}, state)),
   page_region(parent, Composition.DefaultWorkspace{}, Composition.BodyPosition{},
     [project_fact(Identity.Part{parent, "default-workspace"}, "Default workspace", workspace_roots(roots)), project_fact(Identity.Part{parent, "primary"}, "Primary directory", workspace_primary(primary))]),
   page_region(parent, Composition.ProjectGuidance{}, Composition.BodyPosition{}, [project_fact(Identity.Part{parent, "guidance"}, "Project guidance", guidance_text(guidance))]),
   page_region(parent, Composition.ProjectTasks{}, Composition.BodyPosition{}, task_entries(tasks, parent, state))]

def available(value: V.Availability) -> Bool:
  match value:
    case V.Unavailable{reason}: False{}
    case _: True{}

def enabled_control(control: InteractionTypes.Control) -> Bool:
  InteractionTypes.Control{identity, label, prominence, input, availability} = control
  available(availability)

def board_profile(+automatic: Bool, +selected: String, choices: +List<D.Profile>, parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  +observed_application = Core.application(state)
  +world = E.program(observed_application)
  SurfaceTypes.Node{Identity.Part{parent, "drafting-model"}, "drafting-model", "草稿模型", SurfaceTypes.Field{},
    SurfaceTypes.BoardProfile{automatic, selected, choices, enabled_control(Core.control(state, View.board_control("board/profile", "草稿模型", B.Settings{automatic, selected}, world)))}, Nil{}}

def with_search(+search: String, +filter: B.Filter) -> B.Filter:
  B.Filter{view, old, status, priority, date, assignee, creator, project, label} = filter
  B.Filter{view, search, status, priority, date, assignee, creator, project, label}

def retain_filter_value(keep: Bool, +value: String, +rest: +List<String>) -> +List<String>:
  match keep:
    case True{}: value <> rest
    case False{}: rest

def without_filter(+values: +List<String>, +value: String) -> +List<String>:
  match values:
    case Nil{}: Nil{}
    case Con{+head, rest}: retain_filter_value(Bool.not(String.eq(head, value)), head, without_filter(rest, value))

def toggle_filters(present: Bool, +value: String, +values: +List<String>) -> +List<String>:
  match present:
    case True{}: without_filter(values, value)
    case False{}: value <> values

def toggled_filter(+values: +List<String>, +value: String) -> +List<String>:
  toggle_filters(Schema.contains(values, value), value, values)

def toggle_filter(category: String, +value: String, +filter: B.Filter) -> B.Filter:
  match category filter:
    case "status" B.Filter{view, search, status, priority, date, assignee, creator, project, label}:
      B.Filter{view, search, toggled_filter(status, value), priority, date, assignee, creator, project, label}
    case "priority" B.Filter{view, search, status, priority, date, assignee, creator, project, label}:
      B.Filter{view, search, status, toggled_filter(priority, value), date, assignee, creator, project, label}
    case "date" B.Filter{view, search, status, priority, date, assignee, creator, project, label}:
      B.Filter{view, search, status, priority, toggled_filter(date, value), assignee, creator, project, label}
    case "assignee" B.Filter{view, search, status, priority, date, assignee, creator, project, label}:
      B.Filter{view, search, status, priority, date, toggled_filter(assignee, value), creator, project, label}
    case "creator" B.Filter{view, search, status, priority, date, assignee, creator, project, label}:
      B.Filter{view, search, status, priority, date, assignee, toggled_filter(creator, value), project, label}
    case "project" B.Filter{view, search, status, priority, date, assignee, creator, project, label}:
      B.Filter{view, search, status, priority, date, assignee, creator, toggled_filter(project, value), label}
    case "label" B.Filter{view, search, status, priority, date, assignee, creator, project, label}:
      B.Filter{view, search, status, priority, date, assignee, creator, project, toggled_filter(label, value)}
    case _ filter: filter

def board_group(parent: Identity.Key, +identity: String, grouping: SurfaceTypes.BoardGrouping, +children: +List<SurfaceTypes.Node>) -> SurfaceTypes.Node:
  SurfaceTypes.Node{Identity.Part{parent, identity}, "board-group/" ++ identity, "", SurfaceTypes.Toolbar{}, SurfaceTypes.BoardGroup{grouping}, children}

def view_choice(+view: String, label: String, filter: B.Filter, +parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  B.Filter{current_view, search, status, priority, date, assignee, creator, project, labels} = filter
  +declaration: V.ControlDeclaration = V.ControlDeclaration{"view/" ++ view, label, V.Secondary{}, U.FilterBoard{B.Filter{view, search, status, priority, date, assignee, creator, project, labels}}, V.Available{}}
  selected_node(String.eq(current_view, view), declared(parent, declaration, state))

def view_choices(+filter: B.Filter, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  B.Filter{view, search, status, priority, date, assignee, creator, project, label} = filter
  [view_choice("all", "全部", filter, parent, state), view_choice("assigned", "已分配", filter, parent, state),
   view_choice("unassigned", "未分配", filter, parent, state)]

def finite_choice_control(kind: SurfaceTypes.ChoiceKind, classification: Maybe<&2, BoardFilter.Classification>, +selected: Bool, description: String, control: InteractionTypes.Control, parent: Identity.Key) -> SurfaceTypes.Node:
  InteractionTypes.Control{+identity, label, prominence, input, availability} = control
  selected_node(selected, SurfaceTypes.Node{Identity.Part{parent, identity}, identity, label, action_role(prominence), SurfaceTypes.Choice{kind, classification, selected, description, input, availability}, Nil{}})

def filter_option_declaration(choice: BoardFilter.Choice, +category: String, filter: B.Filter) -> V.ControlDeclaration:
  BoardFilter.Choice{+value, label, classification} = choice
  V.ControlDeclaration{"filter/" ++ category ++ "/" ++ value, label, V.Secondary{},
    U.FilterBoard{toggle_filter(category, value, filter)}, V.Available{}}

def filter_option_node(+choice: BoardFilter.Choice, +category: String, +filter: B.Filter, parent: Identity.Key, state: InteractionTypes.State) -> SurfaceTypes.Node:
  BoardFilter.Choice{+value, label, classification} = choice
  finite_choice_control(SurfaceTypes.MultipleChoice{}, Some{classification},
    Schema.contains(BoardFilter.values(category, filter), value), "",
    Core.control(state, filter_option_declaration(choice, category, filter)), Identity.Entity{parent, "filter-option", value})

def filter_option_nodes(+choices: +List<BoardFilter.Choice>, +category: String, +filter: B.Filter, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match choices:
    case Nil{}: Nil{}
    case Con{choice, rest}: filter_option_node(choice, category, filter, parent, state) <> filter_option_nodes(rest, category, filter, parent, state)

def filter_group(+category: String, label: String, +choices: +List<BoardFilter.Choice>, +filter: B.Filter, +parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  SurfaceTypes.Node{Identity.Part{Identity.Part{parent, "filter"}, category}, "filter/" ++ category, label, SurfaceTypes.Section{}, SurfaceTypes.Region{}, filter_option_nodes(choices, category, filter, Identity.Part{Identity.Part{parent, "filter"}, category}, state)}

def board_filter_nodes(+filter: B.Filter, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  +observed_application = Core.application(state)
  +world = E.program(observed_application)
  +cards = B.cards(Board.registry(world))
  filter_group("status", "状态", BoardFilter.stages(B.stages()), filter, parent, state) <>
  filter_group("priority", "优先级", BoardFilter.priority_choices(), filter, parent, state) <>
  filter_group("date", "更新时间", [BoardFilter.choice("1", "最近 24 小时", BoardFilter.Updated{}), BoardFilter.choice("7", "最近 7 天", BoardFilter.Updated{}), BoardFilter.choice("30", "最近 30 天", BoardFilter.Updated{})], filter, parent, state) <>
  filter_group("assignee", "负责人", BoardFilter.owners(world), filter, parent, state) <>
  filter_group("creator", "创建人", [BoardFilter.choice("self", "我", BoardFilter.Person{})], filter, parent, state) <>
  filter_group("project", "项目", BoardFilter.projects(world), filter, parent, state) <>
  filter_group("label", "标签", BoardFilter.label_choices(BoardFilter.collect_labels(cards, Nil{})), filter, parent, state) <>
  [declared(parent, V.ControlDeclaration{"filters/clear", "清除筛选", V.Secondary{}, U.FilterBoard{B.empty_filter()}, V.Available{}}, state)]

def archive_destination(control: V.ControlDeclaration, +parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  +observed_application = Core.application(state)
  +world = E.program(observed_application)
  +observed_session = E.session(observed_application)
  +route = E.route(observed_session)
  +now = E.now(observed_session)
  SurfaceTypes.Node{Identity.Part{parent, "archive-destination"}, "archive-destination", "归档任务", SurfaceTypes.Section{},
    SurfaceTypes.CardArchive{List.length(&2, V.CardScene, View.archived_cards(Board.registry(world), route, now, world))}, [declared(parent, control, state)]}

def board_toolbar(+filter: B.Filter, +working: Nat, create: V.ControlDeclaration, settings: V.ControlDeclaration,
  filters: V.ControlDeclaration, archive: V.ControlDeclaration, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  [board_group(parent, "view-choices", SurfaceTypes.ViewChoices{}, view_choices(filter, Identity.Part{parent, "view-choices"}, state)),
   board_group(parent, "search-area", SurfaceTypes.SearchArea{},
     [SurfaceTypes.Node{Identity.Part{parent, "search"}, "board-search", "搜索任务", SurfaceTypes.Field{}, SurfaceTypes.BoardSearch{filter}, Nil{}}]),
   board_group(parent, "work-status", SurfaceTypes.WorkStatus{},
     [view_choice("working", "正在运行的任务 " ++ Nat.show(working), filter, Identity.Part{parent, "work-status"}, state)]),
   board_group(parent, "secondary-actions", SurfaceTypes.SecondaryActions{}, [declared(parent, filters, state), declared(parent, settings, state), archive_destination(archive, parent, state)]),
   board_group(parent, "primary-action", SurfaceTypes.PrimaryAction{}, [declared(parent, create, state)])]

def creation_title_node(value: V.CreationIntroduction, parent: Identity.Key) -> SurfaceTypes.Node:
  V.CreationIntroduction{+heading, summary, context, project, choose} = value
  SurfaceTypes.Node{Identity.Part{Identity.Part{Identity.Part{Identity.Part{parent, "creation"}, "introduction"}, "creation"}, "title"}, "creation/title", heading, SurfaceTypes.Heading{}, SurfaceTypes.ReadOnly{heading}, Nil{}}

def creation_project_node(value: V.CreationIntroduction, +parent: Identity.Key, state: InteractionTypes.State) -> SurfaceTypes.Node:
  V.CreationIntroduction{heading, summary, context, project, choose} = value
  SurfaceTypes.Node{Identity.Part{Identity.Part{parent, "creation"}, "project"}, "project-chooser", "", SurfaceTypes.Section{}, SurfaceTypes.ProjectChooser{View.project_choice_id(project)}, [declared(parent, choose, state)]}

def creation_context_node(value: V.CreationIntroduction, parent: Identity.Key) -> SurfaceTypes.Node:
  V.CreationIntroduction{heading, summary, context, project, choose} = value
  SurfaceTypes.Node{Identity.Part{Identity.Part{Identity.Part{Identity.Part{parent, "creation"}, "introduction"}, "creation"}, "context"}, "creation/context", "Workspace configuration", SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{summary}, Nil{}}

def creation_introduction_nodes(+value: V.CreationIntroduction, +parent: Identity.Key, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  [page_region(parent, Composition.CreationIntroduction{}, Composition.BodyPosition{}, [creation_title_node(value, parent), creation_project_node(value, parent, state)]),
   page_region(parent, Composition.CreationContext{}, Composition.BodyPosition{}, [creation_context_node(value, parent)])]

def creation_page(+input: Maybe<&2, V.ComposerScene>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  +observed_application = Core.application(state)
  world = E.program(observed_application)
  List.append(&2, SurfaceTypes.Node, creation_introduction_nodes(View.creation_introduction(input, world), parent, state), page_composer(input, parent, parent, state, Composition.BodyPosition{}))

def page_contents(view: V.Page, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match view:
    case V.StartPage{input}: creation_page(input, parent, state)
    case V.TaskPage{value}: task_page(value, parent, state)
    case V.ProjectPage{value}: project_page(value, parent, state)
    case V.ProjectsPage{values, create}:
      [page_region(parent, Composition.CollectionTitle{}, Composition.HeadingPosition{}, [region(parent, "heading", "Projects", SurfaceTypes.Heading{}, Nil{})]),
       page_region(parent, Composition.CollectionActions{}, Composition.HeadingPosition{}, [declared(parent, create, state)]),
       page_region(parent, Composition.ProjectEntries{}, Composition.BodyPosition{}, project_collection_entries(values, parent, state))]
    case V.BoardPage{filter, values, create, working, settings, filters, archive}:
      [page_region(parent, Composition.BoardTitle{}, Composition.HeadingPosition{}, [region(parent, "heading", "Board", SurfaceTypes.Heading{}, Nil{})]),
       page_region(parent, Composition.BoardControls{}, Composition.HeadingPosition{},
         board_toolbar(filter, working, create, settings, filters, archive, parent, state)),
       page_region(parent, Composition.BoardStages{}, Composition.BodyPosition{}, columns(values, parent, state))]
    case V.AgentsPage{values, create}:
      [page_region(parent, Composition.CollectionTitle{}, Composition.HeadingPosition{}, [region(parent, "heading", "Agents", SurfaceTypes.Heading{}, Nil{})]),
       page_region(parent, Composition.CollectionActions{}, Composition.HeadingPosition{}, [declared(parent, create, state)]),
       page_region(parent, Composition.AgentEntries{}, Composition.BodyPosition{}, agents(values, parent, state))]
    case V.MissingObject{message}:
      [page_region(parent, Composition.UnavailableMessage{}, Composition.BodyPosition{}, [SurfaceTypes.Node{Identity.Part{parent, "missing"}, "missing", "Unavailable", SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{message}, Nil{}}])]

def page_conversation(view: V.Page) -> Maybe<&2, Conversation.Identity>:
  match view:
    case V.TaskPage{V.TaskScene{id, title, status, context, timeline, previews, input, details, actions}}: Some{Conversation.identity(timeline)}
    case _: None{}

def page(+view: V.Page, state: InteractionTypes.State) -> SurfaceTypes.Node:
  SurfaceTypes.Node{Identity.Place{"/main"}, "main", "Content", SurfaceTypes.Main{}, SurfaceTypes.PageContext{page_conversation(view)}, page_contents(view, Identity.Place{"/main"}, state)}

def selected_effort(permitted: Bool, effort: String, profile: D.Profile) -> String:
  match permitted:
    case True{}: effort
    case False{}: D.profile_default(profile)

def choice_control(selected: Bool, description: String, control: InteractionTypes.Control, parent: Identity.Key) -> SurfaceTypes.Node:
  InteractionTypes.Control{+identity, label, prominence, input, availability} = control
  SurfaceTypes.Node{Identity.Part{parent, identity}, identity, label, SurfaceTypes.Button{}, SurfaceTypes.Choice{SurfaceTypes.SingleChoice{}, None{}, selected, description, input, availability}, Nil{}}

def declared_choice(selected: Bool, description: String, declaration: V.ControlDeclaration, parent: Identity.Key, state: InteractionTypes.State) -> SurfaceTypes.Node:
  choice_control(selected, description, Core.control(state, declaration), parent)

def model_choice_availability(permitted: Bool) -> V.Availability:
  match permitted:
    case True{}: V.Available{}
    case False{}: V.Unavailable{"The model has no permitted reasoning selection"}

def model_choices(profiles: +List<D.Profile>, +selected: String, +effort: String, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match profiles:
    case Nil{}: Nil{}
    case Con{D.Profile{+key, +provider, +name, policy, options}, rest}:
      +profile: D.Profile = D.Profile{key, provider, name, policy, options}
      +selection = selected_effort(D.profile_permitted(profile, effort), effort, profile)
      declared_choice(String.eq(key, selected), provider, V.ControlDeclaration{"model/" ++ key, name, V.Secondary{}, U.EditDraft{editor, U.ChooseModel{key, selection}}, model_choice_availability(D.profile_permitted(profile, selection))}, Identity.Entity{parent, "profile", key}, state) <> model_choices(rest, selected, effort, editor, parent, state)

def delivery_selected(current: U.Delivery, candidate: U.Delivery) -> Bool:
  match current candidate:
    case U.Send{} U.Send{}: True{}
    case U.Steer{} U.Steer{}: True{}
    case _ _: False{}

def picker_fields(values: +List<V.InputGroup>, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{V.ModelInput{profile, reasoning, choices}, rest}: List.append(&2, SurfaceTypes.Node, model_choices(choices, profile, reasoning, editor, parent, state), picker_fields(rest, editor, parent, state))
    case Con{V.DeliveryInput{+selected, send, steer}, rest}:
      declared_choice(delivery_selected(selected, U.Send{}), "Send a new message to this task.", send, parent, state) <>
      declared_choice(delivery_selected(selected, U.Steer{}), "Guide the current run with this message.", steer, parent, state) <> picker_fields(rest, editor, parent, state)
    case Con{other, rest}: picker_fields(rest, editor, parent, state)

def execution_details(value: Maybe<&2, V.TaskScene>, parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match value:
    case None{}: [SurfaceTypes.Node{Identity.Part{parent, "missing"}, "missing", "Task unavailable", SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{"The task no longer exists"}, Nil{}}]
    case Some{V.TaskScene{id, title, status, context, timeline, previews, composer, details, actions}}:
      [SurfaceTypes.Node{Identity.Part{parent, "execution"}, "execution", "Execution context", SurfaceTypes.Content{}, SurfaceTypes.TaskFacts{details}, Nil{}}]

def enrichment_observation(value: B.Enrichment) -> String:
  match value:
    case B.NoEnrichment{}: ""
    case B.Enriching{ticket, revision, retitle}: "正在生成。原始请求已保存；本次生成完成前不能编辑或移动任务。"
    case B.EnrichmentFailed{reason}: reason

def detail_labels(values: +List<String>) -> String:
  match values:
    case Nil{}: ""
    case Con{value, rest}: value ++ "\n" ++ detail_labels(rest)

def detail_files(values: +List<B.Attachment>, +parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{B.Attachment{+id, +name, +mime, +path, +bytes}, rest}:
      SurfaceTypes.Node{Identity.Entity{parent, "attachment", id}, id, name, SurfaceTypes.Section{}, SurfaceTypes.Region{}, [product_action(Identity.Entity{parent, "attachment", id}, "preview", "Preview " ++ name, InteractionTypes.ServiceInput{Services.OpenPreview{B.Attachment{id, name, mime, path, bytes}, Identity.encode(Identity.Part{Identity.Entity{parent, "attachment", id}, "preview"})}}, True{})]} <>
        detail_files(rest, parent)

def linked_card_controls(value: Maybe<&2, V.TaskEntry>, parent: Identity.Key, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match value:
    case None{}: Nil{}
    case Some{V.TaskEntry{id, title, status, selected, open}}: [declared(parent, open, state)]

def card_error_observations(+card: B.Card, +parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  [project_fact(Identity.Part{parent, "enrichment"}, "生成", enrichment_observation(B.enrichment(card))),
   project_fact(Identity.Part{parent, "start-error"}, "启动错误", B.start_error(card))]

def card_detail_draft(value: B.Draft, +id: Nat, +card: B.Card, actions: +List<V.ControlDeclaration>, linked: Maybe<&2, V.TaskEntry>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  B.Draft{title, description, stage, priority, owner, project, labels, files} = value
  +observed_application = Core.application(state)
  +world = E.program(observed_application)
  List.append(&2, SurfaceTypes.Node, [project_fact(Identity.Part{parent, "identifier"}, "任务", B.identifier(id)), project_fact(Identity.Part{parent, "title"}, "标题", title),
   project_fact(Identity.Part{parent, "description"}, "描述", description), project_fact(Identity.Part{parent, "stage"}, "状态", B.stage_label(stage)),
   project_fact(Identity.Part{parent, "priority"}, "优先级", B.priority_label(priority)), project_fact(Identity.Part{parent, "owner"}, "负责人", View.face_owner(owner, world)),
   project_fact(Identity.Part{parent, "project"}, "项目", View.face_project(project, world)), project_fact(Identity.Part{parent, "labels"}, "标签", detail_labels(labels)),
   project_fact(Identity.Part{parent, "activity"}, "执行", Board.activity_label(Board.activity(card, world))),
   declared(parent, View.control("card/edit/" ++ Nat.show(id), "编辑任务", U.EditCard{id}), state)],
   List.append(&2, SurfaceTypes.Node, card_error_observations(card, parent), List.append(&2, SurfaceTypes.Node, detail_files(files, Identity.Part{parent, "attachments"}),
     List.append(&2, SurfaceTypes.Node, linked_card_controls(linked, parent, state), controls(actions, parent, state)))))

def card_details_scene(value: V.CardScene, parent: Identity.Key, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  V.CardScene{id, +card, open, actions, linked, destinations, candidates} = value
  card_detail_draft(B.draft(card), id, card, actions, linked, parent, state)

def card_details_nodes(value: Maybe<&2, V.CardScene>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match value:
    case None{}: [project_fact(Identity.Part{parent, "missing"}, "Unavailable", "The card no longer exists")]
    case Some{card}: card_details_scene(card, parent, state)

def context_network_text(network: Bool) -> String:
  match network:
    case True{}: "Network enabled"
    case False{}: "Network disabled"

def sandbox_facts(value: D.Sandbox) -> String:
  D.Sandbox{mode, network} = value
  D.sandbox_mode_name(mode) ++ "; " ++ context_network_text(network)

def observation_facts(value: Context.Observation, profiles: +List<D.Profile>) -> String:
  match value:
    case Context.DraftExecution{Context.ContextUnavailable{reason}}: reason
    case Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}:
      "Configured: " ++ sandbox_facts(Context.unwrap_sandbox(sandbox)) ++ "; " ++ View.value_approval_summary(approval, profiles)
    case Context.CommittedExecution{Context.EffectiveContext{task, D.TaskContext{workspace, D.Sandbox{mode, network}, approval, project}, guidance, +access}}:
      Context.filesystem_summary(access, mode) ++ "; " ++ Context.network_summary(access, network) ++ "; " ++ View.policy_approval_summary(approval)

def context_summary_node(+value: Context.Observation, +parent: Identity.Key, state: InteractionTypes.State) -> SurfaceTypes.Node:
  +observed_application = Core.application(state)
  +world = E.program(observed_application)
  +source = View.execution_source_summary(value, world)
  +facts = observation_facts(value, Board.profiles(world))
  SurfaceTypes.Node{Identity.Part{parent, "source"}, "context/source", source, SurfaceTypes.Content{}, SurfaceTypes.ContextSummary{value},
    [SurfaceTypes.Node{Identity.Part{Identity.Part{parent, "source"}, "facts"}, "context/facts", facts, SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{facts}, Nil{}}]}

def sandbox_selected(selected: D.SandboxMode, candidate: D.SandboxMode) -> Bool:
  match selected candidate:
    case D.WorkspaceWrite{} D.WorkspaceWrite{}: True{}
    case D.ReadOnly{} D.ReadOnly{}: True{}
    case _ _: False{}

def approval_selected(selected: Context.ApprovalChoice, candidate: Context.ApprovalChoice) -> Bool:
  match selected candidate:
    case Context.Ask{} Context.Ask{}: True{}
    case Context.Unrestricted{} Context.Unrestricted{}: True{}
    case Context.AutomaticReview{current} Context.AutomaticReview{next}: String.eq(current, next)
    case _ _: False{}

def sandbox_label(mode: D.SandboxMode) -> String:
  match mode:
    case D.WorkspaceWrite{}: "Workspace write"
    case D.ReadOnly{}: "Read only"

def sandbox_description(mode: D.SandboxMode) -> String:
  match mode:
    case D.WorkspaceWrite{}: "Allow edits in the working directories."
    case D.ReadOnly{}: "Read files without modifying them."

def sandbox_choice(+mode: D.SandboxMode, +current: D.SandboxMode, +network: Bool, +editor: U.Editor, parent: Identity.Key, state: InteractionTypes.State) -> SurfaceTypes.Node:
  declared_choice(sandbox_selected(current, mode), sandbox_description(mode),
    V.ControlDeclaration{"filesystem/" ++ D.sandbox_mode_name(mode), sandbox_label(mode), V.Secondary{},
      U.EditDraft{editor, U.ConfigureContext{Context.SetSandbox{D.Sandbox{mode, network}}}}, V.Available{}}, parent, state)

def sandbox_choices(+sandbox: D.Sandbox, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  D.Sandbox{+mode, +network} = sandbox
  SurfaceTypes.Node{Identity.Part{parent, "filesystem"}, "permissions/filesystem", "Filesystem access", SurfaceTypes.Section{}, SurfaceTypes.ChoiceGroup{},
    [sandbox_choice(D.WorkspaceWrite{}, mode, network, editor, Identity.Part{parent, "filesystem"}, state),
     sandbox_choice(D.ReadOnly{}, mode, network, editor, Identity.Part{parent, "filesystem"}, state)]}

def approval_profile_key(choice: Context.ApprovalChoice) -> String:
  match choice:
    case Context.AutomaticReview{profile}: profile
    case _: ""

def approval_description(choice: Context.ApprovalChoice) -> String:
  match choice:
    case Context.Ask{}: "Ask before running actions that require approval."
    case Context.Unrestricted{}: "Run actions without approval prompts."
    case Context.AutomaticReview{profile}: "Use this model to review approval requests."

def approval_choice_node(+choice: Context.ApprovalChoice, +current: Context.ApprovalChoice, reviewer: Maybe<&2, D.Profile>, editor: U.Editor, parent: Identity.Key, state: InteractionTypes.State) -> SurfaceTypes.Node:
  declared_choice(approval_selected(current, choice), approval_description(choice),
    V.ControlDeclaration{"approval/" ++ Context.approval_option(choice) ++ "/" ++ approval_profile_key(choice), View.execution_approval_summary(choice, reviewer), V.Secondary{},
      U.EditDraft{editor, U.ConfigureContext{Context.SetApproval{choice}}}, V.Available{}}, parent, state)

def reviewer_choices(profiles: +List<D.Profile>, +current: Context.ApprovalChoice, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match profiles:
    case Nil{}: Nil{}
    case Con{D.Profile{+key, provider, name, policy, options}, rest}:
      approval_choice_node(Context.AutomaticReview{key}, current, Some{D.Profile{key, provider, name, policy, options}}, editor, Identity.Entity{parent, "profile", key}, state) <> reviewer_choices(rest, current, editor, parent, state)

def approval_choices(+current: Context.ApprovalChoice, reviewers: +List<D.Profile>, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  SurfaceTypes.Node{Identity.Part{parent, "approval"}, "permissions/approval", "Approval policy", SurfaceTypes.Section{}, SurfaceTypes.ChoiceGroup{},
    approval_choice_node(Context.Ask{}, current, None{}, editor, Identity.Part{parent, "approval"}, state) <>
    approval_choice_node(Context.Unrestricted{}, current, None{}, editor, Identity.Part{parent, "approval"}, state) <>
    reviewer_choices(reviewers, current, editor, Identity.Part{parent, "approval"}, state)}

def network_description(network: Bool) -> String:
  match network:
    case False{}: "Keep network access off."
    case True{}: "Allow network access."

def network_key(network: Bool) -> String:
  match network:
    case False{}: "disabled"
    case True{}: "enabled"

def network_label(network: Bool) -> String:
  match network:
    case False{}: "Disabled"
    case True{}: "Enabled"

def network_selected(current: Bool, target: Bool) -> Bool:
  match current target:
    case False{} False{}: True{}
    case True{} True{}: True{}
    case _ _: False{}

def network_choice(+mode: D.SandboxMode, current: Bool, +target: Bool, editor: U.Editor, parent: Identity.Key, state: InteractionTypes.State) -> SurfaceTypes.Node:
  declared_choice(network_selected(current, target), network_description(target),
    V.ControlDeclaration{"permissions/network/" ++ network_key(target), network_label(target), V.Secondary{},
      U.EditDraft{editor, U.ConfigureContext{Context.SetSandbox{D.Sandbox{mode, target}}}}, V.Available{}}, parent, state)

def network_choices(sandbox: D.Sandbox, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  D.Sandbox{+mode, +network} = sandbox
  SurfaceTypes.Node{Identity.Part{parent, "network"}, "permissions/network", "Network access", SurfaceTypes.Section{}, SurfaceTypes.ChoiceGroup{},
    [network_choice(mode, network, False{}, editor, Identity.Part{parent, "network"}, state),
     network_choice(mode, network, True{}, editor, Identity.Part{parent, "network"}, state)]}

def unavailable_context(+reason: String, parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  [SurfaceTypes.Node{Identity.Part{parent, "unavailable"}, "context/unavailable", reason, SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{reason}, Nil{}}]

def optional_control(value: Maybe<&2, V.ControlDeclaration>, parent: Identity.Key, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match value:
    case None{}: Nil{}
    case Some{control}: [declared(parent, control, state)]

def workspace_menu_group(+editor: U.Editor, group: V.InputGroup, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match group:
    case V.ExecutionInput{config, Context.ContextUnavailable{reason}, controls, projects, reviewers}: unavailable_context(reason, parent)
    case V.ExecutionInput{config, +preview, V.WorkspaceControls{identity, roots, inherit}, projects, reviewers}:
      context_summary_node(Context.DraftExecution{preview}, parent, state) <>
      SurfaceTypes.Node{Identity.Part{parent, "instruction"}, "workspace/instruction", "Add directories and choose the primary working directory.", SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{"Add directories and choose the primary working directory."}, Nil{}} <>
      SurfaceTypes.Node{Identity.Part{parent, "add"}, "workspace/add", "Add working directory", SurfaceTypes.Field{}, SurfaceTypes.EnterDirectory{editor, pending_directory(state, editor)}, Nil{}} <>
      directory_confirm(editor, parent, state) <>
      directory_browse(editor, parent, state) <>
      List.append(&2, SurfaceTypes.Node, directory_root_nodes(roots, parent, state), optional_control(inherit, parent, state))
    case _: Nil{}

def workspace_menu(groups: +List<V.InputGroup>, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match groups:
    case Nil{}: Nil{}
    case Con{group, rest}: List.append(&2, SurfaceTypes.Node, workspace_menu_group(editor, group, parent, state), workspace_menu(rest, editor, parent, state))

def permission_menu_group(+editor: U.Editor, group: V.InputGroup, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match group:
    case V.ExecutionInput{config, Context.ContextUnavailable{reason}, controls, projects, reviewers}: unavailable_context(reason, parent)
    case V.ExecutionInput{+config, Context.ProspectiveContext{+origin, +project, +workspace, +sandbox, +approval, +guidance}, controls, projects, reviewers}:
      context_summary_node(Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}, parent, state) <>
      sandbox_choices(Context.unwrap_sandbox(sandbox), editor, parent, state) <>
      network_choices(Context.unwrap_sandbox(sandbox), editor, parent, state) <>
      approval_choices(Context.observed_approval(approval), reviewers, editor, parent, state) <>
      List.append(&2, SurfaceTypes.Node, reset_control(reset_change(config, OperationParameters.SandboxMode{}), editor, OperationParameters.SandboxMode{}, "filesystem and network access", parent, state),
        reset_control(reset_change(config, OperationParameters.ApprovalPolicy{}), editor, OperationParameters.ApprovalPolicy{}, "approval policy", parent, state))
    case _: Nil{}

def permission_menu(groups: +List<V.InputGroup>, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match groups:
    case Nil{}: Nil{}
    case Con{group, rest}: List.append(&2, SurfaceTypes.Node, permission_menu_group(editor, group, parent, state), permission_menu(rest, editor, parent, state))

def committed_primary_text(primary: Bool) -> String:
  match primary:
    case True{}: "Primary working directory"
    case False{}: "Additional directory"

def committed_project_name(found: Maybe<&2, D.Project>, id: Nat) -> String:
  match found:
    case None{}: "Project unavailable (ID " ++ Nat.show(id) ++ ")"
    case Some{D.Project{name, workspace, guidance}}: name

def committed_project_text(project: Maybe<&2, Nat>, world: M.World()) -> String:
  match project:
    case None{}: "Projectless task"
    case Some{+id}: committed_project_name(Projects.find(Projects.registry(F.State(), world), id), id)

def committed_project_node(project: Maybe<&2, Nat>, +parent: Identity.Key, state: InteractionTypes.State) -> SurfaceTypes.Node:
  +observed_application = Core.application(state)
  world = E.program(observed_application)
  +label = committed_project_text(project, world)
  SurfaceTypes.Node{Identity.Part{parent, "project"}, "context/project", label, SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{label}, Nil{}}

def committed_working_directory(primary: Maybe<&2, String>) -> String:
  match primary:
    case None{}: "No working directory"
    case Some{path}: "Working directory: " ++ path

def committed_working_directory_extra(covered: Bool, +primary: Maybe<&2, String>, +parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match covered:
    case True{}: Nil{}
    case False{}:
      [SurfaceTypes.Node{Identity.Part{parent, "working-directory"}, "context/working-directory", committed_working_directory(primary), SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{committed_working_directory(primary)}, Nil{}}]

def committed_directory_nodes(roots: +List<String>, +primary: Maybe<&2, String>, +parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match roots:
    case Nil{}: Nil{}
    case Con{+path, rest}:
      SurfaceTypes.Node{Identity.Entity{parent, "directory", path}, "directory/" ++ path, path, SurfaceTypes.Content{}, SurfaceTypes.DirectoryRow{path, View.is_primary(primary, path)},
        [SurfaceTypes.Node{Identity.Part{Identity.Entity{parent, "directory", path}, "primary"}, "directory/primary", committed_primary_text(View.is_primary(primary, path)), SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{committed_primary_text(View.is_primary(primary, path))}, Nil{}}]} <>
        committed_directory_nodes(rest, primary, parent)

def committed_context_nodes(context: Maybe<&2, Context.EffectiveContext>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match context:
    case None{}: unavailable_context("Task execution context is unavailable", parent)
    case Some{Context.EffectiveContext{+task, D.TaskContext{D.Workspace{+roots, +primary}, +sandbox, +approval, +project}, +guidance, +access}}:
      context_summary_node(Context.CommittedExecution{Context.EffectiveContext{task, D.TaskContext{D.Workspace{roots, primary}, sandbox, approval, project}, guidance, access}}, parent, state) <>
      committed_project_node(project, parent, state) <>
      List.append(&2, SurfaceTypes.Node, committed_working_directory_extra(Context.member_primary(primary, roots), primary, parent), committed_directory_nodes(roots, primary, parent))

def project_picker_control(control: InteractionTypes.Control, selected: Bool, description: String, parent: Identity.Key) -> SurfaceTypes.Node:
  InteractionTypes.Control{+key, label, prominence, input, availability} = control
  SurfaceTypes.Node{Identity.Part{parent, key}, key, label, SurfaceTypes.Button{}, SurfaceTypes.Choice{SurfaceTypes.SingleChoice{}, None{}, selected, description, input, availability}, Nil{}}

def project_picker_choice(declaration: V.ControlDeclaration, selected: Bool, description: String, parent: Identity.Key, state: InteractionTypes.State) -> SurfaceTypes.Node:
  project_picker_control(Core.control(state, declaration), selected, description, parent)

def project_registered_choices(values: +List<V.ProjectChoice>, +selected: Maybe<&2, Nat>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{V.ProjectChoice{+id, name, +workspace}, rest}:
      project_picker_choice(View.control("project/select/" ++ Nat.show(id), name, U.SelectProject{Some{id}}), View.same_project(selected, Some{id}), View.project_folder_description(workspace), Identity.Entity{parent, "project", Nat.show(id)}, state) <>
        project_registered_choices(rest, selected, parent, state)

def project_choice_nodes(values: +List<V.ProjectChoice>, +selected: Maybe<&2, Nat>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  [SurfaceTypes.Node{Identity.Part{parent, "choices"}, "project/choices", "Projects", SurfaceTypes.Section{}, SurfaceTypes.ChoiceGroup{},
    project_picker_choice(View.control("project/select/none", "No project", U.SelectProject{None{}}), View.same_project(selected, None{}), "Use environment defaults", parent, state) <>
      project_registered_choices(values, selected, parent, state)},
   declared(parent, View.control("project/create", "New project", U.EditProject{None{}}), state)]

def layer_content(view: V.LayerContent, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match view:
    case V.ProjectSelection{query, selected, projects}:
      SurfaceTypes.Node{Identity.Part{parent, "search"}, "search", "Search projects", SurfaceTypes.Field{}, SurfaceTypes.SearchChoices{query}, Nil{}} <>
        project_choice_nodes(projects, selected, parent, state)
    case V.ObjectActions{actions}: controls(actions, parent, state)
    case V.ArchivedCards{values}: cards(values, parent, state)
    case V.BoardSettings{+automatic, draft_profile, assistance_profiles, automation}:
      selected_node(automatic, declared(parent, automation, state)) <>
        [board_profile(automatic, draft_profile, assistance_profiles, parent, state)]
    case V.BoardFilters{filter}: board_filter_nodes(filter, parent, state)
    case V.CardDetails{card}: card_details_nodes(card, parent, state)
    case V.ObjectEditor{value}: editor(value, parent, state)
    case V.WorkspaceSettings{identity, values}: workspace_menu(values, identity, parent, state)
    case V.PermissionSettings{identity, values}: permission_menu(values, identity, parent, state)
    case V.CommittedContext{context}: committed_context_nodes(context, parent, state)
    case V.ModelSelection{identity, query, values}:
      SurfaceTypes.Node{Identity.Part{parent, "search"}, "search", "Search models", SurfaceTypes.Field{}, SurfaceTypes.SearchChoices{query}, Nil{}} <> picker_fields(values, identity, parent, state)
    case V.DeliverySelection{identity, values}: picker_fields(values, identity, parent, state)
    case V.ExecutionDetails{value}: execution_details(value, parent)
    case V.Confirmation{title, confirm, cancel}: [dialog_actions(parent, [declared(parent, confirm, state), declared(parent, cancel, state)])]

def layer_role(kind: V.LayerKind) -> SurfaceTypes.Role:
  match kind:
    case V.ModalDialog{}: SurfaceTypes.Dialog{}
    case V.AnchoredMenu{}: SurfaceTypes.Menu{}
    case V.TrailingDetails{}: SurfaceTypes.Details{}

def layer_key(initial_attention: String) -> Identity.Key:
  Identity.Entity{Identity.Place{"/layers"}, "layer", initial_attention}

def dismissal_meaning(value: V.Dismissal) -> SurfaceTypes.Meaning:
  match value:
    case V.OutsideOrEscape{action}: SurfaceTypes.LayerRegion{InteractionTypes.ApplicationInput{E.UserInput{U.Activate{action}}}, True{}, True{}}
    case V.ByTrigger{action}: SurfaceTypes.LayerRegion{InteractionTypes.ApplicationInput{E.UserInput{U.Activate{action}}}, False{}, False{}}

def layers(values: +List<V.Layer>, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{V.Layer{kind, +content, +initial, restore, dismissal}, rest}:
      SurfaceTypes.Node{layer_key(initial), initial, View.layer_title(content), layer_role(kind), dismissal_meaning(dismissal),
        layer_content(content, layer_key(initial), state)} <> layers(rest, state)

def settings_visible(open: Bool, +entered: Bool, close: InteractionTypes.Input, connect: InteractionTypes.Input) -> +List<SurfaceTypes.Node>:
  match open:
    case False{}: Nil{}
    case True{}: [SurfaceTypes.Node{Identity.Place{"/layers/settings"}, "settings", "Settings", SurfaceTypes.Dialog{}, SurfaceTypes.LayerRegion{close, True{}, True{}},
      [SurfaceTypes.Node{Identity.Part{Identity.Place{"/layers/settings"}, "credential"}, "settings/credential", "Access token", SurfaceTypes.Field{}, SurfaceTypes.EnterCredential{entered}, Nil{}},
       region(Identity.Place{"/layers/settings"}, "appearance", "Appearance", SurfaceTypes.Section{}, [
         product_action(Identity.Place{"/layers/settings"}, "light", "Light appearance", InteractionTypes.ServiceInput{Services.ChooseAppearance{Services.LightAppearance{}}}, True{}),
         product_action(Identity.Place{"/layers/settings"}, "dark", "Dark appearance", InteractionTypes.ServiceInput{Services.ChooseAppearance{Services.DarkAppearance{}}}, True{}),
         product_action(Identity.Place{"/layers/settings"}, "system", "System appearance", InteractionTypes.ServiceInput{Services.ChooseAppearance{Services.SystemAppearance{}}}, True{})]),
       dialog_actions(Identity.Place{"/layers/settings"}, [product_action(Identity.Place{"/layers/settings"}, "connect", "Connect", connect, entered)])]}]

def settings(view: InteractionTypes.Settings) -> +List<SurfaceTypes.Node>:
  InteractionTypes.Settings{open, access, entered, appearance, open_action, close_action, connect_action} = view
  settings_visible(open, entered, close_action, connect_action)

def preview_controls(file: B.Attachment, ready: Bool) -> +List<SurfaceTypes.Node>:
  [SurfaceTypes.Node{Identity.Place{"/layers/attachment-preview"}, "attachment-preview", "Attachment preview", SurfaceTypes.Dialog{},
    SurfaceTypes.LayerRegion{InteractionTypes.ServiceInput{Services.ClosePreview{}}, True{}, True{}},
    [dialog_actions(Identity.Place{"/layers/attachment-preview"}, [product_action(Identity.Place{"/layers/attachment-preview"}, "download", "Download", InteractionTypes.ServiceInput{Services.Download{file}}, ready)])]}]

def preview(value: Services.Preview) -> +List<SurfaceTypes.Node>:
  match value:
    case Services.NoPreview{}: Nil{}
    case Services.LoadingPreview{ticket, file, trigger}: preview_controls(file, False{})
    case Services.ReadyPreview{file, resource, image, trigger}: preview_controls(file, True{})
    case Services.FailedPreview{file, reason, trigger}: preview_controls(file, False{})

def directory_visit(parent: Identity.Key, id: String, label: String, path: String) -> SurfaceTypes.Node:
  product_action(parent, id, label, InteractionTypes.ServiceInput{Services.VisitDirectory{path}}, True{})

def directory_parent(parent: Maybe<&2, String>) -> +List<SurfaceTypes.Node>:
  match parent:
    case None{}: Nil{}
    case Some{path}: [directory_visit(Identity.Place{"/layers/directory-picker"}, "parent", "Parent folder", path)]

def directory_entries(values: +List<Services.DirectoryEntry>) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Services.DirectoryEntry{name, +path}, rest}:
      SurfaceTypes.Node{Identity.Entity{Identity.Place{"/layers/directory-picker"}, "directory", path}, "entry/" ++ path, name, SurfaceTypes.Button{}, SurfaceTypes.Activate{InteractionTypes.ServiceInput{Services.VisitDirectory{path}}, V.Available{}}, Nil{}} <> directory_entries(rest)

def directory_truncated(truncated: Bool) -> +List<SurfaceTypes.Node>:
  match truncated:
    case False{}: Nil{}
    case True{}: [SurfaceTypes.Node{Identity.Part{Identity.Place{"/layers/directory-picker"}, "truncated"}, "directory-picker/truncated", "More folders are available", SurfaceTypes.Content{},
      SurfaceTypes.ReadOnly{"The folder list is incomplete. Enter a path to visit another folder."}, Nil{}}]

def directory_picker_content(picker: Services.DirectoryPicker) -> +List<SurfaceTypes.Node>:
  match picker:
    case Services.NoDirectoryPicker{}: Nil{}
    case Services.LoadingDirectory{ticket, editor, path, trigger}:
      [SurfaceTypes.Node{Identity.Part{Identity.Place{"/layers/directory-picker"}, "status"}, "directory-picker/status", "Loading folders", SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{"Loading folders…"}, Nil{}}]
    case Services.FailedDirectory{ticket, editor, path, reason, trigger}:
      [SurfaceTypes.Node{Identity.Part{Identity.Place{"/layers/directory-picker"}, "error"}, "directory-picker/error", "Folder listing failed", SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{reason}, Nil{}},
       directory_visit(Identity.Place{"/layers/directory-picker"}, "retry", "Retry", path)]
    case Services.ReadyDirectory{ticket, editor, Services.DirectoryCatalog{path, +parent, entries, truncated}, location, trigger}:
      [SurfaceTypes.Node{Identity.Part{Identity.Place{"/layers/directory-picker"}, "location"}, "directory-picker/location", "Folder path", SurfaceTypes.Field{}, SurfaceTypes.DirectoryBrowserLocation{location}, Nil{}},
       region(Identity.Place{"/layers/directory-picker"}, "navigation", "Folder navigation", SurfaceTypes.Toolbar{},
         List.append(&2, SurfaceTypes.Node, [product_action(Identity.Place{"/layers/directory-picker"}, "go", "Go", InteractionTypes.ServiceInput{Services.GoDirectory{}}, True{})], directory_parent(parent)))]

def directory_ready_content(picker: Services.DirectoryPicker) -> +List<SurfaceTypes.Node>:
  match picker:
    case Services.ReadyDirectory{ticket, editor, Services.DirectoryCatalog{path, parent, entries, truncated}, location, trigger}:
      [region(Identity.Place{"/layers/directory-picker"}, "folders", "Folders", SurfaceTypes.Section{},
        List.append(&2, SurfaceTypes.Node, directory_entries(entries), directory_truncated(truncated))),
       dialog_actions(Identity.Place{"/layers/directory-picker"}, [SurfaceTypes.Node{Identity.Part{Identity.Place{"/layers/directory-picker"}, "use"}, "directory-picker/use", "Use this folder", SurfaceTypes.PrimaryButton{},
         SurfaceTypes.Activate{InteractionTypes.ServiceInput{Services.ChooseDirectory{}}, V.Available{}}, Nil{}}])]
    case _: Nil{}

def directory_picker(value: Services.DirectoryPicker) -> +List<SurfaceTypes.Node>:
  match value:
    case Services.NoDirectoryPicker{}: Nil{}
    case +other:
      [SurfaceTypes.Node{Identity.Place{"/layers/directory-picker"}, "directory-picker", "Choose folder", SurfaceTypes.Dialog{},
        SurfaceTypes.LayerRegion{InteractionTypes.ServiceInput{Services.CloseDirectoryPicker{}}, True{}, True{}},
        List.append(&2, SurfaceTypes.Node, directory_picker_content(other), directory_ready_content(other))}]

def active_scope(overlays: +List<SurfaceTypes.Node>) -> Maybe<&2, String>:
  match overlays:
    case Nil{}: None{}
    case Con{SurfaceTypes.Node{key, semantic, label, SurfaceTypes.Dialog{}, meaning, children}, rest}: Some{Identity.encode(key)}
    case Con{SurfaceTypes.Node{key, semantic, label, SurfaceTypes.Menu{}, meaning, children}, rest}: Some{Identity.encode(key)}
    case Con{SurfaceTypes.Node{key, semantic, label, SurfaceTypes.Navigation{}, meaning, children}, rest}: Some{Identity.encode(key)}
    case Con{other, rest}: active_scope(rest)

def finish(content: InteractionTypes.Scene, base: +List<SurfaceTypes.Node>, +overlays: +List<SurfaceTypes.Node>) -> SurfaceTypes.Surface:
  SurfaceTypes.Surface{content, base, overlays, active_scope(overlays)}

def collapsed_navigation_toggle(nav: V.Navigation, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  V.Navigation{expanded, create, destinations, projects, tasks, toggle} = nav
  [declared(Identity.Place{"/navigation"}, toggle, state)]

def base_navigation_at(placement: V.NavigationPlacement, nav: V.Navigation, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match placement:
    case V.ModalNavigation{}: Nil{}
    case V.CollapsedNavigation{}: collapsed_navigation_toggle(nav, state)
    case V.LeadingNavigation{}: [navigation(nav, state)]

def base_navigation(arrangement: V.Arrangement, nav: V.Navigation, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  V.Arrangement{placement} = arrangement
  base_navigation_at(placement, nav, state)

def modal_navigation_at(placement: V.NavigationPlacement, nav: V.Navigation, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match placement:
    case V.ModalNavigation{}: [navigation(nav, state)]
    case _: Nil{}

def modal_navigation(arrangement: V.Arrangement, nav: V.Navigation, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  V.Arrangement{placement} = arrangement
  modal_navigation_at(placement, nav, state)

def persistent_details_trigger(overlays: +List<SurfaceTypes.Node>) -> Maybe<&2, SurfaceTypes.PersistentTrigger>:
  match overlays:
    case Nil{}: None{}
    case Con{SurfaceTypes.Node{key, semantic, label, SurfaceTypes.Dialog{},
      SurfaceTypes.LayerRegion{InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.TogglePanel{U.TaskDetails{task}, trigger}}}}, False{}, False{}}, children}, rest}: Some{SurfaceTypes.PersistentTrigger{task, trigger}}
    case Con{SurfaceTypes.Node{key, semantic, label, SurfaceTypes.Dialog{}, meaning, children}, rest}: None{}
    case Con{SurfaceTypes.Node{key, semantic, label, SurfaceTypes.Menu{}, meaning, children}, rest}: None{}
    case Con{other, rest}: persistent_details_trigger(rest)

def retain_node(keep: Bool, node: SurfaceTypes.Node, rest: +List<SurfaceTypes.Node>) -> +List<SurfaceTypes.Node>:
  match keep:
    case True{}: node <> rest
    case False{}: rest

def without_node(nodes: +List<SurfaceTypes.Node>, +key: String) -> +List<SurfaceTypes.Node>:
  match nodes:
    case Nil{}: Nil{}
    case Con{SurfaceTypes.Node{+current, semantic, label, role, meaning, children}, rest}:
      retain_node(Bool.not(String.eq(Identity.encode(current), key)),
        SurfaceTypes.Node{current, semantic, label, role, meaning, without_node(children, key)}, without_node(rest, key))

def prepend_persistent_trigger(overlays: +List<SurfaceTypes.Node>, +trigger: SurfaceTypes.Node) -> +List<SurfaceTypes.Node>:
  match overlays:
    case Nil{}: Nil{}
    case Con{SurfaceTypes.Node{key, semantic, label, SurfaceTypes.Dialog{}, meaning, children}, rest}:
      SurfaceTypes.Node{key, semantic, label, SurfaceTypes.Dialog{}, meaning, trigger <> children} <> rest
    case Con{other, rest}: other <> prepend_persistent_trigger(rest, trigger)

def relocate_valid_trigger(valid: Bool, +node: SurfaceTypes.Node, content: InteractionTypes.Scene,
  +base: +List<SurfaceTypes.Node>, +overlays: +List<SurfaceTypes.Node>) -> SurfaceTypes.Surface:
  match valid:
    case False{}: finish(content, base, overlays)
    case True{}:
      SurfaceTypes.Node{key, semantic, label, role, meaning, children} = node
      finish(content, without_node(base, Identity.encode(key)), prepend_persistent_trigger(overlays, node))

def persistent_trigger_source(meaning: SurfaceTypes.Meaning, target: Nat) -> Bool:
  match meaning:
    case SurfaceTypes.PanelToggle{expanded, InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.TogglePanel{U.TaskDetails{source}, trigger}}}}, availability}: Nat.is_eq(source, target)
    case _: False{}

def relocate_found_trigger(found: Maybe<&2, SurfaceTypes.Node>, +target: Nat, content: InteractionTypes.Scene,
  +base: +List<SurfaceTypes.Node>, +overlays: +List<SurfaceTypes.Node>) -> SurfaceTypes.Surface:
  match found:
    case None{}: finish(content, base, overlays)
    case Some{SurfaceTypes.Node{key, semantic, label, role, +meaning, children}}:
      relocate_valid_trigger(persistent_trigger_source(meaning, target),
        SurfaceTypes.Node{key, semantic, label, role, meaning, children}, content, base, overlays)

def choose_node(same: Bool, node: SurfaceTypes.Node, fallback: Maybe<&2, SurfaceTypes.Node>) -> Maybe<&2, SurfaceTypes.Node>:
  match same:
    case True{}: Some{node}
    case False{}: fallback

def prefer_node(found: Maybe<&2, SurfaceTypes.Node>, fallback: Maybe<&2, SurfaceTypes.Node>) -> Maybe<&2, SurfaceTypes.Node>:
  match found:
    case Some{node}: Some{node}
    case None{}: fallback

def find_node(nodes: +List<SurfaceTypes.Node>, +key: String) -> Maybe<&2, SurfaceTypes.Node>:
  match nodes:
    case Nil{}: None{}
    case Con{SurfaceTypes.Node{+current, semantic, label, role, meaning, +children}, rest}:
      choose_node(String.eq(Identity.encode(current), key), SurfaceTypes.Node{current, semantic, label, role, meaning, children},
        prefer_node(find_node(children, key), find_node(rest, key)))

def scope_node(found: Maybe<&2, SurfaceTypes.Node>) -> +List<SurfaceTypes.Node>:
  match found:
    case None{}: Nil{}
    case Some{node}: [node]

def select_scope(scope: Maybe<&2, String>, base: +List<SurfaceTypes.Node>, overlays: +List<SurfaceTypes.Node>) -> +List<SurfaceTypes.Node>:
  match scope:
    case None{}: List.append(&2, SurfaceTypes.Node, base, overlays)
    case Some{key}: scope_node(find_node(overlays, key))

def active_nodes(surface: SurfaceTypes.Surface) -> +List<SurfaceTypes.Node>:
  SurfaceTypes.Surface{content, base, overlays, scope} = surface
  select_scope(scope, base, overlays)

def when_available(enabled: Bool, input: InteractionTypes.Input) -> Maybe<&2, InteractionTypes.Input>:
  match enabled:
    case True{}: Some{input}
    case False{}: None{}

def profile_exists(profile: Maybe<&2, D.Profile>) -> Bool:
  match profile:
    case None{}: False{}
    case Some{profile}: True{}

def bind(meaning: SurfaceTypes.Meaning, gesture: SurfaceTypes.Gesture) -> Maybe<&2, InteractionTypes.Input>:
  match meaning gesture:
    case SurfaceTypes.ComposerAction{subject, input, availability} SurfaceTypes.Press{}: when_available(available(availability), input)
    case SurfaceTypes.Activate{input, availability} SurfaceTypes.Press{}: when_available(available(availability), input)
    case SurfaceTypes.PanelToggle{expanded, input, availability} SurfaceTypes.Press{}: when_available(available(availability), input)
    case SurfaceTypes.Choice{kind, classification, selected, description, input, availability} SurfaceTypes.Press{}: when_available(available(availability), input)
    case SurfaceTypes.Edit{+editor, +field, OperationParameters.DisplayOnly{}, +value, choices} SurfaceTypes.Change{+next}: None{}
    case SurfaceTypes.Edit{+editor, +field, entry, +value, choices} SurfaceTypes.Change{+next}: Some{InteractionTypes.EditField{editor, field, next}}
    case SurfaceTypes.SearchChoices{query} SurfaceTypes.Search{+next}: Some{InteractionTypes.ApplicationInput{E.UserInput{U.SearchChoices{next}}}}
    case SurfaceTypes.EnterCredential{entered} SurfaceTypes.Credential{+value}: Some{InteractionTypes.ServiceInput{Services.EnterCredential{value}}}
    case SurfaceTypes.BoardSearch{+filter} SurfaceTypes.Search{+next}: Some{InteractionTypes.ApplicationInput{E.UserInput{U.FilterBoard{with_search(next, filter)}}}}
    case SurfaceTypes.ReceiveFile{+editor, +enabled} SurfaceTypes.Attach{file}: when_available(enabled, InteractionTypes.ServiceInput{Services.AddFile{editor, file}})
    case SurfaceTypes.BoardProfile{automatic, selected, choices, +enabled} SurfaceTypes.SelectBoardProfile{+profile}: when_available(enabled && profile_exists(D.find_profile(choices, profile)), InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.BoardCommand{B.Settings{automatic, profile}}}}})
    case SurfaceTypes.DirectoryBrowserLocation{value} SurfaceTypes.Directory{path}: Some{InteractionTypes.ServiceInput{Services.WriteDirectoryLocation{path}}}
    case SurfaceTypes.DirectoryBrowserLocation{value} SurfaceTypes.ConfirmDirectory{}: Some{InteractionTypes.ServiceInput{Services.GoDirectory{}}}
    case SurfaceTypes.EnterDirectory{+editor, text} SurfaceTypes.Directory{path}: Some{InteractionTypes.ApplicationInput{E.UserInput{U.EditDraft{editor, U.WriteDirectory{path}}}}}
    case SurfaceTypes.EnterDirectory{editor, text} SurfaceTypes.ConfirmDirectory{}: Some{InteractionTypes.ApplicationInput{E.UserInput{U.EditDraft{editor, U.ConfirmDirectory{}}}}}
    case _ _: None{}

def bind_node(found: Maybe<&2, SurfaceTypes.Node>, gesture: SurfaceTypes.Gesture) -> Maybe<&2, InteractionTypes.Input>:
  match found:
    case None{}: None{}
    case Some{SurfaceTypes.Node{key, semantic, label, role, meaning, children}}: bind(meaning, gesture)

def prefer_input(found: Maybe<&2, InteractionTypes.Input>, fallback: Maybe<&2, InteractionTypes.Input>) -> Maybe<&2, InteractionTypes.Input>:
  match found:
    case Some{input}: Some{input}
    case None{}: fallback

def placement_input(values: +List<SurfaceTypes.Placement>, +target: String) -> Maybe<&2, InteractionTypes.Input>:
  match values:
    case Nil{}: None{}
    case Con{SurfaceTypes.Placement{key, label, input, availability}, rest}:
      prefer_input(when_available(String.eq(key, target) && available(availability), input), placement_input(rest, target))

def has_available_destination(values: +List<SurfaceTypes.Placement>) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{SurfaceTypes.Placement{target, label, input, availability}, rest}:
      available(availability) || has_available_destination(rest)

def card_placements(values: +List<SurfaceTypes.Node>) -> +List<SurfaceTypes.Placement>:
  match values:
    case Nil{}: Nil{}
    case Con{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.MovableCard{destinations, face}, children}, rest}: destinations
    case Con{other, rest}: card_placements(rest)

def placement_source(source: SurfaceTypes.Node, target: String) -> Maybe<&2, InteractionTypes.Input>:
  match source:
    case SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.MovableCard{destinations, face}, children}: placement_input(destinations, target)
    case SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.CardContent{face}, children}: placement_input(card_placements(children), target)
    case _: None{}

def place(source: Maybe<&2, SurfaceTypes.Node>, target: Maybe<&2, SurfaceTypes.Node>) -> Maybe<&2, InteractionTypes.Input>:
  match source target:
    case Some{node} Some{SurfaceTypes.Node{target, semantic, label, role, meaning, children}}: placement_source(node, Identity.encode(target))
    case _ _: None{}

def resolve_present(+source: SurfaceTypes.Node, gesture: SurfaceTypes.Gesture, surface: SurfaceTypes.Surface) -> Maybe<&2, InteractionTypes.Input>:
  match gesture:
    case SurfaceTypes.Place{target}: placement_source(source, target)
    case other: bind_node(Some{source}, other)

def resolve_source(source: Maybe<&2, SurfaceTypes.Node>, gesture: SurfaceTypes.Gesture, surface: SurfaceTypes.Surface) -> Maybe<&2, InteractionTypes.Input>:
  match source:
    case None{}: None{}
    case Some{node}: resolve_present(node, gesture, surface)

def resolve(+surface: SurfaceTypes.Surface, key: String, gesture: SurfaceTypes.Gesture) -> Maybe<&2, InteractionTypes.Input>:
  resolve_source(find_node(active_nodes(surface), key), gesture, surface)

def apply_input(input: Maybe<&2, InteractionTypes.Input>, +state: InteractionTypes.State) -> InteractionTypes.Decision:
  match input:
    case Some{input}: Core.step(input, state)
    case None{}:
      application = Core.application(state)
      services = Core.services(state)
      Core.application_result(E.unchanged(application), services)

def origin(layers: +List<E.Layer>, key: String) -> String:
  match layers:
    case Con{E.Layer{U.ObjectActions{subject}, trigger, initial, query, layer_occurrence}, rest}: trigger
    case _: key

def layer_trigger(unchanged: Bool, previous: String, origin: String) -> String:
  match unchanged:
    case True{}: previous
    case False{}: origin

def layer_present(layers: +List<E.Layer>, +target: String) -> Bool:
  match layers:
    case Nil{}: False{}
    case Con{E.Layer{panel, trigger, initial, query, layer_occurrence}, rest}:
      String.eq(E.panel_target(panel), target) || layer_present(rest, target)

def record_layer(layers: +List<E.Layer>, previous: +List<E.Layer>, origin: String) -> +List<E.Layer>:
  match layers:
    case Nil{}: Nil{}
    case Con{E.Layer{+panel, trigger, initial, query, layer_occurrence}, rest}:
      E.Layer{panel, layer_trigger(layer_present(previous, E.panel_target(panel)), trigger, origin), initial, query, layer_occurrence} <> rest

def source_session(+session: E.Session, previous: +List<E.Layer>, origin: String) -> E.Session:
  layers = E.layers(session)
  E.with_layers(record_layer(layers, previous, origin), session)

def source_decision(decision: InteractionTypes.Decision, previous: +List<E.Layer>, origin: String) -> InteractionTypes.Decision:
  InteractionTypes.Decision{+observed_state, reply, runtime, interaction, service_effects, durable} = decision
  +observed_application = Core.application(observed_state)
  program = E.program(observed_application)
  session = E.session(observed_application)
  services = Core.services(observed_state)
  InteractionTypes.Decision{Core.from_application(E.from_program(program, source_session(session, previous, origin)), services), reply, runtime, interaction, service_effects, durable}

def record_source(before: InteractionTypes.State, key: String, decision: InteractionTypes.Decision) -> InteractionTypes.Decision:
  +observed_application = Core.application(before)
  +observed_session = E.session(observed_application)
  +layers = E.layers(observed_session)
  source_decision(decision, layers, origin(layers, key))

def navigates(input: Maybe<&2, InteractionTypes.Input>) -> Bool:
  match input:
    case Some{InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.Navigate{route}}}}}: True{}
    case Some{InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.BeginTask{project}}}}}: True{}
    case Some{InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.SelectProject{project}}}}}: True{}
    case _: False{}

def dismiss_navigation(+session: E.Session) -> E.Session:
  navigation = E.navigation(session)
  E.with_navigation(E.set_navigation(False{}, navigation), session)

def navigation_closed(decision: InteractionTypes.Decision) -> InteractionTypes.Decision:
  InteractionTypes.Decision{+observed_state, reply, runtime, interaction, service_effects, durable} = decision
  +observed_application = Core.application(observed_state)
  program = E.program(observed_application)
  session = E.session(observed_application)
  services = Core.services(observed_state)
  InteractionTypes.Decision{Core.from_application(E.from_program(program, dismiss_navigation(session)), services), reply, runtime, interaction, service_effects, durable}

def after_navigation(dismiss: Bool, decision: InteractionTypes.Decision) -> InteractionTypes.Decision:
  match dismiss:
    case False{}: decision
    case True{}: navigation_closed(decision)

def perform_present(capacity: V.Capacity, +state: InteractionTypes.State, key: String, +input: Maybe<&2, InteractionTypes.Input>) -> InteractionTypes.Decision:
  V.Capacity{navigation_beside, details_beside} = capacity
  after_navigation(Bool.not(navigation_beside) && navigates(input), record_source(state, key, apply_input(input, state)))

def perform_input(input: Maybe<&2, InteractionTypes.Input>, capacity: V.Capacity, +state: InteractionTypes.State, key: String) -> InteractionTypes.Decision:
  match input:
    case None{}: apply_input(None{}, state)
    case Some{value}: perform_present(capacity, state, key, Some{value})

def perform(capacity: V.Capacity, state: InteractionTypes.State, key: String, input: Maybe<&2, InteractionTypes.Input>) -> InteractionTypes.Decision:
  perform_input(input, capacity, state, key)

def focusable(meaning: SurfaceTypes.Meaning) -> Bool:
  match meaning:
    case SurfaceTypes.ComposerAction{subject, input, availability}: available(availability)
    case SurfaceTypes.Activate{input, availability}: available(availability)
    case SurfaceTypes.PanelToggle{expanded, input, availability}: available(availability)
    case SurfaceTypes.LayerRegion{dismiss, outside, escape}: True{}
    case SurfaceTypes.Choice{kind, classification, selected, description, input, availability}: available(availability)
    case SurfaceTypes.Edit{editor, field, OperationParameters.DisplayOnly{}, value, choices}: False{}
    case SurfaceTypes.Edit{editor, field, OperationParameters.FileCollection{}, value, choices}: False{}
    case SurfaceTypes.Edit{editor, field, OperationParameters.DirectoryCollection{}, value, choices}: False{}
    case SurfaceTypes.Edit{editor, field, entry, value, choices}: True{}
    case SurfaceTypes.SearchChoices{query}: True{}
    case SurfaceTypes.EnterCredential{entered}: True{}
    case SurfaceTypes.BoardSearch{filter}: True{}
    case SurfaceTypes.ReceiveFile{editor, enabled}: enabled
    case SurfaceTypes.EnterDirectory{editor, text}: True{}
    case SurfaceTypes.DirectoryBrowserLocation{value}: True{}
    case SurfaceTypes.BoardProfile{automatic, selected, choices, enabled}: enabled
    case _: False{}

def preferred_key(found: Maybe<&2, String>, fallback: Maybe<&2, String>) -> Maybe<&2, String>:
  match found:
    case Some{key}: Some{key}
    case None{}: fallback

def candidate_focus(accepted: Bool, key: String, fallback: Maybe<&2, String>) -> Maybe<&2, String>:
  match accepted:
    case True{}: Some{key}
    case False{}: fallback

def first_focus(nodes: +List<SurfaceTypes.Node>) -> Maybe<&2, String>:
  match nodes:
    case Nil{}: None{}
    case Con{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.LayerRegion{dismiss, outside, escape}, children}, rest}:
      preferred_key(first_focus(children), Some{Identity.encode(key)})
    case Con{SurfaceTypes.Node{key, semantic, label, role, meaning, children}, rest}:
      candidate_focus(focusable(meaning), Identity.encode(key), preferred_key(first_focus(children), first_focus(rest)))

def at_focus(matches: Bool, node: SurfaceTypes.Node) -> Maybe<&2, String>:
  match matches:
    case True{}: first_focus([node])
    case False{}: None{}

def matching_focus(nodes: +List<SurfaceTypes.Node>, +requested: String) -> Maybe<&2, String>:
  match nodes:
    case Nil{}: None{}
    case Con{SurfaceTypes.Node{+key, +semantic, label, role, meaning, +children}, rest}:
      preferred_key(at_focus(String.eq(Identity.encode(key), requested) || String.eq(semantic, requested), SurfaceTypes.Node{key, semantic, label, role, meaning, children}),
        preferred_key(matching_focus(children, requested), matching_focus(rest, requested)))

def relocate_trigger_key(found: Maybe<&2, String>, +target: Nat, content: InteractionTypes.Scene,
  +base: +List<SurfaceTypes.Node>, +overlays: +List<SurfaceTypes.Node>) -> SurfaceTypes.Surface:
  match found:
    case None{}: finish(content, base, overlays)
    case Some{key}: relocate_found_trigger(find_node(base, key), target, content, base, overlays)

def relocate_persistent_trigger(trigger: Maybe<&2, SurfaceTypes.PersistentTrigger>, content: InteractionTypes.Scene,
  +base: +List<SurfaceTypes.Node>, +overlays: +List<SurfaceTypes.Node>) -> SurfaceTypes.Surface:
  match trigger:
    case None{}: finish(content, base, overlays)
    case Some{SurfaceTypes.PersistentTrigger{target, requested}}: relocate_trigger_key(matching_focus(base, requested), target, content, base, overlays)

def finish_reachable(content: InteractionTypes.Scene, +base: +List<SurfaceTypes.Node>, +overlays: +List<SurfaceTypes.Node>) -> SurfaceTypes.Surface:
  # NOTE: A modal makes the page inert; move its existing toggle into the
  # active scope rather than creating a second activation authority.
  relocate_persistent_trigger(persistent_details_trigger(overlays), content, base, overlays)

def surface_base(surface: SurfaceTypes.Surface) -> +List<SurfaceTypes.Node>:
  SurfaceTypes.Surface{content, base, overlays, scope} = surface
  base

def surface_overlays(surface: SurfaceTypes.Surface) -> +List<SurfaceTypes.Node>:
  SurfaceTypes.Surface{content, base, overlays, scope} = surface
  overlays

def with_navigation(content: InteractionTypes.Scene, nav: +List<SurfaceTypes.Node>, +reachable: SurfaceTypes.Surface,
  settings: SurfaceTypes.Node, scope: Maybe<&2, String>) -> SurfaceTypes.Surface:
  SurfaceTypes.Surface{content, List.append(&2, SurfaceTypes.Node, nav,
    List.append(&2, SurfaceTypes.Node, surface_base(reachable), [settings])), surface_overlays(reachable), scope}

def assemble(+content: InteractionTypes.Scene, +state: InteractionTypes.State) -> SurfaceTypes.Surface:
  InteractionTypes.Scene{V.Scene{+nav, +main, +views, +arrangement, attention}, +preferences, transfers, +attachment, code, +folder_picker} = content
  +overlays = List.append(&2, SurfaceTypes.Node, preview(attachment), List.append(&2, SurfaceTypes.Node, directory_picker(folder_picker), List.append(&2, SurfaceTypes.Node, settings(preferences), List.append(&2, SurfaceTypes.Node, layers(views, state), modal_navigation(arrangement, nav, state)))))
  # NOTE: Saved trigger identities can alias navigation; only main owns relocation.
  +reachable = finish_reachable(content, [page(main, state)], overlays)
  with_navigation(content, base_navigation(arrangement, nav, state), reachable,
    product_action(Identity.Place{""}, "settings/open", "Settings", InteractionTypes.ServiceInput{Services.OpenSettings{}}, True{}), active_scope(overlays))

def observe(capacity: V.Capacity, +state: InteractionTypes.State) -> SurfaceTypes.Surface:
  assemble(Core.observe(capacity, state), state)

def interact(+capacity: V.Capacity, +key: String, gesture: SurfaceTypes.Gesture, +state: InteractionTypes.State) -> InteractionTypes.Decision:
  perform(capacity, state, key, resolve(observe(capacity, state), key, gesture))

def focus_in(+nodes: +List<SurfaceTypes.Node>, requested: String) -> Maybe<&2, String>:
  preferred_key(matching_focus(nodes, requested), first_focus(nodes))

def focus_target(surface: SurfaceTypes.Surface, requested: String) -> Maybe<&2, String>:
  focus_in(active_nodes(surface), requested)

def all_focus_target(surface: SurfaceTypes.Surface, requested: String) -> Maybe<&2, String>:
  SurfaceTypes.Surface{content, base, overlays, scope} = surface
  focus_in(List.append(&2, SurfaceTypes.Node, base, overlays), requested)

def submits(meaning: SurfaceTypes.Meaning, editor: U.Editor) -> Bool:
  match meaning:
    case SurfaceTypes.ComposerAction{subject, InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.Submit{owner}}}}, availability}: available(availability) && U.same_editor(owner, editor)
    case SurfaceTypes.Activate{InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.Submit{owner}}}}, availability}: available(availability) && U.same_editor(owner, editor)
    case _: False{}

def submission(nodes: +List<SurfaceTypes.Node>, +editor: U.Editor) -> Maybe<&2, SurfaceTypes.Node>:
  match nodes:
    case Nil{}: None{}
    case Con{SurfaceTypes.Node{key, semantic, label, role, +meaning, +children}, rest}:
      choose_node(submits(meaning, editor), SurfaceTypes.Node{key, semantic, label, role, meaning, children}, prefer_node(submission(children, editor), submission(rest, editor)))

def submit_found(found: Maybe<&2, SurfaceTypes.Node>, capacity: V.Capacity, +state: InteractionTypes.State) -> InteractionTypes.Decision:
  match found:
    case None{}: apply_input(None{}, state)
    case Some{SurfaceTypes.Node{key, semantic, label, role, meaning, children}}: perform(capacity, state, Identity.encode(key), bind(meaning, SurfaceTypes.Press{}))

def submit_composer(+capacity: V.Capacity, editor: U.Editor, +state: InteractionTypes.State) -> InteractionTypes.Decision:
  submit_found(submission(active_nodes(observe(capacity, state)), editor), capacity, state)

def has_submission(found: Maybe<&2, SurfaceTypes.Node>) -> Bool:
  match found:
    case None{}: False{}
    case Some{node}: True{}

def composer_enabled(capacity: V.Capacity, editor: U.Editor, state: InteractionTypes.State) -> Bool:
  has_submission(submission(active_nodes(observe(capacity, state)), editor))

def content(surface: SurfaceTypes.Surface) -> InteractionTypes.Scene:
  SurfaceTypes.Surface{content, base, overlays, scope} = surface
  content
