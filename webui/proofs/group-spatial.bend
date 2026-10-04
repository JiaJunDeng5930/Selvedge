import Base
import ../design.bend as Design
import ../layout.bend as Layout
import ../group-spatial-laws.bend as Rule
import ./space.bend as SProof
import ../spatial-rules.bend as SpatialRules

def and_parts(+a: Bool, +b: Bool, proof: {Bool.and(a, b) == True{} : Bool}) ->
  {a == True{} : Bool} & {b == True{} : Bool}:
  match a:
    case False{}: SProof.impossible({False{} == True{} : Bool} & {b == True{} : Bool}, proof)
    case True{}: ({==}, proof)

def and_join(+a: Bool, +b: Bool, first: {a == True{} : Bool}, second: {b == True{} : Bool}) ->
  {Bool.and(a, b) == True{} : Bool}:
  match a:
    case False{}: SProof.impossible({Bool.and(False{}, b) == True{} : Bool}, first)
    case True{}: second

def max_left(+a: Nat, +b: Nat) -> {Nat.is_le(a, Nat.max(a, b)) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(a, Nat.max(a, b)), Nat.is_ge(Nat.max(a, b), a), True{},
    Equal.sym(Bool, Nat.is_ge(Nat.max(a, b), a), Nat.is_le(a, Nat.max(a, b)), SProof.ge_le(Nat.max(a, b), a)), Nat.max_ge_l(a, b))

def max_right(+a: Nat, +b: Nat) -> {Nat.is_le(b, Nat.max(a, b)) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(b, Nat.max(a, b)), Nat.is_ge(Nat.max(a, b), b), True{},
    Equal.sym(Bool, Nat.is_ge(Nat.max(a, b), b), Nat.is_le(b, Nat.max(a, b)), SProof.ge_le(Nat.max(a, b), b)), Nat.max_ge_r(a, b))

def min_lower(+t: Nat, +a: Nat, +b: Nat,
  pa: {Nat.is_le(t, a) == True{} : Bool}, pb: {Nat.is_le(t, b) == True{} : Bool}) ->
  {Nat.is_le(t, Nat.min(a, b)) == True{} : Bool}:
  match t a b:
    case 0n _ _: SProof.zero_le(Nat.min(a, b))
    case 1n+x 0n _: SProof.impossible({Nat.is_le(1n+x, Nat.min(0n, b)) == True{} : Bool}, pa)
    case 1n+x 1n+y 0n: SProof.impossible({Nat.is_le(1n+x, Nat.min(1n+y, 0n)) == True{} : Bool}, pb)
    case 1n+x 1n+y 1n+z: min_lower(x, y, z, pa, pb)

def max_upper(+a: Nat, +b: Nat, +t: Nat,
  pa: {Nat.is_le(a, t) == True{} : Bool}, pb: {Nat.is_le(b, t) == True{} : Bool}) ->
  {Nat.is_le(Nat.max(a, b), t) == True{} : Bool}:
  match a b t:
    case 0n _ _: pb
    case 1n+x 0n _: pa
    case 1n+x 1n+y 0n: SProof.impossible({Nat.is_le(Nat.max(1n+x, 1n+y), 0n) == True{} : Bool}, pa)
    case 1n+x 1n+y 1n+z: max_upper(x, y, z, pa, pb)

