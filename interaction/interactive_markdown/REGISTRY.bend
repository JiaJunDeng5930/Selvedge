import Base
import ../../bendlib/string-equality.bend as SafeText
import ./TYPES.bend as T
import ./PARSER.bend as P
import ./SYNTAX.bend as S
import ./SCHEMA.bend as Schema
import ./EXPRESSION.bend as E
import ../../bendlib/json.bend as J

type Prepared is Data:
  Prepared{locals: +List<T.Local>, env: +List<J.Field>, requests: +List<T.SourceRequest>,
    diagnostics: +List<T.Diagnostic>, seen: +List<String>, visual: Bool, fatal: Bool, remaining: Nat, cut: Nat}

type StructuralItem is Data:
  StructuralItem{element: T.Element, scope: String, depth: Nat}

type Structure is Data:
  Structure{cut: Nat, diagnostics: +List<T.Diagnostic>, failed: Bool}

type PrefixTask is Data:
  PrefixVisit{element: T.Element}
  PrefixClose{tag: String, attributes: +List<T.Attribute>, closed: Bool, before: +List<T.Element>}






def find_local(+locals: +List<T.Local>, +id: String) -> Maybe<&2, T.Local>:
  match locals:
    case Nil{}: None{}
    case Con{T.Local{+key, schema, value, raw, validation}, rest}:
      Bool.pick(Maybe<&2, T.Local>, String.eq(key, id), Some{T.Local{key, schema, value, raw, validation}}, find_local(rest, id))

def local_value(+found: Maybe<&2, T.Local>) -> J.Json:
  match found:
    case None{}: J.Null{}
    case Some{T.Local{id, schema, value, raw, validation}}: value

def local_schema(+found: Maybe<&2, T.Local>) -> Maybe<&2, T.StateSchema>:
  match found:
    case None{}: None{}
    case Some{T.Local{id, schema, value, raw, validation}}: Some{schema}

def local_default(+id: String, +schema: T.StateSchema) -> T.Local:
  T.StateSchema{ +kind, +initial, +minimum, +maximum, +step, +options, +max_length} = schema
  T.Local{id, T.StateSchema{kind, initial, minimum, maximum, step, options, max_length}, initial, S.scalar_text(initial), None{}}

def reuse_local(+found: Maybe<&2, T.Local>, +id: String, +schema: T.StateSchema) -> T.Local:
  match found:
    case None{}: local_default(id, schema)
    case Some{T.Local{key, +old, value, raw, validation}}:
      Bool.pick(T.Local, S.same_schema(old, schema), T.Local{key, old, value, raw, validation}, local_default(id, schema))

def add_diagnostic(+prepared: Prepared, +path: String, +reason: String, +fatal: Bool) -> Prepared:
  Prepared{ +locals, +env, +requests, +diagnostics, +seen, +visual, +failed, +remaining, +cut} = prepared
  Prepared{locals, env, requests, T.Diagnostic{path, reason, fatal} <> diagnostics, seen, visual, failed || fatal, remaining, cut}

def add_local(+local: T.Local, +prepared: Prepared) -> Prepared:
  T.Local{ +id, +schema, +value, +raw, +validation} = local
  Prepared{ +locals, +env, +requests, +diagnostics, +seen, +visual, +fatal, +remaining, +cut} = prepared
  Prepared{T.Local{id, schema, value, raw, validation} <> locals, S.field_set(env, id, value), requests, diagnostics, id <> seen, visual, fatal, remaining, cut}

def state_parsed(+result: Result<&2, &2, String, T.StateSchema>, +id: String, +previous: +List<T.Local>, +prepared: Prepared) -> Prepared:
  match result:
    case Fail{reason}: add_diagnostic(prepared, id, reason, True{})
    case Done{+schema}: add_local(reuse_local(find_local(previous, id), id, schema), prepared)

def state_declaration(+id: String, +attrs: +List<T.Attribute>, +previous: +List<T.Local>, +prepared: Prepared) -> Prepared:
  state_parsed(Schema.from_attributes(attrs), id, previous, prepared)

