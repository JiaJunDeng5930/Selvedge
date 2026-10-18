import Base
import ./MODEL.bend as W
import ./PROGRAM.bend as Actual
import ./SPEC.bend as Spec
import ../../bendlib/component.bend as C
import ../../bendlib/association-map.bend as Finite

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
      {W.graph_owner(W.dissociate_graph(id, state), id) == None{} : Maybe<&2, Nat>}}
