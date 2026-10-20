import Base
import ../DOMAIN.bend as D
import ./SYNTAX.bend as Native
import ../../bendlib/json.bend as J
import ../../bendlib/stdlib.bend as Std
import ../transport/schema.bend as Schema

# Discovery observes the frozen task catalog. Loading a definition neither
# grants a capability nor records a second source of task execution state.
def schema() -> J.Json:
  Schema.object([
    J.Field{"query", D.string_schema("Case-insensitive keywords in the tool name and description. Omit to browse the directory.")},
    J.Field{"names", J.Object{[J.Field{"type", J.Text{"array"}}, J.Field{"description", J.Text{"Exact public tool names; bypasses query, offset and limit. Unknown names are returned in missing."}}, J.Field{"items", D.string_schema("Exact public tool name")}] }},
    J.Field{"limit", D.integer_schema("Maximum search results per page; defaults to 5", 1, 20)},
    J.Field{"offset", D.integer_schema("Search result offset; defaults to 0", 0, 4294967295)}], Nil{})

def external(source: D.Source) -> Bool:
  match source:
    case D.Harness{program}: False{}
    case _: True{}

def definition(tool: D.Tool) -> J.Json:
  D.Tool{name, description, parameters, source} = tool
  J.Object{[J.Field{"name", J.Text{name}}, J.Field{"description", J.Text{description}}, J.Field{"parameters", parameters}]}

def contains(names: +List<J.Json>, +name: String) -> Bool:
  match names:
    case Nil{}: False{}
    case Con{J.Text{value}, rest}: String.eq(value, name) || contains(rest, name)
    case Con{other, rest}: contains(rest, name)

def keywords(terms: +List<String>, +text: String) -> Bool:
  match terms:
    case Nil{}: True{}
    case Con{term, rest}: String.contains(text, term) && keywords(rest, text)

def selected_names(exact: Bool, terms: +List<String>, names: +List<J.Json>, +name: String, description: String) -> Bool:
  match exact:
    case True{}: contains(names, name)
    case False{}: keywords(terms, String.to_lower(name ++ " " ++ description))

def selected(+tool: D.Tool, terms: +List<String>, +names: +List<J.Json>) -> Bool:
  D.Tool{+name, description, parameters, +source} = tool
  external(source) && selected_names(Bool.not(List.is_empty(&2, J.Json, names)), terms, names, name, description)

def retained(include: Bool, tool: D.Tool, rest: +List<D.Tool>) -> +List<D.Tool>:
  match include:
    case True{}: tool <> rest
    case False{}: rest

def matching(tools: +List<D.Tool>, +terms: +List<String>, +names: +List<J.Json>) -> +List<D.Tool>:
  match tools:
    case Nil{}: Nil{}
    case Con{+tool, rest}: retained(selected(tool, terms, names), tool, matching(rest, terms, names))

def known(tools: +List<D.Tool>, +name: String) -> Bool:
  match tools:
    case Nil{}: False{}
    case Con{D.Tool{actual, description, parameters, source}, rest}:
      (String.eq(actual, name) && external(source)) || known(rest, name)

def missing_name(found: Bool, name: J.Json, rest: +List<J.Json>) -> +List<J.Json>:
  match found:
    case True{}: rest
    case False{}: name <> rest

def missing(names: +List<J.Json>, +tools: +List<D.Tool>) -> +List<J.Json>:
  match names:
    case Nil{}: Nil{}
    case Con{+name, rest}: missing_name(known(tools, J.text(name)), name, missing(rest, tools))

def page(exact: Bool, matches: +List<D.Tool>, offset: Nat, limit: Nat) -> +List<D.Tool>:
  match exact:
    case True{}: matches
    case False{}: List.take(&2, D.Tool, List.drop(&2, D.Tool, matches, offset), limit)

