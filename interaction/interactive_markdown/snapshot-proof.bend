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

import ./snapshot-contract.bend as Contract

# Commit proof clients retain these projections while the sole specification
# and its immutable value vocabulary live in snapshot-contract.
def pipeline_block(result: T.Block & +List<T.Effect>) -> T.Block:
  Contract.pipeline_block(result)

def pipeline_effects(result: T.Block & +List<T.Effect>) -> +List<T.Effect>:
  Contract.pipeline_effects(result)

def append_storage(loaded: +List<T.Effect>, result: T.Block & +List<T.Effect>) -> T.Block & +List<T.Effect>:
  Contract.append_storage(loaded, result)

def actual_tail(persist: Bool, loaded: T.Block & +List<T.Effect>) -> T.Block & +List<T.Effect>:
  (block, effects) = loaded
  Contract.append_storage(effects, State.save_snapshot(block, persist))

def actual_pipeline(+before: T.Block, persist: Bool) -> T.Block & +List<T.Effect>:
  actual_tail(persist, State.load_snapshot(before))

def canonical_locals(+locals: +List<T.Local>) ->
  {Codec.locals_json(locals) == Std.map(~T.Local, ~J.Json, ~Contract.canonical_local, locals) : +List<J.Json>}:
  match locals:
    case Nil{}: {==}
    case Con{+local, +rest}:
      match local:
        case T.Local{id, schema, value, raw, validation}:
          Equal.cong(+List<J.Json>, +List<J.Json>, (tail => Contract.canonical_local(local) <> tail),
            Codec.locals_json(rest), Std.map(~T.Local, ~J.Json, ~Contract.canonical_local, rest), canonical_locals(rest))

def keep_view_pick(+keep: Bool, +field: J.Field, +tail: +List<J.Field>) ->
  {Contract.keep_view(keep, field, tail) == Bool.pick(+List<J.Field>, keep, field <> tail, tail) : +List<J.Field>}:
  match keep:
    case True{}: {==}
    case False{}: {==}

def selected_view_fold(+views: +List<J.Field>, +allowed: +List<J.Field>) ->
  {List.foldr(~&2, ~J.Field, ~Contract.ViewSelection, ~Contract.select_view_step, views, Contract.ViewSelection{allowed, Nil{}}) ==
    Contract.ViewSelection{allowed, State.persisted_views(views, allowed)} : Contract.ViewSelection}:
  match views:
    case Nil{}: {==}
    case Con{J.Field{+path, +value}, +rest}:
      Equal.trans(Contract.ViewSelection,
        Contract.select_view_step(J.Field{path, value}, List.foldr(~&2, ~J.Field, ~Contract.ViewSelection, ~Contract.select_view_step, rest, Contract.ViewSelection{allowed, Nil{}})),
        Contract.select_view_step(J.Field{path, value}, Contract.ViewSelection{allowed, State.persisted_views(rest, allowed)}),
        Contract.ViewSelection{allowed, State.persisted_views(J.Field{path, value} <> rest, allowed)},
        Equal.cong(Contract.ViewSelection, Contract.ViewSelection, (context => Contract.select_view_step(J.Field{path, value}, context)),
          List.foldr(~&2, ~J.Field, ~Contract.ViewSelection, ~Contract.select_view_step, rest, Contract.ViewSelection{allowed, Nil{}}),
          Contract.ViewSelection{allowed, State.persisted_views(rest, allowed)}, selected_view_fold(rest, allowed)),
        Equal.cong(+List<J.Field>, Contract.ViewSelection, (values => Contract.ViewSelection{allowed, values}),
          Contract.keep_view(Contract.permitted_view(allowed, J.Field{path, value}), J.Field{path, value}, State.persisted_views(rest, allowed)),
          State.persisted_views(J.Field{path, value} <> rest, allowed),
          keep_view_pick(Contract.permitted_view(allowed, J.Field{path, value}), J.Field{path, value}, State.persisted_views(rest, allowed))))

def views_selected(+views: +List<J.Field>, +allowed: +List<J.Field>) ->
  {State.persisted_views(views, allowed) == Contract.selected_views(views, allowed) : +List<J.Field>}:
  Equal.sym(+List<J.Field>, Contract.selected_views(views, allowed), State.persisted_views(views, allowed),
    Equal.cong(Contract.ViewSelection, +List<J.Field>, Contract.selection_values,
      List.foldr(~&2, ~J.Field, ~Contract.ViewSelection, ~Contract.select_view_step, views, Contract.ViewSelection{allowed, Nil{}}),
      Contract.ViewSelection{allowed, State.persisted_views(views, allowed)}, selected_view_fold(views, allowed)))

