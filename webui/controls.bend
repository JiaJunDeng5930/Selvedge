import Base
import ./spatial.bend as SpatialModel
import ./enclosure.bend as Enclosure
import ./space.bend as Space
import ./typography.bend as Typography
import ../core/interface.bend as UI
import ../core/SYSTEM.bend as Core
import ../core/user-input.bend as User
import ../core/user-experience.bend as Experience
import ../core/ui-world.bend as View
import ../core/form-fields.bend as Forms
import ../core/client-services.bend as Services
import ../core/code-block.bend as Code
import ../core/user-context.bend as Workspace
import ../bendlib/domain.bend as Domain
import ../BOARD.bend as Board

# The visible face never determines the command. The binding below is retained
# from the product observation, including unavailable actions and their reasons.
type Icon is Data:
  ChevronRight{}
  ChevronDown{}
  ArrowUp{}
  ArrowDown{}
  StopSquare{}
  PauseBars{}
  PlayTriangle{}
  CloseCross{}
  MoreDots{}
  Sidebar{}
  SidebarClose{}
  Folder{}
  Conversation{}
  Columns{}
  Agents{}
  Plus{}
  Pencil{}
  Branch{}
  Compact{}
  Settings{}
  FilterFunnel{}
  Inspector{}
  InspectorClose{}
  Eye{}
  Globe{}
  GlobeOff{}
  Hand{}
  Shield{}
  ShieldCode{}
  CopySheets{}
  WrapLines{}
  Check{}
  Warning{}
  Spinner{}
  Trash{}
  ArchiveBox{}
  Restore{}
  Pin{}
  Refresh{}
  Undo{}
  Download{}
  Preview{}
  Paperclip{}
  Grip{}

type Area is Data:
  PageArea{}
  NavigationArea{}
  ComposerArea{}
  ToolbarArea{}
  CodeArea{}
  ActivityArea{}
  ApprovalArea{}
  MenuArea{}
  DialogArea{}
  CollectionArea{}
  CardArea{}
  BoardViewArea{}
  BoardLaneArea{}

type Selection is Data:
  NoSelection{}
  ModelSelection{profile: String}
  DeliverySelection{delivery: User.Delivery}

type SourceFamily is Data:
  Unscoped{}
  SourceFamily{node: UI.Node}

type Context is Data:
  Context{area: Area, selection: Selection, code: Maybe<&2, Code.Scene>,
    appearance: Services.Appearance, access: Services.Access, settings_open: Bool,
    layers: +List<View.Layer>, execution: Maybe<&2, Workspace.Observation>, source_family: SourceFamily}

type Face is Data:
  IconFace{icon: Icon}
  TextFace{text: String}
  SingleLineFace{text: String}
  IconTextFace{icon: Icon, text: String}
  # Render the value and a trailing chevron, with room reserved for both.
  PickerFace{leading: Maybe<&2, Icon>, text: String}
  # Every option reserves the check column, including unselected options.
  ChoiceFace{text: String, description: Maybe<&2, String>, checked: Bool}
  DisclosureFace{text: String, expanded: Bool}
  PermissionFace{filesystem: Icon, network: Icon, approval: Icon}

def caption_wrapping(face: Face) -> Typography.Wrapping:
  match face:
    case SingleLineFace{text}: Typography.SingleLine{}
    case _: Typography.NormalAnywhere{}

def description_wrapping() -> Typography.Wrapping:
  Typography.NormalAnywhere{}

type Behavior is Data:
  Push{}
  Toggle{pressed: Bool}
  Radio{checked: Bool}
  ChoiceRadio{checked: Bool}
  Disclosure{expanded: Bool}
  Popup{menu: Bool, expanded: Bool}
  Destination{current: Bool}

type Geometry is Data:
  Geometry{demand: Space.Demand, icon_size: Nat,
    radius: Nat, leading_slot: Nat}

# Icon controls expose the square footprint consumed by layout and rendering.
def face_demand(face: Face, demand: Space.Demand) -> Space.Demand:
  match face:
    case IconFace{icon}:
      Space.Demand{Enclosure.Extent{width, height}, Enclosure.Extent{preferred_width, preferred_height}} = demand
      +minimum = Nat.max(width, height)
      +preferred = Nat.max(preferred_width, preferred_height)
      Space.Demand{Enclosure.Extent{minimum, minimum}, Enclosure.Extent{preferred, preferred}}
    case _: demand

type ContentLayout is Data:
  ContentLayout{alignment: SpatialModel.ContentAlignment, content_area: Enclosure.ContentArea, gap: Nat}

def content_layout(face: Face) -> ContentLayout:
  match face:
    case IconFace{icon}: ContentLayout{SpatialModel.CenterContents{}, Enclosure.area(Enclosure.IconControl{}), 0n}
    case SingleLineFace{text}: ContentLayout{SpatialModel.LeadingContents{}, Enclosure.ambient(0n, 0n), 0n}
    case ChoiceFace{text, description, checked}: ContentLayout{SpatialModel.LeadingContents{}, Enclosure.area(Enclosure.OptionControl{}), 8n}
    case _: ContentLayout{SpatialModel.LeadingContents{}, Enclosure.area(Enclosure.TextControl{}), 6n}

type IconPaint is Data:
  FilledIcon{}
  StrokedIcon{}

def icon_paint(icon: Icon) -> IconPaint:
  match icon:
    case ArrowUp{}: FilledIcon{}
    case Hand{}: FilledIcon{}
    case Shield{}: FilledIcon{}
    case ShieldCode{}: FilledIcon{}
    case _: StrokedIcon{}

type Placement is Data:
  InFlow{}
  ComposerEnd{}
  PanelHeaderEnd{}
  CodeToolbar{}
  BesideValue{}
  GroupHeadingEnd{}

type Help is Data:
  NoHelp{}
  # Hover and keyboard focus share the same help; Escape dismisses it.
  Tooltip{text: String, delay_ms: Nat, pointer: Bool, keyboard: Bool, takes_focus: Bool}

type Feedback is Data:
  Quiet{}
  Working{message: String}
  Succeeded{message: String}
  Failed{message: String}

type Widget is Data:
  PlainValue{}
  TextInput{}
  MessageInput{}
  TextArea{}
  SelectInput{}
  MultiSelectInput{}
  ToggleInput{}
  NumberInput{minimum: Nat}
  DirectoryList{}
  AttachmentList{}
  FileChooser{face: Face}
  DirectoryChooser{face: Face}
  SearchInput{}
  SecretInput{}

type LabelPlacement is Data:
  AboveInput{}
  AccessibleOnly{}
  BesideInput{}

type Representation is Data:
  NoControl{}
  Action{input: Core.Input, availability: View.Availability, name: String,
    face: Face, behavior: Behavior, geometry: Geometry, placement: Placement,
    help: Help, feedback: Feedback}
  Input{binding: UI.Meaning, name: String, widget: Widget,
    label: LabelPlacement, availability: View.Availability}
  # The grip opens the same destination list for keyboard users that supplies
  # pointer dragging. Each destination retains its own product command/status.
  Movable{destinations: +List<UI.Placement>, face: View.CardFace, name: String, handle: Icon,
    geometry: Geometry, help: Help}

