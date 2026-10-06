import ../core/composition.bend as Composition
import ./presentation-order.bend as Order
import Base
import ../core/ui-identity.bend as UIIdentity
import ./authored-shell.bend as Shell
import ./source.bend as Source
import ./document.bend as Doc
import ./physical-space.bend as Model
import ./typography.bend as Typography
import ./space.bend as Space
import ./physical-space-rules.bend as SpaceRules
import ./design.bend as Design
import ./spatial.bend as Spatial
import ./enclosure.bend as Enclosure
import ../core/ui-world.bend as View
import ../core/SYSTEM.bend as Core
import ../core/interface.bend as UI

def reframing_events(+node: Source.Node, layout: Source.Layout) -> Type:
  {Source.events_of(Shell.reframe(node, layout)) == Source.events_of(node) : +List<Doc.Event>}

def reframing_interaction(+node: Source.Node, layout: Source.Layout) -> Type:
  {Source.interaction_of(Shell.reframe(node, layout)) == Source.interaction_of(node) : Model.Interaction<Doc.Event>}

def reframing_children(+node: Source.Node, layout: Source.Layout) -> Type:
  {Source.children_of(Shell.reframe(node, layout)) == Source.children_of(node) : +List<Source.Node>}

def wrapper_children(key: UIIdentity.Key, style: Source.Style, +children: +List<Source.Node>) -> Type:
  {Source.children_of(Shell.wrap(key, style, children)) == children : +List<Source.Node>}

def wrapper_events(key: UIIdentity.Key, style: Source.Style, children: +List<Source.Node>) -> Type:
  {Source.events_of(Shell.wrap(key, style, children)) == Nil{} : +List<Doc.Event>}

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
  {Shell.structure_reading_width(Design.MainStructure{Composition.ReadingMeasure{}, Composition.CenteredCreation{}}, parameters) == Design.reading_maximum_width(parameters) : Nat}

def creation_assembly(+content: Core.Scene, +theme: Design.Theme, +base: +List<Design.Node>, +overlays: +List<Design.Node>, scope: Maybe<&2, String>, +base_nodes: +List<Source.Node>, +overlay_nodes: +List<Source.Node>, +capacity: View.Capacity, +parameters: Design.LayoutParameters, +layers: +List<View.Layer>, +anchors: +List<Shell.Anchor>, +font: Typography.Presentation) -> Type:
  {Shell.assemble_surface(Design.Surface{content, theme, base, overlays, scope}, base_nodes, overlay_nodes, capacity, parameters, layers, anchors, font) ==
    Shell.assembled_parts(Shell.split_overlays(overlay_nodes, capacity, parameters, layers, base, overlays, anchors), Design.MainStructure{Composition.ReadingMeasure{}, Composition.CenteredCreation{}}, Design.reading_maximum_width(parameters), base_nodes, base, Shell.scene_navigation_placement(content), parameters, font, theme) : Shell.Result}

def creation_child_layout(+layout: Source.Layout, maximum: Nat) -> Type:
  Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position} = layout
  {Shell.creation_layout(layout, maximum) == Source.Layout{direction, main, cross, frame, Shell.reading_policy(width, maximum), Model.NaturalSize{}, minimum, Model.Confined{}, position} : Source.Layout}

def creation_main(+key: UIIdentity.Key, tag: Source.BoxTag, +style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, +maximum: Nat) -> Type:
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, +font, chrome, states} = style
  {Shell.main_box(Design.MainStructure{Composition.ReadingMeasure{}, Composition.CenteredCreation{}}, key, tag, style, attributes, children, maximum) ==
    Source.Box{key, tag, Source.Style{Source.Layout{Model.Vertical{}, Spatial.Centered{}, Spatial.Centered{}, Enclosure.Frame{Enclosure.area(Enclosure.PageContent{}), Enclosure.SeparateFrames{Enclosure.Sections{}}}, Model.StretchSize{}, Model.StretchSize{}, minimum, Model.ScrollVertically{}, Spatial.InFlow{}}, font, chrome, states}, attributes, [Shell.creation_group(key, font, maximum, children)]} : Source.Node}

def other_organization(organization: Composition.Body) -> Bool:
  match organization:
    case Composition.CenteredCreation{}: False{}
    case _: True{}

def other_structure(structure: Design.MainStructure) -> Bool:
  Design.MainStructure{measure, organization} = structure
  other_organization(organization)

