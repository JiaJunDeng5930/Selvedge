import Base
import ../core/SYSTEM.bend as Core
import ../core/ui-world.bend as V
import ../core/interface.bend as UI
import ../core/composition.bend as Composition
import ./design.bend as Design

# Toolbar and reading measurements follow the imported Desktop source.
def toolbar_height() -> Nat:
  46n

# Desktop's sidebar preferred-width token defaults to 275px; the current adapter has no resize control.
def navigation_width() -> Nat:
  275n

# These allocations reserve room for Selvedge's supported content; they do not claim pixel identity with Desktop.
def minimum_main_width() -> Nat:
  480n

def details_width() -> Nat:
  360n

def details_minimum_width() -> Nat:
  Nat.add(Nat.add(navigation_width(), minimum_main_width()), details_width())

def reading_maximum_width() -> Nat:
  640n

# This width is an allocation for the supported project views.
def overview_maximum_width() -> Nat:
  960n

def narrow_threshold() -> Nat:
  768n

def inline_gutter_for_width(narrow: Bool) -> Nat:
  match narrow:
    case True{}: 12n
    case False{}: 16n

def inline_gutter(width: Nat) -> Nat:
  inline_gutter_for_width(Nat.is_lt(width, narrow_threshold()))

def overlay_gutter_for_width(narrow: Bool) -> Nat:
  match narrow:
    case True{}: 8n
    case False{}: 16n

def overlay_gutter(viewport: Design.Viewport) -> Nat:
  Design.Viewport{width, height} = viewport
  overlay_gutter_for_width(Nat.is_lt(width, narrow_threshold()))

def viewport_width(viewport: Design.Viewport) -> Nat:
  Design.Viewport{width, +height} = viewport
  width

def viewport_height(viewport: Design.Viewport) -> Nat:
  Design.Viewport{+width, height} = viewport
  height

def capacity_for_width(+width: Nat) -> V.Capacity:
  V.Capacity{
    Bool.not(Nat.is_lt(width, narrow_threshold())),
    Bool.not(Nat.is_lt(width, details_minimum_width()))}

def capacity(viewport: Design.Viewport) -> V.Capacity:
  capacity_for_width(viewport_width(viewport))

def navigation_bounds(viewport: Design.Viewport) -> Design.Box:
  Design.Viewport{width, height} = viewport
  Design.Box{0n, 0n, Nat.min(navigation_width(), width), height}

def navigation_width_for_width(viewport: Design.Viewport) -> Nat:
  Design.Viewport{width, +height} = viewport
  Nat.min(navigation_width(), width)

def consumed_navigation_width(viewport: Design.Viewport, navigation: V.NavigationPlacement) -> Nat:
  match navigation:
    case V.LeadingNavigation{}: navigation_width_for_width(viewport)
    case _: 0n

def available_details_width(+viewport: Design.Viewport, navigation: V.NavigationPlacement) -> Nat:
  Design.Viewport{width, height} = viewport
  Nat.min(details_width(), Nat.sub(width, consumed_navigation_width(viewport, navigation)))

def requested_details_width(viewport: Design.Viewport, navigation: V.NavigationPlacement, details: Bool) -> Nat:
  match details:
    case False{}: 0n
    case True{}: available_details_width(viewport, navigation)

def shell_navigation(viewport: Design.Viewport, navigation: V.NavigationPlacement) -> Design.Navigation:
  match navigation:
    case V.LeadingNavigation{}: Design.BesideNavigation{navigation_bounds(viewport)}
    case V.ModalNavigation{}: Design.OverlayNavigation{navigation_bounds(viewport)}
    case V.CollapsedNavigation{}: Design.HiddenNavigation{}

def side_pane_box(main: Design.Box, height: Nat, pane_width: Nat) -> Design.Box:
  Design.Box{left, +top, width, +main_height} = main
  Design.Box{Nat.add(left, width), 0n, pane_width, height}

def requested_side_pane(main: Design.Box, height: Nat, pane_width: Nat, details: Bool) -> Maybe<&2, Design.Box>:
  match details:
    case False{}: None{}
    case True{}: Some{side_pane_box(main, height, pane_width)}

def shell(+viewport: Design.Viewport, +navigation: V.NavigationPlacement, +details: Bool) -> Design.Shell:
  Design.Viewport{+width, +height} = viewport
  +nav_width = consumed_navigation_width(viewport, navigation)
  +pane_width = requested_details_width(viewport, navigation, details)
  main_width = Nat.max(0n, Nat.sub(Nat.sub(width, nav_width), pane_width))
  +main: Design.Box = Design.Box{nav_width, 0n, main_width, height}
  Design.Shell{shell_navigation(viewport, navigation), main,
    requested_side_pane(main, height, pane_width, details)}

