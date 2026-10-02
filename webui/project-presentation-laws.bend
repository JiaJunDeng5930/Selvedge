import Base
import ./enclosure.bend as Enclosure
import ./appearance.bend as Appearance
import ../bendlib/stdlib.bend as Std
import ./document.bend as Doc
import ./renderer.bend as Render
import ./design.bend as Design
import ./surfaces.bend as Surfaces
import ./controls.bend as Controls
import ../core/interface.bend as UI
import ../core/composition.bend as Composition
import ../core/SYSTEM.bend as Core
import ../core/user-input.bend as User
import ../core/user-experience.bend as Experience
import ../core/ui-world.bend as View

def group_production(+key: String, label: String, role: UI.Role, +project: Nat, +selected: Bool, +expanded: Bool,
  source: +List<UI.Node>, +children: +List<Doc.Node>, visual: Design.Style, representation: Controls.Representation, +appearances: +List<Design.Appearance>) ->
  {Render.match_node(key, label, role, UI.ProjectGroup{project, selected, expanded}, source, children, visual, representation, appearances) ==
    Doc.Element{key, "div", [Render.property("data-native-key", key), Render.property("data-project", Nat.show(project)), Render.property("data-expanded", Render.boolean(expanded))],
      [Render.property("display", "flex"), Render.property("flex-direction", "column"), Render.property("gap", "2px"), Render.property("min-width", "0")], Nil{},
      Render.project_group_children(children, appearances, selected, expanded)} : Doc.Node}:
  {==}

def header_production(+key: String, +tag: String, +attrs: +List<Doc.Property>, +styles: +List<Doc.Property>, +events: +List<Doc.Event>,
  +children: +List<Doc.Node>, +appearances: +List<Design.Appearance>, +selected: Bool, +expanded: Bool) ->
  {Render.project_header_node(Doc.Element{key, tag, attrs, styles, events, children}, appearances, selected, expanded) ==
    Doc.Element{key, tag, List.append(&2, Doc.Property, attrs, [Render.property("class", "native-surface")]), List.append(&2, Doc.Property, Render.pointer_styles(styles),
      List.append(&2, Doc.Property, List.append(&2, Doc.Property, [Render.property("display", "flex"), Render.property("flex-direction", "row"), Render.property("align-items", "center"), Render.property("gap", "2px"),
       Render.property("min-width", "0"), Render.property("border-radius", "6px"), Render.property("border", "0")], Render.content_area_properties(Enclosure.area(Enclosure.NavigationRow{}))), Render.native_surface_properties(Surfaces.Choice{selected}))), events,
      Render.project_header_controls(children, appearances, expanded)} : Doc.Node}:
  {==}

def disclosure_typed(+project: Nat) ->
  {Render.project_control_input(Core.ApplicationInput{Experience.UserInput{User.Activate{User.ToggleProjectGroup{project}}}}) == Render.ProjectDisclosure{} : Render.ProjectControl}:
  {==}

def name_typed(project: Maybe<&2, Nat>) ->
  {Render.project_control_input(Core.ApplicationInput{Experience.UserInput{User.Activate{User.SelectProject{project}}}}) == Render.ProjectName{} : Render.ProjectControl}:
  {==}

def disclosure_retains_command(+key: String, +tag: String, +attrs: +List<Doc.Property>, +styles: +List<Doc.Property>, +events: +List<Doc.Event>,
  children: +List<Doc.Node>, appearance_key: String, name: String, +expanded: Bool) ->
  {Render.project_control_face(Render.ProjectDisclosure{}, Doc.Element{key, tag, attrs, styles, events, children}, appearance_key, name, expanded) ==
    Doc.Element{key, tag, List.append(&2, Doc.Property, attrs, [Render.property("aria-expanded", Render.boolean(expanded))]),
      List.append(&2, Doc.Property, styles, Render.project_icon_styles("24px")), events, [Render.icon(appearance_key, Render.project_chevron(expanded))]} : Doc.Node}:
  {==}

