import ../bendlib/json.bend as J
import ./speech/MODEL.bend as Speech
import ./services/CONTEXT.bend as Context
import Base
import ../bendlib/categories.bend as Categories
import ./conversation/CODE.bend as Content
import ./conversation/OUTPUT.bend as Live
import ../harness/MODEL.bend as M
import ../harness/transport/command-codec.bend as CommandCodec
import ../features/board/MODEL.bend as B
import ../bendlib/association-map.bend as Finite
import ./INPUT.bend as U
import ./session/MODEL.bend as E
import ./session/PROGRAM.bend as ExperienceProgram
import ./presentation/MODEL.bend as View
import ./submission/FIELDS.bend as Forms
import ./services/MODEL.bend as Services
import ../bendlib/component.bend as C
import ./TYPES.bend as InteractionTypes
import ./presentation/VIEW.bend as View2

def application(state: InteractionTypes.State) -> E.Application:
  InteractionTypes.State{application, services} = state
  application

def services(state: InteractionTypes.State) -> Services.State:
  InteractionTypes.State{application, services} = state
  services

def with_application(value: E.Application, state: InteractionTypes.State) -> InteractionTypes.State:
  InteractionTypes.State{application, services} = state
  InteractionTypes.State{value, services}

def with_services(value: Services.State, state: InteractionTypes.State) -> InteractionTypes.State:
  InteractionTypes.State{application, services} = state
  InteractionTypes.State{application, value}

def from_application(application: E.Application, services: Services.State) -> InteractionTypes.State:
  InteractionTypes.State{application, services}

def initial(program: M.World()) -> InteractionTypes.State:
  InteractionTypes.State{E.initial(program), Services.initial()}

def application_result(decision: E.Decision, services: Services.State) -> InteractionTypes.Decision:
  E.Decision{application, reply, runtime, interaction, durable} = decision
  InteractionTypes.Decision{InteractionTypes.State{application, services}, reply, runtime, interaction, Nil{}, durable}

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

type DirectoryChoice is Data:
  DirectoryChoice{editor: U.Editor, path: String, application: E.Application}

def directory_choice_available(choice: DirectoryChoice) -> Bool:
  DirectoryChoice{editor, path, application} = choice
  accepts_directory(editor, application)

def directory_chosen_calculation(+editor: U.Editor, path: String, +application: E.Application) -> E.Application:
  written = attached(ExperienceProgram.step(E.UserInput{U.EditDraft{editor, U.WriteDirectory{path}}}, application))
  attached(ExperienceProgram.step(E.UserInput{U.EditDraft{editor, U.ConfirmDirectory{}}}, written))

def directory_chosen_accepted(member: Categories.Membership<DirectoryChoice, Categories.holds(DirectoryChoice, directory_choice_available)>) -> E.Application:
  Categories.Membership{DirectoryChoice{editor, path, application}, evidence} = member
  directory_chosen_calculation(editor, path, application)

def directory_choice_admitted(found: Maybe<&1, Categories.Membership<DirectoryChoice, Categories.holds(DirectoryChoice, directory_choice_available)>>, application: E.Application) -> E.Application:
  match found:
    case None{}: application
    case Some{member}: directory_chosen_accepted(member)

def directory_chosen(+editor: U.Editor, path: String, +application: E.Application) -> E.Application:
  directory_choice_admitted(Categories.admit(DirectoryChoice, directory_choice_available, DirectoryChoice{editor, path, application}), application)

def service_effects(effects: +List<Services.Effect>, +application: E.Application) -> E.Application:
  match effects:
    case Nil{}: application
    case Con{Services.AttachToDraft{editor, +file}, rest}:
      service_effects(rest, attached(edit_attachment(editor, Some{file}, file_id(file), application)))
    case Con{Services.DirectoryChosen{editor, path}, rest}: service_effects(rest, directory_chosen(editor, path, application))
    case Con{Services.SessionReady{}, rest}: service_effects(rest, application)
    case Con{Services.SessionEnded{}, rest}: service_effects(rest, attached(E.observe_preview(Live.ConnectionEnded{}, application)))
    case Con{other, rest}: service_effects(rest, application)

def external_effect(effect: Services.Effect) -> Bool:
  match effect:
    case Services.AttachToDraft{editor, file}: False{}
    case Services.DirectoryChosen{editor, path}: False{}
    case Services.SessionReady{}: False{}
    case Services.SessionEnded{}: False{}
    case _: True{}

