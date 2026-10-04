import Base
import ../bendlib/stdlib.bend as Std
import ./layout.bend as Layout
import ./design.bend as Design
import ./controls.bend as Controls
import ./space.bend as Space
import ./space-laws.bend as Allocation
import ./container-space-laws.bend as Container

def placement_key(placement: Design.ControlPlacement) -> String:
  Design.ControlPlacement{key, bounds} = placement
  key

def placement_width(placement: Design.ControlPlacement) -> Nat:
  Design.ControlPlacement{key, Design.Box{left, top, width, height}} = placement
  width

def item_keys(items: +List<Layout.ControlItem>) -> +List<String>:
  match items:
    case Nil{}: Nil{}
    case Con{Layout.FixedControl{key, geometry}, rest}: key <> item_keys(rest)
    case Con{Layout.ControlSpacer{}, rest}: item_keys(rest)

def placement_keys(placements: +List<Design.ControlPlacement>) -> +List<String>:
  match placements:
    case Nil{}: Nil{}
    case Con{Design.ControlPlacement{key, bounds}, rest}: key <> placement_keys(rest)

def control_key(+key: String, geometry: Controls.Geometry, offset: Nat, width: Nat,
  target: Design.Box, band: Nat) ->
  {placement_key(Layout.control_placement(key, geometry, offset, width, target, band)) == key : String}:
  Design.Box{left, top, target_width, target_height} = target
  {==}

def control_width(key: String, geometry: Controls.Geometry, offset: Nat, +width: Nat,
  target: Design.Box, band: Nat) ->
  {placement_width(Layout.control_placement(key, geometry, offset, width, target, band)) == width : Nat}:
  Design.Box{left, top, target_width, target_height} = target
  {==}

def height_limits(+geometry: Controls.Geometry, +band: Nat,
  fits: {Nat.is_le(Controls.geometry_minimum_height(geometry), band) == True{} : Bool}) ->
  {Nat.is_le(Controls.geometry_minimum_height(geometry), Layout.control_height(geometry, band)) == True{} : Bool} &
  {Nat.is_le(Layout.control_height(geometry, band), band) == True{} : Bool}:
  (Allocation.chosen_lower(Space.Fit{Controls.geometry_minimum_height(geometry),
      Nat.sub(Controls.geometry_preferred_height(geometry), Controls.geometry_minimum_height(geometry)), 0n}, band, fits),
    Allocation.min_le_second(Nat.add(Controls.geometry_minimum_height(geometry),
      Nat.sub(Controls.geometry_preferred_height(geometry), Controls.geometry_minimum_height(geometry))), band))

def rendered_order(+placements: +List<Space.Placement<Layout.ControlItem>>, +target: Design.Box, +band: Nat) ->
  {placement_keys(Layout.control_placements(placements, target, band)) ==
    item_keys(Allocation.placement_values(~Layout.ControlItem, placements)) : +List<String>}:
  match placements:
    case Nil{}: {==}
    case Con{Space.Placement{Layout.ControlSpacer{}, offset, width}, rest}:
      rendered_order(rest, target, band)
    case Con{Space.Placement{Layout.FixedControl{+key, geometry}, offset, width}, rest}:
      Design.Box{left, top, target_width, target_height} = target
      Equal.cong(+List<String>, +List<String>, (tail => key <> tail),
        placement_keys(Layout.control_placements(rest, target, band)),
        item_keys(Allocation.placement_values(~Layout.ControlItem, rest)), rendered_order(rest, target, band))

def container_allocation(+leading: +List<Layout.ControlItem>, +trailing: +List<Layout.ControlItem>, +width: Nat) ->
  Container.ContainerClaim(~Layout.ControlItem, Layout.control_container(leading, trailing), width,
    Space.pack_container(~Layout.ControlItem, Layout.control_container(leading, trailing), width)):
  Container.complete(~Layout.ControlItem, Layout.control_container(leading, trailing), width)

# The centering formula uses the pinned Base division worker directly.
def divmod_count_bound(+n: Nat, +m: Nat, +d: Nat, +r: Nat) ->
  {Nat.is_le(Nat.div.fin(Nat.divmod.go(n, m, d, r)), Nat.add(n, d)) == True{} : Bool}:
  match n:
    case 0n: Allocation.le_refl(d)
    case 1n+np:
      match m:
        case 0n:
          %Allocation.add_succ(np, d) :
            {Nat.is_le(Nat.div.fin(Nat.divmod.go(np, r, 1n+d, 0n)), _) == True{} : Bool}
          divmod_count_bound(np, r, 1n+d, 0n)
        case 1n+mp:
          +value = Nat.div.fin(Nat.divmod.go(np, mp, d, 1n+r))
          Allocation.le_trans(value, Nat.add(np, d), 1n+Nat.add(np, d),
            divmod_count_bound(np, mp, d, 1n+r),
            Equal.trans(Bool, Nat.is_le(Nat.add(np, d), 1n+Nat.add(np, d)),
              Nat.is_le(Nat.add(np, d), Nat.add(Nat.add(np, d), 1n)), True{},
              Equal.cong(Nat, Bool, (bound => Nat.is_le(Nat.add(np, d), bound)),
                1n+Nat.add(np, d), Nat.add(Nat.add(np, d), 1n),
                Allocation.add_comm(1n, Nat.add(np, d))),
              Allocation.le_add(Nat.add(np, d), 1n)))

def half_bound(+room: Nat) -> {Nat.is_le(Nat.div(room, 2n), room) == True{} : Bool}:
  %Allocation.add_zero(room) :
    {Nat.is_le(Nat.div(room, 2n), _) == True{} : Bool}
  divmod_count_bound(room, 1n, 0n, 0n)

def max_left(+a: Nat, +b: Nat) -> {Nat.is_le(a, Nat.max(a, b)) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(a, Nat.max(a, b)), Nat.is_ge(Nat.max(a, b), a), True{},
    Equal.sym(Bool, Nat.is_ge(Nat.max(a, b), a), Nat.is_le(a, Nat.max(a, b)), Allocation.ge_le(Nat.max(a, b), a)), Nat.max_ge_l(a, b))