def name_single_face(+key: String, +tag: String, +attrs: +List<Doc.Property>, +styles: +List<Doc.Property>, +events: +List<Doc.Event>,
  children: +List<Doc.Node>, appearance_key: String, +name: String, expanded: Bool) ->
  {Render.project_control_face(Render.ProjectName{}, Doc.Element{key, tag, attrs, styles, events, children}, appearance_key, name, expanded) ==
    Doc.Element{key, tag, attrs, List.append(&2, Doc.Property, styles, Render.project_name_styles()), events, [Doc.Text{name}]} : Doc.Node}:
  Equal.cong(+List<Doc.Property>, Doc.Node, (properties => Doc.Element{key, tag, properties, List.append(&2, Doc.Property, styles, Render.project_name_styles()), events, [Doc.Text{name}]}),
    List.append(&2, Doc.Property, attrs, Nil{}), attrs, Std.app_nil_r(Doc.Property, attrs))

def header_control_actual_input(+node: Doc.Node, +key: String, visual: Design.Style, +input: Core.Input,
  availability: View.Availability, +name: String, face: Controls.Face, behavior: Controls.Behavior, geometry: Controls.Geometry,
  placement: Controls.Placement, help: Controls.Help, feedback: Controls.Feedback, children: +List<Design.Appearance>, +expanded: Bool) ->
  {Render.project_header_control(node, Design.Appearance{key, visual, Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}, children}, expanded) ==
    Render.project_control_face(Render.project_control_input(input), node, key, name, expanded) : Doc.Node}:
  {==}

def icon_geometry(+width: String) ->
  {Render.project_icon_styles(width) ==
    List.append(&2, Doc.Property, [Render.property("display", "inline-flex"), Render.property("align-items", "center"), Render.property("justify-content", "center"),
     Render.property("flex", "0 0 " ++ width), Render.property("width", width), Render.property("min-width", width), Render.property("height", width),
     Render.property("min-height", width), Render.property("border", "0")], Render.content_area_properties(Enclosure.area(Enclosure.IconControl{}))) : +List<Doc.Property>}:
  {==}

def name_geometry() ->
  {Render.project_name_styles() ==
    List.append(&2, Doc.Property, List.append(&2, Doc.Property, [Render.property("display", "block"), Render.property("flex", "1 1 0"), Render.property("min-width", "0"), Render.property("width", "auto"),
     Render.property("overflow", "hidden"), Render.property("text-overflow", "ellipsis"), Render.property("white-space", "nowrap"),
     Render.property("text-align", "start"), Render.property("border", "0")], Render.content_area_properties(Enclosure.ambient(0n, 0n))), Render.embedded_action_properties()) : +List<Doc.Property>}:
  {==}

def task_production(+key: String, label: String, role: UI.Role, +task: Nat, +status: String, +selected: Bool,
  source: +List<UI.Node>, +children: +List<Doc.Node>, visual: Design.Style, representation: Controls.Representation, +appearances: +List<Design.Appearance>) ->
  {Render.match_node(key, label, role, UI.TaskRow{task, status, selected}, source, children, visual, representation, appearances) ==
    Doc.Element{key, "div", [Render.property("data-native-key", key), Render.property("data-task", Nat.show(task)), Render.property("data-status", status), Render.property("class", "native-surface")],
      List.append(&2, Doc.Property, List.append(&2, Doc.Property, [Render.property("display", "flex"), Render.property("align-items", "center"), Render.property("gap", "6px"), Render.property("min-width", "0"),
       Render.property("border-radius", "5px")], Render.content_area_properties(Enclosure.area(Enclosure.NavigationRow{}))), Render.native_surface_properties(Surfaces.Choice{selected})), Nil{},
      Render.task_row_children(children, appearances, status)} : Doc.Node}:
  {==}

def status_visible(+key: String, tag: String, +attrs: +List<Doc.Property>, styles: +List<Doc.Property>, +events: +List<Doc.Event>, children: +List<Doc.Node>, +status: String) ->
  {Render.task_status_node(Doc.Element{key, tag, attrs, styles, events, children}, status) ==
    Doc.Element{key, "span", List.append(&2, Doc.Property, attrs, [Render.property("aria-label", status), Render.property("title", status)]),
      [Render.property("display", "inline-flex"), Render.property("flex", "0 0 auto"), Render.property("align-items", "center"), Render.property("gap", "4px"),
       Render.property("order", "-1"), Render.property("font-size", "11px"), Render.property("color", Render.task_status_tone(status)), Render.property("white-space", "nowrap")], events,
      [Doc.Element{key ++ "/indicator", "span", [Render.property("aria-hidden", "true")], Nil{}, Nil{}, [Doc.Text{"●"}]}, Doc.Text{status}]} : Doc.Node}:
  {==}

