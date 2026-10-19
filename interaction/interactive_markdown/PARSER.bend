import Base
import ./TYPES.bend as T

type Cut is Data:
  Waiting{}
  Token{text: String, rest: String}
  Broken{message: String}

type Lex is Data:
  Lexing{acc: String, depth: Nat, quoted: Bool, escaped: Bool}
  Lexed{text: String}
  LexFailed{reason: String}

type Parsed is Data:
  TagStart{tag: String, attributes: +List<T.Attribute>, leaf: Bool}
  TagClose{tag: String}
  TagInvalid{message: String}

type TagMachine is Data:
  TagMachine{phase: Nat, closing: Bool, tag: String, name: String,
    value: String, attrs: +List<T.Attribute>, depth: Nat, quoted: Bool,
    escaped: Bool, leaf: Bool, error: String}

def space(+c: Char) -> Bool:
  match c:
    case ' ': True{}
    case '\t': True{}
    case '\n': True{}
    case '\r': True{}
    case _: False{}

def trim_start(+text: String) -> String:
  String.trim_start(text)

def name_char(+c: Char) -> Bool:
  match c:
    case Chr{+code}:
      (U32.is_le(65, code) && U32.is_le(code, 90)) ||
      (U32.is_le(97, code) && U32.is_le(code, 122)) ||
      (U32.is_le(48, code) && U32.is_le(code, 57)) || U32.is_eq(code, 45) || U32.is_eq(code, 95)

def initial() -> T.Syntax:
  T.Syntax{Nil{}, Nil{}, "", False{}, False{}, 0n, 0n, ""}

def fail(+reason: String, +syntax: T.Syntax) -> T.Syntax:
  T.Syntax{ +roots, +frames, +tail, +failed, +sealed, +accepted, +characters, +diagnostic} = syntax
  T.Syntax{roots, frames, tail, True{}, sealed, accepted, characters, reason}

def lex_brace(+depth: Nat, +acc: String) -> Lex:
  match depth:
    case 0n: LexFailed{"Unexpected expression closing brace"}
    case 1n+d: Lexing{acc ++ "}", d, False{}, False{}}

def lex_greater(+depth: Nat, +acc: String) -> Lex:
  match depth:
    case 0n: Lexed{acc ++ ">"}
    case _: Lexing{acc ++ ">", depth, False{}, False{}}

def lex_character(+quoted: Bool, +escaped: Bool, +c: Char, +acc: String, +depth: Nat) -> Lex:
  match quoted escaped c:
    case True{} True{} _: Lexing{acc ++ SCon{c, SNil{}}, depth, True{}, False{}}
    case True{} False{} '\\': Lexing{acc ++ "\\", depth, True{}, True{}}
    case True{} False{} '"': Lexing{acc ++ "\"", depth, False{}, False{}}
    case True{} False{} _: Lexing{acc ++ SCon{c, SNil{}}, depth, True{}, False{}}
    case False{} _ '"': Lexing{acc ++ "\"", depth, True{}, False{}}
    case False{} _ '{': Lexing{acc ++ "{", 1n+depth, False{}, False{}}
    case False{} _ '}': lex_brace(depth, acc)
    case False{} _ '>': lex_greater(depth, acc)
    case False{} _ _: Lexing{acc ++ SCon{c, SNil{}}, depth, False{}, False{}}

def lex_step(+lex: Lex, +c: Char) -> Lex:
  match lex:
    case Lexing{acc, depth, quoted, escaped}: lex_character(quoted, escaped, c, acc, depth)
    case _: lex

def cut_scan(+budget: Nat, +text: String, +lex: Lex) -> Cut:
  match budget text lex:
    case _ _ Lexed{value}: Token{value, text}
    case _ _ LexFailed{reason}: Broken{reason}
    case 0n _ _: Broken{"A tag or expression exceeds 8192 characters"}
    case _ SNil{} _: Waiting{}
    case 1n+b SCon{c, rest} Lexing{acc, depth, quoted, escaped}:
      cut_scan(b, rest, lex_step(Lexing{acc, depth, quoted, escaped}, c))

def cut_trimmed(+text: String) -> Cut:
  match text:
    case SNil{}: Waiting{}
    case SCon{'<', rest}: cut_scan(8192n, rest, Lexing{"<", 0n, False{}, False{}})
    case _: Broken{"Only component tags are allowed inside selvedge-ui"}

def cut(+text: String) -> Cut:
  cut_trimmed(trim_start(text))