def max_right(+a: Nat, +b: Nat) -> {Nat.is_le(b, Nat.max(a, b)) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(b, Nat.max(a, b)), Nat.is_ge(Nat.max(a, b), b), True{},
    Equal.sym(Bool, Nat.is_ge(Nat.max(a, b), b), Nat.is_le(b, Nat.max(a, b)), Allocation.ge_le(Nat.max(a, b), b)), Nat.max_ge_r(a, b))

def band_floor(+lower: Nat, +height: Nat, +preferred: Nat,
  fits: {Nat.is_le(lower, height) == True{} : Bool},
  wanted: {Nat.is_le(lower, preferred) == True{} : Bool}) ->
  {Nat.is_le(lower, Nat.min(height, preferred)) == True{} : Bool}:
  match lower height preferred:
    case 0n _ _: Allocation.zero_le(Nat.min(height, preferred))
    case 1n+a 0n _: Allocation.impossible({Nat.is_le(1n+a, Nat.min(0n, preferred)) == True{} : Bool}, fits)
    case 1n+a 1n+b 0n: Allocation.impossible({Nat.is_le(1n+a, 0n) == True{} : Bool}, wanted)
    case 1n+a 1n+b 1n+c: band_floor(a, b, c, fits, wanted)

def HeightFloors(items: +List<Layout.ControlItem>, +band: Nat) -> Type:
  match items:
    case Nil{}: Unit
    case Con{Layout.ControlSpacer{}, rest}: HeightFloors(rest, band)
    case Con{Layout.FixedControl{key, geometry}, rest}:
      {Nat.is_le(Controls.geometry_minimum_height(geometry), band) == True{} : Bool} & HeightFloors(rest, band)

def cross_floors(+items: +List<Layout.ControlItem>, +band: Nat,
  +fits: {Nat.is_le(Layout.cross_minimum(items), band) == True{} : Bool}) -> HeightFloors(items, band):
  match items:
    case Nil{}: Unit{}
    case Con{Layout.ControlSpacer{}, rest}: cross_floors(rest, band, fits)
    case Con{Layout.FixedControl{key, +geometry}, +rest}:
      (Allocation.le_trans(Controls.geometry_minimum_height(geometry),
         Nat.max(Controls.geometry_minimum_height(geometry), Layout.cross_minimum(rest)), band,
         max_left(Controls.geometry_minimum_height(geometry), Layout.cross_minimum(rest)), fits),
       cross_floors(rest, band, Allocation.le_trans(Layout.cross_minimum(rest),
         Nat.max(Controls.geometry_minimum_height(geometry), Layout.cross_minimum(rest)), band,
         max_right(Controls.geometry_minimum_height(geometry), Layout.cross_minimum(rest)), fits)))

def append_floors(+leading: +List<Layout.ControlItem>, +trailing: +List<Layout.ControlItem>, +band: Nat,
  first: HeightFloors(leading, band), last: HeightFloors(trailing, band)) ->
  HeightFloors(List.append(&2, Layout.ControlItem, leading, trailing), band):
  match leading:
    case Nil{}: last
    case Con{Layout.ControlSpacer{}, rest}: append_floors(rest, trailing, band, first, last)
    case Con{Layout.FixedControl{key, geometry}, rest}:
      (head, tail) = first
      (head, append_floors(rest, trailing, band, tail, last))

def trailing_floors(+leading: +List<Layout.ControlItem>, +trailing: +List<Layout.ControlItem>, +band: Nat,
  first: HeightFloors(leading, band), last: HeightFloors(trailing, band)) ->
  HeightFloors(Layout.append_trailing(leading, trailing), band):
  match trailing:
    case Nil{}: first
    case Con{head, rest}: append_floors(leading, Layout.ControlSpacer{} <> head <> rest, band, first, last)

def combined_floors(+leading: +List<Layout.ControlItem>, +trailing: +List<Layout.ControlItem>, +band: Nat,
  +fits: {Nat.is_le(Nat.max(Layout.cross_minimum(leading), Layout.cross_minimum(trailing)), band) == True{} : Bool}) ->
  HeightFloors(Layout.append_trailing(leading, trailing), band):
  first = cross_floors(leading, band, Allocation.le_trans(Layout.cross_minimum(leading),
    Nat.max(Layout.cross_minimum(leading), Layout.cross_minimum(trailing)), band,
    max_left(Layout.cross_minimum(leading), Layout.cross_minimum(trailing)), fits))
  last = cross_floors(trailing, band, Allocation.le_trans(Layout.cross_minimum(trailing),
    Nat.max(Layout.cross_minimum(leading), Layout.cross_minimum(trailing)), band,
    max_right(Layout.cross_minimum(leading), Layout.cross_minimum(trailing)), fits))
  trailing_floors(leading, trailing, band, first, last)

def offset_le(+offset: Nat, +a: Nat, +b: Nat, fits: {Nat.is_le(a, b) == True{} : Bool}) ->
  {Nat.is_le(Nat.add(offset, a), Nat.add(offset, b)) == True{} : Bool}:
  match offset:
    case 0n: fits
    case 1n+rest: offset_le(rest, a, b, fits)

def centered_height(+geometry: Controls.Geometry, +band: Nat,
  floor: {Nat.is_le(Controls.geometry_minimum_height(geometry), band) == True{} : Bool}) ->
  {Nat.is_le(Nat.add(Nat.div(Nat.sub(band, Layout.control_height(geometry, band)), 2n), Layout.control_height(geometry, band)), band) == True{} : Bool}:
  +height = Layout.control_height(geometry, band)
  upper = Allocation.second(
    {Nat.is_le(Controls.geometry_minimum_height(geometry), height) == True{} : Bool},
    {Nat.is_le(height, band) == True{} : Bool}, height_limits(geometry, band, floor))
  Allocation.reserved_use(Nat.div(Nat.sub(band, height), 2n), height, band, upper, half_bound(Nat.sub(band, height)))

def and_parts(+a: Bool, +b: Bool, proof: {(a && b) == True{} : Bool}) ->
  {a == True{} : Bool} & {b == True{} : Bool}:
  match a:
    case True{}: ({==}, proof)
    case False{}: Allocation.impossible({False{} == True{} : Bool} & {b == True{} : Bool}, proof)

