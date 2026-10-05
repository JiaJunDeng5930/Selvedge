import Base
import ../../bendlib/proofs/algebra.bend as Alg
import ../physical-space.bend as Model
import ../physical-allocation.bend as Allocation
import ../physical-width-rules.bend as Rule
import ../space.bend as Space
import ../space-laws.bend as SpaceLaws
import ./space.bend as Order
import ../physical-allocation-population-rules.bend as PopulationRules
import ./physical-allocation-population.bend as PopulationProof
import ./iteration-budget.bend as Budget

# Work ranks count pending transitions, including each suspended parent edge.
def placement_work(~A: Data, ~E: Data, +placements: +List<Space.Placement<Model.Tree<A, E>>>) -> Nat:
  Allocation.width_forest_work(~A, ~E, SpaceLaws.placement_values(~Model.Tree<A, E>, placements))

def return_rank(~A: Data, ~E: Data, return_to: Allocation.WidthReturn<A, E>) -> Nat:
  match return_to:
    case Allocation.WidthRootReturn{}: 0n
    case Allocation.WidthContainerReturn{key, value, interaction, rule, width, offset, direction, remaining, previous, parent}:
      Nat.add(2n, Nat.add(placement_work(~A, ~E, remaining), return_rank(~A, ~E, parent)))

def visit_work(~A: Data, ~E: Data, tree: Model.Tree<A, E>) -> Nat:
  match tree:
    case Model.Leaf{key, value, interaction, rule, demand, height}: 4n
    case Model.Container{key, value, interaction, rule, +children}: Nat.add(5n, Allocation.width_forest_work(~A, ~E, children))

def checked_work(~A: Data, ~E: Data, tree: Model.Tree<A, E>) -> Nat:
  match tree:
    case Model.Leaf{key, value, interaction, rule, demand, height}: 3n
    case Model.Container{key, value, interaction, rule, +children}: Nat.add(4n, Allocation.width_forest_work(~A, ~E, children))

def plan_work(~A: Data, ~E: Data, plan: Allocation.InlinePlan<A, E>) -> Nat:
  match plan:
    case Allocation.InlineFailure{failure}: 2n
    case Allocation.InlinePlanned{placements, direction, canvas}: Nat.add(3n, placement_work(~A, ~E, placements))

def rank(~A: Data, ~E: Data, state: Allocation.WidthState<A, E>) -> Nat:
  match state:
    case Allocation.WidthVisit{tree, width, offset, return_to}:
      Nat.add(visit_work(~A, ~E, tree), return_rank(~A, ~E, return_to))
    case Allocation.WidthMinimumChecked{fits, tree, width, offset, rule, lower, return_to}:
      Nat.add(checked_work(~A, ~E, tree), return_rank(~A, ~E, return_to))
    case Allocation.WidthLeafHeight{sample, key, value, interaction, rule, demand, height, inner_width, outer_width, offset, return_to}:
      Nat.add(2n, return_rank(~A, ~E, return_to))
    case Allocation.WidthContainerPlan{plan, key, value, interaction, rule, width, offset, return_to}:
      Nat.add(plan_work(~A, ~E, plan), return_rank(~A, ~E, return_to))
    case Allocation.WidthChildren{remaining, key, value, interaction, rule, width, offset, direction, previous, return_to}:
      Nat.add(2n, Nat.add(placement_work(~A, ~E, remaining), return_rank(~A, ~E, return_to)))
    case Allocation.WidthComplete{result, return_to}: Nat.add(1n, return_rank(~A, ~E, return_to))
    case Allocation.WidthDone{result}: 0n

def visit_zero(~A: Data, ~E: Data, tree: Model.Tree<A, E>, +continuation: Nat) ->
  {Nat.is_eq(Nat.add(visit_work(~A, ~E, tree), continuation), 0n) == False{} : Bool}:
  match tree:
    case Model.Leaf{key, value, interaction, rule, demand, height}: {==}
    case Model.Container{key, value, interaction, rule, +children}: {==}

