import Base
import ../../interaction/IDENTITY.bend as UIIdentity
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/STATE.bend as Core
import ../MODEL.bend as Model
import ../controls/PROGRAM.bend as Controls
import ../appearance/DESIGN.bend as Design
import ./presentation-order.bend as Order
import ../runtime/PLATFORM.bend as Platform
import ./RENDERED.bend as Rendered
import ../appearance/FONT.bend as F
type NodePayload is Data:
  NodePayload{key: UIIdentity.Key, semantic: String, label: String, role: InterfaceView.Role, meaning: InterfaceView.Meaning}
type SurfacePayload is Data:
  SurfacePayload{content: Core.Scene, scope: Maybe<&2, String>}
def node_payload(value: InterfaceView.Node) -> NodePayload:
  InterfaceView.Node{key, semantic, label, role, meaning, children} = value
  NodePayload{key, semantic, label, role, meaning}

def surface_payload(surface: InterfaceView.Surface) -> SurfacePayload:
  InterfaceView.Surface{content, base, overlays, active_scope} = surface
  SurfacePayload{content, active_scope}

def specified_header_representation(representation: Controls.Representation) -> Bool:
  match representation:
    case Controls.Action{input, availability, name, face, behavior, geometry, Controls.PanelHeaderEnd{}, help, feedback}: True{}
    case _: False{}

def specified_header_child(+value: InterfaceView.Node, +context: Controls.Context) -> Bool:
  InterfaceView.Node{+key, semantic, label, +role, +meaning, children} = value
  +local = Controls.enter(value, context)
  specified_header_representation(Controls.represent(key, meaning, label, role, local))

def header_step(value: InterfaceView.Node, include: Bool, +tail: +List<InterfaceView.Node>) -> +List<InterfaceView.Node>:
  match include:
    case True{}: value <> tail
    case False{}: tail

def body_step(value: InterfaceView.Node, include: Bool, +tail: +List<InterfaceView.Node>) -> +List<InterfaceView.Node>:
  match include:
    case True{}: tail
    case False{}: value <> tail

def specified_header(values: +List<InterfaceView.Node>, +context: Controls.Context) -> +List<InterfaceView.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      header_step(value, specified_header_child(value, context), specified_header(rest, context))

def specified_body(values: +List<InterfaceView.Node>, +context: Controls.Context) -> +List<InterfaceView.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      body_step(value, specified_header_child(value, context), specified_body(rest, context))

def specified_parts(+values: +List<InterfaceView.Node>, +context: Controls.Context) -> Order.DialogParts:
  Order.DialogParts{specified_header(values, context), specified_body(values, context)}

def specified_order(+values: +List<InterfaceView.Node>, +context: Controls.Context) -> +List<InterfaceView.Node>:
  List.append(&2, InterfaceView.Node, specified_header(values, context), specified_body(values, context))

def specified_children(role: InterfaceView.Role, values: +List<InterfaceView.Node>, +context: Controls.Context) -> +List<InterfaceView.Node>:
  match role:
    case InterfaceView.Dialog{}:
      specified_order(values, context)
    case _: values

def non_dialog_order_observation(role: InterfaceView.Role, +values: +List<InterfaceView.Node>, +context: Controls.Context) -> +List<InterfaceView.Node>:
  match role:
    case InterfaceView.Dialog{}: values
    case _: Order.ordered_children(role, values, context)

def occurrence_step(included: Bool, rest: Nat) -> Nat:
  match included:
    case True{}: Nat.add(1n, rest)
    case False{}: rest

def count_key(node: InterfaceView.Node) -> UIIdentity.Key:
  InterfaceView.Node{key, semantic, label, role, meaning, children} = node
  key

type CountPredicate is Data:
  CountAll{}
  CountKey{key: UIIdentity.Key}
def count_matches(predicate: CountPredicate, value: InterfaceView.Node) -> Bool:
  match predicate:
    case CountAll{}: True{}
    case CountKey{key}: String.eq(InterfaceView.node_key(value), UIIdentity.encode(key))

