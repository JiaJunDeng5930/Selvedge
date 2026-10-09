import Base
import ../../interaction/IDENTITY.bend as UIIdentity
import ../layout/SPACE.bend as Space
import ../appearance/TYPOGRAPHY.bend as T
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/INPUT.bend as User
import ../../interaction/session/MODEL.bend as Experience
import ../../interaction/presentation/MODEL.bend as View
import ../../interaction/services/MODEL.bend as Services
import ../../interaction/submission/FIELDS.bend as Forms
import ../../interaction/conversation/CODE.bend as Code
import ../../harness/DOMAIN.bend as Domain
import ./PROGRAM.bend as Controls
import ../appearance/DESIGN.bend as Design
import ../appearance/MODEL.bend as Appearance
import ../reading/MODEL.bend as Reading
import ../layout/enclosure.bend as E
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes
import ../../interaction/TYPES.bend as InteractionTypes
import ../../interaction/presentation/VIEW.bend as View2
import ../../features/board/filter.bend as Filter
import ./CONTROLS.bend as A
import ../appearance/ICONS.bend as I
import ../document/SOURCE.bend as S
import ../../features/board/MODEL.bend as Board
import ../../interaction/submission/field-options.bend as Fields
import ../../interaction/presentation/COMPOSITION.bend as Composition
import ../document/presentation-order.bend as Order
import ./SHELL.bend as Shell
import ./MODEL.bend as Authored
import ./authored-primitives.bend as Factory
import ../document/MODEL.bend as Doc
import ../layout/physical-space.bend as Model
import ../layout/geometry-contract.bend as SpaceRules
import ../layout/GEOMETRY.bend as Spatial
import ../../interaction/conversation/MODEL.bend as Conversation
import ../layout/RENDERER.bend as Renderer
import ../../interaction/services/CONTEXT.bend as Context
import ../document/RENDERED.bend as Observed
import ../../interaction/presentation/CONTRACT.bend as CoreDirectory
import ../../interaction/STATE.bend as Core
import ../runtime/SEMANTICS.bend as Browser
import ./SURFACES.bend as Surfaces
import ../appearance/PROGRAM.bend as Paint
import ../editor/MODEL.bend as EditorLayout

def selection_role(kind: SurfaceTypes.ChoiceKind, area: Controls.Area) -> String:
  match kind area:
    case SurfaceTypes.SingleChoice{} Controls.MenuArea{}: "menuitemradio"
    case SurfaceTypes.SingleChoice{} _: "radio"
    case SurfaceTypes.MultipleChoice{} Controls.MenuArea{}: "menuitemcheckbox"
    case SurfaceTypes.MultipleChoice{} _: "checkbox"

def actual_face(value: Controls.Representation) -> Maybe<&2, Controls.Face>:
  match value:
    case Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}: Some{face}
    case _: None{}

def first_drawing(values: +List<S.Node>) -> Maybe<&2, S.Drawing>:
  match values:
    case Con{S.Glyph{key, drawing, style}, rest}: Some{drawing}
    case _: None{}

def selection_drawing(values: +List<S.Node>) -> Maybe<&2, S.Drawing>:
  match values:
    case Con{S.Box{key, tag, style, attributes, children}, Nil{}}: first_drawing(children)
    case Con{node, rest}: selection_drawing(rest)
    case Nil{}: None{}

def selected_drawing(selected: Bool, size: Nat) -> Maybe<&2, S.Drawing>:
  match selected:
    case True{}: Some{I.drawing(Controls.Check{}, size)}
    case False{}: None{}

def actual_face_law(-key: UIIdentity.Key, -kind: SurfaceTypes.ChoiceKind, -classification: Maybe<&2, Filter.Classification>, -selected: Bool, -description: String, -input: InteractionTypes.Input, -availability: View.Availability, -label: String, -role: SurfaceTypes.Role, +context: Controls.Context) -> Type:
  Controls.Context{area, selection, code, appearance, access, open, layers, execution, source_family} = context
  {actual_face(Controls.make_choice(key, kind, classification, selected, description, input, availability, label, role, context)) ==
    Some{Controls.ChoiceFace{Controls.name_for(Controls.purpose_fields(key, input, selection, code, appearance, access, open, layers), label), Controls.choice_description(description), Controls.classification_icon(classification), selected}} : Maybe<&2, Controls.Face>}

type GlyphMeaning<-category: Filter.Classification, -icon: Controls.Icon> is Type:
  TaskStage{-stage: Board.Stage, source: {category == Filter.TaskStage{stage} : Filter.Classification}, glyph: {icon == Controls.Status{stage} : Controls.Icon}}
  TaskPriority{-priority: Board.Priority, source: {category == Filter.TaskPriority{priority} : Filter.Classification}, glyph: {icon == Controls.Priority{priority} : Controls.Icon}}
  Project{source: {category == Filter.Project{} : Filter.Classification}, glyph: {icon == Controls.Folder{} : Controls.Icon}}
  Person{source: {category == Filter.Person{} : Filter.Classification}, glyph: {icon == Controls.User{} : Controls.Icon}}
  Agent{source: {category == Filter.Agent{} : Filter.Classification}, glyph: {icon == Controls.Bot{} : Controls.Icon}}
  Label{source: {category == Filter.Label{} : Filter.Classification}, glyph: {icon == Controls.Tag{} : Controls.Icon}}
  Updated{source: {category == Filter.Updated{} : Filter.Classification}, glyph: {icon == Controls.Clock{} : Controls.Icon}}

type ChoiceRequirements is Type:
  ChoiceRequirements{
    classification_meaning: @+category:Filter.Classification -> GlyphMeaning<category, Controls.classification_glyph(category)>,
    selection_roles: @+kind:SurfaceTypes.ChoiceKind -> @+area:Controls.Area -> @+selected:Bool ->
      {A.behavior(Controls.choice_behavior(kind, area, selected)) == [S.RoleAttribute{selection_role(kind, area)}, S.AriaAttribute{"checked", Fields.boolean(selected)}] : +List<S.Attribute>},
    semantic_face: @+key:UIIdentity.Key -> @+kind:SurfaceTypes.ChoiceKind -> @+classification:Maybe<&2, Filter.Classification> -> @+selected:Bool -> @+description:String -> @+input:InteractionTypes.Input -> @+availability:View.Availability -> @+label:String -> @+role:SurfaceTypes.Role -> @+context:Controls.Context -> actual_face_law(key, kind, classification, selected, description, input, availability, label, role, context),
    leading_measured_glyph: @+text:String -> @description:Maybe<&2, String> -> @+icon:Controls.Icon -> @selected:Bool -> @+key:UIIdentity.Key -> @+parent:Design.Style -> @+geometry:Controls.Geometry ->
      {first_drawing(A.face_members(Controls.ChoiceFace{text, description, Some{icon}, selected}, key, parent, geometry)) == Some{I.drawing(icon, A.face_icon_size(geometry))} : Maybe<&2, S.Drawing>},
    selected_measured_glyph: @+text:String -> @description:Maybe<&2, String> -> @icon:Maybe<&2, Controls.Icon> -> @+selected:Bool -> @+key:UIIdentity.Key -> @+parent:Design.Style -> @+geometry:Controls.Geometry ->
      {selection_drawing(A.face_members(Controls.ChoiceFace{text, description, icon, selected}, key, parent, geometry)) == selected_drawing(selected, A.face_icon_size(geometry)) : Maybe<&2, S.Drawing>}}

law choice_evidence:
  ChoiceRequirements

def reframing_events(+node: S.Node, layout: S.Layout) -> Type:
  {S.events_of(Shell.reframe(node, layout)) == S.events_of(node) : +List<Doc.DOMEvent>}

def reframing_interaction(+node: S.Node, layout: S.Layout) -> Type:
  {S.interaction_of(Shell.reframe(node, layout)) == S.interaction_of(node) : Model.Interaction<Doc.DOMEvent>}

def reframing_children(+node: S.Node, layout: S.Layout) -> Type:
  {S.children_of(Shell.reframe(node, layout)) == S.children_of(node) : +List<S.Node>}

def wrapper_children(key: UIIdentity.Key, style: S.Style, +children: +List<S.Node>) -> Type:
  {S.children_of(Shell.wrap(key, style, children)) == children : +List<S.Node>}

def wrapper_events(key: UIIdentity.Key, style: S.Style, children: +List<S.Node>) -> Type:
  {S.events_of(Shell.wrap(key, style, children)) == Nil{} : +List<Doc.DOMEvent>}

def footer_children(key: UIIdentity.Key, tag: S.BoxTag, style: S.Style, attributes: +List<S.Attribute>, +children: +List<S.Node>, +settings: +List<S.Node>, +font: T.Presentation) -> Type:
  {S.children_of(Shell.with_footer(key, tag, style, attributes, children, settings, font)) == List.append(&2, S.Node, children, Shell.spacer(UIIdentity.part(UIIdentity.place("/application"), "navigation-spacer"), font) <> settings) : +List<S.Node>}

def reading_policy(+width: Model.AxisSize, maximum: Nat) -> Type:
  match width:
    case Model.StretchSize{}: {Shell.reading_policy(Model.StretchSize{}, maximum) == Model.CappedStretchSize{maximum} : Model.AxisSize}
    case _: {Shell.reading_policy(width, maximum) == width : Model.AxisSize}

def reading_layout(+layout: S.Layout, maximum: Nat) -> Type:
  S.Layout{direction, main, cross, frame, width, height, minimum, scroll, position} = layout
  {Shell.reading_layout(layout, maximum) == S.Layout{direction, main, cross, frame, Shell.reading_policy(width, maximum), height, minimum, scroll, position} : S.Layout}

def width_of(layout: S.Layout) -> Model.AxisSize:
  S.Layout{direction, main, cross, frame, width, height, minimum, scroll, position} = layout
  width

def reading_stretch_dimension(direction: Model.Direction, main: Spatial.Alignment, cross: Spatial.Alignment, frame: E.Frame, height: Model.AxisSize, floor: E.Extent, scroll: Model.Scroll, position: Spatial.Position, maximum: Nat, minimum: Nat, preferred: Nat, offered: Nat) -> Maybe<&2, Space.Dimension>:
  Model.materialize(width_of(Shell.reading_layout(S.Layout{direction, main, cross, frame, Model.StretchSize{}, height, floor, scroll, position}, maximum)), minimum, preferred, offered)

def front_layer_last(+first: S.Node, +rest: +List<S.Node>) -> Type:
  {Shell.back_to_front(first <> rest) == List.append(&2, S.Node, Shell.back_to_front(rest), first <> Nil{}) : +List<S.Node>}

def keys(values: +List<S.Node>) -> +List<UIIdentity.Key>:
  match values:
    case Nil{}: Nil{}
    case Con{node, rest}: S.key_of(node) <> keys(rest)

def creation_population(+children: +List<S.Node>, maximum: Nat) -> Type:
  {keys(Shell.creation_children(children, maximum)) == keys(children) : +List<UIIdentity.Key>}

def creation_group(key: UIIdentity.Key, font: S.FontChoice, +maximum: Nat, children: +List<S.Node>) -> Type:
  {Shell.creation_group(key, font, maximum, children) ==
    S.Box{UIIdentity.part(key, "creation-group"), S.Div{}, Shell.neutral_arranged(font, Model.Vertical{}, Model.CappedStretchSize{maximum}, Model.NaturalSize{}, Spatial.Stretch{}, E.SeparateFrames{E.Sections{}}), Nil{}, Shell.creation_children(children, maximum)} : S.Node}

def frame_of(layout: S.Layout) -> E.Frame:
  S.Layout{direction, main, cross, frame, width, height, minimum, scroll, position} = layout
  frame

def creation_group_spacing(key: UIIdentity.Key, font: S.FontChoice, maximum: Nat, children: +List<S.Node>) -> Type:
  {E.frame_gap(frame_of(Shell.layout_of(Shell.creation_group(key, font, maximum, children)))) == E.separation(E.Sections{}) : Nat}

def creation_reading_width(+parameters: Design.LayoutParameters) -> Type:
  {Shell.structure_reading_width(Design.MainStructure{Composition.ReadingMeasure{}, Composition.NoHeading{}, Composition.CenteredCreation{}}, parameters) == Design.reading_maximum_width(parameters) : Nat}

def creation_assembly(+content: InteractionTypes.Scene, +theme: Design.Theme, +base: +List<Design.Node>, +overlays: +List<Design.Node>, scope: Maybe<&2, String>, +base_nodes: +List<S.Node>, +overlay_nodes: +List<S.Node>, +capacity: View.Capacity, +parameters: Design.LayoutParameters, +layers: +List<View.Layer>, +anchors: +List<Shell.Anchor>, +font: T.Presentation) -> Type:
  {Shell.assemble_surface(Design.Surface{content, theme, base, overlays, scope}, base_nodes, overlay_nodes, capacity, parameters, layers, anchors, font) ==
    Shell.assembled_parts(Shell.split_overlays(overlay_nodes, capacity, Shell.scene_navigation_placement(content), parameters, layers, base, overlays, anchors), Design.MainStructure{Composition.ReadingMeasure{}, Composition.NoHeading{}, Composition.CenteredCreation{}}, Design.reading_maximum_width(parameters), base_nodes, base, Shell.scene_navigation_placement(content), parameters, font, theme) : Shell.ShellAuthorship}

def creation_child_layout(+layout: S.Layout, maximum: Nat) -> Type:
  S.Layout{direction, main, cross, frame, width, height, minimum, scroll, position} = layout
  {Shell.creation_layout(layout, maximum) == S.Layout{direction, main, cross, frame, Shell.reading_policy(width, maximum), Model.NaturalSize{}, minimum, Model.Confined{}, position} : S.Layout}

def creation_main(+key: UIIdentity.Key, tag: S.BoxTag, +style: S.Style, attributes: +List<S.Attribute>, children: +List<S.Node>, +maximum: Nat) -> Type:
  S.Style{S.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, +font, chrome, states} = style
  {Shell.main_box(Design.MainStructure{Composition.ReadingMeasure{}, Composition.NoHeading{}, Composition.CenteredCreation{}}, key, tag, style, attributes, children, maximum) ==
    S.Box{key, tag, S.Style{S.Layout{Model.Vertical{}, Spatial.Centered{}, Spatial.Centered{}, E.Frame{E.area(E.PageContent{}), E.SeparateFrames{E.Sections{}}}, Model.StretchSize{}, Model.StretchSize{}, minimum, Model.ScrollVertically{}, Spatial.InFlow{}}, font, chrome, states}, attributes, [Shell.creation_group(key, font, maximum, children)]} : S.Node}

def other_organization(organization: Composition.Body) -> Bool:
  match organization:
    case Composition.CenteredCreation{}: False{}
    case _: True{}

def other_structure(structure: Design.MainStructure) -> Bool:
  Design.MainStructure{measure, heading, organization} = structure
  other_organization(organization)