def application_result_with_services(decision: E.Decision, services: Services.State, effects: +List<Services.Effect>) -> InteractionTypes.Decision:
  E.Decision{application, reply, runtime, interaction, durable} = decision
  InteractionTypes.Decision{InteractionTypes.State{application, services}, reply, runtime, interaction, effects, durable}

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

def refresh_directory_services(effects: +List<Services.Effect>, decision: E.Decision) -> E.Decision:
  match effects:
    case Nil{}: decision
    case Con{Services.DirectoryChosen{U.NewTaskEditor{work}, path}, rest}: E.observe_workspace_git(decision)
    case Con{other, rest}: refresh_directory_services(rest, decision)

def service_result(decision: Services.Decision, application: E.Application) -> InteractionTypes.Decision:
  Services.Decision{services, +effects} = decision
  application_result_with_services(refresh_directory_services(effects, service_attention(E.unchanged(service_effects(effects, application)), effects)), services,
    List.filter(~Services.Effect, external_effect, effects))

def command_offline(command: Maybe<&2, M.Command>, access: Services.Access) -> Bool:
  match command:
    case Some{command}: Bool.not(Services.connected(access))
    case None{}: False{}

def obstruction_present(obstruction: Maybe<&2, String>) -> Bool:
  match obstruction:
    case None{}: False{}
    case Some{reason}: True{}

def submit_obstruction(connected: Bool, blocked: Bool) -> Maybe<&2, String>:
  match connected blocked:
    case False{} _: Some{"Connect before submitting"}
    case True{} True{}: Some{"Finish this editor's file uploads before submitting"}
    case True{} False{}: None{}

def action_obstruction(blocked: Bool) -> Maybe<&2, String>:
  match blocked:
    case True{}: Some{"Connect before running this action"}
    case False{}: None{}

def submission_obstruction_access(access: Services.Access, transfers: +List<Finite.Entry(Services.Transfer)>, input: E.Input) -> Maybe<&2, String>:
  match input:
    case E.UserInput{U.Activate{U.Submit{editor}}}: submit_obstruction(Services.connected(access), Services.blocks(editor, transfers))
    case E.UserInput{U.Activate{U.RetryWorkspace{editor}}}: submit_obstruction(Services.connected(access), Services.blocks(editor, transfers))
    case E.UserInput{U.Activate{U.ConfirmAction{}}}: action_obstruction(Bool.not(Services.connected(access)))
    case E.UserInput{U.Activate{action}}: action_obstruction(command_offline(U.direct_command(action), access))
    case _: None{}

def submission_blocked_access(access: Services.Access, transfers: +List<Finite.Entry(Services.Transfer)>, input: E.Input) -> Bool:
  obstruction_present(submission_obstruction_access(access, transfers, input))

def submission_blocked(+services: Services.State, input: E.Input) -> Bool:
  submission_blocked_access(Services.access(services), Services.transfers(services), input)

type ApplicationRequest is Data:
  ApplicationRequest{input: E.Input, application: E.Application, services: Services.State}

def application_available(request: ApplicationRequest) -> Bool:
  ApplicationRequest{input, application, services} = request
  Bool.not(submission_blocked(services, input))

def service_decision_state(decision: Services.Decision) -> Services.State:
  Services.Decision{state, effects} = decision
  state

def application_services(input: E.Input, services: Services.State) -> Services.State:
  match input:
    case E.UserInput{U.Activate{U.EditTitlePrompts{}}}: service_decision_state(Services.step(Services.CloseSettings{}, services))
    case _: services

def apply_application(member: Categories.Membership<ApplicationRequest, Categories.holds(ApplicationRequest, application_available)>) -> InteractionTypes.Decision:
  Categories.Membership{ApplicationRequest{+input, application, services}, evidence} = member
  application_result(ExperienceProgram.step(input, application), application_services(input, services))

def application_admitted(found: Maybe<&1, Categories.Membership<ApplicationRequest, Categories.holds(ApplicationRequest, application_available)>>, application: E.Application, services: Services.State) -> InteractionTypes.Decision:
  match found:
    case None{}: application_result(E.refuse(application, "Connect and finish pending file uploads before submitting"), services)
    case Some{member}: apply_application(member)

def is_card_draft(found: Maybe<&2, U.Draft>) -> Bool:
  match found:
    case Some{U.Draft{revision, U.Card{id, version, value, assist, profile, keep_open}, feedback, directory_entry}}: True{}
    case _: False{}

def accepts_files(editor: U.Editor, application: E.Application) -> Bool:
  +observed_session = E.session(application)
  drafts = E.drafts(observed_session)
  is_card_draft(E.find_draft(drafts, editor))

