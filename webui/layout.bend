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

def toolbar_height(+parameters: Design.LayoutParameters) -> Nat:
  Design.LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = parameters
  toolbar

def navigation_width(+parameters: Design.LayoutParameters) -> Nat:
  Design.LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = parameters
  navigation

def minimum_main_width(+parameters: Design.LayoutParameters) -> Nat:
  Design.LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = parameters
  main

def details_width(+parameters: Design.LayoutParameters) -> Nat:
  Design.LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = parameters
  details



def reading_maximum_width(+parameters: Design.LayoutParameters) -> Nat:
  Design.LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = parameters
  reading

def overview_maximum_width(+parameters: Design.LayoutParameters) -> Nat:
  Design.LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = parameters
  overview



def input_minimum_height(+parameters: Design.LayoutParameters) -> Nat:
  Design.LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = parameters
  minimum

def input_maximum_height(+parameters: Design.LayoutParameters) -> Nat:
  Design.LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = parameters
  maximum

def input_line_height(+parameters: Design.LayoutParameters) -> Nat:
  Design.LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = parameters
  leading

def creation_balanced_minimum_height(+parameters: Design.LayoutParameters) -> Nat:
  Design.LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = parameters
  creation

def inline_gutter_for_width(narrow: Bool) -> Nat:
  match narrow:
    case True{}: 12n
    case False{}: 16n

def inline_gutter(+parameters: Design.LayoutParameters, width: Nat) -> Nat:
  inline_gutter_for_width(Nat.is_lt(width, minimum_main_width(parameters)))

def overlay_gutter_for_width(narrow: Bool) -> Nat:
  match narrow:
    case True{}: 8n
    case False{}: 16n

def overlay_gutter(+parameters: Design.LayoutParameters, viewport: Design.Viewport) -> Nat:
  Design.Viewport{width, height} = viewport
  overlay_gutter_for_width(Nat.is_lt(width, minimum_main_width(parameters)))

def viewport_width(viewport: Design.Viewport) -> Nat:
  ViewportSpace.width(viewport)

def viewport_height(viewport: Design.Viewport) -> Nat:
  Design.Viewport{+width, height} = viewport
  height



def capacity(+parameters: Design.LayoutParameters, viewport: Design.Viewport, intent: E.NavigationIntent) -> V.Capacity:
  ViewportSpace.capacity(viewport, parameters, intent)

def shell(+parameters: Design.LayoutParameters, viewport: Design.Viewport, navigation: V.NavigationPlacement, details: Bool) -> ViewportSpace.Result:
  ViewportSpace.shell(viewport, parameters, navigation, details)

def settings_in_navigation(+parameters: Design.LayoutParameters, box: Design.Box) -> Design.Box:
  Design.Box{left, top, +width, +height} = box
  +size = Nat.min(32n, Nat.min(width, height))
  Design.Box{Nat.add(left, Nat.min(16n, Nat.sub(width, size))),
    Nat.add(top, Nat.min(Nat.sub(height, 48n), Nat.sub(height, size))), size, size}

def settings_in_heading(+parameters: Design.LayoutParameters, box: Design.Box) -> Design.Box:
  Design.Box{left, top, +width, +height} = box
  +size = Nat.min(32n, Nat.min(width, height))
  Design.Box{Nat.add(left, Nat.min(Nat.sub(width, 48n), Nat.sub(width, size))),
    Nat.add(top, Nat.min(7n, Nat.sub(height, size))), size, size}

def navigation_toggle_bounds(+parameters: Design.LayoutParameters, shell: Design.Shell) -> Design.Box:
  Design.Shell{navigation, Design.Box{left, top, +width, +height}, details} = shell
  +size = Nat.min(32n, Nat.min(width, height))
  Design.Box{Nat.add(left, Nat.min(8n, Nat.sub(width, size))),
    Nat.add(top, Nat.min(7n, Nat.sub(height, size))), size, size}

def settings_bounds(+parameters: Design.LayoutParameters, navigation: Design.Navigation, main: Design.Box) -> Design.Box:
  match navigation:
    case Design.BesideNavigation{box}: settings_in_navigation(parameters, box)
    case Design.OverlayNavigation{box}: settings_in_navigation(parameters, box)
    case Design.HiddenNavigation{}: settings_in_heading(parameters, main)

def header_height(+parameters: Design.LayoutParameters, main: Design.Box) -> Nat:
  Design.Box{+left, +top, +width, height} = main
  Nat.min(toolbar_height(parameters), height)

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
    case Composition.ReadingMeasure{}: centered_band(parameters, box, reading_maximum_width(parameters))
    case Composition.OverviewMeasure{}: centered_band(parameters, box, overview_maximum_width(parameters))
    case Composition.AvailableMeasure{}: centered_band(parameters, box, box_width(box))

def composer_content_inset() -> Nat:
  Appearance.face_padding(Controls.TextFace{""})

def input_metrics(+parameters: Design.LayoutParameters, canvas: Design.Box) -> Design.InputMetrics:
  Design.Box{+left, +top, +width, height} = canvas
  # The remaining line and spacing values follow the imported Desktop component tokens.
  +maximum = Nat.max(input_minimum_height(parameters), Nat.min(input_maximum_height(parameters), Nat.div(height, 3n)))
  Design.InputMetrics{input_minimum_height(parameters), maximum, input_line_height(parameters), composer_content_inset(), 4n, 8n}

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
  Nat.min(Nat.div(reading_maximum_width(parameters), 2n), Nat.max(0n, Nat.sub(width, Nat.mul(2n, gutter))))

