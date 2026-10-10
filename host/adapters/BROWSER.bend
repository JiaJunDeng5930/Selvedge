import Base
import ../../bendlib/json.bend as J
import ../../bendlib/categories.bend as Categories
import ./MODEL.bend as Model

# UTF-16 units preserve the browser's existing text budget, including astral text.
def character_units(basic: Bool) -> Nat:
  match basic:
    case True{}: 1n
    case False{}: 2n

def text_units(text: String) -> Nat:
  match text:
    case SNil{}: 0n
    case SCon{Chr{code}, rest}: (character_units(U32.is_lt(code, 65536)) + text_units(rest) : Nat)

def raw_characters_scan(text: String, valid: Bool) -> Bool:
  match text:
    case SNil{}: valid
    case SCon{Chr{+code}, rest}:
      raw_characters_scan(rest, valid && Bool.not(U32.is_lt(code, 33) || U32.is_eq(code, 127) || U32.is_eq(code, 92)))

def raw_characters(text: String) -> Bool:
  raw_characters_scan(text, True{})

def unicode_text_scan(text: String, valid: Bool) -> Bool:
  match text:
    case SNil{}: valid
    case SCon{Chr{+code}, rest}:
      unicode_text_scan(rest, valid && (U32.is_lt(code, 1114112) && (U32.is_lt(code, 55296) || Bool.not(U32.is_lt(code, 57344)))))

def unicode_text(text: String) -> Bool:
  unicode_text_scan(text, True{})

def typed_text(+value: J.Json) -> Bool:
  J.is_text(value) && unicode_text(J.text(value))

def raw_valid(source: J.Json) -> Bool:
  +raw = J.get(source, "raw")
  typed_text(raw) && raw_characters(J.text(raw))

def protocol_allowed(+source: J.Json) -> Bool:
  +raw = J.text(J.get(source, "raw"))
  +scheme = J.text(J.get(J.get(source, "observation"), "scheme"))
  String.starts_with(raw, "#") || String.eq(scheme, "https:") || String.eq(scheme, "http:") || String.eq(scheme, "mailto:")

def normalized_target(+source: J.Json) -> Bool:
  String.starts_with(J.text(J.get(source, "raw")), "#") ||
    (J.boolean(J.get(J.get(source, "observation"), "parsed")) && typed_text(J.get(J.get(source, "observation"), "href")))

def raw_category() -> J.Json -> Type: Categories.holds(J.Json, (source => raw_valid(source)))
def protocol_category() -> J.Json -> Type: Categories.holds(J.Json, (source => protocol_allowed(source)))
def normalized_category() -> J.Json -> Type: Categories.holds(J.Json, (source => normalized_target(source)))

def link_policy(+source: J.Json) -> Bool:
  raw_valid(source) && protocol_allowed(source) && normalized_target(source)

def navigation(source: J.Json) -> Type:
  Categories.intersection(J.Json, raw_category(), (value => Categories.intersection(J.Json, protocol_category(), normalized_category(), value)), source)

def navigation_raw() -> Categories.Inclusion<J.Json, navigation, raw_category()>:
  Categories.intersection_first(J.Json, raw_category(), (value => Categories.intersection(J.Json, protocol_category(), normalized_category(), value)))

def navigation_protocol_normalized() -> Categories.Inclusion<J.Json, navigation, (value => Categories.intersection(J.Json, protocol_category(), normalized_category(), value))>:
  Categories.intersection_second(J.Json, raw_category(), (value => Categories.intersection(J.Json, protocol_category(), normalized_category(), value)))

def link_selected(fragment: Bool, +source: J.Json) -> J.Json:
  match fragment:
    case True{}: J.get(source, "raw")
    case False{}: J.get(J.get(source, "observation"), "href")

def navigation_checked(+source: J.Json,
    prior: Categories.intersection(J.Json, protocol_category(), normalized_category(), source),
    accepted: Bool, observed: {raw_valid(source) == accepted : Bool}) -> Maybe<&1, Categories.Membership<J.Json, navigation>>:
  match accepted:
    case True{}: Some{Categories.Membership{source, Categories.Intersection{observed, prior}}}
    case False{}: None{}

