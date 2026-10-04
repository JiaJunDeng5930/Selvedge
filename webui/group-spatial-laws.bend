import Base
import ./design.bend as Design
import ./layout.bend as Layout
import ./spatial-rules.bend as SpatialRules

def left(box: Design.Box) -> Nat:
  Design.Box{l, t, w, h} = box
  l

def top(box: Design.Box) -> Nat:
  Design.Box{l, t, w, h} = box
  t

def right(box: Design.Box) -> Nat:
  Design.Box{l, t, w, h} = box
  Nat.add(l, w)

def bottom(box: Design.Box) -> Nat:
  Design.Box{l, t, w, h} = box
  Nat.add(t, h)

def Parts(+outer: Design.Box, +inner: Design.Box) -> Type:
  Design.Box{+l, +t, w, h} = outer
  Design.Box{+x, +y, a, b} = inner
  {Nat.is_le(l, x) == True{} : Bool} & ({Nat.is_le(t, y) == True{} : Bool} &
    ({Nat.is_le(Nat.add(x, a), Nat.add(l, w)) == True{} : Bool} &
      {Nat.is_le(Nat.add(y, b), Nat.add(t, h)) == True{} : Bool}))

def Fold(+nodes: +List<Design.NodePlacement>, found: Maybe<&2, Design.Box>) -> Type:
  match found:
    case None{}: {nodes == Nil{} : +List<Design.NodePlacement>}
    case Some{bounds}: {SpatialRules.all_contained(bounds, nodes) == True{} : Bool}

def FoundNode(+target: Design.Box, found: Maybe<&2, Design.NodePlacement>) -> Type:
  match found:
    case None{}: Unit
    case Some{Design.NodePlacement{key, bounds}}: {SpatialRules.contains(target, bounds) == True{} : Bool}

def LayoutBounds(placement: Design.NodePlacement) -> Design.Box:
  Design.NodePlacement{key, bounds} = placement
  bounds

def FoundBox(+target: Design.Box, found: Maybe<&2, Design.Box>) -> Type:
  match found:
    case None{}: Unit
    case Some{bounds}: {SpatialRules.contains(target, bounds) == True{} : Bool}


# Unsupported is never mistaken for a successful heading placement.
def successful(+target: Design.Box, result: Layout.ControlAllocation) -> Bool:
  match result:
    case Layout.ControlsReady{placements}: SpatialRules.all_contained(target, placements)
    case Layout.ControlsUnsupported{required, available}: False{}

type Requirements is Type:
  Requirements{
    members: @+items:+List<Layout.BandItem> -> @+placements:+List<Design.NodePlacement> -> @+target:Design.Box ->
      {SpatialRules.all_contained(Layout.group_bounds(Layout.action_group_bounds(items, placements), target), Layout.action_group_nodes(items, placements)) == True{} : Bool},
    enclosure: @+items:+List<Layout.BandItem> -> @+placements:+List<Design.NodePlacement> -> @+target:Design.Box ->
      @contained:{SpatialRules.all_contained(target, placements) == True{} : Bool} ->
      {SpatialRules.contains(target, Layout.group_bounds(Layout.action_group_bounds(items, placements), target)) == True{} : Bool},
    complete: @+actions:Maybe<&2, Layout.HeadingActions> -> @+target:Design.Box -> @+placements:+List<Design.NodePlacement> ->
      @+contained:{SpatialRules.all_contained(target, placements) == True{} : Bool} ->
      {SpatialRules.all_contained(target, Layout.group_heading_actions(actions, target, placements)) == True{} : Bool},
    finished: @+placements:+List<Design.NodePlacement> -> @+content:Layout.HeadingContent -> @+target:Design.Box ->
      @contained:{SpatialRules.all_contained(target, placements) == True{} : Bool} ->
      {successful(target, Layout.finish_task_heading(Layout.ControlsReady{placements}, content, target)) == True{} : Bool}}

law evidence:
  Requirements
