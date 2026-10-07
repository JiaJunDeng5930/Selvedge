import ./presentation-order.bend as Order
import Base
import ../core/ui-identity.bend as UIIdentity
import ./authored.bend as Authored
import ./source.bend as Source
import ./design.bend as Design
import ./physical-space.bend as Model
import ./spatial.bend as Spatial
import ./enclosure.bend as Enclosure
import ./typography.bend as Typography
import ../core/interface.bend as UI
import ../core/ui-world.bend as View
import ../core/SYSTEM.bend as Core
import ../core/composition.bend as Composition

type Anchor is Data:
  Anchor{key: String, bounds: Spatial.Box}

type Result is Data:
  Ready{source: Source.Node}
  Rejected{key: UIIdentity.Key, problem: Authored.Problem}

type BaseParts is Data:
  BaseParts{navigation: +List<Source.Node>, main: +List<Source.Node>, settings: +List<Source.Node>, other: +List<Source.Node>}

type OverlayParts is Data:
  OverlayParts{docked: +List<Source.Node>, floating: +List<Source.Node>}

def neutral_arranged(font: Source.FontChoice, direction: Model.Direction, width: Model.AxisSize, height: Model.AxisSize, cross: Spatial.Alignment, arrangement: Enclosure.Arrangement) -> Source.Style:
  Source.Style{Source.Layout{direction, Spatial.Leading{}, cross,
    Enclosure.frame(Enclosure.ambient(0n, 0n), arrangement),
    width, height, Enclosure.Extent{0n, 0n}, Model.Confined{}, Spatial.InFlow{}},
    font, Design.Chrome{Design.ThemeToken{"--color-token-text-primary"}, Design.Transparent{}, Design.Transparent{}, 0n, 0n, False{}}, Design.Passive{}}

def neutral_choice(font: Source.FontChoice, direction: Model.Direction, width: Model.AxisSize, height: Model.AxisSize, cross: Spatial.Alignment) -> Source.Style:
  neutral_arranged(font, direction, width, height, cross, Enclosure.EmbeddedContent{0n})

def neutral(font: Typography.Presentation, direction: Model.Direction, width: Model.AxisSize, height: Model.AxisSize, cross: Spatial.Alignment) -> Source.Style:
  neutral_choice(Source.ExplicitFont{font}, direction, width, height, cross)

def theme_name(theme: Design.Theme) -> String:
  match theme:
    case Design.Light{}: "light"
    case Design.Dark{}: "dark"

def application_background(style: Source.Style) -> Source.Style:
  Source.Style{layout, font_choice, chrome, states} = style
  Source.Style{layout, font_choice, Design.Chrome{Design.ThemeToken{"--color-token-text-primary"}, Design.ThemeToken{"--color-token-bg-primary"}, Design.Transparent{}, 0n, 0n, False{}}, states}

# Shell geometry retains the authored interaction, typography and descendants.
def application_style(+font: Typography.Presentation) -> Source.Style:
  application_background(neutral(font, Model.Layered{}, Model.StretchSize{}, Model.StretchSize{}, Spatial.Stretch{}))

def reframed_style(style: Source.Style, layout: Source.Layout) -> Source.Style:
  Source.Style{old_layout, font, chrome, states} = style
  Source.Style{layout, font, chrome, states}

def reframe(node: Source.Node, +layout: Source.Layout) -> Source.Node:
  match node:
    case Source.NativeAttachment{key, target, attributes, style, children}: Source.NativeAttachment{key, target, attributes, reframed_style(style, layout), children}
    case Source.Box{key, tag, style, attributes, children}: Source.Box{key, tag, reframed_style(style, layout), attributes, children}
    case Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: Source.Control{key, tag, reframed_style(style, layout), attributes, accessible_name, enabled, first_event, remaining_events, children}
    case Source.Glyph{key, drawing, style}: Source.Glyph{key, drawing, reframed_style(style, layout)}
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: Source.Field{key, kind, reframed_style(style, layout), attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}
    case Source.RichText{key, style, content, attachments, native_owner}: Source.RichText{key, reframed_style(style, layout), content, attachments, native_owner}
    case Source.Text{key, value, font, wrapping}: Source.Text{key, value, font, wrapping}

