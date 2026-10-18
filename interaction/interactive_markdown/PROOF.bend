import Base
import ./CONTRACT.bend as Contract
import ./expression-proof.bend as Expression
import ./TYPES.bend as T
import ./STATE.bend as State
import ./MODEL.bend as Model
import ./PARSER.bend as Parser
import ./SCHEMA.bend as Schema
import ./SYNTAX.bend as Syntax
import ./REGISTRY.bend as Registry
import ./EXPAND.bend as Expand
import ./CODEC.bend as Codec
import ./DECIMAL.bend as D
import ../../bendlib/json.bend as J
import ../../bendlib/stdlib.bend as Std
import ../../bendlib/equality-proof.bend as Equality
import ../../bendlib/string-equality.bend as SafeText
import ../../bendlib/logic-proof.bend as Logic
import ./snapshot-proof.bend as Snapshot

def Contract.empty_initial_state():
  {==}

def Contract.opted_out_fence(kind, info, complete):
  {==}

def ordinary_fence_result(+a: Bool, +b: Bool, +c: Bool) -> {a && b && c && False{} == False{} : Bool}:
  match a b c:
    case False{} _ _: {==}
    case True{} False{} _: {==}
    case True{} True{} False{}: {==}
    case True{} True{} True{}: {==}

def Contract.ordinary_fence(interactive, kind, info, complete, ordinary):
  Std.transport(Bool, False{}, (reserved => {interactive && complete && String.eq(kind, "fenced") && reserved == False{} : Bool}),
    ordinary_fence_result(interactive, complete, String.eq(kind, "fenced")), String.eq(Parser.trim_info(info), "selvedge-ui"), ordinary)

def absent_field_reduce(+block:T.Block, +event:T.EventIdentity, +raw:String,
  observed:{State.current_node(block, event) == None{} : Maybe<&2, T.ExpandedNode>}) ->
  {State.reduce(block, T.FieldEdited{event, raw}) == State.BlockDecision{block, Nil{}, False{}, False{}} : State.BlockDecision}:
  Std.transport(Maybe<&2, T.ExpandedNode>, None{},
    (found => {State.field_node(found, raw, block) == State.BlockDecision{block, Nil{}, False{}, False{}} : State.BlockDecision}),
    {==}, State.current_node(block, event), observed)

def absent_action_reduce(+block:T.Block, +event:T.EventIdentity,
  observed:{State.current_node(block, event) == None{} : Maybe<&2, T.ExpandedNode>}) ->
  {State.reduce(block, T.Activated{event}) == State.BlockDecision{block, Nil{}, False{}, False{}} : State.BlockDecision}:
  Std.transport(Maybe<&2, T.ExpandedNode>, None{},
    (found => {State.action_node(block, found) == State.BlockDecision{block, Nil{}, False{}, False{}} : State.BlockDecision}),
    {==}, State.current_node(block, event), observed)

def no_owner_lookup(+blocks: +List<T.Block>, +owner: T.Owner, absent: Contract.other_owners(blocks, owner)) ->
  {State.find_block(blocks, owner) == None{} : Maybe<&2, T.Block>}:
  match blocks:
    case Nil{}: {==}
    case Con{T.Block{+key, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restored}, +rest}:
      (head, tail) = absent
      Std.transport(Bool, False{},
        (same => {Bool.pick(Maybe<&2, T.Block>, same, Some{T.Block{key, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restored}}, State.find_block(rest, owner)) == None{} : Maybe<&2, T.Block>}),
        no_owner_lookup(rest, owner, tail), Syntax.same_owner(key, owner), head)

def first_owner_lookup(+prefix: +List<T.Block>, +block: T.Block, +suffix: +List<T.Block>, +owner: T.Owner,
  preceding: Contract.other_owners(prefix, owner), owned: {Syntax.same_owner(State.block_owner(block), owner) == True{} : Bool}) ->
  {State.find_block(List.append(&2, T.Block, prefix, block <> suffix), owner) == Some{block} : Maybe<&2, T.Block>}:
  match prefix:
    case Nil{}:
      Std.transport(Bool, True{},
        (same => {Bool.pick(Maybe<&2, T.Block>, same, Some{block}, State.find_block(suffix, owner)) == Some{block} : Maybe<&2, T.Block>}),
        {==}, Syntax.same_owner(State.block_owner(block), owner), owned)
    case Con{T.Block{+key, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restored}, +rest}:
      (head, tail) = preceding
      Std.transport(Bool, False{},
        (same => {Bool.pick(Maybe<&2, T.Block>, same, Some{T.Block{key, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restored}}, State.find_block(List.append(&2, T.Block, rest, block <> suffix), owner)) == Some{block} : Maybe<&2, T.Block>}),
        first_owner_lookup(rest, block, suffix, owner, tail, owned), Syntax.same_owner(key, owner), head)

def no_visible_lookup(+work: Nat, +nodes: +List<T.ExpandedNode>, +event: T.EventIdentity,
  absent: Contract.no_visible_event(work, nodes, event)) ->
  {State.find_node(work, nodes, event) == None{} : Maybe<&2, T.ExpandedNode>}:
  match work nodes:
    case 0n _: {==}
    case 1n+left Nil{}: {==}
    case 1n+left Con{T.ExpandedNode{+identity, +occurrence, +tag, +attrs, +binding, +children}, +rest}:
      (head, tail) = absent
      Std.transport(Bool, False{},
        (same => {Bool.pick(Maybe<&2, T.ExpandedNode>, same, Some{T.ExpandedNode{identity, occurrence, tag, attrs, binding, children}}, State.find_node(left, List.append(&2, T.ExpandedNode, children, rest), event)) == None{} : Maybe<&2, T.ExpandedNode>}),
        no_visible_lookup(left, List.append(&2, T.ExpandedNode, children, rest), event, tail), Syntax.same_event(T.EventIdentity{identity, occurrence}, event), head)

def Contract.unknown_owner_field(blocks, owner, path, occurrence, raw, absent):
  Std.transport(Maybe<&2, T.Block>, None{},
    (found => {State.dispatch_found(found, T.FieldEdited{T.EventIdentity{T.Identity{owner, path}, occurrence}, raw}, T.State{blocks}) == T.Decision{T.State{blocks}, Nil{}} : T.Decision}),
    {==}, State.find_block(blocks, owner), no_owner_lookup(blocks, owner, absent))

def Contract.unknown_owner_action(blocks, owner, path, occurrence, absent):
  Std.transport(Maybe<&2, T.Block>, None{},
    (found => {State.dispatch_found(found, T.Activated{T.EventIdentity{T.Identity{owner, path}, occurrence}}, T.State{blocks}) == T.Decision{T.State{blocks}, Nil{}} : T.Decision}),
    {==}, State.find_block(blocks, owner), no_owner_lookup(blocks, owner, absent))

def Contract.unknown_owner_completion(blocks, owner, path, ticket, success, message, absent):
  Std.transport(Maybe<&2, T.Block>, None{},
    (found => {State.feedback_completed_found(found, path, ticket, success, message, T.State{blocks}) == T.Decision{T.State{blocks}, Nil{}} : T.Decision}),
    {==}, State.find_block(blocks, owner), no_owner_lookup(blocks, owner, absent))

def observed_owned_scene(+prefix: +List<T.Block>, +block: T.Block, +suffix: +List<T.Block>, +owner: T.Owner, +scene: T.Scene,
  preceding: Contract.other_owners(prefix, owner), owned: {Syntax.same_owner(State.block_owner(block), owner) == True{} : Bool},
  exposed: {Model.observe(owner, T.State{List.append(&2, T.Block, prefix, block <> suffix)}) == scene : T.Scene}) ->
  {State.scene(block) == scene : T.Scene}:
  Equal.trans(T.Scene, State.scene(block), Model.observe(owner, T.State{List.append(&2, T.Block, prefix, block <> suffix)}), scene,
    Equal.sym(T.Scene, Model.observe(owner, T.State{List.append(&2, T.Block, prefix, block <> suffix)}), State.scene(block),
      Equal.cong(Maybe<&2, T.Block>, T.Scene, (found => State.observe_found(found, owner)),
        State.find_block(List.append(&2, T.Block, prefix, block <> suffix), owner), Some{block}, first_owner_lookup(prefix, block, suffix, owner, preceding, owned))), exposed)

def invisible_current_node(+block: T.Block, +event: T.EventIdentity, +owner: T.Owner, +nodes: +List<T.ExpandedNode>, +diagnostics: +List<T.Diagnostic>, +complete: Bool, +failed: Bool, +revision: Nat,
  exposed: {State.scene(block) == T.Scene{owner, nodes, diagnostics, complete, failed, revision} : T.Scene},
  absent: Contract.no_visible_event(4096n, nodes, event)) ->
  {State.current_node(block, event) == None{} : Maybe<&2, T.ExpandedNode>}:
  Equal.trans(Maybe<&2, T.ExpandedNode>, State.current_node(block, event), State.find_node(4096n, nodes, event), None{},
    Equal.cong(T.Scene, Maybe<&2, T.ExpandedNode>, (current => State.find_node(4096n, State.scene_nodes(current), event)), State.scene(block), T.Scene{owner, nodes, diagnostics, complete, failed, revision}, exposed),
    no_visible_lookup(4096n, nodes, event, absent))

def Contract.invisible_field(prefix, block, suffix, owner, path, occurrence, raw, nodes, diagnostics, complete, failed, revision, preceding, owned, exposed, absent):
  +state: T.State = T.State{List.append(&2, T.Block, prefix, block <> suffix)}
  +event: T.EventIdentity = T.EventIdentity{T.Identity{owner, path}, occurrence}
  Std.transport(Maybe<&2, T.Block>, Some{block},
    (found => @seen:{State.observe_found(found, owner) == T.Scene{owner, nodes, diagnostics, complete, failed, revision} : T.Scene} ->
      {State.dispatch_found(found, T.FieldEdited{event, raw}, state) == T.Decision{state, Nil{}} : T.Decision}),
    (seen => Equal.cong(State.BlockDecision, T.Decision, (result => State.apply(result, state)),
      State.reduce(block, T.FieldEdited{event, raw}), State.BlockDecision{block, Nil{}, False{}, False{}},
      absent_field_reduce(block, event, raw, invisible_current_node(block, event, owner, nodes, diagnostics, complete, failed, revision, seen, absent)))),
    State.find_block(List.append(&2, T.Block, prefix, block <> suffix), owner),
    first_owner_lookup(prefix, block, suffix, owner, preceding, owned))(exposed)

def Contract.invisible_action(prefix, block, suffix, owner, path, occurrence, nodes, diagnostics, complete, failed, revision, preceding, owned, exposed, absent):
  +state: T.State = T.State{List.append(&2, T.Block, prefix, block <> suffix)}
  +event: T.EventIdentity = T.EventIdentity{T.Identity{owner, path}, occurrence}
  Std.transport(Maybe<&2, T.Block>, Some{block},
    (found => @seen:{State.observe_found(found, owner) == T.Scene{owner, nodes, diagnostics, complete, failed, revision} : T.Scene} ->
      {State.dispatch_found(found, T.Activated{event}, state) == T.Decision{state, Nil{}} : T.Decision}),
    (seen => Equal.cong(State.BlockDecision, T.Decision, (result => State.apply(result, state)),
      State.reduce(block, T.Activated{event}), State.BlockDecision{block, Nil{}, False{}, False{}},
      absent_action_reduce(block, event, invisible_current_node(block, event, owner, nodes, diagnostics, complete, failed, revision, seen, absent)))),
    State.find_block(List.append(&2, T.Block, prefix, block <> suffix), owner),
    first_owner_lookup(prefix, block, suffix, owner, preceding, owned))(exposed)

def same_natural(+value: Nat) -> {Nat.is_eq(value, value) == True{} : Bool}:
  match value:
    case 0n: {==}
    case 1n+rest: same_natural(rest)

def natural_equality_symmetric(+left: Nat, +right: Nat) -> {Nat.is_eq(left, right) == Nat.is_eq(right, left) : Bool}:
  match left right:
    case 0n 0n: {==}
    case 0n 1n+rest: {==}
    case 1n+rest 0n: {==}
    case 1n+a 1n+b: natural_equality_symmetric(a, b)

def same_owner(+owner: T.Owner) -> {Syntax.same_owner(owner, owner) == True{} : Bool}:
  match owner:
    case T.Owner{+key, +epoch}:
      Equal.trans(Bool, String.eq(key, key) && Nat.is_eq(epoch, epoch), Nat.is_eq(epoch, epoch), True{},
        Equal.cong(Bool, Bool, (same => same && Nat.is_eq(epoch, epoch)), String.eq(key, key), True{}, Equality.same_string(key)), same_natural(epoch))

def same_correlation(+path: String, +ticket: Nat, +message: String) ->
  {Contract.correlation(T.Feedback{path, ticket, True{}, message}, path, ticket) == True{} : Bool}:
  Equal.trans(Bool, Contract.correlation(T.Feedback{path, ticket, True{}, message}, path, ticket), String.eq(path, path) && Nat.is_eq(ticket, ticket) && True{}, True{},
    Equal.cong(Bool, Bool, (same => same && Nat.is_eq(ticket, ticket) && True{}), SafeText.string_equal(path, path), String.eq(path, path), Equality.public_refines(path, path)),
    Equal.trans(Bool, String.eq(path, path) && Nat.is_eq(ticket, ticket) && True{}, Nat.is_eq(ticket, ticket) && True{}, True{},
      Equal.cong(Bool, Bool, (same => same && Nat.is_eq(ticket, ticket) && True{}), String.eq(path, path), True{}, Equality.same_string(path)),
      Equal.cong(Bool, Bool, (same => same && True{}), Nat.is_eq(ticket, ticket), True{}, same_natural(ticket))))

def matching_none(+entries: +List<T.Feedback>, +path: String, +ticket: Nat,
  absent: Contract.no_correlation(entries, path, ticket)) ->
  {State.matching_feedback(entries, path, ticket) == False{} : Bool}:
  match entries:
    case Nil{}: {==}
    case Con{T.Feedback{+key, +serial, +pending, +message}, +rest}:
      (head, tail) = absent
      Std.transport(Bool, False{},
        (current => {current || State.matching_feedback(rest, path, ticket) == False{} : Bool}),
        matching_none(rest, path, ticket, tail), Contract.correlation(T.Feedback{key, serial, pending, message}, path, ticket), head)

def matching_captured(+before: +List<T.Feedback>, +after: +List<T.Feedback>, +path: String, +ticket: Nat, +message: String,
  earlier: Contract.no_correlation(before, path, ticket)) ->
  {State.matching_feedback(List.append(&2, T.Feedback, before, T.Feedback{path, ticket, True{}, message} <> after), path, ticket) == True{} : Bool}:
  match before:
    case Nil{}:
      Std.transport(Bool, True{}, (current => {current || State.matching_feedback(after, path, ticket) == True{} : Bool}), {==}, Contract.correlation(T.Feedback{path, ticket, True{}, message}, path, ticket), same_correlation(path, ticket, message))
    case Con{T.Feedback{+key, +serial, +pending, +old}, +rest}:
      (head, tail) = earlier
      Std.transport(Bool, False{},
        (current => {current || State.matching_feedback(List.append(&2, T.Feedback, rest, T.Feedback{path, ticket, True{}, message} <> after), path, ticket) == True{} : Bool}),
        matching_captured(rest, after, path, ticket, message, tail), Contract.correlation(T.Feedback{key, serial, pending, old}, path, ticket), head)

