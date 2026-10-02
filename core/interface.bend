import Base
import ../MODEL.bend as M
import ../COMMANDS.bend as Commands
import ../BOARD.bend as B
import ../PROJECTS.bend as Projects
import ../FEATURES.bend as F
import ../REASONING.bend as Reasoning
import ../bendlib/domain.bend as D
import ../bendlib/board-state.bend as Board
import ../bendlib/board-filter.bend as BoardFilter
import ../bendlib/json.bend as J
import ../bendlib/schema.bend as Schema
import ./SYSTEM.bend as Core
import ./laws.bend as Laws
import ./user-experience.bend as E
import ./user-input.bend as U
import ./ui-world.bend as V
import ./composition.bend as Composition
import ./user-conversation.bend as Conversation
import ./form-fields.bend as Forms
import ./client-services.bend as Services
import ./code-block.bend as Code
import ./live-output.bend as Live
import ./user-context.bend as Context
import ../bendlib/association-map.bend as Finite

type Role is Data:
  Navigation{}
  NavigationHeader{}
  Main{}
  Heading{}
  PrimaryButton{}
  DestructiveButton{}
  SelectedButton{}
  ComposerActions{}
  Timeline{}
  Activity{}
  UserMessage{}
  AssistantMessage{}
  Composer{}
  Approval{}
  Toolbar{}
  CodeBlock{}
  ApprovalQueue{}
  Section{}
  Dialog{}
  Menu{}
  Details{}
  Card{}
  Button{}
  Field{}
  Content{}
  Alert{}

type Placement is Data:
  Placement{target: String, input: Core.Input, availability: V.Availability}

type BoardGrouping is Data:
  ViewChoices{}
  SearchArea{}
  WorkStatus{}
  SecondaryActions{}
  PrimaryAction{}

type Meaning is Data:
  MovableCard{destinations: +List<Placement>, face: V.CardFace}
  Region{}
  ProjectGroup{project: Nat, selected: Bool, expanded: Bool}
  TaskRow{task: Nat, status: String, selected: Bool}
  ProjectChooser{selected: Maybe<&2, Nat>}
  DirectoryRow{path: String, primary: Bool}
  ContextSummary{observation: Context.Observation}
  ChoiceGroup{}
  Choice{selected: Bool, description: String, input: Core.Input, availability: V.Availability}
  PageRegion{region: Composition.Region, position: Composition.Position}
  BoardLane{stage: B.Stage, count: Nat}
  CardArchive{count: Nat}
  BoardSearch{filter: B.Filter}
  BoardGroup{grouping: BoardGrouping}
  ReadOnly{text: String}
  TaskFacts{details: V.TaskDetails}
  CodeFacts{view: Code.Scene}
  Activate{input: Core.Input, availability: V.Availability}
  ComposerAction{subject: V.ComposerSubject, input: Core.Input, availability: V.Availability}
  Edit{editor: U.Editor, field: Forms.Field, entry: Forms.Entry, value: Forms.Observed}
  SearchChoices{query: String}
  EnterCredential{entered: Bool}
  ReceiveFile{editor: U.Editor, enabled: Bool}
  EnterDirectory{editor: U.Editor, text: String}
  BoardProfile{automatic: Bool, selected: String, choices: +List<D.Profile>, enabled: Bool}

type Node is Data:
  Node{key: String, semantic: String, label: String, role: Role, meaning: Meaning, children: +List<Node>}

# Content and interaction are two projections of one observation. Keys in the
# interaction tree identify the actual controls, fields and owning regions.
# Intrinsic declarations in content are never a second activation authority.
type Surface is Data:
  Surface{content: Core.Scene, base: +List<Node>, overlays: +List<Node>, active_scope: Maybe<&2, String>}

type Gesture is Data:
  Place{target: String}
  Press{}
  Change{value: Forms.Value}
  Search{query: String}
  Credential{value: String}
  Filter{value: B.Filter}
  Attach{file: Services.File}
  Directory{path: String}
  ConfirmDirectory{}
  SelectBoardProfile{profile: String}

def region(parent: String, +identity: String, label: String, role: Role, children: +List<Node>) -> Node:
  Node{parent ++ "/" ++ identity, identity, label, role, Region{}, children}

def action_role(prominence: V.Prominence) -> Role:
  match prominence:
    case V.Primary{}: PrimaryButton{}
    case V.Destructive{}: DestructiveButton{}
    case V.Secondary{}: Button{}

def action(parent: String, control: Core.Control) -> Node:
  Core.Control{+identity, label, prominence, input, availability} = control
  Node{parent ++ "/" ++ identity, identity, label, action_role(prominence), Activate{input, availability}, Nil{}}

def replace_role(node: Node, role: Role) -> Node:
  Node{key, semantic, label, old_role, meaning, children} = node
  Node{key, semantic, label, role, meaning, children}

def selected_node(selected: Bool, node: Node) -> Node:
  match selected:
    case True{}: replace_role(node, SelectedButton{})
    case False{}: node

def declared(parent: String, declaration: V.ControlDeclaration, state: Core.State) -> Node:
  action(parent, Core.control(state, declaration))

def controls(values: +List<V.ControlDeclaration>, +parent: String, +state: Core.State) -> +List<Node>:
  match values:
    case Nil{}: Nil{}
    case Con{control, rest}: declared(parent, control, state) <> controls(rest, parent, state)

def availability(enabled: Bool) -> V.Availability:
  match enabled:
    case True{}: V.Available{}
    case False{}: V.Unavailable{"Unavailable in the current state"}

def product_action(parent: String, identity: String, label: String, input: Core.Input, enabled: Bool) -> Node:
  action(parent, Core.Control{identity, label, V.Secondary{}, input, availability(enabled)})

def user_action(parent: String, identity: String, label: String, input: U.Input, enabled: Bool, state: Core.State) -> Node:
  declared(parent, V.ControlDeclaration{identity, label, V.Secondary{}, input, availability(enabled)}, state)

def more(+subject: U.Subject, parent: String, state: Core.State) -> Node:
  declared(parent, V.control("more/" ++ U.subject_key(subject), "More actions",
    U.OpenPanel{U.ObjectActions{subject}, "more/" ++ U.subject_key(subject)}), state)

def task_entries(entries: +List<V.TaskEntry>, +parent: String, +state: Core.State) -> +List<Node>:
  match entries:
    case Nil{}: Nil{}
    case Con{V.TaskEntry{+id, title, +status, +selected, open}, rest}:
      Node{parent ++ "/task/" ++ Nat.show(id), "task-row", "", Section{}, TaskRow{id, status, selected},
        [selected_node(selected, declared(parent ++ "/task/" ++ Nat.show(id), open, state)),
         Node{parent ++ "/task/" ++ Nat.show(id) ++ "/status", "task-status", "Task status", Content{}, ReadOnly{status}, Nil{}}]} <> task_entries(rest, parent, state)

def disclosed_tasks(expanded: Bool, tasks: +List<V.TaskEntry>, parent: String, state: Core.State) -> +List<Node>:
  match expanded:
    case False{}: Nil{}
    case True{}: task_entries(tasks, parent, state)

def project_entries(entries: +List<V.ProjectEntry>, +parent: String, +state: Core.State) -> +List<Node>:
  match entries:
    case Nil{}: Nil{}
    case Con{V.ProjectEntry{+id, name, workspace, +selected, +expanded, tasks, open, create, toggle, more}, rest}:
      Node{parent ++ "/project/" ++ Nat.show(id), "project-group", "", Section{}, ProjectGroup{id, selected, expanded},
        region(parent ++ "/project/" ++ Nat.show(id), "actions", "", Section{},
          [declared(parent ++ "/project/" ++ Nat.show(id), toggle, state), selected_node(selected, declared(parent ++ "/project/" ++ Nat.show(id), open, state)),
           declared(parent ++ "/project/" ++ Nat.show(id), create, state), declared(parent ++ "/project/" ++ Nat.show(id), more, state)]) <>
        disclosed_tasks(expanded, tasks, parent ++ "/project/" ++ Nat.show(id), state)} <> project_entries(rest, parent, state)

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

def selected_declaration(+route: U.Route, +parent: String, declaration: V.ControlDeclaration, +state: Core.State) -> Node:
  V.ControlDeclaration{identity, label, prominence, +input, availability} = declaration
  selected_node(navigation_action_selected(route, input), declared(parent, declaration, state))

def selected_controls(+route: U.Route, +values: +List<V.ControlDeclaration>, +parent: String, +state: Core.State) -> +List<Node>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: selected_declaration(route, parent, value, state) <> selected_controls(route, rest, parent, state)

def navigation_contents(expanded: Bool, +route: U.Route, create: V.ControlDeclaration, destinations: +List<V.ControlDeclaration>, projects: +List<V.ProjectEntry>, tasks: +List<V.TaskEntry>, +state: Core.State) -> +List<Node>:
  match expanded:
    case False{}: Nil{}
    case True{}:
      selected_declaration(route, "/navigation", create, state) <> List.append(&2, Node, selected_controls(route, destinations, "/navigation", state),
        List.append(&2, Node, project_entries(projects, "/navigation", state), task_entries(tasks, "/navigation", state)))

def navigation(view: V.Navigation, +state: Core.State) -> Node:
  V.Navigation{expanded, create, destinations, projects, tasks, toggle} = view
  Core.State{E.Application{world, E.Session{+route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code}}, services} = state
  +header: Node = Node{"/navigation/header", "navigation-header", "Selvedge", NavigationHeader{}, Region{},
    [declared("/navigation", toggle, state)]}
  region("", "navigation", "Navigation", Navigation{}, header <>
    navigation_contents(expanded, route, create, destinations, projects, tasks, state))

def observed_field(found: Maybe<&2, U.Draft>, field: Forms.Field, world: M.World()) -> Forms.Observed:
  match found:
    case None{}: Forms.NotApplicable{}
    case Some{U.Draft{revision, body, feedback, directory_entry}}: Forms.observed(body, field, world)

def field_value(state: Core.State, editor: U.Editor, field: Forms.Field) -> Forms.Observed:
  Core.State{E.Application{world, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code}}, services} = state
  observed_field(E.find_draft(drafts, editor), field, world)

def attachment_nodes(files: +List<B.Attachment>, +editor: U.Editor, +parent: String) -> +List<Node>:
  match files:
    case Nil{}: Nil{}
    case Con{B.Attachment{+id, +name, mime, path, bytes}, rest}:
      region(parent, id, name, Section{},
        [product_action(parent ++ "/" ++ id, "preview", "Preview " ++ name, Core.ServiceInput{Services.OpenPreview{B.Attachment{id, name, mime, path, bytes}, parent ++ "/" ++ id ++ "/preview"}}, True{}),
         product_action(parent ++ "/" ++ id, "remove", "Remove " ++ name, Core.RemoveAttachment{editor, id}, True{})]) <> attachment_nodes(rest, editor, parent)

