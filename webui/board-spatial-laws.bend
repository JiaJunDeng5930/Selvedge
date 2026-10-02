import Base
import ./document.bend as Doc
import ./renderer.bend as Render
import ./appearance.bend as Appearance
import ./design.bend as Design
import ./controls.bend as Controls
import ../core/interface.bend as UI
import ../core/ui-world.bend as View
import ../bendlib/stdlib.bend as Std
import ../BOARD.bend as Board

def children(node: Doc.Node) -> +List<Doc.Node>:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, values}: values
    case _: Nil{}

def styles(node: Doc.Node) -> +List<Doc.Property>:
  match node:
    case Doc.Element{key, tag, attrs, values, events, children}: values
    case _: Nil{}

def first(values: +List<Doc.Node>) -> Doc.Node:
  match values:
    case Nil{}: Doc.Text{""}
    case Con{node, rest}: node

def attributes(node: Doc.Node) -> +List<Doc.Property>:
  match node:
    case Doc.Element{key, tag, values, styles, events, children}: values
    case _: Nil{}

def events(node: Doc.Node) -> +List<Doc.Event>:
  match node:
    case Doc.Element{key, tag, attrs, styles, values, children}: values
    case _: Nil{}

def search_input(+key: String, +filter: Board.Filter, +name: String, visual: Design.Style) -> Doc.Node:
  Render.input(key, UI.BoardSearch{filter},
    Controls.make_input(UI.BoardSearch{filter}, name, Controls.SearchInput{}, View.Available{}), visual)

def search_projection(+key: String, +filter: Board.Filter, +name: String, +visual: Design.Style) ->
  (String & (String & (+List<Doc.Property> & +List<Doc.Event>))):
  +node = search_input(key, filter, name, visual)
  (Render.attr(attributes(node), "placeholder"),
    (Render.attr(attributes(node), "aria-label"),
     (styles(node), events(node))))

def search_styles_expected(visual: Design.Style) -> +List<Doc.Property>:
  List.append(&2, Doc.Property, Render.style(visual),
    [Doc.Property{"width", "168px"}, Doc.Property{"max-width", "100%"}, Doc.Property{"min-width", "0"}, Doc.Property{"height", "32px"},
     Doc.Property{"padding", "4px 8px"}, Doc.Property{"border-radius", "6px"}, Doc.Property{"background", "var(--color-surface-secondary)"}, Doc.Property{"font-size", "13px"}])

def search_hint_boundary(+key: String, +filter: Board.Filter, +name: String, +visual: Design.Style) ->
  {search_projection(key, filter, name, visual) == ("搜索任务", (name, (search_styles_expected(visual), [Doc.EditText{key}]))) :
    (String & (String & (+List<Doc.Property> & +List<Doc.Event>)))}:
  +expected = search_styles_expected(visual)
  Equal.cong(+List<Doc.Property>, (String & (String & (+List<Doc.Property> & +List<Doc.Event>))),
    (properties => ("搜索任务", (name, (properties, [Doc.EditText{key}])))),
    List.append(&2, Doc.Property, expected, Nil{}), expected, Std.app_nil_r(Doc.Property, expected))

# The actual title transform retains the complete accepted action boundary.
def title_action(+title: String, +key: String, +attrs: +List<Doc.Property>,
  +original_styles: +List<Doc.Property>, +events: +List<Doc.Event>, original_children: +List<Doc.Node>) ->
  {Render.card_title_control(title, Doc.Element{key, "button", attrs, original_styles, events, original_children}) ==
    Doc.Element{key, "button", attrs, List.append(&2, Doc.Property, original_styles, Render.card_title_styles()), events, [Doc.Text{title}]} : Doc.Node}:
  {==}

def title_content_inset() ->
  {(Render.attr(Render.card_title_styles(), "padding-inline"),
    (Render.attr(Render.card_title_styles(), "padding-block"),
     (Render.attr(Render.card_title_styles(), "font-weight"),
      (Render.attr(Render.card_title_styles(), "white-space"), Render.attr(Render.card_title_styles(), "min-height"))))) ==
    ("0", ("0", ("580", ("normal", "32px")))) : (String & (String & (String & (String & String))))}:
  {==}

def title_group_binding(+owner: String, +title: String, +node: Doc.Node, +rest: +List<Doc.Node>) ->
  {children(first(Render.card_title_nodes(owner, title, node <> rest))) ==
    Render.card_title_control(title, node) <> Render.card_title_actions(title, rest) : +List<Doc.Node>}:
  {==}

def card_owned_inset() ->
  {(Render.attr(Render.style(Appearance.style(UI.Card{}, UI.Region{})), "padding-inline"),
    Render.attr(Render.style(Appearance.style(UI.Card{}, UI.Region{})), "padding-block")) == ("12px", "12px") : (String & String)}:
  {==}

def lane_group_order(+owner: String, +label: String, +stage: Board.Stage, +count: Nat, +create: +List<Doc.Node>) ->
  {children(Render.lane_heading_node(owner, label, stage, count, create)) ==
    [Render.lane_heading_leading(owner, label, stage, count), Render.lane_heading_trailing(owner, create)] : +List<Doc.Node>}:
  {==}

