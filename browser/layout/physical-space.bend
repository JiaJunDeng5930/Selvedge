import Base
import ./GEOMETRY.bend as Spatial
import ./SPACE.bend as Space
import ./enclosure.bend as Enclosure

type AxisSize is Data:
  NaturalSize{}
  StretchSize{}
  CappedStretchSize{maximum: Nat}
  ExactSize{extent: Nat}
  LimitedSize{minimum: Nat, preferred_extra: Nat, maximum_extra: Nat}
  PercentSize{percent: Nat}
  CappedNaturalSize{maximum_percent: Nat}
  AdaptiveNaturalSize{preferred_maximum_percent: Nat}

type Direction is Data:
  Horizontal{}
  Vertical{}
  ResponsiveHorizontal{}
  Layered{}

type Scroll is Data:
  Confined{}
  ScrollHorizontally{}
  ScrollVertically{}
  ScrollBoth{}

type Interaction<-E: Data> is Data:
  DisplayOnly{}
  Operable{first: E, remaining: +List<E>, enabled: Bool}

type Height is Data:
  FixedHeight{height: Nat}
  HeightAtWidth{key: String}

type Rule is Data:
  Rule{direction: Direction, main_alignment: Spatial.Alignment,
    cross_alignment: Spatial.Alignment, frame: Enclosure.Frame, border: Nat,
    width: AxisSize, height: AxisSize, minimum: Enclosure.Extent, scroll: Scroll, position: Spatial.Position}

type Tree<-A: Data, -E: Data> is Data:
  Leaf{key: String, value: A, interaction: Interaction<E>, rule: Rule,
    demand: Space.Demand, height: Height}
  Container{key: String, value: A, interaction: Interaction<E>, rule: Rule,
    children: +List<Tree<A, E>>}

type HeightSample is Data:
  HeightSample{key: String, width: Nat, height: Nat}

type HeightRequest<-A: Data> is Data:
  HeightRequest{key: String, value: A, width: Nat}

def extent_max(first: Enclosure.Extent, second: Enclosure.Extent) -> Enclosure.Extent:
  Enclosure.Extent{first_width, first_height} = first
  Enclosure.Extent{second_width, second_height} = second
  Enclosure.Extent{Space.larger(first_width, second_width), Space.larger(first_height, second_height)}

def interaction_floor(~E: Data, +interaction: Interaction<E>) -> Enclosure.Extent:
  match interaction:
    case DisplayOnly{}: Enclosure.Extent{0n, 0n}
    case Operable{first, remaining, enabled}: Enclosure.Extent{32n, 32n}

def outer_extent(~E: Data, content: Enclosure.Extent, rule: Rule, interaction: Interaction<E>) -> Enclosure.Extent:
  Enclosure.Extent{width, height} = content
  Rule{direction, main_alignment, cross_alignment, frame, border, width_rule, height_rule, minimum, scroll, position} = rule
  extent_max(Enclosure.required_extent(width, height, border, Enclosure.frame_content(frame)),
    extent_max(minimum, interaction_floor(~E, interaction)))

# Scroll viewport floors are independent of overflowing content; preferred
# demand still retains the full content extent for allocation and scrolling.

def viewport_content_minimum(content: Enclosure.Extent, +scroll: Scroll) -> Enclosure.Extent:
  Enclosure.Extent{width, height} = content
  match scroll:
    case Confined{}: Enclosure.Extent{width, height}
    case ScrollHorizontally{}: Enclosure.Extent{0n, height}
    case ScrollVertically{}: Enclosure.Extent{width, 0n}
    case ScrollBoth{}: Enclosure.Extent{0n, 0n}

type AxisDemand is Data:
  AxisDemand{minimum: Nat, preferred: Nat}

# Authored lower bounds participate before ancestors choose their own size.
# Percentage constraints remain relative to the eventual offered extent.

