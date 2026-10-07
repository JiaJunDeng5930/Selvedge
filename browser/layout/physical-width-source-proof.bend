import Base
import ../../bendlib/stdlib.bend as Std
import ./physical-space.bend as Model
import ./PROGRAM.bend as Allocation
import ./physical-width-source-rules.bend as Rule
import ./physical-width-rules.bend as Completion
import ./physical-width-proof.bend as CompletionProof
import ./physical-allocation-population-rules.bend as Population
import ./physical-allocation-population-proof.bend as PopulationProof
import ./SPACE.bend as Space
import ./space-laws.bend as SpaceLaws
import ../../bendlib/logic-proof.bend as Logic

# The partial source observes only fields consumed by production. A failed or
# pending child makes the enclosing computation incapable of a ready result.
def outcome_source(~A: Data, ~E: Data, result: Allocation.WidthOutcome<A, E>) -> Maybe<&2, Model.Tree<A, E>>:
  match result:
    case Allocation.WidthReady{tree}: Some{Allocation.source_of_measured(~A, ~E, tree)}
    case Allocation.HeightPending{first, remaining}: None{}
    case Allocation.WidthFailure{failure}: None{}

def cons_source(~A: Data, ~E: Data, first: Maybe<&2, Model.Tree<A, E>>, rest: Maybe<&2, +List<Model.Tree<A, E>>>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  match first rest:
    case Some{tree} Some{trees}: Some{tree <> trees}
    case _ _: None{}

def outcome_sources(~A: Data, ~E: Data, values: +List<Allocation.WidthOutcome<A, E>>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
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

def child_sources_from_erased(~A: Data, ~E: Data, current: Maybe<&2, Model.Tree<A, E>>, previous: Maybe<&2, +List<Model.Tree<A, E>>>, remaining: +List<Space.Placement<Model.Tree<A, E>>>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  match current:
    case None{}: None{}
    case Some{tree}: append_source(~A, ~E, previous, tree <> SpaceLaws.placement_values(~Model.Tree<A, E>, remaining))

def child_sources(~A: Data, ~E: Data, previous: +List<Allocation.WidthOutcome<A, E>>, current: Maybe<&2, Model.Tree<A, E>>, remaining: +List<Space.Placement<Model.Tree<A, E>>>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  child_sources_from_erased(~A, ~E, current, outcome_sources(~A, ~E, previous), remaining)

def return_source(~A: Data, ~E: Data, return_to: Allocation.WidthReturn<A, E>, current: Maybe<&2, Model.Tree<A, E>>) -> Maybe<&2, Model.Tree<A, E>>:
  match return_to:
    case Allocation.WidthRootReturn{}: current
    case Allocation.WidthContainerReturn{key, value, interaction, rule, width, offset, direction, remaining, previous, parent}:
      return_source(~A, ~E, parent, container_source(~A, ~E, key, value, interaction, rule, child_sources(~A, ~E, previous, current, remaining)))

def plan_source(~A: Data, ~E: Data, plan: Allocation.InlinePlan<A, E>, key: String, value: A, interaction: Model.Interaction<E>, rule: Model.Rule) -> Maybe<&2, Model.Tree<A, E>>:
  match plan:
    case Allocation.InlineFailure{failure}: None{}
    case Allocation.InlinePlanned{placements, direction, canvas}:
      Some{Model.Container{key, value, interaction, rule, SpaceLaws.placement_values(~Model.Tree<A, E>, placements)}}

def state_source(~A: Data, ~E: Data, state: Allocation.WidthState<A, E>) -> Maybe<&2, Model.Tree<A, E>>:
  match state:
    case Allocation.WidthVisit{tree, width, offset, parent}: return_source(~A, ~E, parent, Some{tree})
    case Allocation.WidthMinimumChecked{False{}, tree, width, offset, rule, lower, parent}: return_source(~A, ~E, parent, None{})
    case Allocation.WidthMinimumChecked{True{}, tree, width, offset, rule, lower, parent}: return_source(~A, ~E, parent, Some{tree})
    case Allocation.WidthLeafHeight{None{}, key, value, interaction, rule, demand, height, inner_width, width, offset, parent}: return_source(~A, ~E, parent, None{})
    case Allocation.WidthLeafHeight{Some{sample}, key, value, interaction, rule, demand, height, inner_width, width, offset, parent}:
      return_source(~A, ~E, parent, Some{Model.Leaf{key, value, interaction, rule, demand, height}})
    case Allocation.WidthContainerPlan{plan, key, value, interaction, rule, width, offset, parent}:
      return_source(~A, ~E, parent, plan_source(~A, ~E, plan, key, value, interaction, rule))
    case Allocation.WidthChildren{remaining, key, value, interaction, rule, width, offset, direction, previous, parent}:
      return_source(~A, ~E, parent, container_source(~A, ~E, key, value, interaction, rule,
        append_source(~A, ~E, outcome_sources(~A, ~E, previous), SpaceLaws.placement_values(~Model.Tree<A, E>, remaining))))
    case Allocation.WidthComplete{result, parent}: return_source(~A, ~E, parent, outcome_source(~A, ~E, result))
    case Allocation.WidthDone{result}: outcome_source(~A, ~E, result)

def partial_match(~A: Data, ~E: Data, actual: Maybe<&2, Model.Tree<A, E>>, expected: Model.Tree<A, E>) -> Type:
  match actual:
    case None{}: {True{} == True{} : Bool}
    case Some{source}: {source == expected : Model.Tree<A, E>}

def return_none(~A: Data, ~E: Data, parent: Allocation.WidthReturn<A, E>) ->
  {return_source(~A, ~E, parent, None{}) == None{} : Maybe<&2, Model.Tree<A, E>>}:
  match parent:
    case Allocation.WidthRootReturn{}: {==}
    case Allocation.WidthContainerReturn{key, value, interaction, rule, width, offset, direction, remaining, previous, rest}:
      return_none(~A, ~E, rest)

def return_drop(~A: Data, ~E: Data, +parent: Allocation.WidthReturn<A, E>, +expected: Model.Tree<A, E>) ->
  partial_match(~A, ~E, return_source(~A, ~E, parent, None{}), expected):
  Std.transport(Maybe<&2, Model.Tree<A, E>>, None{},
    (actual => partial_match(~A, ~E, actual, expected)), {==},
    return_source(~A, ~E, parent, None{}), return_none(~A, ~E, parent))

def return_same(~A: Data, ~E: Data, +parent: Allocation.WidthReturn<A, E>, +actual: Model.Tree<A, E>, +source: Model.Tree<A, E>, +expected: Model.Tree<A, E>,
  same: {actual == source : Model.Tree<A, E>},
  proof: partial_match(~A, ~E, return_source(~A, ~E, parent, Some{source}), expected)) ->
  partial_match(~A, ~E, return_source(~A, ~E, parent, Some{actual}), expected):
  Std.transport(Model.Tree<A, E>, source,
    (tree => partial_match(~A, ~E, return_source(~A, ~E, parent, Some{tree}), expected)),
    proof, actual, same)

def measured_children_source(~A: Data, ~E: Data, children: Allocation.MeasuredChildren<A, E>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  match children:
    case Allocation.ChildrenFailed{failure}: None{}
    case Allocation.ChildrenPending{first, remaining}: None{}
    case Allocation.ChildrenMeasured{trees}: Some{Allocation.source_forest_measured(~A, ~E, trees)}

def merge_source(~A: Data, ~E: Data, +first: Allocation.WidthOutcome<A, E>, +rest: Allocation.MeasuredChildren<A, E>) ->
  {measured_children_source(~A, ~E, Allocation.merge_width(~A, ~E, first, rest)) ==
    cons_source(~A, ~E, outcome_source(~A, ~E, first), measured_children_source(~A, ~E, rest)) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match first rest:
    case Allocation.WidthFailure{failure} _: {==}
    case Allocation.HeightPending{first, remaining} Allocation.ChildrenFailed{failure}: {==}
    case Allocation.HeightPending{first, remaining} Allocation.ChildrenPending{next, tail}: {==}
    case Allocation.HeightPending{first, remaining} Allocation.ChildrenMeasured{trees}: {==}
    case Allocation.WidthReady{tree} Allocation.ChildrenFailed{failure}: {==}
    case Allocation.WidthReady{tree} Allocation.ChildrenPending{first, remaining}: {==}
    case Allocation.WidthReady{Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, width, offset, sample}} Allocation.ChildrenMeasured{trees}: {==}
    case Allocation.WidthReady{Allocation.MeasuredContainer{key, value, interaction, rule, width, offset, direction, children}} Allocation.ChildrenMeasured{trees}: {==}

def collected_source(~A: Data, ~E: Data, +values: +List<Allocation.WidthOutcome<A, E>>) ->
  {measured_children_source(~A, ~E, Allocation.collect_width_outcomes(~A, ~E, values)) ==
    outcome_sources(~A, ~E, values) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match values:
    case Nil{}: {==}
    case Con{+first, +rest}:
      Equal.trans(Maybe<&2, +List<Model.Tree<A, E>>>,
        measured_children_source(~A, ~E, Allocation.merge_width(~A, ~E, first, Allocation.collect_width_outcomes(~A, ~E, rest))),
        cons_source(~A, ~E, outcome_source(~A, ~E, first), measured_children_source(~A, ~E, Allocation.collect_width_outcomes(~A, ~E, rest))),
        cons_source(~A, ~E, outcome_source(~A, ~E, first), outcome_sources(~A, ~E, rest)),
        merge_source(~A, ~E, first, Allocation.collect_width_outcomes(~A, ~E, rest)),
        Equal.cong(Maybe<&2, +List<Model.Tree<A, E>>>, Maybe<&2, +List<Model.Tree<A, E>>>,
          (trees => cons_source(~A, ~E, outcome_source(~A, ~E, first), trees)),
          measured_children_source(~A, ~E, Allocation.collect_width_outcomes(~A, ~E, rest)), outcome_sources(~A, ~E, rest), collected_source(~A, ~E, rest)))

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

def child_cons(~A: Data, ~E: Data, +first: Maybe<&2, Model.Tree<A, E>>, +rest: Maybe<&2, +List<Model.Tree<A, E>>>, +current: Maybe<&2, Model.Tree<A, E>>, +remaining: +List<Space.Placement<Model.Tree<A, E>>>) ->
  {cons_source(~A, ~E, first, child_sources_from_erased(~A, ~E, current, rest, remaining)) ==
    child_sources_from_erased(~A, ~E, current, cons_source(~A, ~E, first, rest), remaining) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match first current:
    case None{} None{}: {==}
    case Some{tree} None{}: {==}
    case _ Some{tree}: Equal.sym(Maybe<&2, +List<Model.Tree<A, E>>>,
      append_source(~A, ~E, cons_source(~A, ~E, first, rest), tree <> SpaceLaws.placement_values(~Model.Tree<A, E>, remaining)),
      cons_source(~A, ~E, first, append_source(~A, ~E, rest, tree <> SpaceLaws.placement_values(~Model.Tree<A, E>, remaining))),
      append_cons(~A, ~E, first, rest, tree <> SpaceLaws.placement_values(~Model.Tree<A, E>, remaining)))

def append_current_cons(~A: Data, ~E: Data, +first: Maybe<&2, Model.Tree<A, E>>, +rest: +List<Allocation.WidthOutcome<A, E>>, +current: Allocation.WidthOutcome<A, E>, +remaining: +List<Space.Placement<Model.Tree<A, E>>>,
  same: {append_source(~A, ~E, outcome_sources(~A, ~E, List.append(&2, Allocation.WidthOutcome<A, E>, rest, current <> Nil{})), SpaceLaws.placement_values(~Model.Tree<A, E>, remaining)) ==
    child_sources(~A, ~E, rest, outcome_source(~A, ~E, current), remaining) : Maybe<&2, +List<Model.Tree<A, E>>>}) ->
  {cons_source(~A, ~E, first, append_source(~A, ~E, outcome_sources(~A, ~E, List.append(&2, Allocation.WidthOutcome<A, E>, rest, current <> Nil{})), SpaceLaws.placement_values(~Model.Tree<A, E>, remaining))) ==
    child_sources_from_erased(~A, ~E, outcome_source(~A, ~E, current), cons_source(~A, ~E, first, outcome_sources(~A, ~E, rest)), remaining) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  Equal.trans(Maybe<&2, +List<Model.Tree<A, E>>>,
    cons_source(~A, ~E, first, append_source(~A, ~E, outcome_sources(~A, ~E, List.append(&2, Allocation.WidthOutcome<A, E>, rest, current <> Nil{})), SpaceLaws.placement_values(~Model.Tree<A, E>, remaining))),
    cons_source(~A, ~E, first, child_sources(~A, ~E, rest, outcome_source(~A, ~E, current), remaining)),
    child_sources_from_erased(~A, ~E, outcome_source(~A, ~E, current), cons_source(~A, ~E, first, outcome_sources(~A, ~E, rest)), remaining),
    Equal.cong(Maybe<&2, +List<Model.Tree<A, E>>>, Maybe<&2, +List<Model.Tree<A, E>>>, (trees => cons_source(~A, ~E, first, trees)),
      append_source(~A, ~E, outcome_sources(~A, ~E, List.append(&2, Allocation.WidthOutcome<A, E>, rest, current <> Nil{})), SpaceLaws.placement_values(~Model.Tree<A, E>, remaining)), child_sources(~A, ~E, rest, outcome_source(~A, ~E, current), remaining), same),
    child_cons(~A, ~E, first, outcome_sources(~A, ~E, rest), outcome_source(~A, ~E, current), remaining))

def append_current(~A: Data, ~E: Data, +previous: +List<Allocation.WidthOutcome<A, E>>, +current: Allocation.WidthOutcome<A, E>, +remaining: +List<Space.Placement<Model.Tree<A, E>>>) ->
  {append_source(~A, ~E, outcome_sources(~A, ~E, List.append(&2, Allocation.WidthOutcome<A, E>, previous, current <> Nil{})), SpaceLaws.placement_values(~Model.Tree<A, E>, remaining)) ==
    child_sources(~A, ~E, previous, outcome_source(~A, ~E, current), remaining) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match previous current:
    case Nil{} Allocation.WidthReady{tree}: {==}
    case Nil{} Allocation.HeightPending{first, tail}: {==}
    case Nil{} Allocation.WidthFailure{failure}: {==}
    case Con{+first, +rest} +current:
      Equal.trans(Maybe<&2, +List<Model.Tree<A, E>>>,
        append_source(~A, ~E, cons_source(~A, ~E, outcome_source(~A, ~E, first), outcome_sources(~A, ~E, List.append(&2, Allocation.WidthOutcome<A, E>, rest, current <> Nil{}))), SpaceLaws.placement_values(~Model.Tree<A, E>, remaining)),
        cons_source(~A, ~E, outcome_source(~A, ~E, first), append_source(~A, ~E, outcome_sources(~A, ~E, List.append(&2, Allocation.WidthOutcome<A, E>, rest, current <> Nil{})), SpaceLaws.placement_values(~Model.Tree<A, E>, remaining))),
        child_sources(~A, ~E, first <> rest, outcome_source(~A, ~E, current), remaining),
        append_cons(~A, ~E, outcome_source(~A, ~E, first), outcome_sources(~A, ~E, List.append(&2, Allocation.WidthOutcome<A, E>, rest, current <> Nil{})), SpaceLaws.placement_values(~Model.Tree<A, E>, remaining)),
        append_current_cons(~A, ~E, outcome_source(~A, ~E, first), rest, current, remaining, append_current(~A, ~E, rest, current, remaining)))

def return_option(~A: Data, ~E: Data, +actual: Maybe<&2, Model.Tree<A, E>>, +source: Model.Tree<A, E>, +parent: Allocation.WidthReturn<A, E>, +expected: Model.Tree<A, E>,
  same: partial_match(~A, ~E, actual, source),
  proof: partial_match(~A, ~E, return_source(~A, ~E, parent, Some{source}), expected)) ->
  partial_match(~A, ~E, return_source(~A, ~E, parent, actual), expected):
  match actual:
    case None{}: return_drop(~A, ~E, parent, expected)
    case Some{tree}: return_same(~A, ~E, parent, tree, source, expected, same, proof)

def checked_preserved(~A: Data, ~E: Data, +fits: Bool, +tree: Model.Tree<A, E>, +width: Nat, +offset: Nat, +rule: Model.Rule, +lower: Nat, +parent: Allocation.WidthReturn<A, E>, +expected: Model.Tree<A, E>,
  proof: partial_match(~A, ~E, return_source(~A, ~E, parent, Some{tree}), expected)) ->
  partial_match(~A, ~E, state_source(~A, ~E, Allocation.WidthMinimumChecked{fits, tree, width, offset, rule, lower, parent}), expected):
  match fits:
    case False{}: return_drop(~A, ~E, parent, expected)
    case True{}: proof

def visit_preserved(~A: Data, ~E: Data, +valid: Bool, +tree: Model.Tree<A, E>, +width: Nat, +offset: Nat, +rule: Model.Rule, +lower: Nat, +parent: Allocation.WidthReturn<A, E>, +expected: Model.Tree<A, E>,
  proof: partial_match(~A, ~E, return_source(~A, ~E, parent, Some{tree}), expected)) ->
  partial_match(~A, ~E, state_source(~A, ~E, Allocation.width_visit_checked(~A, ~E, valid, tree, width, offset, rule, lower, parent)), expected):
  match valid:
    case False{}: return_drop(~A, ~E, parent, expected)
    case True{}: checked_preserved(~A, ~E, Nat.is_le(lower, width), tree, width, offset, rule, lower, parent, expected, proof)

def leaf_preserved(~A: Data, ~E: Data, +sample: Maybe<&2, Nat>, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +demand: Space.Demand, +height: Model.Height, +inner_width: Nat, +width: Nat, +offset: Nat, +parent: Allocation.WidthReturn<A, E>, +expected: Model.Tree<A, E>,
  proof: partial_match(~A, ~E, return_source(~A, ~E, parent, Some{Model.Leaf{key, value, interaction, rule, demand, height}}), expected)) ->
  partial_match(~A, ~E, state_source(~A, ~E, Allocation.WidthLeafHeight{sample, key, value, interaction, rule, demand, height, inner_width, width, offset, parent}), expected):
  match sample:
    case None{}: return_drop(~A, ~E, parent, expected)
    case Some{sample}: proof

def plan_preserved(~A: Data, ~E: Data, +plan: Allocation.InlinePlan<A, E>, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +children: +List<Model.Tree<A, E>>,
  population: Population.InlinePopulation(~A, ~E, children, plan)) ->
  partial_match(~A, ~E, plan_source(~A, ~E, plan, key, value, interaction, rule), Model.Container{key, value, interaction, rule, children}):
  match plan:
    case Allocation.InlineFailure{failure}: {==}
    case Allocation.InlinePlanned{placements, direction, canvas}:
      Equal.cong(+List<Model.Tree<A, E>>, Model.Tree<A, E>,
        (trees => Model.Container{key, value, interaction, rule, trees}), SpaceLaws.placement_values(~Model.Tree<A, E>, placements), children, population)

def finish_children_source(~A: Data, ~E: Data, +result: Allocation.MeasuredChildren<A, E>, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +width: Nat, +offset: Nat, +direction: Allocation.ResolvedDirection) ->
  {outcome_source(~A, ~E, Allocation.finish_measurement(~A, ~E, key, value, interaction, rule, width, offset, direction, result)) ==
    container_source(~A, ~E, key, value, interaction, rule, measured_children_source(~A, ~E, result)) : Maybe<&2, Model.Tree<A, E>>}:
  match result:
    case Allocation.ChildrenFailed{failure}: {==}
    case Allocation.ChildrenPending{first, remaining}: {==}
    case Allocation.ChildrenMeasured{trees}: {==}

def finish_source(~A: Data, ~E: Data, +previous: +List<Allocation.WidthOutcome<A, E>>, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +width: Nat, +offset: Nat, +direction: Allocation.ResolvedDirection) ->
  {outcome_source(~A, ~E, Allocation.finish_measurement(~A, ~E, key, value, interaction, rule, width, offset, direction, Allocation.collect_width_outcomes(~A, ~E, previous))) ==
    container_source(~A, ~E, key, value, interaction, rule, append_source(~A, ~E, outcome_sources(~A, ~E, previous), Nil{})) : Maybe<&2, Model.Tree<A, E>>}:
  Equal.trans(Maybe<&2, Model.Tree<A, E>>,
    outcome_source(~A, ~E, Allocation.finish_measurement(~A, ~E, key, value, interaction, rule, width, offset, direction, Allocation.collect_width_outcomes(~A, ~E, previous))),
    container_source(~A, ~E, key, value, interaction, rule, measured_children_source(~A, ~E, Allocation.collect_width_outcomes(~A, ~E, previous))),
    container_source(~A, ~E, key, value, interaction, rule, append_source(~A, ~E, outcome_sources(~A, ~E, previous), Nil{})),
    finish_children_source(~A, ~E, Allocation.collect_width_outcomes(~A, ~E, previous), key, value, interaction, rule, width, offset, direction),
    Equal.cong(Maybe<&2, +List<Model.Tree<A, E>>>, Maybe<&2, Model.Tree<A, E>>,
      (trees => container_source(~A, ~E, key, value, interaction, rule, trees)),
      measured_children_source(~A, ~E, Allocation.collect_width_outcomes(~A, ~E, previous)), append_source(~A, ~E, outcome_sources(~A, ~E, previous), Nil{}),
      Equal.trans(Maybe<&2, +List<Model.Tree<A, E>>>,
        measured_children_source(~A, ~E, Allocation.collect_width_outcomes(~A, ~E, previous)), outcome_sources(~A, ~E, previous), append_source(~A, ~E, outcome_sources(~A, ~E, previous), Nil{}),
        collected_source(~A, ~E, previous), Equal.sym(Maybe<&2, +List<Model.Tree<A, E>>>, append_source(~A, ~E, outcome_sources(~A, ~E, previous), Nil{}), outcome_sources(~A, ~E, previous), append_empty(~A, ~E, outcome_sources(~A, ~E, previous))))))

def state_same(~A: Data, ~E: Data, +before: Maybe<&2, Model.Tree<A, E>>, +after: Maybe<&2, Model.Tree<A, E>>, +expected: Model.Tree<A, E>,
  same: {after == before : Maybe<&2, Model.Tree<A, E>>}, proof: partial_match(~A, ~E, before, expected)) -> partial_match(~A, ~E, after, expected):
  Std.transport(Maybe<&2, Model.Tree<A, E>>, before, (source => partial_match(~A, ~E, source, expected)), proof, after, same)

def step_preserved(~A: Data, ~E: Data, +state: Allocation.WidthState<A, E>, +samples: +List<Model.HeightSample>, +expected: Model.Tree<A, E>,
  proof: partial_match(~A, ~E, state_source(~A, ~E, state), expected)) ->
  partial_match(~A, ~E, state_source(~A, ~E, Allocation.width_step(~A, ~E, state, samples)), expected):
  match state:
    case Allocation.WidthVisit{+tree, +width, offset, +parent}:
      visit_preserved(~A, ~E, Allocation.width_visit_valid(~A, ~E, Allocation.tree_rule(~A, ~E, tree), parent), tree, width, offset, Allocation.tree_rule(~A, ~E, tree), Allocation.axis_extent(Allocation.InlineAxis{}, Model.minimum_demand(Model.demand(~A, ~E, tree))), parent, expected, proof)
    case Allocation.WidthMinimumChecked{False{}, tree, width, offset, rule, lower, parent}: proof
    case Allocation.WidthMinimumChecked{True{}, Model.Leaf{key, value, interaction, +rule, demand, +height}, +width, offset, checked_rule, lower, parent}:
      leaf_preserved(~A, ~E, Allocation.leaf_height(height, Nat.sub(width, Nat.mul(2n, Allocation.inline_inset(rule))), samples), key, value, interaction, rule, demand, height, Nat.sub(width, Nat.mul(2n, Allocation.inline_inset(rule))), width, offset, parent, expected, proof)
    case Allocation.WidthMinimumChecked{True{}, Model.Container{+key, +value, +interaction, +rule, +children}, +width, offset, checked_rule, lower, +parent}:
      return_option(~A, ~E,
        plan_source(~A, ~E, Allocation.prepare_inline_children(~A, ~E, key, rule, children, Nat.sub(width, Nat.mul(2n, Allocation.inline_inset(rule)))), key, value, interaction, rule),
        Model.Container{key, value, interaction, rule, children}, parent, expected,
        plan_preserved(~A, ~E, Allocation.prepare_inline_children(~A, ~E, key, rule, children, Nat.sub(width, Nat.mul(2n, Allocation.inline_inset(rule)))), key, value, interaction, rule, children,
          PopulationProof.inline_population(~A, ~E, key, rule, children, Nat.sub(width, Nat.mul(2n, Allocation.inline_inset(rule))))), proof)
    case Allocation.WidthLeafHeight{None{}, key, value, interaction, rule, demand, height, inner_width, width, offset, parent}: proof
    case Allocation.WidthLeafHeight{Some{sample}, key, value, interaction, rule, demand, height, inner_width, width, offset, parent}: proof
    case Allocation.WidthContainerPlan{Allocation.InlineFailure{failure}, key, value, interaction, rule, width, offset, parent}: proof
    case Allocation.WidthContainerPlan{Allocation.InlinePlanned{placements, direction, canvas}, key, value, interaction, rule, width, offset, parent}: proof
    case Allocation.WidthChildren{Nil{}, +key, +value, +interaction, +rule, +width, +offset, +direction, +previous, +parent}:
      state_same(~A, ~E,
        state_source(~A, ~E, Allocation.WidthChildren{Nil{}, key, value, interaction, rule, width, offset, direction, previous, parent}),
        state_source(~A, ~E, Allocation.width_step(~A, ~E, Allocation.WidthChildren{Nil{}, key, value, interaction, rule, width, offset, direction, previous, parent}, samples)), expected,
        Equal.cong(Maybe<&2, Model.Tree<A, E>>, Maybe<&2, Model.Tree<A, E>>, (source => return_source(~A, ~E, parent, source)),
          outcome_source(~A, ~E, Allocation.finish_measurement(~A, ~E, key, value, interaction, rule, width, offset, direction, Allocation.collect_width_outcomes(~A, ~E, previous))),
          container_source(~A, ~E, key, value, interaction, rule, append_source(~A, ~E, outcome_sources(~A, ~E, previous), Nil{})), finish_source(~A, ~E, previous, key, value, interaction, rule, width, offset, direction)), proof)
    case Allocation.WidthChildren{Con{Space.Placement{child, child_offset, extent}, rest}, key, value, interaction, rule, width, offset, direction, previous, parent}: proof
    case Allocation.WidthComplete{result, Allocation.WidthRootReturn{}}: proof
    case Allocation.WidthComplete{+result, Allocation.WidthContainerReturn{+key, +value, +interaction, +rule, width, offset, direction, +remaining, +previous, +parent}}:
      state_same(~A, ~E,
        return_source(~A, ~E, parent, container_source(~A, ~E, key, value, interaction, rule, child_sources(~A, ~E, previous, outcome_source(~A, ~E, result), remaining))),
        return_source(~A, ~E, parent, container_source(~A, ~E, key, value, interaction, rule, append_source(~A, ~E, outcome_sources(~A, ~E, List.append(&2, Allocation.WidthOutcome<A, E>, previous, result <> Nil{})), SpaceLaws.placement_values(~Model.Tree<A, E>, remaining)))), expected,
        Equal.cong(Maybe<&2, +List<Model.Tree<A, E>>>, Maybe<&2, Model.Tree<A, E>>,
          (children => return_source(~A, ~E, parent, container_source(~A, ~E, key, value, interaction, rule, children))),
          append_source(~A, ~E, outcome_sources(~A, ~E, List.append(&2, Allocation.WidthOutcome<A, E>, previous, result <> Nil{})), SpaceLaws.placement_values(~Model.Tree<A, E>, remaining)),
          child_sources(~A, ~E, previous, outcome_source(~A, ~E, result), remaining), append_current(~A, ~E, previous, result, remaining)), proof)
    case Allocation.WidthDone{result}: proof

def execution_preserved(~A: Data, ~E: Data, +execution: Allocation.WidthExecution<A, E>, +expected: Model.Tree<A, E>,
  proof: partial_match(~A, ~E, state_source(~A, ~E, Allocation.width_execution_state(~A, ~E, execution)), expected)) ->
  partial_match(~A, ~E, state_source(~A, ~E, Allocation.width_execution_state(~A, ~E, Allocation.width_execution_step(~A, ~E, execution))), expected):
  match execution:
    case Allocation.WidthExecution{state, samples}: step_preserved(~A, ~E, state, samples, expected, proof)

def iterate_preserved(~A: Data, ~E: Data, +budget: Nat, +execution: Allocation.WidthExecution<A, E>, +expected: Model.Tree<A, E>,
  proof: partial_match(~A, ~E, state_source(~A, ~E, Allocation.width_execution_state(~A, ~E, execution)), expected)) ->
  partial_match(~A, ~E, state_source(~A, ~E, Allocation.width_execution_state(~A, ~E, Std.iter(~Allocation.WidthExecution<A, E>, ~(value => Allocation.width_execution_step(~A, ~E, value)), budget, execution))), expected):
  Std.nat_ind(~(n => @+seed:Allocation.WidthExecution<A, E> -> @+source:Model.Tree<A, E> ->
    @initial:partial_match(~A, ~E, state_source(~A, ~E, Allocation.width_execution_state(~A, ~E, seed)), source) ->
    partial_match(~A, ~E, state_source(~A, ~E, Allocation.width_execution_state(~A, ~E, Std.iter(~Allocation.WidthExecution<A, E>, ~(value => Allocation.width_execution_step(~A, ~E, value)), n, seed))), source)),
    ~(+seed => +source => initial => initial),
    ~(+n => induction => +seed => +source => initial => execution_preserved(~A, ~E,
      Std.iter(~Allocation.WidthExecution<A, E>, ~(value => Allocation.width_execution_step(~A, ~E, value)), n, seed), source, induction(seed, source, initial))), budget)(execution, expected, proof)

def outcome_preserved(~A: Data, ~E: Data, +result: Allocation.WidthOutcome<A, E>, +expected: Model.Tree<A, E>,
  proof: partial_match(~A, ~E, outcome_source(~A, ~E, result), expected)) ->
  Rule.source_claim(~A, ~E, expected, result):
  match result:
    case Allocation.WidthReady{tree}: proof
    case Allocation.HeightPending{first, remaining}: {==}
    case Allocation.WidthFailure{failure}: {==}

def finish_completed(~A: Data, ~E: Data, +state: Allocation.WidthState<A, E>, +key: String, +width: Nat, +budget: Nat, +expected: Model.Tree<A, E>,
  complete: {Completion.completed(~A, ~E, state) == True{} : Bool},
  proof: partial_match(~A, ~E, state_source(~A, ~E, state), expected)) ->
  Rule.source_claim(~A, ~E, expected, Allocation.finish_width_iteration(~A, ~E, state, key, width, budget)):
  match state:
    case Allocation.WidthDone{+result}: outcome_preserved(~A, ~E, result, expected, proof)
    case Allocation.WidthVisit{tree, extent, offset, parent}: Logic.impossible(Rule.source_claim(~A, ~E, expected, Allocation.WidthFailure{Allocation.Failure{key, Allocation.InlineAxis{}, budget, width, Allocation.AllocationBoundExceeded{budget}}}), complete)
    case Allocation.WidthMinimumChecked{fits, tree, extent, offset, rule, lower, parent}: Logic.impossible(Rule.source_claim(~A, ~E, expected, Allocation.WidthFailure{Allocation.Failure{key, Allocation.InlineAxis{}, budget, width, Allocation.AllocationBoundExceeded{budget}}}), complete)
    case Allocation.WidthLeafHeight{sample, leaf_key, value, interaction, rule, demand, height, inner_width, outer_width, offset, parent}: Logic.impossible(Rule.source_claim(~A, ~E, expected, Allocation.WidthFailure{Allocation.Failure{key, Allocation.InlineAxis{}, budget, width, Allocation.AllocationBoundExceeded{budget}}}), complete)
    case Allocation.WidthContainerPlan{plan, container_key, value, interaction, rule, outer_width, offset, parent}: Logic.impossible(Rule.source_claim(~A, ~E, expected, Allocation.WidthFailure{Allocation.Failure{key, Allocation.InlineAxis{}, budget, width, Allocation.AllocationBoundExceeded{budget}}}), complete)
    case Allocation.WidthChildren{remaining, container_key, value, interaction, rule, outer_width, offset, direction, previous, parent}: Logic.impossible(Rule.source_claim(~A, ~E, expected, Allocation.WidthFailure{Allocation.Failure{key, Allocation.InlineAxis{}, budget, width, Allocation.AllocationBoundExceeded{budget}}}), complete)
    case Allocation.WidthComplete{result, parent}: Logic.impossible(Rule.source_claim(~A, ~E, expected, Allocation.WidthFailure{Allocation.Failure{key, Allocation.InlineAxis{}, budget, width, Allocation.AllocationBoundExceeded{budget}}}), complete)

def measure_preserved(~A: Data, ~E: Data, +tree: Model.Tree<A, E>, +width: Nat, +offset: Nat, +samples: +List<Model.HeightSample>) ->
  Rule.source_claim(~A, ~E, tree, Allocation.measure_at(~A, ~E, tree, width, offset, samples)):
  finish_completed(~A, ~E, Allocation.iterate_width(~A, ~E, tree, width, offset, samples), Allocation.tree_key(~A, ~E, tree), width, Allocation.width_forest_work(~A, ~E, tree <> Nil{}), tree,
    CompletionProof.complete(~A, ~E, tree, width, offset, samples),
    iterate_preserved(~A, ~E, Allocation.width_forest_work(~A, ~E, tree <> Nil{}), Allocation.WidthExecution{Allocation.WidthVisit{tree, width, offset, Allocation.WidthRootReturn{}}, samples}, tree, {==}))

def first_tree(~A: Data, ~E: Data, values: +List<Model.Tree<A, E>>, fallback: Model.Tree<A, E>) -> Model.Tree<A, E>:
  match values:
    case Nil{}: fallback
    case Con{first, remaining}: first

def root_preserved(~A: Data, ~E: Data, +placements: +List<Space.Placement<Model.Tree<A, E>>>, +tree: Model.Tree<A, E>, +samples: +List<Model.HeightSample>,
  population: {SpaceLaws.placement_values(~Model.Tree<A, E>, placements) == tree <> Nil{} : +List<Model.Tree<A, E>>}) ->
  Rule.source_claim(~A, ~E, tree, Allocation.root_measurement(~A, ~E, tree, placements, samples)):
  match placements:
    case Nil{}: {==}
    case Con{Space.Placement{+value, offset, extent}, rest}:
      Std.transport(Model.Tree<A, E>, value,
        (source => Rule.source_claim(~A, ~E, source, Allocation.measure_at(~A, ~E, value, extent, offset, samples))),
        measure_preserved(~A, ~E, value, extent, offset, samples), tree,
        Equal.sym(Model.Tree<A, E>, value, tree,
          Equal.cong(+List<Model.Tree<A, E>>, Model.Tree<A, E>, (values => first_tree(~A, ~E, values, value)),
            SpaceLaws.placement_values(~Model.Tree<A, E>, Space.Placement{value, offset, extent} <> rest), tree <> Nil{}, population)))

def packed_preserved(~A: Data, ~E: Data, +packing: Space.Packing<Model.Tree<A, E>>, +tree: Model.Tree<A, E>, +samples: +List<Model.HeightSample>,
  population: PopulationProof.PackingPopulation(~Model.Tree<A, E>, tree <> Nil{}, packing)) ->
  Rule.source_claim(~A, ~E, tree, Allocation.dispatch_fit_width_16(~A, ~E, packing, tree, samples)):
  match packing:
    case Space.Insufficient{required, available}: {==}
    case Space.Packed{placements, unused}: root_preserved(~A, ~E, placements, tree, samples, population)

def slots_preserved(~A: Data, ~E: Data, +slots: Allocation.SlotsOutcome<Model.Tree<A, E>>, +tree: Model.Tree<A, E>, +width: Nat, +samples: +List<Model.HeightSample>,
  population: PopulationProof.SlotsPopulation(~Model.Tree<A, E>, tree <> Nil{}, slots)) ->
  Rule.source_claim(~A, ~E, tree, Allocation.dispatch_fit_width_15(~A, ~E, slots, tree, width, samples)):
  match slots:
    case Allocation.SlotsFailure{failure}: {==}
    case Allocation.SlotsReady{+values}:
      packed_preserved(~A, ~E, Allocation.shared_pack(~Model.Tree<A, E>, values, 0n, Nat.sub(width, Allocation.outside_axis(Allocation.InlineAxis{}, Allocation.tree_rule(~A, ~E, tree)))), tree, samples,
        Std.transport(+List<Model.Tree<A, E>>, SpaceLaws.slot_values(~Model.Tree<A, E>, values),
          (children => PopulationProof.PackingPopulation(~Model.Tree<A, E>, children, Allocation.shared_pack(~Model.Tree<A, E>, values, 0n, Nat.sub(width, Allocation.outside_axis(Allocation.InlineAxis{}, Allocation.tree_rule(~A, ~E, tree)))))),
          PopulationProof.shared_population(~Model.Tree<A, E>, values, 0n, Nat.sub(width, Allocation.outside_axis(Allocation.InlineAxis{}, Allocation.tree_rule(~A, ~E, tree)))), tree <> Nil{}, Equal.sym(+List<Model.Tree<A, E>>, SpaceLaws.slot_values(~Model.Tree<A, E>, values), tree <> Nil{}, population)))

def preserved(~A: Data, ~E: Data, +tree: Model.Tree<A, E>, +width: Nat, +samples: +List<Model.HeightSample>) ->
  Rule.source_claim(~A, ~E, tree, Allocation.fit_width(~A, ~E, tree, width, samples)):
  slots_preserved(~A, ~E, Allocation.width_slots(~A, ~E, tree <> Nil{}, width), tree, width, samples,
    PopulationProof.width_population(~A, ~E, tree <> Nil{}, width))

def Rule.evidence(A, E):
  Rule.Requirements{+tree => +width => +samples => preserved(~A, ~E, tree, width, samples)}
