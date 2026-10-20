import Base
import ../../bendlib/equality-proof.bend as Equal
import ./MODEL.bend as Actual
import ./CONTRACT.bend as Rule
import ../INPUT.bend as U

def cancellation(+connections: +List<Actual.Connection>, +selected: Maybe<&2, String>, +next: Nat,
  activity: Actual.Activity, notice: String, live_text: String) ->
  {Actual.step(Actual.Cancel{}, Actual.State{connections, selected, next, activity, notice, live_text}) ==
    Actual.Decision{Actual.State{connections, selected, next, Actual.Idle{}, "", ""}, Rule.stop(Rule.resource(activity))} : Actual.Decision}:
  match activity:
    case Actual.Idle{}: {==}
    case Actual.Acquiring{ticket, editor, revision}: {==}
    case Actual.Recording{ticket, target}: {==}
    case Actual.Transcribing{ticket, target}: {==}
    case Actual.Retained{target, text}: {==}
    case Actual.CreatingTask{ticket}: {==}
    case Actual.ConnectingVoice{ticket, task}: {==}
    case Actual.Voice{ticket, task, input_muted, output_muted}: {==}

def authorization_admission(+state: Actual.State,
  blocked: {Actual.can_authorize(state) == False{} : Bool}) ->
  {Actual.step(Actual.Authorize{}, state) == Actual.Decision{state, Nil{}} : Actual.Decision}:
  Actual.State{+connections, +selected, +next, +activity, +notice, +live_text} = state
  Equal.cong(Bool, Actual.Decision,
    allowed => Actual.begin_authorize(allowed, Actual.State{connections, selected, next, activity, notice, live_text}),
    Actual.can_authorize(Actual.State{connections, selected, next, activity, notice, live_text}), False{}, blocked)

def dictation_admission(+editor: U.Editor, +revision: Nat, +state: Actual.State,
  blocked: {Actual.can_begin(state, False{}) == False{} : Bool}) ->
  {Actual.step(Actual.BeginDictation{editor, revision}, state) == Actual.Decision{state, Nil{}} : Actual.Decision}:
  Actual.State{+connections, +selected, +next, +activity, +notice, +live_text} = state
  Equal.cong(Bool, Actual.Decision,
    allowed => Actual.begin_dictation(allowed, editor, revision, Actual.State{connections, selected, next, activity, notice, live_text}),
    Actual.can_begin(Actual.State{connections, selected, next, activity, notice, live_text}, False{}), False{}, blocked)

def voice_admission(+task: Nat, +state: Actual.State,
  blocked: {Actual.can_begin(state, True{}) == False{} : Bool}) ->
  {Actual.step(Actual.BeginVoice{task}, state) == Actual.Decision{state, Nil{}} : Actual.Decision}:
  Actual.State{+connections, +selected, +next, +activity, +notice, +live_text} = state
  Equal.cong(Bool, Actual.Decision,
    allowed => Actual.begin_voice(allowed, task, Actual.State{connections, selected, next, activity, notice, live_text}),
    Actual.can_begin(Actual.State{connections, selected, next, activity, notice, live_text}, True{}), False{}, blocked)

def stale_transcription(+connections: +List<Actual.Connection>, +selected: Maybe<&2, String>, +next: Nat,
  +current: Nat, +ticket: Nat, +target: Actual.Target, text: String, +notice: String, +live_text: String,
  different: {Nat.is_eq(current, ticket) == False{} : Bool}) ->
  {Actual.step(Actual.Transcribed{ticket, text}, Actual.State{connections, selected, next, Actual.Transcribing{current, target}, notice, live_text}) ==
    Actual.Decision{Actual.State{connections, selected, next, Actual.Transcribing{current, target}, notice, live_text}, Nil{}} : Actual.Decision}:
  Equal.cong(Bool, Actual.Decision,
    owned => Actual.transcribed(owned, target, text, Actual.State{connections, selected, next, Actual.Transcribing{current, target}, notice, live_text}),
    Nat.is_eq(current, ticket), False{}, different)

def production() -> Rule.Requirements:
  Rule.Requirements{cancellation, authorization_admission, dictation_admission, voice_admission, stale_transcription}
