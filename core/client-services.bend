import Base
import ../BOARD.bend as B
import ../bendlib/association-map.bend as Finite
import ./user-input.bend as U

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

type File is Data:
  File{handle: String, name: String, mime: String, bytes: U32}

type Transfer is Data:
  Uploading{editor: U.Editor, file: File}
  UploadFailed{editor: U.Editor, file: File, reason: String}

type Preview is Data:
  NoPreview{}
  LoadingPreview{ticket: Nat, file: B.Attachment, trigger: String}
  ReadyPreview{file: B.Attachment, resource: String, image: Bool, trigger: String}
  FailedPreview{file: B.Attachment, reason: String, trigger: String}

type State is Data:
  State{access: Access, credential: String, settings_open: Bool, appearance: Appearance,
    next: Nat, transfers: +List<Finite.Entry(Transfer)>, preview: Preview}

type Input is Data:
  OpenSettings{}
  CloseSettings{}
  EnterCredential{value: String}
  Connect{}
  Authenticated{ticket: Nat, result: Result<&2, &2, String, Unit>}
  Disconnected{reason: String}
  ChooseAppearance{appearance: Appearance}
  AddFile{editor: U.Editor, file: File}
  RetryUpload{ticket: Nat}
  CancelUpload{ticket: Nat}
  Uploaded{ticket: Nat, result: Result<&2, &2, String, B.Attachment>}
  OpenPreview{file: B.Attachment, trigger: String}
  Previewed{ticket: Nat, result: Result<&2, &2, String, String>}
  ClosePreview{}
  Download{file: B.Attachment}

type Effect is Data:
  Authenticate{ticket: Nat, credential: String}
  StoreAppearance{appearance: Appearance}
  Upload{ticket: Nat, file: File}
  CancelTransfer{ticket: Nat}
  AttachToDraft{editor: U.Editor, file: B.Attachment}
  ReadAttachment{ticket: Nat, file: B.Attachment}
  DownloadAttachment{file: B.Attachment}

type Decision is Data:
  Decision{state: State, effects: +List<Effect>}

def initial() -> State:
  State{CredentialRequired{}, "", True{}, SystemAppearance{}, 0n, Nil{}, NoPreview{}}

def connected(access: Access) -> Bool:
  match access:
    case Connected{}: True{}
    case _: False{}

def transfer_editor(transfer: Transfer) -> U.Editor:
  match transfer:
    case Uploading{editor, file}: editor
    case UploadFailed{editor, file, reason}: editor

def uploading(transfer: Transfer) -> Bool:
  match transfer:
    case Uploading{editor, file}: True{}
    case _: False{}

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
      State{access, credential, settings, appearance, next, transfers, preview} = state
      match result:
        case Done{unit}: Decision{State{Connected{}, "", False{}, appearance, next, transfers, preview}, Nil{}}
        case Fail{reason}: Decision{State{CredentialRejected{reason}, "", True{}, appearance, next, transfers, preview}, Nil{}}

def expected_access(access: Access, ticket: Nat) -> Bool:
  match access:
    case Connecting{current}: Nat.is_eq(current, ticket)
    case _: False{}

def upload_finished(found: Maybe<&2, Transfer>, state: State, +ticket: Nat,
  result: Result<&2, &2, String, B.Attachment>) -> Decision:
  match found:
    case Some{Uploading{editor, file}}:
      State{access, credential, settings, appearance, next, transfers, preview} = state
      match result:
        case Done{attachment}:
          Decision{State{access, credential, settings, appearance, next, Finite.remove(~Transfer, transfers, ticket), preview}, [AttachToDraft{editor, attachment}]}
        case Fail{reason}:
          Decision{State{access, credential, settings, appearance, next,
            (ticket, UploadFailed{editor, file, reason}) <> Finite.remove(~Transfer, transfers, ticket), preview}, Nil{}}
    case _: Decision{state, Nil{}}

def begin_upload(allowed: Bool, editor: U.Editor, +file: File, state: State) -> Decision:
  match allowed:
    case False{}: Decision{state, Nil{}}
    case True{}:
      State{access, credential, settings, appearance, +next, transfers, preview} = state
      Decision{State{access, credential, settings, appearance, (next + 1n : Nat), (next, Uploading{editor, file}) <> transfers, preview}, [Upload{next, file}]}

