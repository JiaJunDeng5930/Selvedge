import Base
import ../../bendlib/proofs/algebra.bend as Alg
import ../../bendlib/stdlib.bend as Std
import ../layout.bend as Layout
import ../design.bend as Design
import ../controls.bend as Controls
import ../enclosure.bend as Enclosure
import ../space.bend as Space
import ../space-laws.bend as Allocation
import ../container-space-laws.bend as Container
import ../control-allocation-laws.bend as Rule
import ./space.bend as AllocationProof
import ../spatial-rules.bend as SpatialRules
import ./container-space.bend as ContainerProof

def control_key(+key: String, geometry: Controls.Geometry, offset: Nat, width: Nat,
  target: Design.Box, band: Nat) ->
  {Rule.placement_key(Layout.control_placement(key, geometry, offset, width, target, band)) == key : String}:
  Design.Box{left, top, target_width, target_height} = target
  {==}

def height_limits(+geometry: Controls.Geometry, +band: Nat,
  fits: {Nat.is_le(Controls.geometry_minimum_height(geometry), band) == True{} : Bool}) ->
  {Nat.is_le(Controls.geometry_minimum_height(geometry), Layout.control_height(geometry, band)) == True{} : Bool} &
  {Nat.is_le(Layout.control_height(geometry, band), band) == True{} : Bool}:
  (AllocationProof.chosen_lower(Space.Fit{Controls.geometry_minimum_height(geometry),
      Nat.sub(Controls.geometry_preferred_height(geometry), Controls.geometry_minimum_height(geometry)), 0n}, band, fits),
    AllocationProof.min_le_second(Nat.add(Controls.geometry_minimum_height(geometry),
      Nat.sub(Controls.geometry_preferred_height(geometry), Controls.geometry_minimum_height(geometry))), band))

# The centering formula uses the pinned Base division worker directly.
def divmod_count_bound(+n: Nat, +m: Nat, +d: Nat, +r: Nat) ->
  {Nat.is_le(Nat.div.fin(Nat.divmod.go(n, m, d, r)), Nat.add(n, d)) == True{} : Bool}:
  match n:
    case 0n: AllocationProof.le_refl(d)
    case 1n+np:
      match m:
        case 0n:
          %Alg.nat_add_succ(np, d) :
            {Nat.is_le(Nat.div.fin(Nat.divmod.go(np, r, 1n+d, 0n)), _) == True{} : Bool}
          divmod_count_bound(np, r, 1n+d, 0n)
        case 1n+mp:
          +value = Nat.div.fin(Nat.divmod.go(np, mp, d, 1n+r))
          AllocationProof.le_trans(value, Nat.add(np, d), 1n+Nat.add(np, d),
            divmod_count_bound(np, mp, d, 1n+r),
            Equal.trans(Bool, Nat.is_le(Nat.add(np, d), 1n+Nat.add(np, d)),
              Nat.is_le(Nat.add(np, d), Nat.add(Nat.add(np, d), 1n)), True{},
              Equal.cong(Nat, Bool, (bound => Nat.is_le(Nat.add(np, d), bound)),
                1n+Nat.add(np, d), Nat.add(Nat.add(np, d), 1n),
                AllocationProof.add_comm(1n, Nat.add(np, d))),
              AllocationProof.le_add(Nat.add(np, d), 1n)))

def half_bound(+room: Nat) -> {Nat.is_le(Nat.div(room, 2n), room) == True{} : Bool}:
  %Alg.nat_add_zero(room) :
    {Nat.is_le(Nat.div(room, 2n), _) == True{} : Bool}
  divmod_count_bound(room, 1n, 0n, 0n)

def max_left(+a: Nat, +b: Nat) -> {Nat.is_le(a, Nat.max(a, b)) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(a, Nat.max(a, b)), Nat.is_ge(Nat.max(a, b), a), True{},
    Equal.sym(Bool, Nat.is_ge(Nat.max(a, b), a), Nat.is_le(a, Nat.max(a, b)), AllocationProof.ge_le(Nat.max(a, b), a)), Nat.max_ge_l(a, b))

def max_right(+a: Nat, +b: Nat) -> {Nat.is_le(b, Nat.max(a, b)) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(b, Nat.max(a, b)), Nat.is_ge(Nat.max(a, b), b), True{},
    Equal.sym(Bool, Nat.is_ge(Nat.max(a, b), b), Nat.is_le(b, Nat.max(a, b)), AllocationProof.ge_le(Nat.max(a, b), b)), Nat.max_ge_r(a, b))

def band_floor(+lower: Nat, +height: Nat, +preferred: Nat,
  fits: {Nat.is_le(lower, height) == True{} : Bool},
  wanted: {Nat.is_le(lower, preferred) == True{} : Bool}) ->
  {Nat.is_le(lower, Nat.min(height, preferred)) == True{} : Bool}:
  match lower height preferred:
    case 0n _ _: AllocationProof.zero_le(Nat.min(height, preferred))
    case 1n+a 0n _: AllocationProof.impossible({Nat.is_le(1n+a, Nat.min(0n, preferred)) == True{} : Bool}, fits)
    case 1n+a 1n+b 0n: AllocationProof.impossible({Nat.is_le(1n+a, 0n) == True{} : Bool}, wanted)
    case 1n+a 1n+b 1n+c: band_floor(a, b, c, fits, wanted)

def offset_le(+offset: Nat, +a: Nat, +b: Nat, fits: {Nat.is_le(a, b) == True{} : Bool}) ->
  {Nat.is_le(Nat.add(offset, a), Nat.add(offset, b)) == True{} : Bool}:
  match offset:
    case 0n: fits
    case 1n+rest: offset_le(rest, a, b, fits)

def centered_height(+geometry: Controls.Geometry, +band: Nat,
  floor: {Nat.is_le(Controls.geometry_minimum_height(geometry), band) == True{} : Bool}) ->
  {Nat.is_le(Nat.add(Nat.div(Nat.sub(band, Layout.control_height(geometry, band)), 2n), Layout.control_height(geometry, band)), band) == True{} : Bool}:
  +height = Layout.control_height(geometry, band)
  upper = AllocationProof.second(
    {Nat.is_le(Controls.geometry_minimum_height(geometry), height) == True{} : Bool},
    {Nat.is_le(height, band) == True{} : Bool}, height_limits(geometry, band, floor))
  AllocationProof.reserved_use(Nat.div(Nat.sub(band, height), 2n), height, band, upper, half_bound(Nat.sub(band, height)))

def and_parts(+a: Bool, +b: Bool, proof: {(a && b) == True{} : Bool}) ->
  {a == True{} : Bool} & {b == True{} : Bool}:
  match a:
    case True{}: ({==}, proof)
    case False{}: AllocationProof.impossible({False{} == True{} : Bool} & {b == True{} : Bool}, proof)

def natural_equal(+a: Nat, +b: Nat, proof: {Nat.is_eq(a, b) == True{} : Bool}) -> {a == b : Nat}:
  match a b:
    case 0n 0n: {==}
    case 0n 1n+rest: AllocationProof.impossible({0n == 1n+rest : Nat}, proof)
    case 1n+rest 0n: AllocationProof.impossible({1n+rest == 0n : Nat}, proof)
    case 1n+left 1n+right: Equal.cong(Nat, Nat, (n => 1n+n), left, right, natural_equal(left, right, proof))

def translated_end(+origin: Nat, +offset: Nat, +extent: Nat, +available: Nat,
  fits: {Nat.is_le(Nat.add(offset, extent), available) == True{} : Bool}) ->
  {Nat.is_le(Nat.add(Nat.add(origin, offset), extent), Nat.add(origin, available)) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(Nat.add(Nat.add(origin, offset), extent), Nat.add(origin, available)),
    Nat.is_le(Nat.add(origin, Nat.add(offset, extent)), Nat.add(origin, available)), True{},
    Equal.cong(Nat, Bool, (n => Nat.is_le(n, Nat.add(origin, available))),
      Nat.add(Nat.add(origin, offset), extent), Nat.add(origin, Nat.add(offset, extent)), Alg.nat_add_assoc(origin, offset, extent)),
    offset_le(origin, Nat.add(offset, extent), available, fits))