def settlement_guard(+key: String, +serial: Nat, +pending: Bool, +old: String, +path: String, +ticket: Nat) ->
  {(SafeText.string_equal(key, path) && Nat.is_eq(ticket, serial) && pending) == Contract.correlation(T.Feedback{key, serial, pending, old}, path, ticket) : Bool}:
  Equal.cong(Bool, Bool, (same => SafeText.string_equal(key, path) && same && pending), Nat.is_eq(ticket, serial), Nat.is_eq(serial, ticket), natural_equality_symmetric(ticket, serial))

def settle_captured(+before: +List<T.Feedback>, +after: +List<T.Feedback>, +path: String, +ticket: Nat, +old: String, +success: Bool, +message: String,
  earlier: Contract.no_correlation(before, path, ticket)) ->
  {State.settle_feedback(List.append(&2, T.Feedback, before, T.Feedback{path, ticket, True{}, old} <> after), path, ticket, success, message) == List.append(&2, T.Feedback, before, T.Feedback{path, ticket, False{}, message} <> after) : +List<T.Feedback>}:
  match before:
    case Nil{}:
      Std.transport(Bool, True{},
        (current => {Bool.pick(+List<T.Feedback>, current, T.Feedback{path, ticket, False{}, message} <> after, T.Feedback{path, ticket, True{}, old} <> State.settle_feedback(after, path, ticket, success, message)) == T.Feedback{path, ticket, False{}, message} <> after : +List<T.Feedback>}),
        {==}, Contract.correlation(T.Feedback{path, ticket, True{}, old}, path, ticket), same_correlation(path, ticket, old))
    case Con{T.Feedback{+key, +serial, +pending, +previous}, +rest}:
      (head, tail) = earlier
      +remaining = List.append(&2, T.Feedback, rest, T.Feedback{path, ticket, True{}, old} <> after)
      Equal.trans(+List<T.Feedback>,
        State.settle_feedback(T.Feedback{key, serial, pending, previous} <> remaining, path, ticket, success, message),
        Bool.pick(+List<T.Feedback>, Contract.correlation(T.Feedback{key, serial, pending, previous}, path, ticket), T.Feedback{key, serial, False{}, message} <> remaining, T.Feedback{key, serial, pending, previous} <> State.settle_feedback(remaining, path, ticket, success, message)),
        List.append(&2, T.Feedback, T.Feedback{key, serial, pending, previous} <> rest, T.Feedback{path, ticket, False{}, message} <> after),
        Equal.cong(Bool, +List<T.Feedback>, (current => Bool.pick(+List<T.Feedback>, current, T.Feedback{key, serial, False{}, message} <> remaining, T.Feedback{key, serial, pending, previous} <> State.settle_feedback(remaining, path, ticket, success, message))),
          SafeText.string_equal(key, path) && Nat.is_eq(ticket, serial) && pending, Contract.correlation(T.Feedback{key, serial, pending, previous}, path, ticket), settlement_guard(key, serial, pending, previous, path, ticket)),
        Std.transport(Bool, False{},
          (current => {Bool.pick(+List<T.Feedback>, current, T.Feedback{key, serial, False{}, message} <> remaining, T.Feedback{key, serial, pending, previous} <> State.settle_feedback(remaining, path, ticket, success, message)) == List.append(&2, T.Feedback, T.Feedback{key, serial, pending, previous} <> rest, T.Feedback{path, ticket, False{}, message} <> after) : +List<T.Feedback>}),
          Equal.cong(+List<T.Feedback>, +List<T.Feedback>, (values => T.Feedback{key, serial, pending, previous} <> values), State.settle_feedback(remaining, path, ticket, success, message), List.append(&2, T.Feedback, rest, T.Feedback{path, ticket, False{}, message} <> after), settle_captured(rest, after, path, ticket, old, success, message, tail)),
          Contract.correlation(T.Feedback{key, serial, pending, previous}, path, ticket), head))

def save_at_replacement_owner(+prefix: +List<T.Block>, +original: T.Block, +suffix: +List<T.Block>, +replacement: T.Block,
  old_owner: {State.block_owner(original) == State.block_owner(replacement) : T.Owner},
  preceding: Contract.other_owners(prefix, State.block_owner(replacement))) ->
  {State.save_block(List.append(&2, T.Block, prefix, original <> suffix), replacement) == List.append(&2, T.Block, prefix, replacement <> suffix) : +List<T.Block>}:
  match prefix:
    case Nil{}:
      Std.transport(Bool, True{},
        (same => {Bool.pick(+List<T.Block>, same, replacement <> suffix, original <> State.save_block(suffix, replacement)) == replacement <> suffix : +List<T.Block>}),
        {==}, Syntax.same_owner(State.block_owner(original), State.block_owner(replacement)),
        Equal.trans(Bool, Syntax.same_owner(State.block_owner(original), State.block_owner(replacement)),
          Syntax.same_owner(State.block_owner(replacement), State.block_owner(replacement)), True{},
          Equal.cong(T.Owner, Bool, (key => Syntax.same_owner(key, State.block_owner(replacement))), State.block_owner(original), State.block_owner(replacement), old_owner),
          same_owner(State.block_owner(replacement))))
    case Con{T.Block{+key, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restored}, +rest}:
      (head, tail) = preceding
      +first: T.Block = T.Block{key, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restored}
      Std.transport(Bool, False{},
        (same => {Bool.pick(+List<T.Block>, same, replacement <> List.append(&2, T.Block, rest, original <> suffix), first <> State.save_block(List.append(&2, T.Block, rest, original <> suffix), replacement)) == List.append(&2, T.Block, first <> rest, replacement <> suffix) : +List<T.Block>}),
        Equal.cong(+List<T.Block>, +List<T.Block>, (remaining => first <> remaining), State.save_block(List.append(&2, T.Block, rest, original <> suffix), replacement), List.append(&2, T.Block, rest, replacement <> suffix), save_at_replacement_owner(rest, original, suffix, replacement, old_owner, tail)),
        Syntax.same_owner(key, State.block_owner(replacement)), head)

def save_existing_owner(+prefix: +List<T.Block>, +original: T.Block, +suffix: +List<T.Block>, +replacement: T.Block, +owner: T.Owner,
  old_owner: {State.block_owner(original) == owner : T.Owner}, new_owner: {State.block_owner(replacement) == owner : T.Owner},
  preceding: Contract.other_owners(prefix, owner)) ->
  {State.save_block(List.append(&2, T.Block, prefix, original <> suffix), replacement) == List.append(&2, T.Block, prefix, replacement <> suffix) : +List<T.Block>}:
  Std.transport(T.Owner, State.block_owner(replacement),
    (key => @old:{State.block_owner(original) == key : T.Owner} -> @before:Contract.other_owners(prefix, key) ->
      {State.save_block(List.append(&2, T.Block, prefix, original <> suffix), replacement) == List.append(&2, T.Block, prefix, replacement <> suffix) : +List<T.Block>}),
    (old => before => save_at_replacement_owner(prefix, original, suffix, replacement, old, before)),
    owner, Equal.sym(T.Owner, State.block_owner(replacement), owner, new_owner))(old_owner)(preceding)

def completed_record(+block: T.Block, +feedback: +List<T.Feedback>) ->
  {State.bump(State.with_feedback(block, feedback)) == Contract.completed_block(block, feedback) : T.Block}:
  match block:
    case T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, old, revision, next, edited, restored}: {==}

def completed_owner(+block: T.Block, +feedback: +List<T.Feedback>) ->
  {State.block_owner(Contract.completed_block(block, feedback)) == State.block_owner(block) : T.Owner}:
  match block:
    case T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, old, revision, next, edited, restored}: {==}

def Contract.uncorrelated_completion(prefix, block, suffix, path, ticket, success, message, preceding, absent):
  +owner = State.block_owner(block)
  +state: T.State = T.State{List.append(&2, T.Block, prefix, block <> suffix)}
  Equal.trans(T.Decision, Model.step(T.EffectCompleted{owner, path, ticket, success, message}, state), State.feedback_completed_found(Some{block}, path, ticket, success, message, state), T.Decision{state, Nil{}},
    Equal.cong(Maybe<&2, T.Block>, T.Decision, (found => State.feedback_completed_found(found, path, ticket, success, message, state)), State.find_block(List.append(&2, T.Block, prefix, block <> suffix), owner), Some{block}, first_owner_lookup(prefix, block, suffix, owner, preceding, same_owner(owner))),
    Equal.cong(Bool, T.Decision, (current => State.feedback_completed_checked(current, block, path, ticket, success, message, state)), State.matching_feedback(State.block_feedback(block), path, ticket), False{}, matching_none(State.block_feedback(block), path, ticket, absent)))

def captured_settlement(+block: T.Block, +before: +List<T.Feedback>, +after: +List<T.Feedback>, +path: String, +ticket: Nat, +old: String, +success: Bool, +message: String,
  earlier: Contract.no_correlation(before, path, ticket), captured: {State.block_feedback(block) == List.append(&2, T.Feedback, before, T.Feedback{path, ticket, True{}, old} <> after) : +List<T.Feedback>}) ->
  {State.settle_feedback(State.block_feedback(block), path, ticket, success, message) == List.append(&2, T.Feedback, before, T.Feedback{path, ticket, False{}, message} <> after) : +List<T.Feedback>}:
  Equal.trans(+List<T.Feedback>, State.settle_feedback(State.block_feedback(block), path, ticket, success, message), State.settle_feedback(List.append(&2, T.Feedback, before, T.Feedback{path, ticket, True{}, old} <> after), path, ticket, success, message), List.append(&2, T.Feedback, before, T.Feedback{path, ticket, False{}, message} <> after),
    Equal.cong(+List<T.Feedback>, +List<T.Feedback>, (feedback => State.settle_feedback(feedback, path, ticket, success, message)), State.block_feedback(block), List.append(&2, T.Feedback, before, T.Feedback{path, ticket, True{}, old} <> after), captured), settle_captured(before, after, path, ticket, old, success, message, earlier))

def split_owner_head(+key: T.Owner, +owner: T.Owner, +rest: +List<T.Block>,
  tails: Pair(Contract.other_owners(rest, owner), Contract.other_owners(rest, owner)),
  head: {Syntax.same_owner(key, owner) == False{} : Bool}) ->
  Pair(Pair({Syntax.same_owner(key, owner) == False{} : Bool}, Contract.other_owners(rest, owner)), Pair({Syntax.same_owner(key, owner) == False{} : Bool}, Contract.other_owners(rest, owner))):
  (left, right) = tails
  Std.transport(Bool, False{},
    (same => Pair(Pair({same == False{} : Bool}, Contract.other_owners(rest, owner)), Pair({same == False{} : Bool}, Contract.other_owners(rest, owner)))),
    (({==}, left), ({==}, right)), Syntax.same_owner(key, owner), head)

def split_owner_facts(+prefix: +List<T.Block>, +owner: T.Owner, facts: Contract.other_owners(prefix, owner)) ->
  Pair(Contract.other_owners(prefix, owner), Contract.other_owners(prefix, owner)):
  match prefix:
    case Nil{}: (Unit{}, Unit{})
    case Con{T.Block{+key, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restored}, +rest}:
      (head, tail) = facts
      split_owner_head(key, owner, rest, split_owner_facts(rest, owner, tail), head)

def split_owner_thrice(+prefix: +List<T.Block>, +owner: T.Owner,
  facts: Pair(Contract.other_owners(prefix, owner), Contract.other_owners(prefix, owner))) ->
  Pair(Contract.other_owners(prefix, owner), Pair(Contract.other_owners(prefix, owner), Contract.other_owners(prefix, owner))):
  (first, remaining) = facts
  (first, split_owner_facts(prefix, owner, remaining))

def split_correlation_head(+entry: T.Feedback, +rest: +List<T.Feedback>, +path: String, +ticket: Nat,
  tails: Pair(Contract.no_correlation(rest, path, ticket), Contract.no_correlation(rest, path, ticket)),
  head: {Contract.correlation(entry, path, ticket) == False{} : Bool}) ->
  Pair(Pair({Contract.correlation(entry, path, ticket) == False{} : Bool}, Contract.no_correlation(rest, path, ticket)), Pair({Contract.correlation(entry, path, ticket) == False{} : Bool}, Contract.no_correlation(rest, path, ticket))):
  (left, right) = tails
  Std.transport(Bool, False{},
    (same => Pair(Pair({same == False{} : Bool}, Contract.no_correlation(rest, path, ticket)), Pair({same == False{} : Bool}, Contract.no_correlation(rest, path, ticket)))),
    (({==}, left), ({==}, right)), Contract.correlation(entry, path, ticket), head)

def split_correlation_facts(+before: +List<T.Feedback>, +path: String, +ticket: Nat,
  facts: Contract.no_correlation(before, path, ticket)) ->
  Pair(Contract.no_correlation(before, path, ticket), Contract.no_correlation(before, path, ticket)):
  match before:
    case Nil{}: (Unit{}, Unit{})
    case Con{+entry, +rest}:
      (head, tail) = facts
      split_correlation_head(entry, rest, path, ticket, split_correlation_facts(rest, path, ticket, tail), head)

def correlated_completion_evidence(+prefix: +List<T.Block>, +block: T.Block, +suffix: +List<T.Block>, +before: +List<T.Feedback>, +after: +List<T.Feedback>, +path: String, +ticket: Nat, +old_message: String, +success: Bool, +message: String,
  prefix_facts: Pair(Contract.other_owners(prefix, State.block_owner(block)), Contract.other_owners(prefix, State.block_owner(block))),
  before_facts: Pair(Contract.no_correlation(before, path, ticket), Contract.no_correlation(before, path, ticket)),
  captured_facts: Pair({State.block_feedback(block) == List.append(&2, T.Feedback, before, T.Feedback{path, ticket, True{}, old_message} <> after) : +List<T.Feedback>}, {State.block_feedback(block) == List.append(&2, T.Feedback, before, T.Feedback{path, ticket, True{}, old_message} <> after) : +List<T.Feedback>})) ->
  {Model.step(T.EffectCompleted{State.block_owner(block), path, ticket, success, message}, T.State{List.append(&2, T.Block, prefix, block <> suffix)}) ==
    T.Decision{T.State{List.append(&2, T.Block, prefix, Contract.completed_block(block, List.append(&2, T.Feedback, before, T.Feedback{path, ticket, False{}, message} <> after)) <> suffix)}, Nil{}} : T.Decision}:
  (lookup_prefix, save_prefix) = prefix_facts
  (matching_before, settlement_before) = before_facts
  (matching_feedback, settlement_feedback) = captured_facts
  +owner = State.block_owner(block)
  +state: T.State = T.State{List.append(&2, T.Block, prefix, block <> suffix)}
  +feedback = List.append(&2, T.Feedback, before, T.Feedback{path, ticket, False{}, message} <> after)
  +replacement = Contract.completed_block(block, feedback)
  Equal.trans(T.Decision, Model.step(T.EffectCompleted{owner, path, ticket, success, message}, state), State.feedback_completed_found(Some{block}, path, ticket, success, message, state), T.Decision{T.State{List.append(&2, T.Block, prefix, replacement <> suffix)}, Nil{}},
    Equal.cong(Maybe<&2, T.Block>, T.Decision, (found => State.feedback_completed_found(found, path, ticket, success, message, state)), State.find_block(List.append(&2, T.Block, prefix, block <> suffix), owner), Some{block}, first_owner_lookup(prefix, block, suffix, owner, lookup_prefix, same_owner(owner))),
    Equal.trans(T.Decision, State.feedback_completed_found(Some{block}, path, ticket, success, message, state), State.feedback_completed_checked(True{}, block, path, ticket, success, message, state), T.Decision{T.State{List.append(&2, T.Block, prefix, replacement <> suffix)}, Nil{}},
      Equal.cong(Bool, T.Decision, (current => State.feedback_completed_checked(current, block, path, ticket, success, message, state)), State.matching_feedback(State.block_feedback(block), path, ticket), True{},
        Equal.trans(Bool, State.matching_feedback(State.block_feedback(block), path, ticket), State.matching_feedback(List.append(&2, T.Feedback, before, T.Feedback{path, ticket, True{}, old_message} <> after), path, ticket), True{},
          Equal.cong(+List<T.Feedback>, Bool, (entries => State.matching_feedback(entries, path, ticket)), State.block_feedback(block), List.append(&2, T.Feedback, before, T.Feedback{path, ticket, True{}, old_message} <> after), matching_feedback), matching_captured(before, after, path, ticket, old_message, matching_before))),
      Equal.trans(T.Decision, State.feedback_completed_checked(True{}, block, path, ticket, success, message, state), T.Decision{T.State{State.save_block(List.append(&2, T.Block, prefix, block <> suffix), replacement)}, Nil{}}, T.Decision{T.State{List.append(&2, T.Block, prefix, replacement <> suffix)}, Nil{}},
        Equal.cong(T.Block, T.Decision, (settled => T.Decision{T.State{State.save_block(List.append(&2, T.Block, prefix, block <> suffix), settled)}, Nil{}}), State.bump(State.with_feedback(block, State.settle_feedback(State.block_feedback(block), path, ticket, success, message))), replacement,
          Equal.trans(T.Block, State.bump(State.with_feedback(block, State.settle_feedback(State.block_feedback(block), path, ticket, success, message))), State.bump(State.with_feedback(block, feedback)), replacement,
            Equal.cong(+List<T.Feedback>, T.Block, (entries => State.bump(State.with_feedback(block, entries))), State.settle_feedback(State.block_feedback(block), path, ticket, success, message), feedback, captured_settlement(block, before, after, path, ticket, old_message, success, message, settlement_before, settlement_feedback)), completed_record(block, feedback))),
        Equal.cong(+List<T.Block>, T.Decision, (blocks => T.Decision{T.State{blocks}, Nil{}}), State.save_block(List.append(&2, T.Block, prefix, block <> suffix), replacement), List.append(&2, T.Block, prefix, replacement <> suffix), save_existing_owner(prefix, block, suffix, replacement, owner, {==}, completed_owner(block, feedback), save_prefix)))))

