import Base
import ./SPACE.bend as Space
import ./geometry-contract.bend as SpaceLaws
import ./PROGRAM.bend as Allocation
import ./physical-space.bend as Model
import ./GEOMETRY.bend as Spatial
import ../../interaction/IDENTITY.bend as UIIdentity
import ./SOURCE.bend as Source
import ./CONTENT.bend as Content
import ./measurement-contract.bend as ContentRules
import ../document/SOURCE.bend as Authored
import ./enclosure.bend as Enclosure
import ../appearance/TYPOGRAPHY.bend as T
import ../document/MODEL.bend as Doc
import ./physical-content-measurement.bend as ContentRules2

# Successful shared packing retains the original authored dimension contract.
def SharedClaim(~A: Data, +slots: +List<Space.Slot<A>>, +gap: Nat, +available: Nat, result: Space.Packing<A>) -> Type:
  match result:
    case Space.Insufficient{required, received}: Unit
    case Space.Packed{placements, unused}:
      SpaceLaws.AllocationEvidence<A, slots, gap, 0n, available, Space.Allocation{placements, unused}>

# Rigid extents are selected directly, without reflecting boolean equality.

def rigid_extent(dimension: Space.Dimension, extent: Nat) -> Type:
  match dimension:
    case Space.Rigid{declared}: {extent == declared : Nat}
    case _: Unit

def rigid_extents(~A: Data, slots: +List<Space.Slot<A>>, placements: +List<Space.Placement<A>>) -> Type:
  match slots placements:
    case Nil{} Nil{}: Unit
    case Con{Space.Slot{value, +dimension}, rest} Con{Space.Placement{other, offset, extent}, tail}:
      rigid_extent(dimension, extent) & rigid_extents(~A, rest, tail)
    case _ _: Empty

def allocation_rigid_extents(~A: Data, slots: +List<Space.Slot<A>>, allocation: Space.Allocation<A>) -> Type:
  Space.Allocation{placements, unused} = allocation
  rigid_extents(~A, slots, placements)

law rigid_placement:
  for ~A: Data
  for +slots: +List<Space.Slot<A>>
  for +gap: Nat
  for +offset: Nat
  for +budget: Nat
  allocation_rigid_extents(~A, slots, Space.place_from(~A, slots, gap, offset, budget))

law shared_packing:
  for ~A: Data
  for +slots: +List<Space.Slot<A>>
  for +gap: Nat
  for +available: Nat
  SharedClaim(~A, slots, gap, available, Allocation.shared_pack(~A, slots, gap, available))

def width_completed(~A: Data, ~E: Data, state: Allocation.WidthState<A, E>) -> Bool:
  match state:
    case Allocation.WidthDone{result}: True{}
    case _: False{}

def width_complete_claim(~A: Data, ~E: Data, +tree: Model.Tree<A, E>, +width: Nat, +offset: Nat, +samples: +List<Model.HeightSample>) -> Type:
  {width_completed(~A, ~E, Allocation.iterate_width(~A, ~E, tree, width, offset, samples)) == True{} : Bool}

type WidthRequirements<-A: Data, -E: Data> is Type:
  WidthRequirements{
    complete: @+tree:Model.Tree<A, E> -> @+width:Nat -> @+offset:Nat -> @+samples:+List<Model.HeightSample> ->
      width_complete_claim(~A, ~E, tree, width, offset, samples)}

law width_evidence:
  for ~A: Data
  for ~E: Data
  WidthRequirements<A, E>

def height_source_source_claim(~A: Data, ~E: Data, +source: Model.Tree<A, E>, result: Allocation.PositionedOutcome<A, E>) -> Type:
  match result:
    case Allocation.Positioned{tree}: {Allocation.source_of_allocated(~A, ~E, tree) == source : Model.Tree<A, E>}
    case _: {True{} == True{} : Bool}

type HeightSourceRequirements<-A: Data, -E: Data> is Type:
  HeightSourceRequirements{preserved: @+tree:Allocation.MeasuredTree<A, E> -> @+bounds:Spatial.Box ->
    height_source_source_claim(~A, ~E, Allocation.source_of_measured(~A, ~E, tree), Allocation.allocate_measured(~A, ~E, tree, bounds))}

law height_source_evidence:
  for ~A: Data
  for ~E: Data
  HeightSourceRequirements<A, E>

