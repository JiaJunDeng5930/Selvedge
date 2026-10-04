import Base
import ../../core/ui-world.bend as V
import ../../core/interface.bend as UI
import ../../core/composition.bend as Composition
import ../design.bend as Design
import ../layout.bend as Layout
import ../viewport-space.bend as ViewportSpace
import ../space.bend as Space
import ../../core/SYSTEM.bend as Core
import ../../core/user-experience.bend as E
import ../layout-laws.bend as Rule
import ./control-allocation.bend as AllocationLawsProof
import ./viewport-space.bend as ViewportSpaceLawsProof
import ./container-space.bend as ContainerLawsProof

def explicit_main_frame(+parameters: Design.LayoutParameters, +recipe: Composition.Recipe, +main: Design.Box) ->
  {Layout.main_frame(parameters, recipe, main) == Rule.expected_main_frame(parameters, recipe, main) : Design.MainFrame}:
  match recipe:
    case Composition.Recipe{measure, page_heading, Composition.CenteredCreation{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, page_heading, Composition.ChronologicalReading{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, page_heading, Composition.ProjectSections{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, page_heading, Composition.ProjectRows{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, page_heading, Composition.AgentRows{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, page_heading, Composition.StageColumns{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, page_heading, Composition.UnavailableNotice{}, composer, decisions, latest}: {==}




def anchor_is_scope_independent(+surface: UI.Surface, +requested: String, scope: Maybe<&2, String>) ->
  {Layout.anchor(surface, requested) ==
    Layout.anchor(Rule.surface_with_scope(surface, scope), requested) : Maybe<&2, String>}:
  match surface:
    case UI.Surface{content, +base, +overlays, +previous_scope}: {==}


def exact_trigger_node_in_base(+surface: UI.Surface, +trigger: UI.Node,
  scope: Maybe<&2, String>,
  found: {UI.find_node(Rule.base_nodes_with_trigger(surface, trigger), UI.node_key(trigger)) ==
    Some{trigger} : Maybe<&2, UI.Node>}) ->
  {Layout.anchor(Rule.surface_with_trigger_in_base(surface, trigger, scope), UI.node_key(trigger)) ==
    Some{UI.node_key(trigger)} : Maybe<&2, String>}:
  match surface:
    case UI.Surface{content, +base, +overlays, +previous_scope}:
      match trigger:
        case UI.Node{key, semantic, label, role, meaning, +children}:
          Equal.trans(Maybe<&2, String>,
            Layout.anchor(Rule.surface_with_trigger_in_base(surface, trigger, scope), key),
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


def empty_tree_anchor_is_absent(+surface: UI.Surface, +requested: String, scope: Maybe<&2, String>) ->
  {Layout.anchor(Rule.surface_with_empty_trees(surface, scope), requested) ==
    None{} : Maybe<&2, String>}:
  match surface:
    case UI.Surface{content, +base, +overlays, +previous_scope}: {==}


def anchored_menu_prefers_block_space(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +origin: String) -> Rule.anchored_menu_prefers_block_space_law(parameters, viewport, origin):
  match viewport:
    case Design.Viewport{width, height}: {==}




def overlay_identity_projection(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +overlays: +List<UI.Node>,
  +layers: +List<V.Layer>, +surface: UI.Surface, +shell: Design.Shell,
  +navigation: V.NavigationPlacement) ->
  {Layout.projected_overlays(parameters, viewport, overlays, layers, surface, shell, navigation) ==
    Rule.expected_projected_overlays(parameters, viewport, overlays, layers, surface, shell, navigation) : +List<Design.Overlay>}:
  match overlays:
    case Nil{}: {==}
    case Con{UI.Node{+key, semantic, label, +role, +meaning, +children}, +rest}:
      Equal.cong(+List<Design.Overlay>, +List<Design.Overlay>,
        (tail => Con{Design.Overlay{key, Nat.add(100n, List.length(&2, UI.Node, rest)),
          Layout.overlay_placement(parameters, viewport,
            UI.Node{key, semantic, label, role, meaning, children}, layers, surface, shell, navigation)},
          tail}),
        Layout.projected_overlays(parameters, viewport, rest, layers, surface, shell, navigation),
        Rule.expected_projected_overlays(parameters, viewport, rest, layers, surface, shell, navigation),
        overlay_identity_projection(parameters, viewport, rest, layers, surface, shell, navigation))


def input_metrics_follow_consistent_bounds(+parameters: Design.LayoutParameters, canvas: Design.Box) -> Rule.input_metrics_law(parameters, canvas):
  match canvas:
    case Design.Box{+left, +top, +width, height}: {==}
















def carried_parameters(+parameters: Design.LayoutParameters, viewport: Design.Viewport, surface: UI.Surface,
  overlays: +List<UI.Node>, shell: Design.Shell, navigation: V.NavigationPlacement, page: Composition.Page,
  layers: +List<V.Layer>) ->
  {Rule.layout_parameters(Layout.layout_with_shell(parameters, viewport, surface, overlays, shell, navigation, page, layers)) == parameters : Design.LayoutParameters}:
  Design.Shell{navigation_value, main, details} = shell
  {==}


def ready_shortage(+outcome: Layout.Outcome) -> {Rule.ready(outcome) == Rule.no_shortage(Rule.outcome_shortage(outcome)) : Bool}:
  match outcome:
    case Layout.LayoutReady{layout}: {==}
    case Layout.LayoutUnsupported{required, available}: {==}


def allocated_shortage(allocation: Space.Allocation<Layout.BandItem>, target: Design.Box, band: Nat) ->
  {Rule.control_shortage(Layout.finish_controls(Space.finish(~Layout.BandItem, allocation), target, band)) == None{} : Maybe<&2, Rule.Shortage>}:
  Space.Allocation{placements, unused} = allocation
  {==}


def container_shortage(+fits: Bool, +container: Space.Container<Layout.BandItem>, +available: Nat, +target: Design.Box, band: Nat) ->
  {Rule.control_shortage(Layout.finish_controls(Space.feasible_container(~Layout.BandItem, fits, container, available), target, band)) ==
    Rule.width_shortage(fits, Space.container_required(~Layout.BandItem, container), available) : Maybe<&2, Rule.Shortage>}:
  match fits:
    case False{}: {==}
    case True{}:
      Space.Container{leading, trailing, gap, slots} = container
      allocated_shortage(Space.place_from(~Layout.BandItem, slots, gap, leading, Nat.sub(Nat.sub(available, leading), trailing)), target, band)


def band_shortage_exact(+fits: Bool, +parameters: Design.LayoutParameters, +target: Design.Box,
  +band: Layout.Band, +cross: Nat) ->
  {Rule.control_shortage(Layout.allocate_band_guard(fits, parameters, target, band, cross)) ==
    Rule.band_shortage(fits, target, band, cross) : Maybe<&2, Rule.Shortage>}:
  match fits:
    case False{}:
      Design.Box{left, top, width, height} = target
      {==}
    case True{}:
      Design.Box{left, top, width, height} = target
      Layout.Band{frame, items} = band
      +block = Layout.frame_block(frame)
      container_shortage(Nat.is_le(Space.container_required(~Layout.BandItem, Layout.band_container(band)), width),
        Layout.band_container(band), width, Layout.inner_band_target(target, block),
        Nat.sub(Nat.min(height, Nat.max(Design.toolbar_height(parameters), cross)), Nat.mul(2n, block)))


def target_shortage_exact(+parameters: Design.LayoutParameters, +target: Design.Box, +band: Layout.Band) ->
  {Rule.control_shortage(Layout.allocate_band(parameters, target, band)) == Rule.target_shortage(target, band) : Maybe<&2, Rule.Shortage>}:
  Design.Box{left, top, width, height} = target
  +cross = Layout.band_cross_required(band)
  band_shortage_exact(Nat.is_le(cross, height), parameters, target, band, cross)


def root_shortage_exact(+parameters: Design.LayoutParameters, +shell: Design.Shell,
  +settings: +List<Layout.BandItem>, +toggles: +List<Layout.BandItem>) ->
  {Rule.control_shortage(Layout.shell_controls(parameters, shell, settings, toggles)) == Rule.root_shortage(shell, settings, toggles) : Maybe<&2, Rule.Shortage>}:
  Design.Shell{navigation, main, details} = shell
  match navigation:
    case Design.HiddenNavigation{}: target_shortage_exact(parameters, main, Layout.root_band(toggles, settings))
    case Design.BesideNavigation{box}: target_shortage_exact(parameters, box, Layout.root_band(Nil{}, settings))
    case Design.OverlayNavigation{box}: target_shortage_exact(parameters, box, Layout.root_band(Nil{}, settings))


def append_shortage(+first: Layout.ControlAllocation, +second: Layout.ControlAllocation) ->
  {Rule.control_shortage(Layout.append_allocation(first, second)) == Rule.first_shortage(Rule.control_shortage(first), Rule.control_shortage(second)) : Maybe<&2, Rule.Shortage>}:
  match first second:
    case Layout.ControlsUnsupported{required, available} _: {==}
    case Layout.ControlsReady{placements} Layout.ControlsUnsupported{required, available}: {==}
    case Layout.ControlsReady{first_placements} Layout.ControlsReady{second_placements}: {==}


def finish_heading_shortage(+result: Layout.ControlAllocation, content: Layout.HeadingContent, target: Design.Box) ->
  {Rule.control_shortage(Layout.finish_task_heading(result, content, target)) == Rule.control_shortage(result) : Maybe<&2, Rule.Shortage>}:
  match result:
    case Layout.ControlsUnsupported{required, available}: {==}
    case Layout.ControlsReady{placements}:
      Layout.HeadingContent{title, actions} = content
      {==}


def navigation_shortage_exact(+parameters: Design.LayoutParameters, +navigation: Design.Navigation, +settings: +List<Layout.BandItem>) ->
  {Rule.control_shortage(Layout.task_navigation_controls(parameters, navigation, settings)) == Rule.navigation_shortage(navigation, settings) : Maybe<&2, Rule.Shortage>}:
  match navigation:
    case Design.HiddenNavigation{}: {==}
    case Design.BesideNavigation{box}: target_shortage_exact(parameters, box, Layout.root_band(Nil{}, settings))
    case Design.OverlayNavigation{box}: target_shortage_exact(parameters, box, Layout.root_band(Nil{}, settings))


def task_shortage_exact(+parameters: Design.LayoutParameters, +shell: Design.Shell, +content: Layout.HeadingContent,
  +settings: +List<Layout.BandItem>, +toggles: +List<Layout.BandItem>) ->
  {Rule.control_shortage(Layout.task_page_controls(parameters, shell, content, settings, toggles)) == Rule.task_shortage(parameters, shell, content, settings, toggles) : Maybe<&2, Rule.Shortage>}:
  Design.Shell{+navigation, main, details} = shell
  +target = Layout.heading_box(parameters, main)
  +band = Layout.task_heading_band(navigation, content, settings, toggles)
  +first = Layout.task_navigation_controls(parameters, navigation, settings)
  +second = Layout.finish_task_heading(Layout.allocate_band(parameters, target, band), content, target)
  Equal.trans(Maybe<&2, Rule.Shortage>, Rule.control_shortage(Layout.append_allocation(first, second)),
    Rule.first_shortage(Rule.control_shortage(first), Rule.control_shortage(second)), Rule.task_shortage(parameters, shell, content, settings, toggles),
    append_shortage(first, second),
    Equal.trans(Maybe<&2, Rule.Shortage>, Rule.first_shortage(Rule.control_shortage(first), Rule.control_shortage(second)),
      Rule.first_shortage(Rule.navigation_shortage(navigation, settings), Rule.control_shortage(second)), Rule.task_shortage(parameters, shell, content, settings, toggles),
      Equal.cong(Maybe<&2, Rule.Shortage>, Maybe<&2, Rule.Shortage>, (value => Rule.first_shortage(value, Rule.control_shortage(second))),
        Rule.control_shortage(first), Rule.navigation_shortage(navigation, settings), navigation_shortage_exact(parameters, navigation, settings)),
      Equal.cong(Maybe<&2, Rule.Shortage>, Maybe<&2, Rule.Shortage>, (value => Rule.first_shortage(Rule.navigation_shortage(navigation, settings), value)),
        Rule.control_shortage(second), Rule.target_shortage(target, band),
        Equal.trans(Maybe<&2, Rule.Shortage>, Rule.control_shortage(second), Rule.control_shortage(Layout.allocate_band(parameters, target, band)), Rule.target_shortage(target, band),
          finish_heading_shortage(Layout.allocate_band(parameters, target, band), content, target), target_shortage_exact(parameters, target, band)))))


def page_shortage_exact(+parameters: Design.LayoutParameters, +shell: Design.Shell, +page: Composition.Page, +content: Layout.HeadingContent,
  +settings: +List<Layout.BandItem>, +toggles: +List<Layout.BandItem>) ->
  {Rule.control_shortage(Layout.page_controls(parameters, shell, page, content, settings, toggles)) == Rule.page_shortage(parameters, shell, page, content, settings, toggles) : Maybe<&2, Rule.Shortage>}:
  match page:
    case Composition.Conversation{composer, approvals, latest}: task_shortage_exact(parameters, shell, content, settings, toggles)
    case Composition.Creation{composer}: root_shortage_exact(parameters, shell, settings, toggles)
    case Composition.ProjectOverview{}: root_shortage_exact(parameters, shell, settings, toggles)
    case Composition.ProjectCollection{}: root_shortage_exact(parameters, shell, settings, toggles)
    case Composition.TaskBoard{}: root_shortage_exact(parameters, shell, settings, toggles)
    case Composition.AgentCollection{}: root_shortage_exact(parameters, shell, settings, toggles)
    case Composition.Unavailable{}: root_shortage_exact(parameters, shell, settings, toggles)


def control_shortage_preserved(+result: Layout.ControlAllocation, +layout: Design.Layout) ->
  {Rule.outcome_shortage(Layout.layout_controls(result, layout)) == Rule.control_shortage(result) : Maybe<&2, Rule.Shortage>}:
  match result:
    case Layout.ControlsUnsupported{required, available}: {==}
    case Layout.ControlsReady{controls}:
      Design.Layout{viewport, shell, main, overlays, parameters, previous} = layout
      {==}


def prepare_shortage_exact(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  +overlays: +List<UI.Node>, +shell: Design.Shell, +navigation: V.NavigationPlacement, +page: Composition.Page, +layers: +List<V.Layer>,
  +content: Layout.HeadingContent, +settings: +List<Layout.BandItem>, +toggles: +List<Layout.BandItem>) ->
  {Rule.outcome_shortage(Layout.prepare_shell_controls(parameters, viewport, surface, overlays, shell, navigation, page, layers, content, settings, toggles)) ==
    Rule.page_shortage(Rule.adapted(parameters, shell, page, content, settings, toggles), shell, page, content, settings, Layout.active_toggles(Rule.shell_navigation(shell), toggles)) : Maybe<&2, Rule.Shortage>}:
  Design.Shell{navigation_value, main, details} = shell
  +selected = Layout.active_toggles(navigation_value, toggles)
  +effective = Rule.adapted(parameters, shell, page, content, settings, toggles)
  +controls = Layout.page_controls(effective, shell, page, content, settings, selected)
  Equal.trans(Maybe<&2, Rule.Shortage>, Rule.outcome_shortage(Layout.prepare_shell_controls(parameters, viewport, surface, overlays, shell, navigation, page, layers, content, settings, toggles)), Rule.control_shortage(controls),
    Rule.page_shortage(effective, shell, page, content, settings, selected),
    control_shortage_preserved(controls, Layout.layout_with_shell(effective, viewport, surface, overlays, shell, navigation, page, layers)),
    page_shortage_exact(effective, shell, page, content, settings, selected))


def outcome_shortage_exact(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  +overlays: +List<UI.Node>, +navigation: V.NavigationPlacement, +page: Composition.Page, +layers: +List<V.Layer>,
  +content: Layout.HeadingContent, +settings: +List<Layout.BandItem>, +toggles: +List<Layout.BandItem>, +result: ViewportSpace.Result) ->
  {Rule.outcome_shortage(Layout.outcome_with_shell(parameters, viewport, surface, overlays, navigation, page, layers, content, settings, toggles, result)) ==
    Rule.decision_shortage(parameters, page, content, settings, toggles, result) : Maybe<&2, Rule.Shortage>}:
  match result:
    case ViewportSpace.Unsupported{required, available}: {==}
    case ViewportSpace.Allocated{shell}: prepare_shortage_exact(parameters, viewport, surface, overlays, shell, navigation, page, layers, content, settings, toggles)


def control_assembly(+result: Layout.ControlAllocation, +layout: Design.Layout) ->
  Rule.AssemblyClaim(Layout.layout_controls(result, layout), Rule.layout_parameters(layout), Rule.layout_main(layout)):
  match result:
    case Layout.ControlsUnsupported{required, available}: Unit{}
    case Layout.ControlsReady{controls}:
      Design.Layout{viewport, shell, main, overlays, parameters, previous} = layout
      ({==}, {==})


def outcome_assembly(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  +overlays: +List<UI.Node>, +navigation: V.NavigationPlacement, +page: Composition.Page, +layers: +List<V.Layer>,
  +content: Layout.HeadingContent, +settings: +List<Layout.BandItem>, +toggles: +List<Layout.BandItem>, +result: ViewportSpace.Result) ->
  Rule.DecisionAssembly(parameters, page, content, settings, toggles, result,
    Layout.outcome_with_shell(parameters, viewport, surface, overlays, navigation, page, layers, content, settings, toggles, result)):
  match result:
    case ViewportSpace.Unsupported{required, available}: {==}
    case ViewportSpace.Allocated{shell}:
      Design.Shell{navigation_value, main, details} = shell
      +effective = Rule.adapted(parameters, shell, page, content, settings, toggles)
      control_assembly(Layout.page_controls(effective, shell, page, content, settings, Layout.active_toggles(navigation_value, toggles)),
        Layout.layout_with_shell(effective, viewport, surface, overlays, shell, navigation, page, layers))


def control_parameters(+result: Layout.ControlAllocation, +layout: Design.Layout) ->
  Rule.ParametersClaim(Layout.layout_controls(result, layout), Rule.layout_parameters(layout)):
  match result:
    case Layout.ControlsUnsupported{required, available}: Unit{}
    case Layout.ControlsReady{controls}:
      Design.Layout{viewport, shell, main, overlays, parameters, previous} = layout
      {==}


def outcome_parameters(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  +overlays: +List<UI.Node>, +navigation: V.NavigationPlacement, +page: Composition.Page, +layers: +List<V.Layer>,
  +content: Layout.HeadingContent, +settings: +List<Layout.BandItem>, +toggles: +List<Layout.BandItem>, +result: ViewportSpace.Result) ->
  Rule.ParametersClaim(Layout.outcome_with_shell(parameters, viewport, surface, overlays, navigation, page, layers, content, settings, toggles, result),
    Rule.decision_parameters(parameters, page, content, result, settings, toggles)):
  match result:
    case ViewportSpace.Unsupported{required, available}: Unit{}
    case ViewportSpace.Allocated{shell}:
      Design.Shell{shell_navigation_value, main, details} = shell
      +effective = Rule.adapted(parameters, shell, page, content, settings, toggles)
      control_parameters(Layout.page_controls(effective, shell, page, content, settings, Layout.active_toggles(shell_navigation_value, toggles)),
        Layout.layout_with_shell(effective, viewport, surface, overlays, shell, navigation, page, layers))


def semantic_shortage_exact(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  +nodes: +List<Design.Node>) ->
  {Rule.outcome_shortage(Layout.present_semantic(parameters, viewport, surface, nodes)) == Rule.SemanticShortage(parameters, viewport, surface, nodes) : Maybe<&2, Rule.Shortage>}:
  UI.Surface{Core.Scene{+view, settings, transfers, preview, code, picker}, base, +overlays, scope} = surface
  V.Scene{navigation, main, +layers, V.Arrangement{+placement}, attention} = view
  outcome_shortage_exact(parameters, viewport, surface, overlays, placement, V.scene_page(view), layers, Layout.heading_content(nodes), Layout.collect_controls(nodes, True{}), Layout.collect_controls(nodes, False{}), Layout.shell(parameters, viewport, placement, Layout.requested_details(parameters, viewport, placement, overlays)))


def semantic_assembly(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  +nodes: +List<Design.Node>) -> Rule.SemanticAssembly(parameters, viewport, surface, nodes, Layout.present_semantic(parameters, viewport, surface, nodes)):
  UI.Surface{Core.Scene{+view, settings, transfers, preview, code, picker}, base, +overlays, scope} = surface
  V.Scene{navigation, main, +layers, V.Arrangement{+placement}, attention} = view
  outcome_assembly(parameters, viewport, surface, overlays, placement, V.scene_page(view), layers, Layout.heading_content(nodes), Layout.collect_controls(nodes, True{}), Layout.collect_controls(nodes, False{}), Layout.shell(parameters, viewport, placement, Layout.requested_details(parameters, viewport, placement, overlays)))


def semantic_parameters(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  +nodes: +List<Design.Node>) ->
  Rule.ParametersClaim(Layout.present_semantic(parameters, viewport, surface, nodes), Rule.SemanticParameters(parameters, viewport, surface, nodes)):
  UI.Surface{Core.Scene{+view, settings, transfers, preview, code, picker}, base, +overlays, scope} = surface
  V.Scene{navigation, main, +layers, V.Arrangement{+placement}, attention} = view
  outcome_parameters(parameters, viewport, surface, overlays, placement, V.scene_page(view), layers, Layout.heading_content(nodes), Layout.collect_controls(nodes, True{}), Layout.collect_controls(nodes, False{}), Layout.shell(parameters, viewport, placement, Layout.requested_details(parameters, viewport, placement, overlays)))


def present_shortage_exact(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +presentation: Design.PreparedSurface) ->
  {Rule.outcome_shortage(Layout.present(parameters, viewport, presentation)) == Rule.PresentShortage(parameters, viewport, presentation) : Maybe<&2, Rule.Shortage>}:
  Design.PreparedSurface{+prepared, cached_base, cached_overlays} = presentation
  Design.Surface{content, theme, +nodes, overlays, active} = prepared
  semantic_shortage_exact(parameters, viewport, Design.semantic_surface(prepared), nodes)


def present_parameters(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +presentation: Design.PreparedSurface) ->
  Rule.ParametersClaim(Layout.present(parameters, viewport, presentation), Rule.PresentParameters(parameters, viewport, presentation)):
  Design.PreparedSurface{+prepared, cached_base, cached_overlays} = presentation
  Design.Surface{content, theme, +nodes, overlays, active} = prepared
  semantic_parameters(parameters, viewport, Design.semantic_surface(prepared), nodes)


def present_assembly(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +presentation: Design.PreparedSurface) ->
  Rule.PresentAssembly(parameters, viewport, presentation, Layout.present(parameters, viewport, presentation)):
  Design.PreparedSurface{+prepared, cached_base, cached_overlays} = presentation
  Design.Surface{content, theme, +nodes, overlays, active} = prepared
  semantic_assembly(parameters, viewport, Design.semantic_surface(prepared), nodes)


def present_feasible(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +presentation: Design.PreparedSurface) ->
  {Rule.ready(Layout.present(parameters, viewport, presentation)) == Rule.PresentFeasibility(parameters, viewport, presentation) : Bool}:
  Equal.trans(Bool, Rule.ready(Layout.present(parameters, viewport, presentation)),
    Rule.no_shortage(Rule.outcome_shortage(Layout.present(parameters, viewport, presentation))), Rule.PresentFeasibility(parameters, viewport, presentation),
    ready_shortage(Layout.present(parameters, viewport, presentation)),
    Equal.cong(Maybe<&2, Rule.Shortage>, Bool, Rule.no_shortage,
      Rule.outcome_shortage(Layout.present(parameters, viewport, presentation)), Rule.PresentShortage(parameters, viewport, presentation),
      present_shortage_exact(parameters, viewport, presentation)))


def parameter_update(+parameters: Design.LayoutParameters, +cross: Nat) ->
  {Layout.adapt_parameters(parameters, cross) == Design.LayoutParameters{
    Design.navigation_width(parameters), Design.main_minimum_width(parameters), Design.details_width(parameters),
    Design.reading_maximum_width(parameters), Design.overview_maximum_width(parameters), Nat.max(Design.toolbar_height(parameters), cross),
    Design.input_minimum_height(parameters), Design.input_maximum_height(parameters), Design.input_line_height(parameters),
    Design.creation_balanced_minimum_height(parameters)} : Design.LayoutParameters}:
  Design.LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = parameters
  {==}

# Every refinement instance receives the exact production-built band and target.

def root_bands(+parameters: Design.LayoutParameters, +shell: Design.Shell,
  +settings: +List<Layout.BandItem>, +toggles: +List<Layout.BandItem>) -> Rule.RootBands(parameters, shell, settings, toggles):
  Design.Shell{navigation, main, details} = shell
  match navigation:
    case Design.HiddenNavigation{}: AllocationLawsProof.band_complete(parameters, main, Layout.root_band(toggles, settings))
    case Design.BesideNavigation{box}: AllocationLawsProof.band_complete(parameters, box, Layout.root_band(Nil{}, settings))
    case Design.OverlayNavigation{box}: AllocationLawsProof.band_complete(parameters, box, Layout.root_band(Nil{}, settings))


def navigation_bands(+parameters: Design.LayoutParameters, +navigation: Design.Navigation,
  +settings: +List<Layout.BandItem>) -> Rule.NavigationBands(parameters, navigation, settings):
  match navigation:
    case Design.HiddenNavigation{}: Unit{}
    case Design.BesideNavigation{box}: AllocationLawsProof.band_complete(parameters, box, Layout.root_band(Nil{}, settings))
    case Design.OverlayNavigation{box}: AllocationLawsProof.band_complete(parameters, box, Layout.root_band(Nil{}, settings))


def task_bands(+parameters: Design.LayoutParameters, +shell: Design.Shell, +content: Layout.HeadingContent,
  +settings: +List<Layout.BandItem>, +toggles: +List<Layout.BandItem>) -> Rule.TaskBands(parameters, shell, content, settings, toggles):
  Design.Shell{+navigation, main, details} = shell
  (navigation_bands(parameters, navigation, settings),
    AllocationLawsProof.band_complete(parameters, Layout.heading_box(parameters, main), Layout.task_heading_band(navigation, content, settings, toggles)))


def page_bands(+parameters: Design.LayoutParameters, +shell: Design.Shell, +page: Composition.Page, +content: Layout.HeadingContent,
  +settings: +List<Layout.BandItem>, +toggles: +List<Layout.BandItem>) -> Rule.PageBands(parameters, shell, page, content, settings, toggles):
  match page:
    case Composition.Conversation{composer, approvals, latest}: task_bands(parameters, shell, content, settings, toggles)
    case Composition.Creation{composer}: root_bands(parameters, shell, settings, toggles)
    case Composition.ProjectOverview{}: root_bands(parameters, shell, settings, toggles)
    case Composition.ProjectCollection{}: root_bands(parameters, shell, settings, toggles)
    case Composition.TaskBoard{}: root_bands(parameters, shell, settings, toggles)
    case Composition.AgentCollection{}: root_bands(parameters, shell, settings, toggles)
    case Composition.Unavailable{}: root_bands(parameters, shell, settings, toggles)


def decision_bands(+parameters: Design.LayoutParameters, +page: Composition.Page, +content: Layout.HeadingContent,
  +settings: +List<Layout.BandItem>, +toggles: +List<Layout.BandItem>, +result: ViewportSpace.Result) -> Rule.DecisionBands(parameters, page, content, settings, toggles, result):
  match result:
    case ViewportSpace.Unsupported{required, available}: Unit{}
    case ViewportSpace.Allocated{+shell}:
      page_bands(Rule.adapted(parameters, shell, page, content, settings, toggles), shell, page, content, settings,
        Layout.active_toggles(Rule.shell_navigation(shell), toggles))


def semantic_bands(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface, +nodes: +List<Design.Node>) -> Rule.SemanticBands(parameters, viewport, surface, nodes):
  UI.Surface{Core.Scene{+view, settings, transfers, preview, code, picker}, base, +overlays, scope} = surface
  V.Scene{navigation, main, +layers, V.Arrangement{+placement}, attention} = view
  decision_bands(parameters, V.scene_page(view), Layout.heading_content(nodes), Layout.collect_controls(nodes, True{}), Layout.collect_controls(nodes, False{}),
    Layout.shell(parameters, viewport, placement, Layout.requested_details(parameters, viewport, placement, overlays)))


def present_bands(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +presentation: Design.PreparedSurface) -> Rule.PresentBands(parameters, viewport, presentation):
  Design.PreparedSurface{+prepared, cached_base, cached_overlays} = presentation
  Design.Surface{content, theme, +nodes, overlays, active} = prepared
  semantic_bands(parameters, viewport, Design.semantic_surface(prepared), nodes)


def navigation_capacity_feasible(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, intent: E.NavigationIntent) ->
  {Rule.navigation_beside(Layout.capacity(parameters, viewport, intent)) ==
    Nat.is_le(Space.minimum_sequence(~ViewportSpace.ShellPart, ViewportSpace.navigation_slots(parameters), 0n), Layout.viewport_width(viewport)) : Bool}:
  ViewportSpaceLawsProof.navigation_feasibility(viewport, parameters, intent)


def details_capacity_feasible(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +intent: E.NavigationIntent) ->
  {Rule.details_beside(Layout.capacity(parameters, viewport, intent)) == Nat.is_le(Space.minimum_sequence(~ViewportSpace.ShellPart,
    ViewportSpace.regular_slots(parameters, ViewportSpace.placement(viewport, parameters, intent), True{}), 0n), Layout.viewport_width(viewport)) : Bool}:
  ViewportSpaceLawsProof.details_feasibility(viewport, parameters, intent)


def input_minimum_retained(+parameters: Design.LayoutParameters, canvas: Design.Box) ->
  {Rule.metrics_minimum(Layout.input_metrics(parameters, canvas)) == Design.input_minimum_height(parameters) : Nat}:
  match canvas:
    case Design.Box{left, top, width, height}: {==}


def input_maximum_fits_minimum(+parameters: Design.LayoutParameters, canvas: Design.Box) ->
  {Nat.is_ge(Rule.metrics_maximum(Layout.input_metrics(parameters, canvas)), Design.input_minimum_height(parameters)) == True{} : Bool}:
  match canvas:
    case Design.Box{left, top, width, height}: Nat.max_ge_l(Design.input_minimum_height(parameters), Nat.min(Design.input_maximum_height(parameters), Nat.div(height, 3n)))


def Rule.evidence():
  Rule.Requirements{input_minimum_retained, input_maximum_fits_minimum,
    +parameters => recipe => main => explicit_main_frame(parameters, recipe, main),
    +parameters => main => composer => decisions => latest => explicit_main_frame(parameters, Rule.conversation_recipe(composer, decisions, latest), main),
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
    +parameters => height => enough => Equal.cong(Bool, Design.CreationFlow, Layout.creation_flow_choice, Nat.is_lt(height, Design.creation_balanced_minimum_height(parameters)), False{}, enough), navigation_capacity_feasible, details_capacity_feasible, carried_parameters, present_feasible, present_shortage_exact, present_assembly, present_bands, present_parameters, parameter_update,
      +band => +available => ContainerLawsProof.complete(~Layout.BandItem, Layout.band_container(band), available)}