def transfer_controls(+ticket: Nat, value: Services.Transfer, +parent: String) -> +List<Node>:
  match value:
    case Services.Uploading{editor, file}:
      [product_action(parent, "cancel-upload/" ++ Nat.show(ticket), "Cancel upload", Core.ServiceInput{Services.CancelUpload{ticket}}, True{})]
    case Services.UploadFailed{editor, file, reason}:
      [product_action(parent, "retry-upload/" ++ Nat.show(ticket), "Retry upload", Core.ServiceInput{Services.RetryUpload{ticket}}, True{}),
       product_action(parent, "cancel-upload/" ++ Nat.show(ticket), "Remove failed upload", Core.ServiceInput{Services.CancelUpload{ticket}}, True{})]

def transfer_node(owned: Bool, ticket: Nat, value: Services.Transfer, parent: String) -> +List<Node>:
  match owned:
    case False{}: Nil{}
    case True{}: transfer_controls(ticket, value, parent)

def transfer_nodes(values: +List<Finite.Entry(Services.Transfer)>, +editor: U.Editor, +parent: String) -> +List<Node>:
  match values:
    case Nil{}: Nil{}
    case Con{(ticket, +value), rest}:
      List.append(&2, Node, transfer_node(U.same_editor(Services.transfer_editor(value), editor), ticket, value, parent), transfer_nodes(rest, editor, parent))

def files_observed(value: Forms.Observed) -> +List<B.Attachment>:
  match value:
    case Forms.AttachmentsValue{files}: files
    case _: Nil{}

def file_field(+editor: U.Editor, +parent: String, state: Core.State) -> +List<Node>:
  Core.State{application, Services.State{+access, credential, settings, appearance, next, +transfers, preview}} = state
  Node{parent ++ "/add", "attachment/add", "Add attachment", Field{}, ReceiveFile{editor, Services.connected(access)}, Nil{}} <>
    List.append(&2, Node, attachment_nodes(files_observed(field_value(state, editor, Forms.CardAttachments{})), editor, parent), transfer_nodes(transfers, editor, parent))

def workspace_value(value: Context.WorkspaceValue) -> D.Workspace:
  match value:
    case Context.InheritedWorkspace{value}: value
    case Context.EnteredWorkspace{value}: value

def context_workspace(value: Context.Preview) -> Maybe<&2, D.Workspace>:
  match value:
    case Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}: Some{workspace_value(workspace)}
    case _: None{}

def workspace_observed(value: Forms.Observed) -> Maybe<&2, D.Workspace>:
  match value:
    case Forms.WorkspaceValue{workspace}: Some{workspace}
    case Forms.ContextValue{value}: context_workspace(value)
    case _: None{}

def directory_primary_controls(primary: Bool, control: V.ControlDeclaration, parent: String, state: Core.State) -> +List<Node>:
  match primary:
    case True{}: [Node{parent ++ "/primary", "directory/primary", "Primary working directory", Content{}, ReadOnly{"Primary working directory"}, Nil{}}]
    case False{}: [declared(parent, control, state)]

def directory_node(value: V.WorkspaceRoot, parent: String, +state: Core.State) -> Node:
  V.WorkspaceRoot{+path, +primary, choose, remove} = value
  +key = parent ++ "/directory/" ++ path
  Node{key, "directory/" ++ path, path, Content{}, DirectoryRow{path, primary},
    List.append(&2, Node, directory_primary_controls(primary, choose, key, state), [declared(key, remove, state)])}

def directory_root_nodes(roots: +List<V.WorkspaceRoot>, +parent: String, +state: Core.State) -> +List<Node>:
  match roots:
    case Nil{}: Nil{}
    case Con{root, rest}: directory_node(root, parent, state) <> directory_root_nodes(rest, parent, state)

def directory_controls(controls: V.WorkspaceControls, parent: String, state: Core.State) -> +List<Node>:
  V.WorkspaceControls{identity, roots, inherit} = controls
  directory_root_nodes(roots, parent, state)

def directory_values(found: Maybe<&2, D.Workspace>, +editor: U.Editor, parent: String, state: Core.State) -> +List<Node>:
  match found:
    case None{}: Nil{}
    case Some{workspace}: directory_controls(V.workspace_controls(workspace, editor, None{}), parent, state)

def draft_directory(found: Maybe<&2, U.Draft>) -> String:
  match found:
    case None{}: ""
    case Some{draft}: U.directory_entry(draft)

def pending_directory(state: Core.State, editor: U.Editor) -> String:
  Core.State{E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code}}, services} = state
  draft_directory(E.find_draft(drafts, editor))

def directory_can_confirm(found: Maybe<&2, U.Draft>) -> Bool:
  match found:
    case None{}: False{}
    case Some{draft}: U.can_confirm_directory(draft)

def directory_ready(state: Core.State, editor: U.Editor) -> Bool:
  Core.State{E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code}}, services} = state
  directory_can_confirm(E.find_draft(drafts, editor))

def directory_confirm(+editor: U.Editor, parent: String, +state: Core.State) -> Node:
  user_action(parent, "workspace/confirm", "Add folder", U.EditDraft{editor, U.ConfirmDirectory{}}, directory_ready(state, editor), state)

def field_children(field: Forms.Field, +editor: U.Editor, +parent: String, +state: Core.State) -> +List<Node>:
  match field:
    case Forms.CardAttachments{}: file_field(editor, parent, state)
    case Forms.WorkspaceDirectories{}:
      Node{parent ++ "/instruction", "workspace/instruction", "Enter a directory path to add it. Listed directories define the workspace; choose the primary working directory.", Content{},
        ReadOnly{"Enter a directory path to add it. Listed directories define the workspace; choose the primary working directory."}, Nil{}} <>
      Node{parent ++ "/add", "workspace/add", "Add working directory", Field{}, EnterDirectory{editor, pending_directory(state, editor)}, Nil{}} <>
      directory_confirm(editor, parent, state) <>
        directory_values(workspace_observed(field_value(state, editor, Forms.WorkspaceDirectories{})), editor, parent, state)
    case _: Nil{}

def policy_entry(policy: Reasoning.Policy) -> Forms.Entry:
  match policy:
    case Reasoning.Fixed{}: Forms.SingleLine{}
    case _: Forms.DisplayOnly{}

def effort_entry(profile: Maybe<&2, D.Profile>) -> Forms.Entry:
  match profile:
    case None{}: Forms.DisplayOnly{}
    case Some{D.Profile{key, provider, name, policy}}: policy_entry(policy)

def field_entry(field: Forms.Field, entry: Forms.Entry, value: Forms.Observed, world: M.World()) -> Forms.Entry:
  match field value:
    case Forms.ReasoningEffort{} Forms.ModelValue{profile, effort}: effort_entry(D.find_profile(Commands.configured(Commands.settings(world)), profile))
    case _ _: entry

def actual_entry(field: Forms.Field, entry: Forms.Entry, value: Forms.Observed, state: Core.State) -> Forms.Entry:
  Core.State{E.Application{world, session}, services} = state
  field_entry(field, entry, value, world)

def field_node(+field: Forms.FieldScene, +editor: U.Editor, +parent: String, +state: Core.State) -> Node:
  Forms.FieldScene{+field, label, entry} = field
  Node{parent ++ "/" ++ Forms.key(field), Forms.key(field), label, Field{}, Edit{editor, field, actual_entry(field, entry, field_value(state, editor, field), state), field_value(state, editor, field)}, field_children(field, editor, parent ++ "/" ++ Forms.key(field), state)}

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

def reset_fields(field: Forms.Field, workspace: Maybe<&2, D.Workspace>, sandbox: Maybe<&2, D.Sandbox>, approval: Maybe<&2, Context.ApprovalChoice>) -> Maybe<&2, Context.Change>:
  match field workspace sandbox approval:
    case Forms.WorkspaceDirectories{} Some{value} _ _: Some{Context.UseDefaultWorkspace{}}
    case Forms.SandboxMode{} _ Some{value} _: Some{Context.UseDefaultSandbox{}}
    case Forms.ApprovalPolicy{} _ _ Some{value}: Some{Context.UseDefaultApproval{}}
    case _ _ _ _: None{}

def reset_change(config: Context.Configuration, field: Forms.Field) -> Maybe<&2, Context.Change>:
  Context.Configuration{origin, workspace, sandbox, approval} = config
  reset_fields(field, workspace, sandbox, approval)

def reset_control(change: Maybe<&2, Context.Change>, editor: U.Editor, field: Forms.Field, label: String, parent: String, state: Core.State) -> +List<Node>:
  match change:
    case None{}: Nil{}
    case Some{change}: [user_action(parent, "default/" ++ Forms.key(field), "Use defaults for " ++ label, U.EditDraft{editor, U.ConfigureContext{change}}, True{}, state)]

def configured_reset(config: Maybe<&2, Context.Configuration>, editor: U.Editor, +field: Forms.Field, label: String, parent: String, state: Core.State) -> +List<Node>:
  match config:
    case None{}: Nil{}
    case Some{value}: reset_control(reset_change(value, field), editor, field, label, parent, state)

def field_resets(+field: Forms.FieldScene, +editor: U.Editor, parent: String, +state: Core.State) -> +List<Node>:
  Forms.FieldScene{+field, label, entry} = field
  Core.State{E.Application{program, E.Session{route, +drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code}}, services} = state
  configured_reset(draft_configuration(E.find_draft(drafts, editor)), editor, field, label, parent, state)
def fields(values: +List<Forms.FieldScene>, +editor: U.Editor, +parent: String, +state: Core.State) -> +List<Node>:
  match values:
    case Nil{}: Nil{}
    case Con{+field, rest}: field_node(field, editor, parent, state) <> List.append(&2, Node, field_resets(field, editor, parent, state), fields(rest, editor, parent, state))

def sections(values: +List<Forms.Section>, +editor: U.Editor, +parent: String, +ordinal: Nat, +state: Core.State) -> +List<Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Forms.Section{title, entries}, rest}:
      region(parent, "section/" ++ Nat.show(ordinal), title, Section{}, fields(entries, editor, parent ++ "/section/" ++ Nat.show(ordinal), state)) <>
        sections(rest, editor, parent, (ordinal + 1n : Nat), state)

def feedback_nodes(+parent: String, feedback: U.Feedback) -> +List<Node>:
  match feedback:
    case U.Rejected{revision, +reason}: [Node{parent ++ "/feedback", "submission-feedback", "Submission failed", Alert{}, ReadOnly{reason}, Nil{}}]
    case _: Nil{}

def editor(view: Maybe<&2, V.EditorScene>, +parent: String, +state: Core.State) -> +List<Node>:
  match view:
    case None{}: Nil{}
    case Some{V.EditorScene{identity, revision, groups, structure, submit, feedback, pending}}:
      List.append(&2, Node, sections(structure, identity, parent, 0n, state), List.append(&2, Node, feedback_nodes(parent, feedback), [declared(parent, submit, state)]))

def composer_control_resolved(subject: V.ComposerSubject, parent: String, control: Core.Control) -> Node:
  Core.Control{+identity, label, prominence, input, availability} = control
  Node{parent ++ "/" ++ identity, identity, label, action_role(prominence), ComposerAction{subject, input, availability}, Nil{}}

def composer_control(parent: String, value: V.ComposerControl, state: Core.State) -> Node:
  V.ComposerControl{subject, declaration} = value
  composer_control_resolved(subject, parent, Core.control(state, declaration))

