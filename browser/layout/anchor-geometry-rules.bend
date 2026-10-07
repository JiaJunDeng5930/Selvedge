import Base
import ./anchor-geometry.bend as Geometry
import ./GEOMETRY.bend as Spatial

law forward_clip:
  for +distance: Nat
  for extent: Nat
  for +limit: Nat
  {Geometry.clip_axis(Geometry.Forward{distance}, extent, limit) ==
    Geometry.Axis{Nat.min(distance, limit), Nat.min(extent, Nat.sub(limit, Nat.min(distance, limit)))} : Geometry.Axis}

law backward_clip:
  for distance: Nat
  for extent: Nat
  for limit: Nat
  {Geometry.clip_axis(Geometry.Backward{distance}, extent, limit) ==
    Geometry.Axis{0n, Nat.min(Nat.sub(extent, distance), limit)} : Geometry.Axis}

law forward_forward:
  for +left: Nat
  for +top: Nat
  for width: Nat
  for height: Nat
  for +viewport_width: Nat
  for +viewport_height: Nat
  {Geometry.visible(Geometry.Forward{left}, Geometry.Forward{top}, width, height, viewport_width, viewport_height) ==
    Spatial.Box{Nat.min(left, viewport_width), Nat.min(top, viewport_height), Nat.min(width, Nat.sub(viewport_width, Nat.min(left, viewport_width))), Nat.min(height, Nat.sub(viewport_height, Nat.min(top, viewport_height)))} : Spatial.Box}

law forward_backward:
  for +left: Nat
  for +top: Nat
  for width: Nat
  for height: Nat
  for +viewport_width: Nat
  for +viewport_height: Nat
  {Geometry.visible(Geometry.Forward{left}, Geometry.Backward{top}, width, height, viewport_width, viewport_height) ==
    Spatial.Box{Nat.min(left, viewport_width), 0n, Nat.min(width, Nat.sub(viewport_width, Nat.min(left, viewport_width))), Nat.min(Nat.sub(height, top), viewport_height)} : Spatial.Box}

law backward_forward:
  for +left: Nat
  for +top: Nat
  for width: Nat
  for height: Nat
  for +viewport_width: Nat
  for +viewport_height: Nat
  {Geometry.visible(Geometry.Backward{left}, Geometry.Forward{top}, width, height, viewport_width, viewport_height) ==
    Spatial.Box{0n, Nat.min(top, viewport_height), Nat.min(Nat.sub(width, left), viewport_width), Nat.min(height, Nat.sub(viewport_height, Nat.min(top, viewport_height)))} : Spatial.Box}

law backward_backward:
  for +left: Nat
  for +top: Nat
  for width: Nat
  for height: Nat
  for +viewport_width: Nat
  for +viewport_height: Nat
  {Geometry.visible(Geometry.Backward{left}, Geometry.Backward{top}, width, height, viewport_width, viewport_height) ==
    Spatial.Box{0n, 0n, Nat.min(Nat.sub(width, left), viewport_width), Nat.min(Nat.sub(height, top), viewport_height)} : Spatial.Box}

law negative_top_regression:
  {Geometry.visible(Geometry.Forward{100n}, Geometry.Backward{8n}, 40n, 40n, 1000n, 800n) ==
    Spatial.Box{100n, 0n, 40n, 32n} : Spatial.Box}
