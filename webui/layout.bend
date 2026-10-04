import Base
import ./enclosure.bend as Enclosure
import ../core/SYSTEM.bend as Core
import ../core/ui-world.bend as V
import ../core/interface.bend as UI
import ../core/composition.bend as Composition
import ./design.bend as Design
import ./appearance.bend as Appearance
import ./controls.bend as Controls
import ./viewport-space.bend as ViewportSpace
import ./space.bend as Space
import ../core/user-experience.bend as E
import ../core/user-input.bend as User





type Outcome is Data:
  LayoutReady{layout: Design.Layout}
  LayoutUnsupported{required: Nat, available: Nat}

type ControlItem is Data:
  FixedControl{key: String, geometry: Controls.Geometry}
  ControlSpacer{}

type ControlAllocation is Data:
  ControlsReady{controls: +List<Design.ControlPlacement>}
  ControlsUnsupported{required: Nat, available: Nat}

def inline_gutter_for_width(narrow: Bool) -> Nat:
  match narrow:
    case True{}: 12n
    case False{}: 16n

def inline_gutter(+parameters: Design.LayoutParameters, width: Nat) -> Nat:
  inline_gutter_for_width(Nat.is_lt(width, Design.main_minimum_width(parameters)))

def overlay_gutter_for_width(narrow: Bool) -> Nat:
  match narrow:
    case True{}: 8n
    case False{}: 16n

def overlay_gutter(+parameters: Design.LayoutParameters, viewport: Design.Viewport) -> Nat:
  Design.Viewport{width, height} = viewport
  overlay_gutter_for_width(Nat.is_lt(width, Design.main_minimum_width(parameters)))

def viewport_width(viewport: Design.Viewport) -> Nat:
  ViewportSpace.width(viewport)



def capacity(+parameters: Design.LayoutParameters, viewport: Design.Viewport, intent: E.NavigationIntent) -> V.Capacity:
  ViewportSpace.capacity(viewport, parameters, intent)

def shell(+parameters: Design.LayoutParameters, viewport: Design.Viewport, navigation: V.NavigationPlacement, details: Bool) -> ViewportSpace.Result:
  ViewportSpace.shell(viewport, parameters, navigation, details)

def header_height(+parameters: Design.LayoutParameters, main: Design.Box) -> Nat:
  Design.Box{+left, +top, +width, height} = main
  Nat.min(Design.toolbar_height(parameters), height)

def heading_box(+parameters: Design.LayoutParameters, +main: Design.Box) -> Design.Box:
  Design.Box{left, top, width, height} = main
  Design.Box{left, top, width, header_height(parameters, main)}

def body_box(+parameters: Design.LayoutParameters, +main: Design.Box) -> Design.Box:
  Design.Box{left, top, width, height} = main
  +header = header_height(parameters, main)
  Design.Box{left, Nat.add(top, header), width, Nat.max(0n, Nat.sub(height, header))}

def centered_band(+parameters: Design.LayoutParameters, box: Design.Box, maximum: Nat) -> Design.Band:
  Design.Box{left, +top, +width, +height} = box
  inset = Nat.min(inline_gutter(parameters, width), Nat.div(width, 2n))
  usable = Nat.max(0n, Nat.sub(width, Nat.mul(2n, inset)))
  +lane_width = Nat.min(maximum, usable)
  Design.Band{Nat.add(left, Nat.div(Nat.sub(width, lane_width), 2n)), lane_width}

def anchor_for_node(found: Maybe<&2, UI.Node>) -> Maybe<&2, String>:
  match found:
    case None{}: None{}
    case Some{UI.Node{key, semantic, label, role, meaning, children}}: Some{key}

def exact_anchor_in_tree(requested: String, nodes: +List<UI.Node>) -> Maybe<&2, String>:
  anchor_for_node(UI.find_node(nodes, requested))

def prefer_anchor(found: Maybe<&2, String>, fallback: Maybe<&2, String>) -> Maybe<&2, String>:
  match found:
    case Some{key}: Some{key}
    case None{}: fallback