def checked_zero(~A: Data, ~E: Data, tree: Model.Tree<A, E>, +continuation: Nat) ->
  {Nat.is_eq(Nat.add(checked_work(~A, ~E, tree), continuation), 0n) == False{} : Bool}:
  match tree:
    case Model.Leaf{key, value, interaction, rule, demand, height}: {==}
    case Model.Container{key, value, interaction, rule, +children}: {==}

def plan_zero(~A: Data, ~E: Data, plan: Allocation.InlinePlan<A, E>, +continuation: Nat) ->
  {Nat.is_eq(Nat.add(plan_work(~A, ~E, plan), continuation), 0n) == False{} : Bool}:
  match plan:
    case Allocation.InlineFailure{failure}: {==}
    case Allocation.InlinePlanned{placements, direction, canvas}: {==}

def rank_zero_completed(~A: Data, ~E: Data, state: Allocation.WidthState<A, E>) ->
  {Nat.is_eq(rank(~A, ~E, state), 0n) == Rule.completed(~A, ~E, state) : Bool}:
  match state:
    case Allocation.WidthVisit{tree, width, offset, return_to}: visit_zero(~A, ~E, tree, return_rank(~A, ~E, return_to))
    case Allocation.WidthMinimumChecked{fits, tree, width, offset, rule, lower, return_to}: checked_zero(~A, ~E, tree, return_rank(~A, ~E, return_to))
    case Allocation.WidthLeafHeight{sample, key, value, interaction, rule, demand, height, inner_width, outer_width, offset, return_to}: {==}
    case Allocation.WidthContainerPlan{plan, key, value, interaction, rule, width, offset, return_to}: plan_zero(~A, ~E, plan, return_rank(~A, ~E, return_to))
    case Allocation.WidthChildren{remaining, key, value, interaction, rule, width, offset, direction, previous, return_to}: {==}
    case Allocation.WidthComplete{result, return_to}: {==}
    case Allocation.WidthDone{result}: {==}

def visit_decrease(~A: Data, ~E: Data, tree: Model.Tree<A, E>, +continuation: Nat) ->
  {Nat.is_le(Nat.add(checked_work(~A, ~E, tree), continuation), Nat.sub(Nat.add(visit_work(~A, ~E, tree), continuation), 1n)) == True{} : Bool}:
  match tree:
    case Model.Leaf{key, value, interaction, rule, demand, height}: Order.le_refl(Nat.add(3n, continuation))
    case Model.Container{key, value, interaction, rule, +children}: Order.le_refl(Nat.add(Nat.add(4n, Allocation.width_forest_work(~A, ~E, children)), continuation))

# A rejected minimum skips all child work; its continuation still completes.
def below_prefix(+value: Nat, +extra: Nat) -> {Nat.is_le(value, Nat.add(extra, value)) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(value, Nat.add(extra, value)), Nat.is_le(value, Nat.add(value, extra)), True{},
    Equal.cong(Nat, Bool, (n => Nat.is_le(value, n)), Nat.add(extra, value), Nat.add(value, extra), Order.add_comm(extra, value)), Order.le_add(value, extra))

def rejected_decrease(~A: Data, ~E: Data, tree: Model.Tree<A, E>, +continuation: Nat) ->
  {Nat.is_le(Nat.add(1n, continuation), Nat.sub(Nat.add(checked_work(~A, ~E, tree), continuation), 1n)) == True{} : Bool}:
  match tree:
    case Model.Leaf{key, value, interaction, rule, demand, height}: below_prefix(continuation, 1n)
    case Model.Container{key, value, interaction, rule, +children}: below_prefix(continuation, Nat.add(2n, Allocation.width_forest_work(~A, ~E, children)))

