import Base
import ../core/interface.bend as UI
import ../core/SYSTEM.bend as Core
import ../core/ui-world.bend as View
import ../core/user-experience.bend as Experience
import ../core/user-input.bend as User
import ../bendlib/stdlib.bend as Std
import ../core/composition.bend as Composition
import ./design.bend as Design
import ./document.bend as Doc
import ./layout.bend as Layout
import ./renderer.bend as Render
import ./appearance.bend as Appearance
import ./controls.bend as Controls

def frame_canvas(frame: Design.MainFrame) -> Design.Box:
  match frame:
    case Design.CreationFrame{heading, canvas, band, input, flow}: canvas
    case Design.OverviewFrame{canvas, band, organization}: canvas
    case Design.BoardFrame{canvas, width, gap, inset}: canvas
    case Design.ConversationFrame{heading, viewport, reading, dock}: viewport
    case Design.UnavailableFrame{heading, canvas, band}: canvas

def inline_canvas(+main: Design.Box, +body: Composition.Body) -> Design.Box:
  frame_canvas(Layout.main_frame(Composition.Recipe{Composition.ReadingMeasure{}, Composition.NoHeading{}, body,
    Composition.NoComposer{}, Composition.NoDecisions{}, Composition.NoLatest{}}, main))

def creation_owns_main(main: Design.Box) -> {inline_canvas(main, Composition.CenteredCreation{}) == main : Design.Box}:
  {==}

def sections_own_main(main: Design.Box) -> {inline_canvas(main, Composition.ProjectSections{}) == main : Design.Box}:
  {==}

def projects_own_main(main: Design.Box) -> {inline_canvas(main, Composition.ProjectRows{}) == main : Design.Box}:
  {==}

def agents_own_main(main: Design.Box) -> {inline_canvas(main, Composition.AgentRows{}) == main : Design.Box}:
  {==}

def board_owns_main(main: Design.Box) -> {inline_canvas(main, Composition.StageColumns{}) == main : Design.Box}:
  {==}

def prepend_recombines(+child: Doc.Node, parts: Render.CreationParts) ->
  {Render.creation_recombine(Render.creation_prepend(child, parts)) == child <> Render.creation_recombine(parts) : +List<Doc.Node>}:
  match parts:
    case Render.CreationParts{hero, footer}: {==}

def partition_step_recombines(starts: Bool, +child: Doc.Node, +rest: +List<Doc.Node>,
  correct: {Render.creation_recombine(Render.creation_partition(rest)) == rest : +List<Doc.Node>}) ->
  {Render.creation_recombine(Render.creation_partition_step(starts, child, rest, Render.creation_partition(rest))) == child <> rest : +List<Doc.Node>}:
  match starts:
    case True{}: {==}
    case False{}:
      Equal.trans(+List<Doc.Node>,
        Render.creation_recombine(Render.creation_prepend(child, Render.creation_partition(rest))),
        child <> Render.creation_recombine(Render.creation_partition(rest)), child <> rest,
        prepend_recombines(child, Render.creation_partition(rest)),
        Equal.cong(+List<Doc.Node>, +List<Doc.Node>, (tail => child <> tail),
          Render.creation_recombine(Render.creation_partition(rest)), rest, correct))

def creation_partition_order(children: +List<Doc.Node>) ->
  {Render.creation_recombine(Render.creation_partition(children)) == children : +List<Doc.Node>}:
  match children:
    case Nil{}: {==}
    case Con{+child, +rest}:
      partition_step_recombines(Render.creation_footer_start(child), child, rest, creation_partition_order(rest))



def creation_region_children(values: +List<Doc.Node>) -> +List<Doc.Node>:
  match values:
    case Con{hero, Con{footer, Nil{}}}: List.append(&2, Doc.Node, Doc.element_children(hero), Doc.element_children(footer))
    case _: Nil{}

def regions_recombine(+band: Design.Band, flow: Design.CreationFlow, parts: Render.CreationParts) ->
  {creation_region_children(Render.creation_regions(band, flow, parts)) == Render.creation_recombine(parts) : +List<Doc.Node>}:
  match parts:
    case Render.CreationParts{hero, footer}: {==}