def union_end(+a: Nat, +w: Nat, +b: Nat, +v: Nat) ->
  {Nat.add(Nat.min(a, b), Nat.sub(Nat.max(Nat.add(a, w), Nat.add(b, v)), Nat.min(a, b))) ==
    Nat.max(Nat.add(a, w), Nat.add(b, v)) : Nat}:
  SProof.second({Nat.is_le(0n, Nat.sub(Nat.max(Nat.add(a, w), Nat.add(b, v)), Nat.min(a, b))) == True{} : Bool},
    {Nat.add(Nat.min(a, b), Nat.sub(Nat.max(Nat.add(a, w), Nat.add(b, v)), Nat.min(a, b))) == Nat.max(Nat.add(a, w), Nat.add(b, v)) : Nat},
    SProof.residual(Nat.min(a, b), 0n, Nat.max(Nat.add(a, w), Nat.add(b, v)),
      Equal.trans(Bool, Nat.is_le(Nat.add(Nat.min(a, b), 0n), Nat.max(Nat.add(a, w), Nat.add(b, v))),
        Nat.is_le(Nat.min(a, b), Nat.max(Nat.add(a, w), Nat.add(b, v))), True{},
        Equal.cong(Nat, Bool, (n => Nat.is_le(n, Nat.max(Nat.add(a, w), Nat.add(b, v)))), Nat.add(Nat.min(a, b), 0n), Nat.min(a, b), SProof.add_zero(Nat.min(a, b))),
        SProof.le_trans(Nat.min(a, b), a, Nat.max(Nat.add(a, w), Nat.add(b, v)), SProof.min_le_first(a, b),
          SProof.le_trans(a, Nat.add(a, w), Nat.max(Nat.add(a, w), Nat.add(b, v)), SProof.le_add(a, w), max_left(Nat.add(a, w), Nat.add(b, v)))))))

def tail_parts(+outer: Design.Box, +inner: Design.Box,
  pair: {Nat.is_le(Rule.top(outer), Rule.top(inner)) == True{} : Bool} &
    {Bool.and(Nat.is_le(Rule.right(inner), Rule.right(outer)), Nat.is_le(Rule.bottom(inner), Rule.bottom(outer))) == True{} : Bool}) ->
  {Nat.is_le(Rule.top(outer), Rule.top(inner)) == True{} : Bool} &
    ({Nat.is_le(Rule.right(inner), Rule.right(outer)) == True{} : Bool} & {Nat.is_le(Rule.bottom(inner), Rule.bottom(outer)) == True{} : Bool}):
  (head, tail) = pair
  (head, and_parts(Nat.is_le(Rule.right(inner), Rule.right(outer)), Nat.is_le(Rule.bottom(inner), Rule.bottom(outer)), tail))

def parts_head(+outer: Design.Box, +inner: Design.Box,
  pair: {Nat.is_le(Rule.left(outer), Rule.left(inner)) == True{} : Bool} &
    {Bool.and(Nat.is_le(Rule.top(outer), Rule.top(inner)), Bool.and(Nat.is_le(Rule.right(inner), Rule.right(outer)), Nat.is_le(Rule.bottom(inner), Rule.bottom(outer)))) == True{} : Bool}) -> Rule.Parts(outer, inner):
  Design.Box{l, t, w, h} = outer
  Design.Box{x, y, a, b} = inner
  (head, tail) = pair
  (head, tail_parts(outer, inner, and_parts(Nat.is_le(Rule.top(outer), Rule.top(inner)), Bool.and(Nat.is_le(Rule.right(inner), Rule.right(outer)), Nat.is_le(Rule.bottom(inner), Rule.bottom(outer))), tail)))

def parts(+outer: Design.Box, +inner: Design.Box, proof: {SpatialRules.contains(outer, inner) == True{} : Bool}) -> Rule.Parts(outer, inner):
  Design.Box{+l, +t, w, h} = outer
  Design.Box{+x, +y, a, b} = inner
  parts_head(outer, inner, and_parts(Nat.is_le(l, x), Bool.and(Nat.is_le(t, y), Bool.and(Nat.is_le(Nat.add(x, a), Nat.add(l, w)), Nat.is_le(Nat.add(y, b), Nat.add(t, h)))), proof))

def join(+outer: Design.Box, +inner: Design.Box, proof: Rule.Parts(outer, inner)) -> {SpatialRules.contains(outer, inner) == True{} : Bool}:
  Design.Box{+l, +t, w, h} = outer
  Design.Box{+x, +y, a, b} = inner
  (left, (top, (right, bottom))) = proof
  and_join(Nat.is_le(l, x), Bool.and(Nat.is_le(t, y), Bool.and(Nat.is_le(Nat.add(x, a), Nat.add(l, w)), Nat.is_le(Nat.add(y, b), Nat.add(t, h)))), left,
    and_join(Nat.is_le(t, y), Bool.and(Nat.is_le(Nat.add(x, a), Nat.add(l, w)), Nat.is_le(Nat.add(y, b), Nat.add(t, h))), top,
      and_join(Nat.is_le(Nat.add(x, a), Nat.add(l, w)), Nat.is_le(Nat.add(y, b), Nat.add(t, h)), right, bottom)))

