import Base
import ../core/interface.bend as UI
import ../core/SYSTEM.bend as Core
import ../core/user-input.bend as U
import ../core/user-experience.bend as E
import ../core/ui-world.bend as View
import ./renderer.bend as Renderer
import ./controls.bend as Controls
import ./dismissal-laws.bend as Dismissal
import ./enclosure-render-laws.bend as Existing
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

def removed_step(same: Bool, +current: String, +semantic: String, +label: String,
  +role: UI.Role, +meaning: UI.Meaning, +children: +List<UI.Node>, +rest: +List<UI.Node>, +key: String,
  same_key: {String.eq(current, key) == same : Bool},
  children_removed: {occurrences(UI.without_node(children, key), key) == 0n : Nat},
  rest_removed: {occurrences(UI.without_node(rest, key), key) == 0n : Nat}) ->
  {occurrences(UI.retain_node(Bool.not(same),
    UI.Node{current, semantic, label, role, meaning, UI.without_node(children, key)}, UI.without_node(rest, key)), key) == 0n : Nat}:
  match same:
    case True{}: rest_removed
    case False{}:
      Equal.trans(Nat,
        Nat.add(bit(String.eq(current, key)), Nat.add(occurrences(UI.without_node(children, key), key), occurrences(UI.without_node(rest, key), key))),
        Nat.add(0n, Nat.add(occurrences(UI.without_node(children, key), key), occurrences(UI.without_node(rest, key), key))), 0n,
        Equal.cong(Bool, Nat, (value => Nat.add(bit(value), Nat.add(occurrences(UI.without_node(children, key), key), occurrences(UI.without_node(rest, key), key)))),
          String.eq(current, key), False{}, same_key),
      Equal.trans(Nat,
        Nat.add(0n, Nat.add(occurrences(UI.without_node(children, key), key), occurrences(UI.without_node(rest, key), key))),
        Nat.add(0n, Nat.add(0n, occurrences(UI.without_node(rest, key), key))), 0n,
        Equal.cong(Nat, Nat, (count => Nat.add(0n, Nat.add(count, occurrences(UI.without_node(rest, key), key)))),
          occurrences(UI.without_node(children, key), key), 0n, children_removed),
        Equal.cong(Nat, Nat, (count => Nat.add(0n, Nat.add(0n, count))),
          occurrences(UI.without_node(rest, key), key), 0n, rest_removed)))

def removed_occurrences(nodes: +List<UI.Node>, +key: String) ->
  {occurrences(UI.without_node(nodes, key), key) == 0n : Nat}:
  match nodes:
    case Nil{}: {==}
    case Con{UI.Node{+current, semantic, label, role, meaning, +children}, +rest}:
      removed_step(String.eq(current, key), current, semantic, label, role, meaning, children, rest, key, {==}, removed_occurrences(children, key), removed_occurrences(rest, key))

def actual_relocation(+scene: Core.Scene, +base: +List<UI.Node>, +overlays: +List<UI.Node>,
  +key: String, +node: UI.Node, +target: Nat,
  found: {UI.find_node(base, key) == Some{node} : Maybe<&2, UI.Node>}) ->
  {UI.relocate_trigger_key(Some{key}, target, scene, base, overlays) == UI.relocate_found_trigger(Some{node}, target, scene, base, overlays) : UI.Surface}:
  Equal.cong(Maybe<&2, UI.Node>, UI.Surface,
    (value => UI.relocate_found_trigger(value, target, scene, base, overlays)), UI.find_node(base, key), Some{node}, found)

