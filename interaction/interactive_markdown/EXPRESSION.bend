import Base
import ../../bendlib/string-equality.bend as SafeText
import ../../bendlib/json.bend as J
import ../../bendlib/stdlib.bend as Std
import ./DECIMAL.bend as D

type Expr is Data:
  Literal{value: J.Json}
  Reference{name: String}
  Unary{operator: String, argument: Expr}
  Binary{operator: String, left: Expr, right: Expr}
  Conditional{test: Expr, yes: Expr, no: Expr}
  Access{value: Expr, key: Expr}
  Array{items: +List<Expr>}
  Record{fields: +List<ExprField>}
  Call{name: String, arguments: +List<Expr>}

type ExprField is Data:
  ExprField{name: String, value: Expr}

type Token is Data:
  Identifier{text: String}
  Quoted{text: String}
  Numeric{text: String}
  Symbol{text: String}

type Scan is Data:
  Scan{text: String, rest: String}

def ident_start(+char: Char) -> Bool:
  Char.is_alpha(char) || Char.is_eq(char, '_')

def ident_continue(+char: Char) -> Bool:
  ident_start(char) || Char.is_digit(char)

def choose(-A: Data, +condition: Bool, yes: Unit -> A, no: Unit -> A) -> A:
  Bool.pick((Unit -> A), condition, yes, no)(Unit{})

def scan_word(+text: String, +accumulator: String, +number: Bool) -> Scan:
  match text:
    case SNil{}: Scan{accumulator, ""}
    case SCon{+char, +rest}:
      choose(Scan, Bool.pick(Bool, number, Char.is_digit(char) || Char.is_eq(char, '.'), ident_continue(char)),
        (_ => scan_word(rest, accumulator ++ SCon{char, ""}, number)),
        (_ => Scan{accumulator, SCon{char, rest}}))

def hex(+char: Char) -> Maybe<&2, U32>:
  match char:
    case Chr{+code}:
      choose((Maybe<&2, U32>), U32.is_ge(code, 48) && U32.is_le(code, 57),
        (_ => Some{U32.sub(code, 48)}),
        (_ => choose((Maybe<&2, U32>), U32.is_ge(code, 65) && U32.is_le(code, 70),
          (_ => Some{U32.add(U32.sub(code, 65), 10)}),
          (_ => choose((Maybe<&2, U32>), U32.is_ge(code, 97) && U32.is_le(code, 102),
            (_ => Some{U32.add(U32.sub(code, 97), 10)}), (_ => None{}))))))