def semantic_match(matches: Bool, key: String, fallback: Maybe<&2, String>) -> Maybe<&2, String>:
  match matches:
    case True{}: Some{key}
    case False{}: fallback

def semantic_anchor_in_tree(+requested: String, +nodes: +List<UI.Node>) -> Maybe<&2, String>:
  match nodes:
    case Nil{}: None{}
    case Con{UI.Node{key, semantic, label, role, meaning, +children}, rest}:
      semantic_match(String.eq(semantic, requested), key,
        prefer_anchor(semantic_anchor_in_tree(requested, children),
          semantic_anchor_in_tree(requested, rest)))

def choose_surface_anchor(exact_base: Maybe<&2, String>, exact_overlays: Maybe<&2, String>,
  semantic_base: Maybe<&2, String>, semantic_overlays: Maybe<&2, String>) -> Maybe<&2, String>:
  prefer_anchor(exact_base,
    prefer_anchor(exact_overlays,
      prefer_anchor(semantic_base, semantic_overlays)))

def anchor_in_trees(+base: +List<UI.Node>, +overlays: +List<UI.Node>, +requested: String) -> Maybe<&2, String>:
  choose_surface_anchor(exact_anchor_in_tree(requested, base),
    exact_anchor_in_tree(requested, overlays),
    semantic_anchor_in_tree(requested, base), semantic_anchor_in_tree(requested, overlays))

def anchor(surface: UI.Surface, requested: String) -> Maybe<&2, String>:
  UI.Surface{content, +base, +overlays, active_scope} = surface
  anchor_in_trees(base, overlays, requested)

def box_width(box: Design.Box) -> Nat:
  Design.Box{+left, +top, width, +height} = box
  width

def box_height(box: Design.Box) -> Nat:
  Design.Box{+left, +top, +width, height} = box
  height

def measure_band(+parameters: Design.LayoutParameters, selected_measure: Composition.Measure, +box: Design.Box) -> Design.Band:
  match selected_measure:
    case Composition.ReadingMeasure{}: centered_band(parameters, box, Design.reading_maximum_width(parameters))
    case Composition.OverviewMeasure{}: centered_band(parameters, box, Design.overview_maximum_width(parameters))
    case Composition.AvailableMeasure{}: centered_band(parameters, box, box_width(box))

def composer_content_inset() -> Nat:
  Appearance.face_padding(Controls.TextFace{""})

def input_metrics(+parameters: Design.LayoutParameters, canvas: Design.Box) -> Design.InputMetrics:
  Design.Box{+left, +top, +width, height} = canvas
  # The remaining line and spacing values follow the imported Desktop component tokens.
  +maximum = Nat.max(Design.input_minimum_height(parameters), Nat.min(Design.input_maximum_height(parameters), Nat.div(height, 3n)))
  Design.InputMetrics{Design.input_minimum_height(parameters), maximum, Design.input_line_height(parameters), composer_content_inset(), 4n, 8n}

def centered_input(+parameters: Design.LayoutParameters, composer: Composition.Composer, canvas: Design.Box) -> Maybe<&2, Design.InputMetrics>:
  match composer:
    case Composition.CenteredInput{}: Some{input_metrics(parameters, canvas)}
    case _: None{}

def bottom_input(+parameters: Design.LayoutParameters, composer: Composition.Composer, canvas: Design.Box) -> Maybe<&2, Design.InputMetrics>:
  match composer:
    case Composition.BottomInput{}: Some{input_metrics(parameters, canvas)}
    case _: None{}

def projected_dock_region(region: Composition.Region) -> Maybe<&2, Design.DockRegion>:
  match region:
    case Composition.LatestAction{}: Some{Design.LatestControl{}}
    case Composition.ApprovalDecisions{}: Some{Design.PendingApprovals{}}
    case Composition.ComposerInput{}: Some{Design.MessageInput{}}
    case _: None{}

