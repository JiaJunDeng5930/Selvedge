import Base
import ../../bendlib/stdlib.bend as Std
import ../physical-space.bend as Model
import ../physical-allocation.bend as Allocation
import ../physical-height-source-rules.bend as Rule
import ../physical-height-rules.bend as Completion
import ./physical-height.bend as CompletionProof
import ../physical-allocation-population-rules.bend as Population
import ./physical-allocation-population.bend as PopulationProof
import ../space.bend as Space
import ../space-laws.bend as SpaceLaws
import ./space.bend as Order
import ../spatial.bend as Spatial
import ../enclosure.bend as Enclosure

# Continuations reconstruct the successful source from fields consumed by the
# next production transition. The accumulated results retain their original order.
def placement_sources(~A: Data, ~E: Data, placements: +List<Space.Placement<Allocation.MeasuredTree<A, E>>>) -> +List<Model.Tree<A, E>>:
  Allocation.source_forest_measured(~A, ~E, SpaceLaws.placement_values(~Allocation.MeasuredTree<A, E>, placements))

def outcome_source(~A: Data, ~E: Data, result: Allocation.PositionedOutcome<A, E>) -> Maybe<&2, Model.Tree<A, E>>:
  match result:
    case Allocation.Positioned{tree}: Some{Allocation.source_of_allocated(~A, ~E, tree)}
    case Allocation.PositionFailure{failure}: None{}