type ServiceRequest is Data:
  ServiceRequest{input: Services.Input, application: E.Application, services: Services.State}

def file_request_available(request: ServiceRequest) -> Bool:
  ServiceRequest{input, application, services} = request
  match input:
    case Services.AddFile{editor, file}: accepts_files(editor, application)
    case _: False{}

def directory_request_available(request: ServiceRequest) -> Bool:
  ServiceRequest{input, application, services} = request
  match input:
    case Services.OpenDirectoryPicker{editor, path, trigger}: accepts_directory(editor, application)
    case _: False{}

def add_allowed(member: Categories.Membership<ServiceRequest, Categories.holds(ServiceRequest, file_request_available)>) -> InteractionTypes.Decision:
  Categories.Membership{ServiceRequest{input, application, services}, evidence} = member
  service_result(Services.step(input, services), application)

def directory_allowed(member: Categories.Membership<ServiceRequest, Categories.holds(ServiceRequest, directory_request_available)>) -> InteractionTypes.Decision:
  Categories.Membership{ServiceRequest{input, application, services}, evidence} = member
  service_result(Services.step(input, services), application)

def file_request_admitted(found: Maybe<&1, Categories.Membership<ServiceRequest, Categories.holds(ServiceRequest, file_request_available)>>, application: E.Application, services: Services.State) -> InteractionTypes.Decision:
  match found:
    case Some{member}: add_allowed(member)
    case None{}: application_result(E.refuse(application, "Attachments belong to a card draft"), services)

def directory_request_admitted(found: Maybe<&1, Categories.Membership<ServiceRequest, Categories.holds(ServiceRequest, directory_request_available)>>, application: E.Application, services: Services.State) -> InteractionTypes.Decision:
  match found:
    case Some{member}: directory_allowed(member)
    case None{}: application_result(E.refuse(application, "The workspace editor is not available"), services)

def speech_draft(application: E.Application, editor: U.Editor) -> Maybe<&2, U.Draft>:
  E.find_draft(E.drafts(E.session(application)), editor)

def speech_text(body: U.Body) -> Maybe<&2, String>:
  match body:
    case U.NewTask{text, profile, reasoning, context, worktree, work}: Some{U.text(text)}
    case U.Message{task, text, delivery}: Some{U.text(text)}
    case _: None{}

def speech_insertion(append: Bool, +old: String, text: String, start: Nat, end: Nat) -> String:
  match append:
    case True{}: old ++ text
    case False{}: String.take(old, start) ++ text ++ String.drop(old, end)

def insert_speech_admitted(found: Maybe<&2, String>, accepted: Bool, editor: U.Editor, text: String, append: Bool, start: Nat, end: Nat, application: E.Application, +services: Services.State) -> InteractionTypes.Decision:
  match found accepted:
    case Some{old} True{}:
      application_result(apply_edit(Some{U.WriteMessage{U.Text{speech_insertion(append, old, text, start, end)}}}, editor, application),
        Services.with_speech(Speech.with_activity(Speech.Idle{}, Services.speech(services)), services))
    case _ _: application_result(E.unchanged(application), services)

def speech_new_command(body: U.Body) -> J.Json:
  match body:
    case U.NewTask{message, profile, reasoning, context, create_worktree, work}:
      CommandCodec.command_json(M.CreateIdle{profile, reasoning, Context.settings(context), work, create_worktree})
    case _: J.Null{}

def insert_speech_text(found: Maybe<&2, String>, current: Nat, target: Speech.Target, text: String, +append: Bool, +application: E.Application, services: Services.State) -> InteractionTypes.Decision:
  Speech.Target{+editor, revision, start, end} = target
  insert_speech_admitted(found, (append || Nat.is_eq(current, revision)) && Bool.not(E.busy(E.pending(E.session(application)), editor)), editor, text, append, start, end, application, services)

def speech_begin_new_found(found: Maybe<&2, U.Draft>, +application: E.Application, +services: Services.State) -> InteractionTypes.Decision:
  match found:
    case Some{U.Draft{revision, U.NewTask{message, profile, reasoning, context, create_worktree, +work}, feedback, directory_entry}}:
      service_result(Services.step(Services.SpeechInput{Speech.BeginNewVoice{U.NewTaskEditor{work}, speech_new_command(U.NewTask{message, profile, reasoning, context, create_worktree, work})}}, services), application)
    case _: application_result(E.refuse(application, "Open a new task composer to start voice"), services)

