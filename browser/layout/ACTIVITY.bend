import Base
import ./enclosure.bend as E
import ../appearance/TYPOGRAPHY.bend as T
import ./natural-size.bend as NaturalSize
import ./physical-space.bend as Space

# Independent positive quantities calibrate motor targets, writing lines and clearance.
type Grammar is Data:
  Grammar{supporting_extra: Nat, writing_lines_extra: Nat, clearance_extra: Nat}

def initial() -> Grammar:
  Grammar{31n, 1n, 11n}

def supporting_minimum(grammar: Grammar) -> Nat:
  Grammar{supporting_extra, writing_lines_extra, clearance_extra} = grammar
  Nat.add(supporting_extra, 1n)

def writing_lines(grammar: Grammar) -> Nat:
  Grammar{supporting_extra, writing_lines_extra, clearance_extra} = grammar
  Nat.add(writing_lines_extra, 1n)

def clearance(grammar: Grammar) -> Nat:
  Grammar{supporting_extra, writing_lines_extra, clearance_extra} = grammar
  Nat.add(clearance_extra, 1n)

def frame(+grammar: Grammar) -> E.Frame:
  E.Frame{E.ambient(clearance(grammar), clearance(grammar)), E.EmbeddedContent{clearance(grammar)}}

# The same presentation calibrates visible content; motor requirements remain a floor.
def length(+capacity: Nat, +text: T.Presentation, nominal: Nat) -> Nat:
  T.scaled(capacity, nominal, T.presentation_scale(text))

def icon(+capacity: Nat, text: T.Presentation) -> Nat:
  length(capacity, text, 16n)

def slot(+capacity: Nat, text: T.Presentation) -> Nat:
  length(capacity, text, 20n)

def target(+capacity: Nat, +text: T.Presentation, minimum: Nat) -> Nat:
  Nat.max(minimum, Nat.max(supporting_minimum(initial()), length(capacity, text, 32n)))

def row_frame(+capacity: Nat, +text: T.Presentation) -> E.Frame:
  E.Frame{E.ambient(length(capacity, text, 8n), 0n), E.EmbeddedContent{length(capacity, text, 8n)}}

def primary(text: T.Presentation) -> T.Presentation:
  T.activity(T.with_tier(text, T.Body{}))

# Reading clearance belongs to captions, not to a child motor target.
def caption_frame(+capacity: Nat, +text: T.Presentation) -> E.Frame:
  E.Frame{E.ambient(length(capacity, text, 8n), length(capacity, text, 6n)), E.EmbeddedContent{length(capacity, text, 8n)}}

def reference_width(advance: Nat, units: Nat) -> Nat:
  Nat.mul(advance, units)

def support_width(advance: Nat, units: Nat) -> Nat:
  Nat.mul(advance, units)

# LimitedSize keeps preferred width dependent on actual child measurement.
def content_width(+minimum: Nat, maximum: Nat) -> Space.AxisSize:
  Space.LimitedSize{minimum, 0n, Nat.sub(Nat.max(minimum, maximum), minimum)}

def surface_width(+capacity: Nat, +text: T.Presentation, advance: Nat) -> Space.AxisSize:
  content_width(length(capacity, text, 200n), Nat.add(reference_width(advance, 56n), length(capacity, text, 16n)))

def description_width(advance: Nat) -> Space.AxisSize:
  content_width(0n, support_width(advance, 38n))

def field_width(advance: Nat) -> Space.AxisSize:
  +required = reference_width(advance, 32n)
  Space.LimitedSize{required, 0n, required}

def member_width(advance: Nat) -> Space.AxisSize:
  content_width(0n, reference_width(advance, 44n))
