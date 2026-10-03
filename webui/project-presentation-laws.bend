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
import ../core/code-block.bend as Code
import ../core/client-services.bend as Services
import ../core/user-context.bend as Workspace

# The projection changes only the visible face, behavior and geometry; all other
# accepted-action fields retain their original source value.
def projected_action(input: Core.Input, availability: View.Availability, name: String, projection: Controls.ActionPresentation, placement: Controls.Placement, help: Controls.Help, feedback: Controls.Feedback) -> Controls.Representation:
  Controls.ActionPresentation{face, behavior, geometry} = projection
  Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}

def projection_construction(input: Core.Input, availability: View.Availability, name: String, projection: Controls.ActionPresentation, placement: Controls.Placement, help: Controls.Help, feedback: Controls.Feedback) ->
  {Controls.presented_action(input, availability, name, projection, placement, help, feedback) == projected_action(input, availability, name, projection, placement, help, feedback) : Controls.Representation}:
  match projection:
    case Controls.ActionPresentation{face, behavior, geometry}: {==}

def label_properties(value: Design.Style) -> (Design.Flow & (Design.Overflow & (Nat & Nat))):
  Design.Style{text, chrome, alignment, flow, overflow, +frame, minimum, maximum, states} = value
  (flow, (overflow, (Enclosure.inline(Enclosure.frame_content(frame)), Enclosure.block(Enclosure.frame_content(frame)))))

def creation_heading_observed(value: Design.Style) -> Design.TextStyle:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
  text

def status_visible_law(-key: String, -tag: String, -attrs: +List<Doc.Property>, -styles: +List<Doc.Property>, -events: +List<Doc.Event>, -children: +List<Doc.Node>, -status: String) -> Type:
  {Render.task_status_node(Doc.Element{key, tag, attrs, styles, events, children}, status) ==
      Doc.Element{key, "span", List.append(&2, Doc.Property, attrs, [Render.property("aria-label", status), Render.property("title", status)]),
        [Render.property("display", "inline-flex"), Render.property("flex", "0 0 auto"), Render.property("align-items", "center"), Render.property("gap", "4px"),
         Render.property("order", "-1"), Render.property("font-size", "11px"), Render.property("color", Render.task_status_tone(status)), Render.property("white-space", "nowrap")], events,
        [Doc.Element{key ++ "/indicator", "span", [Render.property("aria-hidden", "true")], Nil{}, Nil{}, [Doc.Text{"●"}]}, Doc.Text{status}]} : Doc.Node}

def status_visible(+key: String, +tag: String, +attrs: +List<Doc.Property>, +styles: +List<Doc.Property>, +events: +List<Doc.Event>, children: +List<Doc.Node>, +status: String) -> status_visible_law(key, tag, attrs, styles, events, children, status):
  {==}

def group_production_law(-key: String, -label: String, -role: UI.Role, -project: Nat, -selected: Bool, -expanded: Bool, -source: +List<UI.Node>, -children: +List<Doc.Node>, -visual: Design.Style, -representation: Controls.Representation, -appearances: +List<Design.Appearance>) -> Type:
  {Render.match_node(key, label, role, UI.ProjectGroup{project, selected, expanded}, source, children, visual, representation, appearances) ==
    Doc.Element{key, "div", [Render.property("data-native-key", key), Render.property("data-project", Nat.show(project)), Render.property("data-expanded", Render.boolean(expanded))], Render.style(visual), Nil{}, Render.project_group_children(key, children, appearances, selected, expanded)} : Doc.Node}

def group_production(+key: String, +label: String, +role: UI.Role, +project: Nat, +selected: Bool, +expanded: Bool, +source: +List<UI.Node>, +children: +List<Doc.Node>, +visual: Design.Style, +representation: Controls.Representation, +appearances: +List<Design.Appearance>) -> group_production_law(key, label, role, project, selected, expanded, source, children, visual, representation, appearances):
  {==}

