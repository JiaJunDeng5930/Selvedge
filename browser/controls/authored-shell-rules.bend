import ../../interaction/presentation/COMPOSITION.bend as Composition
import ../document/presentation-order.bend as Order
import Base
import ../../interaction/IDENTITY.bend as UIIdentity
import ./SHELL.bend as Shell
import ./MODEL.bend as Authored
import ./authored-primitives.bend as Factory
import ../document/SOURCE.bend as Source
import ../document/MODEL.bend as Doc
import ../layout/physical-space.bend as Model
import ../appearance/TYPOGRAPHY.bend as Typography
import ../layout/SPACE.bend as Space
import ../layout/physical-space-rules.bend as SpaceRules
import ../appearance/DESIGN.bend as Design
import ../layout/GEOMETRY.bend as Spatial
import ../layout/enclosure.bend as Enclosure
import ../../interaction/presentation/MODEL.bend as View
import ../../interaction/STATE.bend as Core
import ../../interaction/presentation/PROGRAM.bend as InterfaceView

def reframing_events(+node: Source.Node, layout: Source.Layout) -> Type:
  {Source.events_of(Shell.reframe(node, layout)) == Source.events_of(node) : +List<Doc.DOMEvent>}

def reframing_interaction(+node: Source.Node, layout: Source.Layout) -> Type:
  {Source.interaction_of(Shell.reframe(node, layout)) == Source.interaction_of(node) : Model.Interaction<Doc.DOMEvent>}

def reframing_children(+node: Source.Node, layout: Source.Layout) -> Type:
  {Source.children_of(Shell.reframe(node, layout)) == Source.children_of(node) : +List<Source.Node>}

def wrapper_children(key: UIIdentity.Key, style: Source.Style, +children: +List<Source.Node>) -> Type:
  {Source.children_of(Shell.wrap(key, style, children)) == children : +List<Source.Node>}

def wrapper_events(key: UIIdentity.Key, style: Source.Style, children: +List<Source.Node>) -> Type:
  {Source.events_of(Shell.wrap(key, style, children)) == Nil{} : +List<Doc.DOMEvent>}

def footer_children(key: UIIdentity.Key, tag: Source.BoxTag, style: Source.Style, attributes: +List<Source.Attribute>, +children: +List<Source.Node>, +settings: +List<Source.Node>, +font: Typography.Presentation) -> Type:
  {Source.children_of(Shell.with_footer(key, tag, style, attributes, children, settings, font)) == List.append(&2, Source.Node, children, Shell.spacer(UIIdentity.part(UIIdentity.place("/application"), "navigation-spacer"), font) <> settings) : +List<Source.Node>}


def reading_policy(+width: Model.AxisSize, maximum: Nat) -> Type:
  match width:
    case Model.StretchSize{}: {Shell.reading_policy(Model.StretchSize{}, maximum) == Model.CappedStretchSize{maximum} : Model.AxisSize}
    case _: {Shell.reading_policy(width, maximum) == width : Model.AxisSize}

def reading_layout(+layout: Source.Layout, maximum: Nat) -> Type:
  Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position} = layout
  {Shell.reading_layout(layout, maximum) == Source.Layout{direction, main, cross, frame, Shell.reading_policy(width, maximum), height, minimum, scroll, position} : Source.Layout}

def width_of(layout: Source.Layout) -> Model.AxisSize:
  Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position} = layout
  width

def reading_stretch_dimension(direction: Model.Direction, main: Spatial.Alignment, cross: Spatial.Alignment, frame: Enclosure.Frame, height: Model.AxisSize, floor: Enclosure.Extent, scroll: Model.Scroll, position: Spatial.Position, maximum: Nat, minimum: Nat, preferred: Nat, offered: Nat) -> Maybe<&2, Space.Dimension>:
  Model.materialize(width_of(Shell.reading_layout(Source.Layout{direction, main, cross, frame, Model.StretchSize{}, height, floor, scroll, position}, maximum)), minimum, preferred, offered)

def front_layer_last(+first: Source.Node, +rest: +List<Source.Node>) -> Type:
  {Shell.back_to_front(first <> rest) == List.append(&2, Source.Node, Shell.back_to_front(rest), first <> Nil{}) : +List<Source.Node>}

def keys(values: +List<Source.Node>) -> +List<UIIdentity.Key>:
  match values:
    case Nil{}: Nil{}
    case Con{node, rest}: Source.key_of(node) <> keys(rest)

def creation_population(+children: +List<Source.Node>, maximum: Nat) -> Type:
  {keys(Shell.creation_children(children, maximum)) == keys(children) : +List<UIIdentity.Key>}

def creation_group(key: UIIdentity.Key, font: Source.FontChoice, +maximum: Nat, children: +List<Source.Node>) -> Type:
  {Shell.creation_group(key, font, maximum, children) ==
    Source.Box{UIIdentity.part(key, "creation-group"), Source.Div{}, Shell.neutral_arranged(font, Model.Vertical{}, Model.CappedStretchSize{maximum}, Model.NaturalSize{}, Spatial.Stretch{}, Enclosure.SeparateFrames{Enclosure.Sections{}}), Nil{}, Shell.creation_children(children, maximum)} : Source.Node}

def frame_of(layout: Source.Layout) -> Enclosure.Frame:
  Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position} = layout
  frame