def count_by(+predicate: CountPredicate, values: +List<InterfaceView.Node>) -> Nat:
  match values:
    case Nil{}: 0n
    case Con{+value, rest}: occurrence_step(count_matches(predicate, value), count_by(predicate, rest))

type Requirements is Type:
  Requirements{
    non_dialog_order: @role:InterfaceView.Role -> @values:+List<InterfaceView.Node> -> @context:Controls.Context ->
      {non_dialog_order_observation(role, values, context) == values : +List<InterfaceView.Node>},
    dialog_partition_specification: @values:+List<InterfaceView.Node> -> @context:Controls.Context ->
      {Order.partition_dialog_children(values, context) == specified_parts(values, context) : Order.DialogParts},
    dialog_partition_length: @values:+List<InterfaceView.Node> -> @context:Controls.Context ->
      {List.length(&2, InterfaceView.Node, Order.ordered_dialog_children(Order.partition_dialog_children(values, context))) ==
        List.length(&2, InterfaceView.Node, values) : Nat},
    dialog_partition_occurrences: @target:InterfaceView.Node -> @values:+List<InterfaceView.Node> -> @context:Controls.Context ->
      {count_by(CountKey{count_key(target)},
          Order.ordered_dialog_children(Order.partition_dialog_children(values, context))) ==
        count_by(CountKey{count_key(target)}, values) : Nat},
    ordered_children_reference: @values:+List<InterfaceView.Node> -> @role:InterfaceView.Role -> @context:Controls.Context ->
      {Order.ordered_children(role, values, context) == specified_children(role, values, context) : +List<InterfaceView.Node>},
    dialog_order_idempotent: @values:+List<InterfaceView.Node> -> @context:Controls.Context ->
      {Order.ordered_children(InterfaceView.Dialog{}, Order.ordered_children(InterfaceView.Dialog{}, values, context), context) ==
        Order.ordered_children(InterfaceView.Dialog{}, values, context) : +List<InterfaceView.Node>},
    node_payload_preserved: @value:InterfaceView.Node -> @children:+List<InterfaceView.Node> ->
      {node_payload(Order.node_with_children(value, children)) == node_payload(value) : NodePayload},
    surface_content_scope_preserved: @surface:InterfaceView.Surface ->
      {surface_payload(Order.ordered_surface(surface)) == surface_payload(surface) : SurfacePayload},
    model_observes_ordered_surface: @+model_state:Model.State ->  {Model.observed_surface(model_state) ==
        Order.ordered_surface(Model.surface(Model.application(model_state))) : InterfaceView.Surface}
  }
law evidence:
  Requirements
law base_classifier:
  for +key: UIIdentity.Key
  for +role: InterfaceView.Role
  {Order.base_region(key, role) == Order.base_region_navigation(Order.is_navigation(key, role), key, role) : Order.BaseRegion}
law navigation_role:
  for +key: UIIdentity.Key
  {Order.base_region(key, InterfaceView.Navigation{}) == Order.NavigationRegion{} : Order.BaseRegion}
law navigation_precedence:
  for +key: UIIdentity.Key
  for +role: InterfaceView.Role
  {Order.base_region_navigation(True{}, key, role) == Order.NavigationRegion{} : Order.BaseRegion}
law remaining_region:
  for +key: UIIdentity.Key
  for +role: InterfaceView.Role
  {Order.base_region_navigation(False{}, key, role) == Order.base_region_role(key, role) : Order.BaseRegion}
law main_precedence:
  for +key: UIIdentity.Key
  {Order.base_region_role(key, InterfaceView.Main{}) == Order.MainRegion{} : Order.BaseRegion}
law footer_region:
  {Order.footer_region(True{}) == Order.NavigationFooterRegion{} : Order.BaseRegion}
law other_region:
  {Order.footer_region(False{}) == Order.OtherRegion{} : Order.BaseRegion}
law base_partition_navigation:
  for +node: InterfaceView.Node
  for +navigation: +List<InterfaceView.Node>
  for +footer: +List<InterfaceView.Node>
  for +main: +List<InterfaceView.Node>
  for +other: +List<InterfaceView.Node>
  {Order.prepend_base(Order.NavigationRegion{}, node, Order.BaseParts{navigation, footer, main, other}) == Order.BaseParts{node <> navigation, footer, main, other} : Order.BaseParts}
