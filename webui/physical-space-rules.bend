import Base
import ./physical-space.bend as Model
import ./space.bend as Space
import ./enclosure.bend as Enclosure

def extent_contains(outer: Enclosure.Extent, inner: Enclosure.Extent) -> Bool:
  Enclosure.Extent{outer_width, outer_height} = outer
  Enclosure.Extent{inner_width, inner_height} = inner
  Nat.is_le(inner_width, outer_width) && Nat.is_le(inner_height, outer_height)

def preferred_covers_minimum(value: Space.Demand) -> Bool:
  Space.Demand{minimum, preferred} = value
  extent_contains(preferred, minimum)

def child_minima_participate(~A: Data, ~E: Data, trees: +List<Model.Tree<A, E>>, +required: Enclosure.Extent) -> Bool:
  match trees:
    case Nil{}: True{}
    case Con{tree, rest}:
      extent_contains(required, Model.minimum_demand(Model.demand(~A, ~E, tree))) &&
        child_minima_participate(~A, ~E, rest, required)

type Requirements<-A: Data, -E: Data> is Type:
  Requirements{
    preferred_floor: @+tree:Model.Tree<A, E> ->
      {preferred_covers_minimum(Model.demand(~A, ~E, tree)) == True{} : Bool},
    children_participate: @+trees:+List<Model.Tree<A, E>> -> @+direction:Model.Direction -> @+gap:Nat ->
      {child_minima_participate(~A, ~E, trees, Model.minimum_demand(Model.content_demand(~A, ~E, trees, direction, gap))) == True{} : Bool},
    operable_floor: @+content:Space.Demand -> @+rule:Model.Rule -> @first:E -> @remaining:+List<E> -> @enabled:Bool ->
      {extent_contains(Model.minimum_demand(Model.outer_demand(~E, content, rule, Model.Operable{first, remaining, enabled})), Enclosure.Extent{32n, 32n}) == True{} : Bool},
    limited_conflict: @+minimum:Nat -> @preferred:Nat -> @offered:Nat -> @+authored_minimum:Nat -> @+preferred_extra:Nat -> @+maximum_extra:Nat ->
      @conflict:{Nat.is_le(minimum, Nat.add(Nat.add(authored_minimum, preferred_extra), maximum_extra)) == False{} : Bool} ->
      {Model.materialize(Model.LimitedSize{authored_minimum, preferred_extra, maximum_extra}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>},
    exact_conflict: @+minimum:Nat -> @preferred:Nat -> @offered:Nat -> @+extent:Nat ->
      @conflict:{Nat.is_le(minimum, extent) == False{} : Bool} ->
      {Model.materialize(Model.ExactSize{extent}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>},
    capped_conflict: @+minimum:Nat -> @+preferred:Nat -> @+offered:Nat -> @+maximum_percent:Nat ->
      @conflict:{(Bool.not(Nat.is_le(maximum_percent, 100n)) || Bool.not(Nat.is_le(minimum, Nat.div(Nat.mul(offered, maximum_percent), 100n)))) == True{} : Bool} ->
      {Model.materialize(Model.CappedNaturalSize{maximum_percent}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>}}

law evidence:
  for ~A: Data
  for ~E: Data
  Requirements<A, E>
