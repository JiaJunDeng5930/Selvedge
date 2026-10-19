import Base
import ../../bendlib/string-equality.bend as SafeText
import ./TYPES.bend as T
import ./PARSER.bend as P
import ./SYNTAX.bend as S
import ./SCHEMA.bend as Schema
import ./REGISTRY.bend as R
import ./CODEC.bend as Codec
import ./VIEW_SCHEMA.bend as ViewSchema
import ./EXPAND.bend as Expand
import ./DECIMAL.bend as D
import ../../bendlib/json.bend as J

type BlockDecision is Data:
  BlockDecision{block: T.Block, effects: +List<T.Effect>, changed: Bool, persist: Bool}

type MountResult is Data:
  MountResult{mounts: +List<T.Mount>, next: Nat}

def initial() -> T.State:
  T.State{Nil{}}

def empty(+owner: T.Owner) -> T.Block:
  T.Block{owner, "", P.initial(), T.Open{}, False{}, False{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, 0n, 1n, False{}, False{}}

def block_locals(+block: T.Block) -> +List<T.Local>:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  locals

def block_owner(+block: T.Block) -> T.Owner:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  owner

def refuse(+block: T.Block) -> BlockDecision:
  BlockDecision{block, Nil{}, False{}, False{}}

def changed(+block: T.Block, +effects: +List<T.Effect>, +persist: Bool) -> BlockDecision:
  BlockDecision{block, effects, True{}, persist}

def with_locals(+block: T.Block, +value: +List<T.Local>) -> T.Block:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  T.Block{owner, source, syntax, ending, closed, external, value, sources, views, mounts, feedback, revision, next, edited, restore_requested}

def with_sources(+block: T.Block, +value: +List<J.Field>) -> T.Block:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  T.Block{owner, source, syntax, ending, closed, external, locals, value, views, mounts, feedback, revision, next, edited, restore_requested}

def with_views(+block: T.Block, +value: +List<J.Field>) -> T.Block:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  T.Block{owner, source, syntax, ending, closed, external, locals, sources, value, mounts, feedback, revision, next, edited, restore_requested}

def with_mounts(+block: T.Block, +value: +List<T.Mount>) -> T.Block:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, value, feedback, revision, next, edited, restore_requested}

def with_feedback(+block: T.Block, +value: +List<T.Feedback>) -> T.Block:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, value, revision, next, edited, restore_requested}

def with_external(+block: T.Block, +value: Bool) -> T.Block:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  T.Block{owner, source, syntax, ending, closed, value, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}

def with_edited(+block: T.Block, +value: Bool) -> T.Block:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, value, restore_requested}

def with_restore_requested(+block: T.Block, +value: Bool) -> T.Block:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, value}

def bump(+block: T.Block) -> T.Block:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, 1n+revision, next, edited, restore_requested}

def find_block(+blocks: +List<T.Block>, +owner: T.Owner) -> Maybe<&2, T.Block>:
  match blocks:
    case Nil{}: None{}
    case Con{+first, rest}: Bool.pick(Maybe<&2, T.Block>, S.same_owner(block_owner(first), owner), Some{first}, find_block(rest, owner))

def save_block(+blocks: +List<T.Block>, +block: T.Block) -> +List<T.Block>:
  match blocks:
    case Nil{}: [block]
    case Con{+first, +rest}: Bool.pick(+List<T.Block>, S.same_owner(block_owner(first), block_owner(block)), block <> rest, first <> save_block(rest, block))

def remove_block(+blocks: +List<T.Block>, +owner: T.Owner) -> +List<T.Block>:
  match blocks:
    case Nil{}: Nil{}
    case Con{+first, rest}:
      +filtered = remove_block(rest, owner)
      Bool.pick(+List<T.Block>, S.same_owner(block_owner(first), owner), filtered, first <> filtered)

def is_complete(+ending: T.Ending) -> Bool:
  match ending:
    case T.Complete{}: True{}
    case _: False{}

def is_terminal(+ending: T.Ending) -> Bool:
  match ending:
    case T.Open{}: False{}
    case _: True{}

def source_fresh(+value: J.Json) -> Bool:
  J.boolean(J.get(value, "fresh")) && String.eq(J.text(J.get(value, "status")), "ready")

def sources_fresh(+sources: +List<J.Field>) -> Bool:
  match sources:
    case Nil{}: True{}
    case Con{J.Field{name, value}, rest}: source_fresh(value) && sources_fresh(rest)

def external_allowed(+block: T.Block, +prepared: R.Prepared) -> Bool:
  T.Block{ +owner, +source, T.Syntax{ +roots, +frames, +tail, +failed, +sealed, +accepted, +characters, +diagnostic}, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  sealed && external && closed && is_complete(ending) && Bool.not(failed) && Bool.not(R.prepared_fatal(prepared)) && sources_fresh(sources)

def raw_nodes(+block: T.Block, +prepared: R.Prepared) -> +List<T.ExpandedNode>:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  Expand.expanded_nodes(Expand.expand_bounded(owner, R.accepted_elements(T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}, prepared), R.prepared_env(prepared), R.prepared_locals(prepared), views, mounts,
    external_allowed(T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}, prepared), R.prepared_remaining(prepared)))

def node_paths(+fuel: Nat, +todo: +List<T.ExpandedNode>, +acc: +List<String>) -> +List<String>:
  match fuel todo:
    case _ Nil{}: List.reverse(&2, String, acc)
    case 0n _: List.reverse(&2, String, acc)
    case 1n+f Con{T.ExpandedNode{T.Identity{owner, path}, occurrence, tag, attrs, binding, children}, rest}:
      node_paths(f, List.append(&2, T.ExpandedNode, children, rest), path <> acc)

