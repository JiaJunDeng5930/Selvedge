import Base
import ./physical-space.bend as Model
import ./space.bend as Space
import ./enclosure.bend as Enclosure
import ./spatial.bend as Spatial

def extent_contains(outer: Enclosure.Extent, inner: Enclosure.Extent) -> Bool:
  Enclosure.Extent{outer_width, outer_height} = outer
  Enclosure.Extent{inner_width, inner_height} = inner
  Nat.is_le(inner_width, outer_width) && Nat.is_le(inner_height, outer_height)

def authored_minimum(size: Model.AxisSize) -> Nat:
  match size:
    case Model.NaturalSize{}: 0n
    case Model.StretchSize{}: 0n
    case Model.CappedStretchSize{maximum}: 0n
    case Model.ExactSize{extent}: extent
    case Model.LimitedSize{minimum, extra, maximum}: minimum
    case Model.PercentSize{percent}: 0n
    case Model.CappedNaturalSize{percent}: 0n
    case Model.AdaptiveNaturalSize{percent}: 0n

def axis_minimum(value: Model.AxisDemand) -> Nat:
  Model.AxisDemand{minimum, preferred} = value
  minimum

def axis_preferred(value: Model.AxisDemand) -> Nat:
  Model.AxisDemand{minimum, preferred} = value
  preferred

def rule_authored_minimum(rule: Model.Rule) -> Enclosure.Extent:
  Model.Rule{direction, main, cross, frame, border, width, height, minimum, scroll, position} = rule
  Enclosure.Extent{authored_minimum(width), authored_minimum(height)}

def preferred_covers_minimum(value: Space.Demand) -> Bool:
  Space.Demand{minimum, preferred} = value
  extent_contains(preferred, minimum)

def child_minima_participate(~A: Data, ~E: Data, trees: +List<Model.Tree<A, E>>, +required: Enclosure.Extent) -> Bool:
  match trees:
    case Nil{}: True{}
    case Con{tree, rest}:
      extent_contains(required, Model.minimum_demand(Model.demand(~A, ~E, tree))) &&
        child_minima_participate(~A, ~E, rest, required)

def percentage_conflict(+extent: Maybe<&2, Nat>, +minimum: Nat) -> Bool:
  match extent:
    case None{}: True{}
    case Some{cap}: Bool.not(Nat.is_le(minimum, cap))

def capped_stretch_dimension(+minimum: Nat, maximum: Nat) -> Space.Dimension:
  Space.Fit{minimum, Nat.sub(maximum, minimum), 0n}

def rejected(result: Maybe<&2, Space.Dimension>) -> Bool:
  match result:
    case None{}: True{}
    case Some{dimension}: False{}

def allocated_width(result: Maybe<&2, Space.Dimension>, room: Nat) -> Maybe<&2, Nat>:
  match result:
    case None{}: None{}
    case Some{dimension}: Some{Space.choose(dimension, room)}

def adaptive_maximum(+minimum: Nat, +offered: Nat, +nominal_cap: Nat) -> Nat:
  Space.smaller(offered, Space.larger(minimum, nominal_cap))

def adaptive_fit(+minimum: Nat, +preferred: Nat, +offered: Nat, +nominal_cap: Nat) -> Space.Dimension:
  +maximum = adaptive_maximum(minimum, offered, nominal_cap)
  +chosen = Space.smaller(maximum, Space.larger(minimum, preferred))
  Space.Fit{minimum, Nat.sub(chosen, minimum), Nat.sub(maximum, chosen)}

def adaptive_ceiling(+minimum: Nat, +preferred: Nat, +offered: Nat, +nominal_cap: Nat) -> Nat:
  +maximum = adaptive_maximum(minimum, offered, nominal_cap)
  +chosen = Space.smaller(maximum, Space.larger(minimum, preferred))
  Nat.add(Nat.add(minimum, Nat.sub(chosen, minimum)), Nat.sub(maximum, chosen))

def nominal_percentage(+offered: Nat, +percent: Nat) -> Nat:
  Nat.add(Nat.mul(Nat.div(offered, 100n), percent), Nat.div(Nat.mul(Nat.mod(offered, 100n), percent), 100n))

def minimum_result(result: Maybe<&2, Space.Dimension>) -> Maybe<&2, Nat>:
  match result:
    case None{}: None{}
    case Some{dimension}: Some{Space.minimum(dimension)}

def maximum_fits(result: Maybe<&2, Space.Dimension>, +offered: Nat) -> Bool:
  match result:
    case None{}: False{}
    case Some{Space.Rigid{extent}}: Nat.is_le(extent, offered)
    case Some{Space.Fit{minimum, preferred_extra, maximum_extra}}: Nat.is_le(Nat.add(Nat.add(minimum, preferred_extra), maximum_extra), offered)
    case Some{Space.Fill{minimum}}: False{}

