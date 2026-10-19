import Base
import ./categories.bend as Categories

def impossible(P: Type, evidence: {False{} == True{} : Bool}) -> P:
  Categories.impossible(P, evidence)
