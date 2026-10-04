import Base
import ../core/interface.bend as UI
import ./design.bend as Design

# The frame contract follows the prescribed layout; interaction retains every
# product node, including navigation that the shell currently hides.
def without_navigation(nodes: +List<UI.Node>) -> +List<UI.Node>:
  match nodes:
    case Nil{}: Nil{}
    case Con{UI.Node{key, semantic, label, role, meaning, children}, rest}:
      match role:
        case UI.Navigation{}: without_navigation(rest)
        case other:
          UI.Node{key, semantic, label, other, meaning, without_navigation(children)} <> without_navigation(rest)

def project_navigation(navigation: Design.Navigation, surface: UI.Surface) -> UI.Surface:
  match navigation:
    case Design.HiddenNavigation{}:
      UI.Surface{content, base, overlays, scope} = surface
      UI.Surface{content, without_navigation(base), without_navigation(overlays), scope}
    case _: surface

def project(surface: UI.Surface, layout: Design.Layout) -> UI.Surface:
  Design.Layout{viewport, Design.Shell{navigation, main, details}, frame, overlays, parameters, controls} = layout
  project_navigation(navigation, surface)
