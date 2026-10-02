import Base
import ../core/ui-world.bend as V
import ../core/interface.bend as UI
import ../core/composition.bend as Composition
import ./design.bend as Design
import ./layout.bend as Layout
import ./renderer.bend as Render

def conversation_recipe(composer: Composition.Composer, decisions: Composition.Decisions,
  latest: Composition.Latest) -> Composition.Recipe:
  Composition.Recipe{Composition.ReadingMeasure{}, Composition.ConversationHeading{},
    Composition.ChronologicalReading{}, composer, decisions, latest}

def expected_main_frame(+recipe: Composition.Recipe, +main: Design.Box) -> Design.MainFrame:
  match recipe:
    case Composition.Recipe{measure, page_heading, Composition.CenteredCreation{}, composer, decisions, latest}:
      Design.CreationFrame{Layout.heading_box(main), main, Layout.measure_band(measure, main),
        Layout.centered_input(composer, main), Layout.creation_flow(main)}
    case Composition.Recipe{measure, page_heading, Composition.ChronologicalReading{}, composer, decisions, latest}:
      heading = Layout.heading_box(main)
      +body_viewport = Layout.body_box(main)
      +reading = Layout.measure_band(measure, body_viewport)
      Design.ConversationFrame{heading, body_viewport, reading,
        Layout.conversation_dock(Layout.recipe_dock(recipe), body_viewport, reading, composer)}
    case Composition.Recipe{measure, page_heading, Composition.ProjectSections{}, composer, decisions, latest}:
      +body_viewport = main
      Design.OverviewFrame{body_viewport, Layout.measure_band(measure, body_viewport), Composition.ProjectSections{}}
    case Composition.Recipe{measure, page_heading, Composition.ProjectRows{}, composer, decisions, latest}:
      +body_viewport = main
      Design.OverviewFrame{body_viewport, Layout.measure_band(measure, body_viewport), Composition.ProjectRows{}}
    case Composition.Recipe{measure, page_heading, Composition.AgentRows{}, composer, decisions, latest}:
      +body_viewport = main
      Design.OverviewFrame{body_viewport, Layout.measure_band(measure, body_viewport), Composition.AgentRows{}}
    case Composition.Recipe{measure, page_heading, Composition.StageColumns{}, composer, decisions, latest}:
      +body_viewport = main
      Design.BoardFrame{body_viewport, Layout.board_column_width(body_viewport),
        16n, 16n}
    case Composition.Recipe{measure, page_heading, Composition.UnavailableNotice{}, composer, decisions, latest}:
      Design.UnavailableFrame{Layout.heading_box(main), Layout.body_box(main), Layout.measure_band(measure, Layout.body_box(main))}

