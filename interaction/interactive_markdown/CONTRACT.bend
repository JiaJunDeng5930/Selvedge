import Base
import ./TYPES.bend as T
import ./STATE.bend as State
import ./MODEL.bend as Model
import ./PARSER.bend as Parser
import ./SCHEMA.bend as Schema
import ./SYNTAX.bend as Syntax
import ./REGISTRY.bend as Registry
import ./EXPAND.bend as Expand
import ./CODEC.bend as Codec
import ./DECIMAL.bend as Decimal
import ./snapshot-contract.bend as Snapshot
import ../../bendlib/json.bend as J
import ../../bendlib/string-equality.bend as SafeText
import ../../bendlib/stdlib.bend as Std

law empty_initial_state:
  {Model.initial() == T.State{Nil{}} : T.State}

law opted_out_fence:
  for +kind: String
  for +info: String
  for +complete: Bool
  {Model.eligible_fence(False{}, kind, info, complete) == False{} : Bool}

law ordinary_fence:
  for +interactive: Bool
  for +kind: String
  for +info: String
  for +complete: Bool
  for ordinary: {String.eq(Parser.trim_info(info), "selvedge-ui") == False{} : Bool}
  {Model.eligible_fence(interactive, kind, info, complete) == False{} : Bool}

# These are facts about the supplied domain, not answers supplied by a reducer
# admission function. In particular an old epoch, an old mount occurrence, and
# a component absent from the current public scene cannot authorize an event.
def other_owners(+blocks: +List<T.Block>, +expected: T.Owner) -> Type:
  match blocks:
    case Nil{}: Unit
    case Con{T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restored}, rest}:
      Pair({Syntax.same_owner(owner, expected) == False{} : Bool}, other_owners(rest, expected))

def no_visible_event(+work: Nat, +nodes: +List<T.ExpandedNode>, +event: T.EventIdentity) -> Type:
  match work nodes:
    case 0n _: Unit
    case _ Nil{}: Unit
    case 1n+left Con{T.ExpandedNode{identity, occurrence, tag, attrs, binding, children}, rest}:
      Pair({Syntax.same_event(T.EventIdentity{identity, occurrence}, event) == False{} : Bool},
        no_visible_event(left, List.append(&2, T.ExpandedNode, children, rest), event))

law unknown_owner_field:
  for +blocks: +List<T.Block>
  for +owner: T.Owner
  for +path: String
  for +occurrence: Nat
  for +raw: String
  for absent: other_owners(blocks, owner)
  {Model.step(T.FieldEdited{T.EventIdentity{T.Identity{owner, path}, occurrence}, raw}, T.State{blocks}) == T.Decision{T.State{blocks}, Nil{}} : T.Decision}

law unknown_owner_action:
  for +blocks: +List<T.Block>
  for +owner: T.Owner
  for +path: String
  for +occurrence: Nat
  for absent: other_owners(blocks, owner)
  {Model.step(T.Activated{T.EventIdentity{T.Identity{owner, path}, occurrence}}, T.State{blocks}) == T.Decision{T.State{blocks}, Nil{}} : T.Decision}

law unknown_owner_completion:
  for +blocks: +List<T.Block>
  for +owner: T.Owner
  for +path: String
  for +ticket: Nat
  for +success: Bool
  for +message: String
  for absent: other_owners(blocks, owner)
  {Model.step(T.EffectCompleted{owner, path, ticket, success, message}, T.State{blocks}) == T.Decision{T.State{blocks}, Nil{}} : T.Decision}

# Ownership is insufficient: this obligation is tied to the entire current
# observation, including when/each membership and the current source revision.
law invisible_field:
  for +prefix: +List<T.Block>
  for +block: T.Block
  for +suffix: +List<T.Block>
  for +owner: T.Owner
  for +path: String
  for +occurrence: Nat
  for +raw: String
  for +nodes: +List<T.ExpandedNode>
  for +diagnostics: +List<T.Diagnostic>
  for +complete: Bool
  for +failed: Bool
  for +revision: Nat
  for preceding: other_owners(prefix, owner)
  for owned: {Syntax.same_owner(State.block_owner(block), owner) == True{} : Bool}
  for exposed: {Model.observe(owner, T.State{List.append(&2, T.Block, prefix, block <> suffix)}) == T.Scene{owner, nodes, diagnostics, complete, failed, revision} : T.Scene}
  for absent: no_visible_event(4096n, nodes, T.EventIdentity{T.Identity{owner, path}, occurrence})
  {Model.step(T.FieldEdited{T.EventIdentity{T.Identity{owner, path}, occurrence}, raw}, T.State{List.append(&2, T.Block, prefix, block <> suffix)}) == T.Decision{T.State{List.append(&2, T.Block, prefix, block <> suffix)}, Nil{}} : T.Decision}

