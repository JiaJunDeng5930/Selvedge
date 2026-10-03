import Base
import ../bendlib/stdlib.bend as Std
import ./page-region-laws.bend as Regions
import ../core/composition.bend as Composition
import ../core/user-input.bend as U
import ./design.bend as Design
import ./document.bend as Doc
import ./reading.bend as Reading
import ./renderer.bend as Render

# Physical extent is measured by the host from the viewport bottom to dock top.
# The pure transition clamps that observation without changing reading intent.




def dock_overflow(band: Design.Band, bottom: Nat, maximum: Nat,
  regions: +List<Design.DockRegion>, input: Maybe<&2, Design.InputMetrics>, reservation: Design.Reservation) ->
  {Render.attr(Render.conversation_dock_styles(Some{Design.Dock{band, bottom, maximum, regions, input, reservation}}), "overflow") == "hidden" : String}:
  Design.Band{left, width} = band
  {==}





def intrinsic_latest(+key: String, +children: +List<Doc.Node>) ->
  {Render.conversation_dock_region(Render.page_region(key, Composition.LatestAction{}, Composition.DockPosition{}, children)) ==
    Render.dock_region_element(False{}, key, "div",
      Render.page_region_attributes(key, Composition.LatestAction{}, Composition.DockPosition{}),
      Render.page_region_styles(Composition.LatestAction{}), Nil{}, children) : Doc.Node}:
  {==}








def composer_nonshrinking() ->
  {Render.dock_region_styles(False{}) == [Render.property("flex", "0 0 auto")] : +List<Doc.Property>}:
  {==}

def approval_shrinking() ->
  {Render.dock_region_styles(True{}) ==
    [Render.property("flex", "1 1 auto"), Render.property("min-height", "0"), Render.property("overflow", "hidden")] : +List<Doc.Property>}:
  {==}

def root_keys(nodes: +List<Doc.Node>) -> +List<String>:
  Std.map(~Doc.Node, ~String, ~Regions.node_key, nodes)

def region_root_key(+node: Doc.Node) ->
  {Regions.node_key(Render.conversation_dock_region(node)) == Regions.node_key(node) : String}:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: {==}
    case Doc.Text{value}: {==}
    case Doc.Markdown{key, source, value}: {==}
    case Doc.Portal{key, target, children}: {==}
    case Doc.TargetProperties{key, target, attrs, styles}: {==}

def region_key_order(+nodes: +List<Doc.Node>) ->
  {root_keys(Render.conversation_dock_regions(nodes)) == root_keys(nodes) : +List<String>}:
  match nodes:
    case Nil{}: {==}
    case Con{+node, +rest}:
      Equal.trans(+List<String>, root_keys(Render.conversation_dock_regions(node <> rest)),
        Regions.node_key(node) <> root_keys(Render.conversation_dock_regions(rest)),
        Regions.node_key(node) <> root_keys(rest),
        Equal.cong(String, +List<String>,
          (key => key <> root_keys(Render.conversation_dock_regions(rest))),
          Regions.node_key(Render.conversation_dock_region(node)), Regions.node_key(node), region_root_key(node)),
        Equal.cong(+List<String>, +List<String>, (keys => Regions.node_key(node) <> keys),
          root_keys(Render.conversation_dock_regions(rest)), root_keys(rest), region_key_order(rest)))

def region_count(+nodes: +List<Doc.Node>) ->
  {List.length(&2, Doc.Node, Render.conversation_dock_regions(nodes)) == List.length(&2, Doc.Node, nodes) : Nat}:
  match nodes:
    case Nil{}: {==}
    case Con{node, +rest}:
      Equal.cong(Nat, Nat, (length => Nat.add(1n, length)),
        List.length(&2, Doc.Node, Render.conversation_dock_regions(rest)), List.length(&2, Doc.Node, rest), region_count(rest))

# This projection retains the complete subtree and every event/attribute,
# while intentionally permitting only the region root's styles to change.
def subtree(node: Doc.Node) -> (String & (String & (+List<Doc.Property> & (+List<Doc.Event> & +List<Doc.Node>)))):
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: (key, (tag, (attrs, (events, children))))
    case _: ("", ("", (Nil{}, (Nil{}, Nil{}))))







