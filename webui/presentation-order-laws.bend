import Base
import ../core/ui-identity.bend as UIIdentity
import ../core/interface.bend as UI
import ../core/SYSTEM.bend as Core
import ./MODEL.bend as Model
import ./controls.bend as Controls
import ./design.bend as Design
import ./presentation-order.bend as Order
import ./platform.bend as Platform
import ./rendered.bend as Rendered
import ./font-observation.bend as F

type NodePayload is Data:
  NodePayload{key: UIIdentity.Key, semantic: String, label: String, role: UI.Role, meaning: UI.Meaning}

type SurfacePayload is Data:
  SurfacePayload{content: Core.Scene, scope: Maybe<&2, String>}

def node_payload(value: UI.Node) -> NodePayload:
  UI.Node{key, semantic, label, role, meaning, children} = value
  NodePayload{key, semantic, label, role, meaning}

def surface_payload(surface: UI.Surface) -> SurfacePayload:
  UI.Surface{content, base, overlays, active_scope} = surface
  SurfacePayload{content, active_scope}

def specified_header_representation(representation: Controls.Representation) -> Bool:
  match representation:
    case Controls.Action{input, availability, name, face, behavior, geometry, Controls.PanelHeaderEnd{}, help, feedback}: True{}
    case _: False{}

def specified_header_child(+value: UI.Node, +context: Controls.Context) -> Bool:
  UI.Node{+key, semantic, label, +role, +meaning, children} = value
  +local = Controls.enter(value, context)
  specified_header_representation(Controls.represent(key, meaning, label, role, local))

def header_step(value: UI.Node, include: Bool, +tail: +List<UI.Node>) -> +List<UI.Node>:
  match include:
    case True{}: value <> tail
    case False{}: tail

def body_step(value: UI.Node, include: Bool, +tail: +List<UI.Node>) -> +List<UI.Node>:
  match include:
    case True{}: tail
    case False{}: value <> tail

def specified_header(values: +List<UI.Node>, +context: Controls.Context) -> +List<UI.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      header_step(value, specified_header_child(value, context), specified_header(rest, context))

def specified_body(values: +List<UI.Node>, +context: Controls.Context) -> +List<UI.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      body_step(value, specified_header_child(value, context), specified_body(rest, context))

def specified_parts(+values: +List<UI.Node>, +context: Controls.Context) -> Order.DialogParts:
  Order.DialogParts{specified_header(values, context), specified_body(values, context)}

def specified_order(+values: +List<UI.Node>, +context: Controls.Context) -> +List<UI.Node>:
  List.append(&2, UI.Node, specified_header(values, context), specified_body(values, context))

def specified_children(role: UI.Role, values: +List<UI.Node>, +context: Controls.Context) -> +List<UI.Node>:
  match role:
    case UI.Dialog{}:
      specified_order(values, context)
    case _: values

def non_dialog_order_observation(role: UI.Role, +values: +List<UI.Node>, +context: Controls.Context) -> +List<UI.Node>:
  match role:
    case UI.Dialog{}: values
    case _: Order.ordered_children(role, values, context)

def occurrence_step(included: Bool, rest: Nat) -> Nat:
  match included:
    case True{}: Nat.add(1n, rest)
    case False{}: rest

def count_key(node: UI.Node) -> UIIdentity.Key:
  UI.Node{key, semantic, label, role, meaning, children} = node
  key

type CountPredicate is Data:
  CountAll{}
  CountKey{key: UIIdentity.Key}

def count_matches(predicate: CountPredicate, value: UI.Node) -> Bool:
  match predicate:
    case CountAll{}: True{}
    case CountKey{key}: String.eq(UI.node_key(value), UIIdentity.encode(key))

def count_by(+predicate: CountPredicate, values: +List<UI.Node>) -> Nat:
  match values:
    case Nil{}: 0n
    case Con{+value, rest}: occurrence_step(count_matches(predicate, value), count_by(predicate, rest))

type Requirements is Type:
  Requirements{
    non_dialog_order: @role:UI.Role -> @values:+List<UI.Node> -> @context:Controls.Context ->
      {non_dialog_order_observation(role, values, context) == values : +List<UI.Node>},
    dialog_partition_specification: @values:+List<UI.Node> -> @context:Controls.Context ->
      {Order.partition_dialog_children(values, context) == specified_parts(values, context) : Order.DialogParts},
    dialog_partition_length: @values:+List<UI.Node> -> @context:Controls.Context ->
      {List.length(&2, UI.Node, Order.ordered_dialog_children(Order.partition_dialog_children(values, context))) ==
        List.length(&2, UI.Node, values) : Nat},
    dialog_partition_occurrences: @target:UI.Node -> @values:+List<UI.Node> -> @context:Controls.Context ->
      {count_by(CountKey{count_key(target)},
          Order.ordered_dialog_children(Order.partition_dialog_children(values, context))) ==
        count_by(CountKey{count_key(target)}, values) : Nat},
    ordered_children_reference: @values:+List<UI.Node> -> @role:UI.Role -> @context:Controls.Context ->
      {Order.ordered_children(role, values, context) == specified_children(role, values, context) : +List<UI.Node>},
    dialog_order_idempotent: @values:+List<UI.Node> -> @context:Controls.Context ->
      {Order.ordered_children(UI.Dialog{}, Order.ordered_children(UI.Dialog{}, values, context), context) ==
        Order.ordered_children(UI.Dialog{}, values, context) : +List<UI.Node>},
    node_payload_preserved: @value:UI.Node -> @children:+List<UI.Node> ->
      {node_payload(Order.node_with_children(value, children)) == node_payload(value) : NodePayload},
    surface_content_scope_preserved: @surface:UI.Surface ->
      {surface_payload(Order.ordered_surface(surface)) == surface_payload(surface) : SurfacePayload},
    model_observes_ordered_surface: @environment:Design.Environment -> @+application:Platform.State ->
      @generation:Nat -> @realization:Rendered.State -> @font:F.State ->
      {Model.observed_surface(Model.State{application, generation, realization, environment, font}) ==
        Order.ordered_surface(Model.surface(application)) : UI.Surface}
  }

