import Base
import ../../bendlib/string-equality.bend as SafeText
import ../../bendlib/equality-proof.bend as TextProof
import ../../bendlib/categories.bend as Categories
import ../document/SOURCE.bend as Source
import ./CONTENT.bend as Content
import ./allocation-contract.bend as RulePhysicalSourceRules
import ./physical-content-measurement.bend as RulePhysicalContentRules2
import ./SOURCE.bend as SourceSource
import ../../bendlib/stdlib.bend as Std
import ./physical-space.bend as Model
import ../document/MODEL.bend as Doc
import ../appearance/TYPOGRAPHY.bend as T
import ../../interaction/IDENTITY.bend as Identity
import ./SPACE.bend as Space
import ./PROGRAM.bend as Allocation
import ./geometry-contract.bend as Rule
import ./geometry-proof.bend as ProofGeometryProof
import ./GEOMETRY.bend as SpatialModel
import ./allocation-proof.bend as ProofAllocationProof
import ../../bendlib/algebra-proof.bend as Alg
import ./enclosure.bend as E
import ../../bendlib/logic-proof.bend as Logic
import ./MODEL.bend as World
import ./CONTRACT.bend as RuleContract
import ./measurement-contract.bend as RuleMeasurement
import ./measurement-requirements.bend as Dimensions
import ./measurement-proof.bend as MeasurementEvidence
import ./physical-native.bend as NativePhysical
import ../../interaction/conversation/CODE.bend as Code

def field_native_footprint(+kind: Source.NativeFieldKind, +node: Source.Node, +key: String,
  +style: Source.ResolvedStyle, +generation: Nat, +observations: +List<Content.Observation>) ->
  RulePhysicalSourceRules.field_native_footprint(kind, node, key, style, generation, observations): {==}

def rejected_duplicate(duplicate: Maybe<&2, Content.NativeSlot>, +prepared: Content.Prepared) ->
  {RulePhysicalContentRules2.ready_native_targets_valid(SourceSource.reject_duplicate(duplicate, prepared)) == True{} : Bool}:
  match duplicate:
    case None{}:
      Content.Prepared{snapshot, tree, roots, policies} = prepared
      {==}
    case Some{Content.NativeSlot{owner_key, target_key}}:
      Content.Prepared{snapshot, tree, roots, policies} = prepared
      {==}

def admitted(member: Maybe<&1, Categories.Membership<Content.Prepared, SourceSource.native_targets_category()>>,
  +prepared: Content.Prepared) ->
  {RulePhysicalContentRules2.ready_native_targets_valid(SourceSource.native_targets_admitted(member, prepared)) == True{} : Bool}:
  match member:
    case Some{Categories.Membership{value, evidence}}: evidence
    case None{}: rejected_duplicate(Content.duplicate_native_slot(Content.native_slots(prepared)), prepared)

def admission(+prepared: Content.Prepared) ->
  {RulePhysicalContentRules2.ready_native_targets_valid(SourceSource.admit_native_targets(prepared)) == True{} : Bool}:
  admitted(Categories.admit(Content.Prepared, RulePhysicalContentRules2.native_targets_valid, prepared), prepared)

def single_root(trees: +List<Model.Tree<Content.Value, Doc.DOMEvent>>, +snapshot: Content.Snapshot,
  +roots: +List<Content.NativeRoot>, +policies: +List<Content.NativePolicy>) ->
  {RulePhysicalContentRules2.ready_native_targets_valid(SourceSource.single_root(trees, snapshot, roots, policies)) == True{} : Bool}:
  match trees:
    case Nil{}: {==}
    case Con{tree, Nil{}}: admission(Content.Prepared{snapshot, tree, roots, policies})
    case Con{tree, Con{next, rest}}: {==}

def preparation(result: SourceSource.Forest, +snapshot: Content.Snapshot) ->
  {RulePhysicalContentRules2.ready_native_targets_valid(SourceSource.preparation(result, snapshot)) == True{} : Bool}:
  match result:
    case SourceSource.ReadyForest{trees, roots, policies}: single_root(trees, snapshot, roots, policies)
    case SourceSource.MissingForest{first, remaining}: {==}
    case SourceSource.InvalidForest{error}: {==}

def native_targets(+snapshot: Content.Snapshot, +observations: +List<Content.Observation>) ->
  RulePhysicalSourceRules.native_targets_claim(snapshot, observations):
  match snapshot:
    case Content.Snapshot{generation, source, default_font}:
      preparation(SourceSource.prepare_forest(source <> Nil{}, default_font, generation, "", 0n, SourceSource.Ordinary{}, observations), snapshot)

def field_width_formula(+capacity: Nat, +kind: Source.NativeFieldKind, +policy: Source.FieldPolicy, +font: T.Presentation, +observation: Content.Observation) ->
  {RulePhysicalSourceRules.minimum_width(SourceSource.field_natural_demand_at(capacity, kind, policy, font, observation)) == Nat.max(RulePhysicalSourceRules.column_floor(policy, observation), RulePhysicalSourceRules.observed_minimum(observation)) : Nat}:
  match policy:
    case Source.FieldPolicy{+columns, +minimum_lines, +maximum_lines}:
      match observation:
        case Content.Observation{generation, key, purpose, +minimum, preferred, height, +advance}:
          {==}

def field_column_floor(+capacity: Nat, +kind: Source.NativeFieldKind, +policy: Source.FieldPolicy, +font: T.Presentation, +observation: Content.Observation) ->
  {Nat.is_ge(RulePhysicalSourceRules.minimum_width(SourceSource.field_natural_demand_at(capacity, kind, policy, font, observation)), RulePhysicalSourceRules.column_floor(policy, observation)) == True{} : Bool}:
  match policy:
    case Source.FieldPolicy{+columns, +minimum_lines, +maximum_lines}:
      match observation:
        case Content.Observation{generation, key, purpose, +minimum, preferred, height, +advance}:
          Nat.max_ge_l(Nat.mul(columns, advance), minimum)

def field_observed_minimum(+capacity: Nat, +kind: Source.NativeFieldKind, +policy: Source.FieldPolicy, +font: T.Presentation, +observation: Content.Observation) ->
  {Nat.is_ge(RulePhysicalSourceRules.minimum_width(SourceSource.field_natural_demand_at(capacity, kind, policy, font, observation)), RulePhysicalSourceRules.observed_minimum(observation)) == True{} : Bool}:
  match policy:
    case Source.FieldPolicy{+columns, +minimum_lines, +maximum_lines}:
      match observation:
        case Content.Observation{generation, key, purpose, +minimum, preferred, height, +advance}:
          Nat.max_ge_r(Nat.mul(columns, advance), minimum)

def field_preferred_width(+capacity: Nat, +kind: Source.NativeFieldKind, +policy: Source.FieldPolicy, +font: T.Presentation, +observation: Content.Observation) ->
  {RulePhysicalSourceRules.preferred_width(SourceSource.field_natural_demand_at(capacity, kind, policy, font, observation)) == Nat.max(RulePhysicalSourceRules.minimum_width(SourceSource.field_natural_demand_at(capacity, kind, policy, font, observation)), RulePhysicalSourceRules.observed_preferred(observation)) : Nat}:
  match policy:
    case Source.FieldPolicy{+columns, +minimum_lines, +maximum_lines}:
      match observation:
        case Content.Observation{generation, key, purpose, +minimum, preferred, height, +advance}:
          {==}

def field_minimum_height_fields(+capacity: Nat, +kind: Source.NativeFieldKind, +font: T.Presentation, +columns: Nat, +minimum_lines: Nat, +maximum_lines: Nat, +generation: Nat, +key: String, +purpose: Content.Purpose, +minimum: Nat, +preferred: Nat, +height: Nat, +advance: Nat) ->
  {RulePhysicalSourceRules.minimum_height(SourceSource.field_natural_demand_at(capacity, kind, Source.FieldPolicy{columns, minimum_lines, maximum_lines}, font, Content.Observation{generation, key, purpose, minimum, preferred, height, advance})) == RulePhysicalSourceRules.expected_height(capacity, kind, Source.FieldPolicy{columns, minimum_lines, maximum_lines}, font, Content.Observation{generation, key, purpose, minimum, preferred, height, advance}) : Nat}:
  match kind:
    case Source.TextField{}: {==}
    case Source.MessageField{}: {==}
    case Source.TextAreaField{}: {==}
    case Source.SelectField{}: {==}
    case Source.MultiSelectField{}: {==}
    case Source.ToggleField{}: {==}
    case Source.NumberField{minimum}: {==}
    case Source.RangeField{minimum, maximum, step}: {==}
    case Source.DecimalField{minimum, maximum, step}: {==}
    case Source.FileField{multiple}: {==}
    case Source.DirectoryField{}: {==}
    case Source.SearchField{}: {==}
    case Source.SecretField{}: {==}

def field_minimum_height(+capacity: Nat, +kind: Source.NativeFieldKind, +policy: Source.FieldPolicy, +font: T.Presentation, +observation: Content.Observation) ->
  {RulePhysicalSourceRules.minimum_height(SourceSource.field_natural_demand_at(capacity, kind, policy, font, observation)) == RulePhysicalSourceRules.expected_height(capacity, kind, policy, font, observation) : Nat}:
  match policy:
    case Source.FieldPolicy{+columns, +minimum_lines, +maximum_lines}:
      match observation:
        case Content.Observation{generation, key, purpose, +minimum, preferred, height, +advance}:
          field_minimum_height_fields(capacity, kind, font, columns, minimum_lines, maximum_lines, generation, key, purpose, minimum, preferred, height, advance)

def field_preferred_height_fields(+capacity: Nat, +kind: Source.NativeFieldKind, +font: T.Presentation, +columns: Nat, +minimum_lines: Nat, +maximum_lines: Nat, +generation: Nat, +key: String, +purpose: Content.Purpose, +minimum: Nat, +preferred: Nat, +height: Nat, +advance: Nat) ->
  {RulePhysicalSourceRules.preferred_height(SourceSource.field_natural_demand_at(capacity, kind, Source.FieldPolicy{columns, minimum_lines, maximum_lines}, font, Content.Observation{generation, key, purpose, minimum, preferred, height, advance})) == RulePhysicalSourceRules.expected_height(capacity, kind, Source.FieldPolicy{columns, minimum_lines, maximum_lines}, font, Content.Observation{generation, key, purpose, minimum, preferred, height, advance}) : Nat}:
  match kind:
    case Source.TextField{}: {==}
    case Source.MessageField{}: {==}
    case Source.TextAreaField{}: {==}
    case Source.SelectField{}: {==}
    case Source.MultiSelectField{}: {==}
    case Source.ToggleField{}: {==}
    case Source.NumberField{minimum}: {==}
    case Source.RangeField{minimum, maximum, step}: {==}
    case Source.DecimalField{minimum, maximum, step}: {==}
    case Source.FileField{multiple}: {==}
    case Source.DirectoryField{}: {==}
    case Source.SearchField{}: {==}
    case Source.SecretField{}: {==}

def field_preferred_height(+capacity: Nat, +kind: Source.NativeFieldKind, +policy: Source.FieldPolicy, +font: T.Presentation, +observation: Content.Observation) ->
  {RulePhysicalSourceRules.preferred_height(SourceSource.field_natural_demand_at(capacity, kind, policy, font, observation)) == RulePhysicalSourceRules.expected_height(capacity, kind, policy, font, observation) : Nat}:
  match policy:
    case Source.FieldPolicy{+columns, +minimum_lines, +maximum_lines}:
      match observation:
        case Content.Observation{generation, key, purpose, +minimum, preferred, height, +advance}:
          field_preferred_height_fields(capacity, kind, font, columns, minimum_lines, maximum_lines, generation, key, purpose, minimum, preferred, height, advance)

def field_production_demand(+capacity: Nat, +label: Identity.Key, +kind: Source.NativeFieldKind, +style: Source.Style,
  +attributes: +List<Source.Attribute>, +value: String, +placeholder: String, +options: +List<Source.Choice>,
  +policy: Source.FieldPolicy, +name: String, +enabled: Bool, +first_event: Doc.DOMEvent,
  +remaining_events: +List<Doc.DOMEvent>, +key: String, +font: T.Presentation, +rule: Model.Rule,
  +observation: Content.Observation, +roots: +List<Content.NativeRoot>, +policies: +List<Content.NativePolicy>) ->
  {RulePhysicalSourceRules.first_leaf_demand(SourceSource.observed_leaf_at(capacity, Source.Field{label, kind, style, attributes, value, placeholder,
    options, policy, name, enabled, first_event, remaining_events}, key, font, rule, observation, roots, policies)) ==
    Some{SourceSource.field_natural_demand_at(capacity, kind, policy, font, observation)} : Maybe<&2, Space.Demand>}:
  match policy:
    case Source.FieldPolicy{columns, minimum_lines, maximum_lines}:
      match observation:
        case Content.Observation{generation, observed_key, purpose, minimum, preferred, height, advance}: {==}

def RulePhysicalSourceRules.source_evidence():
  RulePhysicalSourceRules.SourceRequirements{field_native_footprint, +snapshot => +observations => native_targets(snapshot, observations),
    field_width_formula, field_column_floor, field_observed_minimum, field_preferred_width,
    field_minimum_height, field_preferred_height, field_production_demand}

def physical_height_proof_placement_work(~A: Data, ~E: Data, +placements: +List<Space.Placement<Allocation.MeasuredTree<A, E>>>) -> Nat:
  Allocation.height_forest_work(~A, ~E, Rule.placement_values(~Allocation.MeasuredTree<A, E>, placements))

def physical_height_proof_return_rank(~A: Data, ~E: Data, target: Allocation.HeightReturn<A, E>) -> Nat:
  match target:
    case Allocation.HeightRootReturn{}: 0n
    case Allocation.HeightContainerReturn{key, value, interaction, rule, bounds, canvas, direction, left, top, remaining, previous, parent}:
      Nat.add(2n, Nat.add(physical_height_proof_placement_work(~A, ~E, remaining), physical_height_proof_return_rank(~A, ~E, parent)))

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
    case Allocation.ChildrenPlanned{placements, canvas_height}: Nat.add(3n, Nat.add(physical_height_proof_placement_work(~A, ~E, placements), parent))

def physical_height_proof_rank(~A: Data, ~E: Data, state: Allocation.HeightState<A, E>) -> Nat:
  match state:
    case Allocation.HeightVisit{tree, bounds, parent}: visit_rank(~A, ~E, tree, physical_height_proof_return_rank(~A, ~E, parent))
    case Allocation.HeightMinimumChecked{fits, tree, bounds, lower, parent}: checked_rank(~A, ~E, tree, physical_height_proof_return_rank(~A, ~E, parent))
    case Allocation.HeightContainerPlan{plan, key, value, interaction, rule, bounds, children, direction, width, left, top, parent}:
      plan_rank(~A, ~E, plan, physical_height_proof_return_rank(~A, ~E, parent))
    case Allocation.HeightChildren{remaining, key, value, interaction, rule, bounds, canvas, direction, left, top, previous, parent}:
      Nat.add(2n, Nat.add(physical_height_proof_placement_work(~A, ~E, remaining), physical_height_proof_return_rank(~A, ~E, parent)))
    case Allocation.HeightComplete{result, parent}: Nat.add(1n, physical_height_proof_return_rank(~A, ~E, parent))
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
  {Nat.is_eq(physical_height_proof_rank(~A, ~E, state), 0n) == RulePhysicalSourceRules.height_completed(~A, ~E, state) : Bool}:
  match state:
    case Allocation.HeightVisit{tree, bounds, parent}: visit_nonzero(~A, ~E, tree, physical_height_proof_return_rank(~A, ~E, parent))
    case Allocation.HeightMinimumChecked{fits, tree, bounds, lower, parent}: checked_nonzero(~A, ~E, tree, physical_height_proof_return_rank(~A, ~E, parent))
    case Allocation.HeightContainerPlan{plan, key, value, interaction, rule, bounds, children, direction, width, left, top, parent}:
      plan_nonzero(~A, ~E, plan, physical_height_proof_return_rank(~A, ~E, parent))
    case Allocation.HeightChildren{remaining, key, value, interaction, rule, bounds, canvas, direction, left, top, previous, parent}: {==}
    case Allocation.HeightComplete{result, parent}: {==}
    case Allocation.HeightDone{result}: {==}

def decrease_claim(~A: Data, ~E: Data, state: Allocation.HeightState<A, E>) -> Type:
  {Nat.is_le(physical_height_proof_rank(~A, ~E, Allocation.height_step(~A, ~E, state)), Nat.sub(physical_height_proof_rank(~A, ~E, state), 1n)) == True{} : Bool}

def physical_height_proof_visit_decrease(~A: Data, ~E: Data, tree: Allocation.MeasuredTree<A, E>, +parent: Nat) ->
  {Nat.is_le(checked_rank(~A, ~E, tree, parent), Nat.sub(visit_rank(~A, ~E, tree, parent), 1n)) == True{} : Bool}:
  match tree:
    case Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, width, offset, content_height}: ProofGeometryProof.le_refl(Nat.add(2n, parent))
    case Allocation.MeasuredContainer{key, value, interaction, rule, width, offset, direction, +children}:
      ProofGeometryProof.le_refl(Nat.add(4n, Nat.add(Allocation.height_forest_work(~A, ~E, children), parent)))

def minimum_failure_decrease(~A: Data, ~E: Data, tree: Allocation.MeasuredTree<A, E>, +parent: Nat) ->
  {Nat.is_le(Nat.add(1n, parent), Nat.sub(checked_rank(~A, ~E, tree, parent), 1n)) == True{} : Bool}:
  match tree:
    case Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, width, offset, content_height}: ProofGeometryProof.le_refl(Nat.add(1n, parent))
    case Allocation.MeasuredContainer{key, value, interaction, rule, width, offset, direction, +children}:
      Std.transport(Nat, Nat.add(parent, Nat.add(2n, Allocation.height_forest_work(~A, ~E, children))),
        (bound => {Nat.is_le(parent, bound) == True{} : Bool}),
        ProofGeometryProof.le_add(parent, Nat.add(2n, Allocation.height_forest_work(~A, ~E, children))),
        Nat.add(Nat.add(2n, Allocation.height_forest_work(~A, ~E, children)), parent),
        ProofGeometryProof.add_comm(Nat.add(2n, Allocation.height_forest_work(~A, ~E, children)), parent))

# A child visit replaces its reserved parent edge with its explicit return frame.

def child_resume_rank(+own: Nat, +rest: Nat, +parent: Nat) ->
  {Nat.add(own, Nat.add(2n, Nat.add(rest, parent))) == Nat.add(2n, Nat.add(Nat.add(own, rest), parent)) : Nat}:
  match own:
    case 0n: {==}
    case 1n+tail:
      Equal.cong(Nat, Nat, (value => 1n+value), Nat.add(tail, Nat.add(2n, Nat.add(rest, parent))),
        Nat.add(2n, Nat.add(Nat.add(tail, rest), parent)), child_resume_rank(tail, rest, parent))

def children_visit_decrease(~A: Data, ~E: Data, tree: Allocation.MeasuredTree<A, E>, +remaining: +List<Space.Placement<Allocation.MeasuredTree<A, E>>>, +parent: Nat) ->
  {Nat.is_le(visit_rank(~A, ~E, tree, Nat.add(2n, Nat.add(physical_height_proof_placement_work(~A, ~E, remaining), parent))),
    Nat.sub(Nat.add(2n, Nat.add(Allocation.height_forest_work(~A, ~E, tree <> Rule.placement_values(~Allocation.MeasuredTree<A, E>, remaining)), parent)), 1n)) == True{} : Bool}:
  match tree:
    case Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, width, offset, content_height}:
      ProofGeometryProof.le_refl(Nat.add(5n, Nat.add(physical_height_proof_placement_work(~A, ~E, remaining), parent)))
    case Allocation.MeasuredContainer{key, value, interaction, rule, width, offset, direction, +children}:
      Std.transport(Nat,
        Nat.add(2n, Nat.add(Nat.add(Nat.add(5n, Allocation.height_forest_work(~A, ~E, children)), physical_height_proof_placement_work(~A, ~E, remaining)), parent)),
        (next => {Nat.is_le(next, Nat.add(7n, Nat.add(Nat.add(Allocation.height_forest_work(~A, ~E, children), physical_height_proof_placement_work(~A, ~E, remaining)), parent))) == True{} : Bool}),
        ProofGeometryProof.le_refl(Nat.add(7n, Nat.add(Nat.add(Allocation.height_forest_work(~A, ~E, children), physical_height_proof_placement_work(~A, ~E, remaining)), parent))),
        Nat.add(Nat.add(5n, Allocation.height_forest_work(~A, ~E, children)), Nat.add(2n, Nat.add(physical_height_proof_placement_work(~A, ~E, remaining), parent))),
        child_resume_rank(Nat.add(5n, Allocation.height_forest_work(~A, ~E, children)), physical_height_proof_placement_work(~A, ~E, remaining), parent))

# This premise preserves the full ordered population, not only its numeric weight.

