import Base
import ../page-region-laws.bend as Regions
import ../../core/composition.bend as Composition
import ../design.bend as Design
import ../document.bend as Doc
import ../renderer.bend as Render
import ../dock-laws.bend as Rule

def dock_overflow(band: Design.Band, bottom: Nat, maximum: Nat,
  regions: +List<Design.DockRegion>, input: Maybe<&2, Design.InputMetrics>, reservation: Design.Reservation) ->
  {Render.attr(Render.conversation_dock_styles(Some{Design.Dock{band, bottom, maximum, regions, input, reservation}}), "overflow") == "hidden" : String}:
  Design.Band{left, width} = band
  {==}

def region_root_key(+node: Doc.Node) ->
  {Regions.node_key(Render.conversation_dock_region(node)) == Regions.node_key(node) : String}:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: {==}
    case Doc.Text{value}: {==}
    case Doc.Markdown{key, source, value}: {==}
    case Doc.Portal{key, target, children}: {==}
    case Doc.TargetProperties{key, target, attrs, styles}: {==}

def region_key_order(+nodes: +List<Doc.Node>) ->
  {Rule.root_keys(Render.conversation_dock_regions(nodes)) == Rule.root_keys(nodes) : +List<String>}:
  match nodes:
    case Nil{}: {==}
    case Con{+node, +rest}:
      Equal.trans(+List<String>, Rule.root_keys(Render.conversation_dock_regions(node <> rest)),
        Regions.node_key(node) <> Rule.root_keys(Render.conversation_dock_regions(rest)),
        Regions.node_key(node) <> Rule.root_keys(rest),
        Equal.cong(String, +List<String>,
          (key => key <> Rule.root_keys(Render.conversation_dock_regions(rest))),
          Regions.node_key(Render.conversation_dock_region(node)), Regions.node_key(node), region_root_key(node)),
        Equal.cong(+List<String>, +List<String>, (keys => Regions.node_key(node) <> keys),
          Rule.root_keys(Render.conversation_dock_regions(rest)), Rule.root_keys(rest), region_key_order(rest)))

def region_count(+nodes: +List<Doc.Node>) ->
  {List.length(&2, Doc.Node, Render.conversation_dock_regions(nodes)) == List.length(&2, Doc.Node, nodes) : Nat}:
  match nodes:
    case Nil{}: {==}
    case Con{node, +rest}:
      Equal.cong(Nat, Nat, (length => Nat.add(1n, length)),
        List.length(&2, Doc.Node, Render.conversation_dock_regions(rest)), List.length(&2, Doc.Node, rest), region_count(rest))

# This projection retains the complete subtree and every event/attribute,
# while intentionally permitting only the region root's styles to change.

def Rule.evidence():
  Rule.Requirements{region_key_order, region_count, +key => +tag => +attrs => +styles => +events => +children => not_approval =>
      Equal.cong(Bool, (String & (String & (+List<Doc.Property> & (+List<Doc.Event> & +List<Doc.Node>)))),
        (approval => Rule.subtree(Render.dock_region_element(approval, key, tag, attrs, styles, events, children))),
        String.eq(Render.attr(attrs, "data-page-region"), Composition.region_name(Composition.ApprovalDecisions{})), False{}, not_approval)
    , +key => +tag => +attrs => +styles => +events => +children => {==}, extent => viewport => +intent => +bookmark => reduced => {==}, dock_overflow, +key => +children => {==}, +key => +children =>
        {==}

      # The existing queue's key, attributes and events remain on the scroll viewport.
    , +key => +tag => +attrs => +styles => +events => +children => {==}}