def composer_controls(values: +List<V.ComposerControl>, +parent: String, +state: Core.State) -> +List<Node>:
  match values:
    case Nil{}: Nil{}
    case Con{control, rest}: composer_control(parent, control, state) <> composer_controls(rest, parent, state)

def composer_choices(footer: +List<V.ComposerControl>, +parent: String, +state: Core.State) -> +List<Node>:
  match footer:
    case Nil{}: Nil{}
    case Con{first, rest}:
      [region(parent, "choices", "Choices", Toolbar{}, composer_controls(first <> rest, parent, state))]

def composer_actions(footer: +List<V.ComposerControl>, submit: V.ControlDeclaration, +parent: String, +state: Core.State) -> Node:
  region(parent, "actions", "Actions", ComposerActions{},
    List.append(&2, Node, composer_choices(footer, parent, state), [declared(parent, submit, state)]))

def expected_composer_choices(footer: +List<V.ComposerControl>, +parent: String, +state: Core.State) -> +List<Node>:
  match footer:
    case Nil{}: Nil{}
    case Con{first, rest}:
      [Node{parent ++ "/choices", "choices", "Choices", Toolbar{}, Region{}, composer_controls(first <> rest, parent, state)}]

def expected_composer_actions(footer: +List<V.ComposerControl>, submit: V.ControlDeclaration, +parent: String, +state: Core.State) -> Node:
  Node{parent ++ "/actions", "actions", "Actions", ComposerActions{}, Region{},
    List.append(&2, Node, expected_composer_choices(footer, parent, state), [declared(parent, submit, state)])}

def expected_composer(view: Maybe<&2, V.ComposerScene>, +parent: String, +state: Core.State) -> +List<Node>:
  match view:
    case None{}: Nil{}
    case Some{V.ComposerScene{+identity, revision, message, footer, context, submit, feedback, pending}}:
      +key = parent ++ "/composer/" ++ U.editor_key(identity)
      [Node{key, "composer/" ++ U.editor_key(identity), "Message", Composer{}, Region{},
        field_node(Forms.FieldScene{Forms.MessageText{}, "Message", Forms.Multiline{}}, identity, key, state) <>
          List.append(&2, Node, feedback_nodes(key, feedback), [expected_composer_actions(footer, submit, key, state)])}]

def composer(view: Maybe<&2, V.ComposerScene>, +parent: String, +state: Core.State) -> +List<Node>:
  match view:
    case None{}: Nil{}
    case Some{V.ComposerScene{+identity, revision, message, footer, context, submit, feedback, pending}}:
      +composer_key = parent ++ "/composer/" ++ U.editor_key(identity)
      [region(parent, "composer/" ++ U.editor_key(identity), "Message", Composer{},
        field_node(Forms.FieldScene{Forms.MessageText{}, "Message", Forms.Multiline{}}, identity, composer_key, state) <>
          List.append(&2, Node, feedback_nodes(composer_key, feedback), [composer_actions(footer, submit, composer_key, state)]))]

def composer_tree_present_agreement(+identity: U.Editor, revision: Nat, message: U.Text,
    footer: +List<V.ComposerControl>, context: Maybe<&2, Context.Observation>, submit: V.ControlDeclaration,
    feedback: U.Feedback, pending: Bool, +parent: String, +state: Core.State)
  -> {composer(Some{V.ComposerScene{identity, revision, message, footer, context, submit, feedback, pending}}, parent, state) ==
      expected_composer(Some{V.ComposerScene{identity, revision, message, footer, context, submit, feedback, pending}}, parent, state) : +List<Node>}:
  match footer:
    case Nil{}: {==}
    case Con{first, rest}: {==}

def composer_tree_agreement(view: Maybe<&2, V.ComposerScene>, +parent: String, +state: Core.State)
  -> {composer(view, parent, state) == expected_composer(view, parent, state) : +List<Node>}:
  match view:
    case None{}: {==}
    case Some{V.ComposerScene{+identity, revision, message, footer, context, submit, feedback, pending}}:
      composer_tree_present_agreement(identity, revision, message, footer, context, submit, feedback, pending, parent, state)

def approvals(values: +List<Conversation.DecisionRequest>, +parent: String, +state: Core.State) -> +List<Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Conversation.HumanDecision{+operation, call, approve, deny, +enabled}, rest}:
      region(parent, "approval/" ++ Nat.show(operation), "Approval required", Approval{},
        [user_action(parent ++ "/approval/" ++ Nat.show(operation), "approve", "Approve once", approve, enabled, state),
         user_action(parent ++ "/approval/" ++ Nat.show(operation), "deny", "Deny", deny, enabled, state)]) <> approvals(rest, parent, state)
    case Con{Conversation.AutomaticDecision{+operation, call, reviewer}, rest}:
      region(parent, "approval/" ++ Nat.show(operation), "Automatic review", Approval{}, Nil{}) <> approvals(rest, parent, state)

def disclosure_label(expanded: Bool) -> String:
  match expanded:
    case True{}: "Collapse activity"
    case False{}: "Expand activity"

def disclosure_input(expanded: Bool, expand: U.Input, collapse: U.Input) -> U.Input:
  match expanded:
    case True{}: collapse
    case False{}: expand

def application(state: Core.State) -> E.Application:
  Core.State{application, services} = state
  application

def code_region(value: Code.Scene, +parent: String) -> Node:
  Code.Scene{+identity, literal, wrap, copy, +enabled, controls} = value
  Node{parent ++ "/" ++ Code.key(identity), Code.key(identity), "Code", CodeBlock{}, CodeFacts{Code.Scene{identity, literal, wrap, copy, enabled, controls}},
    [product_action(parent ++ "/" ++ Code.key(identity), "copy", "Copy code", Core.ApplicationInput{E.ContentInput{identity, Code.Copy{}}}, enabled),
     product_action(parent ++ "/" ++ Code.key(identity), "wrap", "Toggle word wrap", Core.ApplicationInput{E.ContentInput{identity, Code.ToggleWrap{}}}, True{})]}

def code_node(owned: Bool, value: Code.Scene, parent: String) -> +List<Node>:
  match owned:
    case False{}: Nil{}
    case True{}: [code_region(value, parent)]

def code_nodes(values: +List<Code.Scene>, +source: Code.Source, +parent: String) -> +List<Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Code.Scene{+identity, literal, wrap, copy, enabled, controls}, rest}:
      List.append(&2, Node, code_node(Code.belongs(identity, source), Code.Scene{identity, literal, wrap, copy, enabled, controls}, parent), code_nodes(rest, source, parent))
def speaker_role(speaker: Conversation.Speaker) -> Role:
  match speaker:
    case Conversation.UserSpeech{}: UserMessage{}
    case Conversation.AssistantSpeech{}: AssistantMessage{}

def groups(values: +List<Conversation.VisibleGroup>, +task: Nat, +parent: String, +state: Core.State) -> +List<Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Conversation.VisibleSpeech{+id, speaker, text, source}, rest}:
      Node{parent ++ "/message/" ++ Nat.show(id), "message/" ++ Nat.show(id), "Message", speaker_role(speaker), ReadOnly{text}, code_nodes(Core.code_scenes(application(state)), Code.Message{task, id}, parent ++ "/message/" ++ Nat.show(id))} <> groups(rest, task, parent, state)
    case Con{Conversation.VisibleActivity{+id, attention, +expanded, summary, audit, expand, collapse}, rest}:
      region(parent, "activity/" ++ Nat.show(id), summary, Activity{},
        [user_action(parent ++ "/activity/" ++ Nat.show(id), "disclosure", disclosure_label(expanded), disclosure_input(expanded, expand, collapse), True{}, state)]) <> groups(rest, task, parent, state)

def latest(input: Maybe<&2, U.Input>, parent: String, state: Core.State) -> +List<Node>:
  match input:
    case None{}: Nil{}
    case Some{input}: [user_action(parent, "latest", "Return to latest", input, True{}, state)]

def operations(values: +List<Conversation.LiveOperation>, +parent: String, +state: Core.State) -> +List<Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Conversation.LiveOperation{id, body, cancel, enabled}, rest}:
      user_action(parent, "cancel/" ++ Nat.show(id), "Cancel operation", cancel, enabled, state) <> operations(rest, parent, state)

def approval_queue(values: +List<Conversation.DecisionRequest>, +parent: String, state: Core.State) -> +List<Node>:
  match values:
    case Nil{}: Nil{}
    case other: [region(parent, "pending-decisions", "Pending approvals", ApprovalQueue{}, approvals(other, parent ++ "/pending-decisions", state))]
def live_parts(parts: +List<Live.Part>, +task: Nat, +operation: Nat, +parent: String, +state: Core.State) -> +List<Node>:
  match parts:
    case Nil{}: Nil{}
    case Con{Live.Part{+index, text}, rest}:
      Node{parent ++ "/part/" ++ Nat.show(index), "stream/part/" ++ Nat.show(index), "Agent output", Content{}, ReadOnly{text}, code_nodes(Core.code_scenes(application(state)), Code.StreamingPart{task, operation, index}, parent ++ "/part/" ++ Nat.show(index))} <> live_parts(rest, task, operation, parent, state)

def live_outputs(outputs: +List<Live.Output>, +parent: String, +state: Core.State) -> +List<Node>:
  match outputs:
    case Nil{}: Nil{}
    case Con{Live.Output{task, +operation, parts}, rest}:
      region(parent, "stream/" ++ Nat.show(operation), "Agent output", Content{}, live_parts(parts, task, operation, parent ++ "/stream/" ++ Nat.show(operation), state)) <> live_outputs(rest, parent, state)

def project(view: V.ProjectScene, +parent: String, +state: Core.State) -> +List<Node>:
  V.ProjectScene{id, name, workspace, guidance, tasks, actions} = view
  region(parent, "heading", name, Heading{}, controls(actions, parent ++ "/heading", state)) <> task_entries(tasks, parent, state)

def projects(values: +List<V.ProjectScene>, +parent: String, +state: Core.State) -> +List<Node>:
  Core.State{E.Application{+world, +session}, services} = state
  E.Session{+route, drafts, readers, layers, focus, +navigation, filter, now, next, pending, previews, code} = session
  project_entries(V.project_entries(Projects.entries(Projects.registry(F.State(), world)), Commands.entries(world), route, V.active_project(route, session, world), navigation), parent, state)

def project_collection_entries(values: +List<V.ProjectScene>, +parent: String, +state: Core.State) -> +List<Node>:
  match values:
    case Nil{}:
      [Node{parent ++ "/projects/empty", "projects/empty", "", Content{},
        ReadOnly{"Create a project to group tasks and choose default working folders."}, Nil{}}]
    case Con{first, rest}: projects(Con{first, rest}, parent, state)

def placement_target(stage: B.Stage, before: Maybe<&2, Nat>) -> String:
  match before:
    case None{}: "/main/" ++ B.stage_name(stage)
    case Some{id}: "/main/" ++ B.stage_name(stage) ++ "/card/" ++ Nat.show(id)

def placement_control(target: String, control: Core.Control) -> Placement:
  Core.Control{identity, label, prominence, input, availability} = control
  Placement{target, input, availability}