def contains(+attrs: +List<T.Attribute>, +name: String) -> Bool:
  match attrs:
    case Nil{}: False{}
    case Con{T.Attribute{key, source}, rest}: String.eq(name, key) || contains(rest, name)

def tag_error(+machine: TagMachine, +error: String) -> TagMachine:
  TagMachine{ +phase, +closing, +tag, +name, +value, +attrs, +depth, +quoted, +escaped, +leaf, +old} = machine
  TagMachine{99n, closing, tag, name, value, attrs, depth, quoted, escaped, leaf, error}

def tag_phase(+machine: TagMachine, +phase: Nat) -> TagMachine:
  TagMachine{ +old, +closing, +tag, +name, +value, +attrs, +depth, +quoted, +escaped, +leaf, +error} = machine
  TagMachine{phase, closing, tag, name, value, attrs, depth, quoted, escaped, leaf, error}

def tag_finish(+machine: TagMachine, +leaf: Bool) -> TagMachine:
  TagMachine{ +phase, +closing, +tag, +name, +value, +attrs, +depth, +quoted, +escaped, +old, +error} = machine
  TagMachine{9n, closing, tag, name, value, attrs, depth, quoted, escaped, leaf, error}

def tag_append(+machine: TagMachine, +target: Nat, +c: Char, +allowed: Bool) -> TagMachine:
  TagMachine{ +phase, +closing, +tag, +name, +value, +attrs, +depth, +quoted, +escaped, +leaf, +error} = machine
  match target allowed:
    case _ False{}: TagMachine{99n, closing, tag, name, value, attrs, depth, quoted, escaped, leaf, "Invalid tag or attribute name"}
    case 2n True{}: TagMachine{2n, closing, tag ++ SCon{c, SNil{}}, name, value, attrs, depth, quoted, escaped, leaf, error}
    case _ True{}: TagMachine{4n, closing, tag, name ++ SCon{c, SNil{}}, value, attrs, depth, quoted, escaped, leaf, error}

def tag_begin(+machine: TagMachine, +c: Char) -> TagMachine:
  TagMachine{ +phase, +closing, +tag, +name, +value, +attrs, +depth, +quoted, +escaped, +leaf, +error} = machine
  match c:
    case '/': TagMachine{1n, True{}, tag, name, value, attrs, depth, quoted, escaped, leaf, error}
    case _: tag_append(TagMachine{phase, closing, tag, name, value, attrs, depth, quoted, escaped, leaf, error}, 2n, c, name_char(c))

def tag_after_name(+machine: TagMachine, +c: Char, +whitespace: Bool) -> TagMachine:
  match c whitespace:
    case '>' _: tag_finish(machine, False{})
    case '/' _: tag_phase(machine, 8n)
    case _ True{}: tag_phase(machine, 3n)
    case _ False{}: tag_append(machine, 2n, c, name_char(c))

def tag_new_attribute(+machine: TagMachine, +c: Char, +whitespace: Bool) -> TagMachine:
  TagMachine{ +phase, +closing, +tag, +name, +value, +attrs, +depth, +quoted, +escaped, +leaf, +error} = machine
  match closing c whitespace:
    case _ '>' _: tag_finish(TagMachine{phase, closing, tag, name, value, attrs, depth, quoted, escaped, leaf, error}, False{})
    case _ _ True{}: TagMachine{phase, closing, tag, name, value, attrs, depth, quoted, escaped, leaf, error}
    case False{} '/' _: TagMachine{8n, closing, tag, name, value, attrs, depth, quoted, escaped, leaf, error}
    case False{} _ False{}: tag_append(TagMachine{phase, closing, tag, "", "", attrs, depth, quoted, escaped, leaf, error}, 4n, c, name_char(c))
    case True{} _ _: tag_error(TagMachine{phase, closing, tag, name, value, attrs, depth, quoted, escaped, leaf, error}, "Closing tags cannot have attributes")

def tag_attribute_name(+machine: TagMachine, +c: Char, +whitespace: Bool) -> TagMachine:
  match c whitespace:
    case '=' _: tag_phase(machine, 5n)
    case _ True{}: tag_phase(machine, 40n)
    case _ False{}: tag_append(machine, 4n, c, name_char(c))