def panel_header(representation: Representation) -> Bool:
  match representation:
    case Action{input, availability, name, face, behavior, geometry, PanelHeaderEnd{}, help, feedback}: True{}
    case _: False{}

type Purpose is Data:
  MessageSubmission{}
  NamedAction{}
  CreateItem{}
  EditItem{}
  ProjectTaskCreation{}
  NavigateTo{icon: Icon}
  MoreActions{expanded: Bool}
  OpenPanel{icon: Icon, menu: Bool, expanded: Bool}
  ChooseValue{expanded: Bool}
  WorkspacePicker{expanded: Bool}
  SelectedOption{checked: Bool}
  Dismiss{}
  StopExecution{}
  PauseExecution{}
  ResumeExecution{}
  InterruptExecution{}
  AbortOperation{}
  ApprovalDecision{allow: Bool}
  DeleteItem{}
  ArchiveItem{archived: Bool}
  PinItem{pinned: Bool}
  AutomaticScheduling{enabled: Bool}
  Regenerate{}
  CopyCode{state: Code.CopyState}
  WrapCode{enabled: Bool}
  ShowActivity{expanded: Bool}
  Latest{}
  ToggleNavigation{expanded: Bool}
  ResetDefaults{}
  RemoveValue{}
  RetryTransfer{}
  PreviewFile{}
  DownloadFile{}
  Connect{access: Services.Access}

def composer_execution(value: Maybe<&2, View.ComposerScene>) -> Maybe<&2, Workspace.Observation>:
  match value:
    case None{}: None{}
    case Some{View.ComposerScene{identity, revision, message, footer, observation, submit, feedback, pending}}: observation

def page_execution(page: View.Page) -> Maybe<&2, Workspace.Observation>:
  match page:
    case View.StartPage{composer}: composer_execution(composer)
    case View.TaskPage{View.TaskScene{task, title, status, context, timeline, previews, composer, details, actions}}: composer_execution(composer)
    case _: None{}

def initial(content: Core.Scene) -> Context:
  Core.Scene{View.Scene{navigation, main, layers, arrangement, attention},
    Core.Settings{open, access, entered, appearance, open_action, close_action, connect},
    transfers, preview, code, directory_picker} = content
  Context{PageArea{}, NoSelection{}, None{}, appearance, access, open, layers, page_execution(main), Unscoped{}}

def area_for(role: UI.Role, inherited: Area) -> Area:
  match role:
    case UI.Navigation{}: NavigationArea{}
    case UI.NavigationHeader{}: NavigationArea{}
    case UI.Card{}: CardArea{}
    case UI.Composer{}: ComposerArea{}
    case UI.ComposerActions{}: ComposerArea{}
    case UI.Heading{}: ToolbarArea{}
    case UI.CodeBlock{}: CodeArea{}
    case UI.Activity{}: ActivityArea{}
    case UI.ApprovalQueue{}: ApprovalArea{}
    case UI.Approval{}: ApprovalArea{}
    case UI.Menu{}: MenuArea{}
    case UI.Dialog{}: DialogArea{}
    case UI.Details{}: DialogArea{}
    case UI.Field{}: CollectionArea{}
    case UI.Toolbar{}:
      match inherited:
        case ComposerArea{}: ComposerArea{}
        case _: ToolbarArea{}
    case _: inherited

def selected_fields(fields: +List<View.InputGroup>) -> Selection:
  match fields:
    case Nil{}: NoSelection{}
    case Con{View.ModelInput{profile, reasoning, choices}, rest}: ModelSelection{profile}
    case Con{View.DeliveryInput{selected, send, steer}, rest}: DeliverySelection{selected}
    case Con{other, rest}: selected_fields(rest)

def layer_selection(content: View.LayerContent) -> Selection:
  match content:
    case View.ModelSelection{editor, query, fields}: selected_fields(fields)
    case View.DeliverySelection{editor, fields}: selected_fields(fields)
    case _: NoSelection{}

def select_layer(same: Bool, found: Selection, inherited: Selection) -> Selection:
  match same:
    case True{}: found
    case False{}: inherited

def selection_at(layers: +List<View.Layer>, +key: String, inherited: Selection) -> Selection:
  match layers:
    case Nil{}: inherited
    case Con{View.Layer{kind, content, initial_attention, restore, close}, rest}:
      select_layer(String.eq(UI.layer_key(initial_attention), key), layer_selection(content),
        selection_at(rest, key, inherited))

def code_at(meaning: UI.Meaning, inherited: Maybe<&2, Code.Scene>) -> Maybe<&2, Code.Scene>:
  match meaning:
    case UI.CodeFacts{scene}: Some{scene}
    case _: inherited

def area_for_node(role: UI.Role, meaning: UI.Meaning, inherited: Area) -> Area:
  match meaning:
    case UI.BoardGroup{UI.ViewChoices{}}: BoardViewArea{}
    case UI.BoardGroup{UI.SecondaryActions{}}: ToolbarArea{}
    case UI.BoardGroup{UI.PrimaryAction{}}: ToolbarArea{}
    case UI.BoardLane{stage, count}: BoardLaneArea{}
    case _: area_for(role, inherited)

def source_scope(role: UI.Role, inherited: SourceFamily) -> SourceFamily:
  match role:
    case UI.Dialog{}: Unscoped{}
    case UI.Menu{}: Unscoped{}
    case _: inherited

def activity_source(role: UI.Role, node: UI.Node, inherited: SourceFamily) -> SourceFamily:
  match role:
    case UI.Activity{}: SourceFamily{node}
    case _: source_scope(role, inherited)

def source_family_at(+node: UI.Node, inherited: SourceFamily) -> SourceFamily:
  UI.Node{key, semantic, label, +role, meaning, children} = node
  match meaning:
    case UI.ProjectGroup{project, selected, expanded}: SourceFamily{node}
    case UI.TaskRow{task, status, selected}: SourceFamily{node}
    case UI.ProjectChooser{selected}: SourceFamily{node}
    case UI.MovableCard{destinations, face}: SourceFamily{node}
    case UI.ActivityContent{expanded, audit}: activity_source(role, node, inherited)
    case _: source_scope(role, inherited)

def source_reference(context: Context) -> SourceFamily:
  Context{area, selection, code, appearance, access, open, layers, execution, source_family} = context
  source_family

def enter(+node: UI.Node, context: Context) -> Context:
  UI.Node{+key, semantic, label, +role, +meaning, children} = node
  Context{parent_area, selection, code, appearance, access, settings_open, +layers, execution, source_family} = context
  Context{area_for_node(role, meaning, parent_area), selection_at(layers, key, selection),
    code_at(meaning, code), appearance, access, settings_open, layers, execution, source_family_at(node, source_family)}

def panel_open(layers: +List<View.Layer>, +trigger: String) -> Bool:
  match layers:
    case Nil{}: False{}
    case Con{View.Layer{kind, content, attention, restore, close}, rest}:
      String.eq(restore, trigger) || panel_open(rest, trigger)