def placements_at(values: +List<V.MoveDestination>, +id: Nat, +revision: Nat, +now: U32, +world: M.World(), +state: Core.State) -> +List<Placement>:
  match values:
    case Nil{}: Nil{}
    case Con{V.MoveDestination{+stage, +before, label, availability}, rest}:
      placement_control(placement_target(stage, before), Core.control(state, V.board_control("move", label, B.Move{id, revision, stage, before, now}, world))) <> placements_at(rest, id, revision, now, world, state)

def placements(values: +List<V.MoveDestination>, id: Nat, revision: Nat, +state: Core.State) -> +List<Placement>:
  Core.State{E.Application{world, E.Session{route, drafts, readers, layers, attention, navigation, filter, +now, next, pending, previews, code}}, services} = state
  placements_at(values, id, revision, now, world, state)

def archive_placement(archived: Bool, id: Nat, revision: Nat, +state: Core.State) -> +List<Placement>:
  match archived:
    case True{}: Nil{}
    case False{}:
      Core.State{E.Application{+world, E.Session{route, drafts, readers, layers, attention, navigation, filter, +now, next, pending, previews, code}}, services} = state
      [placement_control("/main/archive-destination", Core.control(state, V.board_control("archive", "归档任务", B.Archive{id, revision, True{}, now}, world)))]

def card(view: V.CardScene, +parent: String, +state: Core.State) -> Node:
  V.CardScene{+id, +value, open, actions, linked, destinations, candidates} = view
  Core.State{E.Application{world, E.Session{route, drafts, readers, layers, attention, navigation, filter, +now, next, pending, previews, code}}, services} = state
  Node{parent ++ "/card/" ++ Nat.show(id), "card/" ++ Nat.show(id), B.title(B.draft(value)), Card{}, MovableCard{List.append(&2, Placement, placements(destinations, id, B.revision(value), state), archive_placement(B.archived(value), id, B.revision(value), state)), V.card_face(id, value, now, world)},
    [declared(parent ++ "/card/" ++ Nat.show(id), open, state), more(U.CardSubject{id}, parent ++ "/card/" ++ Nat.show(id), state)]}

def cards(values: +List<V.CardScene>, +parent: String, +state: Core.State) -> +List<Node>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: card(value, parent, state) <> cards(rest, parent, state)

def board_lane(+stage: B.Stage, +parent: String, count: Nat, +children: +List<Node>) -> Node:
  +key = parent ++ "/" ++ B.stage_name(stage)
  Node{key, B.stage_name(stage), B.stage_label(stage), Section{}, BoardLane{stage, count}, children}

def columns(values: +List<V.BoardColumn>, +parent: String, +state: Core.State) -> +List<Node>:
  match values:
    case Nil{}: Nil{}
    case Con{V.BoardColumn{+stage, +entries, create}, rest}:
      +key = parent ++ "/" ++ B.stage_name(stage)
      +lane_children: +List<Node> = List.append(&2, Node, [declared(key, create, state)], cards(entries, key, state))
      +lane: Node = board_lane(stage, parent, List.length(&2, V.CardScene, entries), lane_children)
      lane <> columns(rest, parent, state)

def project_fact(+key: String, +label: String, text: String) -> Node:
  Node{key, key, label, Content{}, ReadOnly{label ++ "\n" ++ text}, Nil{}}

def agent_observation(+id: Nat, value: B.AgentProfile, edit: V.ControlDeclaration, +parent: String, +state: Core.State) -> Node:
  B.AgentProfile{revision, +name, profile, reasoning, instructions, settings, concurrency} = value
  Core.State{E.Application{+world, session}, services} = state
  +key = parent ++ "/agent/" ++ Nat.show(id)
  region(parent, "agent/" ++ Nat.show(id), name, Section{},
    [project_fact(key ++ "/profile", "模型", profile), project_fact(key ++ "/reasoning", "推理", reasoning),
     project_fact(key ++ "/instructions", "指令", instructions), project_fact(key ++ "/concurrency", "并发上限", Nat.show(concurrency)),
     project_fact(key ++ "/active", "工作中", Nat.show(Board.active_for(B.cards(Board.registry(world)), B.Agent{id}, world))),
     declared(key, edit, state), more(U.AgentSubject{id}, key, state)])

def agents(values: +List<V.AgentScene>, +parent: String, +state: Core.State) -> +List<Node>:
  match values:
    case Nil{}: Nil{}
    case Con{V.AgentScene{+id, value, edit, remove}, rest}:
      agent_observation(id, value, edit, parent, state) <> agents(rest, parent, state)

def page_region(+parent: String, +part: Composition.Region, position: Composition.Position, children: +List<Node>) -> Node:
  +name = Composition.region_name(part)
  Node{parent ++ "/region/" ++ name, name, "", Section{}, PageRegion{part, position}, children}

def page_composer(+input: Maybe<&2, V.ComposerScene>, +parent: String, +owner: String, +state: Core.State, +position: Composition.Position) -> +List<Node>:
  match input:
    case None{}: Nil{}
    case Some{scene}: [page_region(parent, Composition.ComposerInput{}, position, composer(Some{scene}, owner, state))]

def page_latest(+input: Maybe<&2, U.Input>, +parent: String, +owner: String, +state: Core.State) -> +List<Node>:
  match input:
    case None{}: Nil{}
    case Some{value}: [page_region(parent, Composition.LatestAction{}, Composition.DockPosition{}, latest(Some{value}, owner, state))]

def page_approvals(+values: +List<Conversation.DecisionRequest>, +parent: String, +owner: String, +state: Core.State) -> +List<Node>:
  match values:
    case Nil{}: Nil{}
    case Con{first, rest}: [page_region(parent, Composition.ApprovalDecisions{}, Composition.DockPosition{}, approval_queue(first <> rest, owner, state))]

def task_page_fields(+id: Nat, +title: String, page_timeline: Conversation.Timeline, previews: +List<Live.Output>, input: Maybe<&2, V.ComposerScene>, actions: V.TaskActions, +parent: String, +state: Core.State) -> +List<Node>:
  Conversation.Timeline{task, generation, groups_value, live, decisions, reading, return_latest} = page_timeline
  V.TaskActions{detail, overflow} = actions
  +owner = parent ++ "/task/" ++ Nat.show(id)
  page_region(parent, Composition.ConversationTitle{}, Composition.HeadingPosition{},
    [region(owner, "heading", title, Heading{}, Nil{})]) <>
  page_region(parent, Composition.TaskActions{}, Composition.HeadingPosition{},
    [declared(owner ++ "/heading", detail, state), more(U.TaskSubject{id}, owner ++ "/heading", state)]) <>
  page_region(parent, Composition.TimelineContent{}, Composition.BodyPosition{},
    [region(owner, "timeline", "Conversation", Timeline{}, groups(groups_value, id, owner ++ "/timeline", state))]) <>
  page_region(parent, Composition.StreamingOutput{}, Composition.BodyPosition{},
    List.append(&2, Node, live_outputs(previews, owner, state), operations(live, owner, state))) <>
  List.append(&2, Node, page_latest(return_latest, parent, owner, state),
    List.append(&2, Node, page_approvals(decisions, parent, owner, state), page_composer(input, parent, owner, state, Composition.DockPosition{})))

def task_page(value: V.TaskScene, parent: String, state: Core.State) -> +List<Node>:
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

def project_page(value: V.ProjectScene, +parent: String, +state: Core.State) -> +List<Node>:
  V.ProjectScene{id, +name, D.Workspace{roots, primary}, guidance, tasks, actions} = value
  [page_region(parent, Composition.ProjectTitle{}, Composition.HeadingPosition{}, [region(parent, "heading", name, Heading{}, Nil{})]),
   page_region(parent, Composition.ProjectActions{}, Composition.HeadingPosition{}, controls(actions, parent ++ "/heading", state)),
   page_region(parent, Composition.DefaultWorkspace{}, Composition.BodyPosition{},
     [project_fact("project/default-workspace", "Default workspace", workspace_roots(roots)), project_fact("project/primary", "Primary directory", workspace_primary(primary))]),
   page_region(parent, Composition.ProjectGuidance{}, Composition.BodyPosition{}, [project_fact("project/guidance", "Project guidance", guidance_text(guidance))]),
   page_region(parent, Composition.ProjectTasks{}, Composition.BodyPosition{}, task_entries(tasks, parent, state))]

def available(value: V.Availability) -> Bool:
  match value:
    case V.Unavailable{reason}: False{}
    case _: True{}

def enabled_control(control: Core.Control) -> Bool:
  Core.Control{identity, label, prominence, input, availability} = control
  available(availability)

def board_profile(+automatic: Bool, +selected: String, choices: +List<D.Profile>, parent: String, +state: Core.State) -> Node:
  Core.State{E.Application{+world, session}, services} = state
  Node{parent ++ "/drafting-model", "drafting-model", "草稿模型", Field{},
    BoardProfile{automatic, selected, choices, enabled_control(Core.control(state, V.board_control("board/profile", "草稿模型", B.Settings{automatic, selected}, world)))}, Nil{}}

def with_view(+view: String, +filter: B.Filter) -> B.Filter:
  B.Filter{old, search, status, priority, date, assignee, creator, project, label} = filter
  B.Filter{view, search, status, priority, date, assignee, creator, project, label}

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

def board_group(parent: String, +identity: String, grouping: BoardGrouping, +children: +List<Node>) -> Node:
  Node{parent ++ "/" ++ identity, "board-group/" ++ identity, "", Toolbar{}, BoardGroup{grouping}, children}

def view_choice(+view: String, label: String, filter: B.Filter, +parent: String, +state: Core.State) -> Node:
  B.Filter{current_view, search, status, priority, date, assignee, creator, project, labels} = filter
  +declaration: V.ControlDeclaration = V.ControlDeclaration{"view/" ++ view, label, V.Secondary{}, U.FilterBoard{B.Filter{view, search, status, priority, date, assignee, creator, project, labels}}, V.Available{}}
  selected_node(String.eq(current_view, view), declared(parent, declaration, state))

def view_choices(+filter: B.Filter, +parent: String, +state: Core.State) -> +List<Node>:
  B.Filter{view, search, status, priority, date, assignee, creator, project, label} = filter
  [view_choice("all", "全部", filter, parent, state), view_choice("assigned", "已分配", filter, parent, state),
   view_choice("unassigned", "未分配", filter, parent, state)]

def filter_option_nodes(+choices: +List<J.Json>, +category: String, +filter: B.Filter, +parent: String, +state: Core.State) -> +List<Node>:
  match choices:
    case Nil{}: Nil{}
    case Con{+choice, rest}:
      +value = J.text(J.get(choice, "value"))
      +label = J.text(J.get(choice, "label"))
      +declaration: V.ControlDeclaration = V.ControlDeclaration{"filter/" ++ category ++ "/" ++ value, label, V.Secondary{},
        U.FilterBoard{toggle_filter(category, value, filter)}, V.Available{}}
      selected_node(Schema.contains(BoardFilter.values(category, filter), value), declared(parent, declaration, state)) <>
        filter_option_nodes(rest, category, filter, parent, state)

def filter_group(+category: String, label: String, +choices: +List<J.Json>, +filter: B.Filter, +parent: String, +state: Core.State) -> Node:
  region(parent, "filter/" ++ category, label, Section{}, filter_option_nodes(choices, category, filter, parent ++ "/filter/" ++ category, state))