def include_dock_region(found: Maybe<&2, Design.DockRegion>, rest: +List<Design.DockRegion>) -> +List<Design.DockRegion>:
  match found:
    case None{}: rest
    case Some{region}: region <> rest

def dock_regions(regions: +List<Composition.Region>) -> +List<Design.DockRegion>:
  match regions:
    case Nil{}: Nil{}
    case Con{region, rest}: include_dock_region(projected_dock_region(region), dock_regions(rest))

def dock_maximum_height(canvas: Design.Box) -> Nat:
  Design.Box{+left, +top, +width, height} = canvas
  Nat.min(Nat.div(height, 2n), 400n)

def measured_dock(+parameters: Design.LayoutParameters, +regions: +List<Design.DockRegion>, +canvas: Design.Box, reading: Design.Band,
  composer: Composition.Composer) -> Maybe<&2, Design.Dock>:
  match regions:
    case Nil{}: None{}
    case Con{first, rest}:
      Some{Design.Dock{reading, 8n, dock_maximum_height(canvas), regions,
        bottom_input(parameters, composer, canvas), Design.MeasuredDock{}}}

def conversation_dock(+parameters: Design.LayoutParameters, regions: +List<Composition.Region>, canvas: Design.Box, reading: Design.Band,
  composer: Composition.Composer) -> Maybe<&2, Design.Dock>:
  measured_dock(parameters, dock_regions(regions), canvas, reading, composer)

def structure_dock(structure: Composition.Structure) -> +List<Composition.Region>:
  Composition.Structure{heading, body, dock} = structure
  dock

def recipe_dock(recipe: Composition.Recipe) -> +List<Composition.Region>:
  structure_dock(Composition.structure(recipe))

def board_column_width(+parameters: Design.LayoutParameters, canvas: Design.Box) -> Nat:
  Design.Box{+left, +top, +width, +height} = canvas
  +gutter = inline_gutter(parameters, width)
  Nat.min(Nat.div(Design.reading_maximum_width(parameters), 2n), Nat.max(0n, Nat.sub(width, Nat.mul(2n, gutter))))

def creation_flow_choice(compact: Bool) -> Design.CreationFlow:
  match compact:
    case True{}: Design.Compact{}
    case False{}: Design.Balanced{}

def creation_flow_for_height(+parameters: Design.LayoutParameters, height: Nat) -> Design.CreationFlow:
  creation_flow_choice(Nat.is_lt(height, Design.creation_balanced_minimum_height(parameters)))

def creation_flow(+parameters: Design.LayoutParameters, canvas: Design.Box) -> Design.CreationFlow:
  creation_flow_for_height(parameters, box_height(canvas))

def creation_block_margin(flow: Design.CreationFlow) -> Design.BlockMargin:
  match flow:
    case Design.Balanced{}: Design.AutomaticMargin{}
    case Design.Compact{}: Design.NoMargin{}

def creation_arrangement(flow: Design.CreationFlow) -> Design.CreationArrangement:
  Design.CreationArrangement{24n, 24n, 16n, Design.Centered{}, creation_block_margin(flow)}

def main_frame_structure(structure: Design.MainStructure, +parameters: Design.LayoutParameters, +recipe: Composition.Recipe, +main: Design.Box) -> Design.MainFrame:
  match structure recipe:
    case Design.CreationStructure{} Composition.Recipe{measure, page_heading, body, composer, decisions, latest}:
      Design.CreationFrame{heading_box(parameters, main), main, measure_band(parameters, measure, main), centered_input(parameters, composer, main), creation_flow(parameters, main)}
    case Design.ConversationStructure{} Composition.Recipe{measure, page_heading, body, composer, decisions, latest}:
      heading = heading_box(parameters, main)
      +canvas = body_box(parameters, main)
      +reading = measure_band(parameters, measure, canvas)
      Design.ConversationFrame{heading, canvas, reading,
        conversation_dock(parameters, recipe_dock(recipe), canvas, reading, composer)}
    case Design.OverviewStructure{organization} Composition.Recipe{measure, page_heading, body, composer, decisions, latest}:
      +canvas = main
      Design.OverviewFrame{canvas, measure_band(parameters, measure, canvas), organization}
    case Design.BoardStructure{} Composition.Recipe{measure, page_heading, body, composer, decisions, latest}:
      +canvas = main
      Design.BoardFrame{canvas, board_column_width(parameters, canvas), Enclosure.separation(Enclosure.BoardColumns{}), 16n}
    case Design.UnavailableStructure{} Composition.Recipe{measure, page_heading, body, composer, decisions, latest}:
      Design.UnavailableFrame{heading_box(parameters, main), body_box(parameters, main), measure_band(parameters, measure, body_box(parameters, main))}

