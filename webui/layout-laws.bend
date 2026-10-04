import Base
import ../core/ui-world.bend as V
import ../core/interface.bend as UI
import ../core/composition.bend as Composition
import ./design.bend as Design
import ./layout.bend as Layout
import ./renderer.bend as Render
import ./viewport-space.bend as ViewportSpace
import ./space.bend as Space
import ./container-space-laws.bend as ContainerLaws
import ./control-allocation-laws.bend as AllocationLaws
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


def navigation_beside(capacity: V.Capacity) -> Bool:
  V.Capacity{navigation_beside_content, details_beside_timeline} = capacity
  navigation_beside_content


def details_beside(capacity: V.Capacity) -> Bool:
  V.Capacity{navigation_beside_content, details_beside_timeline} = capacity
  details_beside_timeline








def surface_with_scope(surface: UI.Surface, scope: Maybe<&2, String>) -> UI.Surface:
  UI.Surface{content, +base, +overlays, previous_scope} = surface
  UI.Surface{content, base, overlays, scope}


def surface_with_trigger_in_base(surface: UI.Surface, +trigger: UI.Node,
  scope: Maybe<&2, String>) -> UI.Surface:
  UI.Surface{content, +base, +overlays, previous_scope} = surface
  UI.Surface{content, trigger <> base, overlays, scope}


def base_nodes_with_trigger(+surface: UI.Surface, +trigger: UI.Node) -> +List<UI.Node>:
  UI.Surface{content, +base, +overlays, active_scope} = surface
  trigger <> base




def surface_with_empty_trees(surface: UI.Surface, scope: Maybe<&2, String>) -> UI.Surface:
  UI.Surface{content, base, overlays, previous_scope} = surface
  UI.Surface{content, Nil{}, Nil{}, scope}


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


def ready(value: Layout.Outcome) -> Bool:
  match value:
    case Layout.LayoutReady{layout}: True{}
    case Layout.LayoutUnsupported{required, available}: False{}


def layout_parameters(value: Design.Layout) -> Design.LayoutParameters:
  Design.Layout{viewport, shell, main, overlays, parameters, controls} = value
  parameters


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


def no_shortage(shortage: Maybe<&2, Shortage>) -> Bool:
  match shortage:
    case None{}: True{}
    case Some{value}: False{}


def width_shortage(fits: Bool, required: Nat, available: Nat) -> Maybe<&2, Shortage>:
  match fits:
    case True{}: None{}
    case False{}: Some{Shortage{required, available}}


def band_shortage(fits: Bool, +target: Design.Box, +band: Layout.Band, cross: Nat) -> Maybe<&2, Shortage>:
  match fits:
    case False{}: Some{Shortage{cross, Layout.box_height(target)}}
    case True{}:
      +required = Space.container_required(~Layout.BandItem, Layout.band_container(band))
      width_shortage(Nat.is_le(required, Layout.box_width(target)), required, Layout.box_width(target))


def target_shortage(+target: Design.Box, +band: Layout.Band) -> Maybe<&2, Shortage>:
  +cross = Layout.band_cross_required(band)
  band_shortage(Nat.is_le(cross, Layout.box_height(target)), target, band, cross)


def shell_navigation(shell: Design.Shell) -> Design.Navigation:
  Design.Shell{navigation, main, details} = shell
  navigation


def shell_main(shell: Design.Shell) -> Design.Box:
  Design.Shell{navigation, main, details} = shell
  main


def root_shortage(+shell: Design.Shell, +settings: +List<Layout.BandItem>, +toggles: +List<Layout.BandItem>) -> Maybe<&2, Shortage>:
  Design.Shell{navigation, main, details} = shell
  match navigation:
    case Design.HiddenNavigation{}: target_shortage(main, Layout.root_band(toggles, settings))
    case Design.BesideNavigation{box}: target_shortage(box, Layout.root_band(Nil{}, settings))
    case Design.OverlayNavigation{box}: target_shortage(box, Layout.root_band(Nil{}, settings))


def first_shortage(first: Maybe<&2, Shortage>, second: Maybe<&2, Shortage>) -> Maybe<&2, Shortage>:
  match first:
    case None{}: second
    case Some{value}: Some{value}


