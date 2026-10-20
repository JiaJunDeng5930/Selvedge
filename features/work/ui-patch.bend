import Base

# A Work owns one virtual file. Context is exact and hunks consume source in
# order, so a rejected hunk cannot leave a partially updated document behind.
type Hunk is Data:
  Hunk{before: +List<String>, after: +List<String>}

type Patch is Data:
  Add{lines: +List<String>}
  Update{hunks: +List<Hunk>}
  Delete{}

def invalid() -> String:
  "Use one Add, Update or Delete File operation for work-ui.dsl inside *** Begin Patch and *** End Patch; update hunks start with @@ and use exact context, - and + lines."

def strip_cr_checked(ends: Bool, +line: String) -> String:
  match ends:
    case False{}: line
    case True{}: String.take(line, Nat.sub(String.length(line), 1n))

def strip_cr(+line: String) -> String:
  strip_cr_checked(String.ends_with(line, "\r"), line)

# Model patches may contain tens of thousands of characters. Keep line
# splitting and traversal tail recursive instead of using Base's recursive split.
def lines_acc(text: String, reversed: String, accumulator: +List<String>) -> +List<String>:
  match text:
    case SNil{}: List.reverse(&2, String, String.reverse(reversed) <> accumulator)
    case SCon{'\n', rest}: lines_acc(rest, "", String.reverse(reversed) <> accumulator)
    case SCon{char, rest}: lines_acc(rest, SCon{char, reversed}, accumulator)

def lines(text: String) -> +List<String>:
  lines_acc(text, "", Nil{})

def clean_lines_acc(lines: +List<String>, accumulator: +List<String>) -> +List<String>:
  match lines:
    case Nil{}: List.reverse(&2, String, accumulator)
    case Con{+line, rest}: clean_lines_acc(rest, strip_cr(line) <> accumulator)

def clean_lines(lines: +List<String>) -> +List<String>:
  clean_lines_acc(lines, Nil{})

def finished(lines: +List<String>) -> Bool:
  match lines:
    case Nil{}: True{}
    case Con{"", rest}: finished(rest)
    case _: False{}

def ending(accepted: Bool, patch: Patch) -> Result<&2, &2, String, Patch>:
  match accepted:
    case False{}: Fail{invalid()}
    case True{}: Done{patch}

def added(lines: +List<String>, accumulator: +List<String>) -> Result<&2, &2, String, Patch>:
  match lines:
    case Con{"*** End Patch", rest}: ending(finished(rest), Add{List.reverse(&2, String, accumulator)})
    case Con{SCon{'+', line}, rest}: added(rest, line <> accumulator)
    case _: Fail{invalid()}

def finish_hunk(before: +List<String>, after: +List<String>, hunks: +List<Hunk>) -> +List<Hunk>:
  Hunk{List.reverse(&2, String, before), List.reverse(&2, String, after)} <> hunks

def update_lines(lines: +List<String>, before: +List<String>, after: +List<String>, hunks: +List<Hunk>) -> Result<&2, &2, String, Patch>:
  match lines:
    case Con{"*** End Patch", rest}:
      ending(finished(rest), Update{List.reverse(&2, Hunk, finish_hunk(before, after, hunks))})
    case Con{"@@", rest}: update_lines(rest, Nil{}, Nil{}, finish_hunk(before, after, hunks))
    case Con{SCon{'@', SCon{'@', SCon{' ', header}}}, rest}:
      update_lines(rest, Nil{}, Nil{}, finish_hunk(before, after, hunks))
    case Con{SCon{' ', +line}, rest}: update_lines(rest, line <> before, line <> after, hunks)
    case Con{SCon{'-', line}, rest}: update_lines(rest, line <> before, after, hunks)
    case Con{SCon{'+', line}, rest}: update_lines(rest, before, line <> after, hunks)
    case _: Fail{invalid()}

def update_start(lines: +List<String>) -> Result<&2, &2, String, Patch>:
  match lines:
    case Con{"@@", rest}: update_lines(rest, Nil{}, Nil{}, Nil{})
    case Con{SCon{'@', SCon{'@', SCon{' ', header}}}, rest}: update_lines(rest, Nil{}, Nil{}, Nil{})
    case _: Fail{invalid()}

def parse(lines: +List<String>) -> Result<&2, &2, String, Patch>:
  match lines:
    case Con{"*** Begin Patch", Con{"*** Add File: work-ui.dsl", rest}}: added(rest, Nil{})
    case Con{"*** Begin Patch", Con{"*** Update File: work-ui.dsl", rest}}: update_start(rest)
    case Con{"*** Begin Patch", Con{"*** Delete File: work-ui.dsl", Con{"*** End Patch", rest}}}: ending(finished(rest), Delete{})
    case _: Fail{invalid()}

