import Base
import ../../bendlib/string-equality.bend as SafeText
import ./TYPES.bend as T
import ./SYNTAX.bend as S
import ./EXPRESSION.bend as E
import ./DECIMAL.bend as D
import ../../bendlib/json.bend as J

def contains_name(+choices: String, +name: String) -> Bool:
  String.contains(choices, "|" ++ name ++ "|")

def common_attribute(+name: String) -> Bool:
  contains_name("|id|visible|enabled|tone|motion|transition|", name)

def component_attributes(+tag: String) -> String:
  match tag:
    case "stack": "|gap|"
    case "row-layout": "|gap|"
    case "grid": "|columns|gap|"
    case "card": "|gap|label|"
    case "text": "|label|"
    case "markdown": "|value|"
    case "metric": "|label|value|format|"
    case "badge": "|label|"
    case "slider": "|label|bind|"
    case "number-input": "|label|bind|"
    case "text-input": "|label|bind|"
    case "textarea": "|label|bind|"
    case "checkbox": "|label|bind|"
    case "select": "|label|bind|"
    case "button": "|label|action|target|value|message|url|"
    case "table": "|rows|row-key|sortable|label|"
    case "column": "|field|label|format|"
    case "line-chart": "|data|row-key|x|y|label|x-label|y-label|"
    case "bar-chart": "|data|row-key|x|y|label|x-label|y-label|"
    case "when": "|test|"
    case "each": "|items|item|key|"
    case "resource-view": "|source|let|"
    case "graph-view": "|nodes|edges|node-key|layout|select|label|"
    case "task-node": "|task|label|"
    case _: ""

def attributes_known(+attrs: +List<T.Attribute>, +tag: String) -> Bool:
  match attrs:
    case Nil{}: True{}
    case Con{T.Attribute{+name, +source}, +rest}:
      (common_attribute(name) || contains_name(component_attributes(tag), name)) && attributes_known(rest, tag)

def is_boolean(+value: J.Json) -> Bool:
  match value:
    case J.Boolean{+value}: True{}
    case _: False{}

def optional_type(+fields: +List<J.Field>, +name: String, +kind: String) -> Bool:
  E.choose(Bool, S.field_has(fields, name),
    (_ => String.eq(E.key_type(J.find(fields, name)), kind)), (_ => True{}))

def optional_bool(+fields: +List<J.Field>, +name: String) -> Bool:
  Bool.not(S.field_has(fields, name)) || is_boolean(J.find(fields, name))

def optional_enum(+fields: +List<J.Field>, +name: String, +choices: String) -> Bool:
  Bool.not(S.field_has(fields, name)) || (J.is_text(J.find(fields, name)) && contains_name(choices, J.text(J.find(fields, name))))

def valid_common(+fields: +List<J.Field>) -> Bool:
  S.valid_id(J.text(J.find(fields, "id"))) && optional_bool(fields, "visible") && optional_bool(fields, "enabled") &&
    optional_enum(fields, "tone", "|neutral|accent|success|warning|danger|muted|") &&
    optional_enum(fields, "motion", "|none|pulse|spin|") && optional_enum(fields, "transition", "|none|status|")

def boolean_or(+value: J.Json, +fallback: Bool) -> Bool:
  match value:
    case J.Boolean{+value}: value
    case _: fallback

def nonempty_text(+value: J.Json) -> Bool:
  J.is_text(value) && Bool.not(String.eq(J.text(value), ""))

def label_required(+tag: String) -> Bool:
  contains_name("|text|metric|badge|slider|number-input|text-input|textarea|checkbox|select|button|column|task-node|", tag)

def declaration(+tag: String) -> Bool:
  contains_name("|state|derive|source|dataset|row|", tag)

def input(+tag: String) -> Bool:
  contains_name("|slider|number-input|text-input|textarea|checkbox|select|", tag)

def format_valid(+fields: +List<J.Field>) -> Bool:
  optional_enum(fields, "format", "|number|percent|currency:USD|currency:CNY|")

def item_key(+value: J.Json) -> Maybe<&2, String>:
  match value:
    case J.Text{+text}: Bool.pick((Maybe<&2, String>), Bool.not(String.eq(text, "")), Some{"s:" ++ J.quote(text)}, None{})
    case J.Number{+number}: Bool.pick((Maybe<&2, String>), D.integral(number), Some{"n:" ++ number}, None{})
    case _: None{}

def key_text(+value: Maybe<&2, String>) -> String:
  match value:
    case Some{+key}: key
    case None{}: ""

def keys_valid(+items: +List<J.Json>, +path: String, +seen: +List<String>) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{+item, +rest}:
      +key = key_text(item_key(E.path_field(item, path)))
      Bool.not(String.eq(key, "")) && Bool.not(S.string_seen(seen, key)) && keys_valid(rest, path, key <> seen)

def collection_valid(+value: J.Json, +path: String) -> Bool:
  match value:
    case J.Array{+items}: E.path_valid(String.split(path, '.')) && keys_valid(items, path, Nil{})
    case _: False{}

