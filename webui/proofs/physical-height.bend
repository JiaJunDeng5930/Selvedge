import Base
import ../../bendlib/stdlib.bend as Std
import ../physical-allocation.bend as Allocation
import ../space.bend as Space
import ../space-laws.bend as SpaceLaws
import ../spatial.bend as Spatial
import ../physical-height-rules.bend as Rule
import ./space.bend as SpaceProof
import ../physical-allocation-population-rules.bend as PopulationRules
import ./physical-allocation-population.bend as PopulationProof
import ./iteration-budget.bend as Budget

def placement_work(~A: Data, ~E: Data, +placements: +List<Space.Placement<Allocation.MeasuredTree<A, E>>>) -> Nat:
  Allocation.height_forest_work(~A, ~E, SpaceLaws.placement_values(~Allocation.MeasuredTree<A, E>, placements))

def return_rank(~A: Data, ~E: Data, target: Allocation.HeightReturn<A, E>) -> Nat:
  match target:
    case Allocation.HeightRootReturn{}: 0n
    case Allocation.HeightContainerReturn{key, value, interaction, rule, bounds, canvas, direction, left, top, remaining, previous, parent}:
      Nat.add(2n, Nat.add(placement_work(~A, ~E, remaining), return_rank(~A, ~E, parent)))

# These are W(tree)-1 and W(tree)-2 with the singleton forest's trailing zero removed.
def visit_rank(~A: Data, ~E: Data, tree: Allocation.MeasuredTree<A, E>, +parent: Nat) -> Nat:
  match tree:
    case Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, width, offset, content_height}:
      Nat.add(3n, parent)
    case Allocation.MeasuredContainer{key, value, interaction, rule, width, offset, direction, +children}:
      Nat.add(5n, Nat.add(Allocation.height_forest_work(~A, ~E, children), parent))

def checked_rank(~A: Data, ~E: Data, tree: Allocation.MeasuredTree<A, E>, +parent: Nat) -> Nat:
  match tree:
    case Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, width, offset, content_height}:
      Nat.add(2n, parent)
    case Allocation.MeasuredContainer{key, value, interaction, rule, width, offset, direction, +children}:
      Nat.add(4n, Nat.add(Allocation.height_forest_work(~A, ~E, children), parent))

def plan_rank(~A: Data, ~E: Data, plan: Allocation.ChildPlan<Allocation.MeasuredTree<A, E>>, +parent: Nat) -> Nat:
  match plan:
    case Allocation.PlanningFailure{failure}: Nat.add(2n, parent)
    case Allocation.ChildrenPlanned{placements, canvas_height}: Nat.add(3n, Nat.add(placement_work(~A, ~E, placements), parent))

def rank(~A: Data, ~E: Data, state: Allocation.HeightState<A, E>) -> Nat:
  match state:
    case Allocation.HeightVisit{tree, bounds, parent}: visit_rank(~A, ~E, tree, return_rank(~A, ~E, parent))
    case Allocation.HeightMinimumChecked{fits, tree, bounds, lower, parent}: checked_rank(~A, ~E, tree, return_rank(~A, ~E, parent))
    case Allocation.HeightContainerPlan{plan, key, value, interaction, rule, bounds, children, direction, width, left, top, parent}:
      plan_rank(~A, ~E, plan, return_rank(~A, ~E, parent))
    case Allocation.HeightChildren{remaining, key, value, interaction, rule, bounds, canvas, direction, left, top, previous, parent}:
      Nat.add(2n, Nat.add(placement_work(~A, ~E, remaining), return_rank(~A, ~E, parent)))
    case Allocation.HeightComplete{result, parent}: Nat.add(1n, return_rank(~A, ~E, parent))
    case Allocation.HeightDone{result}: 0n