def child_rank_join(+work: Nat, +rest: Nat, +continuation: Nat) ->
  {Nat.add(work, Nat.add(2n, Nat.add(rest, continuation))) == Nat.add(2n, Nat.add(Nat.add(work, rest), continuation)) : Nat}:
  Equal.trans(Nat,
    Nat.add(work, Nat.add(2n, Nat.add(rest, continuation))),
    Nat.add(2n, Nat.add(work, Nat.add(rest, continuation))),
    Nat.add(2n, Nat.add(Nat.add(work, rest), continuation)),
    Equal.trans(Nat,
      Nat.add(work, Nat.add(2n, Nat.add(rest, continuation))),
      1n+Nat.add(work, 1n+Nat.add(rest, continuation)),
      Nat.add(2n, Nat.add(work, Nat.add(rest, continuation))),
      Alg.nat_add_succ(work, 1n+Nat.add(rest, continuation)),
      Equal.cong(Nat, Nat, (n => 1n+n), Nat.add(work, 1n+Nat.add(rest, continuation)), 1n+Nat.add(work, Nat.add(rest, continuation)), Alg.nat_add_succ(work, Nat.add(rest, continuation)))),
    Equal.cong(Nat, Nat, (n => Nat.add(2n, n)), Nat.add(work, Nat.add(rest, continuation)), Nat.add(Nat.add(work, rest), continuation),
      Equal.sym(Nat, Nat.add(Nat.add(work, rest), continuation), Nat.add(work, Nat.add(rest, continuation)), Alg.nat_add_assoc(work, rest, continuation))))

def child_decrease(~A: Data, ~E: Data, tree: Model.Tree<A, E>, +rest: +List<Space.Placement<Model.Tree<A, E>>>, +continuation: Nat) ->
  {Nat.is_le(Nat.add(visit_work(~A, ~E, tree), Nat.add(2n, Nat.add(placement_work(~A, ~E, rest), continuation))),
    Nat.sub(Nat.add(2n, Nat.add(Allocation.width_forest_work(~A, ~E, tree <> SpaceLaws.placement_values(~Model.Tree<A, E>, rest)), continuation)), 1n)) == True{} : Bool}:
  match tree:
    case Model.Leaf{key, value, interaction, rule, demand, height}:
      Order.le_refl(Nat.add(6n, Nat.add(placement_work(~A, ~E, rest), continuation)))
    case Model.Container{key, value, interaction, rule, +children}:
      Equal.trans(Bool,
        Nat.is_le(Nat.add(Nat.add(5n, Allocation.width_forest_work(~A, ~E, children)), Nat.add(2n, Nat.add(placement_work(~A, ~E, rest), continuation))),
          Nat.add(7n, Nat.add(Nat.add(Allocation.width_forest_work(~A, ~E, children), placement_work(~A, ~E, rest)), continuation))),
        Nat.is_le(Nat.add(7n, Nat.add(Nat.add(Allocation.width_forest_work(~A, ~E, children), placement_work(~A, ~E, rest)), continuation)),
          Nat.add(7n, Nat.add(Nat.add(Allocation.width_forest_work(~A, ~E, children), placement_work(~A, ~E, rest)), continuation))), True{},
        Equal.cong(Nat, Bool, (n => Nat.is_le(n, Nat.add(7n, Nat.add(Nat.add(Allocation.width_forest_work(~A, ~E, children), placement_work(~A, ~E, rest)), continuation)))),
          Nat.add(Nat.add(5n, Allocation.width_forest_work(~A, ~E, children)), Nat.add(2n, Nat.add(placement_work(~A, ~E, rest), continuation))),
          Nat.add(7n, Nat.add(Nat.add(Allocation.width_forest_work(~A, ~E, children), placement_work(~A, ~E, rest)), continuation)),
          child_rank_join(Nat.add(5n, Allocation.width_forest_work(~A, ~E, children)), placement_work(~A, ~E, rest), continuation)),
        Order.le_refl(Nat.add(7n, Nat.add(Nat.add(Allocation.width_forest_work(~A, ~E, children), placement_work(~A, ~E, rest)), continuation))))

