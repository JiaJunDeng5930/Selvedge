import Base
import ../../bendlib/categories.bend as Categories
import ../../bendlib/json.bend as J

type Operations is Type:
  Operations{apply: J.Json -> J.Json}

def faithful(-meaning: J.Json -> J.Json, operations: Operations) -> Type:
  Operations{actual} = operations
  @source:J.Json -> {actual(source) == meaning(source) : J.Json}

def Adapter(-meaning: J.Json -> J.Json) -> Type:
  Categories.Membership<Operations, faithful(meaning)>

def adapter(-meaning: J.Json -> J.Json, actual: J.Json -> J.Json,
  evidence: @source:J.Json -> {actual(source) == meaning(source) : J.Json}) -> Adapter(meaning):
  Categories.Membership{Operations{actual}, evidence}

# The observation and equation retain the same original source; admission must
# not silently replace it with a normalized subset of the request.
def construct(-meaning: J.Json -> J.Json, member: Adapter(meaning), +source: J.Json) -> Categories.Membership<Categories.Construction<J.Json, J.Json>, Categories.constructed_by(J.Json, J.Json, meaning)>:
  Categories.Membership{operations, evidence} = member
  Operations{actual} = operations
  +result = actual(source)
  Categories.Membership{Categories.Construction{source, result}, evidence(source)}

def consume(-meaning: J.Json -> J.Json, member: Categories.Membership<Categories.Construction<J.Json, J.Json>, Categories.constructed_by(J.Json, J.Json, meaning)>) -> J.Json:
  Categories.Membership{construction, evidence} = member
  Categories.Construction{source, result} = construction
  result

def execute(-meaning: J.Json -> J.Json, member: Adapter(meaning), source: J.Json) -> J.Json:
  consume(meaning, construct(meaning, member, source))

def success(value: J.Json) -> J.Json:
  J.Object{Con{J.Field{"ok", J.Boolean{True{}}}, Con{J.Field{"value", value}, Nil{}}}}

def failure(message: String) -> J.Json:
  J.Object{Con{J.Field{"ok", J.Boolean{False{}}}, Con{J.Field{"error", J.Text{message}}, Nil{}}}}

def failure_code(code: String, message: String) -> J.Json:
  J.Object{Con{J.Field{"ok", J.Boolean{False{}}}, Con{J.Field{"error", J.Text{message}}, Con{J.Field{"code", J.Text{code}}, Nil{}}}}}

def same_json(left: J.Json, right: J.Json) -> Bool:
  J.same_unordered(left, right)

# Decimal strings avoid normalizing the JavaScript safe-integer bound into a
# giant unary Nat during checked adapter elaboration.
type DecimalComparison is Data:
  DecimalComparison{left: String, right: String}

def decimal_lexical(comparison: DecimalComparison) -> Bool:
  match comparison:
    case DecimalComparison{SNil{}, SNil{}}: True{}
    case DecimalComparison{SNil{}, SCon{head, rest}}: True{}
    case DecimalComparison{SCon{head, rest}, SNil{}}: False{}
    case DecimalComparison{SCon{Chr{+left}, left_rest}, SCon{Chr{+right}, right_rest}}:
      U32.is_lt(left, right) || (U32.is_eq(left, right) && decimal_lexical(DecimalComparison{left_rest, right_rest}))

def decimal_bound(+text: String) -> Bool:
  Nat.is_lt(String.length(text), 16n) || (Nat.is_eq(String.length(text), 16n) && decimal_lexical(DecimalComparison{text, "9007199254740991"}))

def decimal_digits(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+code}, rest}:
      U32.is_le(48, code) && U32.is_le(code, 57) && decimal_digits(rest)

def decimal_canonical(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{Chr{48}, SNil{}}: True{}
    case SCon{Chr{48}, rest}: False{}
    case SCon{Chr{+code}, rest}:
      U32.is_le(49, code) && U32.is_le(code, 57) && decimal_digits(rest)

def safe_integer_magnitude(+text: String) -> Bool:
  decimal_canonical(text) && decimal_bound(text)

def safe_integer_lexeme(text: String) -> Bool:
  match text:
    case SCon{Chr{45}, rest}: safe_integer_magnitude(rest)
    case other: safe_integer_magnitude(other)

def safe_integer(value: J.Json) -> Bool:
  match value:
    case J.Number{lexeme}: safe_integer_lexeme(lexeme)
    case _: False{}

def decimal_le(+text: String, +maximum: String) -> Bool:
  Nat.is_lt(String.length(text), String.length(maximum)) ||
    (Nat.is_eq(String.length(text), String.length(maximum)) && decimal_lexical(DecimalComparison{text, maximum}))

def nonnegative_le(value: J.Json, maximum: String) -> Bool:
  match value:
    case J.Number{+lexeme}: decimal_canonical(lexeme) && decimal_le(lexeme, maximum)
    case _: False{}

def parsed_array(+value: J.Json) -> Bool:
  match value:
    case J.Array{items}: True{}
    case _: False{}

def parsed_token_tail(+text: String, +result: Result<&2, &2, String, +List<&2, String>>) -> Result<&2, &2, String, +List<&2, String>>:
  match result:
    case Done{rest}: Done{Con{text, rest}}
    case Fail{error}: Fail{error}

def parsed_tokens(+items: +List<&2, J.Json>) -> Result<&2, &2, String, +List<&2, String>>:
  match items:
    case Nil{}: Done{Nil{}}
    case Con{J.Text{text}, rest}: parsed_token_tail(text, parsed_tokens(rest))
    case _: Fail{"Invalid JSON parsing observation"}

def parsed_observation_bound(+bound: Bool, +result: Result<&2, &2, String, +List<&2, String>>) -> Result<&2, &2, String, J.Json>:
  match bound result:
    case True{} Done{values}: J.decode(values)
    case _ _: Fail{"Invalid JSON parsing observation"}

def parsed_observation(+source: J.Json) -> Result<&2, &2, String, J.Json>:
  +observed = J.get(source, "observation")
  parsed_observation_bound(J.same(J.get(source, "text"), J.get(observed, "text")) && parsed_array(J.get(observed, "tokens")), parsed_tokens(J.items(J.get(observed, "tokens"))))