def navigation_protocol_admitted(admission: Maybe<&1, Categories.Membership<J.Json,
    (source => Categories.intersection(J.Json, protocol_category(), normalized_category(), source))>>) -> Maybe<&1, Categories.Membership<J.Json, navigation>>:
  match admission:
    case None{}: None{}
    case Some{member}:
      Categories.Membership{+source, evidence} = member
      navigation_checked(source, evidence, raw_valid(source), {==})

def admit_navigation(source: J.Json) -> Maybe<&1, Categories.Membership<J.Json, navigation>>:
  navigation_protocol_admitted(Categories.admit_intersection(J.Json,
    (candidate => protocol_allowed(candidate)), (candidate => normalized_target(candidate)), source))

def navigation_source(member: Categories.Membership<J.Json, navigation>) -> J.Json:
  Categories.value(J.Json, navigation, member)

def link_owned(member: Categories.Membership<J.Json, navigation>) -> J.Json:
  +source = navigation_source(member)
  link_selected(String.starts_with(J.text(J.get(source, "raw")), "#"), source)

def link_admitted(admission: Maybe<&1, Categories.Membership<J.Json, navigation>>) -> J.Json:
  match admission:
    case None{}: J.Null{}
    case Some{member}: link_owned(member)

def link_calculation(source: J.Json) -> J.Json:
  link_admitted(admit_navigation(source))

law admitted_navigation_original_source:
  @source:J.Json -> @evidence:navigation(source) ->
    {navigation_source(Categories.Membership{source, evidence}) == source : J.Json}

law admitted_navigation_raw:
  @source:J.Json -> navigation(source) -> {raw_valid(source) == True{} : Bool}

law admitted_navigation_protocol:
  @source:J.Json -> navigation(source) -> {protocol_allowed(source) == True{} : Bool}

law admitted_navigation_normalized:
  @source:J.Json -> navigation(source) -> {normalized_target(source) == True{} : Bool}

law admitted_navigation_result:
  @source:J.Json -> @evidence:navigation(source) ->
    {link_owned(Categories.Membership{source, evidence}) ==
      link_selected(String.starts_with(J.text(J.get(source, "raw")), "#"), source) : J.Json}

# Wire text admits Unicode scalar values; invalid surrogate data is not coerced.
def is_array(value: J.Json) -> Bool:
  match value:
    case J.Array{items}: True{}
    case _: False{}

# Safe integers are checked as decimal text; task identities exceed immediate Nat.
def integer_digits(text: String, upper: String, +count: Nat, +smaller: Bool, +greater: Bool) -> Bool:
  match text upper:
    case SNil{} _: Nat.is_lt(count, 16n) || Bool.not(greater)
    case SCon{Chr{+code}, rest} SCon{Chr{+bound}, remaining}:
      Bool.not(U32.is_lt(code, 48)) && U32.is_lt(code, 58) &&
        integer_digits(rest, remaining, (count + 1n : Nat),
          smaller || (Bool.not(greater) && U32.is_lt(code, bound)),
          greater || (Bool.not(smaller) && U32.is_lt(bound, code)))
    case _ SNil{}: False{}

def canonical_digits(text: String) -> Bool:
  match text:
    case SCon{'0', rest}: String.is_empty(rest)
    case _: True{}

def safe_integer(value: J.Json) -> Bool:
  match value:
    case J.Number{lexeme}:
      match lexeme:
        case SCon{'-', +rest}: Bool.not(String.is_empty(rest)) && canonical_digits(rest) && Bool.not(String.eq(rest, "0")) && integer_digits(rest, "9007199254740991", 0n, False{}, False{})
        case +other: Bool.not(String.is_empty(other)) && canonical_digits(other) && integer_digits(other, "9007199254740991", 0n, False{}, False{})
    case _: False{}

def parts_admissible(parts: +List<J.Json>) -> Bool:
  match parts:
    case Nil{}: True{}
    case Con{+part, rest}:
      J.is_object(part) && safe_integer(J.get(part, "output_index")) && typed_text(J.get(part, "text")) && parts_admissible(rest)

def entries_admissible(entries: +List<J.Json>) -> Bool:
  match entries:
    case Nil{}: True{}
    case Con{+entry, rest}:
      J.is_object(entry) && safe_integer(J.get(entry, "task_id")) && safe_integer(J.get(entry, "ticket")) &&
        is_array(J.get(entry, "parts")) && parts_admissible(J.items(J.get(entry, "parts"))) && entries_admissible(rest)