type Requirements is Type:
  Requirements{
    root_order: @+nodes:+List<Doc.Node> ->
      {root_keys(Render.conversation_dock_regions(nodes)) == root_keys(nodes) : +List<String>},
    region_length: @+nodes:+List<Doc.Node> ->
      {List.length(&2, Doc.Node, Render.conversation_dock_regions(nodes)) == List.length(&2, Doc.Node, nodes) : Nat},
    unchanged_subtree: @+key:String -> @+tag:String -> @+attrs:+List<Doc.Property> -> @+styles:+List<Doc.Property> ->
      @+events:+List<Doc.Event> -> @+children:+List<Doc.Node> ->
      @not_approval:{String.eq(Render.attr(attrs, "data-page-region"), Composition.region_name(Composition.ApprovalDecisions{})) == False{} : Bool} ->
      {subtree(Render.conversation_dock_region(Doc.Element{key, tag, attrs, styles, events, children})) ==
        (key, (tag, (attrs, (events, children)))) : (String & (String & (+List<Doc.Property> & (+List<Doc.Event> & +List<Doc.Node>))))},
    wrapped_payload: @+key:String -> @+tag:String -> @+attrs:+List<Doc.Property> -> @+styles:+List<Doc.Property> ->
      @+events:+List<Doc.Event> -> @+children:+List<Doc.Node> ->
      {subtree(Render.dock_approval_queue(Doc.Element{key, tag, attrs, styles, events, children})) ==
          (key, (tag, (attrs, (events,
            [Doc.Element{Render.generated_identity(key, "intrinsic-content"), "div", Nil{},
              [Render.property("display", "flex"), Render.property("flex-direction", "column"), Render.property("gap", "8px"),
                Render.property("flex", "0 0 auto"), Render.property("min-height", "min-content")], Nil{}, children}])))) :
            (String & (String & (+List<Doc.Property> & (+List<Doc.Event> & +List<Doc.Node>))))},
    measured_extent: @extent:F32 -> @viewport:F32 -> @+intent:U.ReadingIntent -> @+bookmark:Reading.Bookmark -> @reduced:Bool ->
      {Reading.step(Reading.LayoutChanged{extent, viewport}, intent, bookmark, reduced) ==
          Reading.Decision{bookmark, None{},
            [Reading.ReserveComposer{Reading.reserve(extent, viewport)}, Reading.layout(intent, bookmark)]} : Reading.Decision},
    bounded_dock: @band:Design.Band -> @bottom:Nat -> @maximum:Nat -> @regions:+List<Design.DockRegion> ->
      @input:Maybe<&2,Design.InputMetrics> -> @reservation:Design.Reservation ->
      {Render.attr(Render.conversation_dock_styles(Some{Design.Dock{band, bottom, maximum, regions, input, reservation}}), "overflow") == "hidden" : String},
    intrinsic_input: @+key:String -> @+children:+List<Doc.Node> ->
      {Render.conversation_dock_region(Render.page_region(key, Composition.ComposerInput{}, Composition.DockPosition{}, children)) ==
          Render.dock_region_element(False{}, key, "div",
            Render.page_region_attributes(key, Composition.ComposerInput{}, Composition.DockPosition{}),
            Render.page_region_styles(Composition.ComposerInput{}), Nil{}, children) : Doc.Node},
    approval_owner: @+key:String -> @+children:+List<Doc.Node> ->
      {Render.conversation_dock_region(Render.page_region(key, Composition.ApprovalDecisions{}, Composition.DockPosition{}, children)) ==
          Render.dock_region_element(True{}, key, "div",
            Render.page_region_attributes(key, Composition.ApprovalDecisions{}, Composition.DockPosition{}),
            Render.page_region_styles(Composition.ApprovalDecisions{}), Nil{}, children) : Doc.Node},
    queue_viewport: @+key:String -> @+tag:String -> @+attrs:+List<Doc.Property> -> @+styles:+List<Doc.Property> ->
      @+events:+List<Doc.Event> -> @+children:+List<Doc.Node> ->
      {Render.dock_approval_queue(Doc.Element{key, tag, attrs, styles, events, children}) ==
          Doc.Element{key, tag, attrs,
            List.append(&2, Doc.Property, styles,
              [Render.property("flex", "1 1 auto"), Render.property("min-height", "0"), Render.property("overflow", "auto")]),
            events, [Render.dock_approval_content(key, children)]} : Doc.Node}
  }

def evidence() -> Requirements:
  Requirements{region_key_order, region_count, +key => +tag => +attrs => +styles => +events => +children => not_approval =>
      Equal.cong(Bool, (String & (String & (+List<Doc.Property> & (+List<Doc.Event> & +List<Doc.Node>)))),
        (approval => subtree(Render.dock_region_element(approval, key, tag, attrs, styles, events, children))),
        String.eq(Render.attr(attrs, "data-page-region"), Composition.region_name(Composition.ApprovalDecisions{})), False{}, not_approval)
    , +key => +tag => +attrs => +styles => +events => +children => {==}, extent => viewport => +intent => +bookmark => reduced => {==}, dock_overflow, +key => +children => {==}, +key => +children =>
        {==}

      # The existing queue's key, attributes and events remain on the scroll viewport.
    , +key => +tag => +attrs => +styles => +events => +children => {==}}
