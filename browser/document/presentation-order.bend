import Base
import ../../interaction/IDENTITY.bend as UIIdentity
import ../controls/PROGRAM.bend as Controls
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes

type BaseRegion is Data:
  NavigationRegion{}
  MainRegion{}
  NavigationFooterRegion{}
  OtherRegion{}

type BaseParts is Data:
  BaseParts{navigation: +List<SurfaceTypes.Node>, footer: +List<SurfaceTypes.Node>, main: +List<SurfaceTypes.Node>, other: +List<SurfaceTypes.Node>}

def is_navigation(+key: UIIdentity.Key, role: SurfaceTypes.Role) -> Bool:
  match role:
    case SurfaceTypes.Navigation{}: True{}
    case _: UIIdentity.same(key, UIIdentity.part(UIIdentity.place("/navigation"), "navigation/toggle"))

def footer_region(found: Bool) -> BaseRegion:
  match found:
    case True{}: NavigationFooterRegion{}
    case False{}: OtherRegion{}

def base_region_role(key: UIIdentity.Key, role: SurfaceTypes.Role) -> BaseRegion:
  match role:
    case SurfaceTypes.Main{}: MainRegion{}
    case _: footer_region(UIIdentity.same(key, UIIdentity.part(UIIdentity.place(""), "settings/open")))

def base_region_navigation(found: Bool, key: UIIdentity.Key, role: SurfaceTypes.Role) -> BaseRegion:
  match found:
    case True{}: NavigationRegion{}
    case False{}: base_region_role(key, role)

def base_region(+key: UIIdentity.Key, +role: SurfaceTypes.Role) -> BaseRegion:
  base_region_navigation(is_navigation(key, role), key, role)

def prepend_base(region: BaseRegion, node: SurfaceTypes.Node, parts: BaseParts) -> BaseParts:
  match region parts:
    case NavigationRegion{} BaseParts{navigation, footer, main, other}: BaseParts{node <> navigation, footer, main, other}
    case NavigationFooterRegion{} BaseParts{navigation, footer, main, other}: BaseParts{navigation, node <> footer, main, other}
    case MainRegion{} BaseParts{navigation, footer, main, other}: BaseParts{navigation, footer, node <> main, other}
    case OtherRegion{} BaseParts{navigation, footer, main, other}: BaseParts{navigation, footer, main, node <> other}

def partition_base(values: +List<SurfaceTypes.Node>) -> BaseParts:
  match values:
    case Nil{}: BaseParts{Nil{}, Nil{}, Nil{}, Nil{}}
    case Con{+node, rest}:
      SurfaceTypes.Node{key, semantic, label, role, meaning, children} = node
      prepend_base(base_region(key, role), node, partition_base(rest))

def flatten_base(parts: BaseParts) -> +List<SurfaceTypes.Node>:
  BaseParts{navigation, footer, main, other} = parts
  List.append(&2, SurfaceTypes.Node, navigation, List.append(&2, SurfaceTypes.Node, footer, List.append(&2, SurfaceTypes.Node, main, other)))

def ordered_base(values: +List<SurfaceTypes.Node>) -> +List<SurfaceTypes.Node>:
  flatten_base(partition_base(values))

type DialogParts is Data:
  DialogParts{header: +List<SurfaceTypes.Node>, body: +List<SurfaceTypes.Node>}

def header_child(+value: SurfaceTypes.Node, +context: Controls.Context) -> Bool:
  SurfaceTypes.Node{+key, semantic, label, +role, +meaning, children} = value
  +local = Controls.enter(value, context)
  Controls.panel_header(Controls.represent(key, meaning, label, role, local))

def prepend_panel_header(value: SurfaceTypes.Node, parts: DialogParts) -> DialogParts:
  DialogParts{+headers, +body} = parts
  DialogParts{value <> headers, body}

def append_body(value: SurfaceTypes.Node, parts: DialogParts) -> DialogParts:
  DialogParts{+headers, +body} = parts
  DialogParts{headers, value <> body}

def partition_child(value: SurfaceTypes.Node, is_panel_header: Bool, parts: DialogParts) -> DialogParts:
  match is_panel_header:
    case True{}: prepend_panel_header(value, parts)
    case False{}: append_body(value, parts)

def partition_dialog_children(values: +List<SurfaceTypes.Node>, +context: Controls.Context) -> DialogParts:
  match values:
    case Nil{}: DialogParts{Nil{}, Nil{}}
    case Con{+value, rest}:
      partition_child(value, header_child(value, context), partition_dialog_children(rest, context))

def ordered_dialog_children(parts: DialogParts) -> +List<SurfaceTypes.Node>:
  DialogParts{+header, +body} = parts
  List.append(&2, SurfaceTypes.Node, header, body)

def partition_header(parts: DialogParts) -> +List<SurfaceTypes.Node>:
  DialogParts{+header, +body} = parts
  header

def partition_body(parts: DialogParts) -> +List<SurfaceTypes.Node>:
  DialogParts{+header, +body} = parts
  body

def ordered_children(role: SurfaceTypes.Role, values: +List<SurfaceTypes.Node>, +context: Controls.Context) -> +List<SurfaceTypes.Node>:
  match role:
    case SurfaceTypes.Dialog{}:
      ordered_dialog_children(partition_dialog_children(values, context))
    case _: values

def node_with_children(value: SurfaceTypes.Node, +children: +List<SurfaceTypes.Node>) -> SurfaceTypes.Node:
  SurfaceTypes.Node{key, semantic, label, role, meaning, original_children} = value
  SurfaceTypes.Node{key, semantic, label, role, meaning, children}

def ordered_nodes(values: +List<SurfaceTypes.Node>, +context: Controls.Context) -> +List<SurfaceTypes.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      SurfaceTypes.Node{+key, semantic, label, +role, +meaning, children} = value
      +local = Controls.enter(value, context)
      Con{node_with_children(value, ordered_children(role, ordered_nodes(children, local), local)),
        ordered_nodes(rest, context)}

def ordered_surface(surface: SurfaceTypes.Surface) -> SurfaceTypes.Surface:
  SurfaceTypes.Surface{+content, base, overlays, active_scope} = surface
  +context = Controls.initial(content)
  SurfaceTypes.Surface{content, ordered_base(ordered_nodes(base, context)), ordered_nodes(overlays, context), active_scope}
