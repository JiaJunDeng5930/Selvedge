import Base
import ../core/interface.bend as UI
import ./design.bend as Design
import ../core/SYSTEM.bend as Core

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
  Design.Layout{viewport, Design.Shell{navigation, main, details}, frame, overlays} = layout
  project_navigation(navigation, surface)

def hidden(content: Core.Scene, base: +List<UI.Node>, overlays: +List<UI.Node>, scope: Maybe<&2, String>, viewport: Design.Viewport, main: Design.Box, details: Maybe<&2, Design.Box>, frame: Design.MainFrame, placements: +List<Design.Overlay>) ->
  {project(UI.Surface{content, base, overlays, scope}, Design.Layout{viewport, Design.Shell{Design.HiddenNavigation{}, main, details}, frame, placements}) == UI.Surface{content, without_navigation(base), without_navigation(overlays), scope} : UI.Surface}:
  {==}





type Requirements is Type:
  Requirements{
    hidden: @content:Core.Scene -> @base:+List<UI.Node> -> @overlays:+List<UI.Node> -> @scope:Maybe<&2, String> -> @viewport:Design.Viewport -> @main:Design.Box -> @details:Maybe<&2, Design.Box> -> @frame:Design.MainFrame -> @placements:+List<Design.Overlay> ->
      {project(UI.Surface{content, base, overlays, scope}, Design.Layout{viewport, Design.Shell{Design.HiddenNavigation{}, main, details}, frame, placements}) == UI.Surface{content, without_navigation(base), without_navigation(overlays), scope} : UI.Surface},
    beside: @surface:UI.Surface -> @viewport:Design.Viewport -> @bounds:Design.Box -> @main:Design.Box -> @details:Maybe<&2, Design.Box> -> @frame:Design.MainFrame -> @placements:+List<Design.Overlay> ->
      {project(surface, Design.Layout{viewport, Design.Shell{Design.BesideNavigation{bounds}, main, details}, frame, placements}) == surface : UI.Surface},
    overlay: @surface:UI.Surface -> @viewport:Design.Viewport -> @bounds:Design.Box -> @main:Design.Box -> @details:Maybe<&2, Design.Box> -> @frame:Design.MainFrame -> @placements:+List<Design.Overlay> ->
      {project(surface, Design.Layout{viewport, Design.Shell{Design.OverlayNavigation{bounds}, main, details}, frame, placements}) == surface : UI.Surface}
  }

def evidence() -> Requirements:
  Requirements{hidden, surface => viewport => bounds => main => details => frame => placements => {==}, surface => viewport => bounds => main => details => frame => placements => {==}}
