import Base
import ../typography.bend as T
import ../document.bend as Doc
import ../renderer.bend as Render
import ../board-spatial-laws.bend as Rule

def title_inset(typography: T.Presentation) ->
  {(Render.attr(Rule.title_production_styles(typography), "padding-inline"),
          (Render.attr(Rule.title_production_styles(typography), "padding-block"),
           (Render.attr(Rule.title_production_styles(typography), "font-weight"),
            (Render.attr(Doc.element_styles(Render.face_label("title", "title")), "white-space"), Render.attr(Rule.title_production_styles(typography), "min-height"))))) ==
          ("8px", ("4px", (Nat.show(T.weight(T.Strong{})), ("normal", "32px")))) : (String & (String & (String & (String & String))))}:
  T.Presentation{tier, emphasis, scale} = typography
  {==}


def Rule.evidence():
  Rule.Requirements{+typography => +key => +filter => +name => {==},
    +typography => +title => +key => +visual => +input => +availability => +name => +behavior => +geometry => +placement => +help => +feedback => {==},
    +typography => title_inset(typography),
    +typography => +owner => +title => +node => +rest => {==},
    +typography => {==},
    +typography => +owner => +label => +stage => +count => +create => {==}, +owner => +create => {==}, +owner => +create => {==},
    +typography => +owner => +label => +stage => +count => +create => {==}, {==},
    +typography => +owner => +description => {==}, +key => +filter => +name => +visual =>
        {==}

      # The title container retains the complete canonical action unchanged.
    }
