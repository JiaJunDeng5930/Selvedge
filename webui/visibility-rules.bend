import Base
import ../core/SYSTEM.bend as Core
import ../core/interface.bend as UI
import ./design.bend as Design
import ./visibility.bend as Model

law hidden:
  for parameters: Design.LayoutParameters
  for content: Core.Scene
  for base: +List<UI.Node>
  for overlays: +List<UI.Node>
  for scope: Maybe<&2, String>
  for viewport: Design.Viewport
  for main: Design.Box
  for details: Maybe<&2, Design.Box>
  for frame: Design.MainFrame
  for placements: +List<Design.Overlay>
  for controls: +List<Design.NodePlacement>
  {Model.project(UI.Surface{content, base, overlays, scope}, Design.Layout{viewport, Design.Shell{Design.HiddenNavigation{}, main, details}, frame, placements, parameters, controls}) == UI.Surface{content, Model.without_navigation(base), Model.without_navigation(overlays), scope} : UI.Surface}


type Requirements is Type:
  Requirements{
    hidden: @parameters:Design.LayoutParameters -> @content:Core.Scene -> @base:+List<UI.Node> -> @overlays:+List<UI.Node> -> @scope:Maybe<&2, String> -> @viewport:Design.Viewport -> @main:Design.Box -> @details:Maybe<&2, Design.Box> -> @frame:Design.MainFrame -> @placements:+List<Design.Overlay> -> @controls:+List<Design.NodePlacement> ->
      {Model.project(UI.Surface{content, base, overlays, scope}, Design.Layout{viewport, Design.Shell{Design.HiddenNavigation{}, main, details}, frame, placements, parameters, controls}) == UI.Surface{content, Model.without_navigation(base), Model.without_navigation(overlays), scope} : UI.Surface},
    beside: @parameters:Design.LayoutParameters -> @surface:UI.Surface -> @viewport:Design.Viewport -> @bounds:Design.Box -> @main:Design.Box -> @details:Maybe<&2, Design.Box> -> @frame:Design.MainFrame -> @placements:+List<Design.Overlay> -> @controls:+List<Design.NodePlacement> ->
      {Model.project(surface, Design.Layout{viewport, Design.Shell{Design.BesideNavigation{bounds}, main, details}, frame, placements, parameters, controls}) == surface : UI.Surface},
    overlay: @parameters:Design.LayoutParameters -> @surface:UI.Surface -> @viewport:Design.Viewport -> @bounds:Design.Box -> @main:Design.Box -> @details:Maybe<&2, Design.Box> -> @frame:Design.MainFrame -> @placements:+List<Design.Overlay> -> @controls:+List<Design.NodePlacement> ->
      {Model.project(surface, Design.Layout{viewport, Design.Shell{Design.OverlayNavigation{bounds}, main, details}, frame, placements, parameters, controls}) == surface : UI.Surface}
  }

law evidence:
  Requirements
