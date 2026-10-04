import Base
import ../core/interface.bend as UI
import ../core/SYSTEM.bend as Core
import ../core/user-input.bend as U
import ../core/user-experience.bend as E
import ../core/ui-world.bend as View
import ../core/client-services.bend as Services

def bit(value: Bool) -> Nat:
  match value:
    case True{}: 1n
    case False{}: 0n

def occurrences(nodes: +List<UI.Node>, +key: String) -> Nat:
  match nodes:
    case Nil{}: 0n
    case Con{UI.Node{+current, semantic, label, role, meaning, children}, rest}:
      Nat.add(bit(String.eq(current, key)),
        Nat.add(occurrences(children, key), occurrences(rest, key)))

def surface_occurrences(surface: UI.Surface, +key: String) -> Nat:
  UI.Surface{content, base, overlays, scope} = surface
  Nat.add(occurrences(base, key), occurrences(overlays, key))

type Requirements is Type:
  Requirements{
    removal: @nodes:+List<UI.Node> -> @+key:String -> {occurrences(UI.without_node(nodes, key), key) == 0n : Nat},
    actual_source: @+scene:Core.Scene -> @+base:+List<UI.Node> -> @+overlays:+List<UI.Node> -> @+trigger:String -> @+key:String -> @+node:UI.Node -> @+target:Nat ->
      @persistent:{UI.persistent_details_trigger(overlays) == Some{UI.PersistentTrigger{target, trigger}} : Maybe<&2, UI.PersistentTrigger>} ->
      @resolved:{UI.matching_focus(base, trigger) == Some{key} : Maybe<&2, String>} ->
      @found:{UI.find_node(base, key) == Some{node} : Maybe<&2, UI.Node>} ->
      {UI.finish_reachable(scene, base, overlays) == UI.relocate_found_trigger(Some{node}, target, scene, base, overlays) : UI.Surface},
    unique_trigger: @+scene:Core.Scene -> @+base:+List<UI.Node> -> @+key:String -> @+semantic:String -> @+label:String -> @+role:UI.Role ->
      @+meaning:UI.Meaning -> @+owner:String -> @+layer_semantic:String -> @+title:String -> @+policy:UI.Meaning ->
      @+body:+List<UI.Node> -> @+rest:+List<UI.Node> -> @+target:Nat ->
      @accepted:{UI.persistent_trigger_source(meaning, target) == True{} : Bool} -> @distinct:{String.eq(owner, key) == False{} : Bool} ->
      @fresh:{Nat.add(occurrences(body, key), occurrences(rest, key)) == 0n : Nat} ->
      {surface_occurrences(UI.relocate_found_trigger(Some{UI.Node{key, semantic, label, role, meaning, Nil{}}}, target,
        scene, base, UI.Node{owner, layer_semantic, title, UI.Dialog{}, policy, body} <> rest), key) == 1n : Nat},
    production_details: @+task:Nat -> @+trigger:String -> @+content:View.LayerContent -> @+initial:String -> @+state:Core.State ->
      {UI.persistent_details_trigger(UI.layers([View.Layer{View.ModalDialog{}, content, initial, trigger,
        View.layer_dismissal(U.TaskDetails{task}, trigger)}], state)) == Some{UI.PersistentTrigger{task, trigger}} : Maybe<&2, UI.PersistentTrigger>},
    wrong_task_stays: @+scene: Core.Scene -> @+base: +List<UI.Node> -> @+overlays: +List<UI.Node> -> @+key: String -> @+semantic: String -> @+label: String -> @+role: UI.Role -> @+expanded: Bool -> @+source: Nat -> @+trigger: String -> @+availability: View.Availability -> @+children: +List<UI.Node> -> @+target: Nat -> @distinct: {Nat.is_eq(source, target) == False{} : Bool} ->
    {UI.relocate_found_trigger(Some{UI.Node{key, semantic, label, role,
            UI.PanelToggle{expanded, Core.ApplicationInput{E.UserInput{U.Activate{U.TogglePanel{U.TaskDetails{source}, trigger}}}}, availability}, children}},
          target, scene, base, overlays) == UI.finish(scene, base, overlays) : UI.Surface},
    wrong_input_stays: @+scene: Core.Scene -> @+base: +List<UI.Node> -> @+overlays: +List<UI.Node> -> @+key: String -> @+semantic: String -> @+label: String -> @+role: UI.Role -> @+expanded: Bool -> @+service: Services.Input -> @+availability: View.Availability -> @+children: +List<UI.Node> -> @+target: Nat ->
    {UI.relocate_found_trigger(Some{UI.Node{key, semantic, label, role,
            UI.PanelToggle{expanded, Core.ServiceInput{service}, availability}, children}}, target, scene, base, overlays) ==
          UI.finish(scene, base, overlays) : UI.Surface},
    navigation_kept: @+scene: Core.Scene -> @+nav: +List<UI.Node> -> @+reachable: UI.Surface -> @+settings: UI.Node -> @+scope: Maybe<&2, String> ->
    {UI.surface_base(UI.with_navigation(scene, nav, reachable, settings, scope)) ==
    List.append(&2, UI.Node, nav, List.append(&2, UI.Node, UI.surface_base(reachable), [settings])) : +List<UI.Node>},
    rejected_source_stays: @+scene: Core.Scene -> @+base: +List<UI.Node> -> @+overlays: +List<UI.Node> -> @+key: String -> @+semantic: String -> @+label: String -> @+role: UI.Role -> @+meaning: UI.Meaning -> @+children: +List<UI.Node> -> @+target: Nat -> @rejected: {UI.persistent_trigger_source(meaning, target) == False{} : Bool} ->
    {UI.relocate_found_trigger(Some{UI.Node{key, semantic, label, role, meaning, children}}, target, scene, base, overlays) ==
    UI.finish(scene, base, overlays) : UI.Surface},
    accepted_same_node: @+scene: Core.Scene -> @+base: +List<UI.Node> -> @+overlays: +List<UI.Node> -> @+key: String -> @+semantic: String -> @+label: String -> @+role: UI.Role -> @+meaning: UI.Meaning -> @+children: +List<UI.Node> -> @+target: Nat -> @accepted: {UI.persistent_trigger_source(meaning, target) == True{} : Bool} ->
    {UI.relocate_found_trigger(Some{UI.Node{key, semantic, label, role, meaning, children}}, target, scene, base, overlays) ==
    UI.relocate_valid_trigger(True{}, UI.Node{key, semantic, label, role, meaning, children}, scene, base, overlays) : UI.Surface}}

law evidence:
  Requirements