def find_mount(+mounts: +List<T.Mount>, +path: String) -> Maybe<&2, Nat>:
  match mounts:
    case Nil{}: None{}
    case Con{T.Mount{key, occurrence}, rest}: Bool.pick(Maybe<&2, Nat>, SafeText.string_equal(key, path), Some{occurrence}, find_mount(rest, path))

def mount_number(+found: Maybe<&2, Nat>, +fallback: Nat) -> Nat:
  match found:
    case Some{occurrence}: occurrence
    case None{}: fallback

def mounts_for(+paths: +List<String>, +previous: +List<T.Mount>, +next: Nat, +acc: +List<T.Mount>) -> MountResult:
  match paths:
    case Nil{}: MountResult{List.reverse(&2, T.Mount, acc), next}
    case Con{+path, rest}:
      mounts_for(rest, previous, 1n+next, T.Mount{path, mount_number(find_mount(previous, path), next)} <> acc)

def mount_present(+found: Maybe<&2, Nat>) -> Bool:
  match found:
    case Some{occurrence}: True{}
    case None{}: False{}

def prune_feedback(+values: +List<T.Feedback>, +mounts: +List<T.Mount>) -> +List<T.Feedback>:
  match values:
    case Nil{}: Nil{}
    case Con{T.Feedback{+path, ticket, pending, message}, rest}:
      +remaining = prune_feedback(rest, mounts)
      Bool.pick(+List<T.Feedback>, String.eq(path, "@storage") || mount_present(find_mount(mounts, path)), T.Feedback{path, ticket, pending, message} <> remaining, remaining)
def normalized_mounts(+block: T.Block, +result: MountResult) -> T.Block:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  MountResult{ +current, +serial} = result
  T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, current, prune_feedback(feedback, current), revision, serial, edited, restore_requested}

def normalize_prepared(+block: T.Block, +prepared: R.Prepared) -> T.Block:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  +current = {T.Block{owner, source, syntax, ending, closed, external, R.prepared_locals(prepared), sources, views, mounts, feedback, revision, next, edited, restore_requested} : T.Block}
  normalized_mounts(current, mounts_for(node_paths(4096n, raw_nodes(current, prepared), Nil{}), mounts, next, Nil{}))

def normalize(+block: T.Block) -> T.Block:
  normalize_prepared(block, R.prepare(block))

def syntax_diagnostics(+syntax: T.Syntax) -> +List<T.Diagnostic>:
  T.Syntax{roots, frames, tail, failed, sealed, accepted, characters, diagnostic} = syntax
  Bool.pick(+List<T.Diagnostic>, String.is_empty(diagnostic), Nil{}, [T.Diagnostic{"ui", diagnostic, failed}])

def syntax_sealed(+syntax: T.Syntax) -> Bool:
  T.Syntax{roots, frames, tail, failed, sealed, accepted, characters, diagnostic} = syntax
  sealed

def syntax_failed(+syntax: T.Syntax) -> Bool:
  T.Syntax{roots, frames, tail, failed, sealed, accepted, characters, diagnostic} = syntax
  failed

def json_fields(+value: J.Json) -> +List<J.Field>:
  match value:
    case J.Object{fields}: fields
    case _: Nil{}
def feedback_binding(+binding: T.Binding, +pending: Bool) -> T.Binding:
  match binding:
    case T.ActionBinding{kind, enabled, old_pending}: T.ActionBinding{kind, enabled && Bool.not(pending), pending}
    case other: other

def feedback_node(+found: Maybe<&2, T.Feedback>, +node: T.ExpandedNode) -> T.ExpandedNode:
  match found node:
    case Some{T.Feedback{path, ticket, pending, message}} T.ExpandedNode{identity, occurrence, tag, attrs, binding, children}:
      T.ExpandedNode{identity, occurrence, tag, J.Object{S.field_set(json_fields(attrs), "@feedback", J.Text{message})}, feedback_binding(binding, pending), children}
    case None{} other: other

def feedback_find(+values: +List<T.Feedback>, +path: String) -> Maybe<&2, T.Feedback>:
  match values:
    case Nil{}: None{}
    case Con{T.Feedback{+key, ticket, pending, message}, rest}: Bool.pick(Maybe<&2, T.Feedback>, SafeText.string_equal(path, key), Some{T.Feedback{key, ticket, pending, message}}, feedback_find(rest, path))

def feedback_nodes(+fuel: Nat, +nodes: +List<T.ExpandedNode>, +feedback: +List<T.Feedback>) -> +List<T.ExpandedNode>:
  match fuel nodes:
    case 0n _: Nil{}
    case _ Nil{}: Nil{}
    case 1n+ +f Con{T.ExpandedNode{T.Identity{owner, +path}, occurrence, tag, attrs, binding, children}, rest}:
      feedback_node(feedback_find(feedback, path), T.ExpandedNode{T.Identity{owner, path}, occurrence, tag, attrs, binding, feedback_nodes(f, children, feedback)}) <> feedback_nodes(f, rest, feedback)

def feedback_diagnostics(+values: +List<T.Feedback>) -> +List<T.Diagnostic>:
  match values:
    case Nil{}: Nil{}
    case Con{T.Feedback{+path, ticket, pending, +message}, rest}:
      List.append(&2, T.Diagnostic, Bool.pick(+List<T.Diagnostic>, pending || String.is_empty(message), Nil{}, [T.Diagnostic{Bool.pick(String, String.eq(path, "@storage"), path, "@feedback/" ++ path), message, False{}}]), feedback_diagnostics(rest))