def planned_minimum_decrease(~A: Data, ~E: Data,
  +placements: +List<Space.Placement<Allocation.MeasuredTree<A, E>>>,
  +children: +List<Allocation.MeasuredTree<A, E>>, +parent: Nat,
  population: {Rule.placement_values(~Allocation.MeasuredTree<A, E>, placements) == children : +List<Allocation.MeasuredTree<A, E>>}) ->
  {Nat.is_le(Nat.add(3n, Nat.add(physical_height_proof_placement_work(~A, ~E, placements), parent)),
    Nat.sub(Nat.add(4n, Nat.add(Allocation.height_forest_work(~A, ~E, children), parent)), 1n)) == True{} : Bool}:
  Std.transport(+List<Allocation.MeasuredTree<A, E>>, children,
    (values => {Nat.is_le(Nat.add(3n, Nat.add(Allocation.height_forest_work(~A, ~E, values), parent)),
      Nat.add(3n, Nat.add(Allocation.height_forest_work(~A, ~E, children), parent))) == True{} : Bool}),
    ProofGeometryProof.le_refl(Nat.add(3n, Nat.add(Allocation.height_forest_work(~A, ~E, children), parent))),
    Rule.placement_values(~Allocation.MeasuredTree<A, E>, placements),
    population)

def minimum_container_decrease(~A: Data, ~E: Data, +plan: Allocation.ChildPlan<Allocation.MeasuredTree<A, E>>, +children: +List<Allocation.MeasuredTree<A, E>>, +parent: Nat,
  population: RulePhysicalSourceRules.BlockPopulation(~A, ~E, children, plan)) ->
  {Nat.is_le(plan_rank(~A, ~E, plan, parent), Nat.sub(Nat.add(4n, Nat.add(Allocation.height_forest_work(~A, ~E, children), parent)), 1n)) == True{} : Bool}:
  match plan:
    case Allocation.PlanningFailure{failure}:
      Std.transport(Nat, Nat.add(parent, Nat.add(1n, Allocation.height_forest_work(~A, ~E, children))),
        (bound => {Nat.is_le(parent, bound) == True{} : Bool}),
        ProofGeometryProof.le_add(parent, Nat.add(1n, Allocation.height_forest_work(~A, ~E, children))),
        Nat.add(Nat.add(1n, Allocation.height_forest_work(~A, ~E, children)), parent),
        ProofGeometryProof.add_comm(Nat.add(1n, Allocation.height_forest_work(~A, ~E, children)), parent))
    case Allocation.ChildrenPlanned{placements, canvas_height}: planned_minimum_decrease(~A, ~E, placements, children, parent, population)

def physical_height_proof_step_decrease(~A: Data, ~E: Data, +state: Allocation.HeightState<A, E>) -> decrease_claim(~A, ~E, state):
  match state:
    case Allocation.HeightVisit{tree, bounds, parent}: physical_height_proof_visit_decrease(~A, ~E, tree, physical_height_proof_return_rank(~A, ~E, parent))
    case Allocation.HeightMinimumChecked{False{}, tree, bounds, lower, parent}: minimum_failure_decrease(~A, ~E, tree, physical_height_proof_return_rank(~A, ~E, parent))
    case Allocation.HeightMinimumChecked{True{}, Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, width, offset, content_height}, bounds, lower, parent}:
      ProofGeometryProof.le_refl(Nat.add(1n, physical_height_proof_return_rank(~A, ~E, parent)))
    case Allocation.HeightMinimumChecked{True{}, Allocation.MeasuredContainer{+key, value, interaction, +rule, width, offset, +direction, +children}, bounds, lower, parent}:
      match bounds:
        case SpatialModel.Box{left, top, offered_width, +offered_height}:
          minimum_container_decrease(~A, ~E, Allocation.prepare_block_children(~A, ~E, key, rule, direction, children, Nat.sub(offered_height, Nat.mul(2n, Allocation.block_inset(rule)))), children, physical_height_proof_return_rank(~A, ~E, parent),
            ProofAllocationProof.block_population(~A, ~E, key, rule, direction, children, Nat.sub(offered_height, Nat.mul(2n, Allocation.block_inset(rule)))))
    case Allocation.HeightContainerPlan{Allocation.PlanningFailure{failure}, key, value, interaction, rule, bounds, children, direction, width, left, top, parent}:
      ProofGeometryProof.le_refl(Nat.add(1n, physical_height_proof_return_rank(~A, ~E, parent)))
    case Allocation.HeightContainerPlan{Allocation.ChildrenPlanned{placements, canvas_height}, key, value, interaction, rule, bounds, children, direction, width, left, top, parent}:
      ProofGeometryProof.le_refl(Nat.add(2n, Nat.add(physical_height_proof_placement_work(~A, ~E, placements), physical_height_proof_return_rank(~A, ~E, parent))))
    case Allocation.HeightChildren{Nil{}, key, value, interaction, rule, bounds, canvas, direction, left, top, previous, parent}:
      ProofGeometryProof.le_refl(Nat.add(1n, physical_height_proof_return_rank(~A, ~E, parent)))
    case Allocation.HeightChildren{Con{Space.Placement{child, offset, extent}, remaining}, key, value, interaction, rule, bounds, canvas, direction, left, top, previous, parent}:
      children_visit_decrease(~A, ~E, child, remaining, physical_height_proof_return_rank(~A, ~E, parent))
    case Allocation.HeightComplete{result, Allocation.HeightRootReturn{}}: {==}
    case Allocation.HeightComplete{result, Allocation.HeightContainerReturn{key, value, interaction, rule, bounds, canvas, direction, left, top, remaining, previous, parent}}:
      ProofGeometryProof.le_refl(Nat.add(2n, Nat.add(physical_height_proof_placement_work(~A, ~E, remaining), physical_height_proof_return_rank(~A, ~E, parent))))
    case Allocation.HeightDone{result}: {==}

# The production budget reserves one more edge than the initial root needs.

def initial_fits(~A: Data, ~E: Data, tree: Allocation.MeasuredTree<A, E>, bounds: SpatialModel.Box) ->
  {Nat.is_le(physical_height_proof_rank(~A, ~E, Allocation.HeightVisit{tree, bounds, Allocation.HeightRootReturn{}}),
    Allocation.height_forest_work(~A, ~E, tree <> Nil{})) == True{} : Bool}:
  match tree:
    case Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, width, offset, content_height}: {==}
    case Allocation.MeasuredContainer{key, value, interaction, rule, width, offset, direction, +children}:
      Std.transport(Nat, Nat.add(Nat.add(Allocation.height_forest_work(~A, ~E, children), 0n), 1n),
        (bound => {Nat.is_le(Nat.add(Allocation.height_forest_work(~A, ~E, children), 0n), bound) == True{} : Bool}),
        ProofGeometryProof.le_add(Nat.add(Allocation.height_forest_work(~A, ~E, children), 0n), 1n),
        Nat.add(1n, Nat.add(Allocation.height_forest_work(~A, ~E, children), 0n)),
        ProofGeometryProof.add_comm(1n, Nat.add(Allocation.height_forest_work(~A, ~E, children), 0n)))

def physical_height_proof_iteration_rank_zero(~A: Data, ~E: Data, +tree: Allocation.MeasuredTree<A, E>, +bounds: SpatialModel.Box) ->
  {physical_height_proof_rank(~A, ~E, Allocation.iterate_height(~A, ~E, tree, bounds)) == 0n : Nat}:
  ProofAllocationProof.iterate_rank_zero(~Allocation.HeightState<A, E>, ~(state => Allocation.height_step(~A, ~E, state)),
    ~(state => physical_height_proof_rank(~A, ~E, state)), ~(+state => physical_height_proof_step_decrease(~A, ~E, state)),
    Allocation.HeightVisit{tree, bounds, Allocation.HeightRootReturn{}},
    Allocation.height_forest_work(~A, ~E, tree <> Nil{}), initial_fits(~A, ~E, tree, bounds))

def physical_height_proof_complete(~A: Data, ~E: Data, +tree: Allocation.MeasuredTree<A, E>, +bounds: SpatialModel.Box) -> RulePhysicalSourceRules.height_complete_claim(~A, ~E, tree, bounds):
  Equal.trans(Bool,
    RulePhysicalSourceRules.height_completed(~A, ~E, Allocation.iterate_height(~A, ~E, tree, bounds)),
    Nat.is_eq(physical_height_proof_rank(~A, ~E, Allocation.iterate_height(~A, ~E, tree, bounds)), 0n), True{},
    Equal.sym(Bool, Nat.is_eq(physical_height_proof_rank(~A, ~E, Allocation.iterate_height(~A, ~E, tree, bounds)), 0n),
      RulePhysicalSourceRules.height_completed(~A, ~E, Allocation.iterate_height(~A, ~E, tree, bounds)), rank_zero(~A, ~E, Allocation.iterate_height(~A, ~E, tree, bounds))),
    Equal.cong(Nat, Bool, (value => Nat.is_eq(value, 0n)), physical_height_proof_rank(~A, ~E, Allocation.iterate_height(~A, ~E, tree, bounds)), 0n,
      physical_height_proof_iteration_rank_zero(~A, ~E, tree, bounds)))

def RulePhysicalSourceRules.height_evidence(A, E):
  RulePhysicalSourceRules.HeightRequirements{+tree => +bounds => physical_height_proof_complete(~A, ~E, tree, bounds)}

# Work ranks count pending transitions, including each suspended parent edge.

def physical_width_proof_placement_work(~A: Data, ~E: Data, +placements: +List<Space.Placement<Model.Tree<A, E>>>) -> Nat:
  Allocation.width_forest_work(~A, ~E, Rule.placement_values(~Model.Tree<A, E>, placements))

def physical_width_proof_return_rank(~A: Data, ~E: Data, return_to: Allocation.WidthReturn<A, E>) -> Nat:
  match return_to:
    case Allocation.WidthRootReturn{}: 0n
    case Allocation.WidthContainerReturn{key, value, interaction, rule, width, offset, direction, remaining, previous, parent}:
      Nat.add(2n, Nat.add(physical_width_proof_placement_work(~A, ~E, remaining), physical_width_proof_return_rank(~A, ~E, parent)))

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
    case Allocation.InlinePlanned{placements, direction, canvas}: Nat.add(3n, physical_width_proof_placement_work(~A, ~E, placements))

def physical_width_proof_rank(~A: Data, ~E: Data, state: Allocation.WidthState<A, E>) -> Nat:
  match state:
    case Allocation.WidthVisit{tree, width, offset, return_to}:
      Nat.add(visit_work(~A, ~E, tree), physical_width_proof_return_rank(~A, ~E, return_to))
    case Allocation.WidthMinimumChecked{fits, tree, width, offset, rule, lower, return_to}:
      Nat.add(checked_work(~A, ~E, tree), physical_width_proof_return_rank(~A, ~E, return_to))
    case Allocation.WidthLeafHeight{sample, key, value, interaction, rule, demand, height, inner_width, outer_width, offset, return_to}:
      Nat.add(2n, physical_width_proof_return_rank(~A, ~E, return_to))
    case Allocation.WidthContainerPlan{plan, key, value, interaction, rule, width, offset, return_to}:
      Nat.add(plan_work(~A, ~E, plan), physical_width_proof_return_rank(~A, ~E, return_to))
    case Allocation.WidthChildren{remaining, key, value, interaction, rule, width, offset, direction, previous, return_to}:
      Nat.add(2n, Nat.add(physical_width_proof_placement_work(~A, ~E, remaining), physical_width_proof_return_rank(~A, ~E, return_to)))
    case Allocation.WidthComplete{result, return_to}: Nat.add(1n, physical_width_proof_return_rank(~A, ~E, return_to))
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
  {Nat.is_eq(physical_width_proof_rank(~A, ~E, state), 0n) == RulePhysicalSourceRules.width_completed(~A, ~E, state) : Bool}:
  match state:
    case Allocation.WidthVisit{tree, width, offset, return_to}: visit_zero(~A, ~E, tree, physical_width_proof_return_rank(~A, ~E, return_to))
    case Allocation.WidthMinimumChecked{fits, tree, width, offset, rule, lower, return_to}: checked_zero(~A, ~E, tree, physical_width_proof_return_rank(~A, ~E, return_to))
    case Allocation.WidthLeafHeight{sample, key, value, interaction, rule, demand, height, inner_width, outer_width, offset, return_to}: {==}
    case Allocation.WidthContainerPlan{plan, key, value, interaction, rule, width, offset, return_to}: plan_zero(~A, ~E, plan, physical_width_proof_return_rank(~A, ~E, return_to))
    case Allocation.WidthChildren{remaining, key, value, interaction, rule, width, offset, direction, previous, return_to}: {==}
    case Allocation.WidthComplete{result, return_to}: {==}
    case Allocation.WidthDone{result}: {==}

def physical_width_proof_visit_decrease(~A: Data, ~E: Data, tree: Model.Tree<A, E>, +continuation: Nat) ->
  {Nat.is_le(Nat.add(checked_work(~A, ~E, tree), continuation), Nat.sub(Nat.add(visit_work(~A, ~E, tree), continuation), 1n)) == True{} : Bool}:
  match tree:
    case Model.Leaf{key, value, interaction, rule, demand, height}: ProofGeometryProof.le_refl(Nat.add(3n, continuation))
    case Model.Container{key, value, interaction, rule, +children}: ProofGeometryProof.le_refl(Nat.add(Nat.add(4n, Allocation.width_forest_work(~A, ~E, children)), continuation))

# A rejected minimum skips all child work; its continuation still completes.

def below_prefix(+value: Nat, +extra: Nat) -> {Nat.is_le(value, Nat.add(extra, value)) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(value, Nat.add(extra, value)), Nat.is_le(value, Nat.add(value, extra)), True{},
    Equal.cong(Nat, Bool, (n => Nat.is_le(value, n)), Nat.add(extra, value), Nat.add(value, extra), ProofGeometryProof.add_comm(extra, value)), ProofGeometryProof.le_add(value, extra))

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
  {Nat.is_le(Nat.add(visit_work(~A, ~E, tree), Nat.add(2n, Nat.add(physical_width_proof_placement_work(~A, ~E, rest), continuation))),
    Nat.sub(Nat.add(2n, Nat.add(Allocation.width_forest_work(~A, ~E, tree <> Rule.placement_values(~Model.Tree<A, E>, rest)), continuation)), 1n)) == True{} : Bool}:
  match tree:
    case Model.Leaf{key, value, interaction, rule, demand, height}:
      ProofGeometryProof.le_refl(Nat.add(6n, Nat.add(physical_width_proof_placement_work(~A, ~E, rest), continuation)))
    case Model.Container{key, value, interaction, rule, +children}:
      Equal.trans(Bool,
        Nat.is_le(Nat.add(Nat.add(5n, Allocation.width_forest_work(~A, ~E, children)), Nat.add(2n, Nat.add(physical_width_proof_placement_work(~A, ~E, rest), continuation))),
          Nat.add(7n, Nat.add(Nat.add(Allocation.width_forest_work(~A, ~E, children), physical_width_proof_placement_work(~A, ~E, rest)), continuation))),
        Nat.is_le(Nat.add(7n, Nat.add(Nat.add(Allocation.width_forest_work(~A, ~E, children), physical_width_proof_placement_work(~A, ~E, rest)), continuation)),
          Nat.add(7n, Nat.add(Nat.add(Allocation.width_forest_work(~A, ~E, children), physical_width_proof_placement_work(~A, ~E, rest)), continuation))), True{},
        Equal.cong(Nat, Bool, (n => Nat.is_le(n, Nat.add(7n, Nat.add(Nat.add(Allocation.width_forest_work(~A, ~E, children), physical_width_proof_placement_work(~A, ~E, rest)), continuation)))),
          Nat.add(Nat.add(5n, Allocation.width_forest_work(~A, ~E, children)), Nat.add(2n, Nat.add(physical_width_proof_placement_work(~A, ~E, rest), continuation))),
          Nat.add(7n, Nat.add(Nat.add(Allocation.width_forest_work(~A, ~E, children), physical_width_proof_placement_work(~A, ~E, rest)), continuation)),
          child_rank_join(Nat.add(5n, Allocation.width_forest_work(~A, ~E, children)), physical_width_proof_placement_work(~A, ~E, rest), continuation)),
        ProofGeometryProof.le_refl(Nat.add(7n, Nat.add(Nat.add(Allocation.width_forest_work(~A, ~E, children), physical_width_proof_placement_work(~A, ~E, rest)), continuation))))

# The ordered population premise is needed only at successful container planning.

def population_decrease(~A: Data, ~E: Data, +placements: +List<Space.Placement<Model.Tree<A, E>>>, +children: +List<Model.Tree<A, E>>, +continuation: Nat,
  population: {Rule.placement_values(~Model.Tree<A, E>, placements) == children : +List<Model.Tree<A, E>>}) ->
  {Nat.is_le(Nat.add(Nat.add(3n, physical_width_proof_placement_work(~A, ~E, placements)), continuation),
    Nat.sub(Nat.add(Nat.add(4n, Allocation.width_forest_work(~A, ~E, children)), continuation), 1n)) == True{} : Bool}:
  Equal.trans(Bool,
    Nat.is_le(Nat.add(Nat.add(3n, physical_width_proof_placement_work(~A, ~E, placements)), continuation), Nat.add(Nat.add(3n, Allocation.width_forest_work(~A, ~E, children)), continuation)),
    Nat.is_le(Nat.add(Nat.add(3n, Allocation.width_forest_work(~A, ~E, children)), continuation), Nat.add(Nat.add(3n, Allocation.width_forest_work(~A, ~E, children)), continuation)), True{},
    Equal.cong(+List<Model.Tree<A, E>>, Bool,
      (trees => Nat.is_le(Nat.add(Nat.add(3n, Allocation.width_forest_work(~A, ~E, trees)), continuation), Nat.add(Nat.add(3n, Allocation.width_forest_work(~A, ~E, children)), continuation))),
      Rule.placement_values(~Model.Tree<A, E>, placements), children, population),
    ProofGeometryProof.le_refl(Nat.add(Nat.add(3n, Allocation.width_forest_work(~A, ~E, children)), continuation)))

def independent_claim(~A: Data, ~E: Data, state: Allocation.WidthState<A, E>, +samples: +List<Model.HeightSample>) -> Type:
  match state:
    case Allocation.WidthMinimumChecked{True{}, Model.Container{key, value, interaction, rule, children}, width, offset, checked_rule, lower, return_to}: Unit
    case _:
      {Nat.is_le(physical_width_proof_rank(~A, ~E, Allocation.width_step(~A, ~E, state, samples)), Nat.sub(physical_width_proof_rank(~A, ~E, state), 1n)) == True{} : Bool}

def visit_checked_decrease(~A: Data, ~E: Data, +valid: Bool, +tree: Model.Tree<A, E>, +width: Nat, +offset: Nat, +rule: Model.Rule, +lower: Nat, +return_to: Allocation.WidthReturn<A, E>) ->
  {Nat.is_le(physical_width_proof_rank(~A, ~E, Allocation.width_visit_checked(~A, ~E, valid, tree, width, offset, rule, lower, return_to)), Nat.sub(physical_width_proof_rank(~A, ~E, Allocation.WidthVisit{tree, width, offset, return_to}), 1n)) == True{} : Bool}:
  match valid:
    case True{}: physical_width_proof_visit_decrease(~A, ~E, tree, physical_width_proof_return_rank(~A, ~E, return_to))
    case False{}:
      match tree:
        case Model.Leaf{key, value, interaction, rule, demand, height}: below_prefix(physical_width_proof_return_rank(~A, ~E, return_to), 2n)
        case Model.Container{key, value, interaction, rule, +children}: below_prefix(physical_width_proof_return_rank(~A, ~E, return_to), Nat.add(3n, Allocation.width_forest_work(~A, ~E, children)))

def independent_decrease(~A: Data, ~E: Data, +state: Allocation.WidthState<A, E>, +samples: +List<Model.HeightSample>) -> independent_claim(~A, ~E, state, samples):
  match state:
    case Allocation.WidthVisit{+tree, +width, +offset, +return_to}: visit_checked_decrease(~A, ~E, Allocation.width_visit_valid(~A, ~E, Allocation.tree_rule(~A, ~E, tree), return_to), tree, width, offset, Allocation.tree_rule(~A, ~E, tree), Allocation.axis_extent(Allocation.InlineAxis{}, Model.minimum_demand(Model.demand(~A, ~E, tree))), return_to)
    case Allocation.WidthMinimumChecked{False{}, tree, width, offset, rule, lower, return_to}: rejected_decrease(~A, ~E, tree, physical_width_proof_return_rank(~A, ~E, return_to))
    case Allocation.WidthMinimumChecked{True{}, Model.Leaf{key, value, interaction, rule, demand, height}, width, offset, checked_rule, lower, return_to}: ProofGeometryProof.le_refl(Nat.add(2n, physical_width_proof_return_rank(~A, ~E, return_to)))
    case Allocation.WidthMinimumChecked{True{}, Model.Container{key, value, interaction, rule, children}, width, offset, checked_rule, lower, return_to}: Unit{}
    case Allocation.WidthLeafHeight{None{}, key, value, interaction, rule, demand, height, inner_width, outer_width, offset, return_to}: ProofGeometryProof.le_refl(Nat.add(1n, physical_width_proof_return_rank(~A, ~E, return_to)))
    case Allocation.WidthLeafHeight{Some{content_height}, key, value, interaction, rule, demand, height, inner_width, outer_width, offset, return_to}: ProofGeometryProof.le_refl(Nat.add(1n, physical_width_proof_return_rank(~A, ~E, return_to)))
    case Allocation.WidthContainerPlan{Allocation.InlineFailure{failure}, key, value, interaction, rule, width, offset, return_to}: ProofGeometryProof.le_refl(Nat.add(1n, physical_width_proof_return_rank(~A, ~E, return_to)))
    case Allocation.WidthContainerPlan{Allocation.InlinePlanned{placements, direction, canvas}, key, value, interaction, rule, width, offset, return_to}: ProofGeometryProof.le_refl(Nat.add(2n, Nat.add(physical_width_proof_placement_work(~A, ~E, placements), physical_width_proof_return_rank(~A, ~E, return_to))))
    case Allocation.WidthChildren{Nil{}, key, value, interaction, rule, width, offset, direction, previous, return_to}: ProofGeometryProof.le_refl(Nat.add(1n, physical_width_proof_return_rank(~A, ~E, return_to)))
    case Allocation.WidthChildren{Con{Space.Placement{child, child_offset, extent}, rest}, key, value, interaction, rule, width, offset, direction, previous, return_to}: child_decrease(~A, ~E, child, rest, physical_width_proof_return_rank(~A, ~E, return_to))
    case Allocation.WidthComplete{result, Allocation.WidthRootReturn{}}: {==}
    case Allocation.WidthComplete{result, Allocation.WidthContainerReturn{key, value, interaction, rule, width, offset, direction, remaining, previous, parent}}: ProofGeometryProof.le_refl(Nat.add(2n, Nat.add(physical_width_proof_placement_work(~A, ~E, remaining), physical_width_proof_return_rank(~A, ~E, parent))))
    case Allocation.WidthDone{result}: {==}

