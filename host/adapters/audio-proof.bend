import Base
import ../../bendlib/json.bend as J
import ./MODEL.bend as Model
import ./AUDIO.bend as Audio

def production_correspondence(+operation: String, +source: J.Json) ->
  {Audio.run(operation, source) == Audio.meaning(operation, source) : J.Json}:
  {==}

def completed_turn_source(turn: J.Json) -> J.Json:
  Audio.object(Con{J.Field{"value", Audio.object(Con{J.Field{"type", J.Text{"turn.done"}}, Con{J.Field{"turn", turn}, Nil{}}})}, Nil{}})

def transcript_does_not_delegate(+turn: J.Json) ->
  {Audio.event(completed_turn_source(turn)) == Audio.transcript_event(J.get(completed_turn_source(turn), "value")) : J.Json}:
  {==}

def unavailable_capability_rejects() ->
  {Audio.capability(J.Null{}) == Model.failure_code("audio_invalid_request", "ChatGPT audio sign-in is required") : J.Json}:
  {==}