def visit_nonzero(~A: Data, ~E: Data, tree: Allocation.MeasuredTree<A, E>, +parent: Nat) ->
  {Nat.is_eq(visit_rank(~A, ~E, tree, parent), 0n) == False{} : Bool}:
  match tree:
    case Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, width, offset, content_height}: {==}
    case Allocation.MeasuredContainer{key, value, interaction, rule, width, offset, direction, +children}: {==}

def checked_nonzero(~A: Data, ~E: Data, tree: Allocation.MeasuredTree<A, E>, +parent: Nat) ->
  {Nat.is_eq(checked_rank(~A, ~E, tree, parent), 0n) == False{} : Bool}:
  match tree:
    case Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, width, offset, content_height}: {==}
    case Allocation.MeasuredContainer{key, value, interaction, rule, width, offset, direction, +children}: {==}

def plan_nonzero(~A: Data, ~E: Data, plan: Allocation.ChildPlan<Allocation.MeasuredTree<A, E>>, +parent: Nat) ->
  {Nat.is_eq(plan_rank(~A, ~E, plan, parent), 0n) == False{} : Bool}:
  match plan:
    case Allocation.PlanningFailure{failure}: {==}
    case Allocation.ChildrenPlanned{placements, canvas_height}: {==}

def rank_zero(~A: Data, ~E: Data, state: Allocation.HeightState<A, E>) ->
  {Nat.is_eq(rank(~A, ~E, state), 0n) == Rule.completed(~A, ~E, state) : Bool}:
  match state:
    case Allocation.HeightVisit{tree, bounds, parent}: visit_nonzero(~A, ~E, tree, return_rank(~A, ~E, parent))
    case Allocation.HeightMinimumChecked{fits, tree, bounds, lower, parent}: checked_nonzero(~A, ~E, tree, return_rank(~A, ~E, parent))
    case Allocation.HeightContainerPlan{plan, key, value, interaction, rule, bounds, children, direction, width, left, top, parent}:
      plan_nonzero(~A, ~E, plan, return_rank(~A, ~E, parent))
    case Allocation.HeightChildren{remaining, key, value, interaction, rule, bounds, canvas, direction, left, top, previous, parent}: {==}
    case Allocation.HeightComplete{result, parent}: {==}
    case Allocation.HeightDone{result}: {==}

def decrease_claim(~A: Data, ~E: Data, state: Allocation.HeightState<A, E>) -> Type:
  {Nat.is_le(rank(~A, ~E, Allocation.height_step(~A, ~E, state)), Nat.sub(rank(~A, ~E, state), 1n)) == True{} : Bool}

def visit_decrease(~A: Data, ~E: Data, tree: Allocation.MeasuredTree<A, E>, +parent: Nat) ->
  {Nat.is_le(checked_rank(~A, ~E, tree, parent), Nat.sub(visit_rank(~A, ~E, tree, parent), 1n)) == True{} : Bool}:
  match tree:
    case Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, width, offset, content_height}: SpaceProof.le_refl(Nat.add(2n, parent))
    case Allocation.MeasuredContainer{key, value, interaction, rule, width, offset, direction, +children}:
      SpaceProof.le_refl(Nat.add(4n, Nat.add(Allocation.height_forest_work(~A, ~E, children), parent)))

def minimum_failure_decrease(~A: Data, ~E: Data, tree: Allocation.MeasuredTree<A, E>, +parent: Nat) ->
  {Nat.is_le(Nat.add(1n, parent), Nat.sub(checked_rank(~A, ~E, tree, parent), 1n)) == True{} : Bool}:
  match tree:
    case Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, width, offset, content_height}: SpaceProof.le_refl(Nat.add(1n, parent))
    case Allocation.MeasuredContainer{key, value, interaction, rule, width, offset, direction, +children}:
      Std.transport(Nat, Nat.add(parent, Nat.add(2n, Allocation.height_forest_work(~A, ~E, children))),
        (bound => {Nat.is_le(parent, bound) == True{} : Bool}),
        SpaceProof.le_add(parent, Nat.add(2n, Allocation.height_forest_work(~A, ~E, children))),
        Nat.add(Nat.add(2n, Allocation.height_forest_work(~A, ~E, children)), parent),
        SpaceProof.add_comm(Nat.add(2n, Allocation.height_forest_work(~A, ~E, children)), parent))