def same_delivery(left: User.Delivery, right: User.Delivery) -> Bool:
  match left right:
    case User.Send{} User.Send{}: True{}
    case User.Steer{} User.Steer{}: True{}
    case _ _: False{}

def same_appearance(left: Services.Appearance, right: Services.Appearance) -> Bool:
  match left right:
    case Services.SystemAppearance{} Services.SystemAppearance{}: True{}
    case Services.LightAppearance{} Services.LightAppearance{}: True{}
    case Services.DarkAppearance{} Services.DarkAppearance{}: True{}
    case _ _: False{}

def selected_edit(edit: User.Edit, selection: Selection) -> Purpose:
  match edit selection:
    case User.ChooseModel{profile, reasoning} ModelSelection{current}:
      SelectedOption{String.eq(profile, current)}
    case User.ChooseDelivery{delivery} DeliverySelection{current}:
      SelectedOption{same_delivery(delivery, current)}
    case User.ConfigureContext{change} _: ResetDefaults{}
    case _ _: NamedAction{}

def submit_purpose(editor: User.Editor) -> Purpose:
  match editor:
    case User.NewTaskEditor{}: MessageSubmission{}
    case User.MessageEditor{task}: MessageSubmission{}
    case _: NamedAction{}

def route_icon(route: User.Route) -> Icon:
  match route:
    case User.Start{}: Plus{}
    case User.Conversation{task}: Conversation{}
    case User.ProjectHome{project}: Folder{}
    case User.ProjectCollection{}: Folder{}
    case User.TaskBoard{}: Columns{}
    case User.AgentCollection{}: Agents{}

def panel_purpose(panel: User.Panel, expanded: Bool) -> Purpose:
  match panel:
    case User.CardDetails{card}: OpenPanel{Inspector{}, False{}, expanded}
    case User.ObjectActions{subject}: MoreActions{expanded}
    case User.BoardSettings{}: OpenPanel{Settings{}, False{}, expanded}
    case User.BoardFilters{}: OpenPanel{FilterFunnel{}, False{}, expanded}
    case User.ModelPicker{editor}: ChooseValue{expanded}
    case User.DeliveryPicker{task}: ChooseValue{expanded}
    case User.ProjectPicker{}: ChooseValue{expanded}
    case User.WorkspaceConfiguration{editor}: WorkspacePicker{expanded}
    case User.PermissionsConfiguration{editor}: ChooseValue{expanded}
    case User.TaskContext{task}: OpenPanel{Inspector{}, False{}, expanded}
    case User.TaskDetails{task}: OpenPanel{Inspector{}, False{}, expanded}
    case User.ArchivedCards{}: OpenPanel{ArchiveBox{}, False{}, expanded}
    case User.EditObject{editor}: OpenPanel{Pencil{}, False{}, expanded}
    case User.Confirm{command, title, destination}: OpenPanel{Warning{}, False{}, expanded}

def task_control(control: Domain.Control) -> Purpose:
  match control:
    case Domain.Freeze{}: PauseExecution{}
    case Domain.Unfreeze{}: ResumeExecution{}
    case Domain.Stop{}: StopExecution{}
    case Domain.Interrupt{}: InterruptExecution{}
    case Domain.Archive{}: ArchiveItem{True{}}

def board_command(command: Board.Command) -> Purpose:
  match command:
    case Board.Archive{id, revision, archived, now}: ArchiveItem{archived}
    case Board.Pin{id, revision, pinned, now}: PinItem{pinned}
    case Board.Settings{automatic, profile}: AutomaticScheduling{Bool.not(automatic)}
    case Board.Delete{id, revision}: DeleteItem{}
    case Board.DeleteAgent{id, revision}: DeleteItem{}
    case Board.Run{id, revision, now}: ResumeExecution{}
    case Board.Regenerate{id, revision, profile, now}: Regenerate{}
    case _: NamedAction{}

def action_purpose(+key: String, action: User.Action, selection: Selection, +layers: +List<View.Layer>) -> Purpose:
  match action:
    case User.Submit{editor}: submit_purpose(editor)
    case User.Navigate{route}: NavigateTo{route_icon(route)}
    case User.BeginTask{None{}}: CreateItem{}
    case User.BeginTask{Some{project}}: ProjectTaskCreation{}
    case User.EditProject{None{}}: CreateItem{}
    case User.EditProject{Some{project}}: EditItem{}
    case User.NewCard{stage}: CreateItem{}
    case User.EditCard{card}: EditItem{}
    case User.EditAgent{None{}}: CreateItem{}
    case User.EditAgent{Some{agent}}: EditItem{}
    case User.ForkTask{task}: OpenPanel{Branch{}, False{}, panel_open(layers, key)}
    case User.CompactTask{task}: OpenPanel{Compact{}, False{}, panel_open(layers, key)}
    case User.ControlTask{task, control}: task_control(control)
    case User.CancelOperation{task, operation}: AbortOperation{}
    case User.ReviewApproval{task, operation, allow, reason}: ApprovalDecision{allow}
    case User.DeleteProject{project}: DeleteItem{}
    case User.BoardCommand{command}: board_command(command)
    case User.OpenPanel{panel, trigger}: panel_purpose(panel, panel_open(layers, key))
    case User.TogglePanel{panel, trigger}: panel_purpose(panel, panel_open(layers, key))
    case User.ClosePanel{}: Dismiss{}
    case User.ConfirmAction{}: NamedAction{}
    case User.SelectProject{project}: NamedAction{}
    case User.ToggleProjectGroup{project}: NamedAction{}

def user_purpose(key: String, input: User.Input, selection: Selection, layers: +List<View.Layer>) -> Purpose:
  match input:
    case User.Activate{action}: action_purpose(key, action, selection, layers)
    case User.EditDraft{editor, edit}: selected_edit(edit, selection)
    case User.ReadTimeline{task, generation, intent}: Latest{}
    case User.SetDisclosure{task, group, occurrence, expanded}: ShowActivity{Bool.not(expanded)}
    case User.SetNavigation{expanded}: ToggleNavigation{Bool.not(expanded)}
    case _: NamedAction{}

def copy_state(code: Maybe<&2, Code.Scene>) -> Code.CopyState:
  match code:
    case Some{Code.Scene{identity, literal, wrap, copy, enabled, controls}}: copy
    case None{}: Code.CopyIdle{}

def wrap_state(code: Maybe<&2, Code.Scene>) -> Bool:
  match code:
    case Some{Code.Scene{identity, literal, wrap, copy, enabled, controls}}: wrap
    case None{}: False{}

def content_purpose(input: Code.Input, code: Maybe<&2, Code.Scene>) -> Purpose:
  match input:
    case Code.Copy{}: CopyCode{copy_state(code)}
    case Code.ToggleWrap{}: WrapCode{wrap_state(code)}
    case _: NamedAction{}