def chooser_production(+key: String, label: String, role: UI.Role, +selected: Maybe<&2, Nat>, source: +List<UI.Node>, +children: +List<Doc.Node>,
  visual: Design.Style, representation: Controls.Representation, +appearances: +List<Design.Appearance>) ->
  {Render.match_node(key, label, role, UI.ProjectChooser{selected}, source, children, visual, representation, appearances) ==
    Doc.Element{key, "div", [Render.property("data-native-key", key)], [Render.property("display", "inline-flex"), Render.property("align-items", "center"), Render.property("min-width", "0")], Nil{},
      Render.project_chooser_children(children, appearances, selected)} : Doc.Node}:
  {==}

def chevron_paths() ->
  {(Render.icon_path(Controls.ChevronRight{}), Render.icon_path(Controls.ChevronDown{})) ==
    ("M7.5 4.5 L13 10 L7.5 15.5", "M4.5 7.5 L10 13 L15.5 7.5") : String & String}:
  {==}


def chooser_value_binding(+key: String, +tag: String, +attrs: +List<Doc.Property>, +styles: +List<Doc.Property>, +events: +List<Doc.Event>, children: +List<Doc.Node>,
  +appearance_key: String, trigger: String, availability: View.Availability, +name: String, face: Controls.Face, behavior: Controls.Behavior,
  geometry: Controls.Geometry, placement: Controls.Placement, help: Controls.Help, feedback: Controls.Feedback, +selected: Maybe<&2, Nat>) ->
  {Render.project_chooser_control(Doc.Element{key, tag, attrs, styles, events, children}, appearance_key,
    Controls.Action{Core.ApplicationInput{Experience.UserInput{User.Activate{User.OpenPanel{User.ProjectPicker{}, trigger}}}}, availability, name, face, behavior, geometry, placement, help, feedback}, selected) ==
    Doc.Element{key, tag, List.append(&2, Doc.Property, attrs, Nil{}), List.append(&2, Doc.Property, styles,
      List.append(&2, Doc.Property, List.append(&2, Doc.Property, Render.project_chooser_styles(selected),
        [Render.property("display", "inline-flex"), Render.property("align-items", "center"), Render.property("gap", "4px"), Render.property("width", "auto"),
         Render.property("padding-inline", "0"), Render.property("border", "0")]), Render.embedded_action_properties())), events,
      [Render.icon(appearance_key ++ "/folder", Controls.Folder{}), Render.face_label(appearance_key, name), Render.icon(appearance_key ++ "/disclosure", Controls.ChevronDown{})]} : Doc.Node}:
  {==}

def create_typed(project: Maybe<&2, Nat>) ->
  {Render.project_control_input(Core.ApplicationInput{Experience.UserInput{User.Activate{User.BeginTask{project}}}}) == Render.ProjectCreate{} : Render.ProjectControl}:
  {==}

def more_typed(project: Nat, trigger: String) ->
  {Render.project_control_input(Core.ApplicationInput{Experience.UserInput{User.Activate{User.OpenPanel{User.ObjectActions{User.ProjectSubject{project}}, trigger}}}}) == Render.ProjectMore{} : Render.ProjectControl}:
  {==}

def create_retains_command(+key: String, +tag: String, +attrs: +List<Doc.Property>, +styles: +List<Doc.Property>, +events: +List<Doc.Event>,
  children: +List<Doc.Node>, +appearance_key: String, name: String, expanded: Bool) ->
  {Render.project_control_face(Render.ProjectCreate{}, Doc.Element{key, tag, attrs, styles, events, children}, appearance_key, name, expanded) ==
    Doc.Element{key, tag, List.append(&2, Doc.Property, attrs, Nil{}), List.append(&2, Doc.Property, styles, Render.project_icon_styles("28px")), events,
      [Render.icon(appearance_key, Controls.Plus{})]} : Doc.Node}:
  {==}