def tag_value_start(+machine: TagMachine, +c: Char, +whitespace: Bool) -> TagMachine:
  TagMachine{ +phase, +closing, +tag, +name, +value, +attrs, +depth, +quoted, +escaped, +leaf, +error} = machine
  match c whitespace:
    case _ True{}: TagMachine{phase, closing, tag, name, value, attrs, depth, quoted, escaped, leaf, error}
    case '"' False{}: TagMachine{6n, closing, tag, name, "\"", attrs, 0n, True{}, False{}, leaf, error}
    case '{' False{}: TagMachine{7n, closing, tag, name, "", attrs, 0n, False{}, False{}, leaf, error}
    case _ _: tag_error(TagMachine{phase, closing, tag, name, value, attrs, depth, quoted, escaped, leaf, error}, "Attribute values require quoted strings or {expressions}")

def tag_save(+machine: TagMachine, +source: String, +duplicate: Bool) -> TagMachine:
  TagMachine{ +phase, +closing, +tag, +name, +value, +attrs, +depth, +quoted, +escaped, +leaf, +error} = machine
  match duplicate:
    case True{}: tag_error(TagMachine{phase, closing, tag, name, value, attrs, depth, quoted, escaped, leaf, error}, "Duplicate attribute")
    case False{}: TagMachine{3n, closing, tag, "", "", T.Attribute{name, source} <> attrs, 0n, False{}, False{}, leaf, error}

def tag_string(+machine: TagMachine, +escaped: Bool, +c: Char) -> TagMachine:
  TagMachine{ +phase, +closing, +tag, +name, +value, +attrs, +depth, +quoted, +old, +leaf, +error} = machine
  match escaped c:
    case False{} '"': tag_save(TagMachine{phase, closing, tag, name, value, attrs, depth, quoted, old, leaf, error}, value ++ "\"", contains(attrs, name))
    case False{} '\\': TagMachine{phase, closing, tag, name, value ++ "\\", attrs, depth, quoted, True{}, leaf, error}
    case _ _: TagMachine{phase, closing, tag, name, value ++ SCon{c, SNil{}}, attrs, depth, quoted, False{}, leaf, error}

def tag_expression_quoted(+machine: TagMachine, +quoted: Bool, +escaped: Bool, +c: Char) -> TagMachine:
  TagMachine{ +phase, +closing, +tag, +name, +value, +attrs, +depth, +old_quoted, +old_escaped, +leaf, +error} = machine
  match quoted escaped c:
    case True{} False{} '"': TagMachine{phase, closing, tag, name, value ++ "\"", attrs, depth, False{}, False{}, leaf, error}
    case True{} False{} '\\': TagMachine{phase, closing, tag, name, value ++ "\\", attrs, depth, True{}, True{}, leaf, error}
    case True{} _ _: TagMachine{phase, closing, tag, name, value ++ SCon{c, SNil{}}, attrs, depth, True{}, False{}, leaf, error}
    case False{} _ '"': TagMachine{phase, closing, tag, name, value ++ "\"", attrs, depth, True{}, False{}, leaf, error}
    case False{} _ '{': TagMachine{phase, closing, tag, name, value ++ "{", attrs, 1n+depth, False{}, False{}, leaf, error}
    case False{} _ _: TagMachine{phase, closing, tag, name, value ++ SCon{c, SNil{}}, attrs, depth, False{}, False{}, leaf, error}

def tag_expression_brace(+machine: TagMachine, +depth: Nat) -> TagMachine:
  TagMachine{ +phase, +closing, +tag, +name, +value, +attrs, +old_depth, +quoted, +escaped, +leaf, +error} = machine
  match depth:
    case 0n: tag_save(TagMachine{phase, closing, tag, name, value, attrs, old_depth, quoted, escaped, leaf, error}, value, contains(attrs, name))
    case 1n+d: TagMachine{phase, closing, tag, name, value ++ "}", attrs, d, False{}, False{}, leaf, error}

def tag_expression(+machine: TagMachine, +quoted: Bool, +c: Char) -> TagMachine:
  TagMachine{ +phase, +closing, +tag, +name, +value, +attrs, +depth, +old_quoted, +escaped, +leaf, +error} = machine
  match quoted c:
    case False{} '}': tag_expression_brace(TagMachine{phase, closing, tag, name, value, attrs, depth, old_quoted, escaped, leaf, error}, depth)
    case _ _: tag_expression_quoted(TagMachine{phase, closing, tag, name, value, attrs, depth, old_quoted, escaped, leaf, error}, quoted, escaped, c)

def tag_equals(+machine: TagMachine, +c: Char, +whitespace: Bool) -> TagMachine:
  match c whitespace:
    case '=' _: tag_phase(machine, 5n)
    case _ True{}: machine
    case _ False{}: tag_error(machine, "Expected = after attribute name")

