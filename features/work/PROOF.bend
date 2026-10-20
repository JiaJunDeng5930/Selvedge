import Base
import ../../harness/DOMAIN.bend as D
import ./MODEL.bend as W
import ./SPEC.bend as Spec
import ./PROGRAM.bend as P
import ./CONTRACT.bend as Contract
import ./CODEC.bend as Codec
import ../../bendlib/component.bend as C
import ../../bendlib/association-map.bend as Finite
import ../../bendlib/json.bend as J

def store_step(hit: Bool, +key: Nat, +previous: W.Work, +rest: +List<Finite.Entry(W.Work)>, +id: Nat, +work: W.Work,
  induction: {P.put_entries(rest, id, work) == Spec.store(rest, id, work) : +List<Finite.Entry(W.Work)>}) ->
  {P.put_selected(hit, key, previous, rest, work, P.put_entries(rest, id, work)) == Spec.replacement(hit, key, previous, rest, work, Spec.store(rest, id, work)) : +List<Finite.Entry(W.Work)>}:
  match hit:
    case True{}: {==}
    case False{}:
      Equal.cong(+List<Finite.Entry(W.Work)>, +List<Finite.Entry(W.Work)>, (tail => (key, previous) <> tail),
        P.put_entries(rest, id, work), Spec.store(rest, id, work), induction)

def store_meaning(entries: +List<Finite.Entry(W.Work)>, +id: Nat, +work: W.Work) ->
  {P.put_entries(entries, id, work) == Spec.store(entries, id, work) : +List<Finite.Entry(W.Work)>}:
  match entries:
    case Nil{}: {==}
    case Con{(+key, +previous), +rest}:
      store_step(Nat.is_eq(id, key), key, previous, rest, id, work, store_meaning(rest, id, work))

def refinement(+change: W.Change, +state: W.State) ->
  {P.realize_calculation(change, state) == Spec.meaning(change, state) : C.Decision<W.State, Unit>}:
  match change:
    case W.Add{+id, +work, +next}:
      W.State{+works, +roots, +graphs, previous} = state
      Equal.cong(+List<Finite.Entry(W.Work)>, C.Decision<W.State, Unit>,
        (entries => C.Decision{W.State{entries, roots, graphs, next}, D.success(W.work_json(id, work)), Nil{}}),
        P.put_entries(works, id, work), Spec.store(works, id, work), store_meaning(works, id, work))
    case W.Retitle{+id, +work}:
      W.State{+works, +roots, +graphs, +next} = state
      Equal.cong(+List<Finite.Entry(W.Work)>, C.Decision<W.State, Unit>,
        (entries => C.Decision{W.State{entries, roots, graphs, next}, D.success(W.work_json(id, work)), Nil{}}),
        P.put_entries(works, id, work), Spec.store(works, id, work), store_meaning(works, id, work))

def same_key(+id: Nat) -> {Nat.is_eq(id, id) == True{} : Bool}:
  match id:
    case 0n: {==}
    case 1n+previous: same_key(previous)

# The imported finite-map interface has no append lookup theorem. This bridge
# keeps its existing find and List.append, and records prefix precedence.
def appended_owner_step(hit: Bool, +previous: Nat, +rest: +List<Finite.Entry(Nat)>, +id: Nat, +owner: Nat,
  induction: {Finite.find(~Nat, List.append(&2, Finite.Entry(Nat), rest, [(id, owner)]), id) ==
    W.preferred_owner(Finite.find(~Nat, rest, id), Some{owner}) : Maybe<&2, Nat>}) ->
  {Finite.choose(~Nat, hit, previous, Finite.find(~Nat, List.append(&2, Finite.Entry(Nat), rest, [(id, owner)]), id)) ==
    W.preferred_owner(Finite.choose(~Nat, hit, previous, Finite.find(~Nat, rest, id)), Some{owner}) : Maybe<&2, Nat>}:
  match hit:
    case True{}: {==}
    case False{}: induction

def appended_owner(entries: +List<Finite.Entry(Nat)>, +id: Nat, +owner: Nat) ->
  {Finite.find(~Nat, List.append(&2, Finite.Entry(Nat), entries, [(id, owner)]), id) ==
    W.preferred_owner(Finite.find(~Nat, entries, id), Some{owner}) : Maybe<&2, Nat>}:
  match entries:
    case Nil{}:
      backwards = Equal.sym(Bool, Nat.is_eq(id, id), True{}, same_key(id))
      %backwards : {Finite.choose(~Nat, _, owner, None{}) == Some{owner} : Maybe<&2, Nat>}
      {==}
    case Con{(+key, +previous), +rest}:
      appended_owner_step(Nat.is_eq(id, key), previous, rest, id, owner, appended_owner(rest, id, owner))