def Contract.correlated_completion(prefix, block, suffix, before, after, path, ticket, old_message, success, message, preceding, earlier, captured):
  +pending_feedback = List.append(&2, T.Feedback, before, T.Feedback{path, ticket, True{}, old_message} <> after)
  correlated_completion_evidence(prefix, block, suffix, before, after, path, ticket, old_message, success, message,
    split_owner_facts(prefix, State.block_owner(block), preceding), split_correlation_facts(before, path, ticket, earlier),
    Std.transport(+List<T.Feedback>, pending_feedback,
      (entries => Pair({entries == pending_feedback : +List<T.Feedback>}, {entries == pending_feedback : +List<T.Feedback>})),
      ({==}, {==}), State.block_feedback(block), captured))

def completed_checked_effects(+current: Bool, +block: T.Block, +path: String, +ticket: Nat,
  +success: Bool, +message: String, +state: T.State) ->
  {Contract.decision_effects(State.feedback_completed_checked(current, block, path, ticket, success, message, state)) == Nil{} : +List<T.Effect>}:
  match current state:
    case False{} _: {==}
    case True{} T.State{blocks}: {==}

def completed_found_effects(+found: Maybe<&2, T.Block>, +path: String, +ticket: Nat,
  +success: Bool, +message: String, +state: T.State) ->
  {Contract.decision_effects(State.feedback_completed_found(found, path, ticket, success, message, state)) == Nil{} : +List<T.Effect>}:
  match found:
    case None{}: {==}
    case Some{+block}:
      completed_checked_effects(State.matching_feedback(State.block_feedback(block), path, ticket), block, path, ticket, success, message, state)

def Contract.completion_emits_no_effects(owner, path, ticket, success, message, state):
  T.State{+blocks} = state
  completed_found_effects(State.find_block(blocks, owner), path, ticket, success, message, T.State{blocks})

def mount_occurrence(+mounts: +List<T.Mount>, +path: String) ->
  {State.find_mount(mounts, path) == Contract.occurrence_at(mounts, path) : Maybe<&2, Nat>}:
  match mounts:
    case Nil{}: {==}
    case Con{T.Mount{+key, +occurrence}, +rest}:
      Equal.cong(Maybe<&2, Nat>, Maybe<&2, Nat>, (tail => Bool.pick(Maybe<&2, Nat>, SafeText.string_equal(key, path), Some{occurrence}, tail)), State.find_mount(rest, path), Contract.occurrence_at(rest, path), mount_occurrence(rest, path))

def mount_exists_branch(+same: Bool, +occurrence: Nat, +tail: Maybe<&2, Nat>) ->
  {State.mount_present(Bool.pick(Maybe<&2, Nat>, same, Some{occurrence}, tail)) == (same || State.mount_present(tail)) : Bool}:
  match same:
    case False{}: {==}
    case True{}: {==}

def mount_exists(+mounts: +List<T.Mount>, +path: String) ->
  {State.mount_present(State.find_mount(mounts, path)) == Contract.path_is_mounted(mounts, path) : Bool}:
  match mounts:
    case Nil{}: {==}
    case Con{T.Mount{+key, +occurrence}, +rest}:
      Equal.trans(Bool, State.mount_present(State.find_mount(T.Mount{key, occurrence} <> rest, path)),
        SafeText.string_equal(key, path) || State.mount_present(State.find_mount(rest, path)), Contract.path_is_mounted(T.Mount{key, occurrence} <> rest, path),
        mount_exists_branch(SafeText.string_equal(key, path), occurrence, State.find_mount(rest, path)),
        Equal.cong(Bool, Bool, (tail => SafeText.string_equal(key, path) || tail), State.mount_present(State.find_mount(rest, path)), Contract.path_is_mounted(rest, path), mount_exists(rest, path)))

def retained_feedback(+entries: +List<T.Feedback>, +mounts: +List<T.Mount>) ->
  {State.prune_feedback(entries, mounts) == Contract.current_feedback(entries, mounts) : +List<T.Feedback>}:
  match entries:
    case Nil{}: {==}
    case Con{T.Feedback{+path, +ticket, +pending, +message}, +rest}:
      Equal.trans(+List<T.Feedback>, State.prune_feedback(T.Feedback{path, ticket, pending, message} <> rest, mounts),
        Bool.pick(+List<T.Feedback>, Contract.keep_feedback(T.Feedback{path, ticket, pending, message}, mounts), T.Feedback{path, ticket, pending, message} <> State.prune_feedback(rest, mounts), State.prune_feedback(rest, mounts)), Contract.current_feedback(T.Feedback{path, ticket, pending, message} <> rest, mounts),
        Equal.cong(Bool, +List<T.Feedback>, (keep => Bool.pick(+List<T.Feedback>, keep, T.Feedback{path, ticket, pending, message} <> State.prune_feedback(rest, mounts), State.prune_feedback(rest, mounts))), String.eq(path, "@storage") || State.mount_present(State.find_mount(mounts, path)), Contract.keep_feedback(T.Feedback{path, ticket, pending, message}, mounts),
          Equal.cong(Bool, Bool, (found => String.eq(path, "@storage") || found), State.mount_present(State.find_mount(mounts, path)), Contract.path_is_mounted(mounts, path), mount_exists(mounts, path))),
        Equal.cong(+List<T.Feedback>, +List<T.Feedback>, (tail => Bool.pick(+List<T.Feedback>, Contract.keep_feedback(T.Feedback{path, ticket, pending, message}, mounts), T.Feedback{path, ticket, pending, message} <> tail, tail)), State.prune_feedback(rest, mounts), Contract.current_feedback(rest, mounts), retained_feedback(rest, mounts)))

def current_sources(+sources: +List<J.Field>) ->
  {State.sources_fresh(sources) == List.all(~&2, ~J.Field, ~Contract.source_is_current, sources) : Bool}:
  match sources:
    case Nil{}: {==}
    case Con{J.Field{+name, +value}, +rest}:
      Equal.cong(Bool, Bool, (tail => Contract.source_is_current(J.Field{name, value}) && tail), State.sources_fresh(rest), List.all(~&2, ~J.Field, ~Contract.source_is_current, rest), current_sources(rest))

def complete_ending(+ending: T.Ending) -> {State.is_complete(ending) == Contract.is_complete(ending) : Bool}:
  match ending:
    case T.Open{}: {==}
    case T.Complete{}: {==}
    case T.Interrupted{}: {==}

def action_authority(+block: T.Block, +prepared: Registry.Prepared) ->
  {State.external_allowed(block, prepared) == Contract.action_authority(block, prepared) : Bool}:
  match block:
    case T.Block{owner, source, T.Syntax{roots, frames, tail, +failed, +sealed, accepted, characters, diagnostic}, +ending, +closed, +external, locals, +sources, views, mounts, feedback, revision, next, edited, restored}:
      Equal.trans(Bool, sealed && external && closed && State.is_complete(ending) && Bool.not(failed) && Bool.not(Registry.prepared_fatal(prepared)) && State.sources_fresh(sources),
        sealed && external && closed && Contract.is_complete(ending) && Bool.not(failed) && Bool.not(Registry.prepared_fatal(prepared)) && State.sources_fresh(sources),
        sealed && external && closed && Contract.is_complete(ending) && Bool.not(failed) && Bool.not(Registry.prepared_fatal(prepared)) && List.all(~&2, ~J.Field, ~Contract.source_is_current, sources),
        Equal.cong(Bool, Bool, (complete => sealed && external && closed && complete && Bool.not(failed) && Bool.not(Registry.prepared_fatal(prepared)) && State.sources_fresh(sources)), State.is_complete(ending), Contract.is_complete(ending), complete_ending(ending)),
        Equal.cong(Bool, Bool, (current => sealed && external && closed && Contract.is_complete(ending) && Bool.not(failed) && Bool.not(Registry.prepared_fatal(prepared)) && current), State.sources_fresh(sources), List.all(~&2, ~J.Field, ~Contract.source_is_current, sources), current_sources(sources)))

def declared_nodes(+block: T.Block, +prepared: Registry.Prepared) ->
  {State.raw_nodes(block, prepared) == Contract.declaration_nodes(block, prepared) : +List<T.ExpandedNode>}:
  match block:
    case T.Block{+owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restored}:
      Equal.cong(Bool, +List<T.ExpandedNode>,
        (allowed => Expand.expanded_nodes(Expand.expand_bounded(owner, Registry.accepted_elements(block, prepared), Registry.prepared_env(prepared), Registry.prepared_locals(prepared), views, mounts, allowed, Registry.prepared_remaining(prepared)))), State.external_allowed(block, prepared), Contract.action_authority(block, prepared), action_authority(block, prepared))

def visible_paths(+work: Nat, +nodes: +List<T.ExpandedNode>, +reversed: +List<String>) ->
  {State.node_paths(work, nodes, reversed) == Contract.visible_paths(work, nodes, reversed) : +List<String>}:
  match work nodes:
    case _ Nil{}: {==}
    case 0n Con{first, rest}: {==}
    case 1n+left Con{T.ExpandedNode{T.Identity{owner, +path}, occurrence, tag, attrs, binding, children}, rest}:
      visible_paths(left, List.append(&2, T.ExpandedNode, children, rest), path <> reversed)

def reverse_mount_suffix(+items: +List<T.Mount>, +reversed: +List<T.Mount>, +suffix: +List<T.Mount>) ->
  {List.reverse.go(&2, T.Mount, items, List.append(&2, T.Mount, reversed, suffix)) == List.append(&2, T.Mount, List.reverse.go(&2, T.Mount, items, reversed), suffix) : +List<T.Mount>}:
  match items:
    case Nil{}: {==}
    case Con{first, rest}: reverse_mount_suffix(rest, first <> reversed, suffix)

def reverse_mount_cons(+entry: T.Mount, +items: +List<T.Mount>) ->
  {List.reverse(&2, T.Mount, entry <> items) == List.append(&2, T.Mount, List.reverse(&2, T.Mount, items), [entry]) : +List<T.Mount>}:
  reverse_mount_suffix(items, Nil{}, [entry])

def chosen_occurrence(+previous: Maybe<&2, Nat>, +floor: Nat) ->
  Contract.occurrence_choice(previous, floor, State.mount_number(previous, floor), 1n+floor):
  match previous:
    case None{}: (0n, ({==}, (0n, {==})))
    case Some{old}: ({==}, (1n, {==}))

def mount_segment(+paths: +List<String>, +previous: +List<T.Mount>, +floor: Nat, +reversed: +List<T.Mount>, +result: State.MountResult) -> Type:
  match result:
    case State.MountResult{mounted, following}:
      Exists(+List<T.Mount>, (suffix => Pair({mounted == List.append(&2, T.Mount, List.reverse(&2, T.Mount, reversed), suffix) : +List<T.Mount>}, Contract.mount_lifecycle(paths, previous, floor, suffix, following))))

def prepend_mount_segment(+path: String, +rest: +List<String>, +previous: +List<T.Mount>, +floor: Nat, +reversed: +List<T.Mount>, +result: State.MountResult,
  tail: mount_segment(rest, previous, 1n+floor, T.Mount{path, State.mount_number(State.find_mount(previous, path), floor)} <> reversed, result)) ->
  mount_segment(path <> rest, previous, floor, reversed, result):
  match result:
    case State.MountResult{+mounted, +following}:
      (+suffix, (same, lifecycle)) = tail
      +occurrence = State.mount_number(State.find_mount(previous, path), floor)
      +entry: T.Mount = T.Mount{path, occurrence}
      (entry <> suffix,
        (Equal.trans(+List<T.Mount>, mounted, List.append(&2, T.Mount, List.reverse(&2, T.Mount, entry <> reversed), suffix), List.append(&2, T.Mount, List.reverse(&2, T.Mount, reversed), entry <> suffix), same,
          Equal.trans(+List<T.Mount>, List.append(&2, T.Mount, List.reverse(&2, T.Mount, entry <> reversed), suffix), List.append(&2, T.Mount, List.append(&2, T.Mount, List.reverse(&2, T.Mount, reversed), [entry]), suffix), List.append(&2, T.Mount, List.reverse(&2, T.Mount, reversed), entry <> suffix),
            Equal.cong(+List<T.Mount>, +List<T.Mount>, (head => List.append(&2, T.Mount, head, suffix)), List.reverse(&2, T.Mount, entry <> reversed), List.append(&2, T.Mount, List.reverse(&2, T.Mount, reversed), [entry]), reverse_mount_cons(entry, reversed)),
            Equal.sym(+List<T.Mount>, List.append(&2, T.Mount, List.reverse(&2, T.Mount, reversed), entry <> suffix), List.append(&2, T.Mount, List.append(&2, T.Mount, List.reverse(&2, T.Mount, reversed), [entry]), suffix), Std.app_assoc(T.Mount, List.reverse(&2, T.Mount, reversed), [entry], suffix)))),
          ({==}, (1n+floor,
            (Std.transport(Maybe<&2, Nat>, State.find_mount(previous, path), (saved => Contract.occurrence_choice(saved, floor, occurrence, 1n+floor)), chosen_occurrence(State.find_mount(previous, path), floor), Contract.occurrence_at(previous, path), Equal.sym(Maybe<&2, Nat>, State.find_mount(previous, path), Contract.occurrence_at(previous, path), mount_occurrence(previous, path))), lifecycle)))))

