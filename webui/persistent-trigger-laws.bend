import Base
import ../core/ui-identity.bend as UIIdentity
import ../core/interface.bend as InterfaceView
import ../core/SYSTEM.bend as Core
import ../core/user-input.bend as U
import ../core/user-experience.bend as E
import ../core/ui-world.bend as View
import ../core/client-services.bend as Services

def bit(value: Bool) -> Nat:
  match value:
    case True{}: 1n
    case False{}: 0n

def occurrences(nodes: +List<InterfaceView.Node>, +key: String) -> Nat:
  match nodes:
    case Nil{}: 0n
    case Con{InterfaceView.Node{+current, semantic, label, role, meaning, children}, rest}:
      Nat.add(bit(String.eq(UIIdentity.encode(current), key)),
        Nat.add(occurrences(children, key), occurrences(rest, key)))

def surface_occurrences(surface: InterfaceView.Surface, +key: String) -> Nat:
  InterfaceView.Surface{content, base, overlays, scope} = surface
  Nat.add(occurrences(base, key), occurrences(overlays, key))

type Requirements is Type:
  Requirements{
    removal: @nodes:+List<InterfaceView.Node> -> @+key:String -> {occurrences(InterfaceView.without_node(nodes, key), key) == 0n : Nat},
    actual_source: @+scene:Core.Scene -> @+base:+List<InterfaceView.Node> -> @+overlays:+List<InterfaceView.Node> -> @+trigger:String -> @+key:String -> @+node:InterfaceView.Node -> @+target:Nat ->
      @persistent:{InterfaceView.persistent_details_trigger(overlays) == Some{InterfaceView.PersistentTrigger{target, trigger}} : Maybe<&2, InterfaceView.PersistentTrigger>} ->
      @resolved:{InterfaceView.matching_focus(base, trigger) == Some{key} : Maybe<&2, String>} ->
      @found:{InterfaceView.find_node(base, key) == Some{node} : Maybe<&2, InterfaceView.Node>} ->
      {InterfaceView.finish_reachable(scene, base, overlays) == InterfaceView.relocate_found_trigger(Some{node}, target, scene, base, overlays) : InterfaceView.Surface},
    unique_trigger: @+scene:Core.Scene -> @+base:+List<InterfaceView.Node> -> @+key:UIIdentity.Key -> @+semantic:String -> @+label:String -> @+role:InterfaceView.Role ->
      @+meaning:InterfaceView.Meaning -> @+owner:UIIdentity.Key -> @+layer_semantic:String -> @+title:String -> @+policy:InterfaceView.Meaning ->
      @+body:+List<InterfaceView.Node> -> @+rest:+List<InterfaceView.Node> -> @+target:Nat ->
      @accepted:{InterfaceView.persistent_trigger_source(meaning, target) == True{} : Bool} -> @distinct:{String.eq(UIIdentity.encode(owner), UIIdentity.encode(key)) == False{} : Bool} ->
      @fresh:{Nat.add(occurrences(body, UIIdentity.encode(key)), occurrences(rest, UIIdentity.encode(key))) == 0n : Nat} ->
      {surface_occurrences(InterfaceView.relocate_found_trigger(Some{InterfaceView.Node{key, semantic, label, role, meaning, Nil{}}}, target,
        scene, base, InterfaceView.Node{owner, layer_semantic, title, InterfaceView.Dialog{}, policy, body} <> rest), UIIdentity.encode(key)) == 1n : Nat},
    production_details: @+task:Nat -> @+trigger:String -> @+content:View.LayerContent -> @+initial:String -> @+state:Core.State ->
      {InterfaceView.persistent_details_trigger(InterfaceView.layers([View.Layer{View.ModalDialog{}, content, initial, trigger,
        View.layer_dismissal(U.TaskDetails{task}, trigger)}], state)) == Some{InterfaceView.PersistentTrigger{task, trigger}} : Maybe<&2, InterfaceView.PersistentTrigger>},
    wrong_task_stays: @+scene: Core.Scene -> @+base: +List<InterfaceView.Node> -> @+overlays: +List<InterfaceView.Node> -> @+key: UIIdentity.Key -> @+semantic: String -> @+label: String -> @+role: InterfaceView.Role -> @+expanded: Bool -> @+source: Nat -> @+trigger: String -> @+availability: View.Availability -> @+children: +List<InterfaceView.Node> -> @+target: Nat -> @distinct: {Nat.is_eq(source, target) == False{} : Bool} ->
    {InterfaceView.relocate_found_trigger(Some{InterfaceView.Node{key, semantic, label, role,
            InterfaceView.PanelToggle{expanded, Core.ApplicationInput{E.UserInput{U.Activate{U.TogglePanel{U.TaskDetails{source}, trigger}}}}, availability}, children}},
          target, scene, base, overlays) == InterfaceView.finish(scene, base, overlays) : InterfaceView.Surface},
    wrong_input_stays: @+scene: Core.Scene -> @+base: +List<InterfaceView.Node> -> @+overlays: +List<InterfaceView.Node> -> @+key: UIIdentity.Key -> @+semantic: String -> @+label: String -> @+role: InterfaceView.Role -> @+expanded: Bool -> @+service: Services.Input -> @+availability: View.Availability -> @+children: +List<InterfaceView.Node> -> @+target: Nat ->
    {InterfaceView.relocate_found_trigger(Some{InterfaceView.Node{key, semantic, label, role,
            InterfaceView.PanelToggle{expanded, Core.ServiceInput{service}, availability}, children}}, target, scene, base, overlays) ==
          InterfaceView.finish(scene, base, overlays) : InterfaceView.Surface},
    navigation_kept: @+scene: Core.Scene -> @+nav: +List<InterfaceView.Node> -> @+reachable: InterfaceView.Surface -> @+settings: InterfaceView.Node -> @+scope: Maybe<&2, String> ->
    {InterfaceView.surface_base(InterfaceView.with_navigation(scene, nav, reachable, settings, scope)) ==
    List.append(&2, InterfaceView.Node, nav, List.append(&2, InterfaceView.Node, InterfaceView.surface_base(reachable), [settings])) : +List<InterfaceView.Node>},
    rejected_source_stays: @+scene: Core.Scene -> @+base: +List<InterfaceView.Node> -> @+overlays: +List<InterfaceView.Node> -> @+key: UIIdentity.Key -> @+semantic: String -> @+label: String -> @+role: InterfaceView.Role -> @+meaning: InterfaceView.Meaning -> @+children: +List<InterfaceView.Node> -> @+target: Nat -> @rejected: {InterfaceView.persistent_trigger_source(meaning, target) == False{} : Bool} ->
    {InterfaceView.relocate_found_trigger(Some{InterfaceView.Node{key, semantic, label, role, meaning, children}}, target, scene, base, overlays) ==
    InterfaceView.finish(scene, base, overlays) : InterfaceView.Surface},
    accepted_same_node: @+scene: Core.Scene -> @+base: +List<InterfaceView.Node> -> @+overlays: +List<InterfaceView.Node> -> @+key: UIIdentity.Key -> @+semantic: String -> @+label: String -> @+role: InterfaceView.Role -> @+meaning: InterfaceView.Meaning -> @+children: +List<InterfaceView.Node> -> @+target: Nat -> @accepted: {InterfaceView.persistent_trigger_source(meaning, target) == True{} : Bool} ->
    {InterfaceView.relocate_found_trigger(Some{InterfaceView.Node{key, semantic, label, role, meaning, children}}, target, scene, base, overlays) ==
    InterfaceView.relocate_valid_trigger(True{}, InterfaceView.Node{key, semantic, label, role, meaning, children}, scene, base, overlays) : InterfaceView.Surface}}

law evidence:
  Requirements