def header_production_law(-key: String, -tag: String, -attrs: +List<Doc.Property>, -styles: +List<Doc.Property>, -events: +List<Doc.Event>, -children: +List<Doc.Node>, -appearances: +List<Design.Appearance>, -selected: Bool, -expanded: Bool) -> Type:
  {Render.project_header_node(Doc.Element{key, tag, attrs, styles, events, children}, appearances, selected, expanded) ==
    Doc.Element{key, tag, List.append(&2, Doc.Property, attrs, [Render.property("class", "native-surface")]), Render.pointer_styles(styles), events, children} : Doc.Node}

def header_production(+key: String, +tag: String, +attrs: +List<Doc.Property>, +styles: +List<Doc.Property>, +events: +List<Doc.Event>, +children: +List<Doc.Node>, +appearances: +List<Design.Appearance>, +selected: Bool, +expanded: Bool) -> header_production_law(key, tag, attrs, styles, events, children, appearances, selected, expanded):
  {==}

def disclosure_typed_law(-project: Nat) -> Type:
  {Controls.project_control_input(Core.ApplicationInput{Experience.UserInput{User.Activate{User.ToggleProjectGroup{project}}}}) == Controls.ProjectDisclosure{} : Controls.ProjectControl}

def disclosure_typed(+project: Nat) -> disclosure_typed_law(project):
  {==}

def name_typed_law(-project: Maybe<&2, Nat>) -> Type:
  {Controls.project_control_input(Core.ApplicationInput{Experience.UserInput{User.Activate{User.SelectProject{project}}}}) == Controls.ProjectName{} : Controls.ProjectControl}

def name_typed(+project: Maybe<&2, Nat>) -> name_typed_law(project):
  {==}

def create_typed_law(-project: Maybe<&2, Nat>) -> Type:
  {Controls.project_control_input(Core.ApplicationInput{Experience.UserInput{User.Activate{User.BeginTask{project}}}}) == Controls.ProjectCreate{} : Controls.ProjectControl}

def create_typed(+project: Maybe<&2, Nat>) -> create_typed_law(project):
  {==}

def more_typed_law(-project: Nat, -trigger: String) -> Type:
  {Controls.project_control_input(Core.ApplicationInput{Experience.UserInput{User.Activate{User.OpenPanel{User.ObjectActions{User.ProjectSubject{project}}, trigger}}}}) == Controls.ProjectMore{} : Controls.ProjectControl}

def more_typed(+project: Nat, +trigger: String) -> more_typed_law(project, trigger):
  {==}

def disclosure_face_law(-name: String, -expanded: Bool, -fallback: Controls.Face) -> Type:
  {Controls.project_face(Controls.ProjectDisclosure{}, name, expanded, fallback) == Controls.IconFace{Controls.project_chevron(expanded)} : Controls.Face}

def disclosure_face(+name: String, +expanded: Bool, +fallback: Controls.Face) -> disclosure_face_law(name, expanded, fallback):
  {==}

def name_single_face_law(-key: String, -name: String) -> Type:
  {Render.face(key, Controls.SingleLineFace{name}) == [Doc.Text{name}] : +List<Doc.Node>}

def name_single_face(+key: String, +name: String) -> name_single_face_law(key, name):
  {==}

def complete_action_projection_law(-area: Controls.Area, -family: Controls.SourceFamily, -input: Core.Input, -availability: View.Availability, -name: String, -face: Controls.Face, -behavior: Controls.Behavior, -geometry: Controls.Geometry, -placement: Controls.Placement, -help: Controls.Help, -feedback: Controls.Feedback) -> Type:
  {Controls.source_action(area, family, Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}) ==
    projected_action(input, availability, name, Controls.source_presentation(area, family, input, name, face, behavior, geometry), placement, help, feedback) : Controls.Representation}

def complete_action_projection(+area: Controls.Area, +family: Controls.SourceFamily, +input: Core.Input, +availability: View.Availability, +name: String, +face: Controls.Face, +behavior: Controls.Behavior, +geometry: Controls.Geometry, +placement: Controls.Placement, +help: Controls.Help, +feedback: Controls.Feedback) -> complete_action_projection_law(area, family, input, availability, name, face, behavior, geometry, placement, help, feedback):
  projection_construction(input, availability, name, Controls.source_presentation(area, family, input, name, face, behavior, geometry), placement, help, feedback)