def derive_parsed(+prepared: Prepared, +result: Result<&2, &2, String, J.Json>, +id: String) -> Prepared:
  Prepared{ +locals, +env, +requests, +diagnostics, +seen, +visual, +fatal, +remaining, +cut} = prepared
  match result:
    case Fail{reason}:
      Prepared{locals, S.field_set(S.field_set(env, "@errors/" ++ id, J.Text{reason}), id, J.Null{}), requests, T.Diagnostic{id, reason, False{}} <> diagnostics, id <> seen, visual, fatal, remaining, cut}
    case Done{value}: Prepared{locals, S.field_set(env, id, value), requests, diagnostics, id <> seen, visual, fatal, remaining, cut}

def derive_evaluated(+prepared: Prepared, +evaluated: E.Evaluation, +id: String) -> Prepared:
  Prepared{ +locals, +env, +requests, +diagnostics, +seen, +visual, +fatal, +old_remaining, +cut} = prepared
  E.Evaluation{ +result, +remaining} = evaluated
  derive_parsed(Prepared{locals, env, requests, diagnostics, seen, visual, fatal, remaining, cut}, result, id)

def derive_expression(+prepared: Prepared, +parsed: Result<&2, &2, String, E.Expr>, +id: String) -> Prepared:
  Prepared{ +locals, +env, +requests, +diagnostics, +seen, +visual, +fatal, +remaining, +cut} = prepared
  match parsed:
    case Fail{reason}: derive_parsed(Prepared{locals, env, requests, diagnostics, seen, visual, fatal, remaining, cut}, Fail{reason}, id)
    case Done{expr}: derive_evaluated(Prepared{locals, env, requests, diagnostics, seen, visual, fatal, remaining, cut}, E.evaluate_bounded(expr, env, remaining), id)

def derive_found(+prepared: Prepared, +found: Maybe<&2, String>, +id: String) -> Prepared:
  match found:
    case None{}: add_diagnostic(prepared, id, "A derive requires value", True{})
    case Some{text}: derive_expression(prepared, E.parse(text), id)

def source_natural(+value: Maybe<&2, Nat>, +text: String) -> Maybe<&2, Nat>:
  match value:
    case None{}: None{}
    case Some{+id}: Bool.pick(Maybe<&2, Nat>, Nat.is_le(String.length(text), 64n) && String.eq(Nat.show(id), text), Some{id}, None{})
def source_id(+value: J.Json) -> Maybe<&2, Nat>:
  match value:
    case J.Number{text}: Nat.read(text)
    case J.Text{text}: source_natural(Nat.read(text), text)
    case _: None{}

def source_admitted(+prepared: Prepared, +graph: Maybe<&2, Nat>, +valid: Bool, +owner: T.Owner, +id: String, +sources: +List<J.Field>) -> Prepared:
  Prepared{ +locals, +env, +requests, +diagnostics, +seen, +visual, +fatal, +remaining, +cut} = prepared
  match graph valid:
    case Some{graph} True{}:
      Prepared{locals, S.field_set(env, id, J.find(sources, id)), T.SourceRequest{owner, id, graph} <> requests, diagnostics, id <> seen, visual, fatal, remaining, cut}
    case _ _: add_diagnostic(Prepared{locals, env, requests, diagnostics, seen, visual, fatal, remaining, cut}, id, "Invalid task-graph source declaration", True{})

def source_declaration(+attrs: +List<T.Attribute>, +owner: T.Owner, +id: String, +sources: +List<J.Field>, +prepared: Prepared) -> Prepared:
  source_admitted(prepared, source_id(S.literal_attribute(attrs, "graph-id", J.Null{})),
    String.eq(J.text(S.literal_attribute(attrs, "kind", J.Null{})), "task-graph") && String.eq(J.text(S.literal_attribute(attrs, "mode", J.Null{})), "live"),
    owner, id, sources)

def dataset_unchecked(+attrs: +List<T.Attribute>, +id: String, +prepared: Prepared) -> Prepared:
  Prepared{ +locals, +env, +requests, +diagnostics, +seen, +visual, +fatal, +remaining, +cut} = prepared
  Prepared{locals, S.field_set(S.field_set(env, "@columns/" ++ id, S.literal_attribute(attrs, "columns", J.Null{})), id, J.Array{Nil{}}), requests, diagnostics, id <> seen, visual, fatal, remaining, cut}

def row_values(+existing: J.Json, +value: J.Json, +key: String, +duplicate: Bool) -> Result<&2, &2, String, J.Json>:
  match existing value duplicate:
    case J.Array{items} J.Object{fields} False{}: Done{J.Array{List.append(&2, J.Json, items, [J.Object{fields}])}}
    case _ _ _: Fail{"A dataset row requires a unique key and literal record"}

