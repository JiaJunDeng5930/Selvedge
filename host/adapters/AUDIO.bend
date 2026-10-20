import Base
import ../../bendlib/json.bend as J
import ../../harness/conversation/PROGRAM.bend as Conversation
import ./MODEL.bend as Model
import ./ACCOUNTS.bend as Accounts

def object(fields: +List<J.Field>) -> J.Json:
  J.Object{fields}
def is_array(value: J.Json) -> Bool:
  match value:
    case J.Array{items}: True{}
    case _: False{}
def text(+value: J.Json) -> Bool:
  J.is_text(value) && Bool.not(String.is_empty(J.text(value)))
def select(condition: Bool, yes: J.Json, no: J.Json) -> J.Json:
  match condition:
    case True{}: yes
    case False{}: no
def admit(valid: Bool, value: J.Json, error: String) -> J.Json:
  match valid:
    case True{}: Model.success(value)
    case False{}: Model.failure_code("audio_invalid_request", error)

def asr_max_bytes() -> String:
  "26214400"
def connect_timeout_ms() -> String:
  "20000"
def request_timeout_ms() -> String:
  "120000"
def session_max_ms() -> String:
  "3600000"
def contract() -> J.Json:
  Model.success(object(Con{J.Field{"transcribe_url", J.Text{"https://chatgpt.com/backend-api/transcribe"}},
    Con{J.Field{"calls_url", J.Text{"https://chatgpt.com/backend-api/wham/realtime/calls?intent=quicksilver&architecture=avas"}},
    Con{J.Field{"sideband_base", J.Text{"wss://api.openai.com/v1/live/"}},
    Con{J.Field{"connect_timeout_ms", J.Number{connect_timeout_ms()}}, Con{J.Field{"request_timeout_ms", J.Number{request_timeout_ms()}},
    Con{J.Field{"session_max_ms", J.Number{session_max_ms()}},
    Con{J.Field{"asr_max_bytes", J.Number{asr_max_bytes()}}, Con{J.Field{"response_max_bytes", J.Number{"2097152"}},
    Con{J.Field{"event_max_bytes", J.Number{"2097152"}}, Con{J.Field{"context_chunk_bytes", J.Number{"500"}}, Nil{}}}}}}}}}}}))

def authorized_audio(+source: J.Json) -> Bool:
  J.boolean(J.get(source, "authorized")) && J.same(J.get(source, "source"), J.Text{"chatgpt_audio"})
def eligible(+source: J.Json) -> Bool:
  authorized_audio(source) && text(J.get(source, "id"))
def capability_value(+source: J.Json) -> J.Json:
  object([J.Field{"id", J.get(source, "id")}, J.Field{"label", J.Text{"ChatGPT"}},
    J.Field{"source", J.Text{"chatgpt_audio"}}, J.Field{"asr", J.Boolean{True{}}}, J.Field{"voice", J.Boolean{True{}}}])
def capability(+source: J.Json) -> J.Json:
  admit(eligible(source), capability_value(source), "ChatGPT audio sign-in is required")
def capability_kept(keep: Bool, source: J.Json, rest: +List<J.Json>) -> +List<J.Json>:
  match keep:
    case True{}: Con{capability_value(source), rest}
    case False{}: rest
def capability_connections(items: +List<J.Json>) -> +List<J.Json>:
  match items:
    case Nil{}: Nil{}
    case Con{+head, rest}: capability_kept(eligible(head), head, capability_connections(rest))
def capabilities(+source: J.Json) -> J.Json:
  admit(is_array(J.get(source, "connections")), J.Array{capability_connections(J.items(J.get(source, "connections")))}, "Audio account discovery requires ChatGPT account observations")

def request_connection(+source: J.Json) -> Bool:
  text(J.get(source, "connection")) && authorized_audio(source)
def mime_component(parts: +List<String>) -> String:
  match parts:
    case Nil{}: ""
    case Con{head, rest}: head
def mime_subtype(value: String) -> String:
  mime_component(String.split(String.drop(value, 6n), Chr{59}))