def layout_of(node: Source.Node) -> Source.Layout:
  match node:
    case Source.NativeAttachment{key, target, attributes, Source.Style{layout, font, chrome, states}, children}: layout
    case Source.Box{key, tag, Source.Style{layout, font, chrome, states}, attributes, children}: layout
    case Source.Control{key, tag, Source.Style{layout, font, chrome, states}, attributes, accessible_name, enabled, first_event, remaining_events, children}: layout
    case Source.Glyph{key, drawing, Source.Style{layout, font, chrome, states}}: layout
    case Source.Field{key, kind, Source.Style{layout, font, chrome, states}, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: layout
    case Source.RichText{key, Source.Style{layout, font, chrome, states}, content, attachments, native_owner}: layout
    case Source.Text{key, value, font, wrapping}:
      Source.Layout{Model.Vertical{}, Spatial.Leading{}, Spatial.Leading{}, Enclosure.frame(Enclosure.ambient(0n, 0n), Enclosure.EmbeddedContent{0n}), Model.NaturalSize{}, Model.NaturalSize{}, Enclosure.Extent{0n, 0n}, Model.Confined{}, Spatial.InFlow{}}

def resized_layout(layout: Source.Layout, width: Model.AxisSize, height: Model.AxisSize, scroll: Model.Scroll, cross: Spatial.Alignment, position: Spatial.Position) -> Source.Layout:
  Source.Layout{direction, main, old_cross, frame, old_width, old_height, minimum, old_scroll, old_position} = layout
  Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}

def resize(+node: Source.Node, width: Model.AxisSize, height: Model.AxisSize, scroll: Model.Scroll, cross: Spatial.Alignment, position: Spatial.Position) -> Source.Node:
  reframe(node, resized_layout(layout_of(node), width, height, scroll, cross, position))

def wrap(key: UIIdentity.Key, style: Source.Style, children: +List<Source.Node>) -> Source.Node:
  Source.Box{key, Source.Div{}, style, Nil{}, children}

def spacer(key: UIIdentity.Key, font: Typography.Presentation) -> Source.Node:
  Source.Box{key, Source.Div{}, neutral(font, Model.Vertical{}, Model.StretchSize{}, Model.StretchSize{}, Spatial.Stretch{}), Nil{}, Nil{}}

def with_footer(key: UIIdentity.Key, tag: Source.BoxTag, style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, settings: +List<Source.Node>, font: Typography.Presentation) -> Source.Node:
  Source.Box{key, tag, style, attributes, List.append(&2, Source.Node, children, spacer(UIIdentity.part(UIIdentity.place("/application"), "navigation-spacer"), font) <> settings)}

def base_role_found(found: Bool, role: UI.Role, fallback: UI.Role) -> UI.Role:
  match found:
    case True{}: role
    case False{}: fallback

def base_role(+key: UIIdentity.Key, +values: +List<Design.Node>) -> UI.Role:
  match values:
    case Nil{}: UI.Content{}
    case Con{Design.Node{current, semantic, label, role, meaning, style, control, children}, rest}:
      base_role_found(UIIdentity.same(key, current), role, base_role(key, rest))

def split_base_region(region: Order.BaseRegion, node: Source.Node, parts: BaseParts) -> BaseParts:
  match region parts:
    case Order.NavigationRegion{} BaseParts{navigation, main, settings, other}: BaseParts{node <> navigation, main, settings, other}
    case Order.MainRegion{} BaseParts{navigation, main, settings, other}: BaseParts{navigation, node <> main, settings, other}
    case Order.NavigationFooterRegion{} BaseParts{navigation, main, settings, other}: BaseParts{navigation, main, node <> settings, other}
    case Order.OtherRegion{} BaseParts{navigation, main, settings, other}: BaseParts{navigation, main, settings, node <> other}

def split_base_settings(found: Bool, node: Source.Node, parts: BaseParts) -> BaseParts:
  split_base_region(Order.footer_region(found), node, parts)

def split_base_role(+node: Source.Node, role: UI.Role, navigation: +List<Source.Node>, main: +List<Source.Node>, settings: +List<Source.Node>, other: +List<Source.Node>) -> BaseParts:
  split_base_region(Order.base_region_role(Source.key_of(node), role), node, BaseParts{navigation, main, settings, other})

def split_base_node(+node: Source.Node, role: UI.Role, parts: BaseParts) -> BaseParts:
  split_base_region(Order.base_region(Source.key_of(node), role), node, parts)

def split_base(+values: +List<Source.Node>, +design: +List<Design.Node>) -> BaseParts:
  match values:
    case Nil{}: BaseParts{Nil{}, Nil{}, Nil{}, Nil{}}
    case Con{+node, rest}:
      split_base_node(node, base_role(Source.key_of(node), design), split_base(rest, design))