def union_first(+first: Design.Box, +second: Design.Box) -> {SpatialRules.contains(Layout.box_union(first, second), first) == True{} : Bool}:
  Design.Box{+x, +y, +w, +h} = first
  Design.Box{+a, +b, +c, +d} = second
  join(Layout.box_union(first, second), first,
    (SProof.min_le_first(x, a), (SProof.min_le_first(y, b),
      (%Equal.sym(Nat, Nat.add(Nat.min(x, a), Nat.sub(Nat.max(Nat.add(x, w), Nat.add(a, c)), Nat.min(x, a))), Nat.max(Nat.add(x, w), Nat.add(a, c)), union_end(x, w, a, c)) : {Nat.is_le(Nat.add(x, w), _) == True{} : Bool}
        max_left(Nat.add(x, w), Nat.add(a, c)),
       %Equal.sym(Nat, Nat.add(Nat.min(y, b), Nat.sub(Nat.max(Nat.add(y, h), Nat.add(b, d)), Nat.min(y, b))), Nat.max(Nat.add(y, h), Nat.add(b, d)), union_end(y, h, b, d)) : {Nat.is_le(Nat.add(y, h), _) == True{} : Bool}
        max_left(Nat.add(y, h), Nat.add(b, d))))))

def union_second(+first: Design.Box, +second: Design.Box) -> {SpatialRules.contains(Layout.box_union(first, second), second) == True{} : Bool}:
  Design.Box{+x, +y, +w, +h} = first
  Design.Box{+a, +b, +c, +d} = second
  join(Layout.box_union(first, second), second,
    (SProof.min_le_second(x, a), (SProof.min_le_second(y, b),
      (%Equal.sym(Nat, Nat.add(Nat.min(x, a), Nat.sub(Nat.max(Nat.add(x, w), Nat.add(a, c)), Nat.min(x, a))), Nat.max(Nat.add(x, w), Nat.add(a, c)), union_end(x, w, a, c)) : {Nat.is_le(Nat.add(a, c), _) == True{} : Bool}
        max_right(Nat.add(x, w), Nat.add(a, c)),
       %Equal.sym(Nat, Nat.add(Nat.min(y, b), Nat.sub(Nat.max(Nat.add(y, h), Nat.add(b, d)), Nat.min(y, b))), Nat.max(Nat.add(y, h), Nat.add(b, d)), union_end(y, h, b, d)) : {Nat.is_le(Nat.add(b, d), _) == True{} : Bool}
        max_right(Nat.add(y, h), Nat.add(b, d))))))

def union_inside_parts(+target: Design.Box, +first: Design.Box, +second: Design.Box, fp: Rule.Parts(target, first), sp: Rule.Parts(target, second)) ->
  {SpatialRules.contains(target, Layout.box_union(first, second)) == True{} : Bool}:
  Design.Box{+l, +t, +tw, +th} = target
  Design.Box{+x, +y, +w, +h} = first
  Design.Box{+a, +b, +c, +d} = second
  (fl, (ft, (fr, fb))) = fp
  (sl, (st, (sr, sb))) = sp
  join(target, Layout.box_union(first, second),
    (min_lower(l, x, a, fl, sl), (min_lower(t, y, b, ft, st),
      (%Equal.sym(Nat, Nat.add(Nat.min(x, a), Nat.sub(Nat.max(Nat.add(x, w), Nat.add(a, c)), Nat.min(x, a))), Nat.max(Nat.add(x, w), Nat.add(a, c)), union_end(x, w, a, c)) : {Nat.is_le(_, Nat.add(l, tw)) == True{} : Bool}
        max_upper(Nat.add(x, w), Nat.add(a, c), Nat.add(l, tw), fr, sr),
       %Equal.sym(Nat, Nat.add(Nat.min(y, b), Nat.sub(Nat.max(Nat.add(y, h), Nat.add(b, d)), Nat.min(y, b))), Nat.max(Nat.add(y, h), Nat.add(b, d)), union_end(y, h, b, d)) : {Nat.is_le(_, Nat.add(t, th)) == True{} : Bool}
        max_upper(Nat.add(y, h), Nat.add(b, d), Nat.add(t, th), fb, sb)))))