def creation_group_spacing(key: UIIdentity.Key, font: Source.FontChoice, maximum: Nat, children: +List<Source.Node>) -> Type:
  {Enclosure.frame_gap(frame_of(Shell.layout_of(Shell.creation_group(key, font, maximum, children)))) == Enclosure.separation(Enclosure.Sections{}) : Nat}

def creation_reading_width(+parameters: Design.LayoutParameters) -> Type:
  {Shell.structure_reading_width(Design.MainStructure{Composition.ReadingMeasure{}, Composition.NoHeading{}, Composition.CenteredCreation{}}, parameters) == Design.reading_maximum_width(parameters) : Nat}

def creation_assembly(+content: Core.Scene, +theme: Design.Theme, +base: +List<Design.Node>, +overlays: +List<Design.Node>, scope: Maybe<&2, String>, +base_nodes: +List<Source.Node>, +overlay_nodes: +List<Source.Node>, +capacity: View.Capacity, +parameters: Design.LayoutParameters, +layers: +List<View.Layer>, +anchors: +List<Shell.Anchor>, +font: Typography.Presentation) -> Type:
  {Shell.assemble_surface(Design.Surface{content, theme, base, overlays, scope}, base_nodes, overlay_nodes, capacity, parameters, layers, anchors, font) ==
    Shell.assembled_parts(Shell.split_overlays(overlay_nodes, capacity, Shell.scene_navigation_placement(content), parameters, layers, base, overlays, anchors), Design.MainStructure{Composition.ReadingMeasure{}, Composition.NoHeading{}, Composition.CenteredCreation{}}, Design.reading_maximum_width(parameters), base_nodes, base, Shell.scene_navigation_placement(content), parameters, font, theme) : Shell.ShellAuthorship}

def creation_child_layout(+layout: Source.Layout, maximum: Nat) -> Type:
  Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position} = layout
  {Shell.creation_layout(layout, maximum) == Source.Layout{direction, main, cross, frame, Shell.reading_policy(width, maximum), Model.NaturalSize{}, minimum, Model.Confined{}, position} : Source.Layout}

def creation_main(+key: UIIdentity.Key, tag: Source.BoxTag, +style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, +maximum: Nat) -> Type:
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, +font, chrome, states} = style
  {Shell.main_box(Design.MainStructure{Composition.ReadingMeasure{}, Composition.NoHeading{}, Composition.CenteredCreation{}}, key, tag, style, attributes, children, maximum) ==
    Source.Box{key, tag, Source.Style{Source.Layout{Model.Vertical{}, Spatial.Centered{}, Spatial.Centered{}, Enclosure.Frame{Enclosure.area(Enclosure.PageContent{}), Enclosure.SeparateFrames{Enclosure.Sections{}}}, Model.StretchSize{}, Model.StretchSize{}, minimum, Model.ScrollVertically{}, Spatial.InFlow{}}, font, chrome, states}, attributes, [Shell.creation_group(key, font, maximum, children)]} : Source.Node}

def other_organization(organization: Composition.Body) -> Bool:
  match organization:
    case Composition.CenteredCreation{}: False{}
    case _: True{}

def other_structure(structure: Design.MainStructure) -> Bool:
  Design.MainStructure{measure, heading, organization} = structure
  other_organization(organization)

def other_main(structure: Design.MainStructure, +key: UIIdentity.Key, tag: Source.BoxTag, +style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, +maximum: Nat) -> Type:
  Design.MainStructure{measure, heading, +organization} = structure
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = style
  {Shell.main_box(Design.MainStructure{measure, heading, organization}, key, tag, style, attributes, children, maximum) ==
    Source.Box{key, tag, Source.Style{Source.Layout{direction, Shell.main_leading(organization, main), Shell.main_cross(organization), Shell.main_frame(organization, frame), Model.StretchSize{}, Model.StretchSize{}, minimum, scroll, Spatial.InFlow{}}, font, chrome, states}, attributes, Shell.measure_children(measure, Shell.heading_children(heading, key, style, children), maximum)} : Source.Node}

def navigation_box(key: UIIdentity.Key, tag: Source.BoxTag, +style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, rest: +List<Source.Node>, +width: Nat) -> Type:
  Source.Style{Source.Layout{direction, main, cross, frame, old_width, height, minimum, scroll, position}, font, chrome, states} = style
  {Shell.navigation_nodes(Source.Box{key, tag, style, attributes, children} <> rest, width) ==
    Source.Box{key, tag, Source.Style{Source.Layout{direction, main, Spatial.Stretch{}, frame, Model.ExactSize{width}, Model.StretchSize{}, minimum, Model.ScrollVertically{}, Spatial.InFlow{}}, font, chrome, states}, attributes, children} <> Shell.navigation_nodes(rest, width) : +List<Source.Node>}

def settings_role(role: InterfaceView.Role) -> Bool:
  match role:
    case InterfaceView.Main{}: False{}
    case InterfaceView.Navigation{}: False{}
    case _: True{}

def settings_classification(+node: Source.Node, role: InterfaceView.Role, +navigation: +List<Source.Node>, +main: +List<Source.Node>, +settings: +List<Source.Node>, +other: +List<Source.Node>) -> Type:
  {Shell.split_base_role(node, role, navigation, main, settings, other) == Shell.BaseParts{navigation, main, node <> settings, other} : Shell.BaseParts}

def recipe_structure(recipe: Composition.Recipe) -> Type:
  Composition.Recipe{measure, heading, organization, composer, decisions, latest} = recipe
  {Design.main_structure(Composition.Recipe{measure, heading, organization, composer, decisions, latest}) == Design.MainStructure{measure, heading, organization} : Design.MainStructure}