def field_native_footprint(+kind: Authored.NativeFieldKind, +node: Authored.Node, +key: String,
  +style: Authored.ResolvedStyle, +generation: Nat, +observations: +List<Content.Observation>) -> Type:
  {Source.field(True{}, kind, node, key, style, generation, observations) ==
    Source.measured(Content.Request{generation, key, Content.local_value(node, Source.resolved_font(style)), Content.Natural{}, Nil{}, Nil{}},
      Authored.native_field_rule(kind, style), Nil{}, Nil{}, observations) : Source.Forest}

def native_targets_claim(+snapshot: Content.Snapshot, +observations: +List<Content.Observation>) -> Type:
  {ContentRules2.ready_native_targets_valid(Source.prepare(snapshot, observations)) == True{} : Bool}

def minimum_width(demand: Space.Demand) -> Nat:
  Space.Demand{Enclosure.Extent{width, height}, preferred} = demand
  width

def preferred_width(demand: Space.Demand) -> Nat:
  Space.Demand{minimum, Enclosure.Extent{width, height}} = demand
  width

def minimum_height(demand: Space.Demand) -> Nat:
  Space.Demand{Enclosure.Extent{width, height}, preferred} = demand
  height

def preferred_height(demand: Space.Demand) -> Nat:
  Space.Demand{minimum, Enclosure.Extent{width, height}} = demand
  height

def column_floor(policy: Authored.FieldPolicy, observation: Content.Observation) -> Nat:
  Authored.FieldPolicy{columns, minimum_lines, maximum_lines} = policy
  Content.Observation{generation, key, purpose, minimum, preferred, height, advance} = observation
  Nat.mul(columns, advance)

def observed_minimum(observation: Content.Observation) -> Nat:
  Content.Observation{generation, key, purpose, minimum, preferred, height, advance} = observation
  minimum

def observed_preferred(observation: Content.Observation) -> Nat:
  Content.Observation{generation, key, purpose, minimum, preferred, height, advance} = observation
  preferred

def fixed_field_height(+capacity: Nat, policy: Authored.FieldPolicy,
  +font: T.Presentation, observation: Content.Observation) -> Nat:
  Authored.FieldPolicy{columns, minimum_lines, maximum_lines} = policy
  Content.Observation{generation, key, purpose, minimum, preferred, +height, advance} = observation
  +line_height = T.resolved_line_height(T.resolve_presentation(capacity, font))
  +floor = Nat.mul(minimum_lines, line_height)
  Nat.max(floor, height)

def variable_field_height(+capacity: Nat, policy: Authored.FieldPolicy,
  +font: T.Presentation, observation: Content.Observation) -> Nat:
  Authored.FieldPolicy{columns, minimum_lines, maximum_lines} = policy
  Content.Observation{generation, key, purpose, minimum, preferred, +height, advance} = observation
  +line_height = T.resolved_line_height(T.resolve_presentation(capacity, font))
  +floor = Nat.mul(minimum_lines, line_height)
  Nat.max(floor, Nat.min(Nat.mul(maximum_lines, line_height), height))

def expected_height(+capacity: Nat, kind: Authored.NativeFieldKind, policy: Authored.FieldPolicy,
  +font: T.Presentation, observation: Content.Observation) -> Nat:
  match kind:
    case Authored.TextField{}: fixed_field_height(capacity, policy, font, observation)
    case Authored.MessageField{}: variable_field_height(capacity, policy, font, observation)
    case Authored.TextAreaField{}: variable_field_height(capacity, policy, font, observation)
    case Authored.SelectField{}: fixed_field_height(capacity, policy, font, observation)
    case Authored.MultiSelectField{}: fixed_field_height(capacity, policy, font, observation)
    case Authored.ToggleField{}: fixed_field_height(capacity, policy, font, observation)
    case Authored.NumberField{minimum}: fixed_field_height(capacity, policy, font, observation)
    case Authored.FileField{multiple}: fixed_field_height(capacity, policy, font, observation)
    case Authored.DirectoryField{}: fixed_field_height(capacity, policy, font, observation)
    case Authored.SearchField{}: fixed_field_height(capacity, policy, font, observation)
    case Authored.SecretField{}: fixed_field_height(capacity, policy, font, observation)

def first_leaf_demand(forest: Source.Forest) -> Maybe<&2, Space.Demand>:
  match forest:
    case Source.ReadyForest{Con{Model.Leaf{key, value, interaction, rule, demand, height}, rest}, roots, policies}: Some{demand}
    case Source.ReadyForest{Nil{}, roots, policies}: None{}
    case Source.ReadyForest{Con{Model.Container{key, value, interaction, rule, children}, rest}, roots, policies}: None{}
    case Source.MissingForest{first, remaining}: None{}
    case Source.InvalidForest{error}: None{}

