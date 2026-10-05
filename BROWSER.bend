import ./webui/native-fields.bend as NativeFields
import ./webui/rendered.bend as Rendered
import ./webui/focus.bend as Focus
import ./webui/physical-plan.bend as Plan
import ./webui/physical-content.bend as Content
import ./webui/browser.bend as Legacy
import Base
import ./MODEL.bend as M
import ./webui/document.bend as Document
import ./webui/editor.bend as Editor
import ./webui/reading.bend as Reading
import ./webui/physical-browser.bend as Browser
import ./webui/font-observation.bend as F
import ./core/client-services.bend as Services
import ./core/code-block.bend as Code
import ./bendlib/json.bend as J

# Pure browser entry. The host executes only Browser.Effect values.
def empty() -> M.World(): Browser.empty()
def initial(program: M.World(), sequence: Nat) -> Browser.State: Browser.initial(program, sequence)
def command_rejected(ticket: Nat, reason: String, state: Browser.State) -> Browser.Decision: Browser.command_rejected(ticket, reason, state)
def step(input: Legacy.Input, state: Browser.State) -> Browser.Decision: Browser.step(input, state)
def observe(state: Browser.State) -> Document.Document: Browser.observe(state)
def activate(key: String, state: Browser.State) -> Browser.Decision: Browser.activate(key, state)
def edit_text(key: String, text: String, state: Browser.State) -> Browser.Decision: Browser.edit_text(key, text, state)
def confirm_text(key: String, keyboard: String, composing: Bool, control: Bool, alt: Bool, shift: Bool, meta: Bool, state: Browser.State) -> Browser.Decision: Browser.confirm_text(key, keyboard, composing, control, alt, shift, meta, state)
def edit_toggle(key: String, enabled: Bool, state: Browser.State) -> Browser.Decision: Browser.edit_toggle(key, enabled, state)
def attach(key: String, file: Services.File, state: Browser.State) -> Browser.Decision: Browser.attach(key, file, state)
def place(key: String, target: String, state: Browser.State) -> Browser.Decision: Browser.place(key, target, state)
def program(state: Browser.State) -> M.World(): Browser.program(state)
def connect(credential: String, state: Browser.State) -> Browser.Decision: Browser.connect(credential, state)
def directories_completed(ticket: Nat, ok: Bool, body: J.Json, state: Browser.State) -> Browser.Decision: Browser.directories_completed(ticket, ok, body, state)
def code_key(source: Code.Source, ordinal: Nat) -> String: Browser.code_key(source, ordinal)
def code_source(source: Code.Source, ordinal: Nat, text: String, state: Browser.State) -> Browser.Decision: Browser.code_source(source, ordinal, text, state)

def editor_event(key: String, event: Editor.Event, state: Browser.State) -> Browser.Decision: Browser.editor_event(key, event, state)
def reading(task: Nat, generation: Nat, event: Reading.Event, state: Browser.State) -> Browser.Decision: Browser.reading(task, generation, event, state)
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

def requested_generation(state: Browser.State) -> Nat: Browser.requested_generation(state)

def render_status(state: Browser.State) -> String: Browser.render_status(state)

def physical_plan(state: Browser.State) -> Maybe<&2, Plan.Plan>: Browser.physical_plan(state)

def physical_measured(generation: Nat, receipts: +List<String>, state: Browser.State) -> Browser.Decision: Browser.physical_measured(generation, receipts, state)

def physical_measurement_failed(generation: Nat, reason: String, state: Browser.State) -> Browser.Decision: Browser.physical_measurement_failed(generation, reason, state)

def capture_anchor(key: String, left: Nat, top: Nat, width: Nat, height: Nat, state: Browser.State) -> Browser.Decision: Browser.capture_anchor(key, left, top, width, height, state)

def remeasure(state: Browser.State) -> Browser.Decision: Browser.remeasure(state)

def probe_document(job: Plan.Job) -> Document.Document: Browser.probe_document(job)

def probe_target_keys(request: Content.Request) -> +List<String>: Browser.probe_target_keys(request)

def publication(last_published: Nat, state: Browser.State) -> Browser.Publication: Browser.publication(last_published, state)

def field_session_initial() -> NativeFields.Record: NativeFields.initial()
def field_session_step(event: NativeFields.Event, record: NativeFields.Record) -> NativeFields.Decision: NativeFields.step(event, record)