def scene_prepared(+block: T.Block, +prepared: R.Prepared) -> T.Scene:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  T.Scene{owner, feedback_nodes(4096n, raw_nodes(T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}, prepared), feedback),
    List.append(&2, T.Diagnostic, feedback_diagnostics(feedback), List.append(&2, T.Diagnostic, syntax_diagnostics(syntax), R.prepared_diagnostics(prepared))), syntax_sealed(syntax) && is_complete(ending) && closed,
    syntax_failed(syntax) || R.prepared_fatal(prepared), revision}

def scene(+block: T.Block) -> T.Scene:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  scene_prepared(T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}, R.prepare(T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}))

def find_node(+fuel: Nat, +nodes: +List<T.ExpandedNode>, +event: T.EventIdentity) -> Maybe<&2, T.ExpandedNode>:
  match fuel:
    case 0n: None{}
    case 1n+f:
      match nodes:
        case Nil{}: None{}
        case Con{T.ExpandedNode{+identity, +occurrence, tag, attrs, binding, +children}, rest}:
          Bool.pick(Maybe<&2, T.ExpandedNode>, S.same_event(T.EventIdentity{identity, occurrence}, event),
            Some{T.ExpandedNode{identity, occurrence, tag, attrs, binding, children}}, find_node(f, List.append(&2, T.ExpandedNode, children, rest), event))

def scene_nodes(+scene: T.Scene) -> +List<T.ExpandedNode>:
  T.Scene{ +owner, +nodes, +diagnostics, +complete, +failed, +revision} = scene
  nodes

def current_node(+block: T.Block, +event: T.EventIdentity) -> Maybe<&2, T.ExpandedNode>:
  find_node(4096n, scene_nodes(scene(block)), event)

def replace_local(+locals: +List<T.Local>, +id: String, +value: T.Local) -> +List<T.Local>:
  match locals:
    case Nil{}: Nil{}
    case Con{T.Local{+key, schema, current, raw, validation}, rest}:
      Bool.pick(+List<T.Local>, String.eq(key, id), value <> rest, T.Local{key, schema, current, raw, validation} <> replace_local(rest, id, value))

def local_edit(+result: Result<&2, &2, String, J.Json>, +id: String, +schema: T.StateSchema, +previous: J.Json, +raw: String) -> T.Local:
  match result:
    case Done{value}: T.Local{id, schema, value, raw, None{}}
    case Fail{reason}: T.Local{id, schema, previous, raw, Some{reason}}

def edit_local_parsed(+block: T.Block, +id: String, +schema: T.StateSchema, +previous: J.Json, +raw: String, +result: Result<&2, &2, String, J.Json>) -> BlockDecision:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  changed(with_edited(with_locals(block, replace_local(locals, id, local_edit(result, id, schema, previous, raw))), True{}), Nil{}, True{})

def edit_local(+block: T.Block, +found: Maybe<&2, T.Local>, +raw: String) -> BlockDecision:
  match found:
    case None{}: refuse(block)
    case Some{T.Local{+id, +schema, value, old, validation}}:
      edit_local_parsed(block, id, schema, value, raw, Schema.parse_raw(schema, raw))

def find_local_alias(+locals: +List<T.Local>, +id: String) -> Maybe<&2, T.Local>:
  R.find_local(locals, id)

def field_bound(+block: T.Block, +id: String, +raw: String) -> BlockDecision:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  edit_local(T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}, find_local_alias(locals, id), raw)

# DEFENSE: Native field edits can exceed 16384 scalars; preserve the previous buffer/value and issue the exact mounted-field rollback.
def raw_within_limit(+fuel: Nat, +raw: String) -> Bool:
  match fuel raw:
    case _ SNil{}: True{}
    case 0n _: False{}
    case 1n+left SCon{char, rest}: raw_within_limit(left, rest)

def oversized_local(+block: T.Block, +found: Maybe<&2, T.Local>, +event: T.EventIdentity, +range: Bool) -> BlockDecision:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  match found:
    case None{}: refuse(block)
    case Some{T.Local{+id, schema, +value, +raw, validation}}:
      changed(with_locals(block, replace_local(locals, id, T.Local{id, schema, value, raw, Some{"Input exceeds the 16384 character limit; the previous value was kept"}})), [T.RestoreFieldBuffer{event, Bool.pick(String, range, S.scalar_text(value), raw)}], False{})

def field_input_admitted(+block: T.Block, +id: String, +raw: String, +event: T.EventIdentity, +range: Bool, +allowed: Bool) -> BlockDecision:
  match allowed:
    case True{}: field_bound(block, id, raw)
    case False{}: oversized_local(block, find_local_alias(block_locals(block), id), event, range)

def field_node(+found: Maybe<&2, T.ExpandedNode>, +raw: String, +block: T.Block) -> BlockDecision:
  match found:
    case Some{T.ExpandedNode{identity, occurrence, tag, attrs, T.FieldBinding{id, schema, old_raw, canonical, validation, True{}}, children}}:
      field_input_admitted(block, id, raw, T.EventIdentity{identity, occurrence}, String.eq(tag, "slider"), raw_within_limit(16384n, raw))
    case _: refuse(block)

def feedback_pending(+feedback: +List<T.Feedback>, +path: String) -> Bool:
  match feedback:
    case Nil{}: False{}
    case Con{T.Feedback{key, ticket, pending, message}, rest}: (SafeText.string_equal(key, path) && pending) || feedback_pending(rest, path)

def feedback_remove(+feedback: +List<T.Feedback>, +path: String) -> +List<T.Feedback>:
  match feedback:
    case Nil{}: Nil{}
    case Con{T.Feedback{+key, ticket, pending, message}, rest}:
      +filtered = feedback_remove(rest, path)
      Bool.pick(+List<T.Feedback>, SafeText.string_equal(key, path), filtered, T.Feedback{key, ticket, pending, message} <> filtered)

def pending_action(+block: T.Block, +path: String) -> T.Block:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts,
    T.Feedback{path, next, True{}, ""} <> feedback_remove(feedback, path), revision, 1n+next, edited, restore_requested}

