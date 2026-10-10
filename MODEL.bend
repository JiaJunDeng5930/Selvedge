import Base
import ./harness/MODEL.bend as Commands
import ./bendlib/json.bend as Json
import ./interaction/INPUT.bend as User
import ./interaction/presentation/MODEL.bend as View
import ./interaction/presentation/SURFACE.bend as Surface

import ./bendlib/categories.bend as Categories

# Operations remain affine; categories index their actual function fields.
type ExecutionOperations<-World: Data, -Decision: Data> is Type:
  ExecutionOperations{
    initial: World,
    valid: World -> Bool,
    run: Commands.Input -> World -> Decision,
    meaning: Commands.Input -> World -> Decision,
    world: Decision -> World,
    reply: Decision -> Json.Json,
    effects: Decision -> +List<Commands.Effect()>,
    durable: Commands.Input -> Bool,
    replay: +List<Commands.Input> -> World -> World}

type ExecutionSafety<-World: Data, -Decision: Data, -initial: World, -valid: World -> Bool, -run: Commands.Input -> World -> Decision, -world: Decision -> World> is Type:
  ExecutionSafety{
    initial_valid: {valid(initial) == True{} : Bool},
    preserves_valid: @state:World -> @input:Commands.Input ->
      @valid_state:{valid(state) == True{} : Bool} ->
      {valid(world(run(input, state))) == True{} : Bool}}

def execution_safe(-World: Data, -Decision: Data, ops: ExecutionOperations<World, Decision>) -> Type:
  match ops:
    case ExecutionOperations{initial, valid, run, meaning, world, reply, effects, durable, replay}: ExecutionSafety<World, Decision, initial, valid, run, world>

type ExecutionRefinement<-World: Data, -Decision: Data, -run: Commands.Input -> World -> Decision, -meaning: Commands.Input -> World -> Decision> is Type:
  ExecutionRefinement{
    refinement: @+input:Commands.Input -> @+state:World ->
      {run(input, state) == meaning(input, state) : Decision}}

def execution_refined(-World: Data, -Decision: Data, ops: ExecutionOperations<World, Decision>) -> Type:
  match ops:
    case ExecutionOperations{initial, valid, run, meaning, world, reply, effects, durable, replay}: ExecutionRefinement<World, Decision, run, meaning>

type ExecutionObservation<-World: Data, -Decision: Data, -run: Commands.Input -> World -> Decision, -world: Decision -> World, -effects: Decision -> +List<Commands.Effect()>, -durable: Commands.Input -> Bool> is Type:
  ExecutionObservation{
    query_world: @+query:Commands.Query -> @+state:World ->
      {world(run(Commands.UserCommand{Commands.Observe{query}}, state)) == state : World},
    query_effects: @+query:Commands.Query -> @+state:World ->
      {effects(run(Commands.UserCommand{Commands.Observe{query}}, state)) == Nil{} : +List<Commands.Effect()>},
    query_not_durable: @query:Commands.Query ->
      {durable(Commands.UserCommand{Commands.Observe{query}}) == False{} : Bool}}

def execution_observational(-World: Data, -Decision: Data, ops: ExecutionOperations<World, Decision>) -> Type:
  match ops:
    case ExecutionOperations{initial, valid, run, meaning, world, reply, effects, durable, replay}: ExecutionObservation<World, Decision, run, world, effects, durable>

type ExecutionHistory<-World: Data, -valid: World -> Bool, -replay: +List<Commands.Input> -> World -> World> is Type:
  ExecutionHistory{
    replay_valid: @+events:+List<Commands.Input> -> @+state:World ->
      @valid_state:{valid(state) == True{} : Bool} ->
      {valid(replay(events, state)) == True{} : Bool},
    query_replay: @+query:Commands.Query -> @+first:+List<Commands.Input> ->
      @+second:+List<Commands.Input> -> @+state:World ->
      {replay(List.append(&2, Commands.Input, first, Commands.UserCommand{Commands.Observe{query}} <> second), state) ==
        replay(List.append(&2, Commands.Input, first, second), state) : World}}

def execution_journaled(-World: Data, -Decision: Data, ops: ExecutionOperations<World, Decision>) -> Type:
  match ops:
    case ExecutionOperations{initial, valid, run, meaning, world, reply, effects, durable, replay}: ExecutionHistory<World, valid, replay>