def service_purpose(input: Services.Input, appearance: Services.Appearance, access: Services.Access, settings_open: Bool) -> Purpose:
  match input:
    case Services.OpenDirectoryPicker{editor, path, trigger}: OpenPanel{Folder{}, False{}, False{}}
    case Services.VisitDirectory{path}: NavigateTo{Folder{}}
    case Services.OpenSettings{}: OpenPanel{Settings{}, False{}, settings_open}
    case Services.CloseSettings{}: Dismiss{}
    case Services.ClosePreview{}: Dismiss{}
    case Services.ChooseAppearance{chosen}: SelectedOption{same_appearance(chosen, appearance)}
    case Services.CancelUpload{ticket}: RemoveValue{}
    case Services.RetryUpload{ticket}: RetryTransfer{}
    case Services.OpenPreview{file, trigger}: PreviewFile{}
    case Services.Download{file}: DownloadFile{}
    case Services.Connect{}: Connect{access}
    case _: NamedAction{}

def purpose_fields(key: String, event: Core.Input, selection: Selection, code: Maybe<&2, Code.Scene>,
  appearance: Services.Appearance, access: Services.Access, settings_open: Bool, layers: +List<View.Layer>) -> Purpose:
  match event:
    case Core.ApplicationInput{Experience.UserInput{input}}: user_purpose(key, input, selection, layers)
    case Core.ApplicationInput{Experience.ContentInput{identity, input}}: content_purpose(input, code)
    case Core.ServiceInput{input}: service_purpose(input, appearance, access, settings_open)
    case Core.RemoveAttachment{editor, id}: RemoveValue{}
    case Core.EditField{editor, Forms.WorkspaceDirectories{}, Forms.WorkspaceChange{Workspace.RemoveRoot{path}}}: RemoveValue{}
    case _: NamedAction{}

def navigation_icon(expanded: Bool) -> Icon:
  match expanded:
    case False{}: Sidebar{}
    case True{}: SidebarClose{}

def inspector_icon(expanded: Bool) -> Icon:
  match expanded:
    case False{}: Inspector{}
    case True{}: InspectorClose{}

def purpose_icon(purpose: Purpose) -> Maybe<&2, Icon>:
  match purpose:
    case MessageSubmission{}: Some{ArrowUp{}}
    case CreateItem{}: Some{Plus{}}
    case EditItem{}: Some{Pencil{}}
    case ProjectTaskCreation{}: Some{Plus{}}
    case NavigateTo{icon}: Some{icon}
    case MoreActions{expanded}: Some{MoreDots{}}
    case OpenPanel{icon, menu, expanded}: Some{icon}
    case WorkspacePicker{expanded}: Some{Folder{}}
    case Dismiss{}: Some{CloseCross{}}
    case StopExecution{}: Some{StopSquare{}}
    case PauseExecution{}: Some{PauseBars{}}
    case ResumeExecution{}: Some{PlayTriangle{}}
    case InterruptExecution{}: Some{StopSquare{}}
    case AbortOperation{}: Some{CloseCross{}}
    case ApprovalDecision{True{}}: Some{Check{}}
    case ApprovalDecision{False{}}: Some{CloseCross{}}
    case DeleteItem{}: Some{Trash{}}
    case ArchiveItem{True{}}: Some{ArchiveBox{}}
    case ArchiveItem{False{}}: Some{Restore{}}
    case PinItem{pinned}: Some{Pin{}}
    case Regenerate{}: Some{Refresh{}}
    case CopyCode{Code.CopyIdle{}}: Some{CopySheets{}}
    case CopyCode{Code.CopyPending{}}: Some{Spinner{}}
    case CopyCode{Code.CopySucceeded{}}: Some{Check{}}
    case CopyCode{Code.CopyFailed{}}: Some{Warning{}}
    case WrapCode{enabled}: Some{WrapLines{}}
    case Latest{}: Some{ArrowDown{}}
    case ToggleNavigation{expanded}: Some{navigation_icon(expanded)}
    case ResetDefaults{}: Some{Undo{}}
    case RemoveValue{}: Some{CloseCross{}}
    case RetryTransfer{}: Some{Refresh{}}
    case PreviewFile{}: Some{Preview{}}
    case DownloadFile{}: Some{Download{}}
    case Connect{Services.Connecting{ticket}}: Some{Spinner{}}
    case _: None{}

def icon_only(purpose: Purpose, area: Area) -> Bool:
  match purpose area:
    case MessageSubmission{} ComposerArea{}: True{}
    case Dismiss{} _: True{}
    case MoreActions{expanded} _: True{}
    case Latest{} _: True{}
    case ToggleNavigation{expanded} _: True{}
    case ProjectTaskCreation{} NavigationArea{}: True{}
    case CreateItem{} BoardLaneArea{}: True{}
    case OpenPanel{Inspector{}, menu, expanded} ToolbarArea{}: True{}
    case OpenPanel{Settings{}, menu, expanded} _: True{}
    case OpenPanel{FilterFunnel{}, menu, expanded} _: True{}
    case OpenPanel{ArchiveBox{}, menu, expanded} ToolbarArea{}: True{}
    case CopyCode{state} CodeArea{}: True{}
    case WrapCode{enabled} CodeArea{}: True{}
    case RemoveValue{} CollectionArea{}: True{}
    case StopExecution{} ToolbarArea{}: True{}
    case PauseExecution{} ToolbarArea{}: True{}
    case ResumeExecution{} ToolbarArea{}: True{}
    case InterruptExecution{} ToolbarArea{}: True{}
    case _ _: False{}

def named_face(icon: Maybe<&2, Icon>, text: String, compact: Bool) -> Face:
  match icon compact:
    case Some{icon} True{}: IconFace{icon}
    case Some{icon} False{}: IconTextFace{icon, text}
    case None{} _: TextFace{text}

def contextual_face(+purpose: Purpose, label: String, +area: Area) -> Face:
  match purpose area:
    case EditItem{} CardArea{}: TextFace{label}
    case ChooseValue{expanded} _: PickerFace{None{}, label}
    case WorkspacePicker{expanded} _: PickerFace{Some{Folder{}}, label}
    case SelectedOption{checked} _: ChoiceFace{label, None{}, checked}
    case ShowActivity{expanded} _: DisclosureFace{label, expanded}
    case _ _: named_face(purpose_icon(purpose), label, icon_only(purpose, area))

def menu_face(purpose: Purpose, label: String) -> Face:
  match purpose:
    case Dismiss{}: IconFace{CloseCross{}}
    case SelectedOption{checked}: ChoiceFace{label, None{}, checked}
    case ChooseValue{expanded}: PickerFace{None{}, label}
    case ShowActivity{expanded}: DisclosureFace{label, expanded}
    case _: named_face(purpose_icon(purpose), label, False{})

def face_for(purpose: Purpose, label: String, area: Area) -> Face:
  match area:
    case MenuArea{}: menu_face(purpose, label)
    case _: contextual_face(purpose, label, area)

def input_face(input: Core.Input, purpose: Purpose, label: String, area: Area) -> Face:
  match input:
    case Core.ApplicationInput{Experience.UserInput{User.Activate{User.ClosePanel{}}}}: TextFace{label}
    case Core.ApplicationInput{Experience.UserInput{User.Activate{User.OpenPanel{User.ProjectPicker{}, trigger}}}}: PickerFace{Some{Folder{}}, label}
    case Core.ApplicationInput{Experience.UserInput{User.EditDraft{editor, User.EditWorkspace{Workspace.RemoveRoot{path}}}}}:
      IconFace{CloseCross{}}
    case _: face_for(purpose, label, area)