def insert_speech_found(found: Maybe<&2, U.Draft>, target: Speech.Target, text: String, append: Bool, +application: E.Application, +services: Services.State) -> InteractionTypes.Decision:
  match found:
    case Some{U.Draft{current, body, feedback, directory_entry}}:
      insert_speech_text(speech_text(body), current, target, text, append, application, services)
    case None{}: application_result(E.unchanged(application), services)

def insert_speech_activity(activity: Speech.Activity, append: Bool, +application: E.Application, services: Services.State) -> InteractionTypes.Decision:
  match activity:
    case Speech.Retained{Speech.Target{+editor, +revision, +start, +end}, text}:
      insert_speech_found(speech_draft(application, editor), Speech.Target{editor, revision, start, end}, text, append, application, services)
    case _: application_result(E.unchanged(application), services)

def insert_speech(append: Bool, +application: E.Application, +services: Services.State) -> InteractionTypes.Decision:
  insert_speech_activity(Speech.activity(Services.speech(services)), append, application, services)

def speech_completion_owned(current: Bool, ticket: Nat, text: String, +application: E.Application, services: Services.State) -> InteractionTypes.Decision:
  match current:
    case False{}: application_result(E.unchanged(application), services)
    case True{}:
      insert_speech(False{}, application, service_decision_state(Services.step(Services.SpeechInput{Speech.Transcribed{ticket, text}}, services)))

def speech_completion_activity(activity: Speech.Activity, +ticket: Nat, text: String, application: E.Application, services: Services.State) -> InteractionTypes.Decision:
  match activity:
    case Speech.Transcribing{current, target}:
      speech_completion_owned(Nat.is_eq(current, ticket), ticket, text, application, services)
    case _: application_result(E.unchanged(application), services)

def speech_completion(+ticket: Nat, text: String, +application: E.Application, +services: Services.State) -> InteractionTypes.Decision:
  speech_completion_activity(Speech.activity(Services.speech(services)), ticket, text, application, services)

def speech_task_created(current: Bool, ticket: Nat, +task: Nat, application: E.Application, services: Services.State) -> InteractionTypes.Decision:
  match current:
    case False{}: application_result(E.unchanged(application), services)
    case True{}: service_result(Services.step(Services.SpeechInput{Speech.TaskCreated{ticket, task}}, services), attached(ExperienceProgram.step(E.UserInput{U.Activate{U.Navigate{U.Conversation{task}}}}, application)))

def speech_input(input: Speech.Input, +application: E.Application, +services: Services.State) -> InteractionTypes.Decision:
  match input:
    case Speech.Transcribed{ticket, text}: speech_completion(ticket, text, application, services)
    case Speech.InsertTranscript{}: insert_speech(True{}, application, services)
    case Speech.BeginNewVoice{editor, command}:
      speech_begin_new_found(speech_draft(application, editor) , application, services)
    case Speech.TaskCreated{+ticket, +task}:
      speech_task_created(Speech.owned(Speech.activity(Services.speech(services)), ticket), ticket, task, application, services)
    case other: service_result(Services.step(Services.SpeechInput{other}, services), application)

def service_input(input: Services.Input, +application: E.Application, +services: Services.State) -> InteractionTypes.Decision:
  match input:
    case Services.SpeechInput{input}: speech_input(input, application, services)
    case Services.OpenDirectoryPicker{+editor, path, trigger}:
      directory_request_admitted(Categories.admit(ServiceRequest, directory_request_available, ServiceRequest{Services.OpenDirectoryPicker{editor, path, trigger}, application, services}), application, services)
    case Services.AddFile{+editor, file}:
      file_request_admitted(Categories.admit(ServiceRequest, file_request_available, ServiceRequest{Services.AddFile{editor, file}, application, services}), application, services)
    case Services.OpenSettings{}: service_result(Services.step(Services.OpenSettings{}, services), E.advance_selection(E.consume_global_navigation(application)))
    case Services.CloseSettings{}: service_result(Services.step(Services.CloseSettings{}, services), E.advance_selection(application))
    case other: service_result(Services.step(other, services), application)

def edit_body(body: U.Body, editor: U.Editor, field: Forms.Field, value: Forms.Value, +application: E.Application) -> E.Decision:
  +program = E.program(application)
  session = E.session(application)
  apply_edit(Forms.edit_for(body, field, value, program), editor, E.from_program(program, session))

type FieldRequest is Data:
  FieldRequest{body: U.Body, editor: U.Editor, field: Forms.Field, value: Forms.Value, application: E.Application}

def field_request_exposed(request: FieldRequest) -> Bool:
  FieldRequest{body, editor, field, value, application} = request
  Forms.exposed(body, field)

