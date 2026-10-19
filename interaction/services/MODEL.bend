import ../speech/MODEL.bend as Speech
import Base
import ../../bendlib/categories.bend as Categories
import ../../features/board/MODEL.bend as B
import ../../bendlib/association-map.bend as Finite
import ../INPUT.bend as U

type Appearance is Data:
  SystemAppearance{}
  LightAppearance{}
  DarkAppearance{}

type Access is Data:
  NotConnected{}
  Connecting{ticket: Nat}
  Connected{ticket: Nat}
  ConnectionLost{ticket: Nat, reason: String}

type SelectedFile is Data:
  SelectedFile{handle: String, name: String, mime: String, bytes: U32}

type Transfer is Data:
  Uploading{editor: U.Editor, file: SelectedFile}
  UploadFailed{editor: U.Editor, file: SelectedFile, reason: String}

type Preview is Data:
  NoPreview{}
  LoadingPreview{ticket: Nat, file: B.Attachment, trigger: String}
  ReadyPreview{file: B.Attachment, resource: String, image: Bool, trigger: String}
  FailedPreview{file: B.Attachment, reason: String, trigger: String}

type DirectoryEntry is Data:
  DirectoryEntry{name: String, path: String}

type DirectoryCatalog is Data:
  DirectoryCatalog{path: String, parent: Maybe<&2, String>, entries: +List<DirectoryEntry>, truncated: Bool}

type DirectoryPicker is Data:
  NoDirectoryPicker{}
  LoadingDirectory{ticket: Nat, editor: U.Editor, path: String, trigger: String}
  ReadyDirectory{ticket: Nat, editor: U.Editor, catalog: DirectoryCatalog, location: String, trigger: String}
  FailedDirectory{ticket: Nat, editor: U.Editor, path: String, reason: String, trigger: String}

type State is Data:
  State{access: Access, settings_open: Bool, appearance: Appearance,
    next: Nat, transfers: +List<Finite.Entry(Transfer)>, preview: Preview, directory_picker: DirectoryPicker, speech: Speech.State}

def speech(state: State) -> Speech.State:
  State{access, settings_open, appearance, next, transfers, preview, directory_picker, speech} = state
  speech

def with_speech(value: Speech.State, state: State) -> State:
  State{access, settings_open, appearance, next, transfers, preview, directory_picker, speech} = state
  State{access, settings_open, appearance, next, transfers, preview, directory_picker, value}

def speech_effects(effects: +List<Speech.Effect>) -> +List<Effect>:
  match effects:
    case Nil{}: Nil{}
    case Con{effect, rest}: SpeechEffect{effect} <> speech_effects(rest)

def speech_result(decision: Speech.Decision, state: State) -> Decision:
  Speech.Decision{speech, effects} = decision
  Decision{with_speech(speech, state), speech_effects(effects)}

def access(state: State) -> Access:
  State{access, settings_open, appearance, next, transfers, preview, directory_picker, +speech} = state
  access

def with_access(value: Access, state: State) -> State:
  State{access, settings_open, appearance, next, transfers, preview, directory_picker, +speech} = state
  State{value, settings_open, appearance, next, transfers, preview, directory_picker, speech}

def with_settings_open(value: Bool, state: State) -> State:
  State{access, settings_open, appearance, next, transfers, preview, directory_picker, +speech} = state
  State{access, value, appearance, next, transfers, preview, directory_picker, speech}

def with_transfers(value: +List<Finite.Entry(Transfer)>, state: State) -> State:
  State{access, settings_open, appearance, next, transfers, preview, directory_picker, +speech} = state
  State{access, settings_open, appearance, next, value, preview, directory_picker, speech}

def settings_open(state: State) -> Bool:
  State{access, settings_open, appearance, next, transfers, preview, directory_picker, +speech} = state
  settings_open

def appearance(state: State) -> Appearance:
  State{access, settings_open, appearance, next, transfers, preview, directory_picker, +speech} = state
  appearance

def next(state: State) -> Nat:
  State{access, settings_open, appearance, next, transfers, preview, directory_picker, +speech} = state
  next

def transfers(state: State) -> +List<Finite.Entry(Transfer)>:
  State{access, settings_open, appearance, next, transfers, preview, directory_picker, +speech} = state
  transfers