# Match the actual computed plan before consuming its population evidence.

def planned_decrease(~A: Data, ~E: Data, +plan: Allocation.InlinePlan<A, E>, +children: +List<Model.Tree<A, E>>, +continuation: Nat,
  population: RulePhysicalSourceRules.InlinePopulation(~A, ~E, children, plan)) ->
  {Nat.is_le(Nat.add(plan_work(~A, ~E, plan), continuation),
    Nat.sub(Nat.add(Nat.add(4n, Allocation.width_forest_work(~A, ~E, children)), continuation), 1n)) == True{} : Bool}:
  match plan:
    case Allocation.InlineFailure{failure}: below_prefix(continuation, Nat.add(1n, Allocation.width_forest_work(~A, ~E, children)))
    case Allocation.InlinePlanned{placements, direction, canvas}: population_decrease(~A, ~E, placements, children, continuation, population)

def physical_width_proof_step_decrease(~A: Data, ~E: Data, +state: Allocation.WidthState<A, E>, +samples: +List<Model.HeightSample>) ->
  {Nat.is_le(physical_width_proof_rank(~A, ~E, Allocation.width_step(~A, ~E, state, samples)), Nat.sub(physical_width_proof_rank(~A, ~E, state), 1n)) == True{} : Bool}:
  match state:
    case Allocation.WidthVisit{tree, width, offset, return_to}: independent_decrease(~A, ~E, Allocation.WidthVisit{tree, width, offset, return_to}, samples)
    case Allocation.WidthMinimumChecked{False{}, tree, width, offset, rule, lower, return_to}: independent_decrease(~A, ~E, Allocation.WidthMinimumChecked{False{}, tree, width, offset, rule, lower, return_to}, samples)
    case Allocation.WidthMinimumChecked{True{}, Model.Leaf{key, value, interaction, rule, demand, height}, width, offset, checked_rule, lower, return_to}: independent_decrease(~A, ~E, Allocation.WidthMinimumChecked{True{}, Model.Leaf{key, value, interaction, rule, demand, height}, width, offset, checked_rule, lower, return_to}, samples)
    case Allocation.WidthMinimumChecked{True{}, Model.Container{+key, value, interaction, +rule, +children}, +width, offset, checked_rule, lower, return_to}:
      planned_decrease(~A, ~E,
        Allocation.prepare_inline_children(~A, ~E, key, rule, children, Nat.sub(width, Nat.mul(2n, Allocation.inline_inset(rule)))),
        children, physical_width_proof_return_rank(~A, ~E, return_to),
        ProofAllocationProof.inline_population(~A, ~E, key, rule, children, Nat.sub(width, Nat.mul(2n, Allocation.inline_inset(rule)))))
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
  {Nat.is_le(physical_width_proof_rank(~A, ~E, Allocation.WidthVisit{tree, width, offset, Allocation.WidthRootReturn{}}), Allocation.width_forest_work(~A, ~E, tree <> Nil{})) == True{} : Bool}:
  Equal.trans(Bool,
    Nat.is_le(Nat.add(visit_work(~A, ~E, tree), 0n), Allocation.width_forest_work(~A, ~E, tree <> Nil{})),
    Nat.is_le(visit_work(~A, ~E, tree), Allocation.width_forest_work(~A, ~E, tree <> Nil{})), True{},
    Equal.cong(Nat, Bool, (n => Nat.is_le(n, Allocation.width_forest_work(~A, ~E, tree <> Nil{}))),
      Nat.add(visit_work(~A, ~E, tree), 0n), visit_work(~A, ~E, tree), Alg.nat_add_zero(visit_work(~A, ~E, tree))), seed_in_budget(~A, ~E, tree))

def execution_rank(~A: Data, ~E: Data, execution: Allocation.WidthExecution<A, E>) -> Nat:
  physical_width_proof_rank(~A, ~E, Allocation.width_execution_state(~A, ~E, execution))

def execution_decrease(~A: Data, ~E: Data, execution: Allocation.WidthExecution<A, E>) ->
  {Nat.is_le(execution_rank(~A, ~E, Allocation.width_execution_step(~A, ~E, execution)), Nat.sub(execution_rank(~A, ~E, execution), 1n)) == True{} : Bool}:
  Allocation.WidthExecution{state, samples} = execution
  physical_width_proof_step_decrease(~A, ~E, state, samples)

def physical_width_proof_iteration_rank_zero(~A: Data, ~E: Data, +tree: Model.Tree<A, E>, +width: Nat, +offset: Nat, +samples: +List<Model.HeightSample>) ->
  {physical_width_proof_rank(~A, ~E, Allocation.iterate_width(~A, ~E, tree, width, offset, samples)) == 0n : Nat}:
  ProofAllocationProof.iterate_rank_zero(~Allocation.WidthExecution<A, E>, ~(execution => Allocation.width_execution_step(~A, ~E, execution)), ~(execution => execution_rank(~A, ~E, execution)),
    ~(+execution => execution_decrease(~A, ~E, execution)),
    Allocation.WidthExecution{Allocation.WidthVisit{tree, width, offset, Allocation.WidthRootReturn{}}, samples}, Allocation.width_forest_work(~A, ~E, tree <> Nil{}),
    initial_in_budget(~A, ~E, tree, width, offset))

def physical_width_proof_complete(~A: Data, ~E: Data, +tree: Model.Tree<A, E>, +width: Nat, +offset: Nat, +samples: +List<Model.HeightSample>) -> RulePhysicalSourceRules.width_complete_claim(~A, ~E, tree, width, offset, samples):
  Equal.trans(Bool,
    RulePhysicalSourceRules.width_completed(~A, ~E, Allocation.iterate_width(~A, ~E, tree, width, offset, samples)),
    Nat.is_eq(physical_width_proof_rank(~A, ~E, Allocation.iterate_width(~A, ~E, tree, width, offset, samples)), 0n), True{},
    Equal.sym(Bool, Nat.is_eq(physical_width_proof_rank(~A, ~E, Allocation.iterate_width(~A, ~E, tree, width, offset, samples)), 0n),
      RulePhysicalSourceRules.width_completed(~A, ~E, Allocation.iterate_width(~A, ~E, tree, width, offset, samples)),
      rank_zero_completed(~A, ~E, Allocation.iterate_width(~A, ~E, tree, width, offset, samples))),
    Equal.cong(Nat, Bool, (n => Nat.is_eq(n, 0n)), physical_width_proof_rank(~A, ~E, Allocation.iterate_width(~A, ~E, tree, width, offset, samples)), 0n,
      physical_width_proof_iteration_rank_zero(~A, ~E, tree, width, offset, samples)))

def RulePhysicalSourceRules.width_evidence(A, E):
  RulePhysicalSourceRules.WidthRequirements{+tree => +width => +offset => +samples => physical_width_proof_complete(~A, ~E, tree, width, offset, samples)}

# Continuations reconstruct the successful source from fields consumed by the
# next production transition. The accumulated results retain their original order.

def placement_sources(~A: Data, ~E: Data, placements: +List<Space.Placement<Allocation.MeasuredTree<A, E>>>) -> +List<Model.Tree<A, E>>:
  Allocation.source_forest_measured(~A, ~E, Rule.placement_values(~Allocation.MeasuredTree<A, E>, placements))

def physical_height_source_proof_outcome_source(~A: Data, ~E: Data, result: Allocation.PositionedOutcome<A, E>) -> Maybe<&2, Model.Tree<A, E>>:
  match result:
    case Allocation.Positioned{tree}: Some{Allocation.source_of_allocated(~A, ~E, tree)}
    case Allocation.PositionFailure{failure}: None{}

def physical_height_source_proof_cons_source(~A: Data, ~E: Data, first: Maybe<&2, Model.Tree<A, E>>, rest: Maybe<&2, +List<Model.Tree<A, E>>>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  match first rest:
    case Some{tree} Some{trees}: Some{tree <> trees}
    case _ _: None{}

def physical_height_source_proof_outcome_sources(~A: Data, ~E: Data, values: +List<Allocation.PositionedOutcome<A, E>>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  match values:
    case Nil{}: Some{Nil{}}
    case Con{first, rest}: physical_height_source_proof_cons_source(~A, ~E, physical_height_source_proof_outcome_source(~A, ~E, first), physical_height_source_proof_outcome_sources(~A, ~E, rest))

def physical_height_source_proof_append_source(~A: Data, ~E: Data, previous: Maybe<&2, +List<Model.Tree<A, E>>>, remaining: +List<Model.Tree<A, E>>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  match previous:
    case None{}: None{}
    case Some{values}: Some{List.append(&2, Model.Tree<A, E>, values, remaining)}

def physical_height_source_proof_container_source(~A: Data, ~E: Data, key: String, value: A, interaction: Model.Interaction<E>, rule: Model.Rule, children: Maybe<&2, +List<Model.Tree<A, E>>>) -> Maybe<&2, Model.Tree<A, E>>:
  match children:
    case None{}: None{}
    case Some{values}: Some{Model.Container{key, value, interaction, rule, values}}

def physical_height_source_proof_child_sources_from_erased(~A: Data, ~E: Data, current: Maybe<&2, Model.Tree<A, E>>, previous: Maybe<&2, +List<Model.Tree<A, E>>>, remaining: +List<Space.Placement<Allocation.MeasuredTree<A, E>>>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  match current:
    case None{}: None{}
    case Some{tree}: physical_height_source_proof_append_source(~A, ~E, previous, tree <> placement_sources(~A, ~E, remaining))

def physical_height_source_proof_child_sources(~A: Data, ~E: Data, previous: +List<Allocation.PositionedOutcome<A, E>>, current: Maybe<&2, Model.Tree<A, E>>, remaining: +List<Space.Placement<Allocation.MeasuredTree<A, E>>>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  physical_height_source_proof_child_sources_from_erased(~A, ~E, current, physical_height_source_proof_outcome_sources(~A, ~E, previous), remaining)

def physical_height_source_proof_return_source(~A: Data, ~E: Data, return_to: Allocation.HeightReturn<A, E>, current: Maybe<&2, Model.Tree<A, E>>) -> Maybe<&2, Model.Tree<A, E>>:
  match return_to:
    case Allocation.HeightRootReturn{}: current
    case Allocation.HeightContainerReturn{key, value, interaction, rule, bounds, canvas, direction, content_left, content_top, remaining, previous, parent}:
      physical_height_source_proof_return_source(~A, ~E, parent, physical_height_source_proof_container_source(~A, ~E, key, value, interaction, rule, physical_height_source_proof_child_sources(~A, ~E, previous, current, remaining)))

def physical_height_source_proof_plan_source(~A: Data, ~E: Data, plan: Allocation.ChildPlan<Allocation.MeasuredTree<A, E>>, key: String, value: A, interaction: Model.Interaction<E>, rule: Model.Rule) -> Maybe<&2, Model.Tree<A, E>>:
  match plan:
    case Allocation.PlanningFailure{failure}: None{}
    case Allocation.ChildrenPlanned{placements, canvas}:
      Some{Model.Container{key, value, interaction, rule, placement_sources(~A, ~E, placements)}}

def physical_height_source_proof_state_source(~A: Data, ~E: Data, state: Allocation.HeightState<A, E>) -> Maybe<&2, Model.Tree<A, E>>:
  match state:
    case Allocation.HeightVisit{tree, bounds, parent}: physical_height_source_proof_return_source(~A, ~E, parent, Some{Allocation.source_of_measured(~A, ~E, tree)})
    case Allocation.HeightMinimumChecked{False{}, tree, bounds, lower, parent}: physical_height_source_proof_return_source(~A, ~E, parent, None{})
    case Allocation.HeightMinimumChecked{True{}, tree, bounds, lower, parent}: physical_height_source_proof_return_source(~A, ~E, parent, Some{Allocation.source_of_measured(~A, ~E, tree)})
    case Allocation.HeightContainerPlan{plan, key, value, interaction, rule, bounds, children, direction, inner_width, left, top, parent}:
      physical_height_source_proof_return_source(~A, ~E, parent, physical_height_source_proof_plan_source(~A, ~E, plan, key, value, interaction, rule))
    case Allocation.HeightChildren{remaining, key, value, interaction, rule, bounds, canvas, direction, content_left, content_top, previous, parent}:
      physical_height_source_proof_return_source(~A, ~E, parent, physical_height_source_proof_container_source(~A, ~E, key, value, interaction, rule,
        physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, previous), placement_sources(~A, ~E, remaining))))
    case Allocation.HeightComplete{result, parent}: physical_height_source_proof_return_source(~A, ~E, parent, physical_height_source_proof_outcome_source(~A, ~E, result))
    case Allocation.HeightDone{result}: physical_height_source_proof_outcome_source(~A, ~E, result)

def physical_height_source_proof_partial_match(~A: Data, ~E: Data, actual: Maybe<&2, Model.Tree<A, E>>, expected: Model.Tree<A, E>) -> Type:
  match actual:
    case None{}: {True{} == True{} : Bool}
    case Some{source}: {source == expected : Model.Tree<A, E>}

def physical_height_source_proof_return_none(~A: Data, ~E: Data, parent: Allocation.HeightReturn<A, E>) ->
  {physical_height_source_proof_return_source(~A, ~E, parent, None{}) == None{} : Maybe<&2, Model.Tree<A, E>>}:
  match parent:
    case Allocation.HeightRootReturn{}: {==}
    case Allocation.HeightContainerReturn{key, value, interaction, rule, bounds, canvas, direction, content_left, content_top, remaining, previous, rest}:
      physical_height_source_proof_return_none(~A, ~E, rest)

def physical_height_source_proof_return_drop(~A: Data, ~E: Data, +parent: Allocation.HeightReturn<A, E>, +expected: Model.Tree<A, E>) ->
  physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_return_source(~A, ~E, parent, None{}), expected):
  Std.transport(Maybe<&2, Model.Tree<A, E>>, None{},
    (actual => physical_height_source_proof_partial_match(~A, ~E, actual, expected)), {==},
    physical_height_source_proof_return_source(~A, ~E, parent, None{}), physical_height_source_proof_return_none(~A, ~E, parent))

def physical_height_source_proof_return_same(~A: Data, ~E: Data, +parent: Allocation.HeightReturn<A, E>, +actual: Model.Tree<A, E>, +source: Model.Tree<A, E>, +expected: Model.Tree<A, E>,
  same: {actual == source : Model.Tree<A, E>},
  proof: physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_return_source(~A, ~E, parent, Some{source}), expected)) ->
  physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_return_source(~A, ~E, parent, Some{actual}), expected):
  Std.transport(Model.Tree<A, E>, source,
    (tree => physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_return_source(~A, ~E, parent, Some{tree}), expected)),
    proof, actual, same)

def allocated_children_source(~A: Data, ~E: Data, children: Allocation.AllocatedChildren<A, E>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  match children:
    case Allocation.AllocationFailed{failure}: None{}
    case Allocation.ChildrenAllocated{trees}: Some{Allocation.source_forest_allocated(~A, ~E, trees)}

def physical_height_source_proof_merge_source(~A: Data, ~E: Data, +first: Allocation.PositionedOutcome<A, E>, +rest: Allocation.AllocatedChildren<A, E>) ->
  {allocated_children_source(~A, ~E, Allocation.merge_allocation(~A, ~E, first, rest)) ==
    physical_height_source_proof_cons_source(~A, ~E, physical_height_source_proof_outcome_source(~A, ~E, first), allocated_children_source(~A, ~E, rest)) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match first rest:
    case Allocation.PositionFailure{failure} _: {==}
    case Allocation.Positioned{tree} Allocation.AllocationFailed{failure}: {==}
    case Allocation.Positioned{Allocation.AllocatedLeaf{key, value, interaction, rule, demand, height, bounds, canvas}} Allocation.ChildrenAllocated{trees}: {==}
    case Allocation.Positioned{Allocation.AllocatedContainer{key, value, interaction, rule, bounds, canvas, direction, children}} Allocation.ChildrenAllocated{trees}: {==}

def physical_height_source_proof_collected_source(~A: Data, ~E: Data, +values: +List<Allocation.PositionedOutcome<A, E>>) ->
  {allocated_children_source(~A, ~E, Allocation.collect_positioned_outcomes(~A, ~E, values)) ==
    physical_height_source_proof_outcome_sources(~A, ~E, values) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match values:
    case Nil{}: {==}
    case Con{+first, +rest}:
      Equal.trans(Maybe<&2, +List<Model.Tree<A, E>>>,
        allocated_children_source(~A, ~E, Allocation.merge_allocation(~A, ~E, first, Allocation.collect_positioned_outcomes(~A, ~E, rest))),
        physical_height_source_proof_cons_source(~A, ~E, physical_height_source_proof_outcome_source(~A, ~E, first), allocated_children_source(~A, ~E, Allocation.collect_positioned_outcomes(~A, ~E, rest))),
        physical_height_source_proof_cons_source(~A, ~E, physical_height_source_proof_outcome_source(~A, ~E, first), physical_height_source_proof_outcome_sources(~A, ~E, rest)),
        physical_height_source_proof_merge_source(~A, ~E, first, Allocation.collect_positioned_outcomes(~A, ~E, rest)),
        Equal.cong(Maybe<&2, +List<Model.Tree<A, E>>>, Maybe<&2, +List<Model.Tree<A, E>>>,
          (trees => physical_height_source_proof_cons_source(~A, ~E, physical_height_source_proof_outcome_source(~A, ~E, first), trees)),
          allocated_children_source(~A, ~E, Allocation.collect_positioned_outcomes(~A, ~E, rest)), physical_height_source_proof_outcome_sources(~A, ~E, rest), physical_height_source_proof_collected_source(~A, ~E, rest)))

def physical_height_source_proof_append_empty(~A: Data, ~E: Data, +values: Maybe<&2, +List<Model.Tree<A, E>>>) ->
  {physical_height_source_proof_append_source(~A, ~E, values, Nil{}) == values : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match values:
    case None{}: {==}
    case Some{+trees}:
      Equal.cong(+List<Model.Tree<A, E>>, Maybe<&2, +List<Model.Tree<A, E>>>,
        (children => Some{children}), List.append(&2, Model.Tree<A, E>, trees, Nil{}), trees, Std.app_nil_r(Model.Tree<A, E>, trees))

def physical_height_source_proof_append_cons(~A: Data, ~E: Data, +first: Maybe<&2, Model.Tree<A, E>>, +rest: Maybe<&2, +List<Model.Tree<A, E>>>, +remaining: +List<Model.Tree<A, E>>) ->
  {physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_cons_source(~A, ~E, first, rest), remaining) ==
    physical_height_source_proof_cons_source(~A, ~E, first, physical_height_source_proof_append_source(~A, ~E, rest, remaining)) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match first rest:
    case None{} _: {==}
    case Some{tree} None{}: {==}
    case Some{tree} Some{trees}: {==}

def physical_height_source_proof_child_cons(~A: Data, ~E: Data, +first: Maybe<&2, Model.Tree<A, E>>, +rest: Maybe<&2, +List<Model.Tree<A, E>>>, +current: Maybe<&2, Model.Tree<A, E>>, +remaining: +List<Space.Placement<Allocation.MeasuredTree<A, E>>>) ->
  {physical_height_source_proof_cons_source(~A, ~E, first, physical_height_source_proof_child_sources_from_erased(~A, ~E, current, rest, remaining)) ==
    physical_height_source_proof_child_sources_from_erased(~A, ~E, current, physical_height_source_proof_cons_source(~A, ~E, first, rest), remaining) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match first current:
    case None{} None{}: {==}
    case Some{tree} None{}: {==}
    case _ Some{tree}: Equal.sym(Maybe<&2, +List<Model.Tree<A, E>>>,
      physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_cons_source(~A, ~E, first, rest), tree <> placement_sources(~A, ~E, remaining)),
      physical_height_source_proof_cons_source(~A, ~E, first, physical_height_source_proof_append_source(~A, ~E, rest, tree <> placement_sources(~A, ~E, remaining))),
      physical_height_source_proof_append_cons(~A, ~E, first, rest, tree <> placement_sources(~A, ~E, remaining)))

def physical_height_source_proof_append_current_cons(~A: Data, ~E: Data, +first: Maybe<&2, Model.Tree<A, E>>, +rest: +List<Allocation.PositionedOutcome<A, E>>, +current: Allocation.PositionedOutcome<A, E>, +remaining: +List<Space.Placement<Allocation.MeasuredTree<A, E>>>,
  same: {physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.PositionedOutcome<A, E>, rest, current <> Nil{})), placement_sources(~A, ~E, remaining)) ==
    physical_height_source_proof_child_sources(~A, ~E, rest, physical_height_source_proof_outcome_source(~A, ~E, current), remaining) : Maybe<&2, +List<Model.Tree<A, E>>>}) ->
  {physical_height_source_proof_cons_source(~A, ~E, first, physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.PositionedOutcome<A, E>, rest, current <> Nil{})), placement_sources(~A, ~E, remaining))) ==
    physical_height_source_proof_child_sources_from_erased(~A, ~E, physical_height_source_proof_outcome_source(~A, ~E, current), physical_height_source_proof_cons_source(~A, ~E, first, physical_height_source_proof_outcome_sources(~A, ~E, rest)), remaining) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  Equal.trans(Maybe<&2, +List<Model.Tree<A, E>>>,
    physical_height_source_proof_cons_source(~A, ~E, first, physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.PositionedOutcome<A, E>, rest, current <> Nil{})), placement_sources(~A, ~E, remaining))),
    physical_height_source_proof_cons_source(~A, ~E, first, physical_height_source_proof_child_sources(~A, ~E, rest, physical_height_source_proof_outcome_source(~A, ~E, current), remaining)),
    physical_height_source_proof_child_sources_from_erased(~A, ~E, physical_height_source_proof_outcome_source(~A, ~E, current), physical_height_source_proof_cons_source(~A, ~E, first, physical_height_source_proof_outcome_sources(~A, ~E, rest)), remaining),
    Equal.cong(Maybe<&2, +List<Model.Tree<A, E>>>, Maybe<&2, +List<Model.Tree<A, E>>>, (trees => physical_height_source_proof_cons_source(~A, ~E, first, trees)),
      physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.PositionedOutcome<A, E>, rest, current <> Nil{})), placement_sources(~A, ~E, remaining)), physical_height_source_proof_child_sources(~A, ~E, rest, physical_height_source_proof_outcome_source(~A, ~E, current), remaining), same),
    physical_height_source_proof_child_cons(~A, ~E, first, physical_height_source_proof_outcome_sources(~A, ~E, rest), physical_height_source_proof_outcome_source(~A, ~E, current), remaining))

