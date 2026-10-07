import Base
import ./code-surface-rules.bend as Rule
import ../appearance/DESIGN.bend as Design

def canonical_frame(+visual: Design.Style) -> Rule.frame_is_canonical(visual):
  match visual:
    case Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states}: {==}

def canonical_chrome(+visual: Design.Style) -> Rule.chrome_is_canonical(visual):
  match visual:
    case Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states}: {==}

def policy_projection(visual: Design.Style, +code_visual: Design.Style, reserve: Nat) -> Rule.policy_uses_code_surface(visual, code_visual, reserve):
  {==}

def Rule.evidence():
  Rule.Requirements{canonical_frame, canonical_chrome, policy_projection}