type SourceRequirements is Type:
  SourceRequirements{
    field_native_footprint: @+kind:Authored.NativeFieldKind -> @+node:Authored.Node -> @+key:String -> @+style:Authored.ResolvedStyle -> @+generation:Nat -> @+observations:+List<Content.Observation> -> field_native_footprint(kind, node, key, style, generation, observations),
    native_targets: @+snapshot:Content.Snapshot -> @+observations:+List<Content.Observation> ->
    native_targets_claim(snapshot, observations),
    field_width_formula: @+capacity:Nat -> @+kind:Authored.NativeFieldKind -> @+policy:Authored.FieldPolicy -> @+font:T.Presentation -> @+observation:Content.Observation ->
      {minimum_width(Source.field_natural_demand_at(capacity, kind, policy, font, observation)) == Nat.max(column_floor(policy, observation), observed_minimum(observation)) : Nat},
    field_column_floor: @+capacity:Nat -> @+kind:Authored.NativeFieldKind -> @+policy:Authored.FieldPolicy -> @+font:T.Presentation -> @+observation:Content.Observation ->
      {Nat.is_ge(minimum_width(Source.field_natural_demand_at(capacity, kind, policy, font, observation)), column_floor(policy, observation)) == True{} : Bool},
    field_observed_minimum: @+capacity:Nat -> @+kind:Authored.NativeFieldKind -> @+policy:Authored.FieldPolicy -> @+font:T.Presentation -> @+observation:Content.Observation ->
      {Nat.is_ge(minimum_width(Source.field_natural_demand_at(capacity, kind, policy, font, observation)), observed_minimum(observation)) == True{} : Bool},
    field_preferred_width: @+capacity:Nat -> @+kind:Authored.NativeFieldKind -> @+policy:Authored.FieldPolicy -> @+font:T.Presentation -> @+observation:Content.Observation ->
      {preferred_width(Source.field_natural_demand_at(capacity, kind, policy, font, observation)) == Nat.max(minimum_width(Source.field_natural_demand_at(capacity, kind, policy, font, observation)), observed_preferred(observation)) : Nat},
    field_minimum_height: @+capacity:Nat -> @+kind:Authored.NativeFieldKind -> @+policy:Authored.FieldPolicy -> @+font:T.Presentation -> @+observation:Content.Observation ->
      {minimum_height(Source.field_natural_demand_at(capacity, kind, policy, font, observation)) == expected_height(capacity, kind, policy, font, observation) : Nat},
    field_preferred_height: @+capacity:Nat -> @+kind:Authored.NativeFieldKind -> @+policy:Authored.FieldPolicy -> @+font:T.Presentation -> @+observation:Content.Observation ->
      {preferred_height(Source.field_natural_demand_at(capacity, kind, policy, font, observation)) == expected_height(capacity, kind, policy, font, observation) : Nat},
    field_production_demand: @+capacity:Nat -> @+label:UIIdentity.Key -> @+kind:Authored.NativeFieldKind -> @+style:Authored.Style -> @+attributes:+List<Authored.Attribute> ->
      @+value:String -> @+placeholder:String -> @+options:+List<Authored.Choice> -> @+policy:Authored.FieldPolicy -> @+name:String ->
      @+enabled:Bool -> @+first_event:Doc.DOMEvent -> @+remaining_events:+List<Doc.DOMEvent> -> @+key:String -> @+font:T.Presentation ->
      @+rule:Model.Rule -> @+observation:Content.Observation -> @+roots:+List<Content.NativeRoot> -> @+policies:+List<Content.NativePolicy> ->
      {first_leaf_demand(Source.observed_leaf_at(capacity, Authored.Field{label, kind, style, attributes, value, placeholder, options, policy,
        name, enabled, first_event, remaining_events}, key, font, rule, observation, roots, policies)) ==
        Some{Source.field_natural_demand_at(capacity, kind, policy, font, observation)} : Maybe<&2, Space.Demand>}}

law source_evidence:
  SourceRequirements

def width_source_source_claim(~A: Data, ~E: Data, +source: Model.Tree<A, E>, result: Allocation.WidthOutcome<A, E>) -> Type:
  match result:
    case Allocation.WidthReady{tree}: {Allocation.source_of_measured(~A, ~E, tree) == source : Model.Tree<A, E>}
    case _: {True{} == True{} : Bool}