def chart_rows_valid(+items: +List<J.Json>, +x: String, +y: String) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{+row, +rest}:
      (J.is_text(E.path_field(row, x)) || String.eq(E.key_type(E.path_field(row, x)), "number")) &&
        String.eq(E.key_type(E.path_field(row, y)), "number") && chart_rows_valid(rest, x, y)

def column_children(+children: +List<T.Element>) -> Bool:
  match children:
    case Nil{}: True{}
    case Con{T.Element{"column", +attrs, Nil{}, +closed}, +rest}: column_children(rest)
    case _: False{}

def graph_template(+children: +List<T.Element>) -> Bool:
  match children:
    case Nil{}: True{}
    case Con{T.Element{"node-template", +attrs, +children, +closed}, Nil{}}: True{}
    case _: False{}

def task_valid(value: J.Json) -> Bool:
  match value:
    case J.Null{}: True{}
    case J.Object{+fields}: is_boolean(J.find(fields, "working")) && is_boolean(J.find(fields, "awaitingHuman")) && J.is_text(J.find(fields, "statusLabel")) && J.is_text(J.find(fields, "phase"))
    case _: False{}

def graph_identity_strings(items: +List<J.Json>) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{+item, rest}: nonempty_text(J.get(item, "identity")) && graph_identity_strings(rest)

def graph_has_node(items: +List<J.Json>, +identity: String) -> Bool:
  match items:
    case Nil{}: False{}
    case Con{item, rest}: SafeText.string_equal(J.text(J.get(item, "identity")), identity) || graph_has_node(rest, identity)

def graph_endpoints(edges: +List<J.Json>, +nodes: +List<J.Json>) -> Bool:
  match edges:
    case Nil{}: True{}
    case Con{+edge, rest}:
      nonempty_text(J.get(edge, "sourceIdentity")) && nonempty_text(J.get(edge, "targetIdentity")) &&
        graph_has_node(nodes, J.text(J.get(edge, "sourceIdentity"))) && graph_has_node(nodes, J.text(J.get(edge, "targetIdentity"))) && graph_endpoints(rest, nodes)

def graph_valid(+fields: +List<J.Field>, +children: +List<T.Element>) -> Bool:
  collection_valid(J.find(fields, "nodes"), "identity") && collection_valid(J.find(fields, "edges"), "identity") &&
    String.eq(J.text(J.find(fields, "node-key")), "identity") && String.eq(J.text(J.find(fields, "layout")), "stable") &&
    Nat.is_le(List.length(&2, J.Json, J.items(J.find(fields, "nodes"))), 128n) && Nat.is_le(List.length(&2, J.Json, J.items(J.find(fields, "edges"))), 512n) &&
    graph_identity_strings(J.items(J.find(fields, "nodes"))) && graph_identity_strings(J.items(J.find(fields, "edges"))) &&
    graph_endpoints(J.items(J.find(fields, "edges")), J.items(J.find(fields, "nodes"))) && graph_template(children)

def component_specific(+tag: String, +fields: +List<J.Field>, +children: +List<T.Element>) -> Bool:
  match tag:
    case "markdown": J.is_text(J.find(fields, "value"))
    case "metric": S.field_has(fields, "value") && E.scalar(J.find(fields, "value")) && format_valid(fields)
    case "grid":
      E.numeric_equality(D.compare(">=", S.scalar_text(J.find(fields, "columns")), "1")) && E.numeric_equality(D.compare("<=", S.scalar_text(J.find(fields, "columns")), "4")) && D.integral(S.scalar_text(J.find(fields, "columns")))
    case "when": is_boolean(J.find(fields, "test"))
    case "each": S.valid_binding_id(J.text(J.find(fields, "item"))) && collection_valid(J.find(fields, "items"), J.text(J.find(fields, "key")))
    case "table":
      collection_valid(J.find(fields, "rows"), J.text(J.find(fields, "row-key"))) && optional_bool(fields, "sortable") && Nat.is_gt(List.length(&2, T.Element, children), 0n) && Nat.is_le(List.length(&2, T.Element, children), 16n) && column_children(children)
    case "line-chart":
      collection_valid(J.find(fields, "data"), J.text(J.find(fields, "row-key"))) && chart_rows_valid(J.items(J.find(fields, "data")), J.text(J.find(fields, "x")), J.text(J.find(fields, "y")))
    case "bar-chart":
      collection_valid(J.find(fields, "data"), J.text(J.find(fields, "row-key"))) && chart_rows_valid(J.items(J.find(fields, "data")), J.text(J.find(fields, "x")), J.text(J.find(fields, "y")))
    case "resource-view": S.valid_binding_id(J.text(J.find(fields, "source"))) && S.valid_binding_id(J.text(J.find(fields, "let")))
    case "task-node": S.field_has(fields, "task") && task_valid(J.find(fields, "task"))
    case "column": nonempty_text(J.find(fields, "field")) && format_valid(fields)
    case "graph-view": graph_valid(fields, children)
    case _: True{}

def children_allowed(+tag: String, +children: +List<T.Element>) -> Bool:
  contains_name("|stack|row-layout|grid|card|when|each|resource-view|graph-view|table|", tag) || List.is_empty(&2, T.Element, children)

