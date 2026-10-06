import Base
import ../text-space-rules.bend as Rule
import ../physical-source.bend as PhysicalSource
import ../physical-content.bend as Content
import ../typography.bend as T
import ./space.bend as Order

def measured_minimum_bound(+observation: Content.Observation) ->
  {Nat.is_le(Rule.minimum_width(PhysicalSource.text_natural_demand(T.SingleLine{}, observation)), PhysicalSource.observation_advance(observation)) == True{} : Bool}:
  Order.min_le_second(PhysicalSource.observation_minimum(observation), PhysicalSource.observation_advance(observation))

def natural_preferred_bound(+observation: Content.Observation) ->
  {Nat.is_le(PhysicalSource.observation_preferred(observation), Rule.preferred_width(PhysicalSource.text_natural_demand(T.SingleLine{}, observation))) == True{} : Bool}:
  Order.max_right(Nat.min(PhysicalSource.observation_minimum(observation), PhysicalSource.observation_advance(observation)), PhysicalSource.observation_preferred(observation))

def demand_policy(+wrapping: T.Wrapping, +observation: Content.Observation) -> Rule.demand_claim(wrapping, observation):
  match wrapping:
    case T.SingleLine{}: {==}
    case T.WrapAnywhere{}: {==}
    case T.WrapWords{}: {==}
    case T.ScrollableCode{}: {==}
    case T.NormalAnywhere{}: {==}
    case T.NormalWords{}: {==}

def attributes_policy(+wrapping: T.Wrapping, +text: String) -> Rule.attributes_claim(wrapping, text):
  match wrapping:
    case T.SingleLine{}: {==}
    case T.WrapAnywhere{}: {==}
    case T.WrapWords{}: {==}
    case T.ScrollableCode{}: {==}
    case T.NormalAnywhere{}: {==}
    case T.NormalWords{}: {==}

def Rule.evidence():
  Rule.Requirements{
    measured_minimum_bound,
    natural_preferred_bound,
    demand_policy,
    label => text => choice => +wrapping => key => font => rule => +observation => roots => policies => {==},
    +capacity => +key => +text => choice => font => bounds => canvas => rule => interaction => styles => owned => {==},
    attributes_policy}
