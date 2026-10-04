import Base
import ./layout.bend as Layout
import ./design.bend as Design
import ./controls.bend as Controls
import ./enclosure.bend as Enclosure
import ./space.bend as Space
import ./space-laws.bend as Allocation
import ./container-space-laws.bend as Container
import ./spatial-rules.bend as SpatialRules

def placement_key(placement: Design.NodePlacement) -> String:
  Design.NodePlacement{key, bounds} = placement
  key

def box_left(box: Design.Box) -> Nat:
  Design.Box{left, top, width, height} = box
  left

def box_top(box: Design.Box) -> Nat:
  Design.Box{left, top, width, height} = box
  top

def placement_bounds(placement: Design.NodePlacement) -> Design.Box:
  Design.NodePlacement{key, bounds} = placement
  bounds

type BoxEvidence<-minimum_width: Nat, -minimum_height: Nat, -target: Design.Box, -actual: Design.Box> is Type:
  BoxEvidence{
    minimum_width: {Nat.is_le(minimum_width, Layout.box_width(actual)) == True{} : Bool},
    minimum_height: {Nat.is_le(minimum_height, Layout.box_height(actual)) == True{} : Bool},
    left: {Nat.is_le(box_left(target), box_left(actual)) == True{} : Bool},
    right: {Nat.is_le(Nat.add(box_left(actual), Layout.box_width(actual)), Nat.add(box_left(target), Layout.box_width(target))) == True{} : Bool},
    top: {Nat.is_le(box_top(target), box_top(actual)) == True{} : Bool},
    bottom: {Nat.is_le(Nat.add(box_top(actual), Layout.box_height(actual)), Nat.add(box_top(target), Layout.box_height(target))) == True{} : Bool}}

def item_keys(items: +List<Layout.BandItem>) -> +List<String>:
  match items:
    case Nil{}: Nil{}
    case Con{Layout.FixedControl{key, geometry}, rest}: key <> item_keys(rest)
    case Con{Layout.FlexibleRegion{key, minimum_height}, rest}: key <> item_keys(rest)
    case Con{Layout.Spacer{minimum_width}, rest}: item_keys(rest)

def placement_keys(placements: +List<Design.NodePlacement>) -> +List<String>:
  match placements:
    case Nil{}: Nil{}
    case Con{Design.NodePlacement{key, bounds}, rest}: key <> placement_keys(rest)

def HeightFloors(items: +List<Layout.BandItem>, +height: Nat) -> Type:
  match items:
    case Nil{}: Unit
    case Con{item, rest}: {Nat.is_le(Layout.item_cross_minimum(item), height) == True{} : Bool} & HeightFloors(rest, height)

def SlotBounds(placements: +List<Space.Placement<Layout.BandItem>>) -> Type:
  match placements:
    case Nil{}: Unit
    case Con{Space.Placement{item, offset, width}, rest}:
      {Nat.is_le(Space.minimum(Layout.item_dimension(item)), width) == True{} : Bool} & SlotBounds(rest)

def IntervalEnds(placements: +List<Space.Placement<Layout.BandItem>>, +end: Nat) -> Type:
  match placements:
    case Nil{}: Unit
    case Con{Space.Placement{item, offset, width}, rest}:
      {Nat.is_le(Nat.add(offset, width), end) == True{} : Bool} & IntervalEnds(rest, end)

def RenderedEvidence(placements: +List<Space.Placement<Layout.BandItem>>, boxes: +List<Design.NodePlacement>, +target: Design.Box) -> Type:
  match placements:
    case Nil{}:
      match boxes:
        case Nil{}: Unit
        case Con{head, rest}: {False{} == True{} : Bool}
    case Con{Space.Placement{Layout.Spacer{minimum_width}, offset, width}, rest}: RenderedEvidence(rest, boxes, target)
    case Con{Space.Placement{Layout.FixedControl{source_key, geometry}, offset, width}, rest}:
      match boxes:
        case Nil{}: {False{} == True{} : Bool}
        case Con{Design.NodePlacement{key, actual}, tail}:
          {key == source_key : String} & (BoxEvidence<Controls.geometry_minimum_width(geometry), Controls.geometry_minimum_height(geometry), target, actual> & RenderedEvidence(rest, tail, target))
    case Con{Space.Placement{Layout.FlexibleRegion{source_key, minimum_height}, offset, width}, rest}:
      match boxes:
        case Nil{}: {False{} == True{} : Bool}
        case Con{Design.NodePlacement{key, actual}, tail}:
          {key == source_key : String} & (BoxEvidence<0n, minimum_height, target, actual> & RenderedEvidence(rest, tail, target))

