import Base
import ../editor-binding-rules.bend as Rule

def Rule.evidence():
  Rule.Requirements{
    +key => +editor => +entry => +value => +choices => {==},
    +key => {==}}