def other_main(structure: Design.MainStructure, +key: UIIdentity.Key, tag: Source.BoxTag, +style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, +maximum: Nat) -> Type:
  Design.MainStructure{measure, +organization} = structure
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = style
  {Shell.main_box(Design.MainStructure{measure, organization}, key, tag, style, attributes, children, maximum) ==
    Source.Box{key, tag, Source.Style{Source.Layout{direction, Shell.main_leading(organization, main), Shell.main_cross(organization), Shell.main_frame(organization, frame), Model.StretchSize{}, Model.StretchSize{}, minimum, scroll, Spatial.InFlow{}}, font, chrome, states}, attributes, Shell.measure_children(measure, children, maximum)} : Source.Node}

def navigation_box(key: UIIdentity.Key, tag: Source.BoxTag, +style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, rest: +List<Source.Node>, +width: Nat) -> Type:
  Source.Style{Source.Layout{direction, main, cross, frame, old_width, height, minimum, scroll, position}, font, chrome, states} = style
  {Shell.navigation_nodes(Source.Box{key, tag, style, attributes, children} <> rest, width) ==
    Source.Box{key, tag, Source.Style{Source.Layout{direction, main, Spatial.Stretch{}, frame, Model.ExactSize{width}, Model.StretchSize{}, minimum, Model.ScrollVertically{}, Spatial.InFlow{}}, font, chrome, states}, attributes, children} <> Shell.navigation_nodes(rest, width) : +List<Source.Node>}

def settings_role(role: UI.Role) -> Bool:
  match role:
    case UI.Main{}: False{}
    case UI.Navigation{}: False{}
    case _: True{}

def settings_classification(+node: Source.Node, role: UI.Role, +navigation: +List<Source.Node>, +main: +List<Source.Node>, +settings: +List<Source.Node>, +other: +List<Source.Node>) -> Type:
  {Shell.split_base_role(node, role, navigation, main, settings, other) == Shell.BaseParts{navigation, main, node <> settings, other} : Shell.BaseParts}

def recipe_structure(recipe: Composition.Recipe) -> Type:
  Composition.Recipe{measure, heading, organization, composer, decisions, latest} = recipe
  {Design.main_structure(Composition.Recipe{measure, heading, organization, composer, decisions, latest}) == Design.MainStructure{measure, organization} : Design.MainStructure}

def available_children(children: +List<Source.Node>, maximum: Nat) -> Type:
  {Shell.measure_children(Composition.AvailableMeasure{}, children, maximum) == children : +List<Source.Node>}

def page_frame(previous: Enclosure.Frame) -> Type:
  {Shell.main_frame(Composition.StageColumns{}, previous) == Enclosure.Frame{Enclosure.area(Enclosure.PageContent{}), Enclosure.SeparateFrames{Enclosure.Sections{}}} : Enclosure.Frame}


def measure_width(parameters: Design.LayoutParameters, organization: Composition.Body) -> Type:
  {(Shell.structure_reading_width(Design.MainStructure{Composition.ReadingMeasure{}, organization}, parameters), (Shell.structure_reading_width(Design.MainStructure{Composition.OverviewMeasure{}, organization}, parameters), Shell.structure_reading_width(Design.MainStructure{Composition.AvailableMeasure{}, organization}, parameters))) == (Design.reading_maximum_width(parameters), (Design.overview_maximum_width(parameters), 0n)) : Nat & (Nat & Nat)}

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
  {Shell.assemble_surface(Design.Surface{content, theme, base, overlays, scope}, base_nodes, overlay_nodes, capacity, parameters, layers, anchors, font) == Shell.assembled_parts(Shell.split_overlays(overlay_nodes, capacity, parameters, layers, base, overlays, anchors), Shell.scene_structure(content), Shell.structure_reading_width(Shell.scene_structure(content), parameters), base_nodes, base, placement, parameters, font, theme) : Shell.Result}