def rendered_order(+placements: +List<Space.Placement<Layout.BandItem>>, +target: Design.Box, +band: Nat) ->
  {Rule.placement_keys(Layout.control_placements(placements, target, band)) ==
    Rule.item_keys(Allocation.placement_values(~Layout.BandItem, placements)) : +List<String>}:
  match placements:
    case Nil{}: {==}
    case Con{Space.Placement{Layout.Spacer{minimum_width}, offset, width}, rest}: rendered_order(rest, target, band)
    case Con{Space.Placement{Layout.FixedControl{+key, geometry}, offset, width}, rest}:
      Design.Box{left, top, target_width, target_height} = target
      Equal.cong(+List<String>, +List<String>, (tail => key <> tail),
        Rule.placement_keys(Layout.control_placements(rest, target, band)), Rule.item_keys(Allocation.placement_values(~Layout.BandItem, rest)), rendered_order(rest, target, band))
    case Con{Space.Placement{Layout.FlexibleRegion{+key, minimum_height}, offset, width}, rest}:
      Design.Box{left, top, target_width, target_height} = target
      Equal.cong(+List<String>, +List<String>, (tail => key <> tail),
        Rule.placement_keys(Layout.control_placements(rest, target, band)), Rule.item_keys(Allocation.placement_values(~Layout.BandItem, rest)), rendered_order(rest, target, band))

def cross_floors(+items: +List<Layout.BandItem>, +height: Nat,
  +fits: {Nat.is_le(Layout.cross_minimum(items), height) == True{} : Bool}) -> Rule.HeightFloors(items, height):
  match items:
    case Nil{}: Unit{}
    case Con{+item, +rest}:
      (AllocationProof.le_trans(Layout.item_cross_minimum(item), Nat.max(Layout.item_cross_minimum(item), Layout.cross_minimum(rest)), height,
         max_left(Layout.item_cross_minimum(item), Layout.cross_minimum(rest)), fits),
       cross_floors(rest, height, AllocationProof.le_trans(Layout.cross_minimum(rest), Nat.max(Layout.item_cross_minimum(item), Layout.cross_minimum(rest)), height,
         max_right(Layout.item_cross_minimum(item), Layout.cross_minimum(rest)), fits)))

def band_slot_values(+items: +List<Layout.BandItem>) ->
  {Allocation.slot_values(~Layout.BandItem, Layout.band_slots(items)) == items : +List<Layout.BandItem>}:
  match items:
    case Nil{}: {==}
    case Con{+head, +rest}:
      Equal.cong(+List<Layout.BandItem>, +List<Layout.BandItem>, (tail => head <> tail),
        Allocation.slot_values(~Layout.BandItem, Layout.band_slots(rest)), rest, band_slot_values(rest))

def limit_tail(+dimension: Space.Dimension, +width: Nat, +rest: +List<Space.Slot<Layout.BandItem>>,
  +tail: +List<Space.Placement<Layout.BandItem>>,
  proof: {(Nat.is_le(Space.minimum(dimension), width) &&
    (Allocation.maximum_ok(dimension, width) && (Allocation.rigid_ok(dimension, width) && Allocation.limits(~Layout.BandItem, rest, tail)))) == True{} : Bool}) ->
  {Allocation.limits(~Layout.BandItem, rest, tail) == True{} : Bool}:
  AllocationProof.second({Allocation.rigid_ok(dimension, width) == True{} : Bool}, {Allocation.limits(~Layout.BandItem, rest, tail) == True{} : Bool},
    and_parts(Allocation.rigid_ok(dimension, width), Allocation.limits(~Layout.BandItem, rest, tail),
      AllocationProof.second({Allocation.maximum_ok(dimension, width) == True{} : Bool},
        {(Allocation.rigid_ok(dimension, width) && Allocation.limits(~Layout.BandItem, rest, tail)) == True{} : Bool},
        and_parts(Allocation.maximum_ok(dimension, width), Allocation.rigid_ok(dimension, width) && Allocation.limits(~Layout.BandItem, rest, tail),
          AllocationProof.second({Nat.is_le(Space.minimum(dimension), width) == True{} : Bool},
            {(Allocation.maximum_ok(dimension, width) && (Allocation.rigid_ok(dimension, width) && Allocation.limits(~Layout.BandItem, rest, tail))) == True{} : Bool},
            and_parts(Nat.is_le(Space.minimum(dimension), width), Allocation.maximum_ok(dimension, width) && (Allocation.rigid_ok(dimension, width) && Allocation.limits(~Layout.BandItem, rest, tail)), proof))))))

def slot_bounds(+placements: +List<Space.Placement<Layout.BandItem>>,
  +bounds: {Allocation.limits(~Layout.BandItem, Layout.band_slots(Allocation.placement_values(~Layout.BandItem, placements)), placements) == True{} : Bool}) -> Rule.SlotBounds(placements):
  match placements:
    case Nil{}: Unit{}
    case Con{Space.Placement{+item, offset, +width}, +rest}:
      (AllocationProof.first({Nat.is_le(Space.minimum(Layout.item_dimension(item)), width) == True{} : Bool},
        {(Allocation.maximum_ok(Layout.item_dimension(item), width) &&
          (Allocation.rigid_ok(Layout.item_dimension(item), width) && Allocation.limits(~Layout.BandItem, Layout.band_slots(Allocation.placement_values(~Layout.BandItem, rest)), rest))) == True{} : Bool},
        and_parts(Nat.is_le(Space.minimum(Layout.item_dimension(item)), width),
          Allocation.maximum_ok(Layout.item_dimension(item), width) &&
          (Allocation.rigid_ok(Layout.item_dimension(item), width) && Allocation.limits(~Layout.BandItem, Layout.band_slots(Allocation.placement_values(~Layout.BandItem, rest)), rest)), bounds)),
        slot_bounds(rest, limit_tail(Layout.item_dimension(item), width, Layout.band_slots(Allocation.placement_values(~Layout.BandItem, rest)), rest, bounds)))

def payload_items(+items: +List<Layout.BandItem>, +placements: +List<Space.Placement<Layout.BandItem>>,
  payload: {Allocation.placement_values(~Layout.BandItem, placements) == Allocation.slot_values(~Layout.BandItem, Layout.band_slots(items)) : +List<Layout.BandItem>}) ->
  {Allocation.placement_values(~Layout.BandItem, placements) == items : +List<Layout.BandItem>}:
  Equal.trans(+List<Layout.BandItem>, Allocation.placement_values(~Layout.BandItem, placements),
    Allocation.slot_values(~Layout.BandItem, Layout.band_slots(items)), items, payload, band_slot_values(items))

def own_limits(+items: +List<Layout.BandItem>, +placements: +List<Space.Placement<Layout.BandItem>>,
  same: {Allocation.placement_values(~Layout.BandItem, placements) == items : +List<Layout.BandItem>},
  bounds: {Allocation.limits(~Layout.BandItem, Layout.band_slots(items), placements) == True{} : Bool}) -> Rule.SlotBounds(placements):
  slot_bounds(placements, Equal.trans(Bool,
    Allocation.limits(~Layout.BandItem, Layout.band_slots(Allocation.placement_values(~Layout.BandItem, placements)), placements),
    Allocation.limits(~Layout.BandItem, Layout.band_slots(items), placements), True{},
    Equal.cong(+List<Layout.BandItem>, Bool, (values => Allocation.limits(~Layout.BandItem, Layout.band_slots(values), placements)),
      Allocation.placement_values(~Layout.BandItem, placements), items, same), bounds))

