import Base
import ./MODEL.bend as Actual
import ../INPUT.bend as U

# The one Activity carrier grants exclusive ownership of the browser microphone.
# This observation names the physical operation that must be released on exit.
def resource(activity: Actual.Activity) -> Maybe<&2, Nat>:
  match activity:
    case Actual.Acquiring{ticket, editor, revision}: Some{ticket}
    case Actual.Recording{ticket, target}: Some{ticket}
    case Actual.Transcribing{ticket, target}: Some{ticket}
    case Actual.CreatingTask{ticket}: Some{ticket}
    case Actual.ConnectingVoice{ticket, task}: Some{ticket}
    case Actual.Voice{ticket, task, input_muted, output_muted}: Some{ticket}
    case _: None{}

def stop(resource: Maybe<&2, Nat>) -> +List<Actual.Effect>:
  match resource:
    case None{}: Nil{}
    case Some{ticket}: [Actual.Release{ticket}]

type Requirements is Type:
  Requirements{
    cancellation: @+connections:+List<Actual.Connection> -> @+selected:Maybe<&2, String> -> @+next:Nat ->
      @activity:Actual.Activity -> @notice:String -> @live_text:String ->
      {Actual.step(Actual.Cancel{}, Actual.State{connections, selected, next, activity, notice, live_text}) ==
        Actual.Decision{Actual.State{connections, selected, next, Actual.Idle{}, "", ""}, stop(resource(activity))} : Actual.Decision},
    authorization_admission: @+state:Actual.State ->
      @blocked:{Actual.can_authorize(state) == False{} : Bool} ->
      {Actual.step(Actual.Authorize{}, state) == Actual.Decision{state, Nil{}} : Actual.Decision},
    dictation_admission: @+editor:U.Editor -> @+revision:Nat -> @+state:Actual.State ->
      @blocked:{Actual.can_begin(state, False{}) == False{} : Bool} ->
      {Actual.step(Actual.BeginDictation{editor, revision}, state) == Actual.Decision{state, Nil{}} : Actual.Decision},
    voice_admission: @+task:Nat -> @+state:Actual.State ->
      @blocked:{Actual.can_begin(state, True{}) == False{} : Bool} ->
      {Actual.step(Actual.BeginVoice{task}, state) == Actual.Decision{state, Nil{}} : Actual.Decision},
    stale_transcription: @+connections:+List<Actual.Connection> -> @+selected:Maybe<&2, String> -> @+next:Nat ->
      @+current:Nat -> @+ticket:Nat -> @+target:Actual.Target -> @text:String -> @+notice:String -> @+live_text:String ->
      @different:{Nat.is_eq(current, ticket) == False{} : Bool} ->
      {Actual.step(Actual.Transcribed{ticket, text}, Actual.State{connections, selected, next, Actual.Transcribing{current, target}, notice, live_text}) ==
        Actual.Decision{Actual.State{connections, selected, next, Actual.Transcribing{current, target}, notice, live_text}, Nil{}} : Actual.Decision}
  }
