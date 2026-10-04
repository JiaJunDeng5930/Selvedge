import Base
import ../core/interface.bend as UI
import ../core/SYSTEM.bend as Core
import ./MODEL.bend as Model
import ./controls.bend as Controls
import ./design.bend as Design
import ./visibility.bend as Visibility
import ./presentation-order.bend as Order
import ./platform.bend as Platform
import ./rendered.bend as Rendered
import ./presentation-laws.bend as PresentationLaws
import ./font-observation.bend as F

type NodePayload is Data:
  NodePayload{key: String, semantic: String, label: String, role: UI.Role, meaning: UI.Meaning}

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

def FrameProjectionClaim(outcome: Model.SceneOutcome, projected: Maybe<&2, UI.Surface>) -> Type:
  match outcome:
    case Model.ReadyScene{scene}:
      {projected == Some{Visibility.project(PresentationLaws.scene_surface(scene), PresentationLaws.scene_layout(scene))} : Maybe<&2, UI.Surface>}
    case _: {projected == None{} : Maybe<&2, UI.Surface>}

def occurrence_step(included: Bool, rest: Nat) -> Nat:
  match included:
    case True{}: Nat.add(1n, rest)
    case False{}: rest

type CountPredicate is Data:
  CountAll{}
  CountKey{key: String}

def count_matches(predicate: CountPredicate, value: UI.Node) -> Bool:
  match predicate:
    case CountAll{}: True{}
    case CountKey{key}: String.eq(UI.node_key(value), key)

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
      {count_by(CountKey{UI.node_key(target)},
          Order.ordered_dialog_children(Order.partition_dialog_children(values, context))) ==
        count_by(CountKey{UI.node_key(target)}, values) : Nat},
    ordered_children_reference: @values:+List<UI.Node> -> @role:UI.Role -> @context:Controls.Context ->
      {Order.ordered_children(role, values, context) == specified_children(role, values, context) : +List<UI.Node>},
    dialog_order_idempotent: @values:+List<UI.Node> -> @context:Controls.Context ->
      {Order.ordered_children(UI.Dialog{}, Order.ordered_children(UI.Dialog{}, values, context), context) ==
        Order.ordered_children(UI.Dialog{}, values, context) : +List<UI.Node>},
    node_payload_preserved: @value:UI.Node -> @children:+List<UI.Node> ->
      {node_payload(Order.node_with_children(value, children)) == node_payload(value) : NodePayload},
    surface_content_scope_preserved: @surface:UI.Surface ->
      {surface_payload(Order.ordered_surface(surface)) == surface_payload(surface) : SurfacePayload},
    scene_uses_ordered_surface: @environment:Design.Environment -> @+application:Platform.State ->
      @generation:Nat -> @realization:Rendered.State -> @font:F.State ->
      PresentationLaws.SemanticClaim(Model.observe(Model.State{application, generation, realization, environment, font}),
        Order.ordered_surface(Model.surface(application))),
    frame_uses_ordered_projection: @+state:Model.State -> @+surface:UI.Surface ->
      FrameProjectionClaim(Model.scene_for_surface(state, Order.ordered_surface(surface)), Model.frame_surface(state, surface))
  }

law evidence:
  Requirements