law invisible_action:
  for +prefix: +List<T.Block>
  for +block: T.Block
  for +suffix: +List<T.Block>
  for +owner: T.Owner
  for +path: String
  for +occurrence: Nat
  for +nodes: +List<T.ExpandedNode>
  for +diagnostics: +List<T.Diagnostic>
  for +complete: Bool
  for +failed: Bool
  for +revision: Nat
  for preceding: other_owners(prefix, owner)
  for owned: {Syntax.same_owner(State.block_owner(block), owner) == True{} : Bool}
  for exposed: {Model.observe(owner, T.State{List.append(&2, T.Block, prefix, block <> suffix)}) == T.Scene{owner, nodes, diagnostics, complete, failed, revision} : T.Scene}
  for absent: no_visible_event(4096n, nodes, T.EventIdentity{T.Identity{owner, path}, occurrence})
  {Model.step(T.Activated{T.EventIdentity{T.Identity{owner, path}, occurrence}}, T.State{List.append(&2, T.Block, prefix, block <> suffix)}) == T.Decision{T.State{List.append(&2, T.Block, prefix, block <> suffix)}, Nil{}} : T.Decision}

def correlation(+entry: T.Feedback, +path: String, +ticket: Nat) -> Bool:
  T.Feedback{key, serial, pending, message} = entry
  SafeText.string_equal(key, path) && Nat.is_eq(serial, ticket) && pending

def no_correlation(+entries: +List<T.Feedback>, +path: String, +ticket: Nat) -> Type:
  match entries:
    case Nil{}: Unit
    case Con{entry, rest}: Pair({correlation(entry, path, ticket) == False{} : Bool}, no_correlation(rest, path, ticket))

# Completion changes just one correlated feedback item and the visible revision.
# In particular it neither reparses nor restores the definition, and cannot
# issue another action, edit a value, revive a mount, or move the ticket source.
def completed_block(+block: T.Block, +feedback: +List<T.Feedback>) -> T.Block:
  T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, old, revision, next, edited, restored} = block
  T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, 1n+revision, next, edited, restored}

law uncorrelated_completion:
  for +prefix: +List<T.Block>
  for +block: T.Block
  for +suffix: +List<T.Block>
  for +path: String
  for +ticket: Nat
  for +success: Bool
  for +message: String
  for preceding: other_owners(prefix, State.block_owner(block))
  for absent: no_correlation(State.block_feedback(block), path, ticket)
  {Model.step(T.EffectCompleted{State.block_owner(block), path, ticket, success, message}, T.State{List.append(&2, T.Block, prefix, block <> suffix)}) == T.Decision{T.State{List.append(&2, T.Block, prefix, block <> suffix)}, Nil{}} : T.Decision}

law correlated_completion:
  for +prefix: +List<T.Block>
  for +block: T.Block
  for +suffix: +List<T.Block>
  for +before: +List<T.Feedback>
  for +after: +List<T.Feedback>
  for +path: String
  for +ticket: Nat
  for +old_message: String
  for +success: Bool
  for +message: String
  for preceding: other_owners(prefix, State.block_owner(block))
  for earlier: no_correlation(before, path, ticket)
  for captured: {State.block_feedback(block) == List.append(&2, T.Feedback, before, T.Feedback{path, ticket, True{}, old_message} <> after) : +List<T.Feedback>}
  {Model.step(T.EffectCompleted{State.block_owner(block), path, ticket, success, message}, T.State{List.append(&2, T.Block, prefix, block <> suffix)}) ==
    T.Decision{T.State{List.append(&2, T.Block, prefix, completed_block(block, List.append(&2, T.Feedback, before, T.Feedback{path, ticket, False{}, message} <> after)) <> suffix)}, Nil{}} : T.Decision}

def decision_effects(+decision: T.Decision) -> +List<T.Effect>:
  T.Decision{state, effects} = decision
  effects

