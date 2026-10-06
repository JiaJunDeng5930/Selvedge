import Base
import ../core/ui-identity.bend as UIIdentity
import ../core/client-services.bend as Services
import ../core/directory-entry-laws.bend as CoreDirectory
import ../core/form-fields.bend as Forms
import ../core/SYSTEM.bend as Core
import ../core/interface.bend as UI
import ../core/user-input.bend as U
import ./browser.bend as Browser
import ./controls.bend as Controls

type Requirements is Type:
  Requirements{
    enter_key: {Browser.confirmation_key("Enter", False{}, False{}, False{}, False{}, False{}) == True{} : Bool},
    composing_key: @keyboard:String -> @control:Bool -> @alt:Bool -> @shift:Bool -> @meta:Bool ->
      {Browser.confirmation_key(keyboard, True{}, control, alt, shift, meta) == False{} : Bool},
    denied_gesture: @found:Maybe<&2, UI.Node> -> {Browser.confirm_gesture(found, False{}) == None{} : Maybe<&2, UI.Gesture>},
    directory_gesture: @key:UIIdentity.Key -> @semantic:String -> @label:String -> @role:UI.Role -> @editor:U.Editor -> @text:String -> @children:+List<UI.Node> ->
      {Browser.confirm_gesture(Some{UI.Node{key, semantic, label, role, UI.EnterDirectory{editor, text}, children}}, True{}) == Some{UI.ConfirmDirectory{}} : Maybe<&2, UI.Gesture>},
    unmatched_confirmation: @+key:String -> @keyboard:String -> @composing:Bool -> @control:Bool -> @alt:Bool -> @shift:Bool -> @meta:Bool -> @+state:Browser.State ->
      @absent:{Browser.confirm_source(Browser.found_node(key, state)) == None{} : Maybe<&2, UI.Gesture>} ->
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
    open_and_browse: @+editor:U.Editor -> @+parent:UIIdentity.Key -> @+state:Core.State -> {UI.field_children(Forms.WorkspaceDirectories{}, editor, parent, state) ==
          UI.Node{UIIdentity.Part{parent, "instruction"}, "workspace/instruction", "Enter a directory path to add it. Listed directories define the workspace; choose the primary working directory.", UI.Content{}, UI.ReadOnly{"Enter a directory path to add it. Listed directories define the workspace; choose the primary working directory."}, Nil{}} <>
          UI.Node{UIIdentity.Part{parent, "add"}, "workspace/add", "Add working directory", UI.Field{}, UI.EnterDirectory{editor, UI.pending_directory(state, editor)}, Nil{}} <>
          UI.directory_confirm(editor, parent, state) <> UI.directory_browse(editor, parent, state) <>
          UI.directory_values(UI.workspace_observed(UI.field_value(state, editor, Forms.WorkspaceDirectories{})), editor, parent, state) : +List<UI.Node>},
    finite_choice: @+field:Forms.Field -> @+value:Forms.Observed -> {selection_widget(Controls.widget_for(Forms.Choice{}, field, value)) == True{} : Bool},
    location_binding: @value:String -> @+path:String -> {UI.bind(UI.DirectoryBrowserLocation{value}, UI.Directory{path}) == Some{Core.ServiceInput{Services.WriteDirectoryLocation{path}}} : Maybe<&2, Core.Input>},
    browse: @+editor:U.Editor -> @+parent:UIIdentity.Key -> @+state:Core.State -> {UI.directory_browse(editor, parent, state) == UI.product_action(parent, "workspace/browse", "Browse folders",
          Core.ServiceInput{Services.OpenDirectoryPicker{editor, UI.browse_start(editor, state), UIIdentity.encode(UIIdentity.Part{parent, "workspace/browse"})}},
          Core.accepts_directory(editor, UI.application_of(state))) : UI.Node}}

law picker_requirements:
  PickerRequirements
