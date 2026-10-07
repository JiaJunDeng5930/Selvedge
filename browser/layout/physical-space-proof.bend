import Base
import ./GEOMETRY.bend as Spatial
import ./physical-space.bend as Model
import ./physical-space-rules.bend as ModelRules
import ./SPACE.bend as Space
import ./enclosure.bend as Enclosure
import ../../bendlib/algebra-proof.bend as Alg
import ./space-proof.bend as Order
import ../../bendlib/logic-proof.bend as Logic

def demand_max_left(+first: Nat, +second: Nat) ->
  {Nat.is_le(first, Space.larger(first, second)) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(first, Space.larger(first, second)), Nat.is_le(first, Nat.max(first, second)), True{},
    Equal.cong(Nat, Bool, (n => Nat.is_le(first, n)), Space.larger(first, second), Nat.max(first, second), Order.larger_eq_max(first, second)),
    Order.max_left(first, second))

def demand_max_right(+first: Nat, +second: Nat) ->
  {Nat.is_le(second, Space.larger(first, second)) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(second, Space.larger(first, second)), Nat.is_le(second, Nat.max(first, second)), True{},
    Equal.cong(Nat, Bool, (n => Nat.is_le(second, n)), Space.larger(first, second), Nat.max(first, second), Order.larger_eq_max(first, second)),
    Order.max_right(first, second))

def and_left(+a: Bool, +b: Bool, evidence: {Bool.and(a, b) == True{} : Bool}) -> {a == True{} : Bool}:
  Order.first({a == True{} : Bool}, {b == True{} : Bool}, Order.and_parts(a, b, evidence))

def and_right(+a: Bool, +b: Bool, evidence: {Bool.and(a, b) == True{} : Bool}) -> {b == True{} : Bool}:
  Order.second({a == True{} : Bool}, {b == True{} : Bool}, Order.and_parts(a, b, evidence))

def max_contains_first(+first: Enclosure.Extent, +second: Enclosure.Extent) ->
  {ModelRules.extent_contains(Model.extent_max(first, second), first) == True{} : Bool}:
  Enclosure.Extent{+w, +h} = first
  Enclosure.Extent{+x, +y} = second
  Order.and_join(Nat.is_le(w, Space.larger(w, x)), Nat.is_le(h, Space.larger(h, y)),
    demand_max_left(w, x), demand_max_left(h, y))

def max_contains_second(+first: Enclosure.Extent, +second: Enclosure.Extent) ->
  {ModelRules.extent_contains(Model.extent_max(first, second), second) == True{} : Bool}:
  Enclosure.Extent{+w, +h} = first
  Enclosure.Extent{+x, +y} = second
  Order.and_join(Nat.is_le(x, Space.larger(w, x)), Nat.is_le(y, Space.larger(h, y)),
    demand_max_right(w, x), demand_max_right(h, y))

def contains_trans(+outer: Enclosure.Extent, +middle: Enclosure.Extent, +inner: Enclosure.Extent,
  +first: {ModelRules.extent_contains(outer, middle) == True{} : Bool},
  +second: {ModelRules.extent_contains(middle, inner) == True{} : Bool}) ->
  {ModelRules.extent_contains(outer, inner) == True{} : Bool}:
  Enclosure.Extent{+w, +h} = outer
  Enclosure.Extent{+x, +y} = middle
  Enclosure.Extent{+a, +b} = inner
  wx = and_left(Nat.is_le(x, w), Nat.is_le(y, h), first)
  hy = and_right(Nat.is_le(x, w), Nat.is_le(y, h), first)
  xa = and_left(Nat.is_le(a, x), Nat.is_le(b, y), second)
  yb = and_right(Nat.is_le(a, x), Nat.is_le(b, y), second)
  Order.and_join(Nat.is_le(a, w), Nat.is_le(b, h), Order.le_trans(a, x, w, xa, wx), Order.le_trans(b, y, h, yb, hy))

def add_contains_second(+first: Nat, +second: Nat) ->
  {Nat.is_le(second, Nat.add(first, second)) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(second, Nat.add(first, second)), Nat.is_le(second, Nat.add(second, first)), True{},
    Equal.cong(Nat, Bool, (n => Nat.is_le(second, n)), Nat.add(first, second), Nat.add(second, first), Order.add_comm(first, second)), Order.le_add(second, first))

def combine_first_horizontal(+gap: Nat, +first: Enclosure.Extent, +rest: Enclosure.Extent) ->
  {ModelRules.extent_contains(Model.horizontal_extent(gap, first, rest), first) == True{} : Bool}:
  Enclosure.Extent{+w, +h} = first
  Enclosure.Extent{+x, +y} = rest
  Order.and_join(Nat.is_le(w, Nat.add(w, Nat.add(gap, x))), Nat.is_le(h, Space.larger(h, y)), Order.le_add(w, Nat.add(gap, x)), demand_max_left(h, y))

def combine_first_vertical(+gap: Nat, +first: Enclosure.Extent, +rest: Enclosure.Extent) ->
  {ModelRules.extent_contains(Model.vertical_extent(gap, first, rest), first) == True{} : Bool}:
  Enclosure.Extent{+w, +h} = first
  Enclosure.Extent{+x, +y} = rest
  Order.and_join(Nat.is_le(w, Space.larger(w, x)), Nat.is_le(h, Nat.add(h, Nat.add(gap, y))), demand_max_left(w, x), Order.le_add(h, Nat.add(gap, y)))

def combine_first(+direction: Model.Direction, +gap: Nat, +first: Enclosure.Extent, +rest: Enclosure.Extent) ->
  {ModelRules.extent_contains(Model.combine_extent(direction, gap, first, rest), first) == True{} : Bool}:
  match direction:
    case Model.Horizontal{}: combine_first_horizontal(gap, first, rest)
    case Model.Vertical{}: combine_first_vertical(gap, first, rest)
    case Model.ResponsiveHorizontal{}: combine_first_vertical(gap, first, rest)
    case Model.Layered{}: max_contains_first(first, rest)

def combine_rest_horizontal(+gap: Nat, +first: Enclosure.Extent, +rest: Enclosure.Extent) ->
  {ModelRules.extent_contains(Model.horizontal_extent(gap, first, rest), rest) == True{} : Bool}:
  Enclosure.Extent{+w, +h} = first
  Enclosure.Extent{+x, +y} = rest
  Order.and_join(Nat.is_le(x, Nat.add(w, Nat.add(gap, x))), Nat.is_le(y, Space.larger(h, y)),
    Order.le_trans(x, Nat.add(gap, x), Nat.add(w, Nat.add(gap, x)), add_contains_second(gap, x), add_contains_second(w, Nat.add(gap, x))), demand_max_right(h, y))

def combine_rest_vertical(+gap: Nat, +first: Enclosure.Extent, +rest: Enclosure.Extent) ->
  {ModelRules.extent_contains(Model.vertical_extent(gap, first, rest), rest) == True{} : Bool}:
  Enclosure.Extent{+w, +h} = first
  Enclosure.Extent{+x, +y} = rest
  Order.and_join(Nat.is_le(x, Space.larger(w, x)), Nat.is_le(y, Nat.add(h, Nat.add(gap, y))), demand_max_right(w, x),
    Order.le_trans(y, Nat.add(gap, y), Nat.add(h, Nat.add(gap, y)), add_contains_second(gap, y), add_contains_second(h, Nat.add(gap, y))))