def component_valid(+tag: String, +fields: +List<J.Field>, +children: +List<T.Element>) -> Bool:
  valid_common(fields) && (Bool.not(label_required(tag)) || nonempty_text(J.find(fields, "label"))) &&
    optional_type(fields, "label", "string") && optional_type(fields, "x-label", "string") && optional_type(fields, "y-label", "string") &&
    optional_enum(fields, "gap", "|none|sm|md|lg|") && children_allowed(tag, children) && component_specific(tag, fields, children)

def local_find(+locals: +List<T.Local>, +name: String) -> Maybe<&2, T.Local>:
  match locals:
    case Nil{}: None{}
    case Con{+local, +rest}:
      T.Local{+id, schema, value, raw, validation} = local
      Bool.pick((Maybe<&2, T.Local>), String.eq(id, name), Some{local}, local_find(rest, name))

def field_kind(+tag: String, +schema: T.StateSchema) -> Bool:
  match tag schema:
    case "slider" T.StateSchema{T.IntegerState{}, +initial, Some{+min}, Some{+max}, +step, +options, +length}: True{}
    case "slider" T.StateSchema{T.NumberState{}, +initial, Some{+min}, Some{+max}, +step, +options, +length}: True{}
    case "number-input" T.StateSchema{T.IntegerState{}, +initial, +min, +max, +step, +options, +length}: True{}
    case "number-input" T.StateSchema{T.NumberState{}, +initial, +min, +max, +step, +options, +length}: True{}
    case "text-input" T.StateSchema{T.StringState{}, +initial, +min, +max, +step, +options, +length}: True{}
    case "textarea" T.StateSchema{T.StringState{}, +initial, +min, +max, +step, +options, +length}: True{}
    case "checkbox" T.StateSchema{T.BooleanState{}, +initial, +min, +max, +step, +options, +length}: True{}
    case "select" T.StateSchema{T.EnumState{}, +initial, +min, +max, +step, +options, +length}: True{}
    case _ _: False{}

def field_binding(+local: Maybe<&2, T.Local>, +tag: String, +enabled: Bool) -> Result<&2, &2, String, T.Binding>:
  match local:
    case None{}: Fail{"input binding does not name a root state"}
    case Some{T.Local{+id, +schema, +value, +raw, +validation}}:
      E.choose((Result<&2, &2, String, T.Binding>), field_kind(tag, schema),
        (_ => Done{T.FieldBinding{id, schema, raw, value, validation, enabled}}), (_ => Fail{"input binding state type mismatch"}))

def action_kind(+action: String) -> Maybe<&2, T.ActionKind>:
  match action:
    case "set": Some{T.SetAction{}}
    case "reset": Some{T.ResetAction{}}
    case "draft": Some{T.DraftAction{}}
    case "submit": Some{T.SubmitAction{}}
    case "copy": Some{T.CopyAction{}}
    case "openUrl": Some{T.OpenUrlAction{}}
    case _: None{}

def action_enabled(+kind: T.ActionKind, +enabled: Bool, +external: Bool) -> Bool:
  match kind:
    case T.SetAction{}: enabled
    case T.ResetAction{}: enabled
    case _: enabled && external

def set_valid(+local: Maybe<&2, T.Local>, +value: J.Json) -> Bool:
  match local:
    case Some{T.Local{+id, +schema, +old, +raw, +validation}}: S.schema_accepts(schema, value)
    case None{}: False{}

def button_valid(+kind: T.ActionKind, +fields: +List<J.Field>, +locals: +List<T.Local>) -> Bool:
  match kind:
    case T.SetAction{}: set_valid(local_find(locals, J.text(J.find(fields, "target"))), J.find(fields, "value"))
    case T.ResetAction{}: Bool.not(S.field_has(fields, "target")) && Bool.not(S.field_has(fields, "value"))
    case T.DraftAction{}: nonempty_text(J.find(fields, "message"))
    case T.SubmitAction{}: nonempty_text(J.find(fields, "message"))
    case T.CopyAction{}: J.is_text(J.find(fields, "value"))
    case T.OpenUrlAction{}: nonempty_text(J.find(fields, "url"))

def button_binding(+found: Maybe<&2, T.ActionKind>, +fields: +List<J.Field>, +locals: +List<T.Local>, +enabled: Bool, +external: Bool) -> Result<&2, &2, String, T.Binding>:
  match found:
    case None{}: Fail{"unknown action kind"}
    case Some{+kind}:
      E.choose((Result<&2, &2, String, T.Binding>), button_valid(kind, fields, locals),
        (_ => Done{T.ActionBinding{kind, action_enabled(kind, enabled, external), False{}}}), (_ => Fail{"invalid action properties"}))