def other_main(structure: Design.MainStructure, +key: UIIdentity.Key, tag: S.BoxTag, +style: S.Style, attributes: +List<S.Attribute>, children: +List<S.Node>, +maximum: Nat) -> Type:
  Design.MainStructure{measure, heading, +organization} = structure
  S.Style{S.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = style
  {Shell.main_box(Design.MainStructure{measure, heading, organization}, key, tag, style, attributes, children, maximum) ==
    S.Box{key, tag, S.Style{S.Layout{direction, Shell.main_leading(organization, main), Shell.main_cross(organization), Shell.main_frame(organization, frame), Model.StretchSize{}, Model.StretchSize{}, minimum, scroll, Spatial.InFlow{}}, font, chrome, states}, attributes, Shell.measure_children(measure, Shell.heading_children(heading, key, style, children), maximum)} : S.Node}

def navigation_box(key: UIIdentity.Key, tag: S.BoxTag, +style: S.Style, attributes: +List<S.Attribute>, children: +List<S.Node>, rest: +List<S.Node>, +width: Nat) -> Type:
  S.Style{S.Layout{direction, main, cross, frame, old_width, height, minimum, scroll, position}, font, chrome, states} = style
  {Shell.navigation_nodes(S.Box{key, tag, style, attributes, children} <> rest, width) ==
    S.Box{key, tag, S.Style{S.Layout{direction, main, Spatial.Stretch{}, frame, Model.ExactSize{width}, Model.StretchSize{}, minimum, Model.ScrollVertically{}, Spatial.InFlow{}}, font, chrome, states}, attributes, children} <> Shell.navigation_nodes(rest, width) : +List<S.Node>}

def settings_role(role: SurfaceTypes.Role) -> Bool:
  match role:
    case SurfaceTypes.Main{}: False{}
    case SurfaceTypes.Navigation{}: False{}
    case _: True{}

def settings_classification(+node: S.Node, role: SurfaceTypes.Role, +navigation: +List<S.Node>, +main: +List<S.Node>, +settings: +List<S.Node>, +other: +List<S.Node>) -> Type:
  {Shell.split_base_role(node, role, navigation, main, settings, other) == Shell.BaseParts{navigation, main, node <> settings, other} : Shell.BaseParts}

def recipe_structure(recipe: Composition.Recipe) -> Type:
  Composition.Recipe{measure, heading, organization, composer, decisions, latest} = recipe
  {Design.main_structure(Composition.Recipe{measure, heading, organization, composer, decisions, latest}) == Design.MainStructure{measure, heading, organization} : Design.MainStructure}

def available_children(children: +List<S.Node>, maximum: Nat) -> Type:
  {Shell.measure_children(Composition.AvailableMeasure{}, children, maximum) == children : +List<S.Node>}

def page_frame(previous: E.Frame) -> Type:
  {Shell.main_frame(Composition.StageColumns{}, previous) == E.Frame{E.area(E.PageContent{}), E.SeparateFrames{E.Sections{}}} : E.Frame}

def measure_width(parameters: Design.LayoutParameters, heading: Composition.Heading, organization: Composition.Body) -> Type:
  {(Shell.structure_reading_width(Design.MainStructure{Composition.ReadingMeasure{}, heading, organization}, parameters), (Shell.structure_reading_width(Design.MainStructure{Composition.OverviewMeasure{}, heading, organization}, parameters), Shell.structure_reading_width(Design.MainStructure{Composition.AvailableMeasure{}, heading, organization}, parameters))) == (Design.reading_maximum_width(parameters), (Design.overview_maximum_width(parameters), 0n)) : Nat & (Nat & Nat)}

def beside_main_style(style: S.Style, +required: Nat) -> Type:
  S.Style{S.Layout{direction, main, cross, frame, width, height, E.Extent{minimum_width, minimum_height}, scroll, position}, font, chrome, states} = style
  {Shell.beside_style(True{}, required, S.Style{S.Layout{direction, main, cross, frame, width, height, E.Extent{minimum_width, minimum_height}, scroll, position}, font, chrome, states}) == S.Style{S.Layout{direction, main, cross, frame, width, height, E.Extent{Nat.max(minimum_width, required), minimum_height}, scroll, position}, font, chrome, states} : S.Style}

def compact_main_style(style: S.Style, required: Nat) -> Type:
  {Shell.beside_style(False{}, required, style) == style : S.Style}

def main_population(key: UIIdentity.Key, tag: S.BoxTag, style: S.Style, attributes: +List<S.Attribute>, children: +List<S.Node>, rest: +List<S.Node>, structure: Design.MainStructure, maximum: Nat, beside: Bool, required: Nat) -> Type:
  {Shell.main_nodes(S.Box{key, tag, style, attributes, children} <> rest, structure, maximum, beside, required) == Shell.main_box(structure, key, tag, Shell.beside_style(beside, required, style), attributes, children, maximum) <> Shell.main_nodes(rest, structure, maximum, beside, required) : +List<S.Node>}

def main_placement_input(placement: View.NavigationPlacement, parameters: Design.LayoutParameters, structure: Design.MainStructure, reading_width: Nat, navigation: +List<S.Node>, main: +List<S.Node>, settings: +List<S.Node>, other: +List<S.Node>, docked: +List<S.Node>, font: T.Presentation) -> Type:
  match placement:
    case View.LeadingNavigation{}: {Shell.body_direction(View.LeadingNavigation{}, parameters, structure, reading_width, navigation, main, settings, other, docked, font) == Shell.body_mode(True{}, Design.navigation_width(parameters), Design.main_minimum_width(parameters), structure, reading_width, navigation, main, settings, other, docked, font) : S.Node}
    case View.ModalNavigation{}: {Shell.body_direction(View.ModalNavigation{}, parameters, structure, reading_width, navigation, main, settings, other, docked, font) == Shell.body_mode(False{}, Design.navigation_width(parameters), Design.main_minimum_width(parameters), structure, reading_width, navigation, main, settings, other, docked, font) : S.Node}
    case View.CollapsedNavigation{}: {Shell.body_direction(View.CollapsedNavigation{}, parameters, structure, reading_width, navigation, main, settings, other, docked, font) == Shell.body_mode(False{}, Design.navigation_width(parameters), Design.main_minimum_width(parameters), structure, reading_width, navigation, main, settings, other, docked, font) : S.Node}

def root_minimum(node: S.Node) -> E.Extent:
  match node:
    case S.Box{key, tag, S.Style{S.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states}, attributes, children}: minimum
    case _: E.Extent{0n, 0n}

def beside_box_floor(structure: Design.MainStructure, key: UIIdentity.Key, tag: S.BoxTag, style: S.Style, attributes: +List<S.Attribute>, children: +List<S.Node>, maximum: Nat, +required: Nat) -> Type:
  S.Style{S.Layout{direction, main, cross, frame, width, height, E.Extent{minimum_width, minimum_height}, scroll, position}, font, chrome, states} = style
  {root_minimum(Shell.main_box(structure, key, tag, Shell.beside_style(True{}, required, S.Style{S.Layout{direction, main, cross, frame, width, height, E.Extent{minimum_width, minimum_height}, scroll, position}, font, chrome, states}), attributes, children, maximum)) == E.Extent{Nat.max(minimum_width, required), minimum_height} : E.Extent}

def navigation_projection(content: InteractionTypes.Scene) -> Type:
  InteractionTypes.Scene{View.Scene{navigation, main, layers, View.Arrangement{placement}, attention}, settings, transfers, preview, code, directory_picker} = content
  {Shell.scene_navigation_placement(InteractionTypes.Scene{View.Scene{navigation, main, layers, View.Arrangement{placement}, attention}, settings, transfers, preview, code, directory_picker}) == placement : View.NavigationPlacement}

def assembly_placement(+content: InteractionTypes.Scene, +theme: Design.Theme, +base: +List<Design.Node>, +overlays: +List<Design.Node>, scope: Maybe<&2, String>, +base_nodes: +List<S.Node>, +overlay_nodes: +List<S.Node>, +capacity: View.Capacity, +parameters: Design.LayoutParameters, +layers: +List<View.Layer>, +anchors: +List<Shell.Anchor>, +font: T.Presentation, placement: View.NavigationPlacement) -> Type:
  {Shell.assemble_surface(Design.Surface{content, theme, base, overlays, scope}, base_nodes, overlay_nodes, capacity, parameters, layers, anchors, font) == Shell.assembled_parts(Shell.split_overlays(overlay_nodes, capacity, placement, parameters, layers, base, overlays, anchors), Shell.scene_structure(content), Shell.structure_reading_width(Shell.scene_structure(content), parameters), base_nodes, base, placement, parameters, font, theme) : Shell.ShellAuthorship}

def chronological_main_frame(frame: E.Frame) -> Type:
  {Shell.main_frame(Composition.ChronologicalReading{}, frame) == E.Frame{E.area(E.PageContent{}), E.SeparateFrames{E.Sections{}}} : E.Frame}

def chronological_main_cross() -> Type:
  {Shell.main_cross(Composition.ChronologicalReading{}) == Spatial.Centered{} : Spatial.Alignment}

def chronological_main_leading(previous: Spatial.Alignment) -> Type:
  {Shell.main_leading(Composition.ChronologicalReading{}, previous) == previous : Spatial.Alignment}

def chronological_reading_width(+parameters: Design.LayoutParameters) -> Type:
  {Shell.structure_reading_width(Design.MainStructure{Composition.ReadingMeasure{}, Composition.ConversationHeading{}, Composition.ChronologicalReading{}}, parameters) == Design.reading_maximum_width(parameters) : Nat}

def conversation_main(+measure: Composition.Measure, +key: UIIdentity.Key, tag: S.BoxTag, +style: S.Style, attributes: +List<S.Attribute>, title: S.Node, actions: S.Node, remaining: +List<S.Node>, +maximum: Nat) -> Type:
  S.Style{S.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = style
  {Shell.main_box(Design.MainStructure{measure, Composition.ConversationHeading{}, Composition.ChronologicalReading{}}, key, tag, style, attributes, title <> actions <> remaining, maximum) ==
    S.Box{key, tag, S.Style{S.Layout{direction, main, Spatial.Centered{}, E.Frame{E.area(E.PageContent{}), E.SeparateFrames{E.Sections{}}}, Model.StretchSize{}, Model.StretchSize{}, minimum, scroll, Spatial.InFlow{}}, font, chrome, states}, attributes,
      Shell.measure_children(measure, Shell.conversation_heading(key, style, title, actions) <> remaining, maximum)} : S.Node}

def conversation_title_font(+font: S.FontChoice) -> Type:
  match font:
    case S.InheritFont{}: {Shell.conversation_title_font(font) == S.InheritFont{} : S.FontChoice}
    case S.ExplicitFont{presentation}:
      {Shell.conversation_title_font(font) == S.ExplicitFont{T.with_emphasis(T.with_tier(presentation, T.Section{}), T.Medium{})} : S.FontChoice}

def conversation_title_style(+style: S.Style) -> Type:
  S.Style{S.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = style
  match direction:
    case Model.Vertical{}:
      {Shell.conversation_title_style(style) == S.Style{S.Layout{direction, Spatial.Centered{}, cross, frame, width, height, minimum, scroll, position}, Shell.conversation_title_font(font), chrome, states} : S.Style}
    case Model.Horizontal{}:
      {Shell.conversation_title_style(style) == S.Style{S.Layout{direction, main, Spatial.Centered{}, frame, width, height, minimum, scroll, position}, Shell.conversation_title_font(font), chrome, states} : S.Style}
    case Model.ResponsiveHorizontal{}:
      {Shell.conversation_title_style(style) == S.Style{S.Layout{direction, main, Spatial.Centered{}, frame, width, height, minimum, scroll, position}, Shell.conversation_title_font(font), chrome, states} : S.Style}
    case Model.Layered{}:
      {Shell.conversation_title_style(style) == S.Style{S.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, Shell.conversation_title_font(font), chrome, states} : S.Style}

def conversation_title_text(+key: UIIdentity.Key, +value: String, +font: S.FontChoice, wrapping: T.Wrapping) -> Type:
  {Shell.conversation_title(S.Text{key, value, font, wrapping}) == S.Text{key, value, Shell.conversation_title_font(font), T.SingleLine{}} : S.Node}

def conversation_title_box(+key: UIIdentity.Key, +tag: S.BoxTag, +style: S.Style, +attributes: +List<S.Attribute>, +children: +List<S.Node>) -> Type:
  {Shell.conversation_title(S.Box{key, tag, style, attributes, children}) == S.Box{key, tag, Shell.conversation_title_style(style), attributes, Shell.conversation_title_children(children)} : S.Node}

def conversation_title_children(+values: +List<S.Node>) -> Type:
  match values:
    case Nil{}: {Shell.conversation_title_children(values) == Nil{} : +List<S.Node>}
    case Con{S.Box{key, tag, style, attributes, children}, rest}:
      {Shell.conversation_title_children(values) == S.Box{key, tag, Shell.conversation_title_style(style), attributes, Shell.conversation_title_children(children)} <> Shell.conversation_title_children(rest) : +List<S.Node>}
    case Con{S.Text{key, value, font, wrapping}, rest}:
      {Shell.conversation_title_children(values) == S.Text{key, value, Shell.conversation_title_font(font), T.SingleLine{}} <> Shell.conversation_title_children(rest) : +List<S.Node>}
    case Con{other, rest}: {Shell.conversation_title_children(values) == other <> Shell.conversation_title_children(rest) : +List<S.Node>}

def conversation_title_other(+node: S.Node) -> Type:
  match node:
    case S.Box{key, tag, style, attributes, children}: Unit
    case S.Text{key, value, font, wrapping}: Unit
    case other: {Shell.conversation_title(node) == other : S.Node}

def other_heading_children(+heading: Composition.Heading, key: UIIdentity.Key, style: S.Style, +children: +List<S.Node>) -> Type:
  match heading:
    case Composition.ConversationHeading{}: Unit
    case other: {Shell.heading_children(heading, key, style, children) == children : +List<S.Node>}

def conversation_header(+key: UIIdentity.Key, +style: S.Style, title: S.Node, actions: S.Node) -> Type:
  S.Style{layout, font, chrome, states} = style
  {Shell.conversation_heading(key, style, title, actions) ==
    S.Box{UIIdentity.part(key, "@heading"), S.Div{}, S.Style{S.Layout{Model.Horizontal{}, Spatial.Leading{}, Spatial.Centered{},
      E.Frame{E.ambient(0n, 0n), E.SeparateFrames{E.ComposerControls{}}},
      Model.StretchSize{}, Model.NaturalSize{}, E.Extent{0n, 0n}, Model.Confined{}, Spatial.InFlow{}}, font, chrome, states}, Nil{}, [Shell.conversation_title(title), actions]} : S.Node}

def conversation_header_frame(+key: UIIdentity.Key, +style: S.Style, title: S.Node, actions: S.Node) -> Type:
  {frame_of(Shell.layout_of(Shell.conversation_heading(key, style, title, actions))) == E.Frame{E.ambient(0n, 0n), E.SeparateFrames{E.ComposerControls{}}} : E.Frame}

def task_action_flow(+visual: Design.Style, position: Composition.Position) -> Type:
  {Authored.region_style(visual, Composition.TaskActions{}, position) ==
    Factory.with_alignments(Factory.with_direction(
      Factory.with_frame(Factory.style(visual, Model.NaturalSize{}, Model.NaturalSize{}, Model.Confined{}),
        E.Frame{E.ambient(0n, 0n), E.SeparateFrames{E.InlineControls{}}}),
      Model.Horizontal{}), Spatial.Leading{}, Spatial.Centered{}) : S.Style}

type AuthoredShellRequirements is Type:
  AuthoredShellRequirements{
    conversation_title_font: @+font:S.FontChoice -> conversation_title_font(font),
    conversation_title_style: @+style:S.Style -> conversation_title_style(style),
    conversation_title_text: @+key:UIIdentity.Key -> @+value:String -> @+font:S.FontChoice -> @wrapping:T.Wrapping -> conversation_title_text(key, value, font, wrapping),
    conversation_title_box: @+key:UIIdentity.Key -> @+tag:S.BoxTag -> @+style:S.Style -> @+attributes:+List<S.Attribute> -> @+children:+List<S.Node> -> conversation_title_box(key, tag, style, attributes, children),
    conversation_title_children: @+values:+List<S.Node> -> conversation_title_children(values),
    conversation_title_other: @+node:S.Node -> conversation_title_other(node),
    other_heading_children: @+heading:Composition.Heading -> @key:UIIdentity.Key -> @style:S.Style -> @+children:+List<S.Node> -> other_heading_children(heading, key, style, children),
    chronological_main_frame: @frame:E.Frame -> chronological_main_frame(frame),
    chronological_main_cross: chronological_main_cross(),
    chronological_main_leading: @previous:Spatial.Alignment -> chronological_main_leading(previous),
    chronological_reading_width: @+parameters:Design.LayoutParameters -> chronological_reading_width(parameters),
    conversation_header_frame: @+key:UIIdentity.Key -> @+style:S.Style -> @title:S.Node -> @actions:S.Node -> conversation_header_frame(key, style, title, actions),
    conversation_main: @+measure:Composition.Measure -> @+key:UIIdentity.Key -> @tag:S.BoxTag -> @+style:S.Style -> @attributes:+List<S.Attribute> -> @title:S.Node -> @actions:S.Node -> @remaining:+List<S.Node> -> @+maximum:Nat -> conversation_main(measure, key, tag, style, attributes, title, actions, remaining, maximum),
    conversation_header: @+key:UIIdentity.Key -> @+style:S.Style -> @title:S.Node -> @actions:S.Node -> conversation_header(key, style, title, actions),
    task_action_flow: @+visual:Design.Style -> @position:Composition.Position -> task_action_flow(visual, position),
    navigation_projection: @content:InteractionTypes.Scene -> navigation_projection(content),
    assembly_placement: @+content:InteractionTypes.Scene -> @+theme:Design.Theme -> @+base:+List<Design.Node> -> @+overlays:+List<Design.Node> -> @scope:Maybe<&2, String> -> @+base_nodes:+List<S.Node> -> @+overlay_nodes:+List<S.Node> -> @+capacity:View.Capacity -> @+parameters:Design.LayoutParameters -> @+layers:+List<View.Layer> -> @+anchors:+List<Shell.Anchor> -> @+font:T.Presentation -> @placement:View.NavigationPlacement -> @projected:{Shell.scene_navigation_placement(content) == placement : View.NavigationPlacement} -> assembly_placement(content, theme, base, overlays, scope, base_nodes, overlay_nodes, capacity, parameters, layers, anchors, font, placement),
    beside_box_floor: @structure:Design.MainStructure -> @key:UIIdentity.Key -> @tag:S.BoxTag -> @style:S.Style -> @attributes:+List<S.Attribute> -> @children:+List<S.Node> -> @maximum:Nat -> @+required:Nat -> beside_box_floor(structure, key, tag, style, attributes, children, maximum, required),
    beside_main_style: @style:S.Style -> @+required:Nat -> beside_main_style(style, required),
    compact_main_style: @style:S.Style -> @required:Nat -> compact_main_style(style, required),
    main_population: @key:UIIdentity.Key -> @tag:S.BoxTag -> @style:S.Style -> @attributes:+List<S.Attribute> -> @children:+List<S.Node> -> @rest:+List<S.Node> -> @structure:Design.MainStructure -> @maximum:Nat -> @beside:Bool -> @required:Nat -> main_population(key, tag, style, attributes, children, rest, structure, maximum, beside, required),
    main_placement_input: @placement:View.NavigationPlacement -> @parameters:Design.LayoutParameters -> @structure:Design.MainStructure -> @reading_width:Nat -> @navigation:+List<S.Node> -> @main:+List<S.Node> -> @settings:+List<S.Node> -> @other:+List<S.Node> -> @docked:+List<S.Node> -> @font:T.Presentation -> main_placement_input(placement, parameters, structure, reading_width, navigation, main, settings, other, docked, font),
    measure_width: @parameters:Design.LayoutParameters -> @heading:Composition.Heading -> @organization:Composition.Body -> measure_width(parameters, heading, organization),
    recipe_structure: @recipe:Composition.Recipe -> recipe_structure(recipe),
    available_children: @children:+List<S.Node> -> @maximum:Nat -> available_children(children, maximum),
    page_frame: @previous:E.Frame -> page_frame(previous),
    front_layer_last: @+first:S.Node -> @+rest:+List<S.Node> -> front_layer_last(first, rest),
    events: @+node:S.Node -> @+layout:S.Layout -> reframing_events(node, layout),
    interaction: @+node:S.Node -> @+layout:S.Layout -> reframing_interaction(node, layout),
    children: @+node:S.Node -> @+layout:S.Layout -> reframing_children(node, layout),
    wrapper: @key:UIIdentity.Key -> @style:S.Style -> @+children:+List<S.Node> -> wrapper_children(key, style, children),
    no_wrapper_events: @key:UIIdentity.Key -> @style:S.Style -> @children:+List<S.Node> -> wrapper_events(key, style, children),
    reading_policy: @+width:Model.AxisSize -> @maximum:Nat -> reading_policy(width, maximum),
    reading_layout: @+layout:S.Layout -> @maximum:Nat -> reading_layout(layout, maximum),
    reading_stretch_width: @direction:Model.Direction -> @main:Spatial.Alignment -> @cross:Spatial.Alignment -> @frame:E.Frame -> @height:Model.AxisSize -> @floor:E.Extent -> @scroll:Model.Scroll -> @position:Spatial.Position -> @+maximum:Nat -> @+minimum:Nat -> @preferred:Nat -> @offered:Nat -> @+room:Nat ->
      @+fits:{Nat.is_le(minimum, maximum) == True{} : Bool} -> @room_fits:{Nat.is_le(minimum, room) == True{} : Bool} ->
      {SpaceRules.allocated_width(reading_stretch_dimension(direction, main, cross, frame, height, floor, scroll, position, maximum, minimum, preferred, offered), room) == Some{Nat.min(room, maximum)} : Maybe<&2, Nat>},
    creation_population: @+children:+List<S.Node> -> @+maximum:Nat -> creation_population(children, maximum),
    creation_group: @key:UIIdentity.Key -> @font:S.FontChoice -> @+maximum:Nat -> @children:+List<S.Node> -> creation_group(key, font, maximum, children),
    creation_group_spacing: @key:UIIdentity.Key -> @font:S.FontChoice -> @maximum:Nat -> @children:+List<S.Node> -> creation_group_spacing(key, font, maximum, children),
    creation_reading_width: @+parameters:Design.LayoutParameters -> creation_reading_width(parameters),
    creation_assembly: @+content:InteractionTypes.Scene -> @+theme:Design.Theme -> @+base:+List<Design.Node> -> @+overlays:+List<Design.Node> -> @scope:Maybe<&2, String> -> @+base_nodes:+List<S.Node> -> @+overlay_nodes:+List<S.Node> -> @+capacity:View.Capacity -> @+parameters:Design.LayoutParameters -> @+layers:+List<View.Layer> -> @+anchors:+List<Shell.Anchor> -> @+font:T.Presentation ->
      @created:{Shell.scene_structure(content) == Design.MainStructure{Composition.ReadingMeasure{}, Composition.NoHeading{}, Composition.CenteredCreation{}} : Design.MainStructure} -> creation_assembly(content, theme, base, overlays, scope, base_nodes, overlay_nodes, capacity, parameters, layers, anchors, font),
    creation_child_layout: @+layout:S.Layout -> @maximum:Nat -> creation_child_layout(layout, maximum),
    creation_main: @+key:UIIdentity.Key -> @tag:S.BoxTag -> @+style:S.Style -> @attributes:+List<S.Attribute> -> @children:+List<S.Node> -> @+maximum:Nat -> creation_main(key, tag, style, attributes, children, maximum),
    other_main: @+structure:Design.MainStructure -> @+key:UIIdentity.Key -> @tag:S.BoxTag -> @+style:S.Style -> @attributes:+List<S.Attribute> -> @children:+List<S.Node> -> @+maximum:Nat -> @other:{other_structure(structure) == True{} : Bool} -> other_main(structure, key, tag, style, attributes, children, maximum),
    navigation_box: @key:UIIdentity.Key -> @tag:S.BoxTag -> @+style:S.Style -> @attributes:+List<S.Attribute> -> @children:+List<S.Node> -> @rest:+List<S.Node> -> @+width:Nat -> navigation_box(key, tag, style, attributes, children, rest, width),
    settings_classification: @+node:S.Node -> @+role:SurfaceTypes.Role -> @+navigation:+List<S.Node> -> @+main:+List<S.Node> -> @+settings:+List<S.Node> -> @+other:+List<S.Node> ->
      @identified:{S.key_of(node) == UIIdentity.part(UIIdentity.place(""), "settings/open") : UIIdentity.Key} -> @belongs:{settings_role(role) == True{} : Bool} -> settings_classification(node, role, navigation, main, settings, other),
    footer: @key:UIIdentity.Key -> @tag:S.BoxTag -> @style:S.Style -> @attributes:+List<S.Attribute> -> @+children:+List<S.Node> -> @+settings:+List<S.Node> -> @+font:T.Presentation -> footer_children(key, tag, style, attributes, children, settings, font)
  }

law authored_shell_evidence:
  AuthoredShellRequirements

law base_shared_classification:
  for +node: S.Node
  for role: SurfaceTypes.Role
  for parts: Shell.BaseParts
  {Shell.split_base_node(node, role, parts) == Shell.split_base_region(Order.base_region(S.key_of(node), role), node, parts) : Shell.BaseParts}

law base_group_navigation:
  for +node: S.Node
  for +navigation: +List<S.Node>
  for +main: +List<S.Node>
  for +settings: +List<S.Node>
  for +other: +List<S.Node>
  {Shell.split_base_region(Order.NavigationRegion{}, node, Shell.BaseParts{navigation, main, settings, other}) == Shell.BaseParts{node <> navigation, main, settings, other} : Shell.BaseParts}

law base_group_main:
  for +node: S.Node
  for +navigation: +List<S.Node>
  for +main: +List<S.Node>
  for +settings: +List<S.Node>
  for +other: +List<S.Node>
  {Shell.split_base_region(Order.MainRegion{}, node, Shell.BaseParts{navigation, main, settings, other}) == Shell.BaseParts{navigation, node <> main, settings, other} : Shell.BaseParts}

law base_group_footer:
  for +node: S.Node
  for +navigation: +List<S.Node>
  for +main: +List<S.Node>
  for +settings: +List<S.Node>
  for +other: +List<S.Node>
  {Shell.split_base_region(Order.NavigationFooterRegion{}, node, Shell.BaseParts{navigation, main, settings, other}) == Shell.BaseParts{navigation, main, node <> settings, other} : Shell.BaseParts}

law base_group_other:
  for +node: S.Node
  for +navigation: +List<S.Node>
  for +main: +List<S.Node>
  for +settings: +List<S.Node>
  for +other: +List<S.Node>
  {Shell.split_base_region(Order.OtherRegion{}, node, Shell.BaseParts{navigation, main, settings, other}) == Shell.BaseParts{navigation, main, settings, node <> other} : Shell.BaseParts}

law modal_navigation_geometry:
  for +node: S.Node
  for +capacity: View.Capacity
  for +parameters: Design.LayoutParameters
  for layers: +List<View.Layer>
  for base: +List<Design.Node>
  for overlays: +List<Design.Node>
  for anchors: +List<Shell.Anchor>
  for docked: +List<S.Node>
  for floating: +List<S.Node>
  {Shell.split_overlay_node(node, SurfaceTypes.Navigation{}, capacity, View.ModalNavigation{}, parameters, layers, base, overlays, anchors, Shell.OverlayParts{docked, floating}) ==
    Shell.OverlayParts{docked, Shell.resize(node, Model.ExactSize{Design.navigation_width(parameters)}, Model.StretchSize{}, Model.ScrollVertically{}, Spatial.Stretch{}, Spatial.AlignedLayer{E.Insets{0n, 0n}, Spatial.Leading{}, Spatial.Leading{}}) <> floating} : Shell.OverlayParts}

law modal_navigation_population:
  for +key: UIIdentity.Key
  for +tag: S.BoxTag
  for +style: S.Style
  for +attributes: +List<S.Attribute>
  for +children: +List<S.Node>
  for +rest: +List<S.Node>
  for +capacity: View.Capacity
  for +parameters: Design.LayoutParameters
  for +layers: +List<View.Layer>
  for +base: +List<Design.Node>
  for +overlays: +List<Design.Node>
  for +anchors: +List<Shell.Anchor>
  for identified: {Shell.base_role(key, overlays) == SurfaceTypes.Navigation{} : SurfaceTypes.Role}
  {Shell.split_overlays(S.Box{key, tag, style, attributes, children} <> rest, capacity, View.ModalNavigation{}, parameters, layers, base, overlays, anchors) ==
    Shell.split_overlay_node(S.Box{key, tag, style, attributes, children}, SurfaceTypes.Navigation{}, capacity, View.ModalNavigation{}, parameters, layers, base, overlays, anchors,
      Shell.split_overlays(rest, capacity, View.ModalNavigation{}, parameters, layers, base, overlays, anchors)) : Shell.OverlayParts}

law modal_navigation_box_preserved:
  for +key: UIIdentity.Key
  for +tag: S.BoxTag
  for +direction: Model.Direction
  for +main: Spatial.Alignment
  for cross: Spatial.Alignment
  for +frame: E.Frame
  for width: Model.AxisSize
  for height: Model.AxisSize
  for +minimum: E.Extent
  for scroll: Model.Scroll
  for position: Spatial.Position
  for +font: S.FontChoice
  for +chrome: Design.Chrome
  for +states: Design.ControlStates
  for +attributes: +List<S.Attribute>
  for +children: +List<S.Node>
  for +capacity: View.Capacity
  for +parameters: Design.LayoutParameters
  for layers: +List<View.Layer>
  for base: +List<Design.Node>
  for overlays: +List<Design.Node>
  for anchors: +List<Shell.Anchor>
  for docked: +List<S.Node>
  for floating: +List<S.Node>
  {Shell.split_overlay_node(S.Box{key, tag, S.Style{S.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states}, attributes, children}, SurfaceTypes.Navigation{}, capacity, View.ModalNavigation{}, parameters, layers, base, overlays, anchors, Shell.OverlayParts{docked, floating}) ==
    Shell.OverlayParts{docked, S.Box{key, tag, S.Style{S.Layout{direction, main, Spatial.Stretch{}, frame, Model.ExactSize{Design.navigation_width(parameters)}, Model.StretchSize{}, minimum, Model.ScrollVertically{}, Spatial.AlignedLayer{E.Insets{0n, 0n}, Spatial.Leading{}, Spatial.Leading{}}}, font, chrome, states}, attributes, children} <> floating} : Shell.OverlayParts}

law dialog_reading_span:
  for navigation_width: Nat
  for main_minimum_width: Nat
  for details_width: Nat
  for +reading_width: Nat
  for overview_width: Nat
  for toolbar_height: Nat
  for input_minimum_height: Nat
  for input_maximum_height: Nat
  for +line_height: Nat
  for creation_height: Nat
  for lane_width: Nat
  {Shell.dialog_reading_width(Design.LayoutParameters{navigation_width, main_minimum_width, details_width, reading_width, overview_width, toolbar_height, input_minimum_height, input_maximum_height, line_height, creation_height, lane_width}) == Nat.min(reading_width, Nat.mul(24n, line_height)) : Nat}

def dialog_clearance(parameters: Design.LayoutParameters) -> E.Insets:
  Design.LayoutParameters{navigation_width, main_minimum_width, details_width, reading_width, overview_width, toolbar_height, input_minimum_height, input_maximum_height, line_height, creation_height, lane_width} = parameters
  Shell.outside_insets(Nat.max(1n, Nat.div(line_height, 4n)))

law dialog_floating_geometry:
  for +node: S.Node
  for +parameters: Design.LayoutParameters
  for layers: +List<View.Layer>
  for base: +List<Design.Node>
  for overlays: +List<Design.Node>
  for anchors: +List<Shell.Anchor>
  for docked: +List<S.Node>
  for floating: +List<S.Node>
  {Shell.float_overlay(SurfaceTypes.Dialog{}, parameters, node, layers, base, overlays, anchors, docked, floating) ==
    Shell.OverlayParts{docked, Shell.resize(node, Model.CappedStretchSize{Shell.dialog_reading_width(parameters)}, Model.CappedNaturalSize{100n}, Model.Confined{}, Spatial.Stretch{}, Spatial.CenteredLayer{dialog_clearance(parameters)}) <> floating} : Shell.OverlayParts}

law dialog_floating_box_preserved:
  for +key: UIIdentity.Key
  for +tag: S.BoxTag
  for +direction: Model.Direction
  for +main: Spatial.Alignment
  for cross: Spatial.Alignment
  for +frame: E.Frame
  for width: Model.AxisSize
  for height: Model.AxisSize
  for +minimum: E.Extent
  for scroll: Model.Scroll
  for position: Spatial.Position
  for +font: S.FontChoice
  for +chrome: Design.Chrome
  for +states: Design.ControlStates
  for +attributes: +List<S.Attribute>
  for +children: +List<S.Node>
  for +parameters: Design.LayoutParameters
  for layers: +List<View.Layer>
  for base: +List<Design.Node>
  for overlays: +List<Design.Node>
  for anchors: +List<Shell.Anchor>
  for docked: +List<S.Node>
  for floating: +List<S.Node>
  {Shell.float_overlay(SurfaceTypes.Dialog{}, parameters, S.Box{key, tag, S.Style{S.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states}, attributes, children}, layers, base, overlays, anchors, docked, floating) ==
    Shell.OverlayParts{docked, S.Box{key, tag, S.Style{S.Layout{direction, main, Spatial.Stretch{}, frame, Model.CappedStretchSize{Shell.dialog_reading_width(parameters)}, Model.CappedNaturalSize{100n}, minimum, Model.Confined{}, Spatial.CenteredLayer{dialog_clearance(parameters)}}, font, chrome, states}, attributes, children} <> floating} : Shell.OverlayParts}

def reading_encoding(+task: Nat, +generation: Nat, +part: Reading.Part) -> Type:
  {S.attribute_properties(S.ReadingAttribute{Reading.Binding{Reading.Context{task, generation}, part}}) ==
    [Doc.Property{"data-reading-task", Nat.show(task)}, Doc.Property{"data-reading-generation", Nat.show(generation)}, Doc.Property{"data-reading-" ++ Reading.part_name(part), ""}] : +List<Doc.Property>}

def encoded_sequence(+attribute: S.Attribute, +rest: +List<S.Attribute>) -> Type:
  {Renderer.attributes(attribute <> rest) == List.append(&2, Doc.Property, S.attribute_properties(attribute), Renderer.attributes(rest)) : +List<Doc.Property>}

def page_context(+previous: Maybe<&2, Reading.Context>, +task: Nat, +generation: Nat) -> Type:
  {Authored.context_from_meaning(previous, SurfaceTypes.PageContext{Some{Conversation.Identity{task, generation}}}) == Some{Reading.Context{task, generation}} : Maybe<&2, Reading.Context>}

def cleared_context(+previous: Maybe<&2, Reading.Context>) -> Type:
  {Authored.context_from_meaning(previous, SurfaceTypes.PageContext{None{}}) == None{} : Maybe<&2, Reading.Context>}

# This equation binds the context propagation to the production forest descent.

def scoped_node(+key: UIIdentity.Key, +semantic: String, +label: String, +role: SurfaceTypes.Role, +meaning: SurfaceTypes.Meaning, +visual: Design.Style, +control: Controls.Representation, +children: +List<Design.Node>, +rest: +List<Design.Node>, +parameters: Design.LayoutParameters, +context: Maybe<&2, Reading.Context>) -> Type:
  {Authored.forest_in_context(Design.Node{key, semantic, label, role, meaning, visual, control, children} <> rest, parameters, context) ==
    Authored.combine(Authored.construct_in_context(Authored.forest_in_context(children, parameters, Authored.context_from_meaning(context, meaning)), key, semantic, label, role, meaning, visual, control, parameters, Authored.context_from_meaning(context, meaning)), Authored.forest_in_context(rest, parameters, context)) : Authored.Forest}

def partition_frame(+key: UIIdentity.Key, +tag: S.BoxTag, +visual: Design.Style, +direction: Model.Direction, +part: E.Part, +arrangement: E.Arrangement, +content: +List<S.Node>) -> Type:
  {Authored.dialog_partition(key, tag, visual, direction, part, arrangement, content) ==
    S.Box{key, tag, Authored.dialog_partition_style(part, Factory.with_frame(Factory.content_style(visual, direction, Model.StretchSize{}, Model.NaturalSize{}, 0n), E.Frame{E.partition(part), arrangement})), Nil{}, content} : S.Node}

def dialog_construction(+key: UIIdentity.Key, +label: String, +meaning: SurfaceTypes.Meaning, +visual: Design.Style, +control: Controls.Representation, +children: +List<Authored.Child>, +parameters: Design.LayoutParameters) -> Type:
  {Authored.regular(key, label, SurfaceTypes.Dialog{}, meaning, visual, control, children, parameters) == Authored.regular_content(key, label, SurfaceTypes.Dialog{}, meaning, visual, control, children, parameters, Authored.dialog_content(key, label, visual, children)) : S.Node}

def timeline_root(+context: Reading.Context, +key: UIIdentity.Key, +tag: S.BoxTag, +style: S.Style, +attributes: +List<S.Attribute>, +children: +List<S.Node>, +visual: Design.Style) -> Type:
  {Authored.reading_box(context, SurfaceTypes.Timeline{}, S.Box{key, tag, style, attributes, children}, visual) ==
    S.Box{key, tag, style, List.append(&2, S.Attribute, attributes, [S.ReadingAttribute{Reading.Binding{context, Reading.ReadingViewport{}}}]),
      [S.Box{UIIdentity.part(key, "@reading-content"), S.Div{}, Factory.with_frame(Factory.content_style(visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), E.Frame{E.ambient(0n, 0n), E.EmbeddedContent{0n}}), [S.ReadingAttribute{Reading.Binding{context, Reading.Content{}}}], children}]} : S.Node}

def composer_root(+context: Reading.Context, +key: UIIdentity.Key, +tag: S.BoxTag, +style: S.Style, +attributes: +List<S.Attribute>, +children: +List<S.Node>, +visual: Design.Style) -> Type:
  {Authored.reading_box(context, SurfaceTypes.Composer{}, S.Box{key, tag, style, attributes, children}, visual) ==
    S.Box{key, tag, style, List.append(&2, S.Attribute, attributes, [S.ReadingAttribute{Reading.Binding{context, Reading.Dock{}}}]), children} : S.Node}

def bound_construction(+children: +List<Authored.Child>, +key: UIIdentity.Key, +semantic: String, +label: String, +role: SurfaceTypes.Role, +meaning: SurfaceTypes.Meaning, +visual: Design.Style, +control: Controls.Representation, +parameters: Design.LayoutParameters, +context: Maybe<&2, Reading.Context>) -> Type:
  {Authored.construct_in_context(Authored.Ready{children}, key, semantic, label, role, meaning, visual, control, parameters, context) ==
    Authored.finish_node(Authored.reading_root(context, key, role, Authored.authored_node(key, label, role, meaning, visual, control, children, parameters), visual), key, semantic, role, meaning, control) : Authored.Forest}

def body_scroll_allocation(value: S.Style) -> Bool:
  S.Style{layout, font, chrome, states} = value
  S.Layout{direction, main, cross, frame, width, height, minimum, scroll, position} = layout
  match height scroll:
    case Model.StretchSize{} Model.ScrollVertically{}: True{}
    case _ _: False{}

def native_attribute_owner(+key: UIIdentity.Key, +previous: String) -> Type:
  {Authored.native_attribute(key, S.DataAttribute{"native-key", previous}) == S.DataAttribute{"native-key", UIIdentity.encode(key)} : S.Attribute}

def native_attribute_data_result(+owned: Bool, +key: UIIdentity.Key, +name: String, +value: String) -> S.Attribute:
  match owned:
    case True{}: S.DataAttribute{"native-key", UIIdentity.encode(key)}
    case False{}: S.DataAttribute{name, value}

def native_attribute_choice(+owned: Bool, +key: UIIdentity.Key, +name: String, +value: String) -> Type:
  {Authored.native_attribute_value(owned, key, name, value) == native_attribute_data_result(owned, key, name, value) : S.Attribute}

def native_attribute_data(+key: UIIdentity.Key, +name: String, +value: String) -> Type:
  {Authored.native_attribute(key, S.DataAttribute{name, value}) == native_attribute_data_result(String.eq(name, "native-key"), key, name, value) : S.Attribute}

def native_attribute_other(+key: UIIdentity.Key, +attribute: S.Attribute) -> Type:
  match attribute:
    case S.DataAttribute{name, value}: Bool
    case other: {Authored.native_attribute(key, other) == other : S.Attribute}

def native_attributes_nil(+key: UIIdentity.Key) -> Type:
  {Authored.native_attributes(key, Nil{}) == Nil{} : +List<S.Attribute>}

def native_attributes_cons(+key: UIIdentity.Key, +attribute: S.Attribute, +rest: +List<S.Attribute>) -> Type:
  {Authored.native_attributes(key, attribute <> rest) == Authored.native_attribute(key, attribute) <> Authored.native_attributes(key, rest) : +List<S.Attribute>}

def native_decoration_result(+node: S.Node, +extra: +List<S.Attribute>) -> S.Node:
  match node:
    case S.Box{key, tag, style, attrs, children}: S.Box{key, tag, style, List.append(&2, S.Attribute, attrs, Authored.native_attributes(key, extra)), children}
    case S.Control{key, tag, style, attrs, name, enabled, first, remaining, children}: S.Control{key, tag, style, List.append(&2, S.Attribute, attrs, Authored.native_attributes(key, extra)), name, enabled, first, remaining, children}
    case S.Field{key, kind, style, attrs, value, placeholder, options, policy, name, enabled, first, remaining}: S.Field{key, kind, style, List.append(&2, S.Attribute, attrs, Authored.native_attributes(key, extra)), value, placeholder, options, policy, name, enabled, first, remaining}
    case other: other

def native_decoration(+node: S.Node, +extra: +List<S.Attribute>) -> Type:
  {Authored.add_attributes(node, extra) == native_decoration_result(node, extra) : S.Node}

type AuthoredContainmentRequirements is Type:
  AuthoredContainmentRequirements{
    native_attribute_owner: @+key:UIIdentity.Key -> @+previous:String -> native_attribute_owner(key, previous),
    native_attribute_data: @+key:UIIdentity.Key -> @+name:String -> @+value:String -> native_attribute_data(key, name, value),
    native_attribute_other: @+key:UIIdentity.Key -> @+attribute:S.Attribute -> native_attribute_other(key, attribute),
    native_attributes_nil: @+key:UIIdentity.Key -> native_attributes_nil(key),
    native_attributes_cons: @+key:UIIdentity.Key -> @+attribute:S.Attribute -> @+rest:+List<S.Attribute> -> native_attributes_cons(key, attribute, rest),
    native_decoration: @+node:S.Node -> @+extra:+List<S.Attribute> -> native_decoration(node, extra),
    body_scroll_allocation: @+value:S.Style ->
      {body_scroll_allocation(Authored.dialog_partition_style(E.Body{}, value)) == True{} : Bool}}

law authored_containment_evidence:
  AuthoredContainmentRequirements

def execution_observation(context: Controls.Context) -> Maybe<&2, Context.Observation>:
  Controls.Context{area, selection, code, appearance, access, settings_open, layers, execution, source_family} = context
  execution

def page_observation(content: InteractionTypes.Scene) -> Maybe<&2, Context.Observation>:
  InteractionTypes.Scene{View.Scene{navigation, main, layers, arrangement, attention}, settings, transfers, preview, code, directory_picker} = content
  Controls.page_execution(main)

type DirectoryEntryRequirements is Type:
  DirectoryEntryRequirements{
    enter_key: {Browser.confirmation_key("Enter", False{}, False{}, False{}, False{}, False{}) == True{} : Bool},
    composing_key: @keyboard:String -> @control:Bool -> @alt:Bool -> @shift:Bool -> @meta:Bool ->
      {Browser.confirmation_key(keyboard, True{}, control, alt, shift, meta) == False{} : Bool},
    denied_gesture: @found:Maybe<&2, SurfaceTypes.Node> -> {Browser.confirm_gesture(found, False{}) == None{} : Maybe<&2, SurfaceTypes.Gesture>},
    directory_gesture: @key:UIIdentity.Key -> @semantic:String -> @label:String -> @role:SurfaceTypes.Role -> @editor:User.Editor -> @text:String -> @children:+List<SurfaceTypes.Node> ->
      {Browser.confirm_gesture(Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.EnterDirectory{editor, text}, children}}, True{}) == Some{SurfaceTypes.ConfirmDirectory{}} : Maybe<&2, SurfaceTypes.Gesture>},
    unmatched_confirmation: @+key:String -> @keyboard:String -> @composing:Bool -> @control:Bool -> @alt:Bool -> @shift:Bool -> @meta:Bool -> @+state:Browser.State ->
      @absent:{Browser.confirm_source(Browser.found_node(key, state)) == None{} : Maybe<&2, SurfaceTypes.Gesture>} ->
      {Browser.confirm_text(key, keyboard, composing, control, alt, shift, meta, state) == Browser.Decision{state, Nil{}} : Browser.Decision},
    rejected_confirmation: @+key:String -> @keyboard:String -> @composing:Bool -> @control:Bool -> @alt:Bool -> @shift:Bool -> @meta:Bool -> @+state:Browser.State ->
      @denied:{Browser.confirmation_key(keyboard, composing, control, alt, shift, meta) == False{} : Bool} ->
      {Browser.confirm_text(key, keyboard, composing, control, alt, shift, meta, state) == Browser.Decision{state, Nil{}} : Browser.Decision}}

law directory_entry_evidence:
  DirectoryEntryRequirements

def selection_widget(widget: Controls.Widget) -> Bool:
  match widget:
    case Controls.SelectInput{}: True{}
    case Controls.ToggleInput{}: True{}
    case _: False{}

type PickerRequirements is Type:
  PickerRequirements{service: CoreDirectory.DirectoryPickerRequirements,
    open_and_browse: @+editor:User.Editor -> @+parent:UIIdentity.Key -> @+state:InteractionTypes.State -> {InterfaceView.field_children(Forms.WorkspaceDirectories{}, editor, parent, state) ==
          SurfaceTypes.Node{UIIdentity.Part{parent, "instruction"}, "workspace/instruction", "Enter a directory path to add it. Listed directories define the workspace; choose the primary working directory.", SurfaceTypes.Content{}, SurfaceTypes.ReadOnly{"Enter a directory path to add it. Listed directories define the workspace; choose the primary working directory."}, Nil{}} <>
          SurfaceTypes.Node{UIIdentity.Part{parent, "add"}, "workspace/add", "Add working directory", SurfaceTypes.Field{}, SurfaceTypes.EnterDirectory{editor, InterfaceView.pending_directory(state, editor)}, Nil{}} <>
          InterfaceView.directory_confirm(editor, parent, state) <> InterfaceView.directory_browse(editor, parent, state) <>
          InterfaceView.directory_values(InterfaceView.workspace_observed(InterfaceView.field_value(state, editor, Forms.WorkspaceDirectories{})), editor, parent, state) : +List<SurfaceTypes.Node>},
    finite_choice: @+field:Forms.Field -> @+value:Forms.Observed -> {selection_widget(Controls.widget_for(Forms.Choice{}, field, value)) == True{} : Bool},
    location_binding: @value:String -> @+path:String -> {InterfaceView.bind(SurfaceTypes.DirectoryBrowserLocation{value}, SurfaceTypes.Directory{path}) == Some{InteractionTypes.ServiceInput{Services.WriteDirectoryLocation{path}}} : Maybe<&2, InteractionTypes.Input>},
    browse: @+editor:User.Editor -> @+parent:UIIdentity.Key -> @+state:InteractionTypes.State -> {InterfaceView.directory_browse(editor, parent, state) == InterfaceView.product_action(parent, "workspace/browse", "Browse folders",
          InteractionTypes.ServiceInput{Services.OpenDirectoryPicker{editor, InterfaceView.browse_start(editor, state), UIIdentity.encode(UIIdentity.Part{parent, "workspace/browse"})}},
          Core.accepts_directory(editor, InterfaceView.application_of(state))) : SurfaceTypes.Node}}

law picker_requirements:
  PickerRequirements

# This specification flattens each original child's ordinary source nodes;
# it does not classify children or move operations past following content.
def dialog_reading_content(+children: +List<Authored.Child>) -> +List<S.Node>:
  match children:
    case Nil{}: Nil{}
    case Con{Authored.Child{key, role, meaning, control, nodes}, rest}:
      List.append(&2, S.Node, Authored.ordinary(nodes), dialog_reading_content(rest))

def dialog_reading_order(+children: +List<Authored.Child>) -> Type:
  {List.append(&2, S.Node, Authored.dialog_body(children), Authored.dialog_actions(children)) ==
    dialog_reading_content(children) : +List<S.Node>}

# Selection alternatives remain content even though choosing one produces input.

law choice_content:
  for kind: SurfaceTypes.ChoiceKind
  for classification: Maybe<&2, Filter.Classification>
  for selected: Bool
  for description: String
  for input: InteractionTypes.Input
  for availability: View.Availability
  {Authored.dialog_operation(SurfaceTypes.Button{}) == False{} : Bool}

law choice_group_content:
  {Authored.dialog_operation(SurfaceTypes.Section{}) == False{} : Bool}

law choice_group_partition:
  for key: UIIdentity.Key
  for control: Controls.Representation
  for +choices: +List<S.Node>
  for action_key: UIIdentity.Key
  for action_control: Controls.Representation
  for +actions: +List<S.Node>
  for input: InteractionTypes.Input
  for availability: View.Availability
  {Authored.dialog_parts([
    Authored.Child{key, SurfaceTypes.Section{}, SurfaceTypes.ChoiceGroup{}, control, choices},
    Authored.Child{action_key, SurfaceTypes.DialogActions{}, SurfaceTypes.Activate{input, availability}, action_control, actions}]) ==
      Authored.BodyAndActions{Authored.ordinary(choices), Authored.ordinary(actions)} : Authored.DialogParts}

law dialog_action_region:
  {Authored.dialog_operation(SurfaceTypes.DialogActions{}) == True{} : Bool}

law dialog_action_footer:
  for key: UIIdentity.Key
  for meaning: SurfaceTypes.Meaning
  for control: Controls.Representation
  for +nodes: +List<S.Node>
  for +rest: +List<Authored.Child>
  for ordered: {Authored.dialog_ordered(Authored.Child{key, SurfaceTypes.DialogActions{}, meaning, control, nodes} <> rest) == True{} : Bool}
  {Authored.dialog_parts(Authored.Child{key, SurfaceTypes.DialogActions{}, meaning, control, nodes} <> rest) ==
    Authored.TrailingActions{List.append(&2, S.Node, Authored.ordinary(nodes), dialog_reading_content(rest))} : Authored.DialogParts}

law dialog_ordinary_activation:
  for key: UIIdentity.Key
  for role: SurfaceTypes.Role
  for input: InteractionTypes.Input
  for availability: View.Availability
  for control: Controls.Representation
  for +nodes: +List<S.Node>
  for +rest: +List<Authored.Child>
  for ordinary: {Authored.dialog_operation(role) == False{} : Bool}
  {Authored.dialog_parts(Authored.Child{key, role, SurfaceTypes.Activate{input, availability}, control, nodes} <> rest) ==
    Authored.BodyAndActions{List.append(&2, S.Node, Authored.ordinary(nodes), Authored.dialog_body(rest)), Authored.dialog_actions(rest)} : Authored.DialogParts}

law dialog_rejects_invalid_order:
  for key: UIIdentity.Key
  for label: String
  for meaning: SurfaceTypes.Meaning
  for visual: Design.Style
  for control: Controls.Representation
  for +children: +List<Authored.Child>
  for parameters: Design.LayoutParameters
  for invalid: {Authored.dialog_ordered(children) == False{} : Bool}
  {Authored.authored_node(key, label, SurfaceTypes.Dialog{}, meaning, visual, control, children, parameters) ==
    Authored.Rejected{key, Authored.InvalidDialogOrder{}} : Authored.Authorship}

def selected_background_wash_percent(background: Surfaces.Color) -> Nat:
  match background:
    case Surfaces.NeutralWash{strength}: Surfaces.wash_percent(strength)
    case _: 0n

def selected_wash_percent(phase: Surfaces.Phase) -> Nat:
  selected_background_wash_percent(Surfaces.background(Surfaces.Choice{True{}}, phase))

type SurfaceRequirements is Type:
  SurfaceRequirements{
    ordinary_foreground: {Surfaces.foreground(Surfaces.QuietAction{}) == Surfaces.Token{"--color-token-text-primary"} : Surfaces.Color},
    primary_foreground: {Surfaces.foreground(Surfaces.PrimaryAction{}) == Surfaces.Token{"--color-text-primary-solid"} : Surfaces.Color},
    destructive_foreground: {Surfaces.foreground(Surfaces.DestructiveAction{}) == Surfaces.Token{"--color-text-danger-ghost"} : Surfaces.Color},
    choice_foreground: @selected:Bool -> {Surfaces.foreground(Surfaces.Choice{selected}) == Surfaces.Token{"--color-token-text-primary"} : Surfaces.Color},
    primary_rest: {Surfaces.background(Surfaces.PrimaryAction{}, Surfaces.Rest{}) == Surfaces.Token{"--color-background-primary-solid"} : Surfaces.Color},
    primary_hover: {Surfaces.background(Surfaces.PrimaryAction{}, Surfaces.Hovered{}) == Surfaces.Token{"--color-background-primary-solid-hover"} : Surfaces.Color},
    primary_pressed: {Surfaces.background(Surfaces.PrimaryAction{}, Surfaces.Pressed{}) == Surfaces.Token{"--color-background-primary-solid-active"} : Surfaces.Color},
    field_phase_stable: @phase:Surfaces.Phase -> {Surfaces.background(Surfaces.Field{}, phase) == Surfaces.Token{"--color-token-main-surface-primary"} : Surfaces.Color},
    embedded_field_phase_stable: @phase:Surfaces.Phase -> {Surfaces.background(Surfaces.EmbeddedField{}, phase) == Surfaces.Clear{} : Surfaces.Color},
    embedded_action_phase_stable: @phase:Surfaces.Phase -> {Surfaces.background(Surfaces.EmbeddedAction{}, phase) == Surfaces.Clear{} : Surfaces.Color},
    selected_rest: {Surfaces.background(Surfaces.Choice{True{}}, Surfaces.Rest{}) == Surfaces.NeutralWash{Surfaces.SubtleWash{}} : Surfaces.Color},
    selected_hover: {Surfaces.background(Surfaces.Choice{True{}}, Surfaces.Hovered{}) == Surfaces.NeutralWash{Surfaces.EmphasizedWash{}} : Surfaces.Color},
    selected_rest_wash_percent: {selected_wash_percent(Surfaces.Rest{}) == 5n : Nat},
    selected_hover_wash_percent: {selected_wash_percent(Surfaces.Hovered{}) == 10n : Nat},
    selected_rest_native_color: {Paint.surface_color(Surfaces.background(Surfaces.Choice{True{}}, Surfaces.Rest{})) == "var(--lightningcss-light, rgba(0, 0, 0, 0.05))var(--lightningcss-dark, rgba(255, 255, 255, 0.05))" : String},
    selected_hover_native_color: {Paint.surface_color(Surfaces.background(Surfaces.Choice{True{}}, Surfaces.Hovered{})) == "var(--lightningcss-light, rgba(0, 0, 0, 0.10))var(--lightningcss-dark, rgba(255, 255, 255, 0.10))" : String},
    unselected_rest: {Surfaces.background(Surfaces.Choice{False{}}, Surfaces.Rest{}) == Surfaces.Clear{} : Surfaces.Color},
    main_surface: @+typography:T.Presentation -> @meaning:SurfaceTypes.Meaning -> {Appearance.style_background(Appearance.style(SurfaceTypes.Main{}, meaning, typography)) == Design.SurfacePaint{Surfaces.Canvas{}, Surfaces.Rest{}} : Design.Paint},
    navigation_surface: @+typography:T.Presentation -> @meaning:SurfaceTypes.Meaning -> {Appearance.style_background(Appearance.style(SurfaceTypes.Navigation{}, meaning, typography)) == Design.SurfacePaint{Surfaces.Navigation{}, Surfaces.Rest{}} : Design.Paint},
    card_surface: @+typography:T.Presentation -> @meaning:SurfaceTypes.Meaning -> {Appearance.style_background(Appearance.style(SurfaceTypes.Card{}, meaning, typography)) == Design.SurfacePaint{Surfaces.Content{}, Surfaces.Rest{}} : Design.Paint},
    dialog_surface: @+typography:T.Presentation -> @meaning:SurfaceTypes.Meaning -> {Appearance.style_background(Appearance.style(SurfaceTypes.Dialog{}, meaning, typography)) == Design.SurfacePaint{Surfaces.Content{}, Surfaces.Rest{}} : Design.Paint},
    menu_surface: @+typography:T.Presentation -> @meaning:SurfaceTypes.Meaning -> {Appearance.style_background(Appearance.style(SurfaceTypes.Menu{}, meaning, typography)) == Design.SurfacePaint{Surfaces.Floating{}, Surfaces.Rest{}} : Design.Paint},
    composer_surface: @+typography:T.Presentation -> @meaning:SurfaceTypes.Meaning -> {Appearance.style_background(Appearance.style(SurfaceTypes.Composer{}, meaning, typography)) == Design.SurfacePaint{Surfaces.Content{}, Surfaces.Rest{}} : Design.Paint},
    input_phase: @+typography:T.Presentation -> @phase:Surfaces.Phase -> {Appearance.phase_background(Appearance.editable_field(typography), phase) == Design.SurfacePaint{Surfaces.Field{}, phase} : Design.Paint},
    message_phase: @+typography:T.Presentation -> @entry:Forms.Entry -> @phase:Surfaces.Phase -> {Appearance.phase_background(Appearance.widget_field_style(Controls.MessageInput{}, entry, typography), phase) == Design.SurfacePaint{Surfaces.EmbeddedField{}, phase} : Design.Paint},
    board_search_surface: @+typography:T.Presentation -> @filter:Board.Filter -> {Appearance.style_background(Appearance.field_style(SurfaceTypes.BoardSearch{filter}, typography)) == Design.SurfacePaint{Surfaces.Inset{}, Surfaces.Rest{}} : Design.Paint},
    selected_control_phase: @+typography:T.Presentation -> @value:Design.Style -> @phase:Surfaces.Phase -> {Appearance.phase_background(Appearance.selection_style(value, Controls.Radio{True{}}, typography), phase) == Design.SurfacePaint{Surfaces.Choice{True{}}, phase} : Design.Paint},
    toggle_control_phase: @+typography:T.Presentation -> @value:Design.Style -> @phase:Surfaces.Phase -> {Appearance.phase_background(Appearance.selection_style(value, Controls.Toggle{True{}}, typography), phase) == Design.SurfacePaint{Surfaces.Choice{True{}}, phase} : Design.Paint},
    menu_choice_phase: @+typography:T.Presentation -> @value:Design.Style -> @phase:Surfaces.Phase -> {Appearance.phase_background(Appearance.selection_style(value, Controls.ChoiceRadio{True{}}, typography), phase) == Design.SurfacePaint{Surfaces.Choice{True{}}, phase} : Design.Paint}}

law surface_evidence:
  SurfaceRequirements

def bit(value: Bool) -> Nat:
  match value:
    case True{}: 1n
    case False{}: 0n

def occurrences(nodes: +List<SurfaceTypes.Node>, +key: String) -> Nat:
  match nodes:
    case Nil{}: 0n
    case Con{SurfaceTypes.Node{+current, semantic, label, role, meaning, children}, rest}:
      Nat.add(bit(String.eq(UIIdentity.encode(current), key)),
        Nat.add(occurrences(children, key), occurrences(rest, key)))

def surface_occurrences(surface: SurfaceTypes.Surface, +key: String) -> Nat:
  SurfaceTypes.Surface{content, base, overlays, scope} = surface
  Nat.add(occurrences(base, key), occurrences(overlays, key))

type PersistentTriggerRequirements is Type:
  PersistentTriggerRequirements{
    removal: @nodes:+List<SurfaceTypes.Node> -> @+key:String -> {occurrences(InterfaceView.without_node(nodes, key), key) == 0n : Nat},
    actual_source: @+scene:InteractionTypes.Scene -> @+base:+List<SurfaceTypes.Node> -> @+overlays:+List<SurfaceTypes.Node> -> @+trigger:String -> @+key:String -> @+node:SurfaceTypes.Node -> @+target:Nat ->
      @persistent:{InterfaceView.persistent_details_trigger(overlays) == Some{SurfaceTypes.PersistentTrigger{target, trigger}} : Maybe<&2, SurfaceTypes.PersistentTrigger>} ->
      @resolved:{InterfaceView.matching_focus(base, trigger) == Some{key} : Maybe<&2, String>} ->
      @found:{InterfaceView.find_node(base, key) == Some{node} : Maybe<&2, SurfaceTypes.Node>} ->
      {InterfaceView.finish_reachable(scene, base, overlays) == InterfaceView.relocate_found_trigger(Some{node}, target, scene, base, overlays) : SurfaceTypes.Surface},
    unique_trigger: @+scene:InteractionTypes.Scene -> @+base:+List<SurfaceTypes.Node> -> @+key:UIIdentity.Key -> @+semantic:String -> @+label:String -> @+role:SurfaceTypes.Role ->
      @+meaning:SurfaceTypes.Meaning -> @+owner:UIIdentity.Key -> @+layer_semantic:String -> @+title:String -> @+policy:SurfaceTypes.Meaning ->
      @+body:+List<SurfaceTypes.Node> -> @+rest:+List<SurfaceTypes.Node> -> @+target:Nat ->
      @accepted:{InterfaceView.persistent_trigger_source(meaning, target) == True{} : Bool} -> @distinct:{String.eq(UIIdentity.encode(owner), UIIdentity.encode(key)) == False{} : Bool} ->
      @fresh:{Nat.add(occurrences(body, UIIdentity.encode(key)), occurrences(rest, UIIdentity.encode(key))) == 0n : Nat} ->
      {surface_occurrences(InterfaceView.relocate_found_trigger(Some{SurfaceTypes.Node{key, semantic, label, role, meaning, Nil{}}}, target,
        scene, base, SurfaceTypes.Node{owner, layer_semantic, title, SurfaceTypes.Dialog{}, policy, body} <> rest), UIIdentity.encode(key)) == 1n : Nat},
    production_details: @+task:Nat -> @+trigger:String -> @+content:View.LayerContent -> @+initial:String -> @+state:InteractionTypes.State ->
      {InterfaceView.persistent_details_trigger(InterfaceView.layers([View.Layer{View.ModalDialog{}, content, initial, trigger,
        View2.layer_dismissal(User.TaskDetails{task}, trigger)}], state)) == Some{SurfaceTypes.PersistentTrigger{task, trigger}} : Maybe<&2, SurfaceTypes.PersistentTrigger>},
    wrong_task_stays: @+scene: InteractionTypes.Scene -> @+base: +List<SurfaceTypes.Node> -> @+overlays: +List<SurfaceTypes.Node> -> @+key: UIIdentity.Key -> @+semantic: String -> @+label: String -> @+role: SurfaceTypes.Role -> @+expanded: Bool -> @+source: Nat -> @+trigger: String -> @+availability: View.Availability -> @+children: +List<SurfaceTypes.Node> -> @+target: Nat -> @distinct: {Nat.is_eq(source, target) == False{} : Bool} ->
    {InterfaceView.relocate_found_trigger(Some{SurfaceTypes.Node{key, semantic, label, role,
            SurfaceTypes.PanelToggle{expanded, InteractionTypes.ApplicationInput{Experience.UserInput{User.Activate{User.TogglePanel{User.TaskDetails{source}, trigger}}}}, availability}, children}},
          target, scene, base, overlays) == InterfaceView.finish(scene, base, overlays) : SurfaceTypes.Surface},
    wrong_input_stays: @+scene: InteractionTypes.Scene -> @+base: +List<SurfaceTypes.Node> -> @+overlays: +List<SurfaceTypes.Node> -> @+key: UIIdentity.Key -> @+semantic: String -> @+label: String -> @+role: SurfaceTypes.Role -> @+expanded: Bool -> @+service: Services.Input -> @+availability: View.Availability -> @+children: +List<SurfaceTypes.Node> -> @+target: Nat ->
    {InterfaceView.relocate_found_trigger(Some{SurfaceTypes.Node{key, semantic, label, role,
            SurfaceTypes.PanelToggle{expanded, InteractionTypes.ServiceInput{service}, availability}, children}}, target, scene, base, overlays) ==
          InterfaceView.finish(scene, base, overlays) : SurfaceTypes.Surface},
    navigation_kept: @+scene: InteractionTypes.Scene -> @+nav: +List<SurfaceTypes.Node> -> @+reachable: SurfaceTypes.Surface -> @+settings: SurfaceTypes.Node -> @+scope: Maybe<&2, String> ->
    {InterfaceView.surface_base(InterfaceView.with_navigation(scene, nav, reachable, settings, scope)) ==
    List.append(&2, SurfaceTypes.Node, nav, List.append(&2, SurfaceTypes.Node, InterfaceView.surface_base(reachable), [settings])) : +List<SurfaceTypes.Node>},
    rejected_source_stays: @+scene: InteractionTypes.Scene -> @+base: +List<SurfaceTypes.Node> -> @+overlays: +List<SurfaceTypes.Node> -> @+key: UIIdentity.Key -> @+semantic: String -> @+label: String -> @+role: SurfaceTypes.Role -> @+meaning: SurfaceTypes.Meaning -> @+children: +List<SurfaceTypes.Node> -> @+target: Nat -> @rejected: {InterfaceView.persistent_trigger_source(meaning, target) == False{} : Bool} ->
    {InterfaceView.relocate_found_trigger(Some{SurfaceTypes.Node{key, semantic, label, role, meaning, children}}, target, scene, base, overlays) ==
    InterfaceView.finish(scene, base, overlays) : SurfaceTypes.Surface},
    accepted_same_node: @+scene: InteractionTypes.Scene -> @+base: +List<SurfaceTypes.Node> -> @+overlays: +List<SurfaceTypes.Node> -> @+key: UIIdentity.Key -> @+semantic: String -> @+label: String -> @+role: SurfaceTypes.Role -> @+meaning: SurfaceTypes.Meaning -> @+children: +List<SurfaceTypes.Node> -> @+target: Nat -> @accepted: {InterfaceView.persistent_trigger_source(meaning, target) == True{} : Bool} ->
    {InterfaceView.relocate_found_trigger(Some{SurfaceTypes.Node{key, semantic, label, role, meaning, children}}, target, scene, base, overlays) ==
    InterfaceView.relocate_valid_trigger(True{}, SurfaceTypes.Node{key, semantic, label, role, meaning, children}, scene, base, overlays) : SurfaceTypes.Surface}}

law persistent_trigger_evidence:
  PersistentTriggerRequirements

def layout_insets(layout: Controls.ContentLayout) -> (Nat & (Nat & Nat)):
  Controls.ContentLayout{alignment, +content_area, gap} = layout
  (E.inline(content_area), (E.block(content_area), gap))

def first_caption(values: +List<S.Node>) -> Maybe<&2, S.Node>:
  match values:
    case Con{S.Text{key,text,font,wrapping}, rest}: Some{S.Text{key,text,font,wrapping}}
    case _: None{}

def trigger_caption(values: +List<S.Node>) -> Maybe<&2, S.Node>:
  match values:
    case Nil{}: None{}
    case Con{S.Text{key,text,font,wrapping}, rest}: Some{S.Text{key,text,font,wrapping}}
    case Con{S.Box{key,tag,style,attributes,children}, rest}: first_caption(children)
    case Con{node, rest}: trigger_caption(rest)

law picker_caption_single_line:
  for leading: Maybe<&2,Controls.Icon>
  for text: String
  {Controls.caption_wrapping(Controls.PickerFace{leading,text}) == T.SingleLine{} : T.Wrapping}

law disclosure_caption_single_line:
  for text: String
  for expanded: Bool
  {Controls.caption_wrapping(Controls.DisclosureFace{text,expanded}) == T.SingleLine{} : T.Wrapping}

law picker_face_caption:
  for +key: UIIdentity.Key
  for +text: String
  for +parent: Design.Style
  for leading: Maybe<&2,Controls.Icon>
  for geometry: Controls.Geometry
  {trigger_caption(A.face(key,Controls.PickerFace{leading,text},parent,geometry)) ==
    Some{S.Text{UIIdentity.part(key,"caption"),text,S.ExplicitFont{A.parent_font(parent)},T.SingleLine{}}} : Maybe<&2,S.Node>}

law disclosure_face_caption:
  for +key: UIIdentity.Key
  for +text: String
  for +parent: Design.Style
  for expanded: Bool
  for geometry: Controls.Geometry
  {trigger_caption(A.face(key,Controls.DisclosureFace{text,expanded},parent,geometry)) ==
    Some{S.Text{UIIdentity.part(key,"caption"),text,S.ExplicitFont{A.parent_font(parent)},T.SingleLine{}}} : Maybe<&2,S.Node>}

law unbroken_caption:
  for text: String
  {Controls.caption_wrapping(Controls.UnbrokenFace{text}) == T.UnbrokenLine{} : T.Wrapping}

law unbroken_face_caption:
  for +key: UIIdentity.Key
  for +text: String
  for +parent: Design.Style
  for geometry: Controls.Geometry
  {A.face(key,Controls.UnbrokenFace{text},parent,geometry) ==
    [S.Text{UIIdentity.part(key,"caption"),text,S.ExplicitFont{A.parent_font(parent)},T.UnbrokenLine{}}] : +List<S.Node>}

type ControlContentRequirements is Type:
  ControlContentRequirements{
    enabled_matches_interface: @+availability:View.Availability ->
      {A.enabled(availability) == InterfaceView.available(availability) : Bool},
    choice_caption_words: @text:String -> @description:Maybe<&2,String> -> @icon:Maybe<&2,Controls.Icon> -> @checked:Bool ->
      {Controls.caption_wrapping(Controls.ChoiceFace{text,description,icon,checked}) == T.NormalWords{} : T.Wrapping},
    choice_description_words: {Controls.description_wrapping() == T.NormalWords{} : T.Wrapping},
    single_line_caption: @text:String ->
      {Controls.caption_wrapping(Controls.SingleLineFace{text}) == T.SingleLine{} : T.Wrapping},
    choice_caption_source: @+key:UIIdentity.Key -> @+text:String -> @+parent:Design.Style -> @description:Maybe<&2,String> -> @icon:Maybe<&2,Controls.Icon> -> @checked:Bool ->
      {A.caption(key,text,parent,Controls.caption_wrapping(Controls.ChoiceFace{text,description,icon,checked})) ==
        S.Text{key,text,S.ExplicitFont{A.parent_font(parent)},T.NormalWords{}} : S.Node},
    choice_description_source: @+key:UIIdentity.Key -> @+text:String -> @+parent:Design.Style ->
      {A.face_description(Some{text},key,parent) ==
        [S.Text{UIIdentity.part(key,"description"),text,S.ExplicitFont{T.supporting(A.parent_font(parent))},T.NormalWords{}}] : +List<S.Node>},
    permission_layout: @filesystem:Controls.Icon -> @network:Controls.Icon -> @approval:Controls.Icon ->
      {Controls.content_layout(Controls.PermissionFace{filesystem, network, approval}) == Controls.ContentLayout{Spatial.LeadingContents{}, E.area(E.TextControl{}), 6n} : Controls.ContentLayout},
    icon_layout: @icon:Controls.Icon ->
      {Controls.content_layout(Controls.IconFace{icon}) == Controls.ContentLayout{Spatial.CenterContents{}, E.area(E.IconControl{}), 0n} : Controls.ContentLayout},
    picker_layout: @+leading:Maybe<&2, Controls.Icon> -> @label:String ->
      {Controls.content_layout(Controls.PickerFace{leading, label}) == Controls.ContentLayout{Spatial.LeadingContents{}, E.area(E.TextControl{}), 6n} : Controls.ContentLayout},
    appearance_consumes_layout: @text:T.Presentation -> @chrome:Design.Chrome -> @alignment:Spatial.Alignment -> @flow:Spatial.Flow -> @overflow:Spatial.Overflow -> @content_area:E.ContentArea -> @gap:Nat -> @height:Nat -> @maximum:Nat -> @states:Design.ControlStates -> @face:Controls.Face -> @size:Controls.Geometry ->
      {SpaceRules.frame_coordinates(Design.style_frame(Appearance.action_style(Design.Style{text, chrome, alignment, flow, overflow, E.Frame{content_area, E.EmbeddedContent{gap}}, height, maximum, states}, face, size))) == layout_insets(Controls.content_layout(face)) : (Nat & (Nat & Nat))}}

law control_content_evidence:
  ControlContentRequirements

law unbroken_icon_caption:
  for icon: Controls.Icon
  for text: String
  {Controls.caption_wrapping(Controls.UnbrokenIconTextFace{icon,text}) == T.UnbrokenLine{} : T.Wrapping}

law unbroken_icon_face_caption:
  for +key: UIIdentity.Key
  for icon: Controls.Icon
  for +text: String
  for +parent: Design.Style
  for geometry: Controls.Geometry
  {trigger_caption(A.face(key,Controls.UnbrokenIconTextFace{icon,text},parent,geometry)) ==
    Some{S.Text{UIIdentity.part(key,"caption"),text,S.ExplicitFont{A.parent_font(parent)},T.UnbrokenLine{}}} : Maybe<&2,S.Node>}

law named_text_caption:
  for text: String
  for compact: Bool
  {Controls.named_face(None{},text,compact) == Controls.UnbrokenFace{text} : Controls.Face}

law named_icon_caption:
  for icon: Controls.Icon
  for text: String
  {Controls.named_face(Some{icon},text,False{}) == Controls.UnbrokenIconTextFace{icon,text} : Controls.Face}

def source_binding(+meaning: SurfaceTypes.Meaning) -> SurfaceTypes.Meaning:
  match meaning:
    case SurfaceTypes.PageRegion{region, position}: SurfaceTypes.Region{}
    case SurfaceTypes.Region{}: SurfaceTypes.Region{}
    case SurfaceTypes.LayerRegion{dismiss, outside, escape}: SurfaceTypes.Region{}
    case SurfaceTypes.PanelToggle{expanded, input, availability}: SurfaceTypes.Activate{input, availability}
    case SurfaceTypes.ProjectGroup{project, selected, expanded}: SurfaceTypes.Region{}
    case SurfaceTypes.TaskRow{task, status, selected}: SurfaceTypes.Region{}
    case SurfaceTypes.ProjectChooser{selected}: SurfaceTypes.Region{}
    case SurfaceTypes.DirectoryRow{path, primary}: SurfaceTypes.Region{}
    case SurfaceTypes.ContextSummary{observation}: SurfaceTypes.Region{}
    case SurfaceTypes.ChoiceGroup{}: SurfaceTypes.Region{}
    case SurfaceTypes.ComposerAction{subject, input, availability}: SurfaceTypes.Activate{input, availability}
    case SurfaceTypes.Choice{kind, icon, selected, description, input, availability}: SurfaceTypes.Activate{input, availability}
    case SurfaceTypes.BoardLane{stage, count}: SurfaceTypes.Region{}
    case SurfaceTypes.CardArchive{count}: SurfaceTypes.Region{}
    case SurfaceTypes.CardContent{face}: SurfaceTypes.Region{}
    case SurfaceTypes.BoardGroup{grouping}: SurfaceTypes.Region{}
    case SurfaceTypes.ReadOnly{text}: SurfaceTypes.Region{}
    case SurfaceTypes.Fact{value}: SurfaceTypes.Region{}
    case SurfaceTypes.RichText{source, value}: SurfaceTypes.Region{}
    case SurfaceTypes.TaskFacts{details}: SurfaceTypes.Region{}
    case SurfaceTypes.CodeFacts{view}: SurfaceTypes.Region{}
    case SurfaceTypes.ActivityContent{expanded, audit}: SurfaceTypes.Region{}
    case SurfaceTypes.PageContext{conversation}: SurfaceTypes.Region{}
    case SurfaceTypes.Edit{editor, field, Forms.DirectoryCollection{}, value, choices}: SurfaceTypes.Region{}
    case SurfaceTypes.Edit{editor, field, Forms.FileCollection{}, value, choices}: SurfaceTypes.Region{}
    case _: meaning

def binding(representation: Controls.Representation) -> SurfaceTypes.Meaning:
  match representation:
    case Controls.NoControl{}: SurfaceTypes.Region{}
    case Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}:
      SurfaceTypes.Activate{input, availability}
    case Controls.Input{meaning, name, widget, label, availability}: meaning
    case Controls.Movable{destinations, face, name, handle, geometry, help}: SurfaceTypes.MovableCard{destinations, face}

