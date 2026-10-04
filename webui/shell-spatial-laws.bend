import Base
import ../core/interface.bend as UI
import ../core/ui-world.bend as View
import ../bendlib/stdlib.bend as Std
import ../core/composition.bend as Composition
import ./design.bend as Design
import ./document.bend as Doc
import ./layout.bend as Layout
import ./renderer.bend as Render
import ./enclosure.bend as Enclosure

def frame_canvas(frame: Design.MainFrame) -> Design.Box:
  match frame:
    case Design.CreationFrame{heading, canvas, band, input, flow}: canvas
    case Design.OverviewFrame{canvas, band, organization}: canvas
    case Design.BoardFrame{canvas, width, gap, inset}: canvas
    case Design.ConversationFrame{heading, viewport, reading, dock}: viewport
    case Design.UnavailableFrame{heading, canvas, band}: canvas


def inline_canvas(+parameters: Design.LayoutParameters, +main: Design.Box, +body: Composition.Body) -> Design.Box:
  frame_canvas(Layout.main_frame(parameters, Composition.Recipe{Composition.ReadingMeasure{}, Composition.NoHeading{}, body,
    Composition.NoComposer{}, Composition.NoDecisions{}, Composition.NoLatest{}}, main))












def creation_region_children(values: +List<Doc.Node>) -> +List<Doc.Node>:
  match values:
    case Con{hero, Con{footer, Nil{}}}: List.append(&2, Doc.Node, Doc.element_children(hero), Doc.element_children(footer))
    case _: Nil{}


def node_key(node: Doc.Node) -> String:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: key
    case Doc.Markdown{key, source, value}: key
    case Doc.Text{value}: ""
    case Doc.Portal{key, target, children}: key
    case Doc.TargetProperties{key, target, attrs, styles}: key











def input_inset(metrics: Design.InputMetrics) -> Nat:
  Design.InputMetrics{minimum, maximum, line_height, inline, gap, footer} = metrics
  inline


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
  {(Render.attr(Doc.element_styles(first(Render.prepare_creation_regions(parts))), "flex"),
      Render.attr(Doc.element_styles(second(Render.prepare_creation_regions(parts))), "flex")) ==
     ("0 0 auto", "0 0 auto") : (String & String)}


def center_owner_law(-band: Design.Band) -> Type:
  {(Render.attr(Render.creation_group_styles(band, Design.Balanced{}), "margin-block"),
      (Render.attr(Render.creation_group_styles(band, Design.Compact{}), "margin-block"),
       Render.attr(Render.place_creation_introduction(Composition.region_name(Composition.CreationIntroduction{}), Layout.creation_arrangement(Design.Balanced{})), "justify-content"))) ==
     ("auto", ("0", "center")) : (String & (String & String))}


def canvas_geometry_law(-canvas: Design.Box, -band: Design.Band, -flow: Design.CreationFlow, -values: +List<Doc.Node>) -> Type:
  {(Render.attr(Doc.element_styles(first(Render.place_children(Render.prepare_creation(values), False{}, Design.CreationFrame{canvas, canvas, band, None{}, flow}))), "align-items"),
      (Render.attr(Doc.element_styles(first(Render.place_children(Render.prepare_creation(values), False{}, Design.CreationFrame{canvas, canvas, band, None{}, flow}))), "overflow-y"),
       Render.attr(Doc.element_styles(first(Render.place_children(Render.prepare_creation(values), False{}, Design.CreationFrame{canvas, canvas, band, None{}, flow}))), "padding-block"))) ==
     ("center", ("auto", "24px")) : (String & (String & String))}