# A child visit replaces its reserved parent edge with its explicit return frame.
def child_resume_rank(+own: Nat, +rest: Nat, +parent: Nat) ->
  {Nat.add(own, Nat.add(2n, Nat.add(rest, parent))) == Nat.add(2n, Nat.add(Nat.add(own, rest), parent)) : Nat}:
  match own:
    case 0n: {==}
    case 1n+tail:
      Equal.cong(Nat, Nat, (value => 1n+value), Nat.add(tail, Nat.add(2n, Nat.add(rest, parent))),
        Nat.add(2n, Nat.add(Nat.add(tail, rest), parent)), child_resume_rank(tail, rest, parent))

def children_visit_decrease(~A: Data, ~E: Data, tree: Allocation.MeasuredTree<A, E>, +remaining: +List<Space.Placement<Allocation.MeasuredTree<A, E>>>, +parent: Nat) ->
  {Nat.is_le(visit_rank(~A, ~E, tree, Nat.add(2n, Nat.add(placement_work(~A, ~E, remaining), parent))),
    Nat.sub(Nat.add(2n, Nat.add(Allocation.height_forest_work(~A, ~E, tree <> SpaceLaws.placement_values(~Allocation.MeasuredTree<A, E>, remaining)), parent)), 1n)) == True{} : Bool}:
  match tree:
    case Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, width, offset, content_height}:
      SpaceProof.le_refl(Nat.add(5n, Nat.add(placement_work(~A, ~E, remaining), parent)))
    case Allocation.MeasuredContainer{key, value, interaction, rule, width, offset, direction, +children}:
      Std.transport(Nat,
        Nat.add(2n, Nat.add(Nat.add(Nat.add(5n, Allocation.height_forest_work(~A, ~E, children)), placement_work(~A, ~E, remaining)), parent)),
        (next => {Nat.is_le(next, Nat.add(7n, Nat.add(Nat.add(Allocation.height_forest_work(~A, ~E, children), placement_work(~A, ~E, remaining)), parent))) == True{} : Bool}),
        SpaceProof.le_refl(Nat.add(7n, Nat.add(Nat.add(Allocation.height_forest_work(~A, ~E, children), placement_work(~A, ~E, remaining)), parent))),
        Nat.add(Nat.add(5n, Allocation.height_forest_work(~A, ~E, children)), Nat.add(2n, Nat.add(placement_work(~A, ~E, remaining), parent))),
        child_resume_rank(Nat.add(5n, Allocation.height_forest_work(~A, ~E, children)), placement_work(~A, ~E, remaining), parent))

# This premise preserves the full ordered population, not only its numeric weight.
def planned_minimum_decrease(~A: Data, ~E: Data,
  +placements: +List<Space.Placement<Allocation.MeasuredTree<A, E>>>,
  +children: +List<Allocation.MeasuredTree<A, E>>, +parent: Nat,
  population: {SpaceLaws.placement_values(~Allocation.MeasuredTree<A, E>, placements) == children : +List<Allocation.MeasuredTree<A, E>>}) ->
  {Nat.is_le(Nat.add(3n, Nat.add(placement_work(~A, ~E, placements), parent)),
    Nat.sub(Nat.add(4n, Nat.add(Allocation.height_forest_work(~A, ~E, children), parent)), 1n)) == True{} : Bool}:
  Std.transport(+List<Allocation.MeasuredTree<A, E>>, children,
    (values => {Nat.is_le(Nat.add(3n, Nat.add(Allocation.height_forest_work(~A, ~E, values), parent)),
      Nat.add(3n, Nat.add(Allocation.height_forest_work(~A, ~E, children), parent))) == True{} : Bool}),
    SpaceProof.le_refl(Nat.add(3n, Nat.add(Allocation.height_forest_work(~A, ~E, children), parent))),
    SpaceLaws.placement_values(~Allocation.MeasuredTree<A, E>, placements),
    population)

