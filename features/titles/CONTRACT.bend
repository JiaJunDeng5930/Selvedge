import Base
import ./MODEL.bend as A
import ./SPEC.bend as Spec
import ./PROGRAM.bend as Actual
import ./STATE.bend as State
import ../../harness/MODEL.bend as M
import ../../harness/features/MODEL.bend as F
import ../../harness/DOMAIN.bend as D
import ../../harness/conversation/TITLE.bend as Title
import ../../bendlib/component.bend as C
import ../../bendlib/association-map.bend as Finite

type Boundary is Type:
  Boundary{
    configuration: @+prompts:Title.Prompts -> @+world:M.World() ->
      {Actual.configure(prompts, world) == Spec.configure(prompts, world) : M.Decision()},
    configuration_written: @+prompts:Title.Prompts -> @+world:M.World() ->
      {A.prompts(State.registry(Spec.world(Actual.configure(prompts, world)))) == prompts : Title.Prompts},
    configuration_entries: @+prompts:Title.Prompts -> @+world:M.World() ->
      {A.entries(State.registry(Spec.world(Actual.configure(prompts, world)))) == A.entries(State.registry(world)) : +List<Finite.Entry(A.Entry)>},
    configuration_core: @+prompts:Title.Prompts -> @+world:M.World() ->
      {C.local(D.State, F.State(), Spec.world(Actual.configure(prompts, world))) == C.local(D.State, F.State(), world) : D.State},
    start: @+operation:Spec.Start -> @+decision:M.Decision() ->
      {Actual.start(operation, decision) == Spec.start(operation, decision) : M.Decision()},
    preparation: @+decision:M.Decision() ->
      {Actual.prepare(decision) == Spec.prepare(decision) : M.Decision()},
    completion: @+completion:A.Completion -> @+world:M.World() ->
      {Actual.complete(completion, world) == Spec.complete(completion, world) : M.Decision()},
    written: @+value:A.State -> @state:F.State() ->
      {F.titles(F.with_titles(value, state)) == value : A.State},
    unrelated: @value:A.State -> @+state:F.State() ->
      {F.with_titles(F.titles(state), F.with_titles(value, state)) == state : F.State()},
    completion_core: @+completion:A.Completion -> @+world:M.World() ->
      {C.local(D.State, F.State(), Spec.world(Actual.complete(completion, world))) == C.local(D.State, F.State(), world) : D.State},
    pending_recovery: @ticket:Nat -> @profile:D.Profile -> @prompt:String ->
      {A.recover_entry(A.Pending{ticket, profile, prompt}) == A.Failed{} : A.Entry}}