def creation_regions_keep_order(+children: +List<Doc.Node>, +band: Design.Band, +flow: Design.CreationFlow) ->
  {creation_region_children(Render.creation_regions(band, flow, Render.creation_partition(children))) == children : +List<Doc.Node>}:
  Equal.trans(+List<Doc.Node>, creation_region_children(Render.creation_regions(band, flow, Render.creation_partition(children))),
    Render.creation_recombine(Render.creation_partition(children)), children,
    regions_recombine(band, flow, Render.creation_partition(children)), creation_partition_order(children))

def node_key(node: Doc.Node) -> String:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: key
    case Doc.Markdown{key, source, value}: key
    case Doc.Text{value}: ""
    case Doc.Portal{key, target, children}: key
    case Doc.TargetProperties{key, target, attrs, styles}: key


def creation_keys_law(-children: +List<Doc.Node>, -band: Design.Band, -flow: Design.CreationFlow) -> Type:
  {Std.map(~Doc.Node, ~String, ~node_key,
      creation_region_children(Render.creation_regions(band, flow, Render.creation_partition(children)))) ==
      Std.map(~Doc.Node, ~String, ~node_key, children) : +List<String>}

def creation_keys_keep_order(+children: +List<Doc.Node>, +band: Design.Band, +flow: Design.CreationFlow) -> creation_keys_law(children, band, flow):
  Equal.cong(+List<Doc.Node>, +List<String>,
    (values => Std.map(~Doc.Node, ~String, ~node_key, values)),
    creation_region_children(Render.creation_regions(band, flow, Render.creation_partition(children))), children,
    creation_regions_keep_order(children, band, flow))

def semantic_partition_law(-owner: String, -introduction: +List<Doc.Node>, -context: +List<Doc.Node>, -composer: +List<Doc.Node>) -> Type:
  {Render.creation_partition([
      Render.page_region(owner ++ "/intro", Composition.CreationIntroduction{}, Composition.BodyPosition{}, introduction),
      Render.page_region(owner ++ "/context", Composition.CreationContext{}, Composition.BodyPosition{}, context),
      Render.page_region(owner ++ "/input", Composition.ComposerInput{}, Composition.BodyPosition{}, composer)]) ==
      Render.CreationParts{
        [Render.page_region(owner ++ "/intro", Composition.CreationIntroduction{}, Composition.BodyPosition{}, introduction)],
        [Render.page_region(owner ++ "/context", Composition.CreationContext{}, Composition.BodyPosition{}, context),
         Render.page_region(owner ++ "/input", Composition.ComposerInput{}, Composition.BodyPosition{}, composer)]} : Render.CreationParts}

def creation_semantic_split(+owner: String, introduction: +List<Doc.Node>, context: +List<Doc.Node>, composer: +List<Doc.Node>) -> semantic_partition_law(owner, introduction, context, composer):
  {==}

def input_inset(metrics: Design.InputMetrics) -> Nat:
  Design.InputMetrics{minimum, maximum, line_height, inline, gap, footer} = metrics
  inline

def shared_composer_inset(canvas: Design.Box) ->
  {input_inset(Layout.input_metrics(canvas)) == Appearance.face_padding(Controls.TextFace{""}) : Nat}:
  match canvas:
    case Design.Box{left, top, width, height}: {==}

def title_node_identity(+key: String, +tag: String, +attrs: +List<Doc.Property>, +styles: +List<Doc.Property>,
  +events: +List<Doc.Event>, +children: +List<Doc.Node>) ->
  {Render.conversation_title_node(Doc.Element{key, tag, attrs, styles, events, children}) ==
    Doc.Element{key, tag, attrs, List.append(&2, Doc.Property, styles, Render.conversation_title_styles()), events, children} : Doc.Node}:
  {==}