def hex4(+a: Maybe<&2, U32>, +b: Maybe<&2, U32>, +c: Maybe<&2, U32>, +d: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match a b c d:
    case Some{+a} Some{+b} Some{+c} Some{+d}: Some{U32.add(U32.add(U32.mul(a, 4096), U32.mul(b, 256)), U32.add(U32.mul(c, 16), d))}
    case _ _ _ _: None{}

type StringScan is Data:
  StringScan{rest: String, value: String, pendingHigh: U32, error: String, complete: Bool}

def string_unit(+rest: String, +accumulator: String, +code: Maybe<&2, U32>, +pending: U32) -> StringScan:
  match code:
    case None{}: StringScan{rest, accumulator, pending, "invalid Unicode escape", False{}}
    case Some{+code}:
      choose(StringScan, U32.is_ge(code, 55296) && U32.is_le(code, 56319),
        (_ => choose(StringScan, U32.is_eq(pending, 0),
          (_ => StringScan{rest, accumulator, code, "", False{}}),
          (_ => StringScan{rest, accumulator, pending, "unpaired high surrogate", False{}}))),
        (_ => choose(StringScan, U32.is_ge(code, 56320) && U32.is_le(code, 57343),
          (_ => choose(StringScan, U32.is_ne(pending, 0),
            (_ => StringScan{rest, accumulator ++ SCon{Chr{U32.add(65536, U32.add(U32.mul(U32.sub(pending, 55296), 1024), U32.sub(code, 56320)))}, ""}, 0, "", False{}}),
            (_ => StringScan{rest, accumulator, pending, "unpaired low surrogate", False{}}))),
          (_ => choose(StringScan, U32.is_eq(pending, 0),
            (_ => StringScan{rest, accumulator ++ SCon{Chr{code}, ""}, 0, "", False{}}),
            (_ => StringScan{rest, accumulator, pending, "unpaired high surrogate", False{}}))))))

def escape_char(+char: Char) -> Maybe<&2, U32>:
  match char:
    case '"': Some{34}
    case '\\': Some{92}
    case '/': Some{47}
    case 'b': Some{8}
    case 'f': Some{12}
    case 'n': Some{10}
    case 'r': Some{13}
    case 't': Some{9}
    case _: None{}

def string_raw(+char: Char, +rest: String, +accumulator: String, +pending: U32) -> StringScan:
  choose(StringScan, U32.is_ge(Char.to_u32(char), 32) && U32.is_eq(pending, 0),
    (_ => StringScan{rest, accumulator ++ SCon{char, ""}, 0, "", False{}}),
    (_ => StringScan{rest, accumulator, pending, "invalid raw string character", False{}}))

def string_unicode(+text: String, +accumulator: String, +pending: U32) -> StringScan:
  match text:
    case SCon{+a, SCon{+b, SCon{+c, SCon{+d, +rest}}}}:
      string_unit(rest, accumulator, hex4(hex(a), hex(b), hex(c), hex(d)), pending)
    case +rest: string_unit(rest, accumulator, None{}, pending)

def string_escape(+text: String, +accumulator: String, +pending: U32) -> StringScan:
  match text:
    case SNil{}: string_raw('\\', "", accumulator, pending)
    case SCon{+char, +rest}:
      choose(StringScan, Char.is_eq(char, 'u'),
        (_ => string_unicode(rest, accumulator, pending)),
        (_ => string_unit(rest, accumulator, escape_char(char), pending)))

def string_character(+char: Char, +rest: String, +accumulator: String, +pending: U32) -> StringScan:
  choose(StringScan, Char.is_eq(char, '"'),
    (_ => choose(StringScan, U32.is_eq(pending, 0),
      (_ => StringScan{rest, accumulator, 0, "", True{}}),
      (_ => StringScan{rest, accumulator, pending, "unpaired high surrogate", False{}}))),
    (_ => choose(StringScan, Char.is_eq(char, '\\'),
      (_ => string_escape(rest, accumulator, pending)),
      (_ => string_raw(char, rest, accumulator, pending)))))

def string_step(+state: StringScan) -> StringScan:
  match state:
    case StringScan{SCon{+char, +rest}, +accumulator, +pending, +error, +complete}:
      string_character(char, rest, accumulator, pending)
    case StringScan{SNil{}, +accumulator, +pending, +error, +complete}: StringScan{"", accumulator, pending, "unterminated string", False{}}

def string_error(+state: StringScan) -> String:
  match state:
    case StringScan{+rest, +value, +pending, +error, +complete}: error

def string_loop(+fuel: Nat, +state: StringScan) -> Result<&2, &2, String, Scan>:
  match fuel state:
    case _ StringScan{+rest, +value, +pending, +error, True{}}: Done{Scan{value, rest}}
    case 0n _: Fail{"string budget exceeded"}
    case 1n+left +state:
      choose((Result<&2, &2, String, Scan>), String.eq(string_error(state), ""),
        (_ => string_loop(left, string_step(state))), (_ => Fail{string_error(state)}))

type Lexed is Data:
  Lexed{rest: String, reversed: +List<Token>, error: String}

def lex_scan(+scan: Scan, +tokens: +List<Token>, +number: Bool) -> Lexed:
  match scan:
    case Scan{+word, +rest}: Lexed{rest, Bool.pick(Token, number, Numeric{word}, Identifier{word}) <> tokens, ""}

def lex_string(+scan: Result<&2, &2, String, Scan>, +tokens: +List<Token>) -> Lexed:
  match scan:
    case Fail{+error}: Lexed{"", tokens, error}
    case Done{Scan{+value, +rest}}: Lexed{rest, Quoted{value} <> tokens, ""}

def lex_single(+char: Char, +rest: String, +tokens: +List<Token>) -> Lexed:
  choose(Lexed, String.contains("()[]{},.:?+-*/%!<>", SCon{char, ""}),
    (_ => Lexed{rest, Symbol{SCon{char, ""}} <> tokens, ""}),
    (_ => Lexed{rest, tokens, "unknown expression character"}))

def lex_step(+state: Lexed) -> Lexed:
  match state:
    case Lexed{SCon{'"', +rest}, +tokens, +error}: lex_string(string_loop(8193n, StringScan{rest, "", 0, "", False{}}), tokens)
    case Lexed{SCon{'&', SCon{'&', +rest}}, +tokens, +error}: Lexed{rest, Symbol{"&&"} <> tokens, ""}
    case Lexed{SCon{'|', SCon{'|', +rest}}, +tokens, +error}: Lexed{rest, Symbol{"||"} <> tokens, ""}
    case Lexed{SCon{'=', SCon{'=', +rest}}, +tokens, +error}: Lexed{rest, Symbol{"=="} <> tokens, ""}
    case Lexed{SCon{'!', SCon{'=', +rest}}, +tokens, +error}: Lexed{rest, Symbol{"!="} <> tokens, ""}
    case Lexed{SCon{'<', SCon{'=', +rest}}, +tokens, +error}: Lexed{rest, Symbol{"<="} <> tokens, ""}
    case Lexed{SCon{'>', SCon{'=', +rest}}, +tokens, +error}: Lexed{rest, Symbol{">="} <> tokens, ""}
    case Lexed{SCon{+char, +rest}, +tokens, +error}:
      choose(Lexed, Char.is_space(char), (_ => Lexed{rest, tokens, ""}),
        (_ => choose(Lexed, ident_start(char),
          (_ => lex_scan(scan_word(rest, SCon{char, ""}, False{}), tokens, False{})),
          (_ => choose(Lexed, Char.is_digit(char),
            (_ => lex_scan(scan_word(rest, SCon{char, ""}, True{}), tokens, True{})),
            (_ => lex_single(char, rest, tokens)))))))
    case +other: other

def lex_error(+state: Lexed) -> String:
  match state:
    case Lexed{+rest, +tokens, +error}: error

def lex_loop(+fuel: Nat, +state: Lexed) -> Result<&2, &2, String, +List<Token>>:
  match fuel state:
    case _ Lexed{SNil{}, +tokens, ""}: Done{List.reverse(&2, Token, tokens)}
    case 0n _: Fail{"expression token budget exceeded"}
    case 1n+left +state:
      choose((Result<&2, &2, String, +List<Token>>), String.eq(lex_error(state), ""),
        (_ => lex_loop(left, lex_step(state))), (_ => Fail{lex_error(state)}))

type ParseTask is Data:
  Read{minimum: Nat, depth: Nat}
  Loop{minimum: Nat, depth: Nat}
  Expect{symbol: String}
  UnaryFinish{operator: String}
  BinaryFinish{operator: String, left: Expr}
  ConditionalYes{test: Expr, depth: Nat}
  ConditionalFinish{test: Expr, yes: Expr}
  AccessFinish{left: Expr}
  Items{kind: String, name: String, reversed: +List<Expr>, depth: Nat}
  ItemFinish{kind: String, name: String, reversed: +List<Expr>, depth: Nat}
  ItemSeparator{kind: String, name: String, reversed: +List<Expr>, depth: Nat}
  Fields{reversed: +List<ExprField>, depth: Nat}
  FieldFinish{name: String, reversed: +List<ExprField>, depth: Nat}
  FieldSeparator{reversed: +List<ExprField>, depth: Nat}

type ParseState is Data:
  ParseState{tasks: +List<ParseTask>, tokens: +List<Token>, values: +List<Expr>, error: String}

def precedence(+op: String) -> Nat:
  match op:
    case "||": 1n
    case "&&": 2n
    case "==": 3n
    case "!=": 3n
    case "<": 4n
    case "<=": 4n
    case ">": 4n
    case ">=": 4n
    case "+": 5n
    case "-": 5n
    case "*": 6n
    case "/": 6n
    case "%": 6n
    case _: 0n

def parse_number(+value: Result<&2, &2, String, String>, +tasks: +List<ParseTask>, +tokens: +List<Token>, +values: +List<Expr>) -> ParseState:
  match value:
    case Fail{+error}: ParseState{tasks, tokens, values, error}
    case Done{+number}: ParseState{tasks, tokens, Literal{J.Number{number}} <> values, ""}

def item_result(+kind: String, +name: String, +reversed: +List<Expr>) -> Expr:
  match kind:
    case "array": Array{List.reverse(&2, Expr, reversed)}
    case _: Call{name, List.reverse(&2, Expr, reversed)}

def item_closer(+kind: String) -> String:
  match kind:
    case "array": "]"
    case _: ")"

def fields_have(+fields: +List<ExprField>, +name: String) -> Bool:
  match fields:
    case Nil{}: False{}
    case Con{ExprField{+key, +value}, +rest}: SafeText.string_equal(key, name) || fields_have(rest, name)

type PrefixContext is Data:
  PrefixContext{minimum: Nat, depth: Nat, tasks: +List<ParseTask>, values: +List<Expr>}

def prefix_child_depth(+context: PrefixContext) -> Nat:
  match context:
    case PrefixContext{minimum, depth, tasks, values}: 1n+depth

def prefix_emit(+value: Expr, +tokens: +List<Token>, +context: PrefixContext) -> ParseState:
  match context:
    case PrefixContext{minimum, depth, tasks, values}:
      ParseState{Loop{minimum, depth} <> tasks, tokens, value <> values, ""}

def prefix_prepend(+added: +List<ParseTask>, +tokens: +List<Token>, +context: PrefixContext) -> ParseState:
  match context:
    case PrefixContext{minimum, depth, tasks, values}:
      ParseState{List.append(&2, ParseTask, added, Loop{minimum, depth} <> tasks), tokens, values, ""}

def prefix_failure(+tokens: +List<Token>, +context: PrefixContext) -> ParseState:
  match context:
    case PrefixContext{minimum, depth, tasks, values}: ParseState{tasks, tokens, values, "expected expression value"}

def prefix_numeric(+number: String, +tokens: +List<Token>, +context: PrefixContext) -> ParseState:
  match context:
    case PrefixContext{minimum, depth, tasks, values}: parse_number(D.parse(number), Loop{minimum, depth} <> tasks, tokens, values)

def prefix_reference(+name: String, +tokens: +List<Token>, +context: PrefixContext) -> ParseState:
  match tokens:
    case Con{Symbol{"("}, +rest}: prefix_prepend([Items{"call", name, Nil{}, prefix_child_depth(context)}], rest, context)
    case +other: prefix_emit(Reference{name}, other, context)

def prefix_identifier(+name: String, +tokens: +List<Token>, +context: PrefixContext) -> ParseState:
  choose(ParseState, String.eq(name, "true"),
    (_ => prefix_emit(Literal{J.Boolean{True{}}}, tokens, context)),
    (_ => choose(ParseState, String.eq(name, "false"),
      (_ => prefix_emit(Literal{J.Boolean{False{}}}, tokens, context)),
      (_ => choose(ParseState, String.eq(name, "null"),
        (_ => prefix_emit(Literal{J.Null{}}, tokens, context)),
        (_ => prefix_reference(name, tokens, context)))))))

def prefix_symbol(+operator: String, +tokens: +List<Token>, +context: PrefixContext) -> ParseState:
  match operator:
    case "(": prefix_prepend([Read{0n, prefix_child_depth(context)}, Expect{")"}], tokens, context)
    case "[": prefix_prepend([Items{"array", "", Nil{}, prefix_child_depth(context)}], tokens, context)
    case "{": prefix_prepend([Fields{Nil{}, prefix_child_depth(context)}], tokens, context)
    case _:
      choose(ParseState, String.eq(operator, "!") || String.eq(operator, "-"),
        (_ => prefix_prepend([Read{7n, prefix_child_depth(context)}, UnaryFinish{operator}], tokens, context)),
        (_ => prefix_failure(tokens, context)))

def prefix_token(+token: Token, +tokens: +List<Token>, +context: PrefixContext) -> ParseState:
  match token:
    case Numeric{number}: prefix_numeric(number, tokens, context)
    case Quoted{text}: prefix_emit(Literal{J.Text{text}}, tokens, context)
    case Identifier{name}: prefix_identifier(name, tokens, context)
    case Symbol{operator}: prefix_symbol(operator, tokens, context)

def prefix_tokens(+tokens: +List<Token>, +context: PrefixContext) -> ParseState:
  match tokens:
    case Con{token, rest}: prefix_token(token, rest, context)
    case Nil{}: prefix_failure(Nil{}, context)

def prefix_step(+minimum: Nat, +depth: Nat, +tasks: +List<ParseTask>, +tokens: +List<Token>, +values: +List<Expr>) -> ParseState:
  prefix_tokens(tokens, PrefixContext{minimum, depth, tasks, values})

def loop_step(+minimum: Nat, +depth: Nat, +tasks: +List<ParseTask>, +tokens: +List<Token>, +values: +List<Expr>) -> ParseState:
  match tokens values:
    case Con{Symbol{"."}, Con{Identifier{+name}, +tokens}} Con{+left, +values}:
      ParseState{Loop{minimum, depth} <> tasks, tokens, Access{left, Literal{J.Text{name}}} <> values, ""}
    case Con{Symbol{"["}, +tokens} Con{+left, +values}:
      ParseState{Read{0n, 1n+depth} <> Expect{"]"} <> AccessFinish{left} <> Loop{minimum, depth} <> tasks, tokens, values, ""}
    case Con{Symbol{"?"}, +tokens} Con{+left, +values}:
      choose(ParseState, Nat.is_eq(minimum, 0n),
        (_ => ParseState{Read{0n, 1n+depth} <> ConditionalYes{left, 1n+depth} <> tasks, tokens, values, ""}),
        (_ => ParseState{tasks, Symbol{"?"} <> tokens, left <> values, ""}))
    case Con{Symbol{+op}, +tokens} Con{+left, +values}:
      +power = precedence(op)
      choose(ParseState, Nat.is_gt(power, 0n) && Nat.is_ge(power, minimum),
        (_ => ParseState{Read{1n+power, 1n+depth} <> BinaryFinish{op, left} <> Loop{minimum, depth} <> tasks, tokens, values, ""}),
        (_ => ParseState{tasks, Symbol{op} <> tokens, left <> values, ""}))
    case +tokens +values: ParseState{tasks, tokens, values, ""}

def items_step(+kind: String, +name: String, +reversed: +List<Expr>, +depth: Nat, +tasks: +List<ParseTask>, +tokens: +List<Token>, +values: +List<Expr>) -> ParseState:
  match tokens:
    case Con{Symbol{+symbol}, +rest}:
      choose(ParseState, String.eq(symbol, item_closer(kind)),
        (_ => ParseState{tasks, rest, item_result(kind, name, reversed) <> values, ""}),
        (_ => ParseState{Read{0n, depth} <> ItemFinish{kind, name, reversed, depth} <> tasks, Symbol{symbol} <> rest, values, ""}))
    case +other: ParseState{Read{0n, depth} <> ItemFinish{kind, name, reversed, depth} <> tasks, other, values, ""}

def field_start(+name: String, +reversed: +List<ExprField>, +depth: Nat, +tasks: +List<ParseTask>, +tokens: +List<Token>, +values: +List<Expr>) -> ParseState:
  choose(ParseState, fields_have(reversed, name),
    (_ => ParseState{tasks, tokens, values, "duplicate record key"}),
    (_ => ParseState{Read{0n, depth} <> FieldFinish{name, reversed, depth} <> tasks, tokens, values, ""}))

def fields_step(+reversed: +List<ExprField>, +depth: Nat, +tasks: +List<ParseTask>, +tokens: +List<Token>, +values: +List<Expr>) -> ParseState:
  match tokens:
    case Con{Symbol{"}"}, +rest}: ParseState{tasks, rest, Record{List.reverse(&2, ExprField, reversed)} <> values, ""}
    case Con{Identifier{+name}, Con{Symbol{":"}, rest}}: field_start(name, reversed, depth, tasks, rest, values)
    case Con{Quoted{+name}, Con{Symbol{":"}, rest}}: field_start(name, reversed, depth, tasks, rest, values)
    case +other: ParseState{tasks, other, values, "expected static record key"}

def parse_step(+state: ParseState) -> ParseState:
  match state:
    case ParseState{Con{Read{+minimum, +depth}, +tasks}, +tokens, +values, +error}:
      choose(ParseState, Nat.is_gt(depth, 32n),
        (_ => ParseState{tasks, tokens, values, "expression depth exceeded"}),
        (_ => prefix_step(minimum, depth, tasks, tokens, values)))
    case ParseState{Con{Loop{+minimum, +depth}, +tasks}, +tokens, +values, +error}: loop_step(minimum, depth, tasks, tokens, values)
    case ParseState{Con{Expect{+wanted}, +tasks}, Con{Symbol{+actual}, +tokens}, +values, +error}:
      choose(ParseState, String.eq(wanted, actual),
        (_ => ParseState{tasks, tokens, values, ""}), (_ => ParseState{tasks, tokens, values, "expected closing delimiter"}))
    case ParseState{Con{UnaryFinish{+op}, +tasks}, +tokens, Con{+value, +values}, +error}: ParseState{tasks, tokens, Unary{op, value} <> values, ""}
    case ParseState{Con{BinaryFinish{+op, +left}, +tasks}, +tokens, Con{+right, +values}, +error}: ParseState{tasks, tokens, Binary{op, left, right} <> values, ""}
    case ParseState{Con{AccessFinish{+left}, +tasks}, +tokens, Con{+key, +values}, +error}: ParseState{tasks, tokens, Access{left, key} <> values, ""}
    case ParseState{Con{ConditionalYes{+test, +depth}, +tasks}, +tokens, Con{+yes, +values}, +error}:
      ParseState{Expect{":"} <> Read{0n, depth} <> ConditionalFinish{test, yes} <> tasks, tokens, values, ""}
    case ParseState{Con{ConditionalFinish{+test, +yes}, +tasks}, +tokens, Con{+no, +values}, +error}: ParseState{tasks, tokens, Conditional{test, yes, no} <> values, ""}
    case ParseState{Con{Items{+kind, +name, +reversed, +depth}, +tasks}, +tokens, +values, +error}:
      items_step(kind, name, reversed, depth, tasks, tokens, values)
    case ParseState{Con{ItemFinish{+kind, +name, +reversed, +depth}, +tasks}, +tokens, Con{+value, +values}, +error}:
      ParseState{ItemSeparator{kind, name, value <> reversed, depth} <> tasks, tokens, values, ""}
    case ParseState{Con{ItemSeparator{+kind, +name, +reversed, +depth}, +tasks}, Con{Symbol{","}, +tokens}, +values, +error}:
      ParseState{Items{kind, name, reversed, depth} <> tasks, tokens, values, ""}
    case ParseState{Con{ItemSeparator{+kind, +name, +reversed, +depth}, +tasks}, Con{Symbol{+symbol}, +tokens}, +values, +error}:
      choose(ParseState, String.eq(symbol, item_closer(kind)),
        (_ => ParseState{tasks, tokens, item_result(kind, name, reversed) <> values, ""}),
        (_ => ParseState{tasks, tokens, values, "expected item separator"}))
    case ParseState{Con{Fields{+reversed, +depth}, +tasks}, +tokens, +values, +error}: fields_step(reversed, depth, tasks, tokens, values)
    case ParseState{Con{FieldFinish{+name, +reversed, +depth}, +tasks}, +tokens, Con{+value, +values}, +error}:
      ParseState{FieldSeparator{ExprField{name, value} <> reversed, depth} <> tasks, tokens, values, ""}
    case ParseState{Con{FieldSeparator{+reversed, +depth}, +tasks}, Con{Symbol{","}, +tokens}, +values, +error}:
      ParseState{Fields{reversed, depth} <> tasks, tokens, values, ""}
    case ParseState{Con{FieldSeparator{+reversed, +depth}, +tasks}, Con{Symbol{"}"}, +tokens}, +values, +error}:
      ParseState{tasks, tokens, Record{List.reverse(&2, ExprField, reversed)} <> values, ""}
    case ParseState{+tasks, +tokens, +values, +error}: ParseState{tasks, tokens, values, "invalid or incomplete expression"}

def parse_error(+state: ParseState) -> String:
  match state:
    case ParseState{+tasks, +tokens, +values, +error}: error

def parse_loop(+fuel: Nat, +state: ParseState) -> Result<&2, &2, String, Expr>:
  match fuel state:
    case _ ParseState{Nil{}, Nil{}, Con{+expression, Nil{}}, ""}: Done{expression}
    case _ ParseState{Nil{}, +tokens, +values, ""}: Fail{"unexpected trailing expression tokens"}
    case 0n _: Fail{"expression parsing budget exceeded"}
    case 1n+left +state:
      choose((Result<&2, &2, String, Expr>), String.eq(parse_error(state), ""),
        (_ => parse_loop(left, parse_step(state))), (_ => Fail{parse_error(state)}))

def parse_tokens(+result: Result<&2, &2, String, +List<Token>>) -> Result<&2, &2, String, Expr>:
  match result:
    case Fail{+error}: Fail{error}
    case Done{+tokens}: parse_loop(65536n, ParseState{Read{0n, 0n} <> Nil{}, tokens, Nil{}, ""})

def parse(+text: String) -> Result<&2, &2, String, Expr>:
  choose((Result<&2, &2, String, Expr>), Nat.is_le(String.length(text), 8192n),
    (_ => parse_tokens(lex_loop(8193n, Lexed{text, Nil{}, ""}))), (_ => Fail{"expression text budget exceeded"}))

def all_true(+items: +List<Bool>) -> Bool:
  List.foldl(~&2, ~Bool, ~Bool, ~(left => right => left && right), items, True{})

def has_field(+fields: +List<J.Field>, +name: String) -> Bool:
  match fields:
    case Nil{}: False{}
    case Con{J.Field{+key, +value}, +rest}: SafeText.string_equal(key, name) || has_field(rest, name)

def list_at(+items: +List<J.Json>, +index: Nat) -> J.Json:
  match items index:
    case Nil{} _: J.Null{}
    case Con{+head, +rest} 0n: head
    case Con{+head, +rest} 1n+left: list_at(rest, left)

def numeric_equality(+result: Result<&2, &2, String, Bool>) -> Bool:
  match result:
    case Done{+same}: same
    case Fail{+error}: False{}

def field_name(+field: J.Field) -> String:
  match field:
    case J.Field{+name, +value}: name

def field_value(+field: J.Field) -> J.Json:
  match field:
    case J.Field{+name, +value}: value

type Comparison is Data:
  Comparison{left: J.Json, right: J.Json}

type SameState is Data:
  SameState{pending: +List<Comparison>, same: Bool}

def comparison_arrays(+left: +List<J.Json>, +right: +List<J.Json>, +tail: +List<Comparison>) -> SameState:
  match left right:
    case Nil{} Nil{}: SameState{tail, True{}}
    case Con{+left, +lr} Con{+right, +rr}: comparison_arrays(lr, rr, Comparison{left, right} <> tail)
    case _ _: SameState{tail, False{}}

def comparison_fields(+left: +List<J.Field>, +right: +List<J.Field>, +tail: +List<Comparison>) -> SameState:
  match left:
    case Nil{}: SameState{tail, True{}}
    case Con{J.Field{+name, +value}, +rest}:
      choose(SameState, has_field(right, name),
        (_ => comparison_fields(rest, right, Comparison{value, J.find(right, name)} <> tail)),
        (_ => SameState{tail, False{}}))

def same_step(+pair: Comparison, +tail: +List<Comparison>) -> SameState:
  match pair:
    case Comparison{J.Null{}, J.Null{}}: SameState{tail, True{}}
    case Comparison{J.Boolean{+left}, J.Boolean{+right}}: SameState{tail, D.bool_equal(left, right)}
    case Comparison{J.Number{+left}, J.Number{+right}}: SameState{tail, numeric_equality(D.compare("==", left, right))}
    case Comparison{J.Text{+left}, J.Text{+right}}: SameState{tail, SafeText.string_equal(left, right)}
    case Comparison{J.Array{+left}, J.Array{+right}}: comparison_arrays(left, right, tail)
    case Comparison{J.Object{+left}, J.Object{+right}}:
      choose(SameState, Nat.is_eq(List.length(&2, J.Field, left), List.length(&2, J.Field, right)),
        (_ => comparison_fields(left, right, tail)), (_ => SameState{tail, False{}}))
    case _: SameState{tail, False{}}

def same_loop(+fuel: Nat, +state: SameState) -> Bool:
  match fuel state:
    case _ SameState{+pending, False{}}: False{}
    case _ SameState{Nil{}, True{}}: True{}
    case 0n _: False{}
    case 1n+left SameState{Con{+pair, +tail}, True{}}: same_loop(left, same_step(pair, tail))

def json_same(+fuel: Nat, +left: J.Json, +right: J.Json) -> Bool:
  same_loop(fuel, SameState{Comparison{left, right} <> Nil{}, True{}})

def expr_field_value(field: ExprField) -> Expr:
  match field:
    case ExprField{+name, +value}: value

def expression_children(+expression: Expr) -> +List<Expr>:
  match expression:
    case Literal{+value}: Nil{}
    case Reference{+name}: Nil{}
    case Unary{+operator, +argument}: argument <> Nil{}
    case Binary{+operator, +left, +right}: left <> right <> Nil{}
    case Conditional{+test, +yes, +no}: test <> yes <> no <> Nil{}
    case Access{+value, +key}: value <> key <> Nil{}
    case Array{+items}: items
    case Record{+fields}: Std.map(~ExprField, ~Expr, ~expr_field_value, fields)
    case Call{+name, +arguments}: arguments

type Inventory is Data:
  Inventory{references: +List<String>, literal: Bool}

def expression_literal(+expression: Expr) -> Bool:
  match expression:
    case Literal{+value}: True{}
    case Array{+items}: True{}
    case Record{+fields}: True{}
    case Unary{+operator, +argument}: String.eq(operator, "-")
    case _: False{}

def expression_reference(+expression: Expr, +references: +List<String>) -> +List<String>:
  match expression:
    case Reference{+name}: name <> references
    case _: references

def inventory_loop(+fuel: Nat, +pending: +List<Expr>, +references: +List<String>, +literal: Bool) -> Inventory:
  match fuel pending:
    case _ Nil{}: Inventory{List.reverse(&2, String, references), literal}
    case 0n _: Inventory{references, False{}}
    case 1n+rest Con{+expression, +pending}:
      inventory_loop(rest, List.append(&2, Expr, expression_children(expression), pending), expression_reference(expression, references), literal && expression_literal(expression))

def inventory_references(+inventory: Inventory) -> +List<String>:
  match inventory:
    case Inventory{+references, +literal}: references

def inventory_literal(+inventory: Inventory) -> Bool:
  match inventory:
    case Inventory{+references, +literal}: literal

def references(+expression: Expr) -> +List<String>:
  inventory_references(inventory_loop(16384n, expression <> Nil{}, Nil{}, True{}))

def literal_only(+expression: Expr) -> Bool:
  inventory_literal(inventory_loop(16384n, expression <> Nil{}, Nil{}, True{}))

def number_result(+result: Result<&2, &2, String, String>) -> Result<&2, &2, String, J.Json>:
  match result:
    case Fail{+error}: Fail{error}
    case Done{+number}: Done{J.Number{number}}

def text_result(+result: Result<&2, &2, String, String>) -> Result<&2, &2, String, J.Json>:
  match result:
    case Fail{+error}: Fail{error}
    case Done{+text}: Done{J.Text{text}}

def bool_result(+result: Result<&2, &2, String, Bool>) -> Result<&2, &2, String, J.Json>:
  match result:
    case Fail{+error}: Fail{error}
    case Done{+value}: Done{J.Boolean{value}}

def unary(+operator: String, +value: J.Json) -> Result<&2, &2, String, J.Json>:
  match operator value:
    case "!" J.Boolean{+value}: Done{J.Boolean{Bool.not(value)}}
    case "-" J.Number{+number}: number_result(D.arithmetic("-", "0", number))
    case _ _: Fail{"invalid unary operand"}

def binary(+operator: String, +left: J.Json, +right: J.Json) -> Result<&2, &2, String, J.Json>:
  match operator left right:
    case "==" +left +right: Done{J.Boolean{json_same(100000n, left, right)}}
    case "!=" +left +right: Done{J.Boolean{Bool.not(json_same(100000n, left, right))}}
    case "+" J.Text{+left} J.Text{+right}: Done{J.Text{left ++ right}}
    case +op J.Number{+left} J.Number{+right}:
      choose((Result<&2, &2, String, J.Json>), String.eq(op, "+") || String.eq(op, "-") || String.eq(op, "*") || String.eq(op, "/") || String.eq(op, "%"),
        (_ => number_result(D.arithmetic(op, left, right))), (_ => bool_result(D.compare(op, left, right))))
    case "&&" J.Boolean{+left} J.Boolean{+right}: Done{J.Boolean{left && right}}
    case "||" J.Boolean{+left} J.Boolean{+right}: Done{J.Boolean{left || right}}
    case _ _ _: Fail{"invalid binary operands"}

def numeric_index(+parsed: Maybe<&2, Nat>, +items: +List<J.Json>) -> Result<&2, &2, String, J.Json>:
  match parsed:
    case Some{+index}: Done{list_at(items, index)}
    case None{}: Fail{"list index must be a nonnegative integer"}

def access(+value: J.Json, +key: J.Json) -> Result<&2, &2, String, J.Json>:
  match value key:
    case J.Object{+fields} J.Text{+name}: Done{J.find(fields, name)}
    case J.Array{+items} J.Number{+index}: numeric_index(Nat.read(index), items)
    case _ _: Fail{"invalid field or index access"}

def path_valid(+parts: +List<String>) -> Bool:
  match parts:
    case Nil{}: False{}
    case Con{+part, Nil{}}: Bool.not(String.eq(part, ""))
    case Con{+part, +rest}: Bool.not(String.eq(part, "")) && path_valid(rest)

def path_get(+parts: +List<String>, +value: J.Json) -> J.Json:
  match parts:
    case Nil{}: value
    case Con{+name, +rest}: path_get(rest, J.get(value, name))

def path_field(+value: J.Json, +path: String) -> J.Json:
  path_get(String.split(path, '.'), value)

def scalar(+value: J.Json) -> Bool:
  match value:
    case J.Array{+items}: False{}
    case J.Object{+fields}: False{}
    case _: True{}

def sum_row(+prior: String, +value: J.Json) -> Result<&2, &2, String, String>:
  match value:
    case J.Number{+value}: D.arithmetic("+", prior, value)
    case _: Fail{"sum requires numeric record fields"}

def sum_rows(+rows: +List<J.Json>, +path: String, +sum: Result<&2, &2, String, String>) -> Result<&2, &2, String, String>:
  match rows sum:
    case Nil{} +result: result
    case Con{+row, +rest} Fail{+error}: Fail{error}
    case Con{+row, +rest} Done{+prior}: sum_rows(rest, path, sum_row(prior, path_field(row, path)))

def records_only(+rows: +List<J.Json>) -> Bool:
  match rows:
    case Nil{}: True{}
    case Con{J.Object{+fields}, +rest}: records_only(rest)
    case _: False{}

def filter_rows(+rows: +List<J.Json>, +path: String, +wanted: J.Json) -> +List<J.Json>:
  match rows:
    case Nil{}: Nil{}
    case Con{+row, +rest}:
      +tail = filter_rows(rest, path, wanted)
      choose((+List<J.Json>), json_same(100000n, path_field(row, path), wanted),
        (_ => row <> tail), (_ => tail))

def key_type(+value: J.Json) -> String:
  match value:
    case J.Number{+number}: "number"
    case J.Text{+text}: "string"
    case _: "invalid"

def sort_valid(+rows: +List<J.Json>, +path: String, +kind: String) -> Bool:
  match rows:
    case Nil{}: True{}
    case Con{+row, +rest}: J.is_object(row) && String.eq(key_type(path_field(row, path)), kind) && sort_valid(rest, path, kind)

def sort_precedes(+direction: String, +left: J.Json, +right: J.Json) -> Bool:
  match direction left right:
    case "asc" J.Number{+left} J.Number{+right}: numeric_equality(D.compare("<=", left, right))
    case "desc" J.Number{+left} J.Number{+right}: numeric_equality(D.compare(">=", left, right))
    case "asc" J.Text{+left} J.Text{+right}: String.is_le(left, right)
    case "desc" J.Text{+left} J.Text{+right}: String.is_ge(left, right)
    case _ _ _: False{}

def insert_row(+rows: +List<J.Json>, +row: J.Json, +path: String, +direction: String) -> +List<J.Json>:
  match rows:
    case Nil{}: row <> Nil{}
    case Con{+head, +rest}:
      choose((+List<J.Json>), sort_precedes(direction, path_field(row, path), path_field(head, path)),
        (_ => row <> head <> rest), (_ => head <> insert_row(rest, row, path, direction)))

def sort_rows(+rows: +List<J.Json>, +path: String, +direction: String) -> +List<J.Json>:
  match rows:
    case Nil{}: Nil{}
    case Con{+head, +rest}: insert_row(sort_rows(rest, path, direction), head, path, direction)

def sorted(+rows: +List<J.Json>, +path: String, +direction: String) -> Result<&2, &2, String, J.Json>:
  match rows:
    case Nil{}: Done{J.Array{Nil{}}}
    case Con{+head, +rest}:
      +kind = key_type(path_field(head, path))
      choose((Result<&2, &2, String, J.Json>), Bool.not(String.eq(kind, "invalid")) && sort_valid(head <> rest, path, kind),
        (_ => Done{J.Array{sort_rows(head <> rest, path, direction)}}),
        (_ => Fail{"sort requires homogeneous non-null numeric or string keys"}))

def text_value(+value: J.Json) -> Result<&2, &2, String, J.Json>:
  match value:
    case J.Null{}: Done{J.Text{""}}
    case J.Boolean{+boolean}: Done{J.Text{Bool.pick(String, boolean, "true", "false")}}
    case J.Number{+number}: text_result(D.parse(number))
    case J.Text{+text}: Done{J.Text{text}}
    case _: Fail{"text requires scalar value"}

def is_boolean(+value: J.Json) -> Bool:
  match value:
    case J.Boolean{+value}: True{}
    case _: False{}

def task_fact(+task: J.Json, +name: String) -> Result<&2, &2, String, J.Json>:
  match task:
    case J.Null{}: Done{J.Boolean{False{}}}
    case J.Object{+fields}:
      choose((Result<&2, &2, String, J.Json>), is_boolean(J.find(fields, "working")) && is_boolean(J.find(fields, "awaitingHuman")),
        (_ => Done{J.find(fields, name)}), (_ => Fail{"malformed task observation"}))
    case _: Fail{"malformed task observation"}

def small_read(+result: Maybe<&2, Nat>, +maximum: Nat) -> Maybe<&2, Nat>:
  match result:
    case Some{+number}: Bool.pick((Maybe<&2, Nat>), Nat.is_le(number, maximum), Some{number}, None{})
    case None{}: None{}

def nonnegative_small(+value: String, +maximum: Nat) -> Maybe<&2, Nat>:
  small_read(Nat.read(value), maximum)

def round_places(+number: String, +places: Maybe<&2, Nat>) -> Result<&2, &2, String, J.Json>:
  match places:
    case Some{+places}: number_result(D.round(number, places))
    case None{}: Fail{"round precision must be integral 0..6"}

def take_count(+items: +List<J.Json>, +count: Maybe<&2, Nat>) -> Result<&2, &2, String, J.Json>:
  match count:
    case Some{+count}: Done{J.Array{List.take(&2, J.Json, items, count)}}
    case None{}: Fail{"take count must be integral 0..4096"}

def absolute_number(+number: String) -> Result<&2, &2, String, J.Json>:
  match number:
    case SCon{'-', +rest}: Done{J.Number{rest}}
    case +rest: Done{J.Number{rest}}

def builtin(+name: String, +arguments: +List<J.Json>) -> Result<&2, &2, String, J.Json>:
  match name arguments:
    case "len" Con{J.Text{+text}, Nil{}}: Done{J.nat(String.length(text))}
    case "len" Con{J.Array{+items}, Nil{}}: Done{J.nat(List.length(&2, J.Json, items))}
    case "count" Con{J.Array{+items}, Nil{}}: Done{J.nat(List.length(&2, J.Json, items))}
    case "min" Con{J.Number{+left}, Con{J.Number{+right}, Nil{}}}:
      Done{J.Number{Bool.pick(String, numeric_equality(D.compare("<=", left, right)), left, right)}}
    case "max" Con{J.Number{+left}, Con{J.Number{+right}, Nil{}}}:
      Done{J.Number{Bool.pick(String, numeric_equality(D.compare(">=", left, right)), left, right)}}
    case "abs" Con{J.Number{+number}, Nil{}}: absolute_number(number)
    case "round" Con{J.Number{+number}, Con{J.Number{+places}, Nil{}}}: round_places(number, nonnegative_small(places, 6n))
    case "clamp" Con{J.Number{+number}, Con{J.Number{+lower}, Con{J.Number{+upper}, Nil{}}}}:
      choose((Result<&2, &2, String, J.Json>), numeric_equality(D.compare("<=", lower, upper)),
        (_ => Done{J.Number{Bool.pick(String, numeric_equality(D.compare("<", number, lower)), lower,
          Bool.pick(String, numeric_equality(D.compare(">", number, upper)), upper, number))}}),
        (_ => Fail{"clamp lower bound exceeds upper bound"}))
    case "sum" Con{J.Array{+rows}, Con{J.Text{+path}, Nil{}}}:
      choose((Result<&2, &2, String, J.Json>), path_valid(String.split(path, '.')) && records_only(rows),
        (_ => number_result(sum_rows(rows, path, Done{"0"}))), (_ => Fail{"sum requires records and field path"}))
    case "filter" Con{J.Array{+rows}, Con{J.Text{+path}, Con{+wanted, Nil{}}}}:
      choose((Result<&2, &2, String, J.Json>), path_valid(String.split(path, '.')) && records_only(rows) && scalar(wanted),
        (_ => Done{J.Array{filter_rows(rows, path, wanted)}}), (_ => Fail{"filter requires records, field path and scalar"}))
    case "sort" Con{J.Array{+rows}, Con{J.Text{+path}, Con{J.Text{+direction}, Nil{}}}}:
      choose((Result<&2, &2, String, J.Json>), path_valid(String.split(path, '.')) && (String.eq(direction, "asc") || String.eq(direction, "desc")),
        (_ => sorted(rows, path, direction)), (_ => Fail{"sort requires field path and asc/desc direction"}))
    case "take" Con{J.Array{+items}, Con{J.Number{+count}, Nil{}}}: take_count(items, nonnegative_small(count, 4096n))
    case "text" Con{+value, Nil{}}: text_value(value)
    case "format" Con{J.Number{+number}, Con{J.Text{+style}, Nil{}}}: text_result(D.format(number, style))
    case "working" Con{+task, Nil{}}: task_fact(task, "working")
    case "awaitingHuman" Con{+task, Nil{}}: task_fact(task, "awaitingHuman")
    case _ _: Fail{"unknown function or invalid function arguments"}

def canonical_number(+result: Result<&2, &2, String, String>, +number: String) -> Bool:
  match result:
    case Done{+canonical}: String.eq(canonical, number)
    case Fail{+error}: False{}

type Validation is Data:
  Validation{depth: Nat, value: J.Json}

type ValidationState is Data:
  ValidationState{pending: +List<Validation>, valid: Bool}

def validate_items(+items: +List<J.Json>, +depth: Nat, +tail: +List<Validation>) -> +List<Validation>:
  match items:
    case Nil{}: tail
    case Con{+value, +rest}: Validation{depth, value} <> validate_items(rest, depth, tail)

def validate_fields(+fields: +List<J.Field>, +depth: Nat, +tail: +List<Validation>) -> +List<Validation>:
  match fields:
    case Nil{}: tail
    case Con{J.Field{+name, +value}, +rest}: Validation{depth, value} <> validate_fields(rest, depth, tail)

def validation_step(+validation: Validation, +tail: +List<Validation>) -> ValidationState:
  match validation:
    case Validation{0n, +value}: ValidationState{tail, False{}}
    case Validation{1n+rest, J.Null{}}: ValidationState{tail, True{}}
    case Validation{1n+rest, J.Boolean{+value}}: ValidationState{tail, True{}}
    case Validation{1n+rest, J.Number{+number}}: ValidationState{tail, canonical_number(D.parse(number), number)}
    case Validation{1n+rest, J.Text{+text}}: ValidationState{tail, Nat.is_le(String.length(text), 16384n)}
    case Validation{1n+rest, J.Array{+items}}:
      ValidationState{validate_items(items, rest, tail), Nat.is_le(List.length(&2, J.Json, items), 4096n)}
    case Validation{1n+rest, J.Object{+fields}}:
      ValidationState{validate_fields(fields, rest, tail), Nat.is_le(List.length(&2, J.Field, fields), 64n)}

def validation_loop(+fuel: Nat, +state: ValidationState) -> Bool:
  match fuel state:
    case _ ValidationState{+pending, False{}}: False{}
    case _ ValidationState{Nil{}, True{}}: True{}
    case 0n _: False{}
    case 1n+rest ValidationState{Con{+head, +tail}, True{}}: validation_loop(rest, validation_step(head, tail))

def value_valid(+depth: Nat, +value: J.Json) -> Bool:
  validation_loop(100000n, ValidationState{Validation{depth, value} <> Nil{}, True{}})

def path_cost(+arguments: +List<J.Json>) -> Nat:
  match arguments:
    case Con{J.Text{+path}, +rest}: 1n+String.length(path)
    case _: 1n

def collection_cost(+arguments: +List<J.Json>, +name: String) -> Nat:
  match arguments:
    case Con{J.Array{+items}, +rest}:
      +length = List.length(&2, J.Json, items)
      +unit = path_cost(rest)
      Bool.pick(Nat, String.eq(name, "sort"), Nat.mul(unit, Nat.mul(1n+length, 1n+length)), Nat.mul(unit, Nat.mul(4n, 1n+length)))
    case _: 1n

type EvalTask is Data:
  Visit{expression: Expr, depth: Nat}
  ValidateValue{validation: ValidationState, value: J.Json}
  CompareValues{comparison: SameState, negated: Bool}
  ApplyUnary{operator: String}
  BinaryLeft{operator: String, right: Expr, depth: Nat}
  ApplyBinary{operator: String, left: J.Json}
  ConditionalSelect{yes: Expr, no: Expr, depth: Nat}
  AccessLeft{key: Expr, depth: Nat}
  ApplyAccess{left: J.Json}
  ItemsNext{kind: String, remaining: +List<Expr>, reversed: +List<J.Json>, depth: Nat}
  ItemsAppend{kind: String, remaining: +List<Expr>, reversed: +List<J.Json>, depth: Nat}
  FieldsNext{remaining: +List<ExprField>, reversed: +List<J.Field>, depth: Nat}
  FieldsAppend{name: String, remaining: +List<ExprField>, reversed: +List<J.Field>, depth: Nat}
  Spend{remaining: Nat, name: String, arguments: +List<J.Json>}

type EvalState is Data:
  EvalState{tasks: +List<EvalTask>, values: +List<J.Json>, error: String}

type Evaluation is Data:
  Evaluation{result: Result<&2, &2, String, J.Json>, remaining: Nat}

def eval_result(+result: Result<&2, &2, String, J.Json>, +tasks: +List<EvalTask>, +values: +List<J.Json>) -> EvalState:
  match result:
    case Fail{+error}: EvalState{tasks, values, error}
    case Done{+value}:
      EvalState{ValidateValue{ValidationState{Validation{33n, value} <> Nil{}, True{}}, value} <> tasks, values, ""}

def apply_binary(+operator: String, +left: J.Json, +right: J.Json, +tasks: +List<EvalTask>, +values: +List<J.Json>) -> EvalState:
  match operator:
    case "==": EvalState{CompareValues{SameState{Comparison{left, right} <> Nil{}, True{}}, False{}} <> tasks, values, ""}
    case "!=": EvalState{CompareValues{SameState{Comparison{left, right} <> Nil{}, True{}}, True{}} <> tasks, values, ""}
    case _: eval_result(binary(operator, left, right), tasks, values)

def validate_value(+validation: ValidationState, +value: J.Json, +tasks: +List<EvalTask>, +values: +List<J.Json>) -> EvalState:
  match validation:
    case ValidationState{pending, False{}}: EvalState{tasks, values, "value budget or type invalid"}
    case ValidationState{Nil{}, True{}}: EvalState{tasks, value <> values, ""}
    case ValidationState{Con{head, tail}, True{}}:
      EvalState{ValidateValue{validation_step(head, tail), value} <> tasks, values, ""}

def compare_values(+comparison: SameState, +negated: Bool, +tasks: +List<EvalTask>, +values: +List<J.Json>) -> EvalState:
  match comparison:
    case SameState{pending, False{}}: EvalState{tasks, J.Boolean{negated} <> values, ""}
    case SameState{Nil{}, True{}}: EvalState{tasks, J.Boolean{Bool.not(negated)} <> values, ""}
    case SameState{Con{head, tail}, True{}}:
      EvalState{CompareValues{same_step(head, tail), negated} <> tasks, values, ""}

def reference_result(+error: J.Json, +name: String, +env: +List<J.Field>) -> Result<&2, &2, String, J.Json>:
  match error:
    case J.Text{+reason}: Fail{"dependency error in " ++ name ++ ": " ++ reason}
    case _:
      choose((Result<&2, &2, String, J.Json>), has_field(env, name),
        (_ => Done{J.find(env, name)}), (_ => Fail{"unknown expression reference: " ++ name}))

def visit(+expression: Expr, +depth: Nat, +tasks: +List<EvalTask>, +values: +List<J.Json>, +env: +List<J.Field>) -> EvalState:
  match expression:
    case Literal{+value}: eval_result(Done{value}, tasks, values)
    case Reference{+name}: eval_result(reference_result(J.find(env, "@errors/" ++ name), name, env), tasks, values)
    case Unary{+operator, +argument}: EvalState{Visit{argument, depth} <> ApplyUnary{operator} <> tasks, values, ""}
    case Binary{+operator, +left, +right}: EvalState{Visit{left, depth} <> BinaryLeft{operator, right, depth} <> tasks, values, ""}
    case Conditional{+test, +yes, +no}: EvalState{Visit{test, depth} <> ConditionalSelect{yes, no, depth} <> tasks, values, ""}
    case Access{+value, +key}: EvalState{Visit{value, depth} <> AccessLeft{key, depth} <> tasks, values, ""}
    case Array{+items}: EvalState{ItemsNext{"", items, Nil{}, depth} <> tasks, values, ""}
    case Record{+fields}: EvalState{FieldsNext{fields, Nil{}, depth} <> tasks, values, ""}
    case Call{+name, +arguments}: EvalState{ItemsNext{name, arguments, Nil{}, depth} <> tasks, values, ""}

def binary_left(+op: String, +left: J.Json, +right: Expr, +depth: Nat, +tasks: +List<EvalTask>, +values: +List<J.Json>) -> EvalState:
  match op left:
    case "&&" J.Boolean{False{}}: EvalState{tasks, J.Boolean{False{}} <> values, ""}
    case "||" J.Boolean{True{}}: EvalState{tasks, J.Boolean{True{}} <> values, ""}
    case "&&" J.Boolean{True{}}: EvalState{Visit{right, depth} <> ApplyBinary{"&&", J.Boolean{True{}}} <> tasks, values, ""}
    case "||" J.Boolean{False{}}: EvalState{Visit{right, depth} <> ApplyBinary{"||", J.Boolean{False{}}} <> tasks, values, ""}
    case "&&" _: EvalState{tasks, values, "Boolean operand required"}
    case "||" _: EvalState{tasks, values, "Boolean operand required"}
    case +op +left: EvalState{Visit{right, depth} <> ApplyBinary{op, left} <> tasks, values, ""}

def eval_step(+state: EvalState, +env: +List<J.Field>) -> EvalState:
  match state:
    case EvalState{Con{Visit{+expression, 0n}, +tasks}, +values, +error}: EvalState{tasks, values, "evaluation depth exceeded"}
    case EvalState{Con{Visit{+expression, 1n+depth}, +tasks}, +values, +error}: visit(expression, depth, tasks, values, env)
    case EvalState{Con{ValidateValue{validation, value}, tasks}, values, error}: validate_value(validation, value, tasks, values)
    case EvalState{Con{CompareValues{comparison, negated}, tasks}, values, error}: compare_values(comparison, negated, tasks, values)
    case EvalState{Con{ApplyUnary{+operator}, +tasks}, Con{+value, +values}, +error}: eval_result(unary(operator, value), tasks, values)
    case EvalState{Con{BinaryLeft{+operator, +right, +depth}, +tasks}, Con{+left, +values}, +error}: binary_left(operator, left, right, depth, tasks, values)
    case EvalState{Con{ApplyBinary{+operator, +left}, +tasks}, Con{+right, +values}, +error}: apply_binary(operator, left, right, tasks, values)
    case EvalState{Con{ConditionalSelect{+yes, +no, +depth}, +tasks}, Con{J.Boolean{+condition}, +values}, +error}:
      EvalState{Visit{Bool.pick(Expr, condition, yes, no), depth} <> tasks, values, ""}
    case EvalState{Con{AccessLeft{+key, +depth}, +tasks}, Con{+left, +values}, +error}: EvalState{Visit{key, depth} <> ApplyAccess{left} <> tasks, values, ""}
    case EvalState{Con{ApplyAccess{+left}, +tasks}, Con{+key, +values}, +error}: eval_result(access(left, key), tasks, values)
    case EvalState{Con{ItemsNext{"", Nil{}, +reversed, +depth}, +tasks}, +values, +error}:
      eval_result(Done{J.Array{List.reverse(&2, J.Json, reversed)}}, tasks, values)
    case EvalState{Con{ItemsNext{+kind, Nil{}, +reversed, +depth}, +tasks}, +values, +error}:
      +arguments = List.reverse(&2, J.Json, reversed)
      EvalState{Spend{collection_cost(arguments, kind), kind, arguments} <> tasks, values, ""}
    case EvalState{Con{ItemsNext{+kind, Con{+head, +remaining}, +reversed, +depth}, +tasks}, +values, +error}:
      EvalState{Visit{head, depth} <> ItemsAppend{kind, remaining, reversed, depth} <> tasks, values, ""}
    case EvalState{Con{ItemsAppend{+kind, +remaining, +reversed, +depth}, +tasks}, Con{+value, +values}, +error}:
      EvalState{ItemsNext{kind, remaining, value <> reversed, depth} <> tasks, values, ""}
    case EvalState{Con{FieldsNext{Nil{}, +reversed, +depth}, +tasks}, +values, +error}:
      eval_result(Done{J.Object{List.reverse(&2, J.Field, reversed)}}, tasks, values)
    case EvalState{Con{FieldsNext{Con{ExprField{+name, +expression}, +remaining}, +reversed, +depth}, +tasks}, +values, +error}:
      EvalState{Visit{expression, depth} <> FieldsAppend{name, remaining, reversed, depth} <> tasks, values, ""}
    case EvalState{Con{FieldsAppend{+name, +remaining, +reversed, +depth}, +tasks}, Con{+value, +values}, +error}:
      EvalState{FieldsNext{remaining, J.Field{name, value} <> reversed, depth} <> tasks, values, ""}
    case EvalState{Con{Spend{0n, +name, +arguments}, +tasks}, +values, +error}: eval_result(builtin(name, arguments), tasks, values)
    case EvalState{Con{Spend{1n+remaining, +name, +arguments}, +tasks}, +values, +error}: EvalState{Spend{remaining, name, arguments} <> tasks, values, ""}
    case EvalState{+tasks, +values, +error}: EvalState{tasks, values, "invalid expression evaluation state"}

def eval_error(+state: EvalState) -> String:
  match state:
    case EvalState{+tasks, +values, +error}: error

def eval_loop(+fuel: Nat, +state: EvalState, +env: +List<J.Field>) -> Evaluation:
  match fuel state:
    case +fuel EvalState{Nil{}, Con{+value, Nil{}}, ""}: Evaluation{Done{value}, fuel}
    case 0n _: Evaluation{Fail{"evaluation budget exceeded"}, 0n}
    case 1n+remaining +state:
      choose(Evaluation, String.eq(eval_error(state), ""),
        (_ => eval_loop(remaining, eval_step(state, env), env)),
        (_ => Evaluation{Fail{eval_error(state)}, remaining}))

def evaluate_bounded(+expression: Expr, +env: +List<J.Field>, +fuel: Nat) -> Evaluation:
  eval_loop(fuel, EvalState{Visit{expression, 33n} <> Nil{}, Nil{}, ""}, env)

def evaluation_result(+evaluation: Evaluation) -> Result<&2, &2, String, J.Json>:
  match evaluation:
    case Evaluation{+result, +remaining}: result

def evaluate(+expression: Expr, +env: +List<J.Field>) -> Result<&2, &2, String, J.Json>:
  evaluation_result(evaluate_bounded(expression, env, 100000n))