def main_frame(+parameters: Design.LayoutParameters, +recipe: Composition.Recipe, +main: Design.Box) -> Design.MainFrame:
  main_frame_structure(Design.main_structure(recipe), parameters, recipe, main)

def inset_box(+parameters: Design.LayoutParameters, +viewport: Design.Viewport) -> Design.Box:
  Design.Viewport{+width, +height} = viewport
  +gutter = overlay_gutter(parameters, viewport)
  +left = Nat.min(gutter, Nat.div(width, 2n))
  +top = Nat.min(gutter, Nat.div(height, 2n))
  Design.Box{left, top, Nat.max(0n, Nat.sub(width, Nat.mul(2n, left))),
    Nat.max(0n, Nat.sub(height, Nat.mul(2n, top)))}

def centered_dialog(+parameters: Design.LayoutParameters, viewport: Design.Viewport, maximum: Nat) -> Design.OverlayPlacement:
  +available = inset_box(parameters, viewport)
  Design.CenteredDialog{available, Nat.min(maximum, box_width(available))}

def details_overlay(+parameters: Design.LayoutParameters, viewport: Design.Viewport, side_pane: Maybe<&2, Design.Box>) -> Design.OverlayPlacement:
  match side_pane:
    case Some{bounds}: Design.TrailingPane{bounds}
    case None{}: centered_dialog(parameters, viewport, Design.reading_maximum_width(parameters))

def choose_layer(matches: Bool, layer: V.Layer, fallback: Maybe<&2, V.Layer>) -> Maybe<&2, V.Layer>:
  match matches:
    case True{}: Some{layer}
    case False{}: fallback

def find_layer(+key: String, layers: +List<V.Layer>) -> Maybe<&2, V.Layer>:
  match layers:
    case Nil{}: None{}
    case Con{+layer, rest}:
      V.Layer{+kind, +content, initial_attention, +return_attention, +close} = layer
      choose_layer(String.eq(UI.layer_key(initial_attention), key), layer,
        find_layer(key, rest))

def anchored_menu_placement(+parameters: Design.LayoutParameters, viewport: Design.Viewport, origin: Maybe<&2, String>) -> Design.OverlayPlacement:
  match origin:
    case None{}: centered_dialog(parameters, viewport, 320n)
    case Some{anchor}:
      +available = inset_box(parameters, viewport)
      Design.AnchoredPopover{anchor, available, Nat.min(320n, box_width(available)),
        Nat.min(400n, box_height(available)), 4n}

def menu_layer_placement(+parameters: Design.LayoutParameters, viewport: Design.Viewport, kind: V.LayerKind, return_attention: String,
  surface: UI.Surface) -> Design.OverlayPlacement:
  match kind:
    case V.AnchoredMenu{}: anchored_menu_placement(parameters, viewport, anchor(surface, return_attention))
    case _: centered_dialog(parameters, viewport, 320n)

def menu_for_layer(+parameters: Design.LayoutParameters, viewport: Design.Viewport, found: Maybe<&2, V.Layer>,
  surface: UI.Surface) -> Design.OverlayPlacement:
  match found:
    case None{}: centered_dialog(parameters, viewport, 320n)
    case Some{V.Layer{kind, content, initial_attention, return_attention, close}}:
      menu_layer_placement(parameters, viewport, kind, return_attention, surface)