type Requirements<-A: Data, -E: Data> is Type:
  Requirements{
    axis_authored_floor: @+size:Model.AxisSize -> @+minimum:Nat -> @+preferred:Nat ->
      {Nat.is_le(authored_minimum(size), axis_minimum(Model.axis_demand(size, minimum, preferred))) == True{} : Bool},
    outer_authored_floor: @+content:Space.Demand -> @+rule:Model.Rule -> @+interaction:Model.Interaction<E> ->
      {extent_contains(Model.minimum_demand(Model.outer_demand(~E, content, rule, interaction)), rule_authored_minimum(rule)) == True{} : Bool},
    axis_intrinsic_floor: @+size:Model.AxisSize -> @+minimum:Nat -> @+preferred:Nat ->
      {Nat.is_le(minimum, axis_minimum(Model.axis_demand(size, minimum, preferred))) == True{} : Bool},
    axis_preferred_floor: @+size:Model.AxisSize -> @+minimum:Nat -> @+preferred:Nat ->
      {Nat.is_le(axis_minimum(Model.axis_demand(size, minimum, preferred)), axis_preferred(Model.axis_demand(size, minimum, preferred))) == True{} : Bool},
    authored_preferred: @+width:Model.AxisSize -> @+height:Model.AxisSize -> @+content:Space.Demand ->
      {preferred_covers_minimum(Model.authored_demand(width, height, content)) == True{} : Bool},
    authored_floor: @+width:Model.AxisSize -> @+height:Model.AxisSize -> @+content:Space.Demand ->
      {extent_contains(Model.minimum_demand(Model.authored_demand(width, height, content)), Model.minimum_demand(content)) == True{} : Bool},
    outer_preferred: @+content:Space.Demand -> @+rule:Model.Rule -> @+interaction:Model.Interaction<E> ->
      {preferred_covers_minimum(Model.outer_demand(~E, content, rule, interaction)) == True{} : Bool},
    outer_intrinsic_floor: @+content:Space.Demand -> @+rule:Model.Rule -> @+interaction:Model.Interaction<E> ->
      {extent_contains(Model.minimum_demand(Model.outer_demand(~E, content, rule, interaction)), Model.minimum_demand(Model.intrinsic_outer_demand(~E, content, rule, interaction))) == True{} : Bool},
    authored_exact: @+minimum:Nat -> @+preferred:Nat -> @+extent:Nat ->
      {Model.axis_demand(Model.ExactSize{extent}, minimum, preferred) == Model.AxisDemand{Nat.max(minimum, extent), Nat.max(minimum, extent)} : Model.AxisDemand},
    authored_limited_floor: @+minimum:Nat -> @+preferred:Nat -> @+authored:Nat -> @+extra:Nat -> @+maximum:Nat ->
      {Nat.is_le(authored, axis_minimum(Model.axis_demand(Model.LimitedSize{authored, extra, maximum}, minimum, preferred))) == True{} : Bool},

    adaptive_exact: @+minimum:Nat -> @+preferred:Nat -> @+offered:Nat -> @+nominal_cap:Nat ->
      @fits:{Nat.is_le(minimum, offered) == True{} : Bool} ->
      {Model.adaptive_dimension(Some{nominal_cap}, minimum, preferred, offered) == Some{adaptive_fit(minimum, preferred, offered, nominal_cap)} : Maybe<&2, Space.Dimension>},
    adaptive_total: @+minimum:Nat -> @+preferred:Nat -> @+offered:Nat -> @+percent:Nat ->
      @valid:{Nat.is_le(percent, 100n) == True{} : Bool} -> @fits:{Nat.is_le(minimum, offered) == True{} : Bool} ->
      {Model.materialize(Model.AdaptiveNaturalSize{percent}, minimum, preferred, offered) == Some{adaptive_fit(minimum, preferred, offered, nominal_percentage(offered, percent))} : Maybe<&2, Space.Dimension>},
    adaptive_minimum: @+minimum:Nat -> @+preferred:Nat -> @+offered:Nat -> @+percent:Nat ->
      @valid:{Nat.is_le(percent, 100n) == True{} : Bool} -> @fits:{Nat.is_le(minimum, offered) == True{} : Bool} ->
      {minimum_result(Model.materialize(Model.AdaptiveNaturalSize{percent}, minimum, preferred, offered)) == Some{minimum} : Maybe<&2, Nat>},
    adaptive_maximum: @+minimum:Nat -> @+preferred:Nat -> @+offered:Nat -> @+percent:Nat ->
      @valid:{Nat.is_le(percent, 100n) == True{} : Bool} -> @fits:{Nat.is_le(minimum, offered) == True{} : Bool} ->
      {maximum_fits(Model.materialize(Model.AdaptiveNaturalSize{percent}, minimum, preferred, offered), offered) == True{} : Bool},
    adaptive_normal: @+minimum:Nat -> @+preferred:Nat -> @+offered:Nat -> @+nominal_cap:Nat ->
      @content_fits:{Nat.is_le(minimum, nominal_cap) == True{} : Bool} -> @cap_fits:{Nat.is_le(nominal_cap, offered) == True{} : Bool} ->
      {Model.adaptive_dimension(Some{nominal_cap}, minimum, preferred, offered) == Model.capped_dimension(Some{nominal_cap}, minimum, preferred) : Maybe<&2, Space.Dimension>},
    adaptive_invalid: @+minimum:Nat -> @+preferred:Nat -> @+offered:Nat -> @+percent:Nat ->
      @invalid:{Nat.is_le(percent, 100n) == False{} : Bool} ->
      {Model.materialize(Model.AdaptiveNaturalSize{percent}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>},
    adaptive_conflict: @+minimum:Nat -> @+preferred:Nat -> @+offered:Nat -> @+percent:Nat ->
      @conflict:{Nat.is_le(minimum, offered) == False{} : Bool} ->
      {Model.materialize(Model.AdaptiveNaturalSize{percent}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>},
    capped_stretch_accepted: @+minimum:Nat -> @preferred:Nat -> @offered:Nat -> @+maximum:Nat ->
      @fits:{Nat.is_le(minimum, maximum) == True{} : Bool} ->
      {Model.materialize(Model.CappedStretchSize{maximum}, minimum, preferred, offered) == Some{capped_stretch_dimension(minimum, maximum)} : Maybe<&2, Space.Dimension>},
    capped_stretch_rejected: @+minimum:Nat -> @preferred:Nat -> @offered:Nat -> @+maximum:Nat ->
      {rejected(Model.materialize(Model.CappedStretchSize{maximum}, minimum, preferred, offered)) == Bool.not(Nat.is_le(minimum, maximum)) : Bool},
    capped_stretch_width: @+minimum:Nat -> @preferred:Nat -> @offered:Nat -> @+maximum:Nat -> @+room:Nat ->
      @+fits:{Nat.is_le(minimum, maximum) == True{} : Bool} -> @room_fits:{Nat.is_le(minimum, room) == True{} : Bool} ->
      {allocated_width(Model.materialize(Model.CappedStretchSize{maximum}, minimum, preferred, offered), room) == Some{Nat.min(room, maximum)} : Maybe<&2, Nat>},
    capped_stretch_attained: @+minimum:Nat -> @preferred:Nat -> @offered:Nat -> @+maximum:Nat -> @+room:Nat ->
      @+fits:{Nat.is_le(minimum, maximum) == True{} : Bool} -> @+room_fits:{Nat.is_le(maximum, room) == True{} : Bool} ->
      {allocated_width(Model.materialize(Model.CappedStretchSize{maximum}, minimum, preferred, offered), room) == Some{maximum} : Maybe<&2, Nat>},
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
    invalid_percent: @+minimum:Nat -> @preferred:Nat -> @+offered:Nat -> @+percent:Nat ->
      @invalid:{Nat.is_le(percent, 100n) == False{} : Bool} ->
      {Model.materialize(Model.PercentSize{percent}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>},
    invalid_cap: @+minimum:Nat -> @+preferred:Nat -> @+offered:Nat -> @+percent:Nat ->
      @invalid:{Nat.is_le(percent, 100n) == False{} : Bool} ->
      {Model.materialize(Model.CappedNaturalSize{percent}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>},
    capped_conflict: @+minimum:Nat -> @+preferred:Nat -> @+offered:Nat -> @+maximum_percent:Nat ->
      @conflict:{percentage_conflict(Model.percentage_extent(offered, maximum_percent), minimum) == True{} : Bool} ->
      {Model.materialize(Model.CappedNaturalSize{maximum_percent}, minimum, preferred, offered) == None{} : Maybe<&2, Space.Dimension>}}

law evidence:
  for ~A: Data
  for ~E: Data
  Requirements<A, E>


law aligned_clearance_contains:
  for +outside: Enclosure.Insets
  for +horizontal: Spatial.Alignment
  for +vertical: Spatial.Alignment
  for +extent: Enclosure.Extent
  {extent_contains(Model.clearance_extent(Model.Layered{}, Spatial.AlignedLayer{outside, horizontal, vertical}, extent), extent) == True{} : Bool}