def creation_flow_choice(compact: Bool) -> Design.CreationFlow:
  match compact:
    case True{}: Design.Compact{}
    case False{}: Design.Balanced{}

def creation_flow_for_height(+parameters: Design.LayoutParameters, height: Nat) -> Design.CreationFlow:
  creation_flow_choice(Nat.is_lt(height, creation_balanced_minimum_height(parameters)))

def creation_flow(+parameters: Design.LayoutParameters, canvas: Design.Box) -> Design.CreationFlow:
  creation_flow_for_height(parameters, box_height(canvas))

def creation_block_margin(flow: Design.CreationFlow) -> Design.BlockMargin:
  match flow:
    case Design.Balanced{}: Design.AutomaticMargin{}
    case Design.Compact{}: Design.NoMargin{}

def creation_arrangement(flow: Design.CreationFlow) -> Design.CreationArrangement:
  Design.CreationArrangement{24n, 24n, 16n, Design.Centered{}, creation_block_margin(flow)}

def main_frame(+parameters: Design.LayoutParameters, +recipe: Composition.Recipe, +main: Design.Box) -> Design.MainFrame:
  match recipe:
    case Composition.Recipe{measure, page_heading, Composition.CenteredCreation{}, composer, decisions, latest}:
      Design.CreationFrame{heading_box(parameters, main), main, measure_band(parameters, measure, main), centered_input(parameters, composer, main), creation_flow(parameters, main)}
    case Composition.Recipe{measure, page_heading, Composition.ChronologicalReading{}, composer, decisions, latest}:
      heading = heading_box(parameters, main)
      +canvas = body_box(parameters, main)
      +reading = measure_band(parameters, measure, canvas)
      Design.ConversationFrame{heading, canvas, reading,
        conversation_dock(parameters, recipe_dock(recipe), canvas, reading, composer)}
    case Composition.Recipe{measure, page_heading, Composition.ProjectSections{}, composer, decisions, latest}:
      +canvas = main
      Design.OverviewFrame{canvas, measure_band(parameters, measure, canvas), Composition.ProjectSections{}}
    case Composition.Recipe{measure, page_heading, Composition.ProjectRows{}, composer, decisions, latest}:
      +canvas = main
      Design.OverviewFrame{canvas, measure_band(parameters, measure, canvas), Composition.ProjectRows{}}
    case Composition.Recipe{measure, page_heading, Composition.AgentRows{}, composer, decisions, latest}:
      +canvas = main
      Design.OverviewFrame{canvas, measure_band(parameters, measure, canvas), Composition.AgentRows{}}
    case Composition.Recipe{measure, page_heading, Composition.StageColumns{}, composer, decisions, latest}:
      +canvas = main
      Design.BoardFrame{canvas, board_column_width(parameters, canvas), Enclosure.separation(Enclosure.BoardColumns{}), 16n}
    case Composition.Recipe{measure, page_heading, Composition.UnavailableNotice{}, composer, decisions, latest}:
      Design.UnavailableFrame{heading_box(parameters, main), body_box(parameters, main), measure_band(parameters, measure, body_box(parameters, main))}

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
    case None{}: centered_dialog(parameters, viewport, reading_maximum_width(parameters))

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
    case UI.Dialog{}: centered_dialog(parameters, viewport, reading_maximum_width(parameters))
    case UI.Menu{}: menu_overlay(parameters, viewport, key, layers, surface)
    case UI.Details{}: details_overlay(parameters, viewport, details)
    case _: centered_dialog(parameters, viewport, reading_maximum_width(parameters))

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
    projected_overlays(parameters, viewport, overlays, layers, surface, shell, navigation), parameters}

def requested_details(+parameters: Design.LayoutParameters, +viewport: Design.Viewport,
  navigation: V.NavigationPlacement, overlays: +List<UI.Node>) -> Bool:
  actual_details(overlays) && ViewportSpace.packed(Space.pack(~ViewportSpace.ShellPart,
    ViewportSpace.regular_slots(parameters, navigation, True{}), 0n, viewport_width(viewport)))

type Outcome is Data:
  LayoutReady{layout: Design.Layout}
  LayoutUnsupported{required: Nat, available: Nat}

def outcome_with_shell(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  overlays: +List<UI.Node>, navigation: V.NavigationPlacement, page: Composition.Page, layers: +List<V.Layer>,
  result: ViewportSpace.Result) -> Outcome:
  match result:
    case ViewportSpace.Allocated{shell}:
      LayoutReady{layout_with_shell(parameters, viewport, surface, overlays, shell, navigation, page, layers)}
    case ViewportSpace.Unsupported{required, available}: LayoutUnsupported{required, available}

def present(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface) -> Outcome:
  UI.Surface{content, base, +overlays, active_scope} = surface
  Core.Scene{+view, settings, transfers, preview, code, directory_picker} = content
  V.Scene{world_navigation, world_main, layers, arrangement, attention} = view
  V.Arrangement{+navigation} = arrangement
  page = V.scene_page(view)
  requested_side_pane = requested_details(parameters, viewport, navigation, overlays)
  outcome_with_shell(parameters, viewport, surface, overlays, navigation, page, layers,
    shell(parameters, viewport, navigation, requested_side_pane))
