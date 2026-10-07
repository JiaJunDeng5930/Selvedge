import ../../bendlib/equality-proof.bend as EqualityProof
import Base
import ../../interaction/IDENTITY.bend as UIIdentity
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/STATE.bend as Core
import ../../interaction/INPUT.bend as U
import ../../interaction/session/MODEL.bend as E
import ./persistent-trigger-laws.bend as Rule

def removed_step(same: Bool, +current: UIIdentity.Key, +semantic: String, +label: String,
  +role: InterfaceView.Role, +meaning: InterfaceView.Meaning, +children: +List<InterfaceView.Node>, +rest: +List<InterfaceView.Node>, +key: String,
  same_key: {String.eq(UIIdentity.encode(current), key) == same : Bool},
  children_removed: {Rule.occurrences(InterfaceView.without_node(children, key), key) == 0n : Nat},
  rest_removed: {Rule.occurrences(InterfaceView.without_node(rest, key), key) == 0n : Nat}) ->
  {Rule.occurrences(InterfaceView.retain_node(Bool.not(same),
    InterfaceView.Node{current, semantic, label, role, meaning, InterfaceView.without_node(children, key)}, InterfaceView.without_node(rest, key)), key) == 0n : Nat}:
  match same:
    case True{}: rest_removed
    case False{}:
      Equal.trans(Nat,
        Nat.add(Rule.bit(String.eq(UIIdentity.encode(current), key)), Nat.add(Rule.occurrences(InterfaceView.without_node(children, key), key), Rule.occurrences(InterfaceView.without_node(rest, key), key))),
        Nat.add(0n, Nat.add(Rule.occurrences(InterfaceView.without_node(children, key), key), Rule.occurrences(InterfaceView.without_node(rest, key), key))), 0n,
        Equal.cong(Bool, Nat, (value => Nat.add(Rule.bit(value), Nat.add(Rule.occurrences(InterfaceView.without_node(children, key), key), Rule.occurrences(InterfaceView.without_node(rest, key), key)))),
          String.eq(UIIdentity.encode(current), key), False{}, same_key),
      Equal.trans(Nat,
        Nat.add(0n, Nat.add(Rule.occurrences(InterfaceView.without_node(children, key), key), Rule.occurrences(InterfaceView.without_node(rest, key), key))),
        Nat.add(0n, Nat.add(0n, Rule.occurrences(InterfaceView.without_node(rest, key), key))), 0n,
        Equal.cong(Nat, Nat, (count => Nat.add(0n, Nat.add(count, Rule.occurrences(InterfaceView.without_node(rest, key), key)))),
          Rule.occurrences(InterfaceView.without_node(children, key), key), 0n, children_removed),
        Equal.cong(Nat, Nat, (count => Nat.add(0n, Nat.add(0n, count))),
          Rule.occurrences(InterfaceView.without_node(rest, key), key), 0n, rest_removed)))

def removed_occurrences(nodes: +List<InterfaceView.Node>, +key: String) ->
  {Rule.occurrences(InterfaceView.without_node(nodes, key), key) == 0n : Nat}:
  match nodes:
    case Nil{}: {==}
    case Con{InterfaceView.Node{+current, semantic, label, role, meaning, +children}, +rest}:
      removed_step(String.eq(UIIdentity.encode(current), key), current, semantic, label, role, meaning, children, rest, key, {==}, removed_occurrences(children, key), removed_occurrences(rest, key))

def actual_relocation(+scene: Core.Scene, +base: +List<InterfaceView.Node>, +overlays: +List<InterfaceView.Node>,
  +key: String, +node: InterfaceView.Node, +target: Nat,
  found: {InterfaceView.find_node(base, key) == Some{node} : Maybe<&2, InterfaceView.Node>}) ->
  {InterfaceView.relocate_trigger_key(Some{key}, target, scene, base, overlays) == InterfaceView.relocate_found_trigger(Some{node}, target, scene, base, overlays) : InterfaceView.Surface}:
  Equal.cong(Maybe<&2, InterfaceView.Node>, InterfaceView.Surface,
    (value => InterfaceView.relocate_found_trigger(value, target, scene, base, overlays)), InterfaceView.find_node(base, key), Some{node}, found)

