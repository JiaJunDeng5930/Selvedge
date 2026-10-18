import Base
import ./TYPES.bend as T
import ./STATE.bend as State
import ./REGISTRY.bend as Registry
import ./CODEC.bend as Codec
import ./SYNTAX.bend as Syntax
import ./VIEW_SCHEMA.bend as Views
import ../../bendlib/json.bend as J
import ../../bendlib/string-equality.bend as Text
import ../../bendlib/stdlib.bend as Std

# Snapshot state contains canonical root values with their complete schemas and
# typed view state. Draft buffers, source facts and pending actions never enter
# this payload. View membership is the shared DSL observation, not a second
# declaration evaluator maintained by persistence.
def canonical_local(local: T.Local) -> J.Json:
  T.Local{id, schema, value, raw, validation} = local
  J.Object{[J.Field{"id", J.Text{id}}, J.Field{"schema", Syntax.schema_json(schema)}, J.Field{"value", value}]}

def permitted_view(+allowed: +List<J.Field>, field: J.Field) -> Bool:
  J.Field{+path, value} = field
  Syntax.field_has(allowed, path) && Codec.view_record(value, J.find(allowed, path))

type ViewSelection is Data:
  ViewSelection{allowed: +List<J.Field>, selected: +List<J.Field>}

def keep_view(keep: Bool, field: J.Field, tail: +List<J.Field>) -> +List<J.Field>:
  match keep:
    case True{}: field <> tail
    case False{}: tail

def select_view_step(field: J.Field, context: ViewSelection) -> ViewSelection:
  match field context:
    case J.Field{+path, +value} ViewSelection{+allowed, tail}:
      ViewSelection{allowed, keep_view(permitted_view(allowed, J.Field{path, value}), J.Field{path, value}, tail)}

def selection_values(context: ViewSelection) -> +List<J.Field>:
  ViewSelection{allowed, selected} = context
  selected

def selected_views(views: +List<J.Field>, allowed: +List<J.Field>) -> +List<J.Field>:
  selection_values(List.foldr(~&2, ~J.Field, ~ViewSelection, ~select_view_step, views, ViewSelection{allowed, Nil{}}))

def payload(+block: T.Block) -> J.Json:
  T.Block{owner, source, syntax, ending, closed, external, locals, sources, +views, mounts, feedback, revision, next, edited, restore_requested} = block
  +allowed = Views.save_descriptors(Registry.accepted_elements(block, Registry.prepare(block)), State.scene_nodes(State.scene(block)), views)
  J.Object{[J.Field{"version", J.nat(1n)}, J.Field{"locals", J.Array{Std.map(~T.Local, ~J.Json, ~canonical_local, locals)}},
    J.Field{"views", J.Object{selected_views(views, allowed)}}]}

def complete(ending: T.Ending) -> Bool:
  match ending:
    case T.Complete{}: True{}
    case _: False{}

def ready(+block: T.Block) -> Bool:
  T.Block{owner, source, T.Syntax{roots, frames, tail, failed, sealed, accepted, characters, diagnostic}, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested} = block
  sealed && closed && complete(ending) && Bool.not(failed) && Bool.not(Registry.prepared_fatal(Registry.prepare(block)))

def remove_storage_entry(remove: Bool, entry: T.Feedback, tail: +List<T.Feedback>) -> +List<T.Feedback>:
  match remove:
    case True{}: tail
    case False{}: entry <> tail

def storage_feedback_step(entry: T.Feedback, tail: +List<T.Feedback>) -> +List<T.Feedback>:
  match entry:
    case T.Feedback{+path, ticket, pending, message}:
      remove_storage_entry(Text.string_equal(path, "@storage"), T.Feedback{path, ticket, pending, message}, tail)

def storage_feedback_removed(feedback: +List<T.Feedback>) -> +List<T.Feedback>:
  List.foldr(~&2, ~T.Feedback, ~(+List<T.Feedback>), ~storage_feedback_step, feedback, Nil{})

def admitted_save(+before: T.Block, +value: J.Json, +allowed: Bool) -> T.Block & +List<T.Effect>:
  match before allowed:
    case T.Block{+owner, +source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested} True{}:
      (T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, storage_feedback_removed(feedback), revision, next, edited, restore_requested},
        [T.SaveSnapshot{owner, source, value}])
    case T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested} False{}:
      (T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts,
        T.Feedback{"@storage", 0n, False{}, "本地状态超过保存上限；当前输入仍保留，但尚未保存。"} <> storage_feedback_removed(feedback), revision, next, edited, restore_requested}, Nil{})

def requested_save(+before: T.Block, +allowed: Bool) -> T.Block & +List<T.Effect>:
  match allowed:
    case False{}: (before, Nil{})
    case True{}: admitted_save(before, payload(before), Codec.payload_fits(payload(before)))

def required_save(+before: T.Block, persist: Bool) -> T.Block & +List<T.Effect>:
  requested_save(before, persist && ready(before))

def admitted_load(+before: T.Block, +allowed: Bool) -> T.Block & +List<T.Effect>:
  match before allowed:
    case T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested} False{}: (before, Nil{})
    case T.Block{+owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested} True{}:
      (T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, True{}},
        [T.LoadSnapshot{owner}])

def required_load(+before: T.Block) -> T.Block & +List<T.Effect>:
  T.Block{+owner, +source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested} = before
  admitted_load(before, ready(before) && Bool.not(edited) && Bool.not(restore_requested))

def pipeline_block(result: T.Block & +List<T.Effect>) -> T.Block:
  (block, effects) = result
  block

def pipeline_effects(result: T.Block & +List<T.Effect>) -> +List<T.Effect>:
  (block, effects) = result
  effects

def append_storage(+loaded: +List<T.Effect>, result: T.Block & +List<T.Effect>) -> T.Block & +List<T.Effect>:
  (block, saved) = result
  (block, List.append(&2, T.Effect, loaded, saved))

def required_tail(persist: Bool, loaded: T.Block & +List<T.Effect>) -> T.Block & +List<T.Effect>:
  (block, effects) = loaded
  append_storage(effects, required_save(block, persist))

def required_pipeline(+before: T.Block, persist: Bool) -> T.Block & +List<T.Effect>:
  required_tail(persist, required_load(before))

def SnapshotOutcome(+before: T.Block, persist: Bool, after: T.Block, effects: +List<T.Effect>) -> Type:
  {(after, effects) == required_pipeline(before, persist) : T.Block & +List<T.Effect>}