def tag_slash(+machine: TagMachine, +c: Char) -> TagMachine:
  match c:
    case '>': tag_finish(machine, True{})
    case _: tag_error(machine, "Expected > after /")

def tag_dispatch(+machine: TagMachine, +phase: Nat, +c: Char) -> TagMachine:
  TagMachine{ +old_phase, +closing, +tag, +name, +value, +attrs, +depth, +quoted, +escaped, +leaf, +error} = machine
  match phase:
    case 1n: tag_begin(TagMachine{old_phase, closing, tag, name, value, attrs, depth, quoted, escaped, leaf, error}, c)
    case 2n: tag_after_name(TagMachine{old_phase, closing, tag, name, value, attrs, depth, quoted, escaped, leaf, error}, c, space(c))
    case 3n: tag_new_attribute(TagMachine{old_phase, closing, tag, name, value, attrs, depth, quoted, escaped, leaf, error}, c, space(c))
    case 4n: tag_attribute_name(TagMachine{old_phase, closing, tag, name, value, attrs, depth, quoted, escaped, leaf, error}, c, space(c))
    case 5n: tag_value_start(TagMachine{old_phase, closing, tag, name, value, attrs, depth, quoted, escaped, leaf, error}, c, space(c))
    case 6n: tag_string(TagMachine{old_phase, closing, tag, name, value, attrs, depth, quoted, escaped, leaf, error}, escaped, c)
    case 7n: tag_expression(TagMachine{old_phase, closing, tag, name, value, attrs, depth, quoted, escaped, leaf, error}, quoted, c)
    case 8n: tag_slash(TagMachine{old_phase, closing, tag, name, value, attrs, depth, quoted, escaped, leaf, error}, c)
    case 40n: tag_equals(TagMachine{old_phase, closing, tag, name, value, attrs, depth, quoted, escaped, leaf, error}, c, space(c))
    case _: tag_error(TagMachine{old_phase, closing, tag, name, value, attrs, depth, quoted, escaped, leaf, error}, "Invalid characters after tag")

def tag_step(+machine: TagMachine, +c: Char) -> TagMachine:
  TagMachine{ +phase, +closing, +tag, +name, +value, +attrs, +depth, +quoted, +escaped, +leaf, +error} = machine
  tag_dispatch(machine, phase, c)

def tag_fold(+text: String, +machine: TagMachine) -> TagMachine:
  match text:
    case SNil{}: machine
    case SCon{c, rest}: tag_fold(rest, tag_step(machine, c))

def tag_result(+machine: TagMachine) -> Parsed:
  TagMachine{ +phase, +closing, +tag, +name, +value, +attrs, +depth, +quoted, +escaped, +leaf, +error} = machine
  match phase closing:
    case 9n True{}: TagClose{tag}
    case 9n False{}: TagStart{tag, List.reverse(&2, T.Attribute, attrs), leaf}
    case _ _: TagInvalid{Bool.pick(String, String.is_empty(error), "Invalid component tag", error)}

def parse(+text: String) -> Parsed:
  match text:
    case SCon{'<', rest}: tag_result(tag_fold(rest, TagMachine{1n, False{}, "", "", "", Nil{}, 0n, False{}, False{}, False{}, ""}))
    case _: TagInvalid{"Expected component tag"}

def append_element(+element: T.Element, +roots: +List<T.Element>, +frames: +List<T.Frame>, +tail: String, +sealed: Bool, +accepted: Nat, +characters: Nat) -> T.Syntax:
  match frames:
    case Nil{}: T.Syntax{element <> roots, Nil{}, tail, False{}, sealed, accepted, characters, ""}
    case Con{T.Frame{tag, attrs, children}, rest}:
      T.Syntax{roots, T.Frame{tag, attrs, element <> children} <> rest, tail, False{}, sealed, accepted, characters, ""}

def closed_match(+same: Bool, +current: String, +attrs: +List<T.Attribute>, +children: +List<T.Element>, +rest: +List<T.Frame>, +roots: +List<T.Element>, +tail: String, +sealed: Bool, +accepted: Nat, +characters: Nat) -> T.Syntax:
  match same:
    case False{}: fail("Mismatched component closing tag", T.Syntax{roots, T.Frame{current, attrs, children} <> rest, tail, False{}, sealed, accepted, characters, ""})
    case True{}: append_element(T.Element{current, attrs, List.reverse(&2, T.Element, children), True{}}, roots, rest, tail, sealed, accepted, characters)

