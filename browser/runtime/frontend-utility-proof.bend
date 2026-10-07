import Base
import ./frontend-utility-rules.bend as Rule
import ./frontend-utility.bend as Utility
import ../appearance/TYPOGRAPHY.bend as T

def supported(+purpose: Utility.Purpose, +font: T.Presentation, +glyph_only: Bool) ->
  {Utility.supported(Utility.source(purpose, font, glyph_only)) == True{} : Bool}:
  match purpose:
    case Utility.Preparing{}:
      match glyph_only:
        case False{}: {==}
        case True{}: {==}
    case Utility.Recovery{message}:
      match glyph_only:
        case False{}: {==}
        case True{}: {==}

def owned(+purpose: Utility.Purpose, +font: T.Presentation, +glyph_only: Bool) ->
  {Utility.owned(Utility.source(purpose, font, glyph_only)) == True{} : Bool}:
  match purpose:
    case Utility.Preparing{}:
      match glyph_only:
        case False{}: {==}
        case True{}: {==}
    case Utility.Recovery{message}:
      match glyph_only:
        case False{}: {==}
        case True{}: {==}

def Rule.evidence():
  Rule.Requirements{supported, +font => +reason => {==}, owned}
