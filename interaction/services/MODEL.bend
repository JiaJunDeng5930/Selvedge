import Base
import ../../features/board/MODEL.bend as B
import ../../bendlib/association-map.bend as Finite
import ../INPUT.bend as U

type Appearance is Data:
  SystemAppearance{}
  LightAppearance{}
  DarkAppearance{}

type Access is Data:
  CredentialRequired{}
  Connecting{ticket: Nat}
  Connected{}
  ConnectionLost{reason: String}
  CredentialRejected{reason: String}

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
  State{access: Access, credential: String, settings_open: Bool, appearance: Appearance,
    next: Nat, transfers: +List<Finite.Entry(Transfer)>, preview: Preview, directory_picker: DirectoryPicker}

def access(state: State) -> Access:
  State{access, credential, settings_open, appearance, next, transfers, preview, directory_picker} = state
  access

def with_access(value: Access, state: State) -> State:
  State{access, credential, settings_open, appearance, next, transfers, preview, directory_picker} = state
  State{value, credential, settings_open, appearance, next, transfers, preview, directory_picker}

def with_credential(value: String, state: State) -> State:
  State{access, credential, settings_open, appearance, next, transfers, preview, directory_picker} = state
  State{access, value, settings_open, appearance, next, transfers, preview, directory_picker}

def with_settings_open(value: Bool, state: State) -> State:
  State{access, credential, settings_open, appearance, next, transfers, preview, directory_picker} = state
  State{access, credential, value, appearance, next, transfers, preview, directory_picker}

def with_transfers(value: +List<Finite.Entry(Transfer)>, state: State) -> State:
  State{access, credential, settings_open, appearance, next, transfers, preview, directory_picker} = state
  State{access, credential, settings_open, appearance, next, value, preview, directory_picker}

def credential(state: State) -> String:
  State{access, credential, settings_open, appearance, next, transfers, preview, directory_picker} = state
  credential

def settings_open(state: State) -> Bool:
  State{access, credential, settings_open, appearance, next, transfers, preview, directory_picker} = state
  settings_open

def appearance(state: State) -> Appearance:
  State{access, credential, settings_open, appearance, next, transfers, preview, directory_picker} = state
  appearance

def next(state: State) -> Nat:
  State{access, credential, settings_open, appearance, next, transfers, preview, directory_picker} = state
  next

def transfers(state: State) -> +List<Finite.Entry(Transfer)>:
  State{access, credential, settings_open, appearance, next, transfers, preview, directory_picker} = state
  transfers

def preview(state: State) -> Preview:
  State{access, credential, settings_open, appearance, next, transfers, preview, directory_picker} = state
  preview

def directory_picker(state: State) -> DirectoryPicker:
  State{access, credential, settings_open, appearance, next, transfers, preview, directory_picker} = state
  directory_picker

type Input is Data:
  OpenSettings{}
  CloseSettings{}
  EnterCredential{value: String}
  Connect{}
  Authenticated{ticket: Nat, result: Result<&2, &2, String, Unit>}
  Disconnected{reason: String}
  ChooseAppearance{appearance: Appearance}
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
  SessionReady{}
  Authenticate{ticket: Nat, credential: String}
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
  State{CredentialRequired{}, "", True{}, SystemAppearance{}, 0n, Nil{}, NoPreview{}, NoDirectoryPicker{}}

def connected(access: Access) -> Bool:
  match access:
    case Connected{}: True{}
    case _: False{}

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

def authentication(owned: Bool, state: State, result: Result<&2, &2, String, Unit>) -> Decision:
  match owned:
    case False{}: Decision{state, Nil{}}
    case True{}:
      State{access, credential, settings, appearance, next, transfers, preview, directory_picker} = state
      match result:
        case Done{unit}: Decision{State{Connected{}, "", False{}, appearance, next, transfers, preview, directory_picker}, [SessionReady{}]}
        case Fail{reason}: Decision{State{CredentialRejected{reason}, "", True{}, appearance, next, transfers, preview, directory_picker}, Nil{}}

def expected_access(access: Access, ticket: Nat) -> Bool:
  match access:
    case Connecting{current}: Nat.is_eq(current, ticket)
    case _: False{}