def union_inside(+target: Design.Box, +first: Design.Box, +second: Design.Box,
  pf: {SpatialRules.contains(target, first) == True{} : Bool}, ps: {SpatialRules.contains(target, second) == True{} : Bool}) ->
  {SpatialRules.contains(target, Layout.box_union(first, second)) == True{} : Bool}:
  Design.Box{+l, +t, +tw, +th} = target
  Design.Box{+x, +y, +w, +h} = first
  Design.Box{+a, +b, +c, +d} = second
  union_inside_parts(target, first, second, parts(target, first, pf), parts(target, second, ps))

def contains_trans_parts(+outer: Design.Box, +middle: Design.Box, +inner: Design.Box,
  first: Rule.Parts(outer, middle), second: Rule.Parts(middle, inner)) -> {SpatialRules.contains(outer, inner) == True{} : Bool}:
  Design.Box{+ol, +ot, +ow, +oh} = outer
  Design.Box{+ml, +mt, +mw, +mh} = middle
  Design.Box{+il, +it, +iw, +ih} = inner
  (fl, (ft, (fr, fb))) = first
  (sl, (st, (sr, sb))) = second
  join(outer, inner, (SProof.le_trans(ol, ml, il, fl, sl), (SProof.le_trans(ot, mt, it, ft, st),
    (SProof.le_trans(Nat.add(il, iw), Nat.add(ml, mw), Nat.add(ol, ow), sr, fr),
     SProof.le_trans(Nat.add(it, ih), Nat.add(mt, mh), Nat.add(ot, oh), sb, fb)))))

def contains_trans(+outer: Design.Box, +middle: Design.Box, +inner: Design.Box,
  first: {SpatialRules.contains(outer, middle) == True{} : Bool}, second: {SpatialRules.contains(middle, inner) == True{} : Bool}) ->
  {SpatialRules.contains(outer, inner) == True{} : Bool}:
  contains_trans_parts(outer, middle, inner, parts(outer, middle, first), parts(middle, inner, second))

def contains_refl(+box: Design.Box) -> {SpatialRules.contains(box, box) == True{} : Bool}:
  Design.Box{+l, +t, w, h} = box
  join(box, box, (SProof.le_refl(l), (SProof.le_refl(t), (SProof.le_refl(Nat.add(l, w)), SProof.le_refl(Nat.add(t, h))))))

def all_trans_step(+outer: Design.Box, +middle: Design.Box, +bounds: Design.Box, +key: String,
  +rest: +List<Design.NodePlacement>, +proof: {SpatialRules.contains(outer, middle) == True{} : Bool},
  pair: {SpatialRules.contains(middle, bounds) == True{} : Bool} & {SpatialRules.all_contained(middle, rest) == True{} : Bool},
  recur: {SpatialRules.all_contained(outer, rest) == True{} : Bool}) ->
  {SpatialRules.all_contained(outer, Design.NodePlacement{key, bounds} <> rest) == True{} : Bool}:
  (head, tail) = pair
  and_join(SpatialRules.contains(outer, bounds), SpatialRules.all_contained(outer, rest),
    contains_trans(outer, middle, bounds, proof, head), recur)

def all_trans(+outer: Design.Box, +middle: Design.Box, +nodes: +List<Design.NodePlacement>,
  +proof: {SpatialRules.contains(outer, middle) == True{} : Bool}, +contained: {SpatialRules.all_contained(middle, nodes) == True{} : Bool}) ->
  {SpatialRules.all_contained(outer, nodes) == True{} : Bool}:
  match nodes:
    case Nil{}: {==}
    case Con{Design.NodePlacement{key, +bounds}, +rest}:
      all_trans_step(outer, middle, bounds, key, rest, proof, and_parts(SpatialRules.contains(middle, bounds), SpatialRules.all_contained(middle, rest), contained),
        all_trans(outer, middle, rest, proof, SProof.second({SpatialRules.contains(middle, bounds) == True{} : Bool}, {SpatialRules.all_contained(middle, rest) == True{} : Bool}, and_parts(SpatialRules.contains(middle, bounds), SpatialRules.all_contained(middle, rest), contained))))

