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

def Adaptation.evidence():
  Adaptation.Requirements{inner_width,
    key => +value => interaction => +rule => demand => height => +bounds => canvas => +query => first_width_none(Adaptation.observed_width(Adaptation.region_matches(query, value), bounds, rule, None{})),
    key => +value => interaction => +rule => +bounds => canvas => direction => +children => +query => first_width_none(Adaptation.observed_width(Adaptation.region_matches(query, value), bounds, rule, Adaptation.region_widths(children, query))),
    +attributes => +name => +value => {==},
    snapshot => +tree => roots => policies => +query => {==}}