def preview(state: State) -> Preview:
  State{access, settings_open, appearance, next, transfers, preview, directory_picker, +speech} = state
  preview

def directory_picker(state: State) -> DirectoryPicker:
  State{access, settings_open, appearance, next, transfers, preview, directory_picker, +speech} = state
  directory_picker

type Input is Data:
  SpeechInput{input: Speech.Input}
  OpenSettings{}
  CloseSettings{}
  Connect{}
  Authenticated{ticket: Nat, result: Result<&2, &2, String, Unit>}
  Disconnected{ticket: Nat, reason: String}
  RetryConnection{ticket: Nat}
  ChooseAppearance{appearance: Appearance}
  AppearanceRestored{stored: Maybe<&2, String>}
  AddFile{editor: U.Editor, file: SelectedFile}
  RetryUpload{ticket: Nat}
  CancelUpload{ticket: Nat}
  Uploaded{ticket: Nat, result: Result<&2, &2, String, B.Attachment>}
  OpenPreview{file: B.Attachment, trigger: String}
  Previewed{ticket: Nat, result: Result<&2, &2, String, String>}
  ClosePreview{}
  Download{file: B.Attachment}
  OpenDirectoryPicker{editor: U.Editor, path: String, trigger: String}
  WriteDirectoryLocation{value: String}
  VisitDirectory{path: String}
  GoDirectory{}
  DirectoryListed{ticket: Nat, result: Result<&2, &2, String, DirectoryCatalog>}
  ChooseDirectory{}
  CloseDirectoryPicker{}

type Effect is Data:
  SpeechEffect{effect: Speech.Effect}
  SessionReady{}
  SessionEnded{}
  Authenticate{ticket: Nat}
  ScheduleReconnect{ticket: Nat, delay_ms: Nat}
  StoreAppearance{appearance: Appearance}
  Upload{ticket: Nat, file: SelectedFile}
  CancelTransfer{ticket: Nat}
  AttachToDraft{editor: U.Editor, file: B.Attachment}
  ReadAttachment{ticket: Nat, file: B.Attachment}
  DownloadAttachment{file: B.Attachment}
  ReadDirectories{ticket: Nat, path: String}
  DirectoryChosen{editor: U.Editor, path: String}

type Decision is Data:
  Decision{state: State, effects: +List<Effect>}

def initial() -> State:
  State{NotConnected{}, False{}, SystemAppearance{}, 0n, Nil{}, NoPreview{}, NoDirectoryPicker{}, Speech.initial()}

def connected(access: Access) -> Bool:
  match access:
    case Connected{ticket}: True{}
    case _: False{}

def connection_ticket(value: Access) -> Nat:
  match value:
    case NotConnected{}: 0n
    case Connecting{ticket}: ticket
    case Connected{ticket}: ticket
    case ConnectionLost{ticket, reason}: ticket

def restored_appearance(stored: Maybe<&2, String>) -> Appearance:
  match stored:
    case Some{"LightAppearance"}: LightAppearance{}
    case Some{"DarkAppearance"}: DarkAppearance{}
    case _: SystemAppearance{}

def transfer_editor(transfer: Transfer) -> U.Editor:
  match transfer:
    case Uploading{editor, file}: editor
    case UploadFailed{editor, file, reason}: editor

def blocks(+editor: U.Editor, transfers: +List<Finite.Entry(Transfer)>) -> Bool:
  match transfers:
    case Nil{}: False{}
    case Con{(ticket, +transfer), rest}:
      U.same_editor(editor, transfer_editor(transfer)) || blocks(editor, rest)

def passive_image(file: B.Attachment) -> Bool:
  B.Attachment{id, name, +mime, path, bytes} = file
  String.eq(mime, "image/png") || String.eq(mime, "image/jpeg") || String.eq(mime, "image/gif") || String.eq(mime, "image/webp")

def expected_access(access: Access, ticket: Nat) -> Bool:
  match access:
    case Connecting{current}: Nat.is_eq(current, ticket)
    case _: False{}

type AuthenticationRequest is Data:
  AuthenticationRequest{ticket: Nat, state: State, result: Result<&2, &2, String, Unit>}