def disclosure_geometry_law(-width: Nat, -height: Nat, -icon: Nat, -radius: Nat, -leading: Nat) -> Type:
  {Controls.project_geometry(Controls.ProjectDisclosure{}, Controls.Geometry{width, height, icon, radius, leading}) == Controls.Geometry{24n, 24n, icon, radius, leading} : Controls.Geometry}

def disclosure_geometry(+width: Nat, +height: Nat, +icon: Nat, +radius: Nat, +leading: Nat) -> disclosure_geometry_law(width, height, icon, radius, leading):
  {==}

def create_geometry_law(-width: Nat, -height: Nat, -icon: Nat, -radius: Nat, -leading: Nat) -> Type:
  {Controls.project_geometry(Controls.ProjectCreate{}, Controls.Geometry{width, height, icon, radius, leading}) == Controls.Geometry{28n, 28n, icon, radius, leading} : Controls.Geometry}

def create_geometry(+width: Nat, +height: Nat, +icon: Nat, +radius: Nat, +leading: Nat) -> create_geometry_law(width, height, icon, radius, leading):
  {==}

def more_geometry_law(-width: Nat, -height: Nat, -icon: Nat, -radius: Nat, -leading: Nat) -> Type:
  {Controls.project_geometry(Controls.ProjectMore{}, Controls.Geometry{width, height, icon, radius, leading}) == Controls.Geometry{28n, 28n, icon, radius, leading} : Controls.Geometry}

def more_geometry(+width: Nat, +height: Nat, +icon: Nat, +radius: Nat, +leading: Nat) -> more_geometry_law(width, height, icon, radius, leading):
  {==}

def name_geometry_law(-visual: Design.Style) -> Type:
  {label_properties(Appearance.project_label_style(visual)) == (Design.BlockFlow{}, (Design.SingleLineOverflow{}, (0n, 0n))) : (Design.Flow & (Design.Overflow & (Nat & Nat)))}

def name_geometry(+visual: Design.Style) -> name_geometry_law(visual):
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
  Design.Chrome{foreground, background, border, width, radius, shadow} = chrome
  {==}

def task_production_law(-key: String, -label: String, -role: UI.Role, -task: Nat, -status: String, -selected: Bool, -source: +List<UI.Node>, -children: +List<Doc.Node>, -visual: Design.Style, -representation: Controls.Representation, -appearances: +List<Design.Appearance>) -> Type:
  {Render.match_node(key, label, role, UI.TaskRow{task, status, selected}, source, children, visual, representation, appearances) ==
    Doc.Element{key, "div", [Render.property("data-native-key", key), Render.property("data-task", Nat.show(task)), Render.property("data-status", status), Render.property("class", "native-surface")], Render.pointer_styles(Render.style(visual)), Nil{}, Render.task_row_children(children, appearances, status)} : Doc.Node}

def task_production(+key: String, +label: String, +role: UI.Role, +task: Nat, +status: String, +selected: Bool, +source: +List<UI.Node>, +children: +List<Doc.Node>, +visual: Design.Style, +representation: Controls.Representation, +appearances: +List<Design.Appearance>) -> task_production_law(key, label, role, task, status, selected, source, children, visual, representation, appearances):
  {==}

def chooser_production_law(-key: String, -label: String, -role: UI.Role, -selected: Maybe<&2, Nat>, -source: +List<UI.Node>, -children: +List<Doc.Node>, -visual: Design.Style, -representation: Controls.Representation, -appearances: +List<Design.Appearance>) -> Type:
  {Render.match_node(key, label, role, UI.ProjectChooser{selected}, source, children, visual, representation, appearances) ==
    Doc.Element{key, "div", [Render.property("data-native-key", key)], Render.style(visual), Nil{}, children} : Doc.Node}