def row_key_exists(+values: +List<J.Json>, +key: String) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{+first, rest}: SafeText.string_equal(J.text(J.get(first, "@row-key")), key) || row_key_exists(rest, key)

def row_saved(+prepared: Prepared, +result: Result<&2, &2, String, J.Json>, +id: String, +key: String) -> Prepared:
  Prepared{ +locals, +env, +requests, +diagnostics, +seen, +visual, +fatal, +remaining, +cut} = prepared
  match result:
    case Fail{reason}: add_diagnostic(Prepared{locals, env, requests, diagnostics, seen, visual, fatal, remaining, cut}, id, reason, False{})
    case Done{value}: Prepared{locals, S.field_set(S.field_set(env, id, value), "@row-keys/" ++ id, J.Array{List.append(&2, J.Json, J.items(J.find(env, "@row-keys/" ++ id)), [J.Text{key}])}), requests, diagnostics, seen, visual, fatal, remaining, cut}

def record_has_columns(+columns: +List<J.Json>, +fields: +List<J.Field>) -> Bool:
  match columns:
    case Nil{}: True{}
    case Con{J.Text{name}, rest}: S.field_has(fields, name) && record_has_columns(rest, fields)
    case _: False{}

def row_schema(+value: J.Json, +columns: J.Json) -> Bool:
  match value columns:
    case J.Object{+fields} J.Array{+names}: Nat.is_eq(List.length(&2, J.Field, fields), List.length(&2, J.Json, names)) && record_has_columns(names, fields)
    case _ _: False{}

def checked_row_values(+existing: J.Json, +value: J.Json, +key: String, +duplicate: Bool, +columns: J.Json) -> Result<&2, &2, String, J.Json>:
  Bool.pick(Result<&2, &2, String, J.Json>, row_schema(value, columns), row_values(existing, value, key, duplicate), Fail{"Row fields must exactly match the dataset columns"})

def row_key_seen(+values: +List<J.Json>, +key: String) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{first, rest}: SafeText.string_equal(J.text(first), key) || row_key_seen(rest, key)
def row_declaration(+attrs: +List<T.Attribute>, +prepared: Prepared) -> Prepared:
  Prepared{ +locals, +env, +requests, +diagnostics, +seen, +visual, +fatal, +remaining, +cut} = prepared
  +id = J.text(S.literal_attribute(attrs, "dataset", J.Null{}))
  +key = J.text(S.literal_attribute(attrs, "key", J.Null{}))
  +existing = J.find(env, id)
  row_saved(Prepared{locals, env, requests, diagnostics, seen, visual, fatal, remaining, cut}, checked_row_values(existing, S.literal_attribute(attrs, "value", J.Null{}), key, row_key_seen(J.items(J.find(env, "@row-keys/" ++ id)), key) || String.is_empty(key) || Nat.is_le(4096n, List.length(&2, J.Json, J.items(existing))), J.find(env, "@columns/" ++ id)), id, key)

def declared(+tag: String) -> Bool:
  String.eq(tag, "state") || String.eq(tag, "derive") || String.eq(tag, "source") || String.eq(tag, "dataset")

def dataset_checked(+attrs: +List<T.Attribute>, +id: String, +prepared: Prepared, +valid: Bool) -> Prepared:
  match valid:
    case True{}: dataset_unchecked(attrs, id, prepared)
    case False{}: add_diagnostic(prepared, id, "Dataset columns must be a nonempty unique list of strings", True{})

def dataset_columns(+value: J.Json) -> Bool:
  match value:
    case J.Array{+values}: Bool.not(List.is_empty(&2, J.Json, values)) && Nat.is_le(List.length(&2, J.Json, values), 64n) && Schema.strings_valid(values, Nil{})
    case _: False{}

def dataset_declaration(+attrs: +List<T.Attribute>, +id: String, +prepared: Prepared) -> Prepared:
  dataset_checked(attrs, id, prepared, dataset_columns(S.literal_attribute(attrs, "columns", J.Null{})))

def declaration_allowed(+prepared: Prepared, +owner: T.Owner, +tag: String, +attrs: +List<T.Attribute>, +id: String, +previous: +List<T.Local>, +sources: +List<J.Field>, +valid: Bool) -> Prepared:
  match tag valid:
    case _ False{}: add_diagnostic(prepared, id, "A declaration has an invalid/duplicate id or follows visual content", True{})
    case "state" True{}: state_declaration(id, attrs, previous, prepared)
    case "derive" True{}: derive_found(prepared, S.source(attrs, "value"), id)
    case "source" True{}: source_declaration(attrs, owner, id, sources, prepared)
    case "dataset" True{}: dataset_declaration(attrs, id, prepared)
    case _ _: prepared