def fold_step(+key: String, +bounds: Design.Box, +rest: +List<Design.NodePlacement>, +found: Maybe<&2, Design.Box>,
  proof: Rule.Fold(rest, found)) -> Rule.Fold(Design.NodePlacement{key, bounds} <> rest, Layout.union_member(Some{bounds}, found)):
  match found:
    case None{}:
      and_join(SpatialRules.contains(bounds, bounds), SpatialRules.all_contained(bounds, rest), contains_refl(bounds),
        %Equal.sym(+List<Design.NodePlacement>, rest, Nil{}, proof) : {SpatialRules.all_contained(bounds, _) == True{} : Bool}
        {==})
    case Some{previous}:
      and_join(SpatialRules.contains(Layout.box_union(bounds, previous), bounds), SpatialRules.all_contained(Layout.box_union(bounds, previous), rest),
        union_first(bounds, previous), all_trans(Layout.box_union(bounds, previous), previous, rest, union_second(bounds, previous), proof))

def fold_members(+nodes: +List<Design.NodePlacement>) -> Rule.Fold(nodes, Layout.placed_group_bounds(nodes)):
  match nodes:
    case Nil{}: {==}
    case Con{Design.NodePlacement{key, bounds}, +rest}:
      fold_step(key, bounds, rest, Layout.placed_group_bounds(rest), fold_members(rest))

def fold_bound(+nodes: +List<Design.NodePlacement>, +target: Design.Box, +found: Maybe<&2, Design.Box>,
  proof: Rule.Fold(nodes, found)) -> {SpatialRules.all_contained(Layout.group_bounds(found, target), nodes) == True{} : Bool}:
  match found:
    case None{}:
      %Equal.sym(+List<Design.NodePlacement>, nodes, Nil{}, proof) : {SpatialRules.all_contained(Layout.group_bounds(None{}, target), _) == True{} : Bool}
      {==}
    case Some{bounds}: proof

def members(+items: +List<Layout.BandItem>, +placements: +List<Design.NodePlacement>, +target: Design.Box) ->
  {SpatialRules.all_contained(Layout.group_bounds(Layout.action_group_bounds(items, placements), target), Layout.action_group_nodes(items, placements)) == True{} : Bool}:
  fold_bound(Layout.action_group_nodes(items, placements), target, Layout.action_group_bounds(items, placements), fold_members(Layout.action_group_nodes(items, placements)))
def lookup_choice(+target: Design.Box, +placement: Design.NodePlacement, +matches: Bool,
  +fallback: Maybe<&2, Design.NodePlacement>, head: {SpatialRules.contains(target, Rule.LayoutBounds(placement)) == True{} : Bool},
  tail: Rule.FoundNode(target, fallback)) -> Rule.FoundNode(target, Layout.choose_actual_placement(matches, placement, fallback)):
  Design.NodePlacement{key, bounds} = placement
  match matches:
    case True{}: head
    case False{}: tail

def lookup(+target: Design.Box, +key: String, +nodes: +List<Design.NodePlacement>,
  +contained: {SpatialRules.all_contained(target, nodes) == True{} : Bool}) -> Rule.FoundNode(target, Layout.actual_placement(key, nodes)):
  match nodes:
    case Nil{}: Unit{}
    case Con{+placement, +rest}:
      Design.NodePlacement{+node_key, +bounds} = placement
      lookup_choice(target, placement, String.eq(key, node_key), Layout.actual_placement(key, rest),
        SProof.first({SpatialRules.contains(target, bounds) == True{} : Bool}, {SpatialRules.all_contained(target, rest) == True{} : Bool}, and_parts(SpatialRules.contains(target, bounds), SpatialRules.all_contained(target, rest), contained)),
        lookup(target, key, rest,
          SProof.second({SpatialRules.contains(target, bounds) == True{} : Bool}, {SpatialRules.all_contained(target, rest) == True{} : Bool}, and_parts(SpatialRules.contains(target, bounds), SpatialRules.all_contained(target, rest), contained))))

