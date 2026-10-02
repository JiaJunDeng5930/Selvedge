import Base
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

def children(node: Doc.Node) -> +List<Doc.Node>:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, values}: values
    case _: Nil{}

def creation_region_children(values: +List<Doc.Node>) -> +List<Doc.Node>:
  match values:
    case Con{hero, Con{footer, Nil{}}}: List.append(&2, Doc.Node, children(hero), children(footer))
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


def creation_keys_keep_order(+children: +List<Doc.Node>, +band: Design.Band, +flow: Design.CreationFlow) ->
  {Std.map(~Doc.Node, ~String, ~node_key,
    creation_region_children(Render.creation_regions(band, flow, Render.creation_partition(children)))) ==
    Std.map(~Doc.Node, ~String, ~node_key, children) : +List<String>}:
  Equal.cong(+List<Doc.Node>, +List<String>,
    (values => Std.map(~Doc.Node, ~String, ~node_key, values)),
    creation_region_children(Render.creation_regions(band, flow, Render.creation_partition(children))), children,
    creation_regions_keep_order(children, band, flow))

def creation_semantic_split(+owner: String, introduction: +List<Doc.Node>, context: +List<Doc.Node>, composer: +List<Doc.Node>) ->
  {Render.creation_partition([
    Render.page_region(owner ++ "/intro", Composition.CreationIntroduction{}, Composition.BodyPosition{}, introduction),
    Render.page_region(owner ++ "/context", Composition.CreationContext{}, Composition.BodyPosition{}, context),
    Render.page_region(owner ++ "/input", Composition.ComposerInput{}, Composition.BodyPosition{}, composer)]) ==
    Render.CreationParts{
      [Render.page_region(owner ++ "/intro", Composition.CreationIntroduction{}, Composition.BodyPosition{}, introduction)],
      [Render.page_region(owner ++ "/context", Composition.CreationContext{}, Composition.BodyPosition{}, context),
       Render.page_region(owner ++ "/input", Composition.ComposerInput{}, Composition.BodyPosition{}, composer)]} : Render.CreationParts}:
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

def conversation_title_properties() ->
  {Render.conversation_title_styles() == [Doc.Property{"display", "block"}, Doc.Property{"min-height", "0"}, Doc.Property{"min-width", "0"}, Doc.Property{"width", "100%"},
    Doc.Property{"overflow", "hidden"}, Doc.Property{"text-overflow", "ellipsis"}, Doc.Property{"white-space", "nowrap"}] : +List<Doc.Property>}:
  {==}

def conversation_title_remaining_width() ->
  {Render.page_region_styles(Composition.ConversationTitle{}) == [Doc.Property{"display", "flex"},
    Doc.Property{"flex-direction", "column"}, Doc.Property{"flex", "1"}, Doc.Property{"min-width", "0"}] : +List<Doc.Property>}:
  {==}

type Requirements is Type:
  Requirements{creation_canvas: @main:Design.Box -> {inline_canvas(main, Composition.CenteredCreation{}) == main : Design.Box},
    section_canvas: @main:Design.Box -> {inline_canvas(main, Composition.ProjectSections{}) == main : Design.Box},
    project_canvas: @main:Design.Box -> {inline_canvas(main, Composition.ProjectRows{}) == main : Design.Box},
    agent_canvas: @main:Design.Box -> {inline_canvas(main, Composition.AgentRows{}) == main : Design.Box},
    board_canvas: @main:Design.Box -> {inline_canvas(main, Composition.StageColumns{}) == main : Design.Box},
    creation_order: @+values:+List<Doc.Node> -> @+band:Design.Band -> @+flow:Design.CreationFlow ->
      {creation_region_children(Render.creation_regions(band, flow, Render.creation_partition(values))) == values : +List<Doc.Node>},
    creation_keys: @+values:+List<Doc.Node> -> @+band:Design.Band -> @+flow:Design.CreationFlow ->
      {Std.map(~Doc.Node, ~String, ~node_key, creation_region_children(Render.creation_regions(band, flow, Render.creation_partition(values)))) ==
        Std.map(~Doc.Node, ~String, ~node_key, values) : +List<String>},
    semantic_partition: @+owner:String -> @introduction:+List<Doc.Node> -> @context:+List<Doc.Node> -> @composer:+List<Doc.Node> ->
      {Render.creation_partition([
        Render.page_region(owner ++ "/intro", Composition.CreationIntroduction{}, Composition.BodyPosition{}, introduction),
        Render.page_region(owner ++ "/context", Composition.CreationContext{}, Composition.BodyPosition{}, context),
        Render.page_region(owner ++ "/input", Composition.ComposerInput{}, Composition.BodyPosition{}, composer)]) ==
        Render.CreationParts{
          [Render.page_region(owner ++ "/intro", Composition.CreationIntroduction{}, Composition.BodyPosition{}, introduction)],
          [Render.page_region(owner ++ "/context", Composition.CreationContext{}, Composition.BodyPosition{}, context),
           Render.page_region(owner ++ "/input", Composition.ComposerInput{}, Composition.BodyPosition{}, composer)]} : Render.CreationParts},
    shared_inset: @canvas:Design.Box -> {input_inset(Layout.input_metrics(canvas)) == Appearance.face_padding(Controls.TextFace{""}) : Nat},
    title_identity: @+key:String -> @+tag:String -> @+attrs:+List<Doc.Property> -> @+styles:+List<Doc.Property> -> @+events:+List<Doc.Event> -> @+values:+List<Doc.Node> ->
      {Render.conversation_title_node(Doc.Element{key, tag, attrs, styles, events, values}) ==
        Doc.Element{key, tag, attrs, List.append(&2, Doc.Property, styles, Render.conversation_title_styles()), events, values} : Doc.Node},
    title_properties: {Render.conversation_title_styles() == [Doc.Property{"display", "block"}, Doc.Property{"min-height", "0"}, Doc.Property{"min-width", "0"}, Doc.Property{"width", "100%"},
      Doc.Property{"overflow", "hidden"}, Doc.Property{"text-overflow", "ellipsis"}, Doc.Property{"white-space", "nowrap"}] : +List<Doc.Property>},
    title_remaining_width: {Render.page_region_styles(Composition.ConversationTitle{}) == [Doc.Property{"display", "flex"},
      Doc.Property{"flex-direction", "column"}, Doc.Property{"flex", "1"}, Doc.Property{"min-width", "0"}] : +List<Doc.Property>}}

def evidence() -> Requirements:
  Requirements{main => creation_owns_main(main), main => sections_own_main(main), main => projects_own_main(main),
    main => agents_own_main(main), main => board_owns_main(main),
    values => band => flow => creation_regions_keep_order(values, band, flow),
    values => band => flow => creation_keys_keep_order(values, band, flow),
    owner => introduction => context => composer => creation_semantic_split(owner, introduction, context, composer),
    canvas => shared_composer_inset(canvas),
    key => tag => attrs => styles => events => values => title_node_identity(key, tag, attrs, styles, events, values),
    conversation_title_properties(), conversation_title_remaining_width()}
