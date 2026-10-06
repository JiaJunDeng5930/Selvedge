import Base
import ../rendered-rules.bend as Rule
import ../rendered.bend as Model

def Rule.stale_frame_retains_state(current, received, surface, frame, previous, different):
  Equal.cong(Bool, Model.State, (owned => Model.receive(owned, current, surface, frame, previous)), Nat.is_eq(current, received), False{}, different)

def Rule.native_ownership_is_complete(identity, owner, rest, active, elements): {==}
def Rule.native_order_is_owned(owner, identity, parent, rest): {==}
def Rule.native_tab_contract(active, elements, native_focus, order): {==}

def Rule.absent_control_is_not_tab_stop(): {==}
def Rule.observed_tab_participation(key,visible,enabled,tab,keyboard,scroll,bounds,hit): {==}
