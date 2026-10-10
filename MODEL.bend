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
  Categories.Membership<Categories.Implementation<ExecutionOperations<World, Decision>>, execution_implementation(World, Decision)>

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
  Categories.Membership<Categories.Implementation<ApplicationOperations<World, State, Input, Decision, Pending, Effect>>, application_implementation(World, State, Input, Decision, Pending, Effect)>

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
  Categories.Membership<Categories.Implementation<DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>>, display_implementation(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, Initialize, Program)>

def display_is_composed(-World: Data, -ApplicationState: Data, -Input: Data, -Effect: Data, -State: Data, -Decision: Data, -Publication: Data, -Fields: Data, -Document: Data, -Initialize: World -> Nat -> ApplicationState, -Program: ApplicationState -> World) -> Categories.Inclusion<DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>, display(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, Initialize, Program), display_composed(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, Initialize, Program)>:
  Categories.Inclusion{ops => evidence => Categories.project_intersection_first(DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>, display_composed(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, Initialize, Program), display_retaining(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, Initialize, Program), ops, evidence)}

def display_is_retaining(-World: Data, -ApplicationState: Data, -Input: Data, -Effect: Data, -State: Data, -Decision: Data, -Publication: Data, -Fields: Data, -Document: Data, -Initialize: World -> Nat -> ApplicationState, -Program: ApplicationState -> World) -> Categories.Inclusion<DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>, display(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, Initialize, Program), display_retaining(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, Initialize, Program)>:
  Categories.Inclusion{ops => evidence => Categories.project_intersection_second(DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>, display_composed(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, Initialize, Program), display_retaining(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, Initialize, Program), ops, evidence)}

def DisplayModel(-World: Data, -ApplicationState: Data, -Input: Data, -Effect: Data, -initialize: World -> Nat -> ApplicationState, -program: ApplicationState -> World) -> Type:
  &State:Data -> &Decision:Data -> &Publication:Data -> &Fields:Data -> &Document:Data ->
    Display(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, initialize, program)

def application_field_initial(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, ops: ApplicationOperations<World, State, Input, Decision, Pending, Effect>) -> World -> Nat -> State:
  ApplicationOperations{initial, user, snapshot_event, completed_event, run, state, effects, finish, program, sequence, lookup, snapshot, settle, observe} = ops
  initial

def application_field_user(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, ops: ApplicationOperations<World, State, Input, Decision, Pending, Effect>) -> User.Input -> Input:
  ApplicationOperations{initial, user, snapshot_event, completed_event, run, state, effects, finish, program, sequence, lookup, snapshot, settle, observe} = ops
  user

def application_field_snapshot_event(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, ops: ApplicationOperations<World, State, Input, Decision, Pending, Effect>) -> Nat -> World -> Input:
  ApplicationOperations{initial, user, snapshot_event, completed_event, run, state, effects, finish, program, sequence, lookup, snapshot, settle, observe} = ops
  snapshot_event

def application_field_completed_event(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, ops: ApplicationOperations<World, State, Input, Decision, Pending, Effect>) -> Nat -> Nat -> World -> Json.Json -> Input:
  ApplicationOperations{initial, user, snapshot_event, completed_event, run, state, effects, finish, program, sequence, lookup, snapshot, settle, observe} = ops
  completed_event

def application_field_run(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, ops: ApplicationOperations<World, State, Input, Decision, Pending, Effect>) -> Input -> State -> Decision:
  ApplicationOperations{initial, user, snapshot_event, completed_event, run, state, effects, finish, program, sequence, lookup, snapshot, settle, observe} = ops
  run

def application_field_state(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, ops: ApplicationOperations<World, State, Input, Decision, Pending, Effect>) -> Decision -> State:
  ApplicationOperations{initial, user, snapshot_event, completed_event, run, state, effects, finish, program, sequence, lookup, snapshot, settle, observe} = ops
  state

def application_field_effects(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, ops: ApplicationOperations<World, State, Input, Decision, Pending, Effect>) -> Decision -> +List<Effect>:
  ApplicationOperations{initial, user, snapshot_event, completed_event, run, state, effects, finish, program, sequence, lookup, snapshot, settle, observe} = ops
  effects

def application_field_finish(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, ops: ApplicationOperations<World, State, Input, Decision, Pending, Effect>) -> State -> +List<Effect> -> Decision:
  ApplicationOperations{initial, user, snapshot_event, completed_event, run, state, effects, finish, program, sequence, lookup, snapshot, settle, observe} = ops
  finish