def asr_requirements(+source: J.Json) -> Bool:
  request_connection(source) && Accounts.number_between(J.get(source, "bytes"), "1", asr_max_bytes()) &&
    String.starts_with(J.text(J.get(source, "mime")), "audio/") && Bool.not(String.is_empty(mime_subtype(J.text(J.get(source, "mime"))))) &&
    (J.same(J.get(source, "language"), J.Null{}) || text(J.get(source, "language")))
def asr_request(+source: J.Json) -> J.Json:
  admit(asr_requirements(source), object(Con{J.Field{"mime", J.get(source, "mime")},
    Con{J.Field{"language", J.get(source, "language")}, Con{J.Field{"filename", J.Text{"recording." ++ mime_subtype(J.text(J.get(source, "mime")))}}, Nil{}}}}),
    "Audio transcription requires a signed-in ChatGPT connection and 1 to 26214400 audio bytes")

def initial_content(items: +List<J.Json>) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{+head, rest}: (String.eq(J.text(J.get(head, "type")), "input_text") || String.eq(J.text(J.get(head, "type")), "output_text")) && text(J.get(head, "text")) && initial_content(rest)
def initial_item(+item: J.Json) -> Bool:
  String.eq(J.text(J.get(item, "type")), "message") &&
    (String.eq(J.text(J.get(item, "role")), "user") || String.eq(J.text(J.get(item, "role")), "assistant")) && is_array(J.get(item, "content")) && initial_content(J.items(J.get(item, "content")))
def initial_items(items: +List<J.Json>) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{+head, rest}: initial_item(head) && initial_items(rest)
def session_requirements(+source: J.Json) -> Bool:
  request_connection(source) && Accounts.number_between(J.get(source, "task_id"), "0", "9007199254740991") &&
    text(J.get(source, "id")) && text(J.get(source, "sdp")) &&
    (J.same(J.get(source, "initial_items"), J.Null{}) || (is_array(J.get(source, "initial_items")) && initial_items(J.items(J.get(source, "initial_items")))))
def instructions() -> String:
  "You are speaking with the user in Selvedge. Converse naturally. Delegate explicit requests to perform work to the client; transcript events alone never start work. Use delegation context updates as the authoritative progress of accepted work. Ending this voice call does not cancel accepted tasks."
def session_request(+source: J.Json) -> J.Json:
  admit(session_requirements(source), object(Con{J.Field{"sdp", J.get(source, "sdp")},
    Con{J.Field{"session", object(Con{J.Field{"model", J.Text{"gpt-live-1-codex"}},
      Con{J.Field{"delegation", object(Con{J.Field{"type", J.Text{"client"}}, Nil{}})},
      Con{J.Field{"audio", object(Con{J.Field{"output", object(Con{J.Field{"voice", J.Text{"arbor"}}, Nil{}})}, Nil{}})},
      Con{J.Field{"instructions", J.Text{instructions()}}, Con{J.Field{"voice_session_id", J.get(source, "id")},
      Con{J.Field{"initial_items", select(is_array(J.get(source, "initial_items")), J.get(source, "initial_items"), J.Array{Nil{}})}, Nil{}}}}}}})}, Nil{}}}),
    "Voice requires a signed-in ChatGPT connection, an existing task and an SDP offer")

def successful_status(+source: J.Json) -> Bool:
  Accounts.number_between(J.get(source, "status"), "200", "299")
def response_failure(+source: J.Json) -> J.Json:
  Model.failure_code("audio_upstream_rejected", "ChatGPT audio request failed with HTTP " ++ Accounts.number_text(J.get(source, "status")))
def asr_response_status(ok: Bool, +source: J.Json) -> J.Json:
  match ok:
    case False{}: response_failure(source)
    case True{}: admit(J.is_text(J.get(J.get(source, "value"), "text")), object(Con{J.Field{"text", J.get(J.get(source, "value"), "text")}, Nil{}}), "ChatGPT transcription response is missing text")
def asr_response(+source: J.Json) -> J.Json:
  asr_response_status(successful_status(source), source)
def session_response_status(ok: Bool, +source: J.Json) -> J.Json:
  match ok:
    case False{}: response_failure(source)
    case True{}: admit(text(J.get(source, "sdp")) && String.starts_with(J.text(J.get(source, "call_id")), "rtc_") && Bool.not(String.eq(J.text(J.get(source, "call_id")), "rtc_")),
      object(Con{J.Field{"call_id", J.get(source, "call_id")}, Con{J.Field{"sdp", J.get(source, "sdp")}, Nil{}}}), "ChatGPT voice response is missing SDP or call identity")