law base_partition_footer:
  for +node: InterfaceView.Node
  for +navigation: +List<InterfaceView.Node>
  for +footer: +List<InterfaceView.Node>
  for +main: +List<InterfaceView.Node>
  for +other: +List<InterfaceView.Node>
  {Order.prepend_base(Order.NavigationFooterRegion{}, node, Order.BaseParts{navigation, footer, main, other}) == Order.BaseParts{navigation, node <> footer, main, other} : Order.BaseParts}
law base_partition_main:
  for +node: InterfaceView.Node
  for +navigation: +List<InterfaceView.Node>
  for +footer: +List<InterfaceView.Node>
  for +main: +List<InterfaceView.Node>
  for +other: +List<InterfaceView.Node>
  {Order.prepend_base(Order.MainRegion{}, node, Order.BaseParts{navigation, footer, main, other}) == Order.BaseParts{navigation, footer, node <> main, other} : Order.BaseParts}
law base_partition_other:
  for +node: InterfaceView.Node
  for +navigation: +List<InterfaceView.Node>
  for +footer: +List<InterfaceView.Node>
  for +main: +List<InterfaceView.Node>
  for +other: +List<InterfaceView.Node>
  {Order.prepend_base(Order.OtherRegion{}, node, Order.BaseParts{navigation, footer, main, other}) == Order.BaseParts{navigation, footer, main, node <> other} : Order.BaseParts}
law base_partition_empty:
  {Order.partition_base(Nil{}) == Order.BaseParts{Nil{}, Nil{}, Nil{}, Nil{}} : Order.BaseParts}
law base_partition_step:
  for +key: UIIdentity.Key
  for +semantic: String
  for +label: String
  for +role: InterfaceView.Role
  for +meaning: InterfaceView.Meaning
  for +children: +List<InterfaceView.Node>
  for +rest: +List<InterfaceView.Node>
  {Order.partition_base(InterfaceView.Node{key, semantic, label, role, meaning, children} <> rest) == Order.prepend_base(Order.base_region(key, role), InterfaceView.Node{key, semantic, label, role, meaning, children}, Order.partition_base(rest)) : Order.BaseParts}
law base_region_order:
  for +navigation: +List<InterfaceView.Node>
  for +footer: +List<InterfaceView.Node>
  for +main: +List<InterfaceView.Node>
  for +other: +List<InterfaceView.Node>
  {Order.flatten_base(Order.BaseParts{navigation, footer, main, other}) == List.append(&2, InterfaceView.Node, navigation, List.append(&2, InterfaceView.Node, footer, List.append(&2, InterfaceView.Node, main, other))) : +List<InterfaceView.Node>}
law ordered_base_partition:
  for +values: +List<InterfaceView.Node>
  {Order.ordered_base(values) == Order.flatten_base(Order.partition_base(values)) : +List<InterfaceView.Node>}
law ordered_surface_base:
  for +content: Core.Scene
  for +base: +List<InterfaceView.Node>
  for +overlays: +List<InterfaceView.Node>
  for +scope: Maybe<&2, String>
  {Order.ordered_surface(InterfaceView.Surface{content, base, overlays, scope}) == InterfaceView.Surface{content, Order.ordered_base(Order.ordered_nodes(base, Controls.initial(content))), Order.ordered_nodes(overlays, Controls.initial(content)), scope} : InterfaceView.Surface}
def non_main_role(role: InterfaceView.Role) -> Bool:
  match role:
    case InterfaceView.Main{}: False{}
    case _: True{}

law remaining_role_classification:
  for +key: UIIdentity.Key
  for +role: InterfaceView.Role
  for belongs: {non_main_role(role) == True{} : Bool}
  {Order.base_region_role(key, role) == Order.footer_region(UIIdentity.same(key, UIIdentity.part(UIIdentity.place(""), "settings/open"))) : Order.BaseRegion}
