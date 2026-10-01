import Base
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
  ArrowUp{}
  ArrowDown{}
  StopSquare{}
  PauseBars{}
  PlayTriangle{}
  CloseCross{}
  MoreDots{}
  Sidebar{}
  Folder{}
  Conversation{}
  Columns{}
  Agents{}
  Plus{}
  Pencil{}
  Branch{}
  Compact{}
  Settings{}
  Inspector{}
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

type Selection is Data:
  NoSelection{}
  ModelSelection{profile: String}
  DeliverySelection{delivery: User.Delivery}

type Context is Data:
  Context{area: Area, selection: Selection, code: Maybe<&2, Code.Scene>,
    appearance: Services.Appearance, access: Services.Access, settings_open: Bool,
    layers: +List<View.Layer>}

type Face is Data:
  IconFace{icon: Icon}
  TextFace{text: String}
  IconTextFace{icon: Icon, text: String}
  # Render the value and a trailing chevron, with room reserved for both.
  PickerFace{leading: Maybe<&2, Icon>, text: String}
  # Every option reserves the check column, including unselected options.
  ChoiceFace{text: String, checked: Bool}
  DisclosureFace{text: String, expanded: Bool}

type Behavior is Data:
  Push{}
  Toggle{pressed: Bool}
  Radio{checked: Bool}
  Disclosure{expanded: Bool}
  Popup{menu: Bool, expanded: Bool}
  Destination{current: Bool}

type Geometry is Data:
  Geometry{minimum_width: Nat, minimum_height: Nat, icon_size: Nat,
    radius: Nat, leading_slot: Nat}

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
  Movable{destinations: +List<UI.Placement>, name: String, handle: Icon,
    geometry: Geometry, help: Help}

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

def initial(content: Core.Scene) -> Context:
  Core.Scene{View.Scene{navigation, main, layers, arrangement, attention},
    Core.Settings{open, access, entered, appearance, open_action, close_action, connect},
    transfers, preview, code} = content
  Context{PageArea{}, NoSelection{}, None{}, appearance, access, open, layers}

def area_for(role: UI.Role, inherited: Area) -> Area:
  match role:
    case UI.Navigation{}: NavigationArea{}
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

def enter(key: String, role: UI.Role, meaning: UI.Meaning, context: Context) -> Context:
  Context{parent_area, selection, code, appearance, access, settings_open, +layers} = context
  Context{area_for(role, parent_area), selection_at(layers, key, selection),
    code_at(meaning, code), appearance, access, settings_open, layers}

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
    case User.ObjectActions{subject}: MoreActions{expanded}
    case User.ModelPicker{editor}: ChooseValue{expanded}
    case User.DeliveryPicker{task}: ChooseValue{expanded}
    case User.TaskConfiguration{}: WorkspacePicker{expanded}
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
    case User.EditCard{None{}}: CreateItem{}
    case User.EditCard{Some{card}}: EditItem{}
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
    case User.ClosePanel{}: Dismiss{}
    case User.ConfirmAction{}: NamedAction{}

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

def purpose_for(key: String, event: Core.Input, context: Context) -> Purpose:
  Context{area, selection, code, appearance, access, settings_open, layers} = context
  purpose_fields(key, event, selection, code, appearance, access, settings_open, layers)

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
    case ToggleNavigation{expanded}: Some{Sidebar{}}
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
    case OpenPanel{Inspector{}, menu, expanded} ToolbarArea{}: True{}
    case OpenPanel{Settings{}, menu, expanded} _: True{}
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
  match purpose:
    case ChooseValue{expanded}: PickerFace{None{}, label}
    case WorkspacePicker{expanded}: PickerFace{Some{Folder{}}, "Workspace"}
    case SelectedOption{checked}: ChoiceFace{label, checked}
    case ShowActivity{expanded}: DisclosureFace{label, expanded}
    case _: named_face(purpose_icon(purpose), label, icon_only(purpose, area))

def menu_face(purpose: Purpose, label: String) -> Face:
  match purpose:
    case Dismiss{}: IconFace{CloseCross{}}
    case SelectedOption{checked}: ChoiceFace{label, checked}
    case ChooseValue{expanded}: PickerFace{None{}, label}
    case ShowActivity{expanded}: DisclosureFace{label, expanded}
    case _: named_face(purpose_icon(purpose), label, False{})

