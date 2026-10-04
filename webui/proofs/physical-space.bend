import Base
import ../spatial.bend as Spatial
import ../physical-space.bend as Model
import ../physical-space-rules.bend as ModelRules
import ../space.bend as Space
import ../enclosure.bend as Enclosure
import ../../bendlib/proofs/algebra.bend as Alg
import ./space.bend as Order

def and_left(+a: Bool, +b: Bool, evidence: {Bool.and(a, b) == True{} : Bool}) -> {a == True{} : Bool}:
  Order.first({a == True{} : Bool}, {b == True{} : Bool}, Order.and_parts(a, b, evidence))

def and_right(+a: Bool, +b: Bool, evidence: {Bool.and(a, b) == True{} : Bool}) -> {b == True{} : Bool}:
  Order.second({a == True{} : Bool}, {b == True{} : Bool}, Order.and_parts(a, b, evidence))

def max_contains_first(+first: Enclosure.Extent, +second: Enclosure.Extent) ->
  {ModelRules.extent_contains(Model.extent_max(first, second), first) == True{} : Bool}:
  Enclosure.Extent{+w, +h} = first
  Enclosure.Extent{+x, +y} = second
  Order.and_join(Nat.is_le(w, Nat.max(w, x)), Nat.is_le(h, Nat.max(h, y)),
    Order.max_left(w, x), Order.max_left(h, y))

def max_contains_second(+first: Enclosure.Extent, +second: Enclosure.Extent) ->
  {ModelRules.extent_contains(Model.extent_max(first, second), second) == True{} : Bool}:
  Enclosure.Extent{+w, +h} = first
  Enclosure.Extent{+x, +y} = second
  Order.and_join(Nat.is_le(x, Nat.max(w, x)), Nat.is_le(y, Nat.max(h, y)),
    Order.max_right(w, x), Order.max_right(h, y))

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
  Order.and_join(Nat.is_le(w, Nat.add(w, Nat.add(gap, x))), Nat.is_le(h, Nat.max(h, y)), Order.le_add(w, Nat.add(gap, x)), Order.max_left(h, y))

def combine_first_vertical(+gap: Nat, +first: Enclosure.Extent, +rest: Enclosure.Extent) ->
  {ModelRules.extent_contains(Model.vertical_extent(gap, first, rest), first) == True{} : Bool}:
  Enclosure.Extent{+w, +h} = first
  Enclosure.Extent{+x, +y} = rest
  Order.and_join(Nat.is_le(w, Nat.max(w, x)), Nat.is_le(h, Nat.add(h, Nat.add(gap, y))), Order.max_left(w, x), Order.le_add(h, Nat.add(gap, y)))

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
  Order.and_join(Nat.is_le(x, Nat.add(w, Nat.add(gap, x))), Nat.is_le(y, Nat.max(h, y)),
    Order.le_trans(x, Nat.add(gap, x), Nat.add(w, Nat.add(gap, x)), add_contains_second(gap, x), add_contains_second(w, Nat.add(gap, x))), Order.max_right(h, y))