def authentication_owned(request: AuthenticationRequest) -> Bool:
  AuthenticationRequest{ticket, state, result} = request
  expected_access(access(state), ticket)

def authentication_calculation(state: State, result: Result<&2, &2, String, Unit>) -> Decision:
  State{+access, settings, appearance, next, transfers, preview, directory_picker, +speech} = state
  match result:
    case Done{unit}: Decision{State{Connected{connection_ticket(access)}, False{}, appearance, next, transfers, preview, directory_picker, speech}, [SessionReady{}]}
    case Fail{reason}: Decision{State{ConnectionLost{connection_ticket(access), reason}, True{}, appearance, next, transfers, preview, directory_picker, speech}, [ScheduleReconnect{connection_ticket(access), 1000n}]}

def authentication(member: Categories.Membership<AuthenticationRequest, Categories.holds(AuthenticationRequest, authentication_owned)>) -> Decision:
  Categories.Membership{AuthenticationRequest{ticket, state, result}, evidence} = member
  authentication_calculation(state, result)

def authentication_admitted(found: Maybe<&1, Categories.Membership<AuthenticationRequest, Categories.holds(AuthenticationRequest, authentication_owned)>>, state: State) -> Decision:
  match found:
    case None{}: Decision{state, Nil{}}
    case Some{member}: authentication(member)


def upload_finished(found: Maybe<&2, Transfer>, state: State, +ticket: Nat,
  result: Result<&2, &2, String, B.Attachment>) -> Decision:
  match found:
    case Some{Uploading{editor, file}}:
      State{access, settings, appearance, next, transfers, preview, directory_picker, +speech} = state
      match result:
        case Done{attachment}:
          Decision{State{access, settings, appearance, next, Finite.remove(~Transfer, transfers, ticket), preview, directory_picker, speech}, [AttachToDraft{editor, attachment}]}
        case Fail{reason}:
          Decision{State{access, settings, appearance, next,
            (ticket, UploadFailed{editor, file, reason}) <> Finite.remove(~Transfer, transfers, ticket), preview, directory_picker, speech}, Nil{}}
    case _: Decision{state, Nil{}}

type UploadRequest is Data:
  UploadRequest{editor: U.Editor, file: SelectedFile, state: State}

def upload_connected(request: UploadRequest) -> Bool:
  UploadRequest{editor, file, state} = request
  connected(access(state))

def upload_calculation(editor: U.Editor, +file: SelectedFile, state: State) -> Decision:
  State{access, settings, appearance, +next, transfers, preview, directory_picker, +speech} = state
  Decision{State{access, settings, appearance, (next + 1n : Nat), (next, Uploading{editor, file}) <> transfers, preview, directory_picker, speech}, [Upload{next, file}]}

def begin_upload(member: Categories.Membership<UploadRequest, Categories.holds(UploadRequest, upload_connected)>) -> Decision:
  Categories.Membership{UploadRequest{editor, file, state}, evidence} = member
  upload_calculation(editor, file, state)

def upload_admitted(found: Maybe<&1, Categories.Membership<UploadRequest, Categories.holds(UploadRequest, upload_connected)>>, state: State) -> Decision:
  match found:
    case None{}: Decision{state, Nil{}}
    case Some{member}: begin_upload(member)

def request_upload(editor: U.Editor, file: SelectedFile, +state: State) -> Decision:
  upload_admitted(Categories.admit(UploadRequest, upload_connected, UploadRequest{editor, file, state}), state)

type UploadRetry is Data:
  UploadRetry{ticket: Nat, editor: U.Editor, file: SelectedFile, state: State}

def retry_connected(request: UploadRetry) -> Bool:
  UploadRetry{ticket, editor, file, state} = request
  connected(access(state))

def retry_upload(member: Categories.Membership<UploadRetry, Categories.holds(UploadRetry, retry_connected)>) -> Decision:
  Categories.Membership{UploadRetry{ticket, editor, file, state}, evidence} = member
  State{access, settings, appearance, next, transfers, preview, directory_picker, +speech} = state
  upload_calculation(editor, file, State{access, settings, appearance, next,
    Finite.remove(~Transfer, transfers, ticket), preview, directory_picker, speech})