# Clamp the shell control and its inset together for viewports smaller than the slot.
def settings_in_navigation(box: Design.Box) -> Design.Box:
  Design.Box{left, top, +width, +height} = box
  +size = Nat.min(32n, Nat.min(width, height))
  Design.Box{Nat.add(left, Nat.min(16n, Nat.sub(width, size))),
    Nat.add(top, Nat.min(Nat.sub(height, 48n), Nat.sub(height, size))), size, size}

def settings_in_heading(box: Design.Box) -> Design.Box:
  Design.Box{left, top, +width, +height} = box
  +size = Nat.min(32n, Nat.min(width, height))
  Design.Box{Nat.add(left, Nat.min(Nat.sub(width, 48n), Nat.sub(width, size))),
    Nat.add(top, Nat.min(7n, Nat.sub(height, size))), size, size}

def settings_bounds(navigation: Design.Navigation, main: Design.Box) -> Design.Box:
  match navigation:
    case Design.BesideNavigation{box}: settings_in_navigation(box)
    case Design.OverlayNavigation{box}: settings_in_navigation(box)
    case Design.HiddenNavigation{}: settings_in_heading(main)

def header_height(main: Design.Box) -> Nat:
  Design.Box{+left, +top, +width, height} = main
  Nat.min(toolbar_height(), height)

def heading_box(+main: Design.Box) -> Design.Box:
  Design.Box{left, top, width, height} = main
  Design.Box{left, top, width, header_height(main)}

def body_box(+main: Design.Box) -> Design.Box:
  Design.Box{left, top, width, height} = main
  +header = header_height(main)
  Design.Box{left, Nat.add(top, header), width, Nat.max(0n, Nat.sub(height, header))}

def centered_band(box: Design.Box, maximum: Nat) -> Design.Band:
  Design.Box{left, +top, +width, +height} = box
  inset = Nat.min(inline_gutter(width), Nat.div(width, 2n))
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

def measure_band(selected_measure: Composition.Measure, +box: Design.Box) -> Design.Band:
  match selected_measure:
    case Composition.ReadingMeasure{}: centered_band(box, reading_maximum_width())
    case Composition.OverviewMeasure{}: centered_band(box, overview_maximum_width())
    case Composition.AvailableMeasure{}: centered_band(box, box_width(box))

def input_metrics(canvas: Design.Box) -> Design.InputMetrics:
  Design.Box{+left, +top, +width, height} = canvas
  # The remaining line and spacing values follow the imported Desktop component tokens.
  +maximum = Nat.min(240n, Nat.div(height, 3n))
  Design.InputMetrics{Nat.min(44n, maximum), maximum, 20n, 12n, 4n, 8n}

def centered_input(composer: Composition.Composer, canvas: Design.Box) -> Maybe<&2, Design.InputMetrics>:
  match composer:
    case Composition.CenteredInput{}: Some{input_metrics(canvas)}
    case _: None{}

def bottom_input(composer: Composition.Composer, canvas: Design.Box) -> Maybe<&2, Design.InputMetrics>:
  match composer:
    case Composition.BottomInput{}: Some{input_metrics(canvas)}
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

def measured_dock(+regions: +List<Design.DockRegion>, +canvas: Design.Box, reading: Design.Band,
  composer: Composition.Composer) -> Maybe<&2, Design.Dock>:
  match regions:
    case Nil{}: None{}
    case Con{first, rest}:
      Some{Design.Dock{reading, 8n, dock_maximum_height(canvas), regions,
        bottom_input(composer, canvas), Design.MeasuredDock{}}}

def conversation_dock(regions: +List<Composition.Region>, canvas: Design.Box, reading: Design.Band,
  composer: Composition.Composer) -> Maybe<&2, Design.Dock>:
  measured_dock(dock_regions(regions), canvas, reading, composer)

def structure_dock(structure: Composition.Structure) -> +List<Composition.Region>:
  Composition.Structure{heading, body, dock} = structure
  dock

def recipe_dock(recipe: Composition.Recipe) -> +List<Composition.Region>:
  structure_dock(Composition.structure(recipe))

def board_column_width(canvas: Design.Box) -> Nat:
  Design.Box{+left, +top, +width, +height} = canvas
  +gutter = inline_gutter(width)
  Nat.min(300n, Nat.max(0n, Nat.sub(width, Nat.mul(2n, gutter))))

