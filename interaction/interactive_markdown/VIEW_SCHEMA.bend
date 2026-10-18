import Base
import ../../bendlib/string-equality.bend as SafeText
import ./TYPES.bend as T
import ./SYNTAX.bend as S
import ./EXPRESSION.bend as E
import ./DECIMAL.bend as D
import ../../bendlib/json.bend as J

# A dormant view retains only its schema. Membership, mounting and effects are
# decided by normal expansion when this exact typed path becomes present again.
type Segment is Data:
  Component{id: String}
  StringItem{key: String}
  NumberItem{key: String}
  GraphNode{identity: String}

type QuoteKind is Data:
  ComponentQuote{}
  ItemQuote{}
  NodeQuote{}

type PathStep is Data:
  PathStep{segment: Segment, rest: String}

type PathState is Data:
  PathState{rest: String, reversed: +List<Segment>, failed: Bool}

def quoted_segment(+kind: QuoteKind, +value: String) -> Segment:
  match kind:
    case ComponentQuote{}: Component{value}
    case ItemQuote{}: StringItem{value}
    case NodeQuote{}: GraphNode{value}

def quote_admitted(+kind: QuoteKind, +value: String) -> Bool:
  match kind:
    case ComponentQuote{}: S.valid_id(value)
    case _: Bool.not(String.eq(value, "")) && Nat.is_le(String.length(value), 16384n)

def quote_result(+kind: QuoteKind, +original: String, +result: Result<&2, &2, String, E.Scan>) -> Maybe<&2, PathStep>:
  match result:
    case Fail{reason}: None{}
    case Done{E.Scan{+value, +rest}}:
      E.choose((Maybe<&2, PathStep>), quote_admitted(kind, value) && SafeText.string_equal(original, J.quote(value) ++ rest),
        (_ => Some{PathStep{quoted_segment(kind, value), rest}}), (_ => None{}))

def read_quote(+kind: QuoteKind, +text: String) -> Maybe<&2, PathStep>:
  match text:
    case SCon{'"', +rest}: quote_result(kind, text, E.string_loop(16385n, E.StringScan{rest, "", 0, "", False{}}))
    case _: None{}

def scan_number(+fuel: Nat, +text: String, +acc: String) -> Maybe<&2, E.Scan>:
  match fuel text:
    case _ SNil{}: Some{E.Scan{acc, ""}}
    case _ SCon{'/', +rest}: Some{E.Scan{acc, text}}
    case 0n _: None{}
    case 1n+left SCon{+char, +rest}: scan_number(left, rest, acc ++ SCon{char, ""})

def number_result(+text: String, +rest: String, +result: Result<&2, &2, String, String>) -> Maybe<&2, PathStep>:
  match result:
    case Fail{reason}: None{}
    case Done{+canonical}:
      E.choose((Maybe<&2, PathStep>), String.eq(canonical, text) && D.integral(canonical),
        (_ => Some{PathStep{NumberItem{canonical}, rest}}), (_ => None{}))

def number_scanned(+result: Maybe<&2, E.Scan>) -> Maybe<&2, PathStep>:
  match result:
    case None{}: None{}
    case Some{E.Scan{+text, +rest}}: number_result(text, rest, D.parse(text))

def read_segment(+text: String) -> Maybe<&2, PathStep>:
  match text:
    case SCon{'/', SCon{'"', +rest}}: read_quote(ComponentQuote{}, SCon{'"', rest})
    case _:
      E.choose((Maybe<&2, PathStep>), String.starts_with(text, "/@item/s:"),
        (_ => read_quote(ItemQuote{}, String.drop(text, 9n))),
        (_ => E.choose((Maybe<&2, PathStep>), String.starts_with(text, "/@item/n:"),
          (_ => number_scanned(scan_number(12n, String.drop(text, 9n), ""))),
          (_ => E.choose((Maybe<&2, PathStep>), String.starts_with(text, "/@node/"),
            (_ => read_quote(NodeQuote{}, String.drop(text, 7n))), (_ => None{}))))))

def path_result(+result: Maybe<&2, PathStep>, +reversed: +List<Segment>) -> PathState:
  match result:
    case None{}: PathState{"", reversed, True{}}
    case Some{PathStep{segment, rest}}: PathState{rest, segment <> reversed, False{}}

