import ./enclosure-render.bend as ExistingProof
import Base
import ../../core/interface.bend as UI
import ../../core/SYSTEM.bend as Core
import ../../core/user-input.bend as U
import ../../core/user-experience.bend as E
import ../persistent-trigger-laws.bend as Rule

def removed_step(same: Bool, +current: String, +semantic: String, +label: String,
  +role: UI.Role, +meaning: UI.Meaning, +children: +List<UI.Node>, +rest: +List<UI.Node>, +key: String,
  same_key: {String.eq(current, key) == same : Bool},
  children_removed: {Rule.occurrences(UI.without_node(children, key), key) == 0n : Nat},
  rest_removed: {Rule.occurrences(UI.without_node(rest, key), key) == 0n : Nat}) ->
  {Rule.occurrences(UI.retain_node(Bool.not(same),
    UI.Node{current, semantic, label, role, meaning, UI.without_node(children, key)}, UI.without_node(rest, key)), key) == 0n : Nat}:
  match same:
    case True{}: rest_removed
    case False{}:
      Equal.trans(Nat,
        Nat.add(Rule.bit(String.eq(current, key)), Nat.add(Rule.occurrences(UI.without_node(children, key), key), Rule.occurrences(UI.without_node(rest, key), key))),
        Nat.add(0n, Nat.add(Rule.occurrences(UI.without_node(children, key), key), Rule.occurrences(UI.without_node(rest, key), key))), 0n,
        Equal.cong(Bool, Nat, (value => Nat.add(Rule.bit(value), Nat.add(Rule.occurrences(UI.without_node(children, key), key), Rule.occurrences(UI.without_node(rest, key), key)))),
          String.eq(current, key), False{}, same_key),
      Equal.trans(Nat,
        Nat.add(0n, Nat.add(Rule.occurrences(UI.without_node(children, key), key), Rule.occurrences(UI.without_node(rest, key), key))),
        Nat.add(0n, Nat.add(0n, Rule.occurrences(UI.without_node(rest, key), key))), 0n,
        Equal.cong(Nat, Nat, (count => Nat.add(0n, Nat.add(count, Rule.occurrences(UI.without_node(rest, key), key)))),
          Rule.occurrences(UI.without_node(children, key), key), 0n, children_removed),
        Equal.cong(Nat, Nat, (count => Nat.add(0n, Nat.add(0n, count))),
          Rule.occurrences(UI.without_node(rest, key), key), 0n, rest_removed)))

def removed_occurrences(nodes: +List<UI.Node>, +key: String) ->
  {Rule.occurrences(UI.without_node(nodes, key), key) == 0n : Nat}:
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

def valid_exactly_once(+scene: Core.Scene, +base: +List<UI.Node>, +key: String, +semantic: String,
  +label: String, +role: UI.Role, +meaning: UI.Meaning, +owner: String, +layer_semantic: String,
  +title: String, +policy: UI.Meaning, +body: +List<UI.Node>, +rest: +List<UI.Node>,
  distinct: {String.eq(owner, key) == False{} : Bool},
  fresh: {Nat.add(Rule.occurrences(body, key), Rule.occurrences(rest, key)) == 0n : Nat}) ->
  {Rule.surface_occurrences(UI.relocate_valid_trigger(True{}, UI.Node{key, semantic, label, role, meaning, Nil{}},
    scene, base, UI.Node{owner, layer_semantic, title, UI.Dialog{}, policy, body} <> rest), key) == 1n : Nat}:
  Equal.trans(Nat,
    Nat.add(Rule.occurrences(UI.without_node(base, key), key),
      Nat.add(Rule.bit(String.eq(owner, key)), Nat.add(Nat.add(Rule.bit(String.eq(key, key)), Rule.occurrences(body, key)), Rule.occurrences(rest, key)))),
    Nat.add(0n, Nat.add(Rule.bit(String.eq(owner, key)), Nat.add(Nat.add(Rule.bit(String.eq(key, key)), Rule.occurrences(body, key)), Rule.occurrences(rest, key)))), 1n,
    Equal.cong(Nat, Nat, (count => Nat.add(count,
      Nat.add(Rule.bit(String.eq(owner, key)), Nat.add(Nat.add(Rule.bit(String.eq(key, key)), Rule.occurrences(body, key)), Rule.occurrences(rest, key))))),
      Rule.occurrences(UI.without_node(base, key), key), 0n, removed_occurrences(base, key)),
    Equal.trans(Nat,
      Nat.add(0n, Nat.add(Rule.bit(String.eq(owner, key)), Nat.add(Nat.add(Rule.bit(String.eq(key, key)), Rule.occurrences(body, key)), Rule.occurrences(rest, key)))),
      Nat.add(0n, Nat.add(0n, Nat.add(Nat.add(Rule.bit(String.eq(key, key)), Rule.occurrences(body, key)), Rule.occurrences(rest, key)))), 1n,
      Equal.cong(Bool, Nat, (same => Nat.add(0n, Nat.add(Rule.bit(same), Nat.add(Nat.add(Rule.bit(String.eq(key, key)), Rule.occurrences(body, key)), Rule.occurrences(rest, key))))),
        String.eq(owner, key), False{}, distinct),
      Equal.trans(Nat,
        Nat.add(0n, Nat.add(0n, Nat.add(Nat.add(Rule.bit(String.eq(key, key)), Rule.occurrences(body, key)), Rule.occurrences(rest, key)))),
        Nat.add(1n, Nat.add(Rule.occurrences(body, key), Rule.occurrences(rest, key))), 1n,
        Equal.cong(Bool, Nat, (same => Nat.add(0n, Nat.add(0n, Nat.add(Nat.add(Rule.bit(same), Rule.occurrences(body, key)), Rule.occurrences(rest, key))))),
          String.eq(key, key), True{}, ExistingProof.same_string(key)),
        Equal.cong(Nat, Nat, (count => Nat.add(1n, count)),
          Nat.add(Rule.occurrences(body, key), Rule.occurrences(rest, key)), 0n, fresh))))