def navigation_shortage(+navigation: Design.Navigation, +settings: +List<Layout.BandItem>) -> Maybe<&2, Shortage>:
  match navigation:
    case Design.HiddenNavigation{}: None{}
    case Design.BesideNavigation{box}: target_shortage(box, Layout.root_band(Nil{}, settings))
    case Design.OverlayNavigation{box}: target_shortage(box, Layout.root_band(Nil{}, settings))


def task_shortage(+parameters: Design.LayoutParameters, +shell: Design.Shell, +content: Layout.HeadingContent,
  +settings: +List<Layout.BandItem>, +toggles: +List<Layout.BandItem>) -> Maybe<&2, Shortage>:
  Design.Shell{+navigation, main, details} = shell
  first_shortage(navigation_shortage(navigation, settings),
    target_shortage(Layout.heading_box(parameters, main), Layout.task_heading_band(navigation, content, settings, toggles)))


def page_shortage(+parameters: Design.LayoutParameters, +shell: Design.Shell, page: Composition.Page, +content: Layout.HeadingContent,
  +settings: +List<Layout.BandItem>, +toggles: +List<Layout.BandItem>) -> Maybe<&2, Shortage>:
  match page:
    case Composition.Conversation{composer, approvals, latest}: task_shortage(parameters, shell, content, settings, toggles)
    case _: root_shortage(shell, settings, toggles)


def adapted(+parameters: Design.LayoutParameters, +shell: Design.Shell, +page: Composition.Page, +content: Layout.HeadingContent,
  +settings: +List<Layout.BandItem>, +toggles: +List<Layout.BandItem>) -> Design.LayoutParameters:
  Design.Shell{+navigation, main, details} = shell
  Layout.adapt_parameters(parameters, Layout.page_cross_required(navigation, page, content, settings, Layout.active_toggles(navigation, toggles)))


def decision_shortage(+parameters: Design.LayoutParameters, +page: Composition.Page, +content: Layout.HeadingContent,
  +settings: +List<Layout.BandItem>, +toggles: +List<Layout.BandItem>, result: ViewportSpace.Result) -> Maybe<&2, Shortage>:
  match result:
    case ViewportSpace.Unsupported{required, available}: Some{Shortage{required, available}}
    case ViewportSpace.Allocated{+shell}:
      page_shortage(adapted(parameters, shell, page, content, settings, toggles), shell, page, content, settings, Layout.active_toggles(shell_navigation(shell), toggles))


def layout_main(layout: Design.Layout) -> Design.MainFrame:
  Design.Layout{viewport, shell, main, overlays, parameters, controls} = layout
  main


def AssemblyClaim(outcome: Layout.Outcome, +parameters: Design.LayoutParameters, frame: Design.MainFrame) -> Type:
  match outcome:
    case Layout.LayoutUnsupported{required, available}: Unit
    case Layout.LayoutReady{layout}:
      {layout_parameters(layout) == parameters : Design.LayoutParameters} & {layout_main(layout) == frame : Design.MainFrame}


def DecisionAssembly(+parameters: Design.LayoutParameters, +page: Composition.Page, +content: Layout.HeadingContent, +settings: +List<Layout.BandItem>,
  +toggles: +List<Layout.BandItem>, result: ViewportSpace.Result, +outcome: Layout.Outcome) -> Type:
  match result:
    case ViewportSpace.Unsupported{required, available}: {outcome == Layout.LayoutUnsupported{required, available} : Layout.Outcome}
    case ViewportSpace.Allocated{+shell}:
      AssemblyClaim(outcome, adapted(parameters, shell, page, content, settings, toggles),
        Layout.main_frame(adapted(parameters, shell, page, content, settings, toggles), Composition.recipe(page), shell_main(shell)))


def ParametersClaim(outcome: Layout.Outcome, parameters: Design.LayoutParameters) -> Type:
  match outcome:
    case Layout.LayoutReady{layout}: {layout_parameters(layout) == parameters : Design.LayoutParameters}
    case Layout.LayoutUnsupported{required, available}: Unit


def decision_parameters(+parameters: Design.LayoutParameters, +page: Composition.Page, +content: Layout.HeadingContent, +result: ViewportSpace.Result,
  +settings: +List<Layout.BandItem>, +toggles: +List<Layout.BandItem>) -> Design.LayoutParameters:
  match result:
    case ViewportSpace.Unsupported{required, available}: parameters
    case ViewportSpace.Allocated{shell}: adapted(parameters, shell, page, content, settings, toggles)


