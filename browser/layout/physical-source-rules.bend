import Base
import ../../interaction/IDENTITY.bend as UIIdentity
import ./SOURCE.bend as Source
import ./CONTENT.bend as Content
import ./physical-content-rules.bend as ContentRules
import ../document/SOURCE.bend as Authored
import ./physical-space.bend as Model
import ./SPACE.bend as Space
import ./enclosure.bend as Enclosure
import ../appearance/TYPOGRAPHY.bend as T
import ../document/MODEL.bend as Doc

def field_native_footprint(+kind: Authored.NativeFieldKind, +node: Authored.Node, +key: String,
  +style: Authored.ResolvedStyle, +generation: Nat, +observations: +List<Content.Observation>) -> Type:
  {Source.field(True{}, kind, node, key, style, generation, observations) ==
    Source.measured(Content.Request{generation, key, Content.local_value(node, Source.resolved_font(style)), Content.Natural{}, Nil{}, Nil{}},
      Authored.native_field_rule(kind, style), Nil{}, Nil{}, observations) : Source.Forest}

def native_targets_claim(+snapshot: Content.Snapshot, +observations: +List<Content.Observation>) -> Type:
  {ContentRules.ready_native_targets_valid(Source.prepare(snapshot, observations)) == True{} : Bool}

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

type Requirements is Type:
  Requirements{
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

law evidence:
  Requirements
