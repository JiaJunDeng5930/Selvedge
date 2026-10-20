import Base
import ../../harness/DOMAIN.bend as D
import ./MODEL.bend as W
import ./PROGRAM.bend as Actual
import ./SPEC.bend as Spec
import ./CODEC.bend as Codec
import ../../bendlib/json.bend as J
import ../../bendlib/component.bend as C
import ../../bendlib/association-map.bend as Finite

type TaskCreation is Type:
  TaskCreation{
    constructed: @+body:J.Json ->
      {Codec.construct(Codec.CreateTaskKind{}, body) ==
        W.CreateTask{Codec.number(J.get(body, "work_id")), J.text(J.get(body, "profile")),
          J.text_or(J.get(body, "reasoning"), "default"), D.user_content(J.get(body, "message"), J.get(body, "images")),
          Codec.settings(J.get(body, "settings")), J.boolean(J.get(body, "create_worktree"))} : W.Command},
    encoded: @+work:Nat -> @+profile:String -> @+reasoning:String -> @+message:D.UserContent -> @+settings:J.Json -> @+create_worktree:Bool ->
      {Codec.command_json(W.CreateTask{work, profile, reasoning, message, settings, create_worktree}) ==
        J.Object{[J.Field{"op", J.Text{"create_work_task"}}, J.Field{"work_id", J.nat(work)}, J.Field{"profile", J.Text{profile}},
          J.Field{"reasoning", J.Text{reasoning}}, J.Field{"message", D.content_json(message)}, J.Field{"settings", settings},
          J.Field{"create_worktree", J.Boolean{create_worktree}}]} : J.Json},
    omitted_worktree: @+body:J.Json -> @absent:{J.get(body, "create_worktree") == J.Null{} : J.Json} ->
      {Codec.construct(Codec.CreateTaskKind{}, body) ==
        W.CreateTask{Codec.number(J.get(body, "work_id")), J.text(J.get(body, "profile")),
          J.text_or(J.get(body, "reasoning"), "default"), D.user_content(J.get(body, "message"), J.get(body, "images")),
          Codec.settings(J.get(body, "settings")), False{}} : W.Command},
    delegated: @work:Nat -> @profile:String -> @reasoning:String -> @message:D.UserContent -> @settings:J.Json -> @create_worktree:Bool -> @state:W.State ->
      {W.resolve(W.CreateTask{work, profile, reasoning, message, settings, create_worktree}, state) ==
        W.Refuse{"task_creation_boundary", "Create Work Tasks through the harness feature operation."} : W.Resolution}}

type SharedUI is Type:
  SharedUI{
    updated: @+id:Nat -> @+source:String -> @+previous:W.Work -> @+state:W.State ->
      {W.find(Actual.result_state(Actual.realize_calculation(W.UpdateUI{id, W.with_ui(source, 1n+W.ui_revision(previous), previous)}, state)), id) ==
        Some{W.with_ui(source, 1n+W.ui_revision(previous), previous)} : Maybe<&2, W.Work>},
    observations: @+source:String -> @+revision:Nat -> @+previous:W.Work ->
      {W.ui_source(W.with_ui(source, revision, previous)) == source : String} &
      {W.ui_revision(W.with_ui(source, revision, previous)) == revision : Nat} &
      {W.name(W.with_ui(source, revision, previous)) == W.name(previous) : String},
    other_work: @+id:Nat -> @+work:W.Work -> @+other:Nat -> @+state:W.State ->
      @different:{Nat.is_eq(other, id) == False{} : Bool} ->
      {W.find(Actual.result_state(Actual.realize_calculation(W.UpdateUI{id, work}, state)), other) == W.find(state, other) : Maybe<&2, W.Work>},
    task_owner: @+id:Nat -> @+work:W.Work -> @+task:Nat -> @+lineage:+List<Nat> -> @+state:W.State ->
      {W.task_owner(Actual.result_state(Actual.realize_calculation(W.UpdateUI{id, work}, state)), task, lineage) == W.task_owner(state, task, lineage) : Maybe<&2, Nat>},
    conflict: @id:Nat -> @patch:String -> @previous:W.Work ->
      {W.patch_revision(False{}, id, patch, previous) ==
        W.Refuse{"revision_conflict", "The Work UI changed. Read its current source and revision before applying another patch."} : W.Resolution},
    resolved: @+id:Nat -> @+source:String -> @+previous:W.Work ->
      {W.patched_source(Done{source}, id, previous) == W.Accept{W.UpdateUI{id, W.with_ui(source, 1n+W.ui_revision(previous), previous)}} : W.Resolution},
    rename_preserves: @+id:Nat -> @+name:String -> @+previous:W.Work ->
      {W.rename_valid(True{}, id, name, previous) == W.Accept{W.Retitle{id, W.Work{name, W.ui_source(previous), W.ui_revision(previous)}}} : W.Resolution}}