def SemanticShortage(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  +nodes: +List<Design.Node>) -> Maybe<&2, Shortage>:
  UI.Surface{Core.Scene{+view, settings, transfers, preview, code, picker}, base, +overlays, scope} = surface
  V.Scene{navigation, main, +layers, V.Arrangement{+placement}, attention} = view
  decision_shortage(parameters, V.scene_page(view), Layout.heading_content(nodes), Layout.collect_controls(nodes, True{}), Layout.collect_controls(nodes, False{}), Layout.shell(parameters, viewport, placement, Layout.requested_details(parameters, viewport, placement, overlays)))


def SemanticAssembly(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  +nodes: +List<Design.Node>, outcome: Layout.Outcome) -> Type:
  UI.Surface{Core.Scene{+view, settings, transfers, preview, code, picker}, base, +overlays, scope} = surface
  V.Scene{navigation, main, +layers, V.Arrangement{+placement}, attention} = view
  DecisionAssembly(parameters, V.scene_page(view), Layout.heading_content(nodes), Layout.collect_controls(nodes, True{}), Layout.collect_controls(nodes, False{}), Layout.shell(parameters, viewport, placement, Layout.requested_details(parameters, viewport, placement, overlays)), outcome)


def SemanticParameters(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  +nodes: +List<Design.Node>) -> Design.LayoutParameters:
  UI.Surface{Core.Scene{+view, settings, transfers, preview, code, picker}, base, +overlays, scope} = surface
  V.Scene{navigation, main, +layers, V.Arrangement{+placement}, attention} = view
  decision_parameters(parameters, V.scene_page(view), Layout.heading_content(nodes), Layout.shell(parameters, viewport, placement, Layout.requested_details(parameters, viewport, placement, overlays)), Layout.collect_controls(nodes, True{}), Layout.collect_controls(nodes, False{}))


def PresentShortage(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, presentation: Design.PreparedSurface) -> Maybe<&2, Shortage>:
  Design.PreparedSurface{+prepared, cached_base, cached_overlays} = presentation
  Design.Surface{content, theme, nodes, overlays, active} = prepared
  SemanticShortage(parameters, viewport, Design.semantic_surface(prepared), nodes)


def PresentParameters(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, presentation: Design.PreparedSurface) -> Design.LayoutParameters:
  Design.PreparedSurface{+prepared, cached_base, cached_overlays} = presentation
  Design.Surface{content, theme, nodes, overlays, active} = prepared
  SemanticParameters(parameters, viewport, Design.semantic_surface(prepared), nodes)


def PresentAssembly(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, presentation: Design.PreparedSurface, outcome: Layout.Outcome) -> Type:
  Design.PreparedSurface{+prepared, cached_base, cached_overlays} = presentation
  Design.Surface{content, theme, nodes, overlays, active} = prepared
  SemanticAssembly(parameters, viewport, Design.semantic_surface(prepared), nodes, outcome)


def PresentFeasibility(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, presentation: Design.PreparedSurface) -> Bool:
  no_shortage(PresentShortage(parameters, viewport, presentation))


def BandEvidence(+parameters: Design.LayoutParameters, +target: Design.Box, +band: Layout.Band) -> Type:
  AllocationLaws.BandClaim(parameters, target, band, Layout.allocate_band(parameters, target, band))


def RootBands(+parameters: Design.LayoutParameters, shell: Design.Shell,
  +settings: +List<Layout.BandItem>, +toggles: +List<Layout.BandItem>) -> Type:
  Design.Shell{navigation, main, details} = shell
  match navigation:
    case Design.HiddenNavigation{}: BandEvidence(parameters, main, Layout.root_band(toggles, settings))
    case Design.BesideNavigation{box}: BandEvidence(parameters, box, Layout.root_band(Nil{}, settings))
    case Design.OverlayNavigation{box}: BandEvidence(parameters, box, Layout.root_band(Nil{}, settings))


def NavigationBands(+parameters: Design.LayoutParameters, navigation: Design.Navigation,
  +settings: +List<Layout.BandItem>) -> Type:
  match navigation:
    case Design.HiddenNavigation{}: Unit
    case Design.BesideNavigation{box}: BandEvidence(parameters, box, Layout.root_band(Nil{}, settings))
    case Design.OverlayNavigation{box}: BandEvidence(parameters, box, Layout.root_band(Nil{}, settings))