def combine_rest(+direction: Model.Direction, +gap: Nat, +first: Enclosure.Extent, +rest: Enclosure.Extent) ->
  {ModelRules.extent_contains(Model.combine_extent(direction, gap, first, rest), rest) == True{} : Bool}:
  match direction:
    case Model.Horizontal{}: combine_rest_horizontal(gap, first, rest)
    case Model.Vertical{}: combine_rest_vertical(gap, first, rest)
    case Model.ResponsiveHorizontal{}: combine_rest_vertical(gap, first, rest)
    case Model.Layered{}: max_contains_second(first, rest)

def max_zero(+value: Nat) -> {Nat.max(value, 0n) == value : Nat}:
  match value:
    case 0n: {==}
    case 1n+rest: {==}

def demand_max_zero(+value: Nat) -> {Space.larger(value, 0n) == value : Nat}:
  Equal.trans(Nat, Space.larger(value, 0n), Nat.max(value, 0n), value, Order.larger_eq_max(value, 0n), max_zero(value))

def combine_empty(+extent: Enclosure.Extent) ->
  {Model.combine_extent(Model.Horizontal{}, 0n, extent, Enclosure.Extent{0n, 0n}) == extent : Enclosure.Extent}:
  Enclosure.Extent{+w, +h} = extent
  Equal.trans(Enclosure.Extent, Enclosure.Extent{Nat.add(w, 0n), Space.larger(h, 0n)}, Enclosure.Extent{w, Space.larger(h, 0n)}, Enclosure.Extent{w, h},
    Equal.cong(Nat, Enclosure.Extent, (n => Enclosure.Extent{n, Space.larger(h, 0n)}), Nat.add(w, 0n), w, Alg.nat_add_zero(w)),
    Equal.cong(Nat, Enclosure.Extent, (n => Enclosure.Extent{w, n}), Space.larger(h, 0n), h, demand_max_zero(h)))

def singleton_minimum(+first: Space.Demand) ->
  {Model.minimum_demand(Model.prepend_demand(Model.Horizontal{}, 0n, first, Space.fixed_demand(0n, 0n))) == Model.minimum_demand(first) : Enclosure.Extent}:
  Space.Demand{+minimum, preferred} = first
  combine_empty(minimum)

def prepend_preferred(+direction: Model.Direction, +gap: Nat, +first: Space.Demand, +rest: Space.Demand) ->
  {ModelRules.preferred_covers_minimum(Model.prepend_demand(direction, gap, first, rest)) == True{} : Bool}:
  Space.Demand{+a, b} = first
  Space.Demand{+c, d} = rest
  max_contains_first(Model.combine_extent(direction, gap, a, c), Model.combine_extent(direction, gap, b, d))

def extent_contains_self(+extent: Enclosure.Extent) ->
  {ModelRules.extent_contains(extent, extent) == True{} : Bool}:
  Enclosure.Extent{+width, +height} = extent
  Order.and_join(Nat.is_le(width, width), Nat.is_le(height, height), Order.le_refl(width), Order.le_refl(height))

def clearance_layered_contains(+outside: Enclosure.Insets, +extent: Enclosure.Extent) ->
  {ModelRules.extent_contains(Model.clearance_extent_layered(outside, extent), extent) == True{} : Bool}:
  Enclosure.Insets{+inline, +block} = outside
  Enclosure.Extent{+width, +height} = extent
  Order.and_join(Nat.is_le(width, Nat.add(width, Nat.mul(2n, inline))), Nat.is_le(height, Nat.add(height, Nat.mul(2n, block))),
    Order.le_add(width, Nat.mul(2n, inline)), Order.le_add(height, Nat.mul(2n, block)))

def clearance_contains(+direction: Model.Direction, +position: Spatial.Position, +extent: Enclosure.Extent) ->
  {ModelRules.extent_contains(Model.clearance_extent(direction, position, extent), extent) == True{} : Bool}:
  match direction:
    case Model.Layered{}: clearance_layered_contains(Model.position_outside(position), extent)
    case Model.Horizontal{}: extent_contains_self(extent)
    case Model.Vertical{}: extent_contains_self(extent)
    case Model.ResponsiveHorizontal{}: extent_contains_self(extent)

def preferred_content(~A: Data, ~E: Data, +trees: +List<Model.Tree<A, E>>, +direction: Model.Direction, +gap: Nat) ->
  {ModelRules.preferred_covers_minimum(Model.content_demand(~A, ~E, trees, direction, gap)) == True{} : Bool}:
  match trees:
    case Nil{}: {==}
    case Con{Model.Leaf{key, value, interaction, +rule, demand, height}, +rest}:
      prepend_preferred(direction, Model.remaining_gap(~A, ~E, rest, gap), Model.clearance_demand(direction, Model.rule_position(rule), Model.outer_demand(~E, Model.leaf_content_demand(demand, height), rule, interaction)), Model.content_demand(~A, ~E, rest, direction, gap))
    case Con{Model.Container{key, value, interaction, +rule, children}, +rest}:
      Model.Rule{child_direction, main, cross, frame, border, width, height, minimum, scroll, position} = rule
      prepend_preferred(direction, Model.remaining_gap(~A, ~E, rest, gap),
        Model.clearance_demand(direction, position, Model.outer_demand(~E, Model.content_demand(~A, ~E, children, child_direction, Enclosure.frame_gap(frame)), rule, interaction)), Model.content_demand(~A, ~E, rest, direction, gap))

def children_raise(~A: Data, ~E: Data, +trees: +List<Model.Tree<A, E>>, +outer: Enclosure.Extent, +inner: Enclosure.Extent,
  +contains: {ModelRules.extent_contains(outer, inner) == True{} : Bool},
  +participating: {ModelRules.child_minima_participate(~A, ~E, trees, inner) == True{} : Bool}) ->
  {ModelRules.child_minima_participate(~A, ~E, trees, outer) == True{} : Bool}:
  match trees:
    case Nil{}: {==}
    case Con{+tree, +rest}:
      +minimum = Model.minimum_demand(Model.demand(~A, ~E, tree))
      head = and_left(ModelRules.extent_contains(inner, minimum), ModelRules.child_minima_participate(~A, ~E, rest, inner), participating)
      tail = and_right(ModelRules.extent_contains(inner, minimum), ModelRules.child_minima_participate(~A, ~E, rest, inner), participating)
      Order.and_join(ModelRules.extent_contains(outer, minimum), ModelRules.child_minima_participate(~A, ~E, rest, outer),
        contains_trans(outer, inner, minimum, contains, head), children_raise(~A, ~E, rest, outer, inner, contains, tail))