def chooser_production(+key: String, +label: String, +role: UI.Role, +selected: Maybe<&2, Nat>, +source: +List<UI.Node>, +children: +List<Doc.Node>, +visual: Design.Style, +representation: Controls.Representation, +appearances: +List<Design.Appearance>) -> chooser_production_law(key, label, role, selected, source, children, visual, representation, appearances):
  {==}

def chevron_paths_law() -> Type:
  {(Render.icon_path(Controls.ChevronRight{}), Render.icon_path(Controls.ChevronDown{})) == ("M7.5 4.5 L13 10 L7.5 15.5", "M4.5 7.5 L10 13 L15.5 7.5") : String & String}

def chevron_paths() -> chevron_paths_law():
  {==}

def chooser_value_binding_law(-trigger: String, -name: String, -face: Controls.Face, -behavior: Controls.Behavior, -geometry: Controls.Geometry) -> Type:
  {Controls.chooser_presentation(Core.ApplicationInput{Experience.UserInput{User.Activate{User.OpenPanel{User.ProjectPicker{}, trigger}}}}, name, face, behavior, geometry) == Controls.ActionPresentation{Controls.PickerFace{Some{Controls.Folder{}}, name}, behavior, geometry} : Controls.ActionPresentation}

def chooser_value_binding(+trigger: String, +name: String, +face: Controls.Face, +behavior: Controls.Behavior, +geometry: Controls.Geometry) -> chooser_value_binding_law(trigger, name, face, behavior, geometry):
  {==}

def create_face_law(-name: String, -expanded: Bool, -fallback: Controls.Face) -> Type:
  {Controls.project_face(Controls.ProjectCreate{}, name, expanded, fallback) == Controls.IconFace{Controls.Plus{}} : Controls.Face}

def create_face(+name: String, +expanded: Bool, +fallback: Controls.Face) -> create_face_law(name, expanded, fallback):
  {==}

def more_face_law(-name: String, -expanded: Bool, -fallback: Controls.Face) -> Type:
  {Controls.project_face(Controls.ProjectMore{}, name, expanded, fallback) == Controls.IconFace{Controls.MoreDots{}} : Controls.Face}

def more_face(+name: String, +expanded: Bool, +fallback: Controls.Face) -> more_face_law(name, expanded, fallback):
  {==}

def children_indent_law(-node: Doc.Node, -appearances: +List<Design.Appearance>, -selected: Bool, -expanded: Bool) -> Type:
  {Render.project_child(False{}, node, appearances, selected, expanded) == Render.replace_styles(node, [Render.property("margin-inline-start", "20px")]) : Doc.Node}

def children_indent(+node: Doc.Node, +appearances: +List<Design.Appearance>, +selected: Bool, +expanded: Bool) -> children_indent_law(node, appearances, selected, expanded):
  {==}

def chooser_draft_observation_law(-id: Nat, -fallback: Design.Style) -> Type:
  {creation_heading_observed(Appearance.chooser_style(Some{id}, fallback)) == Appearance.creation_heading_text() : Design.TextStyle}