def canonical_payload(+block: T.Block) -> {State.snapshot_payload(block) == Contract.payload(block) : J.Json}:
  match block:
    case T.Block{owner, source, syntax, ending, closed, external, +locals, sources, +views, mounts, feedback, revision, next, edited, restore_requested}:
      +allowed = Views.save_descriptors(Registry.accepted_elements(block, Registry.prepare(block)), State.scene_nodes(State.scene(block)), views)
      Equal.trans(J.Json, State.snapshot_payload(block),
        J.Object{[J.Field{"version", J.nat(1n)}, J.Field{"locals", J.Array{Std.map(~T.Local, ~J.Json, ~Contract.canonical_local, locals)}}, J.Field{"views", J.Object{State.persisted_views(views, allowed)}}]}, Contract.payload(block),
        Equal.cong(+List<J.Json>, J.Json,
          (values => J.Object{[J.Field{"version", J.nat(1n)}, J.Field{"locals", J.Array{values}}, J.Field{"views", J.Object{State.persisted_views(views, allowed)}}]}),
          Codec.locals_json(locals), Std.map(~T.Local, ~J.Json, ~Contract.canonical_local, locals), canonical_locals(locals)),
        Equal.cong(+List<J.Field>, J.Json,
          (values => J.Object{[J.Field{"version", J.nat(1n)}, J.Field{"locals", J.Array{Std.map(~T.Local, ~J.Json, ~Contract.canonical_local, locals)}}, J.Field{"views", J.Object{values}}]}),
          State.persisted_views(views, allowed), Contract.selected_views(views, allowed), views_selected(views, allowed)))

def complete_ending(+ending: T.Ending) -> {State.is_complete(ending) == Contract.complete(ending) : Bool}:
  match ending:
    case T.Open{}: {==}
    case T.Complete{}: {==}
    case T.Interrupted{}: {==}

def ready_correspondence(+block: T.Block) -> {State.persistable(block) == Contract.ready(block) : Bool}:
  match block:
    case T.Block{owner, source, T.Syntax{roots, frames, tail, +failed, +sealed, accepted, characters, diagnostic}, +ending, +closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested}:
      Equal.cong(Bool, Bool, (finished => sealed && closed && finished && Bool.not(failed) && Bool.not(Registry.prepared_fatal(Registry.prepare(block)))),
        State.is_complete(ending), Contract.complete(ending), complete_ending(ending))

def remove_storage_pick(+remove: Bool, +entry: T.Feedback, +tail: +List<T.Feedback>) ->
  {Contract.remove_storage_entry(remove, entry, tail) == Bool.pick(+List<T.Feedback>, remove, tail, entry <> tail) : +List<T.Feedback>}:
  match remove:
    case True{}: {==}
    case False{}: {==}

def feedback_cleaned(+feedback: +List<T.Feedback>) ->
  {State.feedback_remove(feedback, "@storage") == Contract.storage_feedback_removed(feedback) : +List<T.Feedback>}:
  match feedback:
    case Nil{}: {==}
    case Con{T.Feedback{+path, +ticket, +pending, +message}, +rest}:
      Equal.trans(+List<T.Feedback>, State.feedback_remove(T.Feedback{path, ticket, pending, message} <> rest, "@storage"),
        Bool.pick(+List<T.Feedback>, Text.string_equal(path, "@storage"), Contract.storage_feedback_removed(rest), T.Feedback{path, ticket, pending, message} <> Contract.storage_feedback_removed(rest)),
        Contract.storage_feedback_removed(T.Feedback{path, ticket, pending, message} <> rest),
        Equal.cong(+List<T.Feedback>, +List<T.Feedback>,
          (tail => Bool.pick(+List<T.Feedback>, Text.string_equal(path, "@storage"), tail, T.Feedback{path, ticket, pending, message} <> tail)),
          State.feedback_remove(rest, "@storage"), Contract.storage_feedback_removed(rest), feedback_cleaned(rest)),
        Equal.sym(+List<T.Feedback>, Contract.storage_feedback_removed(T.Feedback{path, ticket, pending, message} <> rest),
          Bool.pick(+List<T.Feedback>, Text.string_equal(path, "@storage"), Contract.storage_feedback_removed(rest), T.Feedback{path, ticket, pending, message} <> Contract.storage_feedback_removed(rest)),
          remove_storage_pick(Text.string_equal(path, "@storage"), T.Feedback{path, ticket, pending, message}, Contract.storage_feedback_removed(rest))))