def board_filter_nodes(+filter: B.Filter, +parent: String, +state: Core.State) -> +List<Node>:
  Core.State{E.Application{+world, session}, services} = state
  +cards = B.cards(Board.registry(world))
  filter_group("status", "状态", BoardFilter.stages(B.stages()), filter, parent, state) <>
  filter_group("priority", "优先级", BoardFilter.priority_choices(), filter, parent, state) <>
  filter_group("date", "更新时间", [BoardFilter.choice("1", "最近 24 小时", "clock"), BoardFilter.choice("7", "最近 7 天", "clock"), BoardFilter.choice("30", "最近 30 天", "clock")], filter, parent, state) <>
  filter_group("assignee", "负责人", BoardFilter.owners(world), filter, parent, state) <>
  filter_group("creator", "创建人", [BoardFilter.choice("self", "我", "user")], filter, parent, state) <>
  filter_group("project", "项目", BoardFilter.projects(world), filter, parent, state) <>
  filter_group("label", "标签", BoardFilter.label_choices(BoardFilter.collect_labels(cards, Nil{})), filter, parent, state) <>
  [declared(parent, V.ControlDeclaration{"filters/clear", "清除筛选", V.Secondary{}, U.FilterBoard{B.empty_filter()}, V.Available{}}, state)]

def archive_destination(control: V.ControlDeclaration, +parent: String, +state: Core.State) -> Node:
  Core.State{E.Application{+world, E.Session{+route, drafts, readers, layers, attention, navigation, filter, +now, next, pending, previews, code}}, services} = state
  Node{parent ++ "/archive-destination", "archive-destination", "归档任务", Section{},
    CardArchive{List.length(&2, V.CardScene, V.archived_cards(Board.registry(world), route, now, world))}, [declared(parent, control, state)]}

def board_toolbar(+filter: B.Filter, +working: Nat, create: V.ControlDeclaration, settings: V.ControlDeclaration,
  filters: V.ControlDeclaration, archive: V.ControlDeclaration, +parent: String, +state: Core.State) -> +List<Node>:
  [board_group(parent, "view-choices", ViewChoices{}, view_choices(filter, parent ++ "/view-choices", state)),
   board_group(parent, "search-area", SearchArea{},
     [Node{parent ++ "/search", "board-search", "搜索任务", Field{}, BoardSearch{filter}, Nil{}}]),
   board_group(parent, "work-status", WorkStatus{},
     [view_choice("working", "正在运行的任务 " ++ Nat.show(working), filter, parent ++ "/work-status", state)]),
   board_group(parent, "secondary-actions", SecondaryActions{}, [declared(parent, filters, state), declared(parent, settings, state), archive_destination(archive, parent, state)]),
   board_group(parent, "primary-action", PrimaryAction{}, [declared(parent, create, state)])]

def creation_title_node(value: V.CreationIntroduction, parent: String) -> Node:
  V.CreationIntroduction{+heading, summary, context, project, choose} = value
  Node{parent ++ "/creation/introduction/creation/title", "creation/title", heading, Heading{}, ReadOnly{heading}, Nil{}}

def creation_project_node(value: V.CreationIntroduction, +parent: String, state: Core.State) -> Node:
  V.CreationIntroduction{heading, summary, context, project, choose} = value
  Node{parent ++ "/creation/project", "project-chooser", "", Section{}, ProjectChooser{V.project_choice_id(project)}, [declared(parent, choose, state)]}

def creation_context_node(value: V.CreationIntroduction, parent: String) -> Node:
  V.CreationIntroduction{heading, summary, context, project, choose} = value
  Node{parent ++ "/creation/introduction/creation/context", "creation/context", "Workspace configuration", Content{}, ReadOnly{summary}, Nil{}}

def creation_introduction_nodes(+value: V.CreationIntroduction, +parent: String, state: Core.State) -> +List<Node>:
  [page_region(parent, Composition.CreationIntroduction{}, Composition.BodyPosition{}, [creation_title_node(value, parent), creation_project_node(value, parent, state)]),
   page_region(parent, Composition.CreationContext{}, Composition.BodyPosition{}, [creation_context_node(value, parent)])]

def creation_page(+input: Maybe<&2, V.ComposerScene>, +parent: String, +state: Core.State) -> +List<Node>:
  Core.State{E.Application{world, session}, services} = state
  List.append(&2, Node, creation_introduction_nodes(V.creation_introduction(input, world), parent, state), page_composer(input, parent, parent, state, Composition.BodyPosition{}))

def page_contents(view: V.Page, +parent: String, +state: Core.State) -> +List<Node>:
  match view:
    case V.StartPage{input}: creation_page(input, parent, state)
    case V.TaskPage{value}: task_page(value, parent, state)
    case V.ProjectPage{value}: project_page(value, parent, state)
    case V.ProjectsPage{values, create}:
      [page_region(parent, Composition.CollectionTitle{}, Composition.HeadingPosition{}, [region(parent, "heading", "Projects", Heading{}, Nil{})]),
       page_region(parent, Composition.CollectionActions{}, Composition.HeadingPosition{}, [declared(parent, create, state)]),
       page_region(parent, Composition.ProjectEntries{}, Composition.BodyPosition{}, project_collection_entries(values, parent, state))]
    case V.BoardPage{filter, values, create, working, settings, filters, archive}:
      [page_region(parent, Composition.BoardTitle{}, Composition.HeadingPosition{}, [region(parent, "heading", "Board", Heading{}, Nil{})]),
       page_region(parent, Composition.BoardControls{}, Composition.HeadingPosition{},
         board_toolbar(filter, working, create, settings, filters, archive, parent, state)),
       page_region(parent, Composition.BoardStages{}, Composition.BodyPosition{}, columns(values, parent, state))]
    case V.AgentsPage{values, create}:
      [page_region(parent, Composition.CollectionTitle{}, Composition.HeadingPosition{}, [region(parent, "heading", "Agents", Heading{}, Nil{})]),
       page_region(parent, Composition.CollectionActions{}, Composition.HeadingPosition{}, [declared(parent, create, state)]),
       page_region(parent, Composition.AgentEntries{}, Composition.BodyPosition{}, agents(values, parent, state))]
    case V.MissingObject{message}:
      [page_region(parent, Composition.UnavailableMessage{}, Composition.BodyPosition{}, [Node{parent ++ "/missing", "missing", "Unavailable", Content{}, ReadOnly{message}, Nil{}}])]

def page(view: V.Page, state: Core.State) -> Node:
  region("", "main", "Content", Main{}, page_contents(view, "/main", state))

def selected_effort(same: Bool, effort: String, policy: Reasoning.Policy) -> String:
  match same:
    case True{}: effort
    case False{}: Reasoning.default_selection(policy)
def choice_control(selected: Bool, description: String, control: Core.Control, parent: String) -> Node:
  Core.Control{+identity, label, prominence, input, availability} = control
  Node{parent ++ "/" ++ identity, identity, label, Button{}, Choice{selected, description, input, availability}, Nil{}}

def declared_choice(selected: Bool, description: String, declaration: V.ControlDeclaration, parent: String, state: Core.State) -> Node:
  choice_control(selected, description, Core.control(state, declaration), parent)

def model_choices(profiles: +List<D.Profile>, +selected: String, +effort: String, +editor: U.Editor, +parent: String, +state: Core.State) -> +List<Node>:
  match profiles:
    case Nil{}: Nil{}
    case Con{D.Profile{+key, provider, name, policy}, rest}:
      declared_choice(String.eq(key, selected), provider, V.ControlDeclaration{"model/" ++ key, name, V.Secondary{}, U.EditDraft{editor, U.ChooseModel{key, selected_effort(String.eq(key, selected), effort, policy)}}, V.Available{}}, parent, state) <> model_choices(rest, selected, effort, editor, parent, state)

def delivery_selected(current: U.Delivery, candidate: U.Delivery) -> Bool:
  match current candidate:
    case U.Send{} U.Send{}: True{}
    case U.Steer{} U.Steer{}: True{}
    case _ _: False{}

def picker_fields(values: +List<V.InputGroup>, +editor: U.Editor, +parent: String, +state: Core.State) -> +List<Node>:
  match values:
    case Nil{}: Nil{}
    case Con{V.ModelInput{profile, reasoning, choices}, rest}: List.append(&2, Node, model_choices(choices, profile, reasoning, editor, parent, state), picker_fields(rest, editor, parent, state))
    case Con{V.DeliveryInput{+selected, send, steer}, rest}:
      declared_choice(delivery_selected(selected, U.Send{}), "Send a new message to this task.", send, parent, state) <>
      declared_choice(delivery_selected(selected, U.Steer{}), "Guide the current run with this message.", steer, parent, state) <> picker_fields(rest, editor, parent, state)
    case Con{other, rest}: picker_fields(rest, editor, parent, state)

def execution_details(value: Maybe<&2, V.TaskScene>, parent: String) -> +List<Node>:
  match value:
    case None{}: [Node{parent ++ "/missing", "missing", "Task unavailable", Content{}, ReadOnly{"The task no longer exists"}, Nil{}}]
    case Some{V.TaskScene{id, title, status, context, timeline, previews, composer, details, actions}}:
      [Node{parent ++ "/execution", "execution", "Execution context", Content{}, TaskFacts{details}, Nil{}}]
def enrichment_observation(value: B.Enrichment) -> String:
  match value:
    case B.NoEnrichment{}: ""
    case B.Enriching{ticket, revision, retitle}: "正在生成。原始请求已保存；本次生成完成前不能编辑或移动任务。"
    case B.EnrichmentFailed{reason}: reason

def detail_labels(values: +List<String>) -> String:
  match values:
    case Nil{}: ""
    case Con{value, rest}: value ++ "\n" ++ detail_labels(rest)

def detail_files(values: +List<B.Attachment>, +parent: String) -> +List<Node>:
  match values:
    case Nil{}: Nil{}
    case Con{B.Attachment{+id, +name, +mime, +path, +bytes}, rest}:
      region(parent, id, name, Section{},
        [product_action(parent ++ "/" ++ id, "preview", "Preview " ++ name, Core.ServiceInput{Services.OpenPreview{B.Attachment{id, name, mime, path, bytes}, parent ++ "/" ++ id ++ "/preview"}}, True{})]) <>
        detail_files(rest, parent)

def linked_card_controls(value: Maybe<&2, V.TaskEntry>, parent: String, state: Core.State) -> +List<Node>:
  match value:
    case None{}: Nil{}
    case Some{V.TaskEntry{id, title, status, selected, open}}: [declared(parent, open, state)]

def card_error_observations(+card: B.Card, +parent: String) -> +List<Node>:
  [project_fact(parent ++ "/enrichment", "生成", enrichment_observation(B.enrichment(card))),
   project_fact(parent ++ "/start-error", "启动错误", B.start_error(card))]