def prepend_children(~A: Data, ~E: Data, +tree: Model.Tree<A, E>, +rest: +List<Model.Tree<A, E>>, +direction: Model.Direction, +gap: Nat, +first: Space.Demand, +remaining: Space.Demand,
  same: {ModelRules.extent_contains(Model.minimum_demand(first), Model.minimum_demand(Model.demand(~A, ~E, tree))) == True{} : Bool},
  tail: {ModelRules.child_minima_participate(~A, ~E, rest, Model.minimum_demand(remaining)) == True{} : Bool}) ->
  {ModelRules.child_minima_participate(~A, ~E, tree <> rest, Model.minimum_demand(Model.prepend_demand(direction, gap, first, remaining))) == True{} : Bool}:
  Space.Demand{+a, b} = first
  Space.Demand{+c, d} = remaining
  +required = Model.combine_extent(direction, gap, a, c)
  head = contains_trans(required, a, Model.minimum_demand(Model.demand(~A, ~E, tree)), combine_first(direction, gap, a, c), same)
  Order.and_join(ModelRules.extent_contains(required, Model.minimum_demand(Model.demand(~A, ~E, tree))), ModelRules.child_minima_participate(~A, ~E, rest, required),
    head, children_raise(~A, ~E, rest, required, c, combine_rest(direction, gap, a, c), tail))

def clearance_demand_contains(+direction: Model.Direction, +position: Spatial.Position, +minimum: Enclosure.Extent, +preferred: Enclosure.Extent) ->
  {ModelRules.extent_contains(Model.minimum_demand(Model.clearance_demand(direction, position, Space.Demand{minimum, preferred})), minimum) == True{} : Bool}:
  match direction:
    case Model.Layered{}: clearance_contains(Model.Layered{}, position, minimum)
    case Model.Horizontal{}: extent_contains_self(minimum)
    case Model.Vertical{}: extent_contains_self(minimum)
    case Model.ResponsiveHorizontal{}: extent_contains_self(minimum)

def clearance_singleton(+direction: Model.Direction, +position: Spatial.Position, +first: Space.Demand) ->
  {ModelRules.extent_contains(Model.minimum_demand(Model.clearance_demand(direction, position, first)), Model.minimum_demand(Model.prepend_demand(Model.Horizontal{}, 0n, first, Space.fixed_demand(0n, 0n)))) == True{} : Bool}:
  Space.Demand{minimum, preferred} = first
  Equal.trans(Bool,
    ModelRules.extent_contains(Model.minimum_demand(Model.clearance_demand(direction, position, first)), Model.minimum_demand(Model.prepend_demand(Model.Horizontal{}, 0n, first, Space.fixed_demand(0n, 0n)))),
    ModelRules.extent_contains(Model.minimum_demand(Model.clearance_demand(direction, position, first)), Model.minimum_demand(first)), True{},
    Equal.cong(Enclosure.Extent, Bool, (extent => ModelRules.extent_contains(Model.minimum_demand(Model.clearance_demand(direction, position, first)), extent)),
      Model.minimum_demand(Model.prepend_demand(Model.Horizontal{}, 0n, first, Space.fixed_demand(0n, 0n))), Model.minimum_demand(first), singleton_minimum(first)),
    clearance_demand_contains(direction, position, minimum, preferred))

def children_content(~A: Data, ~E: Data, +trees: +List<Model.Tree<A, E>>, +direction: Model.Direction, +gap: Nat) ->
  {ModelRules.child_minima_participate(~A, ~E, trees, Model.minimum_demand(Model.content_demand(~A, ~E, trees, direction, gap))) == True{} : Bool}:
  match trees:
    case Nil{}: {==}
    case Con{Model.Leaf{+key, +value, +interaction, +rule, +demand, +height}, +rest}:
      +first = Model.outer_demand(~E, Model.leaf_content_demand(demand, height), rule, interaction)
      prepend_children(~A, ~E, Model.Leaf{key, value, interaction, rule, demand, height}, rest, direction, Model.remaining_gap(~A, ~E, rest, gap), Model.clearance_demand(direction, Model.rule_position(rule), first), Model.content_demand(~A, ~E, rest, direction, gap),
        clearance_singleton(direction, Model.rule_position(rule), first), children_content(~A, ~E, rest, direction, gap))
    case Con{Model.Container{+key, +value, +interaction, +rule, +children}, +rest}:
      Model.Rule{+child_direction, main, cross, +frame, border, width, height, minimum, scroll, position} = rule
      +first = Model.outer_demand(~E, Model.content_demand(~A, ~E, children, child_direction, Enclosure.frame_gap(frame)), rule, interaction)
      prepend_children(~A, ~E, Model.Container{key, value, interaction, rule, children}, rest, direction, Model.remaining_gap(~A, ~E, rest, gap), Model.clearance_demand(direction, Model.rule_position(rule), first), Model.content_demand(~A, ~E, rest, direction, gap),
        clearance_singleton(direction, Model.rule_position(rule), first), children_content(~A, ~E, rest, direction, gap))

def axis_authored_floor(+size: Model.AxisSize, +minimum: Nat, +preferred: Nat) ->
  {Nat.is_le(ModelRules.authored_minimum(size), ModelRules.axis_minimum(Model.axis_demand(size, minimum, preferred))) == True{} : Bool}:
  match size:
    case Model.NaturalSize{}: Order.zero_le(minimum)
    case Model.StretchSize{}: Order.zero_le(minimum)
    case Model.CappedStretchSize{maximum}: Order.zero_le(minimum)
    case Model.ExactSize{extent}: Order.max_right(minimum, extent)
    case Model.LimitedSize{authored, extra, maximum}: Order.max_right(minimum, authored)
    case Model.PercentSize{percent}: Order.zero_le(minimum)
    case Model.CappedNaturalSize{percent}: Order.zero_le(minimum)
    case Model.AdaptiveNaturalSize{percent}: Order.zero_le(minimum)

def axis_intrinsic_floor(+size: Model.AxisSize, +minimum: Nat, +preferred: Nat) ->
  {Nat.is_le(minimum, ModelRules.axis_minimum(Model.axis_demand(size, minimum, preferred))) == True{} : Bool}:
  match size:
    case Model.NaturalSize{}: Order.le_refl(minimum)
    case Model.StretchSize{}: Order.le_refl(minimum)
    case Model.CappedStretchSize{maximum}: Order.le_refl(minimum)
    case Model.ExactSize{extent}: Order.max_left(minimum, extent)
    case Model.LimitedSize{authored, extra, maximum}: Order.max_left(minimum, authored)
    case Model.PercentSize{percent}: Order.le_refl(minimum)
    case Model.CappedNaturalSize{percent}: Order.le_refl(minimum)
    case Model.AdaptiveNaturalSize{percent}: Order.le_refl(minimum)

def axis_preferred_floor(+size: Model.AxisSize, +minimum: Nat, +preferred: Nat) ->
  {Nat.is_le(ModelRules.axis_minimum(Model.axis_demand(size, minimum, preferred)), ModelRules.axis_preferred(Model.axis_demand(size, minimum, preferred))) == True{} : Bool}:
  match size:
    case Model.NaturalSize{}: Order.max_left(minimum, preferred)
    case Model.StretchSize{}: Order.max_left(minimum, preferred)
    case Model.CappedStretchSize{maximum}: Order.max_left(minimum, maximum)
    case Model.ExactSize{extent}: Order.le_refl(Nat.max(minimum, extent))
    case Model.LimitedSize{authored, extra, maximum}:
      Order.max_left(Nat.max(minimum, authored), Nat.min(Nat.add(Nat.add(authored, extra), maximum), Nat.max(Nat.max(minimum, authored), Nat.max(minimum, preferred))))
    case Model.PercentSize{percent}: Order.max_left(minimum, preferred)
    case Model.CappedNaturalSize{percent}: Order.max_left(minimum, preferred)
    case Model.AdaptiveNaturalSize{percent}: Order.max_left(minimum, preferred)