def reset_locals(+locals: +List<T.Local>) -> +List<T.Local>:
  match locals:
    case Nil{}: Nil{}
    case Con{T.Local{id, schema, value, raw, validation}, rest}: R.local_default(id, schema) <> reset_locals(rest)

def set_local_checked(+block: T.Block, +id: String, +schema: T.StateSchema, +value: J.Json, +allowed: Bool) -> BlockDecision:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  match allowed:
    case False{}: refuse(T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested})
    case True{}: changed(with_edited(with_locals(T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested},
      replace_local(locals, id, T.Local{id, schema, value, S.scalar_text(value), None{}})), True{}), Nil{}, True{})

def set_local(+found: Maybe<&2, T.Local>, +value: J.Json, +block: T.Block) -> BlockDecision:
  match found:
    case None{}: refuse(block)
    case Some{T.Local{id, schema, previous, raw, validation}}: set_local_checked(block, id, schema, value, S.schema_accepts(schema, value))

def action(+block: T.Block, +kind: T.ActionKind, +path: String, +attrs: J.Json) -> BlockDecision:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  match kind:
    case T.SetAction{}: set_local(R.find_local(locals, J.text(J.get(attrs, "target"))), J.get(attrs, "value"), T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested})
    case T.ResetAction{}: changed(with_views(with_edited(with_locals(T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}, reset_locals(locals)), True{}), Nil{}), Nil{}, True{})
    case T.DraftAction{}: changed(T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}, [T.FillDraft{owner, path, J.text(J.get(attrs, "message"))}], False{})
    case T.SubmitAction{}: changed(pending_action(T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}, path), [T.SendMessage{owner, path, next, J.text(J.get(attrs, "message"))}], False{})
    case T.CopyAction{}: changed(pending_action(T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}, path), [T.WriteClipboard{owner, path, next, J.text(J.get(attrs, "value"))}], False{})
    case T.OpenUrlAction{}: changed(T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}, [T.OpenUrl{owner, path, J.text(J.get(attrs, "url"))}], False{})

def action_allowed(+block: T.Block, +kind: T.ActionKind, +path: String, +attrs: J.Json, +allowed: Bool) -> BlockDecision:
  match allowed:
    case False{}: refuse(block)
    case True{}: action(block, kind, path, attrs)

def action_current(+block: T.Block, +kind: T.ActionKind, +path: String, +attrs: J.Json) -> BlockDecision:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  action_allowed(block, kind, path, attrs, Bool.not(feedback_pending(feedback, path)))

def action_target(+block: T.Block, +identity: T.Identity, +attrs: J.Json, +kind: T.ActionKind) -> BlockDecision:
  T.Identity{ +owner, +path} = identity
  action_current(block, kind, path, attrs)

def action_flags(+block: T.Block, +identity: T.Identity, +attrs: J.Json, +kind: T.ActionKind, +enabled: Bool, +pending: Bool) -> BlockDecision:
  match enabled:
    case False{}: refuse(block)
    case True{}:
      match pending:
        case True{}: refuse(block)
        case False{}: action_target(block, identity, attrs, kind)

def action_node(+block: T.Block, +found: Maybe<&2, T.ExpandedNode>) -> BlockDecision:
  match found:
    case Some{T.ExpandedNode{identity, occurrence, tag, attrs, T.ActionBinding{kind, enabled, pending}, children}}:
      action_flags(block, identity, attrs, kind, enabled, pending)
    case _: refuse(block)

def decimal_text(+result: Result<&2, &2, String, String>, +fallback: String) -> String:
  match result:
    case Done{value}: value
    case Fail{reason}: fallback

def bounded_decimal(+value: String, +lower: String, +upper: String) -> String:
  Bool.pick(String, S.decimal_bool(D.compare("<", value, lower)), lower,
    Bool.pick(String, S.decimal_bool(D.compare(">", value, upper)), upper, value))

def view_number(+view: J.Json, +name: String, +fallback: String) -> String:
  S.scalar_text(S.value_or(S.evaluate("text(value)", [J.Field{"value", J.get(view, name)}]), J.Text{fallback}))

def view_default(+view: J.Json, +name: String, +fallback: String) -> String:
  J.text_or(J.get(view, name), fallback)

def numeric_value(+value: J.Json, +fallback: String) -> String:
  match value:
    case J.Number{text}: text
    case _: fallback

def numeric_field(+view: J.Json, +name: String, +fallback: String) -> String:
  numeric_value(J.get(view, name), fallback)

def graph_view(+command: T.ViewCommand, +view: J.Json) -> J.Json:
  match command:
    case T.GraphZoomIn{}: J.Object{[J.Field{"fitWidth", J.Boolean{False{}}}, J.Field{"selection", J.Text{J.text(J.get(view, "selection"))}}, J.Field{"zoom", J.Number{bounded_decimal(decimal_text(D.arithmetic("+", numeric_field(view, "zoom", "100"), "25"), "100"), "25", "200")}}, J.Field{"panX", J.Number{numeric_field(view, "panX", "0")}}, J.Field{"panY", J.Number{numeric_field(view, "panY", "0")}}]}
    case T.GraphZoomOut{}: J.Object{[J.Field{"fitWidth", J.Boolean{False{}}}, J.Field{"selection", J.Text{J.text(J.get(view, "selection"))}}, J.Field{"zoom", J.Number{bounded_decimal(decimal_text(D.arithmetic("-", numeric_field(view, "zoom", "100"), "25"), "100"), "25", "200")}}, J.Field{"panX", J.Number{numeric_field(view, "panX", "0")}}, J.Field{"panY", J.Number{numeric_field(view, "panY", "0")}}]}
    case T.GraphPan{dx, dy}: J.Object{[J.Field{"fitWidth", J.Boolean{J.boolean(J.get(view, "fitWidth"))}}, J.Field{"selection", J.Text{J.text(J.get(view, "selection"))}}, J.Field{"zoom", J.Number{numeric_field(view, "zoom", "100")}}, J.Field{"panX", J.Number{bounded_decimal(decimal_text(D.arithmetic("+", numeric_field(view, "panX", "0"), dx), "0"), "0", "2000")}}, J.Field{"panY", J.Number{bounded_decimal(decimal_text(D.arithmetic("+", numeric_field(view, "panY", "0"), dy), "0"), "0", "2000")}}]}
    case _: J.Object{[J.Field{"fitWidth", J.Boolean{True{}}}, J.Field{"selection", J.Text{J.text(J.get(view, "selection"))}}, J.Field{"zoom", J.Number{"100"}}, J.Field{"panX", J.Number{"0"}}, J.Field{"panY", J.Number{"0"}}]}