def physical_height_source_proof_append_current(~A: Data, ~E: Data, +previous: +List<Allocation.PositionedOutcome<A, E>>, +current: Allocation.PositionedOutcome<A, E>, +remaining: +List<Space.Placement<Allocation.MeasuredTree<A, E>>>) ->
  {physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.PositionedOutcome<A, E>, previous, current <> Nil{})), placement_sources(~A, ~E, remaining)) ==
    physical_height_source_proof_child_sources(~A, ~E, previous, physical_height_source_proof_outcome_source(~A, ~E, current), remaining) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match previous current:
    case Nil{} Allocation.Positioned{tree}: {==}
    case Nil{} Allocation.PositionFailure{failure}: {==}
    case Con{+first, +rest} +current:
      Equal.trans(Maybe<&2, +List<Model.Tree<A, E>>>,
        physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_cons_source(~A, ~E, physical_height_source_proof_outcome_source(~A, ~E, first), physical_height_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.PositionedOutcome<A, E>, rest, current <> Nil{}))), placement_sources(~A, ~E, remaining)),
        physical_height_source_proof_cons_source(~A, ~E, physical_height_source_proof_outcome_source(~A, ~E, first), physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.PositionedOutcome<A, E>, rest, current <> Nil{})), placement_sources(~A, ~E, remaining))),
        physical_height_source_proof_child_sources(~A, ~E, first <> rest, physical_height_source_proof_outcome_source(~A, ~E, current), remaining),
        physical_height_source_proof_append_cons(~A, ~E, physical_height_source_proof_outcome_source(~A, ~E, first), physical_height_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.PositionedOutcome<A, E>, rest, current <> Nil{})), placement_sources(~A, ~E, remaining)),
        physical_height_source_proof_append_current_cons(~A, ~E, physical_height_source_proof_outcome_source(~A, ~E, first), rest, current, remaining, physical_height_source_proof_append_current(~A, ~E, rest, current, remaining)))

def physical_height_source_proof_return_option(~A: Data, ~E: Data, +actual: Maybe<&2, Model.Tree<A, E>>, +source: Model.Tree<A, E>, +parent: Allocation.HeightReturn<A, E>, +expected: Model.Tree<A, E>,
  same: physical_height_source_proof_partial_match(~A, ~E, actual, source),
  proof: physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_return_source(~A, ~E, parent, Some{source}), expected)) ->
  physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_return_source(~A, ~E, parent, actual), expected):
  match actual:
    case None{}: physical_height_source_proof_return_drop(~A, ~E, parent, expected)
    case Some{tree}: physical_height_source_proof_return_same(~A, ~E, parent, tree, source, expected, same, proof)

def physical_height_source_proof_checked_preserved(~A: Data, ~E: Data, +fits: Bool, +tree: Allocation.MeasuredTree<A, E>, +bounds: SpatialModel.Box, +lower: Nat, +parent: Allocation.HeightReturn<A, E>, +expected: Model.Tree<A, E>,
  proof: physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_return_source(~A, ~E, parent, Some{Allocation.source_of_measured(~A, ~E, tree)}), expected)) ->
  physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_state_source(~A, ~E, Allocation.HeightMinimumChecked{fits, tree, bounds, lower, parent}), expected):
  match fits:
    case False{}: physical_height_source_proof_return_drop(~A, ~E, parent, expected)
    case True{}: proof

def physical_height_source_proof_plan_preserved(~A: Data, ~E: Data, +plan: Allocation.ChildPlan<Allocation.MeasuredTree<A, E>>, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +children: +List<Allocation.MeasuredTree<A, E>>,
  population: RulePhysicalSourceRules.BlockPopulation(~A, ~E, children, plan)) ->
  physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_plan_source(~A, ~E, plan, key, value, interaction, rule), Model.Container{key, value, interaction, rule, Allocation.source_forest_measured(~A, ~E, children)}):
  match plan:
    case Allocation.PlanningFailure{failure}: {==}
    case Allocation.ChildrenPlanned{placements, canvas}:
      Equal.cong(+List<Allocation.MeasuredTree<A, E>>, Model.Tree<A, E>,
        (trees => Model.Container{key, value, interaction, rule, Allocation.source_forest_measured(~A, ~E, trees)}),
        Rule.placement_values(~Allocation.MeasuredTree<A, E>, placements), children, population)

def physical_height_source_proof_finish_children_source(~A: Data, ~E: Data, +result: Allocation.AllocatedChildren<A, E>, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +bounds: SpatialModel.Box, +canvas: E.Extent, +direction: Allocation.ResolvedDirection) ->
  {physical_height_source_proof_outcome_source(~A, ~E, Allocation.allocated_container(~A, ~E, key, value, interaction, rule, bounds, canvas, direction, result)) ==
    physical_height_source_proof_container_source(~A, ~E, key, value, interaction, rule, allocated_children_source(~A, ~E, result)) : Maybe<&2, Model.Tree<A, E>>}:
  match result:
    case Allocation.AllocationFailed{failure}: {==}
    case Allocation.ChildrenAllocated{trees}: {==}

def physical_height_source_proof_finish_source(~A: Data, ~E: Data, +previous: +List<Allocation.PositionedOutcome<A, E>>, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +bounds: SpatialModel.Box, +canvas: E.Extent, +direction: Allocation.ResolvedDirection) ->
  {physical_height_source_proof_outcome_source(~A, ~E, Allocation.allocated_container(~A, ~E, key, value, interaction, rule, bounds, canvas, direction, Allocation.collect_positioned_outcomes(~A, ~E, previous))) ==
    physical_height_source_proof_container_source(~A, ~E, key, value, interaction, rule, physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, previous), Nil{})) : Maybe<&2, Model.Tree<A, E>>}:
  Equal.trans(Maybe<&2, Model.Tree<A, E>>,
    physical_height_source_proof_outcome_source(~A, ~E, Allocation.allocated_container(~A, ~E, key, value, interaction, rule, bounds, canvas, direction, Allocation.collect_positioned_outcomes(~A, ~E, previous))),
    physical_height_source_proof_container_source(~A, ~E, key, value, interaction, rule, allocated_children_source(~A, ~E, Allocation.collect_positioned_outcomes(~A, ~E, previous))),
    physical_height_source_proof_container_source(~A, ~E, key, value, interaction, rule, physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, previous), Nil{})),
    physical_height_source_proof_finish_children_source(~A, ~E, Allocation.collect_positioned_outcomes(~A, ~E, previous), key, value, interaction, rule, bounds, canvas, direction),
    Equal.cong(Maybe<&2, +List<Model.Tree<A, E>>>, Maybe<&2, Model.Tree<A, E>>,
      (trees => physical_height_source_proof_container_source(~A, ~E, key, value, interaction, rule, trees)),
      allocated_children_source(~A, ~E, Allocation.collect_positioned_outcomes(~A, ~E, previous)), physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, previous), Nil{}),
      Equal.trans(Maybe<&2, +List<Model.Tree<A, E>>>,
        allocated_children_source(~A, ~E, Allocation.collect_positioned_outcomes(~A, ~E, previous)), physical_height_source_proof_outcome_sources(~A, ~E, previous), physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, previous), Nil{}),
        physical_height_source_proof_collected_source(~A, ~E, previous), Equal.sym(Maybe<&2, +List<Model.Tree<A, E>>>, physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, previous), Nil{}), physical_height_source_proof_outcome_sources(~A, ~E, previous), physical_height_source_proof_append_empty(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, previous))))))

def physical_height_source_proof_state_same(~A: Data, ~E: Data, +before: Maybe<&2, Model.Tree<A, E>>, +after: Maybe<&2, Model.Tree<A, E>>, +expected: Model.Tree<A, E>,
  same: {after == before : Maybe<&2, Model.Tree<A, E>>}, proof: physical_height_source_proof_partial_match(~A, ~E, before, expected)) -> physical_height_source_proof_partial_match(~A, ~E, after, expected):
  Std.transport(Maybe<&2, Model.Tree<A, E>>, before, (source => physical_height_source_proof_partial_match(~A, ~E, source, expected)), proof, after, same)

def leaf_demand_same(~A: Data, ~E: Data, +demand: Space.Demand, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +height: Model.Height, +bounds: SpatialModel.Box, +content_height: Nat, +inner_width: Nat, +inner_height: Nat) ->
  {physical_height_source_proof_outcome_source(~A, ~E, Allocation.allocate_leaf_demand(~A, ~E, demand, key, value, interaction, rule, height, bounds, content_height, inner_width, inner_height)) == Some{Model.Leaf{key, value, interaction, rule, demand, height}} : Maybe<&2, Model.Tree<A, E>>}:
  match demand:
    case Space.Demand{E.Extent{min_width, min_height}, preferred}: {==}

def leaf_same(~A: Data, ~E: Data, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +demand: Space.Demand, +height: Model.Height, +bounds: SpatialModel.Box, +content_height: Nat) ->
  {physical_height_source_proof_outcome_source(~A, ~E, Allocation.allocated_leaf(~A, ~E, key, value, interaction, rule, demand, height, bounds, content_height)) == Some{Model.Leaf{key, value, interaction, rule, demand, height}} : Maybe<&2, Model.Tree<A, E>>}:
  match bounds:
    case SpatialModel.Box{left, top, +width, +block_height}:
      leaf_demand_same(~A, ~E, demand, key, value, interaction, rule, height, SpatialModel.Box{left, top, width, block_height}, content_height,
        Nat.sub(width, Nat.mul(2n, Allocation.axis_inset(Allocation.InlineAxis{}, rule))), Nat.sub(block_height, Nat.mul(2n, Allocation.axis_inset(Allocation.BlockAxis{}, rule))))

def physical_height_source_proof_step_preserved(~A: Data, ~E: Data, +state: Allocation.HeightState<A, E>, +expected: Model.Tree<A, E>,
  proof: physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_state_source(~A, ~E, state), expected)) ->
  physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_state_source(~A, ~E, Allocation.height_step(~A, ~E, state)), expected):
  match state:
    case Allocation.HeightVisit{+tree, +bounds, +parent}:
      physical_height_source_proof_checked_preserved(~A, ~E, Nat.is_le(Allocation.axis_extent(Allocation.BlockAxis{}, Model.minimum_demand(Allocation.measured_demand(~A, ~E, tree))), Allocation.box_height(bounds)), tree, bounds,
        Allocation.axis_extent(Allocation.BlockAxis{}, Model.minimum_demand(Allocation.measured_demand(~A, ~E, tree))), parent, expected, proof)
    case Allocation.HeightMinimumChecked{False{}, tree, bounds, lower, parent}: proof
    case Allocation.HeightMinimumChecked{True{}, Allocation.MeasuredLeaf{+key, +value, +interaction, +rule, +demand, +height, outer_width, inline_offset, +content_height}, +bounds, lower, +parent}:
      physical_height_source_proof_state_same(~A, ~E, physical_height_source_proof_return_source(~A, ~E, parent, Some{Model.Leaf{key, value, interaction, rule, demand, height}}),
        physical_height_source_proof_return_source(~A, ~E, parent, physical_height_source_proof_outcome_source(~A, ~E, Allocation.allocated_leaf(~A, ~E, key, value, interaction, rule, demand, height, bounds, content_height))), expected,
        Equal.cong(Maybe<&2, Model.Tree<A, E>>, Maybe<&2, Model.Tree<A, E>>, (source => physical_height_source_proof_return_source(~A, ~E, parent, source)),
          physical_height_source_proof_outcome_source(~A, ~E, Allocation.allocated_leaf(~A, ~E, key, value, interaction, rule, demand, height, bounds, content_height)), Some{Model.Leaf{key, value, interaction, rule, demand, height}},
          leaf_same(~A, ~E, key, value, interaction, rule, demand, height, bounds, content_height)), proof)
    case Allocation.HeightMinimumChecked{True{}, Allocation.MeasuredContainer{+key, +value, +interaction, +rule, outer_width, inline_offset, +direction, +children}, SpatialModel.Box{+left, +top, +width, +offered_height}, lower, +parent}:
      physical_height_source_proof_return_option(~A, ~E,
        physical_height_source_proof_plan_source(~A, ~E, Allocation.prepare_block_children(~A, ~E, key, rule, direction, children, Nat.sub(offered_height, Nat.mul(2n, Allocation.block_inset(rule)))), key, value, interaction, rule),
        Model.Container{key, value, interaction, rule, Allocation.source_forest_measured(~A, ~E, children)}, parent, expected,
        physical_height_source_proof_plan_preserved(~A, ~E, Allocation.prepare_block_children(~A, ~E, key, rule, direction, children, Nat.sub(offered_height, Nat.mul(2n, Allocation.block_inset(rule)))), key, value, interaction, rule, children,
          ProofAllocationProof.block_population(~A, ~E, key, rule, direction, children, Nat.sub(offered_height, Nat.mul(2n, Allocation.block_inset(rule))))), proof)
    case Allocation.HeightContainerPlan{Allocation.PlanningFailure{failure}, key, value, interaction, rule, bounds, children, direction, inner_width, left, top, parent}: proof
    case Allocation.HeightContainerPlan{Allocation.ChildrenPlanned{placements, canvas_height}, key, value, interaction, rule, bounds, children, direction, inner_width, left, top, parent}: proof
    case Allocation.HeightChildren{Nil{}, +key, +value, +interaction, +rule, +bounds, +canvas, +direction, +content_left, +content_top, +previous, +parent}:
      physical_height_source_proof_state_same(~A, ~E,
        physical_height_source_proof_state_source(~A, ~E, Allocation.HeightChildren{Nil{}, key, value, interaction, rule, bounds, canvas, direction, content_left, content_top, previous, parent}),
        physical_height_source_proof_state_source(~A, ~E, Allocation.height_step(~A, ~E, Allocation.HeightChildren{Nil{}, key, value, interaction, rule, bounds, canvas, direction, content_left, content_top, previous, parent})), expected,
        Equal.cong(Maybe<&2, Model.Tree<A, E>>, Maybe<&2, Model.Tree<A, E>>, (source => physical_height_source_proof_return_source(~A, ~E, parent, source)),
          physical_height_source_proof_outcome_source(~A, ~E, Allocation.allocated_container(~A, ~E, key, value, interaction, rule, bounds, canvas, direction, Allocation.collect_positioned_outcomes(~A, ~E, previous))),
          physical_height_source_proof_container_source(~A, ~E, key, value, interaction, rule, physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, previous), Nil{})), physical_height_source_proof_finish_source(~A, ~E, previous, key, value, interaction, rule, bounds, canvas, direction)), proof)
    case Allocation.HeightChildren{Con{Space.Placement{Allocation.MeasuredLeaf{child_key, child_value, child_interaction, child_rule, demand, height, outer_width, inline_offset, content_height}, child_offset, extent}, rest}, key, value, interaction, rule, bounds, canvas, direction, content_left, content_top, previous, parent}: proof
    case Allocation.HeightChildren{Con{Space.Placement{Allocation.MeasuredContainer{child_key, child_value, child_interaction, child_rule, outer_width, inline_offset, child_direction, children}, child_offset, extent}, rest}, key, value, interaction, rule, bounds, canvas, direction, content_left, content_top, previous, parent}: proof
    case Allocation.HeightComplete{result, Allocation.HeightRootReturn{}}: proof
    case Allocation.HeightComplete{+result, Allocation.HeightContainerReturn{+key, +value, +interaction, +rule, bounds, canvas, direction, content_left, content_top, +remaining, +previous, +parent}}:
      physical_height_source_proof_state_same(~A, ~E,
        physical_height_source_proof_return_source(~A, ~E, parent, physical_height_source_proof_container_source(~A, ~E, key, value, interaction, rule, physical_height_source_proof_child_sources(~A, ~E, previous, physical_height_source_proof_outcome_source(~A, ~E, result), remaining))),
        physical_height_source_proof_return_source(~A, ~E, parent, physical_height_source_proof_container_source(~A, ~E, key, value, interaction, rule, physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.PositionedOutcome<A, E>, previous, result <> Nil{})), placement_sources(~A, ~E, remaining)))), expected,
        Equal.cong(Maybe<&2, +List<Model.Tree<A, E>>>, Maybe<&2, Model.Tree<A, E>>,
          (children => physical_height_source_proof_return_source(~A, ~E, parent, physical_height_source_proof_container_source(~A, ~E, key, value, interaction, rule, children))),
          physical_height_source_proof_append_source(~A, ~E, physical_height_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.PositionedOutcome<A, E>, previous, result <> Nil{})), placement_sources(~A, ~E, remaining)),
          physical_height_source_proof_child_sources(~A, ~E, previous, physical_height_source_proof_outcome_source(~A, ~E, result), remaining), physical_height_source_proof_append_current(~A, ~E, previous, result, remaining)), proof)
    case Allocation.HeightDone{result}: proof

def physical_height_source_proof_iterate_preserved(~A: Data, ~E: Data, +budget: Nat, +state: Allocation.HeightState<A, E>, +expected: Model.Tree<A, E>,
  proof: physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_state_source(~A, ~E, state), expected)) ->
  physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_state_source(~A, ~E, Std.iter(~Allocation.HeightState<A, E>, ~(value => Allocation.height_step(~A, ~E, value)), budget, state)), expected):
  Std.nat_ind(~(n => @+seed:Allocation.HeightState<A, E> -> @+source:Model.Tree<A, E> ->
    @initial:physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_state_source(~A, ~E, seed), source) ->
    physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_state_source(~A, ~E, Std.iter(~Allocation.HeightState<A, E>, ~(value => Allocation.height_step(~A, ~E, value)), n, seed)), source)),
    ~(+seed => +source => initial => initial),
    ~(+n => induction => +seed => +source => initial => physical_height_source_proof_step_preserved(~A, ~E,
      Std.iter(~Allocation.HeightState<A, E>, ~(value => Allocation.height_step(~A, ~E, value)), n, seed), source, induction(seed, source, initial))), budget)(state, expected, proof)