def allowed_attribute(+tag: String, +name: String) -> Bool:
  match tag:
    case "state": S.string_seen(["id", "type", "initial", "min", "max", "step", "options", "max-length"], name)
    case "derive": S.string_seen(["id", "value"], name)
    case "source": S.string_seen(["id", "kind", "graph-id", "mode"], name)
    case "dataset": S.string_seen(["id", "columns"], name)
    case _: False{}

def literal_valid(+result: Result<&2, &2, String, J.Json>) -> Bool:
  match result:
    case Done{value}: True{}
    case Fail{reason}: False{}

# DEFENSE: Model-authored declarations can contain unknown attributes or nonliteral configuration; reject those declarations before creating local state or sources.
def declaration_attributes(+tag: String, +attrs: +List<T.Attribute>) -> Bool:
  match attrs:
    case Nil{}: True{}
    case Con{T.Attribute{+name, source}, rest}: allowed_attribute(tag, name) &&
      (String.eq(tag, "derive") && String.eq(name, "value") || literal_valid(S.literal(source))) && declaration_attributes(tag, rest)
def prepare_tag(+prepared: Prepared, +declaration: Bool, +tag: String, +attrs: +List<T.Attribute>, +owner: T.Owner, +previous: +List<T.Local>, +sources: +List<J.Field>, +id: String) -> Prepared:
  Prepared{ +locals, +env, +requests, +diagnostics, +seen, +visual, +fatal, +remaining, +cut} = prepared
  match declaration tag:
    case True{} _: declaration_allowed(Prepared{locals, env, requests, diagnostics, seen, visual, fatal, remaining, cut}, owner, tag, attrs, id, previous, sources,
      Bool.not(visual) && declaration_attributes(tag, attrs) && S.valid_binding_id(id) && Bool.not(S.string_seen(seen, id)) && Nat.is_lt(List.length(&2, String, seen), 128n))
    case False{} "row": row_declaration(attrs, Prepared{locals, env, requests, diagnostics, seen, visual, fatal, remaining, cut})
    case False{} _: Prepared{locals, env, requests, diagnostics, seen, True{}, fatal, remaining, cut}

def prepare_element(+element: T.Element, +owner: T.Owner, +previous: +List<T.Local>, +sources: +List<J.Field>, +prepared: Prepared) -> Prepared:
  T.Element{ +tag, +attrs, +children, +closed} = element
  Prepared{ +locals, +env, +requests, +diagnostics, +seen, +visual, +fatal, +remaining, +cut} = prepared
  Bool.pick(Prepared, fatal, Prepared{locals, env, requests, diagnostics, seen, visual, fatal, remaining, cut}, prepare_tag(Prepared{locals, env, requests, diagnostics, seen, visual, fatal, remaining, cut}, declared(tag), tag, attrs, owner, previous, sources, J.text(S.literal_attribute(attrs, "id", J.Null{}))))

def declaration_cut(+prepared: Prepared, +index: Nat) -> Prepared:
  Prepared{ +locals, +env, +requests, +diagnostics, +seen, +visual, +fatal, +remaining, +cut} = prepared
  Prepared{locals, env, requests, diagnostics, seen, visual, fatal, remaining, Bool.pick(Nat, fatal && Nat.is_lt(index, cut), index, cut)}

def element_count(+fuel: Nat, +todo: +List<T.Element>, +count: Nat) -> Nat:
  match fuel todo:
    case _ Nil{}: count
    case 0n _: count
    case 1n+f Con{T.Element{tag, attrs, children, closed}, rest}:
      element_count(f, List.append(&2, T.Element, children, rest), 1n+count)

def prepare_list(+fuel: Nat, +elements: +List<T.Element>, +owner: T.Owner, +previous: +List<T.Local>, +sources: +List<J.Field>, +prepared: Prepared, +index: Nat) -> Prepared:
  match fuel elements:
    case _ Nil{}: prepared
    case 0n _: declaration_cut(add_diagnostic(prepared, "ui", "Declaration processing exceeds its limit", True{}), index)
    case 1n+f Con{+first, rest}:
      prepare_list(f, rest, owner, previous, sources, declaration_cut(prepare_element(first, owner, previous, sources, prepared), index), (index + element_count(1024n, [first], 0n) : Nat))