def position_tail_parts(+actual: Nat, +width: Nat, +rest: +List<Space.Placement<Layout.BandItem>>, +gap: Nat, +start: Nat,
  proof: {Nat.is_eq(actual, start) == True{} : Bool} &
    {Allocation.positions(~Layout.BandItem, rest, gap, Nat.add(actual, Nat.add(width, Allocation.placement_gap(~Layout.BandItem, rest, gap)))) == True{} : Bool}) ->
  {actual == start : Nat} & {Allocation.positions(~Layout.BandItem, rest, gap, Nat.add(actual, Nat.add(width, Allocation.placement_gap(~Layout.BandItem, rest, gap)))) == True{} : Bool}:
  (same, tail) = proof
  (natural_equal(actual, start, same), tail)

def position_tail(+item: Layout.BandItem, +actual: Nat, +width: Nat,
  +rest: +List<Space.Placement<Layout.BandItem>>, +gap: Nat, +start: Nat,
  proof: {Allocation.positions(~Layout.BandItem, Space.Placement{item, actual, width} <> rest, gap, start) == True{} : Bool}) ->
  {actual == start : Nat} &
  {Allocation.positions(~Layout.BandItem, rest, gap, Nat.add(actual, Nat.add(width, Allocation.placement_gap(~Layout.BandItem, rest, gap)))) == True{} : Bool}:
  position_tail_parts(actual, width, rest, gap, start, and_parts(Nat.is_eq(actual, start),
    Allocation.positions(~Layout.BandItem, rest, gap, Nat.add(actual, Nat.add(width, Allocation.placement_gap(~Layout.BandItem, rest, gap)))), proof))

def positioned_bound(+item: Layout.BandItem, +actual: Nat, +width: Nat,
  +rest: +List<Space.Placement<Layout.BandItem>>, +gap: Nat, +start: Nat, +end: Nat,
  same: {actual == start : Nat},
  fits: {Nat.is_le(Nat.add(start, Allocation.used(~Layout.BandItem, Space.Placement{item, actual, width} <> rest, gap)), end) == True{} : Bool}) ->
  {Nat.is_le(Nat.add(Nat.add(actual, width), Nat.add(Allocation.placement_gap(~Layout.BandItem, rest, gap), Allocation.used(~Layout.BandItem, rest, gap))), end) == True{} : Bool}:
  Equal.trans(Bool,
    Nat.is_le(Nat.add(Nat.add(actual, width), Nat.add(Allocation.placement_gap(~Layout.BandItem, rest, gap), Allocation.used(~Layout.BandItem, rest, gap))), end),
    Nat.is_le(Nat.add(start, Allocation.used(~Layout.BandItem, Space.Placement{item, actual, width} <> rest, gap)), end), True{},
    Equal.cong(Nat, Bool, (n => Nat.is_le(n, end)),
      Nat.add(Nat.add(actual, width), Nat.add(Allocation.placement_gap(~Layout.BandItem, rest, gap), Allocation.used(~Layout.BandItem, rest, gap))),
      Nat.add(start, Allocation.used(~Layout.BandItem, Space.Placement{item, actual, width} <> rest, gap)),
      Equal.trans(Nat, Nat.add(Nat.add(actual, width), Nat.add(Allocation.placement_gap(~Layout.BandItem, rest, gap), Allocation.used(~Layout.BandItem, rest, gap))),
        Nat.add(actual, Nat.add(width, Nat.add(Allocation.placement_gap(~Layout.BandItem, rest, gap), Allocation.used(~Layout.BandItem, rest, gap)))),
        Nat.add(start, Allocation.used(~Layout.BandItem, Space.Placement{item, actual, width} <> rest, gap)),
        Alg.nat_add_assoc(actual, width, Nat.add(Allocation.placement_gap(~Layout.BandItem, rest, gap), Allocation.used(~Layout.BandItem, rest, gap))),
        Equal.trans(Nat, Nat.add(actual, Nat.add(width, Nat.add(Allocation.placement_gap(~Layout.BandItem, rest, gap), Allocation.used(~Layout.BandItem, rest, gap)))),
          Nat.add(actual, Allocation.used(~Layout.BandItem, Space.Placement{item, actual, width} <> rest, gap)),
          Nat.add(start, Allocation.used(~Layout.BandItem, Space.Placement{item, actual, width} <> rest, gap)),
          Equal.cong(Nat, Nat, (n => Nat.add(actual, n)), Nat.add(width, Nat.add(Allocation.placement_gap(~Layout.BandItem, rest, gap), Allocation.used(~Layout.BandItem, rest, gap))),
            Allocation.used(~Layout.BandItem, Space.Placement{item, actual, width} <> rest, gap),
            Equal.sym(Nat, Allocation.used(~Layout.BandItem, Space.Placement{item, actual, width} <> rest, gap),
              Nat.add(width, Nat.add(Allocation.placement_gap(~Layout.BandItem, rest, gap), Allocation.used(~Layout.BandItem, rest, gap))), AllocationProof.used_split(~Layout.BandItem, item, actual, width, rest, gap))),
          Equal.cong(Nat, Nat, (n => Nat.add(n, Allocation.used(~Layout.BandItem, Space.Placement{item, actual, width} <> rest, gap))), actual, start, same)))), fits)

def next_budget(+actual: Nat, +width: Nat, +between: Nat, +remaining: Nat, +end: Nat,
  fits: {Nat.is_le(Nat.add(Nat.add(actual, width), Nat.add(between, remaining)), end) == True{} : Bool}) ->
  {Nat.is_le(Nat.add(Nat.add(actual, Nat.add(width, between)), remaining), end) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(Nat.add(Nat.add(actual, Nat.add(width, between)), remaining), end),
    Nat.is_le(Nat.add(Nat.add(actual, width), Nat.add(between, remaining)), end), True{},
    Equal.cong(Nat, Bool, (n => Nat.is_le(n, end)),
      Nat.add(Nat.add(actual, Nat.add(width, between)), remaining), Nat.add(Nat.add(actual, width), Nat.add(between, remaining)),
      Equal.trans(Nat, Nat.add(Nat.add(actual, Nat.add(width, between)), remaining), Nat.add(actual, Nat.add(Nat.add(width, between), remaining)),
        Nat.add(Nat.add(actual, width), Nat.add(between, remaining)), Alg.nat_add_assoc(actual, Nat.add(width, between), remaining),
        Equal.trans(Nat, Nat.add(actual, Nat.add(Nat.add(width, between), remaining)), Nat.add(actual, Nat.add(width, Nat.add(between, remaining))),
          Nat.add(Nat.add(actual, width), Nat.add(between, remaining)),
          Equal.cong(Nat, Nat, (n => Nat.add(actual, n)), Nat.add(Nat.add(width, between), remaining), Nat.add(width, Nat.add(between, remaining)), Alg.nat_add_assoc(width, between, remaining)),
          Equal.sym(Nat, Nat.add(Nat.add(actual, width), Nat.add(between, remaining)), Nat.add(actual, Nat.add(width, Nat.add(between, remaining))), Alg.nat_add_assoc(actual, width, Nat.add(between, remaining)))))), fits)

def intervals_step(+actual: Nat, +width: Nat, +rest: +List<Space.Placement<Layout.BandItem>>, +gap: Nat, +end: Nat,
  fits: {Nat.is_le(Nat.add(Nat.add(actual, width), Nat.add(Allocation.placement_gap(~Layout.BandItem, rest, gap), Allocation.used(~Layout.BandItem, rest, gap))), end) == True{} : Bool},
  tail: Rule.IntervalEnds(rest, end)) ->
  {Nat.is_le(Nat.add(actual, width), end) == True{} : Bool} & Rule.IntervalEnds(rest, end):
  (AllocationProof.le_trans(Nat.add(actual, width), Nat.add(Nat.add(actual, width), Nat.add(Allocation.placement_gap(~Layout.BandItem, rest, gap), Allocation.used(~Layout.BandItem, rest, gap))), end,
    AllocationProof.le_add(Nat.add(actual, width), Nat.add(Allocation.placement_gap(~Layout.BandItem, rest, gap), Allocation.used(~Layout.BandItem, rest, gap))), fits), tail)