def close_frame(+tag: String, +syntax: T.Syntax) -> T.Syntax:
  T.Syntax{ +roots, +frames, +tail, +failed, +sealed, +accepted, +characters, +diagnostic} = syntax
  match frames:
    case Nil{}: fail("Closing component has no matching start", T.Syntax{roots, frames, tail, failed, sealed, accepted, characters, diagnostic})
    case Con{T.Frame{+current, attrs, children}, rest}:
      closed_match(String.eq(tag, current), current, attrs, children, rest, roots, tail, sealed, accepted, characters)

def open_frame(+syntax: T.Syntax, +allowed: Bool, +tag: String, +attrs: +List<T.Attribute>) -> T.Syntax:
  T.Syntax{ +roots, +frames, +tail, +failed, +sealed, +accepted, +characters, +diagnostic} = syntax
  match allowed:
    case False{}: fail("Component nesting exceeds 32", T.Syntax{roots, frames, tail, failed, sealed, accepted, characters, diagnostic})
    case True{}: T.Syntax{roots, T.Frame{tag, attrs, Nil{}} <> frames, tail, False{}, sealed, 1n+accepted, characters, ""}

def accept_unbounded(+syntax: T.Syntax, +parsed: Parsed) -> T.Syntax:
  T.Syntax{ +roots, +frames, +tail, +failed, +sealed, +accepted, +characters, +diagnostic} = syntax
  match parsed:
    case TagInvalid{reason}: fail(reason, T.Syntax{roots, frames, tail, failed, sealed, accepted, characters, diagnostic})
    case TagClose{tag}: close_frame(tag, T.Syntax{roots, frames, tail, failed, sealed, accepted, characters, diagnostic})
    case TagStart{tag, attrs, True{}}:
      append_element(T.Element{tag, attrs, Nil{}, True{}}, roots, frames, tail, sealed, 1n+accepted, characters)
    case TagStart{tag, attrs, False{}}:
      open_frame(T.Syntax{roots, frames, tail, failed, sealed, accepted, characters, diagnostic}, Nat.is_lt(List.length(&2, T.Frame, frames), 32n), tag, attrs)

def accepted_count(syntax: T.Syntax) -> Nat:
  T.Syntax{roots, frames, tail, failed, sealed, accepted, characters, diagnostic} = syntax
  accepted

def accept_admitted(syntax: T.Syntax, parsed: Parsed, allowed: Bool) -> T.Syntax:
  match allowed:
    case True{}: accept_unbounded(syntax, parsed)
    case False{}: fail("Component count exceeds 1024", syntax)

def root_start_allowed(syntax: T.Syntax, tag: String) -> Bool:
  T.Syntax{roots, frames, tail, failed, sealed, accepted, characters, diagnostic} = syntax
  match roots frames:
    case Nil{} Nil{}: String.eq(tag, "ui")
    case _ Nil{}: False{}
    case _ _: Bool.not(String.eq(tag, "ui"))

def accept_root(+syntax: T.Syntax, +tag: String, +attrs: +List<T.Attribute>, +leaf: Bool, +allowed: Bool) -> T.Syntax:
  match allowed:
    case True{}: accept_admitted(syntax, TagStart{tag, attrs, leaf}, Nat.is_lt(accepted_count(syntax), 1024n))
    case False{}: fail("Exactly one ui root is allowed", syntax)

def accept(+syntax: T.Syntax, parsed: Parsed) -> T.Syntax:
  match parsed:
    case TagStart{+tag, attrs, leaf}: accept_root(syntax, tag, attrs, leaf, root_start_allowed(syntax, tag))
    case other: accept_unbounded(syntax, other)

def consume(+syntax: T.Syntax, +result: Cut) -> T.Syntax:
  T.Syntax{ +roots, +frames, +tail, +failed, +sealed, +accepted, +characters, +diagnostic} = syntax
  match result:
    case Waiting{}: T.Syntax{roots, frames, tail, failed, sealed, accepted, characters, diagnostic}
    case Broken{reason}: fail(reason, T.Syntax{roots, frames, tail, failed, sealed, accepted, characters, diagnostic})
    case Token{text, rest}: accept(T.Syntax{roots, frames, rest, failed, sealed, accepted, characters, diagnostic}, parse(text))

def one_step(+syntax: T.Syntax) -> T.Syntax:
  T.Syntax{ +roots, +frames, +tail, +failed, +sealed, +accepted, +characters, +diagnostic} = syntax
  consume(T.Syntax{roots, frames, tail, failed, sealed, accepted, characters, diagnostic}, cut(tail))

