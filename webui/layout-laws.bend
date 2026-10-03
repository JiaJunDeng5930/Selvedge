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
import ../bendlib/stdlib.bend as Std
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
      Layout.input_minimum_height(parameters),
      Nat.max(Layout.input_minimum_height(parameters), Nat.min(Layout.input_maximum_height(parameters), Nat.div(Layout.box_height(canvas), 3n))), Layout.input_line_height(parameters), Layout.composer_content_inset(), 4n, 8n} : Design.InputMetrics}

def input_metrics_follow_consistent_bounds(+parameters: Design.LayoutParameters, canvas: Design.Box) -> input_metrics_law(parameters, canvas):
  match canvas:
    case Design.Box{+left, +top, +width, height}: {==}















def ready(value: Layout.Outcome) -> Bool:
  match value:
    case Layout.LayoutReady{layout}: True{}
    case Layout.LayoutUnsupported{required, available}: False{}

def layout_parameters(value: Design.Layout) -> Design.LayoutParameters:
  Design.Layout{viewport, shell, main, overlays, parameters} = value
  parameters

def carried_parameters(+parameters: Design.LayoutParameters, viewport: Design.Viewport, surface: UI.Surface,
  overlays: +List<UI.Node>, shell: Design.Shell, navigation: V.NavigationPlacement, page: Composition.Page,
  layers: +List<V.Layer>) ->
  {layout_parameters(Layout.layout_with_shell(parameters, viewport, surface, overlays, shell, navigation, page, layers)) == parameters : Design.LayoutParameters}:
  Design.Shell{navigation_value, main, details} = shell
  {==}

def allocated_ready(parameters: Design.LayoutParameters, viewport: Design.Viewport, surface: UI.Surface,
  overlays: +List<UI.Node>, shell: Design.Shell, navigation: V.NavigationPlacement, page: Composition.Page,
  layers: +List<V.Layer>) ->
  {ready(Layout.outcome_with_shell(parameters, viewport, surface, overlays, navigation, page, layers,
    ViewportSpace.Allocated{shell})) == True{} : Bool}:
  {==}

def unsupported_preserved(parameters: Design.LayoutParameters, viewport: Design.Viewport, surface: UI.Surface,
  overlays: +List<UI.Node>, navigation: V.NavigationPlacement, page: Composition.Page, layers: +List<V.Layer>,
  +required: Nat, +available: Nat) ->
  {Layout.outcome_with_shell(parameters, viewport, surface, overlays, navigation, page, layers,
    ViewportSpace.Unsupported{required, available}) == Layout.LayoutUnsupported{required, available} : Layout.Outcome}:
  {==}

def packed_ready(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  +overlays: +List<UI.Node>, +navigation: V.NavigationPlacement, +details: Bool, +page: Composition.Page,
  +layers: +List<V.Layer>, +packing: Space.Packing<ViewportSpace.ShellPart>,
  binding: {ViewportSpace.shell_packing(viewport, parameters, navigation, details) == packing : Space.Packing<ViewportSpace.ShellPart>},
  proof: ViewportSpaceLaws.Construction(viewport, parameters, navigation, details, packing)) ->
  {ready(Layout.outcome_with_shell(parameters, viewport, surface, overlays, navigation, page, layers,
    Layout.shell(parameters, viewport, navigation, details))) == True{} : Bool}:
  match packing:
    case Space.Packed{placements, unused}:
      (allocated, bounds) = proof
      Equal.cong(ViewportSpace.Result, Bool,
        (result => ready(Layout.outcome_with_shell(parameters, viewport, surface, overlays, navigation, page, layers, result))),
        Layout.shell(parameters, viewport, navigation, details),
        ViewportSpace.Allocated{ViewportSpace.placed_shell(placements, ViewportSpace.height(viewport), ViewportSpace.empty_shell(viewport, parameters, navigation))}, allocated)
    case Space.Insufficient{required, available}:
      Empty.absurd({ready(Layout.outcome_with_shell(parameters, viewport, surface, overlays, navigation, page, layers,
        Layout.shell(parameters, viewport, navigation, details))) == True{} : Bool}, proof)