def allocated_mounts(+paths: +List<String>, +previous: +List<T.Mount>, +floor: Nat, +reversed: +List<T.Mount>) ->
  mount_segment(paths, previous, floor, reversed, State.mounts_for(paths, previous, floor, reversed)):
  match paths:
    case Nil{}: (Nil{}, (Equal.sym(+List<T.Mount>, List.append(&2, T.Mount, List.reverse(&2, T.Mount, reversed), Nil{}), List.reverse(&2, T.Mount, reversed), Std.app_nil_r(T.Mount, List.reverse(&2, T.Mount, reversed))), (0n, {==})))
    case Con{+path, +rest}:
      prepend_mount_segment(path, rest, previous, floor, reversed,
        State.mounts_for(rest, previous, 1n+floor, T.Mount{path, State.mount_number(State.find_mount(previous, path), floor)} <> reversed),
        allocated_mounts(rest, previous, 1n+floor, T.Mount{path, State.mount_number(State.find_mount(previous, path), floor)} <> reversed))

def declared_paths(+block: T.Block, +prepared: Registry.Prepared) ->
  {State.node_paths(4096n, State.raw_nodes(block, prepared), Nil{}) == Contract.visible_paths(4096n, Contract.declaration_nodes(block, prepared), Nil{}) : +List<String>}:
  Equal.trans(+List<String>, State.node_paths(4096n, State.raw_nodes(block, prepared), Nil{}), Contract.visible_paths(4096n, State.raw_nodes(block, prepared), Nil{}), Contract.visible_paths(4096n, Contract.declaration_nodes(block, prepared), Nil{}),
    visible_paths(4096n, State.raw_nodes(block, prepared), Nil{}),
    Equal.cong(+List<T.ExpandedNode>, +List<String>, (nodes => Contract.visible_paths(4096n, nodes, Nil{})), State.raw_nodes(block, prepared), Contract.declaration_nodes(block, prepared), declared_nodes(block, prepared)))

def reconciled_result(+block: T.Block, +prepared: Registry.Prepared, +result: State.MountResult) -> T.Block:
  State.MountResult{mounts, next} = result
  Contract.reconciled_block(block, prepared, mounts, next)

def reconciled_fields(+block: T.Block, +prepared: Registry.Prepared, +result: State.MountResult) ->
  {State.normalized_mounts(Contract.declaration_block(block, prepared), result) ==
    reconciled_result(block, prepared, result) : T.Block}:
  match block result:
    case T.Block{+owner, +source, +syntax, +ending, +closed, +external, locals, +sources, +views, old_mounts, +feedback, +revision, old_next, +edited, +restored} State.MountResult{+mounts, +next}:
      Equal.cong(+List<T.Feedback>, T.Block,
        (retained => T.Block{owner, source, syntax, ending, closed, external, Registry.prepared_locals(prepared), sources, views, mounts, retained, revision, next, edited, restored}), State.prune_feedback(feedback, mounts), Contract.current_feedback(feedback, mounts), retained_feedback(feedback, mounts))

def reconciliation_assigned(+block: T.Block, +prepared: Registry.Prepared, +result: State.MountResult,
  declarations: {Registry.prepare(block) == prepared : Registry.Prepared},
  allocation: mount_segment(State.node_paths(4096n, State.raw_nodes(Contract.declaration_block(block, prepared), prepared), Nil{}), Contract.block_mounts(block), Contract.block_next(block), Nil{}, result)) ->
  Contract.Reconciled<block, State.normalized_mounts(Contract.declaration_block(block, prepared), result)>:
  match result:
    case State.MountResult{+mounts, +next}:
      (+suffix, (same, lifecycle)) = allocation
      Contract.Reconciled{prepared, mounts, next, declarations,
        Std.transport(+List<String>, State.node_paths(4096n, State.raw_nodes(Contract.declaration_block(block, prepared), prepared), Nil{}),
          (paths => Contract.mount_lifecycle(paths, Contract.block_mounts(block), Contract.block_next(block), mounts, next)),
          Std.transport(+List<T.Mount>, suffix,
            (assigned => Contract.mount_lifecycle(State.node_paths(4096n, State.raw_nodes(Contract.declaration_block(block, prepared), prepared), Nil{}), Contract.block_mounts(block), Contract.block_next(block), assigned, next)), lifecycle, mounts, same),
          Contract.visible_paths(4096n, Contract.declaration_nodes(Contract.declaration_block(block, prepared), prepared), Nil{}),
          Equal.sym(+List<String>, State.node_paths(4096n, State.raw_nodes(Contract.declaration_block(block, prepared), prepared), Nil{}), Contract.visible_paths(4096n, Contract.declaration_nodes(Contract.declaration_block(block, prepared), prepared), Nil{}), declared_paths(Contract.declaration_block(block, prepared), prepared))),
        reconciled_fields(block, prepared, State.MountResult{mounts, next})}

def reconciled(+block: T.Block) -> Contract.Reconciled<block, State.normalize(block)>:
  match block:
    case T.Block{+owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restored}:
      reconciliation_assigned(block, Registry.prepare(block),
        State.mounts_for(State.node_paths(4096n, State.raw_nodes(Contract.declaration_block(block, Registry.prepare(block)), Registry.prepare(block)), Nil{}), mounts, next, Nil{}), {==},
        allocated_mounts(State.node_paths(4096n, State.raw_nodes(Contract.declaration_block(block, Registry.prepare(block)), Registry.prepare(block)), Nil{}), mounts, next, Nil{}))

def selected_visible_node(+work: Nat, +nodes: +List<T.ExpandedNode>, +event: T.EventIdentity, +target: T.ExpandedNode,
  selected: Contract.visible_selection(work, nodes, event, target)) ->
  {State.find_node(work, nodes, event) == Some{target} : Maybe<&2, T.ExpandedNode>}:
  match work nodes selected:
    case 0n Nil{} impossible: Logic.impossible({State.find_node(0n, Nil{}, event) == Some{target} : Maybe<&2, T.ExpandedNode>}, impossible)
    case 0n Con{node, rest} impossible: Logic.impossible({State.find_node(0n, node <> rest, event) == Some{target} : Maybe<&2, T.ExpandedNode>}, impossible)
    case 1n+left Nil{} impossible: Logic.impossible({State.find_node(1n+left, Nil{}, event) == Some{target} : Maybe<&2, T.ExpandedNode>}, impossible)
    case 1n+left Con{T.ExpandedNode{+identity, +occurrence, +tag, +attrs, +binding, +children}, +rest} Inl{(matched, same)}:
      Std.transport(Bool, True{},
        (current => {Bool.pick(Maybe<&2, T.ExpandedNode>, current, Some{T.ExpandedNode{identity, occurrence, tag, attrs, binding, children}}, State.find_node(left, List.append(&2, T.ExpandedNode, children, rest), event)) == Some{target} : Maybe<&2, T.ExpandedNode>}),
        Equal.cong(T.ExpandedNode, Maybe<&2, T.ExpandedNode>, (node => Some{node}), T.ExpandedNode{identity, occurrence, tag, attrs, binding, children}, target, Equal.sym(T.ExpandedNode, target, T.ExpandedNode{identity, occurrence, tag, attrs, binding, children}, same)),
        Syntax.same_event(T.EventIdentity{identity, occurrence}, event), matched)
    case 1n+left Con{T.ExpandedNode{+identity, +occurrence, +tag, +attrs, +binding, +children}, +rest} Inr{(missed, tail)}:
      Std.transport(Bool, False{},
        (current => {Bool.pick(Maybe<&2, T.ExpandedNode>, current, Some{T.ExpandedNode{identity, occurrence, tag, attrs, binding, children}}, State.find_node(left, List.append(&2, T.ExpandedNode, children, rest), event)) == Some{target} : Maybe<&2, T.ExpandedNode>}),
        selected_visible_node(left, List.append(&2, T.ExpandedNode, children, rest), event, target, tail), Syntax.same_event(T.EventIdentity{identity, occurrence}, event), missed)

def observed_selected_node(+block: T.Block, +event: T.EventIdentity, +owner: T.Owner, +nodes: +List<T.ExpandedNode>, +diagnostics: +List<T.Diagnostic>, +complete: Bool, +failed: Bool, +revision: Nat, +target: T.ExpandedNode,
  exposed: {State.scene(block) == T.Scene{owner, nodes, diagnostics, complete, failed, revision} : T.Scene}, selected: Contract.visible_selection(4096n, nodes, event, target)) ->
  {State.current_node(block, event) == Some{target} : Maybe<&2, T.ExpandedNode>}:
  Equal.trans(Maybe<&2, T.ExpandedNode>, State.current_node(block, event), State.find_node(4096n, nodes, event), Some{target},
    Equal.cong(T.Scene, Maybe<&2, T.ExpandedNode>, (scene => State.find_node(4096n, State.scene_nodes(scene), event)), State.scene(block), T.Scene{owner, nodes, diagnostics, complete, failed, revision}, exposed), selected_visible_node(4096n, nodes, event, target, selected))

def first_local_lookup(+before: +List<T.Local>, +after: +List<T.Local>, +id: String, +schema: T.StateSchema, +value: J.Json, +raw: String, +validation: Maybe<&2, String>, earlier: Contract.other_locals(before, id)) ->
  {Registry.find_local(List.append(&2, T.Local, before, T.Local{id, schema, value, raw, validation} <> after), id) == Some{T.Local{id, schema, value, raw, validation}} : Maybe<&2, T.Local>}:
  match before:
    case Nil{}:
      Std.transport(Bool, True{}, (same => {Bool.pick(Maybe<&2, T.Local>, same, Some{T.Local{id, schema, value, raw, validation}}, Registry.find_local(after, id)) == Some{T.Local{id, schema, value, raw, validation}} : Maybe<&2, T.Local>}), {==}, String.eq(id, id), Equality.same_string(id))
    case Con{T.Local{+key, +kind, +previous, +previous_raw, +notice}, +rest}:
      (head, tail) = earlier
      Std.transport(Bool, False{},
        (same => {Bool.pick(Maybe<&2, T.Local>, same, Some{T.Local{key, kind, previous, previous_raw, notice}}, Registry.find_local(List.append(&2, T.Local, rest, T.Local{id, schema, value, raw, validation} <> after), id)) == Some{T.Local{id, schema, value, raw, validation}} : Maybe<&2, T.Local>}), first_local_lookup(rest, after, id, schema, value, raw, validation, tail), String.eq(key, id), head)

def replace_first_local(+before: +List<T.Local>, +after: +List<T.Local>, +id: String, +schema: T.StateSchema, +value: J.Json, +raw: String, +validation: Maybe<&2, String>, +replacement: T.Local, earlier: Contract.other_locals(before, id)) ->
  {State.replace_local(List.append(&2, T.Local, before, T.Local{id, schema, value, raw, validation} <> after), id, replacement) == List.append(&2, T.Local, before, replacement <> after) : +List<T.Local>}:
  match before:
    case Nil{}:
      Std.transport(Bool, True{}, (same => {Bool.pick(+List<T.Local>, same, replacement <> after, T.Local{id, schema, value, raw, validation} <> State.replace_local(after, id, replacement)) == replacement <> after : +List<T.Local>}), {==}, String.eq(id, id), Equality.same_string(id))
    case Con{T.Local{+key, +kind, +previous, +previous_raw, +notice}, +rest}:
      (head, tail) = earlier
      Std.transport(Bool, False{},
        (same => {Bool.pick(+List<T.Local>, same, replacement <> List.append(&2, T.Local, rest, T.Local{id, schema, value, raw, validation} <> after), T.Local{key, kind, previous, previous_raw, notice} <> State.replace_local(List.append(&2, T.Local, rest, T.Local{id, schema, value, raw, validation} <> after), id, replacement)) == List.append(&2, T.Local, T.Local{key, kind, previous, previous_raw, notice} <> rest, replacement <> after) : +List<T.Local>}),
        Equal.cong(+List<T.Local>, +List<T.Local>, (tail => T.Local{key, kind, previous, previous_raw, notice} <> tail), State.replace_local(List.append(&2, T.Local, rest, T.Local{id, schema, value, raw, validation} <> after), id, replacement), List.append(&2, T.Local, rest, replacement <> after), replace_first_local(rest, after, id, schema, value, raw, validation, replacement, tail)), String.eq(key, id), head)

def parsed_local_result(+parsed: Result<&2, &2, String, J.Json>, +id: String, +schema: T.StateSchema, +value: J.Json, +raw: String) ->
  {State.local_edit(parsed, id, schema, value, raw) == Contract.parsed_local(id, schema, value, raw, parsed) : T.Local}:
  match parsed:
    case Done{accepted}: {==}
    case Fail{reason}: {==}

def bounded_raw(+limit: Nat, +raw: String) -> {State.raw_within_limit(limit, raw) == Nat.is_le(String.length(raw), limit) : Bool}:
  match limit raw:
    case _ SNil{}: {==}
    case 0n SCon{char, rest}: {==}
    case 1n+left SCon{char, rest}: bounded_raw(left, rest)

def split_local_head(+key: String, +id: String, +rest: +List<T.Local>,
  tails: Pair(Contract.other_locals(rest, id), Contract.other_locals(rest, id)), head: {String.eq(key, id) == False{} : Bool}) ->
  Pair(Pair({String.eq(key, id) == False{} : Bool}, Contract.other_locals(rest, id)), Pair({String.eq(key, id) == False{} : Bool}, Contract.other_locals(rest, id))):
  (left, right) = tails
  Std.transport(Bool, False{},
    (same => Pair(Pair({same == False{} : Bool}, Contract.other_locals(rest, id)), Pair({same == False{} : Bool}, Contract.other_locals(rest, id)))),
    (({==}, left), ({==}, right)), String.eq(key, id), head)

def split_local_facts(+before: +List<T.Local>, +id: String, facts: Contract.other_locals(before, id)) ->
  Pair(Contract.other_locals(before, id), Contract.other_locals(before, id)):
  match before:
    case Nil{}: (Unit{}, Unit{})
    case Con{T.Local{+key, schema, value, raw, validation}, +rest}:
      (head, tail) = facts
      split_local_head(key, id, rest, split_local_facts(rest, id, tail), head)