type WidthSourceRequirements<-A: Data, -E: Data> is Type:
  WidthSourceRequirements{preserved: @+tree:Model.Tree<A, E> -> @+width:Nat -> @+samples:+List<Model.HeightSample> ->
    width_source_source_claim(~A, ~E, tree, Allocation.fit_width(~A, ~E, tree, width, samples))}

law width_source_evidence:
  for ~A: Data
  for ~E: Data
  WidthSourceRequirements<A, E>

def InlinePopulation(~A: Data, ~E: Data, +children: +List<Model.Tree<A, E>>, result: Allocation.InlinePlan<A, E>) -> Type:
  match result:
    case Allocation.InlinePlanned{placements, direction, canvas}:
      {SpaceLaws.placement_values(~Model.Tree<A, E>, placements) == children : +List<Model.Tree<A, E>>}
    case Allocation.InlineFailure{failure}: {True{} == True{} : Bool}

def BlockPopulation(~A: Data, ~E: Data, +children: +List<Allocation.MeasuredTree<A, E>>, result: Allocation.ChildPlan<Allocation.MeasuredTree<A, E>>) -> Type:
  match result:
    case Allocation.ChildrenPlanned{placements, canvas}:
      {SpaceLaws.placement_values(~Allocation.MeasuredTree<A, E>, placements) == children : +List<Allocation.MeasuredTree<A, E>>}
    case Allocation.PlanningFailure{failure}: {True{} == True{} : Bool}

type AllocationPopulationRequirements<-A: Data, -E: Data> is Type:
  AllocationPopulationRequirements{
    inline_population: @+key:String -> @+rule:Model.Rule -> @+children:+List<Model.Tree<A, E>> -> @+available:Nat ->
      InlinePopulation(~A, ~E, children, Allocation.prepare_inline_children(~A, ~E, key, rule, children, available)),
    block_population: @+key:String -> @+rule:Model.Rule -> @+direction:Allocation.ResolvedDirection ->
      @+children:+List<Allocation.MeasuredTree<A, E>> -> @+available:Nat ->
      BlockPopulation(~A, ~E, children, Allocation.prepare_block_children(~A, ~E, key, rule, direction, children, available))}

law allocation_population_evidence:
  for ~A: Data
  for ~E: Data
  AllocationPopulationRequirements<A, E>

def aligned_bounds(outside: Enclosure.Insets, horizontal: Spatial.Alignment, vertical: Spatial.Alignment, +left: Nat, +top: Nat, +available_width: Nat, +available_height: Nat, +width: Nat, +height: Nat) -> Spatial.Box:
  Enclosure.Insets{+inline, +block} = outside
  Spatial.Box{Nat.add(Nat.add(left, inline), Allocation.alignment_offset(horizontal, Nat.sub(Nat.sub(available_width, Nat.mul(2n, inline)), width))),
    Nat.add(Nat.add(top, block), Allocation.alignment_offset(vertical, Nat.sub(Nat.sub(available_height, Nat.mul(2n, block)), height))), width, height}

law aligned_layer_bounds:
  for +outside: Enclosure.Insets
  for +horizontal: Spatial.Alignment
  for +vertical: Spatial.Alignment
  for rule: Model.Rule
  for +left: Nat
  for +top: Nat
  for +available_width: Nat
  for +available_height: Nat
  for +width: Nat
  for +height: Nat
  {Allocation.layered_bounds(Spatial.AlignedLayer{outside, horizontal, vertical}, rule, left, top, available_width, available_height, width, height) ==
    aligned_bounds(outside, horizontal, vertical, left, top, available_width, available_height, width, height) : Spatial.Box}

law aligned_layer_clearance:
  for +outside: Enclosure.Insets
  for horizontal: Spatial.Alignment
  for vertical: Spatial.Alignment
  {Model.position_outside(Spatial.AlignedLayer{outside, horizontal, vertical}) == outside : Enclosure.Insets}

def RootBoundsPolicy(~A: Data, ~E: Data, +position: Spatial.Position, +tree: Allocation.MeasuredTree<A, E>, +offered: Spatial.Box,
  +offset: Nat, +height: Nat, bounds: Spatial.Box) -> Type:
  match position:
    case Spatial.InFlow{}: {bounds == Allocation.inflow_root_bounds(~A, ~E, tree, offered, offset, height) : Spatial.Box}
    case Spatial.CenteredLayer{outside}: {bounds == Allocation.layered_root_bounds(~A, ~E, tree, Spatial.CenteredLayer{outside}, offered, height) : Spatial.Box}
    case Spatial.AlignedLayer{outside, horizontal, vertical}: {bounds == Allocation.layered_root_bounds(~A, ~E, tree, Spatial.AlignedLayer{outside, horizontal, vertical}, offered, height) : Spatial.Box}
    case Spatial.AnchoredLayer{key, anchor, outside, gap, alignment}: {bounds == Allocation.layered_root_bounds(~A, ~E, tree, Spatial.AnchoredLayer{key, anchor, outside, gap, alignment}, offered, height) : Spatial.Box}

