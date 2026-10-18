import Base
import ../../harness/conversation/TITLE.bend as Title
import ../../harness/transport/wire-shape.bend as Shape
import ../../bendlib/json.bend as J
import ../../bendlib/categories.bend as Categories
import ../../bendlib/stdlib.bend as Std
import ./MODEL.bend as Model

type ResponseText is Data:
  Skipped{}
  Captured{value: J.Json}

def truthy(+value: J.Json) -> Bool:
  match value:
    case J.Null{}: False{}
    case J.Boolean{value}: value
    case J.Text{text}: Bool.not(String.eq(text, ""))
    case J.Number{+lexeme}: Bool.not(String.eq(lexeme, "0") || String.eq(lexeme, "-0"))
    case _: True{}

def field(+name: String, +value: J.Json) -> J.Field:
  J.Field{name, value}

def has_fields(+fields: +List<&2, J.Field>, +name: String) -> Bool:
  match fields:
    case Nil{}: False{}
    case Con{J.Field{key, value}, rest}: String.eq(key, name) || has_fields(rest, name)

def has(+value: J.Json, +name: String) -> Bool:
  match value:
    case J.Object{fields}: has_fields(fields, name)
    case _: False{}

def fields(+value: J.Json) -> +List<&2, J.Field>:
  match value:
    case J.Object{items}: items
    case _: Nil{}

def array(+value: J.Json) -> Bool:
  match value:
    case J.Array{items}: True{}
    case _: False{}

def bool_type(+value: J.Json) -> Bool:
  match value:
    case J.Boolean{value}: True{}
    case _: False{}

def names(+items: +List<&2, String>, +name: String) -> Bool:
  match items:
    case Nil{}: False{}
    case Con{head, rest}: String.eq(head, name) || names(rest, name)

def allowed(+items: +List<&2, J.Field>, +keys: List<&2, String>) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{J.Field{name, value}, rest}: names(keys, name) && allowed(rest, keys)

def length(+items: +List<&2, J.Json>) -> Nat:
  match items:
    case Nil{}: 0n
    case Con{head, rest}: Nat.add(1n, length(rest))

def well_scan(+text: String, +valid: Bool) -> Bool:
  match text:
    case SNil{}: valid
    case SCon{Chr{+code}, rest}: well_scan(rest, valid && Bool.not(U32.is_ge(code, 55296) && U32.is_le(code, 57343)))

def well(+text: String) -> Bool:
  well_scan(text, True{})

def no_nul_scan(+text: String, +valid: Bool) -> Bool:
  match text:
    case SNil{}: valid
    case SCon{Chr{code}, rest}: no_nul_scan(rest, valid && Bool.not(U32.is_eq(code, 0)))

def no_nul(+text: String) -> Bool:
  no_nul_scan(text, True{})

def space(+code: U32) -> Bool:
  (U32.is_ge(code, 9) && U32.is_le(code, 13)) || U32.is_eq(code, 32) || U32.is_eq(code, 160) ||
    U32.is_eq(code, 5760) || (U32.is_ge(code, 8192) && U32.is_le(code, 8202)) || U32.is_eq(code, 8232) ||
    U32.is_eq(code, 8233) || U32.is_eq(code, 8239) || U32.is_eq(code, 8287) || U32.is_eq(code, 12288) || U32.is_eq(code, 65279)

def content_scan(+text: String, +valid: Bool) -> Bool:
  match text:
    case SNil{}: valid
    case SCon{Chr{code}, rest}: content_scan(rest, valid || Bool.not(space(code)))

def content(+text: String) -> Bool:
  content_scan(text, False{})

type TakeRequest is Data:
  TakeRequest{text: String, size: Nat}

def take_request(+request: TakeRequest) -> String:
  match request:
    case TakeRequest{SNil{}, _}: ""
    case TakeRequest{SCon{_, _}, Zero{}}: ""
    case TakeRequest{SCon{head, tail}, Succ{rest}}:
      SCon{head, take_request(TakeRequest{tail, rest})}

def take(+text: String, +size: Nat) -> String:
  take_request(TakeRequest{text, size})

def default_null(+value: J.Json, +fallback: J.Json) -> J.Json:
  match value:
    case J.Null{}: fallback
    case _: value

def token_tail(+text: String, +result: Result<&2, &2, String, +List<&2, String>>) -> Result<&2, &2, String, +List<&2, String>>:
  match result:
    case Done{rest}: Done{Con{text, rest}}
    case Fail{error}: Fail{error}

def tokens(+items: +List<&2, J.Json>) -> Result<&2, &2, String, +List<&2, String>>:
  match items:
    case Nil{}: Done{Nil{}}
    case Con{J.Text{text}, rest}: token_tail(text, tokens(rest))
    case _: Fail{"Invalid JSON parsing observation"}

def observation_bound(+bound: Bool, +result: Result<&2, &2, String, +List<&2, String>>) -> Result<&2, &2, String, J.Json>:
  match bound result:
    case True{} Done{values}: J.decode(values)
    case _ _: Fail{"Invalid JSON parsing observation"}

def observation(+source: J.Json) -> Result<&2, &2, String, J.Json>:
  +observed = J.get(source, "observation")
  observation_bound(J.same(J.get(source, "text"), J.get(observed, "text")) && array(J.get(observed, "tokens")), tokens(J.items(J.get(observed, "tokens"))))

def extract_direct(+valid: Bool, +value: J.Json) -> Result<&2, &2, String, ResponseText>:
  match valid:
    case True{}: Done{Captured{value}}
    case False{}: Fail{"tool"}

def extract_message(+assistant: Bool, +items: +List<&2, J.Json>) -> Result<&2, &2, String, ResponseText>:
  match assistant items:
    case True{} Con{+item, Nil{}}: extract_direct(String.eq(J.text(J.get(item, "type")), "output_text"), J.get(item, "text"))
    case _ _: Fail{"tool"}

type ExtractContextTypeName is Data:
  ExtractContextTypeNameReasoning{}
  ExtractContextTypeNameMessage{}
  ExtractContextTypeNameOther{}

def extract_context_type_discriminant(+value: String) -> ExtractContextTypeName:
  Bool.pick(ExtractContextTypeName, String.eq(value, "reasoning"), ExtractContextTypeNameReasoning{},
    Bool.pick(ExtractContextTypeName, String.eq(value, "message"), ExtractContextTypeNameMessage{},
    ExtractContextTypeNameOther{}))

def extract_context_type_classified(+kind: ExtractContextTypeName, +value: J.Json) -> Result<&2, &2, String, ResponseText>:
  match kind:
    case ExtractContextTypeNameReasoning{}: Done{Skipped{}}
    case ExtractContextTypeNameMessage{}: extract_message(String.eq(J.text(J.get(value, "role")), "assistant"), J.items(J.get(value, "content")))
    case ExtractContextTypeNameOther{}: Fail{"tool"}

def extract_context_type(+kind: String, +value: J.Json) -> Result<&2, &2, String, ResponseText>:
  extract_context_type_classified(extract_context_type_discriminant(kind), value)

def extract_context(+value: J.Json) -> Result<&2, &2, String, ResponseText>:
  extract_context_type(J.text(J.get(value, "type")), value)

type ExtractKindName is Data:
  ExtractKindNameText{}
  ExtractKindNameContext{}
  ExtractKindNameOther{}

def extract_kind_discriminant(+value: String) -> ExtractKindName:
  Bool.pick(ExtractKindName, String.eq(value, "text"), ExtractKindNameText{},
    Bool.pick(ExtractKindName, String.eq(value, "context"), ExtractKindNameContext{},
    ExtractKindNameOther{}))

def extract_kind_classified(+kind: ExtractKindName, +item: J.Json) -> Result<&2, &2, String, ResponseText>:
  match kind:
    case ExtractKindNameText{}: extract_direct(J.is_text(J.get(item, "text")), J.get(item, "text"))
    case ExtractKindNameContext{}: extract_context(J.get(item, "value"))
    case ExtractKindNameOther{}: Fail{"tool"}

def extract_kind(+kind: String, +item: J.Json) -> Result<&2, &2, String, ResponseText>:
  extract_kind_classified(extract_kind_discriminant(kind), item)

def extract_text(+item: J.Json) -> Result<&2, &2, String, ResponseText>:
  extract_kind(J.text(J.get(item, "type")), item)

def extract_combine(+head: Result<&2, &2, String, ResponseText>, +tail: Result<&2, &2, String, +List<&2, J.Json>>) -> Result<&2, &2, String, +List<&2, J.Json>>:
  match head tail:
    case Fail{error} _: Fail{error}
    case _ Fail{error}: Fail{error}
    case Done{Skipped{}} Done{items}: Done{items}
    case Done{Captured{text}} Done{items}: Done{Con{text, items}}

def extract_all(+items: +List<&2, J.Json>) -> Result<&2, &2, String, +List<&2, J.Json>>:
  match items:
    case Nil{}: Done{Nil{}}
    case Con{head, rest}: extract_combine(extract_text(head), extract_all(rest))

def response_bound_result(+valid: Bool, +text: J.Json, +error: String) -> J.Json:
  match valid:
    case True{}: Model.success(text)
    case False{}: Model.failure_code("TypeError", error)

def number_text(+value: J.Json) -> String:
  match value:
    case J.Number{text}: text
    case _: ""

def bytes_within(+text: String, +limit: J.Json) -> Bool:
  Model.nonnegative_le(J.nat(J.utf8_length(text)), number_text(limit))

def approval_response_within(+text: String, +limit: J.Json) -> Bool:
  Model.nonnegative_le(J.nat(Nat.sub(J.utf8_length(text), 256n)), number_text(limit))

def response_bounded(+text: J.Json, +limit: J.Json, +approval: Bool) -> J.Json:
  match approval:
    case True{}: response_bound_result(J.is_text(text) && well(J.text(text)) && approval_response_within(J.text(text), limit), text, "The approval reviewer exceeded its response bound")
    case False{}: response_bound_result(J.is_text(text) && well(J.text(text)) && bytes_within(J.text(text), limit), text, "The drafting endpoint must return one bounded JSON response")

def response_items(+result: Result<&2, &2, String, +List<&2, J.Json>>, +limit: J.Json, +approval: Bool) -> J.Json:
  match result approval:
    case Fail{error} True{}: Model.failure_code("TypeError", "The approval reviewer must return text without tool calls")
    case Fail{error} False{}: Model.failure_code("TypeError", "The drafting endpoint must return text without tool calls")
    case Done{Con{text, Nil{}}} _: response_bounded(text, limit, approval)
    case Done{items} True{}: Model.failure_code("TypeError", "The approval reviewer must return exactly one decision")
    case Done{items} False{}: Model.failure_code("TypeError", "The drafting endpoint must return one bounded JSON response")

def response_array(+valid: Bool, +source: J.Json, +approval: Bool) -> J.Json:
  match valid approval:
    case False{} True{}: Model.failure_code("TypeError", "The approval reviewer returned no output")
    case False{} False{}: Model.failure_code("TypeError", "The drafting endpoint returned no output")
    case True{} _: response_items(extract_all(J.items(J.get(source, "items"))), J.get(source, "limit"), approval)

def response_limit(+valid: Bool, +source: J.Json, +approval: Bool) -> J.Json:
  match valid approval:
    case False{} True{}: Model.failure_code("TypeError", "Missing approval reason byte bound")
    case False{} False{}: Model.failure_code("TypeError", "Missing board response byte bound")
    case True{} _: response_array(array(J.get(source, "items")), source, approval)

def positive_safe_integer(+value: J.Json) -> Bool:
  Model.safe_integer(value) && Model.nonnegative_le(value, "9007199254740991") && Bool.not(J.same(value, J.Number{"0"}))

def response_text(+source: J.Json, +approval: Bool) -> J.Json:
  response_limit(positive_safe_integer(J.get(source, "limit")), source, approval)

def pair_strings(+value: J.Json) -> Bool:
  match value:
    case J.Object{Con{J.Field{a, J.Text{x}}, Con{J.Field{b, J.Text{y}}, Nil{}}}}: True{}
    case _: False{}

def outcome_value(+valid: Bool, +value: J.Json, +error: String) -> J.Json:
  match valid:
    case True{}: Model.success(value)
    case False{}: Model.failure(error)

def type_outcome_value(+valid: Bool, +value: J.Json, +error: String) -> J.Json:
  match valid:
    case True{}: Model.success(value)
    case False{}: Model.failure_code("TypeError", error)

def range_outcome_value(+valid: Bool, +value: J.Json, +error: String) -> J.Json:
  match valid:
    case True{}: Model.success(value)
    case False{}: Model.failure_code("RangeError", error)

def approval_value(+value: J.Json, +limit: J.Json) -> J.Json:
  +reason = J.get(value, "reason")
  type_outcome_value(has(value, "decision") && has(value, "reason") &&
    (String.eq(J.text(J.get(value, "decision")), "allow") || String.eq(J.text(J.get(value, "decision")), "deny")) &&
    J.is_text(reason) && content(J.text(reason)) && well(J.text(reason)) && no_nul(J.text(reason)) && bytes_within(J.text(reason), limit), value, "The approval reviewer returned a malformed decision")

def approval_pair(+valid: Bool, +value: J.Json, +limit: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure_code("TypeError", "The approval reviewer must return exactly two string fields")
    case True{}: approval_value(value, limit)

def approval_decoded(+result: Result<&2, &2, String, J.Json>, +limit: J.Json) -> J.Json:
  match result:
    case Done{+value}: approval_pair(pair_strings(value), value, limit)
    case Fail{error}: approval_pair(False{}, J.Null{}, limit)

def task_text_normalized(+title: String, description: String) -> J.Json:
  type_outcome_value(Bool.not(String.is_empty(title)), J.Object{[field("title", J.Text{title}), field("description", J.Text{description})]}, "The task text endpoint returned an empty title")

def task_text_admitted(valid: Bool, +value: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure_code("TypeError", "The task text endpoint returned invalid title or description fields")
    case True{}: task_text_normalized(Title.normalize(J.text(J.get(value, "title"))), J.text(J.get(value, "description")))

def task_text_fields(+value: J.Json, capture: Bool) -> Bool:
  match capture:
    case False{}: Shape.object_keys(value, ["title"]) && J.is_text(J.get(value, "title"))
    case True{}: Shape.object_keys(value, ["title", "description"]) && J.is_text(J.get(value, "title")) && J.is_text(J.get(value, "description"))

def task_text_value(+value: J.Json, +capture: Bool) -> J.Json:
  task_text_admitted(task_text_fields(value, capture) && Nat.is_le(J.utf8_length(J.text(J.get(value, "title"))), Title.response_title_bytes()) && well(J.text(J.get(value, "title"))) && no_nul(J.text(J.get(value, "title"))) &&
    well(J.text(J.get(value, "description"))) && no_nul(J.text(J.get(value, "description"))), value)

def task_text_decoded(result: Result<&2, &2, String, J.Json>, +context: J.Json) -> J.Json:
  match result:
    case Fail{message}: Model.failure_code("TypeError", "The task text endpoint must return one JSON object")
    case Done{value}: task_text_value(value, Bool.not(String.eq(J.text(J.get(context, "kind")), "task_title") || J.boolean(J.get(context, "retitle"))))

def outcome_kind(approval: Bool, +source: J.Json) -> J.Json:
  match approval:
    case True{}: approval_decoded(observation(source), J.get(source, "limit"))
    case False{}: task_text_decoded(observation(source), J.get(source, "context"))

def outcome(+source: J.Json, +approval: Bool) -> J.Json:
  outcome_kind(approval, source)

def filename_tail(+text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+code}, rest}: U32.is_gt(code, 31) && Bool.not(U32.is_eq(code, 127) || U32.is_eq(code, 47) || U32.is_eq(code, 92)) && filename_tail(rest)

def filename(+value: J.Json) -> J.Json:
  type_outcome_value(J.is_text(value) && Bool.not(String.eq(J.text(value), "")) && well(J.text(value)) && Nat.is_le(J.utf8_length(J.text(value)), 256n) &&
    filename_tail(J.text(value)) && Bool.not(String.eq(J.text(value), ".") || String.eq(J.text(value), "..")), value, "An attachment needs a plain filename of at most 256 UTF-8 bytes")

def hex(+text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+code}, rest}: ((U32.is_ge(code, 48) && U32.is_le(code, 57)) || (U32.is_ge(code, 97) && U32.is_le(code, 102))) && hex(rest)