def session_response(+source: J.Json) -> J.Json:
  session_response_status(successful_status(source), source)

def input_text(items: +List<J.Json>) -> String:
  match items:
    case Nil{}: ""
    case Con{+head, rest}: J.text(select(String.eq(J.text(J.get(head, "type")), "input_text"), J.get(head, "text"), J.Text{""})) ++ input_text(rest)
def ignored() -> J.Json:
  Model.success(J.Null{})
def transcript_event(+value: J.Json) -> J.Json:
  +turn = J.get(value, "turn")
  +role = J.get(turn, "role")
  admit((J.same(role, J.Text{"user"}) || J.same(role, J.Text{"assistant"})) && J.is_text(J.get(turn, "transcript")),
    select(String.is_empty(J.text(J.get(turn, "transcript"))), J.Null{},
      object(Con{J.Field{"type", J.Text{"transcript"}}, Con{J.Field{"role", role},
      Con{J.Field{"text", J.get(turn, "transcript")}, Con{J.Field{"item_id", J.get(turn, "id")}, Nil{}}}}})), "Invalid completed voice transcript")
def turn_text(items: +List<J.Json>, +id: J.Json) -> String:
  match items:
    case Nil{}: ""
    case Con{+head, rest}: J.text(select(J.same(J.get(head, "turn_id"), id), J.get(head, "text"), J.Text{turn_text(rest, id)}))
def delegation_output(ready: Bool, +item: J.Json, +message: String) -> J.Json:
  Model.success(object(Con{J.Field{"type", select(ready, J.Text{"delegation"}, J.Text{"delegation_pending"})},
    Con{J.Field{"item_id", J.get(item, "id")}, Con{J.Field{"text", J.Text{message}},
    Con{J.Field{"turn_id", J.get(item, "user_bidi_turn_id")}, Nil{}}}}}))
def delegation_resolved(+item: J.Json, +source: J.Json) -> J.Json:
  +own = input_text(J.items(J.get(item, "content")))
  +message = J.text(select(Bool.not(String.is_empty(own)), J.Text{own}, J.Text{turn_text(J.items(J.get(source, "turns")), J.get(item, "user_bidi_turn_id"))}))
  delegation_output(Bool.not(String.is_empty(message)), item, message)
def delegation_event(+value: J.Json, +source: J.Json) -> J.Json:
  +item = J.get(value, "item")
  +valid = String.eq(J.text(J.get(item, "type")), "delegation") && String.eq(J.text(J.get(item, "target")), "client") && text(J.get(item, "id")) &&
    (text(J.get(item, "user_bidi_turn_id")) || Bool.not(String.is_empty(input_text(J.items(J.get(item, "content"))))))
  select(valid, delegation_resolved(item, source), Model.failure_code("audio_invalid_request", "Invalid client voice delegation"))
def handoff_event(+value: J.Json, source: J.Json) -> J.Json:
  delegation_event(object(Con{J.Field{"item", object(Con{J.Field{"type", J.Text{"delegation"}}, Con{J.Field{"target", J.Text{"client"}},
    Con{J.Field{"id", J.get(value, "item_id")}, Con{J.Field{"user_bidi_turn_id", J.get(value, "user_bidi_turn_id")},
    Con{J.Field{"content", J.Array{Con{object(Con{J.Field{"type", J.Text{"input_text"}}, Con{J.Field{"text", J.get(value, "input_transcript")}, Nil{}}}), Nil{}}}}, Nil{}}}}}})}, Nil{}}), source)
def turn_created(+value: J.Json) -> J.Json:
  +turn = J.get(value, "turn")
  select(J.same(J.get(turn, "role"), J.Text{"assistant"}), ignored(),
    admit(J.same(J.get(turn, "role"), J.Text{"user"}) && text(J.get(turn, "id")) && text(J.get(turn, "transcript")),
      object(Con{J.Field{"type", J.Text{"turn"}}, Con{J.Field{"turn_id", J.get(turn, "id")}, Con{J.Field{"text", J.get(turn, "transcript")}, Nil{}}}}), "Invalid voice user-turn association"))