law root_position:
  for ~A: Data
  for ~E: Data
  for +tree: Allocation.MeasuredTree<A, E>
  for +offered: Spatial.Box
  for +offset: Nat
  for +height: Nat
  RootBoundsPolicy(~A, ~E, Model.rule_position(Allocation.measured_rule(~A, ~E, tree)), tree, offered, offset, height, Allocation.root_bounds(~A, ~E, tree, offered, offset, height))

law root_width_clearance:
  for ~A: Data
  for ~E: Data
  for +slots: +List<Space.Slot<Model.Tree<A, E>>>
  for +tree: Model.Tree<A, E>
  for +width: Nat
  for +samples: +List<Model.HeightSample>
  {Allocation.dispatch_fit_width_15(~A, ~E, Allocation.SlotsReady{slots}, tree, width, samples) ==
    Allocation.dispatch_fit_width_16(~A, ~E, Allocation.shared_pack(~Model.Tree<A, E>, slots, 0n, Nat.sub(width, Allocation.outside_axis(Allocation.InlineAxis{}, Allocation.tree_rule(~A, ~E, tree)))), tree, samples) : Allocation.WidthOutcome<A, E>}

law root_height_clearance:
  for ~A: Data
  for ~E: Data
  for +slots: +List<Space.Slot<Allocation.MeasuredTree<A, E>>>
  for +tree: Allocation.MeasuredTree<A, E>
  for +offered: Spatial.Box
  {Allocation.dispatch_allocate_root_height_20(~A, ~E, Allocation.SlotsReady{slots}, tree, offered) ==
    Allocation.dispatch_allocate_root_height_21(~A, ~E, Allocation.shared_pack(~Allocation.MeasuredTree<A, E>, slots, 0n, Nat.sub(Allocation.box_height(offered), Allocation.outside_axis(Allocation.BlockAxis{}, Allocation.measured_rule(~A, ~E, tree)))), tree, offered) : Allocation.Outcome<A, E>}

law root_allocation_bounds:
  for ~A: Data
  for ~E: Data
  for +tree: Allocation.MeasuredTree<A, E>
  for +value: Allocation.MeasuredTree<A, E>
  for +rest: +List<Space.Placement<Allocation.MeasuredTree<A, E>>>
  for +offset: Nat
  for +height: Nat
  for +offered: Spatial.Box
  {Allocation.positioned_root_first_placements(~A, ~E, Space.Placement{value, offset, height} <> rest, tree, offered) ==
    Allocation.positioned_outcome(~A, ~E, Allocation.allocate_measured(~A, ~E, value, Allocation.root_bounds(~A, ~E, value, offered, offset, height))) : Allocation.Outcome<A, E>}

law measured_preferred:
  for ~A: Data
  for ~E: Data
  for +tree: Allocation.MeasuredTree<A, E>
  {SpaceLaws.preferred_covers_minimum(Allocation.measured_demand(~A, ~E, tree)) == True{} : Bool}

law measured_authored_floor:
  for ~A: Data
  for ~E: Data
  for +tree: Allocation.MeasuredTree<A, E>
  {SpaceLaws.extent_contains(Model.minimum_demand(Allocation.measured_demand(~A, ~E, tree)), SpaceLaws.rule_authored_minimum(Allocation.measured_rule(~A, ~E, tree))) == True{} : Bool}

def height_completed(~A: Data, ~E: Data, state: Allocation.HeightState<A, E>) -> Bool:
  match state:
    case Allocation.HeightDone{result}: True{}
    case _: False{}

def height_complete_claim(~A: Data, ~E: Data, tree: Allocation.MeasuredTree<A, E>, bounds: Spatial.Box) -> Type:
  {height_completed(~A, ~E, Allocation.iterate_height(~A, ~E, tree, bounds)) == True{} : Bool}

type HeightRequirements<-A: Data, -E: Data> is Type:
  HeightRequirements{
    completion: @+tree:Allocation.MeasuredTree<A, E> -> @+bounds:Spatial.Box -> height_complete_claim(~A, ~E, tree, bounds)}

law height_evidence:
  for ~A: Data
  for ~E: Data
  HeightRequirements<A, E>