def identifier(+value: J.Json) -> J.Json:
  type_outcome_value(J.is_text(value) && Nat.is_eq(J.utf8_length(J.text(value)), 64n) && hex(J.text(value)), value, "Invalid attachment identifier")

def attachment_name_result(+valid: Bool, +result: J.Json, +source: J.Json) -> J.Json:
  match valid:
    case False{}: result
    case True{}: Model.success(J.Object{Con{field("id", J.get(source, "id")), Con{field("name", J.get(result, "value")), Con{field("mime", J.get(J.get(source, "record"), "mime")), Con{field("path", J.get(source, "path")), Con{field("bytes", J.Text{Nat.show(J.natural_or(J.natural(J.get(source, "bytes")), 0n))}), Nil{}}}}}}})

# The callback coordinates originate only in the committed effect, never in an external response.

def attachment_name(+result: J.Json, +source: J.Json) -> J.Json:
  attachment_name_result(J.boolean(J.get(result, "ok")), result, source)

def attachment_integrity(+valid: Bool, +source: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure("Attachment content or metadata failed its integrity check")
    case True{}: attachment_name(filename(J.get(J.get(source, "record"), "name")), source)

def attachment(+source: J.Json) -> J.Json:
  +record = J.get(source, "record")
  attachment_integrity(J.is_object(record) && J.same(J.get(record, "version"), J.nat(1n)) && J.same(J.get(record, "id"), J.get(source, "id")) &&
    J.same(J.get(record, "bytes"), J.get(source, "bytes")) && J.same(J.get(record, "mime"), J.get(source, "mime")) && J.same(J.get(source, "hash"), J.get(source, "id")), source)

def callback_base(+effect: J.Json, +kind: String) -> +List<&2, J.Field>:
  Con{field("kind", J.Text{kind}), Con{field("task_id", J.get(effect, "task_id")), Con{field("ticket", J.get(effect, "ticket")), Nil{}}}}

def callback_field(+reserved: Bool, +value: J.Field, +rest: List<&2, J.Field>) -> List<&2, J.Field>:
  match reserved:
    case True{}: rest
    case False{}: Con{value, rest}

def callback_result_fields(+items: List<&2, J.Field>, +reserved: List<&2, String>) -> List<&2, J.Field>:
  match items:
    case Nil{}: Nil{}
    case Con{J.Field{+name, +value}, rest}:
      callback_field(names(reserved, name), J.Field{name, value}, callback_result_fields(rest, reserved))

type CallbackKind is Data:
  CallbackTaskTitle{}
  CallbackChatgptExec{}
  CallbackBoardText{}
  CallbackApproval{}
  CallbackHook{}
  CallbackAfterHook{}
  CallbackContext{}
  CallbackCompaction{completed: Bool}
  CallbackWorktree{created: Bool}
  CallbackReasoning{}
  CallbackModel{}
  CallbackDefaultTool{}

type ClassifyCallbackKindName is Data:
  ClassifyCallbackKindNameTaskTitle{}
  ClassifyCallbackKindNameChatgptExec{}
  ClassifyCallbackKindNameBoardText{}
  ClassifyCallbackKindNameApproval{}
  ClassifyCallbackKindNameHook{}
  ClassifyCallbackKindNameAfterHook{}
  ClassifyCallbackKindNameObserveContext{}
  ClassifyCallbackKindNameContextScope{}
  ClassifyCallbackKindNameContextCompaction{}
  ClassifyCallbackKindNameWorktreeCreate{}
  ClassifyCallbackKindNameWorktreeArchive{}
  ClassifyCallbackKindNameReasoning{}
  ClassifyCallbackKindNameModel{}
  ClassifyCallbackKindNameOther{}

def classify_callback_kind_discriminant(+value: String) -> ClassifyCallbackKindName:
  Bool.pick(ClassifyCallbackKindName, String.eq(value, "task_title"), ClassifyCallbackKindNameTaskTitle{},
    Bool.pick(ClassifyCallbackKindName, String.eq(value, "chatgpt_exec"), ClassifyCallbackKindNameChatgptExec{},
    Bool.pick(ClassifyCallbackKindName, String.eq(value, "board_text"), ClassifyCallbackKindNameBoardText{},
    Bool.pick(ClassifyCallbackKindName, String.eq(value, "approval"), ClassifyCallbackKindNameApproval{},
    Bool.pick(ClassifyCallbackKindName, String.eq(value, "hook"), ClassifyCallbackKindNameHook{},
    Bool.pick(ClassifyCallbackKindName, String.eq(value, "after_hook"), ClassifyCallbackKindNameAfterHook{},
    Bool.pick(ClassifyCallbackKindName, String.eq(value, "observe_context"), ClassifyCallbackKindNameObserveContext{},
    Bool.pick(ClassifyCallbackKindName, String.eq(value, "context_scope"), ClassifyCallbackKindNameContextScope{},
    Bool.pick(ClassifyCallbackKindName, String.eq(value, "context_measure"), ClassifyCallbackKindNameContextScope{},
    Bool.pick(ClassifyCallbackKindName, String.eq(value, "context_compaction"), ClassifyCallbackKindNameContextCompaction{},
    Bool.pick(ClassifyCallbackKindName, String.eq(value, "worktree_create"), ClassifyCallbackKindNameWorktreeCreate{},
    Bool.pick(ClassifyCallbackKindName, String.eq(value, "worktree_archive"), ClassifyCallbackKindNameWorktreeArchive{},
    Bool.pick(ClassifyCallbackKindName, String.eq(value, "reasoning"), ClassifyCallbackKindNameReasoning{},
    Bool.pick(ClassifyCallbackKindName, String.eq(value, "model"), ClassifyCallbackKindNameModel{},
    ClassifyCallbackKindNameOther{}))))))))))))))

def classify_callback_kind_classified(+kind: ClassifyCallbackKindName) -> CallbackKind:
  match kind:
    case ClassifyCallbackKindNameTaskTitle{}: CallbackTaskTitle{}
    case ClassifyCallbackKindNameChatgptExec{}: CallbackChatgptExec{}
    case ClassifyCallbackKindNameBoardText{}: CallbackBoardText{}
    case ClassifyCallbackKindNameApproval{}: CallbackApproval{}
    case ClassifyCallbackKindNameHook{}: CallbackHook{}
    case ClassifyCallbackKindNameAfterHook{}: CallbackAfterHook{}
    case ClassifyCallbackKindNameObserveContext{}: CallbackContext{}
    case ClassifyCallbackKindNameContextScope{}: CallbackCompaction{False{}}
    case ClassifyCallbackKindNameContextCompaction{}: CallbackCompaction{True{}}
    case ClassifyCallbackKindNameWorktreeCreate{}: CallbackWorktree{True{}}
    case ClassifyCallbackKindNameWorktreeArchive{}: CallbackWorktree{False{}}
    case ClassifyCallbackKindNameReasoning{}: CallbackReasoning{}
    case ClassifyCallbackKindNameModel{}: CallbackModel{}
    case ClassifyCallbackKindNameOther{}: CallbackDefaultTool{}

def classify_callback_kind(+kind: String) -> CallbackKind:
  classify_callback_kind_classified(classify_callback_kind_discriminant(kind))

def compaction_callback_kind(completed: Bool) -> String:
  match completed:
    case True{}: "compaction_completed"
    case False{}: "compaction_measured"

def compaction_callback(completed: Bool, +effect: J.Json, result: J.Json, error: Bool) -> J.Json:
  J.Object{List.append(&2, J.Field, callback_base(effect, compaction_callback_kind(completed)),
    [field("result", result), field("error", J.Boolean{error})])}

def worktree_callback_kind(created: Bool) -> String:
  match created:
    case True{}: "worktree_created"
    case False{}: "worktree_archived"

def worktree_callback_fields(created: Bool, ok: Bool, +result: J.Json) -> +List<J.Field>:
  match created ok:
    case True{} True{}: [field("root", J.get(result, "root")), field("workspace", J.get(result, "workspace")), field("guidance", J.get(result, "guidance"))]
    case True{} False{}: [field("root", J.get(result, "root")), field("message", J.Text{take(J.text(J.get(result, "message")), 1024n)})]
    case False{} True{}: [field("root", J.get(result, "root"))]
    case False{} False{}: [field("message", J.Text{take(J.text(J.get(result, "message")), 1024n)})]

def worktree_callback(+created: Bool, +effect: J.Json, +result: J.Json) -> J.Json:
  J.Object{List.append(&2, J.Field, [field("kind", J.Text{worktree_callback_kind(created)}),
    field("task_id", J.get(effect, "task_id")), field("ok", J.Boolean{J.boolean(J.get(result, "ok"))})],
    worktree_callback_fields(created, J.boolean(J.get(result, "ok")), result))}

def callback_classified(+kind: CallbackKind, +effect: J.Json, +result: J.Json) -> J.Json:
  match kind:
    case CallbackTaskTitle{}: J.Object{List.append(&2, J.Field, callback_base(effect, "task_title"), [field("ok", J.Boolean{True{}}), field("title", J.get(result, "title"))])}
    case CallbackChatgptExec{}: J.Object{List.append(&2, J.Field, Con{field("kind", J.Text{"chatgpt_result"}), Con{field("operation_id", J.get(effect, "operation_id")), Nil{}}}, callback_result_fields(fields(result), ["kind", "operation_id"]))}
    case CallbackBoardText{}: J.Object{List.append(&2, J.Field, Con{field("kind", J.Text{"board_text"}), Con{field("card_id", J.get(effect, "card_id")), Con{field("ticket", J.get(effect, "ticket")), Con{field("ok", J.Boolean{True{}}), Nil{}}}}}, callback_result_fields(fields(result), ["kind", "card_id", "ticket", "ok"]))}
    case CallbackApproval{}: J.Object{List.append(&2, J.Field, callback_base(effect, "approval"), Con{field("outcome", result), Nil{}})}
    case CallbackHook{}: J.Object{List.append(&2, J.Field, callback_base(effect, "hook"), Con{field("outcome", result), Nil{}})}
    case CallbackAfterHook{}: J.Object{List.append(&2, J.Field, callback_base(effect, "after_hook"), Con{field("operation_id", J.get(effect, "operation_id")), Con{field("outcome", result), Nil{}}})}
    case CallbackContext{}: J.Object{List.append(&2, J.Field, callback_base(effect, "context_observed"), Con{field("ok", J.Boolean{True{}}), Con{field("observations", J.get(result, "observations")), Nil{}}})}
    case CallbackCompaction{completed}: compaction_callback(completed, effect, result, False{})
    case CallbackWorktree{created}: worktree_callback(created, effect, result)
    case CallbackReasoning{}: J.Object{List.append(&2, J.Field, callback_base(effect, "reasoning"), Con{field("ok", J.Boolean{True{}}), callback_result_fields(fields(result), ["kind", "task_id", "ticket", "ok"])})}
    case CallbackModel{}: J.Object{List.append(&2, J.Field, callback_base(effect, "model"), Con{field("ok", J.Boolean{True{}}), Con{field("items", result), Nil{}}})}
    case CallbackDefaultTool{}: J.Object{List.append(&2, J.Field, callback_base(effect, "tool"), callback_result_fields(fields(result), ["kind", "task_id", "ticket"]))}

def callback_kind(+kind: String, +effect: J.Json, +result: J.Json) -> J.Json:
  callback_classified(classify_callback_kind(kind), effect, result)

def callback(+effect: J.Json, +result: J.Json) -> J.Json:
  callback_kind(J.text(J.get(effect, "kind")), effect, result)

def failure_message(+source: J.Json) -> String:
  take(J.text_or(J.get(source, "message"), "External execution failed"), 1024n)

def error_value(+message: String) -> J.Json:
  J.Object{Con{field("error", J.Object{Con{field("code", J.Text{"external_execution_failed"}), Con{field("message", J.Text{message}), Nil{}}}}), Nil{}}}

def failed_outcome(+effect: J.Json, +kind: String, +message: String) -> J.Json:
  J.Object{List.append(&2, J.Field, callback_base(effect, kind), Con{field("outcome", J.Object{Con{field("decision", J.Text{"failed"}), Con{field("reason", J.Text{message}), Nil{}}}}), Nil{}})}

def failed_model(+effect: J.Json, +message: String) -> J.Json:
  J.Object{List.append(&2, J.Field, callback_base(effect, "model"), Con{field("ok", J.Boolean{False{}}), Con{field("message", J.Text{message}), Nil{}}})}

# Bounded command arguments are admitted before physical launch.

def failure_classified(+kind: CallbackKind, +effect: J.Json, +message: String) -> J.Json:
  match kind:
    case CallbackTaskTitle{}: J.Object{List.append(&2, J.Field, callback_base(effect, "task_title"), [field("ok", J.Boolean{False{}}), field("message", J.Text{take(message, 400n)})])}
    case CallbackChatgptExec{}: J.Object{Con{field("kind", J.Text{"chatgpt_result"}), Con{field("operation_id", J.get(effect, "operation_id")), Con{field("error", J.Boolean{True{}}), Con{field("value", error_value(message)), Nil{}}}}}}
    case CallbackBoardText{}: J.Object{Con{field("kind", J.Text{"board_text"}), Con{field("card_id", J.get(effect, "card_id")), Con{field("ticket", J.get(effect, "ticket")), Con{field("ok", J.Boolean{False{}}), Con{field("message", J.Text{message}), Nil{}}}}}}}
    case CallbackContext{}: J.Object{List.append(&2, J.Field, callback_base(effect, "context_observed"), Con{field("ok", J.Boolean{False{}}), Con{field("message", J.Text{message}), Nil{}}})}
    case CallbackCompaction{completed}: compaction_callback(completed, effect, J.Object{[field("message", J.Text{message})]}, True{})
    case CallbackWorktree{created}: worktree_callback(created, effect, J.Object{[field("ok", J.Boolean{False{}}), field("root", J.Null{}), field("message", J.Text{message})]})
    case CallbackReasoning{}: J.Object{List.append(&2, J.Field, callback_base(effect, "reasoning"), Con{field("ok", J.Boolean{False{}}), Con{field("message", J.Text{message}), Nil{}}})}
    case CallbackHook{}: failed_outcome(effect, "hook", message)
    case CallbackApproval{}: failed_outcome(effect, "approval", take(message, 400n))
    case CallbackAfterHook{}: J.Object{List.append(&2, J.Field, fields(failed_outcome(effect, "after_hook", message)), Con{field("operation_id", J.get(effect, "operation_id")), Nil{}})}
    case CallbackModel{}: failed_model(effect, message)
    case _: J.Object{List.append(&2, J.Field, callback_base(effect, "tool"), Con{field("error", J.Boolean{True{}}), Con{field("value", error_value(message)), Nil{}}})}

def failure_input(+effect: J.Json, +message: String) -> J.Json:
  failure_classified(classify_callback_kind(J.text(J.get(effect, "kind"))), effect, message)

# Error-class identity is an external observation; the committed effect owns eligibility.
def context_limit_model(+effect: J.Json, +message: String) -> J.Json:
  J.Object{Con{field("failure_kind", J.Text{"context_limit"}), fields(failed_model(effect, message))}}

def failure_context_kind(+context_limit: Bool, +kind: CallbackKind) -> J.Json:
  match context_limit:
    case False{}: J.Null{}
    case True{}:
      match kind:
        case CallbackModel{}: J.Text{"context_limit"}
        case _: J.Null{}

def failure_context_classified(+context_limit: Bool, +kind: CallbackKind, +effect: J.Json, +message: String) -> J.Json:
  match context_limit:
    case False{}: failure_classified(kind, effect, message)
    case True{}:
      match kind:
        case CallbackModel{}: context_limit_model(effect, message)
        case _: failure_classified(kind, effect, message)

def complete_failure_input(+effect: J.Json, +message: String, +context_limit: Bool) -> J.Json:
  failure_context_classified(context_limit, classify_callback_kind(J.text(J.get(effect, "kind"))), effect, message)

def bash_bounds(+valid: Bool, +timeout: J.Json, +maximum: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure_code("TypeError", "Malformed Bash effect")
    case True{}: Model.success(J.Object{Con{field("timeout", timeout), Con{field("maximum", maximum), Nil{}}}})

def bash_arguments(+source: J.Json) -> J.Json:
  +arguments = J.get(source, "arguments")
  +limits = J.get(source, "limits")
  +timeout = default_null(J.get(arguments, "timeout_ms"), J.get(limits, "bash_timeout_ms"))
  +maximum = default_null(J.get(arguments, "max_output_length"), J.get(limits, "bash_default_output_length"))
  bash_bounds(J.is_text(J.get(arguments, "command")) && Bool.not(String.eq(J.text(J.get(arguments, "command")), "")) && well(J.text(J.get(arguments, "command"))) &&
    no_nul(J.text(J.get(arguments, "command"))) && Model.nonnegative_le(timeout, "1800000") && Model.decimal_le("100", number_text(timeout)) && positive_safe_integer(J.get(limits, "bash_max_output_length")) &&
    positive_safe_integer(maximum) && Model.nonnegative_le(maximum, number_text(J.get(limits, "bash_max_output_length"))) && allowed(fields(arguments), ["command", "timeout_ms", "max_output_length", "sandbox_permissions", "justification"]), timeout, maximum)

def artifact_observed(+truncated: Bool, +observed: Bool, +name: String, +artifact: J.Json) -> +List<&2, J.Field>:
  match truncated observed:
    case True{} True{}: Con{field(name, artifact), Nil{}}
    case _ _: Nil{}

def artifact_field(+name: String, +output: J.Json, +artifact: J.Json) -> +List<&2, J.Field>:
  artifact_observed(J.boolean(J.get(output, "truncated")), Bool.not(J.same(artifact, J.Null{})), name, artifact)

def process_value(+source: J.Json) -> J.Json:
  +out = J.get(source, "out")
  +err = J.get(source, "err")
  J.Object{List.append(&2, J.Field,
    Con{field("exit_code", J.get(source, "exitCode")), Con{field("signal", J.get(source, "exitSignal")), Con{field("stdout", J.get(out, "text")), Con{field("stderr", J.get(err, "text")),
    Con{field("stdout_truncated", J.get(out, "truncated")), Con{field("stderr_truncated", J.get(err, "truncated")), Con{field("stdout_bytes", J.get(out, "total_bytes")), Con{field("stderr_bytes", J.get(err, "total_bytes")),
    Con{field("stdout_omitted_characters", J.get(out, "omitted_characters")), Con{field("stderr_omitted_characters", J.get(err, "omitted_characters")), Nil{}}}}}}}}}}},
    List.append(&2, J.Field, artifact_field("stdout_artifact", out, J.get(source, "outArtifact")), artifact_field("stderr_artifact", err, J.get(source, "errArtifact"))))}

def scalar_text(+value: J.Json) -> String:
  match value:
    case J.Number{lexeme}: lexeme
    case J.Text{text}: text
    case J.Null{}: "null"
    case _: ""

def exit_message(+signal: J.Json, +code: J.Json) -> String:
  match signal:
    case J.Null{}: "Command exited with status " ++ scalar_text(code)
    case J.Text{""}: "Command exited with status " ++ scalar_text(code)
    case _: "Command ended with signal " ++ scalar_text(signal)

def exit_reason(+success: Bool, +source: J.Json) -> J.Json:
  match success:
    case True{}: J.Null{}
    case False{}: J.Object{Con{field("code", J.Text{"command_failed"}), Con{field("message", J.Text{exit_message(J.get(source, "exitSignal"), J.get(source, "exitCode"))}), Nil{}}}}

def termination_observed(+reason: J.Json, +source: J.Json) -> J.Json:
  match reason:
    case J.Null{}: exit_reason(J.same(J.get(source, "exitCode"), J.nat(0n)) && J.same(J.get(source, "exitSignal"), J.Null{}), source)
    case reason: reason

def termination_reason(+source: J.Json) -> J.Json:
  termination_observed(J.get(source, "reason"), source)

def process_reason(+reason: J.Json, +value: J.Json) -> J.Json:
  match reason:
    case J.Null{}: J.Object{Con{field("value", value), Con{field("error", J.Boolean{False{}}), Nil{}}}}
    case _: J.Object{Con{field("value", J.Object{List.append(&2, J.Field, fields(value), Con{field("error", reason), Nil{}})}), Con{field("error", J.Boolean{True{}}), Nil{}}}}

def process_result(+source: J.Json) -> J.Json:
  process_reason(termination_reason(source), process_value(source))

def execution_admission(+plan: J.Json) -> J.Json:
  +access = J.text(J.get(plan, "access"))
  +sandbox = J.get(plan, "sandbox")
  +scope = J.get(plan, "scope")
  type_outcome_value(J.is_object(plan) && (String.eq(access, "sandboxed") || String.eq(access, "unrestricted")) &&
    (String.eq(J.text(J.get(sandbox, "mode")), "workspace-write") || String.eq(J.text(J.get(sandbox, "mode")), "read-only")) && bool_type(J.get(sandbox, "network_access")) &&
    (Bool.not(has(plan, "scope")) || String.eq(J.text(scope), "project")) && (Bool.not(String.eq(J.text(scope), "project")) || String.eq(access, "sandboxed")), plan, "Malformed committed sandbox execution plan")

def platform_admission(+valid: Bool, +plan: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure("Selvedge supports Linux and macOS only")
    case True{}: execution_admission(plan)

def paths_valid(+items: +List<&2, J.Json>) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{+head, rest}: J.is_text(head) && no_nul(J.text(head)) && well(J.text(head)) && paths_valid(rest)

def launch_next_case(+accepted: Bool, +result: J.Json, +next: J.Json) -> J.Json:
  match accepted:
    case False{}: result
    case True{}: next

def launch_next(+result: J.Json, +next: J.Json) -> J.Json:
  launch_next_case(J.boolean(J.get(result, "ok")), result, next)

def plan_admission(+source: J.Json) -> J.Json:
  +plan = J.get(source, "plan")
  +options = J.get(source, "options")
  +platform = J.text(J.get(options, "platform"))
  launch_next(type_outcome_value(Bool.not(has(options, "managedWorktreeRoot")) || paths_valid([J.get(options, "managedWorktreeRoot")]), J.Null{}, "Invalid managed Worktree root"), platform_admission(String.eq(platform, "linux") || String.eq(platform, "darwin"), plan))

def writable_mode(+writable: Bool, +workspace: J.Json) -> J.Json:
  match writable:
    case True{}: J.get(workspace, "roots")
    case False{}: J.Array{Nil{}}

def writable_roots(+plan: J.Json, +workspace: J.Json) -> J.Json:
  writable_mode(String.eq(J.text(J.get(J.get(plan, "sandbox"), "mode")), "workspace-write"), workspace)

def workspace_project(+missing: Bool, +source: J.Json, +project: Bool) -> J.Json:
  match missing:
    case True{}: Model.failure("Project execution requires a primary Workspace root")
    case False{}: Model.success(J.Object{Con{field("cwd", default_null(J.get(J.get(source, "workspace"), "primary_root"), J.Text{"/"})), Con{field("projectOnly", J.Boolean{project}), Con{field("unrestricted", J.Boolean{String.eq(J.text(J.get(J.get(source, "plan"), "access")), "unrestricted")}), Con{field("writableRoots", writable_roots(J.get(source, "plan"), J.get(source, "workspace"))), Nil{}}}}}})

def workspace_primary(+source: J.Json) -> J.Json:
  +plan = J.get(source, "plan")
  +workspace = J.get(source, "workspace")
  +project = String.eq(J.text(J.get(plan, "scope")), "project")
  workspace_project(project && (J.same(J.get(workspace, "primary_root"), J.Null{}) || String.eq(J.text(J.get(workspace, "primary_root")), "")), source, project)

def workspace_same(+valid: Bool, +source: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure("A workspace root changed after it was committed; reselect the workspace before executing")
    case True{}: workspace_primary(source)

def workspace_bound(+source: J.Json) -> J.Json:
  +workspace = J.get(source, "workspace")
  +committed = J.get(J.get(source, "plan"), "workspace")
  workspace_same(has(committed, "primary_root") && J.same(J.get(workspace, "roots"), J.get(committed, "roots")) && J.same(J.get(workspace, "primary_root"), J.get(committed, "primary_root")), source)

def within(+root: String, +protected: +List<&2, J.Json>, +separator: String) -> Bool:
  match protected:
    case Nil{}: False{}
    case Con{+head, rest}: String.eq(root, J.text(head)) || String.starts_with(root, J.text(head) ++ separator) || within(root, rest, separator)

def any_within(+roots: +List<&2, J.Json>, +protected: List<&2, J.Json>, +separator: String) -> Bool:
  match roots:
    case Nil{}: False{}
    case Con{head, rest}: within(J.text(head), protected, separator) || any_within(rest, protected, separator)

def strictly_within(+root: String, +protected: +List<&2, J.Json>, +separator: String) -> Bool:
  match protected:
    case Nil{}: False{}
    case Con{head, rest}: String.starts_with(root, J.text(head) ++ separator) || strictly_within(root, rest, separator)

def managed_worktree_admission(+source: J.Json) -> J.Json:
  +root = J.get(source, "managedWorktreeRoot")
  +option = J.get(J.get(source, "options"), "managedWorktreeRoot")
  outcome_value(J.same(root, option) && (J.same(root, J.Null{}) ||
    (paths_valid([root]) && Bool.not(J.boolean(J.get(source, "projectOnly"))) &&
      strictly_within(J.text(root), J.items(J.get(source, "protectedRoots")), J.text(J.get(source, "separator"))) &&
      Bool.not(any_within(J.items(J.get(source, "protectedRoots")), [root], J.text(J.get(source, "separator")))) &&
      within(J.text(J.get(J.get(source, "workspace"), "primary_root")), [root], J.text(J.get(source, "separator"))))), J.Null{}, "Managed Worktree does not match its committed Workspace and private service home")

def managed_writable_item(+managed: Bool, +root: J.Json, +rest: +List<&2, J.Json>) -> +List<&2, J.Json>:
  match managed:
    case True{}: Con{root, rest}
    case False{}: rest

def managed_writable_items(+items: +List<&2, J.Json>, +root: J.Json, +separator: String) -> +List<&2, J.Json>:
  match items:
    case Nil{}: Nil{}
    case Con{+head, rest}:
      managed_writable_item(Bool.not(J.same(root, J.Null{})) && within(J.text(head), [root], separator), head, managed_writable_items(rest, root, separator))

def managed_writable_roots(+source: J.Json) -> +List<&2, J.Json>:
  managed_writable_items(J.items(J.get(source, "writableRoots")), J.get(source, "managedWorktreeRoot"), J.text(J.get(source, "separator")))

def protected_workspace(+source: J.Json) -> J.Json:
  outcome_value(Bool.not(J.boolean(J.get(source, "projectOnly")) && any_within(J.items(J.get(J.get(source, "workspace"), "roots")), J.items(J.get(source, "protectedRoots")), J.text(J.get(source, "separator")))), J.Null{}, "A ChatGPT Workspace cannot be inside the private service home")

def environment_name_removed(+name: String) -> Bool:
  String.eq(name, "BASH_ENV") || String.eq(name, "ENV") || String.starts_with(name, "LD_") || String.starts_with(name, "DYLD_") || names(["TMPDIR", "TMP", "TEMP", "HISTFILE"], name)

def retain_environment_name(+remove: Bool, +name: J.Json, +rest: List<&2, J.Json>) -> List<&2, J.Json>:
  match remove:
    case True{}: rest
    case False{}: Con{name, rest}

def clean_environment_names(+items: List<&2, J.Json>) -> List<&2, J.Json>:
  match items:
    case Nil{}: Nil{}
    case Con{+name, rest}: retain_environment_name(environment_name_removed(J.text(name)), name, clean_environment_names(rest))

def environment_names(+project: Bool, +source: J.Json) -> J.Json:
  match project:
    case True{}: J.Array{Nil{}}
    case False{}: J.Array{clean_environment_names(J.items(J.get(source, "names")))}

type EnvironmentPathName is Data:
  EnvironmentPathNameDarwin{}
  EnvironmentPathNameOther{}

def environment_path_discriminant(+value: String) -> EnvironmentPathName:
  Bool.pick(EnvironmentPathName, String.eq(value, "darwin"), EnvironmentPathNameDarwin{},
    EnvironmentPathNameOther{})

def environment_path_classified(+platform: EnvironmentPathName) -> String:
  match platform:
    case EnvironmentPathNameDarwin{}: "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
    case EnvironmentPathNameOther{}: "/usr/bin:/bin:/usr/sbin:/sbin"

def environment_path(+platform: String) -> String:
  environment_path_classified(environment_path_discriminant(platform))

# Instruction selection is native; the host only writes the observed little-endian ABI bytes.

def environment_overrides(+project: Bool, +source: J.Json, +scratch: J.Json) -> J.Json:
  match project:
    case True{}: J.Object{Con{field("PATH", J.Text{environment_path(J.text(J.get(source, "platform")))}), Con{field("HOME", scratch), Con{field("TMPDIR", scratch), Con{field("TMP", scratch), Con{field("TEMP", scratch), Con{field("HISTFILE", J.Text{"/dev/null"}), Con{field("LANG", J.Text{"C"}), Con{field("TERM", J.Text{"dumb"}), Con{field("GIT_CONFIG_NOSYSTEM", J.Text{"1"}), Nil{}}}}}}}}}}}
    case False{}: J.Object{[field("TMPDIR", scratch), field("TMP", scratch), field("TEMP", scratch), field("HISTFILE", J.Text{"/dev/null"})]}

def environment_plan(+project: Bool, +source: J.Json, +scratch: J.Json) -> J.Json:
  J.Object{[field("names", environment_names(project, source)), field("overrides", environment_overrides(project, source, scratch))]}

def environment(+source: J.Json) -> J.Json:
  environment_plan(J.boolean(J.get(source, "projectOnly")), source, J.get(source, "scratch"))


def bpf_instruction(+code: Nat, +jt: Nat, +jf: Nat, +k: J.Json) -> J.Json:
  J.Object{[field("code", J.nat(code)), field("jt", J.nat(jt)), field("jf", J.nat(jf)), field("k", k)]}

def bpf_denied(+syscalls: +List<&2, J.Json>) -> +List<&2, J.Json>:
  match syscalls:
    case Nil{}: Nil{}
    case Con{number, rest}: Con{bpf_instruction(21n, 0n, 1n, number), Con{bpf_instruction(6n, 0n, 0n, J.Number{"327681"}), bpf_denied(rest)}}

type BpfX32Name is Data:
  BpfX32NameX64{}
  BpfX32NameOther{}

def bpf_x32_discriminant(+value: String) -> BpfX32Name:
  Bool.pick(BpfX32Name, String.eq(value, "x64"), BpfX32NameX64{},
    BpfX32NameOther{})

def bpf_x32_classified(+architecture: BpfX32Name) -> +List<&2, J.Json>:
  match architecture:
    case BpfX32NameX64{}: [bpf_instruction(53n, 0n, 1n, J.Number{"1073741824"}), bpf_instruction(6n, 0n, 0n, J.Number{"327681"})]
    case BpfX32NameOther{}: Nil{}

def bpf_x32(+architecture: String) -> +List<&2, J.Json>:
  bpf_x32_classified(bpf_x32_discriminant(architecture))

def bpf_socket(+network: Bool, +socket: Nat) -> +List<&2, J.Json>:
  match network:
    case False{}: [bpf_instruction(21n, 0n, 1n, J.nat(socket)), bpf_instruction(6n, 0n, 0n, J.Number{"327681"})]
    case True{}: [bpf_instruction(21n, 0n, 5n, J.nat(socket)), bpf_instruction(32n, 0n, 0n, J.Number{"16"}), bpf_instruction(21n, 2n, 0n, J.Number{"2"}), bpf_instruction(21n, 1n, 0n, J.Number{"10"}), bpf_instruction(6n, 0n, 0n, J.Number{"327681"}), bpf_instruction(6n, 0n, 0n, J.Number{"2147418112"})]

def bpf_program(+architecture: String, +network: Bool, +audit: J.Json, +socket: Nat, +clone: Nat, +denied: +List<&2, J.Json>) -> J.Json:
  J.Array{List.append(&2, J.Json,
    [bpf_instruction(32n, 0n, 0n, J.Number{"4"}), bpf_instruction(21n, 1n, 0n, audit), bpf_instruction(6n, 0n, 0n, J.Number{"2147483648"}), bpf_instruction(32n, 0n, 0n, J.Number{"0"})],
    List.append(&2, J.Json, bpf_x32(architecture), List.append(&2, J.Json, bpf_denied(denied), List.append(&2, J.Json,
      [bpf_instruction(21n, 0n, 1n, J.Number{"435"}), bpf_instruction(6n, 0n, 0n, J.Number{"327718"}), bpf_instruction(21n, 0n, 3n, J.nat(clone)), bpf_instruction(32n, 0n, 0n, J.Number{"16"}), bpf_instruction(69n, 0n, 1n, J.Number{"2114060288"}), bpf_instruction(6n, 0n, 0n, J.Number{"327681"}), bpf_instruction(32n, 0n, 0n, J.Number{"0"})],
      List.append(&2, J.Json, bpf_socket(network, socket), [bpf_instruction(6n, 0n, 0n, J.Number{"2147418112"})]))))) }

def seccomp_arch(+architecture: String, +network: Bool) -> J.Json:
  match architecture:
    case "x64": Model.success(bpf_program(architecture, network, J.Number{"3221225534"}, 41n, 56n, [J.nat(101n), J.nat(133n), J.nat(155n), J.nat(161n), J.nat(165n), J.nat(166n), J.nat(167n), J.nat(168n), J.nat(169n), J.nat(172n), J.nat(173n), J.nat(175n), J.nat(176n), J.nat(246n), J.nat(248n), J.nat(249n), J.nat(250n), J.nat(259n), J.nat(272n), J.nat(298n), J.nat(303n), J.nat(304n), J.nat(308n), J.nat(310n), J.nat(311n), J.nat(313n), J.nat(320n), J.nat(321n), J.nat(323n)]))
    case "arm64": Model.success(bpf_program(architecture, network, J.Number{"3221225655"}, 198n, 220n, [J.nat(33n), J.nat(39n), J.nat(40n), J.nat(41n), J.nat(51n), J.nat(97n), J.nat(104n), J.nat(105n), J.nat(106n), J.nat(117n), J.nat(142n), J.nat(217n), J.nat(218n), J.nat(219n), J.nat(224n), J.nat(225n), J.nat(241n), J.nat(264n), J.nat(265n), J.nat(268n), J.nat(270n), J.nat(271n), J.nat(273n), J.nat(280n), J.nat(282n), J.nat(294n)]))
    case _: Model.failure("Linux sandbox does not support architecture " ++ architecture)

def seccomp(+source: J.Json) -> J.Json:
  seccomp_arch(J.text(J.get(source, "architecture")), J.boolean(J.get(source, "networkAccess")))

def sbpl_char(+code: U32) -> String:
  match code:
    case 8: "\\b"
    case 9: "\\t"
    case 10: "\\n"
    case 12: "\\f"
    case 13: "\\r"
    case _: J.escaped_char(code)

def sbpl_text(+text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{Chr{code}, rest}: sbpl_char(code) ++ sbpl_text(rest)

def sbpl_quote(+text: String) -> String:
  "\"" ++ sbpl_text(text) ++ "\""

def path_rule(+root: J.Json, +kind: String) -> String:
  "(" ++ kind ++ " " ++ sbpl_quote(J.text(root)) ++ ")"

def join(+items: +List<&2, String>, +separator: String) -> String:
  match items:
    case Nil{}: ""
    case Con{head, Nil{}}: head
    case Con{head, rest}: head ++ separator ++ join(rest, separator)

def path_rules(+items: +List<&2, J.Json>, +kind: String) -> +List<&2, String>:
  match items:
    case Nil{}: Nil{}
    case Con{root, rest}: Con{path_rule(root, kind), path_rules(rest, kind)}

def deny_read(+root: J.Json, +readable: Bool) -> +List<&2, String>:
  match readable:
    case True{}: Con{"(deny file-read* " ++ path_rule(root, "subpath") ++ ")", Nil{}}
    case False{}: Nil{}

def protected_write_path(+root: J.Json, +exceptions: +List<&2, J.Json>) -> String:
  match exceptions:
    case Nil{}: path_rule(root, "subpath")
    case exceptions: "(require-all " ++ path_rule(root, "subpath") ++ " " ++ join(Std.map(~J.Json, ~String, ~(exception => "(require-not " ++ path_rule(exception, "subpath") ++ ")"), exceptions), " ") ++ ")"

def protected_rules(+roots: +List<&2, J.Json>, +ancestors: +List<&2, J.Json>, +readable: Bool, +exceptions: List<&2, J.Json>) -> +List<&2, String>:
  match roots ancestors:
    case Nil{} _: Nil{}
    case Con{+root, rest} Con{parents, tail}:
      List.append(&2, String, Con{"(deny file-write* " ++ protected_write_path(root, exceptions) ++ ")", deny_read(root, readable)},
        List.append(&2, String, Std.map(~J.Json, ~String, ~(parent => "(deny file-write-unlink " ++ path_rule(parent, "literal") ++ ")"), J.items(parents)), protected_rules(rest, tail, readable, exceptions)))
    case _ _: Nil{}

def unique_append(+found: Bool, +text: String, +acc: +List<&2, String>) -> +List<&2, String>:
  match found:
    case True{}: acc
    case False{}: List.append(&2, String, acc, Con{text, Nil{}})

def unique_paths(+items: +List<&2, J.Json>, +acc: +List<&2, String>) -> +List<&2, String>:
  match items:
    case Nil{}: acc
    case Con{+head, rest}: unique_paths(rest, unique_append(names(acc, J.text(head)), J.text(head), acc))

def flatten(+items: +List<&2, J.Json>) -> +List<&2, J.Json>:
  match items:
    case Nil{}: Nil{}
    case Con{head, rest}: List.append(&2, J.Json, J.items(head), flatten(rest))

def seatbelt_reads(+restricted: Bool, +reads: +List<&2, J.Json>, +ancestors: +List<&2, String>) -> +List<&2, String>:
  match restricted:
    case False{}: ["(allow file-read*)"]
    case True{}: ["(allow file-read-data (literal \"/\"))", "(allow file-read* " ++ join(path_rules(reads, "subpath"), " ") ++ ")", "(allow file-read-metadata " ++ join(Std.map(~String, ~String, ~(parent => "(literal " ++ sbpl_quote(parent) ++ ")"), ancestors), " ") ++ ")"]

def seatbelt_network(+network: Bool) -> +List<&2, String>:
  match network:
    case False{}: Nil{}
    case True{}: ["(allow network-outbound (remote ip \"*:*\"))", "(allow network-inbound (local ip \"*:*\"))", "(allow mach-lookup (global-name \"com.apple.system.config.network_change\") (global-name \"com.apple.mDNSResponder\") (global-name \"com.apple.trustd.agent\"))"]

def seatbelt_rules(+source: J.Json, +writes: +List<&2, J.Json>, +reads: +List<&2, J.Json>) -> +List<&2, String>:
  List.append(&2, String, ["(version 1)", "(deny default)", "(allow process-exec process-fork)", "(allow signal (target same-sandbox))", "(allow process-info* (target same-sandbox))"],
    List.append(&2, String, seatbelt_reads(has(source, "readableRoots") && Bool.not(J.same(J.get(source, "readableRoots"), J.Null{})), reads, unique_paths(flatten(J.items(J.get(source, "readAncestors"))), Nil{})),
      List.append(&2, String, ["(allow sysctl-read)", "(allow mach-lookup (global-name \"com.apple.system.opendirectoryd.libinfo\"))", "(allow ipc-posix-sem)", "(allow file-write-data (require-all (literal \"/dev/null\") (vnode-type CHARACTER-DEVICE)))", "(allow file-write*\n  " ++ join(path_rules(writes, "subpath"), "\n  ") ++ ")"],
        List.append(&2, String, protected_rules(J.items(J.get(source, "readOnlyPaths")), J.items(J.get(source, "protectedAncestors")), has(source, "readableRoots") && Bool.not(J.same(J.get(source, "readableRoots"), J.Null{})), J.items(J.get(source, "readOnlyExceptions"))),
          List.append(&2, String, Std.map(~J.Json, ~String, ~(root => "(deny file-write-unlink " ++ path_rule(root, "literal") ++ ")"), J.items(J.get(source, "readOnlyExceptions"))), seatbelt_network(J.boolean(J.get(source, "networkAccess"))))))))

def seatbelt_valid(+valid: Bool, +source: J.Json, +writes: +List<&2, J.Json>, +reads: +List<&2, J.Json>) -> J.Json:
  match valid:
    case False{}: Model.failure_code("TypeError", "Invalid sandbox path")
    case True{}: Model.success(J.Text{join(seatbelt_rules(source, writes, reads), "\n")})

def seatbelt(+source: J.Json) -> J.Json:
  +writes = List.append(&2, J.Json, J.items(J.get(source, "writableRoots")), Con{J.get(source, "scratch"), Nil{}})
  +reads = List.append(&2, J.Json, J.items(J.get(source, "readableRoots")), Con{J.get(source, "scratch"), Nil{}})
  seatbelt_valid(paths_valid(writes) && paths_valid(J.items(J.get(source, "readOnlyPaths"))) && paths_valid(J.items(J.get(source, "readOnlyExceptions"))) && paths_valid(reads), source, writes, reads)

def binding(+root: J.Json, +readonly: Bool) -> J.Json:
  J.Object{Con{field("root", root), Con{field("readonly", J.Boolean{readonly}), Nil{}}}}

def binding_items(+items: List<&2, J.Json>, +readonly: Bool) -> List<&2, J.Json>:
  match items:
    case Nil{}: Nil{}
    case Con{root, rest}: Con{binding(root, readonly), binding_items(rest, readonly)}

def binding_project(+project: Bool, +source: J.Json) -> J.Json:
  match project:
    case True{}: J.Array{List.append(&2, J.Json, binding_items(J.items(J.get(J.get(source, "workspace"), "roots")), String.eq(J.text(J.get(J.get(J.get(source, "plan"), "sandbox"), "mode")), "read-only")), Con{binding(J.get(source, "scratch"), False{}), Nil{}})}
    case False{}: J.Array{List.append(&2, J.Json, Std.map(~J.Json, ~J.Json, ~(root => binding(root, False{})), List.append(&2, J.Json, J.items(J.get(source, "writableRoots")), Con{J.get(source, "scratch"), Nil{}})),
      List.append(&2, J.Json, binding_items(J.items(J.get(source, "protectedRoots")), True{}), binding_items(managed_writable_roots(source), False{})))}

def bindings(+source: J.Json) -> J.Json:
  binding_project(J.boolean(J.get(source, "projectOnly")), source)

def bind_flag(+readonly: Bool) -> String:
  match readonly:
    case True{}: "--ro-bind"
    case False{}: "--bind"

def bind_arguments(+items: +List<&2, J.Json>) -> +List<&2, J.Json>:
  match items:
    case Nil{}: Nil{}
    case Con{+head, rest}: List.append(&2, J.Json, [J.Text{bind_flag(J.boolean(J.get(head, "readonly")))}, J.Text{"/proc/self/fd/" ++ scalar_text(J.get(head, "descriptor"))}, J.get(head, "root")], bind_arguments(rest))

def runtime_arguments(+items: +List<&2, J.Json>) -> +List<&2, J.Json>:
  match items:
    case Nil{}: Nil{}
    case Con{+head, rest}: List.append(&2, J.Json, [J.Text{"--ro-bind"}, J.get(head, "canonical"), J.get(head, "root")], runtime_arguments(rest))

def protected_arguments(+items: +List<&2, J.Json>) -> +List<&2, J.Json>:
  match items:
    case Nil{}: Nil{}
    case Con{+head, rest}: List.append(&2, J.Json, [J.Text{"--tmpfs"}, head, J.Text{"--remount-ro"}, head], protected_arguments(rest))

def linux_root(+project: Bool) -> +List<&2, J.Json>:
  match project:
    case True{}: [J.Text{"--tmpfs"}, J.Text{"/"}]
    case False{}: [J.Text{"--ro-bind"}, J.Text{"/"}, J.Text{"/"}]

def linux_network(+network: Bool) -> +List<&2, J.Json>:
  match network:
    case True{}: Nil{}
    case False{}: [J.Text{"--unshare-net"}]

def linux_runtime(+project: Bool, +source: J.Json) -> +List<&2, J.Json>:
  match project:
    case True{}: runtime_arguments(J.items(J.get(source, "runtimeReads")))
    case False{}: Nil{}

def linux_protected(+project: Bool, +source: J.Json) -> +List<&2, J.Json>:
  match project:
    case True{}: protected_arguments(J.items(J.get(source, "protectedRoots")))
    case False{}: Nil{}

def linux_prefix(+source: J.Json) -> J.Json:
  +project = J.boolean(J.get(source, "projectOnly"))
  J.Array{List.append(&2, J.Json, [J.Text{"--die-with-parent"}, J.Text{"--new-session"}, J.Text{"--unshare-user"}, J.Text{"--unshare-pid"}, J.Text{"--unshare-ipc"}, J.Text{"--unshare-uts"}, J.Text{"--cap-drop"}, J.Text{"ALL"}],
    List.append(&2, J.Json, linux_root(project), List.append(&2, J.Json, linux_network(J.boolean(J.get(J.get(J.get(source, "plan"), "sandbox"), "network_access"))), List.append(&2, J.Json, linux_runtime(project, source), List.append(&2, J.Json, bind_arguments(J.items(J.get(source, "bindings"))), List.append(&2, J.Json, linux_protected(project, source), [J.Text{"--proc"}, J.Text{"/proc"}, J.Text{"--dev"}, J.Text{"/dev"}, J.Text{"--seccomp"}, J.Text{"3"}, J.Text{"--chdir"}, J.get(source, "cwd"), J.Text{"--"}, J.Text{"/bin/bash"}, J.Text{"--noprofile"}, J.Text{"--norc"}]))))))}

def darwin_prefix(+source: J.Json) -> J.Json:
  J.Array{[J.Text{"-p"}, J.get(source, "profile"), J.Text{"/bin/bash"}, J.Text{"--noprofile"}, J.Text{"--norc"}]}

def request_approval(+source: J.Json) -> J.Json:
  type_outcome_value(String.eq(J.text(J.get(J.get(source, "effect"), "kind")), "approval"), J.Null{}, "Expected a committed approval effect")

def request_task_text_kind(+valid: Bool, +effect: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure_code("TypeError", "Expected a committed task text effect")
    case True{}: type_outcome_value(Bool.not(truthy(J.get(J.get(effect, "model"), "adaptive_reasoning"))), J.Null{}, "Task text generation requires an ordinary model profile")

def request_task_text(+source: J.Json) -> J.Json:
  +effect = J.get(source, "effect")
  request_task_text_kind((String.eq(J.text(J.get(effect, "kind")), "board_text") || String.eq(J.text(J.get(effect, "kind")), "task_title")) && J.is_text(J.get(effect, "prompt")), effect)

def workspace_admit(+value: J.Json) -> J.Json:
  type_outcome_value(J.is_object(value) && array(J.get(value, "roots")) && Nat.is_le(length(J.items(J.get(value, "roots"))), 32n) && allowed(fields(value), ["roots", "primary_root"]), value, "A workspace requires at most 32 roots and an optional primary_root")

def root_admit(+source: J.Json) -> J.Json:
  +value = J.get(source, "root")
  type_outcome_value(J.is_text(value) && J.boolean(J.get(source, "absolute")) && no_nul(J.text(value)) && well(J.text(value)) && Nat.is_le(J.utf8_length(J.text(value)), 4096n), value, "Workspace roots must be bounded absolute directory paths")

def distinct(+items: +List<&2, J.Json>, +seen: +List<&2, String>) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{+head, rest}: Bool.not(names(seen, J.text(head))) && distinct(rest, Con{J.text(head), seen})

def workspace_distinct(+source: J.Json) -> J.Json:
  type_outcome_value(distinct(J.items(J.get(source, "roots")), Nil{}), J.Null{}, "Workspace roots must be distinct after resolving symbolic links")

def workspace_selected(+source: J.Json) -> J.Json:
  +primary = J.get(source, "primary")
  type_outcome_value(J.same(primary, J.Null{}) || names(J.text_values(J.items(J.get(source, "roots"))), J.text(primary)), J.Object{Con{field("roots", J.get(source, "roots")), Con{field("primary_root", primary), Nil{}}}}, "The primary root must be one of the workspace roots")

# Worktree paths and receipt meaning are derived once from the observed home
# and the committed task coordinates. Git and filesystem calls observe facts.
def worktree_select(accepted: Bool, yes: J.Json, no: J.Json) -> J.Json:
  match accepted:
    case True{}: yes
    case False{}: no

def worktree_child(+parent: String, +leaf: String) -> String:
  J.text(worktree_select(String.ends_with(parent, "/"), J.Text{parent ++ leaf}, J.Text{parent ++ "/" ++ leaf}))

def worktree_contains(+root: String, +parent: String) -> Bool:
  String.eq(root, parent) || String.starts_with(root, worktree_child(parent, ""))

def worktree_locations_value(+source: J.Json) -> J.Json:
  +home = J.text(J.get(source, "home"))
  +storage = worktree_child(home, "worktrees")
  +name = "task-" ++ Nat.show(J.natural_or(J.natural(J.get(source, "task_id")), 0n))
  J.Object{[field("home", J.Text{home}), field("storage", J.Text{storage}),
    field("active", J.Text{worktree_child(storage, name)}),
    field("archived", J.Text{worktree_child(worktree_child(storage, "archived"), name)}),
    field("receipt", J.Text{worktree_child(worktree_child(storage, "receipts"), name ++ ".json")})]}

def worktree_locations(+source: J.Json) -> J.Json:
  type_outcome_value(J.is_text(J.get(source, "home")) && String.starts_with(J.text(J.get(source, "home")), "/") &&
    Model.nonnegative_le(J.get(source, "task_id"), "9007199254740991"), worktree_locations_value(source), "Invalid managed worktree task identity or service home")

def worktree_path_admission(+source: J.Json) -> J.Json:
  +operation = J.text(J.get(source, "operation"))
  +root = J.get(source, "root")
  outcome_value((String.eq(operation, "source") &&
      worktree_contains(J.text(J.get(source, "primary")), J.text(J.get(source, "repository"))) &&
      Bool.not(worktree_contains(J.text(J.get(source, "home")), J.text(J.get(source, "repository"))))) ||
    (String.eq(operation, "archive") && (J.same(root, J.get(J.get(source, "files"), "active")) || J.same(root, J.get(J.get(source, "files"), "archived")))) ||
    (String.eq(operation, "copy") && worktree_contains(J.text(J.get(source, "source")), J.text(J.get(source, "repository"))) &&
      worktree_contains(J.text(J.get(source, "destination")), J.text(root)) && Bool.not(J.same(J.get(source, "destination"), root))),
    J.Null{}, "Managed worktree path must remain in its admitted repository or owned storage; service home must stay outside the source repository")

def worktree_receipt(+source: J.Json) -> J.Json:
  +value = J.get(source, "value")
  +workspace = J.get(value, "workspace")
  +root = J.get(value, "root")
  +files = J.get(source, "files")
  type_outcome_value(J.is_object(value) && allowed(fields(value), ["task_id", "source_root", "root", "workspace", "status"]) &&
    J.same(J.get(value, "task_id"), J.get(source, "task_id")) && J.same(J.get(value, "source_root"), J.get(source, "source_root")) &&
    ((J.same(J.get(value, "status"), J.Text{"ready"}) && J.same(root, J.get(files, "active"))) ||
      (J.same(J.get(value, "status"), J.Text{"archived"}) && J.same(root, J.get(files, "archived")))) &&
    J.boolean(J.get(workspace_admit(workspace), "ok")) && paths_valid(J.items(J.get(workspace, "roots"))) &&
    names(J.text_values(J.items(J.get(workspace, "roots"))), J.text(J.get(workspace, "primary_root"))) &&
    worktree_contains(J.text(J.get(workspace, "primary_root")), J.text(root)), value, "Invalid managed worktree receipt")

def worktree_relocated_path(selected: Bool, +value: String, +previous: String, next: String) -> String:
  match selected:
    case False{}: value
    case True{}: next ++ String.drop(value, String.length(previous))

def worktree_map_path(+value: J.Json, +previous: String, +next: String, descendants: Bool) -> J.Json:
  J.Text{worktree_relocated_path(String.eq(J.text(value), previous) || (descendants && worktree_contains(J.text(value), previous)), J.text(value), previous, next)}

def worktree_map_roots(roots: +List<J.Json>, +previous: String, +next: String, +descendants: Bool) -> +List<J.Json>:
  match roots:
    case Nil{}: Nil{}
    case Con{root, rest}: Con{worktree_map_path(root, previous, next, descendants), worktree_map_roots(rest, previous, next, descendants)}

def worktree_workspace(+source: J.Json) -> J.Json:
  +workspace = J.get(source, "workspace")
  +previous = J.text(J.get(source, "previous"))
  +next = J.text(J.get(source, "next"))
  +descendants = J.boolean(J.get(source, "descendants"))
  Model.success(J.Object{[field("roots", J.Array{worktree_map_roots(J.items(J.get(workspace, "roots")), previous, next, descendants)}),
    field("primary_root", worktree_map_path(J.get(workspace, "primary_root"), previous, next, descendants))]})

def worktree_recovery_effect(+source: J.Json) -> J.Json:
  +entry = J.get(source, "entry")
  Model.success(J.Object{[field("kind", worktree_select(names(["creating", "creating_archived"], J.text(J.get(entry, "status"))), J.Text{"worktree_create"}, J.Text{"worktree_archive"})),
    field("task_id", J.get(entry, "task_id")), field("source_root", J.get(entry, "source_root")), field("root", J.get(entry, "root"))]})

def board_command_operation(+observe: Bool, +command: J.Json) -> J.Json:
  Model.success(J.Object{[field("observe", J.Boolean{observe}), field("attachments", J.Boolean{observe && has(command, "attachments") && names(["create_card", "update_card"], J.text(J.get(command, "op")))})]})

def board_command(+source: J.Json) -> J.Json:
  +command = J.get(source, "command")
  board_command_operation(J.is_object(command) && names(["create_card", "update_card", "move_card", "archive_card", "restore_card", "delete_card", "run_card", "link_card", "regenerate_card_title", "pin_card"], J.text(J.get(command, "op"))), command)

def reference_shapes(+items: +List<&2, J.Json>, +seen: +List<&2, String>) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{+head, rest}: J.is_object(head) && allowed(fields(head), ["id", "name", "mime", "path", "bytes"]) && J.is_text(J.get(head, "id")) && Bool.not(names(seen, J.text(J.get(head, "id")))) && reference_shapes(rest, Con{J.text(J.get(head, "id")), seen})

def board_reference_count(+valid: Bool, +references: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure_code("RangeError", "A card accepts at most four attachments")
    case True{}: type_outcome_value(reference_shapes(J.items(references), Nil{}), references, "Attachments must be distinct uploaded file references")

def board_references(+command: J.Json) -> J.Json:
  board_reference_count(array(J.get(command, "attachments")) && Nat.is_le(length(J.items(J.get(command, "attachments"))), 4n), J.get(command, "attachments"))

def reference_field(+valid: Bool, +key: String, +tail: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure_code("TypeError", "Attachment " ++ key ++ " does not match its stored observation")
    case True{}: tail

def reference_match(+keys: +List<&2, String>, +value: J.Json, +attachment: J.Json) -> J.Json:
  match keys:
    case Nil{}: Model.success(attachment)
    case Con{+key, rest}: reference_field(Bool.not(has(value, key)) || J.same(J.get(value, key), J.get(attachment, key)), key, reference_match(rest, value, attachment))

def board_clock(+source: J.Json) -> J.Json:
  range_outcome_value(Model.nonnegative_le(J.get(source, "seconds"), "4294967295"), J.Text{scalar_text(J.get(source, "seconds"))}, "The clock is outside the native board timestamp range")

type RuntimeCandidatesName is Data:
  RuntimeCandidatesNameDarwin{}
  RuntimeCandidatesNameOther{}

def runtime_candidates_discriminant(+value: String) -> RuntimeCandidatesName:
  Bool.pick(RuntimeCandidatesName, String.eq(value, "darwin"), RuntimeCandidatesNameDarwin{},
    RuntimeCandidatesNameOther{})

def runtime_candidates_classified(+platform: RuntimeCandidatesName) -> J.Json:
  match platform:
    case RuntimeCandidatesNameDarwin{}: J.Array{[J.Text{"/System/Library"}, J.Text{"/System/Volumes/Preboot/Cryptexes/OS"}, J.Text{"/usr/bin"}, J.Text{"/usr/lib"}, J.Text{"/usr/libexec"}, J.Text{"/usr/share"}, J.Text{"/bin"}, J.Text{"/sbin"}, J.Text{"/usr/sbin"}, J.Text{"/opt/homebrew/bin"}, J.Text{"/opt/homebrew/sbin"}, J.Text{"/opt/homebrew/lib"}, J.Text{"/opt/homebrew/opt"}, J.Text{"/opt/homebrew/Cellar"}, J.Text{"/opt/homebrew/share"}, J.Text{"/Library/Developer/CommandLineTools"}, J.Text{"/Library/Apple"}, J.Text{"/private/etc/passwd"}, J.Text{"/private/etc/group"}, J.Text{"/private/etc/localtime"}, J.Text{"/private/etc/hosts"}, J.Text{"/private/etc/resolv.conf"}, J.Text{"/private/etc/ssl/cert.pem"}, J.Text{"/private/etc/ssl/certs"}, J.Text{"/dev/null"}, J.Text{"/dev/zero"}, J.Text{"/dev/random"}, J.Text{"/dev/urandom"}, J.Text{"/dev/fd"}]}
    case RuntimeCandidatesNameOther{}: J.Array{[J.Text{"/usr/bin"}, J.Text{"/usr/sbin"}, J.Text{"/usr/lib"}, J.Text{"/usr/lib64"}, J.Text{"/usr/libexec"}, J.Text{"/usr/share"}, J.Text{"/bin"}, J.Text{"/sbin"}, J.Text{"/lib"}, J.Text{"/lib64"}, J.Text{"/etc/ld.so.cache"}, J.Text{"/etc/nsswitch.conf"}, J.Text{"/etc/passwd"}, J.Text{"/etc/group"}, J.Text{"/etc/localtime"}, J.Text{"/etc/hosts"}, J.Text{"/etc/resolv.conf"}, J.Text{"/etc/ssl/certs"}, J.Text{"/etc/os-release"}]}

def runtime_candidates(+platform: String) -> J.Json:
  runtime_candidates_classified(runtime_candidates_discriminant(platform))

type ExecutableCandidatesName is Data:
  ExecutableCandidatesNameDarwin{}
  ExecutableCandidatesNameOther{}

def executable_candidates_discriminant(+value: String) -> ExecutableCandidatesName:
  Bool.pick(ExecutableCandidatesName, String.eq(value, "darwin"), ExecutableCandidatesNameDarwin{},
    ExecutableCandidatesNameOther{})

def executable_candidates_classified(+platform: ExecutableCandidatesName) -> J.Json:
  match platform:
    case ExecutableCandidatesNameDarwin{}: J.Array{[J.Text{"/usr/bin/sandbox-exec"}]}
    case ExecutableCandidatesNameOther{}: J.Array{[J.Text{"/usr/bin/bwrap"}, J.Text{"/bin/bwrap"}]}

def executable_candidates(+platform: String) -> J.Json:
  executable_candidates_classified(executable_candidates_discriminant(platform))

def mac_readable_roots(+project: Bool, +source: J.Json) -> +List<&2, J.Field>:
  match project:
    case False{}: Nil{}
    case True{}: Con{field("readableRoots", J.Array{List.append(&2, J.Json, J.items(J.get(J.get(source, "workspace"), "roots")), Std.map(~J.Json, ~J.Json, ~(entry => J.get(entry, "canonical")), J.items(J.get(source, "runtimeReads"))))}), Nil{}}

def seatbelt_input(+source: J.Json) -> J.Json:
  J.Object{List.append(&2, J.Field, [field("writableRoots", J.get(source, "writableRoots")), field("scratch", J.get(source, "scratch")), field("readOnlyPaths", J.get(source, "protectedRoots")), field("readOnlyExceptions", J.Array{managed_writable_roots(source)}), field("networkAccess", J.get(J.get(J.get(source, "plan"), "sandbox"), "network_access"))], mac_readable_roots(J.boolean(J.get(source, "projectOnly")), source))}

def first_root(+roots: +List<&2, J.Json>) -> J.Json:
  match roots:
    case Nil{}: J.Null{}
    case Con{head, rest}: head

def workspace_default(+default: Bool, +selected: J.Json, +roots: +List<&2, J.Json>) -> J.Json:
  match default:
    case True{}: J.Object{[field("canonicalize", J.Boolean{False{}}), field("root", first_root(roots))]}
    case False{}: J.Object{[field("canonicalize", J.Boolean{True{}}), field("root", selected)]}

def workspace_selection(+source: J.Json) -> J.Json:
  +value = J.get(source, "value")
  +selected = J.get(value, "primary_root")
  workspace_default(J.same(selected, J.Null{}) || J.same(selected, J.Text{""}), selected, J.items(J.get(source, "roots")))

def launch_json_value(value: J.Json) -> J.Json:
  value

# Tagged path observations are OS facts; policy and source coordinates remain native.
def launch_root_observation(+root: J.Json, +observation: J.Json) -> J.Json:
  launch_next(outcome_value(J.is_object(observation) && allowed(fields(observation), ["root", "absolute"]) && has(observation, "root") && bool_type(J.get(observation, "absolute")) && J.same(observation, J.Object{[field("root", root), field("absolute", J.get(observation, "absolute"))]}), J.Null{}, "Workspace path observation does not match its source"), root_admit(observation))

def launch_roots_observed(+roots: +List<&2, J.Json>, +observations: +List<&2, J.Json>) -> J.Json:
  match roots observations:
    case Nil{} Nil{}: Model.success(J.Null{})
    case Con{root, rest} Con{observation, tail}: launch_next(launch_root_observation(root, observation), launch_roots_observed(rest, tail))
    case _ _: Model.failure("Workspace path observations must cover every root in order")

def launch_primary_observed(+canonicalize: Bool, +selected: J.Json, +source: J.Json) -> J.Json:
  match canonicalize:
    case False{}: outcome_value(J.same(J.get(J.get(source, "workspace"), "primary_root"), J.get(selected, "root")), J.Null{}, "Workspace primary observation does not match its selection")
    case True{}: launch_next(launch_root_observation(J.get(selected, "root"), J.get(J.get(source, "root_observations"), "primary")), launch_root_observation(J.get(J.get(source, "workspace"), "primary_root"), J.get(J.get(source, "root_observations"), "canonical_primary")))

def launch_workspace_selected(+source: J.Json) -> J.Json:
  +workspace = J.get(source, "workspace")
  +selected = workspace_selection(J.Object{[field("value", J.get(J.get(source, "plan"), "workspace")), field("roots", J.get(workspace, "roots"))]})
  +selection = launch_json_value(J.Object{[field("value", J.get(J.get(source, "plan"), "workspace")), field("roots", J.get(workspace, "roots")), field("primary", J.get(workspace, "primary_root"))]})
  launch_next(launch_primary_observed(J.boolean(J.get(selected, "canonicalize")), selected, source),
    launch_next(workspace_selected(selection), launch_next(outcome_value(J.same(J.get(workspace_selected(selection), "value"), workspace), J.Null{}, "Workspace observation does not match its selected value"), workspace_bound(source))))

def launch_workspace_roots(+source: J.Json) -> J.Json:
  +workspace = J.get(source, "workspace")
  +committed = J.get(J.get(source, "plan"), "workspace")
  +observations = J.get(source, "root_observations")
  launch_next(outcome_value(J.is_object(observations) && allowed(fields(observations), ["original", "canonical", "primary", "canonical_primary"]) && array(J.get(observations, "original")) && array(J.get(observations, "canonical")), J.Null{}, "Workspace requires tagged path observations"),
    launch_next(launch_roots_observed(J.items(J.get(committed, "roots")), J.items(J.get(observations, "original"))),
      launch_next(launch_roots_observed(J.items(J.get(workspace, "roots")), J.items(J.get(observations, "canonical"))),
        launch_next(outcome_value(J.same(J.nat(length(J.items(J.get(committed, "roots")))), J.nat(length(J.items(J.get(workspace, "roots"))))), J.Null{}, "Workspace root observation count changed"),
          launch_next(workspace_distinct(J.Object{[field("roots", J.get(workspace, "roots"))]}), launch_workspace_selected(source))))))

def launch_workspace_admission(+source: J.Json) -> J.Json:
  launch_next(workspace_admit(J.get(J.get(source, "plan"), "workspace")),
    launch_next(workspace_admit(J.get(source, "workspace")), launch_workspace_roots(source)))

def unrestricted_plan_accepted(+source: J.Json) -> Bool:
  J.boolean(J.get(plan_admission(source), "ok"))

def unrestricted_workspace_accepted(+source: J.Json) -> Bool:
  J.boolean(J.get(launch_workspace_admission(source), "ok"))

def unrestricted_access(+source: J.Json) -> Bool:
  +plan = J.get(source, "plan")
  String.eq(J.text(J.get(plan, "access")), "unrestricted") && Bool.not(String.eq(J.text(J.get(plan, "scope")), "project"))

def unrestricted_plan_category() -> J.Json -> Type:
  Categories.holds(J.Json, (source => unrestricted_plan_accepted(source)))

def unrestricted_workspace_category() -> J.Json -> Type:
  Categories.holds(J.Json, (source => unrestricted_workspace_accepted(source)))

def unrestricted_access_category() -> J.Json -> Type:
  Categories.holds(J.Json, (source => unrestricted_access(source)))

def unrestricted_category(source: J.Json) -> Type:
  Categories.intersection(J.Json, unrestricted_plan_category(),
    (source => Categories.intersection(J.Json, unrestricted_workspace_category(), unrestricted_access_category(), source)), source)

def unrestricted_plan_axis() -> Categories.Inclusion<J.Json, unrestricted_category, unrestricted_plan_category()>:
  Categories.intersection_first(J.Json, unrestricted_plan_category(),
    (source => Categories.intersection(J.Json, unrestricted_workspace_category(), unrestricted_access_category(), source)))

def unrestricted_workspace_access_axes() -> Categories.Inclusion<J.Json, unrestricted_category,
  (source => Categories.intersection(J.Json, unrestricted_workspace_category(), unrestricted_access_category(), source))>:
  Categories.intersection_second(J.Json, unrestricted_plan_category(),
    (source => Categories.intersection(J.Json, unrestricted_workspace_category(), unrestricted_access_category(), source)))

def unrestricted_workspace_axis() -> Categories.Inclusion<J.Json, unrestricted_category, unrestricted_workspace_category()>:
  Categories.inclusion_compose(J.Json, unrestricted_category,
    (source => Categories.intersection(J.Json, unrestricted_workspace_category(), unrestricted_access_category(), source)),
    unrestricted_workspace_category(), unrestricted_workspace_access_axes(),
    Categories.intersection_first(J.Json, unrestricted_workspace_category(), unrestricted_access_category()))

def unrestricted_access_axis() -> Categories.Inclusion<J.Json, unrestricted_category, unrestricted_access_category()>:
  Categories.inclusion_compose(J.Json, unrestricted_category,
    (source => Categories.intersection(J.Json, unrestricted_workspace_category(), unrestricted_access_category(), source)),
    unrestricted_access_category(), unrestricted_workspace_access_axes(),
    Categories.intersection_second(J.Json, unrestricted_workspace_category(), unrestricted_access_category()))

def unrestricted_workspace_cwd(+source: J.Json) -> J.Json:
  J.get(J.get(workspace_bound(source), "value"), "cwd")

def unrestricted_launch_value(+cwd: J.Json) -> J.Json:
  J.Object{[field("file", J.Text{"/bin/bash"}), field("prefix", J.Array{[J.Text{"--noprofile"}, J.Text{"--norc"}]}), field("cwd", cwd)]}

def unrestricted_cwd_matches(+source: J.Json, +cwd: J.Json) -> Bool:
  Bool.not(has(source, "cwd")) || J.same(J.get(source, "cwd"), cwd)

def unrestricted_launch_result_cwd(valid: Bool, cwd: J.Json) -> J.Json:
  match valid:
    case False{}: J.Null{}
    case True{}: cwd

def unrestricted_launch_cwd_checked(valid: Bool, cwd: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure("Unrestricted execution cwd does not match the admitted Workspace")
    case True{}: Model.success(unrestricted_launch_value(cwd))

# The original committed plan and trusted canonical Workspace observation are
# admitted together before deriving the only working directory used by launch.
def unrestricted_launch_owned(member: Categories.Membership<J.Json, unrestricted_category>) -> J.Json:
  Categories.Membership{+source, evidence} = member
  +cwd = unrestricted_workspace_cwd(source)
  unrestricted_launch_cwd_checked(unrestricted_cwd_matches(source, cwd), cwd)

def unrestricted_access_checked(+source: J.Json,
  plan_evidence: {unrestricted_plan_accepted(source) == True{} : Bool},
  workspace_evidence: {unrestricted_workspace_accepted(source) == True{} : Bool}, accepted: Bool,
  access_evidence: {unrestricted_access(source) == accepted : Bool}) -> J.Json:
  match accepted:
    case False{}: Model.failure("Malformed committed sandbox execution plan")
    case True{}: unrestricted_launch_owned(Categories.Membership{source,
      Categories.Intersection{plan_evidence, Categories.Intersection{workspace_evidence, access_evidence}}})

def unrestricted_workspace_checked(+source: J.Json,
  plan_evidence: {unrestricted_plan_accepted(source) == True{} : Bool}, result: J.Json, accepted: Bool,
  workspace_evidence: {unrestricted_workspace_accepted(source) == accepted : Bool}) -> J.Json:
  match accepted:
    case False{}: result
    case True{}: unrestricted_access_checked(source, plan_evidence, workspace_evidence, unrestricted_access(source), {==})

def unrestricted_plan_checked(+source: J.Json, result: J.Json, accepted: Bool,
  plan_evidence: {unrestricted_plan_accepted(source) == accepted : Bool}) -> J.Json:
  match accepted:
    case False{}: result
    case True{}: unrestricted_workspace_checked(source, plan_evidence, launch_workspace_admission(source), unrestricted_workspace_accepted(source), {==})

def unrestricted_launch(+source: J.Json) -> J.Json:
  unrestricted_plan_checked(source, plan_admission(source), unrestricted_plan_accepted(source), {==})

def launch_context(+source: J.Json) -> J.Json:
  +bound = J.get(workspace_bound(source), "value")
  J.Object{[field("plan", J.get(source, "plan")), field("options", J.get(source, "options")), field("workspace", J.get(source, "workspace")), field("cwd", J.get(bound, "cwd")), field("projectOnly", J.get(bound, "projectOnly")), field("writableRoots", J.get(bound, "writableRoots")), field("scratch", J.get(source, "scratch")), field("protectedRoots", J.get(source, "protectedRoots")), field("managedWorktreeRoot", J.get(source, "managedWorktreeRoot")), field("separator", J.get(source, "separator")), field("runtimeReads", J.get(source, "runtimeReads"))]}

def launch_legacy_fields(+keys: +List<&2, String>, +source: J.Json, +context: J.Json) -> Bool:
  match keys:
    case Nil{}: True{}
    case Con{key, rest}: (Bool.not(has(source, key)) || J.same(J.get(source, key), J.get(context, key))) && launch_legacy_fields(rest, source, context)

def launch_resource_admission(+source: J.Json) -> J.Json:
  +context = launch_context(source)
  outcome_value(launch_legacy_fields(["cwd", "projectOnly", "writableRoots"], source, context) &&
    (Bool.not(has(source, "networkAccess")) || J.same(J.get(source, "networkAccess"), J.get(J.get(J.get(source, "plan"), "sandbox"), "network_access"))) &&
    (Bool.not(has(source, "platform")) || J.same(J.get(source, "platform"), J.get(J.get(source, "options"), "platform"))) &&
    J.is_text(J.get(source, "separator")) && String.eq(J.text(J.get(source, "separator")), "/") &&
    paths_valid([J.get(source, "scratch")]) && array(J.get(source, "protectedRoots")) && paths_valid(J.items(J.get(source, "protectedRoots"))) &&
    array(J.get(J.get(source, "options"), "readOnlyPaths")) && J.same(J.nat(length(J.items(J.get(source, "protectedRoots")))), J.nat(length(J.items(J.get(J.get(source, "options"), "readOnlyPaths"))))), J.Null{}, "Sandbox observations do not match the admitted security context")

def sandbox_security_admission(+source: J.Json) -> J.Json:
  launch_next(outcome_value(String.eq(J.text(J.get(J.get(source, "plan"), "access")), "sandboxed"), J.Null{}, "Malformed committed sandbox execution plan"),
    launch_next(launch_resource_admission(source), launch_next(managed_worktree_admission(launch_context(source)), protected_workspace(launch_context(source)))))

def sandbox_security_accepted(+source: J.Json) -> Bool:
  J.boolean(J.get(sandbox_security_admission(source), "ok"))

def sandbox_security_category() -> J.Json -> Type:
  Categories.holds(J.Json, (source => sandbox_security_accepted(source)))

def sandbox_launch_category(source: J.Json) -> Type:
  Categories.intersection(J.Json, unrestricted_plan_category(),
    (source => Categories.intersection(J.Json, unrestricted_workspace_category(), sandbox_security_category(), source)), source)

def sandbox_launch_plan_axis() -> Categories.Inclusion<J.Json, sandbox_launch_category, unrestricted_plan_category()>:
  Categories.intersection_first(J.Json, unrestricted_plan_category(),
    (source => Categories.intersection(J.Json, unrestricted_workspace_category(), sandbox_security_category(), source)))

def sandbox_launch_workspace_security_axes() -> Categories.Inclusion<J.Json, sandbox_launch_category,
  (source => Categories.intersection(J.Json, unrestricted_workspace_category(), sandbox_security_category(), source))>:
  Categories.intersection_second(J.Json, unrestricted_plan_category(),
    (source => Categories.intersection(J.Json, unrestricted_workspace_category(), sandbox_security_category(), source)))

def sandbox_launch_workspace_axis() -> Categories.Inclusion<J.Json, sandbox_launch_category, unrestricted_workspace_category()>:
  Categories.inclusion_compose(J.Json, sandbox_launch_category,
    (source => Categories.intersection(J.Json, unrestricted_workspace_category(), sandbox_security_category(), source)),
    unrestricted_workspace_category(), sandbox_launch_workspace_security_axes(),
    Categories.intersection_first(J.Json, unrestricted_workspace_category(), sandbox_security_category()))

def sandbox_launch_security_axis() -> Categories.Inclusion<J.Json, sandbox_launch_category, sandbox_security_category()>:
  Categories.inclusion_compose(J.Json, sandbox_launch_category,
    (source => Categories.intersection(J.Json, unrestricted_workspace_category(), sandbox_security_category(), source)),
    sandbox_security_category(), sandbox_launch_workspace_security_axes(),
    Categories.intersection_second(J.Json, unrestricted_workspace_category(), sandbox_security_category()))

# Child fd 3 holds seccomp. Directory observations start at child fd 4.
def launch_bound_bindings(+items: +List<&2, J.Json>, +descriptor: Nat) -> +List<&2, J.Json>:
  match items:
    case Nil{}: Nil{}
    case Con{+entry, rest}: Con{J.Object{[field("root", J.get(entry, "root")), field("readonly", J.get(entry, "readonly")), field("descriptor", J.nat(descriptor))]}, launch_bound_bindings(rest, Nat.add(descriptor, 1n))}

def launch_expected_bindings(+source: J.Json) -> J.Json:
  J.Array{launch_bound_bindings(J.items(bindings(launch_context(source))), 4n)}

def launch_runtime_observed(+items: +List<&2, J.Json>, +candidates: +List<&2, String>, +seen: +List<&2, String>) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{+entry, rest}: J.is_object(entry) && allowed(fields(entry), ["root", "canonical"]) && paths_valid([J.get(entry, "root"), J.get(entry, "canonical")]) && names(candidates, J.text(J.get(entry, "root"))) && Bool.not(names(seen, J.text(J.get(entry, "root")))) && launch_runtime_observed(rest, candidates, Con{J.text(J.get(entry, "root")), seen})

def launch_runtime_admission(+source: J.Json) -> J.Json:
  outcome_value(array(J.get(source, "runtimeReads")) && launch_runtime_observed(J.items(J.get(source, "runtimeReads")), J.text_values(J.items(runtime_candidates(J.text(J.get(J.get(source, "options"), "platform"))))), Nil{}) &&
    (J.boolean(J.get(launch_context(source), "projectOnly")) || J.same(J.get(source, "runtimeReads"), J.Array{Nil{}})), J.Null{}, "Sandbox runtime observations do not match the selected platform")

def launch_seatbelt_source(+source: J.Json) -> J.Json:
  +input = seatbelt_input(launch_context(source))
  J.Object{List.append(&2, J.Field, fields(input), [field("protectedAncestors", J.get(source, "protectedAncestors")), field("readAncestors", J.get(source, "readAncestors"))])}

def launch_ancestor_rows(+rows: +List<&2, J.Json>, +roots: +List<&2, J.Json>) -> Bool:
  match rows roots:
    case Nil{} Nil{}: True{}
    case Con{row, rest} Con{root, tail}: array(row) && paths_valid(J.items(row)) && launch_ancestor_rows(rest, tail)
    case _ _: False{}

def launch_darwin_ancestors(+project: Bool, +source: J.Json) -> Bool:
  match project:
    case False{}: J.same(J.get(source, "readAncestors"), J.Array{Nil{}})
    case True{}: launch_ancestor_rows(J.items(J.get(source, "readAncestors")), List.append(&2, J.Json, J.items(J.get(seatbelt_input(launch_context(source)), "readableRoots")), [J.get(source, "scratch")]))

def launch_value(+prefix: J.Json, +cwd: J.Json) -> J.Json:
  J.Object{[field("prefix", prefix), field("cwd", cwd)]}

def launch_darwin_profile(+valid: Bool, +source: J.Json, +profile: J.Json) -> J.Json:
  match valid:
    case False{}: profile
    case True{}: launch_next(outcome_value(Bool.not(has(source, "profile")) || J.same(J.get(source, "profile"), J.get(profile, "value")), J.Null{}, "Sandbox profile does not match the admitted security context"), Model.success(launch_value(darwin_prefix(J.Object{[field("profile", J.get(profile, "value"))]}), J.get(launch_context(source), "cwd"))))

def launch_darwin(+source: J.Json) -> J.Json:
  +profile = seatbelt(launch_seatbelt_source(source))
  launch_next(outcome_value(array(J.get(source, "protectedAncestors")) && array(J.get(source, "readAncestors")) && launch_ancestor_rows(J.items(J.get(source, "protectedAncestors")), J.items(J.get(source, "protectedRoots"))) && launch_darwin_ancestors(J.boolean(J.get(launch_context(source), "projectOnly")), source), J.Null{}, "Sandbox ancestor observations do not match their source paths"), launch_darwin_profile(J.boolean(J.get(profile, "ok")), source, profile))

def launch_linux(+source: J.Json) -> J.Json:
  +context = launch_context(source)
  +expected = launch_expected_bindings(source)
  launch_next(outcome_value(J.same(J.get(source, "bindings"), expected), J.Null{}, "Sandbox descriptor observations do not match their admitted bindings"), Model.success(launch_value(linux_prefix(J.Object{List.append(&2, J.Field, fields(context), [field("bindings", expected)])}), J.get(context, "cwd"))))

def launch_platform(+darwin: Bool, +source: J.Json) -> J.Json:
  match darwin:
    case True{}: launch_darwin(source)
    case False{}: launch_linux(source)

def sandbox_launch_owned(member: Categories.Membership<J.Json, sandbox_launch_category>) -> J.Json:
  Categories.Membership{+source, evidence} = member
  launch_next(launch_runtime_admission(source), launch_platform(String.eq(J.text(J.get(J.get(source, "options"), "platform")), "darwin"), source))

def sandbox_prepare_owned(member: Categories.Membership<J.Json, sandbox_launch_category>) -> J.Json:
  Categories.Membership{+source, evidence} = member
  +context = launch_context(source)
  Model.success(J.Object{[field("cwd", J.get(context, "cwd")), field("projectOnly", J.get(context, "projectOnly")), field("bindings", bindings(context)), field("writableRoots", J.get(context, "writableRoots")), field("seatbeltInput", seatbelt_input(context))]})

def sandbox_launch_security_checked(+prepare: Bool, +source: J.Json,
  plan_evidence: {unrestricted_plan_accepted(source) == True{} : Bool},
  workspace_evidence: {unrestricted_workspace_accepted(source) == True{} : Bool}, accepted: Bool,
  security_evidence: {sandbox_security_accepted(source) == accepted : Bool}) -> J.Json:
  match prepare accepted:
    case _ False{}: sandbox_security_admission(source)
    case True{} True{}: sandbox_prepare_owned(Categories.Membership{source, Categories.Intersection{plan_evidence, Categories.Intersection{workspace_evidence, security_evidence}}})
    case False{} True{}: sandbox_launch_owned(Categories.Membership{source, Categories.Intersection{plan_evidence, Categories.Intersection{workspace_evidence, security_evidence}}})

def sandbox_launch_workspace_checked(+prepare: Bool, +source: J.Json,
  plan_evidence: {unrestricted_plan_accepted(source) == True{} : Bool}, accepted: Bool,
  workspace_evidence: {unrestricted_workspace_accepted(source) == accepted : Bool}) -> J.Json:
  match accepted:
    case False{}: launch_workspace_admission(source)
    case True{}: sandbox_launch_security_checked(prepare, source, plan_evidence, workspace_evidence, sandbox_security_accepted(source), {==})

def sandbox_launch_plan_checked(+prepare: Bool, +source: J.Json, accepted: Bool,
  plan_evidence: {unrestricted_plan_accepted(source) == accepted : Bool}) -> J.Json:
  match accepted:
    case False{}: plan_admission(source)
    case True{}: sandbox_launch_workspace_checked(prepare, source, plan_evidence, unrestricted_workspace_accepted(source), {==})

def sandbox_launch(+source: J.Json) -> J.Json:
  sandbox_launch_plan_checked(False{}, source, unrestricted_plan_accepted(source), {==})

def sandbox_prepare(+source: J.Json) -> J.Json:
  sandbox_launch_plan_checked(True{}, source, unrestricted_plan_accepted(source), {==})

def launch_prefix_result(+accepted: Bool, +result: J.Json) -> J.Json:
  match accepted:
    case False{}: result
    case True{}: Model.success(J.get(J.get(result, "value"), "prefix"))

def guarded_prefix(+platform: String, +source: J.Json) -> J.Json:
  +result = launch_next(outcome_value(J.same(J.get(J.get(source, "options"), "platform"), J.Text{platform}), J.Null{}, "Sandbox terminal platform does not match its source"), sandbox_launch(source))
  launch_prefix_result(J.boolean(J.get(result, "ok")), result)

# Coordinates are obligations only for the callback kinds owning those identities.
def task_coordinate_classified(+kind: CallbackKind, +value: J.Json) -> J.Json:
  match kind:
    case CallbackChatgptExec{}: J.Null{}
    case CallbackBoardText{}: J.Null{}
    case _: J.get(value, "task_id")

def task_coordinate(+kind: String, +value: J.Json) -> J.Json:
  task_coordinate_classified(classify_callback_kind(kind), value)

def ticket_coordinate_classified(+kind: CallbackKind, +value: J.Json) -> J.Json:
  match kind:
    case CallbackChatgptExec{}: J.Null{}
    case CallbackWorktree{created}: J.Null{}
    case _: J.get(value, "ticket")

def ticket_coordinate(+kind: String, +value: J.Json) -> J.Json:
  ticket_coordinate_classified(classify_callback_kind(kind), value)

def operation_coordinate_classified(+kind: CallbackKind, +value: J.Json) -> J.Json:
  match kind:
    case CallbackChatgptExec{}: J.get(value, "operation_id")
    case CallbackAfterHook{}: J.get(value, "operation_id")
    case _: J.Null{}

def operation_coordinate(+kind: String, +value: J.Json) -> J.Json:
  operation_coordinate_classified(classify_callback_kind(kind), value)

def card_coordinate_classified(+kind: CallbackKind, +value: J.Json) -> J.Json:
  match kind:
    case CallbackBoardText{}: J.get(value, "card_id")
    case _: J.Null{}

def card_coordinate(+kind: String, +value: J.Json) -> J.Json:
  card_coordinate_classified(classify_callback_kind(kind), value)

def meaning_launch_route(+prepare: Bool, +source: J.Json) -> J.Json:
  match prepare:
    case True{}: sandbox_prepare(source)
    case False{}: sandbox_launch(source)

def meaning_route_37(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: meaning_launch_route(String.eq(operation, "effect.sandbox_prepare"), source)
    case False{}: Model.failure("Unknown effect operation: " ++ operation)

# NOTE: Boolean routes avoid the pinned checker expanding long string literal patterns.
def meaning_route_36(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: workspace_selected(source)
    case False{}: meaning_route_37(String.eq(operation, "effect.sandbox_launch") || String.eq(operation, "effect.sandbox_prepare"), operation, source)

def meaning_route_35(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(workspace_selection(source))
    case False{}: meaning_route_36(String.eq(operation, "effect.workspace_selected"), operation, source)

def meaning_route_34(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: workspace_distinct(source)
    case False{}: meaning_route_35(String.eq(operation, "effect.workspace_selection"), operation, source)

def meaning_route_33(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: root_admit(source)
    case False{}: meaning_route_34(String.eq(operation, "effect.workspace_distinct"), operation, source)

def meaning_route_32(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: workspace_admit(J.get(source, "value"))
    case False{}: meaning_route_33(String.eq(operation, "effect.root_admit"), operation, source)

def meaning_route_31(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: type_outcome_value(positive_safe_integer(J.get(J.get(source, "limits"), "artifact_bytes")), J.Null{}, "Invalid artifact byte limit")
    case False{}: meaning_route_32(String.eq(operation, "effect.workspace_admit"), operation, source)

def meaning_route_30(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: range_outcome_value(Model.nonnegative_le(J.get(source, "size"), "10485760"), J.Null{}, "Each board attachment is limited to 10 MiB")
    case False{}: meaning_route_31(String.eq(operation, "effect.artifact_limit"), operation, source)

def meaning_route_29(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: unrestricted_launch(source)
    case False{}: meaning_route_30(String.eq(operation, "effect.attachment_budget"), operation, source)

def meaning_route_28(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(seatbelt_input(source))
    case False{}: meaning_route_29(String.eq(operation, "effect.unrestricted_launch"), operation, source)

def meaning_route_27(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(executable_candidates(J.text(J.get(source, "platform"))))
    case False{}: meaning_route_28(String.eq(operation, "effect.seatbelt_input"), operation, source)

def meaning_route_26(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(runtime_candidates(J.text(J.get(source, "platform"))))
    case False{}: meaning_route_27(String.eq(operation, "effect.executable_candidates"), operation, source)

def meaning_route_25(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: guarded_prefix("darwin", source)
    case False{}: meaning_route_26(String.eq(operation, "effect.runtime_candidates"), operation, source)

def meaning_route_24(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: guarded_prefix("linux", source)
    case False{}: meaning_route_25(String.eq(operation, "effect.darwin_prefix"), operation, source)

def meaning_route_23(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(bindings(source))
    case False{}: meaning_route_24(String.eq(operation, "effect.linux_prefix"), operation, source)

def meaning_route_22(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: seatbelt(source)
    case False{}: meaning_route_23(String.eq(operation, "effect.sandbox_bindings"), operation, source)

def meaning_route_21(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: seccomp(source)
    case False{}: meaning_route_22(String.eq(operation, "effect.seatbelt"), operation, source)

def meaning_route_20(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(environment(source))
    case False{}: meaning_route_21(String.eq(operation, "effect.seccomp"), operation, source)

def meaning_route_19(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: protected_workspace(source)
    case False{}: meaning_route_20(String.eq(operation, "effect.environment"), operation, source)

def meaning_route_18(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: workspace_bound(source)
    case False{}: meaning_route_19(String.eq(operation, "effect.protected_workspace"), operation, source)

def meaning_route_17(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: plan_admission(source)
    case False{}: meaning_route_18(String.eq(operation, "effect.workspace_bound"), operation, source)

def meaning_route_16(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(process_result(source))
    case False{}: meaning_route_17(String.eq(operation, "effect.sandbox_admit"), operation, source)

def meaning_route_15(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: bash_arguments(source)
    case False{}: meaning_route_16(String.eq(operation, "effect.process_result"), operation, source)

def meaning_route_14(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(complete_failure_input(J.get(source, "effect"), failure_message(source), J.boolean(J.get(source, "context_limit"))))
    case False{}: meaning_route_15(String.eq(operation, "effect.bash_arguments"), operation, source)

def meaning_route_13(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(callback(J.get(source, "effect"), J.get(source, "result")))
    case False{}: meaning_route_14(String.eq(operation, "effect.failure"), operation, source)

def meaning_route_12(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: board_clock(source)
    case False{}: meaning_route_13(String.eq(operation, "effect.completion"), operation, source)

def meaning_route_11(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: reference_match(["name", "mime", "path", "bytes"], J.get(source, "value"), J.get(source, "attachment"))
    case False{}: meaning_route_12(String.eq(operation, "effect.board_clock"), operation, source)

def meaning_route_10(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: board_references(J.get(source, "command"))
    case False{}: meaning_route_11(String.eq(operation, "effect.reference_match"), operation, source)

def meaning_route_9(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: board_command(source)
    case False{}: meaning_route_10(String.eq(operation, "effect.board_references"), operation, source)

def meaning_route_8(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: attachment(source)
    case False{}: meaning_route_9(String.eq(operation, "effect.board_command"), operation, source)

def meaning_route_7(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: identifier(J.get(source, "id"))
    case False{}: meaning_route_8(String.eq(operation, "effect.attachment"), operation, source)

def meaning_route_6(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: filename(J.get(source, "value"))
    case False{}: meaning_route_7(String.eq(operation, "effect.attachment_id"), operation, source)

def meaning_route_5(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: request_task_text(source)
    case False{}: meaning_route_6(String.eq(operation, "effect.filename"), operation, source)

def meaning_route_4(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: request_approval(source)
    case False{}: meaning_route_5(String.eq(operation, "effect.request_task_text"), operation, source)

def meaning_route_3(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: outcome(source, False{})
    case False{}: meaning_route_4(String.eq(operation, "effect.request_approval"), operation, source)

def meaning_route_2(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: outcome(source, True{})
    case False{}: meaning_route_3(String.eq(operation, "effect.task_text_outcome"), operation, source)

def meaning_route_1(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: response_text(source, False{})
    case False{}: meaning_route_2(String.eq(operation, "effect.approval_outcome"), operation, source)

def meaning_route_0(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: response_text(source, True{})
    case False{}: meaning_route_1(String.eq(operation, "effect.task_text_text"), operation, source)

def meaning(+operation: String, +source: J.Json) -> J.Json:
  match operation:
    case "effect.worktree_locations": worktree_locations(source)
    case "effect.worktree_path": worktree_path_admission(source)
    case "effect.worktree_receipt": worktree_receipt(source)
    case "effect.worktree_workspace": worktree_workspace(source)
    case "effect.worktree_recovery_effect": worktree_recovery_effect(source)
    case +operation: meaning_route_0(String.eq(operation, "effect.approval_text"), operation, source)

def family(+operation: String) -> Model.Adapter(source => meaning(operation, source)):
  Model.adapter(source => meaning(operation, source), source => meaning(operation, source), source => {==})

def run(+operation: String, +source: J.Json) -> J.Json:
  Model.execute(source => meaning(operation, source), family(operation), source)

law complete_correspondence:
  @operation:String -> @source:J.Json -> {run(operation, source) == meaning(operation, source) : J.Json}
law callback_task:
  @effect:J.Json -> @result:J.Json ->
  {task_coordinate(J.text(J.get(effect, "kind")), callback(effect, result)) == task_coordinate(J.text(J.get(effect, "kind")), effect) : J.Json}
law callback_ticket:
  @effect:J.Json -> @result:J.Json ->
  {ticket_coordinate(J.text(J.get(effect, "kind")), callback(effect, result)) == ticket_coordinate(J.text(J.get(effect, "kind")), effect) : J.Json}
law callback_operation:
  @effect:J.Json -> @result:J.Json ->
  {operation_coordinate(J.text(J.get(effect, "kind")), callback(effect, result)) == operation_coordinate(J.text(J.get(effect, "kind")), effect) : J.Json}
law callback_card:
  @effect:J.Json -> @result:J.Json ->
  {card_coordinate(J.text(J.get(effect, "kind")), callback(effect, result)) == card_coordinate(J.text(J.get(effect, "kind")), effect) : J.Json}
law environment_name_selection:
  @source:J.Json -> {J.get(environment(source), "names") == environment_names(J.boolean(J.get(source, "projectOnly")), source) : J.Json}
law environment_override_selection:
  @source:J.Json -> {J.get(environment(source), "overrides") == environment_overrides(J.boolean(J.get(source, "projectOnly")), source, J.get(source, "scratch")) : J.Json}
law process_exit_code:
  @source:J.Json -> {J.get(process_value(source), "exit_code") == J.get(source, "exitCode") : J.Json}
law process_signal:
  @source:J.Json -> {J.get(process_value(source), "signal") == J.get(source, "exitSignal") : J.Json}
law linux_readonly_binding:
  {bind_flag(True{}) == "--ro-bind" : String}
law linux_writable_binding:
  {bind_flag(False{}) == "--bind" : String}
law denial_is_not_execution_failure:
  {J.get(error_value("failed"), "error") == J.Object{Con{field("code", J.Text{"external_execution_failed"}), Con{field("message", J.Text{"failed"}), Nil{}}}} : J.Json}

law failure_without_context_limit:
  @effect:J.Json -> @message:String ->
  {complete_failure_input(effect, message, False{}) == failure_input(effect, message) : J.Json}
law failure_context_limit_field:
  @effect:J.Json -> @message:String -> @context_limit:Bool ->
  {J.get(complete_failure_input(effect, message, context_limit), "failure_kind") == failure_context_kind(context_limit, classify_callback_kind(J.text(J.get(effect, "kind")))) : J.Json}
law context_limit_model_fields:
  @effect:J.Json -> @message:String ->
  {fields(context_limit_model(effect, message)) == Con{field("failure_kind", J.Text{"context_limit"}), fields(failed_model(effect, message))} : List<&2, J.Field>}
law failure_preserves_kind:
  @effect:J.Json -> @message:String -> @context_limit:Bool ->
  {J.get(complete_failure_input(effect, message, context_limit), "kind") == J.get(failure_input(effect, message), "kind") : J.Json}
law failure_preserves_task_id:
  @effect:J.Json -> @message:String -> @context_limit:Bool ->
  {J.get(complete_failure_input(effect, message, context_limit), "task_id") == J.get(failure_input(effect, message), "task_id") : J.Json}
law failure_preserves_ticket:
  @effect:J.Json -> @message:String -> @context_limit:Bool ->
  {J.get(complete_failure_input(effect, message, context_limit), "ticket") == J.get(failure_input(effect, message), "ticket") : J.Json}
law failure_preserves_operation_id:
  @effect:J.Json -> @message:String -> @context_limit:Bool ->
  {J.get(complete_failure_input(effect, message, context_limit), "operation_id") == J.get(failure_input(effect, message), "operation_id") : J.Json}
law failure_preserves_card_id:
  @effect:J.Json -> @message:String -> @context_limit:Bool ->
  {J.get(complete_failure_input(effect, message, context_limit), "card_id") == J.get(failure_input(effect, message), "card_id") : J.Json}
law failure_preserves_ok:
  @effect:J.Json -> @message:String -> @context_limit:Bool ->
  {J.get(complete_failure_input(effect, message, context_limit), "ok") == J.get(failure_input(effect, message), "ok") : J.Json}
law failure_preserves_message:
  @effect:J.Json -> @message:String -> @context_limit:Bool ->
  {J.get(complete_failure_input(effect, message, context_limit), "message") == J.get(failure_input(effect, message), "message") : J.Json}


law unrestricted_launch_complete:
  @source:J.Json -> {run("effect.unrestricted_launch", source) == unrestricted_launch(source) : J.Json}
law unrestricted_launch_cwd_projection:
  @cwd:J.Json -> {J.get(unrestricted_launch_value(cwd), "cwd") == cwd : J.Json}
law unrestricted_launch_file_projection:
  @cwd:J.Json -> {J.get(unrestricted_launch_value(cwd), "file") == J.Text{"/bin/bash"} : J.Json}
law unrestricted_launch_prefix_projection:
  @cwd:J.Json -> {J.get(unrestricted_launch_value(cwd), "prefix") == J.Array{[J.Text{"--noprofile"}, J.Text{"--norc"}]} : J.Json}
law unrestricted_launch_owned_workspace:
  @source:J.Json -> @evidence:unrestricted_category(source) ->
  {unrestricted_launch_owned(Categories.Membership{source, evidence}) ==
    unrestricted_launch_cwd_checked(unrestricted_cwd_matches(source, unrestricted_workspace_cwd(source)), unrestricted_workspace_cwd(source)) : J.Json}
law unrestricted_launch_plan_failure:
  @source:J.Json -> @result:J.Json -> @evidence:{unrestricted_plan_accepted(source) == False{} : Bool} ->
  {unrestricted_plan_checked(source, result, False{}, evidence) == result : J.Json}
law unrestricted_launch_workspace_failure:
  @source:J.Json -> @plan_evidence:{unrestricted_plan_accepted(source) == True{} : Bool} -> @result:J.Json ->
  @evidence:{unrestricted_workspace_accepted(source) == False{} : Bool} ->
  {unrestricted_workspace_checked(source, plan_evidence, result, False{}, evidence) == result : J.Json}

law unrestricted_plan_authority:
  @source:J.Json -> unrestricted_category(source) -> {unrestricted_plan_accepted(source) == True{} : Bool}
law unrestricted_workspace_authority:
  @source:J.Json -> unrestricted_category(source) -> {unrestricted_workspace_accepted(source) == True{} : Bool}
law unrestricted_access_authority:
  @source:J.Json -> unrestricted_category(source) -> {unrestricted_access(source) == True{} : Bool}
law unrestricted_launch_checked_cwd:
  @valid:Bool -> @cwd:J.Json ->
  {J.get(J.get(unrestricted_launch_cwd_checked(valid, cwd), "value"), "cwd") == unrestricted_launch_result_cwd(valid, cwd) : J.Json}
law unrestricted_launch_owned_cwd:
  @source:J.Json -> @evidence:unrestricted_category(source) ->
  {J.get(J.get(unrestricted_launch_owned(Categories.Membership{source, evidence}), "value"), "cwd") ==
    unrestricted_launch_result_cwd(unrestricted_cwd_matches(source, unrestricted_workspace_cwd(source)),
      J.get(J.get(workspace_bound(source), "value"), "cwd")) : J.Json}

law sandbox_launch_complete:
  @source:J.Json -> {run("effect.sandbox_launch", source) == sandbox_launch(source) : J.Json}
law sandbox_prepare_complete:
  @source:J.Json -> {run("effect.sandbox_prepare", source) == sandbox_prepare(source) : J.Json}
law sandbox_launch_owned_decision:
  @source:J.Json -> @evidence:sandbox_launch_category(source) ->
  {sandbox_launch_owned(Categories.Membership{source, evidence}) ==
    launch_next(launch_runtime_admission(source), launch_platform(String.eq(J.text(J.get(J.get(source, "options"), "platform")), "darwin"), source)) : J.Json}
law sandbox_launch_plan_authority:
  @source:J.Json -> sandbox_launch_category(source) -> {unrestricted_plan_accepted(source) == True{} : Bool}
law sandbox_launch_workspace_authority:
  @source:J.Json -> sandbox_launch_category(source) -> {unrestricted_workspace_accepted(source) == True{} : Bool}
law sandbox_launch_security_authority:
  @source:J.Json -> sandbox_launch_category(source) -> {sandbox_security_accepted(source) == True{} : Bool}
law sandbox_launch_context_cwd:
  @source:J.Json -> {J.get(launch_context(source), "cwd") == J.get(J.get(workspace_bound(source), "value"), "cwd") : J.Json}
law sandbox_launch_context_writes:
  @source:J.Json -> {J.get(launch_context(source), "writableRoots") == J.get(J.get(workspace_bound(source), "value"), "writableRoots") : J.Json}
law sandbox_launch_context_scope:
  @source:J.Json -> {J.get(launch_context(source), "projectOnly") == J.get(J.get(workspace_bound(source), "value"), "projectOnly") : J.Json}
law sandbox_without_managed_root:
  @roots:List<&2, J.Json> -> @separator:String ->
  {managed_writable_items(roots, J.Null{}, separator) == Nil{} : List<&2, J.Json>}
law sandbox_readonly_managed_roots:
  @workspace:J.Json -> @root:J.Json -> @separator:String ->
  {managed_writable_items(J.items(writable_mode(False{}, workspace)), root, separator) == Nil{} : List<&2, J.Json>}
law sandbox_managed_binding_order:
  @source:J.Json -> {binding_project(False{}, source) == J.Array{List.append(&2, J.Json,
    Std.map(~J.Json, ~J.Json, ~(root => binding(root, False{})), List.append(&2, J.Json, J.items(J.get(source, "writableRoots")), Con{J.get(source, "scratch"), Nil{}})),
    List.append(&2, J.Json, binding_items(J.items(J.get(source, "protectedRoots")), True{}), binding_items(managed_writable_roots(source), False{})))} : J.Json}
law sandbox_launch_descriptor_coordinates:
  @source:J.Json -> {launch_expected_bindings(source) == J.Array{launch_bound_bindings(J.items(bindings(launch_context(source))), 4n)} : J.Json}
law sandbox_launch_binding_head:
  @entry:J.Json -> @rest:List<&2, J.Json> -> @descriptor:Nat ->
  {launch_bound_bindings(Con{entry, rest}, descriptor) == Con{J.Object{[field("root", J.get(entry, "root")), field("readonly", J.get(entry, "readonly")), field("descriptor", J.nat(descriptor))]}, launch_bound_bindings(rest, Nat.add(descriptor, 1n))} : List<&2, J.Json>}
law sandbox_launch_linux_policy:
  @source:J.Json -> {launch_linux(source) == launch_next(outcome_value(J.same(J.get(source, "bindings"), launch_expected_bindings(source)), J.Null{}, "Sandbox descriptor observations do not match their admitted bindings"), Model.success(launch_value(linux_prefix(J.Object{List.append(&2, J.Field, fields(launch_context(source)), [field("bindings", launch_expected_bindings(source))])}), J.get(launch_context(source), "cwd")))) : J.Json}
law sandbox_launch_darwin_policy:
  @source:J.Json -> {launch_seatbelt_source(source) == J.Object{List.append(&2, J.Field, fields(seatbelt_input(launch_context(source))), [field("protectedAncestors", J.get(source, "protectedAncestors")), field("readAncestors", J.get(source, "readAncestors"))])} : J.Json}
law sandbox_launch_value_cwd:
  @prefix:J.Json -> @cwd:J.Json -> {J.get(launch_value(prefix, cwd), "cwd") == cwd : J.Json}
law sandbox_launch_value_prefix:
  @prefix:J.Json -> @cwd:J.Json -> {J.get(launch_value(prefix, cwd), "prefix") == prefix : J.Json}


law context_callback_observations:
  @effect:J.Json -> @result:J.Json ->
  {J.get(callback_classified(CallbackContext{}, effect, result), "observations") == J.get(result, "observations") : J.Json}
law context_callback_kind:
  @effect:J.Json -> @result:J.Json ->
  {J.get(callback_classified(CallbackContext{}, effect, result), "kind") == J.Text{"context_observed"} : J.Json}
law context_failure_kind:
  @effect:J.Json -> @message:String ->
  {J.get(failure_classified(CallbackContext{}, effect, message), "kind") == J.Text{"context_observed"} : J.Json}

law compaction_callback_result:
  @completed:Bool -> @effect:J.Json -> @result:J.Json ->
  {J.get(callback_classified(CallbackCompaction{completed}, effect, result), "result") == result : J.Json}
law compaction_callback_error:
  @completed:Bool -> @effect:J.Json -> @result:J.Json ->
  {J.get(callback_classified(CallbackCompaction{completed}, effect, result), "error") == J.Boolean{False{}} : J.Json}
law compaction_failure_error:
  @completed:Bool -> @effect:J.Json -> @message:String ->
  {J.get(failure_classified(CallbackCompaction{completed}, effect, message), "error") == J.Boolean{True{}} : J.Json}

law worktree_callback_coordinates:
  @created:Bool -> @effect:J.Json -> @result:J.Json ->
  {J.get(worktree_callback(created, effect, result), "task_id") == J.get(effect, "task_id") : J.Json}
law worktree_callback_operation:
  @created:Bool -> @effect:J.Json -> @result:J.Json ->
  {J.get(worktree_callback(created, effect, result), "kind") == J.Text{worktree_callback_kind(created)} : J.Json}