def behavior_for(purpose: Purpose, selected_role: Bool) -> Behavior:
  match purpose:
    case PinItem{pinned}: Toggle{Bool.not(pinned)}
    case AutomaticScheduling{enabled}: Toggle{enabled}
    case WrapCode{enabled}: Toggle{enabled}
    case SelectedOption{checked}: Radio{checked}
    case ShowActivity{expanded}: Disclosure{expanded}
    case ToggleNavigation{expanded}: Disclosure{expanded}
    case MoreActions{expanded}: Popup{True{}, expanded}
    case ChooseValue{expanded}: Popup{True{}, expanded}
    case WorkspacePicker{expanded}: Popup{False{}, expanded}
    case OpenPanel{icon, menu, expanded}: Popup{menu, expanded}
    case NavigateTo{icon}: Destination{selected_role}
    case _: Push{}

def contextual_behavior(purpose: Purpose, selected: Bool, area: Area) -> Behavior:
  match area:
    case BoardViewArea{}: Toggle{selected}
    case _: behavior_for(purpose, selected)

def selected_role(role: UI.Role) -> Bool:
  match role:
    case UI.SelectedButton{}: True{}
    case _: False{}

def name_for(purpose: Purpose, label: String) -> String:
  match purpose:
    case PinItem{pinned}: "Pin card"
    case ArchiveItem{True{}}: "Archive"
    case ArchiveItem{False{}}: "Restore"
    case _: label

def feedback_for(purpose: Purpose) -> Feedback:
  match purpose:
    case CopyCode{Code.CopyPending{}}: Working{"Copying code"}
    case CopyCode{Code.CopySucceeded{}}: Succeeded{"Code copied"}
    case CopyCode{Code.CopyFailed{}}: Failed{"Could not copy code"}
    case Connect{Services.Connecting{ticket}}: Working{"Connecting"}
    case Connect{Services.CredentialRejected{reason}}: Failed{reason}
    case Connect{Services.ConnectionLost{reason}}: Failed{reason}
    case _: Quiet{}

def tooltip(text: String) -> Help:
  Tooltip{text, 300n, True{}, True{}, False{}}

def unavailable_text(availability: View.Availability, name: String) -> String:
  match availability:
    case View.Unavailable{reason}: reason
    case _: name

def help_text(availability: View.Availability, feedback: Feedback, name: String) -> String:
  match feedback:
    case Working{message}: message
    case Succeeded{message}: message
    case Failed{message}: message
    case Quiet{}: unavailable_text(availability, name)

def availability_help(availability: View.Availability) -> Help:
  match availability:
    case View.Unavailable{reason}: tooltip(reason)
    case _: NoHelp{}

def labelled_help(feedback: Feedback, availability: View.Availability) -> Help:
  match feedback:
    case Quiet{}: availability_help(availability)
    case Working{message}: tooltip(message)
    case Succeeded{message}: tooltip(message)
    case Failed{message}: tooltip(message)

def help_for(face: Face, availability: View.Availability, feedback: Feedback, name: String) -> Help:
  match face:
    case IconFace{icon}: tooltip(help_text(availability, feedback, name))
    case PermissionFace{filesystem, network, approval}: tooltip(help_text(availability, feedback, name))
    case _: labelled_help(feedback, availability)

def geometry_nonchoice(purpose: Purpose, face: Face, area: Area) -> Geometry:
  match purpose face area:
    case MessageSubmission{} IconFace{icon} ComposerArea{}: Geometry{Space.fixed_demand(32n, 32n), 16n, 16n, 0n}
    case ProjectTaskCreation{} IconFace{icon} NavigationArea{}: Geometry{Space.fixed_demand(24n, 24n), 16n, 6n, 0n}
    case _ IconFace{icon} _: Geometry{Space.fixed_demand(32n, 32n), 16n, 8n, 0n}
    case _ _ NavigationArea{}: Geometry{Space.fixed_demand(0n, 29n), 16n, 6n, 20n}
    case _ _ MenuArea{}: Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 20n}
    case _ PickerFace{icon, text} ComposerArea{}: Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 0n}
    case _ PermissionFace{filesystem, network, approval} _: Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 0n}
    case _ _ _: Geometry{Space.fixed_demand(0n, 32n), 16n, 8n, 0n}

def geometry_for(purpose: Purpose, face: Face, area: Area) -> Geometry:
  match face:
    case ChoiceFace{text, description, checked}: Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 20n}
    case other: geometry_nonchoice(purpose, other, area)


def placement_for(purpose: Purpose, area: Area) -> Placement:
  match purpose area:
    case MessageSubmission{} ComposerArea{}: ComposerEnd{}
    case Dismiss{} DialogArea{}: PanelHeaderEnd{}
    case Dismiss{} MenuArea{}: PanelHeaderEnd{}
    case CopyCode{state} CodeArea{}: CodeToolbar{}
    case WrapCode{enabled} CodeArea{}: CodeToolbar{}
    case RemoveValue{} CollectionArea{}: BesideValue{}
    case ProjectTaskCreation{} NavigationArea{}: GroupHeadingEnd{}
    case _ _: InFlow{}

def filesystem_icon(mode: Domain.SandboxMode) -> Icon:
  match mode:
    case Domain.WorkspaceWrite{}: Pencil{}
    case Domain.ReadOnly{}: Eye{}

def network_icon(enabled: Bool) -> Icon:
  match enabled:
    case True{}: Globe{}
    case False{}: GlobeOff{}

def approval_icon(choice: Workspace.ApprovalChoice) -> Icon:
  match choice:
    case Workspace.Ask{}: Hand{}
    case Workspace.Unrestricted{}: Shield{}
    case Workspace.AutomaticReview{profile}: ShieldCode{}

def permission_values_face(sandbox: Domain.Sandbox, approval: Workspace.ApprovalChoice) -> Face:
  Domain.Sandbox{mode, network} = sandbox
  PermissionFace{filesystem_icon(mode), network_icon(network), approval_icon(approval)}

def permission_face(observation: Maybe<&2, Workspace.Observation>) -> Face:
  match observation:
    case Some{Workspace.DraftExecution{Workspace.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}}:
      permission_values_face(View.execution_sandbox(sandbox), Workspace.observed_approval(approval))
    case Some{Workspace.CommittedExecution{Workspace.EffectiveContext{task, Domain.TaskContext{workspace, sandbox, approval, project}, guidance, access}}}:
      permission_values_face(sandbox, Workspace.approval_choice(approval))
    case _: IconFace{Warning{}}

def delivery_name(delivery: User.Delivery) -> String:
  match delivery:
    case User.Send{}: "Send a new message"
    case User.Steer{}: "Steer the running task"

def composer_face(subject: View.ComposerSubject, label: String, current: Face,
  execution: Maybe<&2, Workspace.Observation>) -> Face:
  match subject:
    case View.ModelSubject{}: current
    case View.WorkspaceSubject{}: PickerFace{Some{Folder{}}, label}
    case View.PermissionsSubject{}: permission_face(execution)
    case View.DeliverySubject{User.Send{}}: IconFace{ArrowUp{}}
    case View.DeliverySubject{User.Steer{}}: IconFace{Branch{}}