def axis_demand(+size: AxisSize, +minimum: Nat, +preferred: Nat) -> AxisDemand:
  match size:
    case NaturalSize{}: AxisDemand{minimum, Nat.max(minimum, preferred)}
    case StretchSize{}: AxisDemand{minimum, Nat.max(minimum, preferred)}
    case CappedStretchSize{maximum}: AxisDemand{minimum, Nat.max(minimum, maximum)}
    case ExactSize{extent}:
      +lower = Nat.max(minimum, extent)
      AxisDemand{lower, lower}
    case LimitedSize{authored_minimum, preferred_extra, maximum_extra}:
      +lower = Nat.max(minimum, authored_minimum)
      +upper = Nat.add(Nat.add(authored_minimum, preferred_extra), maximum_extra)
      AxisDemand{lower, Nat.max(lower, Nat.min(upper, Nat.max(lower, Nat.max(minimum, preferred))))}
    case PercentSize{percent}: AxisDemand{minimum, Nat.max(minimum, preferred)}
    case CappedNaturalSize{maximum_percent}: AxisDemand{minimum, Nat.max(minimum, preferred)}
    case AdaptiveNaturalSize{preferred_maximum_percent}: AxisDemand{minimum, Nat.max(minimum, preferred)}

def demand_from_axes(width: AxisDemand, height: AxisDemand) -> Space.Demand:
  AxisDemand{lower_width, chosen_width} = width
  AxisDemand{lower_height, chosen_height} = height
  Space.Demand{Enclosure.Extent{lower_width, lower_height}, Enclosure.Extent{chosen_width, chosen_height}}

def authored_demand(+width: AxisSize, +height: AxisSize, content: Space.Demand) -> Space.Demand:
  Space.Demand{Enclosure.Extent{minimum_width, minimum_height}, Enclosure.Extent{preferred_width, preferred_height}} = content
  demand_from_axes(axis_demand(width, minimum_width, preferred_width), axis_demand(height, minimum_height, preferred_height))

def intrinsic_outer_demand(~E: Data, content: Space.Demand, +rule: Rule, +interaction: Interaction<E>) -> Space.Demand:
  Space.Demand{minimum, preferred} = content
  Rule{direction, main_alignment, cross_alignment, frame, border, width, height, explicit_minimum, scroll, position} = rule
  +lower = outer_extent(~E, viewport_content_minimum(minimum, scroll), rule, interaction)
  Space.Demand{lower, extent_max(lower, outer_extent(~E, preferred, rule, interaction))}

def outer_demand(~E: Data, content: Space.Demand, +rule: Rule, interaction: Interaction<E>) -> Space.Demand:
  Rule{direction, main_alignment, cross_alignment, frame, border, width, height, minimum, scroll, position} = rule
  authored_demand(width, height, intrinsic_outer_demand(~E, content, rule, interaction))

def fixed_leaf_content(demand: Space.Demand, +height: Nat) -> Space.Demand:
  Space.Demand{minimum, preferred} = demand
  Enclosure.Extent{minimum_width, minimum_height} = minimum
  Enclosure.Extent{preferred_width, preferred_height} = preferred
  +lower: Enclosure.Extent = Enclosure.Extent{minimum_width, Space.larger(minimum_height, height)}
  Space.Demand{lower, extent_max(lower, Enclosure.Extent{preferred_width, Space.larger(preferred_height, height)})}

def intrinsic_leaf_content(demand: Space.Demand) -> Space.Demand:
  Space.Demand{+minimum, preferred} = demand
  Space.Demand{minimum, extent_max(minimum, preferred)}

def leaf_content_demand(+demand: Space.Demand, height: Height) -> Space.Demand:
  match height:
    case FixedHeight{fixed}: fixed_leaf_content(demand, fixed)
    case HeightAtWidth{key}: intrinsic_leaf_content(demand)

def horizontal_extent(gap: Nat, first: Enclosure.Extent, rest: Enclosure.Extent) -> Enclosure.Extent:
  Enclosure.Extent{first_width, first_height} = first
  Enclosure.Extent{rest_width, rest_height} = rest
  Enclosure.Extent{Nat.add(first_width, Nat.add(gap, rest_width)), Space.larger(first_height, rest_height)}

def vertical_extent(gap: Nat, first: Enclosure.Extent, rest: Enclosure.Extent) -> Enclosure.Extent:
  Enclosure.Extent{first_width, first_height} = first
  Enclosure.Extent{rest_width, rest_height} = rest
  Enclosure.Extent{Space.larger(first_width, rest_width), Nat.add(first_height, Nat.add(gap, rest_height))}

