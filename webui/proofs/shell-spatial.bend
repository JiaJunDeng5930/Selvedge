import Base
import ../../core/interface.bend as UI
import ../../core/ui-world.bend as View
import ../../bendlib/stdlib.bend as Std
import ../../core/composition.bend as Composition
import ../design.bend as Design
import ../document.bend as Doc
import ../layout.bend as Layout
import ../renderer.bend as Render
import ../enclosure.bend as Enclosure
import ../shell-spatial-laws.bend as Rule

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




def regions_recombine(+band: Design.Band, flow: Design.CreationFlow, parts: Render.CreationParts) ->
  {Rule.creation_region_children(Render.prepare_creation_regions(parts)) == Render.creation_recombine(parts) : +List<Doc.Node>}:
  match parts:
    case Render.CreationParts{hero, footer}: {==}


def creation_regions_keep_order(+children: +List<Doc.Node>, +band: Design.Band, +flow: Design.CreationFlow) ->
  {Rule.creation_region_children(Render.prepare_creation_regions(Render.creation_partition(children))) == children : +List<Doc.Node>}:
  Equal.trans(+List<Doc.Node>, Rule.creation_region_children(Render.prepare_creation_regions(Render.creation_partition(children))),
    Render.creation_recombine(Render.creation_partition(children)), children,
    regions_recombine(band, flow, Render.creation_partition(children)), creation_partition_order(children))


def shared_composer_inset(+parameters: Design.LayoutParameters, canvas: Design.Box) ->
  {Rule.input_inset(Layout.input_metrics(parameters, canvas)) == Enclosure.inline(Enclosure.area(Enclosure.Field{})) : Nat}:
  match canvas:
    case Design.Box{left, top, width, height}: {==}


def title_node_identity(+key: String, +tag: String, +attrs: +List<Doc.Property>, +styles: +List<Doc.Property>,
  +events: +List<Doc.Event>, +children: +List<Doc.Node>) ->
  {Render.conversation_title_node(Doc.Element{key, tag, attrs, styles, events, children}) ==
    Doc.Element{key, tag, attrs, List.append(&2, Doc.Property, styles, Render.conversation_title_styles()), events, children} : Doc.Node}:
  {==}








def creation_group_order(+values: +List<Doc.Node>, +band: Design.Band, +flow: Design.CreationFlow) ->
  {Rule.creation_region_children(Doc.element_children(Rule.first(Doc.element_children(Rule.first(Render.prepare_creation(values)))))) == values : +List<Doc.Node>}:
  creation_regions_keep_order(values, band, flow)





def creation_intrinsic_regions(+band: Design.Band, +flow: Design.CreationFlow, +parts: Render.CreationParts) -> Rule.intrinsic_regions_law(band, flow, parts):
  match band flow parts:
    case Design.Band{left, width} Design.Balanced{} Render.CreationParts{hero, footer}: {==}
    case Design.Band{left, width} Design.Compact{} Render.CreationParts{hero, footer}: {==}


def creation_group_growth(band: Design.Band, flow: Design.CreationFlow) ->
  {Render.attr(Render.creation_group_styles(band, flow), "flex") == "0 0 auto" : String}:
  match band flow:
    case Design.Band{left, width} Design.Balanced{}: {==}
    case Design.Band{left, width} Design.Compact{}: {==}


def creation_center_owner(+band: Design.Band) -> Rule.center_owner_law(band):
  match band:
    case Design.Band{left, width}: {==}


def creation_introduction_center(flow: Design.CreationFlow) ->
  {Render.attr(Render.place_creation_introduction(Composition.region_name(Composition.CreationIntroduction{}),
    Layout.creation_arrangement(flow)), "justify-content") == "center" : String}:
  match flow:
    case Design.Balanced{}: {==}
    case Design.Compact{}: {==}


def creation_canvas_geometry(+canvas: Design.Box, +band: Design.Band, +flow: Design.CreationFlow, +values: +List<Doc.Node>) -> Rule.canvas_geometry_law(canvas, band, flow, values):
  match canvas band flow:
    case Design.Box{left, top, width, height} Design.Band{band_left, band_width} Design.Balanced{}: {==}
    case Design.Box{left, top, width, height} Design.Band{band_left, band_width} Design.Compact{}: {==}












def allocated_control_styles(+key: String, +controls: +List<Design.NodePlacement>, +box: Design.Box,
  found: {Render.node_bounds(key, controls) == Some{box} : Maybe<&2, Design.Box>}) ->
  {Render.node_placement_styles(key, controls) ==
    List.append(&2, Doc.Property, Render.bounds(box), [Doc.Property{"z-index", "6"}]) : +List<Doc.Property>}:
  Equal.cong(Maybe<&2, Design.Box>, +List<Doc.Property>, Render.allocated_node_styles,
    Render.node_bounds(key, controls), Some{box}, found)


def unallocated_node_styles(+key: String, +controls: +List<Design.NodePlacement>,
  absent: {Render.node_bounds(key, controls) == None{} : Maybe<&2, Design.Box>}) ->
  {Render.node_placement_styles(key, controls) == Nil{} : +List<Doc.Property>}:
  Equal.cong(Maybe<&2, Design.Box>, +List<Doc.Property>, Render.allocated_node_styles,
    Render.node_bounds(key, controls), None{}, absent)


def unallocated_role_styles(+role: UI.Role, +navigation: Design.Navigation,
  +main: Design.Box, +details: Maybe<&2, Design.Box>) ->
  {Render.base_shell_styles(role, Design.Shell{navigation, main, details}) ==
    Render.base_role_styles(role, navigation, main) : +List<Doc.Property>}:
  {==}


def reopening_events(+parameters: Design.LayoutParameters, role: UI.Role, expanded: Bool, availability: View.Availability,
  +node: Doc.Node, main: Design.Box, details: Maybe<&2, Design.Box>, key: String,
  controls: +List<Design.NodePlacement>) ->
  {Doc.element_events(Render.replace_styles(node, Render.base_shell_styles(role,
    Design.Shell{Design.HiddenNavigation{}, main, details}))) == Doc.element_events(node) : +List<Doc.Event>}:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: {==}
    case Doc.Text{text}: {==}
    case Doc.Markdown{key, source, text}: {==}
    case Doc.Portal{key, target, children}: {==}
    case Doc.TargetProperties{key, target, attrs, styles}: {==}


def Rule.evidence():
  Rule.Requirements{
    allocated_control_styles, unallocated_node_styles, unallocated_role_styles, reopening_events,
    +parameters => main => {==},
    +parameters => main => {==},
    +parameters => main => {==},
    +parameters => main => {==},
    +parameters => main => {==},
    values => band => flow => creation_regions_keep_order(values, band, flow),
    +children => +band => +flow =>
      Equal.cong(+List<Doc.Node>, +List<String>,
        (values => Std.map(~Doc.Node, ~String, ~Rule.node_key, values)),
        Rule.creation_region_children(Render.prepare_creation_regions(Render.creation_partition(children))), children,
        creation_regions_keep_order(children, band, flow))
    ,
    +owner => introduction => context => composer => {==},
    +parameters => canvas => shared_composer_inset(parameters, canvas),
    key => tag => attrs => styles => events => values => title_node_identity(key, tag, attrs, styles, events, values),
    {==}, {==},
    values => band => flow => creation_group_order(values, band, flow),
    band => flow => parts => creation_intrinsic_regions(band, flow, parts),
    band => flow => creation_group_growth(band, flow), band => creation_center_owner(band), creation_introduction_center,
    canvas => band => flow => values => creation_canvas_geometry(canvas, band, flow, values)}