def composer_name(subject: View.ComposerSubject, label: String) -> String:
  match subject:
    case View.PermissionsSubject{}: "Permissions: " ++ label
    case View.DeliverySubject{delivery}: delivery_name(delivery)
    case _: label

def composer_action_fields(+subject: View.ComposerSubject, +label: String,
  execution: Maybe<&2, Workspace.Observation>, area: Area, value: Representation) -> Representation:
  match value:
    case Action{input, +availability, old_name, current, behavior, geometry, placement, help, +feedback}:
      +name = composer_name(subject, label)
      +face = composer_face(subject, label, current, execution)
      Action{input, availability, name, face, behavior, geometry_for(ChooseValue{False{}}, face, area), placement,
        help_for(face, availability, feedback, name), feedback}
    case _: value

def action_for_purpose(+intent: Purpose, +area: Area, +input: Core.Input,
  +availability: View.Availability, label: String, role: UI.Role) -> Representation:
  +control_name = name_for(intent, label)
  +control_face = input_face(input, intent, control_name, area)
  +response = feedback_for(intent)
  Action{input, availability, control_name, control_face,
    contextual_behavior(intent, selected_role(role), area), geometry_for(intent, control_face, area),
    placement_for(intent, area), help_for(control_face, availability, response, control_name), response}

def make_action(+key: String, +input: Core.Input, +availability: View.Availability, label: String,
  role: UI.Role, +context: Context) -> Representation:
  Context{area, selection, code, appearance, access, settings_open, layers, execution, source_family} = context
  intent = purpose_fields(key, input, selection, code, appearance, access, settings_open, layers)
  action_for_purpose(intent, area, input, availability, label, role)

def panel_toggle_face(input: Core.Input, expanded: Bool, fallback: Face) -> Face:
  match input:
    case Core.ApplicationInput{Experience.UserInput{User.Activate{User.TogglePanel{User.TaskDetails{task}, trigger}}}}:
      IconFace{inspector_icon(expanded)}
    case _: fallback

def panel_toggle_fields(+expanded: Bool, value: Representation) -> Representation:
  match value:
    case Action{+input, availability, name, current, behavior, geometry, placement, help, feedback}:
      Action{input, availability, name, panel_toggle_face(input, expanded, current), Disclosure{expanded},
        geometry, placement, help, feedback}
    case _: value

def make_panel_toggle(key: String, expanded: Bool, input: Core.Input, availability: View.Availability,
  label: String, role: UI.Role, context: Context) -> Representation:
  panel_toggle_fields(expanded, make_action(key, input, availability, label, role, context))

def make_composer_action(key: String, subject: View.ComposerSubject, input: Core.Input,
  availability: View.Availability, +label: String, role: UI.Role, +context: Context) -> Representation:
  Context{area, selection, code, appearance, access, settings_open, layers, +execution, source_family} = context
  composer_action_fields(subject, label, execution, area, make_action(key, input, availability, label, role, context))

def choice_description_for(empty: Bool, value: String) -> Maybe<&2, String>:
  match empty:
    case True{}: None{}
    case False{}: Some{value}

def choice_description(+value: String) -> Maybe<&2, String>:
  choice_description_for(String.eq(value, ""), value)

def choice_action(+selected: Bool, description: Maybe<&2, String>, +purpose: Purpose, +area: Area, value: Representation) -> Representation:
  match value:
    case Action{input, availability, +name, face, behavior, geometry, placement, help, feedback}:
      +actual_face: Face = ChoiceFace{name, description, selected}
      Action{input, availability, name, actual_face, ChoiceRadio{selected}, geometry_for(purpose, actual_face, area), placement, help, feedback}
    case other: other

def make_choice(+key: String, selected: Bool, description: String, +input: Core.Input, availability: View.Availability,
  label: String, role: UI.Role, +context: Context) -> Representation:
  Context{+area, selection, code, appearance, access, settings_open, layers, execution, source_family} = context
  +intent = purpose_fields(key, input, selection, code, appearance, access, settings_open, layers)
  choice_action(selected, choice_description(description), intent, area, action_for_purpose(intent, area, input, availability, label, role))

type ChoiceContentLayout is Data:
  ChoiceContentLayout{text_gap: Nat, mark_extent: Nat, mark_icon_extent: Nat}

def choice_content_layout(geometry: Geometry) -> ChoiceContentLayout:
  Geometry{demand, icon, radius, leading} = geometry
  ChoiceContentLayout{2n, leading, icon}

def choice_layout(value: Representation) -> ChoiceContentLayout:
  match value:
    case Action{input, availability, name, face, behavior, geometry, placement, help, feedback}: choice_content_layout(geometry)
    case _: choice_content_layout(Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 20n})

def entry_widget(entry: Forms.Entry) -> Widget:
  match entry:
    case Forms.DisplayOnly{}: PlainValue{}
    case Forms.SingleLine{}: TextInput{}
    case Forms.Multiline{}: TextArea{}
    case Forms.Choice{}: SelectInput{}
    case Forms.MultipleChoices{}: MultiSelectInput{}
    case Forms.PositiveInteger{}: NumberInput{1n}
    case Forms.DirectoryCollection{}: DirectoryList{}
    case Forms.FileCollection{}: AttachmentList{}

def value_widget(value: Forms.Observed, entry: Forms.Entry) -> Widget:
  match value:
    case Forms.ToggleValue{enabled}: ToggleInput{}
    case _: entry_widget(entry)

def field_widget(field: Forms.Field, entry: Forms.Entry, value: Forms.Observed) -> Widget:
  match field:
    case Forms.AssistedCapture{}: ToggleInput{}
    case _: value_widget(value, entry)

def widget_for(+entry: Forms.Entry, field: Forms.Field, value: Forms.Observed) -> Widget:
  match entry field:
    case Forms.DisplayOnly{} _: PlainValue{}
    case Forms.Multiline{} Forms.MessageText{}: MessageInput{}
    case _ Forms.NetworkAccess{}: ToggleInput{}
    case _ _: field_widget(field, entry, value)

def label_placement(widget: Widget) -> LabelPlacement:
  match widget:
    case MessageInput{}: AccessibleOnly{}
    case ToggleInput{}: BesideInput{}
    case SearchInput{}: AccessibleOnly{}
    case FileChooser{face}: AccessibleOnly{}
    case DirectoryChooser{face}: AccessibleOnly{}
    case _: AboveInput{}

def make_input(meaning: UI.Meaning, name: String, +widget: Widget, availability: View.Availability) -> Representation:
  Input{meaning, name, widget, label_placement(widget), availability}

def field_availability(entry: Forms.Entry) -> View.Availability:
  match entry:
    case Forms.DisplayOnly{}: View.Unavailable{"Read only"}
    case _: View.Available{}

type ProjectControl is Data:
  ProjectDisclosure{}
  ProjectName{}
  ProjectCreate{}
  ProjectMore{}
  ProjectOther{}