def minimum_container_decrease(~A: Data, ~E: Data, +plan: Allocation.ChildPlan<Allocation.MeasuredTree<A, E>>, +children: +List<Allocation.MeasuredTree<A, E>>, +parent: Nat,
  population: PopulationRules.BlockPopulation(~A, ~E, children, plan)) ->
  {Nat.is_le(plan_rank(~A, ~E, plan, parent), Nat.sub(Nat.add(4n, Nat.add(Allocation.height_forest_work(~A, ~E, children), parent)), 1n)) == True{} : Bool}:
  match plan:
    case Allocation.PlanningFailure{failure}:
      Std.transport(Nat, Nat.add(parent, Nat.add(1n, Allocation.height_forest_work(~A, ~E, children))),
        (bound => {Nat.is_le(parent, bound) == True{} : Bool}),
        SpaceProof.le_add(parent, Nat.add(1n, Allocation.height_forest_work(~A, ~E, children))),
        Nat.add(Nat.add(1n, Allocation.height_forest_work(~A, ~E, children)), parent),
        SpaceProof.add_comm(Nat.add(1n, Allocation.height_forest_work(~A, ~E, children)), parent))
    case Allocation.ChildrenPlanned{placements, canvas_height}: planned_minimum_decrease(~A, ~E, placements, children, parent, population)

def step_decrease(~A: Data, ~E: Data, +state: Allocation.HeightState<A, E>) -> decrease_claim(~A, ~E, state):
  match state:
    case Allocation.HeightVisit{tree, bounds, parent}: visit_decrease(~A, ~E, tree, return_rank(~A, ~E, parent))
    case Allocation.HeightMinimumChecked{False{}, tree, bounds, lower, parent}: minimum_failure_decrease(~A, ~E, tree, return_rank(~A, ~E, parent))
    case Allocation.HeightMinimumChecked{True{}, Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, width, offset, content_height}, bounds, lower, parent}:
      SpaceProof.le_refl(Nat.add(1n, return_rank(~A, ~E, parent)))
    case Allocation.HeightMinimumChecked{True{}, Allocation.MeasuredContainer{+key, value, interaction, +rule, width, offset, +direction, +children}, bounds, lower, parent}:
      match bounds:
        case Spatial.Box{left, top, offered_width, +offered_height}:
          minimum_container_decrease(~A, ~E, Allocation.prepare_block_children(~A, ~E, key, rule, direction, children, Nat.sub(offered_height, Nat.mul(2n, Allocation.block_inset(rule)))), children, return_rank(~A, ~E, parent),
            PopulationProof.block_population(~A, ~E, key, rule, direction, children, Nat.sub(offered_height, Nat.mul(2n, Allocation.block_inset(rule)))))
    case Allocation.HeightContainerPlan{Allocation.PlanningFailure{failure}, key, value, interaction, rule, bounds, children, direction, width, left, top, parent}:
      SpaceProof.le_refl(Nat.add(1n, return_rank(~A, ~E, parent)))
    case Allocation.HeightContainerPlan{Allocation.ChildrenPlanned{placements, canvas_height}, key, value, interaction, rule, bounds, children, direction, width, left, top, parent}:
      SpaceProof.le_refl(Nat.add(2n, Nat.add(placement_work(~A, ~E, placements), return_rank(~A, ~E, parent))))
    case Allocation.HeightChildren{Nil{}, key, value, interaction, rule, bounds, canvas, direction, left, top, previous, parent}:
      SpaceProof.le_refl(Nat.add(1n, return_rank(~A, ~E, parent)))
    case Allocation.HeightChildren{Con{Space.Placement{child, offset, extent}, remaining}, key, value, interaction, rule, bounds, canvas, direction, left, top, previous, parent}:
      children_visit_decrease(~A, ~E, child, remaining, return_rank(~A, ~E, parent))
    case Allocation.HeightComplete{result, Allocation.HeightRootReturn{}}: {==}
    case Allocation.HeightComplete{result, Allocation.HeightContainerReturn{key, value, interaction, rule, bounds, canvas, direction, left, top, remaining, previous, parent}}:
      SpaceProof.le_refl(Nat.add(2n, Nat.add(placement_work(~A, ~E, remaining), return_rank(~A, ~E, parent))))
    case Allocation.HeightDone{result}: {==}