def save_admission(+before: T.Block, +value: J.Json, allowed: Bool) ->
  {State.snapshot_admitted(before, value, allowed) == Contract.admitted_save(before, value, allowed) : T.Block & +List<T.Effect>}:
  match before allowed:
    case T.Block{+owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} True{}:
      Equal.cong(+List<T.Feedback>, T.Block & +List<T.Effect>,
        (remaining => (T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, remaining, revision, next, edited, restore_requested}, [T.SaveSnapshot{owner, source, value}])),
        State.feedback_remove(feedback, "@storage"), Contract.storage_feedback_removed(feedback), feedback_cleaned(feedback))
    case T.Block{+owner, +source, +syntax, +ending, +closed, +external, +locals, +sources, +views, +mounts, +feedback, +revision, +next, +edited, +restore_requested} False{}:
      Equal.cong(+List<T.Feedback>, T.Block & +List<T.Effect>,
        (remaining => (T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, T.Feedback{"@storage", 0n, False{}, "本地状态超过保存上限；当前输入仍保留，但尚未保存。"} <> remaining, revision, next, edited, restore_requested}, Nil{})),
        State.feedback_remove(feedback, "@storage"), Contract.storage_feedback_removed(feedback), feedback_cleaned(feedback))

def save_request(+before: T.Block, allowed: Bool) ->
  {State.snapshot_requested(before, allowed) == Contract.requested_save(before, allowed) : T.Block & +List<T.Effect>}:
  match allowed:
    case False{}: {==}
    case True{}:
      Equal.trans(T.Block & +List<T.Effect>, State.snapshot_checked(before, State.snapshot_payload(before)),
        State.snapshot_checked(before, Contract.payload(before)), Contract.requested_save(before, True{}),
        Equal.cong(J.Json, T.Block & +List<T.Effect>, (value => State.snapshot_checked(before, value)), State.snapshot_payload(before), Contract.payload(before), canonical_payload(before)),
        save_admission(before, Contract.payload(before), Codec.payload_fits(Contract.payload(before))))

def save_complete(+before: T.Block, +persist: Bool) ->
  {State.save_snapshot(before, persist) == Contract.required_save(before, persist) : T.Block & +List<T.Effect>}:
  Equal.trans(T.Block & +List<T.Effect>, State.save_snapshot(before, persist),
    State.snapshot_requested(before, persist && Contract.ready(before)), Contract.required_save(before, persist),
    Equal.cong(Bool, T.Block & +List<T.Effect>, (valid => State.snapshot_requested(before, persist && valid)), State.persistable(before), Contract.ready(before), ready_correspondence(before)),
    save_request(before, persist && Contract.ready(before)))

def load_admission(+before: T.Block, allowed: Bool) ->
  {State.load_admitted(before, allowed) == Contract.admitted_load(before, allowed) : T.Block & +List<T.Effect>}:
  match before allowed:
    case T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested} False{}: {==}
    case T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested} True{}: {==}

def load_complete(+before: T.Block) ->
  {State.load_snapshot(before) == Contract.required_load(before) : T.Block & +List<T.Effect>}:
  match before:
    case T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, +edited, +restore_requested}:
      Equal.trans(T.Block & +List<T.Effect>, State.load_snapshot(before),
        State.load_admitted(before, Contract.ready(before) && Bool.not(edited) && Bool.not(restore_requested)), Contract.required_load(before),
        Equal.cong(Bool, T.Block & +List<T.Effect>, (valid => State.load_admitted(before, valid && Bool.not(edited) && Bool.not(restore_requested))),
          State.persistable(before), Contract.ready(before), ready_correspondence(before)),
        load_admission(before, Contract.ready(before) && Bool.not(edited) && Bool.not(restore_requested)))

def tail_complete(+persist: Bool, loaded: T.Block & +List<T.Effect>) ->
  {actual_tail(persist, loaded) == Contract.required_tail(persist, loaded) : T.Block & +List<T.Effect>}:
  (+block, +effects) = loaded
  Equal.cong(T.Block & +List<T.Effect>, T.Block & +List<T.Effect>, (result => Contract.append_storage(effects, result)),
    State.save_snapshot(block, persist), Contract.required_save(block, persist), save_complete(block, persist))

def pipeline_complete(+before: T.Block, +persist: Bool) ->
  {actual_pipeline(before, persist) == Contract.required_pipeline(before, persist) : T.Block & +List<T.Effect>}:
  Equal.trans(T.Block & +List<T.Effect>, actual_pipeline(before, persist),
    actual_tail(persist, Contract.required_load(before)), Contract.required_pipeline(before, persist),
    Equal.cong(T.Block & +List<T.Effect>, T.Block & +List<T.Effect>, (loaded => actual_tail(persist, loaded)), State.load_snapshot(before), Contract.required_load(before), load_complete(before)),
    tail_complete(persist, Contract.required_load(before)))

