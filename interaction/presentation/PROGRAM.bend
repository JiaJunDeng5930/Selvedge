import ../experience/PROGRAM.bend as UX
import ../experience/MODEL.bend as Experience
import ../experience/ACTIVITY.bend as Activity
import ./INFORMATION.bend as Information
import Base
import ../submission/FIELDS.bend as OperationParameters
import ../IDENTITY.bend as Identity
import ../submission/MODEL.bend as Receipt
import ../../harness/MODEL.bend as M
import ../../harness/COMMANDS.bend as Commands
import ../../harness/tasks/PROGRAM.bend as T
import ../../features/board/MODEL.bend as B
import ../../features/task_graph/MODEL.bend as G
import ../../features/task_graph/CODEC.bend as GraphCodec
import ../../features/work/MODEL.bend as Work
import ../../harness/features/work-state.bend as WorkState
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
  InteractionTypes.Control{+identity, label, prominence, input, +availability} = control
  SurfaceTypes.Node{Identity.Part{parent, identity}, identity, label, action_role(prominence), SurfaceTypes.Activate{input, availability}, Nil{}}

def replace_role(node: SurfaceTypes.Node, role: SurfaceTypes.Role) -> SurfaceTypes.Node:
  SurfaceTypes.Node{key, semantic, label, old_role, meaning, children} = node
  SurfaceTypes.Node{key, semantic, label, role, meaning, children}

def selected_node(selected: Bool, node: SurfaceTypes.Node) -> SurfaceTypes.Node:
  match selected:
    case True{}: replace_role(node, SurfaceTypes.SelectedButton{})
    case False{}: node

def declared_panel_toggle_layers(parent: Identity.Key, control: InteractionTypes.Control, panel: U.Panel, layers: +List<E.Layer>) -> SurfaceTypes.Node:
  InteractionTypes.Control{+identity, label, prominence, input, +availability} = control
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
    case U.TaskGraphs{} U.TaskGraphs{}: True{}
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