# The ordered population premise is needed only at successful container planning.
def population_decrease(~A: Data, ~E: Data, +placements: +List<Space.Placement<Model.Tree<A, E>>>, +children: +List<Model.Tree<A, E>>, +continuation: Nat,
  population: {SpaceLaws.placement_values(~Model.Tree<A, E>, placements) == children : +List<Model.Tree<A, E>>}) ->
  {Nat.is_le(Nat.add(Nat.add(3n, placement_work(~A, ~E, placements)), continuation),
    Nat.sub(Nat.add(Nat.add(4n, Allocation.width_forest_work(~A, ~E, children)), continuation), 1n)) == True{} : Bool}:
  Equal.trans(Bool,
    Nat.is_le(Nat.add(Nat.add(3n, placement_work(~A, ~E, placements)), continuation), Nat.add(Nat.add(3n, Allocation.width_forest_work(~A, ~E, children)), continuation)),
    Nat.is_le(Nat.add(Nat.add(3n, Allocation.width_forest_work(~A, ~E, children)), continuation), Nat.add(Nat.add(3n, Allocation.width_forest_work(~A, ~E, children)), continuation)), True{},
    Equal.cong(+List<Model.Tree<A, E>>, Bool,
      (trees => Nat.is_le(Nat.add(Nat.add(3n, Allocation.width_forest_work(~A, ~E, trees)), continuation), Nat.add(Nat.add(3n, Allocation.width_forest_work(~A, ~E, children)), continuation))),
      SpaceLaws.placement_values(~Model.Tree<A, E>, placements), children, population),
    Order.le_refl(Nat.add(Nat.add(3n, Allocation.width_forest_work(~A, ~E, children)), continuation)))

def independent_claim(~A: Data, ~E: Data, state: Allocation.WidthState<A, E>, +samples: +List<Model.HeightSample>) -> Type:
  match state:
    case Allocation.WidthMinimumChecked{True{}, Model.Container{key, value, interaction, rule, children}, width, offset, checked_rule, lower, return_to}: Unit
    case _:
      {Nat.is_le(rank(~A, ~E, Allocation.width_step(~A, ~E, state, samples)), Nat.sub(rank(~A, ~E, state), 1n)) == True{} : Bool}

def visit_checked_decrease(~A: Data, ~E: Data, +valid: Bool, +tree: Model.Tree<A, E>, +width: Nat, +offset: Nat, +rule: Model.Rule, +lower: Nat, +return_to: Allocation.WidthReturn<A, E>) ->
  {Nat.is_le(rank(~A, ~E, Allocation.width_visit_checked(~A, ~E, valid, tree, width, offset, rule, lower, return_to)), Nat.sub(rank(~A, ~E, Allocation.WidthVisit{tree, width, offset, return_to}), 1n)) == True{} : Bool}:
  match valid:
    case True{}: visit_decrease(~A, ~E, tree, return_rank(~A, ~E, return_to))
    case False{}:
      match tree:
        case Model.Leaf{key, value, interaction, rule, demand, height}: below_prefix(return_rank(~A, ~E, return_to), 2n)
        case Model.Container{key, value, interaction, rule, +children}: below_prefix(return_rank(~A, ~E, return_to), Nat.add(3n, Allocation.width_forest_work(~A, ~E, children)))

