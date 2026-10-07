import Base
import ./GEOMETRY.bend as Spatial

type Origin is Data:
  Forward{distance: Nat}
  Backward{distance: Nat}

type Axis is Data:
  Axis{start: Nat, extent: Nat}

# Clip before adding coordinates: observed origins may be negative and extents
# may reach Nat's limit, so an origin-plus-extent sum is not an admissible input.
def clip_axis(origin: Origin, +extent: Nat, +limit: Nat) -> Axis:
  match origin:
    case Forward{distance}:
      +start = Nat.min(distance, limit)
      Axis{start, Nat.min(extent, Nat.sub(limit, start))}
    case Backward{distance}:
      Axis{0n, Nat.min(Nat.sub(extent, distance), limit)}

def from_axes(horizontal: Axis, vertical: Axis) -> Spatial.Box:
  match horizontal:
    case Axis{left, width}:
      match vertical:
        case Axis{top, height}: Spatial.Box{left, top, width, height}

def visible(left: Origin, top: Origin, width: Nat, height: Nat, viewport_width: Nat, viewport_height: Nat) -> Spatial.Box:
  from_axes(clip_axis(left, width, viewport_width), clip_axis(top, height, viewport_height))