def upload_finished(found: Maybe<&2, Transfer>, state: State, +ticket: Nat,
  result: Result<&2, &2, String, B.Attachment>) -> Decision:
  match found:
    case Some{Uploading{editor, file}}:
      State{access, credential, settings, appearance, next, transfers, preview, directory_picker} = state
      match result:
        case Done{attachment}:
          Decision{State{access, credential, settings, appearance, next, Finite.remove(~Transfer, transfers, ticket), preview, directory_picker}, [AttachToDraft{editor, attachment}]}
        case Fail{reason}:
          Decision{State{access, credential, settings, appearance, next,
            (ticket, UploadFailed{editor, file, reason}) <> Finite.remove(~Transfer, transfers, ticket), preview, directory_picker}, Nil{}}
    case _: Decision{state, Nil{}}

def begin_upload(allowed: Bool, editor: U.Editor, +file: SelectedFile, state: State) -> Decision:
  match allowed:
    case False{}: Decision{state, Nil{}}
    case True{}:
      State{access, credential, settings, appearance, +next, transfers, preview, directory_picker} = state
      Decision{State{access, credential, settings, appearance, (next + 1n : Nat), (next, Uploading{editor, file}) <> transfers, preview, directory_picker}, [Upload{next, file}]}

def retry(found: Maybe<&2, Transfer>, ticket: Nat, state: State) -> Decision:
  match found:
    case Some{UploadFailed{editor, file, reason}}:
      State{+access, credential, settings, appearance, next, transfers, preview, directory_picker} = state
      begin_upload(connected(access), editor, file, State{access, credential, settings, appearance, next, Finite.remove(~Transfer, transfers, ticket), preview, directory_picker})
    case _: Decision{state, Nil{}}

def finish_preview(owned: Bool, state: State, +file: B.Attachment, trigger: String, result: Result<&2, &2, String, String>) -> Decision:
  match owned:
    case False{}: Decision{state, Nil{}}
    case True{}:
      State{access, credential, settings, appearance, next, transfers, preview, directory_picker} = state
      match result:
        case Done{resource}: Decision{State{access, credential, settings, appearance, next, transfers, ReadyPreview{file, resource, passive_image(file), trigger}, directory_picker}, Nil{}}
        case Fail{reason}: Decision{State{access, credential, settings, appearance, next, transfers, FailedPreview{file, reason, trigger}, directory_picker}, Nil{}}

def preview_result(preview: Preview, ticket: Nat, result: Result<&2, &2, String, String>, state: State) -> Decision:
  match preview:
    case LoadingPreview{current, file, trigger}: finish_preview(Nat.is_eq(current, ticket), state, file, trigger, result)
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

def connect(state: State, entered: Bool) -> Decision:
  State{access, credential, settings, appearance, +next, transfers, preview, directory_picker} = state
  match entered:
    case False{}: Decision{State{CredentialRequired{}, "", True{}, appearance, next, transfers, preview, directory_picker}, Nil{}}
    case True{}: Decision{State{Connecting{next}, "", settings, appearance, (next + 1n : Nat), lose_transfers(transfers, "Connection replaced"), NoPreview{}, directory_picker}, [Authenticate{next, credential}]}
def replace_directory(state: State, directory_picker: DirectoryPicker) -> State:
  State{access, credential, settings, appearance, next, transfers, preview, old_picker} = state
  State{access, credential, settings, appearance, next, transfers, preview, directory_picker}

def open_directory(editor: U.Editor, +path: String, +trigger: String, state: State) -> Decision:
  State{access, credential, settings, appearance, +next, transfers, preview, old_picker} = state
  Decision{State{access, credential, settings, appearance, (next + 1n : Nat), transfers, preview,
    LoadingDirectory{next, editor, path, trigger}}, [ReadDirectories{next, path}]}

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

def finish_directory(owned: Bool, ticket: Nat, editor: U.Editor, +path: String, trigger: String,
  result: Result<&2, &2, String, DirectoryCatalog>, state: State) -> Decision:
  match owned:
    case False{}: Decision{state, Nil{}}
    case True{}:
      match result:
        case Done{+catalog}:
          DirectoryCatalog{resolved, parent, entries, truncated} = catalog
          Decision{replace_directory(state, ReadyDirectory{ticket, editor, catalog, resolved, trigger}), Nil{}}
        case Fail{reason}: Decision{replace_directory(state, FailedDirectory{ticket, editor, path, reason, trigger}), Nil{}}