def physical_height_source_proof_finish_completed(~A: Data, ~E: Data, +state: Allocation.HeightState<A, E>, +key: String, +height: Nat, +budget: Nat, +expected: Model.Tree<A, E>,
  complete: {RulePhysicalSourceRules.height_completed(~A, ~E, state) == True{} : Bool},
  proof: physical_height_source_proof_partial_match(~A, ~E, physical_height_source_proof_state_source(~A, ~E, state), expected)) ->
  RulePhysicalSourceRules.height_source_source_claim(~A, ~E, expected, Allocation.finish_height_iteration(~A, ~E, state, key, height, budget)):
  match state:
    case Allocation.HeightDone{Allocation.Positioned{tree}}: proof
    case Allocation.HeightDone{Allocation.PositionFailure{failure}}: {==}
    case Allocation.HeightVisit{tree, bounds, parent}: Logic.impossible(RulePhysicalSourceRules.height_source_source_claim(~A, ~E, expected, Allocation.PositionFailure{Allocation.Failure{key, Allocation.BlockAxis{}, budget, height, Allocation.AllocationBoundExceeded{budget}}}), complete)
    case Allocation.HeightMinimumChecked{fits, tree, bounds, lower, parent}: Logic.impossible(RulePhysicalSourceRules.height_source_source_claim(~A, ~E, expected, Allocation.PositionFailure{Allocation.Failure{key, Allocation.BlockAxis{}, budget, height, Allocation.AllocationBoundExceeded{budget}}}), complete)
    case Allocation.HeightContainerPlan{plan, key, value, interaction, rule, bounds, children, direction, inner_width, left, top, parent}: Logic.impossible(RulePhysicalSourceRules.height_source_source_claim(~A, ~E, expected, Allocation.PositionFailure{Allocation.Failure{key, Allocation.BlockAxis{}, budget, height, Allocation.AllocationBoundExceeded{budget}}}), complete)
    case Allocation.HeightChildren{remaining, key, value, interaction, rule, bounds, canvas, direction, content_left, content_top, previous, parent}: Logic.impossible(RulePhysicalSourceRules.height_source_source_claim(~A, ~E, expected, Allocation.PositionFailure{Allocation.Failure{key, Allocation.BlockAxis{}, budget, height, Allocation.AllocationBoundExceeded{budget}}}), complete)
    case Allocation.HeightComplete{result, parent}: Logic.impossible(RulePhysicalSourceRules.height_source_source_claim(~A, ~E, expected, Allocation.PositionFailure{Allocation.Failure{key, Allocation.BlockAxis{}, budget, height, Allocation.AllocationBoundExceeded{budget}}}), complete)

def physical_height_source_proof_preserved(~A: Data, ~E: Data, +tree: Allocation.MeasuredTree<A, E>, +bounds: SpatialModel.Box) ->
  RulePhysicalSourceRules.height_source_source_claim(~A, ~E, Allocation.source_of_measured(~A, ~E, tree), Allocation.allocate_measured(~A, ~E, tree, bounds)):
  physical_height_source_proof_finish_completed(~A, ~E, Allocation.iterate_height(~A, ~E, tree, bounds), Allocation.measured_key(~A, ~E, tree), Allocation.box_height(bounds),
    Allocation.height_forest_work(~A, ~E, tree <> Nil{}), Allocation.source_of_measured(~A, ~E, tree),
    physical_height_proof_complete(~A, ~E, tree, bounds),
    physical_height_source_proof_iterate_preserved(~A, ~E, Allocation.height_forest_work(~A, ~E, tree <> Nil{}), Allocation.HeightVisit{tree, bounds, Allocation.HeightRootReturn{}}, Allocation.source_of_measured(~A, ~E, tree), {==}))

def RulePhysicalSourceRules.height_source_evidence(A, E):
  RulePhysicalSourceRules.HeightSourceRequirements{+tree => +bounds => physical_height_source_proof_preserved(~A, ~E, tree, bounds)}

def production(+engine: World.Engine) -> RuleContract.production_claim(engine):
  match engine:
    case World.Engine{snapshot, viewport, observations, viewports, status}: {==}

def physical_width_source_proof_outcome_source(~A: Data, ~E: Data, result: Allocation.WidthOutcome<A, E>) -> Maybe<&2, Model.Tree<A, E>>:
  match result:
    case Allocation.WidthReady{tree}: Some{Allocation.source_of_measured(~A, ~E, tree)}
    case Allocation.HeightPending{first, remaining}: None{}
    case Allocation.WidthFailure{failure}: None{}

def physical_width_source_proof_cons_source(~A: Data, ~E: Data, first: Maybe<&2, Model.Tree<A, E>>, rest: Maybe<&2, +List<Model.Tree<A, E>>>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  match first rest:
    case Some{tree} Some{trees}: Some{tree <> trees}
    case _ _: None{}

def physical_width_source_proof_outcome_sources(~A: Data, ~E: Data, values: +List<Allocation.WidthOutcome<A, E>>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  match values:
    case Nil{}: Some{Nil{}}
    case Con{first, rest}: physical_width_source_proof_cons_source(~A, ~E, physical_width_source_proof_outcome_source(~A, ~E, first), physical_width_source_proof_outcome_sources(~A, ~E, rest))

def physical_width_source_proof_append_source(~A: Data, ~E: Data, previous: Maybe<&2, +List<Model.Tree<A, E>>>, remaining: +List<Model.Tree<A, E>>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  match previous:
    case None{}: None{}
    case Some{values}: Some{List.append(&2, Model.Tree<A, E>, values, remaining)}

def physical_width_source_proof_container_source(~A: Data, ~E: Data, key: String, value: A, interaction: Model.Interaction<E>, rule: Model.Rule, children: Maybe<&2, +List<Model.Tree<A, E>>>) -> Maybe<&2, Model.Tree<A, E>>:
  match children:
    case None{}: None{}
    case Some{values}: Some{Model.Container{key, value, interaction, rule, values}}

def physical_width_source_proof_child_sources_from_erased(~A: Data, ~E: Data, current: Maybe<&2, Model.Tree<A, E>>, previous: Maybe<&2, +List<Model.Tree<A, E>>>, remaining: +List<Space.Placement<Model.Tree<A, E>>>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  match current:
    case None{}: None{}
    case Some{tree}: physical_width_source_proof_append_source(~A, ~E, previous, tree <> Rule.placement_values(~Model.Tree<A, E>, remaining))

def physical_width_source_proof_child_sources(~A: Data, ~E: Data, previous: +List<Allocation.WidthOutcome<A, E>>, current: Maybe<&2, Model.Tree<A, E>>, remaining: +List<Space.Placement<Model.Tree<A, E>>>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  physical_width_source_proof_child_sources_from_erased(~A, ~E, current, physical_width_source_proof_outcome_sources(~A, ~E, previous), remaining)

def physical_width_source_proof_return_source(~A: Data, ~E: Data, return_to: Allocation.WidthReturn<A, E>, current: Maybe<&2, Model.Tree<A, E>>) -> Maybe<&2, Model.Tree<A, E>>:
  match return_to:
    case Allocation.WidthRootReturn{}: current
    case Allocation.WidthContainerReturn{key, value, interaction, rule, width, offset, direction, remaining, previous, parent}:
      physical_width_source_proof_return_source(~A, ~E, parent, physical_width_source_proof_container_source(~A, ~E, key, value, interaction, rule, physical_width_source_proof_child_sources(~A, ~E, previous, current, remaining)))

def physical_width_source_proof_plan_source(~A: Data, ~E: Data, plan: Allocation.InlinePlan<A, E>, key: String, value: A, interaction: Model.Interaction<E>, rule: Model.Rule) -> Maybe<&2, Model.Tree<A, E>>:
  match plan:
    case Allocation.InlineFailure{failure}: None{}
    case Allocation.InlinePlanned{placements, direction, canvas}:
      Some{Model.Container{key, value, interaction, rule, Rule.placement_values(~Model.Tree<A, E>, placements)}}

def physical_width_source_proof_state_source(~A: Data, ~E: Data, state: Allocation.WidthState<A, E>) -> Maybe<&2, Model.Tree<A, E>>:
  match state:
    case Allocation.WidthVisit{tree, width, offset, parent}: physical_width_source_proof_return_source(~A, ~E, parent, Some{tree})
    case Allocation.WidthMinimumChecked{False{}, tree, width, offset, rule, lower, parent}: physical_width_source_proof_return_source(~A, ~E, parent, None{})
    case Allocation.WidthMinimumChecked{True{}, tree, width, offset, rule, lower, parent}: physical_width_source_proof_return_source(~A, ~E, parent, Some{tree})
    case Allocation.WidthLeafHeight{None{}, key, value, interaction, rule, demand, height, inner_width, width, offset, parent}: physical_width_source_proof_return_source(~A, ~E, parent, None{})
    case Allocation.WidthLeafHeight{Some{sample}, key, value, interaction, rule, demand, height, inner_width, width, offset, parent}:
      physical_width_source_proof_return_source(~A, ~E, parent, Some{Model.Leaf{key, value, interaction, rule, demand, height}})
    case Allocation.WidthContainerPlan{plan, key, value, interaction, rule, width, offset, parent}:
      physical_width_source_proof_return_source(~A, ~E, parent, physical_width_source_proof_plan_source(~A, ~E, plan, key, value, interaction, rule))
    case Allocation.WidthChildren{remaining, key, value, interaction, rule, width, offset, direction, previous, parent}:
      physical_width_source_proof_return_source(~A, ~E, parent, physical_width_source_proof_container_source(~A, ~E, key, value, interaction, rule,
        physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, previous), Rule.placement_values(~Model.Tree<A, E>, remaining))))
    case Allocation.WidthComplete{result, parent}: physical_width_source_proof_return_source(~A, ~E, parent, physical_width_source_proof_outcome_source(~A, ~E, result))
    case Allocation.WidthDone{result}: physical_width_source_proof_outcome_source(~A, ~E, result)

def physical_width_source_proof_partial_match(~A: Data, ~E: Data, actual: Maybe<&2, Model.Tree<A, E>>, expected: Model.Tree<A, E>) -> Type:
  match actual:
    case None{}: {True{} == True{} : Bool}
    case Some{source}: {source == expected : Model.Tree<A, E>}

def physical_width_source_proof_return_none(~A: Data, ~E: Data, parent: Allocation.WidthReturn<A, E>) ->
  {physical_width_source_proof_return_source(~A, ~E, parent, None{}) == None{} : Maybe<&2, Model.Tree<A, E>>}:
  match parent:
    case Allocation.WidthRootReturn{}: {==}
    case Allocation.WidthContainerReturn{key, value, interaction, rule, width, offset, direction, remaining, previous, rest}:
      physical_width_source_proof_return_none(~A, ~E, rest)

def physical_width_source_proof_return_drop(~A: Data, ~E: Data, +parent: Allocation.WidthReturn<A, E>, +expected: Model.Tree<A, E>) ->
  physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_return_source(~A, ~E, parent, None{}), expected):
  Std.transport(Maybe<&2, Model.Tree<A, E>>, None{},
    (actual => physical_width_source_proof_partial_match(~A, ~E, actual, expected)), {==},
    physical_width_source_proof_return_source(~A, ~E, parent, None{}), physical_width_source_proof_return_none(~A, ~E, parent))

def physical_width_source_proof_return_same(~A: Data, ~E: Data, +parent: Allocation.WidthReturn<A, E>, +actual: Model.Tree<A, E>, +source: Model.Tree<A, E>, +expected: Model.Tree<A, E>,
  same: {actual == source : Model.Tree<A, E>},
  proof: physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_return_source(~A, ~E, parent, Some{source}), expected)) ->
  physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_return_source(~A, ~E, parent, Some{actual}), expected):
  Std.transport(Model.Tree<A, E>, source,
    (tree => physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_return_source(~A, ~E, parent, Some{tree}), expected)),
    proof, actual, same)

def measured_children_source(~A: Data, ~E: Data, children: Allocation.MeasuredChildren<A, E>) -> Maybe<&2, +List<Model.Tree<A, E>>>:
  match children:
    case Allocation.ChildrenFailed{failure}: None{}
    case Allocation.ChildrenPending{first, remaining}: None{}
    case Allocation.ChildrenMeasured{trees}: Some{Allocation.source_forest_measured(~A, ~E, trees)}

def physical_width_source_proof_merge_source(~A: Data, ~E: Data, +first: Allocation.WidthOutcome<A, E>, +rest: Allocation.MeasuredChildren<A, E>) ->
  {measured_children_source(~A, ~E, Allocation.merge_width(~A, ~E, first, rest)) ==
    physical_width_source_proof_cons_source(~A, ~E, physical_width_source_proof_outcome_source(~A, ~E, first), measured_children_source(~A, ~E, rest)) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match first rest:
    case Allocation.WidthFailure{failure} _: {==}
    case Allocation.HeightPending{first, remaining} Allocation.ChildrenFailed{failure}: {==}
    case Allocation.HeightPending{first, remaining} Allocation.ChildrenPending{next, tail}: {==}
    case Allocation.HeightPending{first, remaining} Allocation.ChildrenMeasured{trees}: {==}
    case Allocation.WidthReady{tree} Allocation.ChildrenFailed{failure}: {==}
    case Allocation.WidthReady{tree} Allocation.ChildrenPending{first, remaining}: {==}
    case Allocation.WidthReady{Allocation.MeasuredLeaf{key, value, interaction, rule, demand, height, width, offset, sample}} Allocation.ChildrenMeasured{trees}: {==}
    case Allocation.WidthReady{Allocation.MeasuredContainer{key, value, interaction, rule, width, offset, direction, children}} Allocation.ChildrenMeasured{trees}: {==}

def physical_width_source_proof_collected_source(~A: Data, ~E: Data, +values: +List<Allocation.WidthOutcome<A, E>>) ->
  {measured_children_source(~A, ~E, Allocation.collect_width_outcomes(~A, ~E, values)) ==
    physical_width_source_proof_outcome_sources(~A, ~E, values) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match values:
    case Nil{}: {==}
    case Con{+first, +rest}:
      Equal.trans(Maybe<&2, +List<Model.Tree<A, E>>>,
        measured_children_source(~A, ~E, Allocation.merge_width(~A, ~E, first, Allocation.collect_width_outcomes(~A, ~E, rest))),
        physical_width_source_proof_cons_source(~A, ~E, physical_width_source_proof_outcome_source(~A, ~E, first), measured_children_source(~A, ~E, Allocation.collect_width_outcomes(~A, ~E, rest))),
        physical_width_source_proof_cons_source(~A, ~E, physical_width_source_proof_outcome_source(~A, ~E, first), physical_width_source_proof_outcome_sources(~A, ~E, rest)),
        physical_width_source_proof_merge_source(~A, ~E, first, Allocation.collect_width_outcomes(~A, ~E, rest)),
        Equal.cong(Maybe<&2, +List<Model.Tree<A, E>>>, Maybe<&2, +List<Model.Tree<A, E>>>,
          (trees => physical_width_source_proof_cons_source(~A, ~E, physical_width_source_proof_outcome_source(~A, ~E, first), trees)),
          measured_children_source(~A, ~E, Allocation.collect_width_outcomes(~A, ~E, rest)), physical_width_source_proof_outcome_sources(~A, ~E, rest), physical_width_source_proof_collected_source(~A, ~E, rest)))

def physical_width_source_proof_append_empty(~A: Data, ~E: Data, +values: Maybe<&2, +List<Model.Tree<A, E>>>) ->
  {physical_width_source_proof_append_source(~A, ~E, values, Nil{}) == values : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match values:
    case None{}: {==}
    case Some{+trees}:
      Equal.cong(+List<Model.Tree<A, E>>, Maybe<&2, +List<Model.Tree<A, E>>>,
        (children => Some{children}), List.append(&2, Model.Tree<A, E>, trees, Nil{}), trees, Std.app_nil_r(Model.Tree<A, E>, trees))

def physical_width_source_proof_append_cons(~A: Data, ~E: Data, +first: Maybe<&2, Model.Tree<A, E>>, +rest: Maybe<&2, +List<Model.Tree<A, E>>>, +remaining: +List<Model.Tree<A, E>>) ->
  {physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_cons_source(~A, ~E, first, rest), remaining) ==
    physical_width_source_proof_cons_source(~A, ~E, first, physical_width_source_proof_append_source(~A, ~E, rest, remaining)) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match first rest:
    case None{} _: {==}
    case Some{tree} None{}: {==}
    case Some{tree} Some{trees}: {==}

def physical_width_source_proof_child_cons(~A: Data, ~E: Data, +first: Maybe<&2, Model.Tree<A, E>>, +rest: Maybe<&2, +List<Model.Tree<A, E>>>, +current: Maybe<&2, Model.Tree<A, E>>, +remaining: +List<Space.Placement<Model.Tree<A, E>>>) ->
  {physical_width_source_proof_cons_source(~A, ~E, first, physical_width_source_proof_child_sources_from_erased(~A, ~E, current, rest, remaining)) ==
    physical_width_source_proof_child_sources_from_erased(~A, ~E, current, physical_width_source_proof_cons_source(~A, ~E, first, rest), remaining) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match first current:
    case None{} None{}: {==}
    case Some{tree} None{}: {==}
    case _ Some{tree}: Equal.sym(Maybe<&2, +List<Model.Tree<A, E>>>,
      physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_cons_source(~A, ~E, first, rest), tree <> Rule.placement_values(~Model.Tree<A, E>, remaining)),
      physical_width_source_proof_cons_source(~A, ~E, first, physical_width_source_proof_append_source(~A, ~E, rest, tree <> Rule.placement_values(~Model.Tree<A, E>, remaining))),
      physical_width_source_proof_append_cons(~A, ~E, first, rest, tree <> Rule.placement_values(~Model.Tree<A, E>, remaining)))

def physical_width_source_proof_append_current_cons(~A: Data, ~E: Data, +first: Maybe<&2, Model.Tree<A, E>>, +rest: +List<Allocation.WidthOutcome<A, E>>, +current: Allocation.WidthOutcome<A, E>, +remaining: +List<Space.Placement<Model.Tree<A, E>>>,
  same: {physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.WidthOutcome<A, E>, rest, current <> Nil{})), Rule.placement_values(~Model.Tree<A, E>, remaining)) ==
    physical_width_source_proof_child_sources(~A, ~E, rest, physical_width_source_proof_outcome_source(~A, ~E, current), remaining) : Maybe<&2, +List<Model.Tree<A, E>>>}) ->
  {physical_width_source_proof_cons_source(~A, ~E, first, physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.WidthOutcome<A, E>, rest, current <> Nil{})), Rule.placement_values(~Model.Tree<A, E>, remaining))) ==
    physical_width_source_proof_child_sources_from_erased(~A, ~E, physical_width_source_proof_outcome_source(~A, ~E, current), physical_width_source_proof_cons_source(~A, ~E, first, physical_width_source_proof_outcome_sources(~A, ~E, rest)), remaining) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  Equal.trans(Maybe<&2, +List<Model.Tree<A, E>>>,
    physical_width_source_proof_cons_source(~A, ~E, first, physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.WidthOutcome<A, E>, rest, current <> Nil{})), Rule.placement_values(~Model.Tree<A, E>, remaining))),
    physical_width_source_proof_cons_source(~A, ~E, first, physical_width_source_proof_child_sources(~A, ~E, rest, physical_width_source_proof_outcome_source(~A, ~E, current), remaining)),
    physical_width_source_proof_child_sources_from_erased(~A, ~E, physical_width_source_proof_outcome_source(~A, ~E, current), physical_width_source_proof_cons_source(~A, ~E, first, physical_width_source_proof_outcome_sources(~A, ~E, rest)), remaining),
    Equal.cong(Maybe<&2, +List<Model.Tree<A, E>>>, Maybe<&2, +List<Model.Tree<A, E>>>, (trees => physical_width_source_proof_cons_source(~A, ~E, first, trees)),
      physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.WidthOutcome<A, E>, rest, current <> Nil{})), Rule.placement_values(~Model.Tree<A, E>, remaining)), physical_width_source_proof_child_sources(~A, ~E, rest, physical_width_source_proof_outcome_source(~A, ~E, current), remaining), same),
    physical_width_source_proof_child_cons(~A, ~E, first, physical_width_source_proof_outcome_sources(~A, ~E, rest), physical_width_source_proof_outcome_source(~A, ~E, current), remaining))

def physical_width_source_proof_append_current(~A: Data, ~E: Data, +previous: +List<Allocation.WidthOutcome<A, E>>, +current: Allocation.WidthOutcome<A, E>, +remaining: +List<Space.Placement<Model.Tree<A, E>>>) ->
  {physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.WidthOutcome<A, E>, previous, current <> Nil{})), Rule.placement_values(~Model.Tree<A, E>, remaining)) ==
    physical_width_source_proof_child_sources(~A, ~E, previous, physical_width_source_proof_outcome_source(~A, ~E, current), remaining) : Maybe<&2, +List<Model.Tree<A, E>>>}:
  match previous current:
    case Nil{} Allocation.WidthReady{tree}: {==}
    case Nil{} Allocation.HeightPending{first, tail}: {==}
    case Nil{} Allocation.WidthFailure{failure}: {==}
    case Con{+first, +rest} +current:
      Equal.trans(Maybe<&2, +List<Model.Tree<A, E>>>,
        physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_cons_source(~A, ~E, physical_width_source_proof_outcome_source(~A, ~E, first), physical_width_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.WidthOutcome<A, E>, rest, current <> Nil{}))), Rule.placement_values(~Model.Tree<A, E>, remaining)),
        physical_width_source_proof_cons_source(~A, ~E, physical_width_source_proof_outcome_source(~A, ~E, first), physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.WidthOutcome<A, E>, rest, current <> Nil{})), Rule.placement_values(~Model.Tree<A, E>, remaining))),
        physical_width_source_proof_child_sources(~A, ~E, first <> rest, physical_width_source_proof_outcome_source(~A, ~E, current), remaining),
        physical_width_source_proof_append_cons(~A, ~E, physical_width_source_proof_outcome_source(~A, ~E, first), physical_width_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.WidthOutcome<A, E>, rest, current <> Nil{})), Rule.placement_values(~Model.Tree<A, E>, remaining)),
        physical_width_source_proof_append_current_cons(~A, ~E, physical_width_source_proof_outcome_source(~A, ~E, first), rest, current, remaining, physical_width_source_proof_append_current(~A, ~E, rest, current, remaining)))