def field_write_result_evidence(+block: T.Block, +before: +List<T.Local>, +after: +List<T.Local>, +id: String, +schema: T.StateSchema, +value: J.Json, +old_raw: String, +validation: Maybe<&2, String>, +raw: String,
  +root: {Contract.block_locals(block) == List.append(&2, T.Local, before, T.Local{id, schema, value, old_raw, validation} <> after) : +List<T.Local>},
  prior: Pair(Contract.other_locals(before, id), Contract.other_locals(before, id))) ->
  {State.field_bound(block, id, raw) == State.BlockDecision{Contract.field_write(block, before, after, id, schema, value, raw), Nil{}, True{}, True{}} : State.BlockDecision}:
  match block prior:
    case T.Block{+owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restored} Tuple{lookup_before, write_before}:
      Equal.trans(State.BlockDecision, State.field_bound(block, id, raw), State.edit_local(block, Some{T.Local{id, schema, value, old_raw, validation}}, raw), State.BlockDecision{Contract.field_write(block, before, after, id, schema, value, raw), Nil{}, True{}, True{}},
        Equal.cong(Maybe<&2, T.Local>, State.BlockDecision, (found => State.edit_local(block, found, raw)), Registry.find_local(locals, id), Some{T.Local{id, schema, value, old_raw, validation}},
          Equal.trans(Maybe<&2, T.Local>, Registry.find_local(locals, id), Registry.find_local(List.append(&2, T.Local, before, T.Local{id, schema, value, old_raw, validation} <> after), id), Some{T.Local{id, schema, value, old_raw, validation}}, Equal.cong(+List<T.Local>, Maybe<&2, T.Local>, (values => Registry.find_local(values, id)), locals, List.append(&2, T.Local, before, T.Local{id, schema, value, old_raw, validation} <> after), root), first_local_lookup(before, after, id, schema, value, old_raw, validation, lookup_before))),
        Equal.cong(+List<T.Local>, State.BlockDecision,
          (values => State.BlockDecision{T.Block{owner, source, syntax, ending, closed, external, values, sources, views, mounts, feedback, revision, next, True{}, restored}, Nil{}, True{}, True{}}),
          State.replace_local(locals, id, State.local_edit(Schema.parse_raw(schema, raw), id, schema, value, raw)), List.append(&2, T.Local, before, Contract.parsed_local(id, schema, value, raw, Schema.parse_raw(schema, raw)) <> after),
          Equal.trans(+List<T.Local>, State.replace_local(locals, id, State.local_edit(Schema.parse_raw(schema, raw), id, schema, value, raw)), State.replace_local(List.append(&2, T.Local, before, T.Local{id, schema, value, old_raw, validation} <> after), id, Contract.parsed_local(id, schema, value, raw, Schema.parse_raw(schema, raw))), List.append(&2, T.Local, before, Contract.parsed_local(id, schema, value, raw, Schema.parse_raw(schema, raw)) <> after),
            Equal.trans(+List<T.Local>, State.replace_local(locals, id, State.local_edit(Schema.parse_raw(schema, raw), id, schema, value, raw)), State.replace_local(locals, id, Contract.parsed_local(id, schema, value, raw, Schema.parse_raw(schema, raw))), State.replace_local(List.append(&2, T.Local, before, T.Local{id, schema, value, old_raw, validation} <> after), id, Contract.parsed_local(id, schema, value, raw, Schema.parse_raw(schema, raw))),
              Equal.cong(T.Local, +List<T.Local>, (local => State.replace_local(locals, id, local)), State.local_edit(Schema.parse_raw(schema, raw), id, schema, value, raw), Contract.parsed_local(id, schema, value, raw, Schema.parse_raw(schema, raw)), parsed_local_result(Schema.parse_raw(schema, raw), id, schema, value, raw)),
              Equal.cong(+List<T.Local>, +List<T.Local>, (values => State.replace_local(values, id, Contract.parsed_local(id, schema, value, raw, Schema.parse_raw(schema, raw)))), locals, List.append(&2, T.Local, before, T.Local{id, schema, value, old_raw, validation} <> after), root)),
            replace_first_local(before, after, id, schema, value, old_raw, validation, Contract.parsed_local(id, schema, value, raw, Schema.parse_raw(schema, raw)), write_before))))

def field_write_result(+block: T.Block, +before: +List<T.Local>, +after: +List<T.Local>, +id: String, +schema: T.StateSchema, +value: J.Json, +old_raw: String, +validation: Maybe<&2, String>, +raw: String,
  root: {Contract.block_locals(block) == List.append(&2, T.Local, before, T.Local{id, schema, value, old_raw, validation} <> after) : +List<T.Local>}, earlier: Contract.other_locals(before, id)) ->
  {State.field_bound(block, id, raw) == State.BlockDecision{Contract.field_write(block, before, after, id, schema, value, raw), Nil{}, True{}, True{}} : State.BlockDecision}:
  field_write_result_evidence(block, before, after, id, schema, value, old_raw, validation, raw, root, split_local_facts(before, id, earlier))

def enabled_field_input(+target: T.ExpandedNode, +id: String, +raw: String, +block: T.Block,
  bound: Contract.enabled_field(target, id), within: {Nat.is_le(String.length(raw), 16384n) == True{} : Bool}) ->
  {State.field_node(Some{target}, raw, block) == State.field_bound(block, id, raw) : State.BlockDecision}:
  match target:
    case T.ExpandedNode{+identity, +occurrence, +tag, attrs, T.FieldBinding{+root, schema, old_raw, canonical, validation, True{}}, children}:
      Equal.trans(State.BlockDecision, State.field_node(Some{target}, raw, block), State.field_bound(block, root, raw), State.field_bound(block, id, raw),
        Equal.cong(Bool, State.BlockDecision, (allowed => State.field_input_admitted(block, root, raw, T.EventIdentity{identity, occurrence}, String.eq(tag, "slider"), allowed)), State.raw_within_limit(16384n, raw), True{},
          Equal.trans(Bool, State.raw_within_limit(16384n, raw), Nat.is_le(String.length(raw), 16384n), True{}, bounded_raw(16384n, raw), within)),
        Equal.cong(String, State.BlockDecision, (key => State.field_bound(block, key, raw)), root, id, bound))
    case T.ExpandedNode{identity, occurrence, tag, attrs, T.FieldBinding{root, schema, old_raw, canonical, validation, False{}}, children}:
      Logic.impossible({State.field_node(Some{target}, raw, block) == State.field_bound(block, id, raw) : State.BlockDecision}, bound)
    case T.ExpandedNode{identity, occurrence, tag, attrs, T.NoBinding{}, children}:
      Logic.impossible({State.field_node(Some{target}, raw, block) == State.field_bound(block, id, raw) : State.BlockDecision}, bound)
    case T.ExpandedNode{identity, occurrence, tag, attrs, T.ActionBinding{kind, enabled, pending}, children}:
      Logic.impossible({State.field_node(Some{target}, raw, block) == State.field_bound(block, id, raw) : State.BlockDecision}, bound)

def same_owned(+block: T.Block, +owner: T.Owner, owned: {State.block_owner(block) == owner : T.Owner}) -> {Syntax.same_owner(State.block_owner(block), owner) == True{} : Bool}:
  Equal.trans(Bool, Syntax.same_owner(State.block_owner(block), owner), Syntax.same_owner(owner, owner), True{}, Equal.cong(T.Owner, Bool, (key => Syntax.same_owner(key, owner)), State.block_owner(block), owner, owned), same_owner(owner))

def field_event_owner(+event: T.EventIdentity, +raw: String, +owner: T.Owner, belonging: Contract.event_owner(event, owner)) ->
  {State.input_owner(T.FieldEdited{event, raw}) == owner : T.Owner}:
  match event:
    case T.EventIdentity{T.Identity{key, path}, occurrence}: belonging

def field_write_owner(+block: T.Block, +before: +List<T.Local>, +after: +List<T.Local>, +id: String, +schema: T.StateSchema, +value: J.Json, +raw: String) ->
  {State.block_owner(Contract.field_write(block, before, after, id, schema, value, raw)) == State.block_owner(block) : T.Owner}:
  match block:
    case T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restored}: {==}

def bump_revised(+block: T.Block) -> {State.bump(block) == Contract.revised(block) : T.Block}:
  match block:
    case T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restored}: {==}

def revised_owner(+block: T.Block) -> {State.block_owner(Contract.revised(block)) == State.block_owner(block) : T.Owner}:
  match block:
    case T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restored}: {==}

def reconciled_record_owner(+block: T.Block, -prepared: Registry.Prepared, -mounts: +List<T.Mount>, -next: Nat) ->
  {State.block_owner(Contract.reconciled_block(block, prepared, mounts, next)) == State.block_owner(block) : T.Owner}:
  match block:
    case T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, old_mounts, feedback, revision, old_next, edited, restored}: {==}

def reconciliation_owner(+before: T.Block, +after: T.Block, evidence: Contract.Reconciled<before, after>) ->
  {State.block_owner(after) == State.block_owner(before) : T.Owner}:
  match evidence:
    case Contract.Reconciled{prepared, mounts, following, declarations, generations, result}:
      Equal.trans(T.Owner, State.block_owner(after), State.block_owner(Contract.reconciled_block(before, prepared, mounts, following)), State.block_owner(before), Equal.cong(T.Block, T.Owner, (value => State.block_owner(value)), after, Contract.reconciled_block(before, prepared, mounts, following), result), reconciled_record_owner(before, prepared, mounts, following))

def pipeline_decision(pipeline: T.Block & +List<T.Effect>, +state: T.State, +effects: +List<T.Effect>) -> T.Decision:
  match pipeline state:
    case (+block, +storage) T.State{blocks}:
      T.Decision{T.State{State.save_block(blocks, block)}, List.append(&2, T.Effect, effects, storage)}

def pipeline_observation(pipeline: T.Block & +List<T.Effect>, +blocks: +List<T.Block>, +effects: +List<T.Effect>) ->
  {pipeline_decision(pipeline, T.State{blocks}, effects) ==
    T.Decision{T.State{State.save_block(blocks, Snapshot.pipeline_block(pipeline))}, List.append(&2, T.Effect, effects, Snapshot.pipeline_effects(pipeline))} : T.Decision}:
  match pipeline:
    case Tuple{block, storage}: {==}

def applied_saved(saved: T.Block & +List<T.Effect>, +state: T.State, +effects: +List<T.Effect>, +loaded: +List<T.Effect>) ->
  {State.apply_snapshot(saved, state, List.append(&2, T.Effect, effects, loaded)) == pipeline_decision(Snapshot.append_storage(loaded, saved), state, effects) : T.Decision}:
  match saved state:
    case (+block, +stored) T.State{+blocks}:
      Equal.cong(+List<T.Effect>, T.Decision, (all => T.Decision{T.State{State.save_block(blocks, block)}, all}), List.append(&2, T.Effect, List.append(&2, T.Effect, effects, loaded), stored), List.append(&2, T.Effect, effects, List.append(&2, T.Effect, loaded, stored)), Equal.sym(+List<T.Effect>, List.append(&2, T.Effect, effects, List.append(&2, T.Effect, loaded, stored)), List.append(&2, T.Effect, List.append(&2, T.Effect, effects, loaded), stored), Std.app_assoc(T.Effect, effects, loaded, stored)))

def applied_loaded(loaded: T.Block & +List<T.Effect>, +state: T.State, +effects: +List<T.Effect>, +persist: Bool) ->
  {State.apply_loaded(loaded, state, effects, persist) == pipeline_decision(Snapshot.actual_tail(persist, loaded), state, effects) : T.Decision}:
  match loaded:
    case (+block, +load): applied_saved(State.save_snapshot(block, persist), state, effects, load)

def applied_pipeline(+candidate: T.Block, +state: T.State, +effects: +List<T.Effect>, +persist: Bool) ->
  {State.apply(State.BlockDecision{candidate, effects, True{}, persist}, state) == pipeline_decision(Snapshot.actual_pipeline(State.normalize(Contract.revised(candidate)), persist), state, effects) : T.Decision}:
  Equal.trans(T.Decision, State.apply(State.BlockDecision{candidate, effects, True{}, persist}, state), pipeline_decision(Snapshot.actual_pipeline(State.normalize(State.bump(candidate)), persist), state, effects), pipeline_decision(Snapshot.actual_pipeline(State.normalize(Contract.revised(candidate)), persist), state, effects),
    applied_loaded(State.load_snapshot(State.normalize(State.bump(candidate))), state, effects, persist),
    Equal.cong(T.Block, T.Decision, (revised => pipeline_decision(Snapshot.actual_pipeline(State.normalize(revised), persist), state, effects)), State.bump(candidate), Contract.revised(candidate), bump_revised(candidate)))

def committed_application(+prefix: +List<T.Block>, +original: T.Block, +suffix: +List<T.Block>, +candidate: T.Block, +effects: +List<T.Effect>, +persist: Bool,
  preceding: Contract.other_owners(prefix, State.block_owner(original)), candidate_owner: {State.block_owner(candidate) == State.block_owner(original) : T.Owner}) ->
  Contract.Committed<prefix, original, suffix, candidate, effects, persist, State.apply(State.BlockDecision{candidate, effects, True{}, persist}, T.State{List.append(&2, T.Block, prefix, original <> suffix)})>:
  +mounted = State.normalize(Contract.revised(candidate))
  Contract.Committed{mounted, Snapshot.pipeline_block(Snapshot.actual_pipeline(mounted, persist)), Snapshot.pipeline_effects(Snapshot.actual_pipeline(mounted, persist)), reconciled(Contract.revised(candidate)), Snapshot.snapshot_outcome(mounted, persist),
    Equal.trans(T.Decision, State.apply(State.BlockDecision{candidate, effects, True{}, persist}, T.State{List.append(&2, T.Block, prefix, original <> suffix)}), pipeline_decision(Snapshot.actual_pipeline(mounted, persist), T.State{List.append(&2, T.Block, prefix, original <> suffix)}, effects), T.Decision{T.State{List.append(&2, T.Block, prefix, Snapshot.pipeline_block(Snapshot.actual_pipeline(mounted, persist)) <> suffix)}, List.append(&2, T.Effect, effects, Snapshot.pipeline_effects(Snapshot.actual_pipeline(mounted, persist)))},
      applied_pipeline(candidate, T.State{List.append(&2, T.Block, prefix, original <> suffix)}, effects, persist),
      Equal.trans(T.Decision, pipeline_decision(Snapshot.actual_pipeline(mounted, persist), T.State{List.append(&2, T.Block, prefix, original <> suffix)}, effects),
        T.Decision{T.State{State.save_block(List.append(&2, T.Block, prefix, original <> suffix), Snapshot.pipeline_block(Snapshot.actual_pipeline(mounted, persist)))}, List.append(&2, T.Effect, effects, Snapshot.pipeline_effects(Snapshot.actual_pipeline(mounted, persist)))},
        T.Decision{T.State{List.append(&2, T.Block, prefix, Snapshot.pipeline_block(Snapshot.actual_pipeline(mounted, persist)) <> suffix)}, List.append(&2, T.Effect, effects, Snapshot.pipeline_effects(Snapshot.actual_pipeline(mounted, persist)))},
        pipeline_observation(Snapshot.actual_pipeline(mounted, persist), List.append(&2, T.Block, prefix, original <> suffix), effects),
        Equal.cong(+List<T.Block>, T.Decision, (blocks => T.Decision{T.State{blocks}, List.append(&2, T.Effect, effects, Snapshot.pipeline_effects(Snapshot.actual_pipeline(mounted, persist)))}), State.save_block(List.append(&2, T.Block, prefix, original <> suffix), Snapshot.pipeline_block(Snapshot.actual_pipeline(mounted, persist))), List.append(&2, T.Block, prefix, Snapshot.pipeline_block(Snapshot.actual_pipeline(mounted, persist)) <> suffix),
        save_existing_owner(prefix, original, suffix, Snapshot.pipeline_block(Snapshot.actual_pipeline(mounted, persist)), State.block_owner(original), {==},
          Equal.trans(T.Owner, State.block_owner(Snapshot.pipeline_block(Snapshot.actual_pipeline(mounted, persist))), State.block_owner(mounted), State.block_owner(original), Snapshot.pipeline_owner(mounted, persist),
            Equal.trans(T.Owner, State.block_owner(mounted), State.block_owner(Contract.revised(candidate)), State.block_owner(original), reconciliation_owner(Contract.revised(candidate), mounted, reconciled(Contract.revised(candidate))),
              Equal.trans(T.Owner, State.block_owner(Contract.revised(candidate)), State.block_owner(candidate), State.block_owner(original), revised_owner(candidate), candidate_owner))), preceding))))}

