import Base
import ./CONTENT.bend as Content
import ./PROGRAM.bend as Allocation
import ./physical-space.bend as Physical
import ./GEOMETRY.bend as Geometry
import ./SPACE.bend as Space
import ./enclosure.bend as Enclosure
import ../document/SOURCE.bend as Source
import ../document/MODEL.bend as Doc
import ../../interaction/IDENTITY.bend as Identity

# Queries observe allocated content room, rather than authored natural demand.
# Inert suppresses input reachability, but the region still occupies layout space.
type RegionQuery is Data:
  RegionKey{key: String}
  RegionAttribute{name: String, value: String}

def attribute_member(attributes: +List<Source.Attribute>, +name: String, +value: String) -> Bool:
  match attributes:
    case Nil{}: False{}
    case Con{Source.DataAttribute{current_name, current_value}, rest}:
      (String.eq(name, current_name) && String.eq(value, current_value)) || attribute_member(rest, name, value)
    case Con{other, rest}: attribute_member(rest, name, value)

def attributes_match(attributes: Maybe<&2, +List<Source.Attribute>>, name: String, value: String) -> Bool:
  match attributes:
    case None{}: False{}
    case Some{members}: attribute_member(members, name, value)

def region_matches_node(query: RegionQuery, +node: Source.Node) -> Bool:
  match query:
    case RegionKey{key}: String.eq(key, Identity.encode(Source.key_of(node)))
    case RegionAttribute{name, value}: attributes_match(Source.box_attributes_of(node), name, value)

def region_matches(query: RegionQuery, value: Content.Value) -> Bool:
  Content.Value{node, font} = value
  region_matches_node(query, node)

def bounds_width(bounds: Geometry.Box) -> Nat:
  Geometry.Box{left, top, width, height} = bounds
  width

def allocated_inner_width(bounds: Geometry.Box, rule: Physical.Rule) -> Nat:
  Geometry.Box{left, top, width, height} = bounds
  Nat.sub(width, Nat.mul(2n, Allocation.inline_inset(rule)))

