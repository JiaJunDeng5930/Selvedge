import Base
import ../core/ui-world.bend as V
import ../core/interface.bend as UI
import ../core/composition.bend as Composition
import ./design.bend as Design
import ./layout.bend as Layout
import ./renderer.bend as Render

import ./viewport-space.bend as ViewportSpace
import ./viewport-space-laws.bend as ViewportSpaceLaws
import ./space.bend as Space
import ./container-space-laws.bend as ContainerLaws
import ../core/SYSTEM.bend as Core
import ../core/user-experience.bend as E

def conversation_recipe(composer: Composition.Composer, decisions: Composition.Decisions,
  latest: Composition.Latest) -> Composition.Recipe:
  Composition.Recipe{Composition.ReadingMeasure{}, Composition.ConversationHeading{},
    Composition.ChronologicalReading{}, composer, decisions, latest}

def expected_main_frame(+parameters: Design.LayoutParameters, +recipe: Composition.Recipe, +main: Design.Box) -> Design.MainFrame:
  match recipe:
    case Composition.Recipe{measure, page_heading, Composition.CenteredCreation{}, composer, decisions, latest}:
      Design.CreationFrame{Layout.heading_box(parameters, main), main, Layout.measure_band(parameters, measure, main),
        Layout.centered_input(parameters, composer, main), Layout.creation_flow(parameters, main)}
    case Composition.Recipe{measure, page_heading, Composition.ChronologicalReading{}, composer, decisions, latest}:
      heading = Layout.heading_box(parameters, main)
      +body_viewport = Layout.body_box(parameters, main)
      +reading = Layout.measure_band(parameters, measure, body_viewport)
      Design.ConversationFrame{heading, body_viewport, reading,
        Layout.conversation_dock(parameters, Layout.recipe_dock(recipe), body_viewport, reading, composer)}
    case Composition.Recipe{measure, page_heading, Composition.ProjectSections{}, composer, decisions, latest}:
      +body_viewport = main
      Design.OverviewFrame{body_viewport, Layout.measure_band(parameters, measure, body_viewport), Composition.ProjectSections{}}
    case Composition.Recipe{measure, page_heading, Composition.ProjectRows{}, composer, decisions, latest}:
      +body_viewport = main
      Design.OverviewFrame{body_viewport, Layout.measure_band(parameters, measure, body_viewport), Composition.ProjectRows{}}
    case Composition.Recipe{measure, page_heading, Composition.AgentRows{}, composer, decisions, latest}:
      +body_viewport = main
      Design.OverviewFrame{body_viewport, Layout.measure_band(parameters, measure, body_viewport), Composition.AgentRows{}}
    case Composition.Recipe{measure, page_heading, Composition.StageColumns{}, composer, decisions, latest}:
      +body_viewport = main
      Design.BoardFrame{body_viewport, Layout.board_column_width(parameters, body_viewport),
        16n, 16n}
    case Composition.Recipe{measure, page_heading, Composition.UnavailableNotice{}, composer, decisions, latest}:
      Design.UnavailableFrame{Layout.heading_box(parameters, main), Layout.body_box(parameters, main), Layout.measure_band(parameters, measure, Layout.body_box(parameters, main))}