def available_children(children: +List<Source.Node>, maximum: Nat) -> Type:
  {Shell.measure_children(Composition.AvailableMeasure{}, children, maximum) == children : +List<Source.Node>}

def page_frame(previous: Enclosure.Frame) -> Type:
  {Shell.main_frame(Composition.StageColumns{}, previous) == Enclosure.Frame{Enclosure.area(Enclosure.PageContent{}), Enclosure.SeparateFrames{Enclosure.Sections{}}} : Enclosure.Frame}


def measure_width(parameters: Design.LayoutParameters, heading: Composition.Heading, organization: Composition.Body) -> Type:
  {(Shell.structure_reading_width(Design.MainStructure{Composition.ReadingMeasure{}, heading, organization}, parameters), (Shell.structure_reading_width(Design.MainStructure{Composition.OverviewMeasure{}, heading, organization}, parameters), Shell.structure_reading_width(Design.MainStructure{Composition.AvailableMeasure{}, heading, organization}, parameters))) == (Design.reading_maximum_width(parameters), (Design.overview_maximum_width(parameters), 0n)) : Nat & (Nat & Nat)}

def beside_main_style(style: Source.Style, +required: Nat) -> Type:
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, Enclosure.Extent{minimum_width, minimum_height}, scroll, position}, font, chrome, states} = style
  {Shell.beside_style(True{}, required, Source.Style{Source.Layout{direction, main, cross, frame, width, height, Enclosure.Extent{minimum_width, minimum_height}, scroll, position}, font, chrome, states}) == Source.Style{Source.Layout{direction, main, cross, frame, width, height, Enclosure.Extent{Nat.max(minimum_width, required), minimum_height}, scroll, position}, font, chrome, states} : Source.Style}

def compact_main_style(style: Source.Style, required: Nat) -> Type:
  {Shell.beside_style(False{}, required, style) == style : Source.Style}

def main_population(key: UIIdentity.Key, tag: Source.BoxTag, style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, rest: +List<Source.Node>, structure: Design.MainStructure, maximum: Nat, beside: Bool, required: Nat) -> Type:
  {Shell.main_nodes(Source.Box{key, tag, style, attributes, children} <> rest, structure, maximum, beside, required) == Shell.main_box(structure, key, tag, Shell.beside_style(beside, required, style), attributes, children, maximum) <> Shell.main_nodes(rest, structure, maximum, beside, required) : +List<Source.Node>}

def main_placement_input(placement: View.NavigationPlacement, parameters: Design.LayoutParameters, structure: Design.MainStructure, reading_width: Nat, navigation: +List<Source.Node>, main: +List<Source.Node>, settings: +List<Source.Node>, other: +List<Source.Node>, docked: +List<Source.Node>, font: Typography.Presentation) -> Type:
  match placement:
    case View.LeadingNavigation{}: {Shell.body_direction(View.LeadingNavigation{}, parameters, structure, reading_width, navigation, main, settings, other, docked, font) == Shell.body_mode(True{}, Design.navigation_width(parameters), Design.main_minimum_width(parameters), structure, reading_width, navigation, main, settings, other, docked, font) : Source.Node}
    case View.ModalNavigation{}: {Shell.body_direction(View.ModalNavigation{}, parameters, structure, reading_width, navigation, main, settings, other, docked, font) == Shell.body_mode(False{}, Design.navigation_width(parameters), Design.main_minimum_width(parameters), structure, reading_width, navigation, main, settings, other, docked, font) : Source.Node}
    case View.CollapsedNavigation{}: {Shell.body_direction(View.CollapsedNavigation{}, parameters, structure, reading_width, navigation, main, settings, other, docked, font) == Shell.body_mode(False{}, Design.navigation_width(parameters), Design.main_minimum_width(parameters), structure, reading_width, navigation, main, settings, other, docked, font) : Source.Node}

def root_minimum(node: Source.Node) -> Enclosure.Extent:
  match node:
    case Source.Box{key, tag, Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states}, attributes, children}: minimum
    case _: Enclosure.Extent{0n, 0n}

def beside_box_floor(structure: Design.MainStructure, key: UIIdentity.Key, tag: Source.BoxTag, style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, maximum: Nat, +required: Nat) -> Type:
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, Enclosure.Extent{minimum_width, minimum_height}, scroll, position}, font, chrome, states} = style
  {root_minimum(Shell.main_box(structure, key, tag, Shell.beside_style(True{}, required, Source.Style{Source.Layout{direction, main, cross, frame, width, height, Enclosure.Extent{minimum_width, minimum_height}, scroll, position}, font, chrome, states}), attributes, children, maximum)) == Enclosure.Extent{Nat.max(minimum_width, required), minimum_height} : Enclosure.Extent}

def navigation_projection(content: Core.Scene) -> Type:
  Core.Scene{View.Scene{navigation, main, layers, View.Arrangement{placement}, attention}, settings, transfers, preview, code, directory_picker} = content
  {Shell.scene_navigation_placement(Core.Scene{View.Scene{navigation, main, layers, View.Arrangement{placement}, attention}, settings, transfers, preview, code, directory_picker}) == placement : View.NavigationPlacement}