def title_properties_law() -> Type:
  {Render.conversation_title_styles() == [Doc.Property{"display", "block"}, Doc.Property{"min-height", "0"}, Doc.Property{"min-width", "0"}, Doc.Property{"width", "100%"},
      Doc.Property{"overflow", "hidden"}, Doc.Property{"text-overflow", "ellipsis"}, Doc.Property{"white-space", "nowrap"}] : +List<Doc.Property>}

def conversation_title_properties() -> title_properties_law():
  {==}

def conversation_title_remaining_width() ->
  {Render.page_region_styles(Composition.ConversationTitle{}) == [Doc.Property{"display", "flex"},
    Doc.Property{"flex-direction", "column"}, Doc.Property{"flex", "1"}, Doc.Property{"min-width", "0"}] : +List<Doc.Property>}:
  {==}

def creation_group_order(+values: +List<Doc.Node>, +band: Design.Band, +flow: Design.CreationFlow) ->
  {creation_region_children(Doc.element_children(Render.creation_group(band, flow, values))) == values : +List<Doc.Node>}:
  creation_regions_keep_order(values, band, flow)

def first(values: +List<Doc.Node>) -> Doc.Node:
  match values:
    case Con{value, rest}: value
    case Nil{}: Doc.Text{""}

def second(values: +List<Doc.Node>) -> Doc.Node:
  match values:
    case Con{value, rest}: first(rest)
    case Nil{}: Doc.Text{""}



def creation_canvas_children(node: Doc.Node) -> +List<Doc.Node>:
  creation_region_children(Doc.element_children(first(Doc.element_children(node))))

def intrinsic_regions_law(-band: Design.Band, -flow: Design.CreationFlow, -parts: Render.CreationParts) -> Type:
  {(Render.attr(Doc.element_styles(first(Render.creation_regions(band, flow, parts))), "flex"),
      Render.attr(Doc.element_styles(second(Render.creation_regions(band, flow, parts))), "flex")) ==
     ("0 0 auto", "0 0 auto") : (String & String)}

def creation_intrinsic_regions(+band: Design.Band, +flow: Design.CreationFlow, +parts: Render.CreationParts) -> intrinsic_regions_law(band, flow, parts):
  match band flow parts:
    case Design.Band{left, width} Design.Balanced{} Render.CreationParts{hero, footer}: {==}
    case Design.Band{left, width} Design.Compact{} Render.CreationParts{hero, footer}: {==}

def creation_group_growth(band: Design.Band, flow: Design.CreationFlow) ->
  {Render.attr(Render.creation_group_styles(band, flow), "flex") == "0 0 auto" : String}:
  match band flow:
    case Design.Band{left, width} Design.Balanced{}: {==}
    case Design.Band{left, width} Design.Compact{}: {==}

def center_owner_law(-band: Design.Band) -> Type:
  {(Render.attr(Render.creation_group_styles(band, Design.Balanced{}), "margin-block"),
      (Render.attr(Render.creation_group_styles(band, Design.Compact{}), "margin-block"),
       Render.attr(Render.page_region_styles(Composition.CreationIntroduction{}), "justify-content"))) ==
     ("auto", ("0", "center")) : (String & (String & String))}

def creation_center_owner(+band: Design.Band) -> center_owner_law(band):
  match band:
    case Design.Band{left, width}: {==}

def canvas_geometry_law(-canvas: Design.Box, -band: Design.Band, -flow: Design.CreationFlow, -values: +List<Doc.Node>) -> Type:
  {(Render.attr(Doc.element_styles(first(Render.creation_canvas_nodes(canvas, band, flow, values))), "align-items"),
      (Render.attr(Doc.element_styles(first(Render.creation_canvas_nodes(canvas, band, flow, values))), "overflow-y"),
       Render.attr(Doc.element_styles(first(Render.creation_canvas_nodes(canvas, band, flow, values))), "padding-block"))) ==
     ("center", ("auto", "24px")) : (String & (String & String))}

def creation_canvas_geometry(+canvas: Design.Box, +band: Design.Band, +flow: Design.CreationFlow, +values: +List<Doc.Node>) -> canvas_geometry_law(canvas, band, flow, values):
  match canvas band flow:
    case Design.Box{left, top, width, height} Design.Band{band_left, band_width} Design.Balanced{}: {==}
    case Design.Box{left, top, width, height} Design.Band{band_left, band_width} Design.Compact{}: {==}