def feasible_ready(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  +overlays: +List<UI.Node>, +navigation: V.NavigationPlacement, +details: Bool, +page: Composition.Page,
  +layers: +List<V.Layer>,
  fits: {Nat.is_le(Space.minimum_sequence(~ViewportSpace.ShellPart,
    ViewportSpace.shell_slots(viewport, parameters, navigation, details), 0n), Layout.viewport_width(viewport)) == True{} : Bool}) ->
  {ready(Layout.outcome_with_shell(parameters, viewport, surface, overlays, navigation, page, layers,
    Layout.shell(parameters, viewport, navigation, details))) == True{} : Bool}:
  packed_ready(parameters, viewport, surface, overlays, navigation, details, page, layers,
    ViewportSpace.shell_packing(viewport, parameters, navigation, details), {==},
    ViewportSpaceLaws.feasible_construction(viewport, parameters, navigation, details, fits))

def surface_navigation(surface: UI.Surface) -> V.NavigationPlacement:
  UI.Surface{Core.Scene{V.Scene{navigation, main, layers, V.Arrangement{placement}, attention}, settings, transfers, preview, code, picker}, base, overlays, scope} = surface
  placement

def surface_overlays(surface: UI.Surface) -> +List<UI.Node>:
  UI.Surface{content, base, overlays, scope} = surface
  overlays

def present_feasible(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  fits: {Nat.is_le(Space.minimum_sequence(~ViewportSpace.ShellPart,
    ViewportSpace.shell_slots(viewport, parameters, surface_navigation(surface),
      Layout.requested_details(parameters, viewport, surface_navigation(surface), surface_overlays(surface))), 0n), Layout.viewport_width(viewport)) == True{} : Bool}) ->
  {ready(Layout.present(parameters, viewport, surface)) == True{} : Bool}:
  UI.Surface{Core.Scene{+view, settings, transfers, preview, code, picker}, base, +overlays, scope} = surface
  V.Scene{navigation, main, +layers, V.Arrangement{+placement}, attention} = view
  feasible_ready(parameters, viewport, surface, overlays, placement,
    Layout.requested_details(parameters, viewport, placement, overlays), V.scene_page(view), layers, fits)

def present_unsupported(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface,
  no_room: {Nat.is_le(Space.minimum_sequence(~ViewportSpace.ShellPart,
    ViewportSpace.shell_slots(viewport, parameters, surface_navigation(surface),
      Layout.requested_details(parameters, viewport, surface_navigation(surface), surface_overlays(surface))), 0n), Layout.viewport_width(viewport)) == False{} : Bool}) ->
  {Layout.present(parameters, viewport, surface) == Layout.LayoutUnsupported{
    Space.minimum_sequence(~ViewportSpace.ShellPart, ViewportSpace.shell_slots(viewport, parameters, surface_navigation(surface),
      Layout.requested_details(parameters, viewport, surface_navigation(surface), surface_overlays(surface))), 0n), Layout.viewport_width(viewport)} : Layout.Outcome}:
  UI.Surface{Core.Scene{+view, settings, transfers, preview, code, picker}, base, +overlays, scope} = surface
  V.Scene{navigation, main, +layers, V.Arrangement{+placement}, attention} = view
  +requested = Layout.requested_details(parameters, viewport, placement, overlays)
  Equal.cong(ViewportSpace.Result, Layout.Outcome,
    (result => Layout.outcome_with_shell(parameters, viewport, surface, overlays, placement, V.scene_page(view), layers, result)),
    ViewportSpace.shell(viewport, parameters, placement, requested),
    ViewportSpace.Unsupported{Space.minimum_sequence(~ViewportSpace.ShellPart,
      ViewportSpace.shell_slots(viewport, parameters, placement, requested), 0n), Layout.viewport_width(viewport)},
    ViewportSpaceLaws.unsupported_exact(viewport, parameters, placement, requested, no_room))

def ParametersClaim(outcome: Layout.Outcome, parameters: Design.LayoutParameters) -> Type:
  match outcome:
    case Layout.LayoutReady{layout}: {layout_parameters(layout) == parameters : Design.LayoutParameters}
    case Layout.LayoutUnsupported{required, available}: Unit

def outcome_parameters(+parameters: Design.LayoutParameters, viewport: Design.Viewport, surface: UI.Surface,
  overlays: +List<UI.Node>, navigation: V.NavigationPlacement, page: Composition.Page,
  layers: +List<V.Layer>, result: ViewportSpace.Result) ->
  ParametersClaim(Layout.outcome_with_shell(parameters, viewport, surface, overlays, navigation, page, layers, result), parameters):
  match result:
    case ViewportSpace.Allocated{shell}: carried_parameters(parameters, viewport, surface, overlays, shell, navigation, page, layers)
    case ViewportSpace.Unsupported{required, available}: Unit{}