def explicit_main_frame(+parameters: Design.LayoutParameters, +recipe: Composition.Recipe, +main: Design.Box) ->
  {Layout.main_frame(parameters, recipe, main) == expected_main_frame(parameters, recipe, main) : Design.MainFrame}:
  match recipe:
    case Composition.Recipe{measure, page_heading, Composition.CenteredCreation{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, page_heading, Composition.ChronologicalReading{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, page_heading, Composition.ProjectSections{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, page_heading, Composition.ProjectRows{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, page_heading, Composition.AgentRows{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, page_heading, Composition.StageColumns{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, page_heading, Composition.UnavailableNotice{}, composer, decisions, latest}: {==}



def navigation_beside(capacity: V.Capacity) -> Bool:
  V.Capacity{navigation_beside_content, details_beside_timeline} = capacity
  navigation_beside_content

def details_beside(capacity: V.Capacity) -> Bool:
  V.Capacity{navigation_beside_content, details_beside_timeline} = capacity
  details_beside_timeline







def surface_with_scope(surface: UI.Surface, scope: Maybe<&2, String>) -> UI.Surface:
  UI.Surface{content, +base, +overlays, previous_scope} = surface
  UI.Surface{content, base, overlays, scope}

def anchor_is_scope_independent(+surface: UI.Surface, +requested: String, scope: Maybe<&2, String>) ->
  {Layout.anchor(surface, requested) ==
    Layout.anchor(surface_with_scope(surface, scope), requested) : Maybe<&2, String>}:
  match surface:
    case UI.Surface{content, +base, +overlays, +previous_scope}: {==}

def surface_with_trigger_in_base(surface: UI.Surface, +trigger: UI.Node,
  scope: Maybe<&2, String>) -> UI.Surface:
  UI.Surface{content, +base, +overlays, previous_scope} = surface
  UI.Surface{content, trigger <> base, overlays, scope}

def base_nodes_with_trigger(+surface: UI.Surface, +trigger: UI.Node) -> +List<UI.Node>:
  UI.Surface{content, +base, +overlays, active_scope} = surface
  trigger <> base



def exact_trigger_node_in_base(+surface: UI.Surface, +trigger: UI.Node,
  scope: Maybe<&2, String>,
  found: {UI.find_node(base_nodes_with_trigger(surface, trigger), UI.node_key(trigger)) ==
    Some{trigger} : Maybe<&2, UI.Node>}) ->
  {Layout.anchor(surface_with_trigger_in_base(surface, trigger, scope), UI.node_key(trigger)) ==
    Some{UI.node_key(trigger)} : Maybe<&2, String>}:
  match surface:
    case UI.Surface{content, +base, +overlays, +previous_scope}:
      match trigger:
        case UI.Node{key, semantic, label, role, meaning, +children}:
          Equal.trans(Maybe<&2, String>,
            Layout.anchor(surface_with_trigger_in_base(surface, trigger, scope), key),
            Layout.choose_surface_anchor(
              Layout.exact_anchor_in_tree(key, trigger <> base),
              Layout.exact_anchor_in_tree(key, overlays),
              Layout.semantic_anchor_in_tree(key, trigger <> base),
              Layout.semantic_anchor_in_tree(key, overlays)),
            Some{key}, {==},
            Equal.cong(Maybe<&2, String>, Maybe<&2, String>,
              exact_base => Layout.choose_surface_anchor(exact_base,
                Layout.exact_anchor_in_tree(key, overlays),
                Layout.semantic_anchor_in_tree(key, trigger <> base),
                Layout.semantic_anchor_in_tree(key, overlays)),
              Layout.exact_anchor_in_tree(key, trigger <> base), Some{key},
              Equal.cong(Maybe<&2, UI.Node>, Maybe<&2, String>,
                found_node => Layout.anchor_for_node(found_node),
                UI.find_node(trigger <> base, key), Some{trigger}, found)))

def surface_with_empty_trees(surface: UI.Surface, scope: Maybe<&2, String>) -> UI.Surface:
  UI.Surface{content, base, overlays, previous_scope} = surface
  UI.Surface{content, Nil{}, Nil{}, scope}

def empty_tree_anchor_is_absent(+surface: UI.Surface, +requested: String, scope: Maybe<&2, String>) ->
  {Layout.anchor(surface_with_empty_trees(surface, scope), requested) ==
    None{} : Maybe<&2, String>}:
  match surface:
    case UI.Surface{content, +base, +overlays, +previous_scope}: {==}

def anchored_layer(initial_attention: String, return_attention: String,
  content: V.LayerContent, close: V.Dismissal) -> V.Layer:
  V.Layer{V.AnchoredMenu{}, content, initial_attention, return_attention, close}

def expected_anchored_menu(+parameters: Design.LayoutParameters, viewport: Design.Viewport, origin: String) -> Design.OverlayPlacement:
  +available = Layout.inset_box(parameters, viewport)
  Design.AnchoredPopover{origin, available, Nat.min(320n, Layout.box_width(available)),
    Nat.min(400n, Layout.box_height(available)), 4n}


# The browser evaluates real anchor space; this production projection requires
# all anchored menus to prefer larger block space before fitting a scrollport.
def anchored_menu_prefers_block_space_law(+parameters: Design.LayoutParameters, -viewport: Design.Viewport, -origin: String) -> Type:
  {(Render.attr(Render.overlay_styles(Layout.anchored_menu_placement(parameters, viewport, Some{origin})), "position-try-order"),
      Render.attr(Render.overlay_styles(Layout.anchored_menu_placement(parameters, viewport, Some{origin})), "position-try-fallbacks")) ==
      ("most-block-size", "flip-block, flip-inline, flip-block flip-inline") : (String & String)}

def anchored_menu_prefers_block_space(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +origin: String) -> anchored_menu_prefers_block_space_law(parameters, viewport, origin):
  match viewport:
    case Design.Viewport{width, height}: {==}



def expected_projected_overlays(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +overlays: +List<UI.Node>,
  +layers: +List<V.Layer>, +surface: UI.Surface, +shell: Design.Shell,
  +navigation: V.NavigationPlacement) -> +List<Design.Overlay>:
  match overlays:
    case Nil{}: Nil{}
    case Con{UI.Node{key, semantic, label, role, meaning, children}, rest}:
      Con{Design.Overlay{key, Nat.add(100n, List.length(&2, UI.Node, rest)),
        Layout.overlay_placement(parameters, viewport, UI.Node{key, semantic, label, role, meaning, children},
          layers, surface, shell, navigation)},
        expected_projected_overlays(parameters, viewport, rest, layers, surface, shell, navigation)}

def overlay_identity_projection(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +overlays: +List<UI.Node>,
  +layers: +List<V.Layer>, +surface: UI.Surface, +shell: Design.Shell,
  +navigation: V.NavigationPlacement) ->
  {Layout.projected_overlays(parameters, viewport, overlays, layers, surface, shell, navigation) ==
    expected_projected_overlays(parameters, viewport, overlays, layers, surface, shell, navigation) : +List<Design.Overlay>}:
  match overlays:
    case Nil{}: {==}
    case Con{UI.Node{+key, semantic, label, +role, +meaning, +children}, +rest}:
      Equal.cong(+List<Design.Overlay>, +List<Design.Overlay>,
        (tail => Con{Design.Overlay{key, Nat.add(100n, List.length(&2, UI.Node, rest)),
          Layout.overlay_placement(parameters, viewport,
            UI.Node{key, semantic, label, role, meaning, children}, layers, surface, shell, navigation)},
          tail}),
        Layout.projected_overlays(parameters, viewport, rest, layers, surface, shell, navigation),
        expected_projected_overlays(parameters, viewport, rest, layers, surface, shell, navigation),
        overlay_identity_projection(parameters, viewport, rest, layers, surface, shell, navigation))

def conversation_has_no_dock(frame: Design.MainFrame) -> Bool:
  match frame:
    case Design.ConversationFrame{heading, viewport, reading, None{}}: True{}
    case Design.ConversationFrame{heading, viewport, reading, Some{dock}}: False{}
    case _: False{}



def only_pending_approval(regions: +List<Design.DockRegion>) -> Bool:
  match regions:
    case Con{Design.PendingApprovals{}, Nil{}}: True{}
    case _: False{}

def no_dock_input(input: Maybe<&2, Design.InputMetrics>) -> Bool:
  match input:
    case None{}: True{}
    case Some{metrics}: False{}

def conversation_has_approval_only_dock(frame: Design.MainFrame) -> Bool:
  match frame:
    case Design.ConversationFrame{heading, viewport, reading,
      Some{Design.Dock{band, bottom_inset, maximum_height, regions, input, reservation}}}:
      only_pending_approval(regions) && no_dock_input(input)
    case _: False{}



def input_metrics_law(+parameters: Design.LayoutParameters, -canvas: Design.Box) -> Type:
  {Layout.input_metrics(parameters, canvas) == Design.InputMetrics{
      Design.input_minimum_height(parameters),
      Nat.max(Design.input_minimum_height(parameters), Nat.min(Design.input_maximum_height(parameters), Nat.div(Layout.box_height(canvas), 3n))), Design.input_line_height(parameters), Layout.composer_content_inset(), 4n, 8n} : Design.InputMetrics}

def input_metrics_follow_consistent_bounds(+parameters: Design.LayoutParameters, canvas: Design.Box) -> input_metrics_law(parameters, canvas):
  match canvas:
    case Design.Box{+left, +top, +width, height}: {==}















def ready(value: Layout.Outcome) -> Bool:
  match value:
    case Layout.LayoutReady{layout}: True{}
    case Layout.LayoutUnsupported{required, available}: False{}

def layout_parameters(value: Design.Layout) -> Design.LayoutParameters:
  Design.Layout{viewport, shell, main, overlays, parameters, controls} = value
  parameters

def carried_parameters(+parameters: Design.LayoutParameters, viewport: Design.Viewport, surface: UI.Surface,
  overlays: +List<UI.Node>, shell: Design.Shell, navigation: V.NavigationPlacement, page: Composition.Page,
  layers: +List<V.Layer>) ->
  {layout_parameters(Layout.layout_with_shell(parameters, viewport, surface, overlays, shell, navigation, page, layers)) == parameters : Design.LayoutParameters}:
  Design.Shell{navigation_value, main, details} = shell
  {==}

# Success requires both actual control axes, after shell allocation.
def controls_ready(result: Layout.ControlAllocation) -> Bool:
  match result:
    case Layout.ControlsReady{controls}: True{}
    case Layout.ControlsUnsupported{required, available}: False{}

def band_fits(+target: Design.Box, +leading: +List<Layout.ControlItem>, +trailing: +List<Layout.ControlItem>) -> Bool:
  Nat.is_le(Nat.max(Layout.cross_minimum(leading), Layout.cross_minimum(trailing)), Layout.box_height(target)) &&
    Nat.is_le(Space.container_required(~Layout.ControlItem, Layout.control_container(leading, trailing)), Layout.box_width(target))

def allocated_tag(+allocation: Space.Allocation<Layout.ControlItem>, target: Design.Box, band: Nat) ->
  {controls_ready(Layout.finish_controls(Space.finish(~Layout.ControlItem, allocation), target, band)) == True{} : Bool}:
  Space.Allocation{placements, unused} = allocation
  {==}

def container_tag(+fits: Bool, +container: Space.Container<Layout.ControlItem>, +width: Nat, +target: Design.Box, +band: Nat) ->
  {controls_ready(Layout.finish_controls(Space.feasible_container(~Layout.ControlItem, fits, container, width), target, band)) == fits : Bool}:
  match fits:
    case False{}: {==}
    case True{}:
      Space.Container{leading, trailing, gap, slots} = container
      allocated_tag(Space.place_from(~Layout.ControlItem, slots, gap, leading, Nat.sub(Nat.sub(width, leading), trailing)), target, band)

def band_tag(+fits: Bool, +parameters: Design.LayoutParameters, +target: Design.Box,
  +leading: +List<Layout.ControlItem>, +trailing: +List<Layout.ControlItem>, +cross: Nat) ->
  {controls_ready(Layout.allocate_control_band(fits, parameters, target, leading, trailing, cross)) ==
    (fits && Nat.is_le(Space.container_required(~Layout.ControlItem, Layout.control_container(leading, trailing)), Layout.box_width(target))) : Bool}:
  match fits:
    case False{}:
      Design.Box{left, top, width, height} = target
      {==}
    case True{}:
      Design.Box{left, top, width, height} = target
      container_tag(Nat.is_le(Space.container_required(~Layout.ControlItem, Layout.control_container(leading, trailing)), width),
        Layout.control_container(leading, trailing), width, target, Nat.min(height, Nat.max(Design.toolbar_height(parameters), cross)))

def allocation_feasibility(+parameters: Design.LayoutParameters, +target: Design.Box,
  +leading: +List<Layout.ControlItem>, +trailing: +List<Layout.ControlItem>) ->
  {controls_ready(Layout.allocate_controls(parameters, target, leading, trailing)) == band_fits(target, leading, trailing) : Bool}:
  Design.Box{left, top, width, height} = target
  band_tag(Nat.is_le(Nat.max(Layout.cross_minimum(leading), Layout.cross_minimum(trailing)), height),
    parameters, target, leading, trailing, Nat.max(Layout.cross_minimum(leading), Layout.cross_minimum(trailing)))

def shell_fits(+shell: Design.Shell, +settings: +List<Layout.ControlItem>, +toggles: +List<Layout.ControlItem>) -> Bool:
  Design.Shell{navigation, main, details} = shell
  match navigation:
    case Design.HiddenNavigation{}: band_fits(main, toggles, settings)
    case Design.BesideNavigation{box}: band_fits(box, Nil{}, settings)
    case Design.OverlayNavigation{box}: band_fits(box, Nil{}, settings)

def adapted(+parameters: Design.LayoutParameters, +shell: Design.Shell,
  +settings: +List<Layout.ControlItem>, +toggles: +List<Layout.ControlItem>) -> Design.LayoutParameters:
  Design.Shell{navigation, main, details} = shell
  Layout.adapt_parameters(parameters, Nat.max(Layout.cross_minimum(settings), Layout.cross_minimum(Layout.active_toggles(navigation, toggles))))

def shell_feasibility(+parameters: Design.LayoutParameters, +shell: Design.Shell,
  +settings: +List<Layout.ControlItem>, +toggles: +List<Layout.ControlItem>) ->
  {controls_ready(Layout.shell_controls(parameters, shell, settings, toggles)) == shell_fits(shell, settings, toggles) : Bool}:
  Design.Shell{navigation, main, details} = shell
  match navigation:
    case Design.HiddenNavigation{}: allocation_feasibility(parameters, main, toggles, settings)
    case Design.BesideNavigation{box}: allocation_feasibility(parameters, box, Nil{}, settings)
    case Design.OverlayNavigation{box}: allocation_feasibility(parameters, box, Nil{}, settings)

def layout_control_tag(+result: Layout.ControlAllocation, +layout: Design.Layout) ->
  {ready(Layout.layout_controls(result, layout)) == controls_ready(result) : Bool}:
  match result:
    case Layout.ControlsUnsupported{required, available}: {==}
    case Layout.ControlsReady{controls}:
      Design.Layout{viewport, shell, main, overlays, parameters, previous} = layout
      {==}

def decision_fits(+result: ViewportSpace.Result, +settings: +List<Layout.ControlItem>, +toggles: +List<Layout.ControlItem>) -> Bool:
  match result:
    case ViewportSpace.Unsupported{required, available}: False{}
    case ViewportSpace.Allocated{shell}: shell_fits(shell, settings, toggles)

def shell_navigation(shell: Design.Shell) -> Design.Navigation:
  Design.Shell{navigation, main, details} = shell
  navigation

def prepare_tag(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  +overlays: +List<UI.Node>, +shell: Design.Shell, +navigation: V.NavigationPlacement, +page: Composition.Page, +layers: +List<V.Layer>,
  +settings: +List<Layout.ControlItem>, +toggles: +List<Layout.ControlItem>) ->
  {ready(Layout.prepare_shell_controls(parameters, viewport, surface, overlays, shell, navigation, page, layers, settings, toggles)) ==
    shell_fits(shell, settings, Layout.active_toggles(shell_navigation(shell), toggles)) : Bool}:
  Design.Shell{shell_navigation_value, main, details} = shell
  +selected = Layout.active_toggles(shell_navigation_value, toggles)
  +effective = adapted(parameters, shell, settings, toggles)
  Equal.trans(Bool,
    ready(Layout.prepare_shell_controls(parameters, viewport, surface, overlays, shell, navigation, page, layers, settings, toggles)),
    controls_ready(Layout.shell_controls(effective, shell, settings, selected)), shell_fits(shell, settings, selected),
    layout_control_tag(Layout.shell_controls(effective, shell, settings, selected),
      Layout.layout_with_shell(effective, viewport, surface, overlays, shell, navigation, page, layers)),
    shell_feasibility(effective, shell, settings, selected))

def outcome_feasibility(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  +overlays: +List<UI.Node>, +navigation: V.NavigationPlacement, +page: Composition.Page, +layers: +List<V.Layer>,
  +settings: +List<Layout.ControlItem>, +toggles: +List<Layout.ControlItem>, +result: ViewportSpace.Result) ->
  {ready(Layout.outcome_with_shell(parameters, viewport, surface, overlays, navigation, page, layers, settings, toggles, result)) ==
    decision_fits(result, settings, toggles) : Bool}:
  match result:
    case ViewportSpace.Unsupported{required, available}: {==}
    case ViewportSpace.Allocated{shell}:
      Design.Shell{shell_navigation, main, details} = shell
      match shell_navigation:
        case Design.HiddenNavigation{}:
          prepare_tag(parameters, viewport, surface, overlays, shell, navigation, page, layers, settings, toggles)
        case Design.BesideNavigation{box}:
          prepare_tag(parameters, viewport, surface, overlays, shell, navigation, page, layers, settings, toggles)
        case Design.OverlayNavigation{box}:
          prepare_tag(parameters, viewport, surface, overlays, shell, navigation, page, layers, settings, toggles)

def ParametersClaim(outcome: Layout.Outcome, parameters: Design.LayoutParameters) -> Type:
  match outcome:
    case Layout.LayoutReady{layout}: {layout_parameters(layout) == parameters : Design.LayoutParameters}
    case Layout.LayoutUnsupported{required, available}: Unit

def control_parameters(+result: Layout.ControlAllocation, +layout: Design.Layout) ->
  ParametersClaim(Layout.layout_controls(result, layout), layout_parameters(layout)):
  match result:
    case Layout.ControlsUnsupported{required, available}: Unit{}
    case Layout.ControlsReady{controls}:
      Design.Layout{viewport, shell, main, overlays, parameters, previous} = layout
      {==}

def decision_parameters(+parameters: Design.LayoutParameters, +result: ViewportSpace.Result,
  +settings: +List<Layout.ControlItem>, +toggles: +List<Layout.ControlItem>) -> Design.LayoutParameters:
  match result:
    case ViewportSpace.Unsupported{required, available}: parameters
    case ViewportSpace.Allocated{shell}: adapted(parameters, shell, settings, toggles)

def outcome_parameters(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  +overlays: +List<UI.Node>, +navigation: V.NavigationPlacement, +page: Composition.Page, +layers: +List<V.Layer>,
  +settings: +List<Layout.ControlItem>, +toggles: +List<Layout.ControlItem>, +result: ViewportSpace.Result) ->
  ParametersClaim(Layout.outcome_with_shell(parameters, viewport, surface, overlays, navigation, page, layers, settings, toggles, result),
    decision_parameters(parameters, result, settings, toggles)):
  match result:
    case ViewportSpace.Unsupported{required, available}: Unit{}
    case ViewportSpace.Allocated{shell}:
      Design.Shell{shell_navigation_value, main, details} = shell
      +effective = adapted(parameters, shell, settings, toggles)
      control_parameters(Layout.shell_controls(effective, shell, settings, Layout.active_toggles(shell_navigation_value, toggles)),
        Layout.layout_with_shell(effective, viewport, surface, overlays, shell, navigation, page, layers))

def SurfaceFeasibility(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  +nodes: +List<Design.Node>) -> Bool:
  UI.Surface{Core.Scene{view, settings, transfers, preview, code, picker}, base, overlays, scope} = surface
  V.Scene{navigation, main, layers, V.Arrangement{placement}, attention} = view
  decision_fits(Layout.shell(parameters, viewport, placement, Layout.requested_details(parameters, viewport, placement, overlays)),
    Layout.collect_controls(nodes, True{}), Layout.collect_controls(nodes, False{}))

def surface_feasible(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  +nodes: +List<Design.Node>) ->
  {ready(Layout.present_semantic(parameters, viewport, surface, nodes)) == SurfaceFeasibility(parameters, viewport, surface, nodes) : Bool}:
  UI.Surface{Core.Scene{+view, settings, transfers, preview, code, picker}, base, +overlays, scope} = surface
  V.Scene{navigation, main, +layers, V.Arrangement{+placement}, attention} = view
  outcome_feasibility(parameters, viewport, surface, overlays, placement, V.scene_page(view), layers,
    Layout.collect_controls(nodes, True{}), Layout.collect_controls(nodes, False{}),
    Layout.shell(parameters, viewport, placement, Layout.requested_details(parameters, viewport, placement, overlays)))

def PresentFeasibility(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, presentation: Design.PreparedSurface) -> Bool:
  Design.PreparedSurface{+prepared, cached_base, cached_overlays} = presentation
  Design.Surface{content, theme, nodes, overlays, active} = prepared
  SurfaceFeasibility(parameters, viewport, Design.semantic_surface(prepared), nodes)

def present_feasible(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +presentation: Design.PreparedSurface) ->
  {ready(Layout.present(parameters, viewport, presentation)) == PresentFeasibility(parameters, viewport, presentation) : Bool}:
  Design.PreparedSurface{+prepared, cached_base, cached_overlays} = presentation
  Design.Surface{content, theme, +nodes, overlays, active} = prepared
  surface_feasible(parameters, viewport, Design.semantic_surface(prepared), nodes)

def SemanticParameters(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  +nodes: +List<Design.Node>) -> Design.LayoutParameters:
  UI.Surface{Core.Scene{view, settings, transfers, preview, code, picker}, base, overlays, scope} = surface
  V.Scene{navigation, main, layers, V.Arrangement{placement}, attention} = view
  decision_parameters(parameters,
    Layout.shell(parameters, viewport, placement, Layout.requested_details(parameters, viewport, placement, overlays)),
    Layout.collect_controls(nodes, True{}), Layout.collect_controls(nodes, False{}))

def semantic_parameters(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  +nodes: +List<Design.Node>) ->
  ParametersClaim(Layout.present_semantic(parameters, viewport, surface, nodes), SemanticParameters(parameters, viewport, surface, nodes)):
  UI.Surface{Core.Scene{+view, settings, transfers, preview, code, picker}, base, +overlays, scope} = surface
  V.Scene{navigation, main, +layers, V.Arrangement{+placement}, attention} = view
  outcome_parameters(parameters, viewport, surface, overlays, placement, V.scene_page(view), layers,
    Layout.collect_controls(nodes, True{}), Layout.collect_controls(nodes, False{}),
    Layout.shell(parameters, viewport, placement, Layout.requested_details(parameters, viewport, placement, overlays)))

def PresentParameters(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, presentation: Design.PreparedSurface) -> Design.LayoutParameters:
  Design.PreparedSurface{+prepared, cached_base, cached_overlays} = presentation
  Design.Surface{content, theme, nodes, actual_overlays, active} = prepared
  SemanticParameters(parameters, viewport, Design.semantic_surface(prepared), nodes)

def present_parameters(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +presentation: Design.PreparedSurface) ->
  ParametersClaim(Layout.present(parameters, viewport, presentation), PresentParameters(parameters, viewport, presentation)):
  Design.PreparedSurface{+prepared, cached_base, cached_overlays} = presentation
  Design.Surface{content, theme, +nodes, actual_overlays, active} = prepared
  semantic_parameters(parameters, viewport, Design.semantic_surface(prepared), nodes)

def parameter_update(+parameters: Design.LayoutParameters, +cross: Nat) ->
  {Layout.adapt_parameters(parameters, cross) == Design.LayoutParameters{
    Design.navigation_width(parameters), Design.main_minimum_width(parameters), Design.details_width(parameters),
    Design.reading_maximum_width(parameters), Design.overview_maximum_width(parameters), Nat.max(Design.toolbar_height(parameters), cross),
    Design.input_minimum_height(parameters), Design.input_maximum_height(parameters), Design.input_line_height(parameters),
    Design.creation_balanced_minimum_height(parameters)} : Design.LayoutParameters}:
  Design.LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = parameters
  {==}

type Shortage is Data:
  Shortage{required: Nat, available: Nat}

def control_shortage(value: Layout.ControlAllocation) -> Maybe<&2, Shortage>:
  match value:
    case Layout.ControlsReady{controls}: None{}
    case Layout.ControlsUnsupported{required, available}: Some{Shortage{required, available}}

def outcome_shortage(value: Layout.Outcome) -> Maybe<&2, Shortage>:
  match value:
    case Layout.LayoutReady{layout}: None{}
    case Layout.LayoutUnsupported{required, available}: Some{Shortage{required, available}}

def width_shortage(fits: Bool, required: Nat, available: Nat) -> Maybe<&2, Shortage>:
  match fits:
    case True{}: None{}
    case False{}: Some{Shortage{required, available}}

def band_shortage(fits: Bool, +target: Design.Box, +leading: +List<Layout.ControlItem>, +trailing: +List<Layout.ControlItem>, cross: Nat) -> Maybe<&2, Shortage>:
  match fits:
    case False{}: Some{Shortage{cross, Layout.box_height(target)}}
    case True{}:
      +required = Space.container_required(~Layout.ControlItem, Layout.control_container(leading, trailing))
      width_shortage(Nat.is_le(required, Layout.box_width(target)), required, Layout.box_width(target))

def target_shortage(+target: Design.Box, +leading: +List<Layout.ControlItem>, +trailing: +List<Layout.ControlItem>) -> Maybe<&2, Shortage>:
  +cross = Nat.max(Layout.cross_minimum(leading), Layout.cross_minimum(trailing))
  band_shortage(Nat.is_le(cross, Layout.box_height(target)), target, leading, trailing, cross)

def allocated_shortage(allocation: Space.Allocation<Layout.ControlItem>, target: Design.Box, band: Nat) ->
  {control_shortage(Layout.finish_controls(Space.finish(~Layout.ControlItem, allocation), target, band)) == None{} : Maybe<&2, Shortage>}:
  Space.Allocation{placements, unused} = allocation
  {==}

def container_shortage(+fits: Bool, +container: Space.Container<Layout.ControlItem>, +available: Nat, +target: Design.Box, band: Nat) ->
  {control_shortage(Layout.finish_controls(Space.feasible_container(~Layout.ControlItem, fits, container, available), target, band)) ==
    width_shortage(fits, Space.container_required(~Layout.ControlItem, container), available) : Maybe<&2, Shortage>}:
  match fits:
    case False{}: {==}
    case True{}:
      Space.Container{leading, trailing, gap, slots} = container
      allocated_shortage(Space.place_from(~Layout.ControlItem, slots, gap, leading, Nat.sub(Nat.sub(available, leading), trailing)), target, band)

def band_shortage_exact(+fits: Bool, +parameters: Design.LayoutParameters, +target: Design.Box,
  +leading: +List<Layout.ControlItem>, +trailing: +List<Layout.ControlItem>, +cross: Nat) ->
  {control_shortage(Layout.allocate_control_band(fits, parameters, target, leading, trailing, cross)) ==
    band_shortage(fits, target, leading, trailing, cross) : Maybe<&2, Shortage>}:
  match fits:
    case False{}:
      Design.Box{left, top, width, height} = target
      {==}
    case True{}:
      Design.Box{left, top, width, height} = target
      container_shortage(Nat.is_le(Space.container_required(~Layout.ControlItem, Layout.control_container(leading, trailing)), width),
        Layout.control_container(leading, trailing), width, target, Nat.min(height, Nat.max(Design.toolbar_height(parameters), cross)))

def target_shortage_exact(+parameters: Design.LayoutParameters, +target: Design.Box,
  +leading: +List<Layout.ControlItem>, +trailing: +List<Layout.ControlItem>) ->
  {control_shortage(Layout.allocate_controls(parameters, target, leading, trailing)) == target_shortage(target, leading, trailing) : Maybe<&2, Shortage>}:
  Design.Box{left, top, width, height} = target
  +cross = Nat.max(Layout.cross_minimum(leading), Layout.cross_minimum(trailing))
  band_shortage_exact(Nat.is_le(cross, height), parameters, target, leading, trailing, cross)

def shell_shortage(+shell: Design.Shell, +settings: +List<Layout.ControlItem>, +toggles: +List<Layout.ControlItem>) -> Maybe<&2, Shortage>:
  Design.Shell{navigation, main, details} = shell
  match navigation:
    case Design.HiddenNavigation{}: target_shortage(main, toggles, settings)
    case Design.BesideNavigation{box}: target_shortage(box, Nil{}, settings)
    case Design.OverlayNavigation{box}: target_shortage(box, Nil{}, settings)

def shell_shortage_exact(+parameters: Design.LayoutParameters, +shell: Design.Shell,
  +settings: +List<Layout.ControlItem>, +toggles: +List<Layout.ControlItem>) ->
  {control_shortage(Layout.shell_controls(parameters, shell, settings, toggles)) == shell_shortage(shell, settings, toggles) : Maybe<&2, Shortage>}:
  Design.Shell{navigation, main, details} = shell
  match navigation:
    case Design.HiddenNavigation{}: target_shortage_exact(parameters, main, toggles, settings)
    case Design.BesideNavigation{box}: target_shortage_exact(parameters, box, Nil{}, settings)
    case Design.OverlayNavigation{box}: target_shortage_exact(parameters, box, Nil{}, settings)

def control_shortage_preserved(+result: Layout.ControlAllocation, +layout: Design.Layout) ->
  {outcome_shortage(Layout.layout_controls(result, layout)) == control_shortage(result) : Maybe<&2, Shortage>}:
  match result:
    case Layout.ControlsUnsupported{required, available}: {==}
    case Layout.ControlsReady{controls}:
      Design.Layout{viewport, shell, main, overlays, parameters, previous} = layout
      {==}

def prepare_shortage_exact(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  +overlays: +List<UI.Node>, +shell: Design.Shell, +navigation: V.NavigationPlacement, +page: Composition.Page, +layers: +List<V.Layer>,
  +settings: +List<Layout.ControlItem>, +toggles: +List<Layout.ControlItem>) ->
  {outcome_shortage(Layout.prepare_shell_controls(parameters, viewport, surface, overlays, shell, navigation, page, layers, settings, toggles)) ==
    shell_shortage(shell, settings, Layout.active_toggles(shell_navigation(shell), toggles)) : Maybe<&2, Shortage>}:
  Design.Shell{navigation_value, main, details} = shell
  +selected = Layout.active_toggles(navigation_value, toggles)
  +effective = adapted(parameters, shell, settings, toggles)
  Equal.trans(Maybe<&2, Shortage>,
    outcome_shortage(Layout.prepare_shell_controls(parameters, viewport, surface, overlays, shell, navigation, page, layers, settings, toggles)),
    control_shortage(Layout.shell_controls(effective, shell, settings, selected)), shell_shortage(shell, settings, selected),
    control_shortage_preserved(Layout.shell_controls(effective, shell, settings, selected),
      Layout.layout_with_shell(effective, viewport, surface, overlays, shell, navigation, page, layers)),
    shell_shortage_exact(effective, shell, settings, selected))

def decision_shortage(+result: ViewportSpace.Result, +settings: +List<Layout.ControlItem>, +toggles: +List<Layout.ControlItem>) -> Maybe<&2, Shortage>:
  match result:
    case ViewportSpace.Unsupported{required, available}: Some{Shortage{required, available}}
    case ViewportSpace.Allocated{shell}: shell_shortage(shell, settings, toggles)

def outcome_shortage_exact(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  +overlays: +List<UI.Node>, +navigation: V.NavigationPlacement, +page: Composition.Page, +layers: +List<V.Layer>,
  +settings: +List<Layout.ControlItem>, +toggles: +List<Layout.ControlItem>, +result: ViewportSpace.Result) ->
  {outcome_shortage(Layout.outcome_with_shell(parameters, viewport, surface, overlays, navigation, page, layers, settings, toggles, result)) ==
    decision_shortage(result, settings, toggles) : Maybe<&2, Shortage>}:
  match result:
    case ViewportSpace.Unsupported{required, available}: {==}
    case ViewportSpace.Allocated{shell}:
      Design.Shell{navigation_value, main, details} = shell
      match navigation_value:
        case Design.HiddenNavigation{}: prepare_shortage_exact(parameters, viewport, surface, overlays, shell, navigation, page, layers, settings, toggles)
        case Design.BesideNavigation{box}: prepare_shortage_exact(parameters, viewport, surface, overlays, shell, navigation, page, layers, settings, toggles)
        case Design.OverlayNavigation{box}: prepare_shortage_exact(parameters, viewport, surface, overlays, shell, navigation, page, layers, settings, toggles)

def layout_main(layout: Design.Layout) -> Design.MainFrame:
  Design.Layout{viewport, shell, main, overlays, parameters, controls} = layout
  main

def AssemblyClaim(outcome: Layout.Outcome, +parameters: Design.LayoutParameters, frame: Design.MainFrame) -> Type:
  match outcome:
    case Layout.LayoutUnsupported{required, available}: Unit
    case Layout.LayoutReady{layout}:
      {layout_parameters(layout) == parameters : Design.LayoutParameters} & {layout_main(layout) == frame : Design.MainFrame}

def control_assembly(+result: Layout.ControlAllocation, +layout: Design.Layout) ->
  AssemblyClaim(Layout.layout_controls(result, layout), layout_parameters(layout), layout_main(layout)):
  match result:
    case Layout.ControlsUnsupported{required, available}: Unit{}
    case Layout.ControlsReady{controls}:
      Design.Layout{viewport, shell, main, overlays, parameters, previous} = layout
      ({==}, {==})

def shell_main(shell: Design.Shell) -> Design.Box:
  Design.Shell{navigation, main, details} = shell
  main

def DecisionAssembly(+parameters: Design.LayoutParameters, +page: Composition.Page, +settings: +List<Layout.ControlItem>,
  +toggles: +List<Layout.ControlItem>, result: ViewportSpace.Result, +outcome: Layout.Outcome) -> Type:
  match result:
    case ViewportSpace.Unsupported{required, available}: {outcome == Layout.LayoutUnsupported{required, available} : Layout.Outcome}
    case ViewportSpace.Allocated{+shell}:
      AssemblyClaim(outcome, adapted(parameters, shell, settings, toggles),
        Layout.main_frame(adapted(parameters, shell, settings, toggles), Composition.recipe(page), shell_main(shell)))

def outcome_assembly(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  +overlays: +List<UI.Node>, +navigation: V.NavigationPlacement, +page: Composition.Page, +layers: +List<V.Layer>,
  +settings: +List<Layout.ControlItem>, +toggles: +List<Layout.ControlItem>, +result: ViewportSpace.Result) ->
  DecisionAssembly(parameters, page, settings, toggles, result,
    Layout.outcome_with_shell(parameters, viewport, surface, overlays, navigation, page, layers, settings, toggles, result)):
  match result:
    case ViewportSpace.Unsupported{required, available}: {==}
    case ViewportSpace.Allocated{shell}:
      Design.Shell{navigation_value, main, details} = shell
      +effective = adapted(parameters, shell, settings, toggles)
      control_assembly(Layout.shell_controls(effective, shell, settings, Layout.active_toggles(navigation_value, toggles)),
        Layout.layout_with_shell(effective, viewport, surface, overlays, shell, navigation, page, layers))

def SemanticShortage(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  +nodes: +List<Design.Node>) -> Maybe<&2, Shortage>:
  UI.Surface{Core.Scene{view, settings, transfers, preview, code, picker}, base, overlays, scope} = surface
  V.Scene{navigation, main, layers, V.Arrangement{placement}, attention} = view
  decision_shortage(Layout.shell(parameters, viewport, placement, Layout.requested_details(parameters, viewport, placement, overlays)),
    Layout.collect_controls(nodes, True{}), Layout.collect_controls(nodes, False{}))

def semantic_shortage_exact(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  +nodes: +List<Design.Node>) ->
  {outcome_shortage(Layout.present_semantic(parameters, viewport, surface, nodes)) == SemanticShortage(parameters, viewport, surface, nodes) : Maybe<&2, Shortage>}:
  UI.Surface{Core.Scene{+view, settings, transfers, preview, code, picker}, base, +overlays, scope} = surface
  V.Scene{navigation, main, +layers, V.Arrangement{+placement}, attention} = view
  outcome_shortage_exact(parameters, viewport, surface, overlays, placement, V.scene_page(view), layers,
    Layout.collect_controls(nodes, True{}), Layout.collect_controls(nodes, False{}),
    Layout.shell(parameters, viewport, placement, Layout.requested_details(parameters, viewport, placement, overlays)))

def SemanticAssembly(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  +nodes: +List<Design.Node>, outcome: Layout.Outcome) -> Type:
  UI.Surface{Core.Scene{view, settings, transfers, preview, code, picker}, base, overlays, scope} = surface
  V.Scene{navigation, main, layers, V.Arrangement{placement}, attention} = view
  DecisionAssembly(parameters, V.scene_page(view), Layout.collect_controls(nodes, True{}), Layout.collect_controls(nodes, False{}),
    Layout.shell(parameters, viewport, placement, Layout.requested_details(parameters, viewport, placement, overlays)), outcome)

def semantic_assembly(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  +nodes: +List<Design.Node>) -> SemanticAssembly(parameters, viewport, surface, nodes, Layout.present_semantic(parameters, viewport, surface, nodes)):
  UI.Surface{Core.Scene{+view, settings, transfers, preview, code, picker}, base, +overlays, scope} = surface
  V.Scene{navigation, main, +layers, V.Arrangement{+placement}, attention} = view
  outcome_assembly(parameters, viewport, surface, overlays, placement, V.scene_page(view), layers,
    Layout.collect_controls(nodes, True{}), Layout.collect_controls(nodes, False{}),
    Layout.shell(parameters, viewport, placement, Layout.requested_details(parameters, viewport, placement, overlays)))

def PresentShortage(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, presentation: Design.PreparedSurface) -> Maybe<&2, Shortage>:
  Design.PreparedSurface{+prepared, cached_base, cached_overlays} = presentation
  Design.Surface{content, theme, nodes, overlays, active} = prepared
  SemanticShortage(parameters, viewport, Design.semantic_surface(prepared), nodes)

def PresentAssembly(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, presentation: Design.PreparedSurface, outcome: Layout.Outcome) -> Type:
  Design.PreparedSurface{+prepared, cached_base, cached_overlays} = presentation
  Design.Surface{content, theme, nodes, overlays, active} = prepared
  SemanticAssembly(parameters, viewport, Design.semantic_surface(prepared), nodes, outcome)

def present_shortage_exact(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +presentation: Design.PreparedSurface) ->
  {outcome_shortage(Layout.present(parameters, viewport, presentation)) == PresentShortage(parameters, viewport, presentation) : Maybe<&2, Shortage>}:
  Design.PreparedSurface{+prepared, cached_base, cached_overlays} = presentation
  Design.Surface{content, theme, +nodes, overlays, active} = prepared
  semantic_shortage_exact(parameters, viewport, Design.semantic_surface(prepared), nodes)

def present_assembly(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +presentation: Design.PreparedSurface) ->
  PresentAssembly(parameters, viewport, presentation, Layout.present(parameters, viewport, presentation)):
  Design.PreparedSurface{+prepared, cached_base, cached_overlays} = presentation
  Design.Surface{content, theme, +nodes, overlays, active} = prepared
  semantic_assembly(parameters, viewport, Design.semantic_surface(prepared), nodes)

def navigation_capacity_feasible(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, intent: E.NavigationIntent) ->
  {navigation_beside(Layout.capacity(parameters, viewport, intent)) ==
    Nat.is_le(Space.minimum_sequence(~ViewportSpace.ShellPart, ViewportSpace.navigation_slots(parameters), 0n), Layout.viewport_width(viewport)) : Bool}:
  ViewportSpaceLaws.navigation_feasibility(viewport, parameters, intent)

def details_capacity_feasible(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +intent: E.NavigationIntent) ->
  {details_beside(Layout.capacity(parameters, viewport, intent)) == Nat.is_le(Space.minimum_sequence(~ViewportSpace.ShellPart,
    ViewportSpace.regular_slots(parameters, ViewportSpace.placement(viewport, parameters, intent), True{}), 0n), Layout.viewport_width(viewport)) : Bool}:
  ViewportSpaceLaws.details_feasibility(viewport, parameters, intent)

def metrics_minimum(value: Design.InputMetrics) -> Nat:
  Design.InputMetrics{minimum, maximum, line, inset, padding, gap} = value
  minimum

def metrics_maximum(value: Design.InputMetrics) -> Nat:
  Design.InputMetrics{minimum, maximum, line, inset, padding, gap} = value
  maximum

def input_minimum_retained(+parameters: Design.LayoutParameters, canvas: Design.Box) ->
  {metrics_minimum(Layout.input_metrics(parameters, canvas)) == Design.input_minimum_height(parameters) : Nat}:
  match canvas:
    case Design.Box{left, top, width, height}: {==}

def input_maximum_fits_minimum(+parameters: Design.LayoutParameters, canvas: Design.Box) ->
  {Nat.is_ge(metrics_maximum(Layout.input_metrics(parameters, canvas)), Design.input_minimum_height(parameters)) == True{} : Bool}:
  match canvas:
    case Design.Box{left, top, width, height}: Nat.max_ge_l(Design.input_minimum_height(parameters), Nat.min(Design.input_maximum_height(parameters), Nat.div(height, 3n)))

type Requirements is Type:
  Requirements{
    input_minimum: @+parameters:Design.LayoutParameters -> @canvas:Design.Box -> {metrics_minimum(Layout.input_metrics(parameters, canvas)) == Design.input_minimum_height(parameters) : Nat},
    input_maximum: @+parameters:Design.LayoutParameters -> @canvas:Design.Box -> {Nat.is_ge(metrics_maximum(Layout.input_metrics(parameters, canvas)), Design.input_minimum_height(parameters)) == True{} : Bool},
    explicit_main_frame: @+parameters:Design.LayoutParameters -> @recipe:Composition.Recipe -> @main:Design.Box ->
      {Layout.main_frame(parameters, recipe, main) == expected_main_frame(parameters, recipe, main) : Design.MainFrame},
    conversation_dock_band: @+parameters:Design.LayoutParameters -> @main:Design.Box -> @composer:Composition.Composer ->
      @decisions:Composition.Decisions -> @latest:Composition.Latest ->
      {Layout.main_frame(parameters, conversation_recipe(composer, decisions, latest), main) ==
        expected_main_frame(parameters, conversation_recipe(composer, decisions, latest), main) : Design.MainFrame},
    overlay_identity: @+parameters:Design.LayoutParameters -> @+viewport:Design.Viewport -> @overlays:+List<UI.Node> ->
      @layers:+List<V.Layer> -> @+surface:UI.Surface -> @+shell:Design.Shell ->
      @+navigation:V.NavigationPlacement ->
      {Layout.projected_overlays(parameters, viewport, overlays, layers, surface, shell, navigation) ==
        expected_projected_overlays(parameters, viewport, overlays, layers, surface, shell, navigation) : +List<Design.Overlay>},
    empty_conversation_dock: @+parameters:Design.LayoutParameters -> @main:Design.Box ->
      {conversation_has_no_dock(Layout.main_frame(parameters, conversation_recipe(
        Composition.NoComposer{}, Composition.NoDecisions{}, Composition.NoLatest{}), main)) == True{} : Bool},
    approval_only_dock: @+parameters:Design.LayoutParameters -> @main:Design.Box ->
      {conversation_has_approval_only_dock(Layout.main_frame(parameters, conversation_recipe(
        Composition.NoComposer{}, Composition.BeforeComposer{}, Composition.NoLatest{}), main)) == True{} : Bool},
    input_metrics: @+parameters:Design.LayoutParameters -> @canvas:Design.Box ->
      input_metrics_law(parameters, canvas),
    anchor_scope_independence: @+surface:UI.Surface -> @requested:String -> @scope:Maybe<&2, String> ->
      {Layout.anchor(surface, requested) ==
        Layout.anchor(surface_with_scope(surface, scope), requested) : Maybe<&2, String>},
    exact_base_trigger_anchor: @+surface:UI.Surface -> @+trigger:UI.Node -> @scope:Maybe<&2, String> ->
      @found:{UI.find_node(base_nodes_with_trigger(surface, trigger), UI.node_key(trigger)) ==
        Some{trigger} : Maybe<&2, UI.Node>} ->
      {Layout.anchor(surface_with_trigger_in_base(surface, trigger, scope), UI.node_key(trigger)) ==
        Some{UI.node_key(trigger)} : Maybe<&2, String>},
    empty_tree_anchor: @+surface:UI.Surface -> @requested:String -> @scope:Maybe<&2, String> ->
      {Layout.anchor(surface_with_empty_trees(surface, scope), requested) ==
        None{} : Maybe<&2, String>},
    menu_uses_matched_origin: @+parameters:Design.LayoutParameters -> @viewport:Design.Viewport -> @initial_attention:String ->
      @return_attention:String -> @content:V.LayerContent -> @close:V.Dismissal ->
      @+surface:UI.Surface -> @origin:String ->
      @matched:{Layout.anchor(surface, return_attention) == Some{origin} : Maybe<&2, String>} ->
      {Layout.menu_for_layer(parameters, viewport,
        Some{anchored_layer(initial_attention, return_attention, content, close)}, surface) ==
        expected_anchored_menu(parameters, viewport, origin) : Design.OverlayPlacement},
    anchored_menu_prefers_block_space: @+parameters:Design.LayoutParameters -> @+viewport:Design.Viewport -> @+origin:String ->
      anchored_menu_prefers_block_space_law(parameters, viewport, origin),
    compact_creation: @+parameters:Design.LayoutParameters -> @height:Nat -> @below:{Nat.is_lt(height, Design.creation_balanced_minimum_height(parameters)) == True{} : Bool} ->
      {Layout.creation_flow_for_height(parameters, height) == Design.Compact{} : Design.CreationFlow},
    balanced_creation: @+parameters:Design.LayoutParameters -> @height:Nat -> @enough:{Nat.is_lt(height, Design.creation_balanced_minimum_height(parameters)) == False{} : Bool} ->
      {Layout.creation_flow_for_height(parameters, height) == Design.Balanced{} : Design.CreationFlow},
    navigation_capacity_feasible: @+parameters: Design.LayoutParameters -> @+viewport: Design.Viewport -> @intent: E.NavigationIntent ->
      {navigation_beside(Layout.capacity(parameters, viewport, intent)) ==
    Nat.is_le(Space.minimum_sequence(~ViewportSpace.ShellPart, ViewportSpace.navigation_slots(parameters), 0n), Layout.viewport_width(viewport)) : Bool},
    details_capacity_feasible: @+parameters: Design.LayoutParameters -> @+viewport: Design.Viewport -> @+intent: E.NavigationIntent ->
      {details_beside(Layout.capacity(parameters, viewport, intent)) == Nat.is_le(Space.minimum_sequence(~ViewportSpace.ShellPart,
    ViewportSpace.regular_slots(parameters, ViewportSpace.placement(viewport, parameters, intent), True{}), 0n), Layout.viewport_width(viewport)) : Bool},
    carried_parameters: @+parameters: Design.LayoutParameters -> @viewport: Design.Viewport -> @surface: UI.Surface -> @overlays: +List<UI.Node> -> @shell: Design.Shell -> @navigation: V.NavigationPlacement -> @page: Composition.Page -> @layers: +List<V.Layer> ->
      {layout_parameters(Layout.layout_with_shell(parameters, viewport, surface, overlays, shell, navigation, page, layers)) == parameters : Design.LayoutParameters},
    present_feasible: @+parameters:Design.LayoutParameters -> @+viewport:Design.Viewport -> @+presentation:Design.PreparedSurface ->
      {ready(Layout.present(parameters, viewport, presentation)) == PresentFeasibility(parameters, viewport, presentation) : Bool},
    present_shortage: @+parameters:Design.LayoutParameters -> @+viewport:Design.Viewport -> @+presentation:Design.PreparedSurface ->
      {outcome_shortage(Layout.present(parameters, viewport, presentation)) == PresentShortage(parameters, viewport, presentation) : Maybe<&2, Shortage>},
    present_assembly: @+parameters:Design.LayoutParameters -> @+viewport:Design.Viewport -> @+presentation:Design.PreparedSurface ->
      PresentAssembly(parameters, viewport, presentation, Layout.present(parameters, viewport, presentation)),
    present_parameters: @+parameters:Design.LayoutParameters -> @+viewport:Design.Viewport -> @+presentation:Design.PreparedSurface ->
      ParametersClaim(Layout.present(parameters, viewport, presentation), PresentParameters(parameters, viewport, presentation)),
    parameter_update: @+parameters:Design.LayoutParameters -> @+cross:Nat ->
      {Layout.adapt_parameters(parameters, cross) == Design.LayoutParameters{
        Design.navigation_width(parameters), Design.main_minimum_width(parameters), Design.details_width(parameters),
        Design.reading_maximum_width(parameters), Design.overview_maximum_width(parameters), Nat.max(Design.toolbar_height(parameters), cross),
        Design.input_minimum_height(parameters), Design.input_maximum_height(parameters), Design.input_line_height(parameters),
        Design.creation_balanced_minimum_height(parameters)} : Design.LayoutParameters},
    container_allocation: @+leading:+List<Layout.ControlItem> -> @+trailing:+List<Layout.ControlItem> -> @+available:Nat ->
      ContainerLaws.ContainerClaim(~Layout.ControlItem, Layout.control_container(leading, trailing), available,
        Space.pack_container(~Layout.ControlItem, Layout.control_container(leading, trailing), available))
  }





def evidence() -> Requirements:
  Requirements{input_minimum_retained, input_maximum_fits_minimum,
    +parameters => recipe => main => explicit_main_frame(parameters, recipe, main),
    +parameters => main => composer => decisions => latest => explicit_main_frame(parameters, conversation_recipe(composer, decisions, latest), main),
    +parameters => viewport => overlays => layers => surface => shell => navigation =>
      overlay_identity_projection(parameters, viewport, overlays, layers, surface, shell, navigation),
    +parameters => main => {==},
    +parameters => main => {==},
    +parameters => canvas => input_metrics_follow_consistent_bounds(parameters, canvas),
    surface => requested => scope => anchor_is_scope_independent(surface, requested, scope),
    surface => trigger => scope => found => exact_trigger_node_in_base(surface, trigger, scope, found),
    surface => requested => scope => empty_tree_anchor_is_absent(surface, requested, scope),
    +parameters => viewport => initial_attention => return_attention => content => close => +surface => origin => matched =>
      Equal.cong(Maybe<&2, String>, Design.OverlayPlacement,
        resolved => Layout.anchored_menu_placement(parameters, viewport, resolved),
        Layout.anchor(surface, return_attention), Some{origin}, matched),
    +parameters => viewport => origin => anchored_menu_prefers_block_space(parameters, viewport, origin),
    +parameters => height => below => Equal.cong(Bool, Design.CreationFlow, Layout.creation_flow_choice, Nat.is_lt(height, Design.creation_balanced_minimum_height(parameters)), True{}, below),
    +parameters => height => enough => Equal.cong(Bool, Design.CreationFlow, Layout.creation_flow_choice, Nat.is_lt(height, Design.creation_balanced_minimum_height(parameters)), False{}, enough), navigation_capacity_feasible, details_capacity_feasible, carried_parameters, present_feasible, present_shortage_exact, present_assembly, present_parameters, parameter_update,
      +leading => +trailing => +available => ContainerLaws.complete(~Layout.ControlItem, Layout.control_container(leading, trailing), available)}
