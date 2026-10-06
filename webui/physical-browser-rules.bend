import ./anchor-geometry.bend as AnchorGeometry
import ./native-fields-rules.bend as NativeRules
import ./focus.bend as Focus
import ./native-fields.bend as Native
import ../core/interface.bend as UI
import Base
import ./platform.bend as Platform
import ./design.bend as Design
import ./font-observation.bend as F
import ./typography.bend as T
import ./physical-browser.bend as Browser
import ./browser.bend as Legacy
import ./MODEL.bend as Web
import ./rendered.bend as Rendered
import ./physical-world.bend as World
import ./physical-content.bend as Content
import ./physical-renderer.bend as Renderer
import ./authored-shell.bend as Shell
import ./document.bend as Doc
import ../core/ui-world.bend as View
import ../MODEL.bend as M

def stale_frames_claim(+received: Nat, +frame: Rendered.Frame, +state: Browser.State) -> Type:
  {Browser.step(Legacy.Native{Web.FrameObserved{received, frame}}, state) == Browser.Decision{state, Nil{}} : Browser.Decision}
def stale_measurements_claim(+received: Nat, +tokens: +List<String>, +state: Browser.State) -> Type:
  {Browser.physical_measured(received, tokens, state) == Browser.Decision{state, Nil{}} : Browser.Decision}
def ready_document_claim(+legacy: Legacy.State, +serial: Nat, +anchors: +List<Shell.Anchor>, +capacity: View.Capacity, +engine: World.Engine, +world: Content.AllocatedWorld, +semantic: UI.Surface) -> Type:
  {Browser.observe(Browser.State{legacy, serial, anchors, Browser.Displaying{capacity, engine, semantic}, Some{Browser.published(world, capacity, legacy, semantic)}}) ==
    Doc.Document{Doc.Element{"@browser/application", "div", [Doc.Property{"class", "native-application"}], Nil{}, Nil{}, Renderer.nodes(world)}, "Selvedge"} : Doc.Document}
def anchor_preserves_program_claim(+key: String, +left: AnchorGeometry.Origin, +top: AnchorGeometry.Origin, +width: Nat, +height: Nat, +state: Browser.State) -> Type:
  {Browser.program(Browser.decision_state(Browser.capture_anchor(key, left, top, width, height, state))) == Browser.program(state) : M.World()}


def publication_preserves_existing_claim(+last_published: Nat, +state: Browser.State) -> Type:
  {Browser.publication(last_published, state) == Browser.KeepPublished{Browser.native_updates(state)} : Browser.Publication}
def publication_current_claim(+last_published: Nat, +state: Browser.State) -> Type:
  {Browser.publication(last_published, state) == Browser.KeepPublished{Browser.native_updates(state)} : Browser.Publication}

def frame_capture_program_claim(+frame: Rendered.Frame, +state: Browser.State) -> Type:
  {Browser.program(Browser.frame_capture(frame, state)) == Browser.program(state) : M.World()}
def document_keyboard_claim(+key: String, +shift: Bool, +basis: Native.Basis, +semantic: UI.Surface, +frame: Maybe<&2, Rendered.Frame>, +state: Browser.State) -> Type:
  {Browser.published_key(key, shift, Focus.Document{}, basis, semantic, frame, state) == Browser.KeyResult{False{}, Browser.Decision{state, Nil{}}} : Browser.KeyResult}

def temporary_tab_claim(+shift: Bool, +identity: String, +initial: String, +restore: String, +occurrence: Maybe<&2, Nat>, +basis: Native.Basis, +semantic: UI.Surface, +frame: Maybe<&2, Rendered.Frame>, +state: Browser.State) -> Type:
  {Browser.key_handled(Browser.published_key("Tab", shift, Focus.Temporary{identity, initial, restore, occurrence}, basis, semantic, frame, state)) == True{} : Bool}

type Requirements is Type:
  Requirements{
    temporary_tab: @+shift:Bool -> @+identity:String -> @+initial:String -> @+restore:String -> @+occurrence:Maybe<&2, Nat> -> @+basis:Native.Basis -> @+semantic:UI.Surface -> @+frame:Maybe<&2, Rendered.Frame> -> @+state:Browser.State -> temporary_tab_claim(shift, identity, initial, restore, occurrence, basis, semantic, frame, state),
    native_fields: NativeRules.Requirements,
    frame_capture_program: @+frame:Rendered.Frame -> @+state:Browser.State -> frame_capture_program_claim(frame, state),
    document_keyboard: @+key:String -> @+shift:Bool -> @+basis:Native.Basis -> @+semantic:UI.Surface -> @+frame:Maybe<&2, Rendered.Frame> -> @+state:Browser.State -> document_keyboard_claim(key, shift, basis, semantic, frame, state),
    stale_frames: @+received:Nat -> @+frame:Rendered.Frame -> @+state:Browser.State ->
      {Browser.frame_owned(received, state) == False{} : Bool} -> stale_frames_claim(received, frame, state),
    stale_measurements: @+received:Nat -> @+tokens:+List<String> -> @+state:Browser.State ->
      {Browser.measurement_owned(received, state) == False{} : Bool} -> stale_measurements_claim(received, tokens, state),
    ready_document: @+legacy:Legacy.State -> @+serial:Nat -> @+anchors:+List<Shell.Anchor> -> @+capacity:View.Capacity -> @+engine:World.Engine -> @+world:Content.AllocatedWorld -> @+semantic:UI.Surface -> ready_document_claim(legacy, serial, anchors, capacity, engine, world, semantic),
    anchor_preserves_program: @+key:String -> @+left:AnchorGeometry.Origin -> @+top:AnchorGeometry.Origin -> @+width:Nat -> @+height:Nat -> @+state:Browser.State -> anchor_preserves_program_claim(key, left, top, width, height, state),
    publication_preserves_existing: @+last_published:Nat -> @+state:Browser.State ->
      {Bool.not(Nat.is_eq(last_published, 0n)) == True{} : Bool} ->
      {Browser.display_ready(state) == False{} : Bool} -> publication_preserves_existing_claim(last_published, state),
    publication_current: @+last_published:Nat -> @+state:Browser.State ->
      {Bool.not(Nat.is_eq(last_published, 0n)) == True{} : Bool} ->
      {Browser.display_ready(state) == True{} : Bool} ->
      {Nat.is_eq(Browser.displayed_generation(state), last_published) == True{} : Bool} -> publication_current_claim(last_published, state)}