def application_field_program(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, ops: ApplicationOperations<World, State, Input, Decision, Pending, Effect>) -> State -> World:
  ApplicationOperations{initial, user, snapshot_event, completed_event, run, state, effects, finish, program, sequence, lookup, snapshot, settle, observe} = ops
  program

def application_field_sequence(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, ops: ApplicationOperations<World, State, Input, Decision, Pending, Effect>) -> State -> Nat:
  ApplicationOperations{initial, user, snapshot_event, completed_event, run, state, effects, finish, program, sequence, lookup, snapshot, settle, observe} = ops
  sequence

def application_field_lookup(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, ops: ApplicationOperations<World, State, Input, Decision, Pending, Effect>) -> Nat -> State -> Maybe<&2, Pending>:
  ApplicationOperations{initial, user, snapshot_event, completed_event, run, state, effects, finish, program, sequence, lookup, snapshot, settle, observe} = ops
  lookup

def application_field_snapshot(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, ops: ApplicationOperations<World, State, Input, Decision, Pending, Effect>) -> Nat -> World -> State -> Decision:
  ApplicationOperations{initial, user, snapshot_event, completed_event, run, state, effects, finish, program, sequence, lookup, snapshot, settle, observe} = ops
  snapshot

def application_field_settle(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, ops: ApplicationOperations<World, State, Input, Decision, Pending, Effect>) -> Maybe<&2, Pending> -> Nat -> World -> Json.Json -> State -> Decision:
  ApplicationOperations{initial, user, snapshot_event, completed_event, run, state, effects, finish, program, sequence, lookup, snapshot, settle, observe} = ops
  settle

def application_field_observe(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, ops: ApplicationOperations<World, State, Input, Decision, Pending, Effect>) -> View.Capacity -> State -> Surface.Surface:
  ApplicationOperations{initial, user, snapshot_event, completed_event, run, state, effects, finish, program, sequence, lookup, snapshot, settle, observe} = ops
  observe

type ApplicationFaithfulness<-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, -specification: ApplicationOperations<World, State, Input, Decision, Pending, Effect>, -operations: ApplicationOperations<World, State, Input, Decision, Pending, Effect>> is Type:
  ApplicationFaithfulness{
    initial: @+a0:World -> @+a1:Nat -> {application_field_initial(World, State, Input, Decision, Pending, Effect, operations)(a0, a1) == application_field_initial(World, State, Input, Decision, Pending, Effect, specification)(a0, a1) : State},
    user: @+a0:User.Input -> {application_field_user(World, State, Input, Decision, Pending, Effect, operations)(a0) == application_field_user(World, State, Input, Decision, Pending, Effect, specification)(a0) : Input},
    snapshot_event: @+a0:Nat -> @+a1:World -> {application_field_snapshot_event(World, State, Input, Decision, Pending, Effect, operations)(a0, a1) == application_field_snapshot_event(World, State, Input, Decision, Pending, Effect, specification)(a0, a1) : Input},
    completed_event: @+a0:Nat -> @+a1:Nat -> @+a2:World -> @+a3:Json.Json -> {application_field_completed_event(World, State, Input, Decision, Pending, Effect, operations)(a0, a1, a2, a3) == application_field_completed_event(World, State, Input, Decision, Pending, Effect, specification)(a0, a1, a2, a3) : Input},
    run: @+a0:Input -> @+a1:State -> {application_field_run(World, State, Input, Decision, Pending, Effect, operations)(a0, a1) == application_field_run(World, State, Input, Decision, Pending, Effect, specification)(a0, a1) : Decision},
    state: @+a0:Decision -> {application_field_state(World, State, Input, Decision, Pending, Effect, operations)(a0) == application_field_state(World, State, Input, Decision, Pending, Effect, specification)(a0) : State},
    effects: @+a0:Decision -> {application_field_effects(World, State, Input, Decision, Pending, Effect, operations)(a0) == application_field_effects(World, State, Input, Decision, Pending, Effect, specification)(a0) : +List<Effect>},
    finish: @+a0:State -> @+a1:+List<Effect> -> {application_field_finish(World, State, Input, Decision, Pending, Effect, operations)(a0, a1) == application_field_finish(World, State, Input, Decision, Pending, Effect, specification)(a0, a1) : Decision},
    program: @+a0:State -> {application_field_program(World, State, Input, Decision, Pending, Effect, operations)(a0) == application_field_program(World, State, Input, Decision, Pending, Effect, specification)(a0) : World},
    sequence: @+a0:State -> {application_field_sequence(World, State, Input, Decision, Pending, Effect, operations)(a0) == application_field_sequence(World, State, Input, Decision, Pending, Effect, specification)(a0) : Nat},
    lookup: @+a0:Nat -> @+a1:State -> {application_field_lookup(World, State, Input, Decision, Pending, Effect, operations)(a0, a1) == application_field_lookup(World, State, Input, Decision, Pending, Effect, specification)(a0, a1) : Maybe<&2, Pending>},
    snapshot: @+a0:Nat -> @+a1:World -> @+a2:State -> {application_field_snapshot(World, State, Input, Decision, Pending, Effect, operations)(a0, a1, a2) == application_field_snapshot(World, State, Input, Decision, Pending, Effect, specification)(a0, a1, a2) : Decision},
    settle: @+a0:Maybe<&2, Pending> -> @+a1:Nat -> @+a2:World -> @+a3:Json.Json -> @+a4:State -> {application_field_settle(World, State, Input, Decision, Pending, Effect, operations)(a0, a1, a2, a3, a4) == application_field_settle(World, State, Input, Decision, Pending, Effect, specification)(a0, a1, a2, a3, a4) : Decision},
    observe: @+a0:View.Capacity -> @+a1:State -> {application_field_observe(World, State, Input, Decision, Pending, Effect, operations)(a0, a1) == application_field_observe(World, State, Input, Decision, Pending, Effect, specification)(a0, a1) : Surface.Surface}}