def menu_overlay(+parameters: Design.LayoutParameters, viewport: Design.Viewport, key: String, +layers: +List<V.Layer>,
  +surface: UI.Surface) -> Design.OverlayPlacement:
  menu_for_layer(parameters, viewport, find_layer(key, layers), surface)

def role_overlay(+parameters: Design.LayoutParameters, viewport: Design.Viewport, role: UI.Role, key: String, +layers: +List<V.Layer>,
  +surface: UI.Surface, details: Maybe<&2, Design.Box>) -> Design.OverlayPlacement:
  match role:
    case UI.Dialog{}: centered_dialog(parameters, viewport, Design.reading_maximum_width(parameters))
    case UI.Menu{}: menu_overlay(parameters, viewport, key, layers, surface)
    case UI.Details{}: details_overlay(parameters, viewport, details)
    case _: centered_dialog(parameters, viewport, Design.reading_maximum_width(parameters))

def overlay_navigation_bounds(navigation: Design.Navigation) -> Maybe<&2, Design.OverlayPlacement>:
  match navigation:
    case Design.OverlayNavigation{bounds}: Some{Design.NavigationDrawer{bounds}}
    case _: None{}

def navigation_overlay(placement: V.NavigationPlacement, shell_navigation: Design.Navigation) -> Maybe<&2, Design.OverlayPlacement>:
  match placement:
    case V.ModalNavigation{}: overlay_navigation_bounds(shell_navigation)
    case _: None{}

def modal_navigation_or_role(+parameters: Design.LayoutParameters, semantic_is_navigation: Bool, drawer: Design.OverlayPlacement,
  viewport: Design.Viewport, role: UI.Role, key: String, +layers: +List<V.Layer>,
  +surface: UI.Surface, details: Maybe<&2, Design.Box>) -> Design.OverlayPlacement:
  match semantic_is_navigation:
    case True{}: drawer
    case False{}: role_overlay(parameters, viewport, role, key, layers, surface, details)

def overlay_with_drawer(+parameters: Design.LayoutParameters, drawer: Maybe<&2, Design.OverlayPlacement>, semantic: String,
  viewport: Design.Viewport, role: UI.Role, key: String, +layers: +List<V.Layer>,
  +surface: UI.Surface, details: Maybe<&2, Design.Box>) -> Design.OverlayPlacement:
  match drawer:
    case Some{placement}:
      modal_navigation_or_role(parameters, String.eq(semantic, "navigation"), placement,
        viewport, role, key, layers, surface, details)
    case None{}: role_overlay(parameters, viewport, role, key, layers, surface, details)

def overlay_placement_with_drawer(+parameters: Design.LayoutParameters, viewport: Design.Viewport, node: UI.Node, +layers: +List<V.Layer>,
  +surface: UI.Surface, +shell: Design.Shell,
  drawer: Maybe<&2, Design.OverlayPlacement>) -> Design.OverlayPlacement:
  UI.Node{key, semantic, +label, role, +meaning, +children} = node
  Design.Shell{shell_navigation, +main, details} = shell
  overlay_with_drawer(parameters, drawer, semantic, viewport, role, key, layers, surface, details)

def overlay_placement(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, node: UI.Node, +layers: +List<V.Layer>,
  +surface: UI.Surface, +shell: Design.Shell, +navigation: V.NavigationPlacement) -> Design.OverlayPlacement:
  Design.Shell{shell_navigation, main, details} = shell
  overlay_placement_with_drawer(parameters, viewport, node, layers, surface, shell,
    navigation_overlay(navigation, shell_navigation))