def binding(+tag: String, +fields: +List<J.Field>, +locals: +List<T.Local>, +external: Bool) -> Result<&2, &2, String, T.Binding>:
  +enabled = boolean_or(J.find(fields, "enabled"), True{})
  E.choose((Result<&2, &2, String, T.Binding>), input(tag),
    (_ => field_binding(local_find(locals, J.text(J.find(fields, "bind"))), tag, enabled)),
    (_ => E.choose((Result<&2, &2, String, T.Binding>), String.eq(tag, "button"),
      (_ => button_binding(action_kind(J.text(J.find(fields, "action"))), fields, locals, enabled, external)),
      (_ => Done{T.NoBinding{}}))))

def static_expression(+result: Result<&2, &2, String, E.Expr>, +fallback: J.Json) -> J.Json:
  match result:
    case Done{E.Literal{+value}}: value
    case _: fallback

def static_found(+source: Maybe<&2, String>, +fallback: J.Json) -> J.Json:
  match source:
    case Some{+text}: static_expression(E.parse(text), fallback)
    case None{}: fallback

def static_attribute(+attrs: +List<T.Attribute>, +name: String, +fallback: J.Json) -> J.Json:
  static_found(S.source(attrs, name), fallback)

def static_string(+result: Result<&2, &2, String, E.Expr>) -> Bool:
  match result:
    case Done{E.Literal{J.Text{+text}}}: True{}
    case _: False{}

def static_attributes(+attrs: +List<T.Attribute>) -> Bool:
  match attrs:
    case Nil{}: True{}
    case Con{T.Attribute{+name, +source}, +rest}:
      (Bool.not(contains_name("|id|bind|action|target|item|key|source|let|node-key|layout|select|row-key|field|x|y|", name)) || static_string(E.parse(source))) && static_attributes(rest)

def mount_occurrence(+mounts: +List<T.Mount>, +path: String) -> Nat:
  match mounts:
    case Nil{}: 0n
    case Con{T.Mount{+key, +occurrence}, +rest}: E.choose(Nat, SafeText.string_equal(key, path), (_ => occurrence), (_ => mount_occurrence(rest, path)))

def local_value(+local: Maybe<&2, T.Local>) -> J.Json:
  match local:
    case None{}: J.Null{}
    case Some{T.Local{+id, +schema, +value, +raw, +validation}}: value

def view_attributes(+tag: String, +fields: +List<J.Field>, +path: String, +views: +List<J.Field>, +locals: +List<T.Local>) -> +List<J.Field>:
  match tag:
    case "graph-view": S.field_set(S.field_set(fields, "@view", J.find(views, path)), "@selection", Bool.pick(J.Json, S.field_has(fields, "select"), local_value(local_find(locals, J.text(J.find(fields, "select")))), J.get(J.find(views, path), "selection")))
    case "table": S.field_set(fields, "@view", J.find(views, path))
    case _: fields

def sorted_attributes(+result: Result<&2, &2, String, J.Json>, +fields: +List<J.Field>) -> Result<&2, &2, String, +List<J.Field>>:
  match result:
    case Done{+rows}: Done{S.field_set(fields, "rows", rows)}
    case Fail{+error}: Fail{error}

type Context is Data:
  Context{parent: String, environment: +List<J.Field>, fresh: Bool, depth: Nat}

type Task is Data:
  Group{elements: +List<T.Element>, context: Context, index: Nat, seen: +List<String>}
  Node{element: T.Element, context: Context, index: Nat}
  CloseNode{path: String, tag: String, attributes: +List<J.Field>, binding: T.Binding, saved: +List<T.ExpandedNode>}
  Repeat{items: +List<J.Json>, variable: String, key: String, children: +List<T.Element>, context: Context}
  GraphRepeat{items: +List<J.Json>, variable: String, children: +List<T.Element>, context: Context, index: Nat, view: J.Json}

type Expansion is Data:
  Expansion{tasks: +List<Task>, reversed: +List<T.ExpandedNode>, count: Nat}

def error_node(+owner: T.Owner, +path: String, +message: String, +mounts: +List<T.Mount>) -> T.ExpandedNode:
  T.ExpandedNode{T.Identity{owner, path}, mount_occurrence(mounts, path), "@error", J.Object{[J.Field{"label", J.Text{message}}]}, T.NoBinding{}, Nil{}}

def context_env(+context: Context) -> +List<J.Field>:
  match context:
    case Context{+parent, +environment, +fresh, +depth}: environment

def context_fresh(+context: Context) -> Bool:
  match context:
    case Context{+parent, +environment, +fresh, +depth}: fresh

def context_path(+context: Context) -> String:
  match context:
    case Context{+parent, +environment, +fresh, +depth}: parent

def context_depth(+context: Context) -> Nat:
  match context:
    case Context{+parent, +environment, +fresh, +depth}: depth

def error_expansion(+owner: T.Owner, +path: String, +message: String, +tasks: +List<Task>, +reversed: +List<T.ExpandedNode>, +count: Nat, +mounts: +List<T.Mount>) -> Expansion:
  Expansion{tasks, error_node(owner, path, message, mounts) <> reversed, 1n+count}

