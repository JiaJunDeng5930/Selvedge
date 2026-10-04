import Base
import ./iconography.bend as Iconography
import ./spatial.bend as SpatialModel
import ./space.bend as Space
import ./typography.bend as T
import ./enclosure.bend as Enclosure
import ./appearance.bend as Appearance
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

def projected_action(input: Core.Input, availability: View.Availability, name: String, projection: Controls.ActionPresentation, placement: Controls.Placement, help: Controls.Help, feedback: Controls.Feedback) -> Controls.Representation:
  Controls.ActionPresentation{face, behavior, geometry} = projection
  Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}

def label_properties(value: Design.Style) -> (SpatialModel.Flow & (SpatialModel.Overflow & (Nat & Nat))):
  Design.Style{text, chrome, alignment, flow, overflow, +frame, minimum, maximum, states} = value
  (flow, (overflow, (Enclosure.inline(Enclosure.frame_content(frame)), Enclosure.block(Enclosure.frame_content(frame)))))

def name_geometry_law(-visual: Design.Style) -> Type:
  {label_properties(Appearance.project_label_style(visual)) == (SpatialModel.BlockFlow{}, (SpatialModel.SingleLineOverflow{}, (0n, 0n))) : (SpatialModel.Flow & (SpatialModel.Overflow & (Nat & Nat)))}

def chooser_draft_observation_law(-id: Nat, -fallback: Design.Style) -> Type:
  {Design.style_text(Appearance.chooser_style(Some{id}, fallback)) == Design.style_text(fallback) : T.Presentation}

def first_control(values: +List<Design.Node>) -> Controls.Representation:
  match values:
    case Nil{}: Controls.NoControl{}
    case Con{Design.Node{key, semantic, label, role, meaning, visual, control, children}, rest}: control

def project_reference_law(-key: String, -semantic: String, -label: String, -role: UI.Role, -children: +List<UI.Node>, -context: Controls.Context, -project: Nat, -selected: Bool, -expanded: Bool) -> Type:
  {Controls.source_reference(Controls.enter(UI.Node{key, semantic, label, role, UI.ProjectGroup{project, selected, expanded}, children}, context)) == Controls.SourceFamily{UI.Node{key, semantic, label, role, UI.ProjectGroup{project, selected, expanded}, children}} : Controls.SourceFamily}

def task_reference_law(-key: String, -semantic: String, -label: String, -role: UI.Role, -children: +List<UI.Node>, -context: Controls.Context, -task: Nat, -status: String, -selected: Bool) -> Type:
  {Controls.source_reference(Controls.enter(UI.Node{key, semantic, label, role, UI.TaskRow{task, status, selected}, children}, context)) == Controls.SourceFamily{UI.Node{key, semantic, label, role, UI.TaskRow{task, status, selected}, children}} : Controls.SourceFamily}

def chooser_reference_law(-key: String, -semantic: String, -label: String, -role: UI.Role, -children: +List<UI.Node>, -context: Controls.Context, -selected: Maybe<&2, Nat>) -> Type:
  {Controls.source_reference(Controls.enter(UI.Node{key, semantic, label, role, UI.ProjectChooser{selected}, children}, context)) == Controls.SourceFamily{UI.Node{key, semantic, label, role, UI.ProjectChooser{selected}, children}} : Controls.SourceFamily}

