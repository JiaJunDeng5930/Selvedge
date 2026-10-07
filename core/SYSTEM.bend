import Base
import ./code-block.bend as Content
import ./live-output.bend as Live
import ../MODEL.bend as M
import ../BOARD.bend as B
import ../bendlib/json.bend as J
import ../bendlib/association-map.bend as Finite
import ./user-input.bend as U
import ./user-experience.bend as E
import ./user-experience-program.bend as ExperienceProgram
import ./ui-world.bend as View
import ./form-fields.bend as Forms
import ./client-services.bend as Services

type State is Data:
  State{application: E.Application, services: Services.State}

def application(state: State) -> E.Application:
  State{application, services} = state
  application

def services(state: State) -> Services.State:
  State{application, services} = state
  services

def with_application(value: E.Application, state: State) -> State:
  State{application, services} = state
  State{value, services}

def with_services(value: Services.State, state: State) -> State:
  State{application, services} = state
  State{application, value}

def from_application(application: E.Application, services: Services.State) -> State:
  State{application, services}

type Input is Data:
  ApplicationInput{input: E.Input}
  ServiceInput{input: Services.Input}
  EditField{editor: U.Editor, field: Forms.Field, value: Forms.Value}
  RemoveAttachment{editor: U.Editor, id: String}

type Decision is Data:
  Decision{state: State, reply: J.Json, runtime_effects: +List<M.Effect()>,
    interaction_effects: +List<E.Effect>, service_effects: +List<Services.Effect>, durable: Bool}

type Settings is Data:
  Settings{open: Bool, access: Services.Access, credential_entered: Bool,
    appearance: Services.Appearance, open_action: Input, close_action: Input, connect_action: Input}

type Scene is Data:
  Scene{surface: View.Scene, settings: Settings,
    transfers: +List<Finite.Entry(Services.Transfer)>, preview: Services.Preview, code: +List<Content.Scene>, directory_picker: Services.DirectoryPicker}

type Control is Data:
  Control{identity: String, label: String, prominence: View.Prominence, input: Input, availability: View.Availability}
def initial(program: M.World()) -> State:
  State{E.initial(program), Services.initial()}

def application_result(decision: E.Decision, services: Services.State) -> Decision:
  E.Decision{application, reply, runtime, interaction, durable} = decision
  Decision{State{application, services}, reply, runtime, interaction, Nil{}, durable}

def keep_file(same: Bool, file: B.Attachment, rest: +List<B.Attachment>) -> +List<B.Attachment>:
  match same:
    case True{}: rest
    case False{}: file <> rest

def remove_file(files: +List<B.Attachment>, +id: String) -> +List<B.Attachment>:
  match files:
    case Nil{}: Nil{}
    case Con{B.Attachment{+current, name, mime, path, bytes}, rest}:
      keep_file(String.eq(current, id), B.Attachment{current, name, mime, path, bytes}, remove_file(rest, id))

def file_id(file: B.Attachment) -> String:
  B.Attachment{id, name, mime, path, bytes} = file
  id

def add_file(add: Maybe<&2, B.Attachment>, files: +List<B.Attachment>) -> +List<B.Attachment>:
  match add:
    case None{}: files
    case Some{file}: List.append(&2, B.Attachment, files, [file])

def attachment_edit(found: Maybe<&2, U.Draft>, add: Maybe<&2, B.Attachment>, id: String) -> Maybe<&2, U.Edit>:
  match found:
    case Some{U.Draft{revision, U.Card{card, version, B.Draft{title, description, stage, priority, owner, project, labels, files}, assist, profile, keep_open}, feedback, directory_entry}}:
      Some{U.WriteCard{B.Patch{None{}, None{}, None{}, None{}, None{}, None{}, None{}, Some{add_file(add, remove_file(files, id))}}}}
    case _: None{}

def apply_edit(edit: Maybe<&2, U.Edit>, editor: U.Editor, +application: E.Application) -> E.Decision:
  match edit:
    case None{}: E.refuse(application, "This field is not editable here")
    case Some{value}: ExperienceProgram.step(E.UserInput{U.EditDraft{editor, value}}, application)

def edit_attachment(+editor: U.Editor, add: Maybe<&2, B.Attachment>, id: String, +application: E.Application) -> E.Decision:
  program = E.program(application)
  +session = E.session(application)
  +drafts = E.drafts(session)
  apply_edit(attachment_edit(E.find_draft(drafts, editor), add, id), editor, E.from_program(program, session))

def attached(decision: E.Decision) -> E.Application:
  E.Decision{application, reply, effects, interaction, durable} = decision
  application

def workspace_draft(found: Maybe<&2, U.Draft>) -> Bool:
  match found:
    case Some{U.Draft{revision, body, feedback, directory_entry}}: U.workspace_capable(body)
    case None{}: False{}