def table_view(+command: T.ViewCommand, +view: J.Json) -> J.Json:
  match command:
    case T.TableSort{column}: J.Object{[J.Field{"sort", J.Text{column}}, J.Field{"direction", J.Text{Bool.pick(String, SafeText.string_equal(J.text(J.get(view, "sort")), column) && String.eq(J.text(J.get(view, "direction")), "asc"), "desc", "asc")}}, J.Field{"page", J.nat(0n)}]}
    case T.TablePage{page}: J.Object{[J.Field{"sort", J.Text{J.text(J.get(view, "sort"))}}, J.Field{"direction", J.Text{J.text_or(J.get(view, "direction"), "asc")}}, J.Field{"page", J.nat(page)}]}
    case _: view

def view_update(+block: T.Block, +path: String, +value: J.Json) -> BlockDecision:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  changed(with_edited(with_views(T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}, S.field_set(views, path, value)), True{}), Nil{}, True{})

def graph_select(+block: T.Block, +path: String, +attrs: J.Json, +identity: String, +local: Bool) -> BlockDecision:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  match local:
    case True{}: view_update(T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}, path, J.Object{S.field_set(json_fields(J.find(views, path)), "selection", J.Text{identity})})
    case False{}: set_local(R.find_local(locals, J.text(J.get(attrs, "select"))), J.Text{identity}, T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested})

def view_node_unchecked(+block: T.Block, +found: Maybe<&2, T.ExpandedNode>, +command: T.ViewCommand) -> BlockDecision:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  match found command:
    case Some{T.ExpandedNode{T.Identity{node_owner, path}, occurrence, "graph-view", attrs, binding, children}} T.GraphSelect{identity}:
      graph_select(T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}, path, attrs, identity, String.is_empty(J.text(J.get(attrs, "select"))))
    case Some{T.ExpandedNode{T.Identity{node_owner, +path}, occurrence, "graph-view", attrs, binding, children}} other:
      view_update(T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}, path, graph_view(other, J.find(views, path)))
    case Some{T.ExpandedNode{T.Identity{node_owner, +path}, occurrence, "table", attrs, binding, children}} other:
      view_update(T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}, path, table_view(other, J.find(views, path)))
    case _ _: refuse(T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested})

def same_ending(+left: T.Ending, +right: T.Ending) -> Bool:
  match left right:
    case T.Open{} T.Open{}: True{}
    case T.Complete{} T.Complete{}: True{}
    case T.Interrupted{} T.Interrupted{}: True{}
    case _ _: False{}

def settled_syntax(+syntax: T.Syntax, +close: Bool, +pending: Bool) -> T.Syntax:
  match close pending:
    case True{} False{}: P.finish(syntax)
    case _ _: syntax

def parse_effect(+owner: T.Owner, +pending: Bool) -> +List<T.Effect>:
  match pending:
    case True{}: [T.ScheduleParse{owner}]
    case False{}: Nil{}