def path_loop(+fuel: Nat, +state: PathState) -> Maybe<&2, +List<Segment>>:
  match fuel state:
    case _ PathState{rest, reversed, True{}}: None{}
    case _ PathState{SNil{}, reversed, False{}}: Some{List.reverse(&2, Segment, reversed)}
    case 0n _: None{}
    case 1n+left PathState{rest, reversed, False{}}: path_loop(left, path_result(read_segment(rest), reversed))

def literal_result(+result: Result<&2, &2, String, E.Expr>) -> J.Json:
  match result:
    case Done{E.Literal{value}}: value
    case _: J.Null{}

def literal_source(+source: Maybe<&2, String>) -> J.Json:
  match source:
    case None{}: J.Null{}
    case Some{text}: literal_result(E.parse(text))

def literal(+attrs: +List<T.Attribute>, +name: String) -> J.Json:
  literal_source(S.source(attrs, name))

def column_names(+elements: +List<T.Element>) -> +List<J.Json>:
  match elements:
    case Nil{}: Nil{}
    case Con{T.Element{"column", attrs, children, closed}, rest}: literal(attrs, "field") <> column_names(rest)
    case Con{other, rest}: column_names(rest)

def descriptor(+kind: String, +columns: +List<J.Json>) -> J.Json:
  J.Object{[J.Field{"kind", J.Text{kind}}, J.Field{"columns", J.Array{columns}}]}

type Work is Data:
  Work{element: T.Element, segments: +List<Segment>}

type Search is Data:
  Searching{todo: +List<Work>}
  Found{descriptor: J.Json}

def schedule(+elements: +List<T.Element>, +segments: +List<Segment>) -> +List<Work>:
  match elements:
    case Nil{}: Nil{}
    case Con{element, rest}: Work{element, segments} <> schedule(rest, segments)

def graph_children(+elements: +List<T.Element>, +segments: +List<Segment>) -> +List<Work>:
  match elements:
    case Con{T.Element{"node-template", attrs, children, closed}, Nil{}}: schedule(children, segments)
    case _: Nil{}

def descend(+tag: String, +children: +List<T.Element>, +segments: +List<Segment>) -> Search:
  match tag segments:
    case "table" Nil{}: Found{descriptor(tag, column_names(children))}
    case "graph-view" Nil{}: Found{descriptor(tag, Nil{})}
    case "each" Con{StringItem{key}, rest}: Searching{schedule(children, rest)}
    case "each" Con{NumberItem{key}, rest}: Searching{schedule(children, rest)}
    case "graph-view" Con{GraphNode{identity}, rest}: Searching{graph_children(children, rest)}
    case _ _:
      E.choose(Search, S.string_seen(["stack", "row-layout", "grid", "card", "when", "resource-view"], tag),
        (_ => Searching{schedule(children, segments)}), (_ => Searching{Nil{}}))

def search_element(+element: T.Element, +segments: +List<Segment>) -> Search:
  match element segments:
    case T.Element{+tag, +attrs, +children, closed} Con{Component{+id}, +rest}:
      E.choose(Search, String.eq(J.text(literal(attrs, "id")), id),
        (_ => descend(tag, children, rest)), (_ => Searching{Nil{}}))
    case _ _: Searching{Nil{}}

def search_join(+result: Search, +rest: +List<Work>) -> Search:
  match result:
    case Found{value}: Found{value}
    case Searching{todo}: Searching{List.append(&2, Work, todo, rest)}

def search_step(+state: Search) -> Search:
  match state:
    case Searching{Con{Work{element, segments}, rest}}: search_join(search_element(element, segments), rest)
    case other: other

def search_loop(+fuel: Nat, +state: Search) -> Maybe<&2, J.Json>:
  match fuel state:
    case _ Found{value}: Some{value}
    case _ Searching{Nil{}}: None{}
    case 0n _: None{}
    case 1n+left +state: search_loop(left, search_step(state))

def resolve_parsed(+elements: +List<T.Element>, +segments: Maybe<&2, +List<Segment>>) -> Maybe<&2, J.Json>:
  match segments:
    case None{}: None{}
    case Some{segments}: search_loop(2048n, Searching{schedule(elements, segments)})

def resolve(+elements: +List<T.Element>, +storedPath: String) -> Maybe<&2, J.Json>:
  E.choose((Maybe<&2, J.Json>), Nat.is_le(String.length(storedPath), 262144n),
    (_ => resolve_parsed(elements, path_loop(96n, PathState{storedPath, Nil{}, False{}}))), (_ => None{}))

def add_resolved(+path: String, +resolved: Maybe<&2, J.Json>, +rest: +List<J.Field>) -> +List<J.Field>:
  match resolved:
    case None{}: rest
    case Some{value}: J.Field{path, value} <> rest