def physical_width_source_proof_return_option(~A: Data, ~E: Data, +actual: Maybe<&2, Model.Tree<A, E>>, +source: Model.Tree<A, E>, +parent: Allocation.WidthReturn<A, E>, +expected: Model.Tree<A, E>,
  same: physical_width_source_proof_partial_match(~A, ~E, actual, source),
  proof: physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_return_source(~A, ~E, parent, Some{source}), expected)) ->
  physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_return_source(~A, ~E, parent, actual), expected):
  match actual:
    case None{}: physical_width_source_proof_return_drop(~A, ~E, parent, expected)
    case Some{tree}: physical_width_source_proof_return_same(~A, ~E, parent, tree, source, expected, same, proof)

def physical_width_source_proof_checked_preserved(~A: Data, ~E: Data, +fits: Bool, +tree: Model.Tree<A, E>, +width: Nat, +offset: Nat, +rule: Model.Rule, +lower: Nat, +parent: Allocation.WidthReturn<A, E>, +expected: Model.Tree<A, E>,
  proof: physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_return_source(~A, ~E, parent, Some{tree}), expected)) ->
  physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_state_source(~A, ~E, Allocation.WidthMinimumChecked{fits, tree, width, offset, rule, lower, parent}), expected):
  match fits:
    case False{}: physical_width_source_proof_return_drop(~A, ~E, parent, expected)
    case True{}: proof

def visit_preserved(~A: Data, ~E: Data, +valid: Bool, +tree: Model.Tree<A, E>, +width: Nat, +offset: Nat, +rule: Model.Rule, +lower: Nat, +parent: Allocation.WidthReturn<A, E>, +expected: Model.Tree<A, E>,
  proof: physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_return_source(~A, ~E, parent, Some{tree}), expected)) ->
  physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_state_source(~A, ~E, Allocation.width_visit_checked(~A, ~E, valid, tree, width, offset, rule, lower, parent)), expected):
  match valid:
    case False{}: physical_width_source_proof_return_drop(~A, ~E, parent, expected)
    case True{}: physical_width_source_proof_checked_preserved(~A, ~E, Nat.is_le(lower, width), tree, width, offset, rule, lower, parent, expected, proof)

def leaf_preserved(~A: Data, ~E: Data, +sample: Maybe<&2, Nat>, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +demand: Space.Demand, +height: Model.Height, +inner_width: Nat, +width: Nat, +offset: Nat, +parent: Allocation.WidthReturn<A, E>, +expected: Model.Tree<A, E>,
  proof: physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_return_source(~A, ~E, parent, Some{Model.Leaf{key, value, interaction, rule, demand, height}}), expected)) ->
  physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_state_source(~A, ~E, Allocation.WidthLeafHeight{sample, key, value, interaction, rule, demand, height, inner_width, width, offset, parent}), expected):
  match sample:
    case None{}: physical_width_source_proof_return_drop(~A, ~E, parent, expected)
    case Some{sample}: proof

def physical_width_source_proof_plan_preserved(~A: Data, ~E: Data, +plan: Allocation.InlinePlan<A, E>, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +children: +List<Model.Tree<A, E>>,
  population: RulePhysicalSourceRules.InlinePopulation(~A, ~E, children, plan)) ->
  physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_plan_source(~A, ~E, plan, key, value, interaction, rule), Model.Container{key, value, interaction, rule, children}):
  match plan:
    case Allocation.InlineFailure{failure}: {==}
    case Allocation.InlinePlanned{placements, direction, canvas}:
      Equal.cong(+List<Model.Tree<A, E>>, Model.Tree<A, E>,
        (trees => Model.Container{key, value, interaction, rule, trees}), Rule.placement_values(~Model.Tree<A, E>, placements), children, population)

def physical_width_source_proof_finish_children_source(~A: Data, ~E: Data, +result: Allocation.MeasuredChildren<A, E>, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +width: Nat, +offset: Nat, +direction: Allocation.ResolvedDirection) ->
  {physical_width_source_proof_outcome_source(~A, ~E, Allocation.finish_measurement(~A, ~E, key, value, interaction, rule, width, offset, direction, result)) ==
    physical_width_source_proof_container_source(~A, ~E, key, value, interaction, rule, measured_children_source(~A, ~E, result)) : Maybe<&2, Model.Tree<A, E>>}:
  match result:
    case Allocation.ChildrenFailed{failure}: {==}
    case Allocation.ChildrenPending{first, remaining}: {==}
    case Allocation.ChildrenMeasured{trees}: {==}

def physical_width_source_proof_finish_source(~A: Data, ~E: Data, +previous: +List<Allocation.WidthOutcome<A, E>>, +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule, +width: Nat, +offset: Nat, +direction: Allocation.ResolvedDirection) ->
  {physical_width_source_proof_outcome_source(~A, ~E, Allocation.finish_measurement(~A, ~E, key, value, interaction, rule, width, offset, direction, Allocation.collect_width_outcomes(~A, ~E, previous))) ==
    physical_width_source_proof_container_source(~A, ~E, key, value, interaction, rule, physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, previous), Nil{})) : Maybe<&2, Model.Tree<A, E>>}:
  Equal.trans(Maybe<&2, Model.Tree<A, E>>,
    physical_width_source_proof_outcome_source(~A, ~E, Allocation.finish_measurement(~A, ~E, key, value, interaction, rule, width, offset, direction, Allocation.collect_width_outcomes(~A, ~E, previous))),
    physical_width_source_proof_container_source(~A, ~E, key, value, interaction, rule, measured_children_source(~A, ~E, Allocation.collect_width_outcomes(~A, ~E, previous))),
    physical_width_source_proof_container_source(~A, ~E, key, value, interaction, rule, physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, previous), Nil{})),
    physical_width_source_proof_finish_children_source(~A, ~E, Allocation.collect_width_outcomes(~A, ~E, previous), key, value, interaction, rule, width, offset, direction),
    Equal.cong(Maybe<&2, +List<Model.Tree<A, E>>>, Maybe<&2, Model.Tree<A, E>>,
      (trees => physical_width_source_proof_container_source(~A, ~E, key, value, interaction, rule, trees)),
      measured_children_source(~A, ~E, Allocation.collect_width_outcomes(~A, ~E, previous)), physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, previous), Nil{}),
      Equal.trans(Maybe<&2, +List<Model.Tree<A, E>>>,
        measured_children_source(~A, ~E, Allocation.collect_width_outcomes(~A, ~E, previous)), physical_width_source_proof_outcome_sources(~A, ~E, previous), physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, previous), Nil{}),
        physical_width_source_proof_collected_source(~A, ~E, previous), Equal.sym(Maybe<&2, +List<Model.Tree<A, E>>>, physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, previous), Nil{}), physical_width_source_proof_outcome_sources(~A, ~E, previous), physical_width_source_proof_append_empty(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, previous))))))

def physical_width_source_proof_state_same(~A: Data, ~E: Data, +before: Maybe<&2, Model.Tree<A, E>>, +after: Maybe<&2, Model.Tree<A, E>>, +expected: Model.Tree<A, E>,
  same: {after == before : Maybe<&2, Model.Tree<A, E>>}, proof: physical_width_source_proof_partial_match(~A, ~E, before, expected)) -> physical_width_source_proof_partial_match(~A, ~E, after, expected):
  Std.transport(Maybe<&2, Model.Tree<A, E>>, before, (source => physical_width_source_proof_partial_match(~A, ~E, source, expected)), proof, after, same)

def physical_width_source_proof_step_preserved(~A: Data, ~E: Data, +state: Allocation.WidthState<A, E>, +samples: +List<Model.HeightSample>, +expected: Model.Tree<A, E>,
  proof: physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_state_source(~A, ~E, state), expected)) ->
  physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_state_source(~A, ~E, Allocation.width_step(~A, ~E, state, samples)), expected):
  match state:
    case Allocation.WidthVisit{+tree, +width, offset, +parent}:
      visit_preserved(~A, ~E, Allocation.width_visit_valid(~A, ~E, Allocation.tree_rule(~A, ~E, tree), parent), tree, width, offset, Allocation.tree_rule(~A, ~E, tree), Allocation.axis_extent(Allocation.InlineAxis{}, Model.minimum_demand(Model.demand(~A, ~E, tree))), parent, expected, proof)
    case Allocation.WidthMinimumChecked{False{}, tree, width, offset, rule, lower, parent}: proof
    case Allocation.WidthMinimumChecked{True{}, Model.Leaf{key, value, interaction, +rule, demand, +height}, +width, offset, checked_rule, lower, parent}:
      leaf_preserved(~A, ~E, Allocation.leaf_height(height, Nat.sub(width, Nat.mul(2n, Allocation.inline_inset(rule))), samples), key, value, interaction, rule, demand, height, Nat.sub(width, Nat.mul(2n, Allocation.inline_inset(rule))), width, offset, parent, expected, proof)
    case Allocation.WidthMinimumChecked{True{}, Model.Container{+key, +value, +interaction, +rule, +children}, +width, offset, checked_rule, lower, +parent}:
      physical_width_source_proof_return_option(~A, ~E,
        physical_width_source_proof_plan_source(~A, ~E, Allocation.prepare_inline_children(~A, ~E, key, rule, children, Nat.sub(width, Nat.mul(2n, Allocation.inline_inset(rule)))), key, value, interaction, rule),
        Model.Container{key, value, interaction, rule, children}, parent, expected,
        physical_width_source_proof_plan_preserved(~A, ~E, Allocation.prepare_inline_children(~A, ~E, key, rule, children, Nat.sub(width, Nat.mul(2n, Allocation.inline_inset(rule)))), key, value, interaction, rule, children,
          ProofAllocationProof.inline_population(~A, ~E, key, rule, children, Nat.sub(width, Nat.mul(2n, Allocation.inline_inset(rule))))), proof)
    case Allocation.WidthLeafHeight{None{}, key, value, interaction, rule, demand, height, inner_width, width, offset, parent}: proof
    case Allocation.WidthLeafHeight{Some{sample}, key, value, interaction, rule, demand, height, inner_width, width, offset, parent}: proof
    case Allocation.WidthContainerPlan{Allocation.InlineFailure{failure}, key, value, interaction, rule, width, offset, parent}: proof
    case Allocation.WidthContainerPlan{Allocation.InlinePlanned{placements, direction, canvas}, key, value, interaction, rule, width, offset, parent}: proof
    case Allocation.WidthChildren{Nil{}, +key, +value, +interaction, +rule, +width, +offset, +direction, +previous, +parent}:
      physical_width_source_proof_state_same(~A, ~E,
        physical_width_source_proof_state_source(~A, ~E, Allocation.WidthChildren{Nil{}, key, value, interaction, rule, width, offset, direction, previous, parent}),
        physical_width_source_proof_state_source(~A, ~E, Allocation.width_step(~A, ~E, Allocation.WidthChildren{Nil{}, key, value, interaction, rule, width, offset, direction, previous, parent}, samples)), expected,
        Equal.cong(Maybe<&2, Model.Tree<A, E>>, Maybe<&2, Model.Tree<A, E>>, (source => physical_width_source_proof_return_source(~A, ~E, parent, source)),
          physical_width_source_proof_outcome_source(~A, ~E, Allocation.finish_measurement(~A, ~E, key, value, interaction, rule, width, offset, direction, Allocation.collect_width_outcomes(~A, ~E, previous))),
          physical_width_source_proof_container_source(~A, ~E, key, value, interaction, rule, physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, previous), Nil{})), physical_width_source_proof_finish_source(~A, ~E, previous, key, value, interaction, rule, width, offset, direction)), proof)
    case Allocation.WidthChildren{Con{Space.Placement{child, child_offset, extent}, rest}, key, value, interaction, rule, width, offset, direction, previous, parent}: proof
    case Allocation.WidthComplete{result, Allocation.WidthRootReturn{}}: proof
    case Allocation.WidthComplete{+result, Allocation.WidthContainerReturn{+key, +value, +interaction, +rule, width, offset, direction, +remaining, +previous, +parent}}:
      physical_width_source_proof_state_same(~A, ~E,
        physical_width_source_proof_return_source(~A, ~E, parent, physical_width_source_proof_container_source(~A, ~E, key, value, interaction, rule, physical_width_source_proof_child_sources(~A, ~E, previous, physical_width_source_proof_outcome_source(~A, ~E, result), remaining))),
        physical_width_source_proof_return_source(~A, ~E, parent, physical_width_source_proof_container_source(~A, ~E, key, value, interaction, rule, physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.WidthOutcome<A, E>, previous, result <> Nil{})), Rule.placement_values(~Model.Tree<A, E>, remaining)))), expected,
        Equal.cong(Maybe<&2, +List<Model.Tree<A, E>>>, Maybe<&2, Model.Tree<A, E>>,
          (children => physical_width_source_proof_return_source(~A, ~E, parent, physical_width_source_proof_container_source(~A, ~E, key, value, interaction, rule, children))),
          physical_width_source_proof_append_source(~A, ~E, physical_width_source_proof_outcome_sources(~A, ~E, List.append(&2, Allocation.WidthOutcome<A, E>, previous, result <> Nil{})), Rule.placement_values(~Model.Tree<A, E>, remaining)),
          physical_width_source_proof_child_sources(~A, ~E, previous, physical_width_source_proof_outcome_source(~A, ~E, result), remaining), physical_width_source_proof_append_current(~A, ~E, previous, result, remaining)), proof)
    case Allocation.WidthDone{result}: proof

def execution_preserved(~A: Data, ~E: Data, +execution: Allocation.WidthExecution<A, E>, +expected: Model.Tree<A, E>,
  proof: physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_state_source(~A, ~E, Allocation.width_execution_state(~A, ~E, execution)), expected)) ->
  physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_state_source(~A, ~E, Allocation.width_execution_state(~A, ~E, Allocation.width_execution_step(~A, ~E, execution))), expected):
  match execution:
    case Allocation.WidthExecution{state, samples}: physical_width_source_proof_step_preserved(~A, ~E, state, samples, expected, proof)

def physical_width_source_proof_iterate_preserved(~A: Data, ~E: Data, +budget: Nat, +execution: Allocation.WidthExecution<A, E>, +expected: Model.Tree<A, E>,
  proof: physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_state_source(~A, ~E, Allocation.width_execution_state(~A, ~E, execution)), expected)) ->
  physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_state_source(~A, ~E, Allocation.width_execution_state(~A, ~E, Std.iter(~Allocation.WidthExecution<A, E>, ~(value => Allocation.width_execution_step(~A, ~E, value)), budget, execution))), expected):
  Std.nat_ind(~(n => @+seed:Allocation.WidthExecution<A, E> -> @+source:Model.Tree<A, E> ->
    @initial:physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_state_source(~A, ~E, Allocation.width_execution_state(~A, ~E, seed)), source) ->
    physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_state_source(~A, ~E, Allocation.width_execution_state(~A, ~E, Std.iter(~Allocation.WidthExecution<A, E>, ~(value => Allocation.width_execution_step(~A, ~E, value)), n, seed))), source)),
    ~(+seed => +source => initial => initial),
    ~(+n => induction => +seed => +source => initial => execution_preserved(~A, ~E,
      Std.iter(~Allocation.WidthExecution<A, E>, ~(value => Allocation.width_execution_step(~A, ~E, value)), n, seed), source, induction(seed, source, initial))), budget)(execution, expected, proof)

def outcome_preserved(~A: Data, ~E: Data, +result: Allocation.WidthOutcome<A, E>, +expected: Model.Tree<A, E>,
  proof: physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_outcome_source(~A, ~E, result), expected)) ->
  RulePhysicalSourceRules.width_source_source_claim(~A, ~E, expected, result):
  match result:
    case Allocation.WidthReady{tree}: proof
    case Allocation.HeightPending{first, remaining}: {==}
    case Allocation.WidthFailure{failure}: {==}

def physical_width_source_proof_finish_completed(~A: Data, ~E: Data, +state: Allocation.WidthState<A, E>, +key: String, +width: Nat, +budget: Nat, +expected: Model.Tree<A, E>,
  complete: {RulePhysicalSourceRules.width_completed(~A, ~E, state) == True{} : Bool},
  proof: physical_width_source_proof_partial_match(~A, ~E, physical_width_source_proof_state_source(~A, ~E, state), expected)) ->
  RulePhysicalSourceRules.width_source_source_claim(~A, ~E, expected, Allocation.finish_width_iteration(~A, ~E, state, key, width, budget)):
  match state:
    case Allocation.WidthDone{+result}: outcome_preserved(~A, ~E, result, expected, proof)
    case Allocation.WidthVisit{tree, extent, offset, parent}: Logic.impossible(RulePhysicalSourceRules.width_source_source_claim(~A, ~E, expected, Allocation.WidthFailure{Allocation.Failure{key, Allocation.InlineAxis{}, budget, width, Allocation.AllocationBoundExceeded{budget}}}), complete)
    case Allocation.WidthMinimumChecked{fits, tree, extent, offset, rule, lower, parent}: Logic.impossible(RulePhysicalSourceRules.width_source_source_claim(~A, ~E, expected, Allocation.WidthFailure{Allocation.Failure{key, Allocation.InlineAxis{}, budget, width, Allocation.AllocationBoundExceeded{budget}}}), complete)
    case Allocation.WidthLeafHeight{sample, leaf_key, value, interaction, rule, demand, height, inner_width, outer_width, offset, parent}: Logic.impossible(RulePhysicalSourceRules.width_source_source_claim(~A, ~E, expected, Allocation.WidthFailure{Allocation.Failure{key, Allocation.InlineAxis{}, budget, width, Allocation.AllocationBoundExceeded{budget}}}), complete)
    case Allocation.WidthContainerPlan{plan, container_key, value, interaction, rule, outer_width, offset, parent}: Logic.impossible(RulePhysicalSourceRules.width_source_source_claim(~A, ~E, expected, Allocation.WidthFailure{Allocation.Failure{key, Allocation.InlineAxis{}, budget, width, Allocation.AllocationBoundExceeded{budget}}}), complete)
    case Allocation.WidthChildren{remaining, container_key, value, interaction, rule, outer_width, offset, direction, previous, parent}: Logic.impossible(RulePhysicalSourceRules.width_source_source_claim(~A, ~E, expected, Allocation.WidthFailure{Allocation.Failure{key, Allocation.InlineAxis{}, budget, width, Allocation.AllocationBoundExceeded{budget}}}), complete)
    case Allocation.WidthComplete{result, parent}: Logic.impossible(RulePhysicalSourceRules.width_source_source_claim(~A, ~E, expected, Allocation.WidthFailure{Allocation.Failure{key, Allocation.InlineAxis{}, budget, width, Allocation.AllocationBoundExceeded{budget}}}), complete)

def measure_preserved(~A: Data, ~E: Data, +tree: Model.Tree<A, E>, +width: Nat, +offset: Nat, +samples: +List<Model.HeightSample>) ->
  RulePhysicalSourceRules.width_source_source_claim(~A, ~E, tree, Allocation.measure_at(~A, ~E, tree, width, offset, samples)):
  physical_width_source_proof_finish_completed(~A, ~E, Allocation.iterate_width(~A, ~E, tree, width, offset, samples), Allocation.tree_key(~A, ~E, tree), width, Allocation.width_forest_work(~A, ~E, tree <> Nil{}), tree,
    physical_width_proof_complete(~A, ~E, tree, width, offset, samples),
    physical_width_source_proof_iterate_preserved(~A, ~E, Allocation.width_forest_work(~A, ~E, tree <> Nil{}), Allocation.WidthExecution{Allocation.WidthVisit{tree, width, offset, Allocation.WidthRootReturn{}}, samples}, tree, {==}))

def first_tree(~A: Data, ~E: Data, values: +List<Model.Tree<A, E>>, fallback: Model.Tree<A, E>) -> Model.Tree<A, E>:
  match values:
    case Nil{}: fallback
    case Con{first, remaining}: first

def root_preserved(~A: Data, ~E: Data, +placements: +List<Space.Placement<Model.Tree<A, E>>>, +tree: Model.Tree<A, E>, +samples: +List<Model.HeightSample>,
  population: {Rule.placement_values(~Model.Tree<A, E>, placements) == tree <> Nil{} : +List<Model.Tree<A, E>>}) ->
  RulePhysicalSourceRules.width_source_source_claim(~A, ~E, tree, Allocation.root_measurement(~A, ~E, tree, placements, samples)):
  match placements:
    case Nil{}: {==}
    case Con{Space.Placement{+value, offset, extent}, rest}:
      Std.transport(Model.Tree<A, E>, value,
        (source => RulePhysicalSourceRules.width_source_source_claim(~A, ~E, source, Allocation.measure_at(~A, ~E, value, extent, offset, samples))),
        measure_preserved(~A, ~E, value, extent, offset, samples), tree,
        Equal.sym(Model.Tree<A, E>, value, tree,
          Equal.cong(+List<Model.Tree<A, E>>, Model.Tree<A, E>, (values => first_tree(~A, ~E, values, value)),
            Rule.placement_values(~Model.Tree<A, E>, Space.Placement{value, offset, extent} <> rest), tree <> Nil{}, population)))

