import ../experience/PROGRAM.bend as UX
import ../experience/MODEL.bend as Experience
import ../submission/FIELDS.bend as Forms
import Base
import ../INPUT.bend as U
import ../../bendlib/json.bend as J

type Connection is Data:
  Connection{id: String, label: String, asr: Bool, voice: Bool}

type Target is Data:
  Target{editor: U.Editor, revision: Nat, start: Nat, end: Nat}

type Activity is Data:
  Idle{}
  Acquiring{ticket: Nat, editor: U.Editor, revision: Nat}
  Recording{ticket: Nat, target: Target}
  Transcribing{ticket: Nat, target: Target}
  Retained{target: Target, text: String}
  CreatingTask{ticket: Nat}
  ConnectingVoice{ticket: Nat, task: Nat}
  Voice{ticket: Nat, task: Nat, input_muted: Bool, output_muted: Bool}

type State is Data:
  State{connections: +List<Connection>, selected: Maybe<&2, String>, next: Nat,
    activity: Activity, notice: String, live_text: String}

type Input is Data:
  Authorize{}
  Refresh{}
  Capabilities{connections: +List<Connection>}
  CapabilitiesFailed{reason: String}
  Select{connection: String}
  BeginDictation{editor: U.Editor, revision: Nat}
  Captured{ticket: Nat, start: Nat, end: Nat}
  FinishDictation{}
  Transcribed{ticket: Nat, text: String}
  InsertTranscript{}
  DismissTranscript{}
  BeginVoice{task: Nat}
  BeginNewVoice{editor: U.Editor, command: J.Json}
  TaskCreated{ticket: Nat, task: Nat}
  VoiceReady{ticket: Nat}
  LiveText{ticket: Nat, text: String}
  ToggleInputMute{}
  ToggleOutputMute{}
  Cancel{}
  Failed{ticket: Nat, reason: String}
  Ended{ticket: Nat, reason: String}
  Released{}

type Effect is Data:
  BeginAudioLogin{}
  LoadCapabilities{}
  Record{ticket: Nat, owner: String}
  Transcribe{ticket: Nat, connection: String}
  Release{ticket: Nat}
  CreateTask{ticket: Nat, command: J.Json}
  ConnectVoice{ticket: Nat, connection: String, task: Nat}
  SetInputMute{ticket: Nat, muted: Bool}
  SetOutputMute{ticket: Nat, muted: Bool}

type Decision is Data:
  Decision{state: State, effects: +List<Effect>}

def initial() -> State:
  State{Nil{}, None{}, 0n, Idle{}, "", ""}

def activity(+state: State) -> Activity:
  State{connections, selected, next, activity, notice, live_text} = state
  activity

def with_activity(+value: Activity, +state: State) -> State:
  State{connections, selected, next, activity, notice, live_text} = state
  State{connections, selected, next, value, notice, live_text}

def connections(+state: State) -> +List<Connection>:
  State{connections, selected, next, activity, notice, live_text} = state
  connections

def selected(+state: State) -> Maybe<&2, String>:
  State{connections, selected, next, activity, notice, live_text} = state
  selected

def notice(+state: State) -> String:
  State{connections, selected, next, activity, notice, live_text} = state
  notice

def live_text(+state: State) -> String:
  State{connections, selected, next, activity, notice, live_text} = state
  live_text

def connection_enabled(+voice: Bool, asr: Bool, realtime: Bool) -> Bool:
  (voice && realtime) || (Bool.not(voice) && asr)

def activity_free(activity: Activity) -> Bool:
  match activity:
    case Idle{}: True{}
    case _: False{}

def first(+values: +List<Connection>) -> Maybe<&2, String>:
  match values:
    case Nil{}: None{}
    case Con{Connection{id, label, asr, voice}, rest}: Some{id}

def owned(+activity: Activity, +ticket: Nat) -> Bool:
  match activity:
    case Acquiring{current, editor, revision}: Nat.is_eq(current, ticket)
    case Recording{current, target}: Nat.is_eq(current, ticket)
    case Transcribing{current, target}: Nat.is_eq(current, ticket)
    case CreatingTask{current}: Nat.is_eq(current, ticket)
    case ConnectingVoice{current, task}: Nat.is_eq(current, ticket)
    case Voice{current, task, input_muted, output_muted}: Nat.is_eq(current, ticket)
    case _: False{}

def release(+activity: Activity) -> +List<Effect>:
  match activity:
    case Acquiring{ticket, editor, revision}: [Release{ticket}]
    case Recording{ticket, target}: [Release{ticket}]
    case Transcribing{ticket, target}: [Release{ticket}]
    case CreatingTask{ticket}: [Release{ticket}]
    case ConnectingVoice{ticket, task}: [Release{ticket}]
    case Voice{ticket, task, input_muted, output_muted}: [Release{ticket}]
    case _: Nil{}

