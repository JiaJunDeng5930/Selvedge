import Base
import ./physical-browser.bend as Browser
import ./browser.bend as Legacy
import ./MODEL.bend as Web
import ./document.bend as Doc
import ./frontend-utility.bend as Utility
import ./frontend-utility-rules.bend as UtilityRules
import ./source-frame-rules.bend as FrameRules
import ./physical-world.bend as World
import ./physical-plan.bend as Plan
import ./physical-content.bend as Content
import ./physical-renderer.bend as Renderer
import ./rendered.bend as Rendered
import ./authored-shell.bend as Shell
import ./typography.bend as T
import ./focus.bend as Focus
import ./source-frame.bend as SourceFrame
import ./native-fields.bend as Native
import ../MODEL.bend as M
import ../core/interface.bend as InterfaceView
type Requirements is Type:
  Requirements{
    utility_sources: UtilityRules.Requirements,
    source_frames: FrameRules.Requirements,
    admitted_document: @+capacity:Nat -> @+lifecycle:Browser.Lifecycle -> @+world:Browser.Published -> @+font:T.Presentation ->
      {Browser.observed_lifecycle_at(capacity, lifecycle, Some{world}, font) == Browser.application_document(Renderer.nodes(Browser.published_world(world))) : Doc.Document},
    empty_without_admission: @+capacity:Nat -> @+lifecycle:Browser.Lifecycle -> @+font:T.Presentation ->
      {Browser.observed_lifecycle_at(capacity, lifecycle, None{}, font) == Browser.application_document(Nil{}) : Doc.Document},
    utility_publication: @+model_state:Browser.State ->  @+world:Content.AllocatedWorld -> @+purpose:Utility.Purpose -> @+engine:World.Engine -> {Browser.utility_publish(world, purpose, engine, model_state) ==
        Browser.Decision{Browser.with_displayed(Some{Browser.Published{world, Browser.current_legacy_surface(Browser.legacy(model_state)), Focus.Document{}, Native.Basis{Nil{}, Nil{}}, None{}}}, Browser.with_lifecycle(Browser.UtilityDisplaying{purpose, engine}, model_state)), Nil{}} : Browser.Decision},
    correlated_frame: @+model_state:Browser.State ->  @+frame:Rendered.Frame -> @+world:Content.AllocatedWorld -> @+semantic:InterfaceView.Surface -> @+scope:Focus.Scope -> @+basis:Native.Basis -> @+old:Maybe<&2, Rendered.Frame> ->
      {Browser.correlated_frame_owned(True{}, frame, Browser.with_displayed(Some{Browser.Published{world, semantic, scope, basis, old}}, model_state)) ==
        Browser.utility_frame_result(SourceFrame.check(world, frame), frame, Browser.with_displayed(Some{Browser.Published{world, semantic, scope, basis, old}}, model_state)) : Browser.Decision},
    ready_admission: @+world:Content.AllocatedWorld -> @+purpose:Utility.Purpose -> @+engine:World.Engine -> @+round:Nat -> @+glyph_only:Bool -> @+state:Browser.State ->
      {Browser.utility_selected(Plan.Ready{world}, purpose, engine, round, glyph_only, state) == Browser.utility_publish(world, purpose, engine, state) : Browser.Decision},
    correlated_measurement_failure: @+model_state:Browser.State ->  @+purpose:Utility.Purpose -> @+engine:World.Engine -> @+round:Nat -> @+reason:String ->
      {Browser.utility_measurement_failure(reason, Browser.with_lifecycle(Browser.UtilityMeasuring{purpose, engine, round, False{}}, model_state)) ==
        Browser.utility_fallback(reason, Browser.with_lifecycle(Browser.UtilityMeasuring{purpose, engine, round, False{}}, model_state)) : Browser.Decision},
    valid_frame: @+frame:Rendered.Frame -> @+state:Browser.State ->
      {Browser.utility_frame_result(Nil{}, frame, state) == Browser.Decision{Browser.frame_capture(frame, state), Nil{}} : Browser.Decision},
    rejected_frame: @+model_state:Browser.State ->  @+first:Rendered.Violation -> @+rest:+List<Rendered.Violation> -> @+frame:Rendered.Frame -> {Browser.utility_frame_result(first <> rest, frame, model_state) ==
        Browser.Decision{Browser.with_displayed(None{}, Browser.with_lifecycle(Browser.UtilityRejected{"Frontend utility frame does not match its admitted source"}, model_state)), Nil{}} : Browser.Decision},
    retry_dispatch: @+state:Browser.State ->
      {Browser.activate("@browser/retry", state) == Browser.accept(True{}, Legacy.activate("@browser/retry", Browser.legacy(state)), state) : Browser.Decision},
    retry_mount: @+state:Legacy.State ->
      {Legacy.activate("@browser/retry", state) == Legacy.native(Web.Mount{}, state) : Legacy.Decision},
    document_focus: @+input:Web.Input -> @+state:Browser.State ->
      {Browser.auxiliary_focus_owned(True{}, input, state) == Browser.Decision{state, Nil{}} : Browser.Decision}}
law evidence:
  Requirements