def more_retains_command(+key: String, +tag: String, +attrs: +List<Doc.Property>, +styles: +List<Doc.Property>, +events: +List<Doc.Event>,
  children: +List<Doc.Node>, +appearance_key: String, name: String, expanded: Bool) ->
  {Render.project_control_face(Render.ProjectMore{}, Doc.Element{key, tag, attrs, styles, events, children}, appearance_key, name, expanded) ==
    Doc.Element{key, tag, List.append(&2, Doc.Property, attrs, Nil{}), List.append(&2, Doc.Property, styles, Render.project_icon_styles("28px")), events,
      [Render.icon(appearance_key, Controls.MoreDots{})]} : Doc.Node}:
  {==}

def children_indent(+node: Doc.Node, appearances: +List<Design.Appearance>, selected: Bool, expanded: Bool) ->
  {Render.project_child(False{}, node, appearances, selected, expanded) ==
    Render.replace_styles(node, [Render.property("margin-inline-start", "20px"), Render.property("min-width", "0")]) : Doc.Node}:
  {==}

def creation_heading_observed(value: Design.Style) -> Design.TextStyle:
  Design.Style{text, chrome, alignment, flow, overflow, content_area, gap, minimum, maximum, states} = value
  text

def chooser_draft_observation(+id: Nat, +fallback: Design.Style) ->
  {Render.project_chooser_styles(Some{id}) == Render.creation_heading_styles(creation_heading_observed(Appearance.semantic_style("creation/title", fallback))) : +List<Doc.Property>}:
  {==}