def pending_cut(+failed: Bool, +result: Cut) -> Bool:
  match failed result:
    case False{} Token{text, rest}: True{}
    case False{} Broken{reason}: True{}
    case _ _: False{}

def pending(+syntax: T.Syntax) -> Bool:
  T.Syntax{roots, frames, tail, failed, sealed, accepted, characters, diagnostic} = syntax
  pending_cut(failed, cut(tail))

def drain(+fuel: Nat, +ready: Bool, +syntax: T.Syntax) -> T.Syntax:
  match fuel ready:
    case 0n _: syntax
    case _ False{}: syntax
    case 1n+f True{}:
      +next = one_step(syntax)
      drain(f, pending(next), next)

# DEFENSE: Streaming authored code can exceed the token/source limits; retain the accepted syntax and report the bounded parser failure.
def append_admitted(+syntax: T.Syntax, +allowed: Bool, +text: String, +count: Nat) -> T.Syntax:
  T.Syntax{ +roots, +frames, +tail, +failed, +sealed, +accepted, +characters, +diagnostic} = syntax
  match failed allowed:
    case True{} _: T.Syntax{roots, frames, tail, failed, sealed, accepted, characters, diagnostic}
    case False{} False{}: fail("Interactive source or component count exceeds its limit", T.Syntax{roots, frames, tail, failed, sealed, accepted, characters, diagnostic})
    case False{} True{}: drain(256n, True{}, T.Syntax{roots, frames, tail ++ text, failed, sealed, accepted, count, diagnostic})

def append(+text: String, +syntax: T.Syntax) -> T.Syntax:
  T.Syntax{ +roots, +frames, +tail, +failed, +sealed, +accepted, +characters, +diagnostic} = syntax
  +count = (characters + String.length(text) : Nat)
  append_admitted(syntax, Nat.is_le(count, 131072n) && Nat.is_lt(accepted, 1024n), text, count)


def finish_admitted(+syntax: T.Syntax, +incomplete: Bool) -> T.Syntax:
  T.Syntax{ +roots, +frames, +tail, +failed, +sealed, +accepted, +characters, +diagnostic} = syntax
  match incomplete:
    case True{}: fail("The interactive block ended before its definition was complete", T.Syntax{roots, frames, tail, failed, True{}, accepted, characters, diagnostic})
    case False{}: T.Syntax{roots, frames, tail, failed, True{}, accepted, characters, diagnostic}

def finish(+syntax: T.Syntax) -> T.Syntax:
  T.Syntax{ +roots, +frames, +tail, +failed, +sealed, +accepted, +characters, +diagnostic} = syntax
  match failed:
    case True{}: T.Syntax{roots, frames, tail, failed, True{}, accepted, characters, diagnostic}
    case False{}: finish_admitted(syntax, Bool.not(String.is_empty(trim_start(tail))) || Bool.not(List.is_empty(&2, T.Frame, frames)))

def partial(+frames: +List<T.Frame>, +child: Maybe<&2, T.Element>) -> Maybe<&2, T.Element>:
  match frames child:
    case Nil{} item: item
    case Con{T.Frame{tag, attrs, children}, rest} None{}:
      partial(rest, Some{T.Element{tag, attrs, List.reverse(&2, T.Element, children), False{}}})
    case Con{T.Frame{tag, attrs, children}, rest} Some{node}:
      partial(rest, Some{T.Element{tag, attrs, List.reverse(&2, T.Element, node <> children), False{}}})

def elements_partial(+item: Maybe<&2, T.Element>, +roots: +List<T.Element>) -> +List<T.Element>:
  match item:
    case None{}: List.reverse(&2, T.Element, roots)
    case Some{node}: List.reverse(&2, T.Element, node <> roots)

def elements(+syntax: T.Syntax) -> +List<T.Element>:
  T.Syntax{ +roots, +frames, +tail, +failed, +sealed, +accepted, +characters, +diagnostic} = syntax
  elements_partial(partial(frames, None{}), roots)

def trim_info_start(info: String) -> String:
  match info:
    case SCon{' ', rest}: trim_info_start(rest)
    case SCon{'\t', rest}: trim_info_start(rest)
    case other: other

def trim_info(info: String) -> String:
  String.reverse(trim_info_start(String.reverse(trim_info_start(info))))

def eligible_fence(+interactive: Bool, +kind: String, +info: String, +complete: Bool) -> Bool:
  interactive && complete && String.eq(kind, "fenced") && String.eq(trim_info(info), "selvedge-ui")