def first_width(first: Maybe<&2, Nat>, remaining: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match first:
    case Some{width}: Some{width}
    case None{}: remaining

def observed_width(matches: Bool, bounds: Geometry.Box, rule: Physical.Rule, descendants: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match matches:
    case True{}: Some{allocated_inner_width(bounds, rule)}
    case False{}: descendants

def region_widths(trees: +List<Allocation.AllocatedTree<Content.Value, Doc.DOMEvent>>, +query: RegionQuery) -> Maybe<&2, Nat>:
  match trees:
    case Nil{}: None{}
    case Con{Allocation.AllocatedLeaf{key, +value, interaction, +rule, demand, height, +bounds, canvas}, rest}:
      first_width(observed_width(region_matches(query, value), bounds, rule, None{}), region_widths(rest, query))
    case Con{Allocation.AllocatedContainer{key, +value, interaction, +rule, +bounds, canvas, direction, children}, rest}:
      first_width(observed_width(region_matches(query, value), bounds, rule, region_widths(children, query)), region_widths(rest, query))

def region_width(tree: Allocation.AllocatedTree<Content.Value, Doc.DOMEvent>, query: RegionQuery) -> Maybe<&2, Nat>:
  region_widths(tree <> Nil{}, query)

def world_region_width(world: Content.AllocatedWorld, query: RegionQuery) -> Maybe<&2, Nat>:
  Content.AllocatedWorld{snapshot, tree, roots, policies} = world
  region_width(tree, query)

type RegionDemand is Data:
  RegionDemand{available: Nat, preferred: Nat}

def preferred_width(demand: Space.Demand) -> Nat:
  Space.Demand{minimum, preferred} = demand
  Enclosure.extent_width(preferred)

# Ideal single-row demand selects disclosure before the responsive row may wrap.
def ideal_reading_direction(direction: Physical.Direction) -> Physical.Direction:
  match direction:
    case Physical.ResponsiveHorizontal{}: Physical.Horizontal{}
    case other: other

def container_preferred(rule: Physical.Rule, children: +List<Allocation.AllocatedTree<Content.Value, Doc.DOMEvent>>) -> Nat:
  Physical.Rule{direction, main, cross, frame, border, width, height, minimum, scroll, position} = rule
  preferred_width(Physical.content_demand(Content.Value, Doc.DOMEvent,
    Allocation.source_forest_allocated(Content.Value, Doc.DOMEvent, children), ideal_reading_direction(direction), Enclosure.frame_gap(frame)))

def first_region_demand(first: Maybe<&2, RegionDemand>, remaining: Maybe<&2, RegionDemand>) -> Maybe<&2, RegionDemand>:
  match first:
    case Some{value}: Some{value}
    case None{}: remaining

def observed_region_demand(matches: Bool, bounds: Geometry.Box, rule: Physical.Rule, preferred: Nat, descendants: Maybe<&2, RegionDemand>) -> Maybe<&2, RegionDemand>:
  match matches:
    case True{}: Some{RegionDemand{allocated_inner_width(bounds, rule), preferred}}
    case False{}: descendants

def region_demands(trees: +List<Allocation.AllocatedTree<Content.Value, Doc.DOMEvent>>, +query: RegionQuery) -> Maybe<&2, RegionDemand>:
  match trees:
    case Nil{}: None{}
    case Con{Allocation.AllocatedLeaf{key, +value, interaction, +rule, demand, height, +bounds, canvas}, rest}:
      first_region_demand(observed_region_demand(region_matches(query, value), bounds, rule, preferred_width(demand), None{}), region_demands(rest, query))
    case Con{Allocation.AllocatedContainer{key, +value, interaction, +rule, +bounds, canvas, direction, +children}, rest}:
      first_region_demand(observed_region_demand(region_matches(query, value), bounds, rule, container_preferred(rule, children), region_demands(children, query)), region_demands(rest, query))

def region_demand(tree: Allocation.AllocatedTree<Content.Value, Doc.DOMEvent>, query: RegionQuery) -> Maybe<&2, RegionDemand>:
  region_demands(tree <> Nil{}, query)

def world_region_demand(world: Content.AllocatedWorld, query: RegionQuery) -> Maybe<&2, RegionDemand>:
  Content.AllocatedWorld{snapshot, tree, roots, policies} = world
  region_demand(tree, query)

type Requirements is Type:
  Requirements{
    ideal_responsive: {ideal_reading_direction(Physical.ResponsiveHorizontal{}) == Physical.Horizontal{} : Physical.Direction},
    ideal_preferred: @direction:Physical.Direction -> @main:Geometry.Alignment -> @cross:Geometry.Alignment -> @+frame:Enclosure.Frame -> @border:Nat -> @width:Physical.AxisSize -> @height:Physical.AxisSize -> @minimum:Enclosure.Extent -> @scroll:Physical.Scroll -> @position:Geometry.Position -> @+children:+List<Allocation.AllocatedTree<Content.Value, Doc.DOMEvent>> ->
      {container_preferred(Physical.Rule{direction, main, cross, frame, border, width, height, minimum, scroll, position}, children) == preferred_width(Physical.content_demand(Content.Value, Doc.DOMEvent, Allocation.source_forest_allocated(Content.Value, Doc.DOMEvent, children), ideal_reading_direction(direction), Enclosure.frame_gap(frame))) : Nat},
    requirement_leaf: @key:String -> @+value:Content.Value -> @interaction:Physical.Interaction<Doc.DOMEvent> -> @+rule:Physical.Rule -> @+demand:Space.Demand -> @height:Physical.Height -> @+bounds:Geometry.Box -> @canvas:Enclosure.Extent -> @+query:RegionQuery ->
      {region_demand(Allocation.AllocatedLeaf{key, value, interaction, rule, demand, height, bounds, canvas}, query) == observed_region_demand(region_matches(query, value), bounds, rule, preferred_width(demand), None{}) : Maybe<&2, RegionDemand>},
    requirement_container: @key:String -> @+value:Content.Value -> @interaction:Physical.Interaction<Doc.DOMEvent> -> @+rule:Physical.Rule -> @+bounds:Geometry.Box -> @canvas:Enclosure.Extent -> @direction:Allocation.ResolvedDirection -> @+children:+List<Allocation.AllocatedTree<Content.Value, Doc.DOMEvent>> -> @+query:RegionQuery ->
      {region_demand(Allocation.AllocatedContainer{key, value, interaction, rule, bounds, canvas, direction, children}, query) == observed_region_demand(region_matches(query, value), bounds, rule, container_preferred(rule, children), region_demands(children, query)) : Maybe<&2, RegionDemand>},
    requirement_world: @snapshot:Content.Snapshot -> @+tree:Allocation.AllocatedTree<Content.Value, Doc.DOMEvent> -> @roots:+List<Content.AllocatedNative> -> @policies:+List<Content.NativePolicy> -> @+query:RegionQuery ->
      {world_region_demand(Content.AllocatedWorld{snapshot, tree, roots, policies}, query) == region_demand(tree, query) : Maybe<&2, RegionDemand>},
    inner_width: @+bounds:Geometry.Box -> @+rule:Physical.Rule ->
      {allocated_inner_width(bounds, rule) == Nat.sub(bounds_width(bounds), Nat.mul(2n, Allocation.inline_inset(rule))) : Nat},
    leaf: @key:String -> @+value:Content.Value -> @interaction:Physical.Interaction<Doc.DOMEvent> -> @+rule:Physical.Rule -> @demand:Space.Demand -> @height:Physical.Height -> @+bounds:Geometry.Box -> @canvas:Enclosure.Extent -> @+query:RegionQuery ->
      {region_width(Allocation.AllocatedLeaf{key, value, interaction, rule, demand, height, bounds, canvas}, query) == observed_width(region_matches(query, value), bounds, rule, None{}) : Maybe<&2, Nat>},
    container: @key:String -> @+value:Content.Value -> @interaction:Physical.Interaction<Doc.DOMEvent> -> @+rule:Physical.Rule -> @+bounds:Geometry.Box -> @canvas:Enclosure.Extent -> @direction:Allocation.ResolvedDirection -> @+children:+List<Allocation.AllocatedTree<Content.Value, Doc.DOMEvent>> -> @+query:RegionQuery ->
      {region_width(Allocation.AllocatedContainer{key, value, interaction, rule, bounds, canvas, direction, children}, query) == observed_width(region_matches(query, value), bounds, rule, region_widths(children, query)) : Maybe<&2, Nat>},
    inert_preserves_attribute_membership: @+attributes:+List<Source.Attribute> -> @+name:String -> @+value:String ->
      {attribute_member(Source.InertAttribute{} <> attributes, name, value) == attribute_member(attributes, name, value) : Bool},
    world: @snapshot:Content.Snapshot -> @+tree:Allocation.AllocatedTree<Content.Value, Doc.DOMEvent> -> @roots:+List<Content.AllocatedNative> -> @policies:+List<Content.NativePolicy> -> @+query:RegionQuery ->
      {world_region_width(Content.AllocatedWorld{snapshot, tree, roots, policies}, query) == region_width(tree, query) : Maybe<&2, Nat>}}

law evidence:
  Requirements