def container(+path: String, +tag: String, +fields: +List<J.Field>, +binding: T.Binding, +children: +List<T.Element>, +context: Context, +tasks: +List<Task>, +saved: +List<T.ExpandedNode>, +count: Nat) -> Expansion:
  match context:
    case Context{+parent, +environment, +fresh, +depth}:
      Expansion{Group{children, Context{path, environment, fresh, 1n+depth}, 0n, Nil{}} <> CloseNode{path, tag, fields, binding, saved} <> tasks, Nil{}, 1n+count}

def resource_label(+handle: J.Json) -> String:
  "实时视图 / 上次同步序号 " ++ S.scalar_text(J.get(handle, "sequence")) ++
    Bool.pick(String, J.boolean(J.get(handle, "fresh")), "", " / 连接中断，显示上次数据")

def unavailable_label(+status: String) -> String:
  match status:
    case "loading": "实时视图 / 正在加载资源"
    case "missing": "实时视图 / 资源已删除或不存在"
    case "forbidden": "实时视图 / 无权读取此资源"
    case _: "实时视图 / 资源绑定错误"

def placeholder(+path: String, +label: String, +tasks: +List<Task>, +reversed: +List<T.ExpandedNode>, +count: Nat, +owner: T.Owner, +mounts: +List<T.Mount>) -> Expansion:
  Expansion{tasks, T.ExpandedNode{T.Identity{owner, path}, mount_occurrence(mounts, path), "resource-view", J.Object{[J.Field{"label", J.Text{label}}]}, T.NoBinding{}, Nil{}} <> reversed, 1n+count}

def resource_expand(+path: String, +fields: +List<J.Field>, +children: +List<T.Element>, +context: Context, +tasks: +List<Task>, +reversed: +List<T.ExpandedNode>, +count: Nat, +owner: T.Owner, +mounts: +List<T.Mount>) -> Expansion:
  +handle = J.find(context_env(context), J.text(J.find(fields, "source")))
  +variable = J.text(J.find(fields, "let"))
  E.choose(Expansion, S.valid_binding_id(variable) && Bool.not(S.field_has(context_env(context), variable)),
    (_ => E.choose(Expansion, String.eq(J.text(J.get(handle, "status")), "ready") && J.is_object(J.get(handle, "value")),
      (_ => container(path, "resource-view", [J.Field{"id", J.find(fields, "id")}, J.Field{"label", J.Text{resource_label(handle)}}, J.Field{"@sourceFresh", J.get(handle, "fresh")}, J.Field{"@sequence", J.get(handle, "sequence")}], T.NoBinding{}, children,
        Context{path, S.field_set(context_env(context), variable, J.get(handle, "value")), context_fresh(context) && J.boolean(J.get(handle, "fresh")), context_depth(context)}, tasks, reversed, count)),
      (_ => placeholder(path, unavailable_label(J.text(J.get(handle, "status"))), tasks, reversed, count, owner, mounts)))),
    (_ => error_expansion(owner, path, "resource binding variable is invalid or shadows a declaration", tasks, reversed, count, mounts)))

def template_variable(+children: +List<T.Element>) -> String:
  match children:
    case Con{T.Element{"node-template", +attrs, +children, +closed}, Nil{}}: J.text(static_attribute(attrs, "item", J.Text{"node"}))
    case _: "node"

def template_children(+children: +List<T.Element>) -> +List<T.Element>:
  match children:
    case Con{T.Element{"node-template", +attrs, +children, +closed}, Nil{}}: children
    case _: [T.Element{"task-node", [T.Attribute{"id", "\"task\""}, T.Attribute{"label", "node.key"}, T.Attribute{"task", "node.task"}], Nil{}, True{}}]

def graph_expand(+path: String, +fields: +List<J.Field>, +children: +List<T.Element>, +context: Context, +tasks: +List<Task>, +reversed: +List<T.ExpandedNode>, +count: Nat) -> Expansion:
  match context:
    case Context{+parent, +environment, +fresh, +depth}:
      Expansion{GraphRepeat{J.items(J.find(fields, "nodes")), template_variable(children), template_children(children), Context{path, environment, fresh, 1n+depth}, 0n, J.find(fields, "@view")} <> CloseNode{path, "graph-view", fields, T.NoBinding{}, reversed} <> tasks, Nil{}, 1n+count}

def component_expand(+tag: String, +path: String, +fields: +List<J.Field>, +children: +List<T.Element>, +binding: T.Binding, +context: Context, +tasks: +List<Task>, +reversed: +List<T.ExpandedNode>, +count: Nat, +owner: T.Owner, +mounts: +List<T.Mount>) -> Expansion:
  E.choose(Expansion, String.eq(tag, "resource-view"),
    (_ => resource_expand(path, fields, children, context, tasks, reversed, count, owner, mounts)),
    (_ => E.choose(Expansion, String.eq(tag, "graph-view"),
      (_ => graph_expand(path, fields, children, context, tasks, reversed, count)),
      (_ => E.choose(Expansion, String.eq(tag, "each"),
        (_ => Expansion{Repeat{J.items(J.find(fields, "items")), J.text(J.find(fields, "item")), J.text(J.find(fields, "key")), children, Context{path, context_env(context), context_fresh(context), 1n+context_depth(context)}} <> CloseNode{path, tag, fields, binding, reversed} <> tasks, Nil{}, 1n+count}),
        (_ => E.choose(Expansion, String.eq(tag, "when"),
          (_ => E.choose(Expansion, J.boolean(J.find(fields, "test")),
            (_ => container(path, tag, fields, binding, children, context, tasks, reversed, count)),
            (_ => Expansion{tasks, reversed, count}))),
          (_ => container(path, tag, fields, binding, children, context, tasks, reversed, count)))))))))