def visible_field_write_evidence(+prefix: +List<T.Block>, +block: T.Block, +suffix: +List<T.Block>, +owner: T.Owner, +event: T.EventIdentity, +raw: String, +id: String, +schema: T.StateSchema, +previous: J.Json, +previous_raw: String, +validation: Maybe<&2, String>, +before: +List<T.Local>, +after: +List<T.Local>, +target: T.ExpandedNode, +nodes: +List<T.ExpandedNode>, +diagnostics: +List<T.Diagnostic>, +complete: Bool, +failed: Bool, +revision: Nat, contexts: Pair(Contract.other_owners(prefix, owner), Pair(Contract.other_owners(prefix, owner), Contract.other_owners(prefix, owner))), +owned: {State.block_owner(block) == owner : T.Owner}, belonging: Contract.event_owner(event, owner), exposed: {Model.observe(owner, T.State{List.append(&2, T.Block, prefix, block <> suffix)}) == T.Scene{owner, nodes, diagnostics, complete, failed, revision} : T.Scene}, selected: Contract.visible_selection(4096n, nodes, event, target), bound: Contract.enabled_field(target, id), root: {Contract.block_locals(block) == List.append(&2, T.Local, before, T.Local{id, schema, previous, previous_raw, validation} <> after) : +List<T.Local>}, earlier: Contract.other_locals(before, id), within_limit: {Nat.is_le(String.length(raw), 16384n) == True{} : Bool}) ->
  Contract.Committed<prefix, block, suffix, Contract.field_write(block, before, after, id, schema, previous, raw), Nil{}, True{}, Model.step(T.FieldEdited{event, raw}, T.State{List.append(&2, T.Block, prefix, block <> suffix)})>:
  (lookup_prefix, (scene_prefix, save_prefix)) = contexts
  +state: T.State = T.State{List.append(&2, T.Block, prefix, block <> suffix)}
  +candidate = Contract.field_write(block, before, after, id, schema, previous, raw)
  Std.transport(T.Decision, State.apply(State.BlockDecision{candidate, Nil{}, True{}, True{}}, state),
    (result => Contract.Committed<prefix, block, suffix, candidate, Nil{}, True{}, result>),
    committed_application(prefix, block, suffix, candidate, Nil{}, True{}, Std.transport(T.Owner, owner, (key => Contract.other_owners(prefix, key)), save_prefix, State.block_owner(block), owned), field_write_owner(block, before, after, id, schema, previous, raw)), Model.step(T.FieldEdited{event, raw}, state),
    Equal.trans(T.Decision, Model.step(T.FieldEdited{event, raw}, state), State.apply(State.reduce(block, T.FieldEdited{event, raw}), state), State.apply(State.BlockDecision{candidate, Nil{}, True{}, True{}}, state),
      Equal.cong(Maybe<&2, T.Block>, T.Decision, (found => State.dispatch_found(found, T.FieldEdited{event, raw}, state)), State.find_block(List.append(&2, T.Block, prefix, block <> suffix), State.input_owner(T.FieldEdited{event, raw})), Some{block},
        Equal.trans(Maybe<&2, T.Block>, State.find_block(List.append(&2, T.Block, prefix, block <> suffix), State.input_owner(T.FieldEdited{event, raw})), State.find_block(List.append(&2, T.Block, prefix, block <> suffix), owner), Some{block}, Equal.cong(T.Owner, Maybe<&2, T.Block>, (key => State.find_block(List.append(&2, T.Block, prefix, block <> suffix), key)), State.input_owner(T.FieldEdited{event, raw}), owner, field_event_owner(event, raw, owner, belonging)), first_owner_lookup(prefix, block, suffix, owner, lookup_prefix, same_owned(block, owner, owned)))),
      Equal.cong(State.BlockDecision, T.Decision, (intent => State.apply(intent, state)), State.reduce(block, T.FieldEdited{event, raw}), State.BlockDecision{candidate, Nil{}, True{}, True{}},
        Equal.trans(State.BlockDecision, State.reduce(block, T.FieldEdited{event, raw}), State.field_node(Some{target}, raw, block), State.BlockDecision{candidate, Nil{}, True{}, True{}},
          Equal.cong(Maybe<&2, T.ExpandedNode>, State.BlockDecision, (found => State.field_node(found, raw, block)), State.current_node(block, event), Some{target}, observed_selected_node(block, event, owner, nodes, diagnostics, complete, failed, revision, target, observed_owned_scene(prefix, block, suffix, owner, T.Scene{owner, nodes, diagnostics, complete, failed, revision}, scene_prefix, same_owned(block, owner, owned), exposed), selected)),
          Equal.trans(State.BlockDecision, State.field_node(Some{target}, raw, block), State.field_bound(block, id, raw), State.BlockDecision{candidate, Nil{}, True{}, True{}}, enabled_field_input(target, id, raw, block, bound, within_limit), field_write_result(block, before, after, id, schema, previous, previous_raw, validation, raw, root, earlier))))))

def Contract.visible_field_write(prefix, block, suffix, owner, event, raw, id, schema, previous, previous_raw, validation, before, after, target, nodes, diagnostics, complete, failed, revision, preceding, owned, belonging, exposed, selected, bound, root, earlier, within_limit):
  visible_field_write_evidence(prefix, block, suffix, owner, event, raw, id, schema, previous, previous_raw, validation, before, after, target, nodes, diagnostics, complete, failed, revision, split_owner_thrice(prefix, owner, split_owner_facts(prefix, owner, preceding)), owned, belonging, exposed, selected, bound, root, earlier, within_limit)

def oversized_by_root_evidence(+block: T.Block, +before: +List<T.Local>, +after: +List<T.Local>, +id: String, +schema: T.StateSchema, +value: J.Json, +raw: String, +validation: Maybe<&2, String>, +event: T.EventIdentity, +range: Bool,
  +root: {Contract.block_locals(block) == List.append(&2, T.Local, before, T.Local{id, schema, value, raw, validation} <> after) : +List<T.Local>}, prior: Pair(Contract.other_locals(before, id), Contract.other_locals(before, id))) ->
  {State.oversized_local(block, Registry.find_local(State.block_locals(block), id), event, range) == State.BlockDecision{Contract.oversized_write(block, before, after, id, schema, value, raw), [T.RestoreFieldBuffer{event, Bool.pick(String, range, Syntax.scalar_text(value), raw)}], True{}, False{}} : State.BlockDecision}:
  match block prior:
    case T.Block{+owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restored} Tuple{lookup_before, write_before}:
      Equal.trans(State.BlockDecision, State.oversized_local(block, Registry.find_local(locals, id), event, range), State.oversized_local(block, Some{T.Local{id, schema, value, raw, validation}}, event, range), State.BlockDecision{Contract.oversized_write(block, before, after, id, schema, value, raw), [T.RestoreFieldBuffer{event, Bool.pick(String, range, Syntax.scalar_text(value), raw)}], True{}, False{}},
        Equal.cong(Maybe<&2, T.Local>, State.BlockDecision, (found => State.oversized_local(block, found, event, range)), Registry.find_local(locals, id), Some{T.Local{id, schema, value, raw, validation}},
          Equal.trans(Maybe<&2, T.Local>, Registry.find_local(locals, id), Registry.find_local(List.append(&2, T.Local, before, T.Local{id, schema, value, raw, validation} <> after), id), Some{T.Local{id, schema, value, raw, validation}}, Equal.cong(+List<T.Local>, Maybe<&2, T.Local>, (values => Registry.find_local(values, id)), locals, List.append(&2, T.Local, before, T.Local{id, schema, value, raw, validation} <> after), root), first_local_lookup(before, after, id, schema, value, raw, validation, lookup_before))),
        Equal.cong(+List<T.Local>, State.BlockDecision,
          (values => State.BlockDecision{T.Block{owner, source, syntax, ending, closed, external, values, sources, views, mounts, feedback, revision, next, edited, restored}, [T.RestoreFieldBuffer{event, Bool.pick(String, range, Syntax.scalar_text(value), raw)}], True{}, False{}}),
          State.replace_local(locals, id, T.Local{id, schema, value, raw, Some{"Input exceeds the 16384 character limit; the previous value was kept"}}), List.append(&2, T.Local, before, T.Local{id, schema, value, raw, Some{"Input exceeds the 16384 character limit; the previous value was kept"}} <> after),
          Equal.trans(+List<T.Local>, State.replace_local(locals, id, T.Local{id, schema, value, raw, Some{"Input exceeds the 16384 character limit; the previous value was kept"}}), State.replace_local(List.append(&2, T.Local, before, T.Local{id, schema, value, raw, validation} <> after), id, T.Local{id, schema, value, raw, Some{"Input exceeds the 16384 character limit; the previous value was kept"}}), List.append(&2, T.Local, before, T.Local{id, schema, value, raw, Some{"Input exceeds the 16384 character limit; the previous value was kept"}} <> after),
            Equal.cong(+List<T.Local>, +List<T.Local>, (values => State.replace_local(values, id, T.Local{id, schema, value, raw, Some{"Input exceeds the 16384 character limit; the previous value was kept"}})), locals, List.append(&2, T.Local, before, T.Local{id, schema, value, raw, validation} <> after), root), replace_first_local(before, after, id, schema, value, raw, validation, T.Local{id, schema, value, raw, Some{"Input exceeds the 16384 character limit; the previous value was kept"}}, write_before))))

def oversized_by_root(+block: T.Block, +before: +List<T.Local>, +after: +List<T.Local>, +id: String, +schema: T.StateSchema, +value: J.Json, +raw: String, +validation: Maybe<&2, String>, +event: T.EventIdentity, +range: Bool,
  root: {Contract.block_locals(block) == List.append(&2, T.Local, before, T.Local{id, schema, value, raw, validation} <> after) : +List<T.Local>}, earlier: Contract.other_locals(before, id)) ->
  {State.oversized_local(block, Registry.find_local(State.block_locals(block), id), event, range) == State.BlockDecision{Contract.oversized_write(block, before, after, id, schema, value, raw), [T.RestoreFieldBuffer{event, Bool.pick(String, range, Syntax.scalar_text(value), raw)}], True{}, False{}} : State.BlockDecision}:
  oversized_by_root_evidence(block, before, after, id, schema, value, raw, validation, event, range, root, split_local_facts(before, id, earlier))

def oversized_target_result(+target: T.ExpandedNode, +incoming: String, +block: T.Block, +before: +List<T.Local>, +after: +List<T.Local>, +id: String, +schema: T.StateSchema, +value: J.Json, +raw: String, +validation: Maybe<&2, String>,
  bound: Contract.enabled_field(target, id), root: {Contract.block_locals(block) == List.append(&2, T.Local, before, T.Local{id, schema, value, raw, validation} <> after) : +List<T.Local>}, earlier: Contract.other_locals(before, id), oversized: {Nat.is_le(String.length(incoming), 16384n) == False{} : Bool}) ->
  {State.field_node(Some{target}, incoming, block) == State.BlockDecision{Contract.oversized_write(block, before, after, id, schema, value, raw), Contract.rollback_effect(target, value, raw), True{}, False{}} : State.BlockDecision}:
  match target:
    case T.ExpandedNode{+identity, +occurrence, +tag, attrs, T.FieldBinding{+key, display_schema, display_raw, display_value, display_validation, True{}}, children}:
      Equal.trans(State.BlockDecision, State.field_node(Some{target}, incoming, block), State.oversized_local(block, Registry.find_local(State.block_locals(block), id), T.EventIdentity{identity, occurrence}, String.eq(tag, "slider")), State.BlockDecision{Contract.oversized_write(block, before, after, id, schema, value, raw), Contract.rollback_effect(target, value, raw), True{}, False{}},
        Equal.trans(State.BlockDecision, State.field_node(Some{target}, incoming, block), State.field_input_admitted(block, key, incoming, T.EventIdentity{identity, occurrence}, String.eq(tag, "slider"), False{}), State.oversized_local(block, Registry.find_local(State.block_locals(block), id), T.EventIdentity{identity, occurrence}, String.eq(tag, "slider")),
          Equal.cong(Bool, State.BlockDecision, (allowed => State.field_input_admitted(block, key, incoming, T.EventIdentity{identity, occurrence}, String.eq(tag, "slider"), allowed)), State.raw_within_limit(16384n, incoming), False{}, Equal.trans(Bool, State.raw_within_limit(16384n, incoming), Nat.is_le(String.length(incoming), 16384n), False{}, bounded_raw(16384n, incoming), oversized)),
          Equal.cong(String, State.BlockDecision, (root_id => State.oversized_local(block, Registry.find_local(State.block_locals(block), root_id), T.EventIdentity{identity, occurrence}, String.eq(tag, "slider"))), key, id, bound)),
        oversized_by_root(block, before, after, id, schema, value, raw, validation, T.EventIdentity{identity, occurrence}, String.eq(tag, "slider"), root, earlier))
    case T.ExpandedNode{identity, occurrence, tag, attrs, T.FieldBinding{key, display_schema, display_raw, display_value, display_validation, False{}}, children}: Logic.impossible({State.field_node(Some{target}, incoming, block) == State.BlockDecision{Contract.oversized_write(block, before, after, id, schema, value, raw), Contract.rollback_effect(target, value, raw), True{}, False{}} : State.BlockDecision}, bound)
    case T.ExpandedNode{identity, occurrence, tag, attrs, T.NoBinding{}, children}: Logic.impossible({State.field_node(Some{target}, incoming, block) == State.BlockDecision{Contract.oversized_write(block, before, after, id, schema, value, raw), Contract.rollback_effect(target, value, raw), True{}, False{}} : State.BlockDecision}, bound)
    case T.ExpandedNode{identity, occurrence, tag, attrs, T.ActionBinding{kind, enabled, pending}, children}: Logic.impossible({State.field_node(Some{target}, incoming, block) == State.BlockDecision{Contract.oversized_write(block, before, after, id, schema, value, raw), Contract.rollback_effect(target, value, raw), True{}, False{}} : State.BlockDecision}, bound)

def oversized_write_owner(+block: T.Block, +before: +List<T.Local>, +after: +List<T.Local>, +id: String, +schema: T.StateSchema, +value: J.Json, +raw: String) ->
  {State.block_owner(Contract.oversized_write(block, before, after, id, schema, value, raw)) == State.block_owner(block) : T.Owner}:
  match block:
    case T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restored}: {==}