law evidence:
  Requirements

law base_classifier:
  for +key: UIIdentity.Key
  for +role: UI.Role
  {Order.base_region(key, role) == Order.base_region_navigation(Order.is_navigation(key, role), key, role) : Order.BaseRegion}

law navigation_role:
  for +key: UIIdentity.Key
  {Order.base_region(key, UI.Navigation{}) == Order.NavigationRegion{} : Order.BaseRegion}

law navigation_precedence:
  for +key: UIIdentity.Key
  for +role: UI.Role
  {Order.base_region_navigation(True{}, key, role) == Order.NavigationRegion{} : Order.BaseRegion}

law remaining_region:
  for +key: UIIdentity.Key
  for +role: UI.Role
  {Order.base_region_navigation(False{}, key, role) == Order.base_region_role(key, role) : Order.BaseRegion}

law main_precedence:
  for +key: UIIdentity.Key
  {Order.base_region_role(key, UI.Main{}) == Order.MainRegion{} : Order.BaseRegion}

law footer_region:
  {Order.footer_region(True{}) == Order.NavigationFooterRegion{} : Order.BaseRegion}

law other_region:
  {Order.footer_region(False{}) == Order.OtherRegion{} : Order.BaseRegion}

law base_partition_navigation:
  for +node: UI.Node
  for +navigation: +List<UI.Node>
  for +footer: +List<UI.Node>
  for +main: +List<UI.Node>
  for +other: +List<UI.Node>
  {Order.prepend_base(Order.NavigationRegion{}, node, Order.BaseParts{navigation, footer, main, other}) == Order.BaseParts{node <> navigation, footer, main, other} : Order.BaseParts}

law base_partition_footer:
  for +node: UI.Node
  for +navigation: +List<UI.Node>
  for +footer: +List<UI.Node>
  for +main: +List<UI.Node>
  for +other: +List<UI.Node>
  {Order.prepend_base(Order.NavigationFooterRegion{}, node, Order.BaseParts{navigation, footer, main, other}) == Order.BaseParts{navigation, node <> footer, main, other} : Order.BaseParts}

law base_partition_main:
  for +node: UI.Node
  for +navigation: +List<UI.Node>
  for +footer: +List<UI.Node>
  for +main: +List<UI.Node>
  for +other: +List<UI.Node>
  {Order.prepend_base(Order.MainRegion{}, node, Order.BaseParts{navigation, footer, main, other}) == Order.BaseParts{navigation, footer, node <> main, other} : Order.BaseParts}

law base_partition_other:
  for +node: UI.Node
  for +navigation: +List<UI.Node>
  for +footer: +List<UI.Node>
  for +main: +List<UI.Node>
  for +other: +List<UI.Node>
  {Order.prepend_base(Order.OtherRegion{}, node, Order.BaseParts{navigation, footer, main, other}) == Order.BaseParts{navigation, footer, main, node <> other} : Order.BaseParts}

law base_partition_empty:
  {Order.partition_base(Nil{}) == Order.BaseParts{Nil{}, Nil{}, Nil{}, Nil{}} : Order.BaseParts}

law base_partition_step:
  for +key: UIIdentity.Key
  for +semantic: String
  for +label: String
  for +role: UI.Role
  for +meaning: UI.Meaning
  for +children: +List<UI.Node>
  for +rest: +List<UI.Node>
  {Order.partition_base(UI.Node{key, semantic, label, role, meaning, children} <> rest) == Order.prepend_base(Order.base_region(key, role), UI.Node{key, semantic, label, role, meaning, children}, Order.partition_base(rest)) : Order.BaseParts}

law base_region_order:
  for +navigation: +List<UI.Node>
  for +footer: +List<UI.Node>
  for +main: +List<UI.Node>
  for +other: +List<UI.Node>
  {Order.flatten_base(Order.BaseParts{navigation, footer, main, other}) == List.append(&2, UI.Node, navigation, List.append(&2, UI.Node, footer, List.append(&2, UI.Node, main, other))) : +List<UI.Node>}

law ordered_base_partition:
  for +values: +List<UI.Node>
  {Order.ordered_base(values) == Order.flatten_base(Order.partition_base(values)) : +List<UI.Node>}

law ordered_surface_base:
  for +content: Core.Scene
  for +base: +List<UI.Node>
  for +overlays: +List<UI.Node>
  for +scope: Maybe<&2, String>
  {Order.ordered_surface(UI.Surface{content, base, overlays, scope}) == UI.Surface{content, Order.ordered_base(Order.ordered_nodes(base, Controls.initial(content))), Order.ordered_nodes(overlays, Controls.initial(content)), scope} : UI.Surface}

def non_main_role(role: UI.Role) -> Bool:
  match role:
    case UI.Main{}: False{}
    case _: True{}

law remaining_role_classification:
  for +key: UIIdentity.Key
  for +role: UI.Role
  for belongs: {non_main_role(role) == True{} : Bool}
  {Order.base_region_role(key, role) == Order.footer_region(UIIdentity.same(key, UIIdentity.part(UIIdentity.place(""), "settings/open"))) : Order.BaseRegion}
