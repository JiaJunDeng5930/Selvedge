import Base
import ../core/interface.bend as UI
import ./controls.bend as Controls

type DialogParts is Data:
  DialogParts{header: +List<UI.Node>, body: +List<UI.Node>}

def header_child(+value: UI.Node, +context: Controls.Context) -> Bool:
  UI.Node{+key, semantic, label, +role, +meaning, children} = value
  +local = Controls.enter(value, context)
  Controls.panel_header(Controls.represent(key, meaning, label, role, local))

def prepend_panel_header(value: UI.Node, parts: DialogParts) -> DialogParts:
  DialogParts{+headers, +body} = parts
  DialogParts{value <> headers, body}

def append_body(value: UI.Node, parts: DialogParts) -> DialogParts:
  DialogParts{+headers, +body} = parts
  DialogParts{headers, value <> body}

def partition_child(value: UI.Node, is_panel_header: Bool, parts: DialogParts) -> DialogParts:
  match is_panel_header:
    case True{}: prepend_panel_header(value, parts)
    case False{}: append_body(value, parts)

def partition_dialog_children(values: +List<UI.Node>, +context: Controls.Context) -> DialogParts:
  match values:
    case Nil{}: DialogParts{Nil{}, Nil{}}
    case Con{+value, rest}:
      partition_child(value, header_child(value, context), partition_dialog_children(rest, context))

def ordered_dialog_children(parts: DialogParts) -> +List<UI.Node>:
  DialogParts{+header, +body} = parts
  List.append(&2, UI.Node, header, body)

def partition_header(parts: DialogParts) -> +List<UI.Node>:
  DialogParts{+header, +body} = parts
  header

def partition_body(parts: DialogParts) -> +List<UI.Node>:
  DialogParts{+header, +body} = parts
  body

def ordered_children(role: UI.Role, values: +List<UI.Node>, +context: Controls.Context) -> +List<UI.Node>:
  match role:
    case UI.Dialog{}:
      ordered_dialog_children(partition_dialog_children(values, context))
    case _: values

def node_with_children(value: UI.Node, +children: +List<UI.Node>) -> UI.Node:
  UI.Node{key, semantic, label, role, meaning, original_children} = value
  UI.Node{key, semantic, label, role, meaning, children}

def ordered_nodes(values: +List<UI.Node>, +context: Controls.Context) -> +List<UI.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      UI.Node{+key, semantic, label, +role, +meaning, children} = value
      +local = Controls.enter(value, context)
      Con{node_with_children(value, ordered_children(role, ordered_nodes(children, local), local)),
        ordered_nodes(rest, context)}

def ordered_surface(surface: UI.Surface) -> UI.Surface:
  UI.Surface{+content, base, overlays, active_scope} = surface
  +context = Controls.initial(content)
  UI.Surface{content, ordered_nodes(base, context), ordered_nodes(overlays, context), active_scope}