def natural_equal(+a: Nat, +b: Nat, proof: {Nat.is_eq(a, b) == True{} : Bool}) -> {a == b : Nat}:
  match a b:
    case 0n 0n: {==}
    case 0n 1n+rest: Allocation.impossible({0n == 1n+rest : Nat}, proof)
    case 1n+rest 0n: Allocation.impossible({1n+rest == 0n : Nat}, proof)
    case 1n+left 1n+right: Equal.cong(Nat, Nat, (n => 1n+n), left, right, natural_equal(left, right, proof))

def zero_gap(+placements: +List<Space.Placement<Layout.ControlItem>>) ->
  {Allocation.placement_gap(~Layout.ControlItem, placements, 0n) == 0n : Nat}:
  match placements:
    case Nil{}: {==}
    case Con{head, rest}: {==}

def zero_used(+item: Layout.ControlItem, +offset: Nat, +width: Nat, +rest: +List<Space.Placement<Layout.ControlItem>>) ->
  {Allocation.used(~Layout.ControlItem, Space.Placement{item, offset, width} <> rest, 0n) ==
    Nat.add(width, Allocation.used(~Layout.ControlItem, rest, 0n)) : Nat}:
  match rest:
    case Nil{}: Equal.sym(Nat, Nat.add(width, 0n), width, Allocation.add_zero(width))
    case Con{head, tail}: {==}

def IntervalEnds(placements: +List<Space.Placement<Layout.ControlItem>>, +end: Nat) -> Type:
  match placements:
    case Nil{}: Unit
    case Con{Space.Placement{item, offset, width}, rest}:
      {Nat.is_le(Nat.add(offset, width), end) == True{} : Bool} & IntervalEnds(rest, end)

def position_tail_parts(+actual: Nat, +width: Nat, +rest: +List<Space.Placement<Layout.ControlItem>>, +start: Nat,
  proof: {Nat.is_eq(actual, start) == True{} : Bool} &
    {Allocation.positions(~Layout.ControlItem, rest, 0n, Nat.add(actual, Nat.add(width, Allocation.placement_gap(~Layout.ControlItem, rest, 0n)))) == True{} : Bool}) ->
  {actual == start : Nat} & {Allocation.positions(~Layout.ControlItem, rest, 0n, Nat.add(actual, width)) == True{} : Bool}:
  (same, tail) = proof
  (natural_equal(actual, start, same), Equal.trans(Bool,
    Allocation.positions(~Layout.ControlItem, rest, 0n, Nat.add(actual, width)),
    Allocation.positions(~Layout.ControlItem, rest, 0n, Nat.add(actual, Nat.add(width, Allocation.placement_gap(~Layout.ControlItem, rest, 0n)))), True{},
    Equal.cong(Nat, Bool, (n => Allocation.positions(~Layout.ControlItem, rest, 0n, Nat.add(actual, n))),
      width, Nat.add(width, Allocation.placement_gap(~Layout.ControlItem, rest, 0n)),
      Equal.sym(Nat, Nat.add(width, Allocation.placement_gap(~Layout.ControlItem, rest, 0n)), width,
        Equal.trans(Nat, Nat.add(width, Allocation.placement_gap(~Layout.ControlItem, rest, 0n)), Nat.add(width, 0n), width,
          Equal.cong(Nat, Nat, (n => Nat.add(width, n)), Allocation.placement_gap(~Layout.ControlItem, rest, 0n), 0n, zero_gap(rest)), Allocation.add_zero(width)))), tail))

def position_tail(+item: Layout.ControlItem, +actual: Nat, +width: Nat, +rest: +List<Space.Placement<Layout.ControlItem>>, +start: Nat,
  proof: {Allocation.positions(~Layout.ControlItem, Space.Placement{item, actual, width} <> rest, 0n, start) == True{} : Bool}) ->
  {actual == start : Nat} &
  {Allocation.positions(~Layout.ControlItem, rest, 0n, Nat.add(actual, width)) == True{} : Bool}:
  position_tail_parts(actual, width, rest, start, and_parts(Nat.is_eq(actual, start),
    Allocation.positions(~Layout.ControlItem, rest, 0n, Nat.add(actual, Nat.add(width, Allocation.placement_gap(~Layout.ControlItem, rest, 0n)))), proof))

def positioned_bound(+item: Layout.ControlItem, +actual: Nat, +width: Nat,
  +rest: +List<Space.Placement<Layout.ControlItem>>, +start: Nat, +end: Nat,
  same: {actual == start : Nat},
  fits: {Nat.is_le(Nat.add(start, Allocation.used(~Layout.ControlItem, Space.Placement{item, actual, width} <> rest, 0n)), end) == True{} : Bool}) ->
  {Nat.is_le(Nat.add(Nat.add(actual, width), Allocation.used(~Layout.ControlItem, rest, 0n)), end) == True{} : Bool}:
  Equal.trans(Bool,
    Nat.is_le(Nat.add(Nat.add(actual, width), Allocation.used(~Layout.ControlItem, rest, 0n)), end),
    Nat.is_le(Nat.add(start, Allocation.used(~Layout.ControlItem, Space.Placement{item, actual, width} <> rest, 0n)), end), True{},
    Equal.cong(Nat, Bool, (n => Nat.is_le(n, end)),
      Nat.add(Nat.add(actual, width), Allocation.used(~Layout.ControlItem, rest, 0n)),
      Nat.add(start, Allocation.used(~Layout.ControlItem, Space.Placement{item, actual, width} <> rest, 0n)),
      Equal.trans(Nat, Nat.add(Nat.add(actual, width), Allocation.used(~Layout.ControlItem, rest, 0n)),
        Nat.add(actual, Nat.add(width, Allocation.used(~Layout.ControlItem, rest, 0n))),
        Nat.add(start, Allocation.used(~Layout.ControlItem, Space.Placement{item, actual, width} <> rest, 0n)),
        Allocation.add_assoc(actual, width, Allocation.used(~Layout.ControlItem, rest, 0n)),
        Equal.trans(Nat, Nat.add(actual, Nat.add(width, Allocation.used(~Layout.ControlItem, rest, 0n))),
          Nat.add(actual, Allocation.used(~Layout.ControlItem, Space.Placement{item, actual, width} <> rest, 0n)),
          Nat.add(start, Allocation.used(~Layout.ControlItem, Space.Placement{item, actual, width} <> rest, 0n)),
          Equal.cong(Nat, Nat, (n => Nat.add(actual, n)), Nat.add(width, Allocation.used(~Layout.ControlItem, rest, 0n)),
            Allocation.used(~Layout.ControlItem, Space.Placement{item, actual, width} <> rest, 0n),
            Equal.sym(Nat, Allocation.used(~Layout.ControlItem, Space.Placement{item, actual, width} <> rest, 0n),
              Nat.add(width, Allocation.used(~Layout.ControlItem, rest, 0n)), zero_used(item, actual, width, rest))),
          Equal.cong(Nat, Nat, (n => Nat.add(n, Allocation.used(~Layout.ControlItem, Space.Placement{item, actual, width} <> rest, 0n))), actual, start, same)))), fits)