# Feedback cannot submit another command or request storage, even when its
# owner or correlation is no longer current.
law completion_emits_no_effects:
  for +owner: T.Owner
  for +path: String
  for +ticket: Nat
  for +success: Bool
  for +message: String
  for +state: T.State
  {decision_effects(Model.step(T.EffectCompleted{owner, path, ticket, success, message}, state)) == Nil{} : +List<T.Effect>}

# A publication may choose fresh occurrence numbers. The requirement is their
# lifecycle, not an exact increment for each implementation traversal step.
def occurrence_at(+mounts: +List<T.Mount>, +path: String) -> Maybe<&2, Nat>:
  match mounts:
    case Nil{}: None{}
    case Con{T.Mount{+key, occurrence}, +rest}: Bool.pick(Maybe<&2, Nat>, SafeText.string_equal(key, path), Some{occurrence}, occurrence_at(rest, path))

def path_is_mounted(+mounts: +List<T.Mount>, +path: String) -> Bool:
  match mounts:
    case Nil{}: False{}
    case Con{T.Mount{key, occurrence}, rest}: SafeText.string_equal(key, path) || path_is_mounted(rest, path)

def occurrence_choice(+previous: Maybe<&2, Nat>, +floor: Nat, +chosen: Nat, +following: Nat) -> Type:
  match previous:
    case Some{old}: Pair({chosen == old : Nat}, Exists(Nat, (gap => {following == (gap + floor : Nat) : Nat})))
    case None{}: Exists(Nat, (gap => Pair({chosen == (gap + floor : Nat) : Nat}, Exists(Nat, (after => {following == ((1n+after) + chosen : Nat) : Nat})))))

def mount_lifecycle(+paths: +List<String>, +previous: +List<T.Mount>, +floor: Nat, +mounted: +List<T.Mount>, +following: Nat) -> Type:
  match paths mounted:
    case Nil{} Nil{}: Exists(Nat, (gap => {following == (gap + floor : Nat) : Nat}))
    case Con{path, rest} Con{T.Mount{key, occurrence}, tail}:
      Pair({key == path : String}, Exists(Nat, (next => Pair(occurrence_choice(occurrence_at(previous, path), floor, occurrence, next), mount_lifecycle(rest, previous, next, tail, following)))))
    case _ _: {False{} == True{} : Bool}

def visible_paths(+work: Nat, +nodes: +List<T.ExpandedNode>, +reversed: +List<String>) -> +List<String>:
  match work nodes:
    case _ Nil{}: List.reverse(&2, String, reversed)
    case 0n _: List.reverse(&2, String, reversed)
    case 1n+left Con{T.ExpandedNode{T.Identity{owner, path}, occurrence, tag, attrs, binding, children}, rest}:
      visible_paths(left, List.append(&2, T.ExpandedNode, children, rest), path <> reversed)

def declaration_block(+block: T.Block, +prepared: Registry.Prepared) -> T.Block:
  T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restored} = block
  T.Block{owner, source, syntax, ending, closed, external, Registry.prepared_locals(prepared), sources, views, mounts, feedback, revision, next, edited, restored}

def source_is_current(entry: J.Field) -> Bool:
  J.Field{name, +value} = entry
  J.boolean(J.get(value, "fresh")) && String.eq(J.text(J.get(value, "status")), "ready")

def is_complete(+ending: T.Ending) -> Bool:
  match ending:
    case T.Complete{}: True{}
    case _: False{}

def action_authority(+block: T.Block, +prepared: Registry.Prepared) -> Bool:
  T.Block{owner, source, T.Syntax{roots, frames, tail, failed, sealed, accepted, characters, diagnostic}, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restored} = block
  sealed && external && closed && is_complete(ending) && Bool.not(failed) && Bool.not(Registry.prepared_fatal(prepared)) && List.all(~&2, ~J.Field, ~source_is_current, sources)

def declaration_nodes(+block: T.Block, +prepared: Registry.Prepared) -> +List<T.ExpandedNode>:
  T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restored} = block
  Expand.expanded_nodes(Expand.expand_bounded(owner, Registry.accepted_elements(block, prepared), Registry.prepared_env(prepared), Registry.prepared_locals(prepared), views, mounts, action_authority(block, prepared), Registry.prepared_remaining(prepared)))

def keep_feedback(+entry: T.Feedback, +mounts: +List<T.Mount>) -> Bool:
  T.Feedback{path, ticket, pending, message} = entry
  String.eq(path, "@storage") || path_is_mounted(mounts, path)