def directory_listed(picker: DirectoryPicker, +ticket: Nat,
  result: Result<&2, &2, String, DirectoryCatalog>, state: State) -> Decision:
  match picker:
    case LoadingDirectory{+current, editor, path, trigger}:
      finish_directory(Nat.is_eq(current, ticket), current, editor, path, trigger, result, state)
    case _: Decision{state, Nil{}}

def choose_directory(picker: DirectoryPicker, state: State) -> Decision:
  match picker:
    case ReadyDirectory{ticket, editor, DirectoryCatalog{path, parent, entries, truncated}, location, trigger}:
      Decision{replace_directory(state, NoDirectoryPicker{}), [DirectoryChosen{editor, path}]}
    case _: Decision{state, Nil{}}

def dispatch(state: State, input: Input) -> Decision:
  State{+access, +credential, settings, appearance, +next, +transfers, +preview, +directory_picker} = state
  match input:
    case OpenDirectoryPicker{editor, path, trigger}: open_directory(editor, path, trigger, State{access, credential, settings, appearance, next, transfers, preview, directory_picker})
    case WriteDirectoryLocation{value}: write_directory(directory_picker, value, State{access, credential, settings, appearance, next, transfers, preview, directory_picker})
    case VisitDirectory{path}: visit_directory(directory_picker, path, State{access, credential, settings, appearance, next, transfers, preview, directory_picker})
    case GoDirectory{}: go_directory(directory_picker, State{access, credential, settings, appearance, next, transfers, preview, directory_picker})
    case DirectoryListed{ticket, result}: directory_listed(directory_picker, ticket, result, State{access, credential, settings, appearance, next, transfers, preview, directory_picker})
    case ChooseDirectory{}: choose_directory(directory_picker, State{access, credential, settings, appearance, next, transfers, preview, directory_picker})
    case CloseDirectoryPicker{}: Decision{State{access, credential, settings, appearance, next, transfers, preview, NoDirectoryPicker{}}, Nil{}}
    case OpenSettings{}: Decision{State{access, credential, True{}, appearance, next, transfers, preview, directory_picker}, Nil{}}
    case CloseSettings{}: Decision{State{access, credential, False{}, appearance, next, transfers, preview, directory_picker}, Nil{}}
    case EnterCredential{value}: Decision{State{access, value, settings, appearance, next, transfers, preview, directory_picker}, Nil{}}
    case Connect{}: connect(State{access, credential, settings, appearance, next, transfers, preview, directory_picker}, Bool.not(String.eq(credential, "")))
    case Authenticated{+ticket, result}: authentication(expected_access(access, ticket), State{access, credential, settings, appearance, next, transfers, preview, directory_picker}, result)
    case Disconnected{+reason}: Decision{State{ConnectionLost{reason}, credential, settings, appearance, next, lose_transfers(transfers, reason), NoPreview{}, directory_picker}, Nil{}}
    case ChooseAppearance{+selected}: Decision{State{access, credential, settings, selected, next, transfers, preview, directory_picker}, [StoreAppearance{selected}]}
    case AddFile{editor, +file}: begin_upload(connected(access), editor, file, State{access, credential, settings, appearance, next, transfers, preview, directory_picker})
    case RetryUpload{+ticket}: retry(Finite.find(~Transfer, transfers, ticket), ticket, State{access, credential, settings, appearance, next, transfers, preview, directory_picker})
    case CancelUpload{+ticket}: Decision{State{access, credential, settings, appearance, next, Finite.remove(~Transfer, transfers, ticket), preview, directory_picker}, [CancelTransfer{ticket}]}
    case Uploaded{+ticket, result}: upload_finished(Finite.find(~Transfer, transfers, ticket), State{access, credential, settings, appearance, next, transfers, preview, directory_picker}, ticket, result)
    case OpenPreview{+file, trigger}: Decision{State{access, credential, settings, appearance, (next + 1n : Nat), transfers, LoadingPreview{next, file, trigger}, directory_picker}, [ReadAttachment{next, file}]}
    case Previewed{+ticket, result}: preview_result(preview, ticket, result, State{access, credential, settings, appearance, next, transfers, preview, directory_picker})
    case ClosePreview{}: Decision{State{access, credential, settings, appearance, next, transfers, NoPreview{}, directory_picker}, Nil{}}
    case Download{+file}: Decision{State{access, credential, settings, appearance, next, transfers, preview, directory_picker}, [DownloadAttachment{file}]}

def step(input: Input, state: State) -> Decision:
  dispatch(state, input)