def assembly_placement(+content: Core.Scene, +theme: Design.Theme, +base: +List<Design.Node>, +overlays: +List<Design.Node>, scope: Maybe<&2, String>, +base_nodes: +List<Source.Node>, +overlay_nodes: +List<Source.Node>, +capacity: View.Capacity, +parameters: Design.LayoutParameters, +layers: +List<View.Layer>, +anchors: +List<Shell.Anchor>, +font: Typography.Presentation, placement: View.NavigationPlacement) -> Type:
  {Shell.assemble_surface(Design.Surface{content, theme, base, overlays, scope}, base_nodes, overlay_nodes, capacity, parameters, layers, anchors, font) == Shell.assembled_parts(Shell.split_overlays(overlay_nodes, capacity, placement, parameters, layers, base, overlays, anchors), Shell.scene_structure(content), Shell.structure_reading_width(Shell.scene_structure(content), parameters), base_nodes, base, placement, parameters, font, theme) : Shell.ShellAuthorship}

def chronological_main_frame(frame: Enclosure.Frame) -> Type:
  {Shell.main_frame(Composition.ChronologicalReading{}, frame) == Enclosure.Frame{Enclosure.area(Enclosure.PageContent{}), Enclosure.SeparateFrames{Enclosure.Sections{}}} : Enclosure.Frame}

def chronological_main_cross() -> Type:
  {Shell.main_cross(Composition.ChronologicalReading{}) == Spatial.Centered{} : Spatial.Alignment}

def chronological_main_leading(previous: Spatial.Alignment) -> Type:
  {Shell.main_leading(Composition.ChronologicalReading{}, previous) == previous : Spatial.Alignment}

def chronological_reading_width(+parameters: Design.LayoutParameters) -> Type:
  {Shell.structure_reading_width(Design.MainStructure{Composition.ReadingMeasure{}, Composition.ConversationHeading{}, Composition.ChronologicalReading{}}, parameters) == Design.reading_maximum_width(parameters) : Nat}

def conversation_main(+measure: Composition.Measure, +key: UIIdentity.Key, tag: Source.BoxTag, +style: Source.Style, attributes: +List<Source.Attribute>, title: Source.Node, actions: Source.Node, remaining: +List<Source.Node>, +maximum: Nat) -> Type:
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = style
  {Shell.main_box(Design.MainStructure{measure, Composition.ConversationHeading{}, Composition.ChronologicalReading{}}, key, tag, style, attributes, title <> actions <> remaining, maximum) ==
    Source.Box{key, tag, Source.Style{Source.Layout{direction, main, Spatial.Centered{}, Enclosure.Frame{Enclosure.area(Enclosure.PageContent{}), Enclosure.SeparateFrames{Enclosure.Sections{}}}, Model.StretchSize{}, Model.StretchSize{}, minimum, scroll, Spatial.InFlow{}}, font, chrome, states}, attributes,
      Shell.measure_children(measure, Shell.conversation_heading(key, style, title, actions) <> remaining, maximum)} : Source.Node}

def conversation_title_font(+font: Source.FontChoice) -> Type:
  match font:
    case Source.InheritFont{}: {Shell.conversation_title_font(font) == Source.InheritFont{} : Source.FontChoice}
    case Source.ExplicitFont{presentation}:
      {Shell.conversation_title_font(font) == Source.ExplicitFont{Typography.with_emphasis(Typography.with_tier(presentation, Typography.Section{}), Typography.Medium{})} : Source.FontChoice}

def conversation_title_style(+style: Source.Style) -> Type:
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = style
  match direction:
    case Model.Vertical{}:
      {Shell.conversation_title_style(style) == Source.Style{Source.Layout{direction, Spatial.Centered{}, cross, frame, width, height, minimum, scroll, position}, Shell.conversation_title_font(font), chrome, states} : Source.Style}
    case Model.Horizontal{}:
      {Shell.conversation_title_style(style) == Source.Style{Source.Layout{direction, main, Spatial.Centered{}, frame, width, height, minimum, scroll, position}, Shell.conversation_title_font(font), chrome, states} : Source.Style}
    case Model.ResponsiveHorizontal{}:
      {Shell.conversation_title_style(style) == Source.Style{Source.Layout{direction, main, Spatial.Centered{}, frame, width, height, minimum, scroll, position}, Shell.conversation_title_font(font), chrome, states} : Source.Style}
    case Model.Layered{}:
      {Shell.conversation_title_style(style) == Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, Shell.conversation_title_font(font), chrome, states} : Source.Style}

def conversation_title_text(+key: UIIdentity.Key, +value: String, +font: Source.FontChoice, wrapping: Typography.Wrapping) -> Type:
  {Shell.conversation_title(Source.Text{key, value, font, wrapping}) == Source.Text{key, value, Shell.conversation_title_font(font), Typography.SingleLine{}} : Source.Node}

def conversation_title_box(+key: UIIdentity.Key, +tag: Source.BoxTag, +style: Source.Style, +attributes: +List<Source.Attribute>, +children: +List<Source.Node>) -> Type:
  {Shell.conversation_title(Source.Box{key, tag, style, attributes, children}) == Source.Box{key, tag, Shell.conversation_title_style(style), attributes, Shell.conversation_title_children(children)} : Source.Node}