def intervals_step(+actual: Nat, +width: Nat, +rest: +List<Space.Placement<Layout.ControlItem>>, +end: Nat,
  +fits: {Nat.is_le(Nat.add(Nat.add(actual, width), Allocation.used(~Layout.ControlItem, rest, 0n)), end) == True{} : Bool},
  tail: IntervalEnds(rest, end)) ->
  {Nat.is_le(Nat.add(actual, width), end) == True{} : Bool} & IntervalEnds(rest, end):
  (Allocation.le_trans(Nat.add(actual, width), Nat.add(Nat.add(actual, width), Allocation.used(~Layout.ControlItem, rest, 0n)), end,
    Allocation.le_add(Nat.add(actual, width), Allocation.used(~Layout.ControlItem, rest, 0n)), fits), tail)

def position_intervals(+placements: +List<Space.Placement<Layout.ControlItem>>, +start: Nat, +end: Nat,
  +positions: {Allocation.positions(~Layout.ControlItem, placements, 0n, start) == True{} : Bool},
  +fits: {Nat.is_le(Nat.add(start, Allocation.used(~Layout.ControlItem, placements, 0n)), end) == True{} : Bool}) ->
  IntervalEnds(placements, end):
  match placements:
    case Nil{}: Unit{}
    case Con{Space.Placement{+item, +actual, +width}, +rest}:
      tail_positions = Allocation.second({actual == start : Nat},
        {Allocation.positions(~Layout.ControlItem, rest, 0n, Nat.add(actual, width)) == True{} : Bool}, position_tail(item, actual, width, rest, start, positions))
      intervals_step(actual, width, rest, end, positioned_bound(item, actual, width, rest, start, end, Allocation.first({actual == start : Nat},
          {Allocation.positions(~Layout.ControlItem, rest, 0n, Nat.add(actual, width)) == True{} : Bool}, position_tail(item, actual, width, rest, start, positions)), fits),
        position_intervals(rest, Nat.add(actual, width), end, tail_positions, positioned_bound(item, actual, width, rest, start, end, Allocation.first({actual == start : Nat},
          {Allocation.positions(~Layout.ControlItem, rest, 0n, Nat.add(actual, width)) == True{} : Bool}, position_tail(item, actual, width, rest, start, positions)), fits)))

def control_slot_values(+items: +List<Layout.ControlItem>, +clearance: Nat) ->
  {Allocation.slot_values(~Layout.ControlItem, Layout.control_slots(items, clearance)) == items : +List<Layout.ControlItem>}:
  match items:
    case Nil{}: {==}
    case Con{+head, +rest}:
      match head:
        case Layout.ControlSpacer{}:
          Equal.cong(+List<Layout.ControlItem>, +List<Layout.ControlItem>, (tail => Layout.ControlSpacer{} <> tail),
            Allocation.slot_values(~Layout.ControlItem, Layout.control_slots(rest, clearance)), rest, control_slot_values(rest, clearance))
        case Layout.FixedControl{+key, +geometry}:
          Equal.cong(+List<Layout.ControlItem>, +List<Layout.ControlItem>, (tail => Layout.FixedControl{key, geometry} <> tail),
            Allocation.slot_values(~Layout.ControlItem, Layout.control_slots(rest, clearance)), rest, control_slot_values(rest, clearance))

def WidthFloors(placements: +List<Space.Placement<Layout.ControlItem>>) -> Type:
  match placements:
    case Nil{}: Unit
    case Con{Space.Placement{Layout.ControlSpacer{}, offset, width}, rest}: WidthFloors(rest)
    case Con{Space.Placement{Layout.FixedControl{key, geometry}, offset, width}, rest}:
      {Nat.is_le(Controls.geometry_minimum_width(geometry), width) == True{} : Bool} & WidthFloors(rest)

def limit_tail(+dimension: Space.Dimension, +width: Nat, +rest: +List<Space.Slot<Layout.ControlItem>>,
  +tail: +List<Space.Placement<Layout.ControlItem>>,
  proof: {(Nat.is_le(Space.minimum(dimension), width) &&
    (Allocation.maximum_ok(dimension, width) && (Allocation.rigid_ok(dimension, width) && Allocation.limits(~Layout.ControlItem, rest, tail)))) == True{} : Bool}) ->
  {Allocation.limits(~Layout.ControlItem, rest, tail) == True{} : Bool}:
  Allocation.second({Allocation.rigid_ok(dimension, width) == True{} : Bool},
    {Allocation.limits(~Layout.ControlItem, rest, tail) == True{} : Bool},
    and_parts(Allocation.rigid_ok(dimension, width), Allocation.limits(~Layout.ControlItem, rest, tail),
      Allocation.second({Allocation.maximum_ok(dimension, width) == True{} : Bool},
        {(Allocation.rigid_ok(dimension, width) && Allocation.limits(~Layout.ControlItem, rest, tail)) == True{} : Bool},
        and_parts(Allocation.maximum_ok(dimension, width), Allocation.rigid_ok(dimension, width) && Allocation.limits(~Layout.ControlItem, rest, tail),
          Allocation.second({Nat.is_le(Space.minimum(dimension), width) == True{} : Bool},
            {(Allocation.maximum_ok(dimension, width) && (Allocation.rigid_ok(dimension, width) && Allocation.limits(~Layout.ControlItem, rest, tail))) == True{} : Bool},
            and_parts(Nat.is_le(Space.minimum(dimension), width), Allocation.maximum_ok(dimension, width) && (Allocation.rigid_ok(dimension, width) && Allocation.limits(~Layout.ControlItem, rest, tail)), proof))))))