def navigation_toggle_geometry_law(-navigation: Design.Navigation, -left: Nat, -top: Nat, -width: Nat, -height: Nat, -details: Maybe<&2, Design.Box>) -> Type:
  {Layout.navigation_toggle_bounds(Design.Shell{navigation, Design.Box{left, top, width, height}, details}) ==
      Design.Box{Nat.add(left, Nat.min(8n, Nat.sub(width, Nat.min(32n, Nat.min(width, height))))),
        Nat.add(top, Nat.min(7n, Nat.sub(height, Nat.min(32n, Nat.min(width, height))))),
        Nat.min(32n, Nat.min(width, height)), Nat.min(32n, Nat.min(width, height))} : Design.Box}

def navigation_toggle_geometry(+navigation: Design.Navigation, +left: Nat, +top: Nat, +width: Nat, +height: Nat,
  +details: Maybe<&2, Design.Box>) -> navigation_toggle_geometry_law(navigation, left, top, width, height, details):
  {==}

def reopening_rendered_law(-role: UI.Role, -expanded: Bool, -availability: View.Availability, -node: Doc.Node, -main: Design.Box, -details: Maybe<&2, Design.Box>) -> Type:
  {Render.render_base(role, UI.Activate{Core.ApplicationInput{Experience.UserInput{User.SetNavigation{expanded}}}, availability},
      node, Design.HiddenNavigation{}, main, details) ==
      Render.replace_styles(node, List.append(&2, Doc.Property,
        Render.bounds(Layout.navigation_toggle_bounds(Design.Shell{Design.HiddenNavigation{}, main, details})), [Doc.Property{"z-index", "6"}])) : Doc.Node}

def reopening_rendered(+role: UI.Role, expanded: Bool, availability: View.Availability,
  +node: Doc.Node, +main: Design.Box, +details: Maybe<&2, Design.Box>) -> reopening_rendered_law(role, expanded, availability, node, main, details):
  {==}



def reopening_events(role: UI.Role, expanded: Bool, availability: View.Availability,
  +node: Doc.Node, main: Design.Box, details: Maybe<&2, Design.Box>) ->
  {Doc.element_events(Render.render_base(role, UI.Activate{Core.ApplicationInput{Experience.UserInput{User.SetNavigation{expanded}}}, availability},
    node, Design.HiddenNavigation{}, main, details)) == Doc.element_events(node) : +List<Doc.Event>}:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: {==}
    case Doc.Text{text}: {==}
    case Doc.Markdown{key, source, text}: {==}
    case Doc.Portal{key, target, children}: {==}
    case Doc.TargetProperties{key, target, attrs, styles}: {==}