type ContextControlRequirements is Type:
  ContextControlRequirements{
    choice_binding: @+key:UIIdentity.Key -> @kind:SurfaceTypes.ChoiceKind -> @classification:Maybe<&2, Filter.Classification> -> @+selected:Bool -> @description:String -> @+input:InteractionTypes.Input -> @+availability:View.Availability -> @+label:String -> @role:SurfaceTypes.Role -> @context:Controls.Context ->
      {binding(Controls.represent(key, SurfaceTypes.Choice{kind, classification, selected, description, input, availability}, label, role, context)) == SurfaceTypes.Activate{input, availability} : SurfaceTypes.Meaning},
    choice_interactive: @kind:SurfaceTypes.ChoiceKind -> @classification:Maybe<&2, Filter.Classification> -> @+selected:Bool -> @description:String -> @+input:InteractionTypes.Input -> @+availability:View.Availability -> {Observed.interactive(SurfaceTypes.Choice{kind, classification, selected, description, input, availability}) == True{} : Bool},
    choice_enabled: @kind:SurfaceTypes.ChoiceKind -> @classification:Maybe<&2, Filter.Classification> -> @+selected:Bool -> @description:String -> @+input:InteractionTypes.Input -> @+availability:View.Availability -> {Observed.required_enabled(SurfaceTypes.Choice{kind, classification, selected, description, input, availability}) == Observed.enabled(availability) : Bool},
    choice_observed_tabs: @+key:UIIdentity.Key -> @semantic:String -> @+label:String -> @role:SurfaceTypes.Role -> @kind:SurfaceTypes.ChoiceKind -> @classification:Maybe<&2, Filter.Classification> -> @+selected:Bool -> @description:String -> @+input:InteractionTypes.Input -> @+availability:View.Availability -> @+elements:+List<Observed.Element> -> @+native_focus:+List<Observed.NativeFocus> ->
      {Observed.expected_tabs([SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.Choice{kind, classification, selected, description, input, availability}, Nil{}}], elements, native_focus) == Observed.tab_entry(Observed.enabled(availability) && Observed.tab_stop(Observed.find_element(elements, UIIdentity.encode(key))), UIIdentity.encode(key), Nil{}) : +List<String>},
    workspace_label: @+label:String -> @expanded:Bool -> {Controls.face_for(Controls.WorkspacePicker{expanded}, label, Controls.ComposerArea{}) == Controls.PickerFace{Some{Controls.Folder{}}, label} : Controls.Face},
    permissions_label: @+label:String -> @current:Controls.Face -> @+execution:Maybe<&2,Context.Observation> -> {Controls.composer_face(View.PermissionsSubject{}, label, current, execution) == Controls.permission_face(execution) : Controls.Face},
    initial_execution: @+content:InteractionTypes.Scene -> {execution_observation(Controls.initial(content)) == page_observation(content) : Maybe<&2,Context.Observation>},
    draft_permission_face: @+origin:Context.Origin -> @+project:Maybe<&2,Nat> -> @+workspace:Context.WorkspaceValue -> @+sandbox:Context.SandboxValue -> @+approval:Context.ApprovalValue -> @+guidance:Context.GuidancePreview -> {Controls.permission_face(Some{Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}}) == Controls.permission_values_face(Context.unwrap_sandbox(sandbox), Context.observed_approval(approval)) : Controls.Face},
    committed_permission_face: @+task:Nat -> @+workspace:Domain.Workspace -> @+sandbox:Domain.Sandbox -> @+approval:Domain.ApprovalPolicy -> @+project:Maybe<&2,Nat> -> @+guidance:Domain.ProjectContext -> @+access:Domain.ExecutionAccess -> {Controls.permission_face(Some{Context.CommittedExecution{Context.EffectiveContext{task, Domain.TaskContext{workspace, sandbox, approval, project}, guidance, access}}}) == Controls.permission_values_face(sandbox, Context.approval_choice(approval)) : Controls.Face},
    unavailable_permission_face: @+reason:String -> {Controls.permission_face(Some{Context.DraftExecution{Context.ContextUnavailable{reason}}}) == Controls.IconFace{Controls.Warning{}} : Controls.Face},
    permission_accessible_name: @+label:String -> {Controls.composer_name(View.PermissionsSubject{}, label) == "Permissions: " ++ label : String},
    permission_help: @+filesystem:Controls.Icon -> @+network:Controls.Icon -> @+approval:Controls.Icon -> @+name:String -> {Controls.help_for(Controls.PermissionFace{filesystem, network, approval}, View.Available{}, Controls.Quiet{}, name) == Controls.tooltip(name) : Controls.Help},
    delivery_send_face: @+label:String -> @current:Controls.Face -> @execution:Maybe<&2,Context.Observation> -> {Controls.composer_face(View.DeliverySubject{User.Send{}}, label, current, execution) == Controls.IconFace{Controls.ArrowUp{}} : Controls.Face},
    delivery_steer_face: @+label:String -> @current:Controls.Face -> @execution:Maybe<&2,Context.Observation> -> {Controls.composer_face(View.DeliverySubject{User.Steer{}}, label, current, execution) == Controls.IconFace{Controls.Branch{}} : Controls.Face},
    filesystem_write_icon: {Controls.filesystem_icon(Domain.WorkspaceWrite{}) == Controls.Pencil{} : Controls.Icon},
    filesystem_read_icon: {Controls.filesystem_icon(Domain.ReadOnly{}) == Controls.Eye{} : Controls.Icon},
    network_enabled_icon: {Controls.network_icon(True{}) == Controls.Globe{} : Controls.Icon},
    network_disabled_icon: {Controls.network_icon(False{}) == Controls.GlobeOff{} : Controls.Icon},
    ask_approval_icon: {Controls.approval_icon(Context.Ask{}) == Controls.Hand{} : Controls.Icon},
    unrestricted_approval_icon: {Controls.approval_icon(Context.Unrestricted{}) == Controls.Shield{} : Controls.Icon},
    automatic_approval_icon: @+profile:String -> {Controls.approval_icon(Context.AutomaticReview{profile}) == Controls.ShieldCode{} : Controls.Icon}}