def descriptors_for_paths(+elements: +List<T.Element>, +storedviews: +List<J.Field>) -> +List<J.Field>:
  match storedviews:
    case Nil{}: Nil{}
    case Con{J.Field{+path, value}, rest}: add_resolved(path, resolve(elements, path), descriptors_for_paths(elements, rest))


type StaticViewItem is Data:
  StaticViewItem{element: T.Element, parent: String}

def visible_column_names(+nodes: +List<T.ExpandedNode>) -> +List<J.Json>:
  match nodes:
    case Nil{}: Nil{}
    case Con{T.ExpandedNode{identity, occurrence, tag, attrs, binding, children}, rest}: J.get(attrs, "field") <> visible_column_names(rest)

def view_descriptor_add(+path: String, +tag: String, +attrs: J.Json, +children: +List<T.ExpandedNode>, +acc: +List<J.Field>) -> +List<J.Field>:
  match tag:
    case "table": J.Field{path, J.Object{[J.Field{"kind", J.Text{tag}}, J.Field{"columns", J.Array{visible_column_names(children)}}]}} <> acc
    case "graph-view": J.Field{path, J.Object{[J.Field{"kind", J.Text{tag}}, J.Field{"columns", J.Array{Nil{}}}, J.Field{"nodes", J.get(attrs, "nodes")}]}} <> acc
    case "each": J.Field{path, J.Object{[J.Field{"kind", J.Text{tag}}, J.Field{"items", J.get(attrs, "items")}, J.Field{"key", J.get(attrs, "key")}]}} <> acc
    case _: acc

def view_descriptors(+fuel: Nat, +nodes: +List<T.ExpandedNode>, +acc: +List<J.Field>) -> +List<J.Field>:
  match fuel nodes:
    case 0n _: acc
    case _ Nil{}: acc
    case 1n+f Con{T.ExpandedNode{T.Identity{owner, +path}, occurrence, +tag, +attrs, binding, +children}, rest}:
      view_descriptors(f, List.append(&2, T.ExpandedNode, children, rest), view_descriptor_add(path, tag, attrs, children, acc))

def static_column_names(+elements: +List<T.Element>) -> +List<J.Json>:
  match elements:
    case Nil{}: Nil{}
    case Con{T.Element{tag, attrs, children, closed}, rest}:
      S.literal_attribute(attrs, "field", J.Null{}) <> static_column_names(rest)

def static_view_items(+elements: +List<T.Element>, +parent: String) -> +List<StaticViewItem>:
  match elements:
    case Nil{}: Nil{}
    case Con{first, rest}: StaticViewItem{first, parent} <> static_view_items(rest, parent)

def static_container(+tag: String) -> Bool:
  S.string_seen(["stack", "row-layout", "grid", "card", "when", "resource-view"], tag)

def static_view_add(+path: String, +tag: String, +children: +List<T.Element>, +acc: +List<J.Field>) -> +List<J.Field>:
  Bool.pick(+List<J.Field>, S.field_has(acc, path), acc,
    Bool.pick(+List<J.Field>, String.eq(tag, "table"), J.Field{path, J.Object{[J.Field{"kind", J.Text{tag}}, J.Field{"columns", J.Array{static_column_names(children)}}]}} <> acc,
      Bool.pick(+List<J.Field>, String.eq(tag, "graph-view"), J.Field{path, J.Object{[J.Field{"kind", J.Text{tag}}, J.Field{"columns", J.Array{Nil{}}}]}} <> acc, acc)))

def static_view_descriptors(+fuel: Nat, +todo: +List<StaticViewItem>, +acc: +List<J.Field>) -> +List<J.Field>:
  match fuel todo:
    case 0n _: acc
    case _ Nil{}: acc
    case 1n+f Con{StaticViewItem{T.Element{+tag, attrs, +children, closed}, +parent}, rest}:
      +path = parent ++ "/" ++ J.quote(J.text(S.literal_attribute(attrs, "id", J.Null{})))
      static_view_descriptors(f, List.append(&2, StaticViewItem,
        Bool.pick(+List<StaticViewItem>, static_container(tag), static_view_items(children, path), Nil{}), rest), static_view_add(path, tag, children, acc))