def event_text_admissible(claimed: Bool, notice: J.Json) -> Bool:
  match claimed:
    case True{}: typed_text(J.get(notice, "text"))
    case False{}: True{}

def event_admissible(+kind: String, notice: J.Json) -> Bool:
  event_text_admissible(String.eq(kind, "delta") || String.eq(kind, "snapshot"), notice)

def restored_admissible(restored: Bool, +notice: J.Json) -> Bool:
  match restored:
    case True{}: is_array(J.get(notice, "streams")) && entries_admissible(J.items(J.get(notice, "streams")))
    case False{}: event_admissible(J.text(J.get(notice, "type")), notice)

# Ordinary unrecognized or incomplete frames retain the established ignore rule.
# A claimed text field must still be a Unicode string, never a coercible value.
def notice_admissible(+notice: J.Json) -> Bool:
  J.is_object(notice) && typed_text(J.get(notice, "type")) &&
    restored_admissible(String.eq(J.text(J.get(notice, "type")), "stream-state"), notice)

def same_number(left: J.Json, right: J.Json) -> Bool:
  match left right:
    case J.Number{a} J.Number{b}: String.eq(a, b)
    case _ _: False{}

def index_absent(parts: +List<J.Json>, +index: J.Json) -> Bool:
  match parts:
    case Nil{}: True{}
    case Con{+part, rest}: Bool.not(same_number(J.get(part, "output_index"), index)) && index_absent(rest, index)

def parts_unique(parts: +List<J.Json>) -> Bool:
  match parts:
    case Nil{}: True{}
    case Con{+part, +rest}: index_absent(rest, J.get(part, "output_index")) && parts_unique(rest)

def same_stream(+left: J.Json, +right: J.Json) -> Bool:
  same_number(J.get(left, "task_id"), J.get(right, "task_id")) && same_number(J.get(left, "ticket"), J.get(right, "ticket"))

def stream_absent(entries: +List<J.Json>, +entry: J.Json) -> Bool:
  match entries:
    case Nil{}: True{}
    case Con{+first, rest}: Bool.not(same_stream(first, entry)) && stream_absent(rest, entry)

def state_unique(entries: +List<J.Json>) -> Bool:
  match entries:
    case Nil{}: True{}
    case Con{+entry, +rest}: stream_absent(rest, entry) && parts_unique(J.items(J.get(entry, "parts"))) && state_unique(rest)

def stream_source_admissible(+source: J.Json) -> Bool:
  J.is_object(source) && is_array(J.get(source, "state")) && entries_admissible(J.items(J.get(source, "state"))) && state_unique(J.items(J.get(source, "state"))) && notice_admissible(J.get(source, "notice"))

def stream_source_category() -> J.Json -> Type:
  Categories.holds(J.Json, (source => stream_source_admissible(source)))

def stream_entry(+task: J.Json, +ticket: J.Json, +parts: +List<J.Json>) -> J.Json:
  J.Object{[J.Field{"task_id", task}, J.Field{"ticket", ticket}, J.Field{"parts", J.Array{parts}}]}

def part_entry(index: J.Json, +text: String) -> J.Json:
  J.Object{[J.Field{"output_index", index}, J.Field{"text", J.Text{text}}]}

def part_put_found(found: Bool, part: J.Json, rest: +List<J.Json>, value: J.Json, tail: +List<J.Json>) -> +List<J.Json>:
  match found:
    case True{}: value <> rest
    case False{}: part <> tail

def part_put(parts: +List<J.Json>, +value: J.Json) -> +List<J.Json>:
  match parts:
    case Nil{}: value <> Nil{}
    case Con{+part, +rest}:
      part_put_found(same_number(J.get(part, "output_index"), J.get(value, "output_index")), part, rest, value, part_put(rest, value))

def stream_put_found(found: Bool, entry: J.Json, rest: +List<J.Json>, value: J.Json, tail: +List<J.Json>) -> +List<J.Json>:
  match found:
    case True{}: value <> rest
    case False{}: entry <> tail

def stream_put(entries: +List<J.Json>, +value: J.Json) -> +List<J.Json>:
  match entries:
    case Nil{}: value <> Nil{}
    case Con{+entry, +rest}:
      stream_put_found(same_stream(entry, value), entry, rest, value, stream_put(rest, value))