law context_control_evidence:
  ContextControlRequirements

type BoundNode is Data:
  BoundNode{key: UIIdentity.Key, binding: SurfaceTypes.Meaning, children: +List<BoundNode>}

type Bindings is Data:
  Bindings{base: +List<BoundNode>, overlays: +List<BoundNode>}

def source_nodes(values: +List<SurfaceTypes.Node>) -> +List<BoundNode>:
  match values:
    case Nil{}: Nil{}
    case Con{SurfaceTypes.Node{key, semantic, label, role, meaning, children}, rest}:
      Con{BoundNode{key, source_binding(meaning), source_nodes(children)}, source_nodes(rest)}

def presented_nodes(values: +List<Design.Node>) -> +List<BoundNode>:
  match values:
    case Nil{}: Nil{}
    case Con{Design.Node{key, semantic, label, role, meaning, style, control, children}, rest}:
      Con{BoundNode{key, binding(control), presented_nodes(children)}, presented_nodes(rest)}

def visual_bindings(visuals: Design.Surface) -> Bindings:
  Design.Surface{content, theme, base, overlays, active_scope} = visuals
  Bindings{presented_nodes(base), presented_nodes(overlays)}

def surface_bindings(surface: SurfaceTypes.Surface) -> Bindings:
  SurfaceTypes.Surface{content, base, overlays, active_scope} = surface
  Bindings{source_nodes(base), source_nodes(overlays)}