def card_detail_draft(value: B.Draft, +id: Nat, +card: B.Card, actions: +List<V.ControlDeclaration>, linked: Maybe<&2, V.TaskEntry>, +parent: String, +state: Core.State) -> +List<Node>:
  B.Draft{title, description, stage, priority, owner, project, labels, files} = value
  Core.State{E.Application{+world, session}, services} = state
  List.append(&2, Node, [project_fact(parent ++ "/identifier", "任务", B.identifier(id)), project_fact(parent ++ "/title", "标题", title),
   project_fact(parent ++ "/description", "描述", description), project_fact(parent ++ "/stage", "状态", B.stage_label(stage)),
   project_fact(parent ++ "/priority", "优先级", B.priority_label(priority)), project_fact(parent ++ "/owner", "负责人", V.face_owner(owner, world)),
   project_fact(parent ++ "/project", "项目", V.face_project(project, world)), project_fact(parent ++ "/labels", "标签", detail_labels(labels)),
   project_fact(parent ++ "/activity", "执行", Board.activity_label(Board.activity(card, world))),
   declared(parent, V.control("card/edit/" ++ Nat.show(id), "编辑任务", U.EditCard{id}), state)],
   List.append(&2, Node, card_error_observations(card, parent), List.append(&2, Node, detail_files(files, parent ++ "/attachments"),
     List.append(&2, Node, linked_card_controls(linked, parent, state), controls(actions, parent, state)))))


def card_details_scene(value: V.CardScene, parent: String, state: Core.State) -> +List<Node>:
  V.CardScene{id, +card, open, actions, linked, destinations, candidates} = value
  card_detail_draft(B.draft(card), id, card, actions, linked, parent, state)

def card_details_nodes(value: Maybe<&2, V.CardScene>, +parent: String, +state: Core.State) -> +List<Node>:
  match value:
    case None{}: [project_fact(parent ++ "/missing", "Unavailable", "The card no longer exists")]
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
      sandbox_facts(V.execution_sandbox(sandbox)) ++ "; " ++ V.value_approval_summary(approval, profiles)
    case Context.CommittedExecution{Context.EffectiveContext{task, D.TaskContext{workspace, sandbox, approval, project}, guidance, access}}:
      sandbox_facts(sandbox) ++ "; " ++ V.policy_approval_summary(approval)

def context_summary_node(+value: Context.Observation, +parent: String, state: Core.State) -> Node:
  Core.State{E.Application{+world, session}, services} = state
  +source = V.execution_source_summary(value, world)
  +facts = observation_facts(value, Board.profiles(world))
  Node{parent ++ "/source", "context/source", source, Content{}, ContextSummary{value},
    [Node{parent ++ "/source/facts", "context/facts", facts, Content{}, ReadOnly{facts}, Nil{}}]}

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

def sandbox_choice(+mode: D.SandboxMode, +current: D.SandboxMode, +network: Bool, +editor: U.Editor, parent: String, state: Core.State) -> Node:
  declared_choice(sandbox_selected(current, mode), sandbox_description(mode),
    V.ControlDeclaration{"filesystem/" ++ D.sandbox_mode_name(mode), sandbox_label(mode), V.Secondary{},
      U.EditDraft{editor, U.ConfigureContext{Context.SetSandbox{D.Sandbox{mode, network}}}}, V.Available{}}, parent, state)

def sandbox_choices(+sandbox: D.Sandbox, +editor: U.Editor, +parent: String, +state: Core.State) -> Node:
  D.Sandbox{+mode, +network} = sandbox
  Node{parent ++ "/filesystem", "permissions/filesystem", "Filesystem access", Section{}, ChoiceGroup{},
    [sandbox_choice(D.WorkspaceWrite{}, mode, network, editor, parent ++ "/filesystem", state),
     sandbox_choice(D.ReadOnly{}, mode, network, editor, parent ++ "/filesystem", state)]}

def approval_profile_key(choice: Context.ApprovalChoice) -> String:
  match choice:
    case Context.AutomaticReview{profile}: profile
    case _: ""

def approval_description(choice: Context.ApprovalChoice) -> String:
  match choice:
    case Context.Ask{}: "Ask before running actions that require approval."
    case Context.Unrestricted{}: "Run actions without approval prompts."
    case Context.AutomaticReview{profile}: "Use this model to review approval requests."

def approval_choice_node(+choice: Context.ApprovalChoice, +current: Context.ApprovalChoice, reviewer: Maybe<&2, D.Profile>, editor: U.Editor, parent: String, state: Core.State) -> Node:
  declared_choice(approval_selected(current, choice), approval_description(choice),
    V.ControlDeclaration{"approval/" ++ Context.approval_option(choice) ++ "/" ++ approval_profile_key(choice), V.execution_approval_summary(choice, reviewer), V.Secondary{},
      U.EditDraft{editor, U.ConfigureContext{Context.SetApproval{choice}}}, V.Available{}}, parent, state)

def reviewer_choices(profiles: +List<D.Profile>, +current: Context.ApprovalChoice, +editor: U.Editor, +parent: String, +state: Core.State) -> +List<Node>:
  match profiles:
    case Nil{}: Nil{}
    case Con{D.Profile{+key, provider, name, policy}, rest}:
      approval_choice_node(Context.AutomaticReview{key}, current, Some{D.Profile{key, provider, name, policy}}, editor, parent, state) <> reviewer_choices(rest, current, editor, parent, state)

def approval_choices(+current: Context.ApprovalChoice, reviewers: +List<D.Profile>, +editor: U.Editor, +parent: String, +state: Core.State) -> Node:
  Node{parent ++ "/approval", "permissions/approval", "Approval policy", Section{}, ChoiceGroup{},
    approval_choice_node(Context.Ask{}, current, None{}, editor, parent ++ "/approval", state) <>
    approval_choice_node(Context.Unrestricted{}, current, None{}, editor, parent ++ "/approval", state) <>
    reviewer_choices(reviewers, current, editor, parent ++ "/approval", state)}

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

def network_choice(+mode: D.SandboxMode, current: Bool, +target: Bool, editor: U.Editor, parent: String, state: Core.State) -> Node:
  declared_choice(network_selected(current, target), network_description(target),
    V.ControlDeclaration{"permissions/network/" ++ network_key(target), network_label(target), V.Secondary{},
      U.EditDraft{editor, U.ConfigureContext{Context.SetSandbox{D.Sandbox{mode, target}}}}, V.Available{}}, parent, state)

def network_choices(sandbox: D.Sandbox, +editor: U.Editor, +parent: String, +state: Core.State) -> Node:
  D.Sandbox{+mode, +network} = sandbox
  Node{parent ++ "/network", "permissions/network", "Network access", Section{}, ChoiceGroup{},
    [network_choice(mode, network, False{}, editor, parent ++ "/network", state),
     network_choice(mode, network, True{}, editor, parent ++ "/network", state)]}

def unavailable_context(+reason: String, parent: String) -> +List<Node>:
  [Node{parent ++ "/unavailable", "context/unavailable", reason, Content{}, ReadOnly{reason}, Nil{}}]

def optional_control(value: Maybe<&2, V.ControlDeclaration>, parent: String, state: Core.State) -> +List<Node>:
  match value:
    case None{}: Nil{}
    case Some{control}: [declared(parent, control, state)]

def workspace_menu_group(+editor: U.Editor, group: V.InputGroup, +parent: String, +state: Core.State) -> +List<Node>:
  match group:
    case V.ExecutionInput{config, Context.ContextUnavailable{reason}, controls, projects, reviewers}: unavailable_context(reason, parent)
    case V.ExecutionInput{config, +preview, V.WorkspaceControls{identity, roots, inherit}, projects, reviewers}:
      context_summary_node(Context.DraftExecution{preview}, parent, state) <>
      Node{parent ++ "/instruction", "workspace/instruction", "Add directories and choose the primary working directory.", Content{}, ReadOnly{"Add directories and choose the primary working directory."}, Nil{}} <>
      Node{parent ++ "/add", "workspace/add", "Add working directory", Field{}, EnterDirectory{editor, pending_directory(state, editor)}, Nil{}} <>
      directory_confirm(editor, parent, state) <>
      List.append(&2, Node, directory_root_nodes(roots, parent, state), optional_control(inherit, parent, state))
    case _: Nil{}

def workspace_menu(groups: +List<V.InputGroup>, +editor: U.Editor, +parent: String, +state: Core.State) -> +List<Node>:
  match groups:
    case Nil{}: Nil{}
    case Con{group, rest}: List.append(&2, Node, workspace_menu_group(editor, group, parent, state), workspace_menu(rest, editor, parent, state))

def permission_menu_group(+editor: U.Editor, group: V.InputGroup, +parent: String, +state: Core.State) -> +List<Node>:
  match group:
    case V.ExecutionInput{config, Context.ContextUnavailable{reason}, controls, projects, reviewers}: unavailable_context(reason, parent)
    case V.ExecutionInput{+config, Context.ProspectiveContext{+origin, +project, +workspace, +sandbox, +approval, +guidance}, controls, projects, reviewers}:
      context_summary_node(Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}, parent, state) <>
      sandbox_choices(V.execution_sandbox(sandbox), editor, parent, state) <>
      network_choices(V.execution_sandbox(sandbox), editor, parent, state) <>
      approval_choices(Context.observed_approval(approval), reviewers, editor, parent, state) <>
      List.append(&2, Node, reset_control(reset_change(config, Forms.SandboxMode{}), editor, Forms.SandboxMode{}, "filesystem and network access", parent, state),
        reset_control(reset_change(config, Forms.ApprovalPolicy{}), editor, Forms.ApprovalPolicy{}, "approval policy", parent, state))
    case _: Nil{}

def permission_menu(groups: +List<V.InputGroup>, +editor: U.Editor, +parent: String, +state: Core.State) -> +List<Node>:
  match groups:
    case Nil{}: Nil{}
    case Con{group, rest}: List.append(&2, Node, permission_menu_group(editor, group, parent, state), permission_menu(rest, editor, parent, state))

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

def committed_project_node(project: Maybe<&2, Nat>, +parent: String, state: Core.State) -> Node:
  Core.State{E.Application{world, session}, services} = state
  +label = committed_project_text(project, world)
  Node{parent ++ "/project", "context/project", label, Content{}, ReadOnly{label}, Nil{}}

def committed_working_directory(primary: Maybe<&2, String>) -> String:
  match primary:
    case None{}: "No working directory"
    case Some{path}: "Working directory: " ++ path

def committed_working_directory_extra(covered: Bool, +primary: Maybe<&2, String>, +parent: String) -> +List<Node>:
  match covered:
    case True{}: Nil{}
    case False{}:
      [Node{parent ++ "/working-directory", "context/working-directory", committed_working_directory(primary), Content{}, ReadOnly{committed_working_directory(primary)}, Nil{}}]

def committed_directory_nodes(roots: +List<String>, +primary: Maybe<&2, String>, +parent: String) -> +List<Node>:
  match roots:
    case Nil{}: Nil{}
    case Con{+path, rest}:
      Node{parent ++ "/directory/" ++ path, "directory/" ++ path, path, Content{}, DirectoryRow{path, V.is_primary(primary, path)},
        [Node{parent ++ "/directory/" ++ path ++ "/primary", "directory/primary", committed_primary_text(V.is_primary(primary, path)), Content{}, ReadOnly{committed_primary_text(V.is_primary(primary, path))}, Nil{}}]} <>
        committed_directory_nodes(rest, primary, parent)