def execution(-World: Data, -Decision: Data, ops: ExecutionOperations<World, Decision>) -> Type:
  Categories.intersection(ExecutionOperations<World, Decision>, execution_safe(World, Decision), (ops => Categories.intersection(ExecutionOperations<World, Decision>, execution_refined(World, Decision), (ops => Categories.intersection(ExecutionOperations<World, Decision>, execution_observational(World, Decision), execution_journaled(World, Decision), ops)), ops)), ops)

def Execution(-World: Data, -Decision: Data) -> Type:
  Categories.Membership<ExecutionOperations<World, Decision>, execution(World, Decision)>

def execution_is_safe(-World: Data, -Decision: Data) -> Categories.Inclusion<ExecutionOperations<World, Decision>, execution(World, Decision), execution_safe(World, Decision)>:
  Categories.Inclusion{ops => evidence => Categories.project_intersection_first(ExecutionOperations<World, Decision>, execution_safe(World, Decision), (ops => Categories.intersection(ExecutionOperations<World, Decision>, execution_refined(World, Decision), (ops => Categories.intersection(ExecutionOperations<World, Decision>, execution_observational(World, Decision), execution_journaled(World, Decision), ops)), ops)), ops, evidence)}

def execution_is_refined(-World: Data, -Decision: Data) -> Categories.Inclusion<ExecutionOperations<World, Decision>, execution(World, Decision), execution_refined(World, Decision)>:
  Categories.Inclusion{ops => evidence => Categories.project_intersection_first(ExecutionOperations<World, Decision>, execution_refined(World, Decision), (ops => Categories.intersection(ExecutionOperations<World, Decision>, execution_observational(World, Decision), execution_journaled(World, Decision), ops)), ops, Categories.project_intersection_second(ExecutionOperations<World, Decision>, execution_safe(World, Decision), (ops => Categories.intersection(ExecutionOperations<World, Decision>, execution_refined(World, Decision), (ops => Categories.intersection(ExecutionOperations<World, Decision>, execution_observational(World, Decision), execution_journaled(World, Decision), ops)), ops)), ops, evidence))}

def execution_is_observational(-World: Data, -Decision: Data) -> Categories.Inclusion<ExecutionOperations<World, Decision>, execution(World, Decision), execution_observational(World, Decision)>:
  Categories.Inclusion{ops => evidence => Categories.project_intersection_first(ExecutionOperations<World, Decision>, execution_observational(World, Decision), execution_journaled(World, Decision), ops, Categories.project_intersection_second(ExecutionOperations<World, Decision>, execution_refined(World, Decision), (ops => Categories.intersection(ExecutionOperations<World, Decision>, execution_observational(World, Decision), execution_journaled(World, Decision), ops)), ops, Categories.project_intersection_second(ExecutionOperations<World, Decision>, execution_safe(World, Decision), (ops => Categories.intersection(ExecutionOperations<World, Decision>, execution_refined(World, Decision), (ops => Categories.intersection(ExecutionOperations<World, Decision>, execution_observational(World, Decision), execution_journaled(World, Decision), ops)), ops)), ops, evidence)))}

def execution_is_journaled(-World: Data, -Decision: Data) -> Categories.Inclusion<ExecutionOperations<World, Decision>, execution(World, Decision), execution_journaled(World, Decision)>:
  Categories.Inclusion{ops => evidence => Categories.project_intersection_second(ExecutionOperations<World, Decision>, execution_observational(World, Decision), execution_journaled(World, Decision), ops, Categories.project_intersection_second(ExecutionOperations<World, Decision>, execution_refined(World, Decision), (ops => Categories.intersection(ExecutionOperations<World, Decision>, execution_observational(World, Decision), execution_journaled(World, Decision), ops)), ops, Categories.project_intersection_second(ExecutionOperations<World, Decision>, execution_safe(World, Decision), (ops => Categories.intersection(ExecutionOperations<World, Decision>, execution_refined(World, Decision), (ops => Categories.intersection(ExecutionOperations<World, Decision>, execution_observational(World, Decision), execution_journaled(World, Decision), ops)), ops)), ops, evidence)))}

type ApplicationOperations<-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data> is Type:
  ApplicationOperations{
    initial: World -> Nat -> State,
    user: User.Input -> Input,
    snapshot_event: Nat -> World -> Input,
    completed_event: Nat -> Nat -> World -> Json.Json -> Input,
    run: Input -> State -> Decision,
    state: Decision -> State,
    effects: Decision -> +List<Effect>,
    finish: State -> +List<Effect> -> Decision,
    program: State -> World,
    sequence: State -> Nat,
    lookup: Nat -> State -> Maybe<&2, Pending>,
    snapshot: Nat -> World -> State -> Decision,
    settle: Maybe<&2, Pending> -> Nat -> World -> Json.Json -> State -> Decision,
    observe: View.Capacity -> State -> Surface.Surface}

