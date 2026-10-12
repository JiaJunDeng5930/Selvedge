import Base
import ./enclosure.bend as E

# Positive increments bind writing priority and clearance to one calibration.
type Grammar is Data:
  Grammar{supporting_extra: Nat, clearance_extra: Nat}

def initial() -> Grammar:
  Grammar{59n, 11n}

def supporting_minimum(grammar: Grammar) -> Nat:
  Grammar{supporting_extra, clearance_extra} = grammar
  Nat.add(supporting_extra, 1n)

def primary_minimum(+grammar: Grammar) -> Nat:
  Nat.add(supporting_minimum(grammar), supporting_minimum(grammar))

def clearance(grammar: Grammar) -> Nat:
  Grammar{supporting_extra, clearance_extra} = grammar
  Nat.add(clearance_extra, 1n)

def frame(+grammar: Grammar) -> E.Frame:
  E.Frame{E.ambient(clearance(grammar), clearance(grammar)), E.EmbeddedContent{clearance(grammar)}}