# Static conditional declarations retain schemas even when hidden. Repetition
# membership comes from the corresponding observed parent, never a same-key
# item in a different collection. A hidden/unavailable parent is not a deletion.
def descriptors(+elements: +List<T.Element>, +visible: +List<T.ExpandedNode>) -> +List<J.Field>:
  static_view_descriptors(1024n, static_view_items(elements, ""), view_descriptors(4096n, visible, Nil{}))

type Membership is Data:
  Present{}
  Absent{}
  Unknown{}

def merge_membership(previous: Membership, current: Membership) -> Membership:
  match previous current:
    case Absent{} _: Absent{}
    case _ Absent{}: Absent{}
    case Unknown{} _: Unknown{}
    case _ Unknown{}: Unknown{}
    case Present{} Present{}: Present{}

def found_membership(found: Bool) -> Membership:
  match found:
    case True{}: Present{}
    case False{}: Absent{}

def item_seen(items: +List<J.Json>, +key: String, +wanted: J.Json) -> Bool:
  match items:
    case Nil{}: False{}
    case Con{item, rest}: J.same(E.path_field(item, key), wanted) || item_seen(rest, key, wanted)

def graph_node_seen(items: +List<J.Json>, +wanted: String) -> Bool:
  match items:
    case Nil{}: False{}
    case Con{item, rest}: SafeText.string_equal(J.text(J.get(item, "identity")), wanted) || graph_node_seen(rest, wanted)

def item_membership_from(kind: J.Json, items: J.Json, key: String, wanted: J.Json) -> Membership:
  match kind items:
    case J.Text{"each"} J.Array{values}: found_membership(item_seen(values, key, wanted))
    case _ _: Unknown{}

def item_membership(+observed: J.Json, wanted: J.Json) -> Membership:
  item_membership_from(J.get(observed, "kind"), J.get(observed, "items"), J.text(J.get(observed, "key")), wanted)

def graph_membership_from(kind: J.Json, nodes: J.Json, wanted: String) -> Membership:
  match kind nodes:
    case J.Text{"graph-view"} J.Array{items}: found_membership(graph_node_seen(items, wanted))
    case _ _: Unknown{}

def graph_membership(+observed: J.Json, wanted: String) -> Membership:
  graph_membership_from(J.get(observed, "kind"), J.get(observed, "nodes"), wanted)

def path_membership(segments: +List<Segment>, +observations: +List<J.Field>, +parent: String, +prior: Membership) -> Membership:
  match segments:
    case Nil{}: prior
    case Con{Component{id}, rest}: path_membership(rest, observations, parent ++ "/" ++ J.quote(id), prior)
    case Con{StringItem{+key}, rest}:
      path_membership(rest, observations, parent ++ "/@item/s:" ++ J.quote(key), merge_membership(prior, item_membership(J.find(observations, parent), J.Text{key})))
    case Con{NumberItem{+key}, rest}:
      path_membership(rest, observations, parent ++ "/@item/n:" ++ key, merge_membership(prior, item_membership(J.find(observations, parent), J.Number{key})))
    case Con{GraphNode{+identity}, rest}:
      path_membership(rest, observations, parent ++ "/@node/" ++ J.quote(identity), merge_membership(prior, graph_membership(J.find(observations, parent), identity)))

def saved_membership(parsed: Maybe<&2, +List<Segment>>, observations: +List<J.Field>) -> Membership:
  match parsed:
    case None{}: Absent{}
    case Some{segments}: path_membership(segments, observations, "", Present{})

def retain_membership(membership: Membership) -> Bool:
  match membership:
    case Absent{}: False{}
    case _: True{}

def add_save_descriptor(+path: String, resolved: Maybe<&2, J.Json>, membership: Membership, +tail: +List<J.Field>) -> +List<J.Field>:
  match resolved:
    case None{}: tail
    case Some{value}: Bool.pick(+List<J.Field>, retain_membership(membership), J.Field{path, value} <> tail, tail)

def save_path_descriptors(+elements: +List<T.Element>, +observations: +List<J.Field>, views: +List<J.Field>) -> +List<J.Field>:
  match views:
    case Nil{}: Nil{}
    case Con{J.Field{+path, value}, rest}:
      add_save_descriptor(path, resolve(elements, path), saved_membership(path_loop(96n, PathState{path, Nil{}, False{}}), observations),
        save_path_descriptors(elements, observations, rest))

def save_descriptors(+elements: +List<T.Element>, visible: +List<T.ExpandedNode>, views: +List<J.Field>) -> +List<J.Field>:
  save_path_descriptors(elements, view_descriptors(4096n, visible, Nil{}), views)