def expected_icon_help(availability: View.Availability, label: String) -> Controls.Help:
  match availability:
    case View.Available{}: Controls.Tooltip{label, 300n, True{}, True{}, False{}}
    case View.NeedsDirectoryObservation{}: Controls.Tooltip{label, 300n, True{}, True{}, False{}}
    case View.Unavailable{reason}: Controls.Tooltip{reason, 300n, True{}, True{}, False{}}

# Message editors share the arrow form across Send/Steer. The action identity,
# name, availability, and disabled explanation remain those of that observation.

def expected_message(+editor: User.Editor, +availability: View.Availability, +label: String) -> Controls.Representation:
  Controls.Action{InteractionTypes.ApplicationInput{Experience.UserInput{User.Activate{User.Submit{editor}}}},
    availability, label, Controls.IconFace{Controls.ArrowUp{}}, Controls.Push{},
    Controls.Geometry{Space.fixed_demand(32n, 32n), 16n, 16n, 0n}, Controls.ComposerEnd{},
    expected_icon_help(availability, label), Controls.Quiet{}}

def message_uses_arrow_law(-key: UIIdentity.Key, -task: Nat, -availability: View.Availability, -label: String, -role: SurfaceTypes.Role, -selection: Controls.Selection, -code: Maybe<&2, Code.Scene>, -appearance: Services.Appearance, -access: Services.Access, -open: Bool, -layers: +List<View.Layer>) -> Type:
  {Controls.represent(key, SurfaceTypes.Activate{InteractionTypes.ApplicationInput{Experience.UserInput{User.Activate{User.Submit{User.MessageEditor{task}}}}}, availability},
      label, role, Controls.Context{Controls.ComposerArea{}, selection, code, appearance, access, open, layers, None{}, Controls.Unscoped{}}) ==
      expected_message(User.MessageEditor{task}, availability, label) : Controls.Representation}

