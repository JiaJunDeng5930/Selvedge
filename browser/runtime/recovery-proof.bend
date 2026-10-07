import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../focus/MODEL.bend as Focus
import ../document/RENDERED.bend as Rendered
import ../document/FRAME.bend as SourceFrame
import ../layout/MODEL.bend as World
import ./native-fields.bend as Native
import ./frontend-utility.bend as Utility
import ../layout/CONTENT.bend as Content
import ./MODEL.bend as Browser
import Base
import ./recovery-rules.bend as Rule
import ./frontend-utility-rules.bend as UtilityRules
import ../document/source-frame-rules.bend as FrameRules
import ./frontend-utility-proof.bend as UtilityProof
import ../document/source-frame-proof.bend as FrameProof

def state_utility_publication_evidence(+model_state: Browser.State, +world: Content.AllocatedWorld, +purpose: Utility.Purpose, +engine: World.Engine) ->
  {Browser.utility_publish(world, purpose, engine, model_state) ==
        Browser.Decision{Browser.with_displayed(Some{Browser.Published{world, Browser.current_legacy_surface(Browser.legacy(model_state)), Focus.Document{}, Native.Basis{Nil{}, Nil{}}, None{}}}, Browser.with_lifecycle(Browser.UtilityDisplaying{purpose, engine}, model_state)), Nil{}} : Browser.Decision}:
  Browser.State{+legacy, +serial, +anchors, +lifecycle, +displayed} = model_state
  {==}

def state_correlated_frame_evidence(+model_state: Browser.State, +frame: Rendered.Frame, +world: Content.AllocatedWorld, +semantic: InterfaceView.Surface, +scope: Focus.Scope, +basis: Native.Basis, +old: Maybe<&2, Rendered.Frame>) ->
  {Browser.correlated_frame_owned(True{}, frame, Browser.with_displayed(Some{Browser.Published{world, semantic, scope, basis, old}}, model_state)) ==
        Browser.utility_frame_result(SourceFrame.check(world, frame), frame, Browser.with_displayed(Some{Browser.Published{world, semantic, scope, basis, old}}, model_state)) : Browser.Decision}:
  Browser.State{+legacy, +serial, +anchors, +lifecycle, +original_1} = model_state
  {==}

def state_correlated_measurement_failure_evidence(+model_state: Browser.State, +purpose: Utility.Purpose, +engine: World.Engine, +round: Nat, +reason: String) ->
  {Browser.utility_measurement_failure(reason, Browser.with_lifecycle(Browser.UtilityMeasuring{purpose, engine, round, False{}}, model_state)) ==
        Browser.utility_fallback(reason, Browser.with_lifecycle(Browser.UtilityMeasuring{purpose, engine, round, False{}}, model_state)) : Browser.Decision}:
  Browser.State{+legacy, +serial, +anchors, +original_1, +displayed} = model_state
  {==}

def state_rejected_frame_evidence(+model_state: Browser.State, +first: Rendered.Violation, +rest: +List<Rendered.Violation>, +frame: Rendered.Frame) ->
  {Browser.utility_frame_result(first <> rest, frame, model_state) ==
        Browser.Decision{Browser.with_displayed(None{}, Browser.with_lifecycle(Browser.UtilityRejected{"Frontend utility frame does not match its admitted source"}, model_state)), Nil{}} : Browser.Decision}:
  Browser.State{+legacy, +serial, +anchors, +lifecycle, +displayed} = model_state
  {==}

def Rule.evidence():
  Rule.Requirements{
    UtilityRules.evidence(),
    FrameRules.evidence(),
    +capacity => +lifecycle => +world => +font => {==},
    +capacity => +lifecycle => +font => {==},
    state_utility_publication_evidence,
    state_correlated_frame_evidence,
    +world => +purpose => +engine => +round => +glyph_only => +state => {==},
    state_correlated_measurement_failure_evidence,
    +frame => +state => {==},
    state_rejected_frame_evidence,
    +state => {==},
    +state => {==},
    +input => +state => {==}}