type Requirements is Type:
  Requirements{
    navigation_toggle_geometry: @+navigation: Design.Navigation -> @+left: Nat -> @+top: Nat -> @+width: Nat -> @+height: Nat -> @+details: Maybe<&2, Design.Box> -> navigation_toggle_geometry_law(navigation, left, top, width, height, details),
    reopening_rendered: @+role: UI.Role -> @expanded: Bool -> @availability: View.Availability -> @+node: Doc.Node -> @+main: Design.Box -> @+details: Maybe<&2, Design.Box> -> reopening_rendered_law(role, expanded, availability, node, main, details),
    reopening_events: @role: UI.Role -> @expanded: Bool -> @availability: View.Availability -> @+node: Doc.Node -> @main: Design.Box -> @details: Maybe<&2, Design.Box> -> {Doc.element_events(Render.render_base(role, UI.Activate{Core.ApplicationInput{Experience.UserInput{User.SetNavigation{expanded}}}, availability},
    node, Design.HiddenNavigation{}, main, details)) == Doc.element_events(node) : +List<Doc.Event>},
    creation_canvas: @main:Design.Box -> {inline_canvas(main, Composition.CenteredCreation{}) == main : Design.Box},
    section_canvas: @main:Design.Box -> {inline_canvas(main, Composition.ProjectSections{}) == main : Design.Box},
    project_canvas: @main:Design.Box -> {inline_canvas(main, Composition.ProjectRows{}) == main : Design.Box},
    agent_canvas: @main:Design.Box -> {inline_canvas(main, Composition.AgentRows{}) == main : Design.Box},
    board_canvas: @main:Design.Box -> {inline_canvas(main, Composition.StageColumns{}) == main : Design.Box},
    creation_order: @+values:+List<Doc.Node> -> @+band:Design.Band -> @+flow:Design.CreationFlow ->
      {creation_region_children(Render.creation_regions(band, flow, Render.creation_partition(values))) == values : +List<Doc.Node>},
    creation_keys: @+values:+List<Doc.Node> -> @+band:Design.Band -> @+flow:Design.CreationFlow ->
      creation_keys_law(values, band, flow),
    semantic_partition: @+owner:String -> @introduction:+List<Doc.Node> -> @context:+List<Doc.Node> -> @composer:+List<Doc.Node> ->
      semantic_partition_law(owner, introduction, context, composer),
    shared_inset: @canvas:Design.Box -> {input_inset(Layout.input_metrics(canvas)) == Appearance.face_padding(Controls.TextFace{""}) : Nat},
    title_identity: @+key:String -> @+tag:String -> @+attrs:+List<Doc.Property> -> @+styles:+List<Doc.Property> -> @+events:+List<Doc.Event> -> @+values:+List<Doc.Node> ->
      {Render.conversation_title_node(Doc.Element{key, tag, attrs, styles, events, values}) ==
        Doc.Element{key, tag, attrs, List.append(&2, Doc.Property, styles, Render.conversation_title_styles()), events, values} : Doc.Node},
    title_properties: title_properties_law(),
    title_remaining_width: {Render.page_region_styles(Composition.ConversationTitle{}) == [Doc.Property{"display", "flex"},
      Doc.Property{"flex-direction", "column"}, Doc.Property{"flex", "1"}, Doc.Property{"min-width", "0"}] : +List<Doc.Property>},
    group_order: @+values:+List<Doc.Node> -> @+band:Design.Band -> @+flow:Design.CreationFlow ->
      {creation_region_children(Doc.element_children(Render.creation_group(band, flow, values))) == values : +List<Doc.Node>},
    intrinsic_regions: @+band:Design.Band -> @+flow:Design.CreationFlow -> @+parts:Render.CreationParts ->
      intrinsic_regions_law(band, flow, parts),
    group_growth: @band:Design.Band -> @flow:Design.CreationFlow ->
      {Render.attr(Render.creation_group_styles(band, flow), "flex") == "0 0 auto" : String},
    center_owner: @+band:Design.Band ->
      center_owner_law(band),
    canvas_geometry: @+canvas:Design.Box -> @+band:Design.Band -> @+flow:Design.CreationFlow -> @+values:+List<Doc.Node> ->
      canvas_geometry_law(canvas, band, flow, values)}

def evidence() -> Requirements:
  Requirements{navigation_toggle_geometry, reopening_rendered, reopening_events, main => creation_owns_main(main), main => sections_own_main(main), main => projects_own_main(main),
    main => agents_own_main(main), main => board_owns_main(main),
    values => band => flow => creation_regions_keep_order(values, band, flow),
    values => band => flow => creation_keys_keep_order(values, band, flow),
    owner => introduction => context => composer => creation_semantic_split(owner, introduction, context, composer),
    canvas => shared_composer_inset(canvas),
    key => tag => attrs => styles => events => values => title_node_identity(key, tag, attrs, styles, events, values),
    conversation_title_properties(), conversation_title_remaining_width(),
    values => band => flow => creation_group_order(values, band, flow),
    band => flow => parts => creation_intrinsic_regions(band, flow, parts),
    band => flow => creation_group_growth(band, flow), band => creation_center_owner(band),
    canvas => band => flow => values => creation_canvas_geometry(canvas, band, flow, values)}
