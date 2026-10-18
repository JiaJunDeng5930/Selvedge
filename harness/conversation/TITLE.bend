import Base
import ../../bendlib/json.bend as J

# Automatic task title policy follows openai/codex's thread_title.rs at
# ce0323f2f2d3b25e82806cd555237da3db4e1897 (Apache-2.0).
def maximum_characters() -> Nat:
  36n

def prompt_bytes() -> Nat:
  960n

def response_title_bytes() -> Nat:
  4096n

def instructions() -> String:
  "Generate a concise, single-line task title of at most 36 characters and under five words where possible. Start with an imperative verb. Capitalize only the first word unless the user's language, proper nouns, acronyms, or code terms require otherwise. Preserve ticket references exactly. Write in the user's language. Do not use quotes, markdown, or trailing punctuation. Do not answer the request."

type Prompts is Data:
  Prompts{task: String, agent: String}

def default_prompts() -> Prompts:
  Prompts{instructions(), instructions()}

def task_instructions(prompts: Prompts) -> String:
  Prompts{task, agent} = prompts
  task

def agent_instructions(prompts: Prompts) -> String:
  Prompts{task, agent} = prompts
  agent

def maximum_instruction_bytes() -> Nat:
  4096n

def instruction_characters(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+code}, rest}: Bool.not(U32.is_eq(code, 0)) && U32.is_le(code, 1114111) &&
      Bool.not(U32.is_ge(code, 55296) && U32.is_le(code, 57343)) && instruction_characters(rest)

def valid_instructions(+text: String) -> Bool:
  Bool.not(String.is_empty(String.trim(text))) && Nat.is_le(J.utf8_length(text), maximum_instruction_bytes()) && instruction_characters(text)

def valid_prompts(prompts: Prompts) -> Bool:
  Prompts{task, agent} = prompts
  valid_instructions(task) && valid_instructions(agent)

def same_prompts(left: Prompts, right: Prompts) -> Bool:
  Prompts{task, agent} = left
  Prompts{next_task, next_agent} = right
  String.eq(task, next_task) && String.eq(agent, next_agent)

def choose(condition: Bool, yes: Unit -> String, no: Unit -> String) -> String:
  match condition:
    case True{}: yes(Unit{})
    case False{}: no(Unit{})

def bounded(+text: String, +bytes: Nat) -> String:
  match text:
    case SNil{}: ""
    case SCon{+head, tail}:
      choose(Nat.is_le(J.utf8_length(SCon{head, SNil{}}), bytes),
        (unused => SCon{head, bounded(tail, Nat.sub(bytes, J.utf8_length(SCon{head, SNil{}})))}), (unused => ""))

def title_format() -> String:
  "\nReturn only a JSON object with exactly one string field: title.\n\nUser prompt:\n"

def request_bytes() -> Nat:
  Nat.sub(prompt_bytes(), J.utf8_length(instructions() ++ title_format()))

def maximum_prompt_bytes() -> Nat:
  (maximum_instruction_bytes() + J.utf8_length(title_format()) + request_bytes() : Nat)

def prompt_with(instruction: String, +request: String) -> String:
  instruction ++ title_format() ++ bounded(String.trim(request), request_bytes())

def prompt(request: String) -> String:
  prompt_with(instructions(), request)

def capture_prompt(instruction: String, +title: String, +description: String) -> String:
  instruction ++ "\nReturn only a JSON object with exactly two string fields: title and description. Write a clear actionable description. Preserve the user's requirements, language and constraints. Do not invent requirements or claim completion.\n\nTitle/request preview:\n" ++ title ++ "\n\nOriginal user request:\n" ++ description

def board_prompt(+retitle: Bool, +title: String, +description: String, prompts: Prompts) -> String:
  match retitle:
    case True{}: prompt_with(task_instructions(prompts), title ++ "\n\n" ++ description)
    case False{}: capture_prompt(task_instructions(prompts), title, description)

def whitespace(+code: U32) -> Bool:
  U32.is_eq(code, 32) || (U32.is_ge(code, 9) && U32.is_le(code, 13)) ||
    U32.is_eq(code, 133) || U32.is_eq(code, 160) || U32.is_eq(code, 5760) ||
    (U32.is_ge(code, 8192) && U32.is_le(code, 8202)) || U32.is_eq(code, 8232) ||
    U32.is_eq(code, 8233) || U32.is_eq(code, 8239) || U32.is_eq(code, 8287) || U32.is_eq(code, 12288)

def quote(+code: U32) -> Bool:
  U32.is_eq(code, 34) || U32.is_eq(code, 39) || U32.is_eq(code, 96) ||
    U32.is_eq(code, 8216) || U32.is_eq(code, 8217) || U32.is_eq(code, 8220) || U32.is_eq(code, 8221)

def trim_left_kind(+text: String, +quotes: Bool) -> String:
  match text:
    case SNil{}: ""
    case SCon{Chr{+code}, +rest}: choose(whitespace(code) || (quotes && quote(code)),
      (unused => trim_left_kind(rest, quotes)), (unused => SCon{Chr{code}, rest}))

def collapse_character(+space: Bool, +code: U32, +rest: String, +pending: Bool) -> String:
  match space pending:
    case True{} _: rest
    case False{} True{}: SCon{Chr{32}, SCon{Chr{code}, rest}}
    case False{} False{}: SCon{Chr{code}, rest}

def collapse(+text: String, +pending: Bool) -> String:
  match text:
    case SNil{}: ""
    case SCon{Chr{+code}, rest}: collapse_character(whitespace(code), code, collapse(rest, whitespace(code)), pending)

def trim_punctuation(+text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{Chr{+code}, +rest}: choose(whitespace(code) || U32.is_eq(code, 46) || U32.is_eq(code, 63) || U32.is_eq(code, 33),
      (unused => trim_punctuation(rest)), (unused => SCon{Chr{code}, rest}))

def normalize(+text: String) -> String:
  +unquoted = String.reverse(trim_left_kind(String.reverse(trim_left_kind(text, True{})), True{}))
  String.take(String.reverse(trim_punctuation(String.reverse(collapse(unquoted, False{})))), maximum_characters())

def title_field_schema() -> J.Json:
  J.Object{[J.Field{"type", J.Text{"string"}}, J.Field{"minLength", J.nat(1n)}, J.Field{"maxLength", J.nat(maximum_characters())}]}

def title_schema() -> J.Json:
  J.Object{[J.Field{"type", J.Text{"object"}}, J.Field{"properties", J.Object{[J.Field{"title", title_field_schema()}]}},
    J.Field{"required", J.Array{[J.Text{"title"}]}}, J.Field{"additionalProperties", J.Boolean{False{}}}]}

def description_schema() -> J.Json:
  J.Object{[J.Field{"type", J.Text{"string"}}]}
def output_schema(+capture: Bool) -> J.Json:
  match capture:
    case False{}: title_schema()
    case True{}: J.Object{[J.Field{"type", J.Text{"object"}}, J.Field{"properties", J.Object{[
      J.Field{"title", title_field_schema()},
      J.Field{"description", description_schema()}]}},
      J.Field{"required", J.Array{[J.Text{"title"}, J.Text{"description"}]}}, J.Field{"additionalProperties", J.Boolean{False{}}}]}