def valid_exactly_once(+scene: Core.Scene, +base: +List<InterfaceView.Node>, +key: UIIdentity.Key, +semantic: String,
  +label: String, +role: InterfaceView.Role, +meaning: InterfaceView.Meaning, +owner: UIIdentity.Key, +layer_semantic: String,
  +title: String, +policy: InterfaceView.Meaning, +body: +List<InterfaceView.Node>, +rest: +List<InterfaceView.Node>,
  distinct: {String.eq(UIIdentity.encode(owner), UIIdentity.encode(key)) == False{} : Bool},
  fresh: {Nat.add(Rule.occurrences(body, UIIdentity.encode(key)), Rule.occurrences(rest, UIIdentity.encode(key))) == 0n : Nat}) ->
  {Rule.surface_occurrences(InterfaceView.relocate_valid_trigger(True{}, InterfaceView.Node{key, semantic, label, role, meaning, Nil{}},
    scene, base, InterfaceView.Node{owner, layer_semantic, title, InterfaceView.Dialog{}, policy, body} <> rest), UIIdentity.encode(key)) == 1n : Nat}:
  Equal.trans(Nat,
    Nat.add(Rule.occurrences(InterfaceView.without_node(base, UIIdentity.encode(key)), UIIdentity.encode(key)),
      Nat.add(Rule.bit(String.eq(UIIdentity.encode(owner), UIIdentity.encode(key))), Nat.add(Nat.add(Rule.bit(String.eq(UIIdentity.encode(key), UIIdentity.encode(key))), Rule.occurrences(body, UIIdentity.encode(key))), Rule.occurrences(rest, UIIdentity.encode(key))))),
    Nat.add(0n, Nat.add(Rule.bit(String.eq(UIIdentity.encode(owner), UIIdentity.encode(key))), Nat.add(Nat.add(Rule.bit(String.eq(UIIdentity.encode(key), UIIdentity.encode(key))), Rule.occurrences(body, UIIdentity.encode(key))), Rule.occurrences(rest, UIIdentity.encode(key))))), 1n,
    Equal.cong(Nat, Nat, (count => Nat.add(count,
      Nat.add(Rule.bit(String.eq(UIIdentity.encode(owner), UIIdentity.encode(key))), Nat.add(Nat.add(Rule.bit(String.eq(UIIdentity.encode(key), UIIdentity.encode(key))), Rule.occurrences(body, UIIdentity.encode(key))), Rule.occurrences(rest, UIIdentity.encode(key)))))),
      Rule.occurrences(InterfaceView.without_node(base, UIIdentity.encode(key)), UIIdentity.encode(key)), 0n, removed_occurrences(base, UIIdentity.encode(key))),
    Equal.trans(Nat,
      Nat.add(0n, Nat.add(Rule.bit(String.eq(UIIdentity.encode(owner), UIIdentity.encode(key))), Nat.add(Nat.add(Rule.bit(String.eq(UIIdentity.encode(key), UIIdentity.encode(key))), Rule.occurrences(body, UIIdentity.encode(key))), Rule.occurrences(rest, UIIdentity.encode(key))))),
      Nat.add(0n, Nat.add(0n, Nat.add(Nat.add(Rule.bit(String.eq(UIIdentity.encode(key), UIIdentity.encode(key))), Rule.occurrences(body, UIIdentity.encode(key))), Rule.occurrences(rest, UIIdentity.encode(key))))), 1n,
      Equal.cong(Bool, Nat, (same => Nat.add(0n, Nat.add(Rule.bit(same), Nat.add(Nat.add(Rule.bit(String.eq(UIIdentity.encode(key), UIIdentity.encode(key))), Rule.occurrences(body, UIIdentity.encode(key))), Rule.occurrences(rest, UIIdentity.encode(key)))))),
        String.eq(UIIdentity.encode(owner), UIIdentity.encode(key)), False{}, distinct),
      Equal.trans(Nat,
        Nat.add(0n, Nat.add(0n, Nat.add(Nat.add(Rule.bit(String.eq(UIIdentity.encode(key), UIIdentity.encode(key))), Rule.occurrences(body, UIIdentity.encode(key))), Rule.occurrences(rest, UIIdentity.encode(key))))),
        Nat.add(1n, Nat.add(Rule.occurrences(body, UIIdentity.encode(key)), Rule.occurrences(rest, UIIdentity.encode(key)))), 1n,
        Equal.cong(Bool, Nat, (same => Nat.add(0n, Nat.add(0n, Nat.add(Nat.add(Rule.bit(same), Rule.occurrences(body, UIIdentity.encode(key))), Rule.occurrences(rest, UIIdentity.encode(key)))))),
          String.eq(UIIdentity.encode(key), UIIdentity.encode(key)), True{}, EqualityProof.same_string(UIIdentity.encode(key))),
        Equal.cong(Nat, Nat, (count => Nat.add(1n, count)),
          Nat.add(Rule.occurrences(body, UIIdentity.encode(key)), Rule.occurrences(rest, UIIdentity.encode(key))), 0n, fresh))))

