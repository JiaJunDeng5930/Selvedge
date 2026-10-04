import Base
import ../physical-browser.bend as Browser
import ../physical-browser-rules.bend as Rule
import ../browser.bend as Legacy
import ../MODEL.bend as Web
import ../rendered.bend as Rendered
import ../physical-world.bend as World
import ../physical-content.bend as Content
import ../authored-shell.bend as Shell
import ../../core/ui-world.bend as View
import ../../bendlib/stdlib.bend as Std

def stale_frames(+received: Nat, +frame: Rendered.Frame, +state: Browser.State,
  proof: {Browser.display_ready(state) && Nat.is_eq(received, Browser.displayed_generation(state)) == False{} : Bool}) ->
  Rule.stale_frames_claim(received, frame, state):
  Std.transport(Bool, False{},
    (owned => {Browser.received_frame(owned, frame, state) == Browser.Decision{state, Nil{}} : Browser.Decision}),
    {==}, Browser.display_ready(state) && Nat.is_eq(received, Browser.displayed_generation(state)), proof)

def stale_measurements(+received: Nat, +tokens: +List<String>, +state: Browser.State,
  proof: {Browser.measurement_owned(received, state) == False{} : Bool}) ->
  Rule.stale_measurements_claim(received, tokens, state):
  Std.transport(Bool, False{},
    (owned => {Browser.measured_current(owned, tokens, state) == Browser.Decision{state, Nil{}} : Browser.Decision}),
    {==}, Browser.measurement_owned(received, state), proof)

def ready_document(+legacy: Legacy.State, +serial: Nat, +anchors: +List<Shell.Anchor>, +capacity: View.Capacity, +engine: World.Engine, +world: Content.AllocatedWorld) ->
  Rule.ready_document_claim(legacy, serial, anchors, capacity, engine, world):
  match legacy:
    case Legacy.State{Web.State{application, generation, realization, environment, font}, sequence, ticket, pending}: {==}

def anchor_preserves_program(+key: String, +left: Nat, +top: Nat, +width: Nat, +height: Nat, +state: Browser.State) ->
  Rule.anchor_preserves_program_claim(key, left, top, width, height, state):
  match state:
    case Browser.State{legacy, serial, anchors, lifecycle, displayed}: {==}

def publication_preserves_existing(+last_published: Nat, +state: Browser.State,
  existing: {Bool.not(Nat.is_eq(last_published, 0n)) == True{} : Bool},
  waiting: {Browser.display_ready(state) == False{} : Bool}) -> Rule.publication_preserves_existing_claim(last_published, state):
  Std.transport(Bool, True{},
    (has_existing => {Browser.publication_for(has_existing, Browser.display_ready(state),
      Nat.is_eq(Browser.displayed_generation(state), last_published), state) == Browser.KeepPublished{} : Browser.Publication}),
    Std.transport(Bool, False{},
      (ready => {Browser.publication_for(True{}, ready, Nat.is_eq(Browser.displayed_generation(state), last_published), state) == Browser.KeepPublished{} : Browser.Publication}),
      {==}, Browser.display_ready(state), waiting),
    Bool.not(Nat.is_eq(last_published, 0n)), existing)

def publication_current(+last_published: Nat, +state: Browser.State,
  existing: {Bool.not(Nat.is_eq(last_published, 0n)) == True{} : Bool},
  ready: {Browser.display_ready(state) == True{} : Bool},
  current: {Nat.is_eq(Browser.displayed_generation(state), last_published) == True{} : Bool}) -> Rule.publication_current_claim(last_published, state):
  Std.transport(Bool, True{},
    (has_existing => {Browser.publication_for(has_existing, Browser.display_ready(state),
      Nat.is_eq(Browser.displayed_generation(state), last_published), state) == Browser.KeepPublished{} : Browser.Publication}),
    Std.transport(Bool, True{},
      (is_ready => {Browser.publication_for(True{}, is_ready, Nat.is_eq(Browser.displayed_generation(state), last_published), state) == Browser.KeepPublished{} : Browser.Publication}),
      Std.transport(Bool, True{},
        (is_current => {Browser.publication_for(True{}, True{}, is_current, state) == Browser.KeepPublished{} : Browser.Publication}),
        {==}, Nat.is_eq(Browser.displayed_generation(state), last_published), current),
      Browser.display_ready(state), ready),
    Bool.not(Nat.is_eq(last_published, 0n)), existing)

def Rule.evidence():
  Rule.Requirements{
    +received => +frame => +state => proof => stale_frames(received, frame, state, proof),
    +received => +tokens => +state => proof => stale_measurements(received, tokens, state, proof),
    +legacy => +serial => +anchors => +capacity => +engine => +world => ready_document(legacy, serial, anchors, capacity, engine, world),
    +key => +left => +top => +width => +height => +state => anchor_preserves_program(key, left, top, width, height, state),
    +last_published => +state => existing => waiting => publication_preserves_existing(last_published, state, existing, waiting),
    +last_published => +state => existing => ready => current => publication_current(last_published, state, existing, ready, current)}