def combine_extent(+direction: Direction, gap: Nat, first: Enclosure.Extent, rest: Enclosure.Extent) -> Enclosure.Extent:
  match direction:
    case Horizontal{}: horizontal_extent(gap, first, rest)
    case Layered{}: extent_max(first, rest)
    case _: vertical_extent(gap, first, rest)

def position_outside(+position: Spatial.Position) -> Enclosure.Insets:
  match position:
    case Spatial.InFlow{}: Enclosure.Insets{0n, 0n}
    case Spatial.CenteredLayer{outside}: outside
    case Spatial.AlignedLayer{outside, horizontal, vertical}: outside
    case Spatial.AnchoredLayer{anchor_key, anchor, outside, gap, alignment}: outside

def clearance_extent_layered(outside: Enclosure.Insets, extent: Enclosure.Extent) -> Enclosure.Extent:
  Enclosure.Insets{inline, block} = outside
  Enclosure.Extent{width, height} = extent
  Enclosure.Extent{Nat.add(width, Nat.mul(2n, inline)), Nat.add(height, Nat.mul(2n, block))}

def clearance_extent(+direction: Direction, position: Spatial.Position, +extent: Enclosure.Extent) -> Enclosure.Extent:
  match direction:
    case Layered{}: clearance_extent_layered(position_outside(position), extent)
    case _: extent

def clearance_layered_demand(+position: Spatial.Position, demand: Space.Demand) -> Space.Demand:
  Space.Demand{minimum, preferred} = demand
  Space.Demand{clearance_extent(Layered{}, position, minimum), clearance_extent(Layered{}, position, preferred)}

def clearance_demand(+direction: Direction, +position: Spatial.Position, +demand: Space.Demand) -> Space.Demand:
  match direction:
    case Layered{}: clearance_layered_demand(position, demand)
    case _: demand

def rule_position(rule: Rule) -> Spatial.Position:
  Rule{direction, main_alignment, cross_alignment, frame, border, width, height, minimum, scroll, position} = rule
  position

def remaining_gap(~A: Data, ~E: Data, +trees: +List<Tree<A, E>>, gap: Nat) -> Nat:
  match trees:
    case Nil{}: 0n
    case Con{head, rest}: gap

def prepend_demand(+direction: Direction, +gap: Nat, first: Space.Demand, rest: Space.Demand) -> Space.Demand:
  Space.Demand{first_minimum, first_preferred} = first
  Space.Demand{rest_minimum, rest_preferred} = rest
  +minimum = combine_extent(direction, gap, first_minimum, rest_minimum)
  Space.Demand{minimum, extent_max(minimum, combine_extent(direction, gap, first_preferred, rest_preferred))}

# Responsive intrinsic requirements retain column height; row feasibility uses
# the same fold with Horizontal at the offered-width allocation boundary.

def content_demand(~A: Data, ~E: Data, +trees: +List<Tree<A, E>>, +direction: Direction, +gap: Nat) -> Space.Demand:
  match trees:
    case Nil{}: Space.fixed_demand(0n, 0n)
    case Con{Leaf{key, value, interaction, +rule, demand, height}, +rest}:
      prepend_demand(direction, remaining_gap(~A, ~E, rest, gap), clearance_demand(direction, rule_position(rule), outer_demand(~E, leaf_content_demand(demand, height), rule, interaction)),
        content_demand(~A, ~E, rest, direction, gap))
    case Con{Container{key, value, interaction, +rule, children}, +rest}:
      Rule{+child_direction, main_alignment, cross_alignment, +frame, border, width, height, minimum, scroll, position} = rule
      prepend_demand(direction, remaining_gap(~A, ~E, rest, gap),
        clearance_demand(direction, position, outer_demand(~E, content_demand(~A, ~E, children, child_direction, Enclosure.frame_gap(frame)), rule, interaction)),
        content_demand(~A, ~E, rest, direction, gap))

def demand(~A: Data, ~E: Data, tree: Tree<A, E>) -> Space.Demand:
  content_demand(~A, ~E, tree <> Nil{}, Horizontal{}, 0n)

