import Base
import ./MODEL.bend as M
import ./webui/document.bend as Document
import ./webui/editor.bend as Editor
import ./webui/reading.bend as Reading
import ./webui/browser.bend as Browser
import ./core/client-services.bend as Services
import ./core/code-block.bend as Code
import ./bendlib/json.bend as J

# Pure browser entry. The host executes only Browser.Effect values.
def empty() -> M.World(): Browser.empty()
def initial(program: M.World(), sequence: Nat) -> Browser.State: Browser.initial(program, sequence)
def command_rejected(ticket: Nat, reason: String, state: Browser.State) -> Browser.Decision: Browser.command_rejected(ticket, reason, state)
def step(input: Browser.Input, state: Browser.State) -> Browser.Decision: Browser.step(input, state)
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

def key_input(key: String, shift: Bool, state: Browser.State) -> Browser.Decision: Browser.key_input(key, shift, state)

def key_event(key: String, shift: Bool, state: Browser.State) -> Browser.KeyResult: Browser.key_event(key, shift, state)

def directory_listed(ticket: Nat, ok: Bool, body: J.Json, state: Browser.State) -> Browser.Decision: Browser.directory_listed(ticket, ok, body, state)

def outside_event(identity: String, state: Browser.State) -> Browser.OutsideDecision: Browser.outside_event(identity, state)