type ApplicationInitialization<-World: Data, -State: Data, -initial: World -> Nat -> State, -program: State -> World> is Type:
  ApplicationInitialization{
    initial_program: @+world:World -> @+serial:Nat ->
      {program(initial(world, serial)) == world : World}}

def application_initialized(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, ops: ApplicationOperations<World, State, Input, Decision, Pending, Effect>) -> Type:
  match ops:
    case ApplicationOperations{initial, user, snapshot_event, completed_event, run, state, effects, finish, program, sequence, lookup, snapshot, settle, observe}: ApplicationInitialization<World, State, initial, program>

type ApplicationCorrelation<-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -snapshot_event: Nat -> World -> Input, -completed_event: Nat -> Nat -> World -> Json.Json -> Input, -run: Input -> State -> Decision, -lookup: Nat -> State -> Maybe<&2, Pending>, -snapshot: Nat -> World -> State -> Decision, -settle: Maybe<&2, Pending> -> Nat -> World -> Json.Json -> State -> Decision> is Type:
  ApplicationCorrelation{
    snapshot_dispatch: @+serial:Nat -> @+world:World -> @+s:State ->
      {run(snapshot_event(serial, world), s) == snapshot(serial, world, s) : Decision},
    completion_dispatch: @+ticket:Nat -> @+serial:Nat -> @+world:World -> @+reply:Json.Json -> @+s:State ->
      {run(completed_event(ticket, serial, world, reply), s) == settle(lookup(ticket, s), serial, world, reply, s) : Decision}}

def application_correlated(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, ops: ApplicationOperations<World, State, Input, Decision, Pending, Effect>) -> Type:
  match ops:
    case ApplicationOperations{initial, user, snapshot_event, completed_event, run, state, effects, finish, program, sequence, lookup, snapshot, settle, observe}: ApplicationCorrelation<World, State, Input, Decision, Pending, snapshot_event, completed_event, run, lookup, snapshot, settle>

type ApplicationOrdering<-World: Data, -State: Data, -Decision: Data, -Pending: Data, -Effect: Data, -finish: State -> +List<Effect> -> Decision, -sequence: State -> Nat, -snapshot: Nat -> World -> State -> Decision, -settle: Maybe<&2, Pending> -> Nat -> World -> Json.Json -> State -> Decision> is Type:
  ApplicationOrdering{
    stale_snapshot: @+serial:Nat -> @+world:World -> @+s:State ->
      @stale:{Nat.is_lt(sequence(s), serial) == False{} : Bool} ->
      {snapshot(serial, world, s) == finish(s, Nil{}) : Decision},
    unknown_completion: @+serial:Nat -> @+world:World -> @+reply:Json.Json -> @+s:State ->
      {settle(None{}, serial, world, reply, s) == finish(s, Nil{}) : Decision}}

def application_ordered(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, ops: ApplicationOperations<World, State, Input, Decision, Pending, Effect>) -> Type:
  match ops:
    case ApplicationOperations{initial, user, snapshot_event, completed_event, run, state, effects, finish, program, sequence, lookup, snapshot, settle, observe}: ApplicationOrdering<World, State, Decision, Pending, Effect, finish, sequence, snapshot, settle>

def application(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, ops: ApplicationOperations<World, State, Input, Decision, Pending, Effect>) -> Type:
  Categories.intersection(ApplicationOperations<World, State, Input, Decision, Pending, Effect>, application_initialized(World, State, Input, Decision, Pending, Effect), (ops => Categories.intersection(ApplicationOperations<World, State, Input, Decision, Pending, Effect>, application_correlated(World, State, Input, Decision, Pending, Effect), application_ordered(World, State, Input, Decision, Pending, Effect), ops)), ops)

def Application(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data) -> Type:
  Categories.Membership<ApplicationOperations<World, State, Input, Decision, Pending, Effect>, application(World, State, Input, Decision, Pending, Effect)>