def main_frame(+recipe: Composition.Recipe, +main: Design.Box) -> Design.MainFrame:
  match recipe:
    case Composition.Recipe{measure, page_heading, Composition.CenteredCreation{}, composer, decisions, latest}:
      Design.CreationFrame{heading_box(main), body_box(main), measure_band(measure, body_box(main)), centered_input(composer, body_box(main))}
    case Composition.Recipe{measure, page_heading, Composition.ChronologicalReading{}, composer, decisions, latest}:
      heading = heading_box(main)
      +canvas = body_box(main)
      +reading = measure_band(measure, canvas)
      Design.ConversationFrame{heading, canvas, reading,
        conversation_dock(recipe_dock(recipe), canvas, reading, composer)}
    case Composition.Recipe{measure, page_heading, Composition.ProjectSections{}, composer, decisions, latest}:
      heading = heading_box(main)
      +canvas = body_box(main)
      Design.OverviewFrame{heading, canvas, measure_band(measure, canvas), Composition.ProjectSections{}}
    case Composition.Recipe{measure, page_heading, Composition.ProjectRows{}, composer, decisions, latest}:
      heading = heading_box(main)
      +canvas = body_box(main)
      Design.OverviewFrame{heading, canvas, measure_band(measure, canvas), Composition.ProjectRows{}}
    case Composition.Recipe{measure, page_heading, Composition.AgentRows{}, composer, decisions, latest}:
      heading = heading_box(main)
      +canvas = body_box(main)
      Design.OverviewFrame{heading, canvas, measure_band(measure, canvas), Composition.AgentRows{}}
    case Composition.Recipe{measure, page_heading, Composition.StageColumns{}, composer, decisions, latest}:
      heading = heading_box(main)
      +canvas = body_box(main)
      Design.BoardFrame{heading, canvas, board_column_width(canvas), 12n, inline_gutter(box_width(canvas))}
    case Composition.Recipe{measure, page_heading, Composition.UnavailableNotice{}, composer, decisions, latest}:
      Design.UnavailableFrame{heading_box(main), body_box(main), measure_band(measure, body_box(main))}

def inset_box(+viewport: Design.Viewport) -> Design.Box:
  Design.Viewport{+width, +height} = viewport
  +gutter = overlay_gutter(viewport)
  +left = Nat.min(gutter, Nat.div(width, 2n))
  +top = Nat.min(gutter, Nat.div(height, 2n))
  Design.Box{left, top, Nat.max(0n, Nat.sub(width, Nat.mul(2n, left))),
    Nat.max(0n, Nat.sub(height, Nat.mul(2n, top)))}

def centered_dialog(viewport: Design.Viewport, maximum: Nat) -> Design.OverlayPlacement:
  +available = inset_box(viewport)
  Design.CenteredDialog{available, Nat.min(maximum, box_width(available))}

def details_overlay(viewport: Design.Viewport, side_pane: Maybe<&2, Design.Box>) -> Design.OverlayPlacement:
  match side_pane:
    case Some{bounds}: Design.TrailingPane{bounds}
    case None{}: centered_dialog(viewport, 640n)

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

def anchored_menu_placement(viewport: Design.Viewport, origin: Maybe<&2, String>) -> Design.OverlayPlacement:
  match origin:
    case None{}: centered_dialog(viewport, 320n)
    case Some{anchor}:
      +available = inset_box(viewport)
      Design.AnchoredPopover{anchor, available, Nat.min(320n, box_width(available)),
        Nat.min(400n, box_height(available)), 4n}

def menu_layer_placement(viewport: Design.Viewport, kind: V.LayerKind, return_attention: String,
  surface: UI.Surface) -> Design.OverlayPlacement:
  match kind:
    case V.AnchoredMenu{}: anchored_menu_placement(viewport, anchor(surface, return_attention))
    case _: centered_dialog(viewport, 320n)

def menu_for_layer(viewport: Design.Viewport, found: Maybe<&2, V.Layer>,
  surface: UI.Surface) -> Design.OverlayPlacement:
  match found:
    case None{}: centered_dialog(viewport, 320n)
    case Some{V.Layer{kind, content, initial_attention, return_attention, close}}:
      menu_layer_placement(viewport, kind, return_attention, surface)

def menu_overlay(viewport: Design.Viewport, key: String, +layers: +List<V.Layer>,
  +surface: UI.Surface) -> Design.OverlayPlacement:
  menu_for_layer(viewport, find_layer(key, layers), surface)

def role_overlay(viewport: Design.Viewport, role: UI.Role, key: String, +layers: +List<V.Layer>,
  +surface: UI.Surface, details: Maybe<&2, Design.Box>) -> Design.OverlayPlacement:
  match role:
    case UI.Dialog{}: centered_dialog(viewport, 640n)
    case UI.Menu{}: menu_overlay(viewport, key, layers, surface)
    case UI.Details{}: details_overlay(viewport, details)
    case _: centered_dialog(viewport, 640n)

