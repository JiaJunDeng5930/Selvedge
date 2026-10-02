import Base
import ../core/interface.bend as UI
import ../core/SYSTEM.bend as Core
import ../core/ui-world.bend as View
import ../core/user-input.bend as User
import ./controls.bend as Controls
import ./control-laws.bend as Binding
import ./rendered.bend as Observed
import ./renderer.bend as Render
import ./document.bend as Doc
import ./design.bend as Design

def choice_binding(+key: String, +selected: Bool, description: String, +input: Core.Input,
  +availability: View.Availability, +label: String, role: UI.Role, context: Controls.Context) ->
  {Binding.binding(Controls.represent(key, UI.Choice{selected, description, input, availability}, label, role, context)) ==
    UI.Activate{input, availability} : UI.Meaning}:
  Binding.choice_retains_binding(key, selected, input, availability, label, role, context)

def choice_radio(+selected: Bool) ->
  {Render.behavior(Controls.ChoiceRadio{selected}) ==
    [Doc.Property{"role", "radio"}, Doc.Property{"aria-checked", Render.boolean(selected)}] : +List<Doc.Property>}:
  {==}

def choice_interactive(+selected: Bool, description: String, +input: Core.Input, +availability: View.Availability) ->
  {Observed.interactive(UI.Choice{selected, description, input, availability}) == True{} : Bool}:
  {==}

def choice_enabled(+selected: Bool, description: String, +input: Core.Input, +availability: View.Availability) ->
  {Observed.required_enabled(UI.Choice{selected, description, input, availability}) == Observed.enabled(availability) : Bool}:
  {==}

def choice_observed_tabs(+key: String, semantic: String, +label: String, role: UI.Role,
  +selected: Bool, description: String, +input: Core.Input, +availability: View.Availability,
  +elements: +List<Observed.Element>) ->
  {Observed.expected_tabs([UI.Node{key, semantic, label, role, UI.Choice{selected, description, input, availability}, Nil{}}], elements) ==
    Observed.tab_entry(Observed.enabled(availability) && Observed.tab_stop(Observed.find_element(elements, key)), key, Nil{}) : +List<String>}:
  {==}

def workspace_label(+label: String, expanded: Bool) ->
  {Controls.face_for(Controls.WorkspacePicker{expanded}, label, Controls.ComposerArea{}) ==
    Controls.PickerFace{Some{Controls.Folder{}}, label} : Controls.Face}:
  {==}

def permissions_label(+label: String, expanded: Bool) ->
  {Controls.face_for(Controls.panel_purpose(User.PermissionsConfiguration{User.NewTaskEditor{}}, expanded), label, Controls.ComposerArea{}) ==
    Controls.PickerFace{None{}, label} : Controls.Face}:
  {==}

def attributes(value: Doc.Node) -> +List<Doc.Property>:
  match value:
    case Doc.Element{key, tag, attrs, styles, events, children}: attrs
    case _: Nil{}

def events(value: Doc.Node) -> +List<Doc.Event>:
  match value:
    case Doc.Element{key, tag, attrs, styles, events, children}: events
    case _: Nil{}

def choice_native_event(+key: String, label: String, selected: Bool, description: String, +visual: Design.Style,
  input: Core.Input, availability: View.Availability, name: String, face: Controls.Face,
  behavior: Controls.Behavior, geometry: Controls.Geometry, placement: Controls.Placement,
  help: Controls.Help, feedback: Controls.Feedback, visual_children: +List<Design.Appearance>) ->
  {events(Render.choice_node(key, label, selected, description, visual,
    Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}, visual_children)) ==
    [Doc.Activate{key}] : +List<Doc.Event>}:
  {==}

type Requirements is Type:
  Requirements{
    choice_native_event: @+key:String -> @label:String -> @selected:Bool -> @description:String -> @+visual:Design.Style ->
      @input:Core.Input -> @availability:View.Availability -> @name:String -> @face:Controls.Face -> @behavior:Controls.Behavior -> @geometry:Controls.Geometry -> @placement:Controls.Placement -> @help:Controls.Help -> @feedback:Controls.Feedback -> @visual_children:+List<Design.Appearance> ->
      {events(Render.choice_node(key, label, selected, description, visual, Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}, visual_children)) == [Doc.Activate{key}] : +List<Doc.Event>},
    choice_binding: @+key:String -> @+selected:Bool -> @description:String -> @+input:Core.Input -> @+availability:View.Availability -> @+label:String -> @role:UI.Role -> @context:Controls.Context ->
      {Binding.binding(Controls.represent(key, UI.Choice{selected, description, input, availability}, label, role, context)) == UI.Activate{input, availability} : UI.Meaning},
    choice_radio: @+selected:Bool -> {Render.behavior(Controls.ChoiceRadio{selected}) == [Doc.Property{"role", "radio"}, Doc.Property{"aria-checked", Render.boolean(selected)}] : +List<Doc.Property>},
    choice_interactive: @+selected:Bool -> @description:String -> @+input:Core.Input -> @+availability:View.Availability -> {Observed.interactive(UI.Choice{selected, description, input, availability}) == True{} : Bool},
    choice_enabled: @+selected:Bool -> @description:String -> @+input:Core.Input -> @+availability:View.Availability -> {Observed.required_enabled(UI.Choice{selected, description, input, availability}) == Observed.enabled(availability) : Bool},
    choice_observed_tabs: @+key:String -> @semantic:String -> @+label:String -> @role:UI.Role -> @+selected:Bool -> @description:String -> @+input:Core.Input -> @+availability:View.Availability -> @+elements:+List<Observed.Element> ->
      {Observed.expected_tabs([UI.Node{key, semantic, label, role, UI.Choice{selected, description, input, availability}, Nil{}}], elements) == Observed.tab_entry(Observed.enabled(availability) && Observed.tab_stop(Observed.find_element(elements, key)), key, Nil{}) : +List<String>},
    workspace_label: @+label:String -> @expanded:Bool -> {Controls.face_for(Controls.WorkspacePicker{expanded}, label, Controls.ComposerArea{}) == Controls.PickerFace{Some{Controls.Folder{}}, label} : Controls.Face},
    permissions_label: @+label:String -> @expanded:Bool -> {Controls.face_for(Controls.panel_purpose(User.PermissionsConfiguration{User.NewTaskEditor{}}, expanded), label, Controls.ComposerArea{}) == Controls.PickerFace{None{}, label} : Controls.Face}}

def evidence() -> Requirements:
  Requirements{choice_native_event, choice_binding, choice_radio, choice_interactive, choice_enabled, choice_observed_tabs, workspace_label, permissions_label}