def position_intervals(+placements: +List<Space.Placement<Layout.BandItem>>, +gap: Nat, +start: Nat, +end: Nat,
  +positions: {Allocation.positions(~Layout.BandItem, placements, gap, start) == True{} : Bool},
  +fits: {Nat.is_le(Nat.add(start, Allocation.used(~Layout.BandItem, placements, gap)), end) == True{} : Bool}) -> Rule.IntervalEnds(placements, end):
  match placements:
    case Nil{}: Unit{}
    case Con{Space.Placement{+item, +actual, +width}, +rest}:
      tail_positions = AllocationProof.second({actual == start : Nat},
        {Allocation.positions(~Layout.BandItem, rest, gap, Nat.add(actual, Nat.add(width, Allocation.placement_gap(~Layout.BandItem, rest, gap)))) == True{} : Bool}, position_tail(item, actual, width, rest, gap, start, positions))
      intervals_step(actual, width, rest, gap, end, positioned_bound(item, actual, width, rest, gap, start, end, AllocationProof.first({actual == start : Nat},
        {Allocation.positions(~Layout.BandItem, rest, gap, Nat.add(actual, Nat.add(width, Allocation.placement_gap(~Layout.BandItem, rest, gap)))) == True{} : Bool}, position_tail(item, actual, width, rest, gap, start, positions)), fits),
        position_intervals(rest, gap, Nat.add(actual, Nat.add(width, Allocation.placement_gap(~Layout.BandItem, rest, gap))), end, tail_positions,
          next_budget(actual, width, Allocation.placement_gap(~Layout.BandItem, rest, gap), Allocation.used(~Layout.BandItem, rest, gap), end,
            positioned_bound(item, actual, width, rest, gap, start, end, AllocationProof.first({actual == start : Nat},
              {Allocation.positions(~Layout.BandItem, rest, gap, Nat.add(actual, Nat.add(width, Allocation.placement_gap(~Layout.BandItem, rest, gap)))) == True{} : Bool}, position_tail(item, actual, width, rest, gap, start, positions)), fits))))
def container_intervals(+placements: +List<Space.Placement<Layout.BandItem>>, +inset: Nat, +gap: Nat, +unused: Nat, +width: Nat,
  positions: {Allocation.positions(~Layout.BandItem, placements, gap, inset) == True{} : Bool},
  balance: {Nat.add(inset, Nat.add(Nat.add(Allocation.used(~Layout.BandItem, placements, gap), unused), inset)) == width : Nat}) ->
  Rule.IntervalEnds(placements, width):
  position_intervals(placements, gap, inset, width,
    positions, Equal.trans(Bool, Nat.is_le(Nat.add(inset, Allocation.used(~Layout.BandItem, placements, gap)), width),
      Nat.is_le(Nat.add(inset, Allocation.used(~Layout.BandItem, placements, gap)),
        Nat.add(inset, Nat.add(Nat.add(Allocation.used(~Layout.BandItem, placements, gap), unused), inset))), True{},
      Equal.cong(Nat, Bool, (n => Nat.is_le(Nat.add(inset, Allocation.used(~Layout.BandItem, placements, gap)), n)), width,
        Nat.add(inset, Nat.add(Nat.add(Allocation.used(~Layout.BandItem, placements, gap), unused), inset)),
        Equal.sym(Nat, Nat.add(inset, Nat.add(Nat.add(Allocation.used(~Layout.BandItem, placements, gap), unused), inset)), width, balance)),
      offset_le(inset, Allocation.used(~Layout.BandItem, placements, gap),
        Nat.add(Nat.add(Allocation.used(~Layout.BandItem, placements, gap), unused), inset),
        AllocationProof.le_trans(Allocation.used(~Layout.BandItem, placements, gap),
          Nat.add(Allocation.used(~Layout.BandItem, placements, gap), unused),
          Nat.add(Nat.add(Allocation.used(~Layout.BandItem, placements, gap), unused), inset),
          AllocationProof.le_add(Allocation.used(~Layout.BandItem, placements, gap), unused),
          AllocationProof.le_add(Nat.add(Allocation.used(~Layout.BandItem, placements, gap), unused), inset)))))

def control_box(+key: String, +geometry: Controls.Geometry, +offset: Nat, +width: Nat, +target: Design.Box, +band: Nat,
  minimum_width: {Nat.is_le(Controls.geometry_minimum_width(geometry), width) == True{} : Bool},
  +minimum_height: {Nat.is_le(Controls.geometry_minimum_height(geometry), band) == True{} : Bool},
  horizontal: {Nat.is_le(Nat.add(offset, width), Layout.box_width(target)) == True{} : Bool},
  band_fits: {Nat.is_le(band, Layout.box_height(target)) == True{} : Bool}) ->
  Rule.BoxEvidence<Controls.geometry_minimum_width(geometry), Controls.geometry_minimum_height(geometry), target, Rule.placement_bounds(Layout.control_placement(key, geometry, offset, width, target, band))>:
  Design.Box{+left, +top, +target_width, +target_height} = target
  Rule.BoxEvidence{minimum_width,
    AllocationProof.first({Nat.is_le(Controls.geometry_minimum_height(geometry), Layout.control_height(geometry, band)) == True{} : Bool},
      {Nat.is_le(Layout.control_height(geometry, band), band) == True{} : Bool}, height_limits(geometry, band, minimum_height)),
    AllocationProof.le_add(left, offset), translated_end(left, offset, width, target_width, horizontal),
    AllocationProof.le_add(top, Nat.div(Nat.sub(band, Layout.control_height(geometry, band)), 2n)),
    translated_end(top, Nat.div(Nat.sub(band, Layout.control_height(geometry, band)), 2n), Layout.control_height(geometry, band), target_height,
      AllocationProof.le_trans(Nat.add(Nat.div(Nat.sub(band, Layout.control_height(geometry, band)), 2n), Layout.control_height(geometry, band)), band, target_height,
        centered_height(geometry, band, minimum_height), band_fits))}


def region_box(+minimum: Nat, +left: Nat, +top: Nat, +width: Nat, +height: Nat,
  +offset: Nat, +extent: Nat, +band: Nat,
  floor: {Nat.is_le(minimum, band) == True{} : Bool},
  horizontal: {Nat.is_le(Nat.add(offset, extent), width) == True{} : Bool},
  band_fits: {Nat.is_le(band, height) == True{} : Bool}) ->
  Rule.BoxEvidence<0n, minimum, Design.Box{left, top, width, height}, Design.Box{Nat.add(left, offset), top, extent, band}>:
  Rule.BoxEvidence{AllocationProof.zero_le(extent), floor, AllocationProof.le_add(left, offset), translated_end(left, offset, extent, width, horizontal),
    AllocationProof.le_refl(top), offset_le(top, band, height, band_fits)}