def independent_decrease(~A: Data, ~E: Data, +state: Allocation.WidthState<A, E>, +samples: +List<Model.HeightSample>) -> independent_claim(~A, ~E, state, samples):
  match state:
    case Allocation.WidthVisit{+tree, +width, +offset, +return_to}: visit_checked_decrease(~A, ~E, Allocation.width_visit_valid(~A, ~E, Allocation.tree_rule(~A, ~E, tree), return_to), tree, width, offset, Allocation.tree_rule(~A, ~E, tree), Allocation.axis_extent(Allocation.InlineAxis{}, Model.minimum_demand(Model.demand(~A, ~E, tree))), return_to)
    case Allocation.WidthMinimumChecked{False{}, tree, width, offset, rule, lower, return_to}: rejected_decrease(~A, ~E, tree, return_rank(~A, ~E, return_to))
    case Allocation.WidthMinimumChecked{True{}, Model.Leaf{key, value, interaction, rule, demand, height}, width, offset, checked_rule, lower, return_to}: Order.le_refl(Nat.add(2n, return_rank(~A, ~E, return_to)))
    case Allocation.WidthMinimumChecked{True{}, Model.Container{key, value, interaction, rule, children}, width, offset, checked_rule, lower, return_to}: Unit{}
    case Allocation.WidthLeafHeight{None{}, key, value, interaction, rule, demand, height, inner_width, outer_width, offset, return_to}: Order.le_refl(Nat.add(1n, return_rank(~A, ~E, return_to)))
    case Allocation.WidthLeafHeight{Some{content_height}, key, value, interaction, rule, demand, height, inner_width, outer_width, offset, return_to}: Order.le_refl(Nat.add(1n, return_rank(~A, ~E, return_to)))
    case Allocation.WidthContainerPlan{Allocation.InlineFailure{failure}, key, value, interaction, rule, width, offset, return_to}: Order.le_refl(Nat.add(1n, return_rank(~A, ~E, return_to)))
    case Allocation.WidthContainerPlan{Allocation.InlinePlanned{placements, direction, canvas}, key, value, interaction, rule, width, offset, return_to}: Order.le_refl(Nat.add(2n, Nat.add(placement_work(~A, ~E, placements), return_rank(~A, ~E, return_to))))
    case Allocation.WidthChildren{Nil{}, key, value, interaction, rule, width, offset, direction, previous, return_to}: Order.le_refl(Nat.add(1n, return_rank(~A, ~E, return_to)))
    case Allocation.WidthChildren{Con{Space.Placement{child, child_offset, extent}, rest}, key, value, interaction, rule, width, offset, direction, previous, return_to}: child_decrease(~A, ~E, child, rest, return_rank(~A, ~E, return_to))
    case Allocation.WidthComplete{result, Allocation.WidthRootReturn{}}: {==}
    case Allocation.WidthComplete{result, Allocation.WidthContainerReturn{key, value, interaction, rule, width, offset, direction, remaining, previous, parent}}: Order.le_refl(Nat.add(2n, Nat.add(placement_work(~A, ~E, remaining), return_rank(~A, ~E, parent))))
    case Allocation.WidthDone{result}: {==}

# Match the actual computed plan before consuming its population evidence.
def planned_decrease(~A: Data, ~E: Data, +plan: Allocation.InlinePlan<A, E>, +children: +List<Model.Tree<A, E>>, +continuation: Nat,
  population: PopulationRules.InlinePopulation(~A, ~E, children, plan)) ->
  {Nat.is_le(Nat.add(plan_work(~A, ~E, plan), continuation),
    Nat.sub(Nat.add(Nat.add(4n, Allocation.width_forest_work(~A, ~E, children)), continuation), 1n)) == True{} : Bool}:
  match plan:
    case Allocation.InlineFailure{failure}: below_prefix(continuation, Nat.add(1n, Allocation.width_forest_work(~A, ~E, children)))
    case Allocation.InlinePlanned{placements, direction, canvas}: population_decrease(~A, ~E, placements, children, continuation, population)