def width_floors(+placements: +List<Space.Placement<Layout.ControlItem>>, +clearance: Nat,
  +bounds: {Allocation.limits(~Layout.ControlItem,
    Layout.control_slots(Allocation.placement_values(~Layout.ControlItem, placements), clearance), placements) == True{} : Bool}) -> WidthFloors(placements):
  match placements:
    case Nil{}: Unit{}
    case Con{Space.Placement{Layout.ControlSpacer{}, offset, +width}, +rest}:
      width_floors(rest, clearance, limit_tail(Space.Fill{clearance}, width,
        Layout.control_slots(Allocation.placement_values(~Layout.ControlItem, rest), clearance), rest, bounds))
    case Con{Space.Placement{Layout.FixedControl{key, +geometry}, offset, +width}, +rest}:
      (Allocation.first({Nat.is_le(Controls.geometry_minimum_width(geometry), width) == True{} : Bool},
        {(Allocation.maximum_ok(Layout.control_dimension(geometry), width) &&
          (Allocation.rigid_ok(Layout.control_dimension(geometry), width) && Allocation.limits(~Layout.ControlItem,
            Layout.control_slots(Allocation.placement_values(~Layout.ControlItem, rest), clearance), rest))) == True{} : Bool},
        and_parts(Nat.is_le(Controls.geometry_minimum_width(geometry), width),
          Allocation.maximum_ok(Layout.control_dimension(geometry), width) &&
          (Allocation.rigid_ok(Layout.control_dimension(geometry), width) && Allocation.limits(~Layout.ControlItem,
            Layout.control_slots(Allocation.placement_values(~Layout.ControlItem, rest), clearance), rest)), bounds)),
        width_floors(rest, clearance, limit_tail(Layout.control_dimension(geometry), width,
          Layout.control_slots(Allocation.placement_values(~Layout.ControlItem, rest), clearance), rest, bounds)))

def payload_items(+items: +List<Layout.ControlItem>, +clearance: Nat,
  +placements: +List<Space.Placement<Layout.ControlItem>>,
  payload: {Allocation.placement_values(~Layout.ControlItem, placements) ==
    Allocation.slot_values(~Layout.ControlItem, Layout.control_slots(items, clearance)) : +List<Layout.ControlItem>}) ->
  {Allocation.placement_values(~Layout.ControlItem, placements) == items : +List<Layout.ControlItem>}:
  Equal.trans(+List<Layout.ControlItem>, Allocation.placement_values(~Layout.ControlItem, placements),
    Allocation.slot_values(~Layout.ControlItem, Layout.control_slots(items, clearance)), items, payload, control_slot_values(items, clearance))

def own_limits(+items: +List<Layout.ControlItem>, +clearance: Nat,
  +placements: +List<Space.Placement<Layout.ControlItem>>,
  same: {Allocation.placement_values(~Layout.ControlItem, placements) == items : +List<Layout.ControlItem>},
  bounds: {Allocation.limits(~Layout.ControlItem, Layout.control_slots(items, clearance), placements) == True{} : Bool}) -> WidthFloors(placements):
  width_floors(placements, clearance, Equal.trans(Bool,
    Allocation.limits(~Layout.ControlItem, Layout.control_slots(Allocation.placement_values(~Layout.ControlItem, placements), clearance), placements),
    Allocation.limits(~Layout.ControlItem, Layout.control_slots(items, clearance), placements), True{},
    Equal.cong(+List<Layout.ControlItem>, Bool, (values => Allocation.limits(~Layout.ControlItem, Layout.control_slots(values, clearance), placements)),
      Allocation.placement_values(~Layout.ControlItem, placements), items, same), bounds))

def container_intervals(+placements: +List<Space.Placement<Layout.ControlItem>>, +inset: Nat, +unused: Nat, +width: Nat,
  positions: {Allocation.positions(~Layout.ControlItem, placements, 0n, inset) == True{} : Bool},
  balance: {Nat.add(inset, Nat.add(Nat.add(Allocation.used(~Layout.ControlItem, placements, 0n), unused), inset)) == width : Nat}) ->
  IntervalEnds(placements, width):
  position_intervals(placements, inset, width,
    positions, Equal.trans(Bool, Nat.is_le(Nat.add(inset, Allocation.used(~Layout.ControlItem, placements, 0n)), width),
      Nat.is_le(Nat.add(inset, Allocation.used(~Layout.ControlItem, placements, 0n)),
        Nat.add(inset, Nat.add(Nat.add(Allocation.used(~Layout.ControlItem, placements, 0n), unused), inset))), True{},
      Equal.cong(Nat, Bool, (n => Nat.is_le(Nat.add(inset, Allocation.used(~Layout.ControlItem, placements, 0n)), n)), width,
        Nat.add(inset, Nat.add(Nat.add(Allocation.used(~Layout.ControlItem, placements, 0n), unused), inset)),
        Equal.sym(Nat, Nat.add(inset, Nat.add(Nat.add(Allocation.used(~Layout.ControlItem, placements, 0n), unused), inset)), width, balance)),
      offset_le(inset, Allocation.used(~Layout.ControlItem, placements, 0n),
        Nat.add(Nat.add(Allocation.used(~Layout.ControlItem, placements, 0n), unused), inset),
        Allocation.le_trans(Allocation.used(~Layout.ControlItem, placements, 0n),
          Nat.add(Allocation.used(~Layout.ControlItem, placements, 0n), unused),
          Nat.add(Nat.add(Allocation.used(~Layout.ControlItem, placements, 0n), unused), inset),
          Allocation.le_add(Allocation.used(~Layout.ControlItem, placements, 0n), unused),
          Allocation.le_add(Nat.add(Allocation.used(~Layout.ControlItem, placements, 0n), unused), inset)))))