def navigation_footer(+values: +List<Source.Node>, settings: +List<Source.Node>, +font: Typography.Presentation) -> +List<Source.Node>:
  match values:
    case Nil{}: settings
    case Con{Source.Box{key, tag, style, attributes, children}, rest}:
      with_footer(key, tag, style, attributes, children, settings, font) <> rest
    case Con{first, rest}: first <> navigation_footer(rest, settings, font)

def navigation_nodes(+values: +List<Source.Node>, +width: Nat) -> +List<Source.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{node, rest}:
      resize(node, Model.ExactSize{width}, Model.StretchSize{}, Model.ScrollVertically{}, Spatial.Stretch{}, Spatial.InFlow{}) <> navigation_nodes(rest, width)

def reading_policy(width: Model.AxisSize, maximum: Nat) -> Model.AxisSize:
  match width:
    case Model.StretchSize{}: Model.CappedStretchSize{maximum}
    case _: width

def reading_layout(layout: Source.Layout, +maximum: Nat) -> Source.Layout:
  Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position} = layout
  Source.Layout{direction, main, cross, frame, reading_policy(width, maximum), height, minimum, scroll, position}

def reading_children(values: +List<Source.Node>, +maximum: Nat) -> +List<Source.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{+node, rest}: reframe(node, reading_layout(layout_of(node), maximum)) <> reading_children(rest, maximum)

def creation_layout(+layout: Source.Layout, maximum: Nat) -> Source.Layout:
  Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position} = layout
  Source.Layout{direction, main, cross, frame, reading_policy(width, maximum), Model.NaturalSize{}, minimum, Model.Confined{}, position}

def creation_children(values: +List<Source.Node>, +maximum: Nat) -> +List<Source.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{+node, rest}: reframe(node, creation_layout(layout_of(node), maximum)) <> creation_children(rest, maximum)

def creation_group(key: UIIdentity.Key, font: Source.FontChoice, +maximum: Nat, children: +List<Source.Node>) -> Source.Node:
  wrap(UIIdentity.part(key, "creation-group"), neutral_arranged(font, Model.Vertical{}, Model.CappedStretchSize{maximum}, Model.NaturalSize{}, Spatial.Stretch{}, Enclosure.SeparateFrames{Enclosure.Sections{}}), creation_children(children, maximum))

def creation_main_box(+key: UIIdentity.Key, tag: Source.BoxTag, style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, +maximum: Nat) -> Source.Node:
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, +font, chrome, states} = style
  Source.Box{key, tag, Source.Style{Source.Layout{Model.Vertical{}, Spatial.Centered{}, Spatial.Centered{}, Enclosure.Frame{Enclosure.area(Enclosure.PageContent{}), Enclosure.SeparateFrames{Enclosure.Sections{}}}, Model.StretchSize{}, Model.StretchSize{}, minimum, Model.ScrollVertically{}, Spatial.InFlow{}}, font, chrome, states}, attributes, [creation_group(key, font, maximum, children)]}

def page_organization(organization: Composition.Body) -> Bool:
  match organization:
    case Composition.ProjectSections{}: True{}
    case Composition.ProjectRows{}: True{}
    case Composition.AgentRows{}: True{}
    case Composition.StageColumns{}: True{}
    case _: False{}

def page_frame_policy(page: Bool, frame: Enclosure.Frame) -> Enclosure.Frame:
  match page:
    case True{}: Enclosure.Frame{Enclosure.area(Enclosure.PageContent{}), Enclosure.SeparateFrames{Enclosure.Sections{}}}
    case False{}: frame

def page_leading(page: Bool, previous: Spatial.Alignment) -> Spatial.Alignment:
  match page:
    case True{}: Spatial.Leading{}
    case False{}: previous

def page_cross(page: Bool) -> Spatial.Alignment:
  match page:
    case True{}: Spatial.Leading{}
    case False{}: Spatial.Centered{}

def main_frame(organization: Composition.Body, frame: Enclosure.Frame) -> Enclosure.Frame:
  match organization:
    case Composition.ChronologicalReading{}: Enclosure.Frame{Enclosure.area(Enclosure.PageContent{}), Enclosure.SeparateFrames{Enclosure.Sections{}}}
    case _: page_frame_policy(page_organization(organization), frame)

def main_leading(organization: Composition.Body, previous: Spatial.Alignment) -> Spatial.Alignment:
  page_leading(page_organization(organization), previous)

def main_cross(organization: Composition.Body) -> Spatial.Alignment:
  page_cross(page_organization(organization))

