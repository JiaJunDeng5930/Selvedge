import Base
import ./PROGRAM.bend as Allocation
import ./ADAPTATION.bend as Adaptation
import ./GEOMETRY.bend as Geometry
import ./physical-space.bend as Physical

def inner_width(+bounds: Geometry.Box, +rule: Physical.Rule) ->
  {Adaptation.allocated_inner_width(bounds, rule) ==
    Nat.sub(Adaptation.bounds_width(bounds), Nat.mul(2n, Allocation.inline_inset(rule))) : Nat}:
  Geometry.Box{left, top, width, height} = bounds
  {==}

def first_width_none(+width: Maybe<&2, Nat>) -> {Adaptation.first_width(width, None{}) == width : Maybe<&2, Nat>}:
  match width:
    case None{}: {==}
    case Some{value}: {==}

def first_requirement_none(+value: Maybe<&2, Adaptation.RegionDemand>) ->
  {Adaptation.first_region_demand(value, None{}) == value : Maybe<&2, Adaptation.RegionDemand>}:
  match value:
    case None{}: {==}
    case Some{requirement}: {==}

def Adaptation.evidence():
  Adaptation.Requirements{
    {==}, direction => main => cross => frame => border => width => height => minimum => scroll => position => children => {==},
    key => +value => interaction => +rule => +demand => height => +bounds => canvas => +query => first_requirement_none(Adaptation.observed_region_demand(Adaptation.region_matches(query, value), bounds, rule, Adaptation.preferred_width(demand), None{})),
    key => +value => interaction => +rule => +bounds => canvas => direction => +children => +query => first_requirement_none(Adaptation.observed_region_demand(Adaptation.region_matches(query, value), bounds, rule, Adaptation.container_preferred(rule, children), Adaptation.region_demands(children, query))),
    snapshot => +tree => roots => policies => +query => {==},
    inner_width,
    key => +value => interaction => +rule => demand => height => +bounds => canvas => +query => first_width_none(Adaptation.observed_width(Adaptation.region_matches(query, value), bounds, rule, None{})),
    key => +value => interaction => +rule => +bounds => canvas => direction => +children => +query => first_width_none(Adaptation.observed_width(Adaptation.region_matches(query, value), bounds, rule, Adaptation.region_widths(children, query))),
    +attributes => +name => +value => {==},
    snapshot => +tree => roots => policies => +query => {==}}