def accepted_binding(+result: Result<&2, &2, String, T.Binding>, +tag: String, +path: String, +fields: +List<J.Field>, +children: +List<T.Element>, +context: Context, +tasks: +List<Task>, +reversed: +List<T.ExpandedNode>, +count: Nat, +owner: T.Owner, +mounts: +List<T.Mount>) -> Expansion:
  match result:
    case Fail{+error}: error_expansion(owner, path, error, tasks, reversed, count, mounts)
    case Done{+binding}: component_expand(tag, path, fields, children, binding, context, tasks, reversed, count, owner, mounts)

def string_local(+local: Maybe<&2, T.Local>) -> Bool:
  match local:
    case Some{T.Local{+id, T.StateSchema{T.StringState{}, +initial, +min, +max, +step, +options, +length}, +value, +raw, +validation}}: True{}
    case _: False{}

def scope_valid(+tag: String, +fields: +List<J.Field>, +children: +List<T.Element>, +context: Context, +locals: +List<T.Local>) -> Bool:
  match tag:
    case "each": Bool.not(S.field_has(context_env(context), J.text(J.find(fields, "item"))))
    case "graph-view":
      S.valid_binding_id(template_variable(children)) && Bool.not(S.field_has(context_env(context), template_variable(children))) &&
        (Bool.not(S.field_has(fields, "select")) || string_local(local_find(locals, J.text(J.find(fields, "select")))))
    case _: True{}

def accepted_attributes(+result: Result<&2, &2, String, +List<J.Field>>, +tag: String, +path: String, +attrs: +List<T.Attribute>, +children: +List<T.Element>, +context: Context, +tasks: +List<Task>, +reversed: +List<T.ExpandedNode>, +count: Nat, +owner: T.Owner, +mounts: +List<T.Mount>, +locals: +List<T.Local>, +external: Bool) -> Expansion:
  match result:
    case Fail{+error}: error_expansion(owner, path, error, tasks, reversed, count, mounts)
    case Done{+fields}:
      E.choose(Expansion, attributes_known(attrs, tag) && static_attributes(attrs) && component_valid(tag, fields, children) && scope_valid(tag, fields, children, context, locals),
        (_ => E.choose(Expansion, boolean_or(J.find(fields, "visible"), True{}),
          (_ => accepted_binding(binding(tag, fields, locals, external && context_fresh(context)), tag, path, fields, children, context, tasks, reversed, count, owner, mounts)),
          (_ => Expansion{tasks, reversed, count}))),
        (_ => error_expansion(owner, path, "invalid component, property, type, key or collection limit: " ++ tag, tasks, reversed, count, mounts)))

def node_path(+context: Context, +attrs: +List<T.Attribute>, +index: Nat) -> String:
  context_path(context) ++ "/" ++ J.quote(J.text(static_attribute(attrs, "id", J.Text{"@invalid/" ++ Nat.show(index)})))

def element_id(+element: T.Element) -> String:
  match element:
    case T.Element{+tag, +attrs, +children, +closed}: J.text(static_attribute(attrs, "id", J.Null{}))

def element_tag(+element: T.Element) -> String:
  match element:
    case T.Element{+tag, +attrs, +children, +closed}: tag