type Boundary is Type:
  Boundary{
    refinement: @+change:W.Change -> @+state:W.State ->
      {Actual.realize_calculation(change, state) == Spec.meaning(change, state) : C.Decision<W.State, Unit>},
    added: @+id:Nat -> @+work:W.Work -> @+next:Nat -> @+state:W.State ->
      {W.find(Actual.result_state(Actual.realize_calculation(W.Add{id, work, next}, state)), id) == Some{work} : Maybe<&2, W.Work>},
    retitled: @+id:Nat -> @+work:W.Work -> @+state:W.State ->
      {W.find(Actual.result_state(Actual.realize_calculation(W.Retitle{id, work}, state)), id) == Some{work} : Maybe<&2, W.Work>},
    roots_preserved: @+change:W.Change -> @+state:W.State ->
      {W.roots(Actual.result_state(Actual.realize_calculation(change, state))) == W.roots(state) : +List<Finite.Entry(Nat)>},
    graphs_preserved: @+change:W.Change -> @+state:W.State ->
      {W.graphs(Actual.result_state(Actual.realize_calculation(change, state))) == W.graphs(state) : +List<Finite.Entry(Nat)>},
    task_associated: @+id:Nat -> @+owner:Nat -> @+work:W.Work -> @+state:W.State ->
      @+unrecorded:{W.root_owner(state, id) == None{} : Maybe<&2, Nat>} ->
      @existing:{W.find(state, owner) == Some{work} : Maybe<&2, W.Work>} ->
      {W.root_owner(W.associate_task(id, owner, state), id) == Some{owner} : Maybe<&2, Nat>},
    graph_associated: @+id:Nat -> @+owner:Nat -> @+work:W.Work -> @+state:W.State ->
      @+unrecorded:{W.graph_owner(state, id) == None{} : Maybe<&2, Nat>} ->
      @existing:{W.find(state, owner) == Some{work} : Maybe<&2, W.Work>} ->
      {W.graph_owner(W.associate_graph(id, owner, state), id) == Some{owner} : Maybe<&2, Nat>},
    root_no_transfer: @+id:Nat -> @+previous:Nat -> @+owner:Nat -> @+state:W.State ->
      @observed:{W.root_owner(state, id) == Some{previous} : Maybe<&2, Nat>} ->
      {W.associate_task(id, owner, state) == state : W.State},
    lineage_inheritance: @+child:Nat -> @+parent:Nat -> @+lineage:+List<Nat> -> @+state:W.State ->
      @unrecorded:{W.root_owner(state, child) == None{} : Maybe<&2, Nat>} ->
      {W.task_owner(state, child, parent <> lineage) == W.task_owner(state, parent, lineage) : Maybe<&2, Nat>},
    graph_removed: @+id:Nat -> @+state:W.State ->
      {W.graph_owner(W.dissociate_graph(id, state), id) == None{} : Maybe<&2, Nat>},
    task_creation: TaskCreation,
    shared_ui: SharedUI}