def project_control_input(input: Core.Input) -> ProjectControl:
  match input:
    case Core.ApplicationInput{Experience.UserInput{User.Activate{User.ToggleProjectGroup{project}}}}: ProjectDisclosure{}
    case Core.ApplicationInput{Experience.UserInput{User.Activate{User.SelectProject{project}}}}: ProjectName{}
    case Core.ApplicationInput{Experience.UserInput{User.Activate{User.BeginTask{project}}}}: ProjectCreate{}
    case Core.ApplicationInput{Experience.UserInput{User.Activate{User.OpenPanel{User.ObjectActions{User.ProjectSubject{project}}, trigger}}}}: ProjectMore{}
    case _: ProjectOther{}

def project_control_matches(input: Core.Input, project: Nat) -> Bool:
  match input:
    case Core.ApplicationInput{Experience.UserInput{User.Activate{User.ToggleProjectGroup{id}}}}: Nat.is_eq(id, project)
    case Core.ApplicationInput{Experience.UserInput{User.Activate{User.SelectProject{Some{id}}}}}: Nat.is_eq(id, project)
    case Core.ApplicationInput{Experience.UserInput{User.Activate{User.BeginTask{Some{id}}}}}: Nat.is_eq(id, project)
    case Core.ApplicationInput{Experience.UserInput{User.Activate{User.OpenPanel{User.ObjectActions{User.ProjectSubject{id}}, trigger}}}}: Nat.is_eq(id, project)
    case _: False{}

def disclosure_glyph(expanded: Bool) -> Icon:
  match expanded:
    case True{}: ChevronDown{}
    case False{}: ChevronRight{}

def project_face(kind: ProjectControl, name: String, expanded: Bool, fallback: Face) -> Face:
  match kind:
    case ProjectDisclosure{}: IconFace{disclosure_glyph(expanded)}
    case ProjectName{}: SingleLineFace{name}
    case ProjectCreate{}: IconFace{Plus{}}
    case ProjectMore{}: IconFace{MoreDots{}}
    case _: fallback

def project_geometry(kind: ProjectControl, geometry: Geometry) -> Geometry:
  match kind geometry:
    case ProjectDisclosure{} Geometry{demand, icon, radius, leading}: Geometry{Space.fixed_demand(24n, 24n), icon, radius, leading}
    case ProjectCreate{} Geometry{demand, icon, radius, leading}: Geometry{Space.fixed_demand(28n, 28n), icon, radius, leading}
    case ProjectMore{} Geometry{demand, icon, radius, leading}: Geometry{Space.fixed_demand(28n, 28n), icon, radius, leading}
    case _ _: geometry

def project_behavior(kind: ProjectControl, expanded: Bool, fallback: Behavior) -> Behavior:
  match kind:
    case ProjectDisclosure{}: Disclosure{expanded}
    case _: fallback

type ActionPresentation is Data:
  ActionPresentation{face: Face, behavior: Behavior, geometry: Geometry}

def project_presentation(matches: Bool, +kind: ProjectControl, +expanded: Bool, name: String, face: Face, behavior: Behavior, geometry: Geometry) -> ActionPresentation:
  match matches:
    case True{}: ActionPresentation{project_face(kind, name, expanded, face), project_behavior(kind, expanded, behavior), project_geometry(kind, geometry)}
    case False{}: ActionPresentation{face, behavior, geometry}

def task_presentation(input: Core.Input, task: Nat, name: String, face: Face, behavior: Behavior, geometry: Geometry) -> ActionPresentation:
  match input:
    case Core.ApplicationInput{Experience.UserInput{User.Activate{User.Navigate{User.Conversation{id}}}}}:
      project_presentation(Nat.is_eq(id, task), ProjectName{}, False{}, name, face, behavior, geometry)
    case _: ActionPresentation{face, behavior, geometry}

def chooser_presentation(input: Core.Input, +name: String, face: Face, behavior: Behavior, geometry: Geometry) -> ActionPresentation:
  match input:
    case Core.ApplicationInput{Experience.UserInput{User.Activate{User.OpenPanel{User.ProjectPicker{}, trigger}}}}: ActionPresentation{PickerFace{Some{Folder{}}, name}, behavior, geometry}
    case _: ActionPresentation{face, behavior, geometry}

def contextual_source_presentation(area: Area, source_family: SourceFamily, +input: Core.Input, name: String, face: Face, behavior: Behavior, geometry: Geometry) -> ActionPresentation:
  match area source_family:
    case NavigationArea{} SourceFamily{UI.Node{owner, semantic, label, role, UI.ProjectGroup{project, selected, expanded}, children}}:
      project_presentation(project_control_matches(input, project), project_control_input(input), expanded, name, face, behavior, geometry)
    case NavigationArea{} SourceFamily{UI.Node{owner, semantic, label, role, UI.TaskRow{task, status, selected}, children}}: task_presentation(input, task, name, face, behavior, geometry)
    case _ SourceFamily{UI.Node{owner, semantic, label, role, UI.ProjectChooser{selected}, children}}: chooser_presentation(input, name, face, behavior, geometry)
    case _ _: ActionPresentation{face, behavior, geometry}

def uses_source_presentation(input: Core.Input) -> Bool:
  match input:
    case Core.ApplicationInput{Experience.UserInput{User.Activate{User.ToggleProjectGroup{project}}}}: True{}
    case Core.ApplicationInput{Experience.UserInput{User.Activate{User.SelectProject{project}}}}: True{}
    case Core.ApplicationInput{Experience.UserInput{User.Activate{User.BeginTask{project}}}}: True{}
    case Core.ApplicationInput{Experience.UserInput{User.Activate{User.OpenPanel{User.ObjectActions{User.ProjectSubject{project}}, trigger}}}}: True{}
    case Core.ApplicationInput{Experience.UserInput{User.Activate{User.Navigate{User.Conversation{task}}}}}: True{}
    case Core.ApplicationInput{Experience.UserInput{User.Activate{User.OpenPanel{User.ProjectPicker{}, trigger}}}}: True{}
    case _: False{}

def dispatch_source_presentation(enabled: Bool, area: Area, source_family: SourceFamily, input: Core.Input, name: String, face: Face, behavior: Behavior, geometry: Geometry) -> ActionPresentation:
  match enabled:
    case True{}: contextual_source_presentation(area, source_family, input, name, face, behavior, geometry)
    case False{}: ActionPresentation{face, behavior, geometry}

type SourceContent is Data:
  OrdinaryContent{}
  TitleContent{caption: String}
  SummaryContent{caption: String}

def title_target(matches: Bool, caption: String) -> SourceContent:
  match matches:
    case True{}: TitleContent{caption}
    case False{}: OrdinaryContent{}

def summary_target(matches: Bool, caption: String) -> SourceContent:
  match matches:
    case True{}: SummaryContent{caption}
    case False{}: OrdinaryContent{}

def same_disclosure_state(first: Bool, second: Bool) -> Bool:
  match first second:
    case True{} True{}: True{}
    case False{} False{}: True{}
    case _ _: False{}