def visible_oversized_field_evidence(+prefix: +List<T.Block>, +block: T.Block, +suffix: +List<T.Block>, +owner: T.Owner, +event: T.EventIdentity, +incoming: String, +id: String, +schema: T.StateSchema, +canonical: J.Json, +previous_raw: String, +validation: Maybe<&2, String>, +before: +List<T.Local>, +after: +List<T.Local>, +target: T.ExpandedNode, +nodes: +List<T.ExpandedNode>, +diagnostics: +List<T.Diagnostic>, +complete: Bool, +failed: Bool, +revision: Nat, contexts: Pair(Contract.other_owners(prefix, owner), Pair(Contract.other_owners(prefix, owner), Contract.other_owners(prefix, owner))), +owned: {State.block_owner(block) == owner : T.Owner}, belonging: Contract.event_owner(event, owner), exposed: {Model.observe(owner, T.State{List.append(&2, T.Block, prefix, block <> suffix)}) == T.Scene{owner, nodes, diagnostics, complete, failed, revision} : T.Scene}, selected: Contract.visible_selection(4096n, nodes, event, target), bound: Contract.enabled_field(target, id), root: {Contract.block_locals(block) == List.append(&2, T.Local, before, T.Local{id, schema, canonical, previous_raw, validation} <> after) : +List<T.Local>}, earlier: Contract.other_locals(before, id), oversized: {Nat.is_le(String.length(incoming), 16384n) == False{} : Bool}) ->
  Contract.Committed<prefix, block, suffix, Contract.oversized_write(block, before, after, id, schema, canonical, previous_raw), Contract.rollback_effect(target, canonical, previous_raw), False{}, Model.step(T.FieldEdited{event, incoming}, T.State{List.append(&2, T.Block, prefix, block <> suffix)})>:
  (lookup_prefix, (scene_prefix, save_prefix)) = contexts
  +state: T.State = T.State{List.append(&2, T.Block, prefix, block <> suffix)}
  +candidate = Contract.oversized_write(block, before, after, id, schema, canonical, previous_raw)
  +effects = Contract.rollback_effect(target, canonical, previous_raw)
  Std.transport(T.Decision, State.apply(State.BlockDecision{candidate, effects, True{}, False{}}, state), (result => Contract.Committed<prefix, block, suffix, candidate, effects, False{}, result>),
    committed_application(prefix, block, suffix, candidate, effects, False{}, Std.transport(T.Owner, owner, (key => Contract.other_owners(prefix, key)), save_prefix, State.block_owner(block), owned), oversized_write_owner(block, before, after, id, schema, canonical, previous_raw)), Model.step(T.FieldEdited{event, incoming}, state),
    Equal.trans(T.Decision, Model.step(T.FieldEdited{event, incoming}, state), State.apply(State.reduce(block, T.FieldEdited{event, incoming}), state), State.apply(State.BlockDecision{candidate, effects, True{}, False{}}, state),
      Equal.cong(Maybe<&2, T.Block>, T.Decision, (found => State.dispatch_found(found, T.FieldEdited{event, incoming}, state)), State.find_block(List.append(&2, T.Block, prefix, block <> suffix), State.input_owner(T.FieldEdited{event, incoming})), Some{block},
        Equal.trans(Maybe<&2, T.Block>, State.find_block(List.append(&2, T.Block, prefix, block <> suffix), State.input_owner(T.FieldEdited{event, incoming})), State.find_block(List.append(&2, T.Block, prefix, block <> suffix), owner), Some{block}, Equal.cong(T.Owner, Maybe<&2, T.Block>, (key => State.find_block(List.append(&2, T.Block, prefix, block <> suffix), key)), State.input_owner(T.FieldEdited{event, incoming}), owner, field_event_owner(event, incoming, owner, belonging)), first_owner_lookup(prefix, block, suffix, owner, lookup_prefix, same_owned(block, owner, owned)))),
      Equal.cong(State.BlockDecision, T.Decision, (intent => State.apply(intent, state)), State.reduce(block, T.FieldEdited{event, incoming}), State.BlockDecision{candidate, effects, True{}, False{}},
        Equal.trans(State.BlockDecision, State.reduce(block, T.FieldEdited{event, incoming}), State.field_node(Some{target}, incoming, block), State.BlockDecision{candidate, effects, True{}, False{}},
          Equal.cong(Maybe<&2, T.ExpandedNode>, State.BlockDecision, (found => State.field_node(found, incoming, block)), State.current_node(block, event), Some{target}, observed_selected_node(block, event, owner, nodes, diagnostics, complete, failed, revision, target, observed_owned_scene(prefix, block, suffix, owner, T.Scene{owner, nodes, diagnostics, complete, failed, revision}, scene_prefix, same_owned(block, owner, owned), exposed), selected)), oversized_target_result(target, incoming, block, before, after, id, schema, canonical, previous_raw, validation, bound, root, earlier, oversized)))))

def Contract.visible_oversized_field(prefix, block, suffix, owner, event, incoming, id, schema, canonical, previous_raw, validation, before, after, target, nodes, diagnostics, complete, failed, revision, preceding, owned, belonging, exposed, selected, bound, root, earlier, oversized):
  visible_oversized_field_evidence(prefix, block, suffix, owner, event, incoming, id, schema, canonical, previous_raw, validation, before, after, target, nodes, diagnostics, complete, failed, revision, split_owner_thrice(prefix, owner, split_owner_facts(prefix, owner, preceding)), owned, belonging, exposed, selected, bound, root, earlier, oversized)

def denied_field_node(+target: T.ExpandedNode, +raw: String, +block: T.Block, denied: Contract.field_denied(target)) ->
  {State.field_node(Some{target}, raw, block) == State.BlockDecision{block, Nil{}, False{}, False{}} : State.BlockDecision}:
  match target:
    case T.ExpandedNode{identity, occurrence, tag, attrs, T.NoBinding{}, children}: {==}
    case T.ExpandedNode{identity, occurrence, tag, attrs, T.ActionBinding{kind, enabled, pending}, children}: {==}
    case T.ExpandedNode{identity, occurrence, tag, attrs, T.FieldBinding{id, schema, old_raw, canonical, validation, False{}}, children}: {==}
    case T.ExpandedNode{identity, occurrence, tag, attrs, T.FieldBinding{id, schema, old_raw, canonical, validation, True{}}, children}: Logic.impossible({State.field_node(Some{target}, raw, block) == State.BlockDecision{block, Nil{}, False{}, False{}} : State.BlockDecision}, denied)

def visible_field_refused_evidence(+prefix: +List<T.Block>, +block: T.Block, +suffix: +List<T.Block>, +owner: T.Owner, +event: T.EventIdentity, +raw: String, +target: T.ExpandedNode, +nodes: +List<T.ExpandedNode>, +diagnostics: +List<T.Diagnostic>, +complete: Bool, +failed: Bool, +revision: Nat, contexts: Pair(Contract.other_owners(prefix, owner), Contract.other_owners(prefix, owner)), +owned: {State.block_owner(block) == owner : T.Owner}, belonging: Contract.event_owner(event, owner), exposed: {Model.observe(owner, T.State{List.append(&2, T.Block, prefix, block <> suffix)}) == T.Scene{owner, nodes, diagnostics, complete, failed, revision} : T.Scene}, selected: Contract.visible_selection(4096n, nodes, event, target), denied: Contract.field_denied(target)) ->
  {Model.step(T.FieldEdited{event, raw}, T.State{List.append(&2, T.Block, prefix, block <> suffix)}) == T.Decision{T.State{List.append(&2, T.Block, prefix, block <> suffix)}, Nil{}} : T.Decision}:
  (lookup_prefix, scene_prefix) = contexts
  +state: T.State = T.State{List.append(&2, T.Block, prefix, block <> suffix)}
  Equal.trans(T.Decision, Model.step(T.FieldEdited{event, raw}, state), State.apply(State.reduce(block, T.FieldEdited{event, raw}), state), T.Decision{state, Nil{}},
    Equal.cong(Maybe<&2, T.Block>, T.Decision, (found => State.dispatch_found(found, T.FieldEdited{event, raw}, state)), State.find_block(List.append(&2, T.Block, prefix, block <> suffix), State.input_owner(T.FieldEdited{event, raw})), Some{block},
      Equal.trans(Maybe<&2, T.Block>, State.find_block(List.append(&2, T.Block, prefix, block <> suffix), State.input_owner(T.FieldEdited{event, raw})), State.find_block(List.append(&2, T.Block, prefix, block <> suffix), owner), Some{block}, Equal.cong(T.Owner, Maybe<&2, T.Block>, (key => State.find_block(List.append(&2, T.Block, prefix, block <> suffix), key)), State.input_owner(T.FieldEdited{event, raw}), owner, field_event_owner(event, raw, owner, belonging)), first_owner_lookup(prefix, block, suffix, owner, lookup_prefix, same_owned(block, owner, owned)))),
    Equal.cong(State.BlockDecision, T.Decision, (intent => State.apply(intent, state)), State.reduce(block, T.FieldEdited{event, raw}), State.BlockDecision{block, Nil{}, False{}, False{}},
      Equal.trans(State.BlockDecision, State.reduce(block, T.FieldEdited{event, raw}), State.field_node(Some{target}, raw, block), State.BlockDecision{block, Nil{}, False{}, False{}},
        Equal.cong(Maybe<&2, T.ExpandedNode>, State.BlockDecision, (found => State.field_node(found, raw, block)), State.current_node(block, event), Some{target}, observed_selected_node(block, event, owner, nodes, diagnostics, complete, failed, revision, target, observed_owned_scene(prefix, block, suffix, owner, T.Scene{owner, nodes, diagnostics, complete, failed,revision}, scene_prefix, same_owned(block, owner, owned), exposed), selected)), denied_field_node(target, raw, block, denied))))

def Contract.visible_field_refused(prefix, block, suffix, owner, event, raw, target, nodes, diagnostics, complete, failed, revision, preceding, owned, belonging, exposed, selected, denied):
  visible_field_refused_evidence(prefix, block, suffix, owner, event, raw, target, nodes, diagnostics, complete, failed, revision, split_owner_facts(prefix, owner, preceding), owned, belonging, exposed, selected, denied)

def action_decision(+block: T.Block, +intent: Maybe<&2, Contract.ActionWrite>) -> State.BlockDecision:
  match intent:
    case None{}: State.BlockDecision{block, Nil{}, False{}, False{}}
    case Some{Contract.ActionWrite{candidate, effects, persist}}: State.BlockDecision{candidate, effects, True{}, persist}

def assignment_locals(+locals: +List<T.Local>, +id: String, +replacement: T.Local) ->
  {State.replace_local(locals, id, replacement) == Contract.assigned_locals(locals, id, replacement) : +List<T.Local>}:
  match locals:
    case Nil{}: {==}
    case Con{T.Local{+key, +schema, +value, +raw, +validation}, +rest}:
      Equal.cong(+List<T.Local>, +List<T.Local>, (tail => Bool.pick(+List<T.Local>, String.eq(key, id), replacement <> rest, T.Local{key, schema, value, raw, validation} <> tail)), State.replace_local(rest, id, replacement), Contract.assigned_locals(rest, id, replacement), assignment_locals(rest, id, replacement))

def assigned_action_checked(+accepted: Bool, +block: T.Block, +id: String, +schema: T.StateSchema, +value: J.Json) ->
  {State.set_local_checked(block, id, schema, value, accepted) == action_decision(block, Contract.assign_admitted(accepted, block, id, schema, value)) : State.BlockDecision}:
  match accepted block:
    case False{} T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restored}: {==}
    case True{} T.Block{+owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, edited, +restored}:
      Equal.cong(+List<T.Local>, State.BlockDecision, (current => State.BlockDecision{T.Block{owner, source, syntax, ending, closed, external, current, sources, views, mounts, feedback, revision, next, True{}, restored}, Nil{}, True{}, True{}}), State.replace_local(locals, id, T.Local{id, schema, value, Syntax.scalar_text(value), None{}}), Contract.assigned_locals(locals, id, T.Local{id, schema, value, Syntax.scalar_text(value), None{}}), assignment_locals(locals, id, T.Local{id, schema, value, Syntax.scalar_text(value), None{}}))

def assigned_action_result(+found: Maybe<&2, T.Local>, +value: J.Json, +block: T.Block) ->
  {State.set_local(found, value, block) == action_decision(block, Contract.assigned_action(found, block, value)) : State.BlockDecision}:
  match found:
    case None{}: {==}
    case Some{T.Local{id, +schema, previous, raw, validation}}: assigned_action_checked(Syntax.schema_accepts(schema, value), block, id, schema, value)

def initial_local_result(+local: T.Local) -> {State.reset_locals([local]) == [Contract.initial_local(local)] : +List<T.Local>}:
  match local:
    case T.Local{id, T.StateSchema{kind, initial, minimum, maximum, step, options, max_length}, value, raw, validation}: {==}

def reset_local_values(+locals: +List<T.Local>) -> {State.reset_locals(locals) == Std.map(~T.Local, ~T.Local, ~Contract.initial_local, locals) : +List<T.Local>}:
  match locals:
    case Nil{}: {==}
    case Con{T.Local{+id, +schema, +value, +raw, +validation}, +rest}:
      +local: T.Local = T.Local{id, schema, value, raw, validation}
      Equal.trans(+List<T.Local>, State.reset_locals(local <> rest), List.append(&2, T.Local, [Contract.initial_local(local)], State.reset_locals(rest)), Std.map(~T.Local, ~T.Local, ~Contract.initial_local, local <> rest),
        Equal.cong(+List<T.Local>, +List<T.Local>, (head => List.append(&2, T.Local, head, State.reset_locals(rest))), State.reset_locals([local]), [Contract.initial_local(local)], initial_local_result(local)),
        Equal.cong(+List<T.Local>, +List<T.Local>, (tail => Contract.initial_local(local) <> tail), State.reset_locals(rest), Std.map(~T.Local, ~T.Local, ~Contract.initial_local, rest), reset_local_values(rest)))

def feedback_without_path(+feedback: +List<T.Feedback>, +path: String) -> {State.feedback_remove(feedback, path) == Contract.feedback_without(feedback, path) : +List<T.Feedback>}:
  match feedback:
    case Nil{}: {==}
    case Con{T.Feedback{+key, +ticket, +pending, +message}, +rest}:
      Equal.cong(+List<T.Feedback>, +List<T.Feedback>, (tail => Bool.pick(+List<T.Feedback>, SafeText.string_equal(key, path), tail, T.Feedback{key, ticket, pending, message} <> tail)), State.feedback_remove(rest, path), Contract.feedback_without(rest, path), feedback_without_path(rest, path))

def pending_action_write(+block: T.Block, +path: String) -> {State.pending_action(block, path) == Contract.pending_write(block, path) : T.Block}:
  match block:
    case T.Block{+owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restored}:
      Equal.cong(+List<T.Feedback>, T.Block, (tail => T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, T.Feedback{path, next, True{}, ""} <> tail, revision, 1n+next, edited, restored}), State.feedback_remove(feedback, path), Contract.feedback_without(feedback, path), feedback_without_path(feedback, path))

def declared_action_result(+block: T.Block, +kind: T.ActionKind, +path: String, +attrs: J.Json) ->
  {State.action(block, kind, path, attrs) == action_decision(block, Contract.declared_action(block, kind, path, attrs)) : State.BlockDecision}:
  match block kind:
    case T.Block{+owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restored} T.SetAction{}:
      assigned_action_result(Registry.find_local(locals, J.text(J.get(attrs, "target"))), J.get(attrs, "value"), block)
    case T.Block{+owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, views, +mounts, +feedback, +revision, +next, edited, +restored} T.ResetAction{}:
      Equal.cong(+List<T.Local>, State.BlockDecision, (values => State.BlockDecision{T.Block{owner, source, syntax, ending, closed, external, values, sources, Nil{}, mounts, feedback, revision, next, True{}, restored}, Nil{}, True{}, True{}}), State.reset_locals(locals), Std.map(~T.Local, ~T.Local, ~Contract.initial_local, locals), reset_local_values(locals))
    case T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restored} T.DraftAction{}: {==}
    case T.Block{+owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restored} T.SubmitAction{}:
      Equal.cong(T.Block, State.BlockDecision, (pending => State.BlockDecision{pending, [T.SendMessage{owner, path, next, J.text(J.get(attrs, "message"))}], True{}, False{}}), State.pending_action(block, path), Contract.pending_write(block, path), pending_action_write(block, path))
    case T.Block{+owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restored} T.CopyAction{}:
      Equal.cong(T.Block, State.BlockDecision, (pending => State.BlockDecision{pending, [T.WriteClipboard{owner, path, next, J.text(J.get(attrs, "value"))}], True{}, False{}}), State.pending_action(block, path), Contract.pending_write(block, path), pending_action_write(block, path))
    case T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restored} T.OpenUrlAction{}: {==}

def pending_feedback_present(+feedback: +List<T.Feedback>, +path: String) ->
  {State.feedback_pending(feedback, path) == Contract.pending_at(feedback, path) : Bool}:
  match feedback:
    case Nil{}: {==}
    case Con{T.Feedback{+key, ticket, +pending, message}, +rest}:
      Equal.cong(Bool, Bool, (tail => (SafeText.string_equal(key, path) && pending) || tail), State.feedback_pending(rest, path), Contract.pending_at(rest, path), pending_feedback_present(rest, path))