def retry_admitted(found: Maybe<&1, Categories.Membership<UploadRetry, Categories.holds(UploadRetry, retry_connected)>>, state: State) -> Decision:
  match found:
    case None{}: Decision{state, Nil{}}
    case Some{member}: retry_upload(member)

def retry(found: Maybe<&2, Transfer>, ticket: Nat, +state: State) -> Decision:
  match found:
    case Some{UploadFailed{editor, file, reason}}:
      retry_admitted(Categories.admit(UploadRetry, retry_connected, UploadRetry{ticket, editor, file, state}), state)
    case _: Decision{state, Nil{}}

type PreviewResult is Data:
  PreviewResult{current: Nat, ticket: Nat, state: State, file: B.Attachment, trigger: String, result: Result<&2, &2, String, String>}

def preview_result_owned(request: PreviewResult) -> Bool:
  PreviewResult{current, ticket, state, file, trigger, result} = request
  Nat.is_eq(current, ticket)

def preview_calculation(state: State, +file: B.Attachment, trigger: String, result: Result<&2, &2, String, String>) -> Decision:
  State{access, settings, appearance, next, transfers, preview, directory_picker, +speech} = state
  match result:
    case Done{resource}: Decision{State{access, settings, appearance, next, transfers, ReadyPreview{file, resource, passive_image(file), trigger}, directory_picker, speech}, Nil{}}
    case Fail{reason}: Decision{State{access, settings, appearance, next, transfers, FailedPreview{file, reason, trigger}, directory_picker, speech}, Nil{}}

def finish_preview(member: Categories.Membership<PreviewResult, Categories.holds(PreviewResult, preview_result_owned)>) -> Decision:
  Categories.Membership{PreviewResult{current, ticket, state, file, trigger, result}, evidence} = member
  preview_calculation(state, file, trigger, result)

def preview_admitted(found: Maybe<&1, Categories.Membership<PreviewResult, Categories.holds(PreviewResult, preview_result_owned)>>, state: State) -> Decision:
  match found:
    case None{}: Decision{state, Nil{}}
    case Some{member}: finish_preview(member)

def preview_result(preview: Preview, ticket: Nat, result: Result<&2, &2, String, String>, +state: State) -> Decision:
  match preview:
    case LoadingPreview{current, file, trigger}: preview_admitted(Categories.admit(PreviewResult, preview_result_owned, PreviewResult{current, ticket, state, file, trigger, result}), state)
    case _: Decision{state, Nil{}}

def lose_transfer(entry: Finite.Entry(Transfer), reason: String) -> Finite.Entry(Transfer):
  (ticket, transfer) = entry
  match transfer:
    case Uploading{editor, file}: (ticket, UploadFailed{editor, file, reason})
    case other: (ticket, other)

def lose_transfers(transfers: +List<Finite.Entry(Transfer)>, +reason: String) -> +List<Finite.Entry(Transfer)>:
  match transfers:
    case Nil{}: Nil{}
    case Con{entry, rest}: lose_transfer(entry, reason) <> lose_transfers(rest, reason)

def connect_calculation(state: State) -> Decision:
  State{access, settings, appearance, +next, transfers, preview, directory_picker, +speech} = state
  Decision{State{Connecting{next}, settings, appearance, (next + 1n : Nat), lose_transfers(transfers, "Connection replaced"), NoPreview{}, directory_picker, speech}, [SessionEnded{}, Authenticate{next}]}

def connect(state: State) -> Decision:
  connect_calculation(state)

def live_connection(value: Access, ticket: Nat) -> Bool:
  match value:
    case Connecting{current}: Nat.is_eq(current, ticket)
    case Connected{current}: Nat.is_eq(current, ticket)
    case _: False{}

def waiting_reconnect(value: Access, ticket: Nat) -> Bool:
  match value:
    case ConnectionLost{current, reason}: Nat.is_eq(current, ticket)
    case _: False{}

def connection_lost(owned: Bool, +ticket: Nat, +reason: String, state: State) -> Decision:
  match owned:
    case False{}: Decision{state, Nil{}}
    case True{}:
      State{access, settings, appearance, next, transfers, preview, directory_picker, +speech} = state
      Decision{State{ConnectionLost{ticket, reason}, settings, appearance, next,
        lose_transfers(transfers, reason), NoPreview{}, directory_picker, speech}, [SessionEnded{}, ScheduleReconnect{ticket, 1000n}]}