type Requirements is Type:
  Requirements{
    allocated_control_styles: @+key:String -> @+controls:+List<Design.NodePlacement> -> @+box:Design.Box ->
      @found:{Render.node_bounds(key, controls) == Some{box} : Maybe<&2, Design.Box>} ->
      {Render.node_placement_styles(key, controls) ==
        List.append(&2, Doc.Property, Render.bounds(box), [Doc.Property{"z-index", "6"}]) : +List<Doc.Property>},
    unallocated_node_styles: @+key:String -> @+controls:+List<Design.NodePlacement> ->
      @absent:{Render.node_bounds(key, controls) == None{} : Maybe<&2, Design.Box>} ->
      {Render.node_placement_styles(key, controls) == Nil{} : +List<Doc.Property>},
    unallocated_role_styles: @+role:UI.Role -> @+navigation:Design.Navigation ->
      @+main:Design.Box -> @+details:Maybe<&2, Design.Box> ->
      {Render.base_shell_styles(role, Design.Shell{navigation, main, details}) ==
        Render.base_role_styles(role, navigation, main) : +List<Doc.Property>},
    reopening_events: @+parameters:Design.LayoutParameters -> @role:UI.Role -> @expanded:Bool -> @availability:View.Availability ->
      @+node:Doc.Node -> @main:Design.Box -> @details:Maybe<&2, Design.Box> -> @key:String -> @controls:+List<Design.NodePlacement> ->
      {Doc.element_events(Render.replace_styles(node, Render.base_shell_styles(role,
        Design.Shell{Design.HiddenNavigation{}, main, details}))) == Doc.element_events(node) : +List<Doc.Event>},
    creation_canvas: @+parameters:Design.LayoutParameters -> @main:Design.Box -> {inline_canvas(parameters, main, Composition.CenteredCreation{}) == main : Design.Box},
    section_canvas: @+parameters:Design.LayoutParameters -> @main:Design.Box -> {inline_canvas(parameters, main, Composition.ProjectSections{}) == main : Design.Box},
    project_canvas: @+parameters:Design.LayoutParameters -> @main:Design.Box -> {inline_canvas(parameters, main, Composition.ProjectRows{}) == main : Design.Box},
    agent_canvas: @+parameters:Design.LayoutParameters -> @main:Design.Box -> {inline_canvas(parameters, main, Composition.AgentRows{}) == main : Design.Box},
    board_canvas: @+parameters:Design.LayoutParameters -> @main:Design.Box -> {inline_canvas(parameters, main, Composition.StageColumns{}) == main : Design.Box},
    creation_order: @+values:+List<Doc.Node> -> @+band:Design.Band -> @+flow:Design.CreationFlow ->
      {creation_region_children(Render.prepare_creation_regions(Render.creation_partition(values))) == values : +List<Doc.Node>},
    creation_keys: @+values:+List<Doc.Node> -> @+band:Design.Band -> @+flow:Design.CreationFlow ->
      {Std.map(~Doc.Node, ~String, ~node_key,
          creation_region_children(Render.prepare_creation_regions(Render.creation_partition(values)))) ==
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
    shared_inset: @+parameters:Design.LayoutParameters -> @canvas:Design.Box -> {input_inset(Layout.input_metrics(parameters, canvas)) == Enclosure.inline(Enclosure.area(Enclosure.Field{})) : Nat},
    title_identity: @+key:String -> @+tag:String -> @+attrs:+List<Doc.Property> -> @+styles:+List<Doc.Property> -> @+events:+List<Doc.Event> -> @+values:+List<Doc.Node> ->
      {Render.conversation_title_node(Doc.Element{key, tag, attrs, styles, events, values}) ==
        Doc.Element{key, tag, attrs, List.append(&2, Doc.Property, styles, Render.conversation_title_styles()), events, values} : Doc.Node},
    title_properties: {Render.conversation_title_styles() == List.append(&2, Doc.Property,
          [Doc.Property{"display", "block"}, Doc.Property{"min-height", "0"}, Doc.Property{"min-width", "0"}, Doc.Property{"width", "100%"}],
          Render.overflow_style(Design.SingleLineOverflow{})) : +List<Doc.Property>},
    title_remaining_width: {Render.page_region_styles(Composition.ConversationTitle{}) == [Doc.Property{"display", "flex"},
      Doc.Property{"flex-direction", "column"}, Doc.Property{"justify-content", "center"}, Doc.Property{"min-width", "0"}] : +List<Doc.Property>},
    group_order: @+values:+List<Doc.Node> -> @+band:Design.Band -> @+flow:Design.CreationFlow ->
      {creation_region_children(Doc.element_children(first(Doc.element_children(first(Render.prepare_creation(values)))))) == values : +List<Doc.Node>},
    intrinsic_regions: @+band:Design.Band -> @+flow:Design.CreationFlow -> @+parts:Render.CreationParts ->
      intrinsic_regions_law(band, flow, parts),
    group_growth: @band:Design.Band -> @flow:Design.CreationFlow ->
      {Render.attr(Render.creation_group_styles(band, flow), "flex") == "0 0 auto" : String},
    center_owner: @+band:Design.Band ->
      center_owner_law(band),
    introduction_center: @flow:Design.CreationFlow ->
      {Render.attr(Render.place_creation_introduction(Composition.region_name(Composition.CreationIntroduction{}),
        Layout.creation_arrangement(flow)), "justify-content") == "center" : String},
    canvas_geometry: @+canvas:Design.Box -> @+band:Design.Band -> @+flow:Design.CreationFlow -> @+values:+List<Doc.Node> ->
      canvas_geometry_law(canvas, band, flow, values)}


law evidence:
  Requirements
