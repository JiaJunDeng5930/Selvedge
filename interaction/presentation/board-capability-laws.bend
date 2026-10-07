import Base
import ../IDENTITY.bend as Identity
import ./MODEL.bend as View
import ./PROGRAM.bend as Interface
import ../STATE.bend as Core
import ../session/MODEL.bend as E
import ../services/MODEL.bend as Services
import ../../features/board/STATE.bend as Board
import ../INPUT.bend as U
import ../../features/board/MODEL.bend as B
import ../../harness/MODEL.bend as M
import ../../bendlib/json.bend as J

def opening(scene: View.CardScene) -> U.Input:
  View.CardScene{id, value, View.ControlDeclaration{identity, label, prominence, input, availability}, actions, linked, destinations, candidates} = scene
  input

type Requirements is Type:
  Requirements{
    card_opens_details: @+id: Nat -> @card: B.Card -> @route: U.Route -> @now: U32 -> @world: M.World() ->
      {opening(View.card_scene(id, card, route, now, world)) ==
    U.Activate{U.OpenPanel{U.CardDetails{id}, "card/" ++ Nat.show(id)}} : U.Input},
    working_keeps_facets: @+view: String -> @+search: String -> @+status: +List<String> -> @+priority: +List<String> -> @+date: +List<String> -> @+assignee: +List<String> -> @+creator: +List<String> -> @+project: +List<String> -> @+labels: +List<String> -> @+parent: Identity.Key -> @+state: Core.State ->
      {Interface.view_choice("working", "工作中", B.Filter{view, search, status, priority, date, assignee, creator, project, labels}, parent, state) ==
       Interface.selected_node(String.eq(view, "working"), Interface.declared(parent,
         View.ControlDeclaration{"view/working", "工作中", View.Secondary{},
           U.FilterBoard{B.Filter{"working", search, status, priority, date, assignee, creator, project, labels}}, View.Available{}}, state)) : Interface.Node},
    linked_conversation_control: @+id: Nat -> @+title: String -> @+status: View.TaskStatus -> @+selected: Bool -> @+open: View.ControlDeclaration -> @+parent: Identity.Key -> @+state: Core.State ->
      {Interface.linked_card_controls(Some{View.TaskEntry{id, title, status, selected, open}}, parent, state) ==
    [Interface.declared(parent, open, state)] : +List<Interface.Node>},
    unlinked_has_no_conversation: @parent: Identity.Key -> @state: Core.State ->
      {Interface.linked_card_controls(None{}, parent, state) == Nil{} : +List<Interface.Node>},
    failed_generation_is_observed: @+reason: String ->
      {Interface.enrichment_observation(B.EnrichmentFailed{reason}) == reason : String},
    actual_card_errors: @+card:B.Card -> @+parent: Identity.Key ->
      {Interface.card_error_observations(card, parent) ==
        [Interface.project_fact(Identity.Part{parent, "enrichment"}, "生成", Interface.enrichment_observation(B.enrichment(card))),
         Interface.project_fact(Identity.Part{parent, "start-error"}, "启动错误", B.start_error(card))] : +List<Interface.Node>},
    missing_card_is_unavailable: @+parent: Identity.Key -> @state: Core.State ->
      {Interface.card_details_nodes(None{}, parent, state) ==
    [Interface.project_fact(Identity.Part{parent, "missing"}, "Unavailable", "The card no longer exists")] : +List<Interface.Node>},
    archived_has_no_archive_drop: @id: Nat -> @revision: Nat -> @state: Core.State ->
      {Interface.archive_placement(True{}, id, revision, state) == Nil{} : +List<Interface.Placement>},
    agent_row_observes_profile: @+agent:B.AgentProfile -> @+id: Nat -> @+edit: View.ControlDeclaration -> @+parent: Identity.Key -> @+world: M.World() -> @+session: E.Session -> @+services: Services.State ->
      {Interface.agent_observation(id, agent, edit, parent, Core.from_application(E.from_program(world, session), services)) ==
        Interface.Node{Identity.Entity{parent, "agent", Nat.show(id)}, "agent/" ++ Nat.show(id), B.agent_name(agent), Interface.Section{}, Interface.Region{}, [Interface.project_fact(Identity.Part{Identity.Entity{parent, "agent", Nat.show(id)}, "profile"}, "模型", B.agent_profile(agent)),
           Interface.project_fact(Identity.Part{Identity.Entity{parent, "agent", Nat.show(id)}, "reasoning"}, "推理", B.agent_reasoning(agent)),
           Interface.project_fact(Identity.Part{Identity.Entity{parent, "agent", Nat.show(id)}, "instructions"}, "指令", B.agent_instructions(agent)),
           Interface.project_fact(Identity.Part{Identity.Entity{parent, "agent", Nat.show(id)}, "concurrency"}, "并发上限", Nat.show(B.agent_concurrency(agent))),
           Interface.project_fact(Identity.Part{Identity.Entity{parent, "agent", Nat.show(id)}, "active"}, "工作中", Nat.show(Board.active_for(B.cards(Board.registry(world)), B.Agent{id}, world))),
           Interface.declared(Identity.Entity{parent, "agent", Nat.show(id)}, edit, Core.from_application(E.from_program(world, session), services)),
           Interface.more(U.AgentSubject{id}, Identity.Entity{parent, "agent", Nat.show(id)}, Core.from_application(E.from_program(world, session), services))]} : Interface.Node}}

law evidence:
  Requirements