# Correlate the action with the actual declaration under this activity source.
def summary_declaration(children: +List<UI.Node>, task: Nat, group: Nat, occurrence: Nat, expanded: Bool, caption: String) -> SourceContent:
  match children:
    case Con{UI.Node{key, semantic, label, role,
      UI.Activate{Core.ApplicationInput{Experience.UserInput{User.SetDisclosure{actual_task, actual_group, actual_occurrence, actual_expanded}}}, availability}, nested}, rest}:
      summary_target(Nat.is_eq(task, actual_task) && (Nat.is_eq(group, actual_group) &&
        (Nat.is_eq(occurrence, actual_occurrence) && same_disclosure_state(expanded, actual_expanded))), caption)
    case _: OrdinaryContent{}

def source_content_input(input: Core.Input, area: Area, family: SourceFamily, face: Face) -> SourceContent:
  match input area family face:
    case Core.ApplicationInput{Experience.UserInput{User.Activate{User.OpenPanel{User.CardDetails{target}, trigger}}}}
      CardArea{} SourceFamily{UI.Node{key, semantic, label, role,
      UI.MovableCard{destinations, View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated}}, children}} _:
        title_target(Nat.is_eq(id, target), title)
    case Core.ApplicationInput{Experience.UserInput{User.SetDisclosure{task, group, occurrence, requested}}}
      ActivityArea{} SourceFamily{UI.Node{key, semantic, label, UI.Activity{}, UI.ActivityContent{expanded, audit}, children}} DisclosureFace{text, shown}:
        summary_declaration(children, task, group, occurrence, requested, label)
    case _ _ _ _: OrdinaryContent{}

def source_content(area: Area, family: SourceFamily, input: Core.Input, face: Face) -> SourceContent:
  source_content_input(input, area, family, face)

def summary_presentation(face: Face, behavior: Behavior, geometry: Geometry, caption: String) -> ActionPresentation:
  match face:
    case DisclosureFace{text, expanded}: ActionPresentation{DisclosureFace{text ++ " " ++ caption, expanded}, behavior, geometry}
    case _: ActionPresentation{face, behavior, geometry}

def title_presentation(value: ActionPresentation, caption: String) -> ActionPresentation:
  ActionPresentation{face, behavior, geometry} = value
  ActionPresentation{TextFace{caption}, behavior, geometry}

def summary_action_presentation(value: ActionPresentation, caption: String) -> ActionPresentation:
  ActionPresentation{face, behavior, geometry} = value
  summary_presentation(face, behavior, geometry, caption)

def content_presentation(content: SourceContent, value: ActionPresentation) -> ActionPresentation:
  match content:
    case OrdinaryContent{}: value
    case TitleContent{caption}: title_presentation(value, caption)
    case SummaryContent{caption}: summary_action_presentation(value, caption)

def source_presentation(+area: Area, +source_family: SourceFamily, +input: Core.Input, name: String, +face: Face, behavior: Behavior, geometry: Geometry) -> ActionPresentation:
  content_presentation(source_content(area, source_family, input, face),
    dispatch_source_presentation(uses_source_presentation(input), area, source_family, input, name, face, behavior, geometry))

def source_representation_content(value: Representation, area: Area, family: SourceFamily) -> SourceContent:
  match value:
    case Action{input, availability, name, face, behavior, geometry, placement, help, feedback}: source_content(area, family, input, face)
    case _: OrdinaryContent{}

def representation_content(context: Context, value: Representation) -> SourceContent:
  Context{area, selection, code, appearance, access, open, layers, execution, family} = context
  source_representation_content(value, area, family)

def presented_action(input: Core.Input, availability: View.Availability, name: String, projection: ActionPresentation, placement: Placement, help: Help, feedback: Feedback) -> Representation:
  ActionPresentation{face, behavior, geometry} = projection
  Action{input, availability, name, face, behavior, geometry, placement, help, feedback}

def source_action(area: Area, source_family: SourceFamily, value: Representation) -> Representation:
  match value:
    case Action{+input, availability, +name, face, behavior, geometry, placement, help, feedback}:
      presented_action(input, availability, name, source_presentation(area, source_family, input, name, face, behavior, geometry), placement, help, feedback)
    case _: value

def represent_action(key: String, +input: Core.Input, availability: View.Availability, label: String, role: UI.Role, +context: Context) -> Representation:
  Context{+area, selection, code, appearance, access, open, layers, execution, +source_family} = context
  source_action(area, source_family, make_action(key, input, availability, label, role, context))

def represent(key: String, +meaning: UI.Meaning, +label: String, role: UI.Role, +context: Context) -> Representation:
  match meaning:
    case UI.ComposerAction{subject, input, availability}: make_composer_action(key, subject, input, availability, label, role, context)
    case UI.Activate{input, availability}: represent_action(key, input, availability, label, role, context)
    case UI.PanelToggle{expanded, input, availability}: make_panel_toggle(key, expanded, input, availability, label, role, context)
    case UI.Choice{selected, description, input, availability}: make_choice(key, selected, description, input, availability, label, role, context)
    case UI.Edit{editor, field, Forms.DirectoryCollection{}, value, choices}: NoControl{}
    case UI.Edit{editor, field, Forms.FileCollection{}, value, choices}: NoControl{}
    case UI.Edit{editor, field, +entry, value, choices}: make_input(meaning, label, widget_for(entry, field, value), field_availability(entry))
    case UI.SearchChoices{query}: make_input(meaning, label, SearchInput{}, View.Available{})
    case UI.DirectoryBrowserLocation{value}: make_input(meaning, label, DirectoryChooser{TextFace{label}}, View.Available{})
    case UI.EnterCredential{entered}: make_input(meaning, label, SecretInput{}, View.Available{})
    case UI.ReceiveFile{editor, enabled}: make_input(meaning, label, FileChooser{IconTextFace{Paperclip{}, label}}, UI.availability(enabled))
    case UI.EnterDirectory{editor, text}: make_input(meaning, label, DirectoryChooser{IconTextFace{Folder{}, label}}, View.Available{})
    case UI.BoardSearch{filter}: make_input(meaning, label, SearchInput{}, View.Available{})
    case UI.BoardProfile{automatic, selected, choices, enabled}: make_input(meaning, label, SelectInput{}, UI.availability(enabled))
    case UI.CardArchive{count}: NoControl{}
    case UI.MovableCard{destinations, face}:
      Movable{destinations, face, "Move " ++ label, Grip{}, Geometry{Space.fixed_demand(32n, 32n), 16n, 8n, 0n},
        Tooltip{"Move card", 300n, True{}, True{}, False{}}}
    case _: NoControl{}

def layout_content_area(value: ContentLayout) -> Enclosure.ContentArea:
  ContentLayout{alignment, area, gap} = value
  area

def geometry_minimum_width(value: Geometry) -> Nat:
  Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon, radius, leading} = value
  width

def geometry_minimum_height(value: Geometry) -> Nat:
  Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon, radius, leading} = value
  height

def geometry_preferred_width(value: Geometry) -> Nat:
  Geometry{Space.Demand{minimum, Enclosure.Extent{width, height}}, icon, radius, leading} = value
  width

def geometry_preferred_height(value: Geometry) -> Nat:
  Geometry{Space.Demand{minimum, Enclosure.Extent{width, height}}, icon, radius, leading} = value
  height