def changed_source(+block: T.Block, +owner: T.Owner, +source: String, +closed: Bool, +ending: T.Ending, +external: Bool, +parsed: T.Syntax) -> BlockDecision:
  T.Block{ +old_owner, +previous, +syntax, +old_ending, +old_closed, +old_external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  changed(T.Block{owner, source, settled_syntax(parsed, closed || is_terminal(ending), P.pending(parsed)), ending, closed, external,
    locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}, parse_effect(owner, P.pending(parsed)), edited && is_complete(ending))

def append_definition(+suffix: String, +syntax: T.Syntax, +allowed: Bool) -> T.Syntax:
  match allowed:
    case True{}: P.append(suffix, syntax)
    case False{}: P.fail("Definition evaluation budget exceeds 100000", syntax)

def source_prefix(+block: T.Block, +owner: T.Owner, +source: String, +closed: Bool, +ending: T.Ending, +external: Bool, +prefix: Bool) -> BlockDecision:
  T.Block{ +old_owner, +previous, +syntax, +old_ending, +old_closed, +old_external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  match prefix:
    case True{}: changed_source(T.Block{old_owner, previous, syntax, old_ending, old_closed, old_external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}, owner, source, closed, ending, external, append_definition(String.drop(source, String.length(previous)), syntax, Nat.is_lt((2n * String.length(source) : Nat), 100000n)))
    case False{}: changed_source(T.Block{owner, "", P.initial(), T.Open{}, False{}, False{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, revision, 1n+next, False{}, False{}}, owner, source, closed, ending, external, append_definition(source, P.initial(), Nat.is_lt((2n * String.length(source) : Nat), 100000n)))

def source_updated(+block: T.Block, +owner: T.Owner, +source: String, +closed: Bool, +ending: T.Ending, +external: Bool) -> BlockDecision:
  T.Block{ +old_owner, +previous, +syntax, +old_ending, +old_closed, +old_external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  source_prefix(block, owner, source, closed, ending, external, String.starts_with(source, previous) && (Bool.not(is_terminal(old_ending)) || SafeText.string_equal(source, previous)))

def source_changed(+block: T.Block, +owner: T.Owner, +source: String, +closed: Bool, +ending: T.Ending, +external: Bool, +identical: Bool) -> BlockDecision:
  match identical:
    case True{}: refuse(block)
    case False{}: source_updated(block, owner, source, closed, ending, external)

def handle_source(+block: T.Block, +owner: T.Owner, +source: String, +closed: Bool, +ending: T.Ending, +external: Bool) -> BlockDecision:
  T.Block{ +old_owner, +previous, +syntax, +old_ending, +old_closed, +old_external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  source_changed(T.Block{old_owner, previous, syntax, old_ending, old_closed, old_external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}, owner, source, closed, ending, external,
    SafeText.string_equal(previous, source) && J.same(J.Boolean{old_closed}, J.Boolean{closed}) && same_ending(old_ending, ending) && J.same(J.Boolean{old_external}, J.Boolean{external}))

def sources_equal(+left: +List<J.Field>, +right: +List<J.Field>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case Con{J.Field{+name, +value}, rest} Con{J.Field{+other_name, +other}, tail}:
      String.eq(name, other_name) && J.same(J.get(value, "value"), J.get(other, "value")) && J.same(J.get(value, "status"), J.get(other, "status")) && J.same(J.get(value, "fresh"), J.get(other, "fresh")) && J.same(J.get(value, "sequence"), J.get(other, "sequence")) && sources_equal(rest, tail)
    case _ _: False{}

def settle_feedback(+feedback: +List<T.Feedback>, +path: String, +ticket: Nat, +success: Bool, +message: String) -> +List<T.Feedback>:
  match feedback:
    case Nil{}: Nil{}
    case Con{T.Feedback{+key, +serial, +pending, old}, rest}:
      Bool.pick(+List<T.Feedback>, SafeText.string_equal(key, path) && Nat.is_eq(ticket, serial) && pending,
        T.Feedback{key, serial, False{}, message} <> rest,
        T.Feedback{key, serial, pending, old} <> settle_feedback(rest, path, ticket, success, message))

def restored_values(+block: T.Block, +result: Result<&2, &2, String, Codec.RestoredValues>) -> BlockDecision:
  match result:
    case Fail{reason}: changed(block, [T.RemoveSnapshot{block_owner(block)}], False{})
    case Done{Codec.RestoredValues{locals, views}}: changed(with_views(with_locals(block, locals), views), Nil{}, False{})

def restore_view_descriptors(+block: T.Block) -> +List<J.Field>:
  ViewSchema.descriptors(R.accepted_elements(block, R.prepare(block)), scene_nodes(scene(block)))

def supplement_descriptors(+extra: +List<J.Field>, +allowed: +List<J.Field>) -> +List<J.Field>:
  match extra:
    case Nil{}: allowed
    case Con{J.Field{+path, descriptor}, rest}:
      supplement_descriptors(rest, Bool.pick(+List<J.Field>, S.field_has(allowed, path), allowed, J.Field{path, descriptor} <> allowed))

def restore_allowed(+block: T.Block, +payload: J.Json) -> +List<J.Field>:
  supplement_descriptors(ViewSchema.descriptors_for_paths(R.accepted_elements(block, R.prepare(block)), json_fields(J.get(payload, "views"))), restore_view_descriptors(block))

def restore_proposed(+block: T.Block, +payload: J.Json, +locals: +List<T.Local>) -> BlockDecision:
  restored_values(block, Codec.decode_prevalidated_views(locals, payload,
    restore_allowed(with_locals(block, locals), payload)))

def restore_decoded(+block: T.Block, +payload: J.Json, +result: Result<&2, &2, String, +List<T.Local>>) -> BlockDecision:
  match result:
    case Fail{reason}: restored_values(block, Fail{reason})
    case Done{locals}: restore_proposed(block, payload, locals)

def restore_accepted(+block: T.Block, +payload: J.Json) -> BlockDecision:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  restore_decoded(block, payload, Codec.decode_local_values(locals, payload))

# DEFENSE: A delayed storage restore can arrive after edits or for stale ownership; admit only the current untouched block.
def restore_admitted(+block: T.Block, +payload: J.Json, +allowed: Bool) -> BlockDecision:
  match allowed:
    case False{}: refuse(block)
    case True{}: restore_accepted(block, payload)

def continue_accepted(+block: T.Block) -> BlockDecision:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  changed_source(block, owner, source, closed, ending, external, P.drain(256n, True{}, syntax))

def continue_block(+block: T.Block, +pending: Bool) -> BlockDecision:
  match pending:
    case False{}: refuse(block)
    case True{}: continue_accepted(block)

def view_admitted(+block: T.Block, +found: Maybe<&2, T.ExpandedNode>, +command: T.ViewCommand, +allowed: Bool) -> BlockDecision:
  match allowed:
    case True{}: view_node_unchecked(block, found, command)
    case False{}: refuse(block)

def signed_pan(+value: String) -> Bool:
  D.integral(value) && S.decimal_bool(D.compare(">=", value, "-2000")) && S.decimal_bool(D.compare("<=", value, "2000"))

def graph_node_known(+nodes: +List<J.Json>, +identity: String) -> Bool:
  match nodes:
    case Nil{}: False{}
    case Con{first, rest}: SafeText.string_equal(J.text(J.get(first, "identity")), identity) || graph_node_known(rest, identity)

def graph_command(+command: T.ViewCommand, +attrs: J.Json) -> Bool:
  match command:
    case T.GraphZoomIn{}: True{}
    case T.GraphZoomOut{}: True{}
    case T.GraphPan{dx, dy}: signed_pan(dx) && signed_pan(dy)
    case T.GraphFit{}: True{}
    case T.GraphSelect{identity}: graph_node_known(J.items(J.get(attrs, "nodes")), identity)
    case _: False{}

def table_column_known(+columns: +List<T.ExpandedNode>, +name: String) -> Bool:
  match columns:
    case Nil{}: False{}
    case Con{T.ExpandedNode{identity, occurrence, tag, attrs, binding, children}, rest}:
      (String.eq(tag, "column") && SafeText.string_equal(J.text(J.get(attrs, "field")), name)) || table_column_known(rest, name)

def table_command(+command: T.ViewCommand, +attrs: J.Json, +children: +List<T.ExpandedNode>) -> Bool:
  match command:
    case T.TableSort{column}: J.boolean(J.get(attrs, "sortable")) && table_column_known(children, column)
    case T.TablePage{page}: Nat.is_le(page, 40n) && Nat.is_lt((page * 100n : Nat), List.length(&2, J.Json, J.items(J.get(attrs, "rows"))))
    case _: False{}

def view_node(+block: T.Block, +found: Maybe<&2, T.ExpandedNode>, +command: T.ViewCommand) -> BlockDecision:
  match found:
    case None{}: refuse(block)
    case Some{T.ExpandedNode{identity, occurrence, tag, attrs, binding, children}}:
      view_admitted(block, Some{T.ExpandedNode{identity, occurrence, tag, attrs, binding, children}}, command,
        Bool.not(J.same(J.get(attrs, "enabled"), J.Boolean{False{}})) &&
        (String.eq(tag, "graph-view") && graph_command(command, attrs) || String.eq(tag, "table") && table_command(command, attrs, children)))
def matching_feedback(+feedback: +List<T.Feedback>, +path: String, +ticket: Nat) -> Bool:
  match feedback:
    case Nil{}: False{}
    case Con{T.Feedback{key, serial, pending, message}, rest}: (SafeText.string_equal(key, path) && Nat.is_eq(serial, ticket) && pending) || matching_feedback(rest, path, ticket)

def reduce_other(+block: T.Block, +input: T.Input) -> BlockDecision:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  match input:
    case T.SourceChanged{new_owner, text, close, end, allowed}: handle_source(T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}, new_owner, text, close, end, allowed)
    case T.SourcesChanged{new_owner, values}: Bool.pick(BlockDecision, sources_equal(sources, values), refuse(T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}), changed(with_sources(T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}, values), Nil{}, False{}))
    case T.ExternalChanged{new_owner, allowed}: Bool.pick(BlockDecision, J.same(J.Boolean{external}, J.Boolean{allowed}), refuse(T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}), changed(with_external(T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}, allowed), Nil{}, False{}))
    case T.Restored{new_owner, definition, payload}: restore_admitted(T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}, payload, SafeText.string_equal(source, definition) && closed && is_complete(ending) && Bool.not(edited))
    case T.StorageFailed{new_owner, message}: changed(with_feedback(T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}, T.Feedback{"@storage", 0n, False{}, message} <> feedback_remove(feedback, "@storage")), Nil{}, False{})
    case T.ContinueParsing{new_owner}: continue_block(T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}, P.pending(syntax))
    case _: refuse(T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested})