def lane_control_preservation(+owner: String, +create: +List<Doc.Node>) ->
  {children(Render.lane_heading_trailing(owner, create)) == create : +List<Doc.Node>}:
  {==}

def lane_trailing_edge(+owner: String, +create: +List<Doc.Node>) ->
  {(Render.attr(styles(Render.lane_heading_trailing(owner, create)), "margin-inline-start"),
    Render.attr(styles(Render.lane_heading_trailing(owner, create)), "flex")) == ("auto", "0 0 auto") : (String & String)}:
  {==}

def lane_grouping_surface(+owner: String, +label: String, +stage: Board.Stage, +count: Nat, +create: +List<Doc.Node>) ->
  {(Render.attr(Render.board_lane_styles(stage), "border"),
    Render.attr(styles(Render.lane_heading_node(owner, label, stage, count, create)), "border-bottom")) == ("", "") : (String & String)}:
  {==}

def timestamp_intrinsic_width() ->
  {Render.attr(Render.card_timestamp_styles(), "flex") == "none" : String}:
  {==}

def description_line_limit(+owner: String, +description: String) ->
  {Render.attr(styles(first(Render.card_description_when(False{}, owner, description))), "-webkit-line-clamp") == "3" : String}:
  {==}

type Requirements is Type:
  Requirements{
    title_action: @+title:String -> @+key:String -> @+attrs:+List<Doc.Property> -> @+original_styles:+List<Doc.Property> -> @+events:+List<Doc.Event> -> @original_children:+List<Doc.Node> ->
      {Render.card_title_control(title, Doc.Element{key, "button", attrs, original_styles, events, original_children}) == Doc.Element{key, "button", attrs, List.append(&2, Doc.Property, original_styles, Render.card_title_styles()), events, [Doc.Text{title}]} : Doc.Node},
    title_inset: {(Render.attr(Render.card_title_styles(), "padding-inline"), (Render.attr(Render.card_title_styles(), "padding-block"), (Render.attr(Render.card_title_styles(), "font-weight"), (Render.attr(Render.card_title_styles(), "white-space"), Render.attr(Render.card_title_styles(), "min-height"))))) == ("0", ("0", ("580", ("normal", "32px")))) : (String & (String & (String & (String & String))))},
    title_group: @+owner:String -> @+title:String -> @+node:Doc.Node -> @+rest:+List<Doc.Node> -> {children(first(Render.card_title_nodes(owner, title, node <> rest))) == Render.card_title_control(title, node) <> Render.card_title_actions(title, rest) : +List<Doc.Node>},
    card_inset: {(Render.attr(Render.style(Appearance.style(UI.Card{}, UI.Region{})), "padding-inline"), Render.attr(Render.style(Appearance.style(UI.Card{}, UI.Region{})), "padding-block")) == ("12px", "12px") : (String & String)},
    lane_groups: @+owner:String -> @+label:String -> @+stage:Board.Stage -> @+count:Nat -> @+create:+List<Doc.Node> ->
      {children(Render.lane_heading_node(owner, label, stage, count, create)) == [Render.lane_heading_leading(owner, label, stage, count), Render.lane_heading_trailing(owner, create)] : +List<Doc.Node>},
    lane_controls: @+owner:String -> @+create:+List<Doc.Node> -> {children(Render.lane_heading_trailing(owner, create)) == create : +List<Doc.Node>},
    trailing_edge: @+owner:String -> @+create:+List<Doc.Node> -> {(Render.attr(styles(Render.lane_heading_trailing(owner, create)), "margin-inline-start"), Render.attr(styles(Render.lane_heading_trailing(owner, create)), "flex")) == ("auto", "0 0 auto") : (String & String)},
    grouping_surface: @+owner:String -> @+label:String -> @+stage:Board.Stage -> @+count:Nat -> @+create:+List<Doc.Node> -> {(Render.attr(Render.board_lane_styles(stage), "border"), Render.attr(styles(Render.lane_heading_node(owner, label, stage, count, create)), "border-bottom")) == ("", "") : (String & String)},
    timestamp_width: {Render.attr(Render.card_timestamp_styles(), "flex") == "none" : String},
    description_lines: @+owner:String -> @+description:String -> {Render.attr(styles(first(Render.card_description_when(False{}, owner, description))), "-webkit-line-clamp") == "3" : String},
    search_hint: @+key:String -> @+filter:Board.Filter -> @+name:String -> @+visual:Design.Style -> {search_projection(key, filter, name, visual) == ("搜索任务", (name, (search_styles_expected(visual), [Doc.EditText{key}]))) : (String & (String & (+List<Doc.Property> & +List<Doc.Event>)))}
  }

def evidence() -> Requirements:
  Requirements{title_action, title_content_inset(), title_group_binding, card_owned_inset(), lane_group_order, lane_control_preservation, lane_trailing_edge, lane_grouping_surface, timestamp_intrinsic_width(), description_line_limit, search_hint_boundary}