def accepts_directory(+editor: U.Editor, application: E.Application) -> Bool:
  +observed_session = E.session(application)
  drafts = E.drafts(observed_session)
  pending = E.pending(observed_session)
  workspace_draft(E.find_draft(drafts, editor)) && Bool.not(E.busy(pending, editor))

def directory_chosen_accepted(accepted: Bool, +editor: U.Editor, path: String, +application: E.Application) -> E.Application:
  match accepted:
    case False{}: application
    case True{}:
      written = attached(ExperienceProgram.step(E.UserInput{U.EditDraft{editor, U.WriteDirectory{path}}}, application))
      attached(ExperienceProgram.step(E.UserInput{U.EditDraft{editor, U.ConfirmDirectory{}}}, written))

def directory_chosen(+editor: U.Editor, path: String, +application: E.Application) -> E.Application:
  directory_chosen_accepted(accepts_directory(editor, application), editor, path, application)

def service_effects(effects: +List<Services.Effect>, +application: E.Application) -> E.Application:
  match effects:
    case Nil{}: application
    case Con{Services.AttachToDraft{editor, +file}, rest}:
      service_effects(rest, attached(edit_attachment(editor, Some{file}, file_id(file), application)))
    case Con{Services.DirectoryChosen{editor, path}, rest}: service_effects(rest, directory_chosen(editor, path, application))
    case Con{Services.SessionReady{}, rest}: service_effects(rest, application)
    case Con{other, rest}: service_effects(rest, application)

def external_effect(effect: Services.Effect) -> Bool:
  match effect:
    case Services.AttachToDraft{editor, file}: False{}
    case Services.DirectoryChosen{editor, path}: False{}
    case Services.SessionReady{}: False{}
    case _: True{}

def application_result_with_services(decision: E.Decision, services: Services.State, effects: +List<Services.Effect>) -> Decision:
  E.Decision{application, reply, runtime, interaction, durable} = decision
  Decision{State{application, services}, reply, runtime, interaction, effects, durable}

def session_attention(application: E.Application) -> String:
  +observed_session = E.session(application)
  attention = E.attention(observed_session)
  attention

def service_interactions(effects: +List<Services.Effect>, +application: E.Application) -> +List<E.Effect>:
  match effects:
    case Nil{}: Nil{}
    case Con{Services.SessionReady{}, rest}: E.Attend{session_attention(application)} <> service_interactions(rest, application)
    case Con{other, rest}: service_interactions(rest, application)

def service_attention(decision: E.Decision, effects: +List<Services.Effect>) -> E.Decision:
  E.Decision{+application, reply, runtime, interaction, durable} = decision
  E.Decision{application, reply, runtime, service_interactions(effects, application), durable}

def service_result(decision: Services.Decision, application: E.Application) -> Decision:
  Services.Decision{services, +effects} = decision
  application_result_with_services(service_attention(E.unchanged(service_effects(effects, application)), effects), services,
    List.filter(~Services.Effect, external_effect, effects))

def command_offline(command: Maybe<&2, M.Command>, access: Services.Access) -> Bool:
  match command:
    case Some{command}: Bool.not(Services.connected(access))
    case None{}: False{}

def submission_blocked_access(access: Services.Access, transfers: +List<Finite.Entry(Services.Transfer)>, input: E.Input) -> Bool:
  match input:
    case E.UserInput{U.Activate{U.Submit{editor}}}: Services.blocks(editor, transfers) || Bool.not(Services.connected(access))
    case E.UserInput{U.Activate{U.ConfirmAction{}}}: Bool.not(Services.connected(access))
    case E.UserInput{U.Activate{action}}: command_offline(U.direct_command(action), access)
    case _: False{}

def submission_blocked(+services: Services.State, input: E.Input) -> Bool:
  submission_blocked_access(Services.access(services), Services.transfers(services), input)

def apply_application(blocked: Bool, input: E.Input, +application: E.Application, +services: Services.State) -> Decision:
  match blocked:
    case True{}: application_result(E.refuse(application, "Connect and finish pending file uploads before submitting"), services)
    case False{}: application_result(ExperienceProgram.step(input, application), services)

def is_card_draft(found: Maybe<&2, U.Draft>) -> Bool:
  match found:
    case Some{U.Draft{revision, U.Card{id, version, value, assist, profile, keep_open}, feedback, directory_entry}}: True{}
    case _: False{}

def accepts_files(editor: U.Editor, application: E.Application) -> Bool:
  +observed_session = E.session(application)
  drafts = E.drafts(observed_session)
  is_card_draft(E.find_draft(drafts, editor))

def add_allowed(allowed: Bool, input: Services.Input, +application: E.Application, +services: Services.State) -> Decision:
  match allowed:
    case True{}: service_result(Services.step(input, services), application)
    case False{}: application_result(E.refuse(application, "Attachments belong to a card draft"), services)