# The production budget reserves one more edge than the initial root needs.
def initial_fits(~A: Data, ~E: Data, tree: Allocation.MeasuredTree<A, E>, bounds: Spatial.Box) ->
  {Nat.is_le(rank(~A, ~E, Allocation.HeightVisit{tree, bounds, Allocation.HeightRootReturn{}}),
    Allocation.height_forest_work(~A, ~E, tree <> Nil{})) == True{} : Bool}:
  match tree:
    case Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, width, offset, content_height}: {==}
    case Allocation.MeasuredContainer{key, value, interaction, rule, width, offset, direction, +children}:
      Std.transport(Nat, Nat.add(Nat.add(Allocation.height_forest_work(~A, ~E, children), 0n), 1n),
        (bound => {Nat.is_le(Nat.add(Allocation.height_forest_work(~A, ~E, children), 0n), bound) == True{} : Bool}),
        SpaceProof.le_add(Nat.add(Allocation.height_forest_work(~A, ~E, children), 0n), 1n),
        Nat.add(1n, Nat.add(Allocation.height_forest_work(~A, ~E, children), 0n)),
        SpaceProof.add_comm(1n, Nat.add(Allocation.height_forest_work(~A, ~E, children), 0n)))

def iteration_rank_zero(~A: Data, ~E: Data, +tree: Allocation.MeasuredTree<A, E>, +bounds: Spatial.Box) ->
  {rank(~A, ~E, Allocation.iterate_height(~A, ~E, tree, bounds)) == 0n : Nat}:
  Budget.iterate_rank_zero(~Allocation.HeightState<A, E>, ~(state => Allocation.height_step(~A, ~E, state)),
    ~(state => rank(~A, ~E, state)), ~(+state => step_decrease(~A, ~E, state)),
    Allocation.HeightVisit{tree, bounds, Allocation.HeightRootReturn{}},
    Allocation.height_forest_work(~A, ~E, tree <> Nil{}), initial_fits(~A, ~E, tree, bounds))

def complete(~A: Data, ~E: Data, +tree: Allocation.MeasuredTree<A, E>, +bounds: Spatial.Box) -> Rule.complete_claim(~A, ~E, tree, bounds):
  Equal.trans(Bool,
    Rule.completed(~A, ~E, Allocation.iterate_height(~A, ~E, tree, bounds)),
    Nat.is_eq(rank(~A, ~E, Allocation.iterate_height(~A, ~E, tree, bounds)), 0n), True{},
    Equal.sym(Bool, Nat.is_eq(rank(~A, ~E, Allocation.iterate_height(~A, ~E, tree, bounds)), 0n),
      Rule.completed(~A, ~E, Allocation.iterate_height(~A, ~E, tree, bounds)), rank_zero(~A, ~E, Allocation.iterate_height(~A, ~E, tree, bounds))),
    Equal.cong(Nat, Bool, (value => Nat.is_eq(value, 0n)), rank(~A, ~E, Allocation.iterate_height(~A, ~E, tree, bounds)), 0n,
      iteration_rank_zero(~A, ~E, tree, bounds)))

def Rule.evidence(A, E):
  Rule.Requirements{+tree => +bounds => complete(~A, ~E, tree, bounds)}