def appended_unrecorded_owner(+entries: +List<Finite.Entry(Nat)>, +id: Nat, +owner: Nat,
  unrecorded: {Finite.find(~Nat, entries, id) == None{} : Maybe<&2, Nat>}) ->
  {Finite.find(~Nat, List.append(&2, Finite.Entry(Nat), entries, [(id, owner)]), id) == Some{owner} : Maybe<&2, Nat>}:
  Equal.trans(Maybe<&2, Nat>, Finite.find(~Nat, List.append(&2, Finite.Entry(Nat), entries, [(id, owner)]), id),
    W.preferred_owner(Finite.find(~Nat, entries, id), Some{owner}), Some{owner}, appended_owner(entries, id, owner),
    Equal.cong(Maybe<&2, Nat>, Maybe<&2, Nat>, (found => W.preferred_owner(found, Some{owner})),
      Finite.find(~Nat, entries, id), None{}, unrecorded))

def task_association_written(+id: Nat, +owner: Nat, +work: W.Work, +state: W.State,
  unrecorded: {W.root_owner(state, id) == None{} : Maybe<&2, Nat>}) ->
  {W.root_owner(W.associate_task_found(None{}, Some{work}, id, owner, state), id) == Some{owner} : Maybe<&2, Nat>}:
  W.State{works, +roots, graphs, next} = state
  appended_unrecorded_owner(roots, id, owner, unrecorded)

def graph_association_written(+id: Nat, +owner: Nat, +work: W.Work, +state: W.State,
  unrecorded: {W.graph_owner(state, id) == None{} : Maybe<&2, Nat>}) ->
  {W.graph_owner(W.associate_graph_found(None{}, Some{work}, id, owner, state), id) == Some{owner} : Maybe<&2, Nat>}:
  W.State{works, roots, +graphs, next} = state
  appended_unrecorded_owner(graphs, id, owner, unrecorded)

def task_associated(+id: Nat, +owner: Nat, +work: W.Work, +state: W.State,
  +unrecorded: {W.root_owner(state, id) == None{} : Maybe<&2, Nat>},
  existing: {W.find(state, owner) == Some{work} : Maybe<&2, W.Work>}) ->
  {W.root_owner(W.associate_task(id, owner, state), id) == Some{owner} : Maybe<&2, Nat>}:
  Equal.trans(Maybe<&2, Nat>, W.root_owner(W.associate_task(id, owner, state), id),
    W.root_owner(W.associate_task_found(None{}, W.find(state, owner), id, owner, state), id), Some{owner},
    Equal.cong(Maybe<&2, Nat>, Maybe<&2, Nat>,
      (found => W.root_owner(W.associate_task_found(found, W.find(state, owner), id, owner, state), id)),
      W.root_owner(state, id), None{}, unrecorded),
    Equal.trans(Maybe<&2, Nat>, W.root_owner(W.associate_task_found(None{}, W.find(state, owner), id, owner, state), id),
      W.root_owner(W.associate_task_found(None{}, Some{work}, id, owner, state), id), Some{owner},
      Equal.cong(Maybe<&2, W.Work>, Maybe<&2, Nat>,
        (found => W.root_owner(W.associate_task_found(None{}, found, id, owner, state), id)),
        W.find(state, owner), Some{work}, existing), task_association_written(id, owner, work, state, unrecorded)))