def prepend_inside(+target: Design.Box, +found: Maybe<&2, Design.NodePlacement>, +rest: +List<Design.NodePlacement>,
  head: Rule.FoundNode(target, found), tail: {SpatialRules.all_contained(target, rest) == True{} : Bool}) ->
  {SpatialRules.all_contained(target, Layout.prepend_actual_placement(found, rest)) == True{} : Bool}:
  match found:
    case None{}: tail
    case Some{Design.NodePlacement{key, bounds}}:
      and_join(SpatialRules.contains(target, bounds), SpatialRules.all_contained(target, rest), head, tail)

def selected_inside(+target: Design.Box, +items: +List<Layout.BandItem>, +placements: +List<Design.NodePlacement>,
  +contained: {SpatialRules.all_contained(target, placements) == True{} : Bool}) ->
  {SpatialRules.all_contained(target, Layout.action_group_nodes(items, placements)) == True{} : Bool}:
  match items:
    case Nil{}: {==}
    case Con{Layout.FixedControl{+key, geometry}, +rest}:
      prepend_inside(target, Layout.actual_placement(key, placements), Layout.action_group_nodes(rest, placements),
        lookup(target, key, placements, contained), selected_inside(target, rest, placements, contained))
    case Con{Layout.FlexibleRegion{key, minimum_height}, rest}: selected_inside(target, rest, placements, contained)
    case Con{Layout.Spacer{minimum_width}, rest}: selected_inside(target, rest, placements, contained)

def fold_inside_step(+target: Design.Box, +bounds: Design.Box, +found: Maybe<&2, Design.Box>,
  head: {SpatialRules.contains(target, bounds) == True{} : Bool}, tail: Rule.FoundBox(target, found)) ->
  Rule.FoundBox(target, Layout.union_member(Some{bounds}, found)):
  match found:
    case None{}: head
    case Some{previous}: union_inside(target, bounds, previous, head, tail)

def fold_inside(+target: Design.Box, +nodes: +List<Design.NodePlacement>,
  +contained: {SpatialRules.all_contained(target, nodes) == True{} : Bool}) -> Rule.FoundBox(target, Layout.placed_group_bounds(nodes)):
  match nodes:
    case Nil{}: Unit{}
    case Con{Design.NodePlacement{key, +bounds}, +rest}:
      fold_inside_step(target, bounds, Layout.placed_group_bounds(rest),
        SProof.first({SpatialRules.contains(target, bounds) == True{} : Bool}, {SpatialRules.all_contained(target, rest) == True{} : Bool}, and_parts(SpatialRules.contains(target, bounds), SpatialRules.all_contained(target, rest), contained)),
        fold_inside(target, rest, SProof.second({SpatialRules.contains(target, bounds) == True{} : Bool}, {SpatialRules.all_contained(target, rest) == True{} : Bool}, and_parts(SpatialRules.contains(target, bounds), SpatialRules.all_contained(target, rest), contained))))

def group_inside(+target: Design.Box, +found: Maybe<&2, Design.Box>, proof: Rule.FoundBox(target, found)) ->
  {SpatialRules.contains(target, Layout.group_bounds(found, target)) == True{} : Bool}:
  Design.Box{+l, +t, +w, +h} = target
  match found:
    case Some{bounds}: proof
    case None{}:
      join(target, Design.Box{l, t, 0n, 0n}, (SProof.le_refl(l), (SProof.le_refl(t),
        (Equal.trans(Bool, Nat.is_le(Nat.add(l, 0n), Nat.add(l, w)), Nat.is_le(l, Nat.add(l, w)), True{},
          Equal.cong(Nat, Bool, (n => Nat.is_le(n, Nat.add(l, w))), Nat.add(l, 0n), l, SProof.add_zero(l)), SProof.le_add(l, w)),
         Equal.trans(Bool, Nat.is_le(Nat.add(t, 0n), Nat.add(t, h)), Nat.is_le(t, Nat.add(t, h)), True{},
          Equal.cong(Nat, Bool, (n => Nat.is_le(n, Nat.add(t, h))), Nat.add(t, 0n), t, SProof.add_zero(t)), SProof.le_add(t, h))))))

