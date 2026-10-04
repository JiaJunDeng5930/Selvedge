import Base
import ./spatial.bend as SpatialModel
import ../core/SYSTEM.bend as Core
import ../core/interface.bend as UI
import ./design.bend as Design
import ./visibility.bend as Model

type Requirements is Type:
  Requirements{
    hidden: @parameters:Design.LayoutParameters -> @content:Core.Scene -> @base:+List<UI.Node> -> @overlays:+List<UI.Node> -> @scope:Maybe<&2, String> -> @viewport:Design.Viewport -> @main:SpatialModel.Box -> @details:Maybe<&2, SpatialModel.Box> -> @frame:Design.MainFrame -> @placements:+List<Design.Overlay> -> @controls:+List<Design.NodePlacement> ->
      {Model.project(UI.Surface{content, base, overlays, scope}, Design.Layout{viewport, Design.Shell{Design.HiddenNavigation{}, main, details}, frame, placements, parameters, controls}) == UI.Surface{content, Model.without_navigation(base), Model.without_navigation(overlays), scope} : UI.Surface},
    beside: @parameters:Design.LayoutParameters -> @surface:UI.Surface -> @viewport:Design.Viewport -> @bounds:SpatialModel.Box -> @main:SpatialModel.Box -> @details:Maybe<&2, SpatialModel.Box> -> @frame:Design.MainFrame -> @placements:+List<Design.Overlay> -> @controls:+List<Design.NodePlacement> ->
      {Model.project(surface, Design.Layout{viewport, Design.Shell{Design.BesideNavigation{bounds}, main, details}, frame, placements, parameters, controls}) == surface : UI.Surface},
    overlay: @parameters:Design.LayoutParameters -> @surface:UI.Surface -> @viewport:Design.Viewport -> @bounds:SpatialModel.Box -> @main:SpatialModel.Box -> @details:Maybe<&2, SpatialModel.Box> -> @frame:Design.MainFrame -> @placements:+List<Design.Overlay> -> @controls:+List<Design.NodePlacement> ->
      {Model.project(surface, Design.Layout{viewport, Design.Shell{Design.OverlayNavigation{bounds}, main, details}, frame, placements, parameters, controls}) == surface : UI.Surface}
  }

law evidence:
  Requirements
