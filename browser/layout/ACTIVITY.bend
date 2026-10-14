import Base
import ./enclosure.bend as E
import ../appearance/TYPOGRAPHY.bend as T
import ./natural-size.bend as NaturalSize

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
  E.Frame{E.ambient(length(capacity, text, 8n), length(capacity, text, 6n)), E.EmbeddedContent{length(capacity, text, 8n)}}

def primary(text: T.Presentation) -> T.Presentation:
  T.activity(T.with_tier(text, T.Body{}))

def reading_width(capacity: Nat, text: T.Presentation, units: Nat) -> Nat:
  Nat.mul(units, T.resolved_line_height(T.resolve_presentation(capacity, primary(text))))
