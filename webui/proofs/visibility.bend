import Base
import ../visibility-rules.bend as Rule

def Rule.hidden(parameters, content, base, overlays, scope, viewport, main, details, frame, placements, controls):
  {==}

def Rule.evidence():
  Rule.Requirements{Rule.hidden, parameters => surface => viewport => bounds => main => details => frame => placements => controls => {==}, parameters => surface => viewport => bounds => main => details => frame => placements => controls => {==}}
