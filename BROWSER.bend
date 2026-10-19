import ./browser/MODEL.bend as Web
import ./browser/editor/skill-mention.bend as Mention
import ./browser/editor/skill-view.bend as SkillView
import ./interaction/INPUT.bend as UserInput
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
import ./interaction/interactive_markdown/TYPES.bend as Interactive
import ./interaction/interactive_markdown/SCENE.bend as InteractiveScene
import ./interaction/IDENTITY.bend as Identity
import ./bendlib/json.bend as J

def native_editors(state: Browser.State) -> +List<Editor.Editor>:
  Platform.editors(Platform.platform(Web.application(Legacy.web(Browser.legacy(state)))))

def with_editor_overlays(editors: +List<Editor.Editor>, publication: Browser.Publication) -> Browser.Publication:
  match publication:
    case Browser.KeepPublished{fields}: Browser.KeepPublished{fields}
    case Browser.Publish{generation, document, fields}: Browser.Publish{generation, SkillView.document(editors, document), fields}

def activate_choice(choice: Maybe<&2, SkillView.Choice>, key: String, state: Browser.State) -> Browser.Decision:
  match choice:
    case None{}: Browser.activate(key, state)
    case Some{SkillView.Choice{field, index}}: Browser.editor_event(field, Editor.AcceptMention{Some{index}}, state)

def editor_catalog_completed(key: String, ticket: Nat, workspace: String, body: J.Json, state: Browser.State) -> Browser.Decision:
  Browser.editor_event(key, Editor.CatalogObserved{ticket, workspace, body}, state)

def choose_native_editor(same: Bool, editor: Editor.Editor, rest: Maybe<&2, Editor.Editor>) -> Maybe<&2, Editor.Editor>:
  match same:
    case True{}: Some{editor}
    case False{}: rest

def find_native_editor(editors: +List<Editor.Editor>, +key: String) -> Maybe<&2, Editor.Editor>:
  match editors:
    case Nil{}: None{}
    case Con{+editor, rest}: choose_native_editor(String.eq(Mention.field(Editor.mentions(editor)), key), editor, find_native_editor(rest, key))

def mention_key_found(found: Maybe<&2, Editor.Editor>, observation: Editor.KeyObservation) -> Editor.NativeKey:
  match found:
    case None{}: Editor.NativeKey{None{}, False{}}
    case Some{editor}: Editor.native_mentions(observation, editor)

def editor_key_decision(native: Editor.NativeKey, key: String, state: Browser.State) -> Browser.KeyResult:
  Editor.NativeKey{event, handled} = native
  match event:
    case None{}: Browser.KeyResult{False{}, Browser.Decision{state, Nil{}}}
    case Some{input}: Browser.KeyResult{handled, Browser.editor_event(key, input, state)}

def editor_key_event(+key: String, observation: Editor.KeyObservation, +state: Browser.State) -> Browser.KeyResult:
  editor_key_decision(mention_key_found(find_native_editor(native_editors(state), key), observation), key, state)

# Pure browser entry. The host executes only Browser.Effect values.
def empty() -> M.World(): Browser.empty()

def initial(program: M.World(), sequence: Nat) -> Browser.State: Browser.initial(program, sequence)

def command_rejected(ticket: Nat, reason: String, state: Browser.State) -> Browser.Decision: Browser.command_rejected(ticket, reason, state)

def step(input: Legacy.Input, state: Browser.State) -> Browser.Decision: Browser.step(input, state)

def observe(+state: Browser.State) -> CodeObservation.Document: SkillView.document(native_editors(state), Browser.observe(NaturalSize.limit(), state))

def activate(+key: String, +state: Browser.State) -> Browser.Decision: activate_choice(SkillView.choice(native_editors(state), key), key, state)

def edit_text(key: String, text: String, state: Browser.State) -> Browser.Decision: Browser.edit_text(key, text, state)

def edit_structured_text(key: String, text: String, parsed: Maybe<&2, J.Json>, state: Browser.State) -> Browser.Decision: Browser.edit_structured_text(key, text, parsed, state)

def confirm_text(key: String, keyboard: String, composing: Bool, control: Bool, alt: Bool, shift: Bool, meta: Bool, state: Browser.State) -> Browser.Decision: Browser.confirm_text(key, keyboard, composing, control, alt, shift, meta, state)

def edit_toggle(key: String, enabled: Bool, state: Browser.State) -> Browser.Decision: Browser.edit_toggle(key, enabled, state)

def attach(key: String, file: Services.SelectedFile, state: Browser.State) -> Browser.Decision: Browser.attach(key, file, state)

def place(key: String, target: String, state: Browser.State) -> Browser.Decision: Browser.place(key, target, state)

def program(state: Browser.State) -> M.World(): Browser.program(state)

def connect(state: Browser.State) -> Browser.Decision: Browser.connect(state)

def workspace_git_completed(ticket: Nat, available: Bool, state: Browser.State) -> Browser.Decision: Browser.workspace_git_completed(ticket, available, state)