def application_is_initialized(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data) -> Categories.Inclusion<ApplicationOperations<World, State, Input, Decision, Pending, Effect>, application(World, State, Input, Decision, Pending, Effect), application_initialized(World, State, Input, Decision, Pending, Effect)>:
  Categories.Inclusion{ops => evidence => Categories.project_intersection_first(ApplicationOperations<World, State, Input, Decision, Pending, Effect>, application_initialized(World, State, Input, Decision, Pending, Effect), (ops => Categories.intersection(ApplicationOperations<World, State, Input, Decision, Pending, Effect>, application_correlated(World, State, Input, Decision, Pending, Effect), application_ordered(World, State, Input, Decision, Pending, Effect), ops)), ops, evidence)}

def application_is_correlated(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data) -> Categories.Inclusion<ApplicationOperations<World, State, Input, Decision, Pending, Effect>, application(World, State, Input, Decision, Pending, Effect), application_correlated(World, State, Input, Decision, Pending, Effect)>:
  Categories.Inclusion{ops => evidence => Categories.project_intersection_first(ApplicationOperations<World, State, Input, Decision, Pending, Effect>, application_correlated(World, State, Input, Decision, Pending, Effect), application_ordered(World, State, Input, Decision, Pending, Effect), ops, Categories.project_intersection_second(ApplicationOperations<World, State, Input, Decision, Pending, Effect>, application_initialized(World, State, Input, Decision, Pending, Effect), (ops => Categories.intersection(ApplicationOperations<World, State, Input, Decision, Pending, Effect>, application_correlated(World, State, Input, Decision, Pending, Effect), application_ordered(World, State, Input, Decision, Pending, Effect), ops)), ops, evidence))}

def application_is_ordered(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data) -> Categories.Inclusion<ApplicationOperations<World, State, Input, Decision, Pending, Effect>, application(World, State, Input, Decision, Pending, Effect), application_ordered(World, State, Input, Decision, Pending, Effect)>:
  Categories.Inclusion{ops => evidence => Categories.project_intersection_second(ApplicationOperations<World, State, Input, Decision, Pending, Effect>, application_correlated(World, State, Input, Decision, Pending, Effect), application_ordered(World, State, Input, Decision, Pending, Effect), ops, Categories.project_intersection_second(ApplicationOperations<World, State, Input, Decision, Pending, Effect>, application_initialized(World, State, Input, Decision, Pending, Effect), (ops => Categories.intersection(ApplicationOperations<World, State, Input, Decision, Pending, Effect>, application_correlated(World, State, Input, Decision, Pending, Effect), application_ordered(World, State, Input, Decision, Pending, Effect), ops)), ops, evidence))}

type DisplayOperations<-World: Data, -ApplicationState: Data, -Input: Data, -Effect: Data, -State: Data, -Decision: Data, -Publication: Data, -Fields: Data, -Document: Data> is Type:
  DisplayOperations{
    initial: World -> Nat -> State,
    application: State -> ApplicationState,
    program: State -> World,
    run: Input -> State -> Decision,
    state: Decision -> State,
    effects: Decision -> +List<Effect>,
    observe: Nat -> State -> Document,
    publication: Nat -> Nat -> State -> Publication,
    pending: State -> Bool,
    updates: State -> Fields,
    retain: Fields -> Publication}

type DisplayComposition<-World: Data, -ApplicationState: Data, -State: Data, -initial: World -> Nat -> State, -application: State -> ApplicationState, -program: State -> World, -Initialize: World -> Nat -> ApplicationState, -Program: ApplicationState -> World> is Type:
  DisplayComposition{
    initial_application: @+world:World -> @+serial:Nat ->
      {application(initial(world, serial)) == Initialize(world, serial) : ApplicationState},
    program_projection: @+s:State ->
      {program(s) == Program(application(s)) : World}}

def display_composed(-World: Data, -ApplicationState: Data, -Input: Data, -Effect: Data, -State: Data, -Decision: Data, -Publication: Data, -Fields: Data, -Document: Data, -Initialize: World -> Nat -> ApplicationState, -Program: ApplicationState -> World, ops: DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>) -> Type:
  match ops:
    case DisplayOperations{initial, application, program, run, state, effects, observe, publication, pending, updates, retain}: DisplayComposition<World, ApplicationState, State, initial, application, program, Initialize, Program>

type DisplayRetention<-State: Data, -Publication: Data, -Fields: Data, -publication: Nat -> Nat -> State -> Publication, -pending: State -> Bool, -updates: State -> Fields, -retain: Fields -> Publication> is Type:
  DisplayRetention{
    pending_retention: @+capacity:Nat -> @+last:Nat -> @+s:State ->
      @published:{Bool.not(Nat.is_eq(last, 0n)) == True{} : Bool} ->
      @pending_state:{pending(s) == True{} : Bool} ->
      {publication(capacity, last, s) == retain(updates(s)) : Publication}}