def conversation_title_children(+values: +List<Source.Node>) -> Type:
  match values:
    case Nil{}: {Shell.conversation_title_children(values) == Nil{} : +List<Source.Node>}
    case Con{Source.Box{key, tag, style, attributes, children}, rest}:
      {Shell.conversation_title_children(values) == Source.Box{key, tag, Shell.conversation_title_style(style), attributes, Shell.conversation_title_children(children)} <> Shell.conversation_title_children(rest) : +List<Source.Node>}
    case Con{Source.Text{key, value, font, wrapping}, rest}:
      {Shell.conversation_title_children(values) == Source.Text{key, value, Shell.conversation_title_font(font), Typography.SingleLine{}} <> Shell.conversation_title_children(rest) : +List<Source.Node>}
    case Con{other, rest}: {Shell.conversation_title_children(values) == other <> Shell.conversation_title_children(rest) : +List<Source.Node>}

def conversation_title_other(+node: Source.Node) -> Type:
  match node:
    case Source.Box{key, tag, style, attributes, children}: Unit
    case Source.Text{key, value, font, wrapping}: Unit
    case other: {Shell.conversation_title(node) == other : Source.Node}

def other_heading_children(+heading: Composition.Heading, key: UIIdentity.Key, style: Source.Style, +children: +List<Source.Node>) -> Type:
  match heading:
    case Composition.ConversationHeading{}: Unit
    case other: {Shell.heading_children(heading, key, style, children) == children : +List<Source.Node>}

def conversation_header(+key: UIIdentity.Key, +style: Source.Style, title: Source.Node, actions: Source.Node) -> Type:
  Source.Style{layout, font, chrome, states} = style
  {Shell.conversation_heading(key, style, title, actions) ==
    Source.Box{UIIdentity.part(key, "@heading"), Source.Div{}, Source.Style{Source.Layout{Model.Horizontal{}, Spatial.Leading{}, Spatial.Centered{},
      Enclosure.Frame{Enclosure.ambient(0n, 0n), Enclosure.SeparateFrames{Enclosure.ComposerControls{}}},
      Model.StretchSize{}, Model.NaturalSize{}, Enclosure.Extent{0n, 0n}, Model.Confined{}, Spatial.InFlow{}}, font, chrome, states}, Nil{}, [Shell.conversation_title(title), actions]} : Source.Node}

def conversation_header_frame(+key: UIIdentity.Key, +style: Source.Style, title: Source.Node, actions: Source.Node) -> Type:
  {frame_of(Shell.layout_of(Shell.conversation_heading(key, style, title, actions))) == Enclosure.Frame{Enclosure.ambient(0n, 0n), Enclosure.SeparateFrames{Enclosure.ComposerControls{}}} : Enclosure.Frame}

def task_action_flow(+visual: Design.Style, position: Composition.Position) -> Type:
  {Authored.region_style(visual, Composition.TaskActions{}, position) ==
    Factory.with_alignments(Factory.with_direction(
      Factory.with_frame(Factory.style(visual, Model.NaturalSize{}, Model.NaturalSize{}, Model.Confined{}),
        Enclosure.Frame{Enclosure.ambient(0n, 0n), Enclosure.SeparateFrames{Enclosure.InlineControls{}}}),
      Model.Horizontal{}), Spatial.Leading{}, Spatial.Centered{}) : Source.Style}