def current_feedback(+entries: +List<T.Feedback>, +mounts: +List<T.Mount>) -> +List<T.Feedback>:
  match entries:
    case Nil{}: Nil{}
    case Con{+entry, rest}:
      +remaining = current_feedback(rest, mounts)
      Bool.pick(+List<T.Feedback>, keep_feedback(entry, mounts), entry <> remaining, remaining)

# Every field other than declared values, mounted generations and obsolete
# feedback is preserved by reconciliation. The values/tree come from the shared
# DSL denotations; reducer lenses and admission helpers are not specification.
def reconciled_block(+block: T.Block, +prepared: Registry.Prepared, +mounts: +List<T.Mount>, +next: Nat) -> T.Block:
  T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, old_mounts, feedback, revision, old_next, edited, restored} = block
  T.Block{owner, source, syntax, ending, closed, external, Registry.prepared_locals(prepared), sources, views, mounts, current_feedback(feedback, mounts), revision, next, edited, restored}

def block_mounts(+block: T.Block) -> +List<T.Mount>:
  T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restored} = block
  mounts

def block_next(+block: T.Block) -> Nat:
  T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restored} = block
  next

type Reconciled<-before: T.Block, -after: T.Block> is Type:
  Reconciled{-prepared: Registry.Prepared, -mounts: +List<T.Mount>, -following: Nat,
    declarations: {Registry.prepare(before) == prepared : Registry.Prepared},
    generations: mount_lifecycle(visible_paths(4096n, declaration_nodes(declaration_block(before, prepared), prepared), Nil{}), block_mounts(before), block_next(before), mounts, following),
    result: {after == reconciled_block(before, prepared, mounts, following) : T.Block}}

def revised(+block: T.Block) -> T.Block:
  T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restored} = block
  T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, 1n+revision, next, edited, restored}

# A successful event is an atomic owned transaction: its intended local write
# and action effects, reconciliation from current declaration values, then
# bounded storage. Every unrelated block and effect order is specified here.
type Committed<-prefix: +List<T.Block>, -original: T.Block, -suffix: +List<T.Block>, -candidate: T.Block, -effects: +List<T.Effect>, -persist: Bool, -decision: T.Decision> is Type:
  Committed{-mounted: T.Block, -stored: T.Block, -storage_effects: +List<T.Effect>,
    reconciliation: Reconciled<revised(candidate), mounted>,
    persistence: Snapshot.SnapshotOutcome(mounted, persist, stored, storage_effects),
    result: {decision == T.Decision{T.State{List.append(&2, T.Block, prefix, stored <> suffix)}, List.append(&2, T.Effect, effects, storage_effects)} : T.Decision}}

def visible_selection(+work: Nat, +nodes: +List<T.ExpandedNode>, +event: T.EventIdentity, +target: T.ExpandedNode) -> Type:
  match work nodes:
    case 0n _: {False{} == True{} : Bool}
    case _ Nil{}: {False{} == True{} : Bool}
    case 1n+left Con{T.ExpandedNode{identity, occurrence, tag, attrs, binding, children}, rest}:
      Or(Pair({Syntax.same_event(T.EventIdentity{identity, occurrence}, event) == True{} : Bool}, {target == T.ExpandedNode{identity, occurrence, tag, attrs, binding, children} : T.ExpandedNode}),
        Pair({Syntax.same_event(T.EventIdentity{identity, occurrence}, event) == False{} : Bool}, visible_selection(left, List.append(&2, T.ExpandedNode, children, rest), event, target)))

def other_locals(+locals: +List<T.Local>, +id: String) -> Type:
  match locals:
    case Nil{}: Unit
    case Con{T.Local{key, schema, value, raw, validation}, rest}: Pair({String.eq(key, id) == False{} : Bool}, other_locals(rest, id))

def block_locals(+block: T.Block) -> +List<T.Local>:
  T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restored} = block
  locals

def parsed_local(+id: String, +schema: T.StateSchema, +previous: J.Json, +raw: String, +parsed: Result<&2, &2, String, J.Json>) -> T.Local:
  match parsed:
    case Done{value}: T.Local{id, schema, value, raw, None{}}
    case Fail{reason}: T.Local{id, schema, previous, raw, Some{reason}}

def field_write(+block: T.Block, +before: +List<T.Local>, +after: +List<T.Local>, +id: String, +schema: T.StateSchema, +previous: J.Json, +raw: String) -> T.Block:
  T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restored} = block
  T.Block{owner, source, syntax, ending, closed, external,
    List.append(&2, T.Local, before, parsed_local(id, schema, previous, raw, Schema.parse_raw(schema, raw)) <> after), sources, views, mounts, feedback, revision, next, True{}, restored}