def display_retaining(-World: Data, -ApplicationState: Data, -Input: Data, -Effect: Data, -State: Data, -Decision: Data, -Publication: Data, -Fields: Data, -Document: Data, -Initialize: World -> Nat -> ApplicationState, -Program: ApplicationState -> World, ops: DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>) -> Type:
  match ops:
    case DisplayOperations{initial, application, program, run, state, effects, observe, publication, pending, updates, retain}: DisplayRetention<State, Publication, Fields, publication, pending, updates, retain>

def display(-World: Data, -ApplicationState: Data, -Input: Data, -Effect: Data, -State: Data, -Decision: Data, -Publication: Data, -Fields: Data, -Document: Data, -Initialize: World -> Nat -> ApplicationState, -Program: ApplicationState -> World, ops: DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>) -> Type:
  Categories.intersection(DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>, display_composed(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, Initialize, Program), display_retaining(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, Initialize, Program), ops)

def Display(-World: Data, -ApplicationState: Data, -Input: Data, -Effect: Data, -State: Data, -Decision: Data, -Publication: Data, -Fields: Data, -Document: Data, -Initialize: World -> Nat -> ApplicationState, -Program: ApplicationState -> World) -> Type:
  Categories.Membership<DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>, display(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, Initialize, Program)>

def display_is_composed(-World: Data, -ApplicationState: Data, -Input: Data, -Effect: Data, -State: Data, -Decision: Data, -Publication: Data, -Fields: Data, -Document: Data, -Initialize: World -> Nat -> ApplicationState, -Program: ApplicationState -> World) -> Categories.Inclusion<DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>, display(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, Initialize, Program), display_composed(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, Initialize, Program)>:
  Categories.Inclusion{ops => evidence => Categories.project_intersection_first(DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>, display_composed(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, Initialize, Program), display_retaining(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, Initialize, Program), ops, evidence)}

def display_is_retaining(-World: Data, -ApplicationState: Data, -Input: Data, -Effect: Data, -State: Data, -Decision: Data, -Publication: Data, -Fields: Data, -Document: Data, -Initialize: World -> Nat -> ApplicationState, -Program: ApplicationState -> World) -> Categories.Inclusion<DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>, display(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, Initialize, Program), display_retaining(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, Initialize, Program)>:
  Categories.Inclusion{ops => evidence => Categories.project_intersection_second(DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>, display_composed(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, Initialize, Program), display_retaining(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, Initialize, Program), ops, evidence)}

def DisplayModel(-World: Data, -ApplicationState: Data, -Input: Data, -Effect: Data, -initialize: World -> Nat -> ApplicationState, -program: ApplicationState -> World) -> Type:
  &State:Data -> &Decision:Data -> &Publication:Data -> &Fields:Data -> &Document:Data ->
    Display(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, initialize, program)

def application_initial(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, api: Application(World, State, Input, Decision, Pending, Effect)) -> World -> Nat -> State:
  Categories.Membership{ops, evidence} = api
  ApplicationOperations{initial, user, snapshot_event, completed_event, run, state, effects, finish, program, sequence, lookup, snapshot, settle, observe} = ops
  initial

def application_program(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, api: Application(World, State, Input, Decision, Pending, Effect)) -> State -> World:
  Categories.Membership{ops, evidence} = api
  ApplicationOperations{initial, user, snapshot_event, completed_event, run, state, effects, finish, program, sequence, lookup, snapshot, settle, observe} = ops
  program

type Interface<-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data> is Type:
  Interface{
    application: Application(World, State, Input, Decision, Pending, Effect),
    display: DisplayModel(World, State, Input, Effect,
      application_initial(World, State, Input, Decision, Pending, Effect, application),
      application_program(World, State, Input, Decision, Pending, Effect, application))}

def InterfaceModel(-World: Data) -> Type:
  &State:Data -> &Input:Data -> &Decision:Data -> &Pending:Data -> &Effect:Data ->
    Interface<World, State, Input, Decision, Pending, Effect>

type System<-World: Data, -Decision: Data> is Type:
  System{execution: Execution(World, Decision), interface: InterfaceModel(World)}

def SystemModel() -> Type:
  &World:Data -> &Decision:Data -> System<World, Decision>


law system:
  SystemModel()