def packed_preserved(~A: Data, ~E: Data, +packing: Space.Packing<Model.Tree<A, E>>, +tree: Model.Tree<A, E>, +samples: +List<Model.HeightSample>,
  population: ProofAllocationProof.PackingPopulation(~Model.Tree<A, E>, tree <> Nil{}, packing)) ->
  RulePhysicalSourceRules.width_source_source_claim(~A, ~E, tree, Allocation.dispatch_fit_width_16(~A, ~E, packing, tree, samples)):
  match packing:
    case Space.Insufficient{required, available}: {==}
    case Space.Packed{placements, unused}: root_preserved(~A, ~E, placements, tree, samples, population)

def slots_preserved(~A: Data, ~E: Data, +slots: Allocation.SlotsOutcome<Model.Tree<A, E>>, +tree: Model.Tree<A, E>, +width: Nat, +samples: +List<Model.HeightSample>,
  population: ProofAllocationProof.SlotsPopulation(~Model.Tree<A, E>, tree <> Nil{}, slots)) ->
  RulePhysicalSourceRules.width_source_source_claim(~A, ~E, tree, Allocation.dispatch_fit_width_15(~A, ~E, slots, tree, width, samples)):
  match slots:
    case Allocation.SlotsFailure{failure}: {==}
    case Allocation.SlotsReady{+values}:
      packed_preserved(~A, ~E, Allocation.shared_pack(~Model.Tree<A, E>, values, 0n, Nat.sub(width, Allocation.outside_axis(Allocation.InlineAxis{}, Allocation.tree_rule(~A, ~E, tree)))), tree, samples,
        Std.transport(+List<Model.Tree<A, E>>, Rule.slot_values(~Model.Tree<A, E>, values),
          (children => ProofAllocationProof.PackingPopulation(~Model.Tree<A, E>, children, Allocation.shared_pack(~Model.Tree<A, E>, values, 0n, Nat.sub(width, Allocation.outside_axis(Allocation.InlineAxis{}, Allocation.tree_rule(~A, ~E, tree)))))),
          ProofAllocationProof.shared_population(~Model.Tree<A, E>, values, 0n, Nat.sub(width, Allocation.outside_axis(Allocation.InlineAxis{}, Allocation.tree_rule(~A, ~E, tree)))), tree <> Nil{}, Equal.sym(+List<Model.Tree<A, E>>, Rule.slot_values(~Model.Tree<A, E>, values), tree <> Nil{}, population)))

def physical_width_source_proof_preserved(~A: Data, ~E: Data, +tree: Model.Tree<A, E>, +width: Nat, +samples: +List<Model.HeightSample>) ->
  RulePhysicalSourceRules.width_source_source_claim(~A, ~E, tree, Allocation.fit_width(~A, ~E, tree, width, samples)):
  slots_preserved(~A, ~E, Allocation.width_slots(~A, ~E, tree <> Nil{}, width), tree, width, samples,
    ProofAllocationProof.width_population(~A, ~E, tree <> Nil{}, width))

def RulePhysicalSourceRules.width_source_evidence(A, E):
  RulePhysicalSourceRules.WidthSourceRequirements{+tree => +width => +samples => physical_width_source_proof_preserved(~A, ~E, tree, width, samples)}


def probe_or_false(+value: Bool) -> {(value || False{}) == value : Bool}:
  match value:
    case False{}: {==}
    case True{}: {==}

def probe_or_true(+value: Bool) -> {(value || True{}) == True{} : Bool}:
  match value:
    case False{}: {==}
    case True{}: {==}

def probe_and_false(+value: Bool) -> {(value && False{}) == False{} : Bool}:
  match value:
    case False{}: {==}
    case True{}: {==}

def receipt_stages_complete(+generation: Bool, +key: Bool, +purpose: Bool, +shape: Bool,
  valid: Unit -> Bool) ->
  {RulePhysicalContentRules2.receipt_guard(generation, (_ =>
    RulePhysicalContentRules2.receipt_guard(key, (_ =>
      RulePhysicalContentRules2.receipt_guard(purpose, (_ =>
        RulePhysicalContentRules2.receipt_guard(shape, valid))))))) ==
    (generation && key && purpose && shape && valid(Unit{})) : Bool}:
  match generation key purpose shape:
    case False{} _ _ _: {==}
    case True{} False{} _ _: {==}
    case True{} True{} False{} _: {==}
    case True{} True{} True{} False{}: {==}
    case True{} True{} True{} True{}: {==}

def measurement_generation(request: Content.Request) -> Nat:
  Content.Request{generation, key, value, purpose, roots, policies} = request
  generation

def measurement_key(request: Content.Request) -> String:
  Content.Request{generation, key, value, purpose, roots, policies} = request
  key

def measurement_purpose(request: Content.Request) -> Content.Purpose:
  Content.Request{generation, key, value, purpose, roots, policies} = request
  purpose

def observation_generation(observation: Content.Observation) -> Nat:
  Content.Observation{generation, key, purpose, minimum, preferred, height, advance} = observation
  generation

def observation_key(observation: Content.Observation) -> String:
  Content.Observation{generation, key, purpose, minimum, preferred, height, advance} = observation
  key

def observation_purpose(observation: Content.Observation) -> Content.Purpose:
  Content.Observation{generation, key, purpose, minimum, preferred, height, advance} = observation
  purpose

def observation_minimum(observation: Content.Observation) -> Nat:
  Content.Observation{generation, key, purpose, minimum, preferred, height, advance} = observation
  minimum

def observation_preferred(observation: Content.Observation) -> Nat:
  Content.Observation{generation, key, purpose, minimum, preferred, height, advance} = observation
  preferred

def observation_height(observation: Content.Observation) -> Nat:
  Content.Observation{generation, key, purpose, minimum, preferred, height, advance} = observation
  height

def observation_advance(observation: Content.Observation) -> Nat:
  Content.Observation{generation, key, purpose, minimum, preferred, height, advance} = observation
  advance

def receipt_predicate_complete(+request: Content.Request, +observation: Content.Observation) ->
  {(Nat.is_eq(measurement_generation(request), observation_generation(observation)) && SafeText.string_equal(measurement_key(request), observation_key(observation)) && RulePhysicalContentRules2.same_purpose(measurement_purpose(request), observation_purpose(observation)) && Nat.is_le(observation_minimum(observation), observation_preferred(observation)) && RulePhysicalContentRules2.request_observation_valid(request, observation_height(observation), observation_advance(observation))) == Dimensions.observation_matches(request, observation) : Bool}:
  Content.Request{+generation, +key, +value, +purpose, +roots, +policies} = request
  Content.Observation{+observed_generation, +observed_key, +observed_purpose, +minimum, +preferred, +height, +advance} = observation
  +full: Content.Request = Content.Request{generation, key, value, purpose, roots, policies}
  +seen: Content.Observation = Content.Observation{observed_generation, observed_key, observed_purpose, minimum, preferred, height, advance}
  %Equal.sym(Bool, SafeText.string_equal(key, observed_key), String.eq(key, observed_key), TextProof.public_refines(key, observed_key)) :
    {(Nat.is_eq(generation, observed_generation) && _ && RulePhysicalContentRules2.same_purpose(purpose, observed_purpose) && Nat.is_le(minimum, preferred) && RulePhysicalContentRules2.request_observation_valid(full, height, advance)) == Dimensions.observation_matches(full, seen) : Bool}
  %Equal.sym(Bool, RulePhysicalContentRules2.same_purpose(purpose, observed_purpose), Dimensions.same_purpose(purpose, observed_purpose), MeasurementEvidence.same_purpose(purpose, observed_purpose)) :
    {(Nat.is_eq(generation, observed_generation) && String.eq(key, observed_key) && _ && Nat.is_le(minimum, preferred) && RulePhysicalContentRules2.request_observation_valid(full, height, advance)) == Dimensions.observation_matches(full, seen) : Bool}
  %Equal.sym(Bool, RulePhysicalContentRules2.request_observation_valid(full, height, advance), Dimensions.request_observation_valid(full, height, advance), MeasurementEvidence.measurements_request_observation_valid(full, height, advance)) :
    {(Nat.is_eq(generation, observed_generation) && String.eq(key, observed_key) && Dimensions.same_purpose(purpose, observed_purpose) && Nat.is_le(minimum, preferred) && _) == Dimensions.observation_matches(full, seen) : Bool}
  {==}

def receipt_matches_complete(+request: Content.Request, +observation: Content.Observation) ->
  {RulePhysicalContentRules2.observation_matches(request, observation) == RuleMeasurement.receipt_valid_observation(request, observation) : Bool}:
  match request:
    case Content.Request{+generation, +key, Content.Value{+node, +font}, +purpose, +roots, +policies}:
      match observation:
        case Content.Observation{+observed_generation, +observed_key, +observed_purpose, +minimum, +preferred, +height, +advance}:
          +full: Content.Request = Content.Request{generation, key, Content.Value{node, font}, purpose, roots, policies}
          +seen: Content.Observation = Content.Observation{observed_generation, observed_key, observed_purpose, minimum, preferred, height, advance}
          Equal.trans(Bool, RulePhysicalContentRules2.observation_matches(full, seen),
            (Nat.is_eq(generation, observed_generation) && SafeText.string_equal(key, observed_key) && RulePhysicalContentRules2.same_purpose(purpose, observed_purpose) && Nat.is_le(minimum, preferred) && RulePhysicalContentRules2.request_observation_valid(full, height, advance)),
            RuleMeasurement.receipt_valid_observation(full, seen),
            receipt_stages_complete(Nat.is_eq(generation, observed_generation), SafeText.string_equal(key, observed_key), RulePhysicalContentRules2.same_purpose(purpose, observed_purpose), Nat.is_le(minimum, preferred), (_ => RulePhysicalContentRules2.request_observation_valid(full, height, advance))),
            receipt_predicate_complete(full, seen))

def RuleMeasurement.receipt_uses_request_guard(request, observation):
  match request:
    case Content.Request{generation, key, Content.Value{node, font}, purpose, roots, policies}:
      match observation:
        case Content.Observation{observed_generation, observed_key, observed_purpose, minimum, preferred, height, advance}:
          receipt_matches_complete(Content.Request{generation, key, Content.Value{node, font}, purpose, roots, policies},
            Content.Observation{observed_generation, observed_key, observed_purpose, minimum, preferred, height, advance})

def receipt_admission_checked_complete(+request: Content.Request, +observation: Content.Observation,
  fallback: Unit -> Maybe<&2, Content.Observation>, +accepted: Bool,
  observed: {RulePhysicalContentRules2.observation_matches(request, observation) == accepted : Bool}) ->
  {RulePhysicalContentRules2.receipt_admission(request,
    Categories.admit_checked(Content.Observation,
      (candidate => RulePhysicalContentRules2.observation_matches(request, candidate)), observation, accepted, observed), fallback) ==
    RuleMeasurement.required_receipt_pick(accepted, observation, fallback(Unit{})) : Maybe<&2, Content.Observation>}:
  match accepted:
    case False{}: {==}
    case True{}: {==}

def receipt_scan_complete(+observations: +List<Content.Observation>, +request: Content.Request) ->
  {RulePhysicalContentRules2.scan(observations, request) ==
    RuleMeasurement.required_receipt(request, observations) : Maybe<&2, Content.Observation>}:
  match observations:
    case Nil{}: {==}
    case Con{+observation, +rest}:
      +actual_tail: Maybe<&2, Content.Observation> = RulePhysicalContentRules2.scan(rest, request)
      +expected_tail: Maybe<&2, Content.Observation> = RuleMeasurement.required_receipt(request, rest)
      +actual_match: Bool = RulePhysicalContentRules2.observation_matches(request, observation)
      +expected_match: Bool = RuleMeasurement.receipt_valid_observation(request, observation)
      +actual_step: Maybe<&2, Content.Observation> = RuleMeasurement.required_receipt_pick(actual_match, observation, actual_tail)
      +matched_step: Maybe<&2, Content.Observation> = RuleMeasurement.required_receipt_pick(expected_match, observation, actual_tail)
      Equal.trans(Maybe<&2, Content.Observation>,
        RulePhysicalContentRules2.scan(observation <> rest, request), actual_step,
        RuleMeasurement.required_receipt(request, observation <> rest),
        receipt_admission_checked_complete(request, observation, (_ => actual_tail), actual_match, {==}),
        Equal.trans(Maybe<&2, Content.Observation>, actual_step, matched_step,
          RuleMeasurement.required_receipt(request, observation <> rest),
          Equal.cong(Bool, Maybe<&2, Content.Observation>,
            (accepted => RuleMeasurement.required_receipt_pick(accepted, observation, actual_tail)),
            actual_match, expected_match, receipt_matches_complete(request, observation)),
          Equal.cong(Maybe<&2, Content.Observation>, Maybe<&2, Content.Observation>,
            (tail => RuleMeasurement.required_receipt_pick(expected_match, observation, tail)),
            actual_tail, expected_tail, receipt_scan_complete(rest, request))))

def RuleMeasurement.find_first_valid_receipt(request, observations):
  receipt_scan_complete(observations, request)

def RuleMeasurement.width_probe_dimensions(generation, key, node, font, width, roots, policies, height, advance):
  Equal.trans(Bool, RulePhysicalContentRules2.request_observation_valid(Content.Request{generation, key, Content.Value{node, font}, Content.AtWidth{width}, roots, policies}, height, advance),
    RulePhysicalContentRules2.primitive_observation_valid(node, height, advance), Dimensions.primitive_observation_valid(node, height, advance),
    probe_or_false(RulePhysicalContentRules2.primitive_observation_valid(node, height, advance)),
    MeasurementEvidence.measurements_primitive_observation_valid(node, height, advance))

