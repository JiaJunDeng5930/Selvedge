import Base
import ./TYPES.bend as T
import ./SYNTAX.bend as S
import ./DECIMAL.bend as D
import ../../bendlib/json.bend as J

type RestoredValues is Data:
  RestoredValues{locals: +List<T.Local>, views: +List<J.Field>}

def local_json(+local: T.Local) -> J.Json:
  T.Local{ +id, +schema, +value, +raw, +validation} = local
  J.Object{[J.Field{"id", J.Text{id}}, J.Field{"schema", S.schema_json(schema)}, J.Field{"value", value}]}

def locals_json(+locals: +List<T.Local>) -> +List<J.Json>:
  match locals:
    case Nil{}: Nil{}
    case Con{first, rest}: local_json(first) <> locals_json(rest)

def encode(+block: T.Block) -> J.Json:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restored} = block
  J.Object{[J.Field{"version", J.nat(1n)}, J.Field{"locals", J.Array{locals_json(locals)}}, J.Field{"views", J.Object{views}}]}

def stored_local(+entries: +List<J.Json>, +id: String) -> J.Json:
  match entries:
    case Nil{}: J.Null{}
    case Con{+first, rest}: Bool.pick(J.Json, String.eq(J.text(J.get(first, "id")), id), first, stored_local(rest, id))

def restore_admitted(+id: String, +schema: T.StateSchema, +value: J.Json, +valid: Bool) -> Result<&2, &2, String, T.Local>:
  match valid:
    case True{}: Done{T.Local{id, schema, value, S.scalar_text(value), None{}}}
    case False{}: Fail{"The saved state does not match this definition"}

def restore_local(+local: T.Local, +entry: J.Json) -> Result<&2, &2, String, T.Local>:
  T.Local{ +id, +schema, +value, +raw, +validation} = local
  restore_admitted(id, schema, J.get(entry, "value"), J.same(S.schema_json(schema), J.get(entry, "schema")) && S.schema_accepts(schema, J.get(entry, "value")))

def locals_join(+head: Result<&2, &2, String, T.Local>, +tail: Result<&2, &2, String, +List<T.Local>>) -> Result<&2, &2, String, +List<T.Local>>:
  match head tail:
    case Fail{reason} _: Fail{reason}
    case _ Fail{reason}: Fail{reason}
    case Done{first} Done{rest}: Done{first <> rest}

def restore_locals(+locals: +List<T.Local>, +entries: +List<J.Json>) -> Result<&2, &2, String, +List<T.Local>>:
  match locals:
    case Nil{}: Done{Nil{}}
    case Con{T.Local{+id, schema, value, raw, validation}, rest}:
      locals_join(restore_local(T.Local{id, schema, value, raw, validation}, stored_local(entries, id)), restore_locals(rest, entries))

def decoded(+result: Result<&2, &2, String, +List<T.Local>>, +views: J.Json) -> Result<&2, &2, String, RestoredValues>:
  match result views:
    case Fail{reason} _: Fail{reason}
    case Done{locals} J.Object{fields}: Done{RestoredValues{locals, fields}}
    case _ _: Fail{"Invalid saved view state"}

def decode_admitted(+valid: Bool, +locals: +List<T.Local>, +payload: J.Json) -> Result<&2, &2, String, RestoredValues>:
  match valid:
    case False{}: Fail{"Unsupported or corrupt local snapshot"}
    case True{}: decoded(restore_locals(locals, J.items(J.get(payload, "locals"))), J.get(payload, "views"))

def encoded_length(+result: Result<&2, &2, String, String>) -> Nat:
  match result:
    case Done{text}: String.length(text)
    case Fail{reason}: 262145n

def payload_fits(+payload: J.Json) -> Bool:
  Nat.is_le(encoded_length(J.show(payload)), 262144n)

def decode(+locals: +List<T.Local>, +payload: J.Json) -> Result<&2, &2, String, RestoredValues>:
  decode_admitted(J.same(J.get(payload, "version"), J.nat(1n)) && Nat.is_eq(List.length(&2, T.Local, locals), List.length(&2, J.Json, J.items(J.get(payload, "locals")))) && payload_fits(payload), locals, payload)
def required_keys(+keys: +List<String>, +fields: +List<J.Field>) -> Bool:
  match keys:
    case Nil{}: True{}
    case Con{first, rest}: S.field_has(fields, first) && required_keys(rest, fields)

def exact_object(+value: J.Json, +keys: +List<String>) -> Bool:
  match value:
    case J.Object{+fields}: Nat.is_eq(List.length(&2, J.Field, fields), List.length(&2, String, keys)) && required_keys(keys, fields)
    case _: False{}

def local_ids(+locals: +List<T.Local>) -> +List<String>:
  match locals:
    case Nil{}: Nil{}
    case Con{T.Local{id, schema, value, raw, validation}, rest}: id <> local_ids(rest)