def accepted_same_node(+scene: Core.Scene, +base: +List<InterfaceView.Node>, +overlays: +List<InterfaceView.Node>,
  +key: UIIdentity.Key, +semantic: String, +label: String, +role: InterfaceView.Role, +meaning: InterfaceView.Meaning,
  +children: +List<InterfaceView.Node>, +target: Nat,
  accepted: {InterfaceView.persistent_trigger_source(meaning, target) == True{} : Bool}) ->
  {InterfaceView.relocate_found_trigger(Some{InterfaceView.Node{key, semantic, label, role, meaning, children}}, target, scene, base, overlays) ==
    InterfaceView.relocate_valid_trigger(True{}, InterfaceView.Node{key, semantic, label, role, meaning, children}, scene, base, overlays) : InterfaceView.Surface}:
  Equal.cong(Bool, InterfaceView.Surface,
    (valid => InterfaceView.relocate_valid_trigger(valid, InterfaceView.Node{key, semantic, label, role, meaning, children}, scene, base, overlays)),
    InterfaceView.persistent_trigger_source(meaning, target), True{}, accepted)

def rejected_source_stays(+scene: Core.Scene, +base: +List<InterfaceView.Node>, +overlays: +List<InterfaceView.Node>,
  +key: UIIdentity.Key, +semantic: String, +label: String, +role: InterfaceView.Role, +meaning: InterfaceView.Meaning,
  +children: +List<InterfaceView.Node>, +target: Nat,
  rejected: {InterfaceView.persistent_trigger_source(meaning, target) == False{} : Bool}) ->
  {InterfaceView.relocate_found_trigger(Some{InterfaceView.Node{key, semantic, label, role, meaning, children}}, target, scene, base, overlays) ==
    InterfaceView.finish(scene, base, overlays) : InterfaceView.Surface}:
  Equal.cong(Bool, InterfaceView.Surface,
    (valid => InterfaceView.relocate_valid_trigger(valid, InterfaceView.Node{key, semantic, label, role, meaning, children}, scene, base, overlays)),
    InterfaceView.persistent_trigger_source(meaning, target), False{}, rejected)