def projected_overlays(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +overlays: +List<UI.Node>, +layers: +List<V.Layer>,
  +surface: UI.Surface, +shell: Design.Shell, +navigation: V.NavigationPlacement) -> +List<Design.Overlay>:
  match overlays:
    case Nil{}: Nil{}
    case Con{UI.Node{key, semantic, label, role, meaning, children}, rest}:
      Con{Design.Overlay{key, Nat.add(100n, List.length(&2, UI.Node, rest)),
        overlay_placement(parameters, viewport, UI.Node{key, semantic, label, role, meaning, children}, layers,
          surface, shell, navigation)},
        projected_overlays(parameters, viewport, rest, layers, surface, shell, navigation)}

def actual_details(+overlays: +List<UI.Node>) -> Bool:
  match overlays:
    case Nil{}: False{}
    case Con{UI.Node{+key, +semantic, +label, role, +meaning, +children}, rest}:
      match role:
        case UI.Details{}: True{}
        case _: actual_details(rest)

def layout_with_shell(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface, +overlays: +List<UI.Node>, +shell: Design.Shell,
  navigation: V.NavigationPlacement, +page: Composition.Page, +layers: +List<V.Layer>) -> Design.Layout:
  Design.Shell{shell_navigation, main, +details} = shell
  +recipe = Composition.recipe(page)
  Design.Layout{viewport, shell, main_frame(parameters, recipe, main),
    projected_overlays(parameters, viewport, overlays, layers, surface, shell, navigation), parameters, Nil{}}

def requested_details(+parameters: Design.LayoutParameters, +viewport: Design.Viewport,
  navigation: V.NavigationPlacement, overlays: +List<UI.Node>) -> Bool:
  actual_details(overlays) && ViewportSpace.packed(Space.pack(~ViewportSpace.ShellPart,
    ViewportSpace.regular_slots(parameters, navigation, True{}), 0n, viewport_width(viewport)))

def navigation_control(meaning: UI.Meaning) -> Bool:
  match meaning:
    case UI.ComposerAction{subject, Core.ApplicationInput{E.UserInput{User.SetNavigation{expanded}}}, availability}: True{}
    case UI.Activate{Core.ApplicationInput{E.UserInput{User.SetNavigation{expanded}}}, availability}: True{}
    case _: False{}

def selected_control(selected: Bool, key: String, representation: Controls.Representation,
  rest: +List<ControlItem>) -> +List<ControlItem>:
  match selected representation:
    case True{} Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}:
      FixedControl{key, geometry} <> rest
    case _ _: rest

def leading_control(semantic: String, meaning: UI.Meaning) -> Bool:
  match semantic:
    case "settings/open": False{}
    case _: navigation_control(meaning)

def collect_control_kind(settings: Bool, key: String, semantic: String, meaning: UI.Meaning,
  representation: Controls.Representation, rest: +List<ControlItem>) -> +List<ControlItem>:
  match settings:
    case True{}: selected_control(String.eq(semantic, "settings/open"), key, representation, rest)
    case False{}: selected_control(leading_control(semantic, meaning), key, representation, rest)

def collect_controls(+nodes: +List<Design.Node>, +settings: Bool) -> +List<ControlItem>:
  match nodes:
    case Nil{}: Nil{}
    case Con{Design.Node{key, semantic, label, role, meaning, style, representation, children}, rest}:
      collect_control_kind(settings, key, semantic, meaning, representation, collect_controls(rest, settings))

def cross_minimum(items: +List<ControlItem>) -> Nat:
  match items:
    case Nil{}: 0n
    case Con{FixedControl{key, geometry}, rest}: Nat.max(Controls.geometry_minimum_height(geometry), cross_minimum(rest))
    case Con{ControlSpacer{}, rest}: cross_minimum(rest)

def control_inset(items: +List<ControlItem>) -> Nat:
  match items:
    case Nil{}: 0n
    case Con{FixedControl{key, Controls.Geometry{demand, icon, radius, leading}}, rest}:
      Nat.max(Nat.div(icon, 2n), control_inset(rest))
    case Con{ControlSpacer{}, rest}: control_inset(rest)

def adapt_parameters(parameters: Design.LayoutParameters, cross: Nat) -> Design.LayoutParameters:
  Design.LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = parameters
  Design.LayoutParameters{navigation, main, details, reading, overview, Nat.max(toolbar, cross), minimum, maximum, leading, creation}