def accepted_same_node(+scene: Core.Scene, +base: +List<UI.Node>, +overlays: +List<UI.Node>,
  +key: String, +semantic: String, +label: String, +role: UI.Role, +meaning: UI.Meaning,
  +children: +List<UI.Node>, +target: Nat,
  accepted: {UI.persistent_trigger_source(meaning, target) == True{} : Bool}) ->
  {UI.relocate_found_trigger(Some{UI.Node{key, semantic, label, role, meaning, children}}, target, scene, base, overlays) ==
    UI.relocate_valid_trigger(True{}, UI.Node{key, semantic, label, role, meaning, children}, scene, base, overlays) : UI.Surface}:
  Equal.cong(Bool, UI.Surface,
    (valid => UI.relocate_valid_trigger(valid, UI.Node{key, semantic, label, role, meaning, children}, scene, base, overlays)),
    UI.persistent_trigger_source(meaning, target), True{}, accepted)

def rejected_source_stays(+scene: Core.Scene, +base: +List<UI.Node>, +overlays: +List<UI.Node>,
  +key: String, +semantic: String, +label: String, +role: UI.Role, +meaning: UI.Meaning,
  +children: +List<UI.Node>, +target: Nat,
  rejected: {UI.persistent_trigger_source(meaning, target) == False{} : Bool}) ->
  {UI.relocate_found_trigger(Some{UI.Node{key, semantic, label, role, meaning, children}}, target, scene, base, overlays) ==
    UI.finish(scene, base, overlays) : UI.Surface}:
  Equal.cong(Bool, UI.Surface,
    (valid => UI.relocate_valid_trigger(valid, UI.Node{key, semantic, label, role, meaning, children}, scene, base, overlays)),
    UI.persistent_trigger_source(meaning, target), False{}, rejected)

def Rule.evidence():
  Rule.Requirements{removed_occurrences, +scene => +base => +overlays => +trigger => +key => +node => +target => persistent => resolved => found =>
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
    , +scene => +base => +key => +semantic => +label => +role => +meaning => +owner => +layer_semantic => +title => +policy => +body => +rest => +target => accepted => distinct => fresh =>
      Equal.trans(Nat,
        Rule.surface_occurrences(UI.relocate_found_trigger(Some{UI.Node{key, semantic, label, role, meaning, Nil{}}}, target,
          scene, base, UI.Node{owner, layer_semantic, title, UI.Dialog{}, policy, body} <> rest), key),
        Rule.surface_occurrences(UI.relocate_valid_trigger(True{}, UI.Node{key, semantic, label, role, meaning, Nil{}},
          scene, base, UI.Node{owner, layer_semantic, title, UI.Dialog{}, policy, body} <> rest), key), 1n,
        Equal.cong(UI.Surface, Nat, (surface => Rule.surface_occurrences(surface, key)),
          UI.relocate_found_trigger(Some{UI.Node{key, semantic, label, role, meaning, Nil{}}}, target, scene, base, UI.Node{owner, layer_semantic, title, UI.Dialog{}, policy, body} <> rest),
          UI.relocate_valid_trigger(True{}, UI.Node{key, semantic, label, role, meaning, Nil{}}, scene, base, UI.Node{owner, layer_semantic, title, UI.Dialog{}, policy, body} <> rest),
          accepted_same_node(scene, base, UI.Node{owner, layer_semantic, title, UI.Dialog{}, policy, body} <> rest,
            key, semantic, label, role, meaning, Nil{}, target, accepted)),
        valid_exactly_once(scene, base, key, semantic, label, role, meaning, owner, layer_semantic, title, policy, body, rest, distinct, fresh))
    , +task => +trigger => +content => +initial => +state => {==}, +scene => +base => +overlays => +key => +semantic => +label => +role => +expanded => +source => +trigger => +availability => +children => +target => distinct =>
      rejected_source_stays(scene, base, overlays, key, semantic, label, role,
        UI.PanelToggle{expanded, Core.ApplicationInput{E.UserInput{U.Activate{U.TogglePanel{U.TaskDetails{source}, trigger}}}}, availability}, children, target, distinct)
    , +scene => +base => +overlays => +key => +semantic => +label => +role => +expanded => +service => +availability => +children => +target => {==}, +scene => +nav => +reachable => +settings => +scope => {==}, rejected_source_stays, accepted_same_node}