def application_faithful(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, implementation: Categories.Implementation<ApplicationOperations<World, State, Input, Decision, Pending, Effect>>) -> Type:
  Categories.Implementation{specification, operations} = implementation
  ApplicationFaithfulness<World, State, Input, Decision, Pending, Effect, specification, operations>

def application_actual(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, implementation: Categories.Implementation<ApplicationOperations<World, State, Input, Decision, Pending, Effect>>) -> ApplicationOperations<World, State, Input, Decision, Pending, Effect>:
  Categories.Implementation{specification, operations} = implementation
  operations

def application_implementation(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, implementation: Categories.Implementation<ApplicationOperations<World, State, Input, Decision, Pending, Effect>>) -> Type:
  Categories.intersection(Categories.Implementation<ApplicationOperations<World, State, Input, Decision, Pending, Effect>>, application_faithful(World, State, Input, Decision, Pending, Effect), (candidate => application(World, State, Input, Decision, Pending, Effect, application_actual(World, State, Input, Decision, Pending, Effect, candidate))), implementation)

def application_operations(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, api: Application(World, State, Input, Decision, Pending, Effect)) -> Categories.Membership<ApplicationOperations<World, State, Input, Decision, Pending, Effect>, application(World, State, Input, Decision, Pending, Effect)>:
  Categories.Membership{implementation, evidence} = api
  Categories.Implementation{specification, operations} = implementation
  Categories.Intersection{faithfulness, properties} = evidence
  Categories.Membership{operations, properties}

def application_initial_from_operations(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, api: Categories.Membership<ApplicationOperations<World, State, Input, Decision, Pending, Effect>, application(World, State, Input, Decision, Pending, Effect)>) -> World -> Nat -> State:
  Categories.Membership{ops, evidence} = api
  ApplicationOperations{initial, user, snapshot_event, completed_event, run, state, effects, finish, program, sequence, lookup, snapshot, settle, observe} = ops
  initial

def application_initial(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, api: Application(World, State, Input, Decision, Pending, Effect)) -> World -> Nat -> State:
  application_initial_from_operations(World, State, Input, Decision, Pending, Effect, application_operations(World, State, Input, Decision, Pending, Effect, api))

def application_program_from_operations(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, api: Categories.Membership<ApplicationOperations<World, State, Input, Decision, Pending, Effect>, application(World, State, Input, Decision, Pending, Effect)>) -> State -> World:
  Categories.Membership{ops, evidence} = api
  ApplicationOperations{initial, user, snapshot_event, completed_event, run, state, effects, finish, program, sequence, lookup, snapshot, settle, observe} = ops
  program