def assembled_relocation(+scene: Core.Scene, +base: +List<UI.Node>, +overlays: +List<UI.Node>,
  +trigger: String, +key: String, +node: UI.Node, +target: Nat,
  persistent: {UI.persistent_details_trigger(overlays) == Some{UI.PersistentTrigger{target, trigger}} : Maybe<&2, UI.PersistentTrigger>},
  resolved: {UI.matching_focus(base, trigger) == Some{key} : Maybe<&2, String>},
  found: {UI.find_node(base, key) == Some{node} : Maybe<&2, UI.Node>}) ->
  {UI.finish_reachable(scene, base, overlays) == UI.relocate_found_trigger(Some{node}, target, scene, base, overlays) : UI.Surface}:
  Equal.trans(UI.Surface, UI.finish_reachable(scene, base, overlays),
    UI.relocate_persistent_trigger(Some{UI.PersistentTrigger{target, trigger}}, scene, base, overlays),
    UI.relocate_found_trigger(Some{node}, target, scene, base, overlays),
    Equal.cong(Maybe<&2, UI.PersistentTrigger>, UI.Surface,
      (value => UI.relocate_persistent_trigger(value, scene, base, overlays)),
      UI.persistent_details_trigger(overlays), Some{UI.PersistentTrigger{target, trigger}}, persistent),
    Equal.trans(UI.Surface, UI.relocate_persistent_trigger(Some{UI.PersistentTrigger{target, trigger}}, scene, base, overlays),
      UI.relocate_trigger_key(Some{key}, target, scene, base, overlays),
      UI.relocate_found_trigger(Some{node}, target, scene, base, overlays),
      Equal.cong(Maybe<&2, String>, UI.Surface,
        (value => UI.relocate_trigger_key(value, target, scene, base, overlays)),
        UI.matching_focus(base, trigger), Some{key}, resolved),
      actual_relocation(scene, base, overlays, key, node, target, found)))

def surface_occurrences(surface: UI.Surface, +key: String) -> Nat:
  UI.Surface{content, base, overlays, scope} = surface
  Nat.add(occurrences(base, key), occurrences(overlays, key))

def valid_exactly_once(+scene: Core.Scene, +base: +List<UI.Node>, +key: String, +semantic: String,
  +label: String, +role: UI.Role, +meaning: UI.Meaning, +owner: String, +layer_semantic: String,
  +title: String, +policy: UI.Meaning, +body: +List<UI.Node>, +rest: +List<UI.Node>,
  distinct: {String.eq(owner, key) == False{} : Bool},
  fresh: {Nat.add(occurrences(body, key), occurrences(rest, key)) == 0n : Nat}) ->
  {surface_occurrences(UI.relocate_valid_trigger(True{}, UI.Node{key, semantic, label, role, meaning, Nil{}},
    scene, base, UI.Node{owner, layer_semantic, title, UI.Dialog{}, policy, body} <> rest), key) == 1n : Nat}:
  Equal.trans(Nat,
    Nat.add(occurrences(UI.without_node(base, key), key),
      Nat.add(bit(String.eq(owner, key)), Nat.add(Nat.add(bit(String.eq(key, key)), occurrences(body, key)), occurrences(rest, key)))),
    Nat.add(0n, Nat.add(bit(String.eq(owner, key)), Nat.add(Nat.add(bit(String.eq(key, key)), occurrences(body, key)), occurrences(rest, key)))), 1n,
    Equal.cong(Nat, Nat, (count => Nat.add(count,
      Nat.add(bit(String.eq(owner, key)), Nat.add(Nat.add(bit(String.eq(key, key)), occurrences(body, key)), occurrences(rest, key))))),
      occurrences(UI.without_node(base, key), key), 0n, removed_occurrences(base, key)),
    Equal.trans(Nat,
      Nat.add(0n, Nat.add(bit(String.eq(owner, key)), Nat.add(Nat.add(bit(String.eq(key, key)), occurrences(body, key)), occurrences(rest, key)))),
      Nat.add(0n, Nat.add(0n, Nat.add(Nat.add(bit(String.eq(key, key)), occurrences(body, key)), occurrences(rest, key)))), 1n,
      Equal.cong(Bool, Nat, (same => Nat.add(0n, Nat.add(bit(same), Nat.add(Nat.add(bit(String.eq(key, key)), occurrences(body, key)), occurrences(rest, key))))),
        String.eq(owner, key), False{}, distinct),
      Equal.trans(Nat,
        Nat.add(0n, Nat.add(0n, Nat.add(Nat.add(bit(String.eq(key, key)), occurrences(body, key)), occurrences(rest, key)))),
        Nat.add(1n, Nat.add(occurrences(body, key), occurrences(rest, key))), 1n,
        Equal.cong(Bool, Nat, (same => Nat.add(0n, Nat.add(0n, Nat.add(Nat.add(bit(same), occurrences(body, key)), occurrences(rest, key))))),
          String.eq(key, key), True{}, Existing.same_string(key)),
        Equal.cong(Nat, Nat, (count => Nat.add(1n, count)),
          Nat.add(occurrences(body, key), occurrences(rest, key)), 0n, fresh))))