def result(+state: +List<J.Json>, +publish: Bool) -> J.Json:
  J.Object{[J.Field{"state", J.Array{state}}, J.Field{"publish", J.Boolean{publish}}]}

def restore_parts(parts: +List<J.Json>, +result: +List<J.Json>) -> +List<J.Json>:
  match parts:
    case Nil{}: result
    case Con{+part, rest}: restore_parts(rest, part_put(result, part_entry(J.get(part, "output_index"), J.text(J.get(part, "text")))))

def restore_streams(entries: +List<J.Json>, +result: +List<J.Json>) -> +List<J.Json>:
  match entries:
    case Nil{}: result
    case Con{+entry, rest}:
      restore_streams(rest, stream_put(result, stream_entry(J.get(entry, "task_id"), J.get(entry, "ticket"), restore_parts(J.items(J.get(entry, "parts")), Nil{}))))

def stream_remove_found(found: Bool, entry: J.Json, rest: +List<J.Json>, tail: +List<J.Json>) -> +List<J.Json>:
  match found:
    case True{}: rest
    case False{}: entry <> tail

def stream_remove(entries: +List<J.Json>, +notice: J.Json) -> +List<J.Json>:
  match entries:
    case Nil{}: Nil{}
    case Con{+entry, +rest}:
      stream_remove_found(same_stream(entry, notice), entry, rest, stream_remove(rest, notice))

def part_find_found(found: Bool, part: J.Json, tail: Maybe<&2, String>) -> Maybe<&2, String>:
  match found:
    case True{}: Some{J.text(J.get(part, "text"))}
    case False{}: tail

def part_find(parts: +List<J.Json>, +index: J.Json) -> Maybe<&2, String>:
  match parts:
    case Nil{}: None{}
    case Con{+part, rest}:
      part_find_found(same_number(J.get(part, "output_index"), index), part, part_find(rest, index))

def updated_text(delta: Bool, previous: Maybe<&2, String>, +text: String) -> String:
  match delta previous:
    case True{} Some{old}: old ++ text
    case _ _: text

def part_count(parts: +List<J.Json>) -> Nat:
  match parts:
    case Nil{}: 0n
    case Con{part, rest}: (1n + part_count(rest) : Nat)

def part_exists(found: Maybe<&2, String>) -> Bool:
  match found:
    case None{}: False{}
    case Some{text}: True{}

def update_budget(parts: +List<J.Json>, found: Maybe<&2, String>, text: String) -> Bool:
  Nat.is_le(text_units(text), 4194304n) && (Nat.is_lt(part_count(parts), 32n) || part_exists(found))

def update_entry_allowed(allowed: Bool, +entry: J.Json, parts: +List<J.Json>, index: J.Json, text: String) -> Maybe<&2, J.Json>:
  match allowed:
    case False{}: None{}
    case True{}: Some{stream_entry(J.get(entry, "task_id"), J.get(entry, "ticket"), part_put(parts, part_entry(index, text)))}

# The host retains its unlimited stream policy; the browser keeps its UI quota.
def update_policy(bounded: Bool, parts: +List<J.Json>, found: Maybe<&2, String>, text: String) -> Bool:
  match bounded:
    case True{}: update_budget(parts, found, text)
    case False{}: True{}

def update_entry_policy(+bounded: Bool, +entry: J.Json, +notice: J.Json) -> Maybe<&2, J.Json>:
  +parts = J.items(J.get(entry, "parts"))
  +index = J.get(notice, "output_index")
  +found = part_find(parts, index)
  +text = updated_text(String.eq(J.text(J.get(notice, "type")), "delta"), found, J.text(J.get(notice, "text")))
  update_entry_allowed(update_policy(bounded, parts, found, text), entry, parts, index, text)

def preserve_updated_tail(entry: J.Json, updated: (+List<J.Json> & Bool)) -> (+List<J.Json> & Bool):
  (remaining, publish) = updated
  (entry <> remaining, publish)

def stream_update_result(updated: Maybe<&2, J.Json>, entry: J.Json, +rest: +List<J.Json>) -> (+List<J.Json> & Bool):
  match updated:
    case None{}: (entry <> rest, False{})
    case Some{value}: (value <> rest, True{})