def pipeline_parts(result: T.Block & +List<T.Effect>) ->
  {(Contract.pipeline_block(result), Contract.pipeline_effects(result)) == result : T.Block & +List<T.Effect>}:
  (block, effects) = result
  {==}

def snapshot_outcome(+before: T.Block, +persist: Bool) ->
  Contract.SnapshotOutcome(before, persist, Contract.pipeline_block(actual_pipeline(before, persist)), Contract.pipeline_effects(actual_pipeline(before, persist))):
  Equal.trans(T.Block & +List<T.Effect>, (Contract.pipeline_block(actual_pipeline(before, persist)), Contract.pipeline_effects(actual_pipeline(before, persist))),
    actual_pipeline(before, persist), Contract.required_pipeline(before, persist), pipeline_parts(actual_pipeline(before, persist)), pipeline_complete(before, persist))

def admitted_save_owner(+before: T.Block, value: J.Json, allowed: Bool) ->
  {State.block_owner(Contract.pipeline_block(Contract.admitted_save(before, value, allowed))) == State.block_owner(before) : T.Owner}:
  match before allowed:
    case T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested} False{}: {==}
    case T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested} True{}: {==}

def requested_save_owner(+before: T.Block, allowed: Bool) ->
  {State.block_owner(Contract.pipeline_block(Contract.requested_save(before, allowed))) == State.block_owner(before) : T.Owner}:
  match allowed:
    case False{}: {==}
    case True{}: admitted_save_owner(before, Contract.payload(before), Codec.payload_fits(Contract.payload(before)))

def admitted_load_owner(+before: T.Block, allowed: Bool) ->
  {State.block_owner(Contract.pipeline_block(Contract.admitted_load(before, allowed))) == State.block_owner(before) : T.Owner}:
  match before allowed:
    case T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested} False{}: {==}
    case T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, edited, restore_requested} True{}: {==}

def required_load_owner(+before: T.Block) ->
  {State.block_owner(Contract.pipeline_block(Contract.required_load(before))) == State.block_owner(before) : T.Owner}:
  match before:
    case T.Block{owner, source, syntax, ending, closed, external, locals, sources, views, mounts, feedback, revision, next, +edited, +restore_requested}:
      admitted_load_owner(before, Contract.ready(before) && Bool.not(edited) && Bool.not(restore_requested))

def appended_block(effects: +List<T.Effect>, result: T.Block & +List<T.Effect>) ->
  {Contract.pipeline_block(Contract.append_storage(effects, result)) == Contract.pipeline_block(result) : T.Block}:
  (block, saved) = result
  {==}

def required_tail_owner(+persist: Bool, loaded: T.Block & +List<T.Effect>) ->
  {State.block_owner(Contract.pipeline_block(Contract.required_tail(persist, loaded))) == State.block_owner(Contract.pipeline_block(loaded)) : T.Owner}:
  (+block, +effects) = loaded
  Equal.trans(T.Owner, State.block_owner(Contract.pipeline_block(Contract.required_tail(persist, loaded))),
    State.block_owner(Contract.pipeline_block(Contract.required_save(block, persist))), State.block_owner(block),
    Equal.cong(T.Block, T.Owner, (value => State.block_owner(value)),
      Contract.pipeline_block(Contract.append_storage(effects, Contract.required_save(block, persist))), Contract.pipeline_block(Contract.required_save(block, persist)), appended_block(effects, Contract.required_save(block, persist))),
    requested_save_owner(block, persist && Contract.ready(block)))

def pipeline_owner(+before: T.Block, +persist: Bool) ->
  {State.block_owner(Contract.pipeline_block(actual_pipeline(before, persist))) == State.block_owner(before) : T.Owner}:
  Equal.trans(T.Owner, State.block_owner(Contract.pipeline_block(actual_pipeline(before, persist))),
    State.block_owner(Contract.pipeline_block(Contract.required_pipeline(before, persist))), State.block_owner(before),
    Equal.cong(T.Block & +List<T.Effect>, T.Owner, (result => State.block_owner(Contract.pipeline_block(result))),
      actual_pipeline(before, persist), Contract.required_pipeline(before, persist), pipeline_complete(before, persist)),
    Equal.trans(T.Owner, State.block_owner(Contract.pipeline_block(Contract.required_pipeline(before, persist))),
      State.block_owner(Contract.pipeline_block(Contract.required_load(before))), State.block_owner(before), required_tail_owner(persist, Contract.required_load(before)), required_load_owner(before)))