def rootless_natural_zero(+node: Source.Node, +key: String, +height: Nat) ->
  {RulePhysicalContentRules2.natural_ui_zero(node, key, Nil{}, height) == False{} : Bool}:
  match node:
    case Source.RichText{identity, style, Source.RichContent{source, value, policy}, attachments, native_owner}: {==}
    case Source.NativeAttachment{identity, target, attributes, style, children}: {==}
    case Source.Box{identity, tag, style, attributes, children}: {==}
    case Source.Control{identity, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: {==}
    case Source.Text{identity, value, font, wrapping}: {==}
    case Source.Glyph{identity, drawing, style}: {==}
    case Source.Field{identity, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: {==}

def rootless_zero(+purpose: Content.Purpose, +node: Source.Node, +key: String, +height: Nat) ->
  {RulePhysicalContentRules2.zero_height_ui(purpose, node, key, Nil{}, height) == False{} : Bool}:
  match purpose:
    case Content.Natural{}: rootless_natural_zero(node, key, height)
    case Content.AtWidth{width}: {==}

def RuleMeasurement.rootless_probe_dimensions(generation, key, node, font, purpose, policies, height, advance):
  Equal.trans(Bool, RulePhysicalContentRules2.request_observation_valid(Content.Request{generation, key, Content.Value{node, font}, purpose, Nil{}, policies}, height, advance),
    RulePhysicalContentRules2.primitive_observation_valid(node, height, advance), Dimensions.primitive_observation_valid(node, height, advance),
    Equal.trans(Bool,
      RulePhysicalContentRules2.request_observation_valid(Content.Request{generation, key, Content.Value{node, font}, purpose, Nil{}, policies}, height, advance),
      (RulePhysicalContentRules2.primitive_observation_valid(node, height, advance) || False{}),
      RulePhysicalContentRules2.primitive_observation_valid(node, height, advance),
      Equal.cong(Bool, Bool, (extra => RulePhysicalContentRules2.primitive_observation_valid(node, height, advance) || extra),
        RulePhysicalContentRules2.zero_height_ui(purpose, node, key, Nil{}, height), False{}, rootless_zero(purpose, node, key, height)),
      probe_or_false(RulePhysicalContentRules2.primitive_observation_valid(node, height, advance))),
    MeasurementEvidence.measurements_primitive_observation_valid(node, height, advance))

def ordinary_zero(+node: Source.Node, +purpose: Content.Purpose, +key: String, +roots: +List<Content.NativeRoot>, +height: Nat,
  ordinary: {RuleMeasurement.ordinary_probe(node) == True{} : Bool}) ->
  {RulePhysicalContentRules2.zero_height_ui(purpose, node, key, roots, height) == False{} : Bool}:
  match node:
    case Source.RichText{identity, style, Source.RichContent{source, value, policy}, attachments, native_owner}: Logic.impossible({RulePhysicalContentRules2.zero_height_ui(purpose, node, key, roots, height) == False{} : Bool}, ordinary)
    case Source.NativeAttachment{identity, target, attributes, style, children}:
      match purpose:
        case Content.Natural{}: {==}
        case Content.AtWidth{width}: {==}
    case Source.Box{identity, tag, style, attributes, children}:
      match purpose:
        case Content.Natural{}: {==}
        case Content.AtWidth{width}: {==}
    case Source.Control{identity, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}:
      match purpose:
        case Content.Natural{}: {==}
        case Content.AtWidth{width}: {==}
    case Source.Text{identity, value, font, wrapping}:
      match purpose:
        case Content.Natural{}: {==}
        case Content.AtWidth{width}: {==}
    case Source.Glyph{identity, drawing, style}:
      match purpose:
        case Content.Natural{}: {==}
        case Content.AtWidth{width}: {==}
    case Source.Field{identity, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}:
      match purpose:
        case Content.Natural{}: {==}
        case Content.AtWidth{width}: {==}

def RuleMeasurement.ordinary_probe_dimensions(generation, key, node, font, purpose, roots, policies, height, advance, ordinary):
  Equal.trans(Bool, RulePhysicalContentRules2.request_observation_valid(Content.Request{generation, key, Content.Value{node, font}, purpose, roots, policies}, height, advance),
    RulePhysicalContentRules2.primitive_observation_valid(node, height, advance), Dimensions.primitive_observation_valid(node, height, advance),
    Equal.trans(Bool,
      RulePhysicalContentRules2.request_observation_valid(Content.Request{generation, key, Content.Value{node, font}, purpose, roots, policies}, height, advance),
      (RulePhysicalContentRules2.primitive_observation_valid(node, height, advance) || False{}),
      RulePhysicalContentRules2.primitive_observation_valid(node, height, advance),
      Equal.cong(Bool, Bool, (extra => RulePhysicalContentRules2.primitive_observation_valid(node, height, advance) || extra),
        RulePhysicalContentRules2.zero_height_ui(purpose, node, key, roots, height), False{}, ordinary_zero(node, purpose, key, roots, height, ordinary)),
      probe_or_false(RulePhysicalContentRules2.primitive_observation_valid(node, height, advance))),
    MeasurementEvidence.measurements_primitive_observation_valid(node, height, advance))

def singleton_root_correspondence(+root: Content.NativeRoot, +key: String, +source: Code.Source) ->
  {RulePhysicalContentRules2.owned_interactive_root(root <> Nil{}, key, Some{source}) ==
    (RuleMeasurement.single_interactive_owner(root, key, source) || False{}) : Bool}:
  match root:
    case Content.NativeRoot{owner_key, target, tree, attributes, style}:
      match target:
        case Source.InteractiveTarget{identity}: {==}
        case Source.ToolbarTarget{identity}: {==}
        case Source.CodeBodyTarget{identity, wrap}: {==}
        case Source.InteractiveSourceTarget{identity, exposed}: {==}
        case Source.InteractiveFrameTarget{identity, active}: {==}

def natural_zero_owned(+prior: Bool, +owned: Bool, evidence: {owned == True{} : Bool}) ->
  {(prior || ((owned || False{}) && True{})) == True{} : Bool}:
  Std.transport(Bool, True{}, (value => {(prior || ((value || False{}) && True{})) == True{} : Bool}),
    probe_or_true(prior), owned, evidence)

def natural_zero_foreign(+prior: Bool, +owned: Bool, +height: Nat, evidence: {owned == False{} : Bool}) ->
  {(prior || ((owned || False{}) && Nat.is_eq(height, 0n))) == prior : Bool}:
  Std.transport(Bool, False{}, (value => {(prior || ((value || False{}) && Nat.is_eq(height, 0n))) == prior : Bool}),
    probe_or_false(prior), owned, evidence)

def RuleMeasurement.natural_owned_ui_zero_admissible(generation, key, font, style, policy, source, value, root, advance, evidence):
  Equal.trans(Bool,
    RulePhysicalContentRules2.request_observation_valid(RuleMeasurement.rich_probe_request(generation, key, font, style, policy, source, value, Content.Natural{}, root), 0n, advance),
    (RulePhysicalContentRules2.content_height_valid(value, 0n) || ((RuleMeasurement.single_interactive_owner(root, key, source) || False{}) && True{})), True{},
    Equal.cong(Bool, Bool, (owned => RulePhysicalContentRules2.content_height_valid(value, 0n) || (owned && True{})),
      RulePhysicalContentRules2.owned_interactive_root(root <> Nil{}, key, Some{source}),
      (RuleMeasurement.single_interactive_owner(root, key, source) || False{}), singleton_root_correspondence(root, key, source)),
    natural_zero_owned(RulePhysicalContentRules2.content_height_valid(value, 0n), RuleMeasurement.single_interactive_owner(root, key, source), evidence))

def RuleMeasurement.foreign_ui_dimensions(generation, key, font, style, policy, source, value, root, height, advance, evidence):
  Equal.trans(Bool, RulePhysicalContentRules2.request_observation_valid(RuleMeasurement.rich_probe_request(generation, key, font, style, policy, source, value, Content.Natural{}, root), height, advance),
    RulePhysicalContentRules2.content_height_valid(value, height), Dimensions.content_height_valid(value, height),
    Equal.trans(Bool,
      RulePhysicalContentRules2.request_observation_valid(RuleMeasurement.rich_probe_request(generation, key, font, style, policy, source, value, Content.Natural{}, root), height, advance),
      (RulePhysicalContentRules2.content_height_valid(value, height) || ((RuleMeasurement.single_interactive_owner(root, key, source) || False{}) && Nat.is_eq(height, 0n))),
      RulePhysicalContentRules2.content_height_valid(value, height),
      Equal.cong(Bool, Bool, (owned => RulePhysicalContentRules2.content_height_valid(value, height) || (owned && Nat.is_eq(height, 0n))),
        RulePhysicalContentRules2.owned_interactive_root(root <> Nil{}, key, Some{source}),
        (RuleMeasurement.single_interactive_owner(root, key, source) || False{}), singleton_root_correspondence(root, key, source)),
      natural_zero_foreign(RulePhysicalContentRules2.content_height_valid(value, height), RuleMeasurement.single_interactive_owner(root, key, source), height, evidence)),
    MeasurementEvidence.measurements_content_height_valid(value, height))

def RuleMeasurement.foreign_root_owner_rejected(key, source, owner_key, target, tree, attributes, style, evidence):
  Equal.cong(Bool, Bool, (owned => owned && RuleMeasurement.target_interactive_owner(target, source)),
    String.eq(owner_key, key), False{}, evidence)

def RuleMeasurement.foreign_root_source_rejected(key, source, owner_key, identity, tree, attributes, style, evidence):
  Equal.trans(Bool,
    (String.eq(owner_key, key) && Code.belongs(identity, source)), (String.eq(owner_key, key) && False{}), False{},
    Equal.cong(Bool, Bool, (belongs => String.eq(owner_key, key) && belongs), Code.belongs(identity, source), False{}, evidence),
    probe_and_false(String.eq(owner_key, key)))

def viewport_purpose_complete(+first: Content.Purpose, +second: Content.Purpose) ->
  {RulePhysicalContentRules2.same_purpose(first, second) == RuleMeasurement.required_viewport_purpose(first, second) : Bool}:
  match first second:
    case Content.Natural{} Content.Natural{}: {==}
    case Content.Natural{} Content.AtWidth{width}: {==}
    case Content.AtWidth{width} Content.Natural{}: {==}
    case Content.AtWidth{first_width} Content.AtWidth{second_width}: {==}

def viewport_key_guard_complete(+eligible: Bool, +encoded: String, +target: Source.NativeTarget) ->
  {NativePhysical.viewport_key_matches(eligible, encoded, target) ==
    Bool.and(eligible, String.eq(encoded, Source.target_key(target))) : Bool}:
  match eligible:
    case True{}: {==}
    case False{}: {==}

def viewport_slot_keys(+eligible: Bool, +target: Source.NativeTarget, +observed: Source.NativeTarget) ->
  {Bool.and(eligible, String.eq(Source.target_key(target), Source.target_key(observed))) == Bool.and(eligible, String.eq(Dimensions.target_key(target), Dimensions.target_key(observed))) : Bool}:
  %Equal.sym(String, Source.target_key(target), Dimensions.target_key(target), MeasurementEvidence.target_key(target)) :
    {Bool.and(eligible, String.eq(_, Source.target_key(observed))) == Bool.and(eligible, String.eq(Dimensions.target_key(target), Dimensions.target_key(observed))) : Bool}
  Equal.cong(String, Bool, (key => Bool.and(eligible, String.eq(Dimensions.target_key(target), key))),
    Source.target_key(observed), Dimensions.target_key(observed), MeasurementEvidence.target_key(observed))

def viewport_matches_prepared_key(+generation: Nat, +owner: String, +purpose: Content.Purpose, +target: Source.NativeTarget, +value: Content.NativeViewport) ->
  {NativePhysical.viewport_matches_key(generation, owner, purpose, Source.target_key(target), value) == RuleMeasurement.required_viewport_matches(NativePhysical.Query{generation, owner, purpose, target}, value) : Bool}:
  match value:
    case Content.NativeViewport{+observed_generation, +observed_owner, +observed_purpose, +observed_target, +bounds}:
      +eligible = Nat.is_eq(generation, observed_generation) && String.eq(owner, observed_owner) && RulePhysicalContentRules2.same_purpose(purpose, observed_purpose)
      +required = Nat.is_eq(generation, observed_generation) && String.eq(owner, observed_owner) && RuleMeasurement.required_viewport_purpose(purpose, observed_purpose)
      +seen: Content.NativeViewport = Content.NativeViewport{observed_generation, observed_owner, observed_purpose, observed_target, bounds}
      Equal.trans(Bool, NativePhysical.viewport_matches_key(generation, owner, purpose, Source.target_key(target), seen),
        Bool.and(eligible, String.eq(Source.target_key(target), Source.target_key(observed_target))), RuleMeasurement.required_viewport_matches(NativePhysical.Query{generation, owner, purpose, target}, seen),
        viewport_key_guard_complete(eligible, Source.target_key(target), observed_target),
        Equal.trans(Bool, Bool.and(eligible, String.eq(Source.target_key(target), Source.target_key(observed_target))),
          Bool.and(required, String.eq(Source.target_key(target), Source.target_key(observed_target))), RuleMeasurement.required_viewport_matches(NativePhysical.Query{generation, owner, purpose, target}, seen),
          Equal.cong(Bool, Bool, (same => Bool.and(Nat.is_eq(generation, observed_generation) && String.eq(owner, observed_owner) && same, String.eq(Source.target_key(target), Source.target_key(observed_target)))),
            RulePhysicalContentRules2.same_purpose(purpose, observed_purpose), RuleMeasurement.required_viewport_purpose(purpose, observed_purpose), viewport_purpose_complete(purpose, observed_purpose)),
          viewport_slot_keys(required, target, observed_target)))

def viewport_lazy_pick_complete(+same: Bool, +value: Content.NativeViewport,
  fallback: Unit -> Maybe<&2, Content.NativeViewport>) ->
  {NativePhysical.select_viewport_lazy(same, value, fallback) ==
    RuleMeasurement.required_viewport_pick(same, value, fallback(Unit{})) : Maybe<&2, Content.NativeViewport>}:
  match same:
    case True{}: {==}
    case False{}: {==}

def viewport_scan_complete(+generation: Nat, +owner: String, +purpose: Content.Purpose,
  +target: Source.NativeTarget, +values: +List<Content.NativeViewport>) ->
  {NativePhysical.viewport_with_key(generation, owner, purpose, Source.target_key(target), values) ==
    RuleMeasurement.required_viewport(NativePhysical.Query{generation, owner, purpose, target}, values) : Maybe<&2, Content.NativeViewport>}:
  match values:
    case Nil{}: {==}
    case Con{+value, +rest}:
      +encoded = Source.target_key(target)
      +query: NativePhysical.Query = NativePhysical.Query{generation, owner, purpose, target}
      +actual_tail: Maybe<&2, Content.NativeViewport> = NativePhysical.viewport_with_key(generation, owner, purpose, encoded, rest)
      +expected_tail: Maybe<&2, Content.NativeViewport> = RuleMeasurement.required_viewport(query, rest)
      +actual_match: Bool = NativePhysical.viewport_matches_key(generation, owner, purpose, encoded, value)
      +expected_match: Bool = RuleMeasurement.required_viewport_matches(query, value)
      +actual_step: Maybe<&2, Content.NativeViewport> = RuleMeasurement.required_viewport_pick(actual_match, value, actual_tail)
      +matched_step: Maybe<&2, Content.NativeViewport> = RuleMeasurement.required_viewport_pick(expected_match, value, actual_tail)
      Equal.trans(Maybe<&2, Content.NativeViewport>,
        NativePhysical.viewport_with_key(generation, owner, purpose, encoded, value <> rest), actual_step,
        RuleMeasurement.required_viewport(query, value <> rest),
        viewport_lazy_pick_complete(actual_match, value, (_ => actual_tail)),
        Equal.trans(Maybe<&2, Content.NativeViewport>, actual_step, matched_step,
          RuleMeasurement.required_viewport(query, value <> rest),
          Equal.cong(Bool, Maybe<&2, Content.NativeViewport>,
            (same => RuleMeasurement.required_viewport_pick(same, value, actual_tail)),
            actual_match, expected_match, viewport_matches_prepared_key(generation, owner, purpose, target, value)),
          Equal.cong(Maybe<&2, Content.NativeViewport>, Maybe<&2, Content.NativeViewport>,
            (tail => RuleMeasurement.required_viewport_pick(expected_match, value, tail)),
            actual_tail, expected_tail, viewport_scan_complete(generation, owner, purpose, target, rest))))

def viewport_scan_key_correspondence(+generation: Nat, +owner: String, +purpose: Content.Purpose,
  +target: Source.NativeTarget, +encoded: String, +values: +List<Content.NativeViewport>,
  correct: {encoded == Source.target_key(target) : String}) ->
  {NativePhysical.viewport_with_key(generation, owner, purpose, encoded, values) ==
    RuleMeasurement.required_viewport(NativePhysical.Query{generation, owner, purpose, target}, values) : Maybe<&2, Content.NativeViewport>}:
  Equal.trans(Maybe<&2, Content.NativeViewport>,
    NativePhysical.viewport_with_key(generation, owner, purpose, encoded, values),
    NativePhysical.viewport_with_key(generation, owner, purpose, Source.target_key(target), values),
    RuleMeasurement.required_viewport(NativePhysical.Query{generation, owner, purpose, target}, values),
    Equal.cong(String, Maybe<&2, Content.NativeViewport>,
      (key => NativePhysical.viewport_with_key(generation, owner, purpose, key, values)),
      encoded, Source.target_key(target), correct),
    viewport_scan_complete(generation, owner, purpose, target, values))

def RuleMeasurement.viewport_matches_complete(query, value):
  match query:
    case NativePhysical.Query{generation, owner, purpose, target}:
      viewport_matches_prepared_key(generation, owner, purpose, target, value)

def complete_viewport_lookup(+query: NativePhysical.Query, +values: +List<Content.NativeViewport>) ->
  {NativePhysical.viewport(query, values) == RuleMeasurement.required_viewport(query, values) : Maybe<&2, Content.NativeViewport>}:
  match query values:
    case NativePhysical.Query{generation, owner, purpose, target} Nil{}: {==}
    case NativePhysical.Query{generation, owner, purpose, target} Con{value, rest}:
      viewport_scan_complete(generation, owner, purpose, target, value <> rest)

def RuleMeasurement.viewport_complete(query, values):
  complete_viewport_lookup(query, values)

def RuleMeasurement.viewport_empty(query):
  match query:
    case NativePhysical.Query{generation, owner, purpose, target}: {==}

def required_viewport_head(+query: NativePhysical.Query, +value: Content.NativeViewport,
  +rest: +List<Content.NativeViewport>, accepted: {RuleMeasurement.required_viewport_matches(query, value) == True{} : Bool}) ->
  {RuleMeasurement.required_viewport(query, value <> rest) == Some{value} : Maybe<&2, Content.NativeViewport>}:
  Equal.cong(Bool, Maybe<&2, Content.NativeViewport>,
    (same => RuleMeasurement.required_viewport_pick(same, value, RuleMeasurement.required_viewport(query, rest))),
    RuleMeasurement.required_viewport_matches(query, value), True{}, accepted)

def required_viewport_skip(+query: NativePhysical.Query, +value: Content.NativeViewport,
  +rest: +List<Content.NativeViewport>, rejected: {RuleMeasurement.required_viewport_matches(query, value) == False{} : Bool}) ->
  {RuleMeasurement.required_viewport(query, value <> rest) == RuleMeasurement.required_viewport(query, rest) : Maybe<&2, Content.NativeViewport>}:
  Equal.cong(Bool, Maybe<&2, Content.NativeViewport>,
    (same => RuleMeasurement.required_viewport_pick(same, value, RuleMeasurement.required_viewport(query, rest))),
    RuleMeasurement.required_viewport_matches(query, value), False{}, rejected)

def RuleMeasurement.viewport_matching_head(query, value, rest, accepted):
  Equal.trans(Maybe<&2, Content.NativeViewport>, NativePhysical.viewport(query, value <> rest),
    RuleMeasurement.required_viewport(query, value <> rest), Some{value},
    complete_viewport_lookup(query, value <> rest), required_viewport_head(query, value, rest, accepted))

def RuleMeasurement.viewport_nonmatching_head(query, value, rest, rejected):
  Equal.trans(Maybe<&2, Content.NativeViewport>, NativePhysical.viewport(query, value <> rest),
    RuleMeasurement.required_viewport(query, value <> rest), NativePhysical.viewport(query, rest),
    complete_viewport_lookup(query, value <> rest),
    Equal.trans(Maybe<&2, Content.NativeViewport>, RuleMeasurement.required_viewport(query, value <> rest),
      RuleMeasurement.required_viewport(query, rest), NativePhysical.viewport(query, rest),
      required_viewport_skip(query, value, rest, rejected),
      Equal.sym(Maybe<&2, Content.NativeViewport>, NativePhysical.viewport(query, rest), RuleMeasurement.required_viewport(query, rest),
        complete_viewport_lookup(query, rest))))

def RuleMeasurement.viewport_first_duplicate(query, first, second, rest, first_matches, second_matches):
  Equal.trans(Maybe<&2, Content.NativeViewport>, NativePhysical.viewport(query, first <> second <> rest),
    RuleMeasurement.required_viewport(query, first <> second <> rest), Some{first},
    complete_viewport_lookup(query, first <> second <> rest), required_viewport_head(query, first, second <> rest, first_matches))

def height_lazy_complete(+matches: Bool, +height: Nat, fallback: Unit -> Maybe<&2, Nat>) ->
  {Allocation.select_height_lazy(matches, height, fallback) ==
    RulePhysicalSourceRules.required_height_pick(matches, height, fallback(Unit{})) : Maybe<&2, Nat>}:
  match matches:
    case False{}: {==}
    case True{}: {==}

def height_scan_complete(+samples: +List<Model.HeightSample>, +key: String, +width: Nat) ->
  {Allocation.find_height_samples(samples, key, width) ==
    RulePhysicalSourceRules.required_height_scan(samples, key, width) : Maybe<&2, Nat>}:
  match samples:
    case Nil{}: {==}
    case Con{Model.HeightSample{+sample_key, +sample_width, +height}, +rest}:
      +actual_tail: Maybe<&2, Nat> = Allocation.find_height_samples(rest, key, width)
      +expected_tail: Maybe<&2, Nat> = RulePhysicalSourceRules.required_height_scan(rest, key, width)
      +actual_match: Bool = SafeText.string_equal(key, sample_key) && Nat.is_eq(width, sample_width)
      +expected_match: Bool = String.eq(key, sample_key) && Nat.is_eq(width, sample_width)
      +actual_step: Maybe<&2, Nat> = RulePhysicalSourceRules.required_height_pick(actual_match, height, actual_tail)
      +matched_step: Maybe<&2, Nat> = RulePhysicalSourceRules.required_height_pick(expected_match, height, actual_tail)
      Equal.trans(Maybe<&2, Nat>,
        Allocation.find_height_samples(Model.HeightSample{sample_key, sample_width, height} <> rest, key, width), actual_step,
        RulePhysicalSourceRules.required_height_scan(Model.HeightSample{sample_key, sample_width, height} <> rest, key, width),
        height_lazy_complete(actual_match, height, (_ => actual_tail)),
        Equal.trans(Maybe<&2, Nat>, actual_step, matched_step,
          RulePhysicalSourceRules.required_height_scan(Model.HeightSample{sample_key, sample_width, height} <> rest, key, width),
          Equal.cong(Bool, Maybe<&2, Nat>,
            (matches => RulePhysicalSourceRules.required_height_pick(matches, height, actual_tail)),
            actual_match, expected_match,
            Equal.cong(Bool, Bool, (same => same && Nat.is_eq(width, sample_width)),
              SafeText.string_equal(key, sample_key), String.eq(key, sample_key), TextProof.public_refines(key, sample_key))),
          Equal.cong(Maybe<&2, Nat>, Maybe<&2, Nat>,
            (tail => RulePhysicalSourceRules.required_height_pick(expected_match, height, tail)),
            actual_tail, expected_tail, height_scan_complete(rest, key, width))))

def RulePhysicalSourceRules.height_lookup_complete(samples, key, width):
  height_scan_complete(samples, key, width)

def RulePhysicalSourceRules.public_height_lookup_complete(key, width, samples):
  height_scan_complete(samples, key, width)

def leaf_height_complete(+height: Model.Height, +width: Nat, +samples: +List<Model.HeightSample>) ->
  {Allocation.leaf_height(height, width, samples) ==
    RulePhysicalSourceRules.required_leaf_height(height, width, samples) : Maybe<&2, Nat>}:
  match height:
    case Model.FixedHeight{value}: {==}
    case Model.HeightAtWidth{key}: height_scan_complete(samples, key, width)

def RulePhysicalSourceRules.leaf_height_lookup_complete(height, width, samples):
  leaf_height_complete(height, width, samples)

def leaf_height_completion_complete(~A: Data, ~E: Data, +sample: Maybe<&2, Nat>,
  +key: String, +value: A, +interaction: Model.Interaction<E>, +rule: Model.Rule,
  +demand: Space.Demand, +height: Model.Height, +inner_width: Nat, +outer_width: Nat,
  +offset: Nat, +parent: Allocation.WidthReturn<A, E>, +samples: +List<Model.HeightSample>) ->
  {Allocation.width_step(~A, ~E,
    Allocation.WidthLeafHeight{sample, key, value, interaction, rule, demand, height, inner_width, outer_width, offset, parent}, samples) ==
    RulePhysicalSourceRules.required_leaf_height_completion(~A, ~E, sample, key, value, interaction, rule, demand, height, inner_width, outer_width, offset, parent) : Allocation.WidthState<A, E>}:
  match sample height:
    case None{} Model.FixedHeight{fixed}: {==}
    case None{} Model.HeightAtWidth{identity}: {==}
    case Some{content_height} Model.FixedHeight{fixed}: {==}
    case Some{content_height} Model.HeightAtWidth{identity}: {==}

def RulePhysicalSourceRules.width_leaf_measurement_result(A, E, key, value, interaction, rule, demand, height, inner_width, outer_width, offset, parent, samples):
  leaf_height_completion_complete(~A, ~E, RulePhysicalSourceRules.required_leaf_height(height, inner_width, samples), key, value, interaction, rule, demand, height, inner_width, outer_width, offset, parent, samples)

def complete_measured_receipt(+request: Content.Request, +rule: Model.Rule, +roots: +List<Content.NativeRoot>, +policies: +List<Content.NativePolicy>, +observations: +List<Content.Observation>) ->
  {SourceSource.measured(request, rule, roots, policies, observations) == Dimensions.receipt(RuleMeasurement.required_receipt(request, observations), request, rule, roots, policies) : SourceSource.Forest}:
  Equal.trans(SourceSource.Forest, SourceSource.measured(request, rule, roots, policies, observations),
    SourceSource.receipt(RuleMeasurement.required_receipt(request, observations), request, rule, roots, policies),
    Dimensions.receipt(RuleMeasurement.required_receipt(request, observations), request, rule, roots, policies),
    Equal.cong((Maybe<&2, Content.Observation>), SourceSource.Forest, (found => SourceSource.receipt(found, request, rule, roots, policies)),
      RulePhysicalContentRules2.find(request, observations), RuleMeasurement.required_receipt(request, observations), receipt_scan_complete(observations, request)),
    MeasurementEvidence.sourcesource_receipt(RuleMeasurement.required_receipt(request, observations), request, rule, roots, policies))

def RuleMeasurement.measured_receipt_complete(request, rule, roots, policies, observations): complete_measured_receipt(request, rule, roots, policies, observations)

def complete_preparation_receipt(+request: Content.Request, +rule: Model.Rule, +roots: +List<Content.NativeRoot>, +policies: +List<Content.NativePolicy>, +observations: +List<Content.Observation>, +snapshot: Content.Snapshot) ->
  {SourceSource.preparation(SourceSource.measured(request, rule, roots, policies, observations), snapshot) == Dimensions.preparation(Dimensions.receipt(RuleMeasurement.required_receipt(request, observations), request, rule, roots, policies), snapshot) : Content.Preparation}:
  Equal.trans(Content.Preparation, SourceSource.preparation(SourceSource.measured(request, rule, roots, policies, observations), snapshot),
    SourceSource.preparation(Dimensions.receipt(RuleMeasurement.required_receipt(request, observations), request, rule, roots, policies), snapshot),
    Dimensions.preparation(Dimensions.receipt(RuleMeasurement.required_receipt(request, observations), request, rule, roots, policies), snapshot),
    Equal.cong(SourceSource.Forest, Content.Preparation, (forest => SourceSource.preparation(forest, snapshot)),
      SourceSource.measured(request, rule, roots, policies, observations), Dimensions.receipt(RuleMeasurement.required_receipt(request, observations), request, rule, roots, policies), complete_measured_receipt(request, rule, roots, policies, observations)),
    MeasurementEvidence.sourcesource_preparation(Dimensions.receipt(RuleMeasurement.required_receipt(request, observations), request, rule, roots, policies), snapshot))

def RuleMeasurement.preparation_receipt_complete(request, rule, roots, policies, observations, snapshot): complete_preparation_receipt(request, rule, roots, policies, observations, snapshot)