def measure_children(measure: Composition.Measure, children: +List<Source.Node>, maximum: Nat) -> +List<Source.Node>:
  match measure:
    case Composition.AvailableMeasure{}: children
    case _: reading_children(children, maximum)

def ordinary_main_box(measure: Composition.Measure, +organization: Composition.Body, +key: UIIdentity.Key, tag: Source.BoxTag, style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, +maximum: Nat) -> Source.Node:
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = style
  Source.Box{key, tag, Source.Style{Source.Layout{direction, main_leading(organization, main), main_cross(organization), main_frame(organization, frame), Model.StretchSize{}, Model.StretchSize{}, minimum, scroll, Spatial.InFlow{}}, font, chrome, states}, attributes, measure_children(measure, children, maximum)}

def organized_main_box(measure: Composition.Measure, organization: Composition.Body, +key: UIIdentity.Key, tag: Source.BoxTag, style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, maximum: Nat) -> Source.Node:
  match organization:
    case Composition.CenteredCreation{}: creation_main_box(key, tag, style, attributes, children, maximum)
    case _: ordinary_main_box(measure, organization, key, tag, style, attributes, children, maximum)

def conversation_title_font(font: Source.FontChoice) -> Source.FontChoice:
  match font:
    case Source.InheritFont{}: Source.InheritFont{}
    case Source.ExplicitFont{presentation}:
      Source.ExplicitFont{Typography.with_emphasis(Typography.with_tier(presentation, Typography.Section{}), Typography.Medium{})}

def conversation_title_style(style: Source.Style) -> Source.Style:
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = style
  match direction:
    case Model.Vertical{}:
      Source.Style{Source.Layout{direction, Spatial.Centered{}, cross, frame, width, height, minimum, scroll, position}, conversation_title_font(font), chrome, states}
    case Model.Horizontal{}:
      Source.Style{Source.Layout{direction, main, Spatial.Centered{}, frame, width, height, minimum, scroll, position}, conversation_title_font(font), chrome, states}
    case Model.ResponsiveHorizontal{}:
      Source.Style{Source.Layout{direction, main, Spatial.Centered{}, frame, width, height, minimum, scroll, position}, conversation_title_font(font), chrome, states}
    case Model.Layered{}:
      Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, conversation_title_font(font), chrome, states}

def conversation_title_children(values: +List<Source.Node>) -> +List<Source.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Source.Box{key, tag, style, attributes, children}, rest}:
      Source.Box{key, tag, conversation_title_style(style), attributes, conversation_title_children(children)} <> conversation_title_children(rest)
    case Con{Source.Text{key, value, font, wrapping}, rest}:
      Source.Text{key, value, conversation_title_font(font), Typography.SingleLine{}} <> conversation_title_children(rest)
    case Con{other, rest}: other <> conversation_title_children(rest)

def conversation_title(node: Source.Node) -> Source.Node:
  match node:
    case Source.Box{key, tag, style, attributes, children}:
      Source.Box{key, tag, conversation_title_style(style), attributes, conversation_title_children(children)}
    case Source.Text{key, value, font, wrapping}:
      Source.Text{key, value, conversation_title_font(font), Typography.SingleLine{}}
    case other: other

def conversation_heading(+key: UIIdentity.Key, +style: Source.Style, title: Source.Node, actions: Source.Node) -> Source.Node:
  Source.Style{layout, font, chrome, states} = style
  Source.Box{UIIdentity.part(key, "@heading"), Source.Div{},
    Source.Style{Source.Layout{Model.Horizontal{}, Spatial.Leading{}, Spatial.Centered{},
      Enclosure.Frame{Enclosure.ambient(0n, 0n), Enclosure.SeparateFrames{Enclosure.ComposerControls{}}},
      Model.StretchSize{}, Model.NaturalSize{}, Enclosure.Extent{0n, 0n}, Model.Confined{}, Spatial.InFlow{}}, font, chrome, states}, Nil{}, [conversation_title(title), actions]}

def conversation_heading_children(key: UIIdentity.Key, style: Source.Style, children: +List<Source.Node>) -> +List<Source.Node>:
  match children:
    case Con{title, Con{actions, remaining}}: conversation_heading(key, style, title, actions) <> remaining
    case other: other

def heading_children(heading: Composition.Heading, key: UIIdentity.Key, style: Source.Style, children: +List<Source.Node>) -> +List<Source.Node>:
  match heading:
    case Composition.ConversationHeading{}: conversation_heading_children(key, style, children)
    case _: children