def directories_completed(ticket: Nat, ok: Bool, body: J.Json, state: Browser.State) -> Browser.Decision: Browser.directories_completed(ticket, ok, body, state)

def code_key(source: Code.Source, ordinal: Nat) -> String: Browser.code_key(source, ordinal)

def markdown_complete(source: Maybe<&2, Code.Source>) -> Bool: Code.complete(source)

def code_sources(generation: Nat, observations: +List<CodeObservation.Observation>, state: Browser.State) -> Browser.Decision: Browser.code_sources(generation, observations, state)

def editor_event(key: String, event: Editor.EditorEvent, state: Browser.State) -> Browser.Decision: Browser.editor_event(key, event, state)

def native_editor_key(observation: Editor.KeyObservation) -> Editor.NativeKey: Editor.native_key(observation)

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

def publication(last_published: Nat, +state: Browser.State) -> Browser.Publication: with_editor_overlays(native_editors(state), Browser.publication(NaturalSize.limit(), last_published, state))

def field_session_initial() -> NativeFields.Record: NativeFields.initial()

def field_session_step(event: NativeFields.FieldEvent, record: NativeFields.Record) -> NativeFields.Decision: NativeFields.step(event, record)

def native_focus_observed(generation: Nat, owner: String, identity: String, state: Browser.State) -> Browser.Decision: Browser.native_focus_observed(generation, owner, identity, state)

def code_dom_key(source: Code.Source, ordinal: Nat) -> String: Code.dom_key(Code.Identity{source, ordinal})

def render_inspection(state: Browser.State) -> Browser.RenderInspection: Browser.render_inspection(state)

def publication_focus_feedback(publication: Browser.Publication, ticket: Nat, before: Maybe<&2, Focus.Target>, after: Maybe<&2, Focus.Target>) -> Maybe<&2, Platform.Input>: Browser.publication_focus_feedback(publication, ticket, before, after)

def navigation_pointer_observed(owner: Maybe<&2, String>, state: Browser.State) -> Browser.Decision:
  Browser.step(Legacy.Native{Web.PlatformInput{Platform.NavigationPointerObserved{owner}}}, state)

def navigation_focus_observed(owner: Maybe<&2, String>, state: Browser.State) -> Browser.Decision:
  Browser.step(Legacy.Native{Web.PlatformInput{Platform.NavigationFocusObserved{owner}}}, state)

def navigation_hover_observed(capable: Bool, state: Browser.State) -> Browser.Decision:
  Browser.step(Legacy.Native{Web.PlatformInput{Platform.NavigationHoverObserved{capable}}}, state)


def display_pending(state: Browser.State) -> Bool: Browser.display_pending(state)


def markdown_source_key(source: Code.Source) -> String: Code.source_key(source)


type InteractiveStoragePolicy is Data:
  InteractiveStoragePolicy{maximum_documents: Nat, maximum_bytes: Nat}

def interactive_storage_policy() -> InteractiveStoragePolicy:
  InteractiveStoragePolicy{100n, 5242880n}


def snapshot_environment(expected_namespace: String, namespace: String, sequence: Nat, program: M.World(), state: Browser.State) -> Browser.Decision:
  Browser.snapshot_environment(expected_namespace, namespace, sequence, program, state)

def authenticated_snapshot(expected_namespace: String, namespace: String, sequence: Nat, program: M.World(), ticket: Nat, state: Browser.State) -> Browser.Decision:
  Browser.authenticated_snapshot(expected_namespace, namespace, sequence, program, ticket, state)

def network_failed(namespace: String, sequence: Nat, connection_ticket: Nat, reason: String, revoked: Bool, authentication: Maybe<&2, Nat>, state: Browser.State) -> Browser.Decision:
  Browser.network_failed(namespace, sequence, connection_ticket, reason, revoked, authentication, state)

def completed_environment(ticket: Nat, namespace: String, sequence: Nat, program: M.World(), reply: J.Json, state: Browser.State) -> Browser.Decision:
  Browser.completed_environment(ticket, namespace, sequence, program, reply, state)


def store_namespace(state: Browser.State) -> String: Browser.current_namespace(state)

def accepted_sequence(state: Browser.State) -> Nat: Legacy.sequence(Browser.legacy(state))


def source_fresh(state: Browser.State) -> Bool: Browser.source_fresh(state)

def physical_invalidated(before: Browser.State, after: Browser.State) -> Bool:
  Browser.physical_invalidated(before, after)

def interactive_event_key(event: Interactive.EventIdentity) -> String:
  Interactive.EventIdentity{component, occurrence} = event
  Identity.encode(InteractiveScene.mounted_key(component, occurrence))


def stream_notice_owned(body: J.Json, state: Browser.State) -> Bool: Browser.stream_notice_owned(body, state)

def commit_refresh_needed(notice: J.Json, state: Browser.State) -> Bool: Browser.commit_refresh_needed(notice, state)
