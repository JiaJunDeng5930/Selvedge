import Base

type Anchor is Data:
  Anchor{identity: String, offset: F32}

type Selection is Data:
  Selection{start: Nat, end: Nat, direction: String}

type Rect is Data:
  Rect{left: F32, top: F32, right: F32, bottom: F32}

def submit_key(composing: Bool, enter: Bool, multiline: Bool, modified: Bool,
  shift: Bool, alt: Bool, enabled: Bool, pending: Bool) -> Bool:
  Bool.not(composing) && enter && Bool.not(shift) && Bool.not(alt) &&
    (multiline || modified) && enabled && Bool.not(pending)

# A stack expresses temporary focus ownership. Only its top owner can close;
# Escape cannot dismiss a menu and the dialog beneath it in the same event.
def contains(outer: Rect, inner: Rect) -> Bool:
  Rect{left, top, right, bottom} = outer
  Rect{+inner_left, +inner_top, +inner_right, +inner_bottom} = inner
  F32.is_le(left, inner_left) && F32.is_le(top, inner_top) &&
    F32.is_le(inner_right, right) && F32.is_le(inner_bottom, bottom) &&
    F32.is_lt(inner_left, inner_right) && F32.is_lt(inner_top, inner_bottom)