def same_node_in_scope(+scene: Core.Scene, +base: +List<UI.Node>, +key: String, +semantic: String,
  +label: String, +role: UI.Role, +meaning: UI.Meaning, +children: +List<UI.Node>,
  +owner: String, +layer_semantic: String, +title: String, +policy: UI.Meaning,
  +body: +List<UI.Node>, +rest: +List<UI.Node>) ->
  {UI.relocate_valid_trigger(True{}, UI.Node{key, semantic, label, role, meaning, children}, scene, base,
      UI.Node{owner, layer_semantic, title, UI.Dialog{}, policy, body} <> rest) ==
    UI.Surface{scene, UI.without_node(base, key),
      UI.Node{owner, layer_semantic, title, UI.Dialog{}, policy,
        UI.Node{key, semantic, label, role, meaning, children} <> body} <> rest, Some{owner}} : UI.Surface}:
  {==}

def wide_details_stay_in_base(+scene: Core.Scene, +base: +List<UI.Node>, +owner: String,
  +semantic: String, +title: String, +policy: UI.Meaning, +children: +List<UI.Node>) ->
  {UI.finish_reachable(scene, base, [UI.Node{owner, semantic, title, UI.Details{}, policy, children}]) ==
    UI.finish(scene, base, [UI.Node{owner, semantic, title, UI.Details{}, policy, children}]) : UI.Surface}:
  {==}

def current_details_layer(+task: Nat, +trigger: String, +content: View.LayerContent,
  +initial: String, +state: Core.State) ->
  {UI.persistent_details_trigger(UI.layers([View.Layer{View.ModalDialog{}, content, initial, trigger,
      View.layer_dismissal(U.TaskDetails{task}, trigger)}], state)) == Some{UI.PersistentTrigger{task, trigger}} : Maybe<&2, UI.PersistentTrigger>}:
  {==}

def header_action(task: Nat, trigger: String, availability: View.Availability, name: String,
  face: Controls.Face, geometry: Controls.Geometry, placement: Controls.Placement,
  help: Controls.Help, feedback: Controls.Feedback) ->
  {Renderer.persistent_details_header(Controls.Action{
    Core.ApplicationInput{E.UserInput{U.Activate{U.TogglePanel{U.TaskDetails{task}, trigger}}}},
    availability, name, face, Controls.Disclosure{True{}}, geometry, placement, help, feedback}) == True{} : Bool}:
  {==}

def accepted_same_node(+scene: Core.Scene, +base: +List<UI.Node>, +overlays: +List<UI.Node>,
  +key: String, +semantic: String, +label: String, +role: UI.Role, +meaning: UI.Meaning,
  +children: +List<UI.Node>, +target: Nat,
  accepted: {UI.persistent_trigger_source(meaning, target) == True{} : Bool}) ->
  {UI.relocate_found_trigger(Some{UI.Node{key, semantic, label, role, meaning, children}}, target, scene, base, overlays) ==
    UI.relocate_valid_trigger(True{}, UI.Node{key, semantic, label, role, meaning, children}, scene, base, overlays) : UI.Surface}:
  Equal.cong(Bool, UI.Surface,
    (valid => UI.relocate_valid_trigger(valid, UI.Node{key, semantic, label, role, meaning, children}, scene, base, overlays)),
    UI.persistent_trigger_source(meaning, target), True{}, accepted)

def exactly_once(+scene: Core.Scene, +base: +List<UI.Node>, +key: String, +semantic: String,
  +label: String, +role: UI.Role, +meaning: UI.Meaning, +owner: String, +layer_semantic: String,
  +title: String, +policy: UI.Meaning, +body: +List<UI.Node>, +rest: +List<UI.Node>, +target: Nat,
  accepted: {UI.persistent_trigger_source(meaning, target) == True{} : Bool},
  distinct: {String.eq(owner, key) == False{} : Bool},
  fresh: {Nat.add(occurrences(body, key), occurrences(rest, key)) == 0n : Nat}) ->
  {surface_occurrences(UI.relocate_found_trigger(Some{UI.Node{key, semantic, label, role, meaning, Nil{}}}, target,
    scene, base, UI.Node{owner, layer_semantic, title, UI.Dialog{}, policy, body} <> rest), key) == 1n : Nat}:
  Equal.trans(Nat,
    surface_occurrences(UI.relocate_found_trigger(Some{UI.Node{key, semantic, label, role, meaning, Nil{}}}, target,
      scene, base, UI.Node{owner, layer_semantic, title, UI.Dialog{}, policy, body} <> rest), key),
    surface_occurrences(UI.relocate_valid_trigger(True{}, UI.Node{key, semantic, label, role, meaning, Nil{}},
      scene, base, UI.Node{owner, layer_semantic, title, UI.Dialog{}, policy, body} <> rest), key), 1n,
    Equal.cong(UI.Surface, Nat, (surface => surface_occurrences(surface, key)),
      UI.relocate_found_trigger(Some{UI.Node{key, semantic, label, role, meaning, Nil{}}}, target, scene, base, UI.Node{owner, layer_semantic, title, UI.Dialog{}, policy, body} <> rest),
      UI.relocate_valid_trigger(True{}, UI.Node{key, semantic, label, role, meaning, Nil{}}, scene, base, UI.Node{owner, layer_semantic, title, UI.Dialog{}, policy, body} <> rest),
      accepted_same_node(scene, base, UI.Node{owner, layer_semantic, title, UI.Dialog{}, policy, body} <> rest,
        key, semantic, label, role, meaning, Nil{}, target, accepted)),
    valid_exactly_once(scene, base, key, semantic, label, role, meaning, owner, layer_semantic, title, policy, body, rest, distinct, fresh))