def rendered_fixed(+key: String, +geometry: Controls.Geometry, +offset: Nat, +width: Nat,
  +rest: +List<Space.Placement<Layout.BandItem>>, +target: Design.Box, +band: Nat,
  own_width: {Nat.is_le(Controls.geometry_minimum_width(geometry), width) == True{} : Bool},
  own_height: {Nat.is_le(Controls.geometry_minimum_height(geometry), band) == True{} : Bool},
  own_end: {Nat.is_le(Nat.add(offset, width), Layout.box_width(target)) == True{} : Bool},
  band_fits: {Nat.is_le(band, Layout.box_height(target)) == True{} : Bool},
  tail: Rule.RenderedEvidence(rest, Layout.control_placements(rest, target, band), target)) ->
  Rule.RenderedEvidence(Space.Placement{Layout.FixedControl{key, geometry}, offset, width} <> rest,
    Layout.control_placements(Space.Placement{Layout.FixedControl{key, geometry}, offset, width} <> rest, target, band), target):
  Design.Box{left, top, target_width, target_height} = target
  (control_key(key, geometry, offset, width, target, band),
    (control_box(key, geometry, offset, width, target, band, own_width, own_height, own_end, band_fits), tail))

def rendered_region(+key: String, +minimum: Nat, +offset: Nat, +width: Nat,
  +rest: +List<Space.Placement<Layout.BandItem>>, +target: Design.Box, +band: Nat,
  own_height: {Nat.is_le(minimum, band) == True{} : Bool},
  own_end: {Nat.is_le(Nat.add(offset, width), Layout.box_width(target)) == True{} : Bool},
  band_fits: {Nat.is_le(band, Layout.box_height(target)) == True{} : Bool},
  tail: Rule.RenderedEvidence(rest, Layout.control_placements(rest, target, band), target)) ->
  Rule.RenderedEvidence(Space.Placement{Layout.FlexibleRegion{key, minimum}, offset, width} <> rest,
    Layout.control_placements(Space.Placement{Layout.FlexibleRegion{key, minimum}, offset, width} <> rest, target, band), target):
  Design.Box{left, top, target_width, target_height} = target
  ({==}, (region_box(minimum, left, top, target_width, target_height, offset, width, band, own_height, own_end, band_fits), tail))

def rendered_boxes(+placements: +List<Space.Placement<Layout.BandItem>>, +target: Design.Box, +band: Nat,
  widths: Rule.SlotBounds(placements), heights: Rule.HeightFloors(Allocation.placement_values(~Layout.BandItem, placements), band),
  intervals: Rule.IntervalEnds(placements, Layout.box_width(target)),
  +band_fits: {Nat.is_le(band, Layout.box_height(target)) == True{} : Bool}) ->
  Rule.RenderedEvidence(placements, Layout.control_placements(placements, target, band), target):
  match placements:
    case Nil{}: Unit{}
    case Con{Space.Placement{Layout.Spacer{minimum_width}, offset, width}, rest}:
      (own_width, rest_widths) = widths
      (own_height, rest_heights) = heights
      (head_end, tail_ends) = intervals
      rendered_boxes(rest, target, band, rest_widths, rest_heights, tail_ends, band_fits)
    case Con{Space.Placement{Layout.FixedControl{+key, +geometry}, +offset, +width}, +rest}:
      (own_width, rest_widths) = widths
      (own_height, rest_heights) = heights
      (own_end, rest_ends) = intervals
      rendered_fixed(key, geometry, offset, width, rest, target, band, own_width, own_height, own_end, band_fits,
        rendered_boxes(rest, target, band, rest_widths, rest_heights, rest_ends, band_fits))
    case Con{Space.Placement{Layout.FlexibleRegion{+key, +minimum}, +offset, +width}, +rest}:
      (own_width, rest_widths) = widths
      (own_height, rest_heights) = heights
      (own_end, rest_ends) = intervals
      rendered_region(key, minimum, offset, width, rest, target, band, own_height, own_end, band_fits,
        rendered_boxes(rest, target, band, rest_widths, rest_heights, rest_ends, band_fits))

def inner_target_balance(+block: Nat, +height: Nat,
  balance: {Nat.add(Nat.mul(2n, block), Nat.sub(height, Nat.mul(2n, block))) == height : Nat}) ->
  {Nat.is_le(Nat.add(block, Nat.sub(height, Nat.mul(2n, block))), height) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(Nat.add(block, Nat.sub(height, Nat.mul(2n, block))), height),
    Nat.is_le(Nat.add(block, Nat.sub(height, Nat.mul(2n, block))), Nat.add(Nat.mul(2n, block), Nat.sub(height, Nat.mul(2n, block)))), True{},
    Equal.cong(Nat, Bool, (n => Nat.is_le(Nat.add(block, Nat.sub(height, Nat.mul(2n, block))), n)), height,
      Nat.add(Nat.mul(2n, block), Nat.sub(height, Nat.mul(2n, block))), Equal.sym(Nat, Nat.add(Nat.mul(2n, block), Nat.sub(height, Nat.mul(2n, block))), height, balance)),
    Equal.trans(Bool,
      Nat.is_le(Nat.add(block, Nat.sub(height, Nat.mul(2n, block))), Nat.add(Nat.mul(2n, block), Nat.sub(height, Nat.mul(2n, block)))),
      Nat.is_le(Nat.add(block, Nat.sub(height, Nat.mul(2n, block))), Nat.add(block, Nat.add(Nat.add(block, 0n), Nat.sub(height, Nat.mul(2n, block))))), True{},
      Equal.cong(Nat, Bool, (n => Nat.is_le(Nat.add(block, Nat.sub(height, Nat.mul(2n, block))), n)),
        Nat.add(Nat.mul(2n, block), Nat.sub(height, Nat.mul(2n, block))), Nat.add(block, Nat.add(Nat.add(block, 0n), Nat.sub(height, Nat.mul(2n, block)))),
        Alg.nat_add_assoc(block, Nat.add(block, 0n), Nat.sub(height, Nat.mul(2n, block)))),
      offset_le(block, Nat.sub(height, Nat.mul(2n, block)), Nat.add(Nat.add(block, 0n), Nat.sub(height, Nat.mul(2n, block))),
        Equal.trans(Bool, Nat.is_le(Nat.sub(height, Nat.mul(2n, block)), Nat.add(Nat.add(block, 0n), Nat.sub(height, Nat.mul(2n, block)))),
          Nat.is_le(Nat.sub(height, Nat.mul(2n, block)), Nat.add(Nat.sub(height, Nat.mul(2n, block)), Nat.add(block, 0n))), True{},
          Equal.cong(Nat, Bool, (n => Nat.is_le(Nat.sub(height, Nat.mul(2n, block)), n)),
            Nat.add(Nat.add(block, 0n), Nat.sub(height, Nat.mul(2n, block))), Nat.add(Nat.sub(height, Nat.mul(2n, block)), Nat.add(block, 0n)), AllocationProof.add_comm(Nat.add(block, 0n), Nat.sub(height, Nat.mul(2n, block)))),
          AllocationProof.le_add(Nat.sub(height, Nat.mul(2n, block)), Nat.add(block, 0n))))))

# The generic band uses the real target inset on both block sides.
def inner_target_fits(+block: Nat, +height: Nat,
  fits: {Nat.is_le(Nat.mul(2n, block), height) == True{} : Bool}) ->
  {Nat.is_le(Nat.add(block, Nat.sub(height, Nat.mul(2n, block))), height) == True{} : Bool}:
  inner_target_balance(block, height, AllocationProof.second({Nat.is_le(0n, Nat.sub(height, Nat.mul(2n, block))) == True{} : Bool},
    {Nat.add(Nat.mul(2n, block), Nat.sub(height, Nat.mul(2n, block))) == height : Nat},
    AllocationProof.residual(Nat.mul(2n, block), 0n, height,
      Equal.trans(Bool, Nat.is_le(Nat.add(Nat.mul(2n, block), 0n), height), Nat.is_le(Nat.mul(2n, block), height), True{},
        Equal.cong(Nat, Bool, (n => Nat.is_le(n, height)), Nat.add(Nat.mul(2n, block), 0n), Nat.mul(2n, block), Alg.nat_add_zero(Nat.mul(2n, block))), fits))))