type Requirements is Type:
  Requirements{
    group_production: @+key:String -> @label:String -> @role:UI.Role -> @+project:Nat -> @+selected:Bool -> @+expanded:Bool -> @source:+List<UI.Node> -> @+children:+List<Doc.Node> -> @visual:Design.Style -> @representation:Controls.Representation -> @+appearances:+List<Design.Appearance> ->
      {Render.match_node(key, label, role, UI.ProjectGroup{project, selected, expanded}, source, children, visual, representation, appearances) ==
    Doc.Element{key, "div", [Render.property("data-native-key", key), Render.property("data-project", Nat.show(project)), Render.property("data-expanded", Render.boolean(expanded))],
      [Render.property("display", "flex"), Render.property("flex-direction", "column"), Render.property("gap", "2px"), Render.property("min-width", "0")], Nil{},
      Render.project_group_children(children, appearances, selected, expanded)} : Doc.Node},
    header_production: @+key:String -> @+tag:String -> @+attrs:+List<Doc.Property> -> @+styles:+List<Doc.Property> -> @+events:+List<Doc.Event> -> @+children:+List<Doc.Node> -> @+appearances:+List<Design.Appearance> -> @+selected:Bool -> @+expanded:Bool ->
      {Render.project_header_node(Doc.Element{key, tag, attrs, styles, events, children}, appearances, selected, expanded) ==
    Doc.Element{key, tag, List.append(&2, Doc.Property, attrs, [Render.property("class", "native-surface")]), List.append(&2, Doc.Property, Render.pointer_styles(styles),
      List.append(&2, Doc.Property, List.append(&2, Doc.Property, [Render.property("display", "flex"), Render.property("flex-direction", "row"), Render.property("align-items", "center"), Render.property("gap", "2px"),
       Render.property("min-width", "0"), Render.property("border-radius", "6px"), Render.property("border", "0")], Render.content_area_properties(Enclosure.area(Enclosure.NavigationRow{}))), Render.native_surface_properties(Surfaces.Choice{selected}))), events,
      Render.project_header_controls(children, appearances, expanded)} : Doc.Node},
    disclosure_typed: @+project:Nat ->
      {Render.project_control_input(Core.ApplicationInput{Experience.UserInput{User.Activate{User.ToggleProjectGroup{project}}}}) == Render.ProjectDisclosure{} : Render.ProjectControl},
    name_typed: @project:Maybe<&2, Nat> ->
      {Render.project_control_input(Core.ApplicationInput{Experience.UserInput{User.Activate{User.SelectProject{project}}}}) == Render.ProjectName{} : Render.ProjectControl},
    disclosure_retains_command: @+key:String -> @+tag:String -> @+attrs:+List<Doc.Property> -> @+styles:+List<Doc.Property> -> @+events:+List<Doc.Event> -> @children:+List<Doc.Node> -> @appearance_key:String -> @name:String -> @+expanded:Bool ->
      {Render.project_control_face(Render.ProjectDisclosure{}, Doc.Element{key, tag, attrs, styles, events, children}, appearance_key, name, expanded) ==
    Doc.Element{key, tag, List.append(&2, Doc.Property, attrs, [Render.property("aria-expanded", Render.boolean(expanded))]),
      List.append(&2, Doc.Property, styles, Render.project_icon_styles("24px")), events, [Render.icon(appearance_key, Render.project_chevron(expanded))]} : Doc.Node},
    name_single_face: @+key:String -> @+tag:String -> @+attrs:+List<Doc.Property> -> @+styles:+List<Doc.Property> -> @+events:+List<Doc.Event> -> @children:+List<Doc.Node> -> @appearance_key:String -> @+name:String -> @expanded:Bool ->
      {Render.project_control_face(Render.ProjectName{}, Doc.Element{key, tag, attrs, styles, events, children}, appearance_key, name, expanded) ==
    Doc.Element{key, tag, attrs, List.append(&2, Doc.Property, styles, Render.project_name_styles()), events, [Doc.Text{name}]} : Doc.Node},
    header_control_actual_input: @+node:Doc.Node -> @+key:String -> @visual:Design.Style -> @+input:Core.Input -> @availability:View.Availability -> @+name:String -> @face:Controls.Face -> @behavior:Controls.Behavior -> @geometry:Controls.Geometry -> @placement:Controls.Placement -> @help:Controls.Help -> @feedback:Controls.Feedback -> @children:+List<Design.Appearance> -> @+expanded:Bool ->
      {Render.project_header_control(node, Design.Appearance{key, visual, Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}, children}, expanded) ==
    Render.project_control_face(Render.project_control_input(input), node, key, name, expanded) : Doc.Node},
    icon_geometry: @+width:String ->
      {Render.project_icon_styles(width) ==
    List.append(&2, Doc.Property, [Render.property("display", "inline-flex"), Render.property("align-items", "center"), Render.property("justify-content", "center"),
     Render.property("flex", "0 0 " ++ width), Render.property("width", width), Render.property("min-width", width), Render.property("height", width),
     Render.property("min-height", width), Render.property("border", "0")], Render.content_area_properties(Enclosure.area(Enclosure.IconControl{}))) : +List<Doc.Property>},
    name_geometry:
      {Render.project_name_styles() ==
    List.append(&2, Doc.Property, List.append(&2, Doc.Property, [Render.property("display", "block"), Render.property("flex", "1 1 0"), Render.property("min-width", "0"), Render.property("width", "auto"),
     Render.property("overflow", "hidden"), Render.property("text-overflow", "ellipsis"), Render.property("white-space", "nowrap"),
     Render.property("text-align", "start"), Render.property("border", "0")], Render.content_area_properties(Enclosure.ambient(0n, 0n))), Render.embedded_action_properties()) : +List<Doc.Property>},
    task_production: @+key:String -> @label:String -> @role:UI.Role -> @+task:Nat -> @+status:String -> @+selected:Bool -> @source:+List<UI.Node> -> @+children:+List<Doc.Node> -> @visual:Design.Style -> @representation:Controls.Representation -> @+appearances:+List<Design.Appearance> ->
      {Render.match_node(key, label, role, UI.TaskRow{task, status, selected}, source, children, visual, representation, appearances) ==
    Doc.Element{key, "div", [Render.property("data-native-key", key), Render.property("data-task", Nat.show(task)), Render.property("data-status", status), Render.property("class", "native-surface")],
      List.append(&2, Doc.Property, List.append(&2, Doc.Property, [Render.property("display", "flex"), Render.property("align-items", "center"), Render.property("gap", "6px"), Render.property("min-width", "0"),
       Render.property("border-radius", "5px")], Render.content_area_properties(Enclosure.area(Enclosure.NavigationRow{}))), Render.native_surface_properties(Surfaces.Choice{selected})), Nil{},
      Render.task_row_children(children, appearances, status)} : Doc.Node},
    status_visible: @+key:String -> @tag:String -> @+attrs:+List<Doc.Property> -> @styles:+List<Doc.Property> -> @+events:+List<Doc.Event> -> @children:+List<Doc.Node> -> @+status:String ->
      {Render.task_status_node(Doc.Element{key, tag, attrs, styles, events, children}, status) ==
    Doc.Element{key, "span", List.append(&2, Doc.Property, attrs, [Render.property("aria-label", status), Render.property("title", status)]),
      [Render.property("display", "inline-flex"), Render.property("flex", "0 0 auto"), Render.property("align-items", "center"), Render.property("gap", "4px"),
       Render.property("order", "-1"), Render.property("font-size", "11px"), Render.property("color", Render.task_status_tone(status)), Render.property("white-space", "nowrap")], events,
      [Doc.Element{key ++ "/indicator", "span", [Render.property("aria-hidden", "true")], Nil{}, Nil{}, [Doc.Text{"●"}]}, Doc.Text{status}]} : Doc.Node},
    chooser_production: @+key:String -> @label:String -> @role:UI.Role -> @+selected:Maybe<&2, Nat> -> @source:+List<UI.Node> -> @+children:+List<Doc.Node> -> @visual:Design.Style -> @representation:Controls.Representation -> @+appearances:+List<Design.Appearance> ->
      {Render.match_node(key, label, role, UI.ProjectChooser{selected}, source, children, visual, representation, appearances) ==
    Doc.Element{key, "div", [Render.property("data-native-key", key)], [Render.property("display", "inline-flex"), Render.property("align-items", "center"), Render.property("min-width", "0")], Nil{},
      Render.project_chooser_children(children, appearances, selected)} : Doc.Node},
    chevron_paths:
      {(Render.icon_path(Controls.ChevronRight{}), Render.icon_path(Controls.ChevronDown{})) ==
    ("M7.5 4.5 L13 10 L7.5 15.5", "M4.5 7.5 L10 13 L15.5 7.5") : String & String},
    chooser_value_binding: @+key:String -> @+tag:String -> @+attrs:+List<Doc.Property> -> @+styles:+List<Doc.Property> -> @+events:+List<Doc.Event> -> @children:+List<Doc.Node> -> @+appearance_key:String -> @trigger:String -> @availability:View.Availability -> @+name:String -> @face:Controls.Face -> @behavior:Controls.Behavior -> @geometry:Controls.Geometry -> @placement:Controls.Placement -> @help:Controls.Help -> @feedback:Controls.Feedback -> @+selected:Maybe<&2, Nat> ->
      {Render.project_chooser_control(Doc.Element{key, tag, attrs, styles, events, children}, appearance_key,
    Controls.Action{Core.ApplicationInput{Experience.UserInput{User.Activate{User.OpenPanel{User.ProjectPicker{}, trigger}}}}, availability, name, face, behavior, geometry, placement, help, feedback}, selected) ==
    Doc.Element{key, tag, List.append(&2, Doc.Property, attrs, Nil{}), List.append(&2, Doc.Property, styles,
      List.append(&2, Doc.Property, List.append(&2, Doc.Property, Render.project_chooser_styles(selected),
        [Render.property("display", "inline-flex"), Render.property("align-items", "center"), Render.property("gap", "4px"), Render.property("width", "auto"),
         Render.property("padding-inline", "0"), Render.property("border", "0")]), Render.embedded_action_properties())), events,
      [Render.icon(appearance_key ++ "/folder", Controls.Folder{}), Render.face_label(appearance_key, name), Render.icon(appearance_key ++ "/disclosure", Controls.ChevronDown{})]} : Doc.Node},
    create_typed: @project:Maybe<&2, Nat> ->
      {Render.project_control_input(Core.ApplicationInput{Experience.UserInput{User.Activate{User.BeginTask{project}}}}) == Render.ProjectCreate{} : Render.ProjectControl},
    more_typed: @project:Nat -> @trigger:String ->
      {Render.project_control_input(Core.ApplicationInput{Experience.UserInput{User.Activate{User.OpenPanel{User.ObjectActions{User.ProjectSubject{project}}, trigger}}}}) == Render.ProjectMore{} : Render.ProjectControl},
    create_retains_command: @+key:String -> @+tag:String -> @+attrs:+List<Doc.Property> -> @+styles:+List<Doc.Property> -> @+events:+List<Doc.Event> -> @children:+List<Doc.Node> -> @+appearance_key:String -> @name:String -> @expanded:Bool ->
      {Render.project_control_face(Render.ProjectCreate{}, Doc.Element{key, tag, attrs, styles, events, children}, appearance_key, name, expanded) ==
    Doc.Element{key, tag, List.append(&2, Doc.Property, attrs, Nil{}), List.append(&2, Doc.Property, styles, Render.project_icon_styles("28px")), events,
      [Render.icon(appearance_key, Controls.Plus{})]} : Doc.Node},
    more_retains_command: @+key:String -> @+tag:String -> @+attrs:+List<Doc.Property> -> @+styles:+List<Doc.Property> -> @+events:+List<Doc.Event> -> @children:+List<Doc.Node> -> @+appearance_key:String -> @name:String -> @expanded:Bool ->
      {Render.project_control_face(Render.ProjectMore{}, Doc.Element{key, tag, attrs, styles, events, children}, appearance_key, name, expanded) ==
    Doc.Element{key, tag, List.append(&2, Doc.Property, attrs, Nil{}), List.append(&2, Doc.Property, styles, Render.project_icon_styles("28px")), events,
      [Render.icon(appearance_key, Controls.MoreDots{})]} : Doc.Node},
    children_indent: @+node:Doc.Node -> @appearances:+List<Design.Appearance> -> @selected:Bool -> @expanded:Bool ->
      {Render.project_child(False{}, node, appearances, selected, expanded) ==
    Render.replace_styles(node, [Render.property("margin-inline-start", "20px"), Render.property("min-width", "0")]) : Doc.Node},
    chooser_draft_observation: @+id:Nat -> @+fallback:Design.Style ->
      {Render.project_chooser_styles(Some{id}) == Render.creation_heading_styles(creation_heading_observed(Appearance.semantic_style("creation/title", fallback))) : +List<Doc.Property>}}