def control_dimension(+geometry: Controls.Geometry) -> Space.Dimension:
  Space.Fit{Controls.geometry_minimum_width(geometry),
    Nat.sub(Controls.geometry_preferred_width(geometry), Controls.geometry_minimum_width(geometry)), 0n}

def control_slots(items: +List<ControlItem>, +clearance: Nat) -> +List<Space.Slot<ControlItem>>:
  match items:
    case Nil{}: Nil{}
    case Con{FixedControl{key, +geometry}, rest}:
      Space.Slot{FixedControl{key, geometry}, control_dimension(geometry)} <> control_slots(rest, clearance)
    case Con{ControlSpacer{}, rest}:
      Space.Slot{ControlSpacer{}, Space.Fill{clearance}} <> control_slots(rest, clearance)

def append_trailing(leading: +List<ControlItem>, trailing: +List<ControlItem>) -> +List<ControlItem>:
  match trailing:
    case Nil{}: leading
    case Con{head, rest}: List.append(&2, ControlItem, leading, ControlSpacer{} <> head <> rest)

def spacer_clearance(leading: +List<ControlItem>, inset: Nat) -> Nat:
  match leading:
    case Nil{}: 0n
    case Con{head, rest}: inset

def control_container(+leading: +List<ControlItem>, +trailing: +List<ControlItem>) -> Space.Container<ControlItem>:
  +items = append_trailing(leading, trailing)
  +inset = control_inset(items)
  Space.Container{inset, inset, 0n, control_slots(items, spacer_clearance(leading, inset))}

def control_height(+geometry: Controls.Geometry, band: Nat) -> Nat:
  Space.choose(Space.Fit{Controls.geometry_minimum_height(geometry),
    Nat.sub(Controls.geometry_preferred_height(geometry), Controls.geometry_minimum_height(geometry)), 0n}, band)

def control_placement(key: String, geometry: Controls.Geometry, offset: Nat, width: Nat,
  target: Design.Box, +band: Nat) -> Design.ControlPlacement:
  Design.Box{left, top, target_width, target_height} = target
  +height = control_height(geometry, band)
  Design.ControlPlacement{key, Design.Box{Nat.add(left, offset), Nat.add(top, Nat.div(Nat.sub(band, height), 2n)), width, height}}

def control_placements(placements: +List<Space.Placement<ControlItem>>, +target: Design.Box, +band: Nat) -> +List<Design.ControlPlacement>:
  match placements:
    case Nil{}: Nil{}
    case Con{Space.Placement{FixedControl{key, geometry}, offset, width}, rest}:
      control_placement(key, geometry, offset, width, target, band) <> control_placements(rest, target, band)
    case Con{Space.Placement{ControlSpacer{}, offset, width}, rest}: control_placements(rest, target, band)

def finish_controls(result: Space.Packing<ControlItem>, target: Design.Box, band: Nat) -> ControlAllocation:
  match result:
    case Space.Insufficient{required, available}: ControlsUnsupported{required, available}
    case Space.Packed{placements, unused}: ControlsReady{control_placements(placements, target, band)}

def allocate_control_band(fits: Bool, parameters: Design.LayoutParameters, +target: Design.Box,
  +leading: +List<ControlItem>, +trailing: +List<ControlItem>, cross: Nat) -> ControlAllocation:
  match fits:
    case False{}:
      Design.Box{left, top, width, height} = target
      ControlsUnsupported{cross, height}
    case True{}:
      Design.Box{left, top, width, +height} = target
      finish_controls(Space.pack_container(~ControlItem, control_container(leading, trailing), width),
        target, Nat.min(height, Nat.max(Design.toolbar_height(parameters), cross)))

def allocate_controls(+parameters: Design.LayoutParameters, +target: Design.Box,
  +leading: +List<ControlItem>, +trailing: +List<ControlItem>) -> ControlAllocation:
  Design.Box{left, top, width, height} = target
  +cross = Nat.max(cross_minimum(leading), cross_minimum(trailing))
  allocate_control_band(Nat.is_le(cross, height), parameters, target, leading, trailing, cross)