def reconnect(owned: Bool, state: State) -> Decision:
  match owned:
    case False{}: Decision{state, Nil{}}
    case True{}: connect(state)

def replace_directory(state: State, directory_picker: DirectoryPicker) -> State:
  State{access, settings, appearance, next, transfers, preview, old_picker, +speech} = state
  State{access, settings, appearance, next, transfers, preview, directory_picker, speech}

def open_directory(editor: U.Editor, +path: String, +trigger: String, state: State) -> Decision:
  State{access, settings, appearance, +next, transfers, preview, old_picker, +speech} = state
  Decision{State{access, settings, appearance, (next + 1n : Nat), transfers, preview,
    LoadingDirectory{next, editor, path, trigger}, speech}, [ReadDirectories{next, path}]}

def visit_directory(picker: DirectoryPicker, path: String, state: State) -> Decision:
  match picker:
    case NoDirectoryPicker{}: Decision{state, Nil{}}
    case LoadingDirectory{ticket, editor, previous, trigger}: open_directory(editor, path, trigger, state)
    case ReadyDirectory{ticket, editor, catalog, location, trigger}: open_directory(editor, path, trigger, state)
    case FailedDirectory{ticket, editor, previous, reason, trigger}: open_directory(editor, path, trigger, state)

def write_directory(picker: DirectoryPicker, value: String, state: State) -> Decision:
  match picker:
    case ReadyDirectory{ticket, editor, catalog, previous, trigger}:
      Decision{replace_directory(state, ReadyDirectory{ticket, editor, catalog, value, trigger}), Nil{}}
    case _: Decision{state, Nil{}}

def go_directory(picker: DirectoryPicker, state: State) -> Decision:
  match picker:
    case ReadyDirectory{ticket, editor, catalog, location, trigger}: open_directory(editor, location, trigger, state)
    case _: Decision{state, Nil{}}

type DirectoryResult is Data:
  DirectoryResult{current: Nat, ticket: Nat, editor: U.Editor, path: String, trigger: String, result: Result<&2, &2, String, DirectoryCatalog>, state: State}

def directory_result_owned(request: DirectoryResult) -> Bool:
  DirectoryResult{current, ticket, editor, path, trigger, result, state} = request
  Nat.is_eq(current, ticket)

def directory_calculation(ticket: Nat, editor: U.Editor, +path: String, trigger: String, result: Result<&2, &2, String, DirectoryCatalog>, state: State) -> Decision:
  match result:
    case Done{+catalog}:
      DirectoryCatalog{resolved, parent, entries, truncated} = catalog
      Decision{replace_directory(state, ReadyDirectory{ticket, editor, catalog, resolved, trigger}), Nil{}}
    case Fail{reason}: Decision{replace_directory(state, FailedDirectory{ticket, editor, path, reason, trigger}), Nil{}}

def finish_directory(member: Categories.Membership<DirectoryResult, Categories.holds(DirectoryResult, directory_result_owned)>) -> Decision:
  Categories.Membership{DirectoryResult{current, ticket, editor, path, trigger, result, state}, evidence} = member
  directory_calculation(current, editor, path, trigger, result, state)

def directory_admitted(found: Maybe<&1, Categories.Membership<DirectoryResult, Categories.holds(DirectoryResult, directory_result_owned)>>, state: State) -> Decision:
  match found:
    case None{}: Decision{state, Nil{}}
    case Some{member}: finish_directory(member)

def directory_listed(picker: DirectoryPicker, +ticket: Nat, result: Result<&2, &2, String, DirectoryCatalog>, +state: State) -> Decision:
  match picker:
    case LoadingDirectory{+current, editor, path, trigger}:
      directory_admitted(Categories.admit(DirectoryResult, directory_result_owned, DirectoryResult{current, ticket, editor, path, trigger, result, state}), state)
    case _: Decision{state, Nil{}}

def choose_directory(picker: DirectoryPicker, state: State) -> Decision:
  match picker:
    case ReadyDirectory{ticket, editor, DirectoryCatalog{path, parent, entries, truncated}, location, trigger}:
      Decision{replace_directory(state, NoDirectoryPicker{}), [DirectoryChosen{editor, path}]}
    case _: Decision{state, Nil{}}