def application_program(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, api: Application(World, State, Input, Decision, Pending, Effect)) -> State -> World:
  application_program_from_operations(World, State, Input, Decision, Pending, Effect, application_operations(World, State, Input, Decision, Pending, Effect, api))

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

def execution_field_initial(-World: Data, -Decision: Data, ops: ExecutionOperations<World, Decision>) -> World:
  ExecutionOperations{initial, valid, run, meaning, world, reply, effects, durable, replay} = ops
  initial

def execution_field_valid(-World: Data, -Decision: Data, ops: ExecutionOperations<World, Decision>) -> World -> Bool:
  ExecutionOperations{initial, valid, run, meaning, world, reply, effects, durable, replay} = ops
  valid

def execution_field_run(-World: Data, -Decision: Data, ops: ExecutionOperations<World, Decision>) -> Commands.Input -> World -> Decision:
  ExecutionOperations{initial, valid, run, meaning, world, reply, effects, durable, replay} = ops
  run

def execution_field_meaning(-World: Data, -Decision: Data, ops: ExecutionOperations<World, Decision>) -> Commands.Input -> World -> Decision:
  ExecutionOperations{initial, valid, run, meaning, world, reply, effects, durable, replay} = ops
  meaning

def execution_field_world(-World: Data, -Decision: Data, ops: ExecutionOperations<World, Decision>) -> Decision -> World:
  ExecutionOperations{initial, valid, run, meaning, world, reply, effects, durable, replay} = ops
  world

def execution_field_reply(-World: Data, -Decision: Data, ops: ExecutionOperations<World, Decision>) -> Decision -> Json.Json:
  ExecutionOperations{initial, valid, run, meaning, world, reply, effects, durable, replay} = ops
  reply

def execution_field_effects(-World: Data, -Decision: Data, ops: ExecutionOperations<World, Decision>) -> Decision -> +List<Commands.Effect()>:
  ExecutionOperations{initial, valid, run, meaning, world, reply, effects, durable, replay} = ops
  effects

def execution_field_durable(-World: Data, -Decision: Data, ops: ExecutionOperations<World, Decision>) -> Commands.Input -> Bool:
  ExecutionOperations{initial, valid, run, meaning, world, reply, effects, durable, replay} = ops
  durable

def execution_field_replay(-World: Data, -Decision: Data, ops: ExecutionOperations<World, Decision>) -> +List<Commands.Input> -> World -> World:
  ExecutionOperations{initial, valid, run, meaning, world, reply, effects, durable, replay} = ops
  replay

type ExecutionFaithfulness<-World: Data, -Decision: Data, -specification: ExecutionOperations<World, Decision>, -operations: ExecutionOperations<World, Decision>> is Type:
  ExecutionFaithfulness{
    initial: {execution_field_initial(World, Decision, operations) == execution_field_initial(World, Decision, specification) : World},
    valid: @+a0:World -> {execution_field_valid(World, Decision, operations)(a0) == execution_field_valid(World, Decision, specification)(a0) : Bool},
    run: @+a0:Commands.Input -> @+a1:World -> {execution_field_run(World, Decision, operations)(a0, a1) == execution_field_run(World, Decision, specification)(a0, a1) : Decision},
    meaning: @+a0:Commands.Input -> @+a1:World -> {execution_field_meaning(World, Decision, operations)(a0, a1) == execution_field_meaning(World, Decision, specification)(a0, a1) : Decision},
    world: @+a0:Decision -> {execution_field_world(World, Decision, operations)(a0) == execution_field_world(World, Decision, specification)(a0) : World},
    reply: @+a0:Decision -> {execution_field_reply(World, Decision, operations)(a0) == execution_field_reply(World, Decision, specification)(a0) : Json.Json},
    effects: @+a0:Decision -> {execution_field_effects(World, Decision, operations)(a0) == execution_field_effects(World, Decision, specification)(a0) : +List<Commands.Effect()>},
    durable: @+a0:Commands.Input -> {execution_field_durable(World, Decision, operations)(a0) == execution_field_durable(World, Decision, specification)(a0) : Bool},
    replay: @+a0:+List<Commands.Input> -> @+a1:World -> {execution_field_replay(World, Decision, operations)(a0, a1) == execution_field_replay(World, Decision, specification)(a0, a1) : World}}

def execution_faithful(-World: Data, -Decision: Data, implementation: Categories.Implementation<ExecutionOperations<World, Decision>>) -> Type:
  Categories.Implementation{specification, operations} = implementation
  ExecutionFaithfulness<World, Decision, specification, operations>