def lift_box(+minimum_width: Nat, +minimum_height: Nat, +target: Design.Box, +block: Nat, +actual: Design.Box,
  inner_fits: {Nat.is_le(Nat.add(block, Nat.sub(Layout.box_height(target), Nat.mul(2n, block))), Layout.box_height(target)) == True{} : Bool},
  evidence: Rule.BoxEvidence<minimum_width, minimum_height, Layout.inner_band_target(target, block), actual>) ->
  Rule.BoxEvidence<minimum_width, minimum_height, target, actual>:
  Design.Box{+left, +top, +width, +height} = target
  Rule.BoxEvidence{minimum_width_proof, minimum_height_proof, left_proof, right_proof, top_proof, bottom_proof} = evidence
  Rule.BoxEvidence{minimum_width_proof, minimum_height_proof, left_proof, right_proof,
    AllocationProof.le_trans(top, Nat.add(top, block), Rule.box_top(actual), AllocationProof.le_add(top, block), top_proof),
    AllocationProof.le_trans(Nat.add(Rule.box_top(actual), Layout.box_height(actual)), Nat.add(Nat.add(top, block), Nat.sub(height, Nat.mul(2n, block))),
      Nat.add(top, height), bottom_proof, translated_end(top, block, Nat.sub(height, Nat.mul(2n, block)), height, inner_fits))}

def lift_rendered(+placements: +List<Space.Placement<Layout.BandItem>>, +boxes: +List<Design.NodePlacement>, +target: Design.Box, +block: Nat,
  +inner_fits: {Nat.is_le(Nat.add(block, Nat.sub(Layout.box_height(target), Nat.mul(2n, block))), Layout.box_height(target)) == True{} : Bool},
  evidence: Rule.RenderedEvidence(placements, boxes, Layout.inner_band_target(target, block))) -> Rule.RenderedEvidence(placements, boxes, target):
  match placements boxes:
    case Nil{} Nil{}: Unit{}
    case Nil{} Con{head, tail}: AllocationProof.impossible(Rule.RenderedEvidence(Nil{}, head <> tail, target), evidence)
    case Con{Space.Placement{Layout.Spacer{minimum_width}, offset, width}, rest} _:
      lift_rendered(rest, boxes, target, block, inner_fits, evidence)
    case Con{Space.Placement{Layout.FixedControl{key, geometry}, offset, width}, rest} Nil{}:
      AllocationProof.impossible(Rule.RenderedEvidence(Space.Placement{Layout.FixedControl{key, geometry}, offset, width} <> rest, Nil{}, target), evidence)
    case Con{Space.Placement{Layout.FlexibleRegion{key, minimum}, offset, width}, rest} Nil{}:
      AllocationProof.impossible(Rule.RenderedEvidence(Space.Placement{Layout.FlexibleRegion{key, minimum}, offset, width} <> rest, Nil{}, target), evidence)
    case Con{Space.Placement{Layout.FixedControl{+key, +geometry}, offset, width}, +rest} Con{Design.NodePlacement{+actual_key, +actual}, +tail}:
      (same, pair) = evidence
      (own, following) = pair
      (same, (lift_box(Controls.geometry_minimum_width(geometry), Controls.geometry_minimum_height(geometry), target, block, actual, inner_fits, own),
        lift_rendered(rest, tail, target, block, inner_fits, following)))
    case Con{Space.Placement{Layout.FlexibleRegion{+key, +minimum}, offset, width}, +rest} Con{Design.NodePlacement{+actual_key, +actual}, +tail}:
      (same, pair) = evidence
      (own, following) = pair
      (same, (lift_box(0n, minimum, target, block, actual, inner_fits, own),
        lift_rendered(rest, tail, target, block, inner_fits, following)))

def vertical_balanced(+cross: Nat, +block: Nat, +chosen: Nat, +available: Nat,
  +fits: {Nat.is_le(chosen, available) == True{} : Bool},
  +required: {Nat.is_le(Nat.add(cross, Nat.mul(2n, block)), chosen) == True{} : Bool},
  residual: {Nat.is_le(cross, Nat.sub(chosen, Nat.mul(2n, block))) == True{} : Bool} &
    {Nat.add(Nat.mul(2n, block), Nat.sub(chosen, Nat.mul(2n, block))) == chosen : Nat}) -> Rule.VerticalEvidence<cross, block, chosen, available>:
  (floor, +balance) = residual
  Rule.VerticalEvidence{floor, balance, fits,
    AllocationProof.room_fits(Nat.sub(chosen, Nat.mul(2n, block)), Nat.mul(2n, block), available,
      Equal.trans(Bool, Nat.is_le(Nat.add(Nat.sub(chosen, Nat.mul(2n, block)), Nat.mul(2n, block)), available),
        Nat.is_le(chosen, available), True{},
        Equal.cong(Nat, Bool, (n => Nat.is_le(n, available)), Nat.add(Nat.sub(chosen, Nat.mul(2n, block)), Nat.mul(2n, block)), chosen,
          Equal.trans(Nat, Nat.add(Nat.sub(chosen, Nat.mul(2n, block)), Nat.mul(2n, block)), Nat.add(Nat.mul(2n, block), Nat.sub(chosen, Nat.mul(2n, block))), chosen,
            AllocationProof.add_comm(Nat.sub(chosen, Nat.mul(2n, block)), Nat.mul(2n, block)), balance)), fits)),
    AllocationProof.reserve_fits(cross, Nat.mul(2n, block), available,
      AllocationProof.le_trans(Nat.add(cross, Nat.mul(2n, block)), chosen, available, required, fits))}

def vertical_evidence(+cross: Nat, +block: Nat, +chosen: Nat, +available: Nat,
  fits: {Nat.is_le(chosen, available) == True{} : Bool},
  +required: {Nat.is_le(Nat.add(cross, Nat.mul(2n, block)), chosen) == True{} : Bool}) -> Rule.VerticalEvidence<cross, block, chosen, available>:
  vertical_balanced(cross, block, chosen, available, fits, required,
    AllocationProof.residual(Nat.mul(2n, block), cross, chosen,
      Equal.trans(Bool, Nat.is_le(Nat.add(Nat.mul(2n, block), cross), chosen), Nat.is_le(Nat.add(cross, Nat.mul(2n, block)), chosen), True{},
        Equal.cong(Nat, Bool, (n => Nat.is_le(n, chosen)), Nat.add(Nat.mul(2n, block), cross), Nat.add(cross, Nat.mul(2n, block)), AllocationProof.add_comm(Nat.mul(2n, block), cross)), required)))

def and_true(+left: Bool, +right: Bool, first: {left == True{} : Bool}, second: {right == True{} : Bool}) ->
  {Bool.and(left, right) == True{} : Bool}:
  match left:
    case True{}: second
    case False{}: AllocationProof.impossible({Bool.and(False{}, right) == True{} : Bool}, first)

def box_contained(+minimum_width: Nat, +minimum_height: Nat, +target: Design.Box, +actual: Design.Box,
  evidence: Rule.BoxEvidence<minimum_width, minimum_height, target, actual>) -> {SpatialRules.contains(target, actual) == True{} : Bool}:
  Design.Box{+left, +top, +width, +height} = target
  Design.Box{+actual_left, +actual_top, +actual_width, +actual_height} = actual
  Rule.BoxEvidence{own_width, own_height, left_proof, right_proof, top_proof, bottom_proof} = evidence
  and_true(Nat.is_le(left, actual_left), Bool.and(Nat.is_le(top, actual_top),
    Bool.and(Nat.is_le(Nat.add(actual_left, actual_width), Nat.add(left, width)), Nat.is_le(Nat.add(actual_top, actual_height), Nat.add(top, height)))), left_proof,
    and_true(Nat.is_le(top, actual_top), Bool.and(Nat.is_le(Nat.add(actual_left, actual_width), Nat.add(left, width)), Nat.is_le(Nat.add(actual_top, actual_height), Nat.add(top, height))), top_proof,
      and_true(Nat.is_le(Nat.add(actual_left, actual_width), Nat.add(left, width)), Nat.is_le(Nat.add(actual_top, actual_height), Nat.add(top, height)), right_proof, bottom_proof)))