def creation_uses_arrow_law(-key: UIIdentity.Key, -availability: View.Availability, -label: String, -role: SurfaceTypes.Role, -selection: Controls.Selection, -code: Maybe<&2, Code.Scene>, -appearance: Services.Appearance, -access: Services.Access, -open: Bool, -layers: +List<View.Layer>) -> Type:
  {Controls.represent(key, SurfaceTypes.Activate{InteractionTypes.ApplicationInput{Experience.UserInput{User.Activate{User.Submit{User.NewTaskEditor{}}}}}, availability},
      label, role, Controls.Context{Controls.ComposerArea{}, selection, code, appearance, access, open, layers, None{}, Controls.Unscoped{}}) ==
      expected_message(User.NewTaskEditor{}, availability, label) : Controls.Representation}

def menu_text(face: Controls.Face) -> Maybe<&2, String>:
  match face:
    case Controls.IconFace{icon}: None{}
    case Controls.TextFace{text}: Some{text}
    case Controls.UnbrokenFace{text}: Some{text}
    case Controls.SingleLineFace{text}: Some{text}
    case Controls.IconTextFace{icon, text}: Some{text}
    case Controls.UnbrokenIconTextFace{icon, text}: Some{text}
    case Controls.PickerFace{icon, text}: Some{text}
    case Controls.ChoiceFace{text, description, icon, checked}: Some{text}
    case Controls.DisclosureFace{text, expanded}: Some{text}
    case Controls.PermissionFace{filesystem, network, approval}: None{}

