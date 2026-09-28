import Base
import ../../FEATURES.bend as Features
import ../component.bend as Component
import ../../MODEL.bend as M
import ../../PROGRAM.bend as P
import ../../LAWS.bend as Laws
import ../../UI.bend as UI
import ../../INVARIANTS.bend as I
import ../architecture.bend as A
import ../json.bend as J
import ./observations.bend as ObservationsProof

def Laws.ui_submit_semantics(state, command, world):
  {==}

def Laws.ui_action_semantics(key, label, command, world):
  {==}

def Laws.ui_form_semantics(key, title, label, command, fields, world):
  {==}

def Laws.ui_current_surface(state, event, world, reply, effects):
  {==}

def Laws.ui_projection_world(input, decision):
  match input:
    case M.UserInterface{state, event}:
      Component.Decision{world, reply, effects} = decision
      {==}
    case M.UserCommand{command}: {==}
    case M.ModelCompleted{id, ticket, outcome}: {==}
    case M.ReasoningCompleted{id, ticket, outcome}: {==}
    case M.FeatureCompleted{completion}: {==}
    case M.ToolCompleted{id, ticket, value, error}: {==}
    case M.HookCompleted{id, ticket, outcome}: {==}
    case M.AfterCompleted{id, operation, ticket, outcome}: {==}
    case M.ApprovalCompleted{id, ticket, outcome}: {==}
    case M.Configure{environment}: {==}
    case M.Recover{}: {==}
    case M.Continue{}: {==}

def Laws.ui_projection_effects(input, decision):
  match input:
    case M.UserInterface{state, event}:
      Component.Decision{world, reply, effects} = decision
      {==}
    case M.UserCommand{command}: {==}
    case M.ModelCompleted{id, ticket, outcome}: {==}
    case M.ReasoningCompleted{id, ticket, outcome}: {==}
    case M.FeatureCompleted{completion}: {==}
    case M.ToolCompleted{id, ticket, value, error}: {==}
    case M.HookCompleted{id, ticket, outcome}: {==}
    case M.AfterCompleted{id, operation, ticket, outcome}: {==}
    case M.ApprovalCompleted{id, ticket, outcome}: {==}
    case M.Configure{environment}: {==}
    case M.Recover{}: {==}
    case M.Continue{}: {==}

def admitted_world(valid: Bool, change: Bool, +world: M.World(), reply: J.Json) ->
  {P.decision_world(P.admitted(valid, change, Component.Decision{world, reply, Nil{}}, world)) == world : M.World()}:
  match valid change:
    case True{} True{}: {==}
    case True{} False{}: {==}
    case False{} True{}: {==}
    case False{} False{}: {==}

def admitted_effects(valid: Bool, change: Bool, world: M.World(), reply: J.Json) ->
  {P.decision_effects(P.admitted(valid, change, Component.Decision{world, reply, Nil{}}, world)) == Nil{} : +List<M.Effect()>}:
  match valid change:
    case True{} True{}: {==}
    case True{} False{}: {==}
    case False{} True{}: {==}
    case False{} False{}: {==}

def refresh_reply(+state: M.ViewState, +world: M.World()) -> J.Json:
  P.decision_reply(UI.decorate(M.UserInterface{state, M.RefreshView{}}, P.observe(M.Describe{}, world)))

def Laws.ui_refresh_world(state, world):
  +reply = refresh_reply(state, world)
  +decision : M.Decision() = Component.Decision{world, reply, Nil{}}
  Laws.delivery_observation_world(False{}, P.checked(decision, world), world,
    admitted_world(I.world(world), I.decision(world, decision), world, reply))

def Laws.ui_refresh_effects(state, world):
  +reply = refresh_reply(state, world)
  +decision : M.Decision() = Component.Decision{world, reply, Nil{}}
  +checked = P.checked(decision, world)
  Laws.delivery_observation_effects(False{}, checked, world,
    admitted_effects(I.world(world), I.decision(world, decision), world, reply))

def Laws.ui_refresh_not_durable(state):
  {==}

def A.surface():
  A.UserSurface{
    (+state => +world => (Laws.ui_refresh_world(state, world), Laws.ui_refresh_effects(state, world))),
    (state => command => world => Laws.ui_submit_semantics(state, command, world)),
    (key => label => command => world => Laws.ui_action_semantics(key, label, command, world)),
    (key => title => label => command => fields => world => Laws.ui_form_semantics(key, title, label, command, fields, world)),
    (input => decision => Laws.ui_projection_world(input, decision)),
    (input => decision => Laws.ui_projection_effects(input, decision))}