def rendered_contained(+placements: +List<Space.Placement<Layout.BandItem>>, +boxes: +List<Design.NodePlacement>, +target: Design.Box,
  evidence: Rule.RenderedEvidence(placements, boxes, target)) -> {SpatialRules.all_contained(target, boxes) == True{} : Bool}:
  match placements boxes:
    case Nil{} Nil{}: {==}
    case Nil{} Con{head, tail}: AllocationProof.impossible({SpatialRules.all_contained(target, head <> tail) == True{} : Bool}, evidence)
    case Con{Space.Placement{Layout.Spacer{minimum_width}, offset, width}, rest} _: rendered_contained(rest, boxes, target, evidence)
    case Con{Space.Placement{Layout.FixedControl{key, geometry}, offset, width}, rest} Nil{}: {==}
    case Con{Space.Placement{Layout.FlexibleRegion{key, minimum}, offset, width}, rest} Nil{}: {==}
    case Con{Space.Placement{Layout.FixedControl{key, +geometry}, offset, width}, +rest} Con{Design.NodePlacement{actual_key, +actual}, +tail}:
      (same, pair) = evidence
      (own, following) = pair
      and_true(SpatialRules.contains(target, actual), SpatialRules.all_contained(target, tail),
        box_contained(Controls.geometry_minimum_width(geometry), Controls.geometry_minimum_height(geometry), target, actual, own),
        rendered_contained(rest, tail, target, following))
    case Con{Space.Placement{Layout.FlexibleRegion{key, +minimum}, offset, width}, +rest} Con{Design.NodePlacement{actual_key, +actual}, +tail}:
      (same, pair) = evidence
      (own, following) = pair
      and_true(SpatialRules.contains(target, actual), SpatialRules.all_contained(target, tail), box_contained(0n, minimum, target, actual, own),
        rendered_contained(rest, tail, target, following))

def fixed_coordinates(+key: String, +geometry: Controls.Geometry, +offset: Nat, +width: Nat,
  +rest: +List<Space.Placement<Layout.BandItem>>, +origin: Design.Box, +height: Nat,
  tail: Rule.Coordinates(rest, Layout.control_placements(rest, origin, height), origin, height)) ->
  Rule.Coordinates(Space.Placement{Layout.FixedControl{key, geometry}, offset, width} <> rest,
    Layout.control_placements(Space.Placement{Layout.FixedControl{key, geometry}, offset, width} <> rest, origin, height), origin, height):
  Design.Box{left, top, target_width, target_height} = origin
  ({==}, ({==}, ({==}, ({==}, tail))))

def region_coordinates(+key: String, +minimum: Nat, +offset: Nat, +width: Nat,
  +rest: +List<Space.Placement<Layout.BandItem>>, +origin: Design.Box, +height: Nat,
  tail: Rule.Coordinates(rest, Layout.control_placements(rest, origin, height), origin, height)) ->
  Rule.Coordinates(Space.Placement{Layout.FlexibleRegion{key, minimum}, offset, width} <> rest,
    Layout.control_placements(Space.Placement{Layout.FlexibleRegion{key, minimum}, offset, width} <> rest, origin, height), origin, height):
  Design.Box{left, top, target_width, target_height} = origin
  ({==}, ({==}, ({==}, ({==}, tail))))

def coordinates(+placements: +List<Space.Placement<Layout.BandItem>>, +origin: Design.Box, +height: Nat) ->
  Rule.Coordinates(placements, Layout.control_placements(placements, origin, height), origin, height):
  match placements:
    case Nil{}: Unit{}
    case Con{Space.Placement{Layout.Spacer{minimum}, offset, width}, rest}: coordinates(rest, origin, height)
    case Con{Space.Placement{Layout.FixedControl{+key, +geometry}, +offset, +width}, +rest}:
      fixed_coordinates(key, geometry, offset, width, rest, origin, height, coordinates(rest, origin, height))
    case Con{Space.Placement{Layout.FlexibleRegion{+key, +minimum}, +offset, +width}, +rest}:
      region_coordinates(key, minimum, offset, width, rest, origin, height, coordinates(rest, origin, height))

def packed_ready_vertical(+frame: Enclosure.Frame, +items: +List<Layout.BandItem>,
  +target: Design.Box, +chosen: Nat, +placements: +List<Space.Placement<Layout.BandItem>>, +unused: Nat,
  +floor: {Nat.is_le(Layout.cross_minimum(items), Nat.sub(chosen, Nat.mul(2n, Layout.frame_block(frame)))) == True{} : Bool},
  vertical_budget: {Nat.add(Nat.mul(2n, Layout.frame_block(frame)), Nat.sub(chosen, Nat.mul(2n, Layout.frame_block(frame)))) == chosen : Nat},
  extent: {Nat.is_le(chosen, Layout.box_height(target)) == True{} : Bool},
  +inner_extent: {Nat.is_le(Nat.sub(chosen, Nat.mul(2n, Layout.frame_block(frame))), Nat.sub(Layout.box_height(target), Nat.mul(2n, Layout.frame_block(frame)))) == True{} : Bool},
  +insets: {Nat.is_le(Nat.mul(2n, Layout.frame_block(frame)), Layout.box_height(target)) == True{} : Bool},
  claim: Container.ContainerClaim(~Layout.BandItem, Layout.band_container(Layout.Band{frame, items}), Layout.box_width(target), Space.Packed{placements, unused})) ->
  Rule.ReadyEvidence<frame, items, target, chosen, placements, unused,
    Layout.control_placements(placements, Layout.inner_band_target(target, Layout.frame_block(frame)), Nat.sub(chosen, Nat.mul(2n, Layout.frame_block(frame))))>:
  Design.Box{left, top, width, height} = target
  (evidence, +balance) = claim
  Allocation.AllocationEvidence{+payload, +bounds, +positions, total} = evidence
  Rule.ReadyEvidence{payload_items(items, placements, payload),
    Allocation.AllocationEvidence{payload, bounds, positions, total}, balance,
    Rule.VerticalEvidence{floor, vertical_budget, extent, inner_extent, insets},
    lift_rendered(placements,
      Layout.control_placements(placements, Layout.inner_band_target(target, Layout.frame_block(frame)), Nat.sub(chosen, Nat.mul(2n, Layout.frame_block(frame)))),
      target, Layout.frame_block(frame), inner_target_fits(Layout.frame_block(frame), height, insets),
      rendered_boxes(placements, Layout.inner_band_target(target, Layout.frame_block(frame)), Nat.sub(chosen, Nat.mul(2n, Layout.frame_block(frame))),
        own_limits(items, placements, payload_items(items, placements, payload), bounds),
        Std.transport(+List<Layout.BandItem>, items,
          (values => Rule.HeightFloors(values, Nat.sub(chosen, Nat.mul(2n, Layout.frame_block(frame))))),
          cross_floors(items, Nat.sub(chosen, Nat.mul(2n, Layout.frame_block(frame))), floor),
          Allocation.placement_values(~Layout.BandItem, placements), payload_items(items, placements, payload)),
        container_intervals(placements, Layout.frame_inline(frame), Enclosure.frame_gap(frame), unused, width, positions, balance), inner_extent)),
    rendered_contained(placements,
      Layout.control_placements(placements, Layout.inner_band_target(target, Layout.frame_block(frame)), Nat.sub(chosen, Nat.mul(2n, Layout.frame_block(frame)))), target,
lift_rendered(placements,
      Layout.control_placements(placements, Layout.inner_band_target(target, Layout.frame_block(frame)), Nat.sub(chosen, Nat.mul(2n, Layout.frame_block(frame)))),
      target, Layout.frame_block(frame), inner_target_fits(Layout.frame_block(frame), height, insets),
      rendered_boxes(placements, Layout.inner_band_target(target, Layout.frame_block(frame)), Nat.sub(chosen, Nat.mul(2n, Layout.frame_block(frame))),
        own_limits(items, placements, payload_items(items, placements, payload), bounds),
        Std.transport(+List<Layout.BandItem>, items,
          (values => Rule.HeightFloors(values, Nat.sub(chosen, Nat.mul(2n, Layout.frame_block(frame))))),
          cross_floors(items, Nat.sub(chosen, Nat.mul(2n, Layout.frame_block(frame))), floor),
          Allocation.placement_values(~Layout.BandItem, placements), payload_items(items, placements, payload)),
        container_intervals(placements, Layout.frame_inline(frame), Enclosure.frame_gap(frame), unused, width, positions, balance), inner_extent))),
    coordinates(placements, Layout.inner_band_target(target, Layout.frame_block(frame)), Nat.sub(chosen, Nat.mul(2n, Layout.frame_block(frame)))),
    Equal.trans(+List<String>,
      Rule.placement_keys(Layout.control_placements(placements, Layout.inner_band_target(target, Layout.frame_block(frame)), Nat.sub(chosen, Nat.mul(2n, Layout.frame_block(frame))))),
      Rule.item_keys(Allocation.placement_values(~Layout.BandItem, placements)), Rule.item_keys(items),
      rendered_order(placements, Layout.inner_band_target(target, Layout.frame_block(frame)), Nat.sub(chosen, Nat.mul(2n, Layout.frame_block(frame)))),
      Equal.cong(+List<Layout.BandItem>, +List<String>, (values => Rule.item_keys(values)), Allocation.placement_values(~Layout.BandItem, placements), items, payload_items(items, placements, payload)))}