type Requirements is Type:
  Requirements{
    disclosure_typed: @+project:Nat -> {Controls.project_control_input(Core.ApplicationInput{Experience.UserInput{User.Activate{User.ToggleProjectGroup{project}}}}) == Controls.ProjectDisclosure{} : Controls.ProjectControl},
    name_typed: @+project:Maybe<&2, Nat> -> {Controls.project_control_input(Core.ApplicationInput{Experience.UserInput{User.Activate{User.SelectProject{project}}}}) == Controls.ProjectName{} : Controls.ProjectControl},
    create_typed: @+project:Maybe<&2, Nat> -> {Controls.project_control_input(Core.ApplicationInput{Experience.UserInput{User.Activate{User.BeginTask{project}}}}) == Controls.ProjectCreate{} : Controls.ProjectControl},
    more_typed: @+project:Nat -> @+trigger:String -> {Controls.project_control_input(Core.ApplicationInput{Experience.UserInput{User.Activate{User.OpenPanel{User.ObjectActions{User.ProjectSubject{project}}, trigger}}}}) == Controls.ProjectMore{} : Controls.ProjectControl},
    disclosure_face: @+name:String -> @+expanded:Bool -> @+fallback:Controls.Face -> {Controls.project_face(Controls.ProjectDisclosure{}, name, expanded, fallback) == Controls.IconFace{Controls.disclosure_glyph(expanded)} : Controls.Face},
    complete_action_projection: @+area:Controls.Area -> @+family:Controls.SourceFamily -> @+input:Core.Input -> @+availability:View.Availability -> @+name:String -> @+face:Controls.Face -> @+behavior:Controls.Behavior -> @+geometry:Controls.Geometry -> @+placement:Controls.Placement -> @+help:Controls.Help -> @+feedback:Controls.Feedback -> {Controls.source_action(area, family, Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}) ==
        projected_action(input, availability, name, Controls.source_presentation(area, family, input, name, face, behavior, geometry), placement, help, feedback) : Controls.Representation},
    disclosure_geometry: @+width:Nat -> @+height:Nat -> @+preferred:Enclosure.Extent -> @+icon:Nat -> @+radius:Nat -> @+leading:Nat -> {Controls.project_geometry(Controls.ProjectDisclosure{}, Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon, radius, leading}) == Controls.Geometry{Space.fixed_demand(24n, 24n), icon, radius, leading} : Controls.Geometry},
    create_geometry: @+width:Nat -> @+height:Nat -> @+preferred:Enclosure.Extent -> @+icon:Nat -> @+radius:Nat -> @+leading:Nat -> {Controls.project_geometry(Controls.ProjectCreate{}, Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon, radius, leading}) == Controls.Geometry{Space.fixed_demand(28n, 28n), icon, radius, leading} : Controls.Geometry},
    more_geometry: @+width:Nat -> @+height:Nat -> @+preferred:Enclosure.Extent -> @+icon:Nat -> @+radius:Nat -> @+leading:Nat -> {Controls.project_geometry(Controls.ProjectMore{}, Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon, radius, leading}) == Controls.Geometry{Space.fixed_demand(28n, 28n), icon, radius, leading} : Controls.Geometry},
    name_geometry: @+visual:Design.Style -> name_geometry_law(visual),
    chevron_paths: {(Iconography.path(Controls.ChevronRight{}), Iconography.path(Controls.ChevronDown{})) == ("M7.5 4.5 L13 10 L7.5 15.5", "M4.5 7.5 L10 13 L15.5 7.5") : String & String},
    chooser_value_binding: @+trigger:String -> @+name:String -> @+face:Controls.Face -> @+behavior:Controls.Behavior -> @+geometry:Controls.Geometry -> {Controls.chooser_presentation(Core.ApplicationInput{Experience.UserInput{User.Activate{User.OpenPanel{User.ProjectPicker{}, trigger}}}}, name, face, behavior, geometry) == Controls.ActionPresentation{Controls.PickerFace{Some{Controls.Folder{}}, name}, behavior, geometry} : Controls.ActionPresentation},
    create_face: @+name:String -> @+expanded:Bool -> @+fallback:Controls.Face -> {Controls.project_face(Controls.ProjectCreate{}, name, expanded, fallback) == Controls.IconFace{Controls.Plus{}} : Controls.Face},
    more_face: @+name:String -> @+expanded:Bool -> @+fallback:Controls.Face -> {Controls.project_face(Controls.ProjectMore{}, name, expanded, fallback) == Controls.IconFace{Controls.MoreDots{}} : Controls.Face},
    chooser_draft_observation: @+id:Nat -> @+fallback:Design.Style -> chooser_draft_observation_law(id, fallback),
    source_group_style: @+typography:T.Presentation -> @+key:String -> @+context:Controls.Context -> @+representation:Controls.Representation -> @+fallback:Design.Style -> @+project:Nat -> @+selected:Bool -> @+expanded:Bool -> {Appearance.final_style(key, UI.ProjectGroup{project, selected, expanded}, context, representation, fallback, typography) == Appearance.project_group_style(typography) : Design.Style},
    source_task_style: @+typography:T.Presentation -> @+key:String -> @+context:Controls.Context -> @+representation:Controls.Representation -> @+fallback:Design.Style -> @+task:Nat -> @+status:String -> @+selected:Bool -> {Appearance.final_style(key, UI.TaskRow{task, status, selected}, context, representation, fallback, typography) == Appearance.navigation_family_style(selected, 6n, 5n, typography) : Design.Style},
    project_reference: @+key:String -> @+semantic:String -> @+label:String -> @+role:UI.Role -> @+children:+List<UI.Node> -> @+context:Controls.Context -> @+project:Nat -> @+selected:Bool -> @+expanded:Bool -> project_reference_law(key, semantic, label, role, children, context, project, selected, expanded),
    task_reference: @+key:String -> @+semantic:String -> @+label:String -> @+role:UI.Role -> @+children:+List<UI.Node> -> @+context:Controls.Context -> @+task:Nat -> @+status:String -> @+selected:Bool -> task_reference_law(key, semantic, label, role, children, context, task, status, selected),
    chooser_reference: @+key:String -> @+semantic:String -> @+label:String -> @+role:UI.Role -> @+children:+List<UI.Node> -> @+context:Controls.Context -> @+selected:Maybe<&2, Nat> -> chooser_reference_law(key, semantic, label, role, children, context, selected),
    complete_control_binding: @+typography:T.Presentation -> @+in_main:Bool -> @+start:Bool -> @+key:String -> @+semantic:String -> @+label:String -> @+role:UI.Role -> @+meaning:UI.Meaning -> @+children:+List<UI.Node> -> @+context:Controls.Context -> {first_control(Appearance.nodes_at([UI.Node{key, semantic, label, role, meaning, children}], context, typography, in_main, start)) == Controls.represent(key, meaning, label, role, Controls.enter(UI.Node{key, semantic, label, role, meaning, children}, context)) : Controls.Representation},
    actual_header_style: @+typography:T.Presentation -> @+key:String -> @+owner:String -> @+owner_semantic:String -> @+owner_label:String -> @+owner_role:UI.Role -> @+owner_children:+List<UI.Node> -> @+project:Nat -> @+selected:Bool -> @+expanded:Bool -> @+area:Controls.Area -> @+selection:Controls.Selection -> @+code:Maybe<&2, Code.Scene> -> @+appearance:Services.Appearance -> @+access:Services.Access -> @+open:Bool -> @+layers:+List<View.Layer> -> @+execution:Maybe<&2, Workspace.Observation> -> @+representation:Controls.Representation -> @+fallback:Design.Style -> {Appearance.final_style(key, UI.Region{}, Controls.Context{area, selection, code, appearance, access, open, layers, execution, Controls.SourceFamily{UI.Node{owner, owner_semantic, owner_label, owner_role, UI.ProjectGroup{project, selected, expanded}, owner_children}}}, representation, fallback, typography) ==
        Appearance.source_style(String.eq(key, owner ++ "/actions"), Controls.SourceFamily{UI.Node{owner, owner_semantic, owner_label, owner_role, UI.ProjectGroup{project, selected, expanded}, owner_children}}, fallback, typography) : Design.Style}}

law evidence:
  Requirements