def committed_context_nodes(context: Maybe<&2, Context.EffectiveContext>, +parent: String, +state: Core.State) -> +List<Node>:
  match context:
    case None{}: unavailable_context("Task execution context is unavailable", parent)
    case Some{Context.EffectiveContext{+task, D.TaskContext{D.Workspace{+roots, +primary}, +sandbox, +approval, +project}, +guidance, +access}}:
      context_summary_node(Context.CommittedExecution{Context.EffectiveContext{task, D.TaskContext{D.Workspace{roots, primary}, sandbox, approval, project}, guidance, access}}, parent, state) <>
      committed_project_node(project, parent, state) <>
      List.append(&2, Node, committed_working_directory_extra(Context.member_primary(primary, roots), primary, parent), committed_directory_nodes(roots, primary, parent))

def project_picker_control(control: Core.Control, selected: Bool, description: String, parent: String) -> Node:
  Core.Control{+key, label, prominence, input, availability} = control
  Node{parent ++ "/" ++ key, key, label, Button{}, Choice{selected, description, input, availability}, Nil{}}

def project_picker_choice(declaration: V.ControlDeclaration, selected: Bool, description: String, parent: String, state: Core.State) -> Node:
  project_picker_control(Core.control(state, declaration), selected, description, parent)

def project_registered_choices(values: +List<V.ProjectChoice>, +selected: Maybe<&2, Nat>, +parent: String, +state: Core.State) -> +List<Node>:
  match values:
    case Nil{}: Nil{}
    case Con{V.ProjectChoice{+id, name, +workspace}, rest}:
      project_picker_choice(V.control("project/select/" ++ Nat.show(id), name, U.SelectProject{Some{id}}), V.same_project(selected, Some{id}), V.project_folder_description(workspace), parent, state) <>
        project_registered_choices(rest, selected, parent, state)

def project_choice_nodes(values: +List<V.ProjectChoice>, +selected: Maybe<&2, Nat>, +parent: String, +state: Core.State) -> +List<Node>:
  project_picker_choice(V.control("project/select/none", "No project", U.SelectProject{None{}}), V.same_project(selected, None{}), "Use environment defaults", parent, state) <>
    List.append(&2, Node, project_registered_choices(values, selected, parent, state), [declared(parent, V.control("project/create", "New project", U.EditProject{None{}}), state)])

def layer_content(view: V.LayerContent, +parent: String, +state: Core.State) -> +List<Node>:
  match view:
    case V.ProjectSelection{query, selected, projects}:
      Node{parent ++ "/search", "search", "Search projects", Field{}, SearchChoices{query}, Nil{}} <>
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
      Node{parent ++ "/search", "search", "Search models", Field{}, SearchChoices{query}, Nil{}} <> picker_fields(values, identity, parent, state)
    case V.DeliverySelection{identity, values}: picker_fields(values, identity, parent, state)
    case V.ExecutionDetails{value}: execution_details(value, parent)
    case V.Confirmation{title, confirm, cancel}: [declared(parent, confirm, state), declared(parent, cancel, state)]

def layer_role(kind: V.LayerKind) -> Role:
  match kind:
    case V.ModalDialog{}: Dialog{}
    case V.AnchoredMenu{}: Menu{}
    case V.TrailingDetails{}: Details{}

def layer_key(initial_attention: String) -> String:
  "/layers/" ++ initial_attention

def layers(values: +List<V.Layer>, +state: Core.State) -> +List<Node>:
  match values:
    case Nil{}: Nil{}
    case Con{V.Layer{kind, +content, +initial, restore, close}, rest}:
      Node{layer_key(initial), initial, V.layer_title(content), layer_role(kind), Region{}, List.append(&2, Node,
        layer_content(content, layer_key(initial), state), [declared(layer_key(initial), close, state)])} <> layers(rest, state)

def settings_visible(open: Bool, +entered: Bool, close: Core.Input, connect: Core.Input) -> +List<Node>:
  match open:
    case False{}: Nil{}
    case True{}: [region("/layers", "settings", "Settings", Dialog{},
      [Node{"/layers/settings/credential", "settings/credential", "Access token", Field{}, EnterCredential{entered}, Nil{}},
       product_action("/layers/settings", "connect", "Connect", connect, entered),
       product_action("/layers/settings", "light", "Light appearance", Core.ServiceInput{Services.ChooseAppearance{Services.LightAppearance{}}}, True{}),
       product_action("/layers/settings", "dark", "Dark appearance", Core.ServiceInput{Services.ChooseAppearance{Services.DarkAppearance{}}}, True{}),
       product_action("/layers/settings", "system", "System appearance", Core.ServiceInput{Services.ChooseAppearance{Services.SystemAppearance{}}}, True{}),
       product_action("/layers/settings", "close", "Close settings", close, True{})])]

def settings(view: Core.Settings) -> +List<Node>:
  Core.Settings{open, access, entered, appearance, open_action, close_action, connect_action} = view
  settings_visible(open, entered, close_action, connect_action)

def preview_controls(file: B.Attachment, ready: Bool) -> +List<Node>:
  [region("/layers", "attachment-preview", "Attachment preview", Dialog{},
    [product_action("/layers/attachment-preview", "download", "Download", Core.ServiceInput{Services.Download{file}}, ready),
     product_action("/layers/attachment-preview", "attachment-preview/close", "Close preview", Core.ServiceInput{Services.ClosePreview{}}, True{})])]

def preview(value: Services.Preview) -> +List<Node>:
  match value:
    case Services.NoPreview{}: Nil{}
    case Services.LoadingPreview{ticket, file, trigger}: preview_controls(file, False{})
    case Services.ReadyPreview{file, resource, image, trigger}: preview_controls(file, True{})
    case Services.FailedPreview{file, reason, trigger}: preview_controls(file, False{})

def active_scope(overlays: +List<Node>) -> Maybe<&2, String>:
  match overlays:
    case Nil{}: None{}
    case Con{Node{key, semantic, label, Dialog{}, meaning, children}, rest}: Some{key}
    case Con{Node{key, semantic, label, Menu{}, meaning, children}, rest}: Some{key}
    case Con{other, rest}: active_scope(rest)

def finish(content: Core.Scene, base: +List<Node>, +overlays: +List<Node>) -> Surface:
  Surface{content, base, overlays, active_scope(overlays)}
def collapsed_navigation_toggle(nav: V.Navigation, state: Core.State) -> +List<Node>:
  V.Navigation{expanded, create, destinations, projects, tasks, toggle} = nav
  [declared("/navigation", toggle, state)]

def base_navigation_at(placement: V.NavigationPlacement, nav: V.Navigation, state: Core.State) -> +List<Node>:
  match placement:
    case V.ModalNavigation{}: Nil{}
    case V.CollapsedNavigation{}: collapsed_navigation_toggle(nav, state)
    case V.LeadingNavigation{}: [navigation(nav, state)]

def base_navigation(arrangement: V.Arrangement, nav: V.Navigation, state: Core.State) -> +List<Node>:
  V.Arrangement{placement, page} = arrangement
  base_navigation_at(placement, nav, state)

def navigation_dialog(node: Node) -> Node:
  Node{key, semantic, label, role, meaning, children} = node
  Node{key, semantic, label, Dialog{}, meaning, children}
def modal_navigation_at(placement: V.NavigationPlacement, nav: V.Navigation, state: Core.State) -> +List<Node>:
  match placement:
    case V.ModalNavigation{}: [navigation_dialog(navigation(nav, state))]
    case _: Nil{}

def modal_navigation(arrangement: V.Arrangement, nav: V.Navigation, state: Core.State) -> +List<Node>:
  V.Arrangement{placement, page} = arrangement
  modal_navigation_at(placement, nav, state)

def assemble(content: Core.Scene, +state: Core.State) -> Surface:
  Core.Scene{V.Scene{+nav, +main, +views, +arrangement, attention}, +preferences, transfers, +attachment, code} = content
  finish(content, List.append(&2, Node, base_navigation(arrangement, nav, state), [page(main, state),
    product_action("", "settings/open", "Settings", Core.ServiceInput{Services.OpenSettings{}}, True{})]),
    List.append(&2, Node, preview(attachment), List.append(&2, Node, settings(preferences), List.append(&2, Node, layers(views, state), modal_navigation(arrangement, nav, state)))))

def observe(capacity: V.Capacity, +state: Core.State) -> Surface:
  assemble(Core.observe(capacity, state), state)



def choose_node(same: Bool, node: Node, fallback: Maybe<&2, Node>) -> Maybe<&2, Node>:
  match same:
    case True{}: Some{node}
    case False{}: fallback

def prefer_node(found: Maybe<&2, Node>, fallback: Maybe<&2, Node>) -> Maybe<&2, Node>:
  match found:
    case Some{node}: Some{node}
    case None{}: fallback

def find_node(nodes: +List<Node>, +key: String) -> Maybe<&2, Node>:
  match nodes:
    case Nil{}: None{}
    case Con{Node{+current, semantic, label, role, meaning, +children}, rest}:
      choose_node(String.eq(current, key), Node{current, semantic, label, role, meaning, children},
        prefer_node(find_node(children, key), find_node(rest, key)))

def scope_node(found: Maybe<&2, Node>) -> +List<Node>:
  match found:
    case None{}: Nil{}
    case Some{node}: [node]

def select_scope(scope: Maybe<&2, String>, base: +List<Node>, overlays: +List<Node>) -> +List<Node>:
  match scope:
    case None{}: List.append(&2, Node, base, overlays)
    case Some{key}: scope_node(find_node(overlays, key))


def active_nodes(surface: Surface) -> +List<Node>:
  Surface{content, base, overlays, scope} = surface
  select_scope(scope, base, overlays)

def when_available(enabled: Bool, input: Core.Input) -> Maybe<&2, Core.Input>:
  match enabled:
    case True{}: Some{input}
    case False{}: None{}

def profile_exists(profile: Maybe<&2, D.Profile>) -> Bool:
  match profile:
    case None{}: False{}
    case Some{profile}: True{}

def bind(meaning: Meaning, gesture: Gesture) -> Maybe<&2, Core.Input>:
  match meaning gesture:
    case ComposerAction{subject, input, availability} Press{}: when_available(available(availability), input)
    case Activate{input, availability} Press{}: when_available(available(availability), input)
    case Choice{selected, description, input, availability} Press{}: when_available(available(availability), input)
    case Edit{+editor, +field, Forms.DisplayOnly{}, +value} Change{+next}: None{}
    case Edit{+editor, +field, entry, +value} Change{+next}: Some{Core.EditField{editor, field, next}}
    case SearchChoices{query} Search{+next}: Some{Core.ApplicationInput{E.UserInput{U.SearchChoices{next}}}}
    case EnterCredential{entered} Credential{+value}: Some{Core.ServiceInput{Services.EnterCredential{value}}}
    case BoardSearch{+filter} Search{+next}: Some{Core.ApplicationInput{E.UserInput{U.FilterBoard{with_search(next, filter)}}}}
    case ReceiveFile{+editor, +enabled} Attach{file}: when_available(enabled, Core.ServiceInput{Services.AddFile{editor, file}})
    case BoardProfile{automatic, selected, choices, +enabled} SelectBoardProfile{+profile}: when_available(enabled && profile_exists(D.find_profile(choices, profile)), Core.ApplicationInput{E.UserInput{U.Activate{U.BoardCommand{B.Settings{automatic, profile}}}}})
    case EnterDirectory{+editor, text} Directory{path}: Some{Core.ApplicationInput{E.UserInput{U.EditDraft{editor, U.WriteDirectory{path}}}}}
    case EnterDirectory{editor, text} ConfirmDirectory{}: Some{Core.ApplicationInput{E.UserInput{U.EditDraft{editor, U.ConfirmDirectory{}}}}}
    case _ _: None{}