def children(+roots: +List<T.Element>) -> +List<T.Element>:
  match roots:
    case Con{T.Element{"ui", attrs, children, closed}, Nil{}}: children
    case _: Nil{}

def root_valid(+roots: +List<T.Element>) -> Bool:
  match roots:
    case Con{T.Element{"ui", attrs, children, closed}, Nil{}}: S.valid_id(J.text(S.literal_attribute(attrs, "id", J.Null{})))
    case _: False{}

def terminal_ending(+ending: T.Ending) -> Bool:
  match ending:
    case T.Open{}: False{}
    case _: True{}
def prefix_visits(+elements: +List<T.Element>) -> +List<PrefixTask>:
  match elements:
    case Nil{}: Nil{}
    case Con{first, rest}: PrefixVisit{first} <> prefix_visits(rest)

def prefix_loop(+fuel: Nat, +left: Nat, +stopped: Bool, +tasks: +List<PrefixTask>, +reversed: +List<T.Element>) -> +List<T.Element>:
  match fuel left tasks:
    case _ _ Nil{}: List.reverse(&2, T.Element, reversed)
    case 0n _ _: List.reverse(&2, T.Element, reversed)
    case 1n+f 0n Con{PrefixVisit{element}, rest}: prefix_loop(f, 0n, True{}, rest, reversed)
    case 1n+f 1n+r Con{PrefixVisit{T.Element{tag, attributes, children, closed}}, rest}:
      prefix_loop(f, r, stopped, List.append(&2, PrefixTask, prefix_visits(children), PrefixClose{tag, attributes, closed, reversed} <> rest), Nil{})
    case 1n+f _ Con{PrefixClose{tag, attributes, closed, before}, rest}:
      prefix_loop(f, left, stopped, rest, T.Element{tag, attributes, List.reverse(&2, T.Element, reversed), closed && Bool.not(stopped)} <> before)

def prefix_elements(+elements: +List<T.Element>, +cut: Nat) -> +List<T.Element>:
  prefix_loop(4096n, cut, False{}, prefix_visits(elements), Nil{})

def definition_charge(+syntax: T.Syntax) -> Nat:
  T.Syntax{roots, frames, tail, failed, sealed, accepted, characters, diagnostic} = syntax
  (2n * characters : Nat)

def prepared_root(+structure: Structure, +block: T.Block, +valid: Bool, +roots: +List<T.Element>) -> Prepared:
  Structure{+cut, diagnostics, failed} = structure
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restored} = block
  match valid roots:
    case False{} Nil{}: Bool.pick(Prepared, closed || terminal_ending(ending), Prepared{locals, Nil{}, Nil{}, [T.Diagnostic{"ui", "The document ended without a ui root", True{}}], Nil{}, False{}, True{}, 0n, 0n}, Prepared{locals, Nil{}, Nil{}, Nil{}, Nil{}, False{}, False{}, 0n, 0n})
    case False{} _: Prepared{locals, Nil{}, Nil{}, [T.Diagnostic{"ui", "Invalid root or exhausted definition budget", True{}}], Nil{}, False{}, True{}, 0n, 0n}
    case True{} _: prepare_list(1024n, prefix_elements(children(roots), cut), owner, locals, sources, Prepared{Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, False{}, False{}, Nat.sub(100000n, definition_charge(syntax)), cut}, 0n)

def structural_children(+elements: +List<T.Element>, +scope: String, +depth: Nat) -> +List<StructuralItem>:
  match elements:
    case Nil{}: Nil{}
    case Con{first, rest}: StructuralItem{first, scope, depth} <> structural_children(rest, scope, depth)

def structural_scope(+scope: String, +tag: String, +id: String) -> String:
  Bool.pick(String, String.eq(tag, "each") || String.eq(tag, "node-template") || String.eq(tag, "graph-view"), scope ++ "/template/" ++ id, scope)

def syntax_declaration(+tag: String) -> Bool:
  declared(tag) || String.eq(tag, "row")

def structural_has_id(+tag: String) -> Bool:
  Bool.not(syntax_declaration(tag) || String.eq(tag, "node-template"))

