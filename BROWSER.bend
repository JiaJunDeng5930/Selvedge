import Base
import ./browser/layout/GEOMETRY.bend as AnchorGeometry
import ./browser/runtime/native-fields.bend as NativeFields
import ./browser/document/RENDERED.bend as Rendered
import ./browser/focus/MODEL.bend as Focus
import ./browser/runtime/PLATFORM.bend as Platform
import ./browser/layout/physical-plan.bend as Plan
import ./browser/runtime/SEMANTICS.bend as Legacy
import ./browser/document/MODEL.bend as CodeObservation
import ./harness/MODEL.bend as M
import ./browser/editor/MODEL.bend as Editor
import ./browser/reading/MODEL.bend as Reading
import ./browser/runtime/MODEL.bend as Browser
import ./browser/layout/natural-size.bend as NaturalSize
import ./browser/appearance/FONT.bend as F
import ./interaction/services/MODEL.bend as Services
import ./interaction/conversation/CODE.bend as Code
import ./bendlib/json.bend as J

# Pure browser entry. The host executes only Browser.Effect values.
def empty() -> M.World(): Browser.empty()

def initial(program: M.World(), sequence: Nat) -> Browser.State: Browser.initial(program, sequence)

def command_rejected(ticket: Nat, reason: String, state: Browser.State) -> Browser.Decision: Browser.command_rejected(ticket, reason, state)

def step(input: Legacy.Input, state: Browser.State) -> Browser.Decision: Browser.step(input, state)

def observe(state: Browser.State) -> CodeObservation.Document: Browser.observe(NaturalSize.limit(), state)

def activate(key: String, state: Browser.State) -> Browser.Decision: Browser.activate(key, state)

def edit_text(key: String, text: String, state: Browser.State) -> Browser.Decision: Browser.edit_text(key, text, state)

def confirm_text(key: String, keyboard: String, composing: Bool, control: Bool, alt: Bool, shift: Bool, meta: Bool, state: Browser.State) -> Browser.Decision: Browser.confirm_text(key, keyboard, composing, control, alt, shift, meta, state)

def edit_toggle(key: String, enabled: Bool, state: Browser.State) -> Browser.Decision: Browser.edit_toggle(key, enabled, state)

def attach(key: String, file: Services.SelectedFile, state: Browser.State) -> Browser.Decision: Browser.attach(key, file, state)

def place(key: String, target: String, state: Browser.State) -> Browser.Decision: Browser.place(key, target, state)

def program(state: Browser.State) -> M.World(): Browser.program(state)

def connect(credential: String, state: Browser.State) -> Browser.Decision: Browser.connect(credential, state)

def directories_completed(ticket: Nat, ok: Bool, body: J.Json, state: Browser.State) -> Browser.Decision: Browser.directories_completed(ticket, ok, body, state)

def code_key(source: Code.Source, ordinal: Nat) -> String: Browser.code_key(source, ordinal)

def code_sources(generation: Nat, observations: +List<CodeObservation.Observation>, state: Browser.State) -> Browser.Decision: Browser.code_sources(generation, observations, state)

def editor_event(key: String, event: Editor.EditorEvent, state: Browser.State) -> Browser.Decision: Browser.editor_event(key, event, state)

def reading(task: Nat, generation: Nat, event: Reading.ReadingEvent, state: Browser.State) -> Browser.Decision: Browser.reading(task, generation, event, state)

def streams(body: J.Json, state: Browser.State) -> Browser.Decision: Browser.streams(body, state)

def key_input(key: String, shift: Bool, received: Nat, frame: Rendered.Frame, state: Browser.State) -> Browser.Decision: Browser.key_input(key, shift, received, frame, state)

def key_event(key: String, shift: Bool, received: Nat, frame: Rendered.Frame, state: Browser.State) -> Browser.KeyResult: Browser.key_event(key, shift, received, frame, state)

def directory_listed(ticket: Nat, ok: Bool, body: J.Json, state: Browser.State) -> Browser.Decision: Browser.directory_listed(ticket, ok, body, state)

def outside_event(identity: String, state: Browser.State) -> Browser.OutsideDecision: Browser.outside_event(identity, state)

def measurement_budget(state: Browser.State) -> Nat: Browser.measurement_budget(state)

def measurement_plan(state: Browser.State) -> F.Plan: Browser.measurement_plan(state)

def measurements(observation: F.Observation, state: Browser.State) -> Browser.Decision: Browser.measurements(observation, state)

def focus_ticket(state: Browser.State) -> Nat: Browser.focus_ticket(state)

def active_scope(state: Browser.State) -> Focus.Scope: Browser.active_scope(state)

def displayed_generation(state: Browser.State) -> Nat: Browser.displayed_generation(state)

def display_ready(state: Browser.State) -> Bool: Browser.display_ready(state)

def render_status(state: Browser.State) -> String: Browser.render_status(state)

def render_violations(state: Browser.State) -> +List<Rendered.Violation>: Browser.render_violations(state)

def measurement_request(state: Browser.State) -> Maybe<&2, Browser.MeasurementRequest>: Browser.measurement_request(state)

def physical_measured(ticket: Browser.MeasurementTicket, receipts: +List<String>, state: Browser.State) -> Browser.Decision: Browser.physical_measured(ticket, receipts, state)

def physical_measurement_failed(ticket: Browser.MeasurementTicket, reason: String, state: Browser.State) -> Browser.Decision: Browser.physical_measurement_failed(ticket, reason, state)

def capture_anchor(key: String, left: AnchorGeometry.Origin, top: AnchorGeometry.Origin, width: Nat, height: Nat, state: Browser.State) -> Browser.Decision: Browser.capture_anchor(key, left, top, width, height, state)

def remeasure(state: Browser.State) -> Browser.Decision: Browser.remeasure(state)

def probe_document(job: Plan.Job) -> CodeObservation.Document: Browser.probe_document(job)

def probe_target_keys(job: Plan.Job) -> +List<String>: Browser.probe_target_keys(job)

def publication(last_published: Nat, state: Browser.State) -> Browser.Publication: Browser.publication(NaturalSize.limit(), last_published, state)

def field_session_initial() -> NativeFields.Record: NativeFields.initial()

def field_session_step(event: NativeFields.FieldEvent, record: NativeFields.Record) -> NativeFields.Decision: NativeFields.step(event, record)

def native_focus_observed(generation: Nat, owner: String, identity: String, state: Browser.State) -> Browser.Decision: Browser.native_focus_observed(generation, owner, identity, state)

def code_dom_key(source: Code.Source, ordinal: Nat) -> String: Code.dom_key(Code.Identity{source, ordinal})

def render_inspection(state: Browser.State) -> Browser.RenderInspection: Browser.render_inspection(state)

def publication_focus_feedback(publication: Browser.Publication, ticket: Nat, before: Maybe<&2, Focus.Target>, after: Maybe<&2, Focus.Target>) -> Maybe<&2, Platform.Input>: Browser.publication_focus_feedback(publication, ticket, before, after)