type Requirements is Type:
  Requirements{
    navigation_projection: @content:Core.Scene -> navigation_projection(content),
    assembly_placement: @+content:Core.Scene -> @+theme:Design.Theme -> @+base:+List<Design.Node> -> @+overlays:+List<Design.Node> -> @scope:Maybe<&2, String> -> @+base_nodes:+List<Source.Node> -> @+overlay_nodes:+List<Source.Node> -> @+capacity:View.Capacity -> @+parameters:Design.LayoutParameters -> @+layers:+List<View.Layer> -> @+anchors:+List<Shell.Anchor> -> @+font:Typography.Presentation -> @placement:View.NavigationPlacement -> @projected:{Shell.scene_navigation_placement(content) == placement : View.NavigationPlacement} -> assembly_placement(content, theme, base, overlays, scope, base_nodes, overlay_nodes, capacity, parameters, layers, anchors, font, placement),
    beside_box_floor: @structure:Design.MainStructure -> @key:UIIdentity.Key -> @tag:Source.BoxTag -> @style:Source.Style -> @attributes:+List<Source.Attribute> -> @children:+List<Source.Node> -> @maximum:Nat -> @+required:Nat -> beside_box_floor(structure, key, tag, style, attributes, children, maximum, required),
    beside_main_style: @style:Source.Style -> @+required:Nat -> beside_main_style(style, required),
    compact_main_style: @style:Source.Style -> @required:Nat -> compact_main_style(style, required),
    main_population: @key:UIIdentity.Key -> @tag:Source.BoxTag -> @style:Source.Style -> @attributes:+List<Source.Attribute> -> @children:+List<Source.Node> -> @rest:+List<Source.Node> -> @structure:Design.MainStructure -> @maximum:Nat -> @beside:Bool -> @required:Nat -> main_population(key, tag, style, attributes, children, rest, structure, maximum, beside, required),
    main_placement_input: @placement:View.NavigationPlacement -> @parameters:Design.LayoutParameters -> @structure:Design.MainStructure -> @reading_width:Nat -> @navigation:+List<Source.Node> -> @main:+List<Source.Node> -> @settings:+List<Source.Node> -> @other:+List<Source.Node> -> @docked:+List<Source.Node> -> @font:Typography.Presentation -> main_placement_input(placement, parameters, structure, reading_width, navigation, main, settings, other, docked, font),
    measure_width: @parameters:Design.LayoutParameters -> @organization:Composition.Body -> measure_width(parameters, organization),
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
      @created:{Shell.scene_structure(content) == Design.MainStructure{Composition.ReadingMeasure{}, Composition.CenteredCreation{}} : Design.MainStructure} -> creation_assembly(content, theme, base, overlays, scope, base_nodes, overlay_nodes, capacity, parameters, layers, anchors, font),
    creation_child_layout: @+layout:Source.Layout -> @maximum:Nat -> creation_child_layout(layout, maximum),
    creation_main: @+key:UIIdentity.Key -> @tag:Source.BoxTag -> @+style:Source.Style -> @attributes:+List<Source.Attribute> -> @children:+List<Source.Node> -> @+maximum:Nat -> creation_main(key, tag, style, attributes, children, maximum),
    other_main: @+structure:Design.MainStructure -> @+key:UIIdentity.Key -> @tag:Source.BoxTag -> @+style:Source.Style -> @attributes:+List<Source.Attribute> -> @children:+List<Source.Node> -> @+maximum:Nat -> @other:{other_structure(structure) == True{} : Bool} -> other_main(structure, key, tag, style, attributes, children, maximum),
    navigation_box: @key:UIIdentity.Key -> @tag:Source.BoxTag -> @+style:Source.Style -> @attributes:+List<Source.Attribute> -> @children:+List<Source.Node> -> @rest:+List<Source.Node> -> @+width:Nat -> navigation_box(key, tag, style, attributes, children, rest, width),
    settings_classification: @+node:Source.Node -> @+role:UI.Role -> @+navigation:+List<Source.Node> -> @+main:+List<Source.Node> -> @+settings:+List<Source.Node> -> @+other:+List<Source.Node> ->
      @identified:{Source.key_of(node) == UIIdentity.part(UIIdentity.place(""), "settings/open") : UIIdentity.Key} -> @belongs:{settings_role(role) == True{} : Bool} -> settings_classification(node, role, navigation, main, settings, other),
    footer: @key:UIIdentity.Key -> @tag:Source.BoxTag -> @style:Source.Style -> @attributes:+List<Source.Attribute> -> @+children:+List<Source.Node> -> @+settings:+List<Source.Node> -> @+font:Typography.Presentation -> footer_children(key, tag, style, attributes, children, settings, font)
  }

law evidence:
  Requirements

law base_shared_classification:
  for +node: Source.Node
  for role: UI.Role
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
