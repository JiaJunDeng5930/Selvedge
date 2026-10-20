import Base
import ./MODEL.bend as S
import ../DOMAIN.bend as D
import ../workspace/WORKSPACE.bend as Workspace
import ../../bendlib/json.bend as J

# Match ASCII letters without changing Chinese or other Unicode characters.
def folded_character(+code: U32) -> U32:
  Bool.pick(U32, U32.is_ge(code, 65) && U32.is_le(code, 90), (code + 32 : U32), code)

# Long assistant replies cross the JavaScript stack limit when characters are
# rebuilt after recursion; accumulate first so the compiler emits a loop.
def folded_acc(text: String, acc: String) -> String:
  match text:
    case SNil{}: String.reverse(acc)
    case SCon{Chr{code}, rest}: folded_acc(rest, SCon{Chr{folded_character(code)}, acc})

def folded(text: String) -> String:
  folded_acc(text, "")

def matches(+query: String, text: String) -> Bool:
  String.contains(folded(text), query)

def selected(project: Maybe<&2, Nat>, work: Maybe<&2, Nat>, source: S.Source) -> Bool:
  S.Source{task, summary, owner} = source
  S.identity_matches(project, Workspace.project_id(D.task_context(task))) && S.identity_matches(work, owner)

def first_readable_value(found: Maybe<&2, S.Text>, fallback: Unit -> String) -> String:
  match found:
    case None{}: fallback(Unit{})
    case Some{S.Text{role, text}}: String.take(text, S.context_characters())

def first_readable(history: D.History) -> String:
  match history:
    case D.EmptyHistory{}: ""
    case D.HistoryNode{previous, message}:
      first_readable_value(S.readable(message), (unused => first_readable(previous)))

def newer_text(found: Maybe<&2, S.Text>, fallback: String) -> String:
  match found:
    case None{}: fallback
    case Some{S.Text{role, text}}: String.take(text, S.context_characters())

def match_offset_checked(found: Bool, offset: Nat, fallback: Unit -> Nat) -> Nat:
  match found:
    case True{}: offset
    case False{}: fallback(Unit{})

def match_offset(+text: String, +query: String, +offset: Nat) -> Nat:
  match text:
    case SNil{}: offset
    case SCon{character, rest}:
      match_offset_checked(String.starts_with(text, query), offset, (unused => match_offset(rest, query, (1n + offset : Nat))))

def snippet(+query: String, +text: String) -> String:
  String.take(String.drop(text, Nat.sub(match_offset(folded(text), query, 0n), 80n)), S.snippet_characters())

def hit(summary: J.Json, index: Nat, role: String, +text: String, query: String, before: String, after: String) -> J.Json:
  J.Object{[J.Field{"task", summary}, J.Field{"message_index", J.nat(index)},
    J.Field{"role", J.Text{role}}, J.Field{"snippet", J.Text{snippet(query, text)}},
    J.Field{"before", J.Text{before}}, J.Field{"after", J.Text{after}}]}

def keep_hit(found: Bool, summary: J.Json, index: Nat, role: String, text: String, query: String,
  previous: D.History, newer: String, rest: +List<J.Json>) -> +List<J.Json>:
  match found:
    case False{}: rest
    case True{}: hit(summary, index, role, text, query, first_readable(previous), newer) <> rest

def readable_hit(found: Maybe<&2, S.Text>, summary: J.Json, index: Nat, +query: String,
  previous: D.History, newer: String, rest: +List<J.Json>) -> +List<J.Json>:
  match found:
    case None{}: rest
    case Some{S.Text{role, +text}}: keep_hit(matches(query, text), summary, index, role, text, query, previous, newer, rest)

def previous_index(value: Nat) -> Nat:
  match value:
    case 0n: 0n
    case 1n+index: index

# The index counts every original record, including invisible context/tool data.
# Compaction changes model input only; these original positions remain stable.
def scan_history(history: D.History, +remaining: Nat, +summary: J.Json, +query: String, +newer: String) -> +List<J.Json>:
  match history:
    case D.EmptyHistory{}: Nil{}
    case D.HistoryNode{+previous, +message}:
      readable_hit(S.readable(message), summary, previous_index(remaining), query, previous, newer,
        scan_history(previous, previous_index(remaining), summary, query, newer_text(S.readable(message), newer)))

def source_hits(accepted: Bool, source: S.Source, query: String) -> +List<J.Json>:
  match accepted:
    case False{}: Nil{}
    case True{}:
      S.Source{task, summary, work} = source
      +original = D.task_history(task)
      scan_history(original, D.history_length(original), summary, query, "")

def source_id(source: S.Source) -> Nat:
  S.Source{task, summary, work} = source
  D.task_id(task)

def insert_source_ordered(before: Bool, source: S.Source, +head: S.Source, rest: +List<S.Source>, fallback: Unit -> +List<S.Source>) -> +List<S.Source>:
  match before:
    case True{}: source <> head <> rest
    case False{}: head <> fallback(Unit{})

def insert_source(+source: S.Source, sorted: +List<S.Source>) -> +List<S.Source>:
  match sorted:
    case Nil{}: [source]
    case Con{+head, +rest}:
      insert_source_ordered(Nat.is_ge(source_id(source), source_id(head)), source, head, rest, (unused => insert_source(source, rest)))

def ordered(sources: +List<S.Source>, sorted: +List<S.Source>) -> +List<S.Source>:
  match sources:
    case Nil{}: sorted
    case Con{source, rest}: ordered(rest, insert_source(source, sorted))

def collect(sources: +List<S.Source>, +query: String, +project: Maybe<&2, Nat>, +work: Maybe<&2, Nat>) -> +List<J.Json>:
  match sources:
    case Nil{}: Nil{}
    case Con{+source, rest}:
      List.append(&2, J.Json, source_hits(selected(project, work, source), source, query), collect(rest, query, project, work))

def next_after(more: Bool, after: Nat, limit: Nat) -> J.Json:
  match more:
    case False{}: J.Null{}
    case True{}: J.nat((after + limit : Nat))

def page_remaining(+remaining: +List<J.Json>, +after: Nat, +limit: Nat) -> J.Json:
  +more = Nat.is_lt(limit, List.length(&2, J.Json, remaining))
  D.success(J.Object{[J.Field{"hits", J.Array{List.take(&2, J.Json, remaining, limit)}}, J.Field{"after", J.nat(after)},
    J.Field{"has_more", J.Boolean{more}}, J.Field{"next_after", next_after(more, after, limit)}]})

def page(hits: +List<J.Json>, +after: Nat, limit: Nat) -> J.Json:
  page_remaining(List.drop(&2, J.Json, hits, after), after, limit)

def execute_valid(valid: Bool, sources: +List<S.Source>, +query: String, project: Maybe<&2, Nat>, work: Maybe<&2, Nat>, after: Nat, limit: Nat) -> J.Json:
  match valid:
    case False{}: D.failure("invalid_search", "Search requires 1..240 characters and a page size from 1 to 50")
    case True{}: page(collect(ordered(sources, Nil{}), folded(query), project, work), after, limit)

def execute(sources: +List<S.Source>, query: String, project: Maybe<&2, Nat>, work: Maybe<&2, Nat>, after: Nat, +limit: Nat) -> J.Json:
  +text = String.trim(query)
  execute_valid(S.query_valid(text) && S.page_size_valid(limit), sources, text, project, work, after, limit)