def box_left(box: Design.Box) -> Nat:
  Design.Box{left, top, width, height} = box
  left

def box_top(box: Design.Box) -> Nat:
  Design.Box{left, top, width, height} = box
  top

def placement_bounds(placement: Design.ControlPlacement) -> Design.Box:
  Design.ControlPlacement{key, bounds} = placement
  bounds

type BoxEvidence<-geometry: Controls.Geometry, -target: Design.Box, -actual: Design.Box> is Type:
  BoxEvidence{
    minimum_width: {Nat.is_le(Controls.geometry_minimum_width(geometry), Layout.box_width(actual)) == True{} : Bool},
    minimum_height: {Nat.is_le(Controls.geometry_minimum_height(geometry), Layout.box_height(actual)) == True{} : Bool},
    left: {Nat.is_le(box_left(target), box_left(actual)) == True{} : Bool},
    right: {Nat.is_le(Nat.add(box_left(actual), Layout.box_width(actual)), Nat.add(box_left(target), Layout.box_width(target))) == True{} : Bool},
    top: {Nat.is_le(box_top(target), box_top(actual)) == True{} : Bool},
    bottom: {Nat.is_le(Nat.add(box_top(actual), Layout.box_height(actual)), Nat.add(box_top(target), Layout.box_height(target))) == True{} : Bool}}

def translated_end(+origin: Nat, +offset: Nat, +extent: Nat, +available: Nat,
  fits: {Nat.is_le(Nat.add(offset, extent), available) == True{} : Bool}) ->
  {Nat.is_le(Nat.add(Nat.add(origin, offset), extent), Nat.add(origin, available)) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_le(Nat.add(Nat.add(origin, offset), extent), Nat.add(origin, available)),
    Nat.is_le(Nat.add(origin, Nat.add(offset, extent)), Nat.add(origin, available)), True{},
    Equal.cong(Nat, Bool, (n => Nat.is_le(n, Nat.add(origin, available))),
      Nat.add(Nat.add(origin, offset), extent), Nat.add(origin, Nat.add(offset, extent)), Allocation.add_assoc(origin, offset, extent)),
    offset_le(origin, Nat.add(offset, extent), available, fits))

def control_box(+key: String, +geometry: Controls.Geometry, +offset: Nat, +width: Nat, +target: Design.Box, +band: Nat,
  minimum_width: {Nat.is_le(Controls.geometry_minimum_width(geometry), width) == True{} : Bool},
  +minimum_height: {Nat.is_le(Controls.geometry_minimum_height(geometry), band) == True{} : Bool},
  horizontal: {Nat.is_le(Nat.add(offset, width), Layout.box_width(target)) == True{} : Bool},
  band_fits: {Nat.is_le(band, Layout.box_height(target)) == True{} : Bool}) ->
  BoxEvidence<geometry, target, placement_bounds(Layout.control_placement(key, geometry, offset, width, target, band))>:
  Design.Box{+left, +top, +target_width, +target_height} = target
  BoxEvidence{minimum_width,
    Allocation.first({Nat.is_le(Controls.geometry_minimum_height(geometry), Layout.control_height(geometry, band)) == True{} : Bool},
      {Nat.is_le(Layout.control_height(geometry, band), band) == True{} : Bool}, height_limits(geometry, band, minimum_height)),
    Allocation.le_add(left, offset), translated_end(left, offset, width, target_width, horizontal),
    Allocation.le_add(top, Nat.div(Nat.sub(band, Layout.control_height(geometry, band)), 2n)),
    translated_end(top, Nat.div(Nat.sub(band, Layout.control_height(geometry, band)), 2n), Layout.control_height(geometry, band), target_height,
      Allocation.le_trans(Nat.add(Nat.div(Nat.sub(band, Layout.control_height(geometry, band)), 2n), Layout.control_height(geometry, band)), band, target_height,
        centered_height(geometry, band, minimum_height), band_fits))}

def RenderedEvidence(placements: +List<Space.Placement<Layout.ControlItem>>, boxes: +List<Design.ControlPlacement>, +target: Design.Box) -> Type:
  match placements:
    case Nil{}:
      match boxes:
        case Nil{}: Unit
        case Con{head, rest}: {False{} == True{} : Bool}
    case Con{Space.Placement{Layout.ControlSpacer{}, offset, width}, rest}: RenderedEvidence(rest, boxes, target)
    case Con{Space.Placement{Layout.FixedControl{source_key, geometry}, offset, width}, rest}:
      match boxes:
        case Nil{}: {False{} == True{} : Bool}
        case Con{Design.ControlPlacement{key, actual}, tail}:
          {key == source_key : String} & (BoxEvidence<geometry, target, actual> & RenderedEvidence(rest, tail, target))

def rendered_fixed(+key: String, +geometry: Controls.Geometry, +offset: Nat, +width: Nat,
  +rest: +List<Space.Placement<Layout.ControlItem>>, +target: Design.Box, +band: Nat,
  own_width: {Nat.is_le(Controls.geometry_minimum_width(geometry), width) == True{} : Bool},
  own_height: {Nat.is_le(Controls.geometry_minimum_height(geometry), band) == True{} : Bool},
  own_end: {Nat.is_le(Nat.add(offset, width), Layout.box_width(target)) == True{} : Bool},
  band_fits: {Nat.is_le(band, Layout.box_height(target)) == True{} : Bool},
  tail: RenderedEvidence(rest, Layout.control_placements(rest, target, band), target)) ->
  RenderedEvidence(Space.Placement{Layout.FixedControl{key, geometry}, offset, width} <> rest,
    Layout.control_placements(Space.Placement{Layout.FixedControl{key, geometry}, offset, width} <> rest, target, band), target):
  Design.Box{left, top, target_width, target_height} = target
  (control_key(key, geometry, offset, width, target, band),
    (control_box(key, geometry, offset, width, target, band, own_width, own_height, own_end, band_fits), tail))