def cons_source(~A: Data, ~E: Data, first: Maybe<&2, Model.Tree<A, E>>, rest: Maybe<&2, +List<Model.Tree<A, E>>>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  match first rest:
    case Some{tree} Some{trees}: Some{tree <> trees}
    case _ _: None{}

def outcome_sources(~A: Data, ~E: Data, values: +List<Allocation.PositionedOutcome<A, E>>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  match values:
    case Nil{}: Some{Nil{}}
    case Con{first, rest}: cons_source(~A, ~E, outcome_source(~A, ~E, first), outcome_sources(~A, ~E, rest))

def append_source(~A: Data, ~E: Data, previous: Maybe<&2, +List<Model.Tree<A, E>>>, remaining: +List<Model.Tree<A, E>>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  match previous:
    case None{}: None{}
    case Some{values}: Some{List.append(&2, Model.Tree<A, E>, values, remaining)}

def container_source(~A: Data, ~E: Data, key: String, value: A, interaction: Model.Interaction<E>, rule: Model.Rule, children: Maybe<&2, +List<Model.Tree<A, E>>>) -> Maybe<&2, Model.Tree<A, E>>:
  match children:
    case None{}: None{}
    case Some{values}: Some{Model.Container{key, value, interaction, rule, values}}

def child_sources_from_erased(~A: Data, ~E: Data, current: Maybe<&2, Model.Tree<A, E>>, previous: Maybe<&2, +List<Model.Tree<A, E>>>, remaining: +List<Space.Placement<Allocation.MeasuredTree<A, E>>>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  match current:
    case None{}: None{}
    case Some{tree}: append_source(~A, ~E, previous, tree <> placement_sources(~A, ~E, remaining))

def child_sources(~A: Data, ~E: Data, previous: +List<Allocation.PositionedOutcome<A, E>>, current: Maybe<&2, Model.Tree<A, E>>, remaining: +List<Space.Placement<Allocation.MeasuredTree<A, E>>>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  child_sources_from_erased(~A, ~E, current, outcome_sources(~A, ~E, previous), remaining)

def return_source(~A: Data, ~E: Data, return_to: Allocation.HeightReturn<A, E>, current: Maybe<&2, Model.Tree<A, E>>) -> Maybe<&2, Model.Tree<A, E>>:
  match return_to:
    case Allocation.HeightRootReturn{}: current
    case Allocation.HeightContainerReturn{key, value, interaction, rule, bounds, canvas, direction, content_left, content_top, remaining, previous, parent}:
      return_source(~A, ~E, parent, container_source(~A, ~E, key, value, interaction, rule, child_sources(~A, ~E, previous, current, remaining)))

def plan_source(~A: Data, ~E: Data, plan: Allocation.ChildPlan<Allocation.MeasuredTree<A, E>>, key: String, value: A, interaction: Model.Interaction<E>, rule: Model.Rule) -> Maybe<&2, Model.Tree<A, E>>:
  match plan:
    case Allocation.PlanningFailure{failure}: None{}
    case Allocation.ChildrenPlanned{placements, canvas}:
      Some{Model.Container{key, value, interaction, rule, placement_sources(~A, ~E, placements)}}

def state_source(~A: Data, ~E: Data, state: Allocation.HeightState<A, E>) -> Maybe<&2, Model.Tree<A, E>>:
  match state:
    case Allocation.HeightVisit{tree, bounds, parent}: return_source(~A, ~E, parent, Some{Allocation.source_of_measured(~A, ~E, tree)})
    case Allocation.HeightMinimumChecked{False{}, tree, bounds, lower, parent}: return_source(~A, ~E, parent, None{})
    case Allocation.HeightMinimumChecked{True{}, tree, bounds, lower, parent}: return_source(~A, ~E, parent, Some{Allocation.source_of_measured(~A, ~E, tree)})
    case Allocation.HeightContainerPlan{plan, key, value, interaction, rule, bounds, children, direction, inner_width, left, top, parent}:
      return_source(~A, ~E, parent, plan_source(~A, ~E, plan, key, value, interaction, rule))
    case Allocation.HeightChildren{remaining, key, value, interaction, rule, bounds, canvas, direction, content_left, content_top, previous, parent}:
      return_source(~A, ~E, parent, container_source(~A, ~E, key, value, interaction, rule,
        append_source(~A, ~E, outcome_sources(~A, ~E, previous), placement_sources(~A, ~E, remaining))))
    case Allocation.HeightComplete{result, parent}: return_source(~A, ~E, parent, outcome_source(~A, ~E, result))
    case Allocation.HeightDone{result}: outcome_source(~A, ~E, result)

def partial_match(~A: Data, ~E: Data, actual: Maybe<&2, Model.Tree<A, E>>, expected: Model.Tree<A, E>) -> Type:
  match actual:
    case None{}: {True{} == True{} : Bool}
    case Some{source}: {source == expected : Model.Tree<A, E>}

def return_none(~A: Data, ~E: Data, parent: Allocation.HeightReturn<A, E>) ->
  {return_source(~A, ~E, parent, None{}) == None{} : Maybe<&2, Model.Tree<A, E>>}:
  match parent:
    case Allocation.HeightRootReturn{}: {==}
    case Allocation.HeightContainerReturn{key, value, interaction, rule, bounds, canvas, direction, content_left, content_top, remaining, previous, rest}:
      return_none(~A, ~E, rest)

def return_drop(~A: Data, ~E: Data, +parent: Allocation.HeightReturn<A, E>, +expected: Model.Tree<A, E>) ->
  partial_match(~A, ~E, return_source(~A, ~E, parent, None{}), expected):
  Std.transport(Maybe<&2, Model.Tree<A, E>>, None{},
    (actual => partial_match(~A, ~E, actual, expected)), {==},
    return_source(~A, ~E, parent, None{}), return_none(~A, ~E, parent))

def return_same(~A: Data, ~E: Data, +parent: Allocation.HeightReturn<A, E>, +actual: Model.Tree<A, E>, +source: Model.Tree<A, E>, +expected: Model.Tree<A, E>,
  same: {actual == source : Model.Tree<A, E>},
  proof: partial_match(~A, ~E, return_source(~A, ~E, parent, Some{source}), expected)) ->
  partial_match(~A, ~E, return_source(~A, ~E, parent, Some{actual}), expected):
  Std.transport(Model.Tree<A, E>, source,
    (tree => partial_match(~A, ~E, return_source(~A, ~E, parent, Some{tree}), expected)),
    proof, actual, same)

def allocated_children_source(~A: Data, ~E: Data, children: Allocation.AllocatedChildren<A, E>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  match children:
    case Allocation.AllocationFailed{failure}: None{}
    case Allocation.ChildrenAllocated{trees}: Some{Allocation.source_forest_allocated(~A, ~E, trees)}

def merge_source(~A: Data, ~E: Data, +first: Allocation.PositionedOutcome<A, E>, +rest: Allocation.AllocatedChildren<A, E>) ->
  {allocated_children_source(~A, ~E, Allocation.merge_allocation(~A, ~E, first, rest)) ==
    cons_source(~A, ~E, outcome_source(~A, ~E, first), allocated_children_source(~A, ~E, rest)) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match first rest:
    case Allocation.PositionFailure{failure} _: {==}
    case Allocation.Positioned{tree} Allocation.AllocationFailed{failure}: {==}
    case Allocation.Positioned{Allocation.AllocatedLeaf{key, value, interaction, rule, demand, height, bounds, canvas}} Allocation.ChildrenAllocated{trees}: {==}
    case Allocation.Positioned{Allocation.AllocatedContainer{key, value, interaction, rule, bounds, canvas, direction, children}} Allocation.ChildrenAllocated{trees}: {==}

def collected_source(~A: Data, ~E: Data, +values: +List<Allocation.PositionedOutcome<A, E>>) ->
  {allocated_children_source(~A, ~E, Allocation.collect_positioned_outcomes(~A, ~E, values)) ==
    outcome_sources(~A, ~E, values) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match values:
    case Nil{}: {==}
    case Con{+first, +rest}:
      Equal.trans(Maybe<&2, +List<Model.Tree<A, E>>>,
        allocated_children_source(~A, ~E, Allocation.merge_allocation(~A, ~E, first, Allocation.collect_positioned_outcomes(~A, ~E, rest))),
        cons_source(~A, ~E, outcome_source(~A, ~E, first), allocated_children_source(~A, ~E, Allocation.collect_positioned_outcomes(~A, ~E, rest))),
        cons_source(~A, ~E, outcome_source(~A, ~E, first), outcome_sources(~A, ~E, rest)),
        merge_source(~A, ~E, first, Allocation.collect_positioned_outcomes(~A, ~E, rest)),
        Equal.cong(Maybe<&2, +List<Model.Tree<A, E>>>, Maybe<&2, +List<Model.Tree<A, E>>>,
          (trees => cons_source(~A, ~E, outcome_source(~A, ~E, first), trees)),
          allocated_children_source(~A, ~E, Allocation.collect_positioned_outcomes(~A, ~E, rest)), outcome_sources(~A, ~E, rest), collected_source(~A, ~E, rest)))

def append_empty(~A: Data, ~E: Data, +values: Maybe<&2, +List<Model.Tree<A, E>>>) ->
  {append_source(~A, ~E, values, Nil{}) == values : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match values:
    case None{}: {==}
    case Some{+trees}:
      Equal.cong(+List<Model.Tree<A, E>>, Maybe<&2, +List<Model.Tree<A, E>>>,
        (children => Some{children}), List.append(&2, Model.Tree<A, E>, trees, Nil{}), trees, Std.app_nil_r(Model.Tree<A, E>, trees))

def append_cons(~A: Data, ~E: Data, +first: Maybe<&2, Model.Tree<A, E>>, +rest: Maybe<&2, +List<Model.Tree<A, E>>>, +remaining: +List<Model.Tree<A, E>>) ->
  {append_source(~A, ~E, cons_source(~A, ~E, first, rest), remaining) ==
    cons_source(~A, ~E, first, append_source(~A, ~E, rest, remaining)) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match first rest:
    case None{} _: {==}
    case Some{tree} None{}: {==}
    case Some{tree} Some{trees}: {==}

def child_cons(~A: Data, ~E: Data, +first: Maybe<&2, Model.Tree<A, E>>, +rest: Maybe<&2, +List<Model.Tree<A, E>>>, +current: Maybe<&2, Model.Tree<A, E>>, +remaining: +List<Space.Placement<Allocation.MeasuredTree<A, E>>>) ->
  {cons_source(~A, ~E, first, child_sources_from_erased(~A, ~E, current, rest, remaining)) ==
    child_sources_from_erased(~A, ~E, current, cons_source(~A, ~E, first, rest), remaining) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match first current:
    case None{} None{}: {==}
    case Some{tree} None{}: {==}
    case _ Some{tree}: Equal.sym(Maybe<&2, +List<Model.Tree<A, E>>>,
      append_source(~A, ~E, cons_source(~A, ~E, first, rest), tree <> placement_sources(~A, ~E, remaining)),
      cons_source(~A, ~E, first, append_source(~A, ~E, rest, tree <> placement_sources(~A, ~E, remaining))),
      append_cons(~A, ~E, first, rest, tree <> placement_sources(~A, ~E, remaining)))

def append_current_cons(~A: Data, ~E: Data, +first: Maybe<&2, Model.Tree<A, E>>, +rest: +List<Allocation.PositionedOutcome<A, E>>, +current: Allocation.PositionedOutcome<A, E>, +remaining: +List<Space.Placement<Allocation.MeasuredTree<A, E>>>,
  same: {append_source(~A, ~E, outcome_sources(~A, ~E, List.append(&2, Allocation.PositionedOutcome<A, E>, rest, current <> Nil{})), placement_sources(~A, ~E, remaining)) ==
    child_sources(~A, ~E, rest, outcome_source(~A, ~E, current), remaining) : Maybe<&2, +List<Model.Tree<A, E>>>}) ->
  {cons_source(~A, ~E, first, append_source(~A, ~E, outcome_sources(~A, ~E, List.append(&2, Allocation.PositionedOutcome<A, E>, rest, current <> Nil{})), placement_sources(~A, ~E, remaining))) ==
    child_sources_from_erased(~A, ~E, outcome_source(~A, ~E, current), cons_source(~A, ~E, first, outcome_sources(~A, ~E, rest)), remaining) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  Equal.trans(Maybe<&2, +List<Model.Tree<A, E>>>,
    cons_source(~A, ~E, first, append_source(~A, ~E, outcome_sources(~A, ~E, List.append(&2, Allocation.PositionedOutcome<A, E>, rest, current <> Nil{})), placement_sources(~A, ~E, remaining))),
    cons_source(~A, ~E, first, child_sources(~A, ~E, rest, outcome_source(~A, ~E, current), remaining)),
    child_sources_from_erased(~A, ~E, outcome_source(~A, ~E, current), cons_source(~A, ~E, first, outcome_sources(~A, ~E, rest)), remaining),
    Equal.cong(Maybe<&2, +List<Model.Tree<A, E>>>, Maybe<&2, +List<Model.Tree<A, E>>>, (trees => cons_source(~A, ~E, first, trees)),
      append_source(~A, ~E, outcome_sources(~A, ~E, List.append(&2, Allocation.PositionedOutcome<A, E>, rest, current <> Nil{})), placement_sources(~A, ~E, remaining)), child_sources(~A, ~E, rest, outcome_source(~A, ~E, current), remaining), same),
    child_cons(~A, ~E, first, outcome_sources(~A, ~E, rest), outcome_source(~A, ~E, current), remaining))

def append_current(~A: Data, ~E: Data, +previous: +List<Allocation.PositionedOutcome<A, E>>, +current: Allocation.PositionedOutcome<A, E>, +remaining: +List<Space.Placement<Allocation.MeasuredTree<A, E>>>) ->
  {append_source(~A, ~E, outcome_sources(~A, ~E, List.append(&2, Allocation.PositionedOutcome<A, E>, previous, current <> Nil{})), placement_sources(~A, ~E, remaining)) ==
    child_sources(~A, ~E, previous, outcome_source(~A, ~E, current), remaining) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match previous current:
    case Nil{} Allocation.Positioned{tree}: {==}
    case Nil{} Allocation.PositionFailure{failure}: {==}
    case Con{+first, +rest} +current:
      Equal.trans(Maybe<&2, +List<Model.Tree<A, E>>>,
        append_source(~A, ~E, cons_source(~A, ~E, outcome_source(~A, ~E, first), outcome_sources(~A, ~E, List.append(&2, Allocation.PositionedOutcome<A, E>, rest, current <> Nil{}))), placement_sources(~A, ~E, remaining)),
        cons_source(~A, ~E, outcome_source(~A, ~E, first), append_source(~A, ~E, outcome_sources(~A, ~E, List.append(&2, Allocation.PositionedOutcome<A, E>, rest, current <> Nil{})), placement_sources(~A, ~E, remaining))),
        child_sources(~A, ~E, first <> rest, outcome_source(~A, ~E, current), remaining),
        append_cons(~A, ~E, outcome_source(~A, ~E, first), outcome_sources(~A, ~E, List.append(&2, Allocation.PositionedOutcome<A, E>, rest, current <> Nil{})), placement_sources(~A, ~E, remaining)),
        append_current_cons(~A, ~E, outcome_source(~A, ~E, first), rest, current, remaining, append_current(~A, ~E, rest, current, remaining)))

def return_option(~A: Data, ~E: Data, +actual: Maybe<&2, Model.Tree<A, E>>, +source: Model.Tree<A, E>, +parent: Allocation.HeightReturn<A, E>, +expected: Model.Tree<A, E>,
  same: partial_match(~A, ~E, actual, source),
  proof: partial_match(~A, ~E, return_source(~A, ~E, parent, Some{source}), expected)) ->
  partial_match(~A, ~E, return_source(~A, ~E, parent, actual), expected):
  match actual:
    case None{}: return_drop(~A, ~E, parent, expected)
    case Some{tree}: return_same(~A, ~E, parent, tree, source, expected, same, proof)

def checked_preserved(~A: Data, ~E: Data, +fits: Bool, +tree: Allocation.MeasuredTree<A, E>, +bounds: Spatial.Box, +lower: Nat, +parent: Allocation.HeightReturn<A, E>, +expected: Model.Tree<A, E>,
  proof: partial_match(~A, ~E, return_source(~A, ~E, parent, Some{Allocation.source_of_measured(~A, ~E, tree)}), expected)) ->
  partial_match(~A, ~E, state_source(~A, ~E, Allocation.HeightMinimumChecked{fits, tree, bounds, lower, parent}), expected):
  match fits:
    case False{}: return_drop(~A, ~E, parent, expected)
    case True{}: proof

def plan_preserved(~A: Data, ~E: Data, +plan: Allocation.ChildPlan<Allocation.MeasuredTree<A, E>>, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +children: +List<Allocation.MeasuredTree<A, E>>,
  population: Population.BlockPopulation(~A, ~E, children, plan)) ->
  partial_match(~A, ~E, plan_source(~A, ~E, plan, key, value, interaction, rule), Model.Container{key, value, interaction, rule, Allocation.source_forest_measured(~A, ~E, children)}):
  match plan:
    case Allocation.PlanningFailure{failure}: {==}
    case Allocation.ChildrenPlanned{placements, canvas}:
      Equal.cong(+List<Allocation.MeasuredTree<A, E>>, Model.Tree<A, E>,
        (trees => Model.Container{key, value, interaction, rule, Allocation.source_forest_measured(~A, ~E, trees)}),
        SpaceLaws.placement_values(~Allocation.MeasuredTree<A, E>, placements), children, population)

def finish_children_source(~A: Data, ~E: Data, +result: Allocation.AllocatedChildren<A, E>, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +bounds: Spatial.Box, +canvas: Enclosure.Extent, +direction: Allocation.ResolvedDirection) ->
  {outcome_source(~A, ~E, Allocation.allocated_container(~A, ~E, key, value, interaction, rule, bounds, canvas, direction, result)) ==
    container_source(~A, ~E, key, value, interaction, rule, allocated_children_source(~A, ~E, result)) : Maybe<&2, Model.Tree<A, E>>}:
  match result:
    case Allocation.AllocationFailed{failure}: {==}
    case Allocation.ChildrenAllocated{trees}: {==}

def finish_source(~A: Data, ~E: Data, +previous: +List<Allocation.PositionedOutcome<A, E>>, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +bounds: Spatial.Box, +canvas: Enclosure.Extent, +direction: Allocation.ResolvedDirection) ->
  {outcome_source(~A, ~E, Allocation.allocated_container(~A, ~E, key, value, interaction, rule, bounds, canvas, direction, Allocation.collect_positioned_outcomes(~A, ~E, previous))) ==
    container_source(~A, ~E, key, value, interaction, rule, append_source(~A, ~E, outcome_sources(~A, ~E, previous), Nil{})) : Maybe<&2, Model.Tree<A, E>>}:
  Equal.trans(Maybe<&2, Model.Tree<A, E>>,
    outcome_source(~A, ~E, Allocation.allocated_container(~A, ~E, key, value, interaction, rule, bounds, canvas, direction, Allocation.collect_positioned_outcomes(~A, ~E, previous))),
    container_source(~A, ~E, key, value, interaction, rule, allocated_children_source(~A, ~E, Allocation.collect_positioned_outcomes(~A, ~E, previous))),
    container_source(~A, ~E, key, value, interaction, rule, append_source(~A, ~E, outcome_sources(~A, ~E, previous), Nil{})),
    finish_children_source(~A, ~E, Allocation.collect_positioned_outcomes(~A, ~E, previous), key, value, interaction, rule, bounds, canvas, direction),
    Equal.cong(Maybe<&2, +List<Model.Tree<A, E>>>, Maybe<&2, Model.Tree<A, E>>,
      (trees => container_source(~A, ~E, key, value, interaction, rule, trees)),
      allocated_children_source(~A, ~E, Allocation.collect_positioned_outcomes(~A, ~E, previous)), append_source(~A, ~E, outcome_sources(~A, ~E, previous), Nil{}),
      Equal.trans(Maybe<&2, +List<Model.Tree<A, E>>>,
        allocated_children_source(~A, ~E, Allocation.collect_positioned_outcomes(~A, ~E, previous)), outcome_sources(~A, ~E, previous), append_source(~A, ~E, outcome_sources(~A, ~E, previous), Nil{}),
        collected_source(~A, ~E, previous), Equal.sym(Maybe<&2, +List<Model.Tree<A, E>>>, append_source(~A, ~E, outcome_sources(~A, ~E, previous), Nil{}), outcome_sources(~A, ~E, previous), append_empty(~A, ~E, outcome_sources(~A, ~E, previous))))))

def state_same(~A: Data, ~E: Data, +before: Maybe<&2, Model.Tree<A, E>>, +after: Maybe<&2, Model.Tree<A, E>>, +expected: Model.Tree<A, E>,
  same: {after == before : Maybe<&2, Model.Tree<A, E>>}, proof: partial_match(~A, ~E, before, expected)) -> partial_match(~A, ~E, after, expected):
  Std.transport(Maybe<&2, Model.Tree<A, E>>, before, (source => partial_match(~A, ~E, source, expected)), proof, after, same)

def leaf_demand_same(~A: Data, ~E: Data, +demand: Space.Demand, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +height: Model.Height, +bounds: Spatial.Box, +content_height: Nat, +inner_width: Nat, +inner_height: Nat) ->
  {outcome_source(~A, ~E, Allocation.allocate_leaf_demand(~A, ~E, demand, key, value, interaction, rule, height, bounds, content_height, inner_width, inner_height)) == Some{Model.Leaf{key, value, interaction, rule, demand, height}} : Maybe<&2, Model.Tree<A, E>>}:
  match demand:
    case Space.Demand{Enclosure.Extent{min_width, min_height}, preferred}: {==}

def leaf_same(~A: Data, ~E: Data, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +demand: Space.Demand, +height: Model.Height, +bounds: Spatial.Box, +content_height: Nat) ->
  {outcome_source(~A, ~E, Allocation.allocated_leaf(~A, ~E, key, value, interaction, rule, demand, height, bounds, content_height)) == Some{Model.Leaf{key, value, interaction, rule, demand, height}} : Maybe<&2, Model.Tree<A, E>>}:
  match bounds:
    case Spatial.Box{left, top, +width, +block_height}:
      leaf_demand_same(~A, ~E, demand, key, value, interaction, rule, height, Spatial.Box{left, top, width, block_height}, content_height,
        Nat.sub(width, Nat.mul(2n, Allocation.axis_inset(Allocation.InlineAxis{}, rule))), Nat.sub(block_height, Nat.mul(2n, Allocation.axis_inset(Allocation.BlockAxis{}, rule))))

def step_preserved(~A: Data, ~E: Data, +state: Allocation.HeightState<A, E>, +expected: Model.Tree<A, E>,
  proof: partial_match(~A, ~E, state_source(~A, ~E, state), expected)) ->
  partial_match(~A, ~E, state_source(~A, ~E, Allocation.height_step(~A, ~E, state)), expected):
  match state:
    case Allocation.HeightVisit{+tree, +bounds, +parent}:
      checked_preserved(~A, ~E, Nat.is_le(Allocation.axis_extent(Allocation.BlockAxis{}, Model.minimum_demand(Allocation.measured_demand(~A, ~E, tree))), Allocation.box_height(bounds)), tree, bounds,
        Allocation.axis_extent(Allocation.BlockAxis{}, Model.minimum_demand(Allocation.measured_demand(~A, ~E, tree))), parent, expected, proof)
    case Allocation.HeightMinimumChecked{False{}, tree, bounds, lower, parent}: proof
    case Allocation.HeightMinimumChecked{True{}, Allocation.MeasuredLeaf{+key, +value, +interaction, +rule, +demand, +height, outer_width, inline_offset, +content_height}, +bounds, lower, +parent}:
      state_same(~A, ~E, return_source(~A, ~E, parent, Some{Model.Leaf{key, value, interaction, rule, demand, height}}),
        return_source(~A, ~E, parent, outcome_source(~A, ~E, Allocation.allocated_leaf(~A, ~E, key, value, interaction, rule, demand, height, bounds, content_height))), expected,
        Equal.cong(Maybe<&2, Model.Tree<A, E>>, Maybe<&2, Model.Tree<A, E>>, (source => return_source(~A, ~E, parent, source)),
          outcome_source(~A, ~E, Allocation.allocated_leaf(~A, ~E, key, value, interaction, rule, demand, height, bounds, content_height)), Some{Model.Leaf{key, value, interaction, rule, demand, height}},
          leaf_same(~A, ~E, key, value, interaction, rule, demand, height, bounds, content_height)), proof)
    case Allocation.HeightMinimumChecked{True{}, Allocation.MeasuredContainer{+key, +value, +interaction, +rule, outer_width, inline_offset, +direction, +children}, Spatial.Box{+left, +top, +width, +offered_height}, lower, +parent}:
      return_option(~A, ~E,
        plan_source(~A, ~E, Allocation.prepare_block_children(~A, ~E, key, rule, direction, children, Nat.sub(offered_height, Nat.mul(2n, Allocation.block_inset(rule)))), key, value, interaction, rule),
        Model.Container{key, value, interaction, rule, Allocation.source_forest_measured(~A, ~E, children)}, parent, expected,
        plan_preserved(~A, ~E, Allocation.prepare_block_children(~A, ~E, key, rule, direction, children, Nat.sub(offered_height, Nat.mul(2n, Allocation.block_inset(rule)))), key, value, interaction, rule, children,
          PopulationProof.block_population(~A, ~E, key, rule, direction, children, Nat.sub(offered_height, Nat.mul(2n, Allocation.block_inset(rule))))), proof)
    case Allocation.HeightContainerPlan{Allocation.PlanningFailure{failure}, key, value, interaction, rule, bounds, children, direction, inner_width, left, top, parent}: proof
    case Allocation.HeightContainerPlan{Allocation.ChildrenPlanned{placements, canvas_height}, key, value, interaction, rule, bounds, children, direction, inner_width, left, top, parent}: proof
    case Allocation.HeightChildren{Nil{}, +key, +value, +interaction, +rule, +bounds, +canvas, +direction, +content_left, +content_top, +previous, +parent}:
      state_same(~A, ~E,
        state_source(~A, ~E, Allocation.HeightChildren{Nil{}, key, value, interaction, rule, bounds, canvas, direction, content_left, content_top, previous, parent}),
        state_source(~A, ~E, Allocation.height_step(~A, ~E, Allocation.HeightChildren{Nil{}, key, value, interaction, rule, bounds, canvas, direction, content_left, content_top, previous, parent})), expected,
        Equal.cong(Maybe<&2, Model.Tree<A, E>>, Maybe<&2, Model.Tree<A, E>>, (source => return_source(~A, ~E, parent, source)),
          outcome_source(~A, ~E, Allocation.allocated_container(~A, ~E, key, value, interaction, rule, bounds, canvas, direction, Allocation.collect_positioned_outcomes(~A, ~E, previous))),
          container_source(~A, ~E, key, value, interaction, rule, append_source(~A, ~E, outcome_sources(~A, ~E, previous), Nil{})), finish_source(~A, ~E, previous, key, value, interaction, rule, bounds, canvas, direction)), proof)
    case Allocation.HeightChildren{Con{Space.Placement{Allocation.MeasuredLeaf{child_key, child_value, child_interaction, child_rule, demand, height, outer_width, inline_offset, content_height}, child_offset, extent}, rest}, key, value, interaction, rule, bounds, canvas, direction, content_left, content_top, previous, parent}: proof
    case Allocation.HeightChildren{Con{Space.Placement{Allocation.MeasuredContainer{child_key, child_value, child_interaction, child_rule, outer_width, inline_offset, child_direction, children}, child_offset, extent}, rest}, key, value, interaction, rule, bounds, canvas, direction, content_left, content_top, previous, parent}: proof
    case Allocation.HeightComplete{result, Allocation.HeightRootReturn{}}: proof
    case Allocation.HeightComplete{+result, Allocation.HeightContainerReturn{+key, +value, +interaction, +rule, bounds, canvas, direction, content_left, content_top, +remaining, +previous, +parent}}:
      state_same(~A, ~E,
        return_source(~A, ~E, parent, container_source(~A, ~E, key, value, interaction, rule, child_sources(~A, ~E, previous, outcome_source(~A, ~E, result), remaining))),
        return_source(~A, ~E, parent, container_source(~A, ~E, key, value, interaction, rule, append_source(~A, ~E, outcome_sources(~A, ~E, List.append(&2, Allocation.PositionedOutcome<A, E>, previous, result <> Nil{})), placement_sources(~A, ~E, remaining)))), expected,
        Equal.cong(Maybe<&2, +List<Model.Tree<A, E>>>, Maybe<&2, Model.Tree<A, E>>,
          (children => return_source(~A, ~E, parent, container_source(~A, ~E, key, value, interaction, rule, children))),
          append_source(~A, ~E, outcome_sources(~A, ~E, List.append(&2, Allocation.PositionedOutcome<A, E>, previous, result <> Nil{})), placement_sources(~A, ~E, remaining)),
          child_sources(~A, ~E, previous, outcome_source(~A, ~E, result), remaining), append_current(~A, ~E, previous, result, remaining)), proof)
    case Allocation.HeightDone{result}: proof

def iterate_preserved(~A: Data, ~E: Data, +budget: Nat, +state: Allocation.HeightState<A, E>, +expected: Model.Tree<A, E>,
  proof: partial_match(~A, ~E, state_source(~A, ~E, state), expected)) ->
  partial_match(~A, ~E, state_source(~A, ~E, Std.iter(~Allocation.HeightState<A, E>, ~(value => Allocation.height_step(~A, ~E, value)), budget, state)), expected):
  Std.nat_ind(~(n => @+seed:Allocation.HeightState<A, E> -> @+source:Model.Tree<A, E> ->
    @initial:partial_match(~A, ~E, state_source(~A, ~E, seed), source) ->
    partial_match(~A, ~E, state_source(~A, ~E, Std.iter(~Allocation.HeightState<A, E>, ~(value => Allocation.height_step(~A, ~E, value)), n, seed)), source)),
    ~(+seed => +source => initial => initial),
    ~(+n => induction => +seed => +source => initial => step_preserved(~A, ~E,
      Std.iter(~Allocation.HeightState<A, E>, ~(value => Allocation.height_step(~A, ~E, value)), n, seed), source, induction(seed, source, initial))), budget)(state, expected, proof)

def finish_completed(~A: Data, ~E: Data, +state: Allocation.HeightState<A, E>, +key: String, +height: Nat, +budget: Nat, +expected: Model.Tree<A, E>,
  complete: {Completion.completed(~A, ~E, state) == True{} : Bool},
  proof: partial_match(~A, ~E, state_source(~A, ~E, state), expected)) ->
  Rule.source_claim(~A, ~E, expected, Allocation.finish_height_iteration(~A, ~E, state, key, height, budget)):
  match state:
    case Allocation.HeightDone{Allocation.Positioned{tree}}: proof
    case Allocation.HeightDone{Allocation.PositionFailure{failure}}: {==}
    case Allocation.HeightVisit{tree, bounds, parent}: Order.impossible(Rule.source_claim(~A, ~E, expected, Allocation.PositionFailure{Allocation.Failure{key, Allocation.BlockAxis{}, budget, height, Allocation.AllocationBoundExceeded{budget}}}), complete)
    case Allocation.HeightMinimumChecked{fits, tree, bounds, lower, parent}: Order.impossible(Rule.source_claim(~A, ~E, expected, Allocation.PositionFailure{Allocation.Failure{key, Allocation.BlockAxis{}, budget, height, Allocation.AllocationBoundExceeded{budget}}}), complete)
    case Allocation.HeightContainerPlan{plan, key, value, interaction, rule, bounds, children, direction, inner_width, left, top, parent}: Order.impossible(Rule.source_claim(~A, ~E, expected, Allocation.PositionFailure{Allocation.Failure{key, Allocation.BlockAxis{}, budget, height, Allocation.AllocationBoundExceeded{budget}}}), complete)
    case Allocation.HeightChildren{remaining, key, value, interaction, rule, bounds, canvas, direction, content_left, content_top, previous, parent}: Order.impossible(Rule.source_claim(~A, ~E, expected, Allocation.PositionFailure{Allocation.Failure{key, Allocation.BlockAxis{}, budget, height, Allocation.AllocationBoundExceeded{budget}}}), complete)
    case Allocation.HeightComplete{result, parent}: Order.impossible(Rule.source_claim(~A, ~E, expected, Allocation.PositionFailure{Allocation.Failure{key, Allocation.BlockAxis{}, budget, height, Allocation.AllocationBoundExceeded{budget}}}), complete)

def preserved(~A: Data, ~E: Data, +tree: Allocation.MeasuredTree<A, E>, +bounds: Spatial.Box) ->
  Rule.source_claim(~A, ~E, Allocation.source_of_measured(~A, ~E, tree), Allocation.allocate_measured(~A, ~E, tree, bounds)):
  finish_completed(~A, ~E, Allocation.iterate_height(~A, ~E, tree, bounds), Allocation.measured_key(~A, ~E, tree), Allocation.box_height(bounds),
    Allocation.height_forest_work(~A, ~E, tree <> Nil{}), Allocation.source_of_measured(~A, ~E, tree),
    CompletionProof.complete(~A, ~E, tree, bounds),
    iterate_preserved(~A, ~E, Allocation.height_forest_work(~A, ~E, tree <> Nil{}), Allocation.HeightVisit{tree, bounds, Allocation.HeightRootReturn{}}, Allocation.source_of_measured(~A, ~E, tree), {==}))

def Rule.evidence(A, E):
  Rule.Requirements{+tree => +bounds => preserved(~A, ~E, tree, bounds)}