def main_box(structure: Design.MainStructure, +key: UIIdentity.Key, tag: Source.BoxTag, +style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, maximum: Nat) -> Source.Node:
  Design.MainStructure{measure, heading, organization} = structure
  organized_main_box(measure, organization, key, tag, style, attributes, heading_children(heading, key, style, children), maximum)

def minimum_style(style: Source.Style, +required: Nat) -> Source.Style:
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, Enclosure.Extent{minimum_width, minimum_height}, scroll, position}, font, chrome, states} = style
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, Enclosure.Extent{Nat.max(minimum_width, required), minimum_height}, scroll, position}, font, chrome, states}

def beside_style(beside: Bool, required: Nat, style: Source.Style) -> Source.Style:
  match beside:
    case True{}: minimum_style(style, required)
    case False{}: style

def main_nodes(values: +List<Source.Node>, +structure: Design.MainStructure, +maximum: Nat, +beside: Bool, +required: Nat) -> +List<Source.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Source.Box{key, tag, style, attributes, children}, rest}:
      main_box(structure, key, tag, beside_style(beside, required, style), attributes, children, maximum) <> main_nodes(rest, structure, maximum, beside, required)
    case Con{node, rest}: node <> main_nodes(rest, structure, maximum, beside, required)

def body_mode(beside: Bool, navigation_width: Nat, main_minimum_width: Nat, +structure: Design.MainStructure, +reading_width: Nat, navigation: +List<Source.Node>, main: +List<Source.Node>, settings: +List<Source.Node>, other: +List<Source.Node>, docked: +List<Source.Node>, +font: Typography.Presentation) -> Source.Node:
  match beside:
    case True{}:
      Source.Box{UIIdentity.part(UIIdentity.place("/application"), "body"), Source.Div{}, neutral(font, Model.Horizontal{}, Model.StretchSize{}, Model.StretchSize{}, Spatial.Stretch{}), Nil{},
        List.append(&2, Source.Node, navigation_nodes(navigation_footer(navigation, settings, font), navigation_width), List.append(&2, Source.Node, main_nodes(main, structure, reading_width, True{}, main_minimum_width), List.append(&2, Source.Node, other, docked)))}
    case False{}:
      Source.Box{UIIdentity.part(UIIdentity.place("/application"), "body"), Source.Div{}, neutral(font, Model.Vertical{}, Model.StretchSize{}, Model.StretchSize{}, Spatial.Stretch{}), Nil{},
        Source.Box{UIIdentity.part(UIIdentity.place("/application"), "topbar"), Source.Div{}, neutral(font, Model.Horizontal{}, Model.StretchSize{}, Model.NaturalSize{}, Spatial.Centered{}), Nil{},
          List.append(&2, Source.Node, navigation, spacer(UIIdentity.part(UIIdentity.place("/application"), "topbar-spacer"), font) <> settings)} <>
        List.append(&2, Source.Node, main_nodes(main, structure, reading_width, False{}, main_minimum_width), List.append(&2, Source.Node, other, docked))}

def body_direction(placement: View.NavigationPlacement, +parameters: Design.LayoutParameters, structure: Design.MainStructure, reading_width: Nat, navigation: +List<Source.Node>, main: +List<Source.Node>, settings: +List<Source.Node>, other: +List<Source.Node>, docked: +List<Source.Node>, +font: Typography.Presentation) -> Source.Node:
  match placement:
    case View.LeadingNavigation{}: body_mode(True{}, Design.navigation_width(parameters), Design.main_minimum_width(parameters), structure, reading_width, navigation, main, settings, other, docked, font)
    case View.ModalNavigation{}: body_mode(False{}, Design.navigation_width(parameters), Design.main_minimum_width(parameters), structure, reading_width, navigation, main, settings, other, docked, font)
    case View.CollapsedNavigation{}: body_mode(False{}, Design.navigation_width(parameters), Design.main_minimum_width(parameters), structure, reading_width, navigation, main, settings, other, docked, font)

def body(parts: BaseParts, structure: Design.MainStructure, reading_width: Nat, placement: View.NavigationPlacement, +parameters: Design.LayoutParameters, docked: +List<Source.Node>, +font: Typography.Presentation) -> Source.Node:
  BaseParts{navigation, main, settings, other} = parts
  body_direction(placement, parameters, structure, reading_width, navigation, main, settings, other, docked, font)

def prefer_anchor(found: Maybe<&2, String>, fallback: Maybe<&2, String>) -> Maybe<&2, String>:
  match found:
    case Some{key}: Some{key}
    case None{}: fallback