def required_menu_text(purpose: Controls.Purpose, label: String) -> Maybe<&2, String>:
  match purpose:
    case Controls.Dismiss{}: None{}
    case _: Some{label}

type Choice is Data:
  Choice{face: Controls.Face, behavior: Controls.Behavior}

def choice(representation: Controls.Representation) -> Maybe<&2, Choice>:
  match representation:
    case Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}:
      Some{Choice{face, behavior}}
    case _: None{}

def action_text(representation: Controls.Representation) -> Maybe<&2, String>:
  match representation:
    case Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}: menu_text(face)
    case _: None{}

def action_face(representation: Controls.Representation) -> Maybe<&2, Controls.Face>:
  match representation:
    case Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}: Some{face}
    case _: None{}

def declared_action_face(node: SurfaceTypes.Node, context: Controls.Context) -> Maybe<&2, Controls.Face>:
  SurfaceTypes.Node{key, semantic, label, role, meaning, children} = node
  action_face(Controls.represent(key, meaning, label, role, context))

def root_removal_faces(roots: +List<View.WorkspaceRoot>, +parent: UIIdentity.Key, +state: InteractionTypes.State,
  +context: Controls.Context) -> +List<Maybe<&2, Controls.Face>>:
  match roots:
    case Nil{}: Nil{}
    case Con{View.WorkspaceRoot{path, primary, choose, remove}, rest}:
      declared_action_face(InterfaceView.declared(parent, remove, state), context) <> root_removal_faces(rest, parent, state, context)

def workspace_removal_faces(workspace: View.WorkspaceControls, parent: UIIdentity.Key, state: InteractionTypes.State,
  context: Controls.Context) -> +List<Maybe<&2, Controls.Face>>:
  View.WorkspaceControls{editor, roots, inherit} = workspace
  root_removal_faces(roots, parent, state, context)

def approval_keeps_label_law(-key: UIIdentity.Key, -task: Nat, -operation: Nat, -allow: Bool, -reason: String, -availability: View.Availability, -label: String, -role: SurfaceTypes.Role, -selection: Controls.Selection, -code: Maybe<&2, Code.Scene>, -appearance: Services.Appearance, -access: Services.Access, -open: Bool, -layers: +List<View.Layer>) -> Type:
  {action_text(Controls.represent(key, SurfaceTypes.Activate{InteractionTypes.ApplicationInput{Experience.UserInput{
      User.Activate{User.ReviewApproval{task, operation, allow, reason}}}}, availability}, label, role,
      Controls.Context{Controls.ApprovalArea{}, selection, code, appearance, access, open, layers, None{}, Controls.Unscoped{}})) ==
      Some{label} : Maybe<&2, String>}

type HelpAccess is Data:
  HelpAccess{pointer: Bool, keyboard: Bool, takes_focus: Bool}

def help_access(help: Controls.Help) -> HelpAccess:
  match help:
    case Controls.NoHelp{}: HelpAccess{False{}, False{}, False{}}
    case Controls.Tooltip{text, delay, pointer, keyboard, takes_focus}:
      HelpAccess{pointer, keyboard, takes_focus}

