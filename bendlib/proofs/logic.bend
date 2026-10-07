import Base
import ../stdlib.bend as Std

def false_goal(P: Type, value: Bool) -> Type:
  match value:
    case False{}: Unit
    case True{}: P

def impossible(P: Type, evidence: {False{} == True{} : Bool}) -> P:
  Std.transport(Bool, False{}, (value => false_goal(P, value)), Unit{}, True{},
    Equal.sym(Bool, False{}, True{}, evidence))