type VerticalEvidence<-cross: Nat, -block: Nat, -chosen: Nat, -available: Nat> is Type:
  VerticalEvidence{
    minimum: {Nat.is_le(cross, Nat.sub(chosen, Nat.mul(2n, block))) == True{} : Bool},
    budget: {Nat.add(Nat.mul(2n, block), Nat.sub(chosen, Nat.mul(2n, block))) == chosen : Nat},
    extent: {Nat.is_le(chosen, available) == True{} : Bool},
    inner_extent: {Nat.is_le(Nat.sub(chosen, Nat.mul(2n, block)), Nat.sub(available, Nat.mul(2n, block))) == True{} : Bool},
    insets: {Nat.is_le(Nat.mul(2n, block), available) == True{} : Bool}}

def chosen_band_height(+parameters: Design.LayoutParameters, +target: Design.Box, +frame: Enclosure.Frame, +items: +List<Layout.BandItem>) -> Nat:
  Nat.min(Layout.box_height(target), Nat.max(Design.toolbar_height(parameters), Layout.band_cross_required(Layout.Band{frame, items})))

# These equations connect the physical boxes to assigned extents and the one
# production centering calculation; minimum and containment remain separate.
def Coordinates(placements: +List<Space.Placement<Layout.BandItem>>, boxes: +List<Design.NodePlacement>, +origin: Design.Box, +height: Nat) -> Type:
  match placements boxes:
    case Nil{} Nil{}: Unit
    case Con{Space.Placement{Layout.Spacer{minimum}, offset, width}, rest} _: Coordinates(rest, boxes, origin, height)
    case Con{Space.Placement{Layout.FixedControl{key, geometry}, offset, width}, rest} Con{Design.NodePlacement{actual_key, actual}, tail}:
      {Layout.box_width(actual) == width : Nat} &
        ({Layout.box_height(actual) == Layout.control_height(geometry, height) : Nat} &
          ({box_left(actual) == Nat.add(box_left(origin), offset) : Nat} &
            ({box_top(actual) == Nat.add(box_top(origin), Nat.div(Nat.sub(height, Layout.control_height(geometry, height)), 2n)) : Nat} & Coordinates(rest, tail, origin, height))))
    case Con{Space.Placement{Layout.FlexibleRegion{key, minimum}, offset, width}, rest} Con{Design.NodePlacement{actual_key, actual}, tail}:
      {Layout.box_width(actual) == width : Nat} & ({Layout.box_height(actual) == height : Nat} &
        ({box_left(actual) == Nat.add(box_left(origin), offset) : Nat} & ({box_top(actual) == box_top(origin) : Nat} & Coordinates(rest, tail, origin, height))))
    case _ _: {False{} == True{} : Bool}

type ReadyEvidence<-frame: Enclosure.Frame, -items: +List<Layout.BandItem>, -target: Design.Box, -chosen: Nat,
  -placements: +List<Space.Placement<Layout.BandItem>>, -unused: Nat, -boxes: +List<Design.NodePlacement>> is Type:
  ReadyEvidence{
    source: {Allocation.placement_values(~Layout.BandItem, placements) == items : +List<Layout.BandItem>},
    allocation: Allocation.AllocationEvidence<Layout.BandItem, Layout.band_slots(items), Enclosure.frame_gap(frame), Layout.frame_inline(frame),
      Container.inner_budget(Layout.frame_inline(frame), Layout.frame_inline(frame), Layout.box_width(target)), Space.Allocation{placements, unused}>,
    budget: {Nat.add(Layout.frame_inline(frame), Nat.add(Nat.add(Allocation.used(~Layout.BandItem, placements, Enclosure.frame_gap(frame)), unused), Layout.frame_inline(frame))) == Layout.box_width(target) : Nat},
    vertical: VerticalEvidence<Layout.cross_minimum(items), Layout.frame_block(frame), chosen, Layout.box_height(target)>,
    rectangles: RenderedEvidence(placements, boxes, target),
    contained: {SpatialRules.all_contained(target, boxes) == True{} : Bool},
    coordinates: Coordinates(placements, boxes, Layout.inner_band_target(target, Layout.frame_block(frame)), Nat.sub(chosen, Nat.mul(2n, Layout.frame_block(frame)))),
    order: {placement_keys(boxes) == item_keys(items) : +List<String>}}