def execution_actual(-World: Data, -Decision: Data, implementation: Categories.Implementation<ExecutionOperations<World, Decision>>) -> ExecutionOperations<World, Decision>:
  Categories.Implementation{specification, operations} = implementation
  operations

def execution_implementation(-World: Data, -Decision: Data, implementation: Categories.Implementation<ExecutionOperations<World, Decision>>) -> Type:
  Categories.intersection(Categories.Implementation<ExecutionOperations<World, Decision>>, execution_faithful(World, Decision), (candidate => execution(World, Decision, execution_actual(World, Decision, candidate))), implementation)

def execution_operations(-World: Data, -Decision: Data, api: Execution(World, Decision)) -> Categories.Membership<ExecutionOperations<World, Decision>, execution(World, Decision)>:
  Categories.Membership{implementation, evidence} = api
  Categories.Implementation{specification, operations} = implementation
  Categories.Intersection{faithfulness, properties} = evidence
  Categories.Membership{operations, properties}

def display_field_initial(-World: Data, -ApplicationState: Data, -Input: Data, -Effect: Data, -State: Data, -Decision: Data, -Publication: Data, -Fields: Data, -Document: Data, ops: DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>) -> World -> Nat -> State:
  DisplayOperations{initial, application, program, run, state, effects, observe, publication, pending, updates, retain} = ops
  initial

def display_field_application(-World: Data, -ApplicationState: Data, -Input: Data, -Effect: Data, -State: Data, -Decision: Data, -Publication: Data, -Fields: Data, -Document: Data, ops: DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>) -> State -> ApplicationState:
  DisplayOperations{initial, application, program, run, state, effects, observe, publication, pending, updates, retain} = ops
  application

def display_field_program(-World: Data, -ApplicationState: Data, -Input: Data, -Effect: Data, -State: Data, -Decision: Data, -Publication: Data, -Fields: Data, -Document: Data, ops: DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>) -> State -> World:
  DisplayOperations{initial, application, program, run, state, effects, observe, publication, pending, updates, retain} = ops
  program

def display_field_run(-World: Data, -ApplicationState: Data, -Input: Data, -Effect: Data, -State: Data, -Decision: Data, -Publication: Data, -Fields: Data, -Document: Data, ops: DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>) -> Input -> State -> Decision:
  DisplayOperations{initial, application, program, run, state, effects, observe, publication, pending, updates, retain} = ops
  run

def display_field_state(-World: Data, -ApplicationState: Data, -Input: Data, -Effect: Data, -State: Data, -Decision: Data, -Publication: Data, -Fields: Data, -Document: Data, ops: DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>) -> Decision -> State:
  DisplayOperations{initial, application, program, run, state, effects, observe, publication, pending, updates, retain} = ops
  state

def display_field_effects(-World: Data, -ApplicationState: Data, -Input: Data, -Effect: Data, -State: Data, -Decision: Data, -Publication: Data, -Fields: Data, -Document: Data, ops: DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>) -> Decision -> +List<Effect>:
  DisplayOperations{initial, application, program, run, state, effects, observe, publication, pending, updates, retain} = ops
  effects

def display_field_observe(-World: Data, -ApplicationState: Data, -Input: Data, -Effect: Data, -State: Data, -Decision: Data, -Publication: Data, -Fields: Data, -Document: Data, ops: DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>) -> Nat -> State -> Document:
  DisplayOperations{initial, application, program, run, state, effects, observe, publication, pending, updates, retain} = ops
  observe

def display_field_publication(-World: Data, -ApplicationState: Data, -Input: Data, -Effect: Data, -State: Data, -Decision: Data, -Publication: Data, -Fields: Data, -Document: Data, ops: DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>) -> Nat -> Nat -> State -> Publication:
  DisplayOperations{initial, application, program, run, state, effects, observe, publication, pending, updates, retain} = ops
  publication

def display_field_pending(-World: Data, -ApplicationState: Data, -Input: Data, -Effect: Data, -State: Data, -Decision: Data, -Publication: Data, -Fields: Data, -Document: Data, ops: DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>) -> State -> Bool:
  DisplayOperations{initial, application, program, run, state, effects, observe, publication, pending, updates, retain} = ops
  pending