def semantic_anchor_found(found: Bool, key: String, fallback: Maybe<&2, String>) -> Maybe<&2, String>:
  match found:
    case True{}: Some{key}
    case False{}: fallback

def semantic_anchor(+requested: String, +values: +List<UI.Node>) -> Maybe<&2, String>:
  match values:
    case Nil{}: None{}
    case Con{UI.Node{key, semantic, label, role, meaning, children}, rest}:
      semantic_anchor_found(String.eq(semantic, requested), UIIdentity.encode(key), prefer_anchor(semantic_anchor(requested, children), semantic_anchor(requested, rest)))

def found_key(found: Maybe<&2, UI.Node>) -> Maybe<&2, String>:
  match found:
    case None{}: None{}
    case Some{UI.Node{key, semantic, label, role, meaning, children}}: Some{UIIdentity.encode(key)}

def anchor_key(+requested: String, +base: +List<Design.Node>, +overlays: +List<Design.Node>) -> Maybe<&2, String>:
  +semantic_base = Design.semantic_nodes(base)
  +semantic_overlays = Design.semantic_nodes(overlays)
  prefer_anchor(found_key(UI.find_node(semantic_base, requested)),
    prefer_anchor(found_key(UI.find_node(semantic_overlays, requested)),
      prefer_anchor(semantic_anchor(requested, semantic_base), semantic_anchor(requested, semantic_overlays))))

def observed_anchor_found(found: Bool, bounds: Spatial.Box, fallback: Maybe<&2, Spatial.Box>) -> Maybe<&2, Spatial.Box>:
  match found:
    case True{}: Some{bounds}
    case False{}: fallback

def observed_anchor(+key: String, anchors: +List<Anchor>) -> Maybe<&2, Spatial.Box>:
  match anchors:
    case Nil{}: None{}
    case Con{Anchor{current, bounds}, rest}:
      observed_anchor_found(String.eq(key, current), bounds, observed_anchor(key, rest))

def layer_found(found: Bool, layer: View.Layer, fallback: Maybe<&2, View.Layer>) -> Maybe<&2, View.Layer>:
  match found:
    case True{}: Some{layer}
    case False{}: fallback

def find_layer(+key: String, layers: +List<View.Layer>) -> Maybe<&2, View.Layer>:
  match layers:
    case Nil{}: None{}
    case Con{+layer, rest}:
      View.Layer{kind, content, initial, restore, dismissal} = layer
      layer_found(String.eq(UIIdentity.encode(UI.layer_key(initial)), key), layer, find_layer(key, rest))

def anchored_position(found: Maybe<&2, String>, outside: Enclosure.Insets, gap: Nat, anchors: +List<Anchor>) -> Spatial.Position:
  match found:
    case None{}: Spatial.CenteredLayer{outside}
    case Some{+key}: Spatial.AnchoredLayer{key, observed_anchor(key, anchors), outside, gap, Spatial.Leading{}}

def menu_position(found: Maybe<&2, View.Layer>, +outside: Enclosure.Insets, gap: Nat, base: +List<Design.Node>, overlays: +List<Design.Node>, anchors: +List<Anchor>) -> Spatial.Position:
  match found:
    case Some{View.Layer{View.AnchoredMenu{}, content, initial, restore, dismissal}}:
      anchored_position(anchor_key(restore, base, overlays), outside, gap, anchors)
    case _: Spatial.CenteredLayer{outside}

def floating_position(role: UI.Role, key: UIIdentity.Key, +outside: Enclosure.Insets, gap: Nat, layers: +List<View.Layer>, base: +List<Design.Node>, overlays: +List<Design.Node>, anchors: +List<Anchor>) -> Spatial.Position:
  match role:
    case UI.Menu{}: menu_position(find_layer(UIIdentity.encode(key), layers), outside, gap, base, overlays, anchors)
    case _: Spatial.CenteredLayer{outside}

def dialog_reading_span(reading_width: Nat, line_height: Nat) -> Nat:
  Nat.min(reading_width, Nat.mul(24n, line_height))

def dialog_reading_width(parameters: Design.LayoutParameters) -> Nat:
  Design.LayoutParameters{navigation_width, main_minimum_width, details_width, reading_width, overview_width, toolbar_height, input_minimum_height, input_maximum_height, line_height, creation_height, lane_width} = parameters
  dialog_reading_span(reading_width, line_height)

