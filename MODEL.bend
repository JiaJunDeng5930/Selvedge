import Base
import ./harness/MODEL.bend as Commands
import ./bendlib/json.bend as Json
import ./interaction/INPUT.bend as User
import ./interaction/presentation/MODEL.bend as View
import ./interaction/presentation/SURFACE.bend as Surface

# Opaque carriers keep clients independent of aggregate representations.
type Execution<-World: Data, -Decision: Data> is Type:
  Execution{
    initial: World,
    valid: World -> Bool,
    run: Commands.Input -> World -> Decision,
    meaning: Commands.Input -> World -> Decision,
    world: Decision -> World,
    reply: Decision -> Json.Json,
    effects: Decision -> +List<Commands.Effect()>,
    durable: Commands.Input -> Bool,
    initial_valid: {valid(initial) == True{} : Bool},
    preserves_valid: @state:World -> @input:Commands.Input ->
      @valid_state:{valid(state) == True{} : Bool} ->
      {valid(world(run(input, state))) == True{} : Bool},
    refinement: @+input:Commands.Input -> @+state:World ->
      {run(input, state) == meaning(input, state) : Decision},
    query_world: @+query:Commands.Query -> @+state:World ->
      {world(run(Commands.UserCommand{Commands.Observe{query}}, state)) == state : World},
    query_effects: @+query:Commands.Query -> @+state:World ->
      {effects(run(Commands.UserCommand{Commands.Observe{query}}, state)) == Nil{} : +List<Commands.Effect()>},
    query_not_durable: @query:Commands.Query ->
      {durable(Commands.UserCommand{Commands.Observe{query}}) == False{} : Bool},
    replay: +List<Commands.Input> -> World -> World,
    replay_valid: @+events:+List<Commands.Input> -> @+state:World ->
      @valid_state:{valid(state) == True{} : Bool} ->
      {valid(replay(events, state)) == True{} : Bool},
    query_replay: @+query:Commands.Query -> @+first:+List<Commands.Input> ->
      @+second:+List<Commands.Input> -> @+state:World ->
      {replay(List.append(&2, Commands.Input, first, Commands.UserCommand{Commands.Observe{query}} <> second), state) ==
        replay(List.append(&2, Commands.Input, first, second), state) : World}}

# Complete decision equality includes both the resulting state and effects.
type Application<-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data> is Type:
  Application{
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
    observe: View.Capacity -> State -> Surface.Surface,
    initial_program: @+world:World -> @+serial:Nat ->
      {program(initial(world, serial)) == world : World},
    snapshot_dispatch: @+serial:Nat -> @+world:World -> @+s:State ->
      {run(snapshot_event(serial, world), s) == snapshot(serial, world, s) : Decision},
    completion_dispatch: @+ticket:Nat -> @+serial:Nat -> @+world:World -> @+reply:Json.Json -> @+s:State ->
      {run(completed_event(ticket, serial, world, reply), s) == settle(lookup(ticket, s), serial, world, reply, s) : Decision},
    stale_snapshot: @+serial:Nat -> @+world:World -> @+s:State ->
      @stale:{Nat.is_lt(sequence(s), serial) == False{} : Bool} ->
      {snapshot(serial, world, s) == finish(s, Nil{}) : Decision},
    unknown_completion: @+serial:Nat -> @+world:World -> @+reply:Json.Json -> @+s:State ->
      {settle(None{}, serial, world, reply, s) == finish(s, Nil{}) : Decision}}

type Display<-World: Data, -ApplicationState: Data, -Input: Data, -Effect: Data, -State: Data, -Decision: Data, -Publication: Data, -Fields: Data, -Document: Data, -Initialize: World -> Nat -> ApplicationState, -Program: ApplicationState -> World> is Type:
  Display{
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
    retain: Fields -> Publication,
    initial_application: @+world:World -> @+serial:Nat ->
      {application(initial(world, serial)) == Initialize(world, serial) : ApplicationState},
    program_projection: @+s:State ->
      {program(s) == Program(application(s)) : World},
    pending_retention: @+capacity:Nat -> @+last:Nat -> @+s:State ->
      @published:{Bool.not(Nat.is_eq(last, 0n)) == True{} : Bool} ->
      @pending_state:{pending(s) == True{} : Bool} ->
      {publication(capacity, last, s) == retain(updates(s)) : Publication}}

def DisplayModel(-World: Data, -ApplicationState: Data, -Input: Data, -Effect: Data, -initialize: World -> Nat -> ApplicationState, -program: ApplicationState -> World) -> Type:
  &State:Data -> &Decision:Data -> &Publication:Data -> &Fields:Data -> &Document:Data ->
    Display<World, ApplicationState, Input, Effect, State, Decision, Publication, Fields, Document, initialize, program>

def application_initial(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, api: Application<World, State, Input, Decision, Pending, Effect>) -> World -> Nat -> State:
  Application{initial, user, snapshot_event, completed_event, run, state, effects, finish, program, sequence, lookup, snapshot, settle, observe, initial_program, snapshot_dispatch, completion_dispatch, stale_snapshot, unknown_completion} = api
  initial

def application_program(-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data, api: Application<World, State, Input, Decision, Pending, Effect>) -> State -> World:
  Application{initial, user, snapshot_event, completed_event, run, state, effects, finish, program, sequence, lookup, snapshot, settle, observe, initial_program, snapshot_dispatch, completion_dispatch, stale_snapshot, unknown_completion} = api
  program

type Interface<-World: Data, -State: Data, -Input: Data, -Decision: Data, -Pending: Data, -Effect: Data> is Type:
  Interface{
    application: Application<World, State, Input, Decision, Pending, Effect>,
    display: DisplayModel(World, State, Input, Effect,
      application_initial(World, State, Input, Decision, Pending, Effect, application),
      application_program(World, State, Input, Decision, Pending, Effect, application))}

def InterfaceModel(-World: Data) -> Type:
  &State:Data -> &Input:Data -> &Decision:Data -> &Pending:Data -> &Effect:Data ->
    Interface<World, State, Input, Decision, Pending, Effect>

type System<-World: Data, -Decision: Data> is Type:
  System{execution: Execution<World, Decision>, interface: InterfaceModel(World)}

def SystemModel() -> Type:
  &World:Data -> &Decision:Data -> System<World, Decision>


law system:
  SystemModel()