def enabled_field(+node: T.ExpandedNode, +id: String) -> Type:
  match node:
    case T.ExpandedNode{identity, occurrence, tag, attrs, T.FieldBinding{root, schema, raw, canonical, validation, True{}}, children}: {root == id : String}
    case _: {False{} == True{} : Bool}

def event_owner(+event: T.EventIdentity, +expected: T.Owner) -> Type:
  match event:
    case T.EventIdentity{T.Identity{owner, path}, occurrence}: {owner == expected : T.Owner}

law visible_field_write:
  for +prefix: +List<T.Block>
  for +block: T.Block
  for +suffix: +List<T.Block>
  for +owner: T.Owner
  for +event: T.EventIdentity
  for +raw: String
  for +id: String
  for +schema: T.StateSchema
  for +previous: J.Json
  for +previous_raw: String
  for +validation: Maybe<&2, String>
  for +before: +List<T.Local>
  for +after: +List<T.Local>
  for +target: T.ExpandedNode
  for +nodes: +List<T.ExpandedNode>
  for +diagnostics: +List<T.Diagnostic>
  for +complete: Bool
  for +failed: Bool
  for +revision: Nat
  for preceding: other_owners(prefix, owner)
  for owned: {State.block_owner(block) == owner : T.Owner}
  for belonging: event_owner(event, owner)
  for exposed: {Model.observe(owner, T.State{List.append(&2, T.Block, prefix, block <> suffix)}) == T.Scene{owner, nodes, diagnostics, complete, failed, revision} : T.Scene}
  for selected: visible_selection(4096n, nodes, event, target)
  for bound: enabled_field(target, id)
  for root: {block_locals(block) == List.append(&2, T.Local, before, T.Local{id, schema, previous, previous_raw, validation} <> after) : +List<T.Local>}
  for earlier: other_locals(before, id)
  for within_limit: {Nat.is_le(String.length(raw), 16384n) == True{} : Bool}
  Committed<prefix, block, suffix, field_write(block, before, after, id, schema, previous, raw), Nil{}, True{}, Model.step(T.FieldEdited{event, raw}, T.State{List.append(&2, T.Block, prefix, block <> suffix)})>

def oversized_write(+block: T.Block, +before: +List<T.Local>, +after: +List<T.Local>, +id: String, +schema: T.StateSchema, +canonical: J.Json, +previous_raw: String) -> T.Block:
  T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restored} = block
  T.Block{owner, source, syntax, ending, closed, external,
    List.append(&2, T.Local, before, T.Local{id, schema, canonical, previous_raw, Some{"Input exceeds the 16384 character limit; the previous value was kept"}} <> after), sources, views, mounts, feedback, revision, next, edited, restored}

def rollback_effect(+target: T.ExpandedNode, +canonical: J.Json, +previous_raw: String) -> +List<T.Effect>:
  T.ExpandedNode{identity, occurrence, tag, attrs, binding, children} = target
  [T.RestoreFieldBuffer{T.EventIdentity{identity, occurrence}, Bool.pick(String, String.eq(tag, "slider"), Syntax.scalar_text(canonical), previous_raw)}]

law visible_oversized_field:
  for +prefix: +List<T.Block>
  for +block: T.Block
  for +suffix: +List<T.Block>
  for +owner: T.Owner
  for +event: T.EventIdentity
  for +incoming: String
  for +id: String
  for +schema: T.StateSchema
  for +canonical: J.Json
  for +previous_raw: String
  for +validation: Maybe<&2, String>
  for +before: +List<T.Local>
  for +after: +List<T.Local>
  for +target: T.ExpandedNode
  for +nodes: +List<T.ExpandedNode>
  for +diagnostics: +List<T.Diagnostic>
  for +complete: Bool
  for +failed: Bool
  for +revision: Nat
  for preceding: other_owners(prefix, owner)
  for owned: {State.block_owner(block) == owner : T.Owner}
  for belonging: event_owner(event, owner)
  for exposed: {Model.observe(owner, T.State{List.append(&2, T.Block, prefix, block <> suffix)}) == T.Scene{owner, nodes, diagnostics, complete, failed, revision} : T.Scene}
  for selected: visible_selection(4096n, nodes, event, target)
  for bound: enabled_field(target, id)
  for root: {block_locals(block) == List.append(&2, T.Local, before, T.Local{id, schema, canonical, previous_raw, validation} <> after) : +List<T.Local>}
  for earlier: other_locals(before, id)
  for oversized: {Nat.is_le(String.length(incoming), 16384n) == False{} : Bool}
  Committed<prefix, block, suffix, oversized_write(block, before, after, id, schema, canonical, previous_raw), rollback_effect(target, canonical, previous_raw), False{}, Model.step(T.FieldEdited{event, incoming}, T.State{List.append(&2, T.Block, prefix, block <> suffix)})>