def shell_controls(+parameters: Design.LayoutParameters, shell: Design.Shell,
  +settings: +List<ControlItem>, +toggles: +List<ControlItem>) -> ControlAllocation:
  Design.Shell{navigation, +main, details} = shell
  match navigation:
    case Design.HiddenNavigation{}: allocate_controls(parameters, main, toggles, settings)
    case Design.BesideNavigation{box}: allocate_controls(parameters, box, Nil{}, settings)
    case Design.OverlayNavigation{box}: allocate_controls(parameters, box, Nil{}, settings)

def active_toggles(navigation: Design.Navigation, toggles: +List<ControlItem>) -> +List<ControlItem>:
  match navigation:
    case Design.HiddenNavigation{}: toggles
    case _: Nil{}

def layout_controls(result: ControlAllocation, layout: Design.Layout) -> Outcome:
  match result:
    case ControlsUnsupported{required, available}: LayoutUnsupported{required, available}
    case ControlsReady{controls}:
      Design.Layout{viewport, shell, main, overlays, parameters, previous} = layout
      LayoutReady{Design.Layout{viewport, shell, main, overlays, parameters, controls}}

def prepare_shell_controls(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  +overlays: +List<UI.Node>, +shell: Design.Shell, navigation: V.NavigationPlacement,
  +page: Composition.Page, +layers: +List<V.Layer>, +settings: +List<ControlItem>, +toggles: +List<ControlItem>) -> Outcome:
  Design.Shell{+shell_navigation, main, details} = shell
  +selected = active_toggles(shell_navigation, toggles)
  +adapted = adapt_parameters(parameters, Nat.max(cross_minimum(settings), cross_minimum(selected)))
  layout_controls(shell_controls(adapted, shell, settings, selected),
    layout_with_shell(adapted, viewport, surface, overlays, shell, navigation, page, layers))

def outcome_with_shell(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  overlays: +List<UI.Node>, navigation: V.NavigationPlacement, page: Composition.Page, layers: +List<V.Layer>,
  settings: +List<ControlItem>, toggles: +List<ControlItem>, result: ViewportSpace.Result) -> Outcome:
  match result:
    case ViewportSpace.Allocated{shell}:
      prepare_shell_controls(parameters, viewport, surface, overlays, shell, navigation, page, layers, settings, toggles)
    case ViewportSpace.Unsupported{required, available}: LayoutUnsupported{required, available}

def present_semantic(+parameters: Design.LayoutParameters, +viewport: Design.Viewport,
  +surface: UI.Surface, +actual_base: +List<Design.Node>) -> Outcome:
  UI.Surface{content, base, +overlays, active_scope} = surface
  Core.Scene{+view, settings, transfers, preview, code, directory_picker} = content
  V.Scene{world_navigation, world_main, layers, arrangement, attention} = view
  V.Arrangement{+navigation} = arrangement
  page = V.scene_page(view)
  requested_side_pane = requested_details(parameters, viewport, navigation, overlays)
  outcome_with_shell(parameters, viewport, surface, overlays, navigation, page, layers,
    collect_controls(actual_base, True{}), collect_controls(actual_base, False{}),
    shell(parameters, viewport, navigation, requested_side_pane))

def present_surface(parameters: Design.LayoutParameters, viewport: Design.Viewport, +prepared: Design.Surface) -> Outcome:
  Design.Surface{content, theme, actual_base, actual_overlays, active} = prepared
  present_semantic(parameters, viewport, Design.semantic_surface(prepared), actual_base)

def present(parameters: Design.LayoutParameters, viewport: Design.Viewport, presentation: Design.PreparedSurface) -> Outcome:
  Design.PreparedSurface{prepared, cached_base, cached_overlays} = presentation
  present_surface(parameters, viewport, prepared)