def entries_valid(+entries: +List<J.Json>, +ids: +List<String>, +seen: +List<String>) -> Bool:
  match entries:
    case Nil{}: Nat.is_eq(List.length(&2, String, ids), List.length(&2, String, seen))
    case Con{J.Object{+fields}, rest}:
      exact_object(J.Object{fields}, ["id", "schema", "value"]) && S.string_seen(ids, J.text(J.find(fields, "id"))) && Bool.not(S.string_seen(seen, J.text(J.find(fields, "id")))) && entries_valid(rest, ids, J.text(J.find(fields, "id")) <> seen)
    case _: False{}

def bounded_number(+value: J.Json, +lower: String, +upper: String) -> Bool:
  match value:
    case J.Number{+number}: S.decimal_bool(D.compare(">=", number, lower)) && S.decimal_bool(D.compare("<=", number, upper))
    case _: False{}

def graph_field(+key: String, +value: J.Json) -> Bool:
  match key value:
    case "zoom" _: bounded_number(value, "25", "200") && D.integral(S.scalar_text(value))
    case "panX" _: bounded_number(value, "0", "2000") && D.integral(S.scalar_text(value))
    case "panY" _: bounded_number(value, "0", "2000") && D.integral(S.scalar_text(value))
    case "fitWidth" J.Boolean{boolean}: True{}
    case "selection" J.Text{text}: Nat.is_le(String.length(text), 1024n)
    case _ _: False{}

def table_field(+key: String, +value: J.Json, +columns: +List<String>) -> Bool:
  match key value:
    case "page" _: bounded_number(value, "0", "40") && D.integral(S.scalar_text(value))
    case "direction" J.Text{text}: String.eq(text, "asc") || String.eq(text, "desc")
    case "sort" J.Text{text}: String.is_empty(text) || S.string_seen(columns, text)
    case _ _: False{}

def view_field_kind(+kind: String, +key: String, +value: J.Json, +columns: +List<String>) -> Bool:
  match kind:
    case "graph-view": graph_field(key, value)
    case "table": table_field(key, value, columns)
    case _: False{}

def view_fields(+fields: +List<J.Field>, +descriptor: J.Json, +seen: +List<String>) -> Bool:
  match fields:
    case Nil{}: True{}
    case Con{J.Field{+key, +value}, rest}:
      Bool.not(S.string_seen(seen, key)) && view_field_kind(J.text(J.get(descriptor, "kind")), key, value, S.strings(J.items(J.get(descriptor, "columns")))) && view_fields(rest, descriptor, key <> seen)

def view_record(+value: J.Json, +descriptor: J.Json) -> Bool:
  match value:
    case J.Object{fields}: view_fields(fields, descriptor, Nil{})
    case _: False{}

def views_valid(+fields: +List<J.Field>, +allowed: +List<J.Field>, +seen: +List<String>) -> Bool:
  match fields:
    case Nil{}: True{}
    case Con{J.Field{+key, value}, rest}: S.field_has(allowed, key) && Bool.not(S.string_seen(seen, key)) && view_record(value, J.find(allowed, key)) && views_valid(rest, allowed, key <> seen)

def saved_views_valid(+value: J.Json, +allowed: +List<J.Field>) -> Bool:
  match value:
    case J.Object{+fields}: Nat.is_le(List.length(&2, J.Field, fields), 4096n) && views_valid(fields, allowed, Nil{})
    case _: False{}

def saved_locals_valid(+value: J.Json, +ids: +List<String>) -> Bool:
  match value:
    case J.Array{entries}: entries_valid(entries, ids, Nil{})
    case _: False{}

def decode_with_views(+locals: +List<T.Local>, +payload: J.Json, +allowed: +List<J.Field>) -> Result<&2, &2, String, RestoredValues>:
  decode_admitted(exact_object(payload, ["version", "locals", "views"]) && J.same(J.get(payload, "version"), J.nat(1n)) &&
    saved_locals_valid(J.get(payload, "locals"), local_ids(locals)) && saved_views_valid(J.get(payload, "views"), allowed) &&
    payload_fits(payload), locals, payload)

def local_values_admitted(+valid: Bool, +locals: +List<T.Local>, +payload: J.Json) -> Result<&2, &2, String, +List<T.Local>>:
  match valid:
    case False{}: Fail{"Unsupported or corrupt local snapshot"}
    case True{}: restore_locals(locals, J.items(J.get(payload, "locals")))

def decode_local_values(+locals: +List<T.Local>, +payload: J.Json) -> Result<&2, &2, String, +List<T.Local>>:
  local_values_admitted(exact_object(payload, ["version", "locals", "views"]) && J.same(J.get(payload, "version"), J.nat(1n)) &&
    saved_locals_valid(J.get(payload, "locals"), local_ids(locals)) && payload_fits(payload), locals, payload)

def prevalidated_views(+locals: +List<T.Local>, +payload: J.Json, +allowed: +List<J.Field>, +valid: Bool) -> Result<&2, &2, String, RestoredValues>:
  match valid:
    case False{}: Fail{"Invalid saved view state"}
    case True{}: decoded(Done{locals}, J.get(payload, "views"))

def decode_prevalidated_views(+locals: +List<T.Local>, +payload: J.Json, +allowed: +List<J.Field>) -> Result<&2, &2, String, RestoredValues>:
  prevalidated_views(locals, payload, allowed, saved_views_valid(J.get(payload, "views"), allowed))