def field_denied(+target: T.ExpandedNode) -> Type:
  match target:
    case T.ExpandedNode{identity, occurrence, tag, attrs, T.FieldBinding{id, schema, raw, canonical, validation, True{}}, children}: {False{} == True{} : Bool}
    case _: Unit

law visible_field_refused:
  for +prefix: +List<T.Block>
  for +block: T.Block
  for +suffix: +List<T.Block>
  for +owner: T.Owner
  for +event: T.EventIdentity
  for +raw: String
  for +target: T.ExpandedNode
  for +nodes: +List<T.ExpandedNode>
  for +diagnostics: +List<T.Diagnostic>
  for +complete: Bool
  for +failed: Bool
  for +revision: Nat
  for preceding: other_owners(prefix, owner)
  for owned: {State.block_owner(block) == owner : T.Owner}
  for belonging: event_owner(event, owner)
  for exposed: {Model.observe(owner, T.State{List.append(&2, T.Block, prefix, block <> suffix)}) == T.Scene{owner, nodes, diagnostics, complete, failed, revision} : T.Scene}
  for selected: visible_selection(4096n, nodes, event, target)
  for denied: field_denied(target)
  {Model.step(T.FieldEdited{event, raw}, T.State{List.append(&2, T.Block, prefix, block <> suffix)}) == T.Decision{T.State{List.append(&2, T.Block, prefix, block <> suffix)}, Nil{}} : T.Decision}

type ActionWrite is Data:
  ActionWrite{block: T.Block, effects: +List<T.Effect>, persist: Bool}

def assigned_locals(+locals: +List<T.Local>, +id: String, +value: T.Local) -> +List<T.Local>:
  match locals:
    case Nil{}: Nil{}
    case Con{T.Local{+key, schema, previous, raw, validation}, +rest}:
      Bool.pick(+List<T.Local>, String.eq(key, id), value <> rest, T.Local{key, schema, previous, raw, validation} <> assigned_locals(rest, id, value))

def initial_local(local: T.Local) -> T.Local:
  T.Local{id, T.StateSchema{+kind, +initial, +minimum, +maximum, +step, +options, +max_length}, value, raw, validation} = local
  T.Local{id, T.StateSchema{kind, initial, minimum, maximum, step, options, max_length}, initial, Syntax.scalar_text(initial), None{}}

def assignment_write(+block: T.Block, +id: String, +schema: T.StateSchema, +value: J.Json) -> T.Block:
  T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restored} = block
  T.Block{owner, source, syntax, ending, closed, external, assigned_locals(locals, id, T.Local{id, schema, value, Syntax.scalar_text(value), None{}}), sources, views, mounts, feedback, revision, next, True{}, restored}

def reset_write(+block: T.Block) -> T.Block:
  T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restored} = block
  T.Block{owner, source, syntax, ending, closed, external, Std.map(~T.Local, ~T.Local, ~initial_local, locals), sources, Nil{}, mounts, feedback, revision, next, True{}, restored}

def feedback_without(+feedback: +List<T.Feedback>, +path: String) -> +List<T.Feedback>:
  match feedback:
    case Nil{}: Nil{}
    case Con{T.Feedback{+key, ticket, pending, message}, rest}:
      +remaining = feedback_without(rest, path)
      Bool.pick(+List<T.Feedback>, SafeText.string_equal(key, path), remaining, T.Feedback{key, ticket, pending, message} <> remaining)

def pending_write(+block: T.Block, +path: String) -> T.Block:
  T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restored} = block
  T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, T.Feedback{path, next, True{}, ""} <> feedback_without(feedback, path), revision, 1n+next, edited, restored}