def bind_node(found: Maybe<&2, Node>, gesture: Gesture) -> Maybe<&2, Core.Input>:
  match found:
    case None{}: None{}
    case Some{Node{key, semantic, label, role, meaning, children}}: bind(meaning, gesture)

def prefer_input(found: Maybe<&2, Core.Input>, fallback: Maybe<&2, Core.Input>) -> Maybe<&2, Core.Input>:
  match found:
    case Some{input}: Some{input}
    case None{}: fallback

def placement_input(values: +List<Placement>, +target: String) -> Maybe<&2, Core.Input>:
  match values:
    case Nil{}: None{}
    case Con{Placement{key, input, availability}, rest}:
      prefer_input(when_available(String.eq(key, target) && available(availability), input), placement_input(rest, target))

def place(source: Maybe<&2, Node>, target: Maybe<&2, Node>) -> Maybe<&2, Core.Input>:
  match source target:
    case Some{Node{key, semantic, label, role, MovableCard{destinations, face}, children}} Some{Node{target, t_semantic, t_label, t_role, t_meaning, t_children}}: placement_input(destinations, target)
    case _ _: None{}

def resolve_present(+source: Node, gesture: Gesture, surface: Surface) -> Maybe<&2, Core.Input>:
  match gesture:
    case Place{target}: place(Some{source}, find_node(active_nodes(surface), target))
    case other: bind_node(Some{source}, other)

def resolve_source(source: Maybe<&2, Node>, gesture: Gesture, surface: Surface) -> Maybe<&2, Core.Input>:
  match source:
    case None{}: None{}
    case Some{node}: resolve_present(node, gesture, surface)

def resolve(+surface: Surface, key: String, gesture: Gesture) -> Maybe<&2, Core.Input>:
  resolve_source(find_node(active_nodes(surface), key), gesture, surface)

def apply_input(input: Maybe<&2, Core.Input>, state: Core.State) -> Core.Decision:
  match input:
    case Some{input}: Core.step(input, state)
    case None{}:
      Core.State{application, services} = state
      Core.application_result(E.unchanged(application), services)

def origin(layers: +List<E.Layer>, key: String) -> String:
  match layers:
    case Con{E.Layer{U.ObjectActions{subject}, trigger, initial, query}, rest}: trigger
    case _: key

def layer_trigger(unchanged: Bool, previous: String, origin: String) -> String:
  match unchanged:
    case True{}: previous
    case False{}: origin

def layer_present(layers: +List<E.Layer>, +target: String) -> Bool:
  match layers:
    case Nil{}: False{}
    case Con{E.Layer{panel, trigger, initial, query}, rest}:
      String.eq(E.panel_target(panel), target) || layer_present(rest, target)

def record_layer(layers: +List<E.Layer>, previous: +List<E.Layer>, origin: String) -> +List<E.Layer>:
  match layers:
    case Nil{}: Nil{}
    case Con{E.Layer{+panel, trigger, initial, query}, rest}:
      E.Layer{panel, layer_trigger(layer_present(previous, E.panel_target(panel)), trigger, origin), initial, query} <> rest

def source_session(session: E.Session, previous: +List<E.Layer>, origin: String) -> E.Session:
  E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code} = session
  E.Session{route, drafts, readers, record_layer(layers, previous, origin), attention, navigation, filter, now, next, pending, previews, code}

def source_decision(decision: Core.Decision, previous: +List<E.Layer>, origin: String) -> Core.Decision:
  Core.Decision{Core.State{E.Application{program, session}, services}, reply, runtime, interaction, service_effects, durable} = decision
  Core.Decision{Core.State{E.Application{program, source_session(session, previous, origin)}, services}, reply, runtime, interaction, service_effects, durable}

def record_source(before: Core.State, key: String, decision: Core.Decision) -> Core.Decision:
  Core.State{E.Application{program, E.Session{route, drafts, readers, +layers, attention, navigation, filter, now, next, pending, previews, code}}, services} = before
  source_decision(decision, layers, origin(layers, key))
def navigates(input: Maybe<&2, Core.Input>) -> Bool:
  match input:
    case Some{Core.ApplicationInput{E.UserInput{U.Activate{U.Navigate{route}}}}}: True{}
    case Some{Core.ApplicationInput{E.UserInput{U.Activate{U.BeginTask{project}}}}}: True{}
    case Some{Core.ApplicationInput{E.UserInput{U.Activate{U.SelectProject{project}}}}}: True{}
    case _: False{}

def dismiss_navigation(session: E.Session) -> E.Session:
  E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code} = session
  E.Session{route, drafts, readers, layers, attention, E.set_navigation(False{}, navigation), filter, now, next, pending, previews, code}

def navigation_closed(decision: Core.Decision) -> Core.Decision:
  Core.Decision{Core.State{E.Application{program, session}, services}, reply, runtime, interaction, service_effects, durable} = decision
  Core.Decision{Core.State{E.Application{program, dismiss_navigation(session)}, services}, reply, runtime, interaction, service_effects, durable}

def after_navigation(dismiss: Bool, decision: Core.Decision) -> Core.Decision:
  match dismiss:
    case False{}: decision
    case True{}: navigation_closed(decision)

def perform_present(capacity: V.Capacity, +state: Core.State, key: String, +input: Maybe<&2, Core.Input>) -> Core.Decision:
  V.Capacity{navigation_beside, details_beside} = capacity
  after_navigation(Bool.not(navigation_beside) && navigates(input), record_source(state, key, apply_input(input, state)))
def perform_input(input: Maybe<&2, Core.Input>, capacity: V.Capacity, state: Core.State, key: String) -> Core.Decision:
  match input:
    case None{}: apply_input(None{}, state)
    case Some{value}: perform_present(capacity, state, key, Some{value})

def perform(capacity: V.Capacity, state: Core.State, key: String, input: Maybe<&2, Core.Input>) -> Core.Decision:
  perform_input(input, capacity, state, key)
def interact(+capacity: V.Capacity, +key: String, gesture: Gesture, +state: Core.State) -> Core.Decision:
  perform(capacity, state, key, resolve(observe(capacity, state), key, gesture))




def focusable(meaning: Meaning) -> Bool:
  match meaning:
    case ComposerAction{subject, input, availability}: available(availability)
    case Activate{input, availability}: available(availability)
    case Choice{selected, description, input, availability}: available(availability)
    case Edit{editor, field, Forms.DisplayOnly{}, value}: False{}
    case Edit{editor, field, Forms.FileCollection{}, value}: False{}
    case Edit{editor, field, Forms.DirectoryCollection{}, value}: False{}
    case Edit{editor, field, entry, value}: True{}
    case SearchChoices{query}: True{}
    case EnterCredential{entered}: True{}
    case BoardSearch{filter}: True{}
    case ReceiveFile{editor, enabled}: enabled
    case EnterDirectory{editor, text}: True{}
    case BoardProfile{automatic, selected, choices, enabled}: enabled
    case _: False{}

def preferred_key(found: Maybe<&2, String>, fallback: Maybe<&2, String>) -> Maybe<&2, String>:
  match found:
    case Some{key}: Some{key}
    case None{}: fallback

def candidate_focus(accepted: Bool, key: String, fallback: Maybe<&2, String>) -> Maybe<&2, String>:
  match accepted:
    case True{}: Some{key}
    case False{}: fallback

def first_focus(nodes: +List<Node>) -> Maybe<&2, String>:
  match nodes:
    case Nil{}: None{}
    case Con{Node{key, semantic, label, role, meaning, children}, rest}:
      candidate_focus(focusable(meaning), key, preferred_key(first_focus(children), first_focus(rest)))

def at_focus(matches: Bool, node: Node) -> Maybe<&2, String>:
  match matches:
    case True{}: first_focus([node])
    case False{}: None{}

def matching_focus(nodes: +List<Node>, +requested: String) -> Maybe<&2, String>:
  match nodes:
    case Nil{}: None{}
    case Con{Node{+key, +semantic, label, role, meaning, +children}, rest}:
      preferred_key(at_focus(String.eq(key, requested) || String.eq(semantic, requested), Node{key, semantic, label, role, meaning, children}),
        preferred_key(matching_focus(children, requested), matching_focus(rest, requested)))

def focus_in(+nodes: +List<Node>, requested: String) -> Maybe<&2, String>:
  preferred_key(matching_focus(nodes, requested), first_focus(nodes))

def focus_target(surface: Surface, requested: String) -> Maybe<&2, String>:
  focus_in(active_nodes(surface), requested)



def source_preserves_program(decision: Core.Decision, previous: +List<E.Layer>, origin: String) ->
  {Laws.runtime(source_decision(decision, previous, origin)) == Laws.runtime(decision) : M.Decision()}:
  Core.Decision{Core.State{E.Application{program, session}, services}, reply, runtime, interaction, service_effects, durable} = decision
  {==}


def submits(meaning: Meaning, editor: U.Editor) -> Bool:
  match meaning:
    case ComposerAction{subject, Core.ApplicationInput{E.UserInput{U.Activate{U.Submit{owner}}}}, availability}: available(availability) && U.same_editor(owner, editor)
    case Activate{Core.ApplicationInput{E.UserInput{U.Activate{U.Submit{owner}}}}, availability}: available(availability) && U.same_editor(owner, editor)
    case _: False{}

def submission(nodes: +List<Node>, +editor: U.Editor) -> Maybe<&2, Node>:
  match nodes:
    case Nil{}: None{}
    case Con{Node{key, semantic, label, role, +meaning, +children}, rest}:
      choose_node(submits(meaning, editor), Node{key, semantic, label, role, meaning, children}, prefer_node(submission(children, editor), submission(rest, editor)))

def submit_found(found: Maybe<&2, Node>, capacity: V.Capacity, state: Core.State) -> Core.Decision:
  match found:
    case None{}: apply_input(None{}, state)
    case Some{Node{key, semantic, label, role, meaning, children}}: perform(capacity, state, key, bind(meaning, Press{}))

def submit_composer(+capacity: V.Capacity, editor: U.Editor, +state: Core.State) -> Core.Decision:
  submit_found(submission(active_nodes(observe(capacity, state)), editor), capacity, state)

def has_submission(found: Maybe<&2, Node>) -> Bool:
  match found:
    case None{}: False{}
    case Some{node}: True{}

def composer_enabled(capacity: V.Capacity, editor: U.Editor, state: Core.State) -> Bool:
  has_submission(submission(active_nodes(observe(capacity, state)), editor))

def content(surface: Surface) -> Core.Scene:
  Surface{content, base, overlays, scope} = surface
  content

def assembled_content(+scene: Core.Scene, state: Core.State) ->
  {content(assemble(scene, state)) == scene : Core.Scene}:
  Core.Scene{V.Scene{nav, main, views, arrangement, attention}, preferences, transfers, attachment, code} = scene
  {==}