def TaskBands(+parameters: Design.LayoutParameters, shell: Design.Shell, +content: Layout.HeadingContent,
  +settings: +List<Layout.BandItem>, +toggles: +List<Layout.BandItem>) -> Type:
  Design.Shell{+navigation, main, details} = shell
  NavigationBands(parameters, navigation, settings) &
    BandEvidence(parameters, Layout.heading_box(parameters, main), Layout.task_heading_band(navigation, content, settings, toggles))


def PageBands(+parameters: Design.LayoutParameters, +shell: Design.Shell, page: Composition.Page, +content: Layout.HeadingContent,
  +settings: +List<Layout.BandItem>, +toggles: +List<Layout.BandItem>) -> Type:
  match page:
    case Composition.Conversation{composer, approvals, latest}: TaskBands(parameters, shell, content, settings, toggles)
    case _: RootBands(parameters, shell, settings, toggles)


def DecisionBands(+parameters: Design.LayoutParameters, +page: Composition.Page, +content: Layout.HeadingContent,
  +settings: +List<Layout.BandItem>, +toggles: +List<Layout.BandItem>, result: ViewportSpace.Result) -> Type:
  match result:
    case ViewportSpace.Unsupported{required, available}: Unit
    case ViewportSpace.Allocated{+shell}:
      PageBands(adapted(parameters, shell, page, content, settings, toggles), shell, page, content, settings,
        Layout.active_toggles(shell_navigation(shell), toggles))


def SemanticBands(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, surface: UI.Surface, +nodes: +List<Design.Node>) -> Type:
  UI.Surface{Core.Scene{+view, settings, transfers, preview, code, picker}, base, +overlays, scope} = surface
  V.Scene{navigation, main, +layers, V.Arrangement{+placement}, attention} = view
  DecisionBands(parameters, V.scene_page(view), Layout.heading_content(nodes), Layout.collect_controls(nodes, True{}), Layout.collect_controls(nodes, False{}),
    Layout.shell(parameters, viewport, placement, Layout.requested_details(parameters, viewport, placement, overlays)))


def PresentBands(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, presentation: Design.PreparedSurface) -> Type:
  Design.PreparedSurface{+prepared, cached_base, cached_overlays} = presentation
  Design.Surface{content, theme, nodes, overlays, active} = prepared
  SemanticBands(parameters, viewport, Design.semantic_surface(prepared), nodes)


def metrics_minimum(value: Design.InputMetrics) -> Nat:
  Design.InputMetrics{minimum, maximum, line, inset, padding, gap} = value
  minimum


def metrics_maximum(value: Design.InputMetrics) -> Nat:
  Design.InputMetrics{minimum, maximum, line, inset, padding, gap} = value
  maximum


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
    present_bands: @+parameters:Design.LayoutParameters -> @+viewport:Design.Viewport -> @+presentation:Design.PreparedSurface ->
      PresentBands(parameters, viewport, presentation),
    present_parameters: @+parameters:Design.LayoutParameters -> @+viewport:Design.Viewport -> @+presentation:Design.PreparedSurface ->
      ParametersClaim(Layout.present(parameters, viewport, presentation), PresentParameters(parameters, viewport, presentation)),
    parameter_update: @+parameters:Design.LayoutParameters -> @+cross:Nat ->
      {Layout.adapt_parameters(parameters, cross) == Design.LayoutParameters{
        Design.navigation_width(parameters), Design.main_minimum_width(parameters), Design.details_width(parameters),
        Design.reading_maximum_width(parameters), Design.overview_maximum_width(parameters), Nat.max(Design.toolbar_height(parameters), cross),
        Design.input_minimum_height(parameters), Design.input_maximum_height(parameters), Design.input_line_height(parameters),
        Design.creation_balanced_minimum_height(parameters)} : Design.LayoutParameters},
    container_allocation: @+band:Layout.Band -> @+available:Nat ->
      ContainerLaws.ContainerClaim(~Layout.BandItem, Layout.band_container(band), available,
        Space.pack_container(~Layout.BandItem, Layout.band_container(band), available))
  }






law evidence:
  Requirements