def display_field_updates(-World: Data, -ApplicationState: Data, -Input: Data, -Effect: Data, -State: Data, -Decision: Data, -Publication: Data, -Fields: Data, -Document: Data, ops: DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>) -> State -> Fields:
  DisplayOperations{initial, application, program, run, state, effects, observe, publication, pending, updates, retain} = ops
  updates

def display_field_retain(-World: Data, -ApplicationState: Data, -Input: Data, -Effect: Data, -State: Data, -Decision: Data, -Publication: Data, -Fields: Data, -Document: Data, ops: DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>) -> Fields -> Publication:
  DisplayOperations{initial, application, program, run, state, effects, observe, publication, pending, updates, retain} = ops
  retain

type DisplayFaithfulness<-World: Data, -ApplicationState: Data, -Input: Data, -Effect: Data, -State: Data, -Decision: Data, -Publication: Data, -Fields: Data, -Document: Data, -specification: DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>, -operations: DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>> is Type:
  DisplayFaithfulness{
    initial: @+a0:World -> @+a1:Nat -> {display_field_initial(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, operations)(a0, a1) == display_field_initial(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, specification)(a0, a1) : State},
    application: @+a0:State -> {display_field_application(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, operations)(a0) == display_field_application(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, specification)(a0) : ApplicationState},
    program: @+a0:State -> {display_field_program(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, operations)(a0) == display_field_program(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, specification)(a0) : World},
    run: @+a0:Input -> @+a1:State -> {display_field_run(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, operations)(a0, a1) == display_field_run(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, specification)(a0, a1) : Decision},
    state: @+a0:Decision -> {display_field_state(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, operations)(a0) == display_field_state(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, specification)(a0) : State},
    effects: @+a0:Decision -> {display_field_effects(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, operations)(a0) == display_field_effects(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, specification)(a0) : +List<Effect>},
    observe: @+a0:Nat -> @+a1:State -> {display_field_observe(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, operations)(a0, a1) == display_field_observe(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, specification)(a0, a1) : Document},
    publication: @+a0:Nat -> @+a1:Nat -> @+a2:State -> {display_field_publication(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, operations)(a0, a1, a2) == display_field_publication(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, specification)(a0, a1, a2) : Publication},
    pending: @+a0:State -> {display_field_pending(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, operations)(a0) == display_field_pending(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, specification)(a0) : Bool},
    updates: @+a0:State -> {display_field_updates(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, operations)(a0) == display_field_updates(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, specification)(a0) : Fields},
    retain: @+a0:Fields -> {display_field_retain(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, operations)(a0) == display_field_retain(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, specification)(a0) : Publication}}

def display_faithful(-World: Data, -ApplicationState: Data, -Input: Data, -Effect: Data, -State: Data, -Decision: Data, -Publication: Data, -Fields: Data, -Document: Data, implementation: Categories.Implementation<DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>>) -> Type:
  Categories.Implementation{specification, operations} = implementation
  DisplayFaithfulness<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, specification, operations>

def display_actual(-World: Data, -ApplicationState: Data, -Input: Data, -Effect: Data, -State: Data, -Decision: Data, -Publication: Data, -Fields: Data, -Document: Data, implementation: Categories.Implementation<DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>>) -> DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>:
  Categories.Implementation{specification, operations} = implementation
  operations

def display_implementation(-World: Data, -ApplicationState: Data, -Input: Data, -Effect: Data, -State: Data, -Decision: Data, -Publication: Data, -Fields: Data, -Document: Data, -Initialize: World -> Nat -> ApplicationState, -Program: ApplicationState -> World, implementation: Categories.Implementation<DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>>) -> Type:
  Categories.intersection(Categories.Implementation<DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>>, display_faithful(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document), (candidate => display(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, Initialize, Program, display_actual(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, candidate))), implementation)

def display_operations(-World: Data, -ApplicationState: Data, -Input: Data, -Effect: Data, -State: Data, -Decision: Data, -Publication: Data, -Fields: Data, -Document: Data, -Initialize: World -> Nat -> ApplicationState, -Program: ApplicationState -> World, api: Display(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, Initialize, Program)) -> Categories.Membership<DisplayOperations<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document>, display(World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, Initialize, Program)>:
  Categories.Membership{implementation, evidence} = api
  Categories.Implementation{specification, operations} = implementation
  Categories.Intersection{faithfulness, properties} = evidence
  Categories.Membership{operations, properties}