def present_parameters(+parameters: Design.LayoutParameters, +viewport: Design.Viewport, +surface: UI.Surface) ->
  ParametersClaim(Layout.present(parameters, viewport, surface), parameters):
  UI.Surface{Core.Scene{+view, settings, transfers, preview, code, picker}, base, +overlays, scope} = surface
  V.Scene{navigation, main, +layers, V.Arrangement{+placement}, attention} = view
  outcome_parameters(parameters, viewport, surface, overlays, placement, V.scene_page(view), layers,
    ViewportSpace.shell(viewport, parameters, placement, Layout.requested_details(parameters, viewport, placement, overlays)))

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
  {metrics_minimum(Layout.input_metrics(parameters, canvas)) == Layout.input_minimum_height(parameters) : Nat}:
  match canvas:
    case Design.Box{left, top, width, height}: {==}

def input_maximum_fits_minimum(+parameters: Design.LayoutParameters, canvas: Design.Box) ->
  {Nat.is_ge(metrics_maximum(Layout.input_metrics(parameters, canvas)), Layout.input_minimum_height(parameters)) == True{} : Bool}:
  match canvas:
    case Design.Box{left, top, width, height}: Nat.max_ge_l(Layout.input_minimum_height(parameters), Nat.min(Layout.input_maximum_height(parameters), Nat.div(height, 3n)))