def rendered_boxes(+placements: +List<Space.Placement<Layout.ControlItem>>, +target: Design.Box, +band: Nat,
  widths: WidthFloors(placements), heights: HeightFloors(Allocation.placement_values(~Layout.ControlItem, placements), band),
  intervals: IntervalEnds(placements, Layout.box_width(target)),
  +band_fits: {Nat.is_le(band, Layout.box_height(target)) == True{} : Bool}) ->
  RenderedEvidence(placements, Layout.control_placements(placements, target, band), target):
  match placements:
    case Nil{}: Unit{}
    case Con{Space.Placement{Layout.ControlSpacer{}, offset, width}, rest}:
      (head_end, tail_ends) = intervals
      rendered_boxes(rest, target, band, widths, heights, tail_ends, band_fits)
    case Con{Space.Placement{Layout.FixedControl{+key, +geometry}, +offset, +width}, +rest}:
      (own_width, rest_widths) = widths
      (own_height, rest_heights) = heights
      (own_end, rest_ends) = intervals
      rendered_fixed(key, geometry, offset, width, rest, target, band, own_width, own_height, own_end, band_fits,
        rendered_boxes(rest, target, band, rest_widths, rest_heights, rest_ends, band_fits))

type ReadyEvidence<-items: +List<Layout.ControlItem>, -clearance: Nat, -inset: Nat,
  -target: Design.Box, -placements: +List<Space.Placement<Layout.ControlItem>>, -unused: Nat,
  -boxes: +List<Design.ControlPlacement>> is Type:
  ReadyEvidence{
    source: {Allocation.placement_values(~Layout.ControlItem, placements) == items : +List<Layout.ControlItem>},
    allocation: Allocation.AllocationEvidence<Layout.ControlItem, Layout.control_slots(items, clearance), 0n, inset,
      Container.inner_budget(inset, inset, Layout.box_width(target)), Space.Allocation{placements, unused}>,
    budget: {Nat.add(inset, Nat.add(Nat.add(Allocation.used(~Layout.ControlItem, placements, 0n), unused), inset)) == Layout.box_width(target) : Nat},
    rectangles: RenderedEvidence(placements, boxes, target),
    order: {placement_keys(boxes) == item_keys(items) : +List<String>}}

def PackedControlsClaim(+items: +List<Layout.ControlItem>, +clearance: Nat, +inset: Nat, +target: Design.Box,
  packing: Space.Packing<Layout.ControlItem>, result: Layout.ControlAllocation) -> Type:
  match packing result:
    case Space.Packed{placements, unused} Layout.ControlsReady{boxes}:
      ReadyEvidence<items, clearance, inset, target, placements, unused, boxes>
    case Space.Insufficient{required, available} Layout.ControlsUnsupported{actual_required, actual_available}:
      {actual_required == required : Nat} & ({actual_available == available : Nat} &
        ({required == Space.container_required(~Layout.ControlItem, Space.Container{inset, inset, 0n, Layout.control_slots(items, clearance)}) : Nat} &
          ({available == Layout.box_width(target) : Nat} &
            {Nat.is_le(Space.container_required(~Layout.ControlItem, Space.Container{inset, inset, 0n, Layout.control_slots(items, clearance)}), Layout.box_width(target)) == False{} : Bool})))
    case _ _: {False{} == True{} : Bool}

def packed_ready(+items: +List<Layout.ControlItem>, +clearance: Nat, +inset: Nat,
  +target: Design.Box, +band: Nat, +placements: +List<Space.Placement<Layout.ControlItem>>, +unused: Nat,
  heights: HeightFloors(items, band),
  band_fits: {Nat.is_le(band, Layout.box_height(target)) == True{} : Bool},
  claim: Container.ContainerClaim(~Layout.ControlItem, Space.Container{inset, inset, 0n, Layout.control_slots(items, clearance)},
    Layout.box_width(target), Space.Packed{placements, unused})) ->
  ReadyEvidence<items, clearance, inset, target, placements, unused, Layout.control_placements(placements, target, band)>:
  (evidence, +balance) = claim
  Allocation.AllocationEvidence{+payload, +bounds, +positions, total} = evidence
  ReadyEvidence{payload_items(items, clearance, placements, payload),
    Allocation.AllocationEvidence{payload, bounds, positions, total}, balance,
    rendered_boxes(placements, target, band,
      own_limits(items, clearance, placements, payload_items(items, clearance, placements, payload), bounds),
      Std.transport(+List<Layout.ControlItem>, items, (values => HeightFloors(values, band)), heights,
        Allocation.placement_values(~Layout.ControlItem, placements), payload_items(items, clearance, placements, payload)),
      container_intervals(placements, inset, unused, Layout.box_width(target), positions, balance), band_fits),
    Equal.trans(+List<String>, placement_keys(Layout.control_placements(placements, target, band)),
      item_keys(Allocation.placement_values(~Layout.ControlItem, placements)), item_keys(items),
      rendered_order(placements, target, band),
      Equal.cong(+List<Layout.ControlItem>, +List<String>, (values => item_keys(values)),
        Allocation.placement_values(~Layout.ControlItem, placements), items, payload_items(items, clearance, placements, payload)))}

def finish_refinement(+items: +List<Layout.ControlItem>, +clearance: Nat, +inset: Nat,
  +target: Design.Box, +band: Nat, +packing: Space.Packing<Layout.ControlItem>,
  heights: HeightFloors(items, band), band_fits: {Nat.is_le(band, Layout.box_height(target)) == True{} : Bool},
  claim: Container.ContainerClaim(~Layout.ControlItem, Space.Container{inset, inset, 0n, Layout.control_slots(items, clearance)}, Layout.box_width(target), packing)) ->
  PackedControlsClaim(items, clearance, inset, target, packing, Layout.finish_controls(packing, target, band)):
  match packing:
    case Space.Packed{placements, unused}: packed_ready(items, clearance, inset, target, band, placements, unused, heights, band_fits, claim)
    case Space.Insufficient{required, available}: ({==}, ({==}, claim))