def combine_rest_vertical(+gap: Nat, +first: Enclosure.Extent, +rest: Enclosure.Extent) ->
  {ModelRules.extent_contains(Model.vertical_extent(gap, first, rest), rest) == True{} : Bool}:
  Enclosure.Extent{+w, +h} = first
  Enclosure.Extent{+x, +y} = rest
  Order.and_join(Nat.is_le(x, Nat.max(w, x)), Nat.is_le(y, Nat.add(h, Nat.add(gap, y))), Order.max_right(w, x),
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

def combine_empty(+extent: Enclosure.Extent) ->
  {Model.combine_extent(Model.Horizontal{}, 0n, extent, Enclosure.Extent{0n, 0n}) == extent : Enclosure.Extent}:
  Enclosure.Extent{+w, +h} = extent
  Equal.trans(Enclosure.Extent, Enclosure.Extent{Nat.add(w, 0n), Nat.max(h, 0n)}, Enclosure.Extent{w, Nat.max(h, 0n)}, Enclosure.Extent{w, h},
    Equal.cong(Nat, Enclosure.Extent, (n => Enclosure.Extent{n, Nat.max(h, 0n)}), Nat.add(w, 0n), w, Alg.nat_add_zero(w)),
    Equal.cong(Nat, Enclosure.Extent, (n => Enclosure.Extent{w, n}), Nat.max(h, 0n), h, max_zero(h)))

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

def operable_outer(~E: Data, +content: Enclosure.Extent, +rule: Model.Rule, +first: E, +remaining: +List<E>, +enabled: Bool) ->
  {ModelRules.extent_contains(Model.outer_extent(~E, content, rule, Model.Operable{first, remaining, enabled}), Enclosure.Extent{32n, 32n}) == True{} : Bool}:
  Enclosure.Extent{+w, +h} = content
  Model.Rule{direction, main, cross, +frame, +border, width, height, +minimum, scroll, position} = rule
  contains_trans(Model.extent_max(Enclosure.required_extent(w, h, border, Enclosure.frame_content(frame)), Model.extent_max(minimum, Enclosure.Extent{32n, 32n})),
    Model.extent_max(minimum, Enclosure.Extent{32n, 32n}), Enclosure.Extent{32n, 32n},
    max_contains_second(Enclosure.required_extent(w, h, border, Enclosure.frame_content(frame)), Model.extent_max(minimum, Enclosure.Extent{32n, 32n})), max_contains_second(minimum, Enclosure.Extent{32n, 32n}))

def operable(~E: Data, +content: Space.Demand, +rule: Model.Rule, +first: E, +remaining: +List<E>, +enabled: Bool) ->
  {ModelRules.extent_contains(Model.minimum_demand(Model.outer_demand(~E, content, rule, Model.Operable{first, remaining, enabled})), Enclosure.Extent{32n, 32n}) == True{} : Bool}:
  Space.Demand{content_minimum, preferred} = content
  Model.Rule{direction, main, cross, frame, border, width, height, minimum, scroll, position} = rule
  operable_outer(~E, Model.viewport_content_minimum(content_minimum, scroll), rule, first, remaining, enabled)

def lower_conflict(+minimum: Nat, +authored: Nat, +maximum: Nat,
  conflict: {Nat.is_le(minimum, maximum) == False{} : Bool}) ->
  {Nat.is_le(Nat.max(minimum, authored), maximum) == False{} : Bool}:
  match minimum authored maximum:
    case 0n _ _: Order.impossible({Nat.is_le(Nat.max(0n, authored), maximum) == False{} : Bool},
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
  +lower = Nat.max(minimum, authored)
  +chosen = Nat.min(maximum, Nat.max(lower, preferred))
  Equal.cong(Bool, Maybe<&2, Space.Dimension>, (fits => Model.accept_dimension(fits, Space.Fit{lower, Nat.sub(chosen, lower), Nat.sub(maximum, chosen)})),
    Nat.is_le(lower, maximum), False{}, lower_conflict(minimum, authored, maximum, conflict))

def capped_rejected(+percent_fits: Bool, +minimum_fits: Bool, +dimension: Space.Dimension,
  conflict: {(Bool.not(percent_fits) || Bool.not(minimum_fits)) == True{} : Bool}) ->
  {Model.accept_dimension(percent_fits && minimum_fits, dimension) == None{} : Maybe<&2, Space.Dimension>}:
  match percent_fits minimum_fits:
    case False{} False{}: {==}
    case False{} True{}: {==}
    case True{} False{}: {==}
    case True{} True{}: Order.impossible(
      {Model.accept_dimension(True{} && True{}, dimension) == None{} : Maybe<&2, Space.Dimension>}, conflict)

def capped_conflict(+minimum: Nat, +preferred: Nat, +offered: Nat, +maximum_percent: Nat,
  conflict: {(Bool.not(Nat.is_le(maximum_percent, 100n)) || Bool.not(Nat.is_le(minimum, Nat.div(Nat.mul(offered, maximum_percent), 100n)))) == True{} : Bool}) ->
  {Model.materialize(Model.CappedNaturalSize{maximum_percent}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>}:
  +cap = Nat.div(Nat.mul(offered, maximum_percent), 100n)
  +chosen = Nat.min(cap, Nat.max(minimum, preferred))
  capped_rejected(Nat.is_le(maximum_percent, 100n), Nat.is_le(minimum, cap),
    Space.Fit{minimum, Nat.sub(chosen, minimum), Nat.sub(cap, chosen)}, conflict)

def ModelRules.evidence(A, E):
  ModelRules.Requirements{
    (tree => preferred_content(~A, ~E, tree <> Nil{}, Model.Horizontal{}, 0n)),
    (trees => direction => gap => children_content(~A, ~E, trees, direction, gap)),
    (content => rule => first => remaining => enabled => operable(~E, content, rule, first, remaining, enabled)),
    (minimum => preferred => offered => authored => extra => maximum_extra => conflict => limited_conflict(minimum, preferred, offered, authored, extra, maximum_extra, conflict)),
    (minimum => preferred => offered => extent => conflict => exact_conflict(minimum, preferred, offered, extent, conflict)),
    (minimum => preferred => offered => maximum_percent => conflict => capped_conflict(minimum, preferred, offered, maximum_percent, conflict))}