def navigation_declaration(+route: U.Route, +parent: Identity.Key, +declaration: V.ControlDeclaration, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  V.ControlDeclaration{identity, label, prominence, +input, availability} = declaration
  replace_role(selected_declaration(route, parent, declaration, state), SurfaceTypes.NavigationEntry{navigation_action_selected(route, input)})

def navigation_controls(+route: U.Route, +values: +List<V.ControlDeclaration>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: navigation_declaration(route, parent, value, state) <> navigation_controls(route, rest, parent, state)

def task_navigation_creation(+route: U.Route, create: V.ControlDeclaration, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  SurfaceTypes.Node{Identity.Part{Identity.Place{"/navigation"}, "task-creation"}, "task-navigation-creation", "", SurfaceTypes.NavigationSection{}, SurfaceTypes.Region{},
    [navigation_declaration(route, Identity.Place{"/navigation"}, create, state)]}

def global_navigation_declaration(+compact: Bool, +route: U.Route, parent: Identity.Key, +declaration: V.ControlDeclaration, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  V.ControlDeclaration{identity, label, prominence, +input, availability} = declaration
  replace_role(declared(parent, declaration, state), SurfaceTypes.GlobalNavigationEntry{navigation_action_selected(route, input), compact})

def global_navigation_controls(+compact: Bool, +route: U.Route, values: +List<V.ControlDeclaration>, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{first, rest}: global_navigation_declaration(compact, route, Identity.Place{"/navigation"}, first, state) <> global_navigation_controls(compact, route, rest, state)

# NOTE: Global destinations have no Task visibility dependency and keep their original inputs.
def global_navigation_form(+compact: Bool, +route: U.Route, destinations: +List<V.ControlDeclaration>, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  SurfaceTypes.Node{Identity.Place{"/global-navigation"}, "global-navigation", "Global navigation", SurfaceTypes.GlobalNavigation{compact}, SurfaceTypes.Region{},
    [region(Identity.Place{"/global-navigation"}, "global-destinations", "", SurfaceTypes.Section{},
      global_navigation_declaration(compact, route, Identity.Place{"/global-navigation"}, View.control("home", "Home", U.Navigate{U.Start{}}), state) <>
        global_navigation_controls(compact, route, destinations, state)),
     region(Identity.Place{"/global-navigation"}, "global-settings", "", SurfaceTypes.Section{},
       [replace_role(product_action(Identity.Place{""}, "settings/open", "Settings", InteractionTypes.ServiceInput{Services.OpenSettings{}}, True{}), SurfaceTypes.GlobalNavigationEntry{False{}, compact})])]}

def global_navigation(+compact: Bool, view: V.Navigation, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  V.Navigation{expanded, create, destinations, projects, tasks, toggle} = view
  global_navigation_form(compact, E.route(E.session(Core.application(state))), destinations, state)

def global_menu_declaration(+route: U.Route, +parent: Identity.Key, +declaration: V.ControlDeclaration, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  V.ControlDeclaration{identity, label, prominence, +input, availability} = declaration
  replace_role(declared(parent, declaration, state), SurfaceTypes.CompactNavigationEntry{navigation_action_selected(route, input)})

def global_menu_controls(+route: U.Route, values: +List<V.ControlDeclaration>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{first, rest}: global_menu_declaration(route, parent, first, state) <> global_menu_controls(route, rest, parent, state)

def global_navigation_menu(+route: U.Route, destinations: +List<V.ControlDeclaration>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  [region(parent, "global-menu/entries", "Global destinations", SurfaceTypes.CompactNavigationMenu{},
    List.append(&2, SurfaceTypes.Node,
      global_menu_declaration(route, parent, View.control("global/home", "Home", U.Navigate{U.Start{}}), state) <> global_menu_controls(route, destinations, parent, state),
      [replace_role(product_action(parent, "global/settings", "Settings", InteractionTypes.ServiceInput{Services.OpenSettings{}}, True{}), SurfaceTypes.CompactNavigationEntry{False{}}),
       declared(parent, View.control("global/done", "Done", U.ClosePanel{}), state)]))]

def independent_task_entries(tasks: +List<V.TaskEntry>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match tasks:
    case Nil{}: Nil{}
    case Con{first, rest}:
      [region(parent, "independent-tasks", "", SurfaceTypes.NavigationSection{},
        SurfaceTypes.Node{Identity.Part{Identity.Part{parent, "independent-tasks"}, "title"}, "independent-tasks/title", "Tasks without a project", SurfaceTypes.Heading{}, SurfaceTypes.InformationText{Information.NavigationCaption{}}, Nil{}} <>
        task_entries(Con{first, rest}, parent, state))]

def navigation_contents(expanded: Bool, +route: U.Route, create: V.ControlDeclaration, destinations: +List<V.ControlDeclaration>, projects: +List<V.ProjectEntry>, tasks: +List<V.TaskEntry>, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match expanded:
    case False{}: Nil{}
    case True{}:
      [SurfaceTypes.Node{Identity.Part{Identity.Place{"/navigation"}, "contents"}, "navigation-content", "", SurfaceTypes.NavigationCollection{}, SurfaceTypes.Region{},
        task_navigation_creation(route, create, state) <> List.append(&2, SurfaceTypes.Node,
          project_entries(projects, Identity.Place{"/navigation"}, state), independent_task_entries(tasks, Identity.Place{"/navigation"}, state))}]

def work_settings(work: Maybe<&2, Nat>, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match work:
    case None{}: Nil{}
    case Some{+id}: [declared(Identity.Place{"/navigation"}, View.control("work/rename/" ++ Nat.show(id), "Rename Work", U.RenameWork{id}), state)]

def navigation(view: V.Navigation, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  V.Navigation{expanded, create, destinations, projects, tasks, toggle} = view
  +observed_application = Core.application(state)
  +observed_session = E.session(observed_application)
  +route = E.route(observed_session)
  navigation = E.navigation(observed_session)
  +header: SurfaceTypes.Node = SurfaceTypes.Node{Identity.Part{Identity.Place{"/navigation"}, "header"}, "navigation-header", "Task tree", SurfaceTypes.NavigationHeader{}, SurfaceTypes.Region{},
    List.append(&2, SurfaceTypes.Node, [declared(Identity.Place{"/navigation"}, toggle, state)], work_settings(E.active_work(observed_session), state))}
  SurfaceTypes.Node{Identity.Place{"/navigation"}, "navigation", "Task tree", SurfaceTypes.Navigation{}, SurfaceTypes.Region{}, header <>
    navigation_contents(expanded, route, create, destinations, projects, tasks, state)}

# The compact header moves with the modal tree so its three real launchers stay
# in the active scope. Its native identities occur exactly once in either form.
def compact_navigation(view: V.Navigation, header: SurfaceTypes.Node, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  V.Navigation{expanded, create, destinations, projects, tasks, toggle} = view
  +current = E.session(Core.application(state))
  SurfaceTypes.Node{Identity.Place{"/navigation"}, "navigation", "Task tree", SurfaceTypes.Navigation{}, SurfaceTypes.Region{},
    header <> SurfaceTypes.Node{Identity.Part{Identity.Place{"/navigation"}, "header"}, "navigation-header", "Task tree", SurfaceTypes.NavigationHeader{}, SurfaceTypes.Region{},
      work_settings(E.active_work(current), state)} <>
      navigation_contents(expanded, E.route(current), create, destinations, projects, tasks, state)}

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
    case OperationParameters.ContextValue{value, reviewers}: context_workspace(value)
    case _: None{}

def collection_control(found: Maybe<&2, U.Input>, identity: String, label: String, prominence: V.Prominence, parent: Identity.Key, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match found:
    case None{}: Nil{}
    case Some{input}: [declared(parent, V.ControlDeclaration{identity, label, prominence, input, V.Available{}}, state)]

def collection_primary_controls(primary: Bool, collection: Experience.Collection, path: String, +parent: Identity.Key, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match primary:
    case True{}: [SurfaceTypes.Node{Identity.Part{parent, "primary"}, "directory/primary", "Primary working directory", SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{"Primary working directory"}, Nil{}}]
    case False{}: collection_control(UX.choose_primary(collection, path), "directory/primary", "Use as primary", V.Secondary{}, parent, state)

def collection_member(+collection: Experience.Collection, +path: String, parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  +key : Identity.Key = Identity.Entity{parent, "directory", path}
  SurfaceTypes.Node{key, "directory/" ++ path, path, SurfaceTypes.Content{}, SurfaceTypes.WorkspaceMember{collection, path}, List.append(&2, SurfaceTypes.Node, collection_primary_controls(UX.is_primary(collection, path), collection, path, key, state), collection_control(UX.remove_member(collection, path), "directory/remove", "Remove", V.Destructive{}, key, state))}

def collection_rows(paths: +List<String>, +collection: Experience.Collection, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match paths:
    case Nil{}: Nil{}
    case Con{path, rest}: collection_member(collection, path, parent, state) <> collection_rows(rest, collection, parent, state)

def collection_surface(+collection: Experience.Collection, +parent: Identity.Key, state: InteractionTypes.State) -> SurfaceTypes.Node:
  SurfaceTypes.Node{Identity.Part{parent, "workspace"}, "workspace/collection", "Working directories", SurfaceTypes.Section{}, SurfaceTypes.WorkspaceCollection{collection}, collection_rows(UX.collection_members(collection), collection, parent, state)}

def directory_values(found: Maybe<&2, D.Workspace>, +editor: U.Editor, parent: Identity.Key, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match found:
    case None{}: Nil{}
    case Some{workspace}: [collection_surface(UX.collection(editor, workspace), parent, state)]

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

def unavailable_context(+reason: String, parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  [SurfaceTypes.Node{Identity.Part{parent, "unavailable"}, "context/unavailable", reason, SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{reason}, Nil{}}]

def optional_control(value: Maybe<&2, V.ControlDeclaration>, parent: Identity.Key, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match value:
    case None{}: Nil{}
    case Some{control}: [declared(parent, control, state)]

def unadded_directory_status(empty: Bool, parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match empty:
    case True{}: Nil{}
    case False{}: [SurfaceTypes.Node{Identity.Part{parent, "unadded-directory"}, "assessment/unadded_directory", "Add or clear the directory before saving", SurfaceTypes.Content{}, SurfaceTypes.InformationText{Information.Status{}}, Nil{}}]

def workspace_collection_menu(found: Maybe<&2, D.Workspace>, +editor: U.Editor, inherit: Maybe<&2, V.ControlDeclaration>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match found:
    case None{}: unavailable_context("Workspace is unavailable", parent)
    case Some{workspace}:
      +collection = UX.collection(editor, workspace)
      [SurfaceTypes.Node{Identity.Part{parent, "workspace"}, "workspace/collection", "Working directories", SurfaceTypes.Section{}, SurfaceTypes.WorkspaceCollection{collection},
        SurfaceTypes.Node{Identity.Part{parent, "instruction"}, "workspace/instruction", "Add directories and choose the primary working directory.", SurfaceTypes.Content{}, SurfaceTypes.InformationText{Information.Description{}}, Nil{}} <>
        SurfaceTypes.Node{Identity.Part{parent, "add"}, "workspace/add", "Add working directory", SurfaceTypes.Field{}, SurfaceTypes.EnterDirectory{editor, pending_directory(state, editor)}, unadded_directory_status(String.eq(pending_directory(state, editor), ""), Identity.Part{parent, "add"})} <>
        directory_confirm(editor, parent, state) <> directory_browse(editor, parent, state) <>
        List.append(&2, SurfaceTypes.Node, collection_rows(UX.collection_members(collection), collection, parent, state), optional_control(inherit, parent, state))}]
def field_children(field: OperationParameters.Field, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match field:
    case OperationParameters.CardAttachments{}: file_field(editor, parent, state)
    case OperationParameters.WorkspaceDirectories{}: workspace_collection_menu(workspace_observed(field_value(state, editor, OperationParameters.WorkspaceDirectories{})), editor, None{}, parent, state)
    case _: Nil{}

def policy_entry(policy: Reasoning.Policy) -> OperationParameters.Entry:
  OperationParameters.policy_entry(policy)

def profile_effort_entry(profile: D.Profile) -> OperationParameters.Entry:
  OperationParameters.profile_effort_entry(profile)

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

def primary_choices(alternatives: +List<Experience.Alternative>) -> +List<OperationParameters.ChoiceValue>:
  match alternatives:
    case Nil{}: Nil{}
    case Con{Experience.Alternative{label, explanation, Experience.PrimaryDirectory{path}}, rest}: OperationParameters.ChoiceValue{path, label} <> primary_choices(rest)
    case Con{other, rest}: primary_choices(rest)

def observed_primary_choices(found: Maybe<&2, D.Workspace>, editor: U.Editor) -> +List<OperationParameters.ChoiceValue>:
  match found:
    case None{}: Nil{}
    case Some{workspace}: primary_choices(UX.decision_alternatives(UX.primary_decision(UX.collection(editor, workspace))))
def scoped_entry_choices(entry: OperationParameters.Entry, field: OperationParameters.Field, +observed: OperationParameters.Observed, editor: U.Editor, groups: +List<V.InputGroup>) -> +List<OperationParameters.ChoiceValue>:
  match field observed:
    case OperationParameters.WorkspacePrimary{} OperationParameters.WorkspaceValue{workspace}: primary_choices(UX.decision_alternatives(UX.primary_decision(UX.collection(editor, workspace))))
    case OperationParameters.WorkspacePrimary{} OperationParameters.ContextValue{preview, reviewers}: observed_primary_choices(context_workspace(preview), editor)
    case _ _: entry_choices(entry, field, observed, groups)

def approval_fact(+parent: Identity.Key, +key: String, +label: String, text: String) -> SurfaceTypes.Node:
  SurfaceTypes.Node{Identity.Part{parent, key}, key, label, SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{text}, Nil{}}

def restrict_different_reason(same: Bool, assessment: Experience.Assessment, reason: String) -> Experience.Assessment:
  match same:
    case True{}: assessment
    case False{}: UX.restricted(assessment, reason)

def final_assessment(availability: V.Availability, +assessment: Experience.Assessment) -> Experience.Assessment:
  match availability:
    case V.Unavailable{+reason}: restrict_different_reason(String.eq(reason, UX.assessment_reason(assessment)), assessment, reason)
    case _: assessment

def current_control_assessment(assessment: Experience.Assessment, control: InteractionTypes.Control) -> Maybe<&2, Experience.Assessment>:
  InteractionTypes.Control{key, label, prominence, input, availability} = control
  Some{final_assessment(availability, assessment)}

def current_editor_assessment(scene: V.EditorScene, state: InteractionTypes.State) -> Maybe<&2, Experience.Assessment>:
  V.EditorScene{identity, revision, groups, structure, assessment, declaration, feedback, waiting} = scene
  current_control_assessment(assessment, Core.control(state, declaration))

def current_draft_assessment(found: Maybe<&2, U.Draft>, pending: +List<E.Pending>, now: U32, world: M.World(), state: InteractionTypes.State) -> Maybe<&2, Experience.Assessment>:
  match found:
    case None{}: None{}
    case Some{draft}: current_editor_assessment(View.editor_scene(draft, pending, now, world), state)

def editor_current_assessment(editor: U.Editor, +state: InteractionTypes.State) -> Maybe<&2, Experience.Assessment>:
  +application = Core.application(state)
  +session = E.session(application)
  current_draft_assessment(E.find_draft(E.drafts(session), editor), E.pending(session), E.now(session), E.program(application), state)

def subject_repair_display(empty: Bool, +obstruction: Experience.Obstruction, parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match empty:
    case True{}: Nil{}
    case False{}: [approval_fact(parent, "field-repair", "Repair", UX.obstruction_message(obstruction))]

def subject_repair_found(found: Maybe<&2, Experience.Obstruction>, parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match found:
    case None{}: Nil{}
    case Some{+obstruction}: subject_repair_display(String.eq(UX.obstruction_code(obstruction), "empty_message"), obstruction, parent)

def subject_repair_assessment(assessment: Maybe<&2, Experience.Assessment>, subject: Experience.Subject, parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match assessment:
    case None{}: Nil{}
    case Some{assessment}: subject_repair_found(UX.subject_obstruction(subject, assessment), parent)

def subject_repair(+editor: U.Editor, field: OperationParameters.Field, parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  subject_repair_assessment(editor_current_assessment(editor, state), Experience.Subject{editor, field}, parent)

def field_node(+field: OperationParameters.FieldScene, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State, groups: +List<V.InputGroup>) -> SurfaceTypes.Node:
  OperationParameters.FieldScene{+field, label, entry} = field
  +observed = field_value(state, editor, field)
  +resolved_entry = actual_entry(field, entry, observed, state)
  SurfaceTypes.Node{Identity.Part{parent, OperationParameters.key(field)}, OperationParameters.key(field), label, SurfaceTypes.Field{}, SurfaceTypes.Edit{editor, field, resolved_entry, observed, scoped_entry_choices(resolved_entry, field, observed, editor, groups)}, List.append(&2, SurfaceTypes.Node, field_children(field, editor, Identity.Part{parent, OperationParameters.key(field)}, state), subject_repair(editor, field, Identity.Part{parent, OperationParameters.key(field)}, state))}

def configuration(body: U.Body) -> Maybe<&2, Context.Configuration>:
  match body:
    case U.NewTask{message, profile, effort, config, work}: Some{config}
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

def section_fields(entries: +List<OperationParameters.FieldScene>) -> +List<OperationParameters.Field>:
  match entries:
    case Nil{}: Nil{}
    case Con{OperationParameters.FieldScene{field, label, entry}, rest}: field <> section_fields(rest)

def sections(values: +List<OperationParameters.Section>, +editor: U.Editor, +parent: Identity.Key, +ordinal: Nat, +state: InteractionTypes.State, +groups: +List<V.InputGroup>) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{OperationParameters.Section{title, +entries}, rest}:
      SurfaceTypes.Node{Identity.Entity{parent, "section", Nat.show(ordinal)}, "section/" ++ Nat.show(ordinal), title, SurfaceTypes.Section{}, SurfaceTypes.ObjectGroup{UX.group_owner(editor, section_fields(entries))}, fields(entries, editor, Identity.Entity{parent, "section", Nat.show(ordinal)}, state, groups)} <>
        sections(rest, editor, parent, (ordinal + 1n : Nat), state, groups)

def feedback_nodes(+parent: Identity.Key, feedback: U.Feedback) -> +List<SurfaceTypes.Node>:
  match feedback:
    case U.Rejected{revision, +reason}: [SurfaceTypes.Node{Identity.Part{parent, "feedback"}, "submission-feedback", "Submission failed", SurfaceTypes.Alert{}, SurfaceTypes.ReadOnly{reason}, Nil{}}]
    case _: Nil{}

def feedback_surface(found: Maybe<&2, Experience.Feedback>, +parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match found:
    case None{}: Nil{}
    case Some{+value}:
      Experience.Feedback{editor, revision, +reason} = value
      [SurfaceTypes.Node{Identity.Part{parent, "feedback"}, "submission-feedback", "Submission failed", SurfaceTypes.Alert{}, SurfaceTypes.ActionFeedback{value}, [SurfaceTypes.Node{Identity.Part{parent, "reason"}, "submission-feedback/reason", reason, SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{reason}, Nil{}}]}]

def action_feedback_nodes(editor: U.Editor, feedback: U.Feedback, parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  feedback_surface(UX.feedback(editor, feedback), parent)

def visible_action_obstruction_selected(passive: Bool, obstruction: Experience.Obstruction, assessment: Experience.Assessment, parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match passive:
    case True{}: Nil{}
    case False{}: [SurfaceTypes.Node{Identity.Part{parent, "action-explanation"}, "action-explanation", UX.obstruction_message(obstruction), SurfaceTypes.Content{}, SurfaceTypes.ActionExplanation{assessment}, Nil{}}]

def visible_action_obstruction(found: Maybe<&2, Experience.Obstruction>, +assessment: Experience.Assessment, parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match found:
    case None{}: Nil{}
    case Some{+obstruction}:
      visible_action_obstruction_selected(UX.passive_obstruction(obstruction) || UX.obstruction_has_field(UX.obstruction_field(obstruction)), obstruction, assessment, parent)

def action_state_explanation(state: Experience.AssessmentState, +assessment: Experience.Assessment, +parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match state:
    case Experience.Blocked{}: visible_action_obstruction(UX.attention_obstruction(assessment), assessment, parent)
    case _: Nil{}


def action_explanation(+assessment: Experience.Assessment, +parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  action_state_explanation(UX.assessment_state(assessment), assessment, parent)


def supporting_node(visible: Bool, support: Experience.Support, +property: Experience.Property, parent: Identity.Key, control: InteractionTypes.Control) -> +List<SurfaceTypes.Node>:
  match visible:
    case False{}: Nil{}
    case True{}:
      InteractionTypes.Control{+identity, label, prominence, input, availability} = control
      [SurfaceTypes.Node{Identity.Part{parent, identity}, identity, label, action_role(prominence), SurfaceTypes.SupportingControl{support, property, input, availability}, Nil{}}]

def supporting_project(visible: Bool, support: Experience.Support, +property: Experience.Property, +parent: Identity.Key, control: InteractionTypes.Control, selected: Maybe<&2, Nat>) -> +List<SurfaceTypes.Node>:
  match visible:
    case False{}: Nil{}
    case True{}: [SurfaceTypes.Node{Identity.Part{parent, "project"}, "project-chooser", "", SurfaceTypes.Section{}, SurfaceTypes.ProjectChooser{selected}, supporting_node(True{}, support, property, parent, control)}]

def supporting_control_owned(+support: Experience.Support, +property: Experience.Property, +parent: Identity.Key, +control: InteractionTypes.Control, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match control:
    case InteractionTypes.Control{identity, label, prominence, InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.OpenPanel{U.ProjectPicker{}, trigger}}}}, availability}:
      +application = Core.application(state)
      +session = E.session(application)
      +world = E.program(application)
      supporting_project(UX.support_visible(support), support, property, parent, control, View.active_project(E.route(session), session, world))
    case _: supporting_node(UX.support_visible(support), support, property, parent, control)

def workspace_retry_control(needed: Bool, +editor: U.Editor, parent: Identity.Key, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match needed:
    case False{}: Nil{}
    case True{}: [declared(parent, View.control("workspace/retry/" ++ U.editor_key(editor), "Retry", U.RetryWorkspace{editor}), state)]

def property_repair_found(found: Maybe<&2, Experience.Obstruction>, +property: Experience.Property, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match found:
    case None{}: Nil{}
    case Some{+obstruction}:
      +key: Identity.Key = Identity.Entity{parent, "repair", UX.subject_key(Experience.Subject{UX.property_editor(property), UX.property_repair_field(property)})}
      SurfaceTypes.Node{key, "property-repair/" ++ UX.subject_key(Experience.Subject{UX.property_editor(property), UX.property_repair_field(property)}), UX.obstruction_message(obstruction), SurfaceTypes.Alert{}, SurfaceTypes.ReadOnly{UX.obstruction_message(obstruction)}, Nil{}} <>
        workspace_retry_control(String.eq(UX.obstruction_code(obstruction), "workspace_observation_failed"), UX.property_editor(property), key, state)

def property_repair_assessment(assessment: Maybe<&2, Experience.Assessment>, +property: Experience.Property, parent: Identity.Key, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match assessment:
    case None{}: Nil{}
    case Some{assessment}: property_repair_found(UX.property_obstruction(property, assessment), property, parent, state)

def property_repair(+property: Experience.Property, parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  property_repair_assessment(editor_current_assessment(UX.property_editor(property), state), property, parent, state)

def supporting_property_repair(visible: Bool, property: Experience.Property, parent: Identity.Key, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match visible:
    case False{}: Nil{}
    case True{}: property_repair(property, parent, state)

def supporting_controls(values: +List<V.ComposerControl>, +action: Experience.ActionUnit, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{V.ComposerControl{+property, declaration}, rest}:
      +support = UX.property_support(action, property)
      List.append(&2, SurfaceTypes.Node, List.append(&2, SurfaceTypes.Node, supporting_control_owned(support, property, parent, Core.control(state, declaration), state), supporting_property_repair(UX.support_visible(support), property, parent, state)), supporting_controls(rest, action, parent, state))

def composer_creation_context(controls: +List<V.ComposerControl>, action: Experience.ActionUnit, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match controls:
    case Nil{}: Nil{}
    case Con{first, rest}: [region(parent, "creation-context", "Task context", SurfaceTypes.Toolbar{}, supporting_controls(first <> rest, action, parent, state))]

def action_commit_control(assessment: Experience.Assessment, +parent: Identity.Key, control: InteractionTypes.Control) -> SurfaceTypes.Node:
  InteractionTypes.Control{+identity, label, prominence, input, +availability} = control
  SurfaceTypes.Node{Identity.Part{parent, identity}, identity, label, action_role(prominence), SurfaceTypes.ActionCommit{final_assessment(availability, assessment), input, availability}, Nil{}}


def canonical_commit(+action: Experience.ActionUnit, +assessment: Experience.Assessment, declaration: V.ControlDeclaration, parent: Identity.Key, state: InteractionTypes.State) -> SurfaceTypes.Node:
  V.ControlDeclaration{identity, label, prominence, input, availability} = declaration
  action_commit_control(assessment, parent, Core.control(state, V.ControlDeclaration{identity, label, prominence, UX.commit(action), availability}))

def action_control_explanation(assessment: Experience.Assessment, parent: Identity.Key, control: InteractionTypes.Control) -> +List<SurfaceTypes.Node>:
  InteractionTypes.Control{identity, label, prominence, input, availability} = control
  action_explanation(final_assessment(availability, assessment), parent)

def canonical_explanation(+action: Experience.ActionUnit, assessment: Experience.Assessment, declaration: V.ControlDeclaration, parent: Identity.Key, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  V.ControlDeclaration{identity, label, prominence, input, availability} = declaration
  action_control_explanation(assessment, parent, Core.control(state, V.ControlDeclaration{identity, label, prominence, UX.commit(action), availability}))

def action_footer(controls: +List<V.ComposerControl>, +action: Experience.ActionUnit, +assessment: Experience.Assessment, submit: V.ControlDeclaration, +parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  region(parent, "actions", "Actions", SurfaceTypes.ComposerActions{}, [region(parent, "supporting-controls", "Supporting controls", SurfaceTypes.Toolbar{}, supporting_controls(controls, action, parent, state)), canonical_commit(action, assessment, submit, parent, state)])

def ordinary_editor(view: Maybe<&2, V.EditorScene>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match view:
    case None{}: Nil{}
    case Some{V.EditorScene{+identity, +revision, groups, structure, +assessment, +submit, feedback, +pending}}:
      List.append(&2, SurfaceTypes.Node, sections(structure, identity, parent, 0n, state, groups), List.append(&2, SurfaceTypes.Node, List.append(&2, SurfaceTypes.Node, canonical_explanation(UX.action(identity, revision, pending), assessment, submit, parent, state), action_feedback_nodes(identity, feedback, parent)), [dialog_actions(parent, [canonical_commit(UX.action(identity, revision, pending), assessment, submit, parent, state)])]))

def expected_composer(view: Maybe<&2, V.ComposerScene>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match view:
    case None{}: Nil{}
    case Some{V.ComposerScene{+identity, +revision, message, phase, creation_context, execution_controls, context, +assessment, +submit, feedback, +pending}}:
      +key : Identity.Key = Identity.Entity{parent, "composer", U.editor_key(identity)}
      List.append(&2, SurfaceTypes.Node, composer_creation_context(creation_context, UX.action(identity, revision, pending), key, state),
        [SurfaceTypes.Node{key, "composer/" ++ U.editor_key(identity), "Message", SurfaceTypes.Composer{}, SurfaceTypes.ActionUnit{UX.action(identity, revision, pending)},
          field_node(OperationParameters.FieldScene{OperationParameters.MessageText{}, "Message", OperationParameters.Multiline{}}, identity, key, state, Nil{}) <>
            List.append(&2, SurfaceTypes.Node, List.append(&2, SurfaceTypes.Node, canonical_explanation(UX.action(identity, revision, pending), assessment, submit, key, state), action_feedback_nodes(identity, feedback, key)), [action_footer(execution_controls, UX.action(identity, revision, pending), assessment, submit, key, state)])}])

def composer(view: Maybe<&2, V.ComposerScene>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match view:
    case None{}: Nil{}
    case Some{V.ComposerScene{+identity, +revision, message, phase, creation_context, execution_controls, context, +assessment, +submit, feedback, +pending}}:
      +composer_key : Identity.Key = Identity.Entity{parent, "composer", U.editor_key(identity)}
      List.append(&2, SurfaceTypes.Node, composer_creation_context(creation_context, UX.action(identity, revision, pending), composer_key, state),
        [SurfaceTypes.Node{composer_key, "composer/" ++ U.editor_key(identity), "Message", SurfaceTypes.Composer{}, SurfaceTypes.ActionUnit{UX.action(identity, revision, pending)},
          field_node(OperationParameters.FieldScene{OperationParameters.MessageText{}, "Message", OperationParameters.Multiline{}}, identity, composer_key, state, Nil{}) <>
            List.append(&2, SurfaceTypes.Node, List.append(&2, SurfaceTypes.Node, canonical_explanation(UX.action(identity, revision, pending), assessment, submit, composer_key, state), action_feedback_nodes(identity, feedback, composer_key)), [action_footer(execution_controls, UX.action(identity, revision, pending), assessment, submit, composer_key, state)])}])

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

def task_graph_message(message: G.Message) -> String:
  approval_serialized(J.show(GraphCodec.message_json(message)))

def resolved_task_graph_endpoint(key: String, found: Maybe<&2, Nat>) -> String:
  match found:
    case None{}: key ++ " (unavailable)"
    case Some{task}: key ++ " (Task #" ++ Nat.show(task) ++ ")"

def task_graph_endpoint(+key: String, nodes: +List<G.ResolvedNode>) -> String:
  resolved_task_graph_endpoint(key, G.resolve(key, nodes))

def task_graph_node_entry(entry: Maybe<&2, V.TaskEntry>, parent: Identity.Key, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match entry:
    case None{}: [project_fact(Identity.Part{parent, "status"}, "Task status", "Unavailable")]
    case Some{task}: task_entries([task], parent, state)

def task_graph_node_rows(nodes: +List<V.TaskGraphNode>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match nodes:
    case Nil{}: Nil{}
    case Con{V.TaskGraphNode{+key, +task, entry}, rest}:
      SurfaceTypes.Node{Identity.Entity{parent, "node", key}, "task-graph/node", key ++ " · Task #" ++ Nat.show(task), SurfaceTypes.Section{}, SurfaceTypes.ObjectGroup{Experience.Task{task}},
        task_graph_node_entry(entry, Identity.Entity{parent, "node", key}, state)} <> task_graph_node_rows(rest, parent, state)

def task_graph_action_rows(actions: +List<G.Action>, +source: String, +nodes: +List<G.ResolvedNode>, +parent: Identity.Key, +ordinal: Nat) -> +List<SurfaceTypes.Node>:
  match actions:
    case Nil{}: Nil{}
    case Con{G.Action{target, message}, rest}:
      project_fact(Identity.Entity{parent, "action", Nat.show(ordinal)}, "Output delivery",
        task_graph_endpoint(source, nodes) ++ " → " ++ task_graph_endpoint(target, nodes) ++ ": " ++ task_graph_message(message)) <>
        task_graph_action_rows(rest, source, nodes, parent, Nat.add(ordinal, 1n))

def task_graph_rule_rows(rules: +List<G.Rule>, +nodes: +List<G.ResolvedNode>, +parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match rules:
    case Nil{}: Nil{}
    case Con{G.Rule{+key, source, actions}, rest}:
      SurfaceTypes.Node{Identity.Entity{parent, "rule", key}, "task-graph/rule", key, SurfaceTypes.Section{}, SurfaceTypes.Region{},
        task_graph_action_rows(actions, source, nodes, Identity.Entity{parent, "rule", key}, 0n)} <> task_graph_rule_rows(rest, nodes, parent)

def task_graph_receipt_rows(receipts: +List<G.Receipt>, +parent: Identity.Key, +ordinal: Nat) -> +List<SurfaceTypes.Node>:
  match receipts:
    case Nil{}: Nil{}
    case Con{G.Receipt{source, rule, target, reply}, rest}:
      project_fact(Identity.Entity{parent, "receipt", Nat.show(ordinal)}, "Last delivery result",
        "Task #" ++ Nat.show(source) ++ " → Task #" ++ Nat.show(target) ++ " (" ++ rule ++ "): " ++ approval_value(reply)) <>
        task_graph_receipt_rows(rest, parent, Nat.add(ordinal, 1n))

def task_graph_observation(+id: Nat, +value: G.Graph, nodes: +List<V.TaskGraphNode>, edit: V.ControlDeclaration, remove: V.ControlDeclaration, parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  +key : Identity.Key = Identity.Entity{parent, "task-graph", Nat.show(id)}
  SurfaceTypes.Node{key, "task-graph/" ++ Nat.show(id), G.name(value), SurfaceTypes.Section{}, SurfaceTypes.ObjectGroup{UX.root_object(U.TaskGraphEditor{Some{id}})},
    [region(key, "actions", "", SurfaceTypes.Section{}, [declared(key, edit, state), declared(key, remove, state)]),
     region(key, "nodes", "Tasks", SurfaceTypes.Section{}, task_graph_node_rows(nodes, key, state)),
     region(key, "rules", "Output rules", SurfaceTypes.Section{}, task_graph_rule_rows(G.rules(value), G.nodes(value), key)),
     region(key, "receipts", "Last delivery results", SurfaceTypes.Section{}, task_graph_receipt_rows(G.receipts(value), key, 0n))]}

def task_graphs(values: +List<V.TaskGraphScene>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{V.TaskGraphScene{id, value, nodes, edit, remove}, rest}:
      task_graph_observation(id, value, nodes, edit, remove, parent, state) <> task_graphs(rest, parent, state)

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
  SurfaceTypes.Node{Identity.Part{Identity.Part{Identity.Part{Identity.Part{parent, "creation"}, "introduction"}, "creation"}, "title"}, "creation/title", heading, SurfaceTypes.Heading{}, SurfaceTypes.InformationText{Information.IntroductionTitle{}}, Nil{}}

def creation_project_node(value: V.CreationIntroduction, +parent: Identity.Key, state: InteractionTypes.State) -> SurfaceTypes.Node:
  V.CreationIntroduction{heading, summary, context, project, choose} = value
  SurfaceTypes.Node{Identity.Part{Identity.Part{parent, "creation"}, "project"}, "project-chooser", "", SurfaceTypes.Section{}, SurfaceTypes.ProjectChooser{View.project_choice_id(project)}, [declared(parent, choose, state)]}

def creation_context_node(value: V.CreationIntroduction, parent: Identity.Key) -> SurfaceTypes.Node:
  V.CreationIntroduction{heading, summary, context, project, choose} = value
  SurfaceTypes.Node{Identity.Part{Identity.Part{Identity.Part{Identity.Part{parent, "creation"}, "introduction"}, "creation"}, "context"}, "creation/context", "Workspace configuration", SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{summary}, Nil{}}

def creation_introduction_nodes(+value: V.CreationIntroduction, +parent: Identity.Key, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  [page_region(parent, Composition.CreationIntroduction{}, Composition.BodyPosition{}, [creation_title_node(value, parent)])]

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
    case V.TaskGraphsPage{values, create}:
      [page_region(parent, Composition.CollectionTitle{}, Composition.HeadingPosition{}, [region(parent, "heading", "Task graphs", SurfaceTypes.Heading{}, Nil{})]),
       page_region(parent, Composition.CollectionActions{}, Composition.HeadingPosition{}, [declared(parent, create, state)]),
       page_region(parent, Composition.TaskGraphEntries{}, Composition.BodyPosition{}, task_graphs(values, parent, state))]
    case V.MissingObject{message}:
      [page_region(parent, Composition.UnavailableMessage{}, Composition.BodyPosition{}, [SurfaceTypes.Node{Identity.Part{parent, "missing"}, "missing", "Unavailable", SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{message}, Nil{}}])]

def page_conversation(view: V.Page) -> Maybe<&2, Conversation.Identity>:
  match view:
    case V.TaskPage{V.TaskScene{id, title, status, context, timeline, previews, input, details, actions}}: Some{Conversation.identity(timeline)}
    case _: None{}

def page(+view: V.Page, state: InteractionTypes.State) -> SurfaceTypes.Node:
  SurfaceTypes.Node{Identity.Place{"/main"}, "main", "Content", SurfaceTypes.Main{}, SurfaceTypes.PageContext{page_conversation(view)}, page_contents(view, Identity.Place{"/main"}, state)}

def choice_control(selected: Bool, description: String, control: InteractionTypes.Control, parent: Identity.Key) -> SurfaceTypes.Node:
  InteractionTypes.Control{+identity, label, prominence, input, +availability} = control
  SurfaceTypes.Node{Identity.Part{parent, identity}, identity, label, SurfaceTypes.Button{}, SurfaceTypes.Choice{SurfaceTypes.SingleChoice{}, None{}, selected, description, input, availability}, Nil{}}

def declared_choice(selected: Bool, description: String, declaration: V.ControlDeclaration, parent: Identity.Key, state: InteractionTypes.State) -> SurfaceTypes.Node:
  choice_control(selected, description, Core.control(state, declaration), parent)

def model_choice_availability(permitted: Bool) -> V.Availability:
  match permitted:
    case True{}: V.Available{}
    case False{}: V.Unavailable{"The model has no permitted reasoning selection"}

def delivery_selected(current: U.Delivery, candidate: U.Delivery) -> Bool:
  match current candidate:
    case U.Send{} U.Send{}: True{}
    case U.Steer{} U.Steer{}: True{}
    case _ _: False{}

def decision_choice_resolved(+found: Maybe<&2, U.Input>, +decision: Experience.Decision, alternative: Experience.Alternative, +parent: Identity.Key, state: InteractionTypes.State) -> SurfaceTypes.Node:
  match found alternative:
    case Some{input} Experience.Alternative{label, explanation, +value}: declared_choice(UX.selected(decision, value), explanation, V.ControlDeclaration{UX.value_key(value), label, V.Secondary{}, input, V.Available{}}, parent, state)
    case None{} Experience.Alternative{label, +explanation, +value}: SurfaceTypes.Node{Identity.Part{parent, UX.value_key(value)}, UX.value_key(value), label, SurfaceTypes.Content{}, SurfaceTypes.InformationText{Information.Status{}}, [SurfaceTypes.Node{Identity.Part{parent, "reason"}, "decision/unavailable", explanation, SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{explanation}, Nil{}}]}

def decision_choices(alternatives: +List<Experience.Alternative>, +decision: Experience.Decision, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match alternatives:
    case Nil{}: Nil{}
    case Con{+alternative, rest}:
      Experience.Alternative{label, explanation, value} = alternative
      decision_choice_resolved(UX.choose(decision, value), decision, alternative, parent, state) <> decision_choices(rest, decision, parent, state)

def decision_content(availability: Experience.Availability, +decision: Experience.Decision, +parent: Identity.Key, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match availability:
    case Experience.Available{}: decision_choices(UX.decision_alternatives(decision), decision, parent, state)
    case Experience.Unavailable{+reason}: [SurfaceTypes.Node{Identity.Part{parent, "status"}, "decision/status", reason, SurfaceTypes.Content{}, SurfaceTypes.InformationText{Information.Status{}}, [SurfaceTypes.Node{Identity.Part{parent, "reason"}, "decision/reason", reason, SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{reason}, Nil{}}]}]

def decision_surface(+decision: Experience.Decision, +parent: Identity.Key, state: InteractionTypes.State) -> SurfaceTypes.Node:
  +key : Identity.Key = Identity.Part{parent, UX.subject_key(UX.decision_subject(decision))}
  SurfaceTypes.Node{key, "decision/" ++ UX.subject_key(UX.decision_subject(decision)), UX.decision_question(decision), SurfaceTypes.Section{}, SurfaceTypes.DecisionGroup{decision}, decision_content(UX.decision_availability(decision), decision, key, state)}

def profile_alternatives(profiles: +List<D.Profile>) -> +List<Experience.Alternative>:
  match profiles:
    case Nil{}: Nil{}
    case Con{+profile, rest}:
      D.Profile{key, provider, name, policy, options} = profile
      Experience.Alternative{name, provider, Experience.Model{profile}} <> profile_alternatives(rest)

def effort_alternatives(choices: +List<OperationParameters.ChoiceValue>) -> +List<Experience.Alternative>:
  match choices:
    case Nil{}: Nil{}
    case Con{OperationParameters.ChoiceValue{value, +label}, rest}: Experience.Alternative{label, label, Experience.Effort{value}} <> effort_alternatives(rest)

def admitted_model_alternatives(+subject: Experience.Subject, +observed: OperationParameters.Observed, profiles: +List<D.Profile>) -> +List<Experience.Alternative>:
  match profiles:
    case Nil{}: Nil{}
    case Con{profile, rest}: List.append(&2, Experience.Alternative, UX.decision_alternatives(UX.decision(subject, observed, "Model", profile_alternatives([profile]))), admitted_model_alternatives(subject, observed, rest))

def model_effort_surface(entry: OperationParameters.Entry, +observation: OperationParameters.Observed, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State, groups: +List<V.InputGroup>) -> SurfaceTypes.Node:
  match entry:
    case OperationParameters.Choice{}: decision_surface(UX.decision(Experience.Subject{editor, OperationParameters.ReasoningEffort{}}, observation, "Reasoning effort", effort_alternatives(FieldOptions.choices(OperationParameters.ReasoningEffort{}, observation, groups))), parent, state)
    case OperationParameters.SingleLine{}: field_node(OperationParameters.FieldScene{OperationParameters.ReasoningEffort{}, "Reasoning effort", OperationParameters.SingleLine{}}, editor, parent, state, groups)
    case OperationParameters.DisplayOnly{}: field_node(OperationParameters.FieldScene{OperationParameters.ReasoningEffort{}, "Reasoning effort", OperationParameters.DisplayOnly{}}, editor, parent, state, groups)
    case OperationParameters.Multiline{}: field_node(OperationParameters.FieldScene{OperationParameters.ReasoningEffort{}, "Reasoning effort", OperationParameters.Multiline{}}, editor, parent, state, groups)
    case OperationParameters.StructuredText{}: field_node(OperationParameters.FieldScene{OperationParameters.ReasoningEffort{}, "Reasoning effort", OperationParameters.StructuredText{}}, editor, parent, state, groups)
    case OperationParameters.MultipleChoices{}: field_node(OperationParameters.FieldScene{OperationParameters.ReasoningEffort{}, "Reasoning effort", OperationParameters.MultipleChoices{}}, editor, parent, state, groups)
    case OperationParameters.PositiveInteger{}: field_node(OperationParameters.FieldScene{OperationParameters.ReasoningEffort{}, "Reasoning effort", OperationParameters.PositiveInteger{}}, editor, parent, state, groups)
    case OperationParameters.DirectoryCollection{}: field_node(OperationParameters.FieldScene{OperationParameters.ReasoningEffort{}, "Reasoning effort", OperationParameters.DirectoryCollection{}}, editor, parent, state, groups)
    case OperationParameters.FileCollection{}: field_node(OperationParameters.FieldScene{OperationParameters.ReasoningEffort{}, "Reasoning effort", OperationParameters.FileCollection{}}, editor, parent, state, groups)
def model_decisions(+profile: String, +reasoning: String, +choices: +List<D.Profile>, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State, +groups: +List<V.InputGroup>) -> +List<SurfaceTypes.Node>:
  +observation : OperationParameters.Observed = OperationParameters.ModelValue{profile, reasoning}
  decision_surface(UX.decision(Experience.Subject{editor, OperationParameters.ModelProfile{}}, observation, "Model", admitted_model_alternatives(Experience.Subject{editor, OperationParameters.ModelProfile{}}, observation, choices)), parent, state) <>
  [model_effort_surface(actual_entry(OperationParameters.ReasoningEffort{}, OperationParameters.Choice{}, observation, state), observation, editor, parent, state, groups)]

def picker_fields(values: +List<V.InputGroup>, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{V.ModelInput{+profile, +reasoning, +choices}, +rest}: List.append(&2, SurfaceTypes.Node, model_decisions(profile, reasoning, choices, editor, parent, state, V.ModelInput{profile, reasoning, choices} <> rest), picker_fields(rest, editor, parent, state))
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

def observation_facts(+value: Context.Observation) -> String:
  "Permissions · " ++ UX.permission_value(value) ++ " · " ++ UX.permission_detail(value) ++ "; " ++ UX.permission_source_detail(value)

def context_summary_node(+value: Context.Observation, +parent: Identity.Key, state: InteractionTypes.State) -> SurfaceTypes.Node:
  +observed_application = Core.application(state)
  +world = E.program(observed_application)
  +source = "Working directories · " ++ View.execution_source_summary(value, world)
  +facts = observation_facts(value)
  SurfaceTypes.Node{Identity.Part{parent, "source"}, "context/source", "Execution context", SurfaceTypes.Content{}, SurfaceTypes.ContextSummary{value},
    [SurfaceTypes.Node{Identity.Part{Identity.Part{parent, "source"}, "workspace-source"}, "context/workspace-source", source, SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{source}, Nil{}},
     SurfaceTypes.Node{Identity.Part{Identity.Part{parent, "source"}, "permissions"}, "context/permissions", facts, SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{facts}, Nil{}}]}

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

def sandbox_alternative(+mode: D.SandboxMode) -> Experience.Alternative:
  Experience.Alternative{sandbox_label(mode), sandbox_description(mode), Experience.Filesystem{mode}}

def sandbox_choice(+mode: D.SandboxMode, +current: D.SandboxMode, +network: Bool, +editor: U.Editor, parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  +alternative = sandbox_alternative(mode)
  +decision = UX.decision(Experience.Subject{editor, OperationParameters.SandboxMode{}}, field_value(state, editor, OperationParameters.SandboxMode{}), "Filesystem access", [alternative])
  decision_choice_resolved(UX.choose(decision, Experience.Filesystem{mode}), decision, alternative, parent, state)

def sandbox_choices(+sandbox: D.Sandbox, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  decision_surface(UX.decision(Experience.Subject{editor, OperationParameters.SandboxMode{}}, field_value(state, editor, OperationParameters.SandboxMode{}), "Filesystem access", [sandbox_alternative(D.ReadOnly{}), sandbox_alternative(D.WorkspaceWrite{})]), parent, state)

def approval_profile_key(choice: Context.ApprovalChoice) -> String:
  match choice:
    case Context.AutomaticReview{profile}: profile
    case _: ""

def approval_description(choice: Context.ApprovalChoice) -> String:
  match choice:
    case Context.Ask{}: "Ask before running actions that require approval."
    case Context.Unrestricted{}: "Run actions without approval prompts."
    case Context.AutomaticReview{profile}: "Use this model to review approval requests."

def approval_alternative(+choice: Context.ApprovalChoice, profile: Maybe<&2, D.Profile>) -> Experience.Alternative:
  Experience.Alternative{View.execution_approval_summary(choice, profile), approval_description(choice), Experience.Approval{choice}}

def approval_choice_node(+choice: Context.ApprovalChoice, +current: Context.ApprovalChoice, reviewer: Maybe<&2, D.Profile>, +editor: U.Editor, parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  +alternative = approval_alternative(choice, reviewer)
  +decision = UX.decision(Experience.Subject{editor, OperationParameters.ApprovalPolicy{}}, field_value(state, editor, OperationParameters.ApprovalPolicy{}), "Approval policy", [alternative])
  decision_choice_resolved(UX.choose(decision, Experience.Approval{choice}), decision, alternative, parent, state)

def reviewer_choices(profiles: +List<D.Profile>, +current: Context.ApprovalChoice, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match profiles:
    case Nil{}: Nil{}
    case Con{D.Profile{+key, provider, name, policy, options}, rest}:
      approval_choice_node(Context.AutomaticReview{key}, current, Some{D.Profile{key, provider, name, policy, options}}, editor, Identity.Entity{parent, "profile", key}, state) <> reviewer_choices(rest, current, editor, parent, state)

def reviewer_alternatives(profiles: +List<D.Profile>) -> +List<Experience.Alternative>:
  match profiles:
    case Nil{}: Nil{}
    case Con{+profile, rest}:
      D.Profile{key, provider, name, policy, options} = profile
      approval_alternative(Context.AutomaticReview{key}, Some{profile}) <> reviewer_alternatives(rest)

def approval_choices(+current: Context.ApprovalChoice, reviewers: +List<D.Profile>, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  decision_surface(UX.decision(Experience.Subject{editor, OperationParameters.ApprovalPolicy{}}, field_value(state, editor, OperationParameters.ApprovalPolicy{}), "Approval policy", approval_alternative(Context.Ask{}, None{}) <> approval_alternative(Context.Unrestricted{}, None{}) <> reviewer_alternatives(reviewers)), parent, state)

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

def network_alternative(+enabled: Bool) -> Experience.Alternative:
  Experience.Alternative{network_label(enabled), network_description(enabled), Experience.Network{enabled}}

def network_choice(+mode: D.SandboxMode, current: Bool, +target: Bool, +editor: U.Editor, parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  +alternative = network_alternative(target)
  +decision = UX.decision(Experience.Subject{editor, OperationParameters.NetworkAccess{}}, field_value(state, editor, OperationParameters.NetworkAccess{}), "Network access", [alternative])
  decision_choice_resolved(UX.choose(decision, Experience.Network{target}), decision, alternative, parent, state)

def network_choices(sandbox: D.Sandbox, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  decision_surface(UX.decision(Experience.Subject{editor, OperationParameters.NetworkAccess{}}, field_value(state, editor, OperationParameters.NetworkAccess{}), "Network access", [network_alternative(False{}), network_alternative(True{})]), parent, state)

def property_scope(editor: U.Editor) -> String:
  match editor:
    case U.NewTaskEditor{work}: "Applies to this new task"
    case U.MessageEditor{task}: "Applies to this task"
    case U.ForkEditor{task}: "Applies to the new fork"
    case U.ProjectEditor{project}: "Defaults for future tasks using this project. Existing task directories and explicit overrides stay unchanged."
    case U.AgentEditor{agent}: "Applies to this agent profile"
    case _: "Applies to this editor"

# NOTE: Rows retain original interactive descendants; decoration does not own an action.
def activity_row(role: SurfaceTypes.ActivityRowRole, node: SurfaceTypes.Node) -> SurfaceTypes.Node:
  SurfaceTypes.Node{+key, +semantic, label, original_role, meaning, children} = node
  SurfaceTypes.Node{Identity.Part{key, "activity-row"}, semantic ++ "/row", "", SurfaceTypes.Content{}, SurfaceTypes.ActivityRow{role}, [SurfaceTypes.Node{key, semantic, label, original_role, meaning, children}]}

def activity_rows(+role: SurfaceTypes.ActivityRowRole, nodes: +List<SurfaceTypes.Node>) -> +List<SurfaceTypes.Node>:
  match nodes:
    case Nil{}: Nil{}
    case Con{node, rest}: activity_row(role, node) <> activity_rows(role, rest)

def activity_requested_focus(field: Maybe<&2, OperationParameters.Field>, editor: U.Editor) -> Maybe<&2, Experience.Subject>:
  match field:
    case None{}: None{}
    case Some{field}: Some{Experience.Subject{editor, field}}

# A read-only source child does not change the observation of its owning view.
def activity_observation_layers(layers: +List<E.Layer>) -> +List<E.Layer>:
  match layers:
    case Con{E.Layer{U.PropertySource{origin}, trigger, initial, query, occurrence, expanded, field, parameter_buffer}, rest}: activity_observation_layers(rest)
    case other: other

def activity_current_view(+activity: Activity.Activity, +state: InteractionTypes.State) -> Activity.View:
  +editor = Activity.scope(activity)
  +layers = activity_observation_layers(E.layers(E.session(Core.application(state))))
  Activity.view(activity, activity_requested_focus(E.requested_decision(layers, editor), editor), E.property_source_expanded(layers, editor))

def activity_subject_title(subject: Experience.Subject) -> String:
  Experience.Subject{editor, field} = subject
  match field:
    case OperationParameters.ModelProfile{}: "Model"
    case OperationParameters.ReasoningEffort{}: "Reasoning parameter"
    case OperationParameters.ApprovalPolicy{}: "Execution strategy"
    case OperationParameters.SandboxMode{}: "Filesystem access"
    case OperationParameters.NetworkAccess{}: "Network access"
    case OperationParameters.ApprovalReviewer{}: "Reviewing model"
    case OperationParameters.ProjectName{}: "Name"
    case _: OperationParameters.key(field)

def activity_permission_sandbox(observation: Context.Observation) -> Maybe<&2, D.Sandbox>:
  match observation:
    case Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}: Some{Context.unwrap_sandbox(sandbox)}
    case Context.CommittedExecution{Context.EffectiveContext{task, D.TaskContext{workspace, sandbox, approval, project}, guidance, access}}: Some{sandbox}
    case _: None{}

def activity_permission_approval(observation: Context.Observation) -> Maybe<&2, Context.ApprovalChoice>:
  match observation:
    case Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}: Some{Context.observed_approval(approval)}
    case Context.CommittedExecution{Context.EffectiveContext{task, D.TaskContext{workspace, sandbox, approval, project}, guidance, access}}: Some{Context.approval_choice(approval)}
    case _: None{}

def activity_reviewer_value(choice: Maybe<&2, Context.ApprovalChoice>) -> String:
  match choice:
    case Some{Context.AutomaticReview{profile}}: profile
    case _: "No automatic reviewing model"

def activity_permission_sandbox_value(field: OperationParameters.Field, found: Maybe<&2, D.Sandbox>) -> String:
  match field found:
    case OperationParameters.SandboxMode{} Some{D.Sandbox{mode, network}}: D.sandbox_mode_name(mode)
    case OperationParameters.NetworkAccess{} Some{D.Sandbox{mode, network}}: Context.network_summary(D.Sandboxed{}, network)
    case _ _: "Unavailable"

def activity_permission_policy_value(found: Maybe<&2, Context.ApprovalChoice>) -> String:
  match found:
    case Some{choice}: Context.approval_option(choice)
    case None{}: "Unavailable"

def activity_permission_access(observation: Context.Observation) -> Maybe<&2, D.ExecutionAccess>:
  match observation:
    case Context.DraftExecution{preview}: Context.preview_access(preview)
    case Context.CommittedExecution{Context.EffectiveContext{task, context, guidance, access}}: Some{access}

def activity_permission_effective_value(access: Maybe<&2, D.ExecutionAccess>, +field: OperationParameters.Field, observation: Context.Observation) -> String:
  match access field:
    case Some{D.Unrestricted{}} OperationParameters.SandboxMode{}: "Full access"
    case Some{D.Unrestricted{}} OperationParameters.NetworkAccess{}: "Network available"
    case _ _: activity_permission_sandbox_value(field, activity_permission_sandbox(observation))

def activity_permission_subject_value(+field: OperationParameters.Field, +observation: Context.Observation) -> String:
  match field:
    case OperationParameters.SandboxMode{}: activity_permission_effective_value(activity_permission_access(observation), field, observation)
    case OperationParameters.NetworkAccess{}: activity_permission_effective_value(activity_permission_access(observation), field, observation)
    case OperationParameters.ApprovalReviewer{}: activity_reviewer_value(activity_permission_approval(observation))
    case OperationParameters.ApprovalPolicy{}: activity_permission_policy_value(activity_permission_approval(observation))
    case _: ""

def activity_model_subject_value(field: OperationParameters.Field, property: Experience.Property, reasoning: String) -> String:
  match field:
    case OperationParameters.ModelProfile{}: UX.property_value(property)
    case OperationParameters.ReasoningEffort{}: reasoning
    case _: ""

def activity_subject_value_context(model: Maybe<&2, OperationParameters.Observed>, permission: Maybe<&2, Context.Observation>, editor: U.Editor, field: OperationParameters.Field, property: Experience.Property, state: InteractionTypes.State) -> String:
  match model permission:
    case Some{OperationParameters.ModelValue{profile, reasoning}} _: activity_model_subject_value(field, property, reasoning)
    case None{} Some{observation}: activity_permission_subject_value(field, observation)
    case _ _: FieldOptions.observed(field_value(state, editor, field))

def activity_subject_value_parts(editor: U.Editor, field: OperationParameters.Field, +property: Experience.Property, state: InteractionTypes.State) -> String:
  activity_subject_value_context(UX.property_model_context(property), UX.property_permission_context(property), editor, field, property, state)

def activity_subject_value(subject: Experience.Subject, property: Experience.Property, +state: InteractionTypes.State) -> String:
  Experience.Subject{editor, field} = subject
  activity_subject_value_parts(editor, field, property, state)

def activity_parameter_observed(buffer: Maybe<&2, String>, observed: OperationParameters.Observed) -> OperationParameters.Observed:
  match buffer observed:
    case Some{value} OperationParameters.ModelValue{profile, current}: OperationParameters.ModelValue{profile, value}
    case _ original: original

# NOTE: Read-only controls output the value without their name. The retained
# subject therefore supplies an explicit caption beside that same observed value.
def activity_readonly_field(+subject: Experience.Subject, value: OperationParameters.Observed, parent: Identity.Key) -> SurfaceTypes.Node:
  Experience.Subject{+editor, +field} = subject
  +key: Identity.Key = Identity.Part{parent, "fact/" ++ UX.subject_key(subject)}
  +name = activity_subject_title(subject)
  SurfaceTypes.Node{key, "fact/" ++ UX.subject_key(subject), "", SurfaceTypes.Content{}, SurfaceTypes.Region{},
    [SurfaceTypes.Node{Identity.Part{key, "label"}, "fact/label", name, SurfaceTypes.Content{}, SurfaceTypes.InformationText{Information.FieldLabel{}}, Nil{}},
     SurfaceTypes.Node{Identity.Part{key, "value"}, "fact/value", name, SurfaceTypes.Field{}, SurfaceTypes.Edit{editor, field, OperationParameters.DisplayOnly{}, value, Nil{}}, Nil{}}]}

def activity_parameter_editable_field(entry: OperationParameters.Entry, subject: Experience.Subject, value: OperationParameters.Observed, +parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  Experience.Subject{+editor, +field} = subject
  activity_row(SurfaceTypes.DependencyRow{}, SurfaceTypes.Node{Identity.Part{parent, OperationParameters.key(field)}, OperationParameters.key(field), "Reasoning parameter", SurfaceTypes.Field{}, SurfaceTypes.Edit{editor, field, entry, value, Nil{}}, subject_repair(editor, field, Identity.Part{parent, OperationParameters.key(field)}, state)})

def activity_parameter_field_entry(entry: OperationParameters.Entry, +subject: Experience.Subject, value: OperationParameters.Observed, +parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  match entry:
    case OperationParameters.DisplayOnly{}: activity_row(SurfaceTypes.DependencyRow{}, activity_readonly_field(subject, value, parent))
    case other: activity_parameter_editable_field(other, subject, value, parent, state)

def activity_parameter_field(+subject: Experience.Subject, entry: OperationParameters.Entry, +parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  Experience.Subject{+editor, +field} = subject
  +observed = field_value(state, editor, field)
  +value = activity_parameter_observed(E.requested_parameter(E.layers(E.session(Core.application(state))), editor), observed)
  activity_parameter_field_entry(entry, subject, value, parent, state)

def activity_dependency_summary(+subject: Experience.Subject, +value: String, parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  Experience.Subject{editor, +field} = subject
  [activity_row(SurfaceTypes.DependencyRow{}, SurfaceTypes.Node{Identity.Part{parent, "decision/" ++ OperationParameters.key(field)}, "decision/" ++ OperationParameters.key(field), activity_subject_title(subject) ++ " · " ++ value, SurfaceTypes.Button{}, SurfaceTypes.SettingEntry{subject, value, InteractionTypes.ApplicationInput{E.UserInput{U.EnterDecision{editor, OperationParameters.key(field)}}}, V.Available{}}, Nil{}})]

def activity_inline_expression(+subject: Experience.Subject, property: Experience.Property, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  [activity_row(SurfaceTypes.SupportingRow{}, activity_readonly_field(subject, OperationParameters.TextValue{activity_subject_value(subject, property, state)}, parent))]

def activity_draft_field_node(identity: Activity.DraftFieldIdentity, +parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  Activity.DraftFieldIdentity{owner, Experience.Subject{+editor, +field}, draft} = identity
  +value = OperationParameters.observed(U.contents(draft), field, E.program(Core.application(state)))
  activity_row(SurfaceTypes.DependencyRow{}, SurfaceTypes.Node{Identity.Part{parent, OperationParameters.key(field)}, OperationParameters.key(field), "Name", SurfaceTypes.Field{}, SurfaceTypes.Edit{editor, field, OperationParameters.SingleLine{}, value, Nil{}}, subject_repair(editor, field, Identity.Part{parent, OperationParameters.key(field)}, state)})

def activity_original_context(found: Maybe<&2, D.Project>, parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match found:
    case None{}: Nil{}
    case Some{D.Project{name, workspace, guidance}}:
      [activity_row(SurfaceTypes.SupportingRow{}, approval_fact(parent, "object", "Original project", name))]

def activity_original_expression(subject: Experience.Subject, +edit: Experience.ProjectEdit, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  Experience.Subject{editor, field} = subject
  List.append(&2, SurfaceTypes.Node, activity_original_context(UX.project_edit_original(edit), parent),
    [activity_draft_field_node(Activity.draft_field_identity(edit, Experience.Subject{editor, OperationParameters.ProjectName{}}), parent, state)])

def activity_inspection_focus(focused: Maybe<&2, OperationParameters.Field>, editor: U.Editor) -> Activity.View:
  match focused:
    case Some{field}: Activity.InspectionView{Some{Experience.Subject{editor, field}}}
    case None{}: Activity.InspectionView{None{}}

def activity_current_view_for_property(+property: Experience.Property, +state: InteractionTypes.State) -> Activity.View:
  +editor = UX.property_editor(property)
  activity_inspection_focus(E.requested_decision(activity_observation_layers(E.layers(E.session(Core.application(state)))), editor), editor)

def activity_relation_covers_subject(exposure: Activity.Exposure, view: Activity.RelationView, subject: Experience.Subject) -> Bool:
  match exposure view:
    case Activity.DependencySummary{} Activity.RootDecisionView{decision, children}: UX.same_subject(UX.decision_subject(decision), subject)
    case Activity.DependencySummary{} Activity.DependentDecisionView{parent, prerequisite, decision}: UX.same_subject(UX.decision_subject(decision), subject)
    case Activity.DependencySummary{} Activity.FieldSpecificationView{parent, child, entry, profile}: UX.same_subject(child, subject)
    case Activity.ParameterControl{} Activity.FieldSpecificationView{parent, child, entry, profile}: UX.same_subject(child, subject)
    case _ _: False{}

type InspectionCoverageContext is Data:
  InspectionCoverageContext{activity: Activity.Activity, current: Activity.View, subject: Experience.Subject}

def activity_inspection_child_covered(values: +List<Bool>) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{first, rest}: first || activity_inspection_child_covered(rest)

def activity_inspection_coverage_retained(+activity: Activity.Activity, +current: Activity.View, subject: Experience.Subject, +relation: Activity.RelationView, children: +List<Bool>) -> Bool:
  activity_relation_covers_subject(Activity.relation_view_exposure(activity, current, relation), relation, subject) || activity_inspection_child_covered(children)

def activity_inspection_coverage_handler(context: InspectionCoverageContext, relation: Activity.RelationView, children: +List<Bool>) -> Bool:
  InspectionCoverageContext{activity, current, subject} = context
  activity_inspection_coverage_retained(activity, current, subject, relation, children)

def activity_inspection_subject_covered(+activity: Activity.Activity, current: Activity.View, subject: Experience.Subject) -> Bool:
  activity_inspection_child_covered(Activity.fold_relations(~InspectionCoverageContext, ~Bool, ~activity_inspection_coverage_handler,
    InspectionCoverageContext{activity, current, subject}, Activity.relations(activity)))

def activity_inspection_uncovered(covered: Bool, subject: Experience.Subject, property: Experience.Property, parent: Identity.Key, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match covered:
    case True{}: Nil{}
    case False{}: activity_inline_expression(subject, property, parent, state)

def activity_inspection_expression_visible(+current: Activity.View, +activity: Activity.Activity, +subject: Experience.Subject, property: Experience.Property, parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match current:
    case Activity.InspectionView{None{}}: activity_inspection_uncovered(activity_inspection_subject_covered(activity, current, subject), subject, property, parent, state)
    case _: Nil{}

def activity_inspection_expression(+subject: Experience.Subject, +activity: Activity.Activity, +property: Experience.Property, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  activity_inspection_expression_visible(activity_current_view_for_property(property, state), activity, subject, property, parent, state)

def activity_candidate_description(same: Bool, explanation: String) -> String:
  match same:
    case True{}: ""
    case False{}: explanation

def activity_candidate_reason(reason: Maybe<&2, String>) -> String:
  match reason:
    case None{}: ""
    case Some{reason}: reason

def activity_model_consequence(same: Bool, reasoning: String, description: String) -> String:
  match same:
    case True{}: description
    case False{}: description ++ " · Reasoning effort: " ++ reasoning

def activity_candidate_consequence(input: U.Input, observed: OperationParameters.Observed, description: String) -> String:
  match input observed:
    case U.EditDraft{editor, U.ChooseModel{profile, +next}} OperationParameters.ModelValue{current, reasoning}: activity_model_consequence(String.eq(next, reasoning), next, description)
    case _ _: description

def activity_permission_effect_value(strategy: Experience.Strategy, field: OperationParameters.Field, observation: Context.Observation) -> String:
  match strategy field:
    case Experience.FullAccess{} OperationParameters.SandboxMode{}: "Filesystem: full access"
    case Experience.FullAccess{} OperationParameters.NetworkAccess{}: "Network available"
    case Experience.FullAccess{} OperationParameters.ApprovalReviewer{}: "No approval review"
    case Experience.Ask{} OperationParameters.ApprovalReviewer{}: ""
    case Experience.AutomaticReview{} OperationParameters.ApprovalReviewer{}: "Reviewer: " ++ activity_permission_subject_value(field, observation)
    case _ OperationParameters.SandboxMode{}: "Filesystem: " ++ activity_permission_sandbox_value(field, activity_permission_sandbox(observation))
    case _ OperationParameters.NetworkAccess{}: activity_permission_sandbox_value(field, activity_permission_sandbox(observation))
    case _ _: ""

def activity_description_append(empty: Bool, detail: String, description: String) -> String:
  match empty:
    case True{}: description
    case False{}: description ++ " · " ++ detail

def activity_candidate_reviewer(input: Maybe<&2, U.Input>, observation: Context.Observation) -> String:
  match input:
    case Some{U.EditDraft{editor, U.ConfigureContext{Context.SetApproval{choice}}}}: activity_reviewer_value(Some{choice})
    case _: activity_reviewer_value(activity_permission_approval(observation))

def activity_permission_candidate_effect(strategy: Experience.Strategy, field: OperationParameters.Field, +observation: Context.Observation, input: Maybe<&2, U.Input>) -> String:
  match strategy field:
    case Experience.AutomaticReview{} OperationParameters.ApprovalReviewer{}: "Reviewer: " ++ activity_candidate_reviewer(input, observation)
    case _ _: activity_permission_effect_value(strategy, field, observation)

def activity_consequence_expression(expression: Activity.SubjectExpression, value: Experience.Value, input: Maybe<&2, U.Input>, description: String) -> String:
  match expression value:
    case Activity.PermissionConsequence{Experience.Subject{editor, +field}, observation, decision} Experience.ExecutionStrategy{strategy}:
      +detail = activity_permission_candidate_effect(strategy, field, observation, input)
      activity_description_append(String.eq(detail, ""), detail, description)
    case _ _: description

def activity_consequence_expressions(expressions: +List<Activity.SubjectExpression>, +value: Experience.Value, +input: Maybe<&2, U.Input>, description: String) -> String:
  match expressions:
    case Nil{}: description
    case Con{expression, rest}: activity_consequence_expressions(rest, value, input, activity_consequence_expression(expression, value, input, description))

def activity_candidate_full_description(+activity: Activity.Activity, +candidate: Experience.CandidateObservation, +value: Experience.Value, description: String) -> String:
  activity_consequence_expressions(Activity.coverage_expressions(Activity.coverage(activity, Activity.PrincipalView{}, Activity.property(activity))), value, UX.candidate_canonical_result(candidate), description)

def activity_candidate_unavailable_values(canonical: Maybe<&2, U.Input>, +candidate: Experience.CandidateObservation, +value: Experience.Value, label: String, description: String, +reason: String, +parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  match canonical:
    case Some{input}: declared_choice(UX.candidate_selected(candidate), description ++ " · " ++ reason,
      V.ControlDeclaration{UX.value_key(value), label, V.Secondary{}, input, V.Unavailable{reason}}, parent, state)
    case None{}: approval_fact(parent, UX.value_key(value), label, description ++ " · " ++ reason)

def activity_candidate_unavailable(canonical: Maybe<&2, U.Input>, +candidate: Experience.CandidateObservation, +alternative: Experience.Alternative, +activity: Activity.Activity, parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  Experience.Alternative{+label, +explanation, +value} = alternative
  activity_candidate_unavailable_values(canonical, candidate, value, label,
    activity_candidate_full_description(activity, candidate, value, activity_candidate_description(String.eq(label, explanation), explanation)),
    activity_candidate_reason(UX.candidate_reason(candidate)), parent, state)

def activity_candidate_available(+input: U.Input, +candidate: Experience.CandidateObservation, alternative: Experience.Alternative, +activity: Activity.Activity, +parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  Experience.Alternative{+label, +explanation, +value} = alternative
  +description = activity_candidate_full_description(activity, candidate, value, activity_candidate_description(String.eq(label, explanation), explanation))
  declared_choice(UX.candidate_selected(candidate), activity_candidate_consequence(input, UX.decision_observation(UX.candidate_decision(candidate)), description), V.ControlDeclaration{UX.value_key(value), label, V.Secondary{}, input, V.Available{}}, parent, state)

def activity_candidate_alternative(input: Maybe<&2, U.Input>, +candidate: Experience.CandidateObservation, alternative: Experience.Alternative, +activity: Activity.Activity, +parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  match input:
    case Some{input}: activity_candidate_available(input, candidate, alternative, activity, parent, state)
    case None{}: activity_candidate_unavailable(UX.candidate_canonical_result(candidate), candidate, alternative, activity, parent, state)

def activity_candidate_input(input: Maybe<&2, U.Input>, +candidate: Experience.CandidateObservation, activity: Activity.Activity, parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  activity_row(SurfaceTypes.ChoiceRow{}, activity_candidate_alternative(input, candidate, UX.candidate_alternative(candidate), activity, parent, state))

def activity_candidate_nodes(candidates: +List<Experience.CandidateObservation>, +activity: Activity.Activity, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match candidates:
    case Nil{}: Nil{}
    case Con{+candidate, rest}: activity_candidate_input(UX.candidate_selection_input(candidate), candidate, activity, parent, state) <> activity_candidate_nodes(rest, activity, parent, state)

def activity_candidate_input_present(input: Maybe<&2, U.Input>) -> Bool:
  match input:
    case None{}: False{}
    case Some{input}: True{}

def activity_candidates_usable(candidates: +List<Experience.CandidateObservation>) -> Bool:
  match candidates:
    case Nil{}: False{}
    case Con{candidate, rest}: activity_candidate_input_present(UX.candidate_selection_input(candidate)) || activity_candidates_usable(rest)

def activity_unusable_candidates(usable: Bool, parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match usable:
    case True{}: Nil{}
    case False{}: [approval_fact(parent, "candidates/unavailable", "Choices", "No available choices")]

def activity_candidates_status(full: +List<Experience.CandidateObservation>, visible: +List<Experience.CandidateObservation>, parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match full visible:
    case Nil{} _: [approval_fact(parent, "candidates/empty", "Choices", "No choices have been configured")]
    case Con{first, rest} Nil{}: [approval_fact(parent, "candidates/no-match", "Search", "No choices match this search")]
    case +available Con{first, rest}: activity_unusable_candidates(activity_candidates_usable(available), parent)

def activity_requested_decision_caption(requested: Bool, subject: Experience.Subject, parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match requested:
    case False{}: Nil{}
    case True{}: [activity_row(SurfaceTypes.SupportingRow{}, SurfaceTypes.Node{Identity.Part{parent, "subject"}, "decision/subject", activity_subject_title(subject), SurfaceTypes.Content{}, SurfaceTypes.InformationText{Information.FieldLabel{}}, Nil{}})]

def activity_decision_candidates(+activity: Activity.Activity, +decision: Experience.Decision, +query: String, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  List.append(&2, SurfaceTypes.Node,
    Nil{},
    List.append(&2, SurfaceTypes.Node,
      activity_candidates_status(Activity.decision_candidates(activity, decision), Activity.visible_candidate_observations(activity, decision, query), parent),
      activity_candidate_nodes(Activity.visible_candidate_observations(activity, decision, query), activity, parent, state)))

def activity_coverage_parameter(exposure: Activity.Exposure, +subject: Experience.Subject, +activity: Activity.Activity, parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match exposure:
    case Activity.DependencySummary{}: activity_dependency_summary(subject, activity_subject_value(subject, Activity.property(activity), state), parent, state)
    case _: Nil{}

def activity_coverage_present(expression: Activity.SubjectExpression, +activity: Activity.Activity, +query: String, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match expression:
    case Activity.SelectedSubject{subject, decision}: activity_decision_candidates(activity, decision, query, Identity.Part{parent, UX.subject_key(subject)}, state)
    case Activity.OwnedParameter{+subject, relation}:
      activity_coverage_parameter(Activity.relation_exposure(activity, activity_current_view(activity, state), relation), subject, activity, parent, state)
    case Activity.PermissionConsequence{subject, observation, decision}: Nil{}
    case Activity.OwnerContext{subject, property}: activity_inline_expression(subject, property, parent, state)
    case Activity.OriginalIdentity{subject, edit}: activity_original_expression(subject, edit, parent, state)
    case Activity.InspectionFact{subject, property}: activity_inspection_expression(subject, activity, property, parent, state)
    case Activity.InlineSubject{subject, property}: activity_inline_expression(subject, property, parent, state)

def activity_information_notice(status: Experience.InformationStatus, +subject: Experience.Subject, parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match status:
    case Experience.NotApplicable{reason}: [activity_row(SurfaceTypes.SupportingRow{}, approval_fact(parent, "information/inapplicable/" ++ UX.subject_key(subject), activity_subject_title(subject), "Not applicable: " ++ reason))]
    case Experience.RequiredAbsence{reason}: [activity_row(SurfaceTypes.SupportingRow{}, SurfaceTypes.Node{Identity.Part{parent, "information/required/" ++ UX.subject_key(subject)}, "information/required", activity_subject_title(subject), SurfaceTypes.Alert{}, SurfaceTypes.ReadOnly{reason}, Nil{}})]
    case Experience.UnavailableInformation{reason}: [activity_row(SurfaceTypes.SupportingRow{}, approval_fact(parent, "information/unavailable/" ++ UX.subject_key(subject), activity_subject_title(subject), reason))]
    case _: Nil{}

def activity_coverage_information(status: Experience.InformationStatus, +expression: Activity.SubjectExpression, +activity: Activity.Activity, query: String, +parent: Identity.Key, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match status:
    case Experience.NotApplicable{reason}: activity_information_notice(Experience.NotApplicable{reason}, Activity.expression_subject(expression), parent)
    case other: List.append(&2, SurfaceTypes.Node, activity_coverage_present(expression, activity, query, parent, state), activity_information_notice(other, Activity.expression_subject(expression), parent))

def activity_coverage_expression(+expression: Activity.SubjectExpression, +activity: Activity.Activity, +query: String, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  activity_coverage_information(Activity.information_status(activity, activity_current_view(activity, state), Activity.property(activity), Activity.expression_subject(expression)), expression, activity, query, parent, state)

def activity_coverage_nodes(expressions: +List<Activity.SubjectExpression>, +activity: Activity.Activity, +query: String, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match expressions:
    case Nil{}: Nil{}
    case Con{expression, rest}: List.append(&2, SurfaceTypes.Node, activity_coverage_expression(expression, activity, query, parent, state), activity_coverage_nodes(rest, activity, query, parent, state))

def activity_required_property(+activity: Activity.Activity, +property: Experience.Property, +query: String, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  activity_coverage_nodes(Activity.information_expressions(activity, activity_current_view(activity, state), Activity.coverage(activity, activity_current_view(activity, state), property)), activity, query, parent, state)

def property_source_details(expanded: Bool, +property: Experience.Property, parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match expanded:
    case False{}: Nil{}
    case True{}: [approval_fact(parent, "property-source/details", "Source", UX.property_source_description(property))]

def property_source_toggle_control(expanded: Bool, parent: Identity.Key, control: InteractionTypes.Control) -> SurfaceTypes.Node:
  InteractionTypes.Control{+identity, label, prominence, input, availability} = control
  SurfaceTypes.Node{Identity.Part{parent, identity}, identity, label, action_role(prominence), SurfaceTypes.PanelToggle{expanded, input, availability}, Nil{}}

def property_source_toggle(+editor: U.Editor, parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  property_source_toggle_control(E.property_source_expanded(E.layers(E.session(Core.application(state))), editor), parent,
    Core.control(state, V.ControlDeclaration{"property-source/" ++ U.editor_key(editor), "Source of these settings", V.Secondary{}, U.TogglePropertySource{editor}, V.Available{}}))

def property_source_entry_for_owner(owned: Bool, origin: U.Panel, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match owned:
    case False{}: Nil{}
    case True{}: [activity_row(SurfaceTypes.InspectionRow{}, user_action(parent, "source/open", "Configuration source…", U.Activate{U.OpenPanel{U.PropertySource{origin}, Identity.encode(Identity.Part{parent, "source/open"})}}, True{}, state))]

def property_source_entry_layers(layers: +List<E.Layer>, editor: U.Editor, parent: Identity.Key, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match layers:
    case Nil{}: Nil{}
    case Con{E.Layer{+panel, trigger, initial, query, occurrence, expanded, field, parameter_buffer}, rest}:
      property_source_entry_for_owner(E.decision_editor_matches(E.decision_panel_editor(panel), editor), panel, parent, state)

def property_source_controls(+property: Experience.Property, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  property_source_entry_layers(E.layers(E.session(Core.application(state))), UX.property_editor(property), parent, state)

def property_source_nodes(+property: Experience.Property, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  approval_fact(parent, "property-scope", "Scope", property_scope(UX.property_editor(property))) <>
    property_source_controls(property, parent, state)

# NOTE: Keep the complete context observable without making every fact visible.
def workspace_current_context(+preview: Context.Preview, +parent: Identity.Key) -> SurfaceTypes.Node:
  SurfaceTypes.Node{Identity.Part{parent, "workspace/current"}, "workspace/current", UX.workspace_paths(context_workspace(preview)),
    SurfaceTypes.Content{}, SurfaceTypes.ContextSummary{Context.DraftExecution{preview}}, Nil{}}

def permission_context_summary(+editor: U.Editor, +observation: Context.Observation, +parent: Identity.Key, state: InteractionTypes.State) -> SurfaceTypes.Node:
  SurfaceTypes.Node{Identity.Part{parent, "property-scope"}, "property-scope", property_scope(editor),
    SurfaceTypes.Content{}, SurfaceTypes.ContextSummary{observation}, property_source_controls(UX.permissions_property(editor, observation), parent, state)}

def model_source(groups: +List<V.InputGroup>, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match groups:
    case Nil{}: Nil{}
    case Con{V.ModelInput{profile, reasoning, choices}, rest}:
      property_source_nodes(UX.model_property(editor, profile, reasoning, E.program(Core.application(state))), parent, state)
    case Con{other, rest}: model_source(rest, editor, parent, state)

def workspace_menu_group(+editor: U.Editor, group: V.InputGroup, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match group:
    case V.ExecutionInput{config, Context.ContextUnavailable{reason}, controls, projects, reviewers}: unavailable_context(reason, parent)
    case V.ExecutionInput{config, +preview, V.WorkspaceControls{identity, roots, inherit}, projects, reviewers}:
      workspace_current_context(preview, parent) <>
      List.append(&2, SurfaceTypes.Node, workspace_collection_menu(context_workspace(preview), editor, inherit, parent, state),
        property_source_nodes(UX.workspace_property(editor, Context.DraftExecution{preview}, E.program(Core.application(state))), parent, state))
    case _: Nil{}

def workspace_menu(groups: +List<V.InputGroup>, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match groups:
    case Nil{}: Nil{}
    case Con{group, rest}: List.append(&2, SurfaceTypes.Node, workspace_menu_group(editor, group, parent, state), workspace_menu(rest, editor, parent, state))

def committed_permission_summary(found: Maybe<&2, Context.EffectiveContext>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match found:
    case Some{+context}: [permission_context_summary(U.MessageEditor{View.context_task(context)}, Context.CommittedExecution{context}, parent, state)]
    case None{}: unavailable_context("Task execution context is unavailable", parent)

def permission_summary(editor: U.Editor, preview: Context.Preview, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match editor:
    case U.MessageEditor{task}:
      world = E.program(Core.application(state))
      committed_permission_summary(View.committed_context(T.find(Commands.entries(world), task)), parent, state)
    case _: [permission_context_summary(editor, Context.DraftExecution{preview}, parent, state)]

def permission_resets(+editor: U.Editor, +config: Context.Configuration, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match editor:
    case U.MessageEditor{task}: Nil{}
    case _:
      List.append(&2, SurfaceTypes.Node, reset_control(reset_change(config, OperationParameters.SandboxMode{}), editor, OperationParameters.SandboxMode{}, "filesystem and network access", parent, state),
        reset_control(reset_change(config, OperationParameters.ApprovalPolicy{}), editor, OperationParameters.ApprovalPolicy{}, "approval policy", parent, state))

def permission_decisions(+editor: U.Editor, +preview: Context.Preview, +reviewers: +List<D.Profile>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  +observed : OperationParameters.Observed = OperationParameters.ContextValue{preview, reviewers}
  decision_surface(UX.decision(Experience.Subject{editor, OperationParameters.SandboxMode{}}, observed, "Filesystem access", [sandbox_alternative(D.ReadOnly{}), sandbox_alternative(D.WorkspaceWrite{})]), parent, state) <>
  decision_surface(UX.decision(Experience.Subject{editor, OperationParameters.NetworkAccess{}}, observed, "Network access", [network_alternative(False{}), network_alternative(True{})]), parent, state) <>
  [decision_surface(UX.decision(Experience.Subject{editor, OperationParameters.ApprovalPolicy{}}, observed, "Approval policy", approval_alternative(Context.Ask{}, None{}) <> approval_alternative(Context.Unrestricted{}, None{}) <> reviewer_alternatives(reviewers)), parent, state)]

def permission_menu_group(+editor: U.Editor, group: V.InputGroup, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match group:
    case V.ExecutionInput{config, Context.ContextUnavailable{reason}, controls, projects, reviewers}: unavailable_context(reason, parent)
    case V.ExecutionInput{+config, Context.ProspectiveContext{+origin, +project, +workspace, +sandbox, +approval, +guidance}, controls, projects, reviewers}:
      List.append(&2, SurfaceTypes.Node,
        permission_summary(editor, Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, parent, state),
        List.append(&2, SurfaceTypes.Node, permission_decisions(editor, Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}, reviewers, parent, state),
        permission_resets(editor, config, parent, state)))
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
  InteractionTypes.Control{+key, label, prominence, input, +availability} = control
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

def activity_focus_field(field: Maybe<&2, OperationParameters.Field>, editor: U.Editor) -> Maybe<&2, Experience.Subject>:
  match field:
    case None{}: None{}
    case Some{field}: Some{Experience.Subject{editor, field}}

def activity_focus_owned(owned: Bool, field: Maybe<&2, OperationParameters.Field>, editor: U.Editor) -> Maybe<&2, Experience.Subject>:
  match owned:
    case False{}: None{}
    case True{}: activity_focus_field(field, editor)

def activity_focus_layers(layers: +List<E.Layer>, +editor: U.Editor) -> Maybe<&2, Experience.Subject>:
  match layers:
    case Nil{}: None{}
    case Con{E.Layer{+panel, trigger, initial, query, occurrence, source_expanded, field, parameter_buffer}, rest}:
      activity_focus_owned(E.decision_editor_matches(E.decision_panel_editor(panel), editor), field, editor)

def activity_current_selected(selected: Bool, label: String, rest: String) -> String:
  match selected:
    case True{}: label
    case False{}: rest

def activity_current_candidate(selected: Bool, alternative: Experience.Alternative, rest: String) -> String:
  match alternative:
    case Experience.Alternative{label, explanation, value}: activity_current_selected(selected, label, rest)

def activity_current_candidates(candidates: +List<Experience.CandidateObservation>, fallback: String) -> String:
  match candidates:
    case Nil{}: fallback
    case Con{+candidate, rest}: activity_current_candidate(UX.candidate_selected(candidate), UX.candidate_alternative(candidate), activity_current_candidates(rest, fallback))

def activity_compound_terminal(+action: Experience.ActionUnit, +assessment: Experience.Assessment, submit: V.ControlDeclaration, +parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  activity_row(SurfaceTypes.TerminalRow{}, dialog_actions(parent,
    [user_action(parent, "cancel", "Cancel", U.Activate{U.ClosePanel{}}, True{}, state), canonical_commit(action, assessment, submit, parent, state)]))

def activity_action_scene(scene: Maybe<&2, V.EditorScene>, +action: Experience.ActionUnit, +assessment: Experience.Assessment, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match scene:
    case None{}: Nil{}
    case Some{V.EditorScene{identity, revision, groups, structure, old_assessment, submit, feedback, pending}}:
      List.append(&2, SurfaceTypes.Node, activity_rows(SurfaceTypes.SupportingRow{}, action_feedback_nodes(identity, feedback, parent)), [activity_compound_terminal(action, assessment, submit, parent, state)])

def activity_action(+action: Experience.ActionUnit, assessment: Experience.Assessment, parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  +application = Core.application(state)
  activity_action_scene(View.editor(UX.action_editor(action), E.session(application), E.program(application)), action, assessment, parent, state)

def activity_compound_completion(completion: Activity.Completion, action: Experience.ActionUnit, assessment: Experience.Assessment, parent: Identity.Key, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match completion:
    case Activity.CommitOrDiscard{}: activity_action(action, assessment, parent, state)
    case _: Nil{}

def activity_flatten(values: +List<+List<SurfaceTypes.Node>>) -> +List<SurfaceTypes.Node>:
  List.foldr(~&2, ~(+List<SurfaceTypes.Node>), ~(+List<SurfaceTypes.Node>), ~(nodes => tail => List.append(&2, SurfaceTypes.Node, nodes, tail)), values, Nil{})

def activity_support_resets_config(found: Maybe<&2, Context.Configuration>, editor: U.Editor, parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match found:
    case None{}: Nil{}
    case Some{config}: permission_resets(editor, config, parent, state)

def activity_support_resets_visible(expanded: Bool, +editor: U.Editor, parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match expanded:
    case False{}: Nil{}
    case True{}: activity_support_resets_config(draft_configuration(E.find_draft(E.drafts(E.session(Core.application(state))), editor)), editor, parent, state)

def activity_support_resets_kind(kind: Experience.PropertyKind, +property: Experience.Property, parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match kind:
    case Experience.PermissionsProperty{}: activity_support_resets_visible(E.property_source_expanded(E.layers(E.session(Core.application(state))), UX.property_editor(property)), UX.property_editor(property), parent, state)
    case _: Nil{}

def activity_support(+property: Experience.Property, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  List.append(&2, SurfaceTypes.Node, property_source_controls(property, parent, state), activity_support_resets_kind(UX.property_kind(property), property, parent, state))

def activity_collection_obstruction_code(code: String, +obstruction: Experience.Obstruction, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match code:
    case "unadded_directory": Nil{}
    case +other:
      SurfaceTypes.Node{Identity.Part{parent, "workspace/error"}, "assessment/" ++ other, UX.obstruction_message(obstruction), SurfaceTypes.Alert{}, SurfaceTypes.ReadOnly{UX.obstruction_message(obstruction)}, Nil{}} <>
        workspace_retry_control(String.eq(other, "workspace_observation_failed"), editor, parent, state)

def activity_collection_obstruction(found: Maybe<&2, Experience.Obstruction>, editor: U.Editor, parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match found:
    case None{}: Nil{}
    case Some{+obstruction}: activity_collection_obstruction_code(UX.obstruction_code(obstruction), obstruction, editor, parent, state)

def activity_collection_assessment(edit: Maybe<&2, Experience.ProjectEdit>, +editor: U.Editor, parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match edit:
    case None{}: Nil{}
    case Some{edit}: activity_collection_obstruction(UX.subject_obstruction(Experience.Subject{editor, OperationParameters.WorkspaceDirectories{}}, UX.project_edit_assessment(edit)), editor, parent, state)

def activity_expression_owns_subject(expressions: +List<Activity.SubjectExpression>, +subject: Experience.Subject) -> Bool:
  match expressions:
    case Nil{}: False{}
    case Con{expression, rest}:
      match expression:
        case Activity.OwnedParameter{parameter, relation}: UX.same_subject(parameter, subject) || activity_expression_owns_subject(rest, subject)
        case _: activity_expression_owns_subject(rest, subject)

def activity_coverage_owns_parameter(+activity: Activity.Activity, current: Activity.View, subject: Experience.Subject) -> Bool:
  activity_expression_owns_subject(Activity.coverage_expressions(Activity.coverage(activity, current, Activity.property(activity))), subject)

def activity_decision_summary(covered: Bool, +activity: Activity.Activity, +decision: Experience.Decision, parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match covered:
    case True{}: Nil{}
    case False{}: activity_dependency_summary(UX.decision_subject(decision), activity_current_candidates(Activity.decision_candidates(activity, decision), FieldOptions.observed(UX.decision_observation(decision))), parent, state)

def activity_field_summary(covered: Bool, +activity: Activity.Activity, +subject: Experience.Subject, parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match covered:
    case True{}: Nil{}
    case False{}: activity_dependency_summary(subject, activity_subject_value(subject, Activity.property(activity), state), parent, state)

def activity_field_specification_summary(entry: OperationParameters.Entry, covered: Bool, +activity: Activity.Activity, +subject: Experience.Subject, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match entry:
    case OperationParameters.DisplayOnly{}: activity_inline_expression(subject, Activity.property(activity), parent, state)
    case other: activity_field_summary(covered, activity, subject, parent, state)

def activity_inspection_label(kind: Experience.PropertyKind) -> String:
  match kind:
    case Experience.ModelProperty{}: "Model settings…"
    case Experience.PermissionsProperty{}: "Custom permissions…"
    case _: "Configuration source…"

def activity_inspection_entry(+property: Experience.Property, parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  [activity_row(SurfaceTypes.InspectionRow{}, user_action(parent, "inspection", activity_inspection_label(UX.property_kind(property)), U.TogglePropertySource{UX.property_editor(property)}, True{}, state))]

def activity_requested_support(current: Activity.View, +property: Experience.Property, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match current:
    case Activity.InspectionView{None{}}:
      List.append(&2, SurfaceTypes.Node,
        [activity_row(SurfaceTypes.SupportingRow{}, approval_fact(parent, "property-scope", "Scope", property_scope(UX.property_editor(property))))], property_source_controls(property, parent, state))
    case Activity.CompoundView{}: activity_rows(SurfaceTypes.InspectionRow{}, activity_support(property, parent, state))
    case _: Nil{}

def activity_collection_editing_actions(+editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  region(parent, "directory-entry-actions", "", SurfaceTypes.Toolbar{},
    [directory_confirm(editor, parent, state), user_action(parent, "workspace/clear", "Clear", U.EditDraft{editor, U.WriteDirectory{""}}, True{}, state), directory_browse(editor, parent, state)])

def activity_collection_content(+collection: Experience.Collection, +activity: Activity.Activity, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  +editor = UX.collection_editor(collection)
  List.append(&2, SurfaceTypes.Node, [activity_row(SurfaceTypes.ObjectHeading{}, approval_fact(parent, "workspace-heading", "Working directories", property_scope(editor))),
    activity_row(SurfaceTypes.DependencyRow{}, SurfaceTypes.Node{Identity.Part{parent, "add"}, "workspace/add", "Add working directory", SurfaceTypes.Field{}, SurfaceTypes.EnterDirectory{editor, pending_directory(state, editor)},
      unadded_directory_status(String.eq(pending_directory(state, editor), ""), Identity.Part{parent, "add"})}),
    activity_collection_editing_actions(editor, parent, state)], List.append(&2, SurfaceTypes.Node,
      activity_rows(SurfaceTypes.MemberRow{}, collection_rows(UX.collection_members(collection), collection, parent, state)), activity_rows(SurfaceTypes.SupportingRow{}, activity_collection_assessment(Activity.editing_observation(activity), editor, parent, state))))

def activity_root_candidate_content(current: Activity.View, +activity: Activity.Activity, decision: Experience.Decision, children: +List<+List<SurfaceTypes.Node>>, query: String, parent: Identity.Key, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match current:
    case Activity.PrincipalView{}: activity_flatten(children)
    case _: List.append(&2, SurfaceTypes.Node, activity_decision_candidates(activity, decision, query, parent, state), activity_flatten(children))

def activity_exposed_relation(exposure: Activity.Exposure, view: Activity.RelationView, children: +List<+List<SurfaceTypes.Node>>, +activity: Activity.Activity, +current: Activity.View, query: String, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match exposure view:
    case Activity.HiddenRelation{} _: activity_flatten(children)
    case Activity.RequiredExpression{} Activity.RequiredValueView{property}: activity_required_property(activity, property, query, parent, state)
    case Activity.CandidateChoices{} Activity.RootDecisionView{decision, actual_children}: activity_root_candidate_content(current, activity, decision, children, query, parent, state)
    case Activity.CandidateChoices{} Activity.DependentDecisionView{owner, prerequisite, +decision}: activity_decision_candidates(activity, decision, "", Identity.Part{parent, UX.subject_key(UX.decision_subject(decision))}, state)
    case Activity.DependencySummary{} Activity.RootDecisionView{+decision, actual_children}: List.append(&2, SurfaceTypes.Node, activity_decision_summary(False{}, activity, decision, parent, state), activity_flatten(children))
    case Activity.DependencySummary{} Activity.DependentDecisionView{owner, prerequisite, +decision}: activity_decision_summary(activity_coverage_owns_parameter(activity, current, UX.decision_subject(decision)), activity, decision, parent, state)
    case Activity.DependencySummary{} Activity.FieldSpecificationView{owner, +subject, entry, profile}: activity_field_specification_summary(entry, activity_coverage_owns_parameter(activity, current, subject), activity, subject, parent, state)
    case Activity.ParameterControl{} Activity.FieldSpecificationView{owner, subject, entry, profile}: [activity_parameter_field(subject, entry, parent, state)]
    case Activity.RequestedInformation{} Activity.SupportingValueView{property}: activity_requested_support(current, property, Identity.Part{parent, "source"}, state)
    case Activity.CompoundContent{} Activity.CollectionMembersView{collection}: activity_collection_content(collection, activity, parent, state)
    case Activity.CompoundContent{} Activity.AssessedActionView{action, assessment}: activity_compound_completion(Activity.completion(activity, current), action, assessment, parent, state)
    case _ _: activity_flatten(children)

def activity_relation_nodes(+view: Activity.RelationView, children: +List<+List<SurfaceTypes.Node>>, +activity: Activity.Activity, query: String, focused: Maybe<&2, Experience.Subject>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  +current = activity_current_view(activity, state)
  activity_exposed_relation(Activity.relation_view_exposure(activity, current, view), view, children, activity, current, query, parent, state)

def activity_search(required: Bool, query: String, parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match required:
    case True{}: [activity_row(SurfaceTypes.DependencyRow{}, SurfaceTypes.Node{Identity.Part{parent, "search"}, "search", "Search models", SurfaceTypes.Field{}, SurfaceTypes.SearchChoices{query}, Nil{}})]
    case False{}: Nil{}

def activity_parameter_apply_entry(entry: OperationParameters.Entry, editor: U.Editor, parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match entry:
    case OperationParameters.SingleLine{}: [activity_row(SurfaceTypes.TerminalRow{}, user_action(parent, "parameter/apply", "Apply", U.CompleteDecisionParameter{editor}, True{}, state))]
    case _: Nil{}

def activity_parameter_apply(field: Maybe<&2, OperationParameters.Field>, +editor: U.Editor, parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match field:
    case Some{OperationParameters.ReasoningEffort{}}: activity_parameter_apply_entry(actual_entry(OperationParameters.ReasoningEffort{}, OperationParameters.Choice{}, field_value(state, editor, OperationParameters.ReasoningEffort{}), state), editor, parent, state)
    case _: Nil{}

def activity_inspection_kind_title(kind: Experience.PropertyKind, property: Experience.Property) -> String:
  match kind:
    case Experience.ModelProperty{}: "Model settings"
    case Experience.PermissionsProperty{}: "Permissions"
    case _: UX.property_title(property)

def activity_inspection_title(+property: Experience.Property) -> String:
  activity_inspection_kind_title(UX.property_kind(property), property)

def activity_view_title(current: Activity.View, property: Experience.Property) -> String:
  match current:
    case Activity.DependentView{subject}: activity_subject_title(subject)
    case Activity.InspectionView{Some{subject}}: activity_subject_title(subject)
    case Activity.InspectionView{None{}}: activity_inspection_title(property)
    case _: ""

# The current activity names the destination; completion retains the actual
# return input. Neither a title nor a label is used to infer navigation.
def activity_navigation_header(title: String, back: U.Input, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  [activity_row(SurfaceTypes.NavigationRow{}, region(parent, "view/header", "", SurfaceTypes.Toolbar{},
    [user_action(parent, "view/back", "Back", back, True{}, state),
     SurfaceTypes.Node{Identity.Part{parent, "view/title"}, "view/title", title, SurfaceTypes.Heading{}, SurfaceTypes.InformationText{Information.SurfaceTitle{}}, Nil{}}]))]

def activity_view_header(title: String, editor: U.Editor, parent: Identity.Key, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  activity_navigation_header(title, U.LeaveDecision{editor}, parent, state)

def activity_view_completion_controls(completion: Activity.Completion, title: String, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match completion:
    case Activity.ApplyAndDismiss{}: Nil{}
    case Activity.CommitOrDiscard{}: Nil{}
    case Activity.ApplyAndReturn{}: activity_view_header(title, editor, parent, state)
    case Activity.ReturnToOwner{}: activity_view_header(title, editor, parent, state)

def activity_view_parameter_completion(completion: Activity.Completion, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match completion:
    case Activity.ApplyAndReturn{}: activity_parameter_apply(E.requested_decision(E.layers(E.session(Core.application(state))), editor), editor, parent, state)
    case Activity.ReturnToOwner{}: Nil{}
    case _: Nil{}

def activity_view_inspection_entry(current: Activity.View, property: Experience.Property, parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match current:
    case Activity.PrincipalView{}: activity_inspection_entry(property, parent, state)
    case _: Nil{}

type ActivityRenderContext is Data:
  ActivityRenderContext{activity: Activity.Activity, query: String, focused: Maybe<&2, Experience.Subject>, parent: Identity.Key, state: InteractionTypes.State}

def activity_relation_handler(context: ActivityRenderContext, view: Activity.RelationView, children: +List<+List<SurfaceTypes.Node>>) -> +List<SurfaceTypes.Node>:
  ActivityRenderContext{activity, query, focused, parent, state} = context
  activity_relation_nodes(view, children, activity, query, focused, parent, state)

def activity_content(+activity: Activity.Activity, +query: String, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  focused = activity_focus_layers(activity_observation_layers(E.layers(E.session(Core.application(state)))), Activity.scope(activity))
  context: ActivityRenderContext = ActivityRenderContext{activity, query, focused, parent, state}
  List.append(&2, SurfaceTypes.Node, activity_search(Activity.search_required(activity, activity_current_view(activity, state)), query, parent), activity_flatten(Activity.fold_relations(~ActivityRenderContext, ~(+List<SurfaceTypes.Node>), ~activity_relation_handler, context, Activity.relations(activity))))

def activity_nodes(+activity: Activity.Activity, +query: String, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  +current = activity_current_view(activity, state)
  +completion = Activity.completion(activity, current)
  List.append(&2, SurfaceTypes.Node, activity_view_completion_controls(completion, activity_view_title(current, Activity.property(activity)), Activity.scope(activity), parent, state), List.append(&2, SurfaceTypes.Node, activity_content(activity, query, parent, state),
    List.append(&2, SurfaceTypes.Node, activity_view_parameter_completion(completion, Activity.scope(activity), parent, state), activity_view_inspection_entry(current, Activity.property(activity), parent, state))))

def model_activity_children_entry(entry: OperationParameters.Entry, profile: D.Profile, +observed: OperationParameters.Observed, +editor: U.Editor, groups: +List<V.InputGroup>) -> +List<Activity.Dependency>:
  match entry:
    case OperationParameters.Choice{}:
      [Activity.Dependency{Experience.Model{profile}, UX.decision(Experience.Subject{editor, OperationParameters.ReasoningEffort{}}, observed, "Reasoning effort", effort_alternatives(FieldOptions.choices(OperationParameters.ReasoningEffort{}, observed, groups)))}]
    case _: Nil{}

def model_activity_children(found: Maybe<&2, D.Profile>, +observed: OperationParameters.Observed, editor: U.Editor, +state: InteractionTypes.State, groups: +List<V.InputGroup>) -> +List<Activity.Dependency>:
  match found:
    case None{}: Nil{}
    case Some{profile}: model_activity_children_entry(actual_entry(OperationParameters.ReasoningEffort{}, OperationParameters.Choice{}, observed, state), profile, observed, editor, groups)

def model_activity_groups(groups: +List<V.InputGroup>, +editor: U.Editor, +state: InteractionTypes.State) -> Maybe<&2, Activity.Activity>:
  match groups:
    case Nil{}: None{}
    case Con{V.ModelInput{+profile, +reasoning, +choices}, +rest}:
      +observed: OperationParameters.Observed = OperationParameters.ModelValue{profile, reasoning}
      +decision = UX.decision(Experience.Subject{editor, OperationParameters.ModelProfile{}}, observed, "Model", admitted_model_alternatives(Experience.Subject{editor, OperationParameters.ModelProfile{}}, observed, choices))
      Some{Activity.comparison(UX.model_property(editor, profile, reasoning, E.program(Core.application(state))), decision,
        model_activity_children(D.find_profile(choices, profile), observed, editor, state, V.ModelInput{profile, reasoning, choices} <> rest), Nil{}, choices)}
    case Con{other, rest}: model_activity_groups(rest, editor, state)

def project_activity_draft(found: Maybe<&2, U.Draft>, +state: InteractionTypes.State) -> Maybe<&2, Activity.Activity>:
  match found:
    case None{}: None{}
    case Some{+draft}:
      +application = Core.application(state)
      +session = E.session(application)
      Some{Activity.editing(UX.project_edit(draft, E.busy(E.pending(session), U.owner(U.contents(draft))), E.now(session), E.program(application)))}

def project_activity_scene(scene: Maybe<&2, V.EditorScene>, +state: InteractionTypes.State) -> Maybe<&2, Activity.Activity>:
  match scene:
    case Some{V.EditorScene{+identity, revision, groups, structure, assessment, submit, feedback, pending}}:
      match identity:
        case U.ProjectEditor{id}: project_activity_draft(E.find_draft(E.drafts(E.session(Core.application(state))), U.ProjectEditor{id}), state)
        case _: None{}
    case None{}: None{}

def policy_reviewer_alternatives(reviewers: +List<D.Profile>) -> +List<Experience.Alternative>:
  Activity.reviewer_catalog_alternatives(reviewers)

def policy_restricted_dependencies(+strategy: Experience.Strategy, +observed: OperationParameters.Observed, +editor: U.Editor) -> +List<Activity.Dependency>:
  [Activity.Dependency{Experience.ExecutionStrategy{strategy}, UX.decision(Experience.Subject{editor, OperationParameters.SandboxMode{}}, observed, "Filesystem access", [sandbox_alternative(D.ReadOnly{}), sandbox_alternative(D.WorkspaceWrite{})])},
   Activity.Dependency{Experience.ExecutionStrategy{strategy}, UX.decision(Experience.Subject{editor, OperationParameters.NetworkAccess{}}, observed, "Network access", [network_alternative(False{}), network_alternative(True{})])}]

def policy_review_dependencies(+observed: OperationParameters.Observed, +editor: U.Editor, reviewers: +List<D.Profile>) -> +List<Activity.Dependency>:
  Activity.Dependency{Experience.ExecutionStrategy{Experience.AutomaticReview{}}, UX.decision(Experience.Subject{editor, OperationParameters.ApprovalReviewer{}}, observed, "Reviewing model", policy_reviewer_alternatives(reviewers))} <>
    policy_restricted_dependencies(Experience.AutomaticReview{}, observed, editor)

def policy_admitted_alternatives(alternatives: +List<Experience.Alternative>, +subject: Experience.Subject, +observed: OperationParameters.Observed) -> +List<Experience.Alternative>:
  match alternatives:
    case Nil{}: Nil{}
    case Con{alternative, rest}: List.append(&2, Experience.Alternative, UX.decision_alternatives(UX.decision(subject, observed, "Execution strategy", [alternative])), policy_admitted_alternatives(rest, subject, observed))

def policy_effective_committed(found: Maybe<&2, Context.EffectiveContext>, preview: Context.Preview) -> Context.Observation:
  match found:
    case None{}: Context.DraftExecution{preview}
    case Some{context}: Context.CommittedExecution{context}

def policy_effective_observation(editor: U.Editor, preview: Context.Preview, world: M.World()) -> Context.Observation:
  match editor:
    case U.MessageEditor{task}: policy_effective_committed(View.committed_context(T.find(Commands.entries(world), task)), preview)
    case _: Context.DraftExecution{preview}

def policy_activity_preview(preview: Context.Preview, +reviewers: +List<D.Profile>, +editor: U.Editor, +state: InteractionTypes.State) -> Maybe<&2, Activity.Activity>:
  match preview:
    case Context.ContextUnavailable{reason}: None{}
    case Context.ProspectiveContext{+origin, +project, +workspace, +sandbox, +approval, +guidance}:
      +preview: Context.Preview = Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}
      +observed: OperationParameters.Observed = OperationParameters.ContextValue{preview, reviewers}
      +subject: Experience.Subject = Experience.Subject{editor, OperationParameters.ApprovalPolicy{}}
      +decision = UX.decision(subject, observed, "Execution strategy", policy_admitted_alternatives(Activity.execution_strategy_alternatives(observed), subject, observed))
      Some{Activity.explanation(UX.permissions_property(editor, policy_effective_observation(editor, preview, E.program(Core.application(state)))), decision,
        List.append(&2, Activity.Dependency, policy_restricted_dependencies(Experience.Ask{}, observed, editor), policy_review_dependencies(observed, editor, reviewers)), Nil{}, reviewers)}

def policy_activity_groups(groups: +List<V.InputGroup>, +editor: U.Editor, +state: InteractionTypes.State) -> Maybe<&2, Activity.Activity>:
  match groups:
    case Nil{}: None{}
    case Con{V.ExecutionInput{config, preview, controls, projects, reviewers}, rest}: policy_activity_preview(preview, reviewers, editor, state)
    case Con{other, rest}: policy_activity_groups(rest, editor, state)

def activity_or_content(found: Maybe<&2, Activity.Activity>, query: String, parent: Identity.Key, +state: InteractionTypes.State, fallback: +List<SurfaceTypes.Node>) -> +List<SurfaceTypes.Node>:
  match found:
    case None{}: fallback
    case Some{activity}: activity_nodes(activity, query, parent, state)

def editor(+view: Maybe<&2, V.EditorScene>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  activity_or_content(project_activity_scene(view, state), "", parent, state, ordinary_editor(view, parent, state))

def layer_activity(content: V.LayerContent, +state: InteractionTypes.State) -> Maybe<&2, Activity.Activity>:
  match content:
    case V.ModelSelection{identity, query, values}: model_activity_groups(values, identity, state)
    case V.ObjectEditor{value}: project_activity_scene(value, state)
    case V.PermissionSettings{identity, values}: policy_activity_groups(values, identity, state)
    case _: None{}


def workspace_source_property(groups: +List<V.InputGroup>, +editor: U.Editor, +state: InteractionTypes.State) -> Maybe<&2, Experience.Property>:
  match groups:
    case Nil{}: None{}
    case Con{V.ExecutionInput{config, preview, controls, projects, reviewers}, rest}: Some{UX.workspace_property(editor, Context.DraftExecution{preview}, E.program(Core.application(state)))}
    case Con{other, rest}: workspace_source_property(rest, editor, state)

def layer_activity_property(found: Maybe<&2, Activity.Activity>) -> Maybe<&2, Experience.Property>:
  match found:
    case None{}: None{}
    case Some{activity}: Some{Activity.property(activity)}

def layer_property(+origin: V.LayerContent, +state: InteractionTypes.State) -> Maybe<&2, Experience.Property>:
  match origin:
    case V.WorkspaceSettings{editor, fields}: workspace_source_property(fields, editor, state)
    case other: layer_activity_property(layer_activity(other, state))

def property_source_observation(found: Maybe<&2, Experience.Property>, +parent: Identity.Key) -> +List<SurfaceTypes.Node>:
  match found:
    case None{}: [activity_row(SurfaceTypes.SupportingRow{}, approval_fact(parent, "source/unavailable", "Source", "The original settings observation is unavailable"))]
    case Some{+property}: [activity_row(SurfaceTypes.SupportingRow{}, approval_fact(parent, "source/owner", "Settings", UX.property_title(property))),
      activity_row(SurfaceTypes.SupportingRow{}, approval_fact(parent, "source/details", "Source", UX.property_source_description(property)))]

def property_source_content(origin: V.LayerContent, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  List.append(&2, SurfaceTypes.Node, activity_navigation_header("Configuration source", U.Activate{U.ClosePanel{}}, parent, state), property_source_observation(layer_property(origin, state), parent))

def work_overview_choice(value: V.WorkChoice, +selected: Maybe<&2, Nat>, parent: Identity.Key, state: InteractionTypes.State) -> SurfaceTypes.Node:
  V.WorkChoice{+work, name, description} = value
  project_picker_choice(View.control("overview/" ++ E.work_target(work), name, U.SelectWork{work}), E.same_work(work, selected), description, parent, state)

def work_choice_rows(values: +List<V.WorkChoice>, +selected: Maybe<&2, Nat>, +parent: Identity.Key, +state: InteractionTypes.State, +index: Nat) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{first, Nil{}}:
      [region(parent, "work-row/" ++ Nat.show(index), "", SurfaceTypes.WorkChoiceRow{},
        [work_overview_choice(first, selected, parent, state), region(parent, "work-gap/" ++ Nat.show(index), "", SurfaceTypes.Section{}, Nil{})])]
    case Con{first, Con{second, rest}}:
      region(parent, "work-row/" ++ Nat.show(index), "", SurfaceTypes.WorkChoiceRow{},
        [work_overview_choice(first, selected, parent, state), work_overview_choice(second, selected, parent, state)]) <>
        work_choice_rows(rest, selected, parent, state, (index + 1n : Nat))

def work_overview(selected: Maybe<&2, Nat>, works: +List<V.WorkChoice>, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  [SurfaceTypes.Node{Identity.Part{parent, "work-choices"}, "work-choices", "Works", SurfaceTypes.Section{}, SurfaceTypes.ChoiceGroup{}, work_choice_rows(works, selected, parent, state, 0n)},
    dialog_actions(parent, [declared(parent, View.control("overview/new", "New Work", U.CreateWork{}), state),
      region(parent, "overview/action-space", "", SurfaceTypes.Section{}, Nil{}),
      declared(parent, View.control("overview/done", "Done", U.ClosePanel{}), state)])]

def layer_content(view: V.LayerContent, +parent: Identity.Key, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match view:
    case V.GlobalNavigation{route, destinations}: global_navigation_menu(route, destinations, parent, state)
    case V.WorkSelection{selected, works}: work_overview(selected, works, parent, state)
    case V.PropertySource{origin}: property_source_content(origin, parent, state)
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
    case V.PermissionSettings{+identity, +values}: activity_or_content(policy_activity_groups(values, identity, state), "", parent, state, permission_menu(values, identity, parent, state))
    case V.CommittedContext{context}: committed_context_nodes(context, parent, state)
    case V.ModelSelection{+identity, query, +values}:
      activity_or_content(model_activity_groups(values, identity, state), query, parent, state, Nil{})
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


def activity_layer_meaning(activity: Activity.Activity, dismissal: V.Dismissal) -> SurfaceTypes.Meaning:
  match dismissal:
    case V.OutsideOrEscape{action}: SurfaceTypes.ActivityGroup{activity, InteractionTypes.ApplicationInput{E.UserInput{U.Activate{action}}}, True{}, True{}}
    case V.ByTrigger{action}: SurfaceTypes.ActivityGroup{activity, InteractionTypes.ApplicationInput{E.UserInput{U.Activate{action}}}, False{}, False{}}

def layer_meaning(found: Maybe<&2, Activity.Activity>, dismissal: V.Dismissal) -> SurfaceTypes.Meaning:
  match found:
    case None{}: dismissal_meaning(dismissal)
    case Some{activity}: activity_layer_meaning(activity, dismissal)

# NOTE: A compound edit needs its activity title; choosing and inspection already
# express their owner and parameter through subject coverage inside the surface.
def activity_goal_label(goal: Activity.Purpose, fallback: String) -> String:
  match goal:
    case Activity.ObjectEditing{}: fallback
    case Activity.Comparison{}: ""
    case Activity.EffectExplanation{}: ""

def activity_layer_view_label(title: String, goal: Activity.Purpose, fallback: String) -> String:
  match title:
    case "": activity_goal_label(goal, fallback)
    case current: current

def activity_layer_label(found: Maybe<&2, Activity.Activity>, +fallback: String, state: InteractionTypes.State) -> String:
  match found:
    case None{}: fallback
    case Some{+activity}: activity_layer_view_label(activity_view_title(activity_current_view(activity, state), Activity.property(activity)), Activity.purpose(activity), fallback)

def layers(values: +List<V.Layer>, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{V.Layer{kind, +content, +initial, restore, dismissal}, rest}:
      SurfaceTypes.Node{layer_key(initial), initial, activity_layer_label(layer_activity(content, state), View.layer_title(content), state), layer_role(kind), layer_meaning(layer_activity(content, state), dismissal),
        layer_content(content, layer_key(initial), state)} <> layers(rest, state)

def settings_visible(open: Bool, close: InteractionTypes.Input, connect: InteractionTypes.Input) -> +List<SurfaceTypes.Node>:
  match open:
    case False{}: Nil{}
    case True{}: [SurfaceTypes.Node{Identity.Place{"/layers/settings"}, "settings", "Settings", SurfaceTypes.Dialog{}, SurfaceTypes.LayerRegion{close, True{}, True{}},
      [region(Identity.Place{"/layers/settings"}, "appearance", "Appearance", SurfaceTypes.Section{}, [
         product_action(Identity.Place{"/layers/settings"}, "light", "Light appearance", InteractionTypes.ServiceInput{Services.ChooseAppearance{Services.LightAppearance{}}}, True{}),
         product_action(Identity.Place{"/layers/settings"}, "dark", "Dark appearance", InteractionTypes.ServiceInput{Services.ChooseAppearance{Services.DarkAppearance{}}}, True{}),
         product_action(Identity.Place{"/layers/settings"}, "system", "System appearance", InteractionTypes.ServiceInput{Services.ChooseAppearance{Services.SystemAppearance{}}}, True{})]),
       dialog_actions(Identity.Place{"/layers/settings"}, [product_action(Identity.Place{"/layers/settings"}, "connect", "Connect", connect, True{})])]}]

def settings(view: InteractionTypes.Settings) -> +List<SurfaceTypes.Node>:
  InteractionTypes.Settings{open, access, appearance, open_action, close_action, connect_action} = view
  settings_visible(open, close_action, connect_action)

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

def persistent_layer_trigger(behavior: Maybe<&2, SurfaceTypes.LayerBehavior>) -> Maybe<&2, SurfaceTypes.PersistentTrigger>:
  match behavior:
    case Some{SurfaceTypes.LayerBehavior{InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.TogglePanel{U.TaskDetails{task}, trigger}}}}, False{}, False{}}}: Some{SurfaceTypes.PersistentTrigger{task, trigger}}
    case _: None{}

def persistent_details_trigger(overlays: +List<SurfaceTypes.Node>) -> Maybe<&2, SurfaceTypes.PersistentTrigger>:
  match overlays:
    case Nil{}: None{}
    case Con{SurfaceTypes.Node{key, semantic, label, SurfaceTypes.Dialog{}, meaning, children}, rest}: persistent_layer_trigger(SurfaceTypes.layer_region(meaning))
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
    case SurfaceTypes.ActionCommit{assessment, input, availability} SurfaceTypes.Press{}: when_available(UX.assessment_ready(assessment) && available(availability), input)
    case SurfaceTypes.SupportingControl{support, property, input, availability} SurfaceTypes.Press{}: when_available(UX.support_visible(support) && available(availability), input)
    case SurfaceTypes.SettingEntry{subject, value, input, availability} SurfaceTypes.Press{}: when_available(available(availability), input)
    case SurfaceTypes.Activate{input, availability} SurfaceTypes.Press{}: when_available(available(availability), input)
    case SurfaceTypes.PanelToggle{expanded, input, availability} SurfaceTypes.Press{}: when_available(available(availability), input)
    case SurfaceTypes.Choice{kind, classification, selected, description, input, availability} SurfaceTypes.Press{}: when_available(available(availability), input)
    case SurfaceTypes.Edit{+editor, +field, OperationParameters.DisplayOnly{}, +value, choices} SurfaceTypes.Change{+next}: None{}
    case SurfaceTypes.Edit{+editor, +field, entry, +value, choices} SurfaceTypes.Change{+next}: Some{InteractionTypes.EditField{editor, field, next}}
    case SurfaceTypes.SearchChoices{query} SurfaceTypes.Search{+next}: Some{InteractionTypes.ApplicationInput{E.UserInput{U.SearchChoices{next}}}}
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

def activity_requested_field_bound(requested: Maybe<&2, OperationParameters.Field>, +editor: U.Editor, +field: OperationParameters.Field, value: OperationParameters.Value, input: InteractionTypes.Input) -> InteractionTypes.Input:
  match requested field value:
    case Some{OperationParameters.ReasoningEffort{}} OperationParameters.ReasoningEffort{} OperationParameters.Model{profile, reasoning}:
      InteractionTypes.ApplicationInput{E.UserInput{U.WriteDecisionParameter{editor, reasoning}}}
    case _ _ _: input

def activity_requested_field_input(+editor: U.Editor, field: OperationParameters.Field, value: OperationParameters.Value, input: InteractionTypes.Input, +state: InteractionTypes.State) -> InteractionTypes.Input:
  activity_requested_field_bound(E.requested_decision(E.layers(E.session(Core.application(state))), editor), editor, field, value, input)

def activity_requested_input(+input: InteractionTypes.Input, +state: InteractionTypes.State) -> InteractionTypes.Input:
  match input:
    case InteractionTypes.EditField{+editor, +field, +value}: activity_requested_field_input(editor, field, value, input, state)
    case _: input

def apply_input(input: Maybe<&2, InteractionTypes.Input>, +state: InteractionTypes.State) -> InteractionTypes.Decision:
  match input:
    case Some{input}: Core.step(activity_requested_input(input, state), state)
    case None{}:
      application = Core.application(state)
      services = Core.services(state)
      Core.application_result(E.unchanged(application), services)

def origin(layers: +List<E.Layer>, key: String) -> String:
  match layers:
    case Con{E.Layer{U.ObjectActions{subject}, trigger, initial, query, layer_occurrence, source_expanded, decision_field, parameter_buffer}, rest}: trigger
    case _: key

def layer_trigger(unchanged: Bool, previous: String, origin: String) -> String:
  match unchanged:
    case True{}: previous
    case False{}: origin

def layer_present(layers: +List<E.Layer>, +target: String) -> Bool:
  match layers:
    case Nil{}: False{}
    case Con{E.Layer{panel, trigger, initial, query, layer_occurrence, source_expanded, decision_field, parameter_buffer}, rest}:
      String.eq(E.panel_target(panel), target) || layer_present(rest, target)

def record_layer(layers: +List<E.Layer>, previous: +List<E.Layer>, origin: String) -> +List<E.Layer>:
  match layers:
    case Nil{}: Nil{}
    case Con{E.Layer{+panel, trigger, initial, query, layer_occurrence, source_expanded, decision_field, parameter_buffer}, rest}:
      E.Layer{panel, layer_trigger(layer_present(previous, E.panel_target(panel)), trigger, origin), initial, query, layer_occurrence, source_expanded, decision_field, parameter_buffer} <> rest

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
    case Some{InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.SelectWork{work}}}}}: True{}
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
    case SurfaceTypes.ActionCommit{assessment, input, availability}: UX.assessment_ready(assessment) && available(availability)
    case SurfaceTypes.SupportingControl{support, property, input, availability}: UX.support_visible(support) && available(availability)
    case SurfaceTypes.SettingEntry{subject, value, input, availability}: available(availability)
    case SurfaceTypes.Activate{input, availability}: available(availability)
    case SurfaceTypes.PanelToggle{expanded, input, availability}: available(availability)
    case SurfaceTypes.LayerRegion{dismiss, outside, escape}: True{}
    case SurfaceTypes.Choice{kind, classification, selected, description, input, availability}: available(availability)
    case SurfaceTypes.Edit{editor, field, OperationParameters.DisplayOnly{}, value, choices}: False{}
    case SurfaceTypes.Edit{editor, field, OperationParameters.FileCollection{}, value, choices}: False{}
    case SurfaceTypes.Edit{editor, field, OperationParameters.DirectoryCollection{}, value, choices}: False{}
    case SurfaceTypes.Edit{editor, field, entry, value, choices}: True{}
    case SurfaceTypes.SearchChoices{query}: True{}
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

def with_workspace_navigation(content: InteractionTypes.Scene, nav: +List<SurfaceTypes.Node>, +reachable: SurfaceTypes.Surface, scope: Maybe<&2, String>) -> SurfaceTypes.Surface:
  SurfaceTypes.Surface{content, List.append(&2, SurfaceTypes.Node, nav, surface_base(reachable)), surface_overlays(reachable), scope}

def work_tab_identity(work: Maybe<&2, Nat>) -> String:
  E.work_target(work)

def work_tab(+work: Maybe<&2, Nat>, label: String, +active: Maybe<&2, Nat>, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  +identity = work_tab_identity(work)
  replace_role(declared(Identity.Place{"/work-tabs"}, View.control(identity, label, U.SelectWork{work}), state), SurfaceTypes.WorkTab{E.same_work(work, active)})

def work_tab_entries(values: +List<Finite.Entry(Work.Work)>, +active: Maybe<&2, Nat>, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{(id, value), rest}: work_tab(Some{id}, Work.name(value), active, state) <> work_tab_entries(rest, active, state)

def found_work_label(found: Maybe<&2, Work.Work>, id: Nat) -> String:
  match found:
    case None{}: "Work #" ++ Nat.show(id)
    case Some{value}: Work.name(value)

def work_label(work: Maybe<&2, Nat>, world: M.World()) -> String:
  match work:
    case None{}: "All Tasks"
    case Some{+id}: found_work_label(Work.find(WorkState.registry(world), id), id)

def work_count_label(count: Nat) -> String:
  match count:
    case 1n: "1 tab"
    case other: Nat.show(other) ++ " tabs"

def work_overview_trigger(+count: Nat, state: InteractionTypes.State) -> SurfaceTypes.Node:
  replace_role(declared(Identity.Place{"/work-tabs"}, View.control("work/overview", "Work overview, " ++ work_count_label(count), U.OpenPanel{U.WorkOverview{}, "work/overview"}), state), SurfaceTypes.WorkOverviewButton{count})

def compact_work_scope(+active: Maybe<&2, Nat>, +title: String, +count: Nat, state: InteractionTypes.State) -> SurfaceTypes.Node:
  replace_role(declared(Identity.Place{"/work-tabs"}, View.control(work_tab_identity(active), title ++ ", Work overview, " ++ work_count_label(count), U.OpenPanel{U.WorkOverview{}, work_tab_identity(active)}), state), SurfaceTypes.CompactWorkScope{title, count})

def counted_work_tab_form(full: Bool, +active: Maybe<&2, Nat>, values: +List<Finite.Entry(Work.Work)>, world: M.World(), +state: InteractionTypes.State, count: Nat) -> SurfaceTypes.Node:
  match full:
    case True{}:
      SurfaceTypes.Node{Identity.Place{"/work-tabs"}, "work-tabs", "Works", SurfaceTypes.WorkTabs{}, SurfaceTypes.Region{},
        [work_tab(None{}, "All Tasks", active, state),
          region(Identity.Place{"/work-tabs"}, "work-tabs/collection", "", SurfaceTypes.WorkTabGroup{}, work_tab_entries(values, active, state)),
          declared(Identity.Place{"/work-tabs"}, View.control("work/new", "New Work", U.CreateWork{}), state), work_overview_trigger(count, state)]}
    case False{}:
      compact_work_scope(active, work_label(active, world), count, state)

def work_tab_form(full: Bool, active: Maybe<&2, Nat>, +values: +List<Finite.Entry(Work.Work)>, world: M.World(), state: InteractionTypes.State) -> SurfaceTypes.Node:
  counted_work_tab_form(full, active, values, world, state, (List.length(&2, Finite.Entry(Work.Work), values) + 1n : Nat))

def work_tabs(full: Bool, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  +application = Core.application(state)
  +active = E.active_work(E.session(application))
  work_tab_form(full, active, Work.works(WorkState.registry(E.program(application))), E.program(application), state)

def compact_navigation_toggle(expanded: Bool, declaration: V.ControlDeclaration) -> V.ControlDeclaration:
  V.ControlDeclaration{identity, label, prominence, input, availability} = declaration
  V.ControlDeclaration{identity, View.compact_task_navigation_toggle_label(expanded), prominence, input, availability}

def compact_header(view: V.Navigation, +state: InteractionTypes.State) -> SurfaceTypes.Node:
  V.Navigation{expanded, create, destinations, projects, tasks, toggle} = view
  SurfaceTypes.Node{Identity.Place{"/work-tabs"}, "work-switcher", "Workspace navigation", SurfaceTypes.CompactHeader{}, SurfaceTypes.Region{},
    [declared(Identity.Place{"/global-navigation"}, View.control("global/menu", "Global navigation", U.OpenPanel{U.GlobalNavigation{}, "global/menu"}), state),
     work_tabs(False{}, state), declared(Identity.Place{"/navigation"}, compact_navigation_toggle(expanded, toggle), state)]}

def compact_base_header(placement: V.NavigationPlacement, nav: V.Navigation, state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match placement:
    case V.ModalNavigation{}: Nil{}
    case _: [compact_header(nav, state)]

def workspace_navigation(full: Bool, arrangement: V.Arrangement, +nav: V.Navigation, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match full arrangement:
    case True{} original: global_navigation(False{}, nav, state) <> work_tabs(True{}, state) <> base_navigation(original, nav, state)
    case False{} V.Arrangement{placement}: compact_base_header(placement, nav, state)

def workspace_modal_navigation(full: Bool, arrangement: V.Arrangement, +nav: V.Navigation, +state: InteractionTypes.State) -> +List<SurfaceTypes.Node>:
  match full arrangement:
    case True{} original: modal_navigation(original, nav, state)
    case False{} V.Arrangement{V.ModalNavigation{}}: [compact_navigation(nav, compact_header(nav, state), state)]
    case False{} _: Nil{}

def compact_navigation_action_role(role: SurfaceTypes.Role, meaning: SurfaceTypes.Meaning) -> SurfaceTypes.Role:
  match meaning:
    case SurfaceTypes.Activate{InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.CreateWork{}}}}, availability}: SurfaceTypes.CompactNavigationEntry{False{}}
    case SurfaceTypes.Activate{InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.ClosePanel{}}}}, availability}: SurfaceTypes.CompactNavigationEntry{False{}}
    case _: role

def compact_overview_actions(values: +List<SurfaceTypes.Node>) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{SurfaceTypes.Node{key, semantic, label, role, +meaning, children}, rest}:
      SurfaceTypes.Node{key, semantic, label, compact_navigation_action_role(role, meaning), meaning, compact_overview_actions(children)} <> compact_overview_actions(rest)

def compact_overview_when(selected: Bool, node: SurfaceTypes.Node) -> SurfaceTypes.Node:
  match selected node:
    case True{} SurfaceTypes.Node{key, semantic, label, role, meaning, children}:
      SurfaceTypes.Node{key, semantic, label, role, meaning, compact_overview_actions(children)}
    case False{} original: original

def compact_overview_layers(values: +List<SurfaceTypes.Node>) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{+node, rest}:
      compact_overview_when(String.eq(node_key(node), Identity.encode(layer_key("work-overview"))), node) <> compact_overview_layers(rest)

def navigation_layers(full: Bool, values: +List<SurfaceTypes.Node>) -> +List<SurfaceTypes.Node>:
  match full:
    case True{}: values
    case False{}: compact_overview_layers(values)

def assemble(+full: Bool, +content: InteractionTypes.Scene, +state: InteractionTypes.State) -> SurfaceTypes.Surface:
  InteractionTypes.Scene{V.Scene{+nav, +main, +views, +arrangement, attention}, +preferences, transfers, +attachment, code, +folder_picker} = content
  +overlays = List.append(&2, SurfaceTypes.Node, preview(attachment), List.append(&2, SurfaceTypes.Node, directory_picker(folder_picker), List.append(&2, SurfaceTypes.Node, settings(preferences), List.append(&2, SurfaceTypes.Node, navigation_layers(full, layers(views, state)), workspace_modal_navigation(full, arrangement, nav, state)))))
  # NOTE: Saved trigger identities can alias navigation; only main owns relocation.
  +reachable = finish_reachable(content, [page(main, state)], overlays)
  with_workspace_navigation(content,
    workspace_navigation(full, arrangement, nav, state), reachable, active_scope(overlays))

def observe(capacity: V.Capacity, +state: InteractionTypes.State) -> SurfaceTypes.Surface:
  V.Capacity{+navigation_beside, +details_beside} = capacity
  assemble(navigation_beside, Core.observe(V.Capacity{navigation_beside, details_beside}, state), state)

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
    case SurfaceTypes.ActionCommit{assessment, InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.Submit{owner}}}}, availability}: UX.assessment_ready(assessment) && available(availability) && U.same_editor(owner, editor)
    case SurfaceTypes.SupportingControl{support, property, InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.Submit{owner}}}}, availability}: UX.support_visible(support) && available(availability) && U.same_editor(owner, editor)
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