def action_admission_result(+accepted: Bool, +block: T.Block, +kind: T.ActionKind, +path: String, +attrs: J.Json) ->
  {State.action_allowed(block, kind, path, attrs, accepted) == action_decision(block, Bool.pick(Maybe<&2, Contract.ActionWrite>, accepted, Contract.declared_action(block, kind, path, attrs), None{})) : State.BlockDecision}:
  match accepted:
    case False{}: {==}
    case True{}: declared_action_result(block, kind, path, attrs)

def current_action_result(+block: T.Block, +kind: T.ActionKind, +path: String, +attrs: J.Json) ->
  {State.action_current(block, kind, path, attrs) == action_decision(block,
    Bool.pick(Maybe<&2, Contract.ActionWrite>, Bool.not(State.feedback_pending(State.block_feedback(block), path)), Contract.declared_action(block, kind, path, attrs), None{})) : State.BlockDecision}:
  match block:
    case T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, +feedback, revision, next, edited, restored}:
      action_admission_result(Bool.not(State.feedback_pending(feedback, path)), block, kind, path, attrs)

def activation_for_identity(+block: T.Block, +identity: T.Identity, +attrs: J.Json, +kind: T.ActionKind, +enabled: Bool, +pending: Bool) -> State.BlockDecision:
  T.Identity{owner, path} = identity
  action_decision(block, Contract.activation_gate(enabled, pending, Contract.pending_at(State.block_feedback(block), path), kind, block, path, attrs))

def action_flags_result(+block: T.Block, +identity: T.Identity, +attrs: J.Json, +kind: T.ActionKind, +enabled: Bool, +pending: Bool) ->
  {State.action_flags(block, identity, attrs, kind, enabled, pending) == activation_for_identity(block, identity, attrs, kind, enabled, pending) : State.BlockDecision}:
  match identity enabled pending:
    case T.Identity{owner, path} False{} _: {==}
    case T.Identity{owner, path} True{} True{}: {==}
    case T.Identity{owner, +path} True{} False{}:
      Equal.trans(State.BlockDecision, State.action_flags(block, T.Identity{owner, path}, attrs, kind, True{}, False{}),
        action_decision(block, Bool.pick(Maybe<&2, Contract.ActionWrite>, Bool.not(State.feedback_pending(State.block_feedback(block), path)), Contract.declared_action(block, kind, path, attrs), None{})),
        activation_for_identity(block, T.Identity{owner, path}, attrs, kind, True{}, False{}),
        current_action_result(block, kind, path, attrs),
        Equal.cong(Bool, State.BlockDecision, (present => action_decision(block, Contract.activation_gate(True{}, False{}, present, kind, block, path, attrs))), State.feedback_pending(State.block_feedback(block), path), Contract.pending_at(State.block_feedback(block), path), pending_feedback_present(State.block_feedback(block), path)))

def activation_result(+block: T.Block, +target: T.ExpandedNode) ->
  {State.action_node(block, Some{target}) == action_decision(block, Contract.declared_activation(block, target)) : State.BlockDecision}:
  match target:
    case T.ExpandedNode{T.Identity{owner, path}, occurrence, tag, attrs, T.ActionBinding{kind, enabled, pending}, children}: action_flags_result(block, T.Identity{owner, path}, attrs, kind, enabled, pending)
    case T.ExpandedNode{T.Identity{owner, path}, occurrence, tag, attrs, T.NoBinding{}, children}: {==}
    case T.ExpandedNode{T.Identity{owner, path}, occurrence, tag, attrs, T.FieldBinding{id, schema, raw, canonical, validation, enabled}, children}: {==}

def IntentOwned(+owner: T.Owner, +intent: Maybe<&2, Contract.ActionWrite>) -> Type:
  match intent:
    case None{}: Unit
    case Some{Contract.ActionWrite{block, effects, persist}}: {State.block_owner(block) == owner : T.Owner}

def assignment_owner(+block: T.Block, +id: String, +schema: T.StateSchema, +value: J.Json) ->
  {State.block_owner(Contract.assignment_write(block, id, schema, value)) == State.block_owner(block) : T.Owner}:
  match block:
    case T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restored}: {==}

def assignment_admitted_owner(+accepted: Bool, +block: T.Block, +id: String, +schema: T.StateSchema, +value: J.Json) ->
  IntentOwned(State.block_owner(block), Contract.assign_admitted(accepted, block, id, schema, value)):
  match accepted:
    case False{}: Unit{}
    case True{}: assignment_owner(block, id, schema, value)

def assigned_action_owner(+found: Maybe<&2, T.Local>, +block: T.Block, +value: J.Json) ->
  IntentOwned(State.block_owner(block), Contract.assigned_action(found, block, value)):
  match found:
    case None{}: Unit{}
    case Some{T.Local{id, +schema, previous, raw, validation}}: assignment_admitted_owner(Syntax.schema_accepts(schema, value), block, id, schema, value)

def declared_action_owner(+block: T.Block, +kind: T.ActionKind, +path: String, +attrs: J.Json) ->
  IntentOwned(State.block_owner(block), Contract.declared_action(block, kind, path, attrs)):
  match block kind:
    case T.Block{owner, source, syntax, ending, closed, external, +locals, sources, views, mounts, feedback, revision, next, edited, restored} T.SetAction{}: assigned_action_owner(Registry.find_local(locals, J.text(J.get(attrs, "target"))), block, J.get(attrs, "value"))
    case T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restored} T.ResetAction{}: {==}
    case T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restored} T.DraftAction{}: {==}
    case T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restored} T.SubmitAction{}: {==}
    case T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restored} T.CopyAction{}: {==}
    case T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restored} T.OpenUrlAction{}: {==}

def activation_gate_owned(+enabled: Bool, +pending: Bool, +present: Bool, +block: T.Block, +kind: T.ActionKind, +path: String, +attrs: J.Json) ->
  IntentOwned(State.block_owner(block), Contract.activation_gate(enabled, pending, present, kind, block, path, attrs)):
  match enabled pending present:
    case False{} _ _: Unit{}
    case True{} True{} _: Unit{}
    case True{} False{} True{}: Unit{}
    case True{} False{} False{}: declared_action_owner(block, kind, path, attrs)

def activation_owned(+block: T.Block, +target: T.ExpandedNode) -> IntentOwned(State.block_owner(block), Contract.declared_activation(block, target)):
  match target:
    case T.ExpandedNode{T.Identity{owner, path}, occurrence, tag, attrs, T.ActionBinding{kind, enabled, pending}, children}: activation_gate_owned(enabled, pending, Contract.pending_at(State.block_feedback(block), path), block, kind, path, attrs)
    case T.ExpandedNode{identity, occurrence, tag, attrs, T.NoBinding{}, children}: Unit{}
    case T.ExpandedNode{identity, occurrence, tag, attrs, T.FieldBinding{id, schema, raw, canonical, validation, enabled}, children}: Unit{}

def applied_action_outcome(+prefix: +List<T.Block>, +block: T.Block, +suffix: +List<T.Block>, +intent: Maybe<&2, Contract.ActionWrite>, preceding: Contract.other_owners(prefix, State.block_owner(block)), owned: IntentOwned(State.block_owner(block), intent)) ->
  Contract.ActionOutcome(prefix, block, suffix, intent, State.apply(action_decision(block, intent), T.State{List.append(&2, T.Block, prefix, block <> suffix)})):
  match intent:
    case None{}: {==}
    case Some{Contract.ActionWrite{candidate, effects, persist}}: committed_application(prefix, block, suffix, candidate, effects, persist, preceding, owned)

def action_event_owner(+event: T.EventIdentity, +owner: T.Owner, belonging: Contract.event_owner(event, owner)) ->
  {State.input_owner(T.Activated{event}) == owner : T.Owner}:
  match event:
    case T.EventIdentity{T.Identity{key, path}, occurrence}: belonging

def visible_action_evidence(+prefix: +List<T.Block>, +block: T.Block, +suffix: +List<T.Block>, +owner: T.Owner, +event: T.EventIdentity, +target: T.ExpandedNode, +nodes: +List<T.ExpandedNode>, +diagnostics: +List<T.Diagnostic>, +complete: Bool, +failed: Bool, +revision: Nat, contexts: Pair(Contract.other_owners(prefix, owner), Pair(Contract.other_owners(prefix, owner), Contract.other_owners(prefix, owner))), +owned: {State.block_owner(block) == owner : T.Owner}, belonging: Contract.event_owner(event, owner), exposed: {Model.observe(owner, T.State{List.append(&2, T.Block, prefix, block <> suffix)}) == T.Scene{owner, nodes, diagnostics, complete, failed, revision} : T.Scene}, selected: Contract.visible_selection(4096n, nodes, event, target)) ->
  Contract.ActionOutcome(prefix, block, suffix, Contract.declared_activation(block, target), Model.step(T.Activated{event}, T.State{List.append(&2, T.Block, prefix, block <> suffix)})):
  (lookup_prefix, (scene_prefix, save_prefix)) = contexts
  +state: T.State = T.State{List.append(&2, T.Block, prefix, block <> suffix)}
  +intent = Contract.declared_activation(block, target)
  Std.transport(T.Decision, State.apply(action_decision(block, intent), state), (result => Contract.ActionOutcome(prefix, block, suffix, intent, result)),
    applied_action_outcome(prefix, block, suffix, intent, Std.transport(T.Owner, owner, (key => Contract.other_owners(prefix, key)), save_prefix, State.block_owner(block), owned), activation_owned(block, target)), Model.step(T.Activated{event}, state),
    Equal.trans(T.Decision, Model.step(T.Activated{event}, state), State.apply(State.reduce(block, T.Activated{event}), state), State.apply(action_decision(block, intent), state),
      Equal.cong(Maybe<&2, T.Block>, T.Decision, (found => State.dispatch_found(found, T.Activated{event}, state)), State.find_block(List.append(&2, T.Block, prefix, block <> suffix), State.input_owner(T.Activated{event})), Some{block},
        Equal.trans(Maybe<&2, T.Block>, State.find_block(List.append(&2, T.Block, prefix, block <> suffix), State.input_owner(T.Activated{event})), State.find_block(List.append(&2, T.Block, prefix, block <> suffix), owner), Some{block}, Equal.cong(T.Owner, Maybe<&2, T.Block>, (key => State.find_block(List.append(&2, T.Block, prefix, block <> suffix), key)), State.input_owner(T.Activated{event}), owner, action_event_owner(event, owner, belonging)), first_owner_lookup(prefix, block, suffix, owner, lookup_prefix, same_owned(block, owner, owned)))),
      Equal.cong(State.BlockDecision, T.Decision, (local => State.apply(local, state)), State.reduce(block, T.Activated{event}), action_decision(block, intent),
        Equal.trans(State.BlockDecision, State.reduce(block, T.Activated{event}), State.action_node(block, Some{target}), action_decision(block, intent),
          Equal.cong(Maybe<&2, T.ExpandedNode>, State.BlockDecision, (found => State.action_node(block, found)), State.current_node(block, event), Some{target}, observed_selected_node(block, event, owner, nodes, diagnostics, complete, failed, revision, target, observed_owned_scene(prefix, block, suffix, owner, T.Scene{owner, nodes, diagnostics, complete, failed, revision}, scene_prefix, same_owned(block, owner, owned), exposed), selected)), activation_result(block, target)))))

def Contract.visible_action(prefix, block, suffix, owner, event, target, nodes, diagnostics, complete, failed, revision, preceding, owned, belonging, exposed, selected):
  visible_action_evidence(prefix, block, suffix, owner, event, target, nodes, diagnostics, complete, failed, revision, split_owner_thrice(prefix, owner, split_owner_facts(prefix, owner, preceding)), owned, belonging, exposed, selected)

def Contract.integer_step_is_required(initial, minimum, maximum, step, options, max_length, number, rejected):
  Std.transport(Bool, False{},
    (accepted => {accepted && Syntax.valid_number(D.parse(number)) && D.integral(number) && Syntax.number_bound(J.Number{number}, minimum, ">=") && Syntax.number_bound(J.Number{number}, maximum, "<=") == False{} : Bool}),
    {==}, Syntax.number_step(number, minimum, step), rejected)

def Contract.impossible_decimal_spelling_is_rejected(text, rejected):
  Std.transport(Bool, False{},
    (accepted => {D.read_admitted(text, accepted) == Fail{"invalid fixed decimal: spelling exceeds 18 characters"} : Result<&2, &2, String, D.Decimal>}),
    {==}, D.spelling_within_limit(18n, text), rejected)

def Contract.number_step_is_required(initial, minimum, maximum, step, options, max_length, number, rejected):
  Std.transport(Bool, False{},
    (accepted => {accepted && Syntax.valid_number(D.parse(number)) && Syntax.number_bound(J.Number{number}, minimum, ">=") && Syntax.number_bound(J.Number{number}, maximum, "<=") == False{} : Bool}),
    {==}, Syntax.number_step(number, minimum, step), rejected)

def Contract.rejected_initial_is_not_built(kind, initial, minimum, maximum, step, options, max_length, rejected):
  Std.transport(Bool, False{},
    (accepted => {Schema.admit(Contract.declared_schema(kind, initial, minimum, maximum, step, options, max_length), accepted && Schema.valid_options(kind, initial, minimum, maximum, step, options, max_length)) == Fail{"Invalid state type, default, range, step or options"} : Result<&2, &2, String, T.StateSchema>}),
    {==}, Syntax.schema_accepts(Contract.declared_schema(kind, initial, minimum, maximum, step, options, max_length), initial), rejected)

def Contract.rejected_raw_has_validation(kind, initial, minimum, maximum, step, options, max_length, raw, value, parsed, rejected):
  Std.transport(Result<&2, &2, String, J.Json>, Done{value},
    (result => {Schema.validated_raw(T.StateSchema{kind, initial, minimum, maximum, step, options, max_length}, result) == Fail{"The input is outside its declared type, range or step grid"} : Result<&2, &2, String, J.Json>}),
    Std.transport(Bool, False{},
      (accepted => {Schema.validated_value(value, accepted) == Fail{"The input is outside its declared type, range or step grid"} : Result<&2, &2, String, J.Json>}),
      {==}, Syntax.schema_accepts(T.StateSchema{kind, initial, minimum, maximum, step, options, max_length}, value), rejected),
    Schema.raw_value(kind, raw), parsed)

def Contract.rejected_assignment_preserves_block(block, id, schema, previous, raw, validation, value, rejected):
  match block:
    case T.Block{+owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested}:
      Std.transport(Bool, False{},
        (accepted => {State.set_local_checked(block, id, schema, value, accepted) == State.BlockDecision{block, Nil{}, False{}, False{}} : State.BlockDecision}),
        {==}, Syntax.schema_accepts(schema, value), rejected)

def rejected_restore_candidate(+id: String, +schema: T.StateSchema, +value: J.Json, +matches: Bool) ->
  {Codec.restore_admitted(id, schema, value, matches && False{}) == Fail{"The saved state does not match this definition"} : Result<&2, &2, String, T.Local>}:
  match matches:
    case True{}: {==}
    case False{}: {==}

def Contract.rejected_restored_value_is_not_loaded(id, schema, previous, raw, validation, entry, rejected):
  Std.transport(Bool, False{},
    (accepted => {Codec.restore_admitted(id, schema, J.get(entry, "value"), J.same(Syntax.schema_json(schema), J.get(entry, "schema")) && accepted) == Fail{"The saved state does not match this definition"} : Result<&2, &2, String, T.Local>}),
    rejected_restore_candidate(id, schema, J.get(entry, "value"), J.same(Syntax.schema_json(schema), J.get(entry, "schema"))),
    Syntax.schema_accepts(schema, J.get(entry, "value")), rejected)