def step_decrease(~A: Data, ~E: Data, +state: Allocation.WidthState<A, E>, +samples: +List<Model.HeightSample>) ->
  {Nat.is_le(rank(~A, ~E, Allocation.width_step(~A, ~E, state, samples)), Nat.sub(rank(~A, ~E, state), 1n)) == True{} : Bool}:
  match state:
    case Allocation.WidthVisit{tree, width, offset, return_to}: independent_decrease(~A, ~E, Allocation.WidthVisit{tree, width, offset, return_to}, samples)
    case Allocation.WidthMinimumChecked{False{}, tree, width, offset, rule, lower, return_to}: independent_decrease(~A, ~E, Allocation.WidthMinimumChecked{False{}, tree, width, offset, rule, lower, return_to}, samples)
    case Allocation.WidthMinimumChecked{True{}, Model.Leaf{key, value, interaction, rule, demand, height}, width, offset, checked_rule, lower, return_to}: independent_decrease(~A, ~E, Allocation.WidthMinimumChecked{True{}, Model.Leaf{key, value, interaction, rule, demand, height}, width, offset, checked_rule, lower, return_to}, samples)
    case Allocation.WidthMinimumChecked{True{}, Model.Container{+key, value, interaction, +rule, +children}, +width, offset, checked_rule, lower, return_to}:
      planned_decrease(~A, ~E,
        Allocation.prepare_inline_children(~A, ~E, key, rule, children, Nat.sub(width, Nat.mul(2n, Allocation.inline_inset(rule)))),
        children, return_rank(~A, ~E, return_to),
        PopulationProof.inline_population(~A, ~E, key, rule, children, Nat.sub(width, Nat.mul(2n, Allocation.inline_inset(rule)))))
    case Allocation.WidthLeafHeight{None{}, key, value, interaction, rule, demand, height, inner_width, outer_width, offset, return_to}: independent_decrease(~A, ~E, Allocation.WidthLeafHeight{None{}, key, value, interaction, rule, demand, height, inner_width, outer_width, offset, return_to}, samples)
    case Allocation.WidthLeafHeight{Some{content_height}, key, value, interaction, rule, demand, height, inner_width, outer_width, offset, return_to}: independent_decrease(~A, ~E, Allocation.WidthLeafHeight{Some{content_height}, key, value, interaction, rule, demand, height, inner_width, outer_width, offset, return_to}, samples)
    case Allocation.WidthContainerPlan{Allocation.InlineFailure{failure}, key, value, interaction, rule, width, offset, return_to}: independent_decrease(~A, ~E, Allocation.WidthContainerPlan{Allocation.InlineFailure{failure}, key, value, interaction, rule, width, offset, return_to}, samples)
    case Allocation.WidthContainerPlan{Allocation.InlinePlanned{placements, direction, canvas}, key, value, interaction, rule, width, offset, return_to}: independent_decrease(~A, ~E, Allocation.WidthContainerPlan{Allocation.InlinePlanned{placements, direction, canvas}, key, value, interaction, rule, width, offset, return_to}, samples)
    case Allocation.WidthChildren{Nil{}, key, value, interaction, rule, width, offset, direction, previous, return_to}: independent_decrease(~A, ~E, Allocation.WidthChildren{Nil{}, key, value, interaction, rule, width, offset, direction, previous, return_to}, samples)
    case Allocation.WidthChildren{Con{Space.Placement{child, child_offset, extent}, rest}, key, value, interaction, rule, width, offset, direction, previous, return_to}: independent_decrease(~A, ~E, Allocation.WidthChildren{Con{Space.Placement{child, child_offset, extent}, rest}, key, value, interaction, rule, width, offset, direction, previous, return_to}, samples)
    case Allocation.WidthComplete{result, Allocation.WidthRootReturn{}}: independent_decrease(~A, ~E, Allocation.WidthComplete{result, Allocation.WidthRootReturn{}}, samples)
    case Allocation.WidthComplete{result, Allocation.WidthContainerReturn{key, value, interaction, rule, width, offset, direction, remaining, previous, parent}}: independent_decrease(~A, ~E, Allocation.WidthComplete{result, Allocation.WidthContainerReturn{key, value, interaction, rule, width, offset, direction, remaining, previous, parent}}, samples)
    case Allocation.WidthDone{result}: independent_decrease(~A, ~E, Allocation.WidthDone{result}, samples)

def seed_in_budget(~A: Data, ~E: Data, tree: Model.Tree<A, E>) ->
  {Nat.is_le(visit_work(~A, ~E, tree), Allocation.width_forest_work(~A, ~E, tree <> Nil{})) == True{} : Bool}:
  match tree:
    case Model.Leaf{key, value, interaction, rule, demand, height}: {==}
    case Model.Container{key, value, interaction, rule, +children}:
      Equal.trans(Bool,
        Nat.is_le(Nat.add(5n, Allocation.width_forest_work(~A, ~E, children)), Nat.add(6n, Nat.add(Allocation.width_forest_work(~A, ~E, children), 0n))),
        Nat.is_le(Nat.add(5n, Allocation.width_forest_work(~A, ~E, children)), Nat.add(6n, Allocation.width_forest_work(~A, ~E, children))), True{},
        Equal.cong(Nat, Bool, (n => Nat.is_le(Nat.add(5n, Allocation.width_forest_work(~A, ~E, children)), Nat.add(6n, n))),
          Nat.add(Allocation.width_forest_work(~A, ~E, children), 0n), Allocation.width_forest_work(~A, ~E, children), Alg.nat_add_zero(Allocation.width_forest_work(~A, ~E, children))),
        below_prefix(Nat.add(5n, Allocation.width_forest_work(~A, ~E, children)), 1n))