def reduce(+block: T.Block, +input: T.Input) -> BlockDecision:
  match input:
    case T.FieldEdited{event, raw}: field_node(current_node(block, event), raw, block)
    case T.Activated{event}: action_node(block, current_node(block, event))
    case T.ViewChanged{event, command}: view_node(block, current_node(block, event), command)
    case other: reduce_other(block, other)

def input_owner(+input: T.Input) -> T.Owner:
  match input:
    case T.SourceChanged{owner, source, closed, ending, external}: owner
    case T.SourcesChanged{owner, values}: owner
    case T.ExternalChanged{owner, allowed}: owner
    case T.ContinueParsing{owner}: owner
    case T.Restored{owner, definition, payload}: owner
    case T.EffectCompleted{owner, path, ticket, success, message}: owner
    case T.StorageFailed{owner, message}: owner
    case T.Removed{owner}: owner
    case T.FieldEdited{T.EventIdentity{T.Identity{owner, path}, occurrence}, raw}: owner
    case T.Activated{T.EventIdentity{T.Identity{owner, path}, occurrence}}: owner
    case T.ViewChanged{T.EventIdentity{T.Identity{owner, path}, occurrence}, command}: owner

def persistable(+block: T.Block) -> Bool:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  syntax_sealed(syntax) && closed && is_complete(ending) && Bool.not(syntax_failed(syntax)) && Bool.not(R.prepared_fatal(R.prepare(block)))

def persisted_views(+views: +List<J.Field>, +allowed: +List<J.Field>) -> +List<J.Field>:
  match views:
    case Nil{}: Nil{}
    case Con{J.Field{+path, +value}, rest}:
      +tail = persisted_views(rest, allowed)
      Bool.pick(+List<J.Field>, S.field_has(allowed, path) && Codec.view_record(value, J.find(allowed, path)), J.Field{path, value} <> tail, tail)

def snapshot_payload(+block: T.Block) -> J.Json:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  Codec.encode(with_views(block, persisted_views(views, ViewSchema.save_descriptors(
    R.accepted_elements(block, R.prepare(block)), scene_nodes(scene(block)), views))))