def axes_floor(+width: Model.AxisDemand, +height: Model.AxisDemand, +mw: Nat, +mh: Nat,
  +width_floor: {Nat.is_le(mw, ModelRules.axis_minimum(width)) == True{} : Bool},
  +height_floor: {Nat.is_le(mh, ModelRules.axis_minimum(height)) == True{} : Bool}) ->
  {ModelRules.extent_contains(Model.minimum_demand(Model.demand_from_axes(width, height)), Enclosure.Extent{mw, mh}) == True{} : Bool}:
  Model.AxisDemand{lower_width, chosen_width} = width
  Model.AxisDemand{lower_height, chosen_height} = height
  Order.and_join(Nat.is_le(mw, lower_width), Nat.is_le(mh, lower_height), width_floor, height_floor)

def authored_floor(+width: Model.AxisSize, +height: Model.AxisSize, +content: Space.Demand) ->
  {ModelRules.extent_contains(Model.minimum_demand(Model.authored_demand(width, height, content)), Model.minimum_demand(content)) == True{} : Bool}:
  Space.Demand{Enclosure.Extent{+mw, +mh}, Enclosure.Extent{+pw, +ph}} = content
  axes_floor(Model.axis_demand(width, mw, pw), Model.axis_demand(height, mh, ph), mw, mh,
    axis_intrinsic_floor(width, mw, pw), axis_intrinsic_floor(height, mh, ph))

def axes_preferred(+width: Model.AxisDemand, +height: Model.AxisDemand,
  +width_floor: {Nat.is_le(ModelRules.axis_minimum(width), ModelRules.axis_preferred(width)) == True{} : Bool},
  +height_floor: {Nat.is_le(ModelRules.axis_minimum(height), ModelRules.axis_preferred(height)) == True{} : Bool}) ->
  {ModelRules.preferred_covers_minimum(Model.demand_from_axes(width, height)) == True{} : Bool}:
  Model.AxisDemand{lower_width, chosen_width} = width
  Model.AxisDemand{lower_height, chosen_height} = height
  Order.and_join(Nat.is_le(lower_width, chosen_width), Nat.is_le(lower_height, chosen_height), width_floor, height_floor)

def authored_preferred(+width: Model.AxisSize, +height: Model.AxisSize, +content: Space.Demand) ->
  {ModelRules.preferred_covers_minimum(Model.authored_demand(width, height, content)) == True{} : Bool}:
  Space.Demand{Enclosure.Extent{+mw, +mh}, Enclosure.Extent{+pw, +ph}} = content
  axes_preferred(Model.axis_demand(width, mw, pw), Model.axis_demand(height, mh, ph),
    axis_preferred_floor(width, mw, pw), axis_preferred_floor(height, mh, ph))

def authored_lower_pair(+width: Model.AxisSize, +height: Model.AxisSize, content: Space.Demand) ->
  {ModelRules.extent_contains(Model.minimum_demand(Model.authored_demand(width, height, content)), Enclosure.Extent{ModelRules.authored_minimum(width), ModelRules.authored_minimum(height)}) == True{} : Bool}:
  Space.Demand{Enclosure.Extent{+mw, +mh}, Enclosure.Extent{+pw, +ph}} = content
  axes_floor(Model.axis_demand(width, mw, pw), Model.axis_demand(height, mh, ph), ModelRules.authored_minimum(width), ModelRules.authored_minimum(height),
    axis_authored_floor(width, mw, pw), axis_authored_floor(height, mh, ph))

def outer_authored_floor(~E: Data, +content: Space.Demand, +rule: Model.Rule, +interaction: Model.Interaction<E>) ->
  {ModelRules.extent_contains(Model.minimum_demand(Model.outer_demand(~E, content, rule, interaction)), ModelRules.rule_authored_minimum(rule)) == True{} : Bool}:
  Model.Rule{direction, main, cross, frame, border, width, height, minimum, scroll, position} = rule
  authored_lower_pair(width, height, Model.intrinsic_outer_demand(~E, content, rule, interaction))

def outer_preferred(~E: Data, +content: Space.Demand, +rule: Model.Rule, +interaction: Model.Interaction<E>) ->
  {ModelRules.preferred_covers_minimum(Model.outer_demand(~E, content, rule, interaction)) == True{} : Bool}:
  Model.Rule{direction, main, cross, frame, border, width, height, minimum, scroll, position} = rule
  authored_preferred(width, height, Model.intrinsic_outer_demand(~E, content, rule, interaction))

def outer_intrinsic_floor(~E: Data, +content: Space.Demand, +rule: Model.Rule, +interaction: Model.Interaction<E>) ->
  {ModelRules.extent_contains(Model.minimum_demand(Model.outer_demand(~E, content, rule, interaction)), Model.minimum_demand(Model.intrinsic_outer_demand(~E, content, rule, interaction))) == True{} : Bool}:
  Model.Rule{direction, main, cross, frame, border, width, height, minimum, scroll, position} = rule
  authored_floor(width, height, Model.intrinsic_outer_demand(~E, content, rule, interaction))

def operable_outer(~E: Data, +content: Enclosure.Extent, +rule: Model.Rule, +first: E, +remaining: +List<E>, +enabled: Bool) ->
  {ModelRules.extent_contains(Model.outer_extent(~E, content, rule, Model.Operable{first, remaining, enabled}), Enclosure.Extent{32n, 32n}) == True{} : Bool}:
  Enclosure.Extent{+w, +h} = content
  Model.Rule{direction, main, cross, +frame, +border, width, height, +minimum, scroll, position} = rule
  contains_trans(Model.extent_max(Enclosure.required_extent(w, h, border, Enclosure.frame_content(frame)), Model.extent_max(minimum, Enclosure.Extent{32n, 32n})),
    Model.extent_max(minimum, Enclosure.Extent{32n, 32n}), Enclosure.Extent{32n, 32n},
    max_contains_second(Enclosure.required_extent(w, h, border, Enclosure.frame_content(frame)), Model.extent_max(minimum, Enclosure.Extent{32n, 32n})), max_contains_second(minimum, Enclosure.Extent{32n, 32n}))

def operable(~E: Data, +content: Space.Demand, +rule: Model.Rule, +first: E, +remaining: +List<E>, +enabled: Bool) ->
  {ModelRules.extent_contains(Model.minimum_demand(Model.outer_demand(~E, content, rule, Model.Operable{first, remaining, enabled})), Enclosure.Extent{32n, 32n}) == True{} : Bool}:
  Space.Demand{+content_minimum, preferred} = content
  Model.Rule{direction, main, cross, frame, border, width, height, minimum, +scroll, position} = rule
  contains_trans(Model.minimum_demand(Model.outer_demand(~E, content, rule, Model.Operable{first, remaining, enabled})),
    Model.minimum_demand(Model.intrinsic_outer_demand(~E, content, rule, Model.Operable{first, remaining, enabled})), Enclosure.Extent{32n, 32n},
    outer_intrinsic_floor(~E, content, rule, Model.Operable{first, remaining, enabled}),
    operable_outer(~E, Model.viewport_content_minimum(content_minimum, scroll), rule, first, remaining, enabled))

