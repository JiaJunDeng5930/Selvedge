import Base
import ./MODEL.bend as A
import ./STATE.bend as S
import ./SPEC.bend as Spec
import ./PROGRAM.bend as Actual
import ./CONTRACT.bend as Contract
import ../../harness/MODEL.bend as M
import ../../harness/DOMAIN.bend as D
import ../../harness/features/MODEL.bend as F
import ../../bendlib/component.bend as C
import ../../bendlib/association-map.bend as Finite
import ../../harness/conversation/TITLE.bend as Title

def configuration(+prompts: Title.Prompts, +world: M.World()) ->
  {Actual.configure(prompts, world) == Spec.configure(prompts, world) : M.Decision()}:
  match world:
    case C.Frame{core, features}: {==}

def start(+operation: Spec.Start, +decision: M.Decision()) ->
  {Actual.start(operation, decision) == Spec.start(operation, decision) : M.Decision()}:
  match operation decision:
    case Spec.Skip{} decision: {==}
    case Spec.Generate{id, ticket, profile, prompt} C.Decision{C.Frame{core, features}, reply, effects}: {==}

def tasks(+values: +List<D.Task>, +decision: M.Decision()) ->
  {Spec.prepare_tasks(~Actual.start, values, decision) == Spec.prepare_tasks(~Spec.start, values, decision) : M.Decision()}:
  match values:
    case Nil{}: {==}
    case Con{+task, +rest}:
      +operation = Spec.resolve(task, Spec.world(decision))
      +actual = Actual.start(operation, decision)
      +required = Spec.start(operation, decision)
      Equal.trans(M.Decision(), Spec.prepare_tasks(~Actual.start, rest, actual),
        Spec.prepare_tasks(~Spec.start, rest, actual), Spec.prepare_tasks(~Spec.start, rest, required),
        tasks(rest, actual), Equal.cong(M.Decision(), M.Decision(), (value => Spec.prepare_tasks(~Spec.start, rest, value)), actual, required, start(operation, decision)))

def preparation(+decision: M.Decision()) ->
  {Actual.prepare(decision) == Spec.prepare(decision) : M.Decision()}:
  tasks(S.tasks(Spec.world(decision)), decision)

def complete_selected(+current: Bool, +id: Nat, +outcome: A.Outcome, +world: M.World()) ->
  {Actual.complete_selected(current, id, outcome, world) == Spec.accepted(current, id, outcome, world) : M.Decision()}:
  match current world:
    case False{} world: {==}
    case True{} C.Frame{core, features}: {==}

def completion(+completion: A.Completion, +world: M.World()) ->
  {Actual.complete(completion, world) == Spec.complete(completion, world) : M.Decision()}:
  A.Completed{+id, ticket, outcome} = completion
  complete_selected(S.correlated(A.find(S.registry(world), id), ticket), id, outcome, world)

def written(+value: A.State, state: F.State()) ->
  {F.titles(F.with_titles(value, state)) == value : A.State}:
  match state:
    case C.Frame{board, C.Frame{chatgpt, C.Frame{graph, C.Frame{compaction, C.Frame{worktree, C.Frame{remote, C.Frame{work, C.Frame{previous, rest}}}}}}}}: {==}

def unrelated(value: A.State, +state: F.State()) ->
  {F.with_titles(F.titles(state), F.with_titles(value, state)) == state : F.State()}:
  match state:
    case C.Frame{board, C.Frame{chatgpt, C.Frame{graph, C.Frame{compaction, C.Frame{worktree, C.Frame{remote, C.Frame{work, C.Frame{previous, rest}}}}}}}}: {==}

def prompts_written(+value: Title.Prompts, state: A.State) ->
  {A.prompts(A.with_prompts(value, state)) == value : Title.Prompts}:
  match state:
    case A.State{entries, revision, prompts}: {==}

def entries_retained(value: Title.Prompts, +state: A.State) ->
  {A.entries(A.with_prompts(value, state)) == A.entries(state) : +List<Finite.Entry(A.Entry)>}:
  match state:
    case A.State{entries, revision, prompts}: {==}

def configuration_written(+prompts: Title.Prompts, +world: M.World()) ->
  {A.prompts(S.registry(Spec.world(Actual.configure(prompts, world)))) == prompts : Title.Prompts}:
  C.Frame{core, +features} = world
  +updated = A.with_prompts(prompts, F.titles(features))
  +found = F.titles(F.with_titles(updated, features))
  Equal.trans(Title.Prompts, A.prompts(found), A.prompts(updated), prompts,
    Equal.cong(A.State, Title.Prompts, A.prompts, found, updated, written(updated, features)),
    prompts_written(prompts, F.titles(features)))

def configuration_entries(+prompts: Title.Prompts, +world: M.World()) ->
  {A.entries(S.registry(Spec.world(Actual.configure(prompts, world)))) == A.entries(S.registry(world)) : +List<Finite.Entry(A.Entry)>}:
  C.Frame{core, +features} = world
  +updated = A.with_prompts(prompts, F.titles(features))
  +found = F.titles(F.with_titles(updated, features))
  Equal.trans(+List<Finite.Entry(A.Entry)>, A.entries(found), A.entries(updated), A.entries(F.titles(features)),
    Equal.cong(A.State, +List<Finite.Entry(A.Entry)>, value => A.entries(value), found, updated, written(updated, features)),
    entries_retained(prompts, F.titles(features)))

def configuration_core(+prompts: Title.Prompts, +world: M.World()) ->
  {C.local(D.State, F.State(), Spec.world(Actual.configure(prompts, world))) == C.local(D.State, F.State(), world) : D.State}:
  match world:
    case C.Frame{core, features}: {==}

def selected_core(+current: Bool, +id: Nat, +outcome: A.Outcome, +world: M.World()) ->
  {C.local(D.State, F.State(), Spec.world(Actual.complete_selected(current, id, outcome, world))) == C.local(D.State, F.State(), world) : D.State}:
  match current world:
    case False{} C.Frame{core, features}: {==}
    case True{} C.Frame{core, features}: {==}

def completion_core(+completion: A.Completion, +world: M.World()) ->
  {C.local(D.State, F.State(), Spec.world(Actual.complete(completion, world))) == C.local(D.State, F.State(), world) : D.State}:
  A.Completed{+id, ticket, outcome} = completion
  selected_core(S.correlated(A.find(S.registry(world), id), ticket), id, outcome, world)

def boundary() -> Contract.Boundary:
  Contract.Boundary{configuration, configuration_written, configuration_entries, configuration_core, start, preparation, completion, written, unrelated, completion_core, ticket => profile => prompt => {==}}