type Requirements is Type:
  Requirements{
    input_minimum: @+parameters:Design.LayoutParameters -> @canvas:Design.Box -> {metrics_minimum(Layout.input_metrics(parameters, canvas)) == Layout.input_minimum_height(parameters) : Nat},
    input_maximum: @+parameters:Design.LayoutParameters -> @canvas:Design.Box -> {Nat.is_ge(metrics_maximum(Layout.input_metrics(parameters, canvas)), Layout.input_minimum_height(parameters)) == True{} : Bool},
    settings_beside: @+parameters:Design.LayoutParameters -> @+box:Design.Box -> @main:Design.Box ->
      {Layout.settings_bounds(parameters, Design.BesideNavigation{box}, main) == Layout.settings_in_navigation(parameters, box) : Design.Box},
    settings_overlay: @+parameters:Design.LayoutParameters -> @+box:Design.Box -> @main:Design.Box ->
      {Layout.settings_bounds(parameters, Design.OverlayNavigation{box}, main) == Layout.settings_in_navigation(parameters, box) : Design.Box},
    settings_hidden: @+parameters:Design.LayoutParameters -> @+main:Design.Box ->
      {Layout.settings_bounds(parameters, Design.HiddenNavigation{}, main) == Layout.settings_in_heading(parameters, main) : Design.Box},
    settings_navigation_coordinates: @+parameters:Design.LayoutParameters -> @+left:Nat -> @+top:Nat -> @+width:Nat -> @+height:Nat ->
      {Layout.settings_in_navigation(parameters, Design.Box{left, top, width, height}) ==
          Design.Box{Nat.add(left, Nat.min(16n, Nat.sub(width, Nat.min(32n, Nat.min(width, height))))),
            Nat.add(top, Nat.min(Nat.sub(height, 48n), Nat.sub(height, Nat.min(32n, Nat.min(width, height))))),
            Nat.min(32n, Nat.min(width, height)), Nat.min(32n, Nat.min(width, height))} : Design.Box},
    settings_heading_coordinates: @+parameters:Design.LayoutParameters -> @+left:Nat -> @+top:Nat -> @+width:Nat -> @+height:Nat ->
      {Layout.settings_in_heading(parameters, Design.Box{left, top, width, height}) ==
          Design.Box{Nat.add(left, Nat.min(Nat.sub(width, 48n), Nat.sub(width, Nat.min(32n, Nat.min(width, height))))),
            Nat.add(top, Nat.min(7n, Nat.sub(height, Nat.min(32n, Nat.min(width, height))))),
            Nat.min(32n, Nat.min(width, height)), Nat.min(32n, Nat.min(width, height))} : Design.Box},
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
    compact_creation: @+parameters:Design.LayoutParameters -> @height:Nat -> @below:{Nat.is_lt(height, Layout.creation_balanced_minimum_height(parameters)) == True{} : Bool} ->
      {Layout.creation_flow_for_height(parameters, height) == Design.Compact{} : Design.CreationFlow},
    balanced_creation: @+parameters:Design.LayoutParameters -> @height:Nat -> @enough:{Nat.is_lt(height, Layout.creation_balanced_minimum_height(parameters)) == False{} : Bool} ->
      {Layout.creation_flow_for_height(parameters, height) == Design.Balanced{} : Design.CreationFlow},
    navigation_capacity_feasible: @+parameters: Design.LayoutParameters -> @+viewport: Design.Viewport -> @intent: E.NavigationIntent ->
      {navigation_beside(Layout.capacity(parameters, viewport, intent)) ==
    Nat.is_le(Space.minimum_sequence(~ViewportSpace.ShellPart, ViewportSpace.navigation_slots(parameters), 0n), Layout.viewport_width(viewport)) : Bool},
    details_capacity_feasible: @+parameters: Design.LayoutParameters -> @+viewport: Design.Viewport -> @+intent: E.NavigationIntent ->
      {details_beside(Layout.capacity(parameters, viewport, intent)) == Nat.is_le(Space.minimum_sequence(~ViewportSpace.ShellPart,
    ViewportSpace.regular_slots(parameters, ViewportSpace.placement(viewport, parameters, intent), True{}), 0n), Layout.viewport_width(viewport)) : Bool},
    carried_parameters: @+parameters: Design.LayoutParameters -> @viewport: Design.Viewport -> @surface: UI.Surface -> @overlays: +List<UI.Node> -> @shell: Design.Shell -> @navigation: V.NavigationPlacement -> @page: Composition.Page -> @layers: +List<V.Layer> ->
      {layout_parameters(Layout.layout_with_shell(parameters, viewport, surface, overlays, shell, navigation, page, layers)) == parameters : Design.LayoutParameters},
    present_feasible: @+parameters: Design.LayoutParameters -> @+viewport: Design.Viewport -> @+surface: UI.Surface -> @fits: {Nat.is_le(Space.minimum_sequence(~ViewportSpace.ShellPart,
    ViewportSpace.shell_slots(viewport, parameters, surface_navigation(surface),
      Layout.requested_details(parameters, viewport, surface_navigation(surface), surface_overlays(surface))), 0n), Layout.viewport_width(viewport)) == True{} : Bool} ->
      {ready(Layout.present(parameters, viewport, surface)) == True{} : Bool},
    present_unsupported: @+parameters: Design.LayoutParameters -> @+viewport: Design.Viewport -> @+surface: UI.Surface -> @no_room: {Nat.is_le(Space.minimum_sequence(~ViewportSpace.ShellPart,
    ViewportSpace.shell_slots(viewport, parameters, surface_navigation(surface),
      Layout.requested_details(parameters, viewport, surface_navigation(surface), surface_overlays(surface))), 0n), Layout.viewport_width(viewport)) == False{} : Bool} ->
      {Layout.present(parameters, viewport, surface) == Layout.LayoutUnsupported{
    Space.minimum_sequence(~ViewportSpace.ShellPart, ViewportSpace.shell_slots(viewport, parameters, surface_navigation(surface),
      Layout.requested_details(parameters, viewport, surface_navigation(surface), surface_overlays(surface))), 0n), Layout.viewport_width(viewport)} : Layout.Outcome},
    present_parameters: @+parameters: Design.LayoutParameters -> @+viewport: Design.Viewport -> @+surface: UI.Surface ->
      ParametersClaim(Layout.present(parameters, viewport, surface), parameters)
  }





def evidence() -> Requirements:
  Requirements{input_minimum_retained, input_maximum_fits_minimum,
    +parameters => +box => main => {==},
    +parameters => +box => main => {==},
    +parameters => +main => {==},
    +parameters => +left => +top => +width => +height => {==},
    +parameters => +left => +top => +width => +height => {==},
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
    +parameters => height => below => Equal.cong(Bool, Design.CreationFlow, Layout.creation_flow_choice, Nat.is_lt(height, Layout.creation_balanced_minimum_height(parameters)), True{}, below),
    +parameters => height => enough => Equal.cong(Bool, Design.CreationFlow, Layout.creation_flow_choice, Nat.is_lt(height, Layout.creation_balanced_minimum_height(parameters)), False{}, enough), navigation_capacity_feasible, details_capacity_feasible, carried_parameters, present_feasible, present_unsupported, present_parameters}