law evidence:
  Requirements

law forwarded_frame_uses_published_surface:
  for +stored: Legacy.State
  for +serial: Nat
  for +anchors: +List<Shell.Anchor>
  for +lifecycle: Browser.Lifecycle
  for +world: Content.AllocatedWorld
  for +semantic: UI.Surface
  for +scope: Focus.Scope
  for +basis: Native.Basis
  for +old: Maybe<&2, Rendered.Frame>
  for +frame: Rendered.Frame
  {Browser.frame_forward_ready(True{}, Browser.State{stored, serial, anchors, lifecycle,
    Some{Browser.Published{world, semantic, scope, basis, old}}}, frame) ==
    Browser.accept(False{}, Legacy.observe_frame(Browser.semantic_generation(stored), semantic, frame, stored),
      Browser.State{stored, serial, anchors, lifecycle, Some{Browser.Published{world, semantic, scope, basis, old}}}) : Browser.Decision}

law failed_font_candidate_blocked:
  for +application: Platform.State
  for +generation: Nat
  for +realization: Rendered.State
  for +environment: Design.Environment
  for +font_generation: Nat
  for +scale: T.Scale
  for +sequence: Nat
  for +ticket: Nat
  for +pending: +List<Legacy.Pending>
  for +serial: Nat
  for +anchors: +List<Shell.Anchor>
  for +lifecycle: Browser.Lifecycle
  for +displayed: Maybe<&2, Browser.Published>
  for +index: Nat
  {Browser.one_candidate(index, Browser.State{Legacy.State{Web.State{application, generation, realization,
    environment, F.Failed{font_generation, scale}}, sequence, ticket, pending, None{}}, serial, anchors, lifecycle, displayed}) ==
    Browser.Stopped{Browser.Decision{Browser.State{Legacy.State{Web.State{application, generation, realization,
      environment, F.Failed{font_generation, scale}}, sequence, ticket, pending, None{}}, serial, anchors,
      Browser.Blocked{"Font measurements could not be validated."}, displayed}, Nil{}}} : Browser.Search}

law unmet_frame_status:
  for +semantic: UI.Surface
  for +application: Platform.State
  for +generation: Nat
  for +frame_generation: Nat
  for +frame: Rendered.Frame
  for +violations: +List<Rendered.Violation>
  for +environment: Design.Environment
  for +font: F.State
  for +sequence: Nat
  for +ticket: Nat
  for +pending: +List<Legacy.Pending>
  for +serial: Nat
  for +anchors: +List<Shell.Anchor>
  for +capacity: View.Capacity
  for +engine: World.Engine
  for +displayed: Maybe<&2, Browser.Published>
  {Browser.render_status(Browser.State{Legacy.State{Web.State{application, generation,
    Rendered.Unmet{frame_generation, frame, violations}, environment, font}, sequence, ticket, pending, None{}},
    serial, anchors, Browser.Displaying{capacity, engine, semantic}, displayed}) == "unmet" : String}


def element_enabled(element: Rendered.Element) -> Bool:
  Rendered.Element{key, visible, enabled, tab_stop, keyboard, scroll, bounds, hit} = element
  enabled

def element_reachable(element: Rendered.Element) -> Bool:
  Rendered.Element{key, visible, enabled, tab_stop, keyboard, scroll, bounds, hit} = element
  visible || scroll

law enabled_reachable_tab_member:
  for +element: Rendered.Element
  for admitted: {element_enabled(element) == True{} : Bool}
  for reachable: {element_reachable(element) == True{} : Bool}
  {Browser.observed_eligible(Some{element}) == True{} : Bool}


law rejected_native_focus_preserves_state:
  for +generation: Nat
  for +owner: String
  for +identity: String
  for +state: Browser.State
  for rejected: {Browser.native_observation_owned(generation, owner, identity, state) == False{} : Bool}
  {Browser.native_focus_observed(generation, owner, identity, state) == Browser.Decision{state, Nil{}} : Browser.Decision}

law missing_native_frame_rejects:
  for semantic: UI.Surface
  for owner: String
  for identity: String
  {Browser.native_frame_owned(None{}, semantic, owner, identity) == False{} : Bool}


law stale_native_focus_preserves_state:
  for +generation: Nat
  for +owner: String
  for +identity: String
  for +state: Browser.State
  for stale: {Browser.frame_owned(generation, state) == False{} : Bool}
  {Browser.native_focus_observed(generation, owner, identity, state) == Browser.Decision{state, Nil{}} : Browser.Decision}