def begin_voice(+allowed: Bool, +task: Nat, +state: State) -> Decision:
  match allowed state:
    case True{} State{connections, Some{+connection}, +next, activity, notice, live_text}:
      Decision{State{connections, Some{connection}, (next + 1n : Nat), ConnectingVoice{next, task}, "", ""}, [ConnectVoice{next, connection, task}]}
    case _ state: Decision{state, Nil{}}

def created(+current: Bool, +ticket: Nat, +task: Nat, +state: State) -> Decision:
  match current state:
    case True{} State{connections, Some{+connection}, next, activity, notice, live_text}:
      Decision{State{connections, Some{connection}, next, ConnectingVoice{ticket, task}, "", ""}, [ConnectVoice{ticket, connection, task}]}
    case _ state: Decision{state, Nil{}}

def live(+current: Bool, +text: String, +state: State) -> Decision:
  match current:
    case False{}: Decision{state, Nil{}}
    case True{}:
      State{connections, selected, next, activity, notice, old} = state
      Decision{State{connections, selected, next, activity, notice, text}, Nil{}}

def replace_notice(reason: String, state: State) -> Decision:
  State{connections, selected, next, activity, notice, live_text} = state
  Decision{State{connections, selected, next, activity, reason, live_text}, Nil{}}

def field_owner(editor: U.Editor) -> String:
  UX.object_key(UX.owner(Experience.Subject{editor, Forms.MessageText{}}))

def select_connection(valid: Bool, id: String, state: State) -> Decision:
  match valid:
    case True{}:
      State{connections, selected, next, activity, notice, live_text} = state
      Decision{State{connections, Some{id}, next, activity, "", live_text}, Nil{}}
    case False{}: Decision{state, Nil{}}

def create_task(valid: Bool, command: J.Json, state: State) -> Decision:
  match valid:
    case True{}:
      State{connections, selected, +next, activity, notice, live_text} = state
      Decision{State{connections, selected, (next + 1n : Nat), CreatingTask{next}, "", ""}, [CreateTask{next, command}]}
    case False{}: Decision{state, Nil{}}
def allows(values: +List<Connection>, +id: String, +voice: Bool) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{Connection{+current, label, asr, realtime}, rest}:
      (String.eq(current, id) && connection_enabled(voice, asr, realtime)) ||
        (Bool.not(String.eq(current, id)) && allows(rest, id, voice))

def free(state: State) -> Bool:
  activity_free(activity(state))

def cancel(+state: State) -> Decision:
  State{connections, selected, next, +activity, notice, live_text} = state
  Decision{State{connections, selected, next, Idle{}, "", ""}, release(activity)}

def settled(+current: Bool, +reason: String, +state: State) -> Decision:
  match current:
    case False{}: Decision{state, Nil{}}
    case True{}:
      State{connections, selected, next, +activity, notice, live_text} = state
      Decision{State{connections, selected, next, Idle{}, reason, ""}, release(activity)}

def begin_dictation(+allowed: Bool, +editor: U.Editor, +revision: Nat, +state: State) -> Decision:
  match allowed:
    case False{}: Decision{state, Nil{}}
    case True{}:
      State{connections, selected, +next, activity, notice, live_text} = state
      Decision{State{connections, selected, (next + 1n : Nat), Acquiring{next, editor, revision}, "", ""}, [Record{next, field_owner(editor)}]}

def captured(+current: Bool, +ticket: Nat, +editor: U.Editor, +revision: Nat, +start: Nat, +end: Nat, +state: State) -> Decision:
  match current:
    case False{}: Decision{state, Nil{}}
    case True{}: Decision{with_activity(Recording{ticket, Target{editor, revision, start, end}}, state), Nil{}}

def transcribed(+current: Bool, +target: Target, +text: String, +state: State) -> Decision:
  match current:
    case False{}: Decision{state, Nil{}}
    case True{}: Decision{with_activity(Retained{target, text}, state), Nil{}}

def ready(+current: Bool, +ticket: Nat, +task: Nat, +state: State) -> Decision:
  match current:
    case False{}: Decision{state, Nil{}}
    case True{}: Decision{with_activity(Voice{ticket, task, False{}, False{}}, state), Nil{}}

def selection_found(valid: Bool, id: String, values: +List<Connection>) -> Maybe<&2, String>:
  match valid:
    case True{}: Some{id}
    case False{}: first(values)