def assign_admitted(+accepted: Bool, +block: T.Block, +id: String, +schema: T.StateSchema, +value: J.Json) -> Maybe<&2, ActionWrite>:
  match accepted:
    case False{}: None{}
    case True{}: Some{ActionWrite{assignment_write(block, id, schema, value), Nil{}, True{}}}

def assigned_action(+local: Maybe<&2, T.Local>, +block: T.Block, +value: J.Json) -> Maybe<&2, ActionWrite>:
  match local:
    case None{}: None{}
    case Some{T.Local{id, schema, previous, raw, validation}}: assign_admitted(Syntax.schema_accepts(schema, value), block, id, schema, value)

# Action meanings are the declared local write or captured capability intent.
# Authority below is read from the current exposed binding and pending facts;
# command execution remains the session/Commands domain, not the DSL evaluator.
def declared_action(+block: T.Block, +kind: T.ActionKind, +path: String, +attrs: J.Json) -> Maybe<&2, ActionWrite>:
  T.Block{+owner, source, syntax, ending, closed, external, +locals, sources, views, mounts, feedback, revision, +next, edited, restored} = block
  match kind:
    case T.SetAction{}: assigned_action(Registry.find_local(locals, J.text(J.get(attrs, "target"))), block, J.get(attrs, "value"))
    case T.ResetAction{}: Some{ActionWrite{reset_write(block), Nil{}, True{}}}
    case T.DraftAction{}: Some{ActionWrite{block, [T.FillDraft{owner, path, J.text(J.get(attrs, "message"))}], False{}}}
    case T.SubmitAction{}: Some{ActionWrite{pending_write(block, path), [T.SendMessage{owner, path, next, J.text(J.get(attrs, "message"))}], False{}}}
    case T.CopyAction{}: Some{ActionWrite{pending_write(block, path), [T.WriteClipboard{owner, path, next, J.text(J.get(attrs, "value"))}], False{}}}
    case T.OpenUrlAction{}: Some{ActionWrite{block, [T.OpenUrl{owner, path, J.text(J.get(attrs, "url"))}], False{}}}

def pending_feedback(+entry: T.Feedback, +path: String) -> Bool:
  T.Feedback{key, ticket, pending, message} = entry
  SafeText.string_equal(key, path) && pending

def pending_at(+feedback: +List<T.Feedback>, +path: String) -> Bool:
  match feedback:
    case Nil{}: False{}
    case Con{entry, rest}: pending_feedback(entry, path) || pending_at(rest, path)

def activation_gate(+enabled: Bool, +pending: Bool, +current_pending: Bool, +kind: T.ActionKind, +block: T.Block, +path: String, +attrs: J.Json) -> Maybe<&2, ActionWrite>:
  Bool.pick(Maybe<&2, ActionWrite>, enabled && Bool.not(pending) && Bool.not(current_pending), declared_action(block, kind, path, attrs), None{})

def declared_activation(+block: T.Block, +target: T.ExpandedNode) -> Maybe<&2, ActionWrite>:
  match target:
    case T.ExpandedNode{T.Identity{owner, path}, occurrence, tag, attrs, T.ActionBinding{kind, enabled, pending}, children}:
      activation_gate(enabled, pending, pending_at(State.block_feedback(block), path), kind, block, path, attrs)
    case _: None{}

def ActionOutcome(+prefix: +List<T.Block>, +block: T.Block, +suffix: +List<T.Block>, +intent: Maybe<&2, ActionWrite>, +decision: T.Decision) -> Type:
  match intent:
    case None{}: {decision == T.Decision{T.State{List.append(&2, T.Block, prefix, block <> suffix)}, Nil{}} : T.Decision}
    case Some{ActionWrite{candidate, effects, persist}}: Committed<prefix, block, suffix, candidate, effects, persist, decision>

law visible_action:
  for +prefix: +List<T.Block>
  for +block: T.Block
  for +suffix: +List<T.Block>
  for +owner: T.Owner
  for +event: T.EventIdentity
  for +target: T.ExpandedNode
  for +nodes: +List<T.ExpandedNode>
  for +diagnostics: +List<T.Diagnostic>
  for +complete: Bool
  for +failed: Bool
  for +revision: Nat
  for preceding: other_owners(prefix, owner)
  for owned: {State.block_owner(block) == owner : T.Owner}
  for belonging: event_owner(event, owner)
  for exposed: {Model.observe(owner, T.State{List.append(&2, T.Block, prefix, block <> suffix)}) == T.Scene{owner, nodes, diagnostics, complete, failed, revision} : T.Scene}
  for selected: visible_selection(4096n, nodes, event, target)
  ActionOutcome(prefix, block, suffix, declared_activation(block, target), Model.step(T.Activated{event}, T.State{List.append(&2, T.Block, prefix, block <> suffix)}))

