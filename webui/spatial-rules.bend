import Base
import ./design.bend as Model

def contains(outer: Model.Box, inner: Model.Box) -> Bool:
  Model.Box{+outer_left, +outer_top, outer_width, outer_height} = outer
  Model.Box{+inner_left, +inner_top, inner_width, inner_height} = inner
  Bool.and(Nat.is_le(outer_left, inner_left),
    Bool.and(Nat.is_le(outer_top, inner_top),
      Bool.and(Nat.is_le(Nat.add(inner_left, inner_width), Nat.add(outer_left, outer_width)),
        Nat.is_le(Nat.add(inner_top, inner_height), Nat.add(outer_top, outer_height)))))

def all_contained(+target: Model.Box, placements: +List<Model.NodePlacement>) -> Bool:
  match placements:
    case Nil{}: True{}
    case Con{Model.NodePlacement{key, bounds}, rest}:
      Bool.and(contains(target, bounds), all_contained(target, rest))
