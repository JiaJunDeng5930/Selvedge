import Base
import ./enclosure.bend as E

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
