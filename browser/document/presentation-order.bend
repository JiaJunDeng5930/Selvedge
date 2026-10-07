import ../../interaction/IDENTITY.bend as UIIdentity
import Base
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../controls/PROGRAM.bend as Controls

type BaseRegion is Data:
  NavigationRegion{}
  MainRegion{}
  NavigationFooterRegion{}
  OtherRegion{}

type BaseParts is Data:
  BaseParts{navigation: +List<InterfaceView.Node>, footer: +List<InterfaceView.Node>, main: +List<InterfaceView.Node>, other: +List<InterfaceView.Node>}

def is_navigation(+key: UIIdentity.Key, role: InterfaceView.Role) -> Bool:
  match role:
    case InterfaceView.Navigation{}: True{}
    case _: UIIdentity.same(key, UIIdentity.part(UIIdentity.place("/navigation"), "navigation/toggle"))

def footer_region(found: Bool) -> BaseRegion:
  match found:
    case True{}: NavigationFooterRegion{}
    case False{}: OtherRegion{}

def base_region_role(key: UIIdentity.Key, role: InterfaceView.Role) -> BaseRegion:
  match role:
    case InterfaceView.Main{}: MainRegion{}
    case _: footer_region(UIIdentity.same(key, UIIdentity.part(UIIdentity.place(""), "settings/open")))

def base_region_navigation(found: Bool, key: UIIdentity.Key, role: InterfaceView.Role) -> BaseRegion:
  match found:
    case True{}: NavigationRegion{}
    case False{}: base_region_role(key, role)

def base_region(+key: UIIdentity.Key, +role: InterfaceView.Role) -> BaseRegion:
  base_region_navigation(is_navigation(key, role), key, role)

def prepend_base(region: BaseRegion, node: InterfaceView.Node, parts: BaseParts) -> BaseParts:
  match region parts:
    case NavigationRegion{} BaseParts{navigation, footer, main, other}: BaseParts{node <> navigation, footer, main, other}
    case NavigationFooterRegion{} BaseParts{navigation, footer, main, other}: BaseParts{navigation, node <> footer, main, other}
    case MainRegion{} BaseParts{navigation, footer, main, other}: BaseParts{navigation, footer, node <> main, other}
    case OtherRegion{} BaseParts{navigation, footer, main, other}: BaseParts{navigation, footer, main, node <> other}

def partition_base(values: +List<InterfaceView.Node>) -> BaseParts:
  match values:
    case Nil{}: BaseParts{Nil{}, Nil{}, Nil{}, Nil{}}
    case Con{+node, rest}:
      InterfaceView.Node{key, semantic, label, role, meaning, children} = node
      prepend_base(base_region(key, role), node, partition_base(rest))

def flatten_base(parts: BaseParts) -> +List<InterfaceView.Node>:
  BaseParts{navigation, footer, main, other} = parts
  List.append(&2, InterfaceView.Node, navigation, List.append(&2, InterfaceView.Node, footer, List.append(&2, InterfaceView.Node, main, other)))

def ordered_base(values: +List<InterfaceView.Node>) -> +List<InterfaceView.Node>:
  flatten_base(partition_base(values))

type DialogParts is Data:
  DialogParts{header: +List<InterfaceView.Node>, body: +List<InterfaceView.Node>}

def header_child(+value: InterfaceView.Node, +context: Controls.Context) -> Bool:
  InterfaceView.Node{+key, semantic, label, +role, +meaning, children} = value
  +local = Controls.enter(value, context)
  Controls.panel_header(Controls.represent(key, meaning, label, role, local))

def prepend_panel_header(value: InterfaceView.Node, parts: DialogParts) -> DialogParts:
  DialogParts{+headers, +body} = parts
  DialogParts{value <> headers, body}

def append_body(value: InterfaceView.Node, parts: DialogParts) -> DialogParts:
  DialogParts{+headers, +body} = parts
  DialogParts{headers, value <> body}

def partition_child(value: InterfaceView.Node, is_panel_header: Bool, parts: DialogParts) -> DialogParts:
  match is_panel_header:
    case True{}: prepend_panel_header(value, parts)
    case False{}: append_body(value, parts)

def partition_dialog_children(values: +List<InterfaceView.Node>, +context: Controls.Context) -> DialogParts:
  match values:
    case Nil{}: DialogParts{Nil{}, Nil{}}
    case Con{+value, rest}:
      partition_child(value, header_child(value, context), partition_dialog_children(rest, context))

def ordered_dialog_children(parts: DialogParts) -> +List<InterfaceView.Node>:
  DialogParts{+header, +body} = parts
  List.append(&2, InterfaceView.Node, header, body)

def partition_header(parts: DialogParts) -> +List<InterfaceView.Node>:
  DialogParts{+header, +body} = parts
  header

def partition_body(parts: DialogParts) -> +List<InterfaceView.Node>:
  DialogParts{+header, +body} = parts
  body

def ordered_children(role: InterfaceView.Role, values: +List<InterfaceView.Node>, +context: Controls.Context) -> +List<InterfaceView.Node>:
  match role:
    case InterfaceView.Dialog{}:
      ordered_dialog_children(partition_dialog_children(values, context))
    case _: values

def node_with_children(value: InterfaceView.Node, +children: +List<InterfaceView.Node>) -> InterfaceView.Node:
  InterfaceView.Node{key, semantic, label, role, meaning, original_children} = value
  InterfaceView.Node{key, semantic, label, role, meaning, children}

def ordered_nodes(values: +List<InterfaceView.Node>, +context: Controls.Context) -> +List<InterfaceView.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      InterfaceView.Node{+key, semantic, label, +role, +meaning, children} = value
      +local = Controls.enter(value, context)
      Con{node_with_children(value, ordered_children(role, ordered_nodes(children, local), local)),
        ordered_nodes(rest, context)}

def ordered_surface(surface: InterfaceView.Surface) -> InterfaceView.Surface:
  InterfaceView.Surface{+content, base, overlays, active_scope} = surface
  +context = Controls.initial(content)
  InterfaceView.Surface{content, ordered_base(ordered_nodes(base, context)), ordered_nodes(overlays, context), active_scope}
