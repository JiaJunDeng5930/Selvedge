import Base
import ./typography.bend as T
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
import ../core/SYSTEM.bend as Core





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
  List.append(&2, Doc.Property, Render.style(visual), Nil{})




def title_production_styles(+typography: T.Presentation) -> +List<Doc.Property>:
  Render.style(Appearance.source_content_style(Controls.TitleContent{"title"}, Controls.Geometry{32n, 32n, 16n, 6n, 20n}, Appearance.ordinary_button(typography)))





















def title_inset(typography: T.Presentation) ->
  {(Render.attr(title_production_styles(typography), "padding-inline"),
          (Render.attr(title_production_styles(typography), "padding-block"),
           (Render.attr(title_production_styles(typography), "font-weight"),
            (Render.attr(Doc.element_styles(Render.face_label("title", "title")), "white-space"), Render.attr(title_production_styles(typography), "min-height"))))) ==
          ("8px", ("4px", (Nat.show(T.weight(T.Strong{})), ("normal", "32px")))) : (String & (String & (String & (String & String))))}:
  T.Presentation{tier, emphasis, scale} = typography
  {==}

type Requirements is Type:
  Requirements{
    search_intrinsic_minimum: @+typography:T.Presentation -> @+key:String -> @+filter:Board.Filter -> @+name:String ->
      {(Render.attr(Doc.element_styles(search_input(key, filter, name, Appearance.field_style(UI.BoardSearch{filter}, typography))), "min-height"), Render.attr(Doc.element_styles(search_input(key, filter, name, Appearance.field_style(UI.BoardSearch{filter}, typography))), "height")) == (Render.px(Appearance.style_minimum_height(Appearance.field_style(UI.BoardSearch{filter}, typography))), "") : (String & String)},
    title_action: @+typography:T.Presentation -> @+title:String -> @+key:String -> @+visual:Design.Style -> @+input:Core.Input -> @+availability:View.Availability -> @+name:String -> @+behavior:Controls.Behavior -> @+geometry:Controls.Geometry -> @+placement:Controls.Placement -> @+help:Controls.Help -> @+feedback:Controls.Feedback ->
      {Doc.element_children(first(Render.card_title_nodes(key, title,
        [Render.action(key, visual, Controls.Action{input, availability, name, Controls.TextFace{title}, behavior, geometry, placement, help, feedback})], typography))) ==
        [Render.action(key, visual, Controls.Action{input, availability, name, Controls.TextFace{title}, behavior, geometry, placement, help, feedback})] : +List<Doc.Node>},
    title_inset: @+typography:T.Presentation -> {(Render.attr(title_production_styles(typography), "padding-inline"),
          (Render.attr(title_production_styles(typography), "padding-block"),
           (Render.attr(title_production_styles(typography), "font-weight"),
            (Render.attr(Doc.element_styles(Render.face_label("title", "title")), "white-space"), Render.attr(title_production_styles(typography), "min-height"))))) ==
          ("8px", ("4px", (Nat.show(T.weight(T.Strong{})), ("normal", "32px")))) : (String & (String & (String & (String & String))))},
    title_group: @+typography:T.Presentation -> @+owner:String -> @+title:String -> @+node:Doc.Node -> @+rest:+List<Doc.Node> -> {Doc.element_children(first(Render.card_title_nodes(owner, title, node <> rest, typography))) == node <> rest : +List<Doc.Node>},
    card_inset: @+typography:T.Presentation -> {(Render.attr(Render.style(Appearance.style(UI.Card{}, UI.Region{}, typography)), "padding-inline"), Render.attr(Render.style(Appearance.style(UI.Card{}, UI.Region{}, typography)), "padding-block")) == ("12px", "12px") : (String & String)},
    lane_groups: @+typography:T.Presentation -> @+owner:String -> @+label:String -> @+stage:Board.Stage -> @+count:Nat -> @+create:+List<Doc.Node> ->
      {Doc.element_children(Render.lane_heading_node(owner, label, stage, count, create, typography)) == [Render.lane_heading_leading(owner, label, stage, count, typography), Render.lane_heading_trailing(owner, create)] : +List<Doc.Node>},
    lane_controls: @+owner:String -> @+create:+List<Doc.Node> -> {Doc.element_children(Render.lane_heading_trailing(owner, create)) == create : +List<Doc.Node>},
    trailing_edge: @+owner:String -> @+create:+List<Doc.Node> -> {(Render.attr(Doc.element_styles(Render.lane_heading_trailing(owner, create)), "margin-inline-start"), Render.attr(Doc.element_styles(Render.lane_heading_trailing(owner, create)), "flex")) == ("auto", "0 0 auto") : (String & String)},
    grouping_surface: @+typography:T.Presentation -> @+owner:String -> @+label:String -> @+stage:Board.Stage -> @+count:Nat -> @+create:+List<Doc.Node> -> {(Render.attr(Render.board_lane_styles(stage), "border"), Render.attr(Doc.element_styles(Render.lane_heading_node(owner, label, stage, count, create, typography)), "border-bottom")) == ("", "") : (String & String)},
    timestamp_width: {Render.attr(Render.card_timestamp_styles(), "flex") == "none" : String},
    description_lines: @+typography:T.Presentation -> @+owner:String -> @+description:String -> {Render.attr(Doc.element_styles(first(Render.card_description_when(False{}, owner, description, typography))), "-webkit-line-clamp") == "3" : String},
    search_hint: @+key:String -> @+filter:Board.Filter -> @+name:String -> @+visual:Design.Style -> {search_projection(key, filter, name, visual) == ("搜索任务", (name, (search_styles_expected(visual), [Doc.EditText{key}]))) : (String & (String & (+List<Doc.Property> & +List<Doc.Event>)))}
  }

def evidence() -> Requirements:
  Requirements{+typography => +key => +filter => +name => {==},
    +typography => +title => +key => +visual => +input => +availability => +name => +behavior => +geometry => +placement => +help => +feedback => {==},
    +typography => title_inset(typography),
    +typography => +owner => +title => +node => +rest => {==},
    +typography => {==},
    +typography => +owner => +label => +stage => +count => +create => {==}, +owner => +create => {==}, +owner => +create => {==},
    +typography => +owner => +label => +stage => +count => +create => {==}, {==},
    +typography => +owner => +description => {==}, +key => +filter => +name => +visual =>
        {==}

      # The title container retains the complete canonical action unchanged.
    }