def lower_conflict(+minimum: Nat, +authored: Nat, +maximum: Nat,
  conflict: {Nat.is_le(minimum, maximum) == False{} : Bool}) ->
  {Nat.is_le(Nat.max(minimum, authored), maximum) == False{} : Bool}:
  match minimum authored maximum:
    case 0n _ _: Logic.impossible({Nat.is_le(Nat.max(0n, authored), maximum) == False{} : Bool},
      Equal.trans(Bool, False{}, Nat.is_le(0n, maximum), True{}, Equal.sym(Bool, Nat.is_le(0n, maximum), False{}, conflict), Order.zero_le(maximum)))
    case 1n+a 0n _: conflict
    case 1n+a 1n+b 0n: {==}
    case 1n+a 1n+b 1n+c: lower_conflict(a, b, c, conflict)

def exact_conflict(+minimum: Nat, preferred: Nat, offered: Nat, +extent: Nat,
  conflict: {Nat.is_le(minimum, extent) == False{} : Bool}) ->
  {Model.materialize(Model.ExactSize{extent}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>}:
  Equal.cong(Bool, Maybe<&2, Space.Dimension>, (fits => Model.accept_dimension(fits, Space.Rigid{extent})), Nat.is_le(minimum, extent), False{}, conflict)

def limited_conflict(+minimum: Nat, +preferred: Nat, offered: Nat, +authored: Nat, +extra: Nat, +maximum_extra: Nat,
  conflict: {Nat.is_le(minimum, Nat.add(Nat.add(authored, extra), maximum_extra)) == False{} : Bool}) ->
  {Model.materialize(Model.LimitedSize{authored, extra, maximum_extra}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>}:
  +maximum = Nat.add(Nat.add(authored, extra), maximum_extra)
  +lower = Space.larger(minimum, authored)
  +chosen = Space.smaller(maximum, Space.larger(lower, preferred))
  Equal.cong(Bool, Maybe<&2, Space.Dimension>, (fits => Model.accept_dimension(fits, Space.Fit{lower, Nat.sub(chosen, lower), Nat.sub(maximum, chosen)})),
    Nat.is_le(lower, maximum), False{},
    Equal.trans(Bool, Nat.is_le(lower, maximum), Nat.is_le(Nat.max(minimum, authored), maximum), False{},
      Equal.cong(Nat, Bool, (n => Nat.is_le(n, maximum)), lower, Nat.max(minimum, authored), Order.larger_eq_max(minimum, authored)),
      lower_conflict(minimum, authored, maximum, conflict)))

def invalid_percent(+minimum: Nat, preferred: Nat, +offered: Nat, +percent: Nat,
  invalid: {Nat.is_le(percent, 100n) == False{} : Bool}) ->
  {Model.materialize(Model.PercentSize{percent}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>}:
  Equal.cong(Bool, Maybe<&2, Space.Dimension>,
    (valid => Model.percentage_dimension(Model.percentage_checked(valid, offered, percent), minimum)),
    Nat.is_le(percent, 100n), False{}, invalid)

def invalid_cap(+minimum: Nat, +preferred: Nat, +offered: Nat, +percent: Nat,
  invalid: {Nat.is_le(percent, 100n) == False{} : Bool}) ->
  {Model.materialize(Model.CappedNaturalSize{percent}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>}:
  Equal.cong(Bool, Maybe<&2, Space.Dimension>,
    (valid => Model.capped_dimension(Model.percentage_checked(valid, offered, percent), minimum, preferred)),
    Nat.is_le(percent, 100n), False{}, invalid)

def capped_rejected(+fits: Bool, +dimension: Space.Dimension,
  conflict: {Bool.not(fits) == True{} : Bool}) ->
  {Model.accept_dimension(fits, dimension) == None{} : Maybe<&2, Space.Dimension>}:
  match fits:
    case False{}: {==}
    case True{}: Logic.impossible(
      {Model.accept_dimension(True{}, dimension) == None{} : Maybe<&2, Space.Dimension>}, conflict)

def capped_extent_conflict(+extent: Maybe<&2, Nat>, +minimum: Nat, +preferred: Nat,
  conflict: {ModelRules.percentage_conflict(extent, minimum) == True{} : Bool}) ->
  {Model.capped_dimension(extent, minimum, preferred) == None{} : Maybe<&2, Space.Dimension>}:
  match extent:
    case None{}: {==}
    case Some{+cap}:
      +chosen = Space.smaller(cap, Space.larger(minimum, preferred))
      capped_rejected(Nat.is_le(minimum, cap), Space.Fit{minimum, Nat.sub(chosen, minimum), Nat.sub(cap, chosen)}, conflict)

def capped_conflict(+minimum: Nat, +preferred: Nat, +offered: Nat, +maximum_percent: Nat,
  conflict: {ModelRules.percentage_conflict(Model.percentage_extent(offered, maximum_percent), minimum) == True{} : Bool}) ->
  {Model.materialize(Model.CappedNaturalSize{maximum_percent}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>}:
  capped_extent_conflict(Model.percentage_extent(offered, maximum_percent), minimum, preferred, conflict)

def capped_stretch_accepted(+minimum: Nat, preferred: Nat, offered: Nat, +maximum: Nat,
  fits: {Nat.is_le(minimum, maximum) == True{} : Bool}) ->
  {Model.materialize(Model.CappedStretchSize{maximum}, minimum, preferred, offered) == Some{ModelRules.capped_stretch_dimension(minimum, maximum)} : Maybe<&2, Space.Dimension>}:
  Equal.cong(Bool, Maybe<&2, Space.Dimension>, (valid => Model.accept_dimension(valid, ModelRules.capped_stretch_dimension(minimum, maximum))), Nat.is_le(minimum, maximum), True{}, fits)

def capped_stretch_rejected_checked(+fits: Bool, dimension: Space.Dimension) ->
  {ModelRules.rejected(Model.accept_dimension(fits, dimension)) == Bool.not(fits) : Bool}:
  match fits:
    case False{}: {==}
    case True{}: {==}

def capped_stretch_rejected(+minimum: Nat, preferred: Nat, offered: Nat, +maximum: Nat) ->
  {ModelRules.rejected(Model.materialize(Model.CappedStretchSize{maximum}, minimum, preferred, offered)) == Bool.not(Nat.is_le(minimum, maximum)) : Bool}:
  capped_stretch_rejected_checked(Nat.is_le(minimum, maximum), ModelRules.capped_stretch_dimension(minimum, maximum))

def capped_stretch_balance(+minimum: Nat, +maximum: Nat,
  fits: {Nat.is_le(minimum, maximum) == True{} : Bool}) ->
  {Nat.add(minimum, Nat.sub(maximum, minimum)) == maximum : Nat}:
  lower_fits = Equal.trans(Bool, Nat.is_le(Nat.add(minimum, 0n), maximum), Nat.is_le(minimum, maximum), True{},
    Equal.cong(Nat, Bool, (n => Nat.is_le(n, maximum)), Nat.add(minimum, 0n), minimum, Alg.nat_add_zero(minimum)), fits)
  Order.second({Nat.is_le(0n, Nat.sub(maximum, minimum)) == True{} : Bool},
    {Nat.add(minimum, Nat.sub(maximum, minimum)) == maximum : Nat}, Order.residual(minimum, 0n, maximum, lower_fits))

# The base library defines minimum but exports no commutation or selection law.
def minimum_commutes(+left: Nat, +right: Nat) -> {Nat.min(left, right) == Nat.min(right, left) : Nat}:
  match left right:
    case 0n 0n: {==}
    case 0n 1n+b: {==}
    case 1n+a 0n: {==}
    case 1n+a 1n+b: Equal.cong(Nat, Nat, (n => 1n+n), Nat.min(a, b), Nat.min(b, a), minimum_commutes(a, b))

def minimum_attained(+maximum: Nat, +room: Nat,
  fits: {Nat.is_le(maximum, room) == True{} : Bool}) -> {Nat.min(maximum, room) == maximum : Nat}:
  match maximum room:
    case 0n _: {==}
    case 1n+a 0n: Logic.impossible({Nat.min(1n+a, 0n) == 1n+a : Nat}, fits)
    case 1n+a 1n+b: Equal.cong(Nat, Nat, (n => 1n+n), Nat.min(a, b), a, minimum_attained(a, b, fits))

def capped_stretch_width(+minimum: Nat, preferred: Nat, offered: Nat, +maximum: Nat, +room: Nat,
  +fits: {Nat.is_le(minimum, maximum) == True{} : Bool}, room_fits: {Nat.is_le(minimum, room) == True{} : Bool}) ->
  {ModelRules.allocated_width(Model.materialize(Model.CappedStretchSize{maximum}, minimum, preferred, offered), room) == Some{Nat.min(room, maximum)} : Maybe<&2, Nat>}:
  accepted = Equal.cong(Maybe<&2, Space.Dimension>, Maybe<&2, Nat>, (result => ModelRules.allocated_width(result, room)),
    Model.materialize(Model.CappedStretchSize{maximum}, minimum, preferred, offered), Some{ModelRules.capped_stretch_dimension(minimum, maximum)}, capped_stretch_accepted(minimum, preferred, offered, maximum, fits))
  selected = Equal.cong(Nat, Maybe<&2, Nat>, (n => Some{n}), Space.smaller(Nat.add(minimum, Nat.sub(maximum, minimum)), room), Nat.min(Nat.add(minimum, Nat.sub(maximum, minimum)), room), Order.smaller_eq_min(Nat.add(minimum, Nat.sub(maximum, minimum)), room))
  bounded = Equal.cong(Nat, Maybe<&2, Nat>, (cap => Some{Nat.min(cap, room)}), Nat.add(minimum, Nat.sub(maximum, minimum)), maximum, capped_stretch_balance(minimum, maximum, fits))
  Equal.trans(Maybe<&2, Nat>, ModelRules.allocated_width(Model.materialize(Model.CappedStretchSize{maximum}, minimum, preferred, offered), room),
    Some{Nat.min(Nat.add(minimum, Nat.sub(maximum, minimum)), room)}, Some{Nat.min(room, maximum)},
    Equal.trans(Maybe<&2, Nat>, ModelRules.allocated_width(Model.materialize(Model.CappedStretchSize{maximum}, minimum, preferred, offered), room), Some{Space.smaller(Nat.add(minimum, Nat.sub(maximum, minimum)), room)}, Some{Nat.min(Nat.add(minimum, Nat.sub(maximum, minimum)), room)}, accepted, selected),
    Equal.trans(Maybe<&2, Nat>, Some{Nat.min(Nat.add(minimum, Nat.sub(maximum, minimum)), room)}, Some{Nat.min(maximum, room)}, Some{Nat.min(room, maximum)}, bounded,
      Equal.cong(Nat, Maybe<&2, Nat>, (n => Some{n}), Nat.min(maximum, room), Nat.min(room, maximum), minimum_commutes(maximum, room))))

def capped_stretch_attained(+minimum: Nat, preferred: Nat, offered: Nat, +maximum: Nat, +room: Nat,
  +fits: {Nat.is_le(minimum, maximum) == True{} : Bool}, +room_fits: {Nat.is_le(maximum, room) == True{} : Bool}) ->
  {ModelRules.allocated_width(Model.materialize(Model.CappedStretchSize{maximum}, minimum, preferred, offered), room) == Some{maximum} : Maybe<&2, Nat>}:
  Equal.trans(Maybe<&2, Nat>, ModelRules.allocated_width(Model.materialize(Model.CappedStretchSize{maximum}, minimum, preferred, offered), room), Some{Nat.min(room, maximum)}, Some{maximum},
    capped_stretch_width(minimum, preferred, offered, maximum, room, fits, Order.le_trans(minimum, maximum, room, fits, room_fits)),
    Equal.cong(Nat, Maybe<&2, Nat>, (n => Some{n}), Nat.min(room, maximum), maximum,
      Equal.trans(Nat, Nat.min(room, maximum), Nat.min(maximum, room), maximum, minimum_commutes(room, maximum), minimum_attained(maximum, room, room_fits))))

def adaptive_exact(+minimum: Nat, +preferred: Nat, +offered: Nat, +nominal_cap: Nat,
  +fits: {Nat.is_le(minimum, offered) == True{} : Bool}) ->
  {Model.adaptive_dimension(Some{nominal_cap}, minimum, preferred, offered) == Some{ModelRules.adaptive_fit(minimum, preferred, offered, nominal_cap)} : Maybe<&2, Space.Dimension>}:
  Equal.cong(Bool, Maybe<&2, Space.Dimension>,
    valid => Model.adaptive_checked(valid, minimum, preferred, offered, nominal_cap),
    Nat.is_le(minimum, offered), True{}, fits)

def adaptive_total(+minimum: Nat, +preferred: Nat, +offered: Nat, +percent: Nat,
  +valid: {Nat.is_le(percent, 100n) == True{} : Bool}, +fits: {Nat.is_le(minimum, offered) == True{} : Bool}) ->
  {Model.materialize(Model.AdaptiveNaturalSize{percent}, minimum, preferred, offered) == Some{ModelRules.adaptive_fit(minimum, preferred, offered, ModelRules.nominal_percentage(offered, percent))} : Maybe<&2, Space.Dimension>}:
  Equal.trans(Maybe<&2, Space.Dimension>,
    Model.materialize(Model.AdaptiveNaturalSize{percent}, minimum, preferred, offered),
    Model.adaptive_dimension(Some{ModelRules.nominal_percentage(offered, percent)}, minimum, preferred, offered),
    Some{ModelRules.adaptive_fit(minimum, preferred, offered, ModelRules.nominal_percentage(offered, percent))},
    Equal.cong(Bool, Maybe<&2, Space.Dimension>,
      accepted => Model.adaptive_dimension(Model.percentage_checked(accepted, offered, percent), minimum, preferred, offered),
      Nat.is_le(percent, 100n), True{}, valid),
    adaptive_exact(minimum, preferred, offered, ModelRules.nominal_percentage(offered, percent), fits))

def adaptive_minimum(+minimum: Nat, +preferred: Nat, +offered: Nat, +percent: Nat,
  +valid: {Nat.is_le(percent, 100n) == True{} : Bool}, +fits: {Nat.is_le(minimum, offered) == True{} : Bool}) ->
  {ModelRules.minimum_result(Model.materialize(Model.AdaptiveNaturalSize{percent}, minimum, preferred, offered)) == Some{minimum} : Maybe<&2, Nat>}:
  Equal.cong(Maybe<&2, Space.Dimension>, Maybe<&2, Nat>, result => ModelRules.minimum_result(result),
    Model.materialize(Model.AdaptiveNaturalSize{percent}, minimum, preferred, offered),
    Some{ModelRules.adaptive_fit(minimum, preferred, offered, ModelRules.nominal_percentage(offered, percent))},
    adaptive_total(minimum, preferred, offered, percent, valid, fits))

# Existing packing arithmetic supplies the order and subtraction balance facts.
def smaller_floor(+minimum: Nat, +first: Nat, +second: Nat,
  first_fits: {Nat.is_le(minimum, first) == True{} : Bool}, second_fits: {Nat.is_le(minimum, second) == True{} : Bool}) ->
  {Nat.is_le(minimum, Space.smaller(first, second)) == True{} : Bool}:
  +extra = Nat.sub(first, minimum)
  Equal.trans(Bool, Nat.is_le(minimum, Space.smaller(first, second)), Nat.is_le(minimum, Nat.min(first, second)), True{},
    Equal.cong(Nat, Bool, size => Nat.is_le(minimum, size), Space.smaller(first, second), Nat.min(first, second), Order.smaller_eq_min(first, second)),
    Equal.trans(Bool, Nat.is_le(minimum, Nat.min(first, second)), Nat.is_le(minimum, Nat.min(Nat.add(minimum, extra), second)), True{},
      Equal.cong(Nat, Bool, size => Nat.is_le(minimum, Nat.min(size, second)), first, Nat.add(minimum, extra),
        Equal.sym(Nat, Nat.add(minimum, extra), first, capped_stretch_balance(minimum, first, first_fits))),
      Order.min_floor(minimum, extra, second, second_fits)))

def smaller_left(+first: Nat, +second: Nat) -> {Nat.is_le(Space.smaller(first, second), first) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(Space.smaller(first, second), first), Nat.is_le(Nat.min(first, second), first), True{},
    Equal.cong(Nat, Bool, size => Nat.is_le(size, first), Space.smaller(first, second), Nat.min(first, second), Order.smaller_eq_min(first, second)),
    Order.min_le_first(first, second))

def adaptive_fit_maximum(+minimum: Nat, +preferred: Nat, +offered: Nat, +nominal_cap: Nat,
  +fits: {Nat.is_le(minimum, offered) == True{} : Bool}) ->
  {ModelRules.adaptive_ceiling(minimum, preferred, offered, nominal_cap) == ModelRules.adaptive_maximum(minimum, offered, nominal_cap) : Nat}:
  +maximum = ModelRules.adaptive_maximum(minimum, offered, nominal_cap)
  +chosen = Space.smaller(maximum, Space.larger(minimum, preferred))
  +maximum_floor = smaller_floor(minimum, offered, Space.larger(minimum, nominal_cap), fits, demand_max_left(minimum, nominal_cap))
  +chosen_floor = smaller_floor(minimum, maximum, Space.larger(minimum, preferred), maximum_floor, demand_max_left(minimum, preferred))
  Equal.trans(Nat, ModelRules.adaptive_ceiling(minimum, preferred, offered, nominal_cap),
    Nat.add(chosen, Nat.sub(maximum, chosen)), maximum,
    Equal.cong(Nat, Nat, size => Nat.add(size, Nat.sub(maximum, chosen)),
      Nat.add(minimum, Nat.sub(chosen, minimum)), chosen, capped_stretch_balance(minimum, chosen, chosen_floor)),
    capped_stretch_balance(chosen, maximum, smaller_left(maximum, Space.larger(minimum, preferred))))

def adaptive_fit_bound(+minimum: Nat, +preferred: Nat, +offered: Nat, +nominal_cap: Nat,
  +fits: {Nat.is_le(minimum, offered) == True{} : Bool}) ->
  {Nat.is_le(ModelRules.adaptive_ceiling(minimum, preferred, offered, nominal_cap), offered) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(ModelRules.adaptive_ceiling(minimum, preferred, offered, nominal_cap), offered),
    Nat.is_le(ModelRules.adaptive_maximum(minimum, offered, nominal_cap), offered), True{},
    Equal.cong(Nat, Bool, size => Nat.is_le(size, offered),
      ModelRules.adaptive_ceiling(minimum, preferred, offered, nominal_cap), ModelRules.adaptive_maximum(minimum, offered, nominal_cap),
      adaptive_fit_maximum(minimum, preferred, offered, nominal_cap, fits)),
    smaller_left(offered, Space.larger(minimum, nominal_cap)))

def adaptive_maximum(+minimum: Nat, +preferred: Nat, +offered: Nat, +percent: Nat,
  +valid: {Nat.is_le(percent, 100n) == True{} : Bool}, +fits: {Nat.is_le(minimum, offered) == True{} : Bool}) ->
  {ModelRules.maximum_fits(Model.materialize(Model.AdaptiveNaturalSize{percent}, minimum, preferred, offered), offered) == True{} : Bool}:
  Equal.trans(Bool,
    ModelRules.maximum_fits(Model.materialize(Model.AdaptiveNaturalSize{percent}, minimum, preferred, offered), offered),
    Nat.is_le(ModelRules.adaptive_ceiling(minimum, preferred, offered, ModelRules.nominal_percentage(offered, percent)), offered), True{},
    Equal.cong(Maybe<&2, Space.Dimension>, Bool, result => ModelRules.maximum_fits(result, offered),
      Model.materialize(Model.AdaptiveNaturalSize{percent}, minimum, preferred, offered),
      Some{ModelRules.adaptive_fit(minimum, preferred, offered, ModelRules.nominal_percentage(offered, percent))},
      adaptive_total(minimum, preferred, offered, percent, valid, fits)),
    adaptive_fit_bound(minimum, preferred, offered, ModelRules.nominal_percentage(offered, percent), fits))

def maximum_attained(+minimum: Nat, +maximum: Nat,
  +fits: {Nat.is_le(minimum, maximum) == True{} : Bool}) -> {Space.larger(minimum, maximum) == maximum : Nat}:
  match minimum maximum:
    case 0n 0n: {==}
    case 0n 1n+b: {==}
    case 1n+a 0n: Logic.impossible({Space.larger(1n+a, 0n) == 0n : Nat}, fits)
    case 1n+a 1n+b:
      Equal.trans(Nat, Space.larger(1n+a, 1n+b), 1n+Space.larger(a, b), 1n+b,
        Order.choose_extent_successor(Nat.is_ge(a, b), a, b),
        Equal.cong(Nat, Nat, value => 1n+value, Space.larger(a, b), b, maximum_attained(a, b, fits)))

def smaller_attained(+maximum: Nat, +cap: Nat,
  +fits: {Nat.is_le(cap, maximum) == True{} : Bool}) -> {Space.smaller(maximum, cap) == cap : Nat}:
  Equal.trans(Nat, Space.smaller(maximum, cap), Nat.min(maximum, cap), cap,
    Order.smaller_eq_min(maximum, cap),
    Equal.trans(Nat, Nat.min(maximum, cap), Nat.min(cap, maximum), cap,
      minimum_commutes(maximum, cap), minimum_attained(cap, maximum, fits)))

def adaptive_normal(+minimum: Nat, +preferred: Nat, +offered: Nat, +nominal_cap: Nat,
  +content_fits: {Nat.is_le(minimum, nominal_cap) == True{} : Bool}, +cap_fits: {Nat.is_le(nominal_cap, offered) == True{} : Bool}) ->
  {Model.adaptive_dimension(Some{nominal_cap}, minimum, preferred, offered) == Model.capped_dimension(Some{nominal_cap}, minimum, preferred) : Maybe<&2, Space.Dimension>}:
  +effective = ModelRules.adaptive_maximum(minimum, offered, nominal_cap)
  +effective_same = Equal.trans(Nat, effective, Space.smaller(offered, nominal_cap), nominal_cap,
    Equal.cong(Nat, Nat, size => Space.smaller(offered, size), Space.larger(minimum, nominal_cap), nominal_cap, maximum_attained(minimum, nominal_cap, content_fits)),
    smaller_attained(offered, nominal_cap, cap_fits))
  +chosen = Space.smaller(nominal_cap, Space.larger(minimum, preferred))
  Equal.trans(Maybe<&2, Space.Dimension>,
    Model.adaptive_dimension(Some{nominal_cap}, minimum, preferred, offered),
    Some{Space.Fit{minimum, Nat.sub(chosen, minimum), Nat.sub(nominal_cap, chosen)}},
    Model.capped_dimension(Some{nominal_cap}, minimum, preferred),
    Equal.trans(Maybe<&2, Space.Dimension>,
      Model.adaptive_dimension(Some{nominal_cap}, minimum, preferred, offered),
      Some{ModelRules.adaptive_fit(minimum, preferred, offered, nominal_cap)},
      Some{Space.Fit{minimum, Nat.sub(chosen, minimum), Nat.sub(nominal_cap, chosen)}},
      adaptive_exact(minimum, preferred, offered, nominal_cap, Order.le_trans(minimum, nominal_cap, offered, content_fits, cap_fits)),
      Equal.cong(Nat, Maybe<&2, Space.Dimension>, maximum => Some{Space.Fit{minimum, Nat.sub(Space.smaller(maximum, Space.larger(minimum, preferred)), minimum), Nat.sub(maximum, Space.smaller(maximum, Space.larger(minimum, preferred)))}},
        effective, nominal_cap, effective_same)),
    Equal.sym(Maybe<&2, Space.Dimension>, Model.capped_dimension(Some{nominal_cap}, minimum, preferred), Some{Space.Fit{minimum, Nat.sub(chosen, minimum), Nat.sub(nominal_cap, chosen)}},
      Equal.cong(Bool, Maybe<&2, Space.Dimension>, accepted => Model.accept_dimension(accepted, Space.Fit{minimum, Nat.sub(chosen, minimum), Nat.sub(nominal_cap, chosen)}),
        Nat.is_le(minimum, nominal_cap), True{}, content_fits)))

def adaptive_invalid(+minimum: Nat, +preferred: Nat, +offered: Nat, +percent: Nat,
  invalid: {Nat.is_le(percent, 100n) == False{} : Bool}) ->
  {Model.materialize(Model.AdaptiveNaturalSize{percent}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>}:
  Equal.cong(Bool, Maybe<&2, Space.Dimension>,
    valid => Model.adaptive_dimension(Model.percentage_checked(valid, offered, percent), minimum, preferred, offered),
    Nat.is_le(percent, 100n), False{}, invalid)

def adaptive_conflict_extent(+extent: Maybe<&2, Nat>, +minimum: Nat, +preferred: Nat, +offered: Nat,
  conflict: {Nat.is_le(minimum, offered) == False{} : Bool}) ->
  {Model.adaptive_dimension(extent, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>}:
  match extent:
    case None{}: {==}
    case Some{cap}:
      Equal.cong(Bool, Maybe<&2, Space.Dimension>, valid => Model.adaptive_checked(valid, minimum, preferred, offered, cap),
        Nat.is_le(minimum, offered), False{}, conflict)

def adaptive_conflict(+minimum: Nat, +preferred: Nat, +offered: Nat, +percent: Nat,
  conflict: {Nat.is_le(minimum, offered) == False{} : Bool}) ->
  {Model.materialize(Model.AdaptiveNaturalSize{percent}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>}:
  adaptive_conflict_extent(Model.percentage_extent(offered, percent), minimum, preferred, offered, conflict)

def ModelRules.evidence(A, E):
  ModelRules.Requirements{
    axis_authored_floor,
    (content => rule => interaction => outer_authored_floor(~E, content, rule, interaction)),
    axis_intrinsic_floor, axis_preferred_floor, authored_preferred, authored_floor,
    (content => rule => interaction => outer_preferred(~E, content, rule, interaction)),
    (content => rule => interaction => outer_intrinsic_floor(~E, content, rule, interaction)),
    (minimum => preferred => extent => {==}),
    (minimum => preferred => authored => extra => maximum => Order.max_right(minimum, authored)),

    (+minimum => +preferred => +offered => +cap => fits => adaptive_exact(minimum, preferred, offered, cap, fits)),
    (+minimum => +preferred => +offered => +percent => valid => fits => adaptive_total(minimum, preferred, offered, percent, valid, fits)),
    (+minimum => +preferred => +offered => +percent => valid => fits => adaptive_minimum(minimum, preferred, offered, percent, valid, fits)),
    (+minimum => +preferred => +offered => +percent => valid => fits => adaptive_maximum(minimum, preferred, offered, percent, valid, fits)),
    (+minimum => +preferred => +offered => +cap => content_fits => cap_fits => adaptive_normal(minimum, preferred, offered, cap, content_fits, cap_fits)),
    (+minimum => +preferred => +offered => +percent => invalid => adaptive_invalid(minimum, preferred, offered, percent, invalid)),
    (+minimum => +preferred => +offered => +percent => conflict => adaptive_conflict(minimum, preferred, offered, percent, conflict)),
    capped_stretch_accepted, capped_stretch_rejected, capped_stretch_width, capped_stretch_attained,
    (tree => preferred_content(~A, ~E, tree <> Nil{}, Model.Horizontal{}, 0n)),
    (trees => direction => gap => children_content(~A, ~E, trees, direction, gap)),
    (content => rule => first => remaining => enabled => operable(~E, content, rule, first, remaining, enabled)),
    (minimum => preferred => offered => authored => extra => maximum_extra => conflict => limited_conflict(minimum, preferred, offered, authored, extra, maximum_extra, conflict)),
    (minimum => preferred => offered => extent => conflict => exact_conflict(minimum, preferred, offered, extent, conflict)),
    (minimum => preferred => offered => percent => invalid => invalid_percent(minimum, preferred, offered, percent, invalid)),
    (minimum => preferred => offered => percent => invalid => invalid_cap(minimum, preferred, offered, percent, invalid)),
    (minimum => preferred => offered => maximum_percent => conflict => capped_conflict(minimum, preferred, offered, maximum_percent, conflict))}


def ModelRules.aligned_clearance_contains(outside, horizontal, vertical, extent):
  clearance_layered_contains(outside, extent)
