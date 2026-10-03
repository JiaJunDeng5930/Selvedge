import Base
import ./enclosure.bend as Enclosure
import ./document.bend as Doc
import ./renderer.bend as Render
import ./appearance.bend as Appearance
import ./design.bend as Design
import ./controls.bend as Controls
import ../core/interface.bend as UI
import ../core/ui-world.bend as View
import ../bendlib/stdlib.bend as Std
import ../BOARD.bend as Board





def first(values: +List<Doc.Node>) -> Doc.Node:
  match values:
    case Nil{}: Doc.Text{""}
    case Con{node, rest}: node





def search_input(+key: String, +filter: Board.Filter, +name: String, visual: Design.Style) -> Doc.Node:
  Render.input(key, UI.BoardSearch{filter},
    Controls.make_input(UI.BoardSearch{filter}, name, Controls.SearchInput{}, View.Available{}), visual)

def search_projection(+key: String, +filter: Board.Filter, +name: String, +visual: Design.Style) ->
  (String & (String & (+List<Doc.Property> & +List<Doc.Event>))):
  +node = search_input(key, filter, name, visual)
  (Render.attr(Doc.element_attributes(node), "placeholder"),
    (Render.attr(Doc.element_attributes(node), "aria-label"),
     (Doc.element_styles(node), Doc.element_events(node))))

def search_styles_expected(visual: Design.Style) -> +List<Doc.Property>:
  List.append(&2, Doc.Property, Render.style(visual), [Doc.Property{"height", "32px"}])




def title_production_styles() -> +List<Doc.Property>:
  Doc.element_styles(Render.card_title_control("title", Doc.Element{"title", "button", Nil{}, Render.style(Appearance.ordinary_button()), Nil{}, [Doc.Text{"title"}]}))





















type Requirements is Type:
  Requirements{
    title_action: @+title:String -> @+key:String -> @+attrs:+List<Doc.Property> -> @+original_styles:+List<Doc.Property> -> @+events:+List<Doc.Event> -> @original_children:+List<Doc.Node> ->
      {Render.card_title_control(title, Doc.Element{key, "button", attrs, original_styles, events, original_children}) == Doc.Element{key, "button", attrs, List.append(&2, Doc.Property, original_styles, Render.card_title_styles()), events, [Doc.Text{title}]} : Doc.Node},
    title_inset: {(Render.attr(title_production_styles(), "padding-inline"),
          (Render.attr(title_production_styles(), "padding-block"),
           (Render.attr(title_production_styles(), "font-weight"),
            (Render.attr(title_production_styles(), "white-space"), Render.attr(title_production_styles(), "min-height"))))) ==
          ("8px", ("4px", ("580", ("normal", "32px")))) : (String & (String & (String & (String & String))))},
    title_group: @+owner:String -> @+title:String -> @+node:Doc.Node -> @+rest:+List<Doc.Node> -> {Doc.element_children(first(Render.card_title_nodes(owner, title, node <> rest))) == Render.card_title_control(title, node) <> Render.card_title_actions(title, rest) : +List<Doc.Node>},
    card_inset: {(Render.attr(Render.style(Appearance.style(UI.Card{}, UI.Region{})), "padding-inline"), Render.attr(Render.style(Appearance.style(UI.Card{}, UI.Region{})), "padding-block")) == ("12px", "12px") : (String & String)},
    lane_groups: @+owner:String -> @+label:String -> @+stage:Board.Stage -> @+count:Nat -> @+create:+List<Doc.Node> ->
      {Doc.element_children(Render.lane_heading_node(owner, label, stage, count, create)) == [Render.lane_heading_leading(owner, label, stage, count), Render.lane_heading_trailing(owner, create)] : +List<Doc.Node>},
    lane_controls: @+owner:String -> @+create:+List<Doc.Node> -> {Doc.element_children(Render.lane_heading_trailing(owner, create)) == create : +List<Doc.Node>},
    trailing_edge: @+owner:String -> @+create:+List<Doc.Node> -> {(Render.attr(Doc.element_styles(Render.lane_heading_trailing(owner, create)), "margin-inline-start"), Render.attr(Doc.element_styles(Render.lane_heading_trailing(owner, create)), "flex")) == ("auto", "0 0 auto") : (String & String)},
    grouping_surface: @+owner:String -> @+label:String -> @+stage:Board.Stage -> @+count:Nat -> @+create:+List<Doc.Node> -> {(Render.attr(Render.board_lane_styles(stage), "border"), Render.attr(Doc.element_styles(Render.lane_heading_node(owner, label, stage, count, create)), "border-bottom")) == ("", "") : (String & String)},
    timestamp_width: {Render.attr(Render.card_timestamp_styles(), "flex") == "none" : String},
    description_lines: @+owner:String -> @+description:String -> {Render.attr(Doc.element_styles(first(Render.card_description_when(False{}, owner, description))), "-webkit-line-clamp") == "3" : String},
    search_hint: @+key:String -> @+filter:Board.Filter -> @+name:String -> @+visual:Design.Style -> {search_projection(key, filter, name, visual) == ("搜索任务", (name, (search_styles_expected(visual), [Doc.EditText{key}]))) : (String & (String & (+List<Doc.Property> & +List<Doc.Event>)))}
  }

def evidence() -> Requirements:
  Requirements{+title => +key => +attrs => +original_styles => +events => original_children => {==}, {==}, +owner => +title => +node => +rest => {==}, {==}, +owner => +label => +stage => +count => +create => {==}, +owner => +create => {==}, +owner => +create => {==}, +owner => +label => +stage => +count => +create => {==}, {==}, +owner => +description => {==}, +key => +filter => +name => +visual =>
        {==}

      # The actual title transform retains the complete accepted action boundary.
    }