def enclosure(+items: +List<Layout.BandItem>, +placements: +List<Design.NodePlacement>, +target: Design.Box,
  contained: {SpatialRules.all_contained(target, placements) == True{} : Bool}) ->
  {SpatialRules.contains(target, Layout.group_bounds(Layout.action_group_bounds(items, placements), target)) == True{} : Bool}:
  group_inside(target, Layout.action_group_bounds(items, placements),
    fold_inside(target, Layout.action_group_nodes(items, placements), selected_inside(target, items, placements, contained)))
def append_inside_step(+target: Design.Box, +key: String, +bounds: Design.Box,
  +rest: +List<Design.NodePlacement>, +second: +List<Design.NodePlacement>,
  pair: {SpatialRules.contains(target, bounds) == True{} : Bool} & {SpatialRules.all_contained(target, rest) == True{} : Bool},
  tail: {SpatialRules.all_contained(target, List.append(&2, Design.NodePlacement, rest, second)) == True{} : Bool}) ->
  {SpatialRules.all_contained(target, List.append(&2, Design.NodePlacement, Design.NodePlacement{key, bounds} <> rest, second)) == True{} : Bool}:
  (head, unused) = pair
  and_join(SpatialRules.contains(target, bounds), SpatialRules.all_contained(target, List.append(&2, Design.NodePlacement, rest, second)), head, tail)

def append_inside(+target: Design.Box, +first: +List<Design.NodePlacement>, +second: +List<Design.NodePlacement>,
  +pf: {SpatialRules.all_contained(target, first) == True{} : Bool}, +ps: {SpatialRules.all_contained(target, second) == True{} : Bool}) ->
  {SpatialRules.all_contained(target, List.append(&2, Design.NodePlacement, first, second)) == True{} : Bool}:
  match first:
    case Nil{}: ps
    case Con{Design.NodePlacement{key, +bounds}, +rest}:
      append_inside_step(target, key, bounds, rest, second, and_parts(SpatialRules.contains(target, bounds), SpatialRules.all_contained(target, rest), pf),
        append_inside(target, rest, second,
          SProof.second({SpatialRules.contains(target, bounds) == True{} : Bool}, {SpatialRules.all_contained(target, rest) == True{} : Bool}, and_parts(SpatialRules.contains(target, bounds), SpatialRules.all_contained(target, rest), pf)), ps))

def complete(+actions: Maybe<&2, Layout.HeadingActions>, +target: Design.Box, +placements: +List<Design.NodePlacement>,
  +contained: {SpatialRules.all_contained(target, placements) == True{} : Bool}) ->
  {SpatialRules.all_contained(target, Layout.group_heading_actions(actions, target, placements)) == True{} : Bool}:
  match actions:
    case None{}: contained
    case Some{Layout.HeadingActions{key, +items}}:
      append_inside(target, placements, [Design.NodePlacement{key, Layout.group_bounds(Layout.action_group_bounds(items, placements), target)}], contained,
        and_join(SpatialRules.contains(target, Layout.group_bounds(Layout.action_group_bounds(items, placements), target)), True{}, enclosure(items, placements, target, contained), {==}))
def finished(+placements: +List<Design.NodePlacement>, +content: Layout.HeadingContent, +target: Design.Box,
  contained: {SpatialRules.all_contained(target, placements) == True{} : Bool}) ->
  {Rule.successful(target, Layout.finish_task_heading(Layout.ControlsReady{placements}, content, target)) == True{} : Bool}:
  Layout.HeadingContent{title, actions} = content
  complete(actions, target, placements, contained)

def Rule.evidence():
  Rule.Requirements{members, enclosure, complete, finished}