def expansion_step(+expansion: Expansion, +owner: T.Owner, +locals: +List<T.Local>, +views: +List<J.Field>, +mounts: +List<T.Mount>, +external: Bool) -> Expansion:
  match expansion:
    case Expansion{Con{Group{Nil{}, +context, +index, +seen}, +tasks}, +reversed, +count}: Expansion{tasks, reversed, count}
    case Expansion{Con{Group{Con{+element, +remaining}, +context, +index, +seen}, +tasks}, +reversed, +count}:
      +next: +List<Task> = Group{remaining, context, 1n+index, element_id(element) <> seen} <> tasks
      E.choose(Expansion, declaration(element_tag(element)),
        (_ => E.choose(Expansion, Nat.is_eq(context_depth(context), 0n),
          (_ => Expansion{Group{remaining, context, 1n+index, seen} <> tasks, reversed, count}),
          (_ => error_expansion(owner, context_path(context) ++ "/@declaration/" ++ Nat.show(index), "declarations are only allowed directly inside ui", next, reversed, count, mounts)))),
        (_ => E.choose(Expansion, S.string_seen(seen, element_id(element)),
          (_ => error_expansion(owner, context_path(context) ++ "/@duplicate/" ++ Nat.show(index), "duplicate component id in lexical siblings", next, reversed, count, mounts)),
          (_ => Expansion{Node{element, context, index} <> next, reversed, count}))))
    case Expansion{Con{Node{+element, +context, +index}, +tasks}, +reversed, +count}:
      error_expansion(owner, context_path(context) ++ "/@unprepared", "internal expansion node was not prepared", tasks, reversed, count, mounts)
    case Expansion{Con{CloseNode{+path, +tag, +fields, +binding, +saved}, +tasks}, +reversed, +count}:
      Expansion{tasks, T.ExpandedNode{T.Identity{owner, path}, mount_occurrence(mounts, path), tag, J.Object{fields}, binding, List.reverse(&2, T.ExpandedNode, reversed)} <> saved, count}
    case Expansion{Con{Repeat{Nil{}, +variable, +key, +children, +context}, +tasks}, +reversed, +count}: Expansion{tasks, reversed, count}
    case Expansion{Con{Repeat{Con{+item, +remaining}, +variable, +key, +children, Context{+parent, +env, +fresh, +depth}}, +tasks}, +reversed, +count}:
      +path = parent ++ "/@item/" ++ key_text(item_key(E.path_field(item, key)))
      Expansion{Group{children, Context{path, S.field_set(env, variable, item), fresh, depth}, 0n, Nil{}} <> Repeat{remaining, variable, key, children, Context{parent, env, fresh, depth}} <> tasks, reversed, count}
    case Expansion{Con{GraphRepeat{Nil{}, +variable, +children, +context, +index, +view}, +tasks}, +reversed, +count}: Expansion{tasks, reversed, count}
    case Expansion{Con{GraphRepeat{Con{+item, +remaining}, +variable, +children, Context{+parent, +env, +fresh, +depth}, +index, +view}, +tasks}, +reversed, +count}:
      +identity = J.text(J.get(item, "identity"))
      +path = parent ++ "/@node/" ++ J.quote(identity)
      Expansion{Group{children, Context{path, S.field_set(env, variable, item), fresh, depth}, 0n, Nil{}} <>
        CloseNode{path, "@graph-node", [J.Field{"identity", J.Text{identity}}, J.Field{"index", J.nat(index)}, J.Field{"@view", view}], T.NoBinding{}, reversed} <>
        GraphRepeat{remaining, variable, children, Context{parent, env, fresh, depth}, 1n+index, view} <> tasks, Nil{}, 1n+count}
    case Expansion{Nil{}, +reversed, +count}: Expansion{Nil{}, reversed, count}

def expansion_count(+expansion: Expansion) -> Nat:
  match expansion:
    case Expansion{+tasks, +reversed, +count}: count

type AttributesEvaluation is Data:
  AttributesEvaluation{result: Result<&2, &2, String, +List<J.Field>>, remaining: Nat}

def evaluation_remaining(+evaluation: E.Evaluation) -> Nat:
  match evaluation:
    case E.Evaluation{+result, +remaining}: remaining

def evaluate_attribute(+parsed: Result<&2, &2, String, E.Expr>, +env: +List<J.Field>, +fuel: Nat) -> E.Evaluation:
  match parsed:
    case Fail{+error}: E.Evaluation{Fail{error}, fuel}
    case Done{+expression}: E.evaluate_bounded(expression, env, fuel)

def attributes_bounded(+attrs: +List<T.Attribute>, +env: +List<J.Field>, +fuel: Nat, +result: Result<&2, &2, String, +List<J.Field>>) -> AttributesEvaluation:
  match attrs:
    case Nil{}: AttributesEvaluation{result, fuel}
    case Con{T.Attribute{+name, +source}, +rest}:
      +evaluated = evaluate_attribute(E.parse(source), env, fuel)
      attributes_bounded(rest, env, evaluation_remaining(evaluated), S.attributes_join(name, E.evaluation_result(evaluated), result))

def sorted_evaluation(+evaluation: E.Evaluation, +fields: +List<J.Field>) -> AttributesEvaluation:
  match evaluation:
    case E.Evaluation{+result, +remaining}: AttributesEvaluation{sorted_attributes(result, fields), remaining}

def prepare_attributes(+evaluation: AttributesEvaluation, +tag: String, +path: String, +views: +List<J.Field>, +locals: +List<T.Local>, +fresh: Bool) -> AttributesEvaluation:
  match evaluation:
    case AttributesEvaluation{Fail{+error}, +remaining}: AttributesEvaluation{Fail{error}, remaining}
    case AttributesEvaluation{Done{+fields}, +remaining}:
      +final = view_attributes(tag, Bool.pick((+List<J.Field>), fresh, fields, S.field_set(fields, "motion", J.Text{"none"})), path, views, locals)
      +view = J.find(views, path)
      E.choose(AttributesEvaluation, String.eq(tag, "table") && Bool.not(String.eq(J.text(J.get(view, "sort")), "")),
        (_ => sorted_evaluation(E.evaluate_bounded(E.Call{"sort", [E.Literal{J.find(fields, "rows")}, E.Literal{J.get(view, "sort")}, E.Literal{J.get(view, "direction")}]}, Nil{}, remaining), final)),
        (_ => AttributesEvaluation{Done{final}, remaining}))