def dispatch(state: State, input: Input) -> Decision:
  State{+access, +settings, +appearance, +next, +transfers, +preview, +directory_picker, +speech} = state
  match input:
    case SpeechInput{input}: speech_result(Speech.step(input, speech), state)
    case OpenDirectoryPicker{editor, path, trigger}: open_directory(editor, path, trigger, State{access, settings, appearance, next, transfers, preview, directory_picker, speech})
    case WriteDirectoryLocation{value}: write_directory(directory_picker, value, State{access, settings, appearance, next, transfers, preview, directory_picker, speech})
    case VisitDirectory{path}: visit_directory(directory_picker, path, State{access, settings, appearance, next, transfers, preview, directory_picker, speech})
    case GoDirectory{}: go_directory(directory_picker, State{access, settings, appearance, next, transfers, preview, directory_picker, speech})
    case DirectoryListed{ticket, result}: directory_listed(directory_picker, ticket, result, State{access, settings, appearance, next, transfers, preview, directory_picker, speech})
    case ChooseDirectory{}: choose_directory(directory_picker, State{access, settings, appearance, next, transfers, preview, directory_picker, speech})
    case CloseDirectoryPicker{}: Decision{State{access, settings, appearance, next, transfers, preview, NoDirectoryPicker{}, speech}, Nil{}}
    case OpenSettings{}: Decision{State{access, True{}, appearance, next, transfers, preview, directory_picker, speech}, Nil{}}
    case CloseSettings{}: Decision{State{access, False{}, appearance, next, transfers, preview, directory_picker, speech}, Nil{}}
    case Connect{}: connect(State{access, settings, appearance, next, transfers, preview, directory_picker, speech})
    case Authenticated{+ticket, result}: authentication_admitted(Categories.admit(AuthenticationRequest, authentication_owned, AuthenticationRequest{ticket, State{access, settings, appearance, next, transfers, preview, directory_picker, speech}, result}), State{access, settings, appearance, next, transfers, preview, directory_picker, speech})
    case Disconnected{+ticket, +reason}: connection_lost(live_connection(access, ticket), ticket, reason, State{access, settings, appearance, next, transfers, preview, directory_picker, speech})
    case RetryConnection{+ticket}: reconnect(waiting_reconnect(access, ticket), State{access, settings, appearance, next, transfers, preview, directory_picker, speech})
    case ChooseAppearance{+selected}: Decision{State{access, settings, selected, next, transfers, preview, directory_picker, speech}, [StoreAppearance{selected}]}
    case AppearanceRestored{stored}: Decision{State{access, settings, restored_appearance(stored), next, transfers, preview, directory_picker, speech}, Nil{}}
    case AddFile{editor, +file}: request_upload(editor, file, State{access, settings, appearance, next, transfers, preview, directory_picker, speech})
    case RetryUpload{+ticket}: retry(Finite.find(~Transfer, transfers, ticket), ticket, State{access, settings, appearance, next, transfers, preview, directory_picker, speech})
    case CancelUpload{+ticket}: Decision{State{access, settings, appearance, next, Finite.remove(~Transfer, transfers, ticket), preview, directory_picker, speech}, [CancelTransfer{ticket}]}
    case Uploaded{+ticket, result}: upload_finished(Finite.find(~Transfer, transfers, ticket), State{access, settings, appearance, next, transfers, preview, directory_picker, speech}, ticket, result)
    case OpenPreview{+file, trigger}: Decision{State{access, settings, appearance, (next + 1n : Nat), transfers, LoadingPreview{next, file, trigger}, directory_picker, speech}, [ReadAttachment{next, file}]}
    case Previewed{+ticket, result}: preview_result(preview, ticket, result, State{access, settings, appearance, next, transfers, preview, directory_picker, speech})
    case ClosePreview{}: Decision{State{access, settings, appearance, next, transfers, NoPreview{}, directory_picker, speech}, Nil{}}
    case Download{+file}: Decision{State{access, settings, appearance, next, transfers, preview, directory_picker, speech}, [DownloadAttachment{file}]}

def step(input: Input, state: State) -> Decision:
  dispatch(state, input)