def snapshot_notice(+block: T.Block, +message: String) -> T.Block:
  T.Block{+owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  with_feedback(block, T.Feedback{"@storage", 0n, False{}, message} <> feedback_remove(feedback, "@storage"))

def snapshot_saved(+block: T.Block, +payload: J.Json) -> T.Block & +List<T.Effect>:
  T.Block{+owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  (with_feedback(block, feedback_remove(feedback, "@storage")), [T.SaveSnapshot{owner, source, payload}])

# DEFENSE: Authored local state can exceed the 262144-scalar snapshot limit; keep it in memory and omit the oversized storage write.
def snapshot_admitted(+block: T.Block, +payload: J.Json, +allowed: Bool) -> T.Block & +List<T.Effect>:
  match allowed:
    case False{}: (snapshot_notice(block, "本地状态超过保存上限；当前输入仍保留，但尚未保存。"), Nil{})
    case True{}: snapshot_saved(block, payload)

def snapshot_checked(+block: T.Block, +payload: J.Json) -> T.Block & +List<T.Effect>:
  snapshot_admitted(block, payload, Codec.payload_fits(payload))

def snapshot_requested(+block: T.Block, +allowed: Bool) -> T.Block & +List<T.Effect>:
  match allowed:
    case False{}: (block, Nil{})
    case True{}: snapshot_checked(block, snapshot_payload(block))

def save_snapshot(+block: T.Block, +persist: Bool) -> T.Block & +List<T.Effect>:
  snapshot_requested(block, persist && persistable(block))

def load_admitted(+block: T.Block, +allowed: Bool) -> T.Block & +List<T.Effect>:
  match allowed:
    case False{}: (block, Nil{})
    case True{}: (with_restore_requested(block, True{}), [T.LoadSnapshot{block_owner(block)}])

def load_snapshot(+block: T.Block) -> T.Block & +List<T.Effect>:
  T.Block{ +owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} = block
  load_admitted(T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}, persistable(T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}) && Bool.not(edited) && Bool.not(restore_requested))

def apply_snapshot(result: T.Block & +List<T.Effect>, +state: T.State, +effects: +List<T.Effect>) -> T.Decision:
  (+block, saved) = result
  T.State{ +blocks} = state
  T.Decision{T.State{save_block(blocks, block)}, List.append(&2, T.Effect, effects, saved)}

def apply_loaded(result: T.Block & +List<T.Effect>, +state: T.State, +effects: +List<T.Effect>, +persist: Bool) -> T.Decision:
  (+block, load) = result
  apply_snapshot(save_snapshot(block, persist), state, List.append(&2, T.Effect, effects, load))

def apply(+decision: BlockDecision, +state: T.State) -> T.Decision:
  match decision:
    case BlockDecision{block, effects, False{}, persist}: T.Decision{state, effects}
    case BlockDecision{block, effects, True{}, persist}: apply_loaded(load_snapshot(normalize(bump(block))), state, effects, persist)

def dispatch_found(+found: Maybe<&2, T.Block>, +input: T.Input, +state: T.State) -> T.Decision:
  match found input:
    case None{} T.SourceChanged{owner, source, closed, ending, external}: apply(reduce(empty(owner), T.SourceChanged{owner, source, closed, ending, external}), state)
    case None{} _: T.Decision{state, Nil{}}
    case Some{block} other: apply(reduce(block, other), state)

# Command completion settles an existing correlation. It must not re-evaluate
# declarations, allocate mounts, request storage, or retry the authored action.
def block_feedback(+block: T.Block) -> +List<T.Feedback>:
  T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested} = block
  feedback

# DEFENSE: An authored command completion can arrive after its owner, mount or pending ticket changes; settle only the still-current correlation.
def feedback_completed_checked(+current: Bool, +block: T.Block, +path: String, +ticket: Nat, +success: Bool, +message: String, +state: T.State) -> T.Decision:
  match current state:
    case False{} _: T.Decision{state, Nil{}}
    case True{} T.State{blocks}:
      T.Decision{T.State{save_block(blocks, bump(with_feedback(block, settle_feedback(block_feedback(block), path, ticket, success, message))))}, Nil{}}

def feedback_completed_found(+found: Maybe<&2, T.Block>, +path: String, +ticket: Nat, +success: Bool, +message: String, +state: T.State) -> T.Decision:
  match found:
    case None{}: T.Decision{state, Nil{}}
    case Some{+block}:
      feedback_completed_checked(matching_feedback(block_feedback(block), path, ticket), block, path, ticket, success, message, state)

def step_kind(+input: T.Input, +state: T.State, +blocks: +List<T.Block>) -> T.Decision:
  match input:
    case T.Removed{owner}: T.Decision{T.State{remove_block(blocks, owner)}, Nil{}}
    case T.EffectCompleted{owner, path, ticket, success, message}: feedback_completed_found(find_block(blocks, owner), path, ticket, success, message, state)
    case other: dispatch_found(find_block(blocks, input_owner(other)), other, state)

def step(+input: T.Input, +state: T.State) -> T.Decision:
  T.State{ +blocks} = state
  step_kind(input, T.State{blocks}, blocks)

def observe_found(+found: Maybe<&2, T.Block>, +owner: T.Owner) -> T.Scene:
  match found:
    case Some{block}: scene(block)
    case None{}: T.Scene{owner, Nil{}, Nil{}, False{}, False{}, 0n}

def observe(+owner: T.Owner, +state: T.State) -> T.Scene:
  T.State{ +blocks} = state
  observe_found(find_block(blocks, owner), owner)

def source_requests_blocks(+blocks: +List<T.Block>) -> +List<T.SourceRequest>:
  match blocks:
    case Nil{}: Nil{}
    case Con{block, rest}: List.append(&2, T.SourceRequest, R.prepared_requests(R.prepare(block)), source_requests_blocks(rest))

def source_requests(+state: T.State) -> +List<T.SourceRequest>:
  T.State{ +blocks} = state
  source_requests_blocks(blocks)
