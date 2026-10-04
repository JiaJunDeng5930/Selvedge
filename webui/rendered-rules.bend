import Base
import ../core/interface.bend as UI
import ./rendered.bend as Model

law stale_frame_retains_state:
  for +current: Nat
  for +received: Nat
  for +surface: UI.Surface
  for +frame: Model.Frame
  for +previous: Model.State
  for different: {Nat.is_eq(current, received) == False{} : Bool}
  {Model.observe(current, received, surface, frame, previous) == previous : Model.State}