# Direct membership cases constrain the shared view denotation. Only an actual
# corresponding parent's observed exclusion deletes a dynamic saved view.
def table_schema() -> T.Element:
  T.Element{"table", [T.Attribute{"id", "\"table\""}, T.Attribute{"rows", "[]"}, T.Attribute{"row-key", "\"id\""}, T.Attribute{"label", "\"Rows\""}],
    [T.Element{"column", [T.Attribute{"id", "\"name\""}, T.Attribute{"field", "\"name\""}, T.Attribute{"label", "\"Name\""}], Nil{}, True{}}], True{}}

def hidden_table_schema() -> T.Element:
  T.Element{"when", [T.Attribute{"id", "\"hidden\""}, T.Attribute{"test", "false"}], [table_schema()], True{}}

def each_schema() -> T.Element:
  T.Element{"each", [T.Attribute{"id", "\"items\""}, T.Attribute{"items", "[]"}, T.Attribute{"item", "\"row\""}, T.Attribute{"key", "\"id\""}], [hidden_table_schema()], True{}}

def observed_each(owner: T.Owner, path: String, items: +List<J.Json>) -> T.ExpandedNode:
  T.ExpandedNode{T.Identity{owner, path}, 1n, "each", J.Object{[J.Field{"items", J.Array{items}}, J.Field{"key", J.Text{"id"}}]}, T.NoBinding{}, Nil{}}

def saved_page(path: String) -> J.Field:
  J.Field{path, J.Object{[J.Field{"page", J.nat(1n)}]}}

def required_table_schema() -> J.Json:
  J.Object{[J.Field{"kind", J.Text{"table"}}, J.Field{"columns", J.Array{[J.Text{"name"}]}}]}

def static_conditional_view_saved() ->
  {Views.save_descriptors([hidden_table_schema()], Nil{}, [saved_page("/\"hidden\"/\"table\"")]) ==
    [J.Field{"/\"hidden\"/\"table\"", required_table_schema()}] : +List<J.Field>}:
  {==}

def existing_dynamic_conditional_view_saved(+owner: T.Owner) ->
  {Views.save_descriptors([each_schema()], [observed_each(owner, "/\"items\"", [J.Object{[J.Field{"id", J.Text{"a"}}]}])],
    [saved_page("/\"items\"/@item/s:\"a\"/\"hidden\"/\"table\"")]) ==
    [J.Field{"/\"items\"/@item/s:\"a\"/\"hidden\"/\"table\"", required_table_schema()}] : +List<J.Field>}:
  {==}

def absent_dynamic_view_omitted(+owner: T.Owner) ->
  {Views.save_descriptors([each_schema()], [observed_each(owner, "/\"items\"", Nil{})],
    [saved_page("/\"items\"/@item/s:\"a\"/\"hidden\"/\"table\"")]) == Nil{} : +List<J.Field>}:
  {==}

def unobserved_dynamic_view_retained() ->
  {Views.save_descriptors([each_schema()], Nil{}, [saved_page("/\"items\"/@item/s:\"a\"/\"hidden\"/\"table\"")]) ==
    [J.Field{"/\"items\"/@item/s:\"a\"/\"hidden\"/\"table\"", required_table_schema()}] : +List<J.Field>}:
  {==}

def other_parent_cannot_supply_membership(+owner: T.Owner) ->
  {Views.save_descriptors([each_schema()], [observed_each(owner, "/\"items\"", Nil{}), observed_each(owner, "/\"other\"", [J.Object{[J.Field{"id", J.Text{"a"}}]}])],
    [saved_page("/\"items\"/@item/s:\"a\"/\"hidden\"/\"table\"")]) == Nil{} : +List<J.Field>}:
  {==}

def graph_schema() -> T.Element:
  T.Element{"graph-view", [T.Attribute{"id", "\"graph\""}], [T.Element{"node-template", Nil{}, [hidden_table_schema()], True{}}], True{}}

def absent_graph_node_view_omitted(+owner: T.Owner) ->
  {Views.save_descriptors([graph_schema()],
    [T.ExpandedNode{T.Identity{owner, "/\"graph\""}, 1n, "graph-view", J.Object{[J.Field{"nodes", J.Array{Nil{}}}]}, T.NoBinding{}, Nil{}}],
    [saved_page("/\"graph\"/@node/\"a\"/\"hidden\"/\"table\"")]) == Nil{} : +List<J.Field>}:
  {==}