def directory_allowed(allowed: Bool, input: Services.Input, +application: E.Application, +services: Services.State) -> Decision:
  match allowed:
    case True{}: service_result(Services.step(input, services), application)
    case False{}: application_result(E.refuse(application, "The workspace editor is not available"), services)

def service_input(input: Services.Input, +application: E.Application, +services: Services.State) -> Decision:
  match input:
    case Services.OpenDirectoryPicker{+editor, path, trigger}:
      directory_allowed(accepts_directory(editor, application), Services.OpenDirectoryPicker{editor, path, trigger}, application, services)
    case Services.AddFile{+editor, file}:
      add_allowed(accepts_files(editor, application), Services.AddFile{editor, file}, application, services)
    case Services.Connect{}: service_result(Services.step(Services.Connect{}, services), attached(E.observe_preview(Live.ConnectionEnded{}, application)))
    case Services.Disconnected{reason}: service_result(Services.step(Services.Disconnected{reason}, services), attached(E.observe_preview(Live.ConnectionEnded{}, application)))
    case other: service_result(Services.step(other, services), application)

def edit_body(body: U.Body, editor: U.Editor, field: Forms.Field, value: Forms.Value, +application: E.Application) -> E.Decision:
  +program = E.program(application)
  session = E.session(application)
  apply_edit(Forms.edit_for(body, field, value, program), editor, E.from_program(program, session))
def edit_exposed(exposed: Bool, body: U.Body, editor: U.Editor, field: Forms.Field, value: Forms.Value, +application: E.Application) -> E.Decision:
  match exposed:
    case False{}: E.refuse(application, "This field is not part of this editor")
    case True{}: edit_body(body, editor, field, value, application)

def edit_found(found: Maybe<&2, U.Draft>, editor: U.Editor, +field: Forms.Field, value: Forms.Value, +application: E.Application) -> E.Decision:
  match found:
    case None{}: E.refuse(application, "The editor is not open")
    case Some{U.Draft{revision, +body, feedback, directory_entry}}: edit_exposed(Forms.exposed(body, field), body, editor, field, value, application)

def edit_field(+editor: U.Editor, field: Forms.Field, value: Forms.Value, +application: E.Application) -> E.Decision:
  program = E.program(application)
  +observed_session = E.session(application)
  +drafts = E.drafts(observed_session)
  edit_found(E.find_draft(drafts, editor), editor, field, value,
    E.from_program(program, observed_session))
def dispatch(state: State, +input: Input) -> Decision:
  State{application, +services} = state
  match input:
    case ApplicationInput{+input}: apply_application(submission_blocked(services, input), input, application, services)
    case ServiceInput{+input}: service_input(input, application, services)
    case EditField{editor, field, value}: application_result(edit_field(editor, field, value, application), services)
    case RemoveAttachment{editor, id}: application_result(edit_attachment(editor, None{}, id, application), services)

def code_scenes(application: E.Application) -> +List<Content.Scene>:
  +observed_session = E.session(application)
  code_blocks = E.code_blocks(observed_session)
  List.foldr(~&2, ~Content.Block, ~(+List<Content.Scene>), ~(block => rest => Content.observe(block) <> rest), code_blocks, Nil{})
def observe(capacity: View.Capacity, state: State) -> Scene:
  State{+application, +observed_state} = state
  access = Services.access(observed_state)
  credential = Services.credential(observed_state)
  settings = Services.settings_open(observed_state)
  appearance = Services.appearance(observed_state)
  transfers = Services.transfers(observed_state)
  preview = Services.preview(observed_state)
  directory_picker = Services.directory_picker(observed_state)
  Scene{View.observe(capacity, application),
    Settings{settings, access, Bool.not(String.eq(credential, "")), appearance,
      ServiceInput{Services.OpenSettings{}}, ServiceInput{Services.CloseSettings{}}, ServiceInput{Services.Connect{}}}, transfers, preview, code_scenes(application), directory_picker}

def step(input: Input, state: State) -> Decision:
  dispatch(state, input)

# Renderers observe a control through this entry, so service readiness and the
# domain command contract cannot disagree about whether activation is allowed.
def control_availability(blocked: Bool, intrinsic: View.Availability) -> View.Availability:
  match blocked:
    case True{}: View.Unavailable{"Connect and finish pending file uploads before submitting"}
    case False{}: intrinsic
def control(state: State, declaration: View.ControlDeclaration) -> Control:
  State{application, services} = state
  View.ControlDeclaration{identity, label, prominence, +input, availability} = declaration
  Control{identity, label, prominence, ApplicationInput{E.UserInput{input}}, control_availability(submission_blocked(services, E.UserInput{input}), availability)}