type Requirements is Type:
  Requirements{
    present_retains_bindings: @+scale:T.Scale -> @surface:SurfaceTypes.Surface -> @system_dark:Bool ->
      {visual_bindings(Appearance.present(surface, system_dark, scale)) == surface_bindings(surface) : Bindings},
    message_uses_arrow: @+key:UIIdentity.Key -> @task:Nat -> @+availability:View.Availability -> @+label:String -> @role:SurfaceTypes.Role ->
      @selection:Controls.Selection -> @code:Maybe<&2, Code.Scene> -> @appearance:Services.Appearance ->
      @access:Services.Access -> @open:Bool -> @layers:+List<View.Layer> ->
      message_uses_arrow_law(key, task, availability, label, role, selection, code, appearance, access, open, layers),
    creation_uses_arrow: @+key:UIIdentity.Key -> @+availability:View.Availability -> @+label:String -> @role:SurfaceTypes.Role ->
      @selection:Controls.Selection -> @code:Maybe<&2, Code.Scene> -> @appearance:Services.Appearance ->
      @access:Services.Access -> @open:Bool -> @layers:+List<View.Layer> ->
      creation_uses_arrow_law(key, availability, label, role, selection, code, appearance, access, open, layers),
    menu_preserves_labels: @+purpose:Controls.Purpose -> @+label:String ->
      {menu_text(Controls.face_for(purpose, label, Controls.MenuArea{})) == required_menu_text(purpose, label) : Maybe<&2, String>},
    copy_keeps_space: @state:Code.CopyState ->
      {Controls.geometry_for(Controls.CopyCode{state}, Controls.face_for(Controls.CopyCode{state}, "Copy code", Controls.CodeArea{}), Controls.CodeArea{}) ==
        Controls.Geometry{Space.fixed_demand(32n, 32n), 16n, 8n, 0n} : Controls.Geometry},
    radio_reserves_check: @label:String -> @checked:Bool ->
      {Controls.geometry_for(Controls.SelectedOption{checked}, Controls.ChoiceFace{label, None{}, None{}, checked}, Controls.MenuArea{}) ==
        Controls.Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 20n} : Controls.Geometry},
    model_option_marks_current: @+key:UIIdentity.Key -> @editor:User.Editor -> @+profile:String -> @reasoning:String ->
      @+current:String -> @+label:String -> @role:SurfaceTypes.Role -> @code:Maybe<&2, Code.Scene> ->
      @appearance:Services.Appearance -> @access:Services.Access -> @open:Bool -> @layers:+List<View.Layer> ->
      {choice(Controls.represent(key, SurfaceTypes.Activate{InteractionTypes.ApplicationInput{Experience.UserInput{
          User.EditDraft{editor, User.ChooseModel{profile, reasoning}}}}, View.Available{}}, label, role,
          Controls.Context{Controls.MenuArea{}, Controls.ModelSelection{current}, code, appearance, access, open, layers, None{}, Controls.Unscoped{}})) ==
          Some{Choice{Controls.ChoiceFace{label, None{}, None{}, String.eq(profile, current)}, Controls.Radio{String.eq(profile, current)}}} : Maybe<&2, Choice>},
    delivery_option_marks_current: @+key:UIIdentity.Key -> @task:Nat -> @+delivery:User.Delivery -> @+current:User.Delivery ->
      @+label:String -> @role:SurfaceTypes.Role -> @code:Maybe<&2, Code.Scene> -> @appearance:Services.Appearance ->
      @access:Services.Access -> @open:Bool -> @layers:+List<View.Layer> ->
      {choice(Controls.represent(key, SurfaceTypes.Activate{InteractionTypes.ApplicationInput{Experience.UserInput{
          User.EditDraft{User.MessageEditor{task}, User.ChooseDelivery{delivery}}}}, View.Available{}}, label, role,
          Controls.Context{Controls.MenuArea{}, Controls.DeliverySelection{current}, code, appearance, access, open, layers, None{}, Controls.Unscoped{}})) ==
          Some{Choice{Controls.ChoiceFace{label, None{}, None{}, Controls.same_delivery(delivery, current)},
            Controls.Radio{Controls.same_delivery(delivery, current)}}} : Maybe<&2, Choice>},
    approval_keeps_label: @key:UIIdentity.Key -> @task:Nat -> @operation:Nat -> @allow:Bool -> @reason:String ->
      @availability:View.Availability -> @+label:String -> @role:SurfaceTypes.Role -> @selection:Controls.Selection ->
      @code:Maybe<&2, Code.Scene> -> @appearance:Services.Appearance -> @access:Services.Access -> @open:Bool -> @layers:+List<View.Layer> ->
      approval_keeps_label_law(key, task, operation, allow, reason, availability, label, role, selection, code, appearance, access, open, layers),
    icon_help_supports_focus: @icon:Controls.Icon -> @availability:View.Availability -> @feedback:Controls.Feedback -> @label:String ->
      {help_access(Controls.help_for(Controls.IconFace{icon}, availability, feedback, label)) ==
        HelpAccess{True{}, True{}, False{}} : HelpAccess},
    input_label_is_accessible_only: @value:Forms.Observed ->
      {Controls.label_placement(Controls.widget_for(Forms.Multiline{}, Forms.MessageText{}, value)) ==
        Controls.AccessibleOnly{} : Controls.LabelPlacement},
    settings_uses_gear: @expanded:Bool -> @label:String ->
      {Controls.face_for(Controls.OpenPanel{Controls.Settings{}, False{}, expanded}, label, Controls.PageArea{}) == Controls.IconFace{Controls.Settings{}} : Controls.Face},
    introduction_uses_context_label: @expanded:Bool -> @+label:String ->
      {Controls.face_for(Controls.WorkspacePicker{expanded}, label, Controls.ComposerArea{}) == Controls.PickerFace{Some{Controls.Folder{}}, label} : Controls.Face},
    directory_removal_uses_cross: @+parent:UIIdentity.Key -> @+editor:User.Editor -> @+path:String ->
      @primary:Maybe<&2, String> -> @state:InteractionTypes.State -> @context:Controls.Context ->
      {workspace_removal_faces(View2.workspace_controls(Domain.Workspace{[path], primary}, editor, None{}),
        parent, state, context) == [Some{Controls.IconFace{Controls.CloseCross{}}}] : +List<Maybe<&2, Controls.Face>>},
    directory_parent_has_no_control: @choices:+List<Forms.ChoiceValue> -> @key:UIIdentity.Key -> @editor:User.Editor -> @field:Forms.Field -> @value:Forms.Observed -> @label:String -> @role:SurfaceTypes.Role -> @context:Controls.Context ->
      {Controls.represent(key, SurfaceTypes.Edit{editor, field, Forms.DirectoryCollection{}, value, choices}, label, role, context) == Controls.NoControl{} : Controls.Representation},
    file_parent_has_no_control: @choices:+List<Forms.ChoiceValue> -> @key:UIIdentity.Key -> @editor:User.Editor -> @field:Forms.Field -> @value:Forms.Observed -> @label:String -> @role:SurfaceTypes.Role -> @context:Controls.Context ->
      {Controls.represent(key, SurfaceTypes.Edit{editor, field, Forms.FileCollection{}, value, choices}, label, role, context) == Controls.NoControl{} : Controls.Representation}
  }

law evidence:
  Requirements

law card_content_source_family:
  for +key: UIIdentity.Key
  for +semantic: String
  for +label: String
  for +role: SurfaceTypes.Role
  for +face: View.CardFace
  for +children: +List<SurfaceTypes.Node>
  for inherited: Controls.SourceFamily
  {Controls.source_family_at(SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.CardContent{face}, children}, inherited) == Controls.SourceFamily{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.CardContent{face}, children}} : Controls.SourceFamily}

law card_content_has_no_input:
  for key: UIIdentity.Key
  for face: View.CardFace
  for label: String
  for role: SurfaceTypes.Role
  for context: Controls.Context
  {Controls.represent(key, SurfaceTypes.CardContent{face}, label, role, context) == Controls.NoControl{} : Controls.Representation}

type DockRequirements is Type:
  DockRequirements{
    measured_extent: @extent:F32 -> @viewport:F32 -> @+intent:User.ReadingIntent -> @+bookmark:Reading.Bookmark -> @reduced:Bool ->
      {Reading.step(Reading.LayoutChanged{extent, viewport}, intent, bookmark, reduced) ==
          Reading.Decision{bookmark, None{},
            Reading.ReserveComposer{Reading.reserve(extent, viewport)} <> Reading.layout(intent, bookmark)} : Reading.Decision}}

law dock_evidence:
  DockRequirements

type FactContentRequirements is Type:
  FactContentRequirements{
    frames: {Design.fact_content_layout() == Design.FactContentLayout{E.Frame{E.ambient(0n, 0n), E.EmbeddedContent{4n}}, E.Frame{E.ambient(0n, 0n), E.SeparateFrames{E.Sections{}}}} : Design.FactContentLayout}}

law fact_content_evidence:
  FactContentRequirements

type FeedbackRequirements is Type:
  FeedbackRequirements{
    source_alert_passive: @+reason:String ->
      {InterfaceView.focusable(SurfaceTypes.ReadOnly{reason}) == False{} : Bool}}

law feedback_evidence:
  FeedbackRequirements

type DialogSpatialRequirements is Type:
  DialogSpatialRequirements{
    field_style_widget_binding: @+typography:T.Presentation -> @editor:User.Editor -> @+field:Forms.Field -> @+entry:Forms.Entry -> @+value:Forms.Observed ->
      @choices:+List<Forms.ChoiceValue> ->
      @toggle:{Controls.widget_for(entry, field, value) == Controls.ToggleInput{} : Controls.Widget} ->
      {Appearance.field_style(SurfaceTypes.Edit{editor, field, entry, value, choices}, typography) == Appearance.toggle_field(typography) : Design.Style},
    dialog_outer_inset: @+typography:T.Presentation -> {SpaceRules.frame_coordinates(Design.style_frame(Appearance.style(SurfaceTypes.Dialog{}, SurfaceTypes.Region{}, typography))) == (0n, (0n, 0n)) : (Nat & (Nat & Nat))},
    concrete_field_kinds:   {[EditorLayout.card_field(Forms.CardTitle{}), EditorLayout.card_field(Forms.CardDescription{}),
          EditorLayout.card_field(Forms.CardStage{}), EditorLayout.card_field(Forms.CardPriority{}),
          EditorLayout.card_field(Forms.CardProject{}), EditorLayout.card_field(Forms.CardOwner{}),
          EditorLayout.card_field(Forms.CardLabels{}), EditorLayout.card_field(Forms.ContinueCapture{}),
          EditorLayout.card_field(Forms.AssistedCapture{}), EditorLayout.card_field(Forms.AssistanceProfile{})] ==
         [EditorLayout.WorkTitle{}, EditorLayout.WorkDescription{}, EditorLayout.MetadataFlexible{},
          EditorLayout.MetadataFlexible{}, EditorLayout.MetadataFlexible{}, EditorLayout.MetadataWide{},
          EditorLayout.MetadataWide{}, EditorLayout.CaptureOption{}, EditorLayout.CaptureOption{},
          EditorLayout.CaptureOption{}] : +List<EditorLayout.FieldKind>},
    field_layout_binding: @card:Maybe<&2, Nat> -> @field:Forms.Field -> @entry:Forms.Entry -> @value:Forms.Observed ->
      @choices:+List<Forms.ChoiceValue> ->
      {EditorLayout.field_kind(SurfaceTypes.Edit{User.CardEditor{card}, field, entry, value, choices}) ==
        EditorLayout.card_field(field) : EditorLayout.FieldKind},
    shared_inline_inset: {E.partition_inline() == 24n : Nat}}

law dialog_spatial_evidence:
  DialogSpatialRequirements

def labels_in_fields(values: +List<Forms.FieldScene>) -> Maybe<&2, Forms.Entry>:
  match values:
    case Nil{}: None{}
    case Con{Forms.FieldScene{Forms.CardLabels{}, label, entry}, rest}: Some{entry}
    case Con{other, rest}: labels_in_fields(rest)

def labels_or_rest(found: Maybe<&2, Forms.Entry>, rest: Maybe<&2, Forms.Entry>) -> Maybe<&2, Forms.Entry>:
  match found:
    case Some{entry}: Some{entry}
    case None{}: rest

def labels_in_sections(values: +List<Forms.Section>) -> Maybe<&2, Forms.Entry>:
  match values:
    case Nil{}: None{}
    case Con{Forms.Section{label, fields}, rest}: labels_or_rest(labels_in_fields(fields), labels_in_sections(rest))

type FormInputRequirements is Type:
  FormInputRequirements{
    labels_structure: @id:Maybe<&2, Nat> -> @revision:Nat -> @draft:Board.Draft -> @assist:Bool -> @profile:String -> @keep_open:Bool ->
      {labels_in_sections(Forms.structure(User.Card{id, revision, draft, assist, profile, keep_open})) == Some{Forms.Multiline{}} : Maybe<&2, Forms.Entry>},
    labels_text_edit: @editor:User.Editor -> @value:Forms.Observed -> @text:String -> @state:Browser.State ->
      {Browser.field_text(editor, Forms.CardLabels{}, Forms.Multiline{}, value, text, state) ==
    Some{SurfaceTypes.Change{Forms.Strings{String.split(text, Chr{10})}}} : Maybe<&2, SurfaceTypes.Gesture>},
    labels_update: @values:+List<String> -> @title:String -> @description:String -> @stage:Board.Stage -> @priority:Board.Priority -> @owner:Board.Owner -> @project:Maybe<&2, Nat> -> @previous:+List<String> -> @attachments:+List<Board.Attachment> ->
      {User.patch_card(Board.Patch{None{}, None{}, None{}, None{}, None{}, None{}, Some{values}, None{}},
          Board.Draft{title, description, stage, priority, owner, project, previous, attachments}) ==
          Board.Draft{title, description, stage, priority, owner, project, values, attachments} : Board.Draft},
    labels_edit: @values:+List<String> ->
      {Forms.edit(Forms.CardLabels{}, Forms.Strings{values}) ==
    Some{User.WriteCard{Board.Patch{None{}, None{}, None{}, None{}, None{}, None{}, Some{values}, None{}}}} : Maybe<&2, User.Edit>},
    labels_representation: @choices:+List<Forms.ChoiceValue> -> @key:UIIdentity.Key -> @editor:User.Editor -> @values:+List<String> -> @label:String -> @role:SurfaceTypes.Role -> @context:Controls.Context ->
      {Controls.represent(key, SurfaceTypes.Edit{editor, Forms.CardLabels{}, Forms.Multiline{}, Forms.TextsValue{values}, choices}, label, role, context) ==
          Controls.Input{SurfaceTypes.Edit{editor, Forms.CardLabels{}, Forms.Multiline{}, Forms.TextsValue{values}, choices}, label,
            Controls.TextArea{}, Controls.AboveInput{}, Controls.field_availability(Forms.Multiline{})} : Controls.Representation},
    labels_observation: @values:+List<String> ->
      {Fields.observed(Forms.TextsValue{values}) == Fields.joined(values) : String},
    assistance_representation: @choices:+List<Forms.ChoiceValue> -> @key:UIIdentity.Key -> @editor:User.Editor -> @enabled:Bool -> @profile:String -> @label:String -> @role:SurfaceTypes.Role -> @context:Controls.Context ->
      {Controls.represent(key, SurfaceTypes.Edit{editor, Forms.AssistedCapture{}, Forms.Choice{}, Forms.AssistanceValue{enabled, profile}, choices}, label, role, context) ==
          Controls.Input{SurfaceTypes.Edit{editor, Forms.AssistedCapture{}, Forms.Choice{}, Forms.AssistanceValue{enabled, profile}, choices}, label,
            Controls.ToggleInput{}, Controls.BesideInput{}, Controls.field_availability(Forms.Choice{})} : Controls.Representation},
    assistance_profile_representation: @choices:+List<Forms.ChoiceValue> -> @key:UIIdentity.Key -> @editor:User.Editor -> @enabled:Bool -> @profile:String -> @label:String -> @role:SurfaceTypes.Role -> @context:Controls.Context ->
      {Controls.represent(key, SurfaceTypes.Edit{editor, Forms.AssistanceProfile{}, Forms.Choice{}, Forms.AssistanceValue{enabled, profile}, choices}, label, role, context) ==
          Controls.Input{SurfaceTypes.Edit{editor, Forms.AssistanceProfile{}, Forms.Choice{}, Forms.AssistanceValue{enabled, profile}, choices}, label,
            Controls.SelectInput{}, Controls.AboveInput{}, Controls.field_availability(Forms.Choice{})} : Controls.Representation},
    assistance_gesture: @choices:+List<Forms.ChoiceValue> -> @key:UIIdentity.Key -> @semantic:String -> @label:String -> @role:SurfaceTypes.Role -> @editor:User.Editor -> @previous:Bool -> @profile:String -> @children:+List<SurfaceTypes.Node> -> @enabled:Bool ->
      {Browser.toggle_gesture(Some{SurfaceTypes.Node{key, semantic, label, role,
          SurfaceTypes.Edit{editor, Forms.AssistedCapture{}, Forms.Choice{}, Forms.AssistanceValue{previous, profile}, choices}, children}}, enabled) ==
          Some{SurfaceTypes.Change{Forms.Assistance{enabled, profile}}} : Maybe<&2, SurfaceTypes.Gesture>},
    assistance_preserves_profile: @enabled:Bool -> @selected:String -> @previous:Bool -> @profile:String ->
      {Forms.card_edit(Forms.AssistedCapture{}, Forms.Assistance{enabled, selected}, previous, profile) ==
    Some{User.ConfigureCardAssistance{enabled, profile}} : Maybe<&2, User.Edit>},
    profile_preserves_assistance: @enabled:Bool -> @selected:String -> @previous:Bool -> @profile:String ->
      {Forms.card_edit(Forms.AssistanceProfile{}, Forms.Assistance{enabled, selected}, previous, profile) ==
    Some{User.ConfigureCardAssistance{previous, selected}} : Maybe<&2, User.Edit>},
    stage_choices: @stage:Board.Stage -> @rest:+List<Board.Stage> ->
      {Fields.stage_options(Con{stage, rest}) ==
        Forms.ChoiceValue{Board.stage_name(stage), Board.stage_label(stage)} <> Fields.stage_options(rest) : +List<Forms.ChoiceValue>},
    priority_choices: @priority:Board.Priority -> @rest:+List<Board.Priority> ->
      {Fields.priority_options(Con{priority, rest}) ==
        Forms.ChoiceValue{Board.priority_name(priority), Board.priority_label(priority)} <> Fields.priority_options(rest) : +List<Forms.ChoiceValue>},
    stage_choices_binding: @value:Forms.Observed ->
      {Fields.field_options(Forms.CardStage{}, value) == Fields.stage_options(Board.stages()) : +List<Forms.ChoiceValue>},
    priority_choices_binding: @value:Forms.Observed ->
      {Fields.field_options(Forms.CardPriority{}, value) ==
        Fields.priority_options(Board.priorities()) : +List<Forms.ChoiceValue>}}

law form_input_evidence:
  FormInputRequirements