def stream_update_found_policy(+bounded: Bool, found: Bool, +entry: J.Json, rest: +List<J.Json>, notice: J.Json, tail: (+List<J.Json> & Bool)) -> (+List<J.Json> & Bool):
  match found:
    case True{}: stream_update_result(update_entry_policy(bounded, entry, notice), entry, rest)
    case False{}: preserve_updated_tail(entry, tail)

def stream_update_policy(+bounded: Bool, entries: +List<J.Json>, +notice: J.Json) -> (+List<J.Json> & Bool):
  match entries:
    case Nil{}: (Nil{}, False{})
    case Con{+entry, +rest}:
      stream_update_found_policy(bounded, same_stream(entry, notice), entry, rest, notice, stream_update_policy(bounded, rest, notice))

def stream_notice_valid(+notice: J.Json) -> Bool:
  safe_integer(J.get(notice, "task_id")) && safe_integer(J.get(notice, "ticket"))

def stream_update_valid(+notice: J.Json) -> Bool:
  +kind = J.text(J.get(notice, "type"))
  (String.eq(kind, "delta") || String.eq(kind, "snapshot")) && J.is_text(J.get(notice, "text")) && safe_integer(J.get(notice, "output_index"))

def stream_updated_result(updated: (+List<J.Json> & Bool)) -> J.Json:
  (state, publish) = updated
  result(state, publish)

def stream_delta_policy(+bounded: Bool, valid: Bool, +state: +List<J.Json>, notice: J.Json) -> J.Json:
  match valid:
    case False{}: result(state, False{})
    case True{}: stream_updated_result(stream_update_policy(bounded, state, notice))

def stream_end_policy(+bounded: Bool, ended: Bool, +state: +List<J.Json>, +notice: J.Json) -> J.Json:
  match ended:
    case True{}: result(stream_remove(state, notice), True{})
    case False{}: stream_delta_policy(bounded, stream_update_valid(notice), state, notice)

def stream_start_policy(+bounded: Bool, start: Bool, +kind: String, +state: +List<J.Json>, +notice: J.Json) -> J.Json:
  match start:
    case True{}: result(stream_put(state, stream_entry(J.get(notice, "task_id"), J.get(notice, "ticket"), Nil{})), True{})
    case False{}: stream_end_policy(bounded, String.eq(kind, "stream_end") || String.eq(kind, "stream_cancel"), state, notice)

def stream_event_kind_policy(+bounded: Bool, +kind: String, state: +List<J.Json>, +notice: J.Json) -> J.Json:
  stream_start_policy(bounded, String.eq(kind, "stream_start"), kind, state, notice)

def stream_event_owned_policy(+bounded: Bool, valid: Bool, +state: +List<J.Json>, +notice: J.Json) -> J.Json:
  match valid:
    case False{}: result(state, False{})
    case True{}: stream_event_kind_policy(bounded, J.text(J.get(notice, "type")), state, notice)

def stream_event_policy(+bounded: Bool, state: +List<J.Json>, +notice: J.Json) -> J.Json:
  stream_event_owned_policy(bounded, stream_notice_valid(notice), state, notice)

def update_entry(+entry: J.Json, +notice: J.Json) -> Maybe<&2, J.Json>:
  update_entry_policy(True{}, entry, notice)

def stream_update_found(found: Bool, +entry: J.Json, rest: +List<J.Json>, notice: J.Json, tail: (+List<J.Json> & Bool)) -> (+List<J.Json> & Bool):
  stream_update_found_policy(True{}, found, entry, rest, notice, tail)

def stream_update(entries: +List<J.Json>, +notice: J.Json) -> (+List<J.Json> & Bool):
  stream_update_policy(True{}, entries, notice)

def stream_delta(valid: Bool, +state: +List<J.Json>, notice: J.Json) -> J.Json:
  stream_delta_policy(True{}, valid, state, notice)

def stream_end(ended: Bool, +state: +List<J.Json>, +notice: J.Json) -> J.Json:
  stream_end_policy(True{}, ended, state, notice)

def stream_start(start: Bool, +kind: String, +state: +List<J.Json>, +notice: J.Json) -> J.Json:
  stream_start_policy(True{}, start, kind, state, notice)

def stream_event_kind(+kind: String, state: +List<J.Json>, +notice: J.Json) -> J.Json:
  stream_event_kind_policy(True{}, kind, state, notice)