def initial_in_budget(~A: Data, ~E: Data, +tree: Model.Tree<A, E>, +width: Nat, +offset: Nat) ->
  {Nat.is_le(rank(~A, ~E, Allocation.WidthVisit{tree, width, offset, Allocation.WidthRootReturn{}}), Allocation.width_forest_work(~A, ~E, tree <> Nil{})) == True{} : Bool}:
  Equal.trans(Bool,
    Nat.is_le(Nat.add(visit_work(~A, ~E, tree), 0n), Allocation.width_forest_work(~A, ~E, tree <> Nil{})),
    Nat.is_le(visit_work(~A, ~E, tree), Allocation.width_forest_work(~A, ~E, tree <> Nil{})), True{},
    Equal.cong(Nat, Bool, (n => Nat.is_le(n, Allocation.width_forest_work(~A, ~E, tree <> Nil{}))),
      Nat.add(visit_work(~A, ~E, tree), 0n), visit_work(~A, ~E, tree), Alg.nat_add_zero(visit_work(~A, ~E, tree))), seed_in_budget(~A, ~E, tree))

def execution_rank(~A: Data, ~E: Data, execution: Allocation.WidthExecution<A, E>) -> Nat:
  rank(~A, ~E, Allocation.width_execution_state(~A, ~E, execution))

def execution_decrease(~A: Data, ~E: Data, execution: Allocation.WidthExecution<A, E>) ->
  {Nat.is_le(execution_rank(~A, ~E, Allocation.width_execution_step(~A, ~E, execution)), Nat.sub(execution_rank(~A, ~E, execution), 1n)) == True{} : Bool}:
  Allocation.WidthExecution{state, samples} = execution
  step_decrease(~A, ~E, state, samples)

def iteration_rank_zero(~A: Data, ~E: Data, +tree: Model.Tree<A, E>, +width: Nat, +offset: Nat, +samples: +List<Model.HeightSample>) ->
  {rank(~A, ~E, Allocation.iterate_width(~A, ~E, tree, width, offset, samples)) == 0n : Nat}:
  Budget.iterate_rank_zero(~Allocation.WidthExecution<A, E>, ~(execution => Allocation.width_execution_step(~A, ~E, execution)), ~(execution => execution_rank(~A, ~E, execution)),
    ~(+execution => execution_decrease(~A, ~E, execution)),
    Allocation.WidthExecution{Allocation.WidthVisit{tree, width, offset, Allocation.WidthRootReturn{}}, samples}, Allocation.width_forest_work(~A, ~E, tree <> Nil{}),
    initial_in_budget(~A, ~E, tree, width, offset))

def complete(~A: Data, ~E: Data, +tree: Model.Tree<A, E>, +width: Nat, +offset: Nat, +samples: +List<Model.HeightSample>) -> Rule.complete_claim(~A, ~E, tree, width, offset, samples):
  Equal.trans(Bool,
    Rule.completed(~A, ~E, Allocation.iterate_width(~A, ~E, tree, width, offset, samples)),
    Nat.is_eq(rank(~A, ~E, Allocation.iterate_width(~A, ~E, tree, width, offset, samples)), 0n), True{},
    Equal.sym(Bool, Nat.is_eq(rank(~A, ~E, Allocation.iterate_width(~A, ~E, tree, width, offset, samples)), 0n),
      Rule.completed(~A, ~E, Allocation.iterate_width(~A, ~E, tree, width, offset, samples)),
      rank_zero_completed(~A, ~E, Allocation.iterate_width(~A, ~E, tree, width, offset, samples))),
    Equal.cong(Nat, Bool, (n => Nat.is_eq(n, 0n)), rank(~A, ~E, Allocation.iterate_width(~A, ~E, tree, width, offset, samples)), 0n,
      iteration_rank_zero(~A, ~E, tree, width, offset, samples)))

def Rule.evidence(A, E):
  Rule.Requirements{+tree => +width => +offset => +samples => complete(~A, ~E, tree, width, offset, samples)}