type Requirements is Type:
  Requirements{
    conversation_title_font: @+font:Source.FontChoice -> conversation_title_font(font),
    conversation_title_style: @+style:Source.Style -> conversation_title_style(style),
    conversation_title_text: @+key:UIIdentity.Key -> @+value:String -> @+font:Source.FontChoice -> @wrapping:Typography.Wrapping -> conversation_title_text(key, value, font, wrapping),
    conversation_title_box: @+key:UIIdentity.Key -> @+tag:Source.BoxTag -> @+style:Source.Style -> @+attributes:+List<Source.Attribute> -> @+children:+List<Source.Node> -> conversation_title_box(key, tag, style, attributes, children),
    conversation_title_children: @+values:+List<Source.Node> -> conversation_title_children(values),
    conversation_title_other: @+node:Source.Node -> conversation_title_other(node),
    other_heading_children: @+heading:Composition.Heading -> @key:UIIdentity.Key -> @style:Source.Style -> @+children:+List<Source.Node> -> other_heading_children(heading, key, style, children),
    chronological_main_frame: @frame:Enclosure.Frame -> chronological_main_frame(frame),
    chronological_main_cross: chronological_main_cross(),
    chronological_main_leading: @previous:Spatial.Alignment -> chronological_main_leading(previous),
    chronological_reading_width: @+parameters:Design.LayoutParameters -> chronological_reading_width(parameters),
    conversation_header_frame: @+key:UIIdentity.Key -> @+style:Source.Style -> @title:Source.Node -> @actions:Source.Node -> conversation_header_frame(key, style, title, actions),
    conversation_main: @+measure:Composition.Measure -> @+key:UIIdentity.Key -> @tag:Source.BoxTag -> @+style:Source.Style -> @attributes:+List<Source.Attribute> -> @title:Source.Node -> @actions:Source.Node -> @remaining:+List<Source.Node> -> @+maximum:Nat -> conversation_main(measure, key, tag, style, attributes, title, actions, remaining, maximum),
    conversation_header: @+key:UIIdentity.Key -> @+style:Source.Style -> @title:Source.Node -> @actions:Source.Node -> conversation_header(key, style, title, actions),
    task_action_flow: @+visual:Design.Style -> @position:Composition.Position -> task_action_flow(visual, position),
    navigation_projection: @content:Core.Scene -> navigation_projection(content),
    assembly_placement: @+content:Core.Scene -> @+theme:Design.Theme -> @+base:+List<Design.Node> -> @+overlays:+List<Design.Node> -> @scope:Maybe<&2, String> -> @+base_nodes:+List<Source.Node> -> @+overlay_nodes:+List<Source.Node> -> @+capacity:View.Capacity -> @+parameters:Design.LayoutParameters -> @+layers:+List<View.Layer> -> @+anchors:+List<Shell.Anchor> -> @+font:Typography.Presentation -> @placement:View.NavigationPlacement -> @projected:{Shell.scene_navigation_placement(content) == placement : View.NavigationPlacement} -> assembly_placement(content, theme, base, overlays, scope, base_nodes, overlay_nodes, capacity, parameters, layers, anchors, font, placement),
    beside_box_floor: @structure:Design.MainStructure -> @key:UIIdentity.Key -> @tag:Source.BoxTag -> @style:Source.Style -> @attributes:+List<Source.Attribute> -> @children:+List<Source.Node> -> @maximum:Nat -> @+required:Nat -> beside_box_floor(structure, key, tag, style, attributes, children, maximum, required),
    beside_main_style: @style:Source.Style -> @+required:Nat -> beside_main_style(style, required),
    compact_main_style: @style:Source.Style -> @required:Nat -> compact_main_style(style, required),
    main_population: @key:UIIdentity.Key -> @tag:Source.BoxTag -> @style:Source.Style -> @attributes:+List<Source.Attribute> -> @children:+List<Source.Node> -> @rest:+List<Source.Node> -> @structure:Design.MainStructure -> @maximum:Nat -> @beside:Bool -> @required:Nat -> main_population(key, tag, style, attributes, children, rest, structure, maximum, beside, required),
    main_placement_input: @placement:View.NavigationPlacement -> @parameters:Design.LayoutParameters -> @structure:Design.MainStructure -> @reading_width:Nat -> @navigation:+List<Source.Node> -> @main:+List<Source.Node> -> @settings:+List<Source.Node> -> @other:+List<Source.Node> -> @docked:+List<Source.Node> -> @font:Typography.Presentation -> main_placement_input(placement, parameters, structure, reading_width, navigation, main, settings, other, docked, font),
    measure_width: @parameters:Design.LayoutParameters -> @heading:Composition.Heading -> @organization:Composition.Body -> measure_width(parameters, heading, organization),
    recipe_structure: @recipe:Composition.Recipe -> recipe_structure(recipe),
    available_children: @children:+List<Source.Node> -> @maximum:Nat -> available_children(children, maximum),
    page_frame: @previous:Enclosure.Frame -> page_frame(previous),
    front_layer_last: @+first:Source.Node -> @+rest:+List<Source.Node> -> front_layer_last(first, rest),
    events: @+node:Source.Node -> @+layout:Source.Layout -> reframing_events(node, layout),
    interaction: @+node:Source.Node -> @+layout:Source.Layout -> reframing_interaction(node, layout),
    children: @+node:Source.Node -> @+layout:Source.Layout -> reframing_children(node, layout),
    wrapper: @key:UIIdentity.Key -> @style:Source.Style -> @+children:+List<Source.Node> -> wrapper_children(key, style, children),
    no_wrapper_events: @key:UIIdentity.Key -> @style:Source.Style -> @children:+List<Source.Node> -> wrapper_events(key, style, children),
    reading_policy: @+width:Model.AxisSize -> @maximum:Nat -> reading_policy(width, maximum),
    reading_layout: @+layout:Source.Layout -> @maximum:Nat -> reading_layout(layout, maximum),
    reading_stretch_width: @direction:Model.Direction -> @main:Spatial.Alignment -> @cross:Spatial.Alignment -> @frame:Enclosure.Frame -> @height:Model.AxisSize -> @floor:Enclosure.Extent -> @scroll:Model.Scroll -> @position:Spatial.Position -> @+maximum:Nat -> @+minimum:Nat -> @preferred:Nat -> @offered:Nat -> @+room:Nat ->
      @+fits:{Nat.is_le(minimum, maximum) == True{} : Bool} -> @room_fits:{Nat.is_le(minimum, room) == True{} : Bool} ->
      {SpaceRules.allocated_width(reading_stretch_dimension(direction, main, cross, frame, height, floor, scroll, position, maximum, minimum, preferred, offered), room) == Some{Nat.min(room, maximum)} : Maybe<&2, Nat>},
    creation_population: @+children:+List<Source.Node> -> @+maximum:Nat -> creation_population(children, maximum),
    creation_group: @key:UIIdentity.Key -> @font:Source.FontChoice -> @+maximum:Nat -> @children:+List<Source.Node> -> creation_group(key, font, maximum, children),
    creation_group_spacing: @key:UIIdentity.Key -> @font:Source.FontChoice -> @maximum:Nat -> @children:+List<Source.Node> -> creation_group_spacing(key, font, maximum, children),
    creation_reading_width: @+parameters:Design.LayoutParameters -> creation_reading_width(parameters),
    creation_assembly: @+content:Core.Scene -> @+theme:Design.Theme -> @+base:+List<Design.Node> -> @+overlays:+List<Design.Node> -> @scope:Maybe<&2, String> -> @+base_nodes:+List<Source.Node> -> @+overlay_nodes:+List<Source.Node> -> @+capacity:View.Capacity -> @+parameters:Design.LayoutParameters -> @+layers:+List<View.Layer> -> @+anchors:+List<Shell.Anchor> -> @+font:Typography.Presentation ->
      @created:{Shell.scene_structure(content) == Design.MainStructure{Composition.ReadingMeasure{}, Composition.NoHeading{}, Composition.CenteredCreation{}} : Design.MainStructure} -> creation_assembly(content, theme, base, overlays, scope, base_nodes, overlay_nodes, capacity, parameters, layers, anchors, font),
    creation_child_layout: @+layout:Source.Layout -> @maximum:Nat -> creation_child_layout(layout, maximum),
    creation_main: @+key:UIIdentity.Key -> @tag:Source.BoxTag -> @+style:Source.Style -> @attributes:+List<Source.Attribute> -> @children:+List<Source.Node> -> @+maximum:Nat -> creation_main(key, tag, style, attributes, children, maximum),
    other_main: @+structure:Design.MainStructure -> @+key:UIIdentity.Key -> @tag:Source.BoxTag -> @+style:Source.Style -> @attributes:+List<Source.Attribute> -> @children:+List<Source.Node> -> @+maximum:Nat -> @other:{other_structure(structure) == True{} : Bool} -> other_main(structure, key, tag, style, attributes, children, maximum),
    navigation_box: @key:UIIdentity.Key -> @tag:Source.BoxTag -> @+style:Source.Style -> @attributes:+List<Source.Attribute> -> @children:+List<Source.Node> -> @rest:+List<Source.Node> -> @+width:Nat -> navigation_box(key, tag, style, attributes, children, rest, width),
    settings_classification: @+node:Source.Node -> @+role:InterfaceView.Role -> @+navigation:+List<Source.Node> -> @+main:+List<Source.Node> -> @+settings:+List<Source.Node> -> @+other:+List<Source.Node> ->
      @identified:{Source.key_of(node) == UIIdentity.part(UIIdentity.place(""), "settings/open") : UIIdentity.Key} -> @belongs:{settings_role(role) == True{} : Bool} -> settings_classification(node, role, navigation, main, settings, other),
    footer: @key:UIIdentity.Key -> @tag:Source.BoxTag -> @style:Source.Style -> @attributes:+List<Source.Attribute> -> @+children:+List<Source.Node> -> @+settings:+List<Source.Node> -> @+font:Typography.Presentation -> footer_children(key, tag, style, attributes, children, settings, font)
  }