def PackedClaim(+frame: Enclosure.Frame, +items: +List<Layout.BandItem>, +target: Design.Box, +chosen: Nat,
  packing: Space.Packing<Layout.BandItem>, result: Layout.ControlAllocation) -> Type:
  match packing result:
    case Space.Packed{placements, unused} Layout.ControlsReady{boxes}:
      ReadyEvidence<frame, items, target, chosen, placements, unused, boxes>
    case Space.Insufficient{required, available} Layout.ControlsUnsupported{actual_required, actual_available}:
      {actual_required == required : Nat} & ({actual_available == available : Nat} &
        ({required == Space.container_required(~Layout.BandItem, Layout.band_container(Layout.Band{frame, items})) : Nat} &
          ({available == Layout.box_width(target) : Nat} &
            {Nat.is_le(Space.container_required(~Layout.BandItem, Layout.band_container(Layout.Band{frame, items})), Layout.box_width(target)) == False{} : Bool})))
    case _ _: {False{} == True{} : Bool}

def PackedBandClaim(+parameters: Design.LayoutParameters, +target: Design.Box, band: Layout.Band,
  packing: Space.Packing<Layout.BandItem>, result: Layout.ControlAllocation) -> Type:
  Layout.Band{+frame, +items} = band
  PackedClaim(frame, items, target, chosen_band_height(parameters, target, frame, items), packing, result)


# Guard rejection and accepted packing retain different, exact shortage axes.
def BandClaimChoice(fits: Bool, +parameters: Design.LayoutParameters, +target: Design.Box,
  +band: Layout.Band, result: Layout.ControlAllocation) -> Type:
  match fits:
    case False{}:
      match result:
        case Layout.ControlsReady{boxes}: {False{} == True{} : Bool}
        case Layout.ControlsUnsupported{required, available}:
          {required == Layout.band_cross_required(band) : Nat} &
            ({available == Layout.box_height(target) : Nat} &
              {Nat.is_le(Layout.band_cross_required(band), Layout.box_height(target)) == False{} : Bool})
    case True{}:
      {Nat.is_le(Layout.band_cross_required(band), Layout.box_height(target)) == True{} : Bool} &
        PackedBandClaim(parameters, target, band,
          Space.pack_container(~Layout.BandItem, Layout.band_container(band), Layout.box_width(target)), result)

def BandClaim(+parameters: Design.LayoutParameters, +target: Design.Box,
  +band: Layout.Band, result: Layout.ControlAllocation) -> Type:
  BandClaimChoice(Nat.is_le(Layout.band_cross_required(band), Layout.box_height(target)), parameters, target, band, result)

def ControlClaim(+parameters: Design.LayoutParameters, +target: Design.Box,
  +leading: +List<Layout.BandItem>, +trailing: +List<Layout.BandItem>, result: Layout.ControlAllocation) -> Type:
  BandClaim(parameters, target, Layout.root_band(leading, trailing), result)

type Requirements is Type:
  Requirements{
    band_complete: @+parameters:Design.LayoutParameters -> @+target:Design.Box -> @+band:Layout.Band ->
      BandClaim(parameters, target, band, Layout.allocate_band(parameters, target, band)),
    complete: @+parameters:Design.LayoutParameters -> @+target:Design.Box -> @+leading:+List<Layout.BandItem> -> @+trailing:+List<Layout.BandItem> ->
      ControlClaim(parameters, target, leading, trailing, Layout.allocate_controls(parameters, target, leading, trailing))}

law evidence:
  Requirements