type ExpansionTurn is Data:
  ExpansionTurn{expansion: Expansion, remaining: Nat}

type ExpandedResult is Data:
  ExpandedResult{nodes: +List<T.ExpandedNode>, remaining: Nat}

def node_turn(+evaluation: AttributesEvaluation, +tag: String, +path: String, +attrs: +List<T.Attribute>, +children: +List<T.Element>, +context: Context, +tasks: +List<Task>, +reversed: +List<T.ExpandedNode>, +count: Nat, +owner: T.Owner, +mounts: +List<T.Mount>, +locals: +List<T.Local>, +external: Bool) -> ExpansionTurn:
  match evaluation:
    case AttributesEvaluation{+result, +remaining}:
      ExpansionTurn{accepted_attributes(result, tag, path, attrs, children, context, tasks, reversed, count, owner, mounts, locals, external), remaining}

def expansion_turn(+expansion: Expansion, +budget: Nat, +owner: T.Owner, +locals: +List<T.Local>, +views: +List<J.Field>, +mounts: +List<T.Mount>, +external: Bool) -> ExpansionTurn:
  match expansion:
    case Expansion{Con{Node{T.Element{+tag, +attrs, +children, +closed}, +context, +index}, +tasks}, +reversed, +count}:
      +path = node_path(context, attrs, index)
      E.choose(ExpansionTurn, Nat.is_le(context_depth(context), 32n) && Bool.not(String.eq(component_attributes(tag), "")),
        (_ => node_turn(prepare_attributes(attributes_bounded(attrs, context_env(context), budget, Done{Nil{}}), tag, path, views, locals, context_fresh(context)), tag, path, attrs, children, context, tasks, reversed, count, owner, mounts, locals, external)),
        (_ => ExpansionTurn{error_expansion(owner, path, "unknown component or expansion depth exceeded: " ++ tag, tasks, reversed, count, mounts), budget}))
    case +other: ExpansionTurn{expansion_step(other, owner, locals, views, mounts, external), budget}

def turn_expansion(+turn: ExpansionTurn) -> Expansion:
  match turn:
    case ExpansionTurn{+expansion, +remaining}: expansion

def turn_remaining(+turn: ExpansionTurn) -> Nat:
  match turn:
    case ExpansionTurn{+expansion, +remaining}: remaining

def expansion_loop(+fuel: Nat, +expansion: Expansion, +budget: Nat, +owner: T.Owner, +locals: +List<T.Local>, +views: +List<J.Field>, +mounts: +List<T.Mount>, +external: Bool) -> ExpandedResult:
  match fuel expansion:
    case _ Expansion{Nil{}, +reversed, +count}: ExpandedResult{List.reverse(&2, T.ExpandedNode, reversed), budget}
    case 0n Expansion{+tasks, +reversed, +count}: ExpandedResult{error_node(owner, "@expansion-budget", "interactive expansion step budget exceeded", mounts) <> List.reverse(&2, T.ExpandedNode, reversed), budget}
    case 1n+remaining +expansion:
      +turn = expansion_turn(expansion, budget, owner, locals, views, mounts, external)
      E.choose(ExpandedResult, Nat.is_lt(expansion_count(expansion), 4096n),
        (_ => expansion_loop(remaining, turn_expansion(turn), turn_remaining(turn), owner, locals, views, mounts, external)),
        (_ => ExpandedResult{[error_node(owner, "@expanded-node-limit", "expanded component limit exceeded", mounts)], budget}))

def handle_fresh(value: J.Json) -> Bool:
  match value:
    case J.Object{+fields}:
      E.choose(Bool, S.field_has(fields, "status") && S.field_has(fields, "fresh") && S.field_has(fields, "value"),
        (_ => J.boolean(J.find(fields, "fresh")) && String.eq(J.text(J.find(fields, "status")), "ready")), (_ => True{}))
    case _: True{}

def environment_fresh(fields: +List<J.Field>) -> Bool:
  match fields:
    case Nil{}: True{}
    case Con{J.Field{name, value}, rest}: handle_fresh(value) && environment_fresh(rest)

def expand_bounded(+owner: T.Owner, +elements: +List<T.Element>, +env: +List<J.Field>, +locals: +List<T.Local>, +views: +List<J.Field>, +mounts: +List<T.Mount>, +external: Bool, +fuel: Nat) -> ExpandedResult:
  expansion_loop(32768n, Expansion{Group{elements, Context{"", env, environment_fresh(env), 0n}, 0n, Nil{}} <> Nil{}, Nil{}, 0n}, fuel, owner, locals, views, mounts, external)

def expanded_nodes(+result: ExpandedResult) -> +List<T.ExpandedNode>:
  match result:
    case ExpandedResult{+nodes, +remaining}: nodes

def expand(+owner: T.Owner, +elements: +List<T.Element>, +env: +List<J.Field>, +locals: +List<T.Local>, +views: +List<J.Field>, +mounts: +List<T.Mount>, +external: Bool) -> +List<T.ExpandedNode>:
  expanded_nodes(expand_bounded(owner, elements, env, locals, views, mounts, external, 100000n))