law evidence:
  Requirements

law base_shared_classification:
  for +node: Source.Node
  for role: InterfaceView.Role
  for parts: Shell.BaseParts
  {Shell.split_base_node(node, role, parts) == Shell.split_base_region(Order.base_region(Source.key_of(node), role), node, parts) : Shell.BaseParts}

law base_group_navigation:
  for +node: Source.Node
  for +navigation: +List<Source.Node>
  for +main: +List<Source.Node>
  for +settings: +List<Source.Node>
  for +other: +List<Source.Node>
  {Shell.split_base_region(Order.NavigationRegion{}, node, Shell.BaseParts{navigation, main, settings, other}) == Shell.BaseParts{node <> navigation, main, settings, other} : Shell.BaseParts}

law base_group_main:
  for +node: Source.Node
  for +navigation: +List<Source.Node>
  for +main: +List<Source.Node>
  for +settings: +List<Source.Node>
  for +other: +List<Source.Node>
  {Shell.split_base_region(Order.MainRegion{}, node, Shell.BaseParts{navigation, main, settings, other}) == Shell.BaseParts{navigation, node <> main, settings, other} : Shell.BaseParts}

law base_group_footer:
  for +node: Source.Node
  for +navigation: +List<Source.Node>
  for +main: +List<Source.Node>
  for +settings: +List<Source.Node>
  for +other: +List<Source.Node>
  {Shell.split_base_region(Order.NavigationFooterRegion{}, node, Shell.BaseParts{navigation, main, settings, other}) == Shell.BaseParts{navigation, main, node <> settings, other} : Shell.BaseParts}

law base_group_other:
  for +node: Source.Node
  for +navigation: +List<Source.Node>
  for +main: +List<Source.Node>
  for +settings: +List<Source.Node>
  for +other: +List<Source.Node>
  {Shell.split_base_region(Order.OtherRegion{}, node, Shell.BaseParts{navigation, main, settings, other}) == Shell.BaseParts{navigation, main, settings, node <> other} : Shell.BaseParts}


law modal_navigation_geometry:
  for +node: Source.Node
  for +capacity: View.Capacity
  for +parameters: Design.LayoutParameters
  for layers: +List<View.Layer>
  for base: +List<Design.Node>
  for overlays: +List<Design.Node>
  for anchors: +List<Shell.Anchor>
  for docked: +List<Source.Node>
  for floating: +List<Source.Node>
  {Shell.split_overlay_node(node, InterfaceView.Navigation{}, capacity, View.ModalNavigation{}, parameters, layers, base, overlays, anchors, Shell.OverlayParts{docked, floating}) ==
    Shell.OverlayParts{docked, Shell.resize(node, Model.ExactSize{Design.navigation_width(parameters)}, Model.StretchSize{}, Model.ScrollVertically{}, Spatial.Stretch{}, Spatial.AlignedLayer{Enclosure.Insets{0n, 0n}, Spatial.Leading{}, Spatial.Leading{}}) <> floating} : Shell.OverlayParts}