def graph_associated(+id: Nat, +owner: Nat, +work: W.Work, +state: W.State,
  +unrecorded: {W.graph_owner(state, id) == None{} : Maybe<&2, Nat>},
  existing: {W.find(state, owner) == Some{work} : Maybe<&2, W.Work>}) ->
  {W.graph_owner(W.associate_graph(id, owner, state), id) == Some{owner} : Maybe<&2, Nat>}:
  Equal.trans(Maybe<&2, Nat>, W.graph_owner(W.associate_graph(id, owner, state), id),
    W.graph_owner(W.associate_graph_found(None{}, W.find(state, owner), id, owner, state), id), Some{owner},
    Equal.cong(Maybe<&2, Nat>, Maybe<&2, Nat>,
      (found => W.graph_owner(W.associate_graph_found(found, W.find(state, owner), id, owner, state), id)),
      W.graph_owner(state, id), None{}, unrecorded),
    Equal.trans(Maybe<&2, Nat>, W.graph_owner(W.associate_graph_found(None{}, W.find(state, owner), id, owner, state), id),
      W.graph_owner(W.associate_graph_found(None{}, Some{work}, id, owner, state), id), Some{owner},
      Equal.cong(Maybe<&2, W.Work>, Maybe<&2, Nat>,
        (found => W.graph_owner(W.associate_graph_found(None{}, found, id, owner, state), id)),
        W.find(state, owner), Some{work}, existing), graph_association_written(id, owner, work, state, unrecorded)))

def lookup_put_step(+hit: Bool, +key: Nat, +previous: W.Work, +rest: +List<Finite.Entry(W.Work)>, +id: Nat, +work: W.Work,
  +observed: {Nat.is_eq(id, key) == hit : Bool},
  induction: {Finite.find(~W.Work, P.put_entries(rest, id, work), id) == Some{work} : Maybe<&2, W.Work>}) ->
  {Finite.find(~W.Work, P.put_selected(hit, key, previous, rest, work, P.put_entries(rest, id, work)), id) == Some{work} : Maybe<&2, W.Work>}:
  match hit:
    case True{}:
      backwards = Equal.sym(Bool, Nat.is_eq(id, key), True{}, observed)
      %backwards : {Finite.choose(~W.Work, _, work, Finite.find(~W.Work, rest, id)) == Some{work} : Maybe<&2, W.Work>}
      {==}
    case False{}:
      backwards = Equal.sym(Bool, Nat.is_eq(id, key), False{}, observed)
      %backwards : {Finite.choose(~W.Work, _, previous, Finite.find(~W.Work, P.put_entries(rest, id, work), id)) == Some{work} : Maybe<&2, W.Work>}
      induction

def lookup_put(entries: +List<Finite.Entry(W.Work)>, +id: Nat, +work: W.Work) ->
  {Finite.find(~W.Work, P.put_entries(entries, id, work), id) == Some{work} : Maybe<&2, W.Work>}:
  match entries:
    case Nil{}:
      backwards = Equal.sym(Bool, Nat.is_eq(id, id), True{}, same_key(id))
      %backwards : {Finite.choose(~W.Work, _, work, None{}) == Some{work} : Maybe<&2, W.Work>}
      {==}
    case Con{(+key, +previous), +rest}:
      lookup_put_step(Nat.is_eq(id, key), key, previous, rest, id, work, {==}, lookup_put(rest, id, work))

def written(+id: Nat, +work: W.Work, state: W.State, +next: Nat) ->
  {W.find(P.put(id, work, state, next), id) == Some{work} : Maybe<&2, W.Work>}:
  W.State{works, roots, graphs, previous_next} = state
  lookup_put(works, id, work)

def added(+id: Nat, +work: W.Work, +next: Nat, +state: W.State) ->
  {W.find(P.result_state(P.realize_calculation(W.Add{id, work, next}, state)), id) == Some{work} : Maybe<&2, W.Work>}:
  written(id, work, state, next)

def retitled(+id: Nat, +work: W.Work, +state: W.State) ->
  {W.find(P.result_state(P.realize_calculation(W.Retitle{id, work}, state)), id) == Some{work} : Maybe<&2, W.Work>}:
  written(id, work, state, W.next(state))

def roots_preserved(+change: W.Change, +state: W.State) ->
  {W.roots(P.result_state(P.realize_calculation(change, state))) == W.roots(state) : +List<Finite.Entry(Nat)>}:
  match change:
    case W.Add{id, work, next}:
      W.State{works, roots, graphs, previous} = state
      {==}
    case W.Retitle{id, work}:
      W.State{works, roots, graphs, next} = state
      {==}

def graphs_preserved(+change: W.Change, +state: W.State) ->
  {W.graphs(P.result_state(P.realize_calculation(change, state))) == W.graphs(state) : +List<Finite.Entry(Nat)>}:
  match change:
    case W.Add{id, work, next}:
      W.State{works, roots, graphs, previous} = state
      {==}
    case W.Retitle{id, work}:
      W.State{works, roots, graphs, next} = state
      {==}