def overlay_navigation_bounds(navigation: Design.Navigation) -> Maybe<&2, Design.OverlayPlacement>:
  match navigation:
    case Design.OverlayNavigation{bounds}: Some{Design.NavigationDrawer{bounds}}
    case _: None{}

def navigation_overlay(placement: V.NavigationPlacement, shell_navigation: Design.Navigation) -> Maybe<&2, Design.OverlayPlacement>:
  match placement:
    case V.ModalNavigation{}: overlay_navigation_bounds(shell_navigation)
    case _: None{}

def modal_navigation_or_role(semantic_is_navigation: Bool, drawer: Design.OverlayPlacement,
  viewport: Design.Viewport, role: UI.Role, key: String, +layers: +List<V.Layer>,
  +surface: UI.Surface, details: Maybe<&2, Design.Box>) -> Design.OverlayPlacement:
  match semantic_is_navigation:
    case True{}: drawer
    case False{}: role_overlay(viewport, role, key, layers, surface, details)

def overlay_with_drawer(drawer: Maybe<&2, Design.OverlayPlacement>, semantic: String,
  viewport: Design.Viewport, role: UI.Role, key: String, +layers: +List<V.Layer>,
  +surface: UI.Surface, details: Maybe<&2, Design.Box>) -> Design.OverlayPlacement:
  match drawer:
    case Some{placement}:
      modal_navigation_or_role(String.eq(semantic, "navigation"), placement,
        viewport, role, key, layers, surface, details)
    case None{}: role_overlay(viewport, role, key, layers, surface, details)

def overlay_placement_with_drawer(viewport: Design.Viewport, node: UI.Node, +layers: +List<V.Layer>,
  +surface: UI.Surface, +shell: Design.Shell,
  drawer: Maybe<&2, Design.OverlayPlacement>) -> Design.OverlayPlacement:
  UI.Node{key, semantic, +label, role, +meaning, +children} = node
  Design.Shell{shell_navigation, +main, details} = shell
  overlay_with_drawer(drawer, semantic, viewport, role, key, layers, surface, details)

def overlay_placement(+viewport: Design.Viewport, node: UI.Node, +layers: +List<V.Layer>,
  +surface: UI.Surface, +shell: Design.Shell, +navigation: V.NavigationPlacement) -> Design.OverlayPlacement:
  Design.Shell{shell_navigation, main, details} = shell
  overlay_placement_with_drawer(viewport, node, layers, surface, shell,
    navigation_overlay(navigation, shell_navigation))

def projected_overlays(+viewport: Design.Viewport, +overlays: +List<UI.Node>, +layers: +List<V.Layer>,
  +surface: UI.Surface, +shell: Design.Shell, +navigation: V.NavigationPlacement) -> +List<Design.Overlay>:
  match overlays:
    case Nil{}: Nil{}
    case Con{UI.Node{key, semantic, label, role, meaning, children}, rest}:
      Con{Design.Overlay{key, Nat.add(100n, List.length(&2, UI.Node, rest)),
        overlay_placement(viewport, UI.Node{key, semantic, label, role, meaning, children}, layers,
          surface, shell, navigation)},
        projected_overlays(viewport, rest, layers, surface, shell, navigation)}

def actual_details(+overlays: +List<UI.Node>) -> Bool:
  match overlays:
    case Nil{}: False{}
    case Con{UI.Node{+key, +semantic, +label, role, +meaning, +children}, rest}:
      match role:
        case UI.Details{}: True{}
        case _: actual_details(rest)

def layout_with_shell(+viewport: Design.Viewport, +surface: UI.Surface, +overlays: +List<UI.Node>, +shell: Design.Shell,
  navigation: V.NavigationPlacement, +page: Composition.Page, +layers: +List<V.Layer>) -> Design.Layout:
  Design.Shell{shell_navigation, main, +details} = shell
  +recipe = Composition.recipe(page)
  Design.Layout{viewport, shell, main_frame(recipe, main),
    projected_overlays(viewport, overlays, layers, surface, shell, navigation), Composition.structure(recipe)}

def capacity_allows_details(capacity: V.Capacity) -> Bool:
  V.Capacity{navigation_beside_content, details_beside_timeline} = capacity
  details_beside_timeline

def present(+viewport: Design.Viewport, +surface: UI.Surface) -> Design.Layout:
  UI.Surface{content, base, +overlays, active_scope} = surface
  Core.Scene{V.Scene{world_navigation, world_main, layers, arrangement, attention}, settings, transfers, preview, code} = content
  V.Arrangement{navigation, page} = arrangement
  requested_side_pane = actual_details(overlays) && capacity_allows_details(capacity(viewport))
  current_shell = shell(viewport, navigation, requested_side_pane)
  layout_with_shell(viewport, surface, overlays, current_shell, navigation, page, layers)