def edit_exposed(member: Categories.Membership<FieldRequest, Categories.holds(FieldRequest, field_request_exposed)>) -> E.Decision:
  Categories.Membership{FieldRequest{body, editor, field, value, application}, evidence} = member
  edit_body(body, editor, field, value, application)

def field_request_admitted(found: Maybe<&1, Categories.Membership<FieldRequest, Categories.holds(FieldRequest, field_request_exposed)>>, application: E.Application) -> E.Decision:
  match found:
    case None{}: E.refuse(application, "This field is not part of this editor")
    case Some{member}: edit_exposed(member)

def edit_found(found: Maybe<&2, U.Draft>, editor: U.Editor, +field: Forms.Field, value: Forms.Value, +application: E.Application) -> E.Decision:
  match found:
    case None{}: E.refuse(application, "The editor is not open")
    case Some{U.Draft{revision, +body, feedback, directory_entry}}: field_request_admitted(Categories.admit(FieldRequest, field_request_exposed, FieldRequest{body, editor, field, value, application}), application)

def edit_field(+editor: U.Editor, field: Forms.Field, value: Forms.Value, +application: E.Application) -> E.Decision:
  program = E.program(application)
  +observed_session = E.session(application)
  +drafts = E.drafts(observed_session)
  edit_found(E.find_draft(drafts, editor), editor, field, value,
    E.from_program(program, observed_session))

def dispatch(state: InteractionTypes.State, +input: InteractionTypes.Input) -> InteractionTypes.Decision:
  InteractionTypes.State{+application, +services} = state
  match input:
    case InteractionTypes.Interactive{input}: application_result(ExperienceProgram.step(E.InteractiveInput{input}, application), services)
    case InteractionTypes.ApplicationInput{+input}: application_admitted(Categories.admit(ApplicationRequest, application_available, ApplicationRequest{input, application, services}), application, services)
    case InteractionTypes.ServiceInput{+input}: service_input(input, application, services)
    case InteractionTypes.EditField{editor, field, value}: application_result(edit_field(editor, field, value, application), services)
    case InteractionTypes.RemoveAttachment{editor, id}: application_result(edit_attachment(editor, None{}, id, application), services)

def code_scenes(application: E.Application) -> +List<Content.Scene>:
  +observed_session = E.session(application)
  code_blocks = E.code_blocks(observed_session)
  List.foldr(~&2, ~Content.Block, ~(+List<Content.Scene>), ~(block => rest => Content.observe(block) <> rest), code_blocks, Nil{})

def observe(capacity: View.Capacity, state: InteractionTypes.State) -> InteractionTypes.Scene:
  InteractionTypes.State{+application, +observed_state} = state
  access = Services.access(observed_state)
  settings = Services.settings_open(observed_state)
  appearance = Services.appearance(observed_state)
  transfers = Services.transfers(observed_state)
  preview = Services.preview(observed_state)
  directory_picker = Services.directory_picker(observed_state)
  InteractionTypes.Scene{View2.observe(capacity, application),
    InteractionTypes.Settings{settings, access, appearance,
      InteractionTypes.ServiceInput{Services.OpenSettings{}}, InteractionTypes.ServiceInput{Services.CloseSettings{}}, InteractionTypes.ServiceInput{Services.Connect{}}}, transfers, preview, code_scenes(application), directory_picker}

def step(input: InteractionTypes.Input, state: InteractionTypes.State) -> InteractionTypes.Decision:
  dispatch(state, input)

# Renderers observe a control through this entry, so service readiness and the
# domain command contract cannot disagree about whether activation is allowed.

def control_availability(obstruction: Maybe<&2, String>, intrinsic: View.Availability) -> View.Availability:
  match obstruction:
    case Some{reason}: View.Unavailable{reason}
    case None{}: intrinsic

def control(state: InteractionTypes.State, declaration: View.ControlDeclaration) -> InteractionTypes.Control:
  InteractionTypes.State{application, +services} = state
  View.ControlDeclaration{identity, label, prominence, +input, availability} = declaration
  InteractionTypes.Control{identity, label, prominence, InteractionTypes.ApplicationInput{E.UserInput{input}}, control_availability(submission_obstruction_access(Services.access(services), Services.transfers(services), E.UserInput{input}), availability)}

def runtime(decision: InteractionTypes.Decision) -> M.Decision():
  InteractionTypes.Decision{+observed_state, reply, effects, interaction, service, durable} = decision
  +observed_application = application(observed_state)
  program = E.program(observed_application)
  C.Decision{program, reply, effects}