def stream_event_owned(valid: Bool, +state: +List<J.Json>, +notice: J.Json) -> J.Json:
  stream_event_owned_policy(True{}, valid, state, notice)

def stream_event(state: +List<J.Json>, +notice: J.Json) -> J.Json:
  stream_event_policy(True{}, state, notice)

def stream_restore(restored: Bool, state: +List<J.Json>, +notice: J.Json) -> J.Json:
  match restored:
    case True{}: result(restore_streams(J.items(J.get(notice, "streams")), Nil{}), True{})
    case False{}: stream_event(state, notice)

def stream_transition_calculation(+source: J.Json) -> J.Json:
  +notice = J.get(source, "notice")
  stream_restore(String.eq(J.text(J.get(notice, "type")), "stream-state"), J.items(J.get(source, "state")), notice)

def stream_owned(member: Categories.Membership<J.Json, stream_source_category()>) -> J.Json:
  Categories.Membership{source, evidence} = member
  Model.success(stream_transition_calculation(source))

def stream_admitted(admission: Maybe<&1, Categories.Membership<J.Json, stream_source_category()>>) -> J.Json:
  match admission:
    case None{}: Model.failure("Invalid browser stream source: expected typed stream state and notice")
    case Some{member}: stream_owned(member)

def host_stream_transition_calculation(+source: J.Json) -> J.Json:
  stream_event_policy(False{}, J.items(J.get(source, "state")), J.get(source, "notice"))

def host_stream_owned(member: Categories.Membership<J.Json, stream_source_category()>) -> J.Json:
  Categories.Membership{source, evidence} = member
  Model.success(host_stream_transition_calculation(source))

def host_stream_admitted(admission: Maybe<&1, Categories.Membership<J.Json, stream_source_category()>>) -> J.Json:
  match admission:
    case None{}: Model.failure("Invalid browser stream source: expected typed stream state and notice")
    case Some{member}: host_stream_owned(member)

def host_stream_step_calculation(+source: J.Json) -> J.Json:
  host_stream_admitted(Categories.admit(J.Json, (candidate => stream_source_admissible(candidate)), source))

def stream_step_calculation(+source: J.Json) -> J.Json:
  stream_admitted(Categories.admit(J.Json, (candidate => stream_source_admissible(candidate)), source))

# Factories retain the complete raw source and consume its canonical construction.
def link_adapter() -> Model.Adapter(link_calculation):
  Model.adapter(link_calculation, link_calculation, source => {==})

def stream_adapter() -> Model.Adapter((source => stream_step_calculation(source))):
  Model.adapter((source => stream_step_calculation(source)), (source => stream_step_calculation(source)), source => {==})

def host_stream_adapter() -> Model.Adapter((source => host_stream_step_calculation(source))):
  Model.adapter((source => host_stream_step_calculation(source)), (source => host_stream_step_calculation(source)), source => {==})

def host_stream_step(+source: J.Json) -> J.Json:
  Model.execute((candidate => host_stream_step_calculation(candidate)), host_stream_adapter(), source)

def link(source: J.Json) -> J.Json:
  Model.execute(link_calculation, link_adapter(), source)

def stream_step(+source: J.Json) -> J.Json:
  Model.execute((candidate => stream_step_calculation(candidate)), stream_adapter(), source)

law link_correspondence:
  @source:J.Json -> {link(source) == link_calculation(source) : J.Json}

law stream_correspondence:
  @source:J.Json -> {stream_step(source) == stream_step_calculation(source) : J.Json}

# These production equations expose rejected writes, removal and preservation
# independently of the full source-to-result construction equation.
law update_rejected:
  @entry:J.Json -> @parts:+List<J.Json> -> @index:J.Json -> @text:String ->
    {update_entry_allowed(False{}, entry, parts, index, text) == None{} : Maybe<&2, J.Json>}

law update_committed:
  @entry:J.Json -> @parts:+List<J.Json> -> @index:J.Json -> @text:String ->
    {update_entry_allowed(True{}, entry, parts, index, text) ==
      Some{stream_entry(J.get(entry, "task_id"), J.get(entry, "ticket"), part_put(parts, part_entry(index, text)))} : Maybe<&2, J.Json>}

law removal_owned:
  @entry:J.Json -> @rest:+List<J.Json> -> @notice:J.Json ->
    {stream_remove_found(True{}, entry, rest, stream_remove(rest, notice)) == rest : +List<J.Json>}