def floating_width(role: UI.Role, +reading_width: Nat, dialog_width: Nat) -> Model.AxisSize:
  match role:
    case UI.Dialog{}: Model.CappedStretchSize{dialog_width}
    case UI.Menu{}: Model.CappedNaturalSize{100n}
    case _: Model.LimitedSize{0n, reading_width, reading_width}

def floating_scroll(role: UI.Role) -> Model.Scroll:
  match role:
    case UI.Dialog{}: Model.Confined{}
    case _: Model.ScrollVertically{}

def dock_overlay(parameters: Design.LayoutParameters, node: Source.Node, docked: +List<Source.Node>, floating: +List<Source.Node>) -> OverlayParts:
  Design.LayoutParameters{navigation_width, main_minimum_width, +details_width, reading_width, overview_width, toolbar_height, input_minimum_height, input_maximum_height, line_height, creation_height, lane_width} = parameters
  OverlayParts{resize(node, Model.LimitedSize{0n, details_width, details_width}, Model.StretchSize{}, Model.ScrollVertically{}, Spatial.Stretch{}, Spatial.InFlow{}) <> docked, floating}

def outside_insets(+unit: Nat) -> Enclosure.Insets:
  Enclosure.Insets{Nat.mul(2n, unit), Nat.mul(2n, unit)}

def float_overlay(+role: UI.Role, +parameters: Design.LayoutParameters, +node: Source.Node, layers: +List<View.Layer>, base: +List<Design.Node>, overlays: +List<Design.Node>, anchors: +List<Anchor>, docked: +List<Source.Node>, floating: +List<Source.Node>) -> OverlayParts:
  Design.LayoutParameters{navigation_width, main_minimum_width, details_width, +reading_width, overview_width, toolbar_height, input_minimum_height, input_maximum_height, +line_height, creation_height, lane_width} = parameters
  +dialog_width = dialog_reading_span(reading_width, line_height)
  +unit = Nat.max(1n, Nat.div(line_height, 4n))
  +outside = outside_insets(unit)
  OverlayParts{docked, resize(node, floating_width(role, reading_width, dialog_width), Model.CappedNaturalSize{100n}, floating_scroll(role), Spatial.Stretch{}, floating_position(role, Source.key_of(node), outside, unit, layers, base, overlays, anchors)) <> floating}

def standard_overlay_layout(+role: UI.Role, details_beside: Bool, parameters: Design.LayoutParameters, +node: Source.Node, layers: +List<View.Layer>, base: +List<Design.Node>, overlays: +List<Design.Node>, anchors: +List<Anchor>, docked: +List<Source.Node>, floating: +List<Source.Node>) -> OverlayParts:
  match role details_beside:
    case UI.Details{} True{}:
      dock_overlay(parameters, node, docked, floating)
    case _ _:
      float_overlay(role, parameters, node, layers, base, overlays, anchors, docked, floating)

def overlay_layout(+role: UI.Role, +details_beside: Bool, +placement: View.NavigationPlacement, parameters: Design.LayoutParameters, +node: Source.Node, layers: +List<View.Layer>, base: +List<Design.Node>, overlays: +List<Design.Node>, anchors: +List<Anchor>, docked: +List<Source.Node>, floating: +List<Source.Node>) -> OverlayParts:
  match role placement:
    case UI.Navigation{} View.ModalNavigation{}:
      Design.LayoutParameters{navigation_width, main_minimum_width, details_width, reading_width, overview_width, toolbar_height, input_minimum_height, input_maximum_height, line_height, creation_height, lane_width} = parameters
      OverlayParts{docked, resize(node, Model.ExactSize{navigation_width}, Model.StretchSize{}, Model.ScrollVertically{}, Spatial.Stretch{}, Spatial.AlignedLayer{Enclosure.Insets{0n, 0n}, Spatial.Leading{}, Spatial.Leading{}}) <> floating}
    case _ _:
      standard_overlay_layout(role, details_beside, parameters, node, layers, base, overlays, anchors, docked, floating)

def overlay_capacity(+role: UI.Role, capacity: View.Capacity, placement: View.NavigationPlacement, parameters: Design.LayoutParameters, +node: Source.Node, layers: +List<View.Layer>, base: +List<Design.Node>, overlays: +List<Design.Node>, anchors: +List<Anchor>, docked: +List<Source.Node>, floating: +List<Source.Node>) -> OverlayParts:
  View.Capacity{navigation_beside, details_beside} = capacity
  overlay_layout(role, details_beside, placement, parameters, node, layers, base, overlays, anchors, docked, floating)