def evidence() -> Requirements:
  Requirements{
    key => label => role => project => selected => expanded => source => children => visual => representation => appearances => group_production(key, label, role, project, selected, expanded, source, children, visual, representation, appearances),
    key => tag => attrs => styles => events => children => appearances => selected => expanded => header_production(key, tag, attrs, styles, events, children, appearances, selected, expanded),
    project => disclosure_typed(project),
    project => name_typed(project),
    key => tag => attrs => styles => events => children => appearance_key => name => expanded => disclosure_retains_command(key, tag, attrs, styles, events, children, appearance_key, name, expanded),
    key => tag => attrs => styles => events => children => appearance_key => name => expanded => name_single_face(key, tag, attrs, styles, events, children, appearance_key, name, expanded),
    node => key => visual => input => availability => name => face => behavior => geometry => placement => help => feedback => children => expanded => header_control_actual_input(node, key, visual, input, availability, name, face, behavior, geometry, placement, help, feedback, children, expanded),
    width => icon_geometry(width),
    name_geometry(),
    key => label => role => task => status => selected => source => children => visual => representation => appearances => task_production(key, label, role, task, status, selected, source, children, visual, representation, appearances),
    key => tag => attrs => styles => events => children => status => status_visible(key, tag, attrs, styles, events, children, status),
    key => label => role => selected => source => children => visual => representation => appearances => chooser_production(key, label, role, selected, source, children, visual, representation, appearances),
    chevron_paths(),
    key => tag => attrs => styles => events => children => appearance_key => trigger => availability => name => face => behavior => geometry => placement => help => feedback => selected => chooser_value_binding(key, tag, attrs, styles, events, children, appearance_key, trigger, availability, name, face, behavior, geometry, placement, help, feedback, selected),
    project => create_typed(project),
    project => trigger => more_typed(project, trigger),
    key => tag => attrs => styles => events => children => appearance_key => name => expanded => create_retains_command(key, tag, attrs, styles, events, children, appearance_key, name, expanded),
    key => tag => attrs => styles => events => children => appearance_key => name => expanded => more_retains_command(key, tag, attrs, styles, events, children, appearance_key, name, expanded),
    node => appearances => selected => expanded => children_indent(node, appearances, selected, expanded),
    id => fallback => chooser_draft_observation(id, fallback)}