def rejected_source_stays(+scene: Core.Scene, +base: +List<UI.Node>, +overlays: +List<UI.Node>,
  +key: String, +semantic: String, +label: String, +role: UI.Role, +meaning: UI.Meaning,
  +children: +List<UI.Node>, +target: Nat,
  rejected: {UI.persistent_trigger_source(meaning, target) == False{} : Bool}) ->
  {UI.relocate_found_trigger(Some{UI.Node{key, semantic, label, role, meaning, children}}, target, scene, base, overlays) ==
    UI.finish(scene, base, overlays) : UI.Surface}:
  Equal.cong(Bool, UI.Surface,
    (valid => UI.relocate_valid_trigger(valid, UI.Node{key, semantic, label, role, meaning, children}, scene, base, overlays)),
    UI.persistent_trigger_source(meaning, target), False{}, rejected)

def wrong_task_stays(+scene: Core.Scene, +base: +List<UI.Node>, +overlays: +List<UI.Node>,
  +key: String, +semantic: String, +label: String, +role: UI.Role, +expanded: Bool,
  +source: Nat, +trigger: String, +availability: View.Availability, +children: +List<UI.Node>, +target: Nat,
  distinct: {Nat.is_eq(source, target) == False{} : Bool}) ->
  {UI.relocate_found_trigger(Some{UI.Node{key, semantic, label, role,
      UI.PanelToggle{expanded, Core.ApplicationInput{E.UserInput{U.Activate{U.TogglePanel{U.TaskDetails{source}, trigger}}}}, availability}, children}},
    target, scene, base, overlays) == UI.finish(scene, base, overlays) : UI.Surface}:
  rejected_source_stays(scene, base, overlays, key, semantic, label, role,
    UI.PanelToggle{expanded, Core.ApplicationInput{E.UserInput{U.Activate{U.TogglePanel{U.TaskDetails{source}, trigger}}}}, availability}, children, target, distinct)

def wrong_input_stays(+scene: Core.Scene, +base: +List<UI.Node>, +overlays: +List<UI.Node>,
  +key: String, +semantic: String, +label: String, +role: UI.Role, +expanded: Bool,
  +service: Services.Input, +availability: View.Availability, +children: +List<UI.Node>, +target: Nat) ->
  {UI.relocate_found_trigger(Some{UI.Node{key, semantic, label, role,
      UI.PanelToggle{expanded, Core.ServiceInput{service}, availability}, children}}, target, scene, base, overlays) ==
    UI.finish(scene, base, overlays) : UI.Surface}:
  {==}

def navigation_kept(+scene: Core.Scene, +nav: +List<UI.Node>, +reachable: UI.Surface,
  +settings: UI.Node, +scope: Maybe<&2, String>) ->
  {UI.surface_base(UI.with_navigation(scene, nav, reachable, settings, scope)) ==
    List.append(&2, UI.Node, nav, List.append(&2, UI.Node, UI.surface_base(reachable), [settings])) : +List<UI.Node>}:
  {==}

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
    UI.relocate_valid_trigger(True{}, UI.Node{key, semantic, label, role, meaning, children}, scene, base, overlays) : UI.Surface},
    dismissal: Dismissal.Requirements}

def evidence() -> Requirements:
  Requirements{removed_occurrences, assembled_relocation, exactly_once, current_details_layer, wrong_task_stays, wrong_input_stays, navigation_kept, rejected_source_stays, accepted_same_node, Dismissal.evidence()}