def split_overlay_node(+node: Source.Node, +role: UI.Role, capacity: View.Capacity, placement: View.NavigationPlacement, parameters: Design.LayoutParameters, layers: +List<View.Layer>, base: +List<Design.Node>, overlays: +List<Design.Node>, anchors: +List<Anchor>, parts: OverlayParts) -> OverlayParts:
  OverlayParts{docked, floating} = parts
  overlay_capacity(role, capacity, placement, parameters, node, layers, base, overlays, anchors, docked, floating)

def split_overlays(+values: +List<Source.Node>, +capacity: View.Capacity, +placement: View.NavigationPlacement, +parameters: Design.LayoutParameters, +layers: +List<View.Layer>, +base: +List<Design.Node>, +overlays: +List<Design.Node>, +anchors: +List<Anchor>) -> OverlayParts:
  match values:
    case Nil{}: OverlayParts{Nil{}, Nil{}}
    case Con{+node, rest}:
      split_overlay_node(node, base_role(Source.key_of(node), overlays), capacity, placement, parameters, layers, base, overlays, anchors,
        split_overlays(rest, capacity, placement, parameters, layers, base, overlays, anchors))

def back_to_front(floating: +List<Source.Node>) -> +List<Source.Node>:
  List.reverse(&2, Source.Node, floating)

def assembled_parts(parts: OverlayParts, structure: Design.MainStructure, reading_width: Nat, base_nodes: +List<Source.Node>, base: +List<Design.Node>, placement: View.NavigationPlacement, parameters: Design.LayoutParameters, +font: Typography.Presentation, theme: Design.Theme) -> Result:
  OverlayParts{docked, floating} = parts
  Ready{Source.Box{UIIdentity.place("/application"), Source.Div{}, application_style(font), [Source.DataAttribute{"theme", theme_name(theme)}],
        body(split_base(base_nodes, base), structure, reading_width, placement, parameters, docked, font) <> back_to_front(floating)}}

def measure_width(measure: Composition.Measure, parameters: Design.LayoutParameters) -> Nat:
  match measure:
    case Composition.ReadingMeasure{}: Design.reading_maximum_width(parameters)
    case Composition.OverviewMeasure{}: Design.overview_maximum_width(parameters)
    case Composition.AvailableMeasure{}: 0n

def structure_reading_width(structure: Design.MainStructure, parameters: Design.LayoutParameters) -> Nat:
  Design.MainStructure{measure, heading, organization} = structure
  measure_width(measure, parameters)

def scene_structure(content: Core.Scene) -> Design.MainStructure:
  Core.Scene{surface, settings, transfers, preview, code, directory_picker} = content
  Design.main_structure(Composition.recipe(View.scene_page(surface)))

def scene_navigation_placement(content: Core.Scene) -> View.NavigationPlacement:
  Core.Scene{View.Scene{navigation, main, layers, View.Arrangement{placement}, attention}, settings, transfers, preview, code, directory_picker} = content
  placement

def assemble_surface(surface: Design.Surface, base_nodes: +List<Source.Node>, overlay_nodes: +List<Source.Node>, +capacity: View.Capacity, +parameters: Design.LayoutParameters, layers: +List<View.Layer>, anchors: +List<Anchor>, +font: Typography.Presentation) -> Result:
  Design.Surface{+content, theme, +base, +overlays, active_scope} = surface
  +structure = scene_structure(content)
  assembled_parts(split_overlays(overlay_nodes, capacity, scene_navigation_placement(content), parameters, layers, base, overlays, anchors), structure, structure_reading_width(structure, parameters), base_nodes, base, scene_navigation_placement(content), parameters, font, theme)

def assemble(base_result: Authored.Result, overlay_result: Authored.Result, +surface: Design.Surface, capacity: View.Capacity, parameters: Design.LayoutParameters, layers: +List<View.Layer>, anchors: +List<Anchor>, +font: Typography.Presentation) -> Result:
  match base_result overlay_result:
    case Authored.Rejected{key, problem} _: Rejected{key, problem}
    case _ Authored.Rejected{key, problem}: Rejected{key, problem}
    case Authored.Authored{base_nodes} Authored.Authored{overlay_nodes}:
      assemble_surface(surface, base_nodes, overlay_nodes, capacity, parameters, layers, anchors, font)

def source(+surface: Design.Surface, +parameters: Design.LayoutParameters, capacity: View.Capacity, layers: +List<View.Layer>, anchors: +List<Anchor>, font: Typography.Presentation) -> Result:
  assemble(Authored.base(surface, parameters), Authored.overlays(surface, parameters), surface, capacity, parameters, layers, anchors, font)