def retry(found: Maybe<&2, Transfer>, ticket: Nat, state: State) -> Decision:
  match found:
    case Some{UploadFailed{editor, file, reason}}:
      State{+access, credential, settings, appearance, next, transfers, preview} = state
      begin_upload(connected(access), editor, file, State{access, credential, settings, appearance, next, Finite.remove(~Transfer, transfers, ticket), preview})
    case _: Decision{state, Nil{}}

def finish_preview(owned: Bool, state: State, +file: B.Attachment, trigger: String, result: Result<&2, &2, String, String>) -> Decision:
  match owned:
    case False{}: Decision{state, Nil{}}
    case True{}:
      State{access, credential, settings, appearance, next, transfers, preview} = state
      match result:
        case Done{resource}: Decision{State{access, credential, settings, appearance, next, transfers, ReadyPreview{file, resource, passive_image(file), trigger}}, Nil{}}
        case Fail{reason}: Decision{State{access, credential, settings, appearance, next, transfers, FailedPreview{file, reason, trigger}}, Nil{}}

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
  State{access, credential, settings, appearance, +next, transfers, preview} = state
  match entered:
    case False{}: Decision{State{CredentialRequired{}, "", True{}, appearance, next, transfers, preview}, Nil{}}
    case True{}: Decision{State{Connecting{next}, "", settings, appearance, (next + 1n : Nat), lose_transfers(transfers, "Connection replaced"), NoPreview{}}, [Authenticate{next, credential}]}
def dispatch(state: State, input: Input) -> Decision:
  State{+access, +credential, settings, appearance, +next, +transfers, +preview} = state
  match input:
    case OpenSettings{}: Decision{State{access, credential, True{}, appearance, next, transfers, preview}, Nil{}}
    case CloseSettings{}: Decision{State{access, credential, False{}, appearance, next, transfers, preview}, Nil{}}
    case EnterCredential{value}: Decision{State{access, value, settings, appearance, next, transfers, preview}, Nil{}}
    case Connect{}: connect(State{access, credential, settings, appearance, next, transfers, preview}, Bool.not(String.eq(credential, "")))
    case Authenticated{+ticket, result}: authentication(expected_access(access, ticket), State{access, credential, settings, appearance, next, transfers, preview}, result)
    case Disconnected{+reason}: Decision{State{ConnectionLost{reason}, credential, settings, appearance, next, lose_transfers(transfers, reason), NoPreview{}}, Nil{}}
    case ChooseAppearance{+selected}: Decision{State{access, credential, settings, selected, next, transfers, preview}, [StoreAppearance{selected}]}
    case AddFile{editor, +file}: begin_upload(connected(access), editor, file, State{access, credential, settings, appearance, next, transfers, preview})
    case RetryUpload{+ticket}: retry(Finite.find(~Transfer, transfers, ticket), ticket, State{access, credential, settings, appearance, next, transfers, preview})
    case CancelUpload{+ticket}: Decision{State{access, credential, settings, appearance, next, Finite.remove(~Transfer, transfers, ticket), preview}, [CancelTransfer{ticket}]}
    case Uploaded{+ticket, result}: upload_finished(Finite.find(~Transfer, transfers, ticket), State{access, credential, settings, appearance, next, transfers, preview}, ticket, result)
    case OpenPreview{+file, trigger}: Decision{State{access, credential, settings, appearance, (next + 1n : Nat), transfers, LoadingPreview{next, file, trigger}}, [ReadAttachment{next, file}]}
    case Previewed{+ticket, result}: preview_result(preview, ticket, result, State{access, credential, settings, appearance, next, transfers, preview})
    case ClosePreview{}: Decision{State{access, credential, settings, appearance, next, transfers, NoPreview{}}, Nil{}}
    case Download{+file}: Decision{State{access, credential, settings, appearance, next, transfers, preview}, [DownloadAttachment{file}]}

def step(input: Input, state: State) -> Decision:
  dispatch(state, input)