law modal_navigation_population:
  for +key: UIIdentity.Key
  for +tag: Source.BoxTag
  for +style: Source.Style
  for +attributes: +List<Source.Attribute>
  for +children: +List<Source.Node>
  for +rest: +List<Source.Node>
  for +capacity: View.Capacity
  for +parameters: Design.LayoutParameters
  for +layers: +List<View.Layer>
  for +base: +List<Design.Node>
  for +overlays: +List<Design.Node>
  for +anchors: +List<Shell.Anchor>
  for identified: {Shell.base_role(key, overlays) == InterfaceView.Navigation{} : InterfaceView.Role}
  {Shell.split_overlays(Source.Box{key, tag, style, attributes, children} <> rest, capacity, View.ModalNavigation{}, parameters, layers, base, overlays, anchors) ==
    Shell.split_overlay_node(Source.Box{key, tag, style, attributes, children}, InterfaceView.Navigation{}, capacity, View.ModalNavigation{}, parameters, layers, base, overlays, anchors,
      Shell.split_overlays(rest, capacity, View.ModalNavigation{}, parameters, layers, base, overlays, anchors)) : Shell.OverlayParts}

law modal_navigation_box_preserved:
  for +key: UIIdentity.Key
  for +tag: Source.BoxTag
  for +direction: Model.Direction
  for +main: Spatial.Alignment
  for cross: Spatial.Alignment
  for +frame: Enclosure.Frame
  for width: Model.AxisSize
  for height: Model.AxisSize
  for +minimum: Enclosure.Extent
  for scroll: Model.Scroll
  for position: Spatial.Position
  for +font: Source.FontChoice
  for +chrome: Design.Chrome
  for +states: Design.ControlStates
  for +attributes: +List<Source.Attribute>
  for +children: +List<Source.Node>
  for +capacity: View.Capacity
  for +parameters: Design.LayoutParameters
  for layers: +List<View.Layer>
  for base: +List<Design.Node>
  for overlays: +List<Design.Node>
  for anchors: +List<Shell.Anchor>
  for docked: +List<Source.Node>
  for floating: +List<Source.Node>
  {Shell.split_overlay_node(Source.Box{key, tag, Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states}, attributes, children}, InterfaceView.Navigation{}, capacity, View.ModalNavigation{}, parameters, layers, base, overlays, anchors, Shell.OverlayParts{docked, floating}) ==
    Shell.OverlayParts{docked, Source.Box{key, tag, Source.Style{Source.Layout{direction, main, Spatial.Stretch{}, frame, Model.ExactSize{Design.navigation_width(parameters)}, Model.StretchSize{}, minimum, Model.ScrollVertically{}, Spatial.AlignedLayer{Enclosure.Insets{0n, 0n}, Spatial.Leading{}, Spatial.Leading{}}}, font, chrome, states}, attributes, children} <> floating} : Shell.OverlayParts}


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

def dialog_clearance(parameters: Design.LayoutParameters) -> Enclosure.Insets:
  Design.LayoutParameters{navigation_width, main_minimum_width, details_width, reading_width, overview_width, toolbar_height, input_minimum_height, input_maximum_height, line_height, creation_height, lane_width} = parameters
  Shell.outside_insets(Nat.max(1n, Nat.div(line_height, 4n)))

law dialog_floating_geometry:
  for +node: Source.Node
  for +parameters: Design.LayoutParameters
  for layers: +List<View.Layer>
  for base: +List<Design.Node>
  for overlays: +List<Design.Node>
  for anchors: +List<Shell.Anchor>
  for docked: +List<Source.Node>
  for floating: +List<Source.Node>
  {Shell.float_overlay(InterfaceView.Dialog{}, parameters, node, layers, base, overlays, anchors, docked, floating) ==
    Shell.OverlayParts{docked, Shell.resize(node, Model.CappedStretchSize{Shell.dialog_reading_width(parameters)}, Model.CappedNaturalSize{100n}, Model.Confined{}, Spatial.Stretch{}, Spatial.CenteredLayer{dialog_clearance(parameters)}) <> floating} : Shell.OverlayParts}


law dialog_floating_box_preserved:
  for +key: UIIdentity.Key
  for +tag: Source.BoxTag
  for +direction: Model.Direction
  for +main: Spatial.Alignment
  for cross: Spatial.Alignment
  for +frame: Enclosure.Frame
  for width: Model.AxisSize
  for height: Model.AxisSize
  for +minimum: Enclosure.Extent
  for scroll: Model.Scroll
  for position: Spatial.Position
  for +font: Source.FontChoice
  for +chrome: Design.Chrome
  for +states: Design.ControlStates
  for +attributes: +List<Source.Attribute>
  for +children: +List<Source.Node>
  for +parameters: Design.LayoutParameters
  for layers: +List<View.Layer>
  for base: +List<Design.Node>
  for overlays: +List<Design.Node>
  for anchors: +List<Shell.Anchor>
  for docked: +List<Source.Node>
  for floating: +List<Source.Node>
  {Shell.float_overlay(InterfaceView.Dialog{}, parameters, Source.Box{key, tag, Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states}, attributes, children}, layers, base, overlays, anchors, docked, floating) ==
    Shell.OverlayParts{docked, Source.Box{key, tag, Source.Style{Source.Layout{direction, main, Spatial.Stretch{}, frame, Model.CappedStretchSize{Shell.dialog_reading_width(parameters)}, Model.CappedNaturalSize{100n}, minimum, Model.Confined{}, Spatial.CenteredLayer{dialog_clearance(parameters)}}, font, chrome, states}, attributes, children} <> floating} : Shell.OverlayParts}
