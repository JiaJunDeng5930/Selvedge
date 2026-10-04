import Base
import ./typography.bend as T
import ./enclosure.bend as Enclosure
import ./appearance.bend as Appearance
import ./document.bend as Doc
import ./renderer.bend as Render
import ../core/field-options.bend as Options
import ./design.bend as Design
import ./controls.bend as Controls
import ../core/interface.bend as UI
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






















































def name_geometry_law(-visual: Design.Style) -> Type:
  {label_properties(Appearance.project_label_style(visual)) == (Design.BlockFlow{}, (Design.SingleLineOverflow{}, (0n, 0n))) : (Design.Flow & (Design.Overflow & (Nat & Nat)))}

def name_geometry(+visual: Design.Style) -> name_geometry_law(visual):
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
  Design.Chrome{foreground, background, border, width, radius, shadow} = chrome
  {==}





























def chooser_draft_observation_law(-id: Nat, -fallback: Design.Style) -> Type:
  {Design.style_text(Appearance.chooser_style(Some{id}, fallback)) == Design.style_text(fallback) : T.Presentation}

def chooser_draft_observation(+id: Nat, +fallback: Design.Style) -> chooser_draft_observation_law(id, fallback):
  Design.Style{text, Design.Chrome{foreground, background, border, width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = fallback
  {==}









def first_control(values: +List<Design.Node>) -> Controls.Representation:
  match values:
    case Nil{}: Controls.NoControl{}
    case Con{Design.Node{key, semantic, label, role, meaning, visual, control, children}, rest}: control

def project_reference_law(-key: String, -semantic: String, -label: String, -role: UI.Role, -children: +List<UI.Node>, -context: Controls.Context, -project: Nat, -selected: Bool, -expanded: Bool) -> Type:
  {Controls.source_reference(Controls.enter(UI.Node{key, semantic, label, role, UI.ProjectGroup{project, selected, expanded}, children}, context)) == Controls.SourceFamily{UI.Node{key, semantic, label, role, UI.ProjectGroup{project, selected, expanded}, children}} : Controls.SourceFamily}

def project_reference(+key: String, +semantic: String, +label: String, +role: UI.Role, +children: +List<UI.Node>, +context: Controls.Context, +project: Nat, +selected: Bool, +expanded: Bool) -> project_reference_law(key, semantic, label, role, children, context, project, selected, expanded):
  Controls.Context{area, selection, code, appearance, access, open, layers, execution, family} = context
  {==}

def task_reference_law(-key: String, -semantic: String, -label: String, -role: UI.Role, -children: +List<UI.Node>, -context: Controls.Context, -task: Nat, -status: String, -selected: Bool) -> Type:
  {Controls.source_reference(Controls.enter(UI.Node{key, semantic, label, role, UI.TaskRow{task, status, selected}, children}, context)) == Controls.SourceFamily{UI.Node{key, semantic, label, role, UI.TaskRow{task, status, selected}, children}} : Controls.SourceFamily}

def task_reference(+key: String, +semantic: String, +label: String, +role: UI.Role, +children: +List<UI.Node>, +context: Controls.Context, +task: Nat, +status: String, +selected: Bool) -> task_reference_law(key, semantic, label, role, children, context, task, status, selected):
  Controls.Context{area, selection, code, appearance, access, open, layers, execution, family} = context
  {==}

def chooser_reference_law(-key: String, -semantic: String, -label: String, -role: UI.Role, -children: +List<UI.Node>, -context: Controls.Context, -selected: Maybe<&2, Nat>) -> Type:
  {Controls.source_reference(Controls.enter(UI.Node{key, semantic, label, role, UI.ProjectChooser{selected}, children}, context)) == Controls.SourceFamily{UI.Node{key, semantic, label, role, UI.ProjectChooser{selected}, children}} : Controls.SourceFamily}

def chooser_reference(+key: String, +semantic: String, +label: String, +role: UI.Role, +children: +List<UI.Node>, +context: Controls.Context, +selected: Maybe<&2, Nat>) -> chooser_reference_law(key, semantic, label, role, children, context, selected):
  Controls.Context{area, selection, code, appearance, access, open, layers, execution, family} = context
  {==}









type Requirements is Type:
  Requirements{
    group_production: @+key:String -> @+semantic:String -> @+label:String -> @+role:UI.Role -> @+project:Nat -> @+selected:Bool -> @+expanded:Bool -> @+children:+List<Design.Node> -> @+visual:Design.Style -> @+representation:Controls.Representation -> {Render.match_node(Design.Node{key, semantic, label, role, UI.ProjectGroup{project, selected, expanded}, visual, representation, children}, Render.render_children(children)) ==
        Doc.Element{key, "div", [Render.property("data-native-key", key), Render.property("data-project", Nat.show(project)), Render.property("data-expanded", Options.boolean(expanded))], Render.style(visual), Nil{}, Render.project_group_children(key, Render.render_children(children), selected, expanded)} : Doc.Node},
    header_production: @+key:String -> @+tag:String -> @+attrs:+List<Doc.Property> -> @+styles:+List<Doc.Property> -> @+events:+List<Doc.Event> -> @+children:+List<Doc.Node> -> {Render.project_header_node(Doc.Element{key, tag, attrs, styles, events, children}) ==
        Doc.Element{key, tag, List.append(&2, Doc.Property, attrs, [Render.property("class", "native-surface")]), Render.pointer_styles(styles), events, children} : Doc.Node},
    disclosure_typed: @+project:Nat -> {Controls.project_control_input(Core.ApplicationInput{Experience.UserInput{User.Activate{User.ToggleProjectGroup{project}}}}) == Controls.ProjectDisclosure{} : Controls.ProjectControl},
    name_typed: @+project:Maybe<&2, Nat> -> {Controls.project_control_input(Core.ApplicationInput{Experience.UserInput{User.Activate{User.SelectProject{project}}}}) == Controls.ProjectName{} : Controls.ProjectControl},
    create_typed: @+project:Maybe<&2, Nat> -> {Controls.project_control_input(Core.ApplicationInput{Experience.UserInput{User.Activate{User.BeginTask{project}}}}) == Controls.ProjectCreate{} : Controls.ProjectControl},
    more_typed: @+project:Nat -> @+trigger:String -> {Controls.project_control_input(Core.ApplicationInput{Experience.UserInput{User.Activate{User.OpenPanel{User.ObjectActions{User.ProjectSubject{project}}, trigger}}}}) == Controls.ProjectMore{} : Controls.ProjectControl},
    disclosure_face: @+name:String -> @+expanded:Bool -> @+fallback:Controls.Face -> {Controls.project_face(Controls.ProjectDisclosure{}, name, expanded, fallback) == Controls.IconFace{Controls.project_chevron(expanded)} : Controls.Face},
    name_single_face: @+typography:T.Presentation -> @geometry:Controls.Geometry -> @+key:String -> @+name:String -> {Render.face(key, Controls.SingleLineFace{name}, typography, geometry) == [Doc.Text{name}] : +List<Doc.Node>},
    complete_action_projection: @+area:Controls.Area -> @+family:Controls.SourceFamily -> @+input:Core.Input -> @+availability:View.Availability -> @+name:String -> @+face:Controls.Face -> @+behavior:Controls.Behavior -> @+geometry:Controls.Geometry -> @+placement:Controls.Placement -> @+help:Controls.Help -> @+feedback:Controls.Feedback -> {Controls.source_action(area, family, Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}) ==
        projected_action(input, availability, name, Controls.source_presentation(area, family, input, name, face, behavior, geometry), placement, help, feedback) : Controls.Representation},
    disclosure_geometry: @+width:Nat -> @+height:Nat -> @+icon:Nat -> @+radius:Nat -> @+leading:Nat -> {Controls.project_geometry(Controls.ProjectDisclosure{}, Controls.Geometry{width, height, icon, radius, leading}) == Controls.Geometry{24n, 24n, icon, radius, leading} : Controls.Geometry},
    create_geometry: @+width:Nat -> @+height:Nat -> @+icon:Nat -> @+radius:Nat -> @+leading:Nat -> {Controls.project_geometry(Controls.ProjectCreate{}, Controls.Geometry{width, height, icon, radius, leading}) == Controls.Geometry{28n, 28n, icon, radius, leading} : Controls.Geometry},
    more_geometry: @+width:Nat -> @+height:Nat -> @+icon:Nat -> @+radius:Nat -> @+leading:Nat -> {Controls.project_geometry(Controls.ProjectMore{}, Controls.Geometry{width, height, icon, radius, leading}) == Controls.Geometry{28n, 28n, icon, radius, leading} : Controls.Geometry},
    name_geometry: @+visual:Design.Style -> name_geometry_law(visual),
    task_production: @+key:String -> @+semantic:String -> @+label:String -> @+role:UI.Role -> @+task:Nat -> @+status:String -> @+selected:Bool -> @+children:+List<Design.Node> -> @+visual:Design.Style -> @+representation:Controls.Representation -> {Render.match_node(Design.Node{key, semantic, label, role, UI.TaskRow{task, status, selected}, visual, representation, children}, Render.render_children(children)) ==
        Doc.Element{key, "div", [Render.property("data-native-key", key), Render.property("data-task", Nat.show(task)), Render.property("data-status", status), Render.property("class", "native-surface")], Render.pointer_styles(Render.style(visual)), Nil{}, Render.task_row_children(Render.render_children(children), status, Design.style_text(visual))} : Doc.Node},
    chooser_production: @+key:String -> @+semantic:String -> @+label:String -> @+role:UI.Role -> @+selected:Maybe<&2, Nat> -> @+children:+List<Design.Node> -> @+visual:Design.Style -> @+representation:Controls.Representation -> {Render.match_node(Design.Node{key, semantic, label, role, UI.ProjectChooser{selected}, visual, representation, children}, Render.render_children(children)) ==
        Doc.Element{key, "div", [Render.property("data-native-key", key)], Render.style(visual), Nil{}, Render.documents(Render.render_children(children))} : Doc.Node},
    chevron_paths: {(Render.icon_path(Controls.ChevronRight{}), Render.icon_path(Controls.ChevronDown{})) == ("M7.5 4.5 L13 10 L7.5 15.5", "M4.5 7.5 L10 13 L15.5 7.5") : String & String},
    chooser_value_binding: @+trigger:String -> @+name:String -> @+face:Controls.Face -> @+behavior:Controls.Behavior -> @+geometry:Controls.Geometry -> {Controls.chooser_presentation(Core.ApplicationInput{Experience.UserInput{User.Activate{User.OpenPanel{User.ProjectPicker{}, trigger}}}}, name, face, behavior, geometry) == Controls.ActionPresentation{Controls.PickerFace{Some{Controls.Folder{}}, name}, behavior, geometry} : Controls.ActionPresentation},
    create_face: @+name:String -> @+expanded:Bool -> @+fallback:Controls.Face -> {Controls.project_face(Controls.ProjectCreate{}, name, expanded, fallback) == Controls.IconFace{Controls.Plus{}} : Controls.Face},
    more_face: @+name:String -> @+expanded:Bool -> @+fallback:Controls.Face -> {Controls.project_face(Controls.ProjectMore{}, name, expanded, fallback) == Controls.IconFace{Controls.MoreDots{}} : Controls.Face},
    children_indent: @+node:Doc.Node -> {Render.project_child(False{}, node) == Render.replace_styles(node, [Render.property("margin-inline-start", "20px")]) : Doc.Node},
    chooser_draft_observation: @+id:Nat -> @+fallback:Design.Style -> chooser_draft_observation_law(id, fallback),
    source_group_style: @+typography:T.Presentation -> @+key:String -> @+context:Controls.Context -> @+representation:Controls.Representation -> @+fallback:Design.Style -> @+project:Nat -> @+selected:Bool -> @+expanded:Bool -> {Appearance.final_style(key, UI.ProjectGroup{project, selected, expanded}, context, representation, fallback, typography) == Appearance.project_group_style(typography) : Design.Style},
    source_task_style: @+typography:T.Presentation -> @+key:String -> @+context:Controls.Context -> @+representation:Controls.Representation -> @+fallback:Design.Style -> @+task:Nat -> @+status:String -> @+selected:Bool -> {Appearance.final_style(key, UI.TaskRow{task, status, selected}, context, representation, fallback, typography) == Appearance.navigation_family_style(selected, 6n, 5n, typography) : Design.Style},
    project_reference: @+key:String -> @+semantic:String -> @+label:String -> @+role:UI.Role -> @+children:+List<UI.Node> -> @+context:Controls.Context -> @+project:Nat -> @+selected:Bool -> @+expanded:Bool -> project_reference_law(key, semantic, label, role, children, context, project, selected, expanded),
    task_reference: @+key:String -> @+semantic:String -> @+label:String -> @+role:UI.Role -> @+children:+List<UI.Node> -> @+context:Controls.Context -> @+task:Nat -> @+status:String -> @+selected:Bool -> task_reference_law(key, semantic, label, role, children, context, task, status, selected),
    chooser_reference: @+key:String -> @+semantic:String -> @+label:String -> @+role:UI.Role -> @+children:+List<UI.Node> -> @+context:Controls.Context -> @+selected:Maybe<&2, Nat> -> chooser_reference_law(key, semantic, label, role, children, context, selected),
    complete_control_binding: @+typography:T.Presentation -> @+in_main:Bool -> @+start:Bool -> @+key:String -> @+semantic:String -> @+label:String -> @+role:UI.Role -> @+meaning:UI.Meaning -> @+children:+List<UI.Node> -> @+context:Controls.Context -> {first_control(Appearance.nodes_at([UI.Node{key, semantic, label, role, meaning, children}], context, typography, in_main, start)) == Controls.represent(key, meaning, label, role, Controls.enter(UI.Node{key, semantic, label, role, meaning, children}, context)) : Controls.Representation},
    actual_header_style: @+typography:T.Presentation -> @+key:String -> @+owner:String -> @+owner_semantic:String -> @+owner_label:String -> @+owner_role:UI.Role -> @+owner_children:+List<UI.Node> -> @+project:Nat -> @+selected:Bool -> @+expanded:Bool -> @+area:Controls.Area -> @+selection:Controls.Selection -> @+code:Maybe<&2, Code.Scene> -> @+appearance:Services.Appearance -> @+access:Services.Access -> @+open:Bool -> @+layers:+List<View.Layer> -> @+execution:Maybe<&2, Workspace.Observation> -> @+representation:Controls.Representation -> @+fallback:Design.Style -> {Appearance.final_style(key, UI.Region{}, Controls.Context{area, selection, code, appearance, access, open, layers, execution, Controls.SourceFamily{UI.Node{owner, owner_semantic, owner_label, owner_role, UI.ProjectGroup{project, selected, expanded}, owner_children}}}, representation, fallback, typography) ==
        Appearance.source_style(String.eq(key, owner ++ "/actions"), Controls.SourceFamily{UI.Node{owner, owner_semantic, owner_label, owner_role, UI.ProjectGroup{project, selected, expanded}, owner_children}}, fallback, typography) : Design.Style},
    status_visible: @+typography:T.Presentation -> @+key:String -> @+tag:String -> @+attrs:+List<Doc.Property> -> @+styles:+List<Doc.Property> -> @+events:+List<Doc.Event> -> @children:+List<Doc.Node> -> @+status:String -> {Render.task_status_node(Doc.Element{key, tag, attrs, styles, events, children}, status, typography) ==
          Doc.Element{key, "span", List.append(&2, Doc.Property, attrs, [Render.property("aria-label", status), Render.property("title", status)]),
            List.append(&2, Doc.Property, Render.part_text(typography, T.Support{}, T.Medium{}), [Render.property("display", "inline-flex"), Render.property("flex", "0 0 auto"), Render.property("align-items", "center"), Render.property("gap", "4px"),
             Render.property("order", "-1"), Render.property("color", Render.task_status_tone(status)), Render.property("white-space", "nowrap")]), events,
            [Doc.Element{key ++ "/indicator", "span", [Render.property("aria-hidden", "true")], Nil{}, Nil{}, [Doc.Text{"●"}]}, Doc.Text{status}]} : Doc.Node}}

def evidence() -> Requirements:
  Requirements{+key => +semantic => +label => +role => +project => +selected => +expanded => +children => +visual => +representation => {==}, +key => +tag => +attrs => +styles => +events => +children => {==}, +project => {==}, +project => {==}, +project => {==}, +project => +trigger => {==}, +name => +expanded => +fallback => {==}, +typography => geometry => +key => +name => {==}, +area => +family => +input => +availability => +name => +face => +behavior => +geometry => +placement => +help => +feedback => projection_construction(input, availability, name, Controls.source_presentation(area, family, input, name, face, behavior, geometry), placement, help, feedback), +width => +height => +icon => +radius => +leading => {==}, +width => +height => +icon => +radius => +leading => {==}, +width => +height => +icon => +radius => +leading => {==}, name_geometry,
    +key => +semantic => +label => +role => +task => +status => +selected => +children => +visual => +representation => {==}, +key => +semantic => +label => +role => +selected => +children => +visual => +representation => {==}, {==}, +trigger => +name => +face => +behavior => +geometry => {==}, +name => +expanded => +fallback => {==}, +name => +expanded => +fallback => {==}, +node => {==}, chooser_draft_observation,
    +typography => +key => +context => +representation => +fallback => +project => +selected => +expanded => {==},
    +typography => +key => +context => +representation => +fallback => +task => +status => +selected => {==}, project_reference, task_reference, chooser_reference,
    +typography => +in_main => +start => +key => +semantic => +label => +role => +meaning => +children => +context => {==},
    +typography => +key => +owner => +owner_semantic => +owner_label => +owner_role => +owner_children => +project => +selected => +expanded => +area => +selection => +code => +appearance => +access => +open => +layers => +execution => +representation => +fallback => {==},
    +typography => +key => +tag => +attrs => +styles => +events => children => +status => {==}}