law integer_step_is_required:
  for +initial: J.Json
  for +minimum: Maybe<&2, J.Json>
  for +maximum: Maybe<&2, J.Json>
  for +step: J.Json
  for +options: +List<String>
  for +max_length: Nat
  for +number: String
  for rejected: {Syntax.number_step(number, minimum, step) == False{} : Bool}
  {Syntax.schema_accepts(T.StateSchema{T.IntegerState{}, initial, minimum, maximum, step, options, max_length}, J.Number{number}) == False{} : Bool}

law impossible_decimal_spelling_is_rejected:
  for +text: String
  for rejected: {Decimal.spelling_within_limit(18n, text) == False{} : Bool}
  {Decimal.read(text) == Fail{"invalid fixed decimal: spelling exceeds 18 characters"} : Result<&2, &2, String, Decimal.Decimal>}

law number_step_is_required:
  for +initial: J.Json
  for +minimum: Maybe<&2, J.Json>
  for +maximum: Maybe<&2, J.Json>
  for +step: J.Json
  for +options: +List<String>
  for +max_length: Nat
  for +number: String
  for rejected: {Syntax.number_step(number, minimum, step) == False{} : Bool}
  {Syntax.schema_accepts(T.StateSchema{T.NumberState{}, initial, minimum, maximum, step, options, max_length}, J.Number{number}) == False{} : Bool}

def declared_schema(+kind: T.StateKind, +initial: J.Json, +minimum: J.Json, +maximum: J.Json, +step: J.Json, +options: J.Json, +max_length: Nat) -> T.StateSchema:
  T.StateSchema{kind, initial, Schema.optional_number(minimum), Schema.optional_number(maximum), step, Syntax.strings(J.items(options)), max_length}

law rejected_initial_is_not_built:
  for +kind: T.StateKind
  for +initial: J.Json
  for +minimum: J.Json
  for +maximum: J.Json
  for +step: J.Json
  for +options: J.Json
  for +max_length: Nat
  for rejected: {Syntax.schema_accepts(declared_schema(kind, initial, minimum, maximum, step, options, max_length), initial) == False{} : Bool}
  {Schema.build(kind, initial, minimum, maximum, step, options, max_length) == Fail{"Invalid state type, default, range, step or options"} : Result<&2, &2, String, T.StateSchema>}

law rejected_raw_has_validation:
  for +kind: T.StateKind
  for +initial: J.Json
  for +minimum: Maybe<&2, J.Json>
  for +maximum: Maybe<&2, J.Json>
  for +step: J.Json
  for +options: +List<String>
  for +max_length: Nat
  for +raw: String
  for +value: J.Json
  for parsed: {Schema.raw_value(kind, raw) == Done{value} : Result<&2, &2, String, J.Json>}
  for rejected: {Syntax.schema_accepts(T.StateSchema{kind, initial, minimum, maximum, step, options, max_length}, value) == False{} : Bool}
  {Schema.parse_raw(T.StateSchema{kind, initial, minimum, maximum, step, options, max_length}, raw) == Fail{"The input is outside its declared type, range or step grid"} : Result<&2, &2, String, J.Json>}

law rejected_assignment_preserves_block:
  for +block: T.Block
  for +id: String
  for +schema: T.StateSchema
  for +previous: J.Json
  for +raw: String
  for +validation: Maybe<&2, String>
  for +value: J.Json
  for rejected: {Syntax.schema_accepts(schema, value) == False{} : Bool}
  {State.set_local(Some{T.Local{id, schema, previous, raw, validation}}, value, block) == State.BlockDecision{block, Nil{}, False{}, False{}} : State.BlockDecision}

law rejected_restored_value_is_not_loaded:
  for +id: String
  for +schema: T.StateSchema
  for +previous: J.Json
  for +raw: String
  for +validation: Maybe<&2, String>
  for +entry: J.Json
  for rejected: {Syntax.schema_accepts(schema, J.get(entry, "value")) == False{} : Bool}
  {Codec.restore_local(T.Local{id, schema, previous, raw, validation}, entry) == Fail{"The saved state does not match this definition"} : Result<&2, &2, String, T.Local>}