# This relation retains the complete failure reason and the container's actual
# payload/order/budget evidence alongside the physical rectangles it produces.
def ControlClaimChoice(fits: Bool, +parameters: Design.LayoutParameters, +target: Design.Box,
  +leading: +List<Layout.ControlItem>, +trailing: +List<Layout.ControlItem>, result: Layout.ControlAllocation) -> Type:
  match fits:
    case False{}:
      match result:
        case Layout.ControlsReady{boxes}: {False{} == True{} : Bool}
        case Layout.ControlsUnsupported{required, available}:
          {required == Nat.max(Layout.cross_minimum(leading), Layout.cross_minimum(trailing)) : Nat} &
            ({available == Layout.box_height(target) : Nat} &
              {Nat.is_le(Nat.max(Layout.cross_minimum(leading), Layout.cross_minimum(trailing)), Layout.box_height(target)) == False{} : Bool})
    case True{}:
      {Nat.is_le(Nat.max(Layout.cross_minimum(leading), Layout.cross_minimum(trailing)), Layout.box_height(target)) == True{} : Bool} &
        PackedControlsClaim(Layout.append_trailing(leading, trailing),
          Layout.spacer_clearance(leading, Layout.control_inset(Layout.append_trailing(leading, trailing))),
          Layout.control_inset(Layout.append_trailing(leading, trailing)), target,
          Space.pack_container(~Layout.ControlItem, Layout.control_container(leading, trailing), Layout.box_width(target)), result)

def ControlClaim(+parameters: Design.LayoutParameters, +target: Design.Box,
  +leading: +List<Layout.ControlItem>, +trailing: +List<Layout.ControlItem>, result: Layout.ControlAllocation) -> Type:
  ControlClaimChoice(Nat.is_le(Nat.max(Layout.cross_minimum(leading), Layout.cross_minimum(trailing)), Layout.box_height(target)),
    parameters, target, leading, trailing, result)

def complete_rejected(+parameters: Design.LayoutParameters, +target: Design.Box,
  +leading: +List<Layout.ControlItem>, +trailing: +List<Layout.ControlItem>,
  correspondence: {Nat.is_le(Nat.max(Layout.cross_minimum(leading), Layout.cross_minimum(trailing)), Layout.box_height(target)) == False{} : Bool}) ->
  ControlClaimChoice(False{}, parameters, target, leading, trailing,
    Layout.allocate_control_band(False{}, parameters, target, leading, trailing, Nat.max(Layout.cross_minimum(leading), Layout.cross_minimum(trailing)))):
  Design.Box{left, top, width, height} = target
  ({==}, ({==}, correspondence))

def complete_accepted(+parameters: Design.LayoutParameters, +target: Design.Box,
  +leading: +List<Layout.ControlItem>, +trailing: +List<Layout.ControlItem>,
  +correspondence: {Nat.is_le(Nat.max(Layout.cross_minimum(leading), Layout.cross_minimum(trailing)), Layout.box_height(target)) == True{} : Bool}) ->
  ControlClaimChoice(True{}, parameters, target, leading, trailing,
    Layout.allocate_control_band(True{}, parameters, target, leading, trailing, Nat.max(Layout.cross_minimum(leading), Layout.cross_minimum(trailing)))):
  Design.Box{left, top, width, height} = target
  (correspondence,
    finish_refinement(Layout.append_trailing(leading, trailing),
      Layout.spacer_clearance(leading, Layout.control_inset(Layout.append_trailing(leading, trailing))),
      Layout.control_inset(Layout.append_trailing(leading, trailing)), target,
      Nat.min(Layout.box_height(target), Nat.max(Design.toolbar_height(parameters), Nat.max(Layout.cross_minimum(leading), Layout.cross_minimum(trailing)))),
      Space.pack_container(~Layout.ControlItem, Layout.control_container(leading, trailing), Layout.box_width(target)),
      combined_floors(leading, trailing,
        Nat.min(Layout.box_height(target), Nat.max(Design.toolbar_height(parameters), Nat.max(Layout.cross_minimum(leading), Layout.cross_minimum(trailing)))),
        band_floor(Nat.max(Layout.cross_minimum(leading), Layout.cross_minimum(trailing)), Layout.box_height(target),
          Nat.max(Design.toolbar_height(parameters), Nat.max(Layout.cross_minimum(leading), Layout.cross_minimum(trailing))), correspondence,
          max_right(Design.toolbar_height(parameters), Nat.max(Layout.cross_minimum(leading), Layout.cross_minimum(trailing))))),
      Allocation.min_le_first(Layout.box_height(target), Nat.max(Design.toolbar_height(parameters), Nat.max(Layout.cross_minimum(leading), Layout.cross_minimum(trailing)))),
      container_allocation(leading, trailing, Layout.box_width(target))))

def complete_band(fits: Bool, +parameters: Design.LayoutParameters, +target: Design.Box,
  +leading: +List<Layout.ControlItem>, +trailing: +List<Layout.ControlItem>,
  +correspondence: {Nat.is_le(Nat.max(Layout.cross_minimum(leading), Layout.cross_minimum(trailing)), Layout.box_height(target)) == fits : Bool}) ->
  ControlClaimChoice(fits, parameters, target, leading, trailing,
    Layout.allocate_control_band(fits, parameters, target, leading, trailing, Nat.max(Layout.cross_minimum(leading), Layout.cross_minimum(trailing)))):
  match fits:
    case False{}:
      complete_rejected(parameters, target, leading, trailing, correspondence)
    case True{}: complete_accepted(parameters, target, leading, trailing, correspondence)


def complete(+parameters: Design.LayoutParameters, +target: Design.Box,
  +leading: +List<Layout.ControlItem>, +trailing: +List<Layout.ControlItem>) ->
  ControlClaim(parameters, target, leading, trailing, Layout.allocate_controls(parameters, target, leading, trailing)):
  Design.Box{left, top, width, height} = target
  complete_band(Nat.is_le(Nat.max(Layout.cross_minimum(leading), Layout.cross_minimum(trailing)), height),
    parameters, target, leading, trailing, {==})

type Requirements is Type:
  Requirements{
    complete: @+parameters:Design.LayoutParameters -> @+target:Design.Box ->
      @+leading:+List<Layout.ControlItem> -> @+trailing:+List<Layout.ControlItem> ->
      ControlClaim(parameters, target, leading, trailing, Layout.allocate_controls(parameters, target, leading, trailing))}

def evidence() -> Requirements:
  Requirements{complete}