def packed_ready(+frame: Enclosure.Frame, +items: +List<Layout.BandItem>,
  +target: Design.Box, +chosen: Nat, +placements: +List<Space.Placement<Layout.BandItem>>, +unused: Nat,
  vertical: Rule.VerticalEvidence<Layout.cross_minimum(items), Layout.frame_block(frame), chosen, Layout.box_height(target)>,
  claim: Container.ContainerClaim(~Layout.BandItem, Layout.band_container(Layout.Band{frame, items}), Layout.box_width(target), Space.Packed{placements, unused})) ->
  Rule.ReadyEvidence<frame, items, target, chosen, placements, unused,
    Layout.control_placements(placements, Layout.inner_band_target(target, Layout.frame_block(frame)), Nat.sub(chosen, Nat.mul(2n, Layout.frame_block(frame))))>:
  Rule.VerticalEvidence{floor, budget, extent, inner_extent, insets} = vertical
  packed_ready_vertical(frame, items, target, chosen, placements, unused, floor, budget, extent, inner_extent, insets, claim)

def finish_refinement(+frame: Enclosure.Frame, +items: +List<Layout.BandItem>, +target: Design.Box, +chosen: Nat,
  +packing: Space.Packing<Layout.BandItem>,
  vertical: Rule.VerticalEvidence<Layout.cross_minimum(items), Layout.frame_block(frame), chosen, Layout.box_height(target)>,
  claim: Container.ContainerClaim(~Layout.BandItem, Layout.band_container(Layout.Band{frame, items}), Layout.box_width(target), packing)) ->
  Rule.PackedClaim(frame, items, target, chosen, packing,
    Layout.finish_controls(packing, Layout.inner_band_target(target, Layout.frame_block(frame)), Nat.sub(chosen, Nat.mul(2n, Layout.frame_block(frame))))):
  match packing:
    case Space.Packed{placements, unused}: packed_ready(frame, items, target, chosen, placements, unused, vertical, claim)
    case Space.Insufficient{required, available}: ({==}, ({==}, claim))
def complete_rejected(+parameters: Design.LayoutParameters, +target: Design.Box, +band: Layout.Band,
  correspondence: {Nat.is_le(Layout.band_cross_required(band), Layout.box_height(target)) == False{} : Bool}) ->
  Rule.BandClaimChoice(False{}, parameters, target, band, Layout.allocate_band_guard(False{}, parameters, target, band, Layout.band_cross_required(band))):
  Design.Box{left, top, width, height} = target
  ({==}, ({==}, correspondence))

def complete_accepted_frame(+parameters: Design.LayoutParameters, +target: Design.Box, +frame: Enclosure.Frame, +items: +List<Layout.BandItem>,
  +correspondence: {Nat.is_le(Layout.band_cross_required(Layout.Band{frame, items}), Layout.box_height(target)) == True{} : Bool}) ->
  Rule.BandClaimChoice(True{}, parameters, target, Layout.Band{frame, items},
    Layout.allocate_band_guard(True{}, parameters, target, Layout.Band{frame, items}, Layout.band_cross_required(Layout.Band{frame, items}))):
  Design.Box{left, top, width, height} = target
  (correspondence,
    finish_refinement(frame, items, target, Rule.chosen_band_height(parameters, target, frame, items),
      Space.pack_container(~Layout.BandItem, Layout.band_container(Layout.Band{frame, items}), width),
      vertical_evidence(Layout.cross_minimum(items), Layout.frame_block(frame), Rule.chosen_band_height(parameters, target, frame, items), height,
        AllocationProof.min_le_first(height, Nat.max(Design.toolbar_height(parameters), Layout.band_cross_required(Layout.Band{frame, items}))),
        band_floor(Layout.band_cross_required(Layout.Band{frame, items}), height,
          Nat.max(Design.toolbar_height(parameters), Layout.band_cross_required(Layout.Band{frame, items})), correspondence,
          max_right(Design.toolbar_height(parameters), Layout.band_cross_required(Layout.Band{frame, items})))),
      ContainerProof.complete(~Layout.BandItem, Layout.band_container(Layout.Band{frame, items}), width)))

def complete_accepted(+parameters: Design.LayoutParameters, +target: Design.Box, +band: Layout.Band,
  correspondence: {Nat.is_le(Layout.band_cross_required(band), Layout.box_height(target)) == True{} : Bool}) ->
  Rule.BandClaimChoice(True{}, parameters, target, band, Layout.allocate_band_guard(True{}, parameters, target, band, Layout.band_cross_required(band))):
  Layout.Band{+frame, +items} = band
  complete_accepted_frame(parameters, target, frame, items, correspondence)

def complete_choice(fits: Bool, +parameters: Design.LayoutParameters, +target: Design.Box, +band: Layout.Band,
  correspondence: {Nat.is_le(Layout.band_cross_required(band), Layout.box_height(target)) == fits : Bool}) ->
  Rule.BandClaimChoice(fits, parameters, target, band, Layout.allocate_band_guard(fits, parameters, target, band, Layout.band_cross_required(band))):
  match fits:
    case False{}: complete_rejected(parameters, target, band, correspondence)
    case True{}: complete_accepted(parameters, target, band, correspondence)

def band_complete(+parameters: Design.LayoutParameters, +target: Design.Box, +band: Layout.Band) ->
  Rule.BandClaim(parameters, target, band, Layout.allocate_band(parameters, target, band)):
  Design.Box{left, top, width, height} = target
  complete_choice(Nat.is_le(Layout.band_cross_required(band), height), parameters, target, band, {==})

def complete(+parameters: Design.LayoutParameters, +target: Design.Box,
  +leading: +List<Layout.BandItem>, +trailing: +List<Layout.BandItem>) ->
  Rule.ControlClaim(parameters, target, leading, trailing, Layout.allocate_controls(parameters, target, leading, trailing)):
  band_complete(parameters, target, Layout.root_band(leading, trailing))

def Rule.evidence():
  Rule.Requirements{band_complete, complete}
