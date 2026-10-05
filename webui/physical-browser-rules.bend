import ./native-fields-rules.bend as NativeRules
import ./focus.bend as Focus
import ./native-fields.bend as Native
import ../core/interface.bend as UI
import Base
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
def ready_document_claim(+legacy: Legacy.State, +serial: Nat, +anchors: +List<Shell.Anchor>, +capacity: View.Capacity, +engine: World.Engine, +world: Content.AllocatedWorld) -> Type:
  {Browser.observe(Browser.State{legacy, serial, anchors, Browser.Displaying{capacity, engine}, Some{Browser.published(world, capacity, legacy)}}) ==
    Doc.Document{Doc.Element{"@browser/application", "div", [Doc.Property{"class", "native-application"}], Nil{}, Nil{}, Renderer.nodes(world)}, "Selvedge"} : Doc.Document}
def anchor_preserves_program_claim(+key: String, +left: Nat, +top: Nat, +width: Nat, +height: Nat, +state: Browser.State) -> Type:
  {Browser.program(Browser.decision_state(Browser.capture_anchor(key, left, top, width, height, state))) == Browser.program(state) : M.World()}


def publication_preserves_existing_claim(+last_published: Nat, +state: Browser.State) -> Type:
  {Browser.publication(last_published, state) == Browser.KeepPublished{Browser.native_updates(state)} : Browser.Publication}
def publication_current_claim(+last_published: Nat, +state: Browser.State) -> Type:
  {Browser.publication(last_published, state) == Browser.KeepPublished{Browser.native_updates(state)} : Browser.Publication}

def frame_capture_program_claim(+frame: Rendered.Frame, +state: Browser.State) -> Type:
  {Browser.program(Browser.frame_capture(frame, state)) == Browser.program(state) : M.World()}
def document_keyboard_claim(+key: String, +shift: Bool, +basis: Native.Basis, +semantic: UI.Surface, +frame: Maybe<&2, Rendered.Frame>, +state: Browser.State) -> Type:
  {Browser.published_key(key, shift, Focus.Document{}, basis, semantic, frame, state) == Browser.KeyResult{False{}, Browser.Decision{state, Nil{}}} : Browser.KeyResult}

def temporary_tab_claim(+shift: Bool, +identity: String, +initial: String, +restore: String, +basis: Native.Basis, +semantic: UI.Surface, +frame: Maybe<&2, Rendered.Frame>, +state: Browser.State) -> Type:
  {Browser.key_handled(Browser.published_key("Tab", shift, Focus.Temporary{identity, initial, restore}, basis, semantic, frame, state)) == True{} : Bool}

type Requirements is Type:
  Requirements{
    temporary_tab: @+shift:Bool -> @+identity:String -> @+initial:String -> @+restore:String -> @+basis:Native.Basis -> @+semantic:UI.Surface -> @+frame:Maybe<&2, Rendered.Frame> -> @+state:Browser.State -> temporary_tab_claim(shift, identity, initial, restore, basis, semantic, frame, state),
    native_fields: NativeRules.Requirements,
    frame_capture_program: @+frame:Rendered.Frame -> @+state:Browser.State -> frame_capture_program_claim(frame, state),
    document_keyboard: @+key:String -> @+shift:Bool -> @+basis:Native.Basis -> @+semantic:UI.Surface -> @+frame:Maybe<&2, Rendered.Frame> -> @+state:Browser.State -> document_keyboard_claim(key, shift, basis, semantic, frame, state),
    stale_frames: @+received:Nat -> @+frame:Rendered.Frame -> @+state:Browser.State ->
      {Browser.frame_owned(received, state) == False{} : Bool} -> stale_frames_claim(received, frame, state),
    stale_measurements: @+received:Nat -> @+tokens:+List<String> -> @+state:Browser.State ->
      {Browser.measurement_owned(received, state) == False{} : Bool} -> stale_measurements_claim(received, tokens, state),
    ready_document: @+legacy:Legacy.State -> @+serial:Nat -> @+anchors:+List<Shell.Anchor> -> @+capacity:View.Capacity -> @+engine:World.Engine -> @+world:Content.AllocatedWorld -> ready_document_claim(legacy, serial, anchors, capacity, engine, world),
    anchor_preserves_program: @+key:String -> @+left:Nat -> @+top:Nat -> @+width:Nat -> @+height:Nat -> @+state:Browser.State -> anchor_preserves_program_claim(key, left, top, width, height, state),
    publication_preserves_existing: @+last_published:Nat -> @+state:Browser.State ->
      {Bool.not(Nat.is_eq(last_published, 0n)) == True{} : Bool} ->
      {Browser.display_ready(state) == False{} : Bool} -> publication_preserves_existing_claim(last_published, state),
    publication_current: @+last_published:Nat -> @+state:Browser.State ->
      {Bool.not(Nat.is_eq(last_published, 0n)) == True{} : Bool} ->
      {Browser.display_ready(state) == True{} : Bool} ->
      {Nat.is_eq(Browser.displayed_generation(state), last_published) == True{} : Bool} -> publication_current_claim(last_published, state)}

law evidence:
  Requirements