def minimum_demand(value: Space.Demand) -> Enclosure.Extent:
  Space.Demand{minimum, preferred} = value
  minimum

def accept_dimension(+fits: Bool, value: Space.Dimension) -> Maybe<&2, Space.Dimension>:
  match fits:
    case False{}: None{}
    case True{}: Some{value}

# Reject invalid percentages before evaluating quotient/remainder arithmetic.

def percentage_checked(+valid: Bool, +offered: Nat, +percent: Nat) -> Maybe<&2, Nat>:
  match valid:
    case False{}: None{}
    case True{}:
      Some{Nat.add(Nat.mul(Nat.div(offered, 100n), percent), Nat.div(Nat.mul(Nat.mod(offered, 100n), percent), 100n))}

def percentage_extent(+offered: Nat, +percent: Nat) -> Maybe<&2, Nat>:
  percentage_checked(Nat.is_le(percent, 100n), offered, percent)

def percentage_dimension(+extent: Maybe<&2, Nat>, +minimum: Nat) -> Maybe<&2, Space.Dimension>:
  match extent:
    case None{}: None{}
    case Some{+extent}: accept_dimension(Nat.is_le(minimum, extent), Space.Rigid{extent})

def capped_dimension(+extent: Maybe<&2, Nat>, +minimum: Nat, +preferred: Nat) -> Maybe<&2, Space.Dimension>:
  match extent:
    case None{}: None{}
    case Some{+cap}:
      +chosen = Space.smaller(cap, Space.larger(minimum, preferred))
      accept_dimension(Nat.is_le(minimum, cap), Space.Fit{minimum, Nat.sub(chosen, minimum), Nat.sub(cap, chosen)})

# A preferred cap yields to content minima while the offered space stays hard.

def adaptive_checked(+fits: Bool, +minimum: Nat, +preferred: Nat, +offered: Nat, +nominal_cap: Nat) -> Maybe<&2, Space.Dimension>:
  +maximum = Space.smaller(offered, Space.larger(minimum, nominal_cap))
  +chosen = Space.smaller(maximum, Space.larger(minimum, preferred))
  accept_dimension(fits, Space.Fit{minimum, Nat.sub(chosen, minimum), Nat.sub(maximum, chosen)})

def adaptive_dimension(extent: Maybe<&2, Nat>, +minimum: Nat, preferred: Nat, +offered: Nat) -> Maybe<&2, Space.Dimension>:
  match extent:
    case None{}: None{}
    case Some{cap}: adaptive_checked(Nat.is_le(minimum, offered), minimum, preferred, offered, cap)

def materialize(+size: AxisSize, +minimum: Nat, +preferred: Nat, +offered: Nat) -> Maybe<&2, Space.Dimension>:
  match size:
    case NaturalSize{}: Some{Space.Fit{minimum, Nat.sub(Space.larger(minimum, preferred), minimum), 0n}}
    case StretchSize{}: Some{Space.Fill{minimum}}
    case CappedStretchSize{maximum}: accept_dimension(Nat.is_le(minimum, maximum), Space.Fit{minimum, Nat.sub(maximum, minimum), 0n})
    case ExactSize{+extent}: accept_dimension(Nat.is_le(minimum, extent), Space.Rigid{extent})
    case LimitedSize{+authored_minimum, +preferred_extra, maximum_extra}:
      +maximum = Nat.add(Nat.add(authored_minimum, preferred_extra), maximum_extra)
      +lower = Space.larger(minimum, authored_minimum)
      +chosen = Space.smaller(maximum, Space.larger(lower, preferred))
      accept_dimension(Nat.is_le(lower, maximum), Space.Fit{lower, Nat.sub(chosen, lower), Nat.sub(maximum, chosen)})
    case PercentSize{+percent}: percentage_dimension(percentage_extent(offered, percent), minimum)
    case CappedNaturalSize{+maximum_percent}: capped_dimension(percentage_extent(offered, maximum_percent), minimum, preferred)
    case AdaptiveNaturalSize{+preferred_maximum_percent}: adaptive_dimension(percentage_extent(offered, preferred_maximum_percent), minimum, preferred, offered)