def consume_checked(before: +List<String>, source: +List<String>, equal: Bool) -> Maybe<&2, +List<String>>:
  match before source equal:
    case _ _ False{}: None{}
    case Nil{} _ True{}: Some{source}
    case Con{+wanted, rest} Con{+line, tail} True{}: consume_checked(rest, tail, String.eq(wanted, line))
    case _ Nil{} True{}: None{}

def consume(before: +List<String>, source: +List<String>) -> Maybe<&2, +List<String>>:
  consume_checked(before, source, True{})

type Location is Data:
  Location{prefix: +List<String>, tail: +List<String>}

# Exact context is checked once per candidate. Recurse only after a mismatch;
# eager evaluation of a recursive argument would search the already matched tail.
def seek_checked(source: +List<String>, +before: +List<String>, found: Maybe<&2, +List<String>>, prefix: +List<String>) -> Maybe<&2, Location>:
  match source found:
    case _ Some{tail}: Some{Location{List.reverse(&2, String, prefix), tail}}
    case Nil{} None{}: None{}
    case Con{line, +tail} None{}: seek_checked(tail, before, consume(before, tail), line <> prefix)

def seek(+before: +List<String>, +source: +List<String>) -> Maybe<&2, Location>:
  seek_checked(source, before, consume(before, source), Nil{})

def appended(prefix: +List<String>, result: Result<&2, &2, String, +List<String>>) -> Result<&2, &2, String, +List<String>>:
  match result:
    case Fail{reason}: Fail{reason}
    case Done{lines}: Done{List.append(&2, String, prefix, lines)}

def located(remaining: +List<String> -> Result<&2, &2, String, +List<String>>,
  found: Maybe<&2, Location>, after: +List<String>) -> Result<&2, &2, String, +List<String>>:
  match found:
    case None{}: Fail{"Patch context does not match the current Work UI source."}
    case Some{Location{prefix, tail}}: appended(prefix, appended(after, remaining(tail)))

def applied_hunks(hunks: +List<Hunk>, source: +List<String>) -> Result<&2, &2, String, +List<String>>:
  match hunks:
    case Nil{}: Done{source}
    case Con{Hunk{before, after}, rest}: located((tail => applied_hunks(rest, tail)), seek(before, source), after)

def source_lines(source: String) -> +List<String>:
  match source:
    case "": Nil{}
    case _: lines(source)

def joined(result: Result<&2, &2, String, +List<String>>) -> Result<&2, &2, String, String>:
  match result:
    case Fail{reason}: Fail{reason}
    case Done{lines}: Done{String.join(lines, "\n")}

def add_empty(empty: Bool, lines: +List<String>) -> Result<&2, &2, String, String>:
  match empty:
    case False{}: Fail{"Add File requires an empty Work UI. Use Update File to edit the existing source."}
    case True{}: Done{String.join(lines, "\n")}

def realize(patch: Patch, +source: String) -> Result<&2, &2, String, String>:
  match patch:
    case Add{lines}: add_empty(String.eq(source, ""), lines)
    case Update{hunks}: joined(applied_hunks(hunks, source_lines(source)))
    case Delete{}: Done{""}

def parsed(result: Result<&2, &2, String, Patch>, source: String) -> Result<&2, &2, String, String>:
  match result:
    case Fail{reason}: Fail{reason}
    case Done{patch}: realize(patch, source)

def bounded_source(accepted: Bool, source: String) -> Result<&2, &2, String, String>:
  match accepted:
    case False{}: Fail{"Work UI source cannot exceed 100000 characters."}
    case True{}: Done{source}

def bounded_result(result: Result<&2, &2, String, String>) -> Result<&2, &2, String, String>:
  match result:
    case Fail{reason}: Fail{reason}
    case Done{+source}: bounded_source(Nat.is_le(String.length(source), 100000n), source)

def bounded_patch(accepted: Bool, source: String, patch: String) -> Result<&2, &2, String, String>:
  match accepted:
    case False{}: Fail{"A Work UI patch cannot exceed 200000 characters."}
    case True{}: bounded_result(parsed(parse(clean_lines(lines(patch))), source))

def apply(source: String, +patch: String) -> Result<&2, &2, String, String>:
  bounded_patch(Nat.is_le(String.length(patch), 200000n), source, patch)