def face_for(purpose: Purpose, label: String, area: Area) -> Face:
  match area:
    case MenuArea{}: menu_face(purpose, label)
    case _: contextual_face(purpose, label, area)

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
    case _: labelled_help(feedback, availability)

def geometry_for(purpose: Purpose, face: Face, area: Area) -> Geometry:
  match purpose face area:
    case MessageSubmission{} IconFace{icon} ComposerArea{}: Geometry{32n, 32n, 16n, 16n, 0n}
    case ProjectTaskCreation{} IconFace{icon} NavigationArea{}: Geometry{24n, 24n, 16n, 6n, 0n}
    case _ IconFace{icon} _: Geometry{32n, 32n, 16n, 8n, 0n}
    case _ _ NavigationArea{}: Geometry{0n, 29n, 16n, 6n, 20n}
    case _ _ MenuArea{}: Geometry{0n, 28n, 16n, 6n, 20n}
    case _ ChoiceFace{text, checked} _: Geometry{0n, 28n, 16n, 6n, 20n}
    case _ PickerFace{icon, text} ComposerArea{}: Geometry{0n, 28n, 16n, 6n, 0n}
    case _ _ _: Geometry{0n, 32n, 16n, 8n, 0n}

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

def workspace_face(key: String, expanded: Bool, label: String, area: Area) -> Face:
  match key:
    case "/main/creation/introduction/creation/context/composer/context": PickerFace{Some{Folder{}}, "Context"}
    case _: face_for(WorkspacePicker{expanded}, label, area)

def keyed_face(key: String, purpose: Purpose, label: String, area: Area) -> Face:
  match purpose:
    case WorkspacePicker{expanded}: workspace_face(key, expanded, label, area)
    case other: face_for(other, label, area)

def make_action(+key: String, +input: Core.Input, +availability: View.Availability, label: String,
  role: UI.Role, +context: Context) -> Representation:
  Context{+area, selection, code, appearance, access, settings_open, layers} = context
  +intent = purpose_fields(key, input, selection, code, appearance, access, settings_open, layers)
  +control_name = name_for(intent, label)
  +control_face = keyed_face(key, intent, control_name, area)
  +response = feedback_for(intent)
  Action{input, availability, control_name, control_face,
    behavior_for(intent, selected_role(role)), geometry_for(intent, control_face, area),
    placement_for(intent, area), help_for(control_face, availability, response, control_name), response}

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

def widget_for(+entry: Forms.Entry, field: Forms.Field, value: Forms.Observed) -> Widget:
  match entry field:
    case Forms.DisplayOnly{} _: PlainValue{}
    case Forms.Multiline{} Forms.MessageText{}: MessageInput{}
    case _ Forms.NetworkAccess{}: ToggleInput{}
    case _ _: value_widget(value, entry)

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

def represent(key: String, +meaning: UI.Meaning, +label: String, role: UI.Role, +context: Context) -> Representation:
  match meaning:
    case UI.Activate{input, availability}: make_action(key, input, availability, label, role, context)
    case UI.Edit{editor, field, Forms.DirectoryCollection{}, value}: NoControl{}
    case UI.Edit{editor, field, Forms.FileCollection{}, value}: NoControl{}
    case UI.Edit{editor, field, +entry, value}: make_input(meaning, label, widget_for(entry, field, value), field_availability(entry))
    case UI.SearchChoices{query}: make_input(meaning, label, SearchInput{}, View.Available{})
    case UI.EnterCredential{entered}: make_input(meaning, label, SecretInput{}, View.Available{})
    case UI.ReceiveFile{editor, enabled}: make_input(meaning, label, FileChooser{IconTextFace{Paperclip{}, label}}, UI.availability(enabled))
    case UI.EnterDirectory{editor}: make_input(meaning, label, DirectoryChooser{IconTextFace{Folder{}, label}}, View.Available{})
    case UI.BoardFilter{value}: make_input(meaning, label, SelectInput{}, View.Available{})
    case UI.BoardProfile{automatic, selected, choices, enabled}: make_input(meaning, label, SelectInput{}, UI.availability(enabled))
    case UI.MovableCard{destinations}:
      Movable{destinations, "Move " ++ label, Grip{}, Geometry{32n, 32n, 16n, 8n, 0n},
        Tooltip{"Move card", 300n, True{}, True{}, False{}}}
    case _: NoControl{}