def delta_event(+value: J.Json, role: String) -> J.Json:
  admit(J.is_text(J.get(J.get(value, "item"), "text")), object(Con{J.Field{"type", J.Text{"delta"}}, Con{J.Field{"role", J.Text{role}}, Con{J.Field{"text", J.get(J.get(value, "item"), "text")}, Nil{}}}}), "Invalid voice transcript increment")
def event_route_7(accepted: Bool, +value: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(object(Con{J.Field{"type", J.Text{"error"}}, Con{J.Field{"error", J.Text{"ChatGPT voice control reported an error"}}, Nil{}}}))
    case False{}: ignored()
def event_route_6(accepted: Bool, +value: J.Json) -> J.Json:
  match accepted:
    case True{}: turn_created(value)
    case False{}: event_route_7(String.eq(J.text(J.get(value, "type")), "error"), value)
def event_route_5(accepted: Bool, +value: J.Json, source: J.Json) -> J.Json:
  match accepted:
    case True{}: handoff_event(value, source)
    case False{}: event_route_6(String.eq(J.text(J.get(value, "type")), "turn.created"), value)
def event_route_4(accepted: Bool, +value: J.Json, source: J.Json) -> J.Json:
  match accepted:
    case True{}: delta_event(value, "assistant")
    case False{}: event_route_5(String.eq(J.text(J.get(value, "type")), "conversation.handoff.requested"), value, source)
def event_route_3(accepted: Bool, +value: J.Json, source: J.Json) -> J.Json:
  match accepted:
    case True{}: delta_event(value, "user")
    case False{}: event_route_4(String.eq(J.text(J.get(value, "type")), "output_transcript.added"), value, source)
def event_route_2(accepted: Bool, +value: J.Json, source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(object(Con{J.Field{"type", J.Text{"ready"}}, Nil{}}))
    case False{}: event_route_3(String.eq(J.text(J.get(value, "type")), "input_transcript.added"), value, source)
def event_route_1(accepted: Bool, +value: J.Json, source: J.Json) -> J.Json:
  match accepted:
    case True{}: delegation_event(value, source)
    case False{}: event_route_2(String.eq(J.text(J.get(value, "type")), "session.started") || String.eq(J.text(J.get(value, "type")), "session.updated"), value, source)
def event_kind(accepted: Bool, +value: J.Json, source: J.Json) -> J.Json:
  match accepted:
    case True{}: transcript_event(value)
    case False{}: event_route_1(String.eq(J.text(J.get(value, "type")), "delegation.created"), value, source)
def event(+source: J.Json) -> J.Json:
  +value = J.get(source, "value")
  event_kind(String.eq(J.text(J.get(value, "type")), "turn.done"), value, source)

def context_requirements(+source: J.Json) -> Bool:
  text(J.get(source, "text")) && (J.same(J.get(source, "delegation_item_id"), J.Null{}) || text(J.get(source, "delegation_item_id"))) &&
    (J.same(J.get(source, "channel"), J.Null{}) || J.same(J.get(source, "channel"), J.Text{"commentary"}) || J.same(J.get(source, "channel"), J.Text{"speakable"}))
def context_fields(absent: Bool, delegation: J.Json, base: +List<J.Field>) -> +List<J.Field>:
  match absent:
    case True{}: base
    case False{}: Con{J.Field{"delegation_item_id", delegation}, base}
def context_content(value: J.Json) -> J.Json:
  J.Array{Con{object(Con{J.Field{"type", J.Text{"input_text"}}, Con{J.Field{"text", value}, Nil{}}}), Nil{}}}
def context(+source: J.Json) -> J.Json:
  +delegation = J.get(source, "delegation_item_id")
  +base: +List<J.Field> = Con{J.Field{"type", select(J.same(delegation, J.Null{}), J.Text{"session.context.append"}, J.Text{"delegation.context.append"})},
    Con{J.Field{"channel", select(J.same(J.get(source, "channel"), J.Null{}), J.Text{"speakable"}, J.get(source, "channel"))},
    Con{J.Field{"content", context_content(J.get(source, "text"))}, Nil{}}}}
  admit(context_requirements(source), object(context_fields(J.same(delegation, J.Null{}), delegation, base)), "Voice context requires text and an optional delegation identity")

def initial_context_plan(+source: J.Json) -> J.Json:
  +cursor = J.get(source, "cursor")
  admit(Accounts.number_between(cursor, "0", "9007199254740991"),
    object([J.Field{"after", J.nat(Nat.sub(J.natural_or(J.natural(cursor), 0n), 100n))}, J.Field{"limit", J.Number{"100"}}]),
    "Voice history requires a committed Task cursor")

def initial_message(+role: String, value: J.Json) -> J.Json:
  object([J.Field{"type", J.Text{"message"}}, J.Field{"role", J.Text{role}},
    J.Field{"content", J.Array{[object([J.Field{"type", select(String.eq(role, "assistant"), J.Text{"output_text"}, J.Text{"input_text"})}, J.Field{"text", value}])]}}])
def initial_message_kept(keep: Bool, role: String, value: J.Json) -> +List<J.Json>:
  match keep:
    case True{}: [initial_message(role, value)]
    case False{}: Nil{}
def initial_summary(summary: Bool, +message: J.Json) -> +List<J.Json>:
  match summary:
    case True{}: initial_message_kept(text(J.get(message, "content")), "user", J.Text{"Previous Task context summary:\n" ++ J.text(J.get(message, "content"))})
    case False{}: Nil{}
def task_assistant(+message: J.Json) -> Bool:
  J.same(J.get(message, "role"), J.Text{"assistant"}) ||
    (J.same(J.get(message, "role"), J.Text{"model_context"}) && Conversation.provider_assistant(J.get(message, "content")))
def task_content(+message: J.Json) -> J.Json:
  select(J.same(J.get(message, "role"), J.Text{"model_context"}),
    J.Text{Conversation.provider_text(J.get(message, "content"))}, J.get(message, "content"))
def initial_history_item(+message: J.Json) -> +List<J.Json>:
  +role = select(task_assistant(message), J.Text{"assistant"},
    select(J.same(J.get(message, "role"), J.Text{"speech_transcript"}), J.get(message, "speaker"), J.get(message, "role")))
  +content = task_content(message)
  List.append(&2, J.Json,
    initial_message_kept((J.same(role, J.Text{"user"}) || J.same(role, J.Text{"assistant"})) && text(content), J.text(role), content),
    initial_summary(J.same(J.get(message, "role"), J.Text{"context_replacement"}), message))
def initial_history(items: +List<J.Json>) -> +List<J.Json>:
  match items:
    case Nil{}: Nil{}
    case Con{head, rest}: List.append(&2, J.Json, initial_history_item(head), initial_history(rest))
def initial_context(+source: J.Json) -> J.Json:
  admit(is_array(J.get(source, "messages")), J.Array{initial_history(J.items(J.get(source, "messages")))}, "Voice history requires committed Task messages")

def task_progress_kept(keep: Bool, content: J.Json, channel: J.Json) -> +List<J.Json>:
  match keep:
    case True{}: [object([J.Field{"text", content}, J.Field{"channel", channel}])]
    case False{}: Nil{}
def task_progress_items(items: +List<J.Json>, +channel: J.Json) -> +List<J.Json>:
  match items:
    case Nil{}: Nil{}
    case Con{+head, rest}:
      +content = task_content(head)
      List.append(&2, J.Json,
        task_progress_kept((task_assistant(head) || J.same(J.get(head, "role"), J.Text{"error"})) && text(content), content, channel),
        task_progress_items(rest, channel))
def task_progress(+source: J.Json) -> J.Json:
  admit(is_array(J.get(source, "messages")), J.Array{task_progress_items(J.items(J.get(source, "messages")),
    select(J.same(J.get(J.get(source, "task"), "phase"), J.Text{"idle"}), J.Text{"speakable"}, J.Text{"commentary"}))},
    "Voice progress requires committed Task messages")

def transcript_remaining(+pending: String, +completed: String) -> String:
  # A delayed final can follow the next utterance's deltas. Consume only its
  # matching prefix; a final extending the whole partial consumes that partial.
  J.text(select(String.starts_with(pending, completed), J.Text{String.drop(pending, String.length(completed))},
    select(String.starts_with(completed, pending), J.Text{""}, J.Text{pending})))
def transcript_tail(+source: J.Json) -> J.Json:
  admit(J.is_text(J.get(source, "pending")) && J.is_text(J.get(source, "completed")),
    J.Text{transcript_remaining(J.text(J.get(source, "pending")), J.text(J.get(source, "completed")))},
    "Voice transcript completion requires its accumulated partial text")

# URL parsing is the browser observation; admission keeps credentials and
# navigation restricted to ChatGPT's authorization endpoint.
def login_target(+source: J.Json) -> J.Json:
  admit(text(J.get(source, "url")) && J.same(J.get(source, "protocol"), J.Text{"https:"}) &&
    J.same(J.get(source, "hostname"), J.Text{"auth.openai.com"}) && J.same(J.get(source, "pathname"), J.Text{"/oauth/authorize"}) &&
    J.same(J.get(source, "username"), J.Text{""}) && J.same(J.get(source, "password"), J.Text{""}) &&
    (J.same(J.get(source, "port"), J.Text{""}) || J.same(J.get(source, "port"), J.Text{"443"})),
    object([J.Field{"url", J.get(source, "url")}]), "Invalid ChatGPT authorization URL")

def meaning_route_14(accepted: Bool, +operation: String, source: J.Json) -> J.Json:
  match accepted:
    case True{}: login_target(source)
    case False{}: Model.failure("Unknown audio operation")
def meaning_route_13(accepted: Bool, +operation: String, source: J.Json) -> J.Json:
  match accepted:
    case True{}: capabilities(source)
    case False{}: meaning_route_14(String.eq(operation, "audio.login_target"), operation, source)
def meaning_route_12(accepted: Bool, +operation: String, source: J.Json) -> J.Json:
  match accepted:
    case True{}: task_progress(source)
    case False{}: meaning_route_13(String.eq(operation, "audio.capabilities"), operation, source)
def meaning_route_11(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: transcript_tail(source)
    case False{}: meaning_route_12(String.eq(operation, "audio.task_progress"), operation, source)
def meaning_route_10(accepted: Bool, +operation: String, source: J.Json) -> J.Json:
  match accepted:
    case True{}: initial_context(source)
    case False{}: meaning_route_11(String.eq(operation, "audio.transcript_tail"), operation, source)
def meaning_route_9(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: initial_context_plan(source)
    case False{}: meaning_route_10(String.eq(operation, "audio.initial_context"), operation, source)

def meaning_route_8(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Accounts.catalog_transport(source)
    case False{}: meaning_route_9(String.eq(operation, "audio.initial_context_plan"), operation, source)

def meaning_route_7(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: context(source)
    case False{}: meaning_route_8(String.eq(operation, "audio.transport"), operation, source)

def meaning_route_6(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: event(source)
    case False{}: meaning_route_7(String.eq(operation, "audio.context"), operation, source)

def meaning_route_5(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: session_response(source)
    case False{}: meaning_route_6(String.eq(operation, "audio.event"), operation, source)

def meaning_route_4(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: session_request(source)
    case False{}: meaning_route_5(String.eq(operation, "audio.session_response"), operation, source)

def meaning_route_3(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: asr_response(source)
    case False{}: meaning_route_4(String.eq(operation, "audio.session_request"), operation, source)

def meaning_route_2(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: asr_request(source)
    case False{}: meaning_route_3(String.eq(operation, "audio.asr_response"), operation, source)

def meaning_route_1(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: capability(source)
    case False{}: meaning_route_2(String.eq(operation, "audio.asr_request"), operation, source)

def meaning_route_0(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: contract()
    case False{}: meaning_route_1(String.eq(operation, "audio.capability"), operation, source)

def meaning(+operation: String, +source: J.Json) -> J.Json:
  meaning_route_0(String.eq(operation, "audio.contract"), operation, source)

def factory(+operation: String) -> Model.Adapter((source => meaning(operation, source))):
  Model.adapter((source => meaning(operation, source)), (source => meaning(operation, source)), source => {==})
def run(+operation: String, source: J.Json) -> J.Json:
  Model.execute((candidate => meaning(operation, candidate)), factory(operation), source)