def result(+tools: +List<D.Tool>, +arguments: J.Json) -> J.Json:
  +names = J.items(J.get(arguments, "names"))
  +exact = Bool.not(List.is_empty(&2, J.Json, names))
  +matches = matching(tools, String.split(String.to_lower(String.trim(J.text(J.get(arguments, "query")))), ' '), names)
  +offset = J.natural_or(J.natural(J.get(arguments, "offset")), 0n)
  +limit = J.natural_or(J.natural(J.get(arguments, "limit")), 5n)
  +count = List.length(&2, D.Tool, matches)
  J.Object{[J.Field{"tools", J.Array{Std.map(~D.Tool, ~J.Json, ~definition, page(exact, matches, offset, limit))}},
    J.Field{"missing", J.Array{missing(names, tools)}}, J.Field{"total_matches", J.nat(count)},
    J.Field{"has_more", J.Boolean{Bool.not(exact) && Nat.is_lt(Nat.add(offset, limit), count)}}]}

def discover(tools: +List<D.Tool>, arguments: J.Json) -> J.Json:
  result(tools, arguments)

# Full external schemas live at their committed tool-result position. These
# declarations stay unchanged when discovery appends results to the history.
def deferred_parameters() -> J.Json:
  J.Object{[J.Field{"type", J.Text{"object"}}, J.Field{"properties", J.Object{Nil{}}}, J.Field{"additionalProperties", J.Boolean{True{}}}]}

def resident(tool: J.Json) -> Bool:
  String.eq(J.text(J.get(J.get(tool, "source"), "kind")), "native")

def presented_parameters(native: Bool, tool: J.Json) -> J.Json:
  match native:
    case True{}: J.get(tool, "parameters")
    case False{}: deferred_parameters()

def presented_description(native: Bool, tool: J.Json) -> J.Json:
  match native:
    case True{}: J.get(tool, "description")
    case False{}: J.Text{String.take(J.text(J.get(tool, "description")), 160n) ++ " [Load parameters by this exact name through the resident discovery tool.]"}

# DEFENSE: A task may have frozen its catalog before Discover was installed;
# without that capability it must retain its original complete definitions.
def discovery_available(tools: +List<J.Json>) -> Bool:
  match tools:
    case Nil{}: False{}
    case Con{+tool, rest}:
      (resident(tool) && String.eq(J.text(J.get(J.get(J.get(tool, "source"), "program"), "kind")), "Discover")) || discovery_available(rest)

def presented(available: Bool, +tool: J.Json) -> J.Json:
  +complete = Bool.not(available) || resident(tool)
  J.Object{[J.Field{"name", J.get(tool, "name")},
    J.Field{"description", presented_description(complete, tool)},
    J.Field{"parameters", presented_parameters(complete, tool)}]}

def presentation_catalog_available(tools: +List<J.Json>, +available: Bool) -> +List<J.Json>:
  match tools:
    case Nil{}: Nil{}
    case Con{tool, rest}: presented(available, tool) <> presentation_catalog_available(rest, available)

def presentation_catalog(+tools: +List<J.Json>) -> +List<J.Json>:
  presentation_catalog_available(tools, discovery_available(tools))

law definition_name:
  @name:String -> @description:String -> @parameters:J.Json -> @source:D.Source ->
  {J.get(definition(D.Tool{name, description, parameters, source}), "name") == J.Text{name} : J.Json}

law definition_parameters:
  @name:String -> @description:String -> @parameters:J.Json -> @source:D.Source ->
  {J.get(definition(D.Tool{name, description, parameters, source}), "parameters") == parameters : J.Json}

law exact_ignores_keywords:
  @terms:+List<String> -> @names:+List<J.Json> -> @name:String -> @description:String ->
  {selected_names(True{}, terms, names, name, description) == contains(names, name) : Bool}

law exact_ignores_page:
  @matches:+List<D.Tool> -> @offset:Nat -> @limit:Nat ->
  {page(True{}, matches, offset, limit) == matches : +List<D.Tool>}

law native_not_deferred:
  @program:Native.Body -> {external(D.Harness{program}) == False{} : Bool}

law resident_parameters:
  @tool:J.Json -> {presented_parameters(True{}, tool) == J.get(tool, "parameters") : J.Json}

law deferred_parameters_independent:
  @tool:J.Json -> {presented_parameters(False{}, tool) == deferred_parameters() : J.Json}

law presentation_name:
  @available:Bool -> @tool:J.Json ->
  {J.get(presented(available, tool), "name") == J.get(tool, "name") : J.Json}

law unavailable_preserves_parameters:
  @tool:J.Json -> {J.get(presented(False{}, tool), "parameters") == J.get(tool, "parameters") : J.Json}
