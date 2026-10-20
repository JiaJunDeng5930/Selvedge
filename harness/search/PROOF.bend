import Base
import ../MODEL.bend as M
import ../COMMANDS.bend as Commands
import ./MODEL.bend as S
import ./PROGRAM.bend as Actual
import ../DOMAIN.bend as D
import ../../bendlib/json.bend as J

# A rejected project/Work intersection contributes no messages to the result.
def excluded_source(+source: S.Source, +query: String, +project: Maybe<&2, Nat>, +work: Maybe<&2, Nat>, +rest: +List<S.Source>,
  excluded: {Actual.selected(project, work, source) == False{} : Bool}) ->
  {Actual.collect(source <> rest, query, project, work) == Actual.collect(rest, query, project, work) : +List<J.Json>}:
  Equal.cong(Bool, +List<J.Json>, accepted => List.append(&2, J.Json, Actual.source_hits(accepted, source, query), Actual.collect(rest, query, project, work)),
    Actual.selected(project, work, source), False{}, excluded)

# This index includes invisible records in the original history. It is not the
# position in filtered search results or in the current model context.
def latest_user_location(+previous: D.History, +summary: J.Json, +query: String, +text: String, +newer: String,
  found: {Actual.matches(query, text) == True{} : Bool}) ->
  {Actual.scan_history(D.HistoryNode{previous, D.UserMessage{text}}, (1n + D.history_length(previous) : Nat), summary, query, newer) ==
    Actual.hit(summary, D.history_length(previous), "user", text, query, Actual.first_readable(previous), newer) <>
      Actual.scan_history(previous, D.history_length(previous), summary, query, String.take(text, S.context_characters())) : +List<J.Json>}:
  Equal.cong(Bool, +List<J.Json>, accepted => Actual.keep_hit(accepted, summary, D.history_length(previous), "user", text, query, previous, newer,
      Actual.scan_history(previous, D.history_length(previous), summary, query, String.take(text, S.context_characters()))),
    Actual.matches(query, text), True{}, found)

def hidden_context_keeps_original_offset(previous: D.History, remaining: Nat, summary: J.Json, query: String, newer: String, context: D.HistoryContext) ->
  {Actual.scan_history(D.HistoryNode{previous, D.ContextMessage{context}}, (1n + remaining : Nat), summary, query, newer) ==
    Actual.scan_history(previous, remaining, summary, query, newer) : +List<J.Json>}:
  {==}

def drop_zero(items: +List<J.Json>) -> {List.drop(&2, J.Json, items, 0n) == items : +List<J.Json>}:
  match items:
    case Nil{}: {==}
    case Con{head, tail}: {==}

# Removing an already delivered prefix leaves precisely the next result page.
def drop_delivered(+prefix: +List<J.Json>, +rest: +List<J.Json>) ->
  {List.drop(&2, J.Json, List.append(&2, J.Json, prefix, rest), List.length(&2, J.Json, prefix)) == rest : +List<J.Json>}:
  match prefix:
    case Nil{}: drop_zero(rest)
    case Con{head, tail}: drop_delivered(tail, rest)

def next_page(+delivered: +List<J.Json>, +remaining: +List<J.Json>, +limit: Nat) ->
  {Actual.page(List.append(&2, J.Json, delivered, remaining), List.length(&2, J.Json, delivered), limit) ==
    Actual.page_remaining(remaining, List.length(&2, J.Json, delivered), limit) : J.Json}:
  Equal.cong(+List<J.Json>, J.Json, suffix => Actual.page_remaining(suffix, List.length(&2, J.Json, delivered), limit),
    List.drop(&2, J.Json, List.append(&2, J.Json, delivered, remaining), List.length(&2, J.Json, delivered)), remaining,
    drop_delivered(delivered, remaining))

def invalid_request(sources: +List<S.Source>, query: String, project: Maybe<&2, Nat>, work: Maybe<&2, Nat>, after: Nat, limit: Nat) ->
  {Actual.execute_valid(False{}, sources, query, project, work, after, limit) ==
    D.failure("invalid_search", "Search requires 1..240 characters and a page size from 1 to 50") : J.Json}:
  {==}

# Both clients call this public query. Its successful scope resolution reaches
# the verified selector and page calculation; generic observation laws already
# establish unchanged world, no effects and no durable journal input.
def public_selected_page(+query: String, +project: Maybe<&2, Nat>, +work: Maybe<&2, Nat>, +after: Nat, +limit: Nat, +world: M.World(),
  project_exists: {Commands.search_project_exists(project, world) == True{} : Bool},
  work_exists: {Commands.search_work_exists(work, world) == True{} : Bool}) ->
  {Commands.query(M.Search{query, project, work, after, limit}, world) ==
    Actual.execute(Commands.search_sources(Commands.entries(world), world), query, project, work, after, limit) : J.Json}:
  Equal.trans(J.Json,
    Commands.query(M.Search{query, project, work, after, limit}, world),
    Commands.search_scoped(True{}, Commands.search_work_exists(work, world), query, project, work, after, limit, world),
    Actual.execute(Commands.search_sources(Commands.entries(world), world), query, project, work, after, limit),
    Equal.cong(Bool, J.Json, exists => Commands.search_scoped(exists, Commands.search_work_exists(work, world), query, project, work, after, limit, world),
      Commands.search_project_exists(project, world), True{}, project_exists),
    Equal.cong(Bool, J.Json, exists => Commands.search_scoped(True{}, exists, query, project, work, after, limit, world),
      Commands.search_work_exists(work, world), True{}, work_exists))

def public_missing_project(+query: String, +project: Maybe<&2, Nat>, +work: Maybe<&2, Nat>, +after: Nat, +limit: Nat, +world: M.World(),
  missing: {Commands.search_project_exists(project, world) == False{} : Bool}) ->
  {Commands.query(M.Search{query, project, work, after, limit}, world) == D.failure("project_not_found", "The project does not exist") : J.Json}:
  Equal.cong(Bool, J.Json, exists => Commands.search_scoped(exists, Commands.search_work_exists(work, world), query, project, work, after, limit, world),
    Commands.search_project_exists(project, world), False{}, missing)
