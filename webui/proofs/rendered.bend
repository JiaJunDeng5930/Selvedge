import Base
import ../rendered-rules.bend as Rule
import ../rendered.bend as Model

def Rule.stale_frame_retains_state(current, received, surface, frame, previous, different):
  Equal.cong(Bool, Model.State, (owned => Model.receive(owned, current, surface, frame, previous)), Nat.is_eq(current, received), False{}, different)
