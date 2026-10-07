import Base
import ../controls/MODEL.bend as Authored
import ./SOURCE.bend as Source
import ../appearance/DESIGN.bend as Design
import ../layout/enclosure.bend as Enclosure

def frame_is_canonical(+visual: Design.Style) -> Type:
  {Source.code_surface_frame(Authored.code_surface(visual)) == Design.style_frame(visual) : Enclosure.Frame}

def chrome_is_canonical(+visual: Design.Style) -> Type:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
  {Source.code_surface_chrome(Authored.code_surface(visual)) == chrome : Design.Chrome}

def policy_uses_code_surface(visual: Design.Style, +code_visual: Design.Style, reserve: Nat) -> Type:
  {Source.rich_policy_code_surface(Authored.rich_policy(visual, code_visual, reserve)) == Authored.code_surface(code_visual) : Source.CodeSurface}

type Requirements is Type:
  Requirements{
    canonical_frame: @+visual:Design.Style -> frame_is_canonical(visual),
    canonical_chrome: @+visual:Design.Style -> chrome_is_canonical(visual),
    policy_projection: @visual:Design.Style -> @+code_visual:Design.Style -> @reserve:Nat -> policy_uses_code_surface(visual, code_visual, reserve)
  }

law evidence:
  Requirements