law removal_unrelated:
  @entry:J.Json -> @rest:+List<J.Json> -> @notice:J.Json ->
    {stream_remove_found(False{}, entry, rest, stream_remove(rest, notice)) == entry <> stream_remove(rest, notice) : +List<J.Json>}

law update_unrelated:
  @entry:J.Json -> @rest:+List<J.Json> -> @notice:J.Json ->
    {stream_update_found(False{}, entry, rest, notice, stream_update(rest, notice)) ==
      preserve_updated_tail(entry, stream_update(rest, notice)) : (+List<J.Json> & Bool)}

law end_removal:
  @state:+List<J.Json> -> @notice:J.Json ->
    {stream_end(True{}, state, notice) == result(stream_remove(state, notice), True{}) : J.Json}

law limit_correspondence:
  @parts:+List<J.Json> -> @found:Maybe<&2, String> -> @text:String ->
    {update_budget(parts, found, text) ==
      Nat.is_le(text_units(text), 4194304n) && (Nat.is_lt(part_count(parts), 32n) || part_exists(found)) : Bool}

law host_stream_correspondence:
  @source:J.Json -> {host_stream_step(source) == host_stream_step_calculation(source) : J.Json}

law host_unlimited:
  @parts:+List<J.Json> -> @found:Maybe<&2, String> -> @text:String ->
    {update_policy(False{}, parts, found, text) == True{} : Bool}

law update_first_hit:
  @bounded:Bool -> @entry:J.Json -> @rest:+List<J.Json> -> @notice:J.Json -> @tail:(+List<J.Json> & Bool) ->
    {stream_update_found_policy(bounded, True{}, entry, rest, notice, tail) ==
      stream_update_result(update_entry_policy(bounded, entry, notice), entry, rest) : (+List<J.Json> & Bool)}

law update_policy_unrelated:
  @bounded:Bool -> @entry:J.Json -> @rest:+List<J.Json> -> @notice:J.Json -> @tail:(+List<J.Json> & Bool) ->
    {stream_update_found_policy(bounded, False{}, entry, rest, notice, tail) ==
      preserve_updated_tail(entry, tail) : (+List<J.Json> & Bool)}

law end_policy_removal:
  @bounded:Bool -> @state:+List<J.Json> -> @notice:J.Json ->
    {stream_end_policy(bounded, True{}, state, notice) == result(stream_remove(state, notice), True{}) : J.Json}

def run_host_stream(selected: Bool, operation: String, source: J.Json) -> J.Json:
  match selected:
    case True{}: host_stream_step(source)
    case False{}: Model.failure("Unknown browser model operation: " ++ operation)

def run_stream(selected: Bool, +operation: String, source: J.Json) -> J.Json:
  match selected:
    case True{}: stream_step(source)
    case False{}: run_host_stream(String.eq(operation, "browser.host_stream_step"), operation, source)
def run_link(selected: Bool, +operation: String, +source: J.Json) -> J.Json:
  match selected:
    case True{}: Model.success(link(source))
    case False{}: run_stream(String.eq(operation, "browser.stream_step"), operation, source)

def run(+operation: String, source: J.Json) -> J.Json:
  run_link(String.eq(operation, "browser.link"), operation, source)


def meaning_host_stream(selected: Bool, operation: String, source: J.Json) -> J.Json:
  match selected:
    case True{}: host_stream_step_calculation(source)
    case False{}: Model.failure("Unknown browser model operation: " ++ operation)

def meaning_stream(selected: Bool, +operation: String, source: J.Json) -> J.Json:
  match selected:
    case True{}: stream_step_calculation(source)
    case False{}: meaning_host_stream(String.eq(operation, "browser.host_stream_step"), operation, source)

def meaning_link(selected: Bool, +operation: String, +source: J.Json) -> J.Json:
  match selected:
    case True{}: Model.success(link_calculation(source))
    case False{}: meaning_stream(String.eq(operation, "browser.stream_step"), operation, source)

def meaning(+operation: String, source: J.Json) -> J.Json:
  meaning_link(String.eq(operation, "browser.link"), operation, source)

law complete_correspondence:
  @operation:String -> @source:J.Json -> {run(operation, source) == meaning(operation, source) : J.Json}