def Rule.evidence():
  Rule.Requirements{removed_occurrences, +scene => +base => +overlays => +trigger => +key => +node => +target => persistent => resolved => found =>
      Equal.trans(InterfaceView.Surface, InterfaceView.finish_reachable(scene, base, overlays),
        InterfaceView.relocate_persistent_trigger(Some{InterfaceView.PersistentTrigger{target, trigger}}, scene, base, overlays),
        InterfaceView.relocate_found_trigger(Some{node}, target, scene, base, overlays),
        Equal.cong(Maybe<&2, InterfaceView.PersistentTrigger>, InterfaceView.Surface,
          (value => InterfaceView.relocate_persistent_trigger(value, scene, base, overlays)),
          InterfaceView.persistent_details_trigger(overlays), Some{InterfaceView.PersistentTrigger{target, trigger}}, persistent),
        Equal.trans(InterfaceView.Surface, InterfaceView.relocate_persistent_trigger(Some{InterfaceView.PersistentTrigger{target, trigger}}, scene, base, overlays),
          InterfaceView.relocate_trigger_key(Some{key}, target, scene, base, overlays),
          InterfaceView.relocate_found_trigger(Some{node}, target, scene, base, overlays),
          Equal.cong(Maybe<&2, String>, InterfaceView.Surface,
            (value => InterfaceView.relocate_trigger_key(value, target, scene, base, overlays)),
            InterfaceView.matching_focus(base, trigger), Some{key}, resolved),
          actual_relocation(scene, base, overlays, key, node, target, found)))
    , +scene => +base => +key => +semantic => +label => +role => +meaning => +owner => +layer_semantic => +title => +policy => +body => +rest => +target => accepted => distinct => fresh =>
      Equal.trans(Nat,
        Rule.surface_occurrences(InterfaceView.relocate_found_trigger(Some{InterfaceView.Node{key, semantic, label, role, meaning, Nil{}}}, target,
          scene, base, InterfaceView.Node{owner, layer_semantic, title, InterfaceView.Dialog{}, policy, body} <> rest), UIIdentity.encode(key)),
        Rule.surface_occurrences(InterfaceView.relocate_valid_trigger(True{}, InterfaceView.Node{key, semantic, label, role, meaning, Nil{}},
          scene, base, InterfaceView.Node{owner, layer_semantic, title, InterfaceView.Dialog{}, policy, body} <> rest), UIIdentity.encode(key)), 1n,
        Equal.cong(InterfaceView.Surface, Nat, (surface => Rule.surface_occurrences(surface, UIIdentity.encode(key))),
          InterfaceView.relocate_found_trigger(Some{InterfaceView.Node{key, semantic, label, role, meaning, Nil{}}}, target, scene, base, InterfaceView.Node{owner, layer_semantic, title, InterfaceView.Dialog{}, policy, body} <> rest),
          InterfaceView.relocate_valid_trigger(True{}, InterfaceView.Node{key, semantic, label, role, meaning, Nil{}}, scene, base, InterfaceView.Node{owner, layer_semantic, title, InterfaceView.Dialog{}, policy, body} <> rest),
          accepted_same_node(scene, base, InterfaceView.Node{owner, layer_semantic, title, InterfaceView.Dialog{}, policy, body} <> rest,
            key, semantic, label, role, meaning, Nil{}, target, accepted)),
        valid_exactly_once(scene, base, key, semantic, label, role, meaning, owner, layer_semantic, title, policy, body, rest, distinct, fresh))
    , +task => +trigger => +content => +initial => +state => {==}, +scene => +base => +overlays => +key => +semantic => +label => +role => +expanded => +source => +trigger => +availability => +children => +target => distinct =>
      rejected_source_stays(scene, base, overlays, key, semantic, label, role,
        InterfaceView.PanelToggle{expanded, Core.ApplicationInput{E.UserInput{U.Activate{U.TogglePanel{U.TaskDetails{source}, trigger}}}}, availability}, children, target, distinct)
    , +scene => +base => +overlays => +key => +semantic => +label => +role => +expanded => +service => +availability => +children => +target => {==}, +scene => +nav => +reachable => +settings => +scope => {==}, rejected_source_stays, accepted_same_node}