def root_no_transfer(+id: Nat, +previous: Nat, +owner: Nat, +state: W.State,
  observed: {W.root_owner(state, id) == Some{previous} : Maybe<&2, Nat>}) ->
  {W.associate_task(id, owner, state) == state : W.State}:
  Equal.cong(Maybe<&2, Nat>, W.State, (found => W.associate_task_found(found, W.find(state, owner), id, owner, state)),
    W.root_owner(state, id), Some{previous}, observed)

def graph_removed(+id: Nat, +state: W.State) ->
  {W.graph_owner(W.dissociate_graph(id, state), id) == None{} : Maybe<&2, Nat>}:
  W.State{works, roots, graphs, next} = state
  Finite.removal_absence(~Nat, graphs, id)

def lineage_inheritance(+child: Nat, +parent: Nat, +lineage: +List<Nat>, +state: W.State,
  unrecorded: {W.root_owner(state, child) == None{} : Maybe<&2, Nat>}) ->
  {W.task_owner(state, child, parent <> lineage) == W.task_owner(state, parent, lineage) : Maybe<&2, Nat>}:
  Equal.cong(Maybe<&2, Nat>, Maybe<&2, Nat>, (found => W.task_owner_found(found, state, parent <> lineage)),
    W.root_owner(state, child), None{}, unrecorded)

def initial_valid() -> {W.valid(W.initial()) == True{} : Bool}:
  {==}

def task_creation_constructed(+body: J.Json) ->
  {Codec.construct(Codec.CreateTaskKind{}, body) ==
    W.CreateTask{Codec.number(J.get(body, "work_id")), J.text(J.get(body, "profile")),
      J.text_or(J.get(body, "reasoning"), "default"), D.user_content(J.get(body, "message"), J.get(body, "images")),
      Codec.settings(J.get(body, "settings")), J.boolean(J.get(body, "create_worktree"))} : W.Command}:
  {==}

def task_creation_encoded(+work: Nat, +profile: String, +reasoning: String, +message: D.UserContent, +settings: J.Json, +create_worktree: Bool) ->
  {Codec.command_json(W.CreateTask{work, profile, reasoning, message, settings, create_worktree}) ==
    J.Object{[J.Field{"op", J.Text{"create_work_task"}}, J.Field{"work_id", J.nat(work)}, J.Field{"profile", J.Text{profile}},
      J.Field{"reasoning", J.Text{reasoning}}, J.Field{"message", D.content_json(message)}, J.Field{"settings", settings},
      J.Field{"create_worktree", J.Boolean{create_worktree}}]} : J.Json}:
  {==}

def task_creation_omitted_worktree(+body: J.Json, absent: {J.get(body, "create_worktree") == J.Null{} : J.Json}) ->
  {Codec.construct(Codec.CreateTaskKind{}, body) ==
    W.CreateTask{Codec.number(J.get(body, "work_id")), J.text(J.get(body, "profile")),
      J.text_or(J.get(body, "reasoning"), "default"), D.user_content(J.get(body, "message"), J.get(body, "images")),
      Codec.settings(J.get(body, "settings")), False{}} : W.Command}:
  Equal.cong(J.Json, W.Command, (value => W.CreateTask{Codec.number(J.get(body, "work_id")), J.text(J.get(body, "profile")),
    J.text_or(J.get(body, "reasoning"), "default"), D.user_content(J.get(body, "message"), J.get(body, "images")), Codec.settings(J.get(body, "settings")), J.boolean(value)}),
    J.get(body, "create_worktree"), J.Null{}, absent)

def task_creation_delegated(work: Nat, profile: String, reasoning: String, message: D.UserContent, settings: J.Json, create_worktree: Bool, state: W.State) ->
  {W.resolve(W.CreateTask{work, profile, reasoning, message, settings, create_worktree}, state) ==
    W.Refuse{"task_creation_boundary", "Create Work Tasks through the harness feature operation."} : W.Resolution}:
  {==}

def task_creation() -> Contract.TaskCreation:
  Contract.TaskCreation{task_creation_constructed, task_creation_encoded, task_creation_omitted_worktree, task_creation_delegated}

def boundary() -> Contract.Boundary:
  Contract.Boundary{refinement, added, retitled, roots_preserved, graphs_preserved,
    task_associated, graph_associated, root_no_transfer, lineage_inheritance, graph_removed, task_creation()}