def chooser_draft_observation(+id: Nat, +fallback: Design.Style) -> chooser_draft_observation_law(id, fallback):
  Design.Style{text, Design.Chrome{foreground, background, border, width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = fallback
  {==}

def source_group_style_law(-key: String, -context: Controls.Context, -representation: Controls.Representation, -fallback: Design.Style, -project: Nat, -selected: Bool, -expanded: Bool) -> Type:
  {Appearance.final_style(key, UI.ProjectGroup{project, selected, expanded}, context, representation, fallback) == Appearance.project_group_style() : Design.Style}

def source_group_style(+key: String, +context: Controls.Context, +representation: Controls.Representation, +fallback: Design.Style, +project: Nat, +selected: Bool, +expanded: Bool) -> source_group_style_law(key, context, representation, fallback, project, selected, expanded):
  {==}

def source_task_style_law(-key: String, -context: Controls.Context, -representation: Controls.Representation, -fallback: Design.Style, -task: Nat, -status: String, -selected: Bool) -> Type:
  {Appearance.final_style(key, UI.TaskRow{task, status, selected}, context, representation, fallback) == Appearance.navigation_family_style(selected, 6n, 5n) : Design.Style}

def source_task_style(+key: String, +context: Controls.Context, +representation: Controls.Representation, +fallback: Design.Style, +task: Nat, +status: String, +selected: Bool) -> source_task_style_law(key, context, representation, fallback, task, status, selected):
  {==}

def first_control(values: +List<Design.Appearance>) -> Controls.Representation:
  match values:
    case Nil{}: Controls.NoControl{}
    case Con{Design.Appearance{key, visual, control, children}, rest}: control

def project_reference_law(-key: String, -role: UI.Role, -context: Controls.Context, -project: Nat, -selected: Bool, -expanded: Bool) -> Type:
  {Controls.source_reference(Controls.enter(key, role, UI.ProjectGroup{project, selected, expanded}, context)) == Controls.SourceFamily{key, UI.ProjectGroup{project, selected, expanded}} : Controls.SourceFamily}

def project_reference(+key: String, +role: UI.Role, +context: Controls.Context, +project: Nat, +selected: Bool, +expanded: Bool) -> project_reference_law(key, role, context, project, selected, expanded):
  Controls.Context{area, selection, code, appearance, access, open, layers, execution, family} = context
  {==}

def task_reference_law(-key: String, -role: UI.Role, -context: Controls.Context, -task: Nat, -status: String, -selected: Bool) -> Type:
  {Controls.source_reference(Controls.enter(key, role, UI.TaskRow{task, status, selected}, context)) == Controls.SourceFamily{key, UI.TaskRow{task, status, selected}} : Controls.SourceFamily}

def task_reference(+key: String, +role: UI.Role, +context: Controls.Context, +task: Nat, +status: String, +selected: Bool) -> task_reference_law(key, role, context, task, status, selected):
  Controls.Context{area, selection, code, appearance, access, open, layers, execution, family} = context
  {==}

def chooser_reference_law(-key: String, -role: UI.Role, -context: Controls.Context, -selected: Maybe<&2, Nat>) -> Type:
  {Controls.source_reference(Controls.enter(key, role, UI.ProjectChooser{selected}, context)) == Controls.SourceFamily{key, UI.ProjectChooser{selected}} : Controls.SourceFamily}

def chooser_reference(+key: String, +role: UI.Role, +context: Controls.Context, +selected: Maybe<&2, Nat>) -> chooser_reference_law(key, role, context, selected):
  Controls.Context{area, selection, code, appearance, access, open, layers, execution, family} = context
  {==}

def complete_control_binding_law(-key: String, -semantic: String, -label: String, -role: UI.Role, -meaning: UI.Meaning, -children: +List<UI.Node>, -context: Controls.Context) -> Type:
  {first_control(Appearance.nodes_at([UI.Node{key, semantic, label, role, meaning, children}], context)) == Controls.represent(key, meaning, label, role, Controls.enter(key, role, meaning, context)) : Controls.Representation}

def complete_control_binding(+key: String, +semantic: String, +label: String, +role: UI.Role, +meaning: UI.Meaning, +children: +List<UI.Node>, +context: Controls.Context) -> complete_control_binding_law(key, semantic, label, role, meaning, children, context):
  {==}

def actual_header_style_law(-key: String, -owner: String, -project: Nat, -selected: Bool, -expanded: Bool, -area: Controls.Area, -selection: Controls.Selection, -code: Maybe<&2, Code.Scene>, -appearance: Services.Appearance, -access: Services.Access, -open: Bool, -layers: +List<View.Layer>, -execution: Maybe<&2, Workspace.Observation>, -representation: Controls.Representation, -fallback: Design.Style) -> Type:
  {Appearance.final_style(key, UI.Region{}, Controls.Context{area, selection, code, appearance, access, open, layers, execution, Controls.SourceFamily{owner, UI.ProjectGroup{project, selected, expanded}}}, representation, fallback) ==
    Appearance.source_style(String.eq(key, owner ++ "/actions"), Controls.SourceFamily{owner, UI.ProjectGroup{project, selected, expanded}}, fallback) : Design.Style}

def actual_header_style(+key: String, +owner: String, +project: Nat, +selected: Bool, +expanded: Bool, +area: Controls.Area, +selection: Controls.Selection, +code: Maybe<&2, Code.Scene>, +appearance: Services.Appearance, +access: Services.Access, +open: Bool, +layers: +List<View.Layer>, +execution: Maybe<&2, Workspace.Observation>, +representation: Controls.Representation, +fallback: Design.Style) -> actual_header_style_law(key, owner, project, selected, expanded, area, selection, code, appearance, access, open, layers, execution, representation, fallback):
  {==}

type Requirements is Type:
  Requirements{
    group_production: @+key:String -> @+label:String -> @+role:UI.Role -> @+project:Nat -> @+selected:Bool -> @+expanded:Bool -> @+source:+List<UI.Node> -> @+children:+List<Doc.Node> -> @+visual:Design.Style -> @+representation:Controls.Representation -> @+appearances:+List<Design.Appearance> -> group_production_law(key, label, role, project, selected, expanded, source, children, visual, representation, appearances),
    header_production: @+key:String -> @+tag:String -> @+attrs:+List<Doc.Property> -> @+styles:+List<Doc.Property> -> @+events:+List<Doc.Event> -> @+children:+List<Doc.Node> -> @+appearances:+List<Design.Appearance> -> @+selected:Bool -> @+expanded:Bool -> header_production_law(key, tag, attrs, styles, events, children, appearances, selected, expanded),
    disclosure_typed: @+project:Nat -> disclosure_typed_law(project),
    name_typed: @+project:Maybe<&2, Nat> -> name_typed_law(project),
    create_typed: @+project:Maybe<&2, Nat> -> create_typed_law(project),
    more_typed: @+project:Nat -> @+trigger:String -> more_typed_law(project, trigger),
    disclosure_face: @+name:String -> @+expanded:Bool -> @+fallback:Controls.Face -> disclosure_face_law(name, expanded, fallback),
    name_single_face: @+key:String -> @+name:String -> name_single_face_law(key, name),
    complete_action_projection: @+area:Controls.Area -> @+family:Controls.SourceFamily -> @+input:Core.Input -> @+availability:View.Availability -> @+name:String -> @+face:Controls.Face -> @+behavior:Controls.Behavior -> @+geometry:Controls.Geometry -> @+placement:Controls.Placement -> @+help:Controls.Help -> @+feedback:Controls.Feedback -> complete_action_projection_law(area, family, input, availability, name, face, behavior, geometry, placement, help, feedback),
    disclosure_geometry: @+width:Nat -> @+height:Nat -> @+icon:Nat -> @+radius:Nat -> @+leading:Nat -> disclosure_geometry_law(width, height, icon, radius, leading),
    create_geometry: @+width:Nat -> @+height:Nat -> @+icon:Nat -> @+radius:Nat -> @+leading:Nat -> create_geometry_law(width, height, icon, radius, leading),
    more_geometry: @+width:Nat -> @+height:Nat -> @+icon:Nat -> @+radius:Nat -> @+leading:Nat -> more_geometry_law(width, height, icon, radius, leading),
    name_geometry: @+visual:Design.Style -> name_geometry_law(visual),
    task_production: @+key:String -> @+label:String -> @+role:UI.Role -> @+task:Nat -> @+status:String -> @+selected:Bool -> @+source:+List<UI.Node> -> @+children:+List<Doc.Node> -> @+visual:Design.Style -> @+representation:Controls.Representation -> @+appearances:+List<Design.Appearance> -> task_production_law(key, label, role, task, status, selected, source, children, visual, representation, appearances),
    chooser_production: @+key:String -> @+label:String -> @+role:UI.Role -> @+selected:Maybe<&2, Nat> -> @+source:+List<UI.Node> -> @+children:+List<Doc.Node> -> @+visual:Design.Style -> @+representation:Controls.Representation -> @+appearances:+List<Design.Appearance> -> chooser_production_law(key, label, role, selected, source, children, visual, representation, appearances),
    chevron_paths: chevron_paths_law(),
    chooser_value_binding: @+trigger:String -> @+name:String -> @+face:Controls.Face -> @+behavior:Controls.Behavior -> @+geometry:Controls.Geometry -> chooser_value_binding_law(trigger, name, face, behavior, geometry),
    create_face: @+name:String -> @+expanded:Bool -> @+fallback:Controls.Face -> create_face_law(name, expanded, fallback),
    more_face: @+name:String -> @+expanded:Bool -> @+fallback:Controls.Face -> more_face_law(name, expanded, fallback),
    children_indent: @+node:Doc.Node -> @+appearances:+List<Design.Appearance> -> @+selected:Bool -> @+expanded:Bool -> children_indent_law(node, appearances, selected, expanded),
    chooser_draft_observation: @+id:Nat -> @+fallback:Design.Style -> chooser_draft_observation_law(id, fallback),
    source_group_style: @+key:String -> @+context:Controls.Context -> @+representation:Controls.Representation -> @+fallback:Design.Style -> @+project:Nat -> @+selected:Bool -> @+expanded:Bool -> source_group_style_law(key, context, representation, fallback, project, selected, expanded),
    source_task_style: @+key:String -> @+context:Controls.Context -> @+representation:Controls.Representation -> @+fallback:Design.Style -> @+task:Nat -> @+status:String -> @+selected:Bool -> source_task_style_law(key, context, representation, fallback, task, status, selected),
    project_reference: @+key:String -> @+role:UI.Role -> @+context:Controls.Context -> @+project:Nat -> @+selected:Bool -> @+expanded:Bool -> project_reference_law(key, role, context, project, selected, expanded),
    task_reference: @+key:String -> @+role:UI.Role -> @+context:Controls.Context -> @+task:Nat -> @+status:String -> @+selected:Bool -> task_reference_law(key, role, context, task, status, selected),
    chooser_reference: @+key:String -> @+role:UI.Role -> @+context:Controls.Context -> @+selected:Maybe<&2, Nat> -> chooser_reference_law(key, role, context, selected),
    complete_control_binding: @+key:String -> @+semantic:String -> @+label:String -> @+role:UI.Role -> @+meaning:UI.Meaning -> @+children:+List<UI.Node> -> @+context:Controls.Context -> complete_control_binding_law(key, semantic, label, role, meaning, children, context),
    actual_header_style: @+key:String -> @+owner:String -> @+project:Nat -> @+selected:Bool -> @+expanded:Bool -> @+area:Controls.Area -> @+selection:Controls.Selection -> @+code:Maybe<&2, Code.Scene> -> @+appearance:Services.Appearance -> @+access:Services.Access -> @+open:Bool -> @+layers:+List<View.Layer> -> @+execution:Maybe<&2, Workspace.Observation> -> @+representation:Controls.Representation -> @+fallback:Design.Style -> actual_header_style_law(key, owner, project, selected, expanded, area, selection, code, appearance, access, open, layers, execution, representation, fallback),
    status_visible: @+key:String -> @+tag:String -> @+attrs:+List<Doc.Property> -> @+styles:+List<Doc.Property> -> @+events:+List<Doc.Event> -> @children:+List<Doc.Node> -> @+status:String -> status_visible_law(key, tag, attrs, styles, events, children, status)}

def evidence() -> Requirements:
  Requirements{group_production, header_production, disclosure_typed, name_typed, create_typed, more_typed, disclosure_face, name_single_face, complete_action_projection, disclosure_geometry, create_geometry, more_geometry, name_geometry, task_production, chooser_production, chevron_paths(), chooser_value_binding, create_face, more_face, children_indent, chooser_draft_observation, source_group_style, source_task_style, project_reference, task_reference, chooser_reference, complete_control_binding, actual_header_style, status_visible}