def structure_checked(+result: Structure, +seen: +List<String>, +scope: String, +depth: Nat, +tag: String, +id: String, +index: Nat) -> Structure:
  Structure{+cut, +diagnostics, +failed} = result
  Bool.pick(Structure, failed, Structure{cut, diagnostics, failed},
    Bool.pick(Structure, syntax_declaration(tag) && Bool.not(Nat.is_eq(depth, 1n)),
      Structure{index, [T.Diagnostic{id, "Declarations are allowed only directly inside ui", True{}}], True{}},
      Bool.pick(Structure, structural_has_id(tag) && (Bool.not(S.valid_id(id)) || S.string_seen(seen, scope ++ "/" ++ id)),
        Structure{index, [T.Diagnostic{id, "Component ids must be valid and unique in their lexical scope", True{}}], True{}}, result)))

def structure_scan(+fuel: Nat, +todo: +List<StructuralItem>, +seen: +List<String>, +index: Nat, +result: Structure) -> Structure:
  match fuel todo:
    case _ Nil{}: result
    case 0n _: Structure{index, [T.Diagnostic{"ui", "Structural validation exceeds its limit", True{}}], True{}}
    case 1n+f Con{StructuralItem{T.Element{+tag, +attrs, children, closed}, +scope, +depth}, rest}:
      +id: String = J.text(S.literal_attribute(attrs, "id", J.Null{}))
      structure_scan(f, List.append(&2, StructuralItem, structural_children(children, structural_scope(scope, tag, id), 1n+depth), rest),
        (scope ++ "/" ++ id) <> seen, 1n+index,
        structure_checked(result, seen, scope, depth, tag, id, index))

def structure_finalize(+prepared: Prepared, +structure: Structure) -> Prepared:
  Prepared{ +locals, +env, +requests, +diagnostics, +seen, +visual, +fatal, +remaining, +cut} = prepared
  Structure{structural_cut, structural_diagnostics, failed} = structure
  Prepared{locals, env, requests, List.append(&2, T.Diagnostic, diagnostics, structural_diagnostics), seen, visual, fatal || failed, remaining, cut}

def definition_budget(+block: T.Block) -> Bool:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restored} = block
  Nat.is_lt(definition_charge(syntax), 100000n)

def prepare_structured(+block: T.Block, +roots: +List<T.Element>, +structure: Structure) -> Prepared:
  structure_finalize(prepared_root(structure, block, root_valid(roots) && definition_budget(block), roots), structure)

def prepare(+block: T.Block) -> Prepared:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restored} = block
  +roots = P.elements(syntax)
  prepare_structured(block, roots, structure_scan(1024n, structural_children(children(roots), "ui", 1n), Nil{}, 0n, Structure{1024n, Nil{}, False{}}))

def prepared_locals(+prepared: Prepared) -> +List<T.Local>:
  Prepared{ +locals, +env, +requests, +diagnostics, +seen, +visual, +fatal, +remaining, +cut} = prepared
  locals

def prepared_env(+prepared: Prepared) -> +List<J.Field>:
  Prepared{ +locals, +env, +requests, +diagnostics, +seen, +visual, +fatal, +remaining, +cut} = prepared
  env

def prepared_requests(+prepared: Prepared) -> +List<T.SourceRequest>:
  Prepared{ +locals, +env, +requests, +diagnostics, +seen, +visual, +fatal, +remaining, +cut} = prepared
  requests

def prepared_diagnostics(+prepared: Prepared) -> +List<T.Diagnostic>:
  Prepared{ +locals, +env, +requests, +diagnostics, +seen, +visual, +fatal, +remaining, +cut} = prepared
  diagnostics

def prepared_fatal(+prepared: Prepared) -> Bool:
  Prepared{ +locals, +env, +requests, +diagnostics, +seen, +visual, +fatal, +remaining, +cut} = prepared
  fatal

def prepared_remaining(+prepared: Prepared) -> Nat:
  Prepared{ +locals, +env, +requests, +diagnostics, +seen, +visual, +fatal, +remaining, +cut} = prepared
  remaining


def prepared_cut(+prepared: Prepared) -> Nat:
  Prepared{ +locals, +env, +requests, +diagnostics, +seen, +visual, +fatal, +remaining, +cut} = prepared
  cut

def accepted_elements(+block: T.Block, +prepared: Prepared) -> +List<T.Element>:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restored} = block
  prefix_elements(children(P.elements(syntax)), prepared_cut(prepared))
