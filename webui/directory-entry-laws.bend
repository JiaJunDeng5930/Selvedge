import Base
import ../core/ui-identity.bend as UIIdentity
import ../core/client-services.bend as Services
import ../core/directory-entry-laws.bend as CoreDirectory
import ../core/form-fields.bend as Forms
import ../core/SYSTEM.bend as Core
import ../core/interface.bend as InterfaceView
import ../core/user-input.bend as U
import ./browser.bend as Browser
import ./controls.bend as Controls

type Requirements is Type:
  Requirements{
    enter_key: {Browser.confirmation_key("Enter", False{}, False{}, False{}, False{}, False{}) == True{} : Bool},
    composing_key: @keyboard:String -> @control:Bool -> @alt:Bool -> @shift:Bool -> @meta:Bool ->
      {Browser.confirmation_key(keyboard, True{}, control, alt, shift, meta) == False{} : Bool},
    denied_gesture: @found:Maybe<&2, InterfaceView.Node> -> {Browser.confirm_gesture(found, False{}) == None{} : Maybe<&2, InterfaceView.Gesture>},
    directory_gesture: @key:UIIdentity.Key -> @semantic:String -> @label:String -> @role:InterfaceView.Role -> @editor:U.Editor -> @text:String -> @children:+List<InterfaceView.Node> ->
      {Browser.confirm_gesture(Some{InterfaceView.Node{key, semantic, label, role, InterfaceView.EnterDirectory{editor, text}, children}}, True{}) == Some{InterfaceView.ConfirmDirectory{}} : Maybe<&2, InterfaceView.Gesture>},
    unmatched_confirmation: @+key:String -> @keyboard:String -> @composing:Bool -> @control:Bool -> @alt:Bool -> @shift:Bool -> @meta:Bool -> @+state:Browser.State ->
      @absent:{Browser.confirm_source(Browser.found_node(key, state)) == None{} : Maybe<&2, InterfaceView.Gesture>} ->
      {Browser.confirm_text(key, keyboard, composing, control, alt, shift, meta, state) == Browser.Decision{state, Nil{}} : Browser.Decision},
    rejected_confirmation: @+key:String -> @keyboard:String -> @composing:Bool -> @control:Bool -> @alt:Bool -> @shift:Bool -> @meta:Bool -> @+state:Browser.State ->
      @denied:{Browser.confirmation_key(keyboard, composing, control, alt, shift, meta) == False{} : Bool} ->
      {Browser.confirm_text(key, keyboard, composing, control, alt, shift, meta, state) == Browser.Decision{state, Nil{}} : Browser.Decision}}

law evidence:
  Requirements

def selection_widget(widget: Controls.Widget) -> Bool:
  match widget:
    case Controls.SelectInput{}: True{}
    case Controls.ToggleInput{}: True{}
    case _: False{}

type PickerRequirements is Type:
  PickerRequirements{service: CoreDirectory.DirectoryPickerRequirements,
    open_and_browse: @+editor:U.Editor -> @+parent:UIIdentity.Key -> @+state:Core.State -> {InterfaceView.field_children(Forms.WorkspaceDirectories{}, editor, parent, state) ==
          InterfaceView.Node{UIIdentity.Part{parent, "instruction"}, "workspace/instruction", "Enter a directory path to add it. Listed directories define the workspace; choose the primary working directory.", InterfaceView.Content{}, InterfaceView.ReadOnly{"Enter a directory path to add it. Listed directories define the workspace; choose the primary working directory."}, Nil{}} <>
          InterfaceView.Node{UIIdentity.Part{parent, "add"}, "workspace/add", "Add working directory", InterfaceView.Field{}, InterfaceView.EnterDirectory{editor, InterfaceView.pending_directory(state, editor)}, Nil{}} <>
          InterfaceView.directory_confirm(editor, parent, state) <> InterfaceView.directory_browse(editor, parent, state) <>
          InterfaceView.directory_values(InterfaceView.workspace_observed(InterfaceView.field_value(state, editor, Forms.WorkspaceDirectories{})), editor, parent, state) : +List<InterfaceView.Node>},
    finite_choice: @+field:Forms.Field -> @+value:Forms.Observed -> {selection_widget(Controls.widget_for(Forms.Choice{}, field, value)) == True{} : Bool},
    location_binding: @value:String -> @+path:String -> {InterfaceView.bind(InterfaceView.DirectoryBrowserLocation{value}, InterfaceView.Directory{path}) == Some{Core.ServiceInput{Services.WriteDirectoryLocation{path}}} : Maybe<&2, Core.Input>},
    browse: @+editor:U.Editor -> @+parent:UIIdentity.Key -> @+state:Core.State -> {InterfaceView.directory_browse(editor, parent, state) == InterfaceView.product_action(parent, "workspace/browse", "Browse folders",
          Core.ServiceInput{Services.OpenDirectoryPicker{editor, InterfaceView.browse_start(editor, state), UIIdentity.encode(UIIdentity.Part{parent, "workspace/browse"})}},
          Core.accepts_directory(editor, InterfaceView.application_of(state))) : InterfaceView.Node}}

law picker_requirements:
  PickerRequirements