def explicit_main_frame(+recipe: Composition.Recipe, +main: Design.Box) ->
  {Layout.main_frame(recipe, main) == expected_main_frame(recipe, main) : Design.MainFrame}:
  match recipe:
    case Composition.Recipe{measure, page_heading, Composition.CenteredCreation{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, page_heading, Composition.ChronologicalReading{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, page_heading, Composition.ProjectSections{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, page_heading, Composition.ProjectRows{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, page_heading, Composition.AgentRows{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, page_heading, Composition.StageColumns{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, page_heading, Composition.UnavailableNotice{}, composer, decisions, latest}: {==}

def conversation_band_uses_reading_band(main: Design.Box, composer: Composition.Composer,
  decisions: Composition.Decisions, latest: Composition.Latest) ->
  {Layout.main_frame(conversation_recipe(composer, decisions, latest), main) ==
    expected_main_frame(conversation_recipe(composer, decisions, latest), main) : Design.MainFrame}:
  explicit_main_frame(conversation_recipe(composer, decisions, latest), main)

def expected_navigation_capacity(width: Nat) -> Bool:
  Bool.not(Nat.is_lt(width, Layout.narrow_threshold()))

def expected_details_capacity(width: Nat) -> Bool:
  Bool.not(Nat.is_lt(width, Layout.details_minimum_width()))

def navigation_beside(capacity: V.Capacity) -> Bool:
  V.Capacity{navigation_beside_content, details_beside_timeline} = capacity
  navigation_beside_content

def details_beside(capacity: V.Capacity) -> Bool:
  V.Capacity{navigation_beside_content, details_beside_timeline} = capacity
  details_beside_timeline

def navigation_is_hidden_below_threshold(viewport: Design.Viewport,
  below: {Nat.is_lt(Layout.viewport_width(viewport), Layout.narrow_threshold()) == True{} : Bool}) ->
  {navigation_beside(Layout.capacity(viewport)) == False{} : Bool}:
  Equal.trans(Bool, navigation_beside(Layout.capacity(viewport)),
    Bool.not(Nat.is_lt(Layout.viewport_width(viewport), Layout.narrow_threshold())), False{},
    Equal.cong(V.Capacity, Bool, measured => navigation_beside(measured),
      Layout.capacity(viewport), V.Capacity{
        Bool.not(Nat.is_lt(Layout.viewport_width(viewport), Layout.narrow_threshold())),
        Bool.not(Nat.is_lt(Layout.viewport_width(viewport), Layout.details_minimum_width()))}, {==}),
    Equal.cong(Bool, Bool, value => Bool.not(value),
      Nat.is_lt(Layout.viewport_width(viewport), Layout.narrow_threshold()), True{}, below))

def details_are_hidden_below_threshold(viewport: Design.Viewport,
  below: {Nat.is_lt(Layout.viewport_width(viewport), Layout.details_minimum_width()) == True{} : Bool}) ->
  {details_beside(Layout.capacity(viewport)) == False{} : Bool}:
  Equal.trans(Bool, details_beside(Layout.capacity(viewport)),
    Bool.not(Nat.is_lt(Layout.viewport_width(viewport), Layout.details_minimum_width())), False{},
    Equal.cong(V.Capacity, Bool, measured => details_beside(measured),
      Layout.capacity(viewport), V.Capacity{
        Bool.not(Nat.is_lt(Layout.viewport_width(viewport), Layout.narrow_threshold())),
        Bool.not(Nat.is_lt(Layout.viewport_width(viewport), Layout.details_minimum_width()))}, {==}),
    Equal.cong(Bool, Bool, value => Bool.not(value),
      Nat.is_lt(Layout.viewport_width(viewport), Layout.details_minimum_width()), True{}, below))

def capacity_selects_named_thresholds(viewport: Design.Viewport) ->
  {Layout.capacity(viewport) == V.Capacity{expected_navigation_capacity(Layout.viewport_width(viewport)),
    expected_details_capacity(Layout.viewport_width(viewport))} : V.Capacity}:
  {==}

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

def node_key(node: UI.Node) -> String:
  UI.Node{key, semantic, label, role, meaning, children} = node
  key

def exact_trigger_node_in_base(+surface: UI.Surface, +trigger: UI.Node,
  scope: Maybe<&2, String>,
  found: {UI.find_node(base_nodes_with_trigger(surface, trigger), node_key(trigger)) ==
    Some{trigger} : Maybe<&2, UI.Node>}) ->
  {Layout.anchor(surface_with_trigger_in_base(surface, trigger, scope), node_key(trigger)) ==
    Some{node_key(trigger)} : Maybe<&2, String>}:
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

def expected_anchored_menu(viewport: Design.Viewport, origin: String) -> Design.OverlayPlacement:
  +available = Layout.inset_box(viewport)
  Design.AnchoredPopover{origin, available, Nat.min(320n, Layout.box_width(available)),
    Nat.min(400n, Layout.box_height(available)), 4n}


# The browser evaluates real anchor space; this production projection requires
# all anchored menus to prefer larger block space before fitting a scrollport.
def anchored_menu_prefers_block_space(+viewport: Design.Viewport, +origin: String) ->
  {(Render.attr(Render.overlay_styles(Layout.anchored_menu_placement(viewport, Some{origin})), "position-try-order"),
    Render.attr(Render.overlay_styles(Layout.anchored_menu_placement(viewport, Some{origin})), "position-try-fallbacks")) ==
    ("most-block-size", "flip-block, flip-inline, flip-block flip-inline") : (String & String)}:
  match viewport:
    case Design.Viewport{width, height}: {==}

def menu_uses_resolved_origin(viewport: Design.Viewport, initial_attention: String,
  return_attention: String, content: V.LayerContent, close: V.Dismissal,
  +surface: UI.Surface, origin: String,
  matched: {Layout.anchor(surface, return_attention) == Some{origin} : Maybe<&2, String>}) ->
  {Layout.menu_for_layer(viewport, Some{anchored_layer(initial_attention, return_attention, content, close)}, surface) ==
    expected_anchored_menu(viewport, origin) : Design.OverlayPlacement}:
  Equal.cong(Maybe<&2, String>, Design.OverlayPlacement,
    resolved => Layout.anchored_menu_placement(viewport, resolved),
    Layout.anchor(surface, return_attention), Some{origin}, matched)

def collapsed_navigation_uses_zero_main_offset(+viewport: Design.Viewport) ->
  {Layout.shell(viewport, V.CollapsedNavigation{}, False{}) ==
    Design.Shell{Design.HiddenNavigation{},
      Design.Box{0n, 0n,
        Nat.max(0n, Nat.sub(Nat.sub(Layout.viewport_width(viewport), 0n), 0n)),
        Layout.viewport_height(viewport)}, None{}} : Design.Shell}:
  match viewport:
    case Design.Viewport{width, height}: {==}

def shell_without_details(+viewport: Design.Viewport, navigation: V.NavigationPlacement) -> Design.Shell:
  match navigation:
    case V.LeadingNavigation{}:
      Design.Shell{Design.BesideNavigation{Layout.navigation_bounds(viewport)},
        Design.Box{Layout.navigation_width_for_width(viewport), 0n,
          Nat.max(0n, Nat.sub(Nat.sub(Layout.viewport_width(viewport),
            Layout.navigation_width_for_width(viewport)), 0n)), Layout.viewport_height(viewport)}, None{}}
    case V.ModalNavigation{}:
      Design.Shell{Design.OverlayNavigation{Layout.navigation_bounds(viewport)},
        Design.Box{0n, 0n,
          Nat.max(0n, Nat.sub(Nat.sub(Layout.viewport_width(viewport), 0n), 0n)),
          Layout.viewport_height(viewport)}, None{}}
    case V.CollapsedNavigation{}:
      Design.Shell{Design.HiddenNavigation{},
        Design.Box{0n, 0n,
          Nat.max(0n, Nat.sub(Nat.sub(Layout.viewport_width(viewport), 0n), 0n)),
          Layout.viewport_height(viewport)}, None{}}

def unrequested_details_are_absent(+viewport: Design.Viewport, +navigation: V.NavigationPlacement) ->
  {Layout.shell(viewport, navigation, False{}) == shell_without_details(viewport, navigation) : Design.Shell}:
  match viewport:
    case Design.Viewport{width, height}:
      match navigation:
        case V.LeadingNavigation{}: {==}
        case V.ModalNavigation{}: {==}
        case V.CollapsedNavigation{}: {==}

def expected_projected_overlays(+viewport: Design.Viewport, +overlays: +List<UI.Node>,
  +layers: +List<V.Layer>, +surface: UI.Surface, +shell: Design.Shell,
  +navigation: V.NavigationPlacement) -> +List<Design.Overlay>:
  match overlays:
    case Nil{}: Nil{}
    case Con{UI.Node{key, semantic, label, role, meaning, children}, rest}:
      Con{Design.Overlay{key, Nat.add(100n, List.length(&2, UI.Node, rest)),
        Layout.overlay_placement(viewport, UI.Node{key, semantic, label, role, meaning, children},
          layers, surface, shell, navigation)},
        expected_projected_overlays(viewport, rest, layers, surface, shell, navigation)}

def overlay_identity_projection(+viewport: Design.Viewport, +overlays: +List<UI.Node>,
  +layers: +List<V.Layer>, +surface: UI.Surface, +shell: Design.Shell,
  +navigation: V.NavigationPlacement) ->
  {Layout.projected_overlays(viewport, overlays, layers, surface, shell, navigation) ==
    expected_projected_overlays(viewport, overlays, layers, surface, shell, navigation) : +List<Design.Overlay>}:
  match overlays:
    case Nil{}: {==}
    case Con{UI.Node{+key, semantic, label, +role, +meaning, +children}, +rest}:
      Equal.cong(+List<Design.Overlay>, +List<Design.Overlay>,
        (tail => Con{Design.Overlay{key, Nat.add(100n, List.length(&2, UI.Node, rest)),
          Layout.overlay_placement(viewport,
            UI.Node{key, semantic, label, role, meaning, children}, layers, surface, shell, navigation)},
          tail}),
        Layout.projected_overlays(viewport, rest, layers, surface, shell, navigation),
        expected_projected_overlays(viewport, rest, layers, surface, shell, navigation),
        overlay_identity_projection(viewport, rest, layers, surface, shell, navigation))

def conversation_has_no_dock(frame: Design.MainFrame) -> Bool:
  match frame:
    case Design.ConversationFrame{heading, viewport, reading, None{}}: True{}
    case Design.ConversationFrame{heading, viewport, reading, Some{dock}}: False{}
    case _: False{}

def empty_conversation_omits_dock(main: Design.Box) ->
  {conversation_has_no_dock(Layout.main_frame(conversation_recipe(
    Composition.NoComposer{}, Composition.NoDecisions{}, Composition.NoLatest{}), main)) == True{} : Bool}:
  {==}

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

def approval_without_composer_retains_dock(main: Design.Box) ->
  {conversation_has_approval_only_dock(Layout.main_frame(conversation_recipe(
    Composition.NoComposer{}, Composition.BeforeComposer{}, Composition.NoLatest{}), main)) == True{} : Bool}:
  {==}

def input_metrics_follow_consistent_bounds(canvas: Design.Box) ->
  {Layout.input_metrics(canvas) == Design.InputMetrics{
    Nat.min(44n, Nat.min(240n, Nat.div(Layout.box_height(canvas), 3n))),
    Nat.min(240n, Nat.div(Layout.box_height(canvas), 3n)), 20n, Layout.composer_content_inset(), 4n, 8n} : Design.InputMetrics}:
  match canvas:
    case Design.Box{+left, +top, +width, height}: {==}

def settings_beside(+box: Design.Box, main: Design.Box) ->
  {Layout.settings_bounds(Design.BesideNavigation{box}, main) == Layout.settings_in_navigation(box) : Design.Box}:
  {==}

def settings_overlay(+box: Design.Box, main: Design.Box) ->
  {Layout.settings_bounds(Design.OverlayNavigation{box}, main) == Layout.settings_in_navigation(box) : Design.Box}:
  {==}

def settings_hidden(+main: Design.Box) ->
  {Layout.settings_bounds(Design.HiddenNavigation{}, main) == Layout.settings_in_heading(main) : Design.Box}:
  {==}

def settings_navigation_coordinates(+left: Nat, +top: Nat, +width: Nat, +height: Nat) ->
  {Layout.settings_in_navigation(Design.Box{left, top, width, height}) ==
    Design.Box{Nat.add(left, Nat.min(16n, Nat.sub(width, Nat.min(32n, Nat.min(width, height))))),
      Nat.add(top, Nat.min(Nat.sub(height, 48n), Nat.sub(height, Nat.min(32n, Nat.min(width, height))))),
      Nat.min(32n, Nat.min(width, height)), Nat.min(32n, Nat.min(width, height))} : Design.Box}:
  {==}

def settings_heading_coordinates(+left: Nat, +top: Nat, +width: Nat, +height: Nat) ->
  {Layout.settings_in_heading(Design.Box{left, top, width, height}) ==
    Design.Box{Nat.add(left, Nat.min(Nat.sub(width, 48n), Nat.sub(width, Nat.min(32n, Nat.min(width, height))))),
      Nat.add(top, Nat.min(7n, Nat.sub(height, Nat.min(32n, Nat.min(width, height))))),
      Nat.min(32n, Nat.min(width, height)), Nat.min(32n, Nat.min(width, height))} : Design.Box}:
  {==}

type Requirements is Type:
  Requirements{
    settings_beside: @+box:Design.Box -> @main:Design.Box ->
      {Layout.settings_bounds(Design.BesideNavigation{box}, main) == Layout.settings_in_navigation(box) : Design.Box},
    settings_overlay: @+box:Design.Box -> @main:Design.Box ->
      {Layout.settings_bounds(Design.OverlayNavigation{box}, main) == Layout.settings_in_navigation(box) : Design.Box},
    settings_hidden: @+main:Design.Box ->
      {Layout.settings_bounds(Design.HiddenNavigation{}, main) == Layout.settings_in_heading(main) : Design.Box},
    settings_navigation_coordinates: @+left:Nat -> @+top:Nat -> @+width:Nat -> @+height:Nat ->
      {Layout.settings_in_navigation(Design.Box{left, top, width, height}) ==
        Design.Box{Nat.add(left, Nat.min(16n, Nat.sub(width, Nat.min(32n, Nat.min(width, height))))),
          Nat.add(top, Nat.min(Nat.sub(height, 48n), Nat.sub(height, Nat.min(32n, Nat.min(width, height))))),
          Nat.min(32n, Nat.min(width, height)), Nat.min(32n, Nat.min(width, height))} : Design.Box},
    settings_heading_coordinates: @+left:Nat -> @+top:Nat -> @+width:Nat -> @+height:Nat ->
      {Layout.settings_in_heading(Design.Box{left, top, width, height}) ==
        Design.Box{Nat.add(left, Nat.min(Nat.sub(width, 48n), Nat.sub(width, Nat.min(32n, Nat.min(width, height))))),
          Nat.add(top, Nat.min(7n, Nat.sub(height, Nat.min(32n, Nat.min(width, height))))),
          Nat.min(32n, Nat.min(width, height)), Nat.min(32n, Nat.min(width, height))} : Design.Box},
    explicit_main_frame: @recipe:Composition.Recipe -> @main:Design.Box ->
      {Layout.main_frame(recipe, main) == expected_main_frame(recipe, main) : Design.MainFrame},
    conversation_dock_band: @main:Design.Box -> @composer:Composition.Composer ->
      @decisions:Composition.Decisions -> @latest:Composition.Latest ->
      {Layout.main_frame(conversation_recipe(composer, decisions, latest), main) ==
        expected_main_frame(conversation_recipe(composer, decisions, latest), main) : Design.MainFrame},
    capacity_thresholds: @viewport:Design.Viewport ->
      {Layout.capacity(viewport) == V.Capacity{expected_navigation_capacity(Layout.viewport_width(viewport)),
        expected_details_capacity(Layout.viewport_width(viewport))} : V.Capacity},
    navigation_narrow_capacity: @viewport:Design.Viewport ->
      @below:{Nat.is_lt(Layout.viewport_width(viewport), Layout.narrow_threshold()) == True{} : Bool} ->
      {navigation_beside(Layout.capacity(viewport)) == False{} : Bool},
    details_narrow_capacity: @viewport:Design.Viewport ->
      @below:{Nat.is_lt(Layout.viewport_width(viewport), Layout.details_minimum_width()) == True{} : Bool} ->
      {details_beside(Layout.capacity(viewport)) == False{} : Bool},
    collapsed_navigation_offset: @+viewport:Design.Viewport ->
      {Layout.shell(viewport, V.CollapsedNavigation{}, False{}) ==
        Design.Shell{Design.HiddenNavigation{},
          Design.Box{0n, 0n,
            Nat.max(0n, Nat.sub(Nat.sub(Layout.viewport_width(viewport), 0n), 0n)),
            Layout.viewport_height(viewport)}, None{}} : Design.Shell},
    unrequested_details: @+viewport:Design.Viewport -> @+navigation:V.NavigationPlacement ->
      {Layout.shell(viewport, navigation, False{}) == shell_without_details(viewport, navigation) : Design.Shell},
    overlay_identity: @+viewport:Design.Viewport -> @overlays:+List<UI.Node> ->
      @layers:+List<V.Layer> -> @+surface:UI.Surface -> @+shell:Design.Shell ->
      @+navigation:V.NavigationPlacement ->
      {Layout.projected_overlays(viewport, overlays, layers, surface, shell, navigation) ==
        expected_projected_overlays(viewport, overlays, layers, surface, shell, navigation) : +List<Design.Overlay>},
    empty_conversation_dock: @main:Design.Box ->
      {conversation_has_no_dock(Layout.main_frame(conversation_recipe(
        Composition.NoComposer{}, Composition.NoDecisions{}, Composition.NoLatest{}), main)) == True{} : Bool},
    approval_only_dock: @main:Design.Box ->
      {conversation_has_approval_only_dock(Layout.main_frame(conversation_recipe(
        Composition.NoComposer{}, Composition.BeforeComposer{}, Composition.NoLatest{}), main)) == True{} : Bool},
    input_metrics: @canvas:Design.Box ->
      {Layout.input_metrics(canvas) == Design.InputMetrics{
        Nat.min(44n, Nat.min(240n, Nat.div(Layout.box_height(canvas), 3n))),
        Nat.min(240n, Nat.div(Layout.box_height(canvas), 3n)), 20n, Layout.composer_content_inset(), 4n, 8n} : Design.InputMetrics},
    anchor_scope_independence: @+surface:UI.Surface -> @requested:String -> @scope:Maybe<&2, String> ->
      {Layout.anchor(surface, requested) ==
        Layout.anchor(surface_with_scope(surface, scope), requested) : Maybe<&2, String>},
    exact_base_trigger_anchor: @+surface:UI.Surface -> @+trigger:UI.Node -> @scope:Maybe<&2, String> ->
      @found:{UI.find_node(base_nodes_with_trigger(surface, trigger), node_key(trigger)) ==
        Some{trigger} : Maybe<&2, UI.Node>} ->
      {Layout.anchor(surface_with_trigger_in_base(surface, trigger, scope), node_key(trigger)) ==
        Some{node_key(trigger)} : Maybe<&2, String>},
    empty_tree_anchor: @+surface:UI.Surface -> @requested:String -> @scope:Maybe<&2, String> ->
      {Layout.anchor(surface_with_empty_trees(surface, scope), requested) ==
        None{} : Maybe<&2, String>},
    menu_uses_matched_origin: @viewport:Design.Viewport -> @initial_attention:String ->
      @return_attention:String -> @content:V.LayerContent -> @close:V.Dismissal ->
      @+surface:UI.Surface -> @origin:String ->
      @matched:{Layout.anchor(surface, return_attention) == Some{origin} : Maybe<&2, String>} ->
      {Layout.menu_for_layer(viewport,
        Some{anchored_layer(initial_attention, return_attention, content, close)}, surface) ==
        expected_anchored_menu(viewport, origin) : Design.OverlayPlacement},
    anchored_menu_prefers_block_space: @+viewport:Design.Viewport -> @+origin:String ->
      {(Render.attr(Render.overlay_styles(Layout.anchored_menu_placement(viewport, Some{origin})), "position-try-order"),
        Render.attr(Render.overlay_styles(Layout.anchored_menu_placement(viewport, Some{origin})), "position-try-fallbacks")) ==
        ("most-block-size", "flip-block, flip-inline, flip-block flip-inline") : (String & String)},
    compact_creation: @height:Nat -> @below:{Nat.is_lt(height, 420n) == True{} : Bool} ->
      {Layout.creation_flow_for_height(height) == Design.Compact{} : Design.CreationFlow},
    balanced_creation: @height:Nat -> @enough:{Nat.is_lt(height, 420n) == False{} : Bool} ->
      {Layout.creation_flow_for_height(height) == Design.Balanced{} : Design.CreationFlow}
  }

def compact_creation(height: Nat, below: {Nat.is_lt(height, 420n) == True{} : Bool}) ->
  {Layout.creation_flow_for_height(height) == Design.Compact{} : Design.CreationFlow}:
  Equal.cong(Bool, Design.CreationFlow, Layout.creation_flow_choice, Nat.is_lt(height, 420n), True{}, below)

def balanced_creation(height: Nat, enough: {Nat.is_lt(height, 420n) == False{} : Bool}) ->
  {Layout.creation_flow_for_height(height) == Design.Balanced{} : Design.CreationFlow}:
  Equal.cong(Bool, Design.CreationFlow, Layout.creation_flow_choice, Nat.is_lt(height, 420n), False{}, enough)

def evidence() -> Requirements:
  Requirements{
    box => main => settings_beside(box, main),
    box => main => settings_overlay(box, main),
    main => settings_hidden(main),
    left => top => width => height => settings_navigation_coordinates(left, top, width, height),
    left => top => width => height => settings_heading_coordinates(left, top, width, height),
    recipe => main => explicit_main_frame(recipe, main),
    main => composer => decisions => latest => conversation_band_uses_reading_band(main, composer, decisions, latest),
    viewport => capacity_selects_named_thresholds(viewport),
    viewport => below => navigation_is_hidden_below_threshold(viewport, below),
    viewport => below => details_are_hidden_below_threshold(viewport, below),
    viewport => collapsed_navigation_uses_zero_main_offset(viewport),
    viewport => navigation => unrequested_details_are_absent(viewport, navigation),
    viewport => overlays => layers => surface => shell => navigation =>
      overlay_identity_projection(viewport, overlays, layers, surface, shell, navigation),
    main => empty_conversation_omits_dock(main),
    main => approval_without_composer_retains_dock(main),
    canvas => input_metrics_follow_consistent_bounds(canvas),
    surface => requested => scope => anchor_is_scope_independent(surface, requested, scope),
    surface => trigger => scope => found => exact_trigger_node_in_base(surface, trigger, scope, found),
    surface => requested => scope => empty_tree_anchor_is_absent(surface, requested, scope),
    viewport => initial_attention => return_attention => content => close => surface => origin => matched =>
      menu_uses_resolved_origin(viewport, initial_attention, return_attention, content, close, surface, origin, matched),
    viewport => origin => anchored_menu_prefers_block_space(viewport, origin),
    height => below => compact_creation(height, below),
    height => enough => balanced_creation(height, enough)
  }
