import Base
import ../ui-identity.bend as Identity
import ../interface.bend as Interface
import ../SYSTEM.bend as Core
import ../user-experience.bend as E
import ../client-services.bend as Services
import ../../bendlib/board-state.bend as Board
import ../../bendlib/json.bend as J
import ../board-capability-laws.bend as Rule
import ../ui-world.bend as View
import ../user-input.bend as U
import ../../BOARD.bend as B
import ../../MODEL.bend as M

def card_opens_details(+id: Nat, card: B.Card, route: U.Route, now: U32, world: M.World()) ->
  {Rule.opening(View.card_scene(id, card, route, now, world)) ==
    U.Activate{U.OpenPanel{U.CardDetails{id}, "card/" ++ Nat.show(id)}} : U.Input}:
  B.Card{revision, draft, task, archived, created, updated, enrichment, error, pinned} = card
  {==}

def actual_card_errors(+card: B.Card, +parent: Identity.Key) ->
  {Interface.card_error_observations(card, parent) ==
        [Interface.project_fact(Identity.Part{parent, "enrichment"}, "生成", Interface.enrichment_observation(B.enrichment(card))),
         Interface.project_fact(Identity.Part{parent, "start-error"}, "启动错误", B.start_error(card))] : +List<Interface.Node>}:
  B.Card{revision, draft, task, archived, created, updated, enrichment, error, pinned} = card
  {==}

def agent_row_observes_profile(+agent: B.AgentProfile, +id: Nat, +edit: View.ControlDeclaration, +parent: Identity.Key, +world: M.World(), +session: E.Session, +services: Services.State) ->
  {Interface.agent_observation(id, agent, edit, parent, Core.from_application(E.from_program(world, session), services)) ==
        Interface.Node{Identity.Entity{parent, "agent", Nat.show(id)}, "agent/" ++ Nat.show(id), B.agent_name(agent), Interface.Section{}, Interface.Region{}, [Interface.project_fact(Identity.Part{Identity.Entity{parent, "agent", Nat.show(id)}, "profile"}, "模型", B.agent_profile(agent)),
           Interface.project_fact(Identity.Part{Identity.Entity{parent, "agent", Nat.show(id)}, "reasoning"}, "推理", B.agent_reasoning(agent)),
           Interface.project_fact(Identity.Part{Identity.Entity{parent, "agent", Nat.show(id)}, "instructions"}, "指令", B.agent_instructions(agent)),
           Interface.project_fact(Identity.Part{Identity.Entity{parent, "agent", Nat.show(id)}, "concurrency"}, "并发上限", Nat.show(B.agent_concurrency(agent))),
           Interface.project_fact(Identity.Part{Identity.Entity{parent, "agent", Nat.show(id)}, "active"}, "工作中", Nat.show(Board.active_for(B.cards(Board.registry(world)), B.Agent{id}, world))),
           Interface.declared(Identity.Entity{parent, "agent", Nat.show(id)}, edit, Core.from_application(E.from_program(world, session), services)),
           Interface.more(U.AgentSubject{id}, Identity.Entity{parent, "agent", Nat.show(id)}, Core.from_application(E.from_program(world, session), services))]} : Interface.Node}:
  B.AgentProfile{revision, name, profile, reasoning, instructions, settings, concurrency} = agent
  {==}

def Rule.evidence():
  Rule.Requirements{
    card_opens_details,
    +view => +search => +status => +priority => +date => +assignee => +creator => +project => +labels => +parent => +state => {==},
    +id => +title => +status => +selected => +open => +parent => +state => {==},
    parent => state => {==},
    +reason => {==},
    actual_card_errors,
    +parent => state => {==},
    id => revision => state => {==},
    agent_row_observes_profile}