def eligible(+state: State, +voice: Bool) -> Bool:
  State{connections, selected, next, activity, notice, live_text} = state
  match selected:
    case None{}: False{}
    case Some{id}: allows(connections, id, voice)

def selection(+values: +List<Connection>, +old: Maybe<&2, String>) -> Maybe<&2, String>:
  match old:
    case Some{id}:
      selection_found(allows(values, id, False{}) || allows(values, id, True{}), id, values)
    case None{}: first(values)

def eligible_id(state: State, +id: String) -> Bool:
  State{+connections, selected, next, activity, notice, live_text} = state
  allows(connections, id, False{}) || allows(connections, id, True{})

def can_begin(+state: State, +voice: Bool) -> Bool:
  free(state) && eligible(state, voice)

def can_authorize(+state: State) -> Bool:
  free(state) && List.is_empty(&2, Connection, connections(state))

def begin_authorize(allowed: Bool, state: State) -> Decision:
  match allowed:
    case True{}: Decision{state, [BeginAudioLogin{}]}
    case False{}: Decision{state, Nil{}}

def replace_capabilities(+values: +List<Connection>, state: State) -> Decision:
  State{connections, selected, next, activity, notice, live_text} = state
  Decision{State{values, selection(values, selected), next, activity, "", live_text}, Nil{}}

def dispatch_activity(input: Input, activity: Activity, selected: Maybe<&2, String>, +state: State) -> Decision:
  match input activity selected:
    case Authorize{} _ _: begin_authorize(can_authorize(state), state)
    case Refresh{} _ _: Decision{state, [LoadCapabilities{}]}
    case Capabilities{values} _ _: replace_capabilities(values, state)
    case CapabilitiesFailed{reason} _ _: replace_notice(reason, state)
    case Select{+id} _ _: select_connection(free(state) && eligible_id(state, id), id, state)
    case BeginDictation{editor, revision} _ _: begin_dictation(can_begin(state, False{}), editor, revision, state)
    case Captured{+ticket, start, end} Acquiring{current, editor, revision} _:
      captured(Nat.is_eq(current, ticket), ticket, editor, revision, start, end, state)
    case Captured{ticket, start, end} _ _: Decision{state, Nil{}}
    case FinishDictation{} Recording{+ticket, +target} Some{connection}:
      Decision{with_activity(Transcribing{ticket, target}, state), [Transcribe{ticket, connection}]}
    case FinishDictation{} _ _: Decision{state, Nil{}}
    case Transcribed{ticket, text} Transcribing{current, target} _:
      transcribed(Nat.is_eq(current, ticket), target, text, state)
    case Transcribed{ticket, text} _ _: Decision{state, Nil{}}
    case InsertTranscript{} _ _: Decision{state, Nil{}}
    case DismissTranscript{} Retained{target, text} _: Decision{with_activity(Idle{}, state), Nil{}}
    case DismissTranscript{} _ _: Decision{state, Nil{}}
    case BeginVoice{task} _ _: begin_voice(can_begin(state, True{}), task, state)
    case BeginNewVoice{editor, command} _ _: create_task(can_begin(state, True{}), command, state)
    case TaskCreated{+ticket, task} CreatingTask{current} _:
      created(Nat.is_eq(current, ticket), ticket, task, state)
    case TaskCreated{ticket, task} _ _: Decision{state, Nil{}}
    case VoiceReady{+ticket} ConnectingVoice{current, task} _:
      ready(Nat.is_eq(current, ticket), ticket, task, state)
    case VoiceReady{ticket} _ _: Decision{state, Nil{}}
    case LiveText{ticket, text} activity _: live(owned(activity, ticket), text, state)
    case ToggleInputMute{} Voice{+ticket, task, +muted, output} _:
      Decision{with_activity(Voice{ticket, task, Bool.not(muted), output}, state), [SetInputMute{ticket, Bool.not(muted)}]}
    case ToggleInputMute{} _ _: Decision{state, Nil{}}
    case ToggleOutputMute{} Voice{+ticket, task, input, +muted} _:
      Decision{with_activity(Voice{ticket, task, input, Bool.not(muted)}, state), [SetOutputMute{ticket, Bool.not(muted)}]}
    case ToggleOutputMute{} _ _: Decision{state, Nil{}}
    case Cancel{} _ _: cancel(state)
    case Failed{ticket, reason} activity _: settled(owned(activity, ticket), reason, state)
    case Ended{ticket, reason} activity _: settled(owned(activity, ticket), reason, state)
    case Released{} _ _: cancel(state)

def dispatch(+state: State, input: Input) -> Decision:
  dispatch_activity(input, activity(state), selected(state), state)

def step(+input: Input, +state: State) -> Decision:
  dispatch(state, input)
