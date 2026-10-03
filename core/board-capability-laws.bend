import Base
import ./ui-world.bend as View
import ./interface.bend as Interface
import ./SYSTEM.bend as Core
import ./user-experience.bend as E
import ./client-services.bend as Services
import ../bendlib/board-state.bend as Board
import ../bendlib/association-map.bend as Finite
import ./user-input.bend as U
import ../BOARD.bend as B
import ../MODEL.bend as M
import ../bendlib/json.bend as J

# These observations constrain production controls and details, rather than a
# second Board lifecycle or a browser-only action menu.
def opening(scene: View.CardScene) -> U.Input:
  View.CardScene{id, value, View.ControlDeclaration{identity, label, prominence, input, availability}, actions, linked, destinations, candidates} = scene
  input

def card_opens_details(+id: Nat, card: B.Card, route: U.Route, now: U32, world: M.World()) ->
  {opening(View.card_scene(id, card, route, now, world)) ==
    U.Activate{U.OpenPanel{U.CardDetails{id}, "card/" ++ Nat.show(id)}} : U.Input}:
  B.Card{revision, draft, task, archived, created, updated, enrichment, error, pinned} = card
  {==}

def working_keeps_facets_law(-view: String, -search: String, -status: +List<String>,
  -priority: +List<String>, -date: +List<String>, -assignee: +List<String>, -creator: +List<String>,
  -project: +List<String>, -labels: +List<String>, -parent: String, -state: Core.State) -> Type:
  {Interface.view_choice("working", "工作中", B.Filter{view, search, status, priority, date, assignee, creator, project, labels}, parent, state) ==
   Interface.selected_node(String.eq(view, "working"), Interface.declared(parent,
     View.ControlDeclaration{"view/working", "工作中", View.Secondary{},
       U.FilterBoard{B.Filter{"working", search, status, priority, date, assignee, creator, project, labels}}, View.Available{}}, state)) : Interface.Node}

def working_keeps_facets(+view: String, +search: String, +status: +List<String>, +priority: +List<String>, +date: +List<String>,
  +assignee: +List<String>, +creator: +List<String>, +project: +List<String>, +labels: +List<String>, +parent: String, +state: Core.State) ->
  working_keeps_facets_law(view, search, status, priority, date, assignee, creator, project, labels, parent, state):
  {==}

def linked_conversation_control(+id: Nat, +title: String, +status: String, +selected: Bool, +open: View.ControlDeclaration, +parent: String, +state: Core.State) ->
  {Interface.linked_card_controls(Some{View.TaskEntry{id, title, status, selected, open}}, parent, state) ==
    [Interface.declared(parent, open, state)] : +List<Interface.Node>}:
  {==}

def unlinked_has_no_conversation(parent: String, state: Core.State) ->
  {Interface.linked_card_controls(None{}, parent, state) == Nil{} : +List<Interface.Node>}:
  {==}

def failed_generation_is_observed(+reason: String) ->
  {Interface.enrichment_observation(B.EnrichmentFailed{reason}) == reason : String}:
  {==}

def actual_card_errors_law(-revision: Nat, -draft: B.Draft, -task: Maybe<&2, Nat>, -archived: Bool,
  -created: U32, -updated: U32, -enrichment: B.Enrichment, -error: String, -pinned: Bool,
  -parent: String) -> Type:
  {Interface.card_error_observations(B.Card{revision, draft, task, archived, created, updated, enrichment, error, pinned}, parent) ==
    [Interface.project_fact(parent ++ "/enrichment", "生成", Interface.enrichment_observation(enrichment)),
     Interface.project_fact(parent ++ "/start-error", "启动错误", error)] : +List<Interface.Node>}

def actual_card_errors(+revision: Nat, +draft: B.Draft, +task: Maybe<&2, Nat>, +archived: Bool, +created: U32, +updated: U32,
  +enrichment: B.Enrichment, +error: String, +pinned: Bool, +parent: String) ->
  actual_card_errors_law(revision, draft, task, archived, created, updated, enrichment, error, pinned, parent):
  {==}

def missing_card_is_unavailable(+parent: String, state: Core.State) ->
  {Interface.card_details_nodes(None{}, parent, state) ==
    [Interface.project_fact(parent ++ "/missing", "Unavailable", "The card no longer exists")] : +List<Interface.Node>}:
  {==}

def archived_has_no_archive_drop(id: Nat, revision: Nat, state: Core.State) ->
  {Interface.archive_placement(True{}, id, revision, state) == Nil{} : +List<Interface.Placement>}:
  {==}

def agent_row_observes_profile_law(-id: Nat, -revision: Nat, -name: String, -profile: String,
  -reasoning: String, -instructions: String, -settings: J.Json, -concurrency: Nat,
  -edit: View.ControlDeclaration, -parent: String, -world: M.World(), -session: E.Session,
  -services: Services.State) -> Type:
  {Interface.agent_observation(id, B.AgentProfile{revision, name, profile, reasoning, instructions, settings, concurrency}, edit, parent, Core.State{E.Application{world, session}, services}) ==
    Interface.region(parent, "agent/" ++ Nat.show(id), name, Interface.Section{},
      [Interface.project_fact((parent ++ "/agent/" ++ Nat.show(id)) ++ "/profile", "模型", profile),
       Interface.project_fact((parent ++ "/agent/" ++ Nat.show(id)) ++ "/reasoning", "推理", reasoning),
       Interface.project_fact((parent ++ "/agent/" ++ Nat.show(id)) ++ "/instructions", "指令", instructions),
       Interface.project_fact((parent ++ "/agent/" ++ Nat.show(id)) ++ "/concurrency", "并发上限", Nat.show(concurrency)),
       Interface.project_fact((parent ++ "/agent/" ++ Nat.show(id)) ++ "/active", "工作中", Nat.show(Board.active_for(B.cards(Board.registry(world)), B.Agent{id}, world))),
       Interface.declared(parent ++ "/agent/" ++ Nat.show(id), edit, Core.State{E.Application{world, session}, services}),
       Interface.more(U.AgentSubject{id}, parent ++ "/agent/" ++ Nat.show(id), Core.State{E.Application{world, session}, services})]) : Interface.Node}

def agent_row_observes_profile(+id: Nat, +revision: Nat, +name: String, +profile: String, +reasoning: String, +instructions: String,
  +settings: J.Json, +concurrency: Nat, +edit: View.ControlDeclaration, +parent: String, +world: M.World(), +session: E.Session, +services: Services.State) ->
  agent_row_observes_profile_law(id, revision, name, profile, reasoning, instructions, settings, concurrency, edit, parent, world, session, services):
  {==}

type Requirements is Type:
  Requirements{
    card_opens_details: @+id: Nat -> @card: B.Card -> @route: U.Route -> @now: U32 -> @world: M.World() ->
      {opening(View.card_scene(id, card, route, now, world)) ==
    U.Activate{U.OpenPanel{U.CardDetails{id}, "card/" ++ Nat.show(id)}} : U.Input},
    working_keeps_facets: @+view: String -> @+search: String -> @+status: +List<String> -> @+priority: +List<String> -> @+date: +List<String> -> @+assignee: +List<String> -> @+creator: +List<String> -> @+project: +List<String> -> @+labels: +List<String> -> @+parent: String -> @+state: Core.State ->
      working_keeps_facets_law(view, search, status, priority, date, assignee, creator, project, labels, parent, state),
    linked_conversation_control: @+id: Nat -> @+title: String -> @+status: String -> @+selected: Bool -> @+open: View.ControlDeclaration -> @+parent: String -> @+state: Core.State ->
      {Interface.linked_card_controls(Some{View.TaskEntry{id, title, status, selected, open}}, parent, state) ==
    [Interface.declared(parent, open, state)] : +List<Interface.Node>},
    unlinked_has_no_conversation: @parent: String -> @state: Core.State ->
      {Interface.linked_card_controls(None{}, parent, state) == Nil{} : +List<Interface.Node>},
    failed_generation_is_observed: @+reason: String ->
      {Interface.enrichment_observation(B.EnrichmentFailed{reason}) == reason : String},
    actual_card_errors: @+revision: Nat -> @+draft: B.Draft -> @+task: Maybe<&2, Nat> -> @+archived: Bool -> @+created: U32 -> @+updated: U32 -> @+enrichment: B.Enrichment -> @+error: String -> @+pinned: Bool -> @+parent: String ->
      actual_card_errors_law(revision, draft, task, archived, created, updated, enrichment, error, pinned, parent),
    missing_card_is_unavailable: @+parent: String -> @state: Core.State ->
      {Interface.card_details_nodes(None{}, parent, state) ==
    [Interface.project_fact(parent ++ "/missing", "Unavailable", "The card no longer exists")] : +List<Interface.Node>},
    archived_has_no_archive_drop: @id: Nat -> @revision: Nat -> @state: Core.State ->
      {Interface.archive_placement(True{}, id, revision, state) == Nil{} : +List<Interface.Placement>},
    agent_row_observes_profile: @+id: Nat -> @+revision: Nat -> @+name: String -> @+profile: String -> @+reasoning: String -> @+instructions: String -> @+settings: J.Json -> @+concurrency: Nat -> @+edit: View.ControlDeclaration -> @+parent: String -> @+world: M.World() -> @+session: E.Session -> @+services: Services.State ->
      agent_row_observes_profile_law(id, revision, name, profile, reasoning, instructions, settings, concurrency, edit, parent, world, session, services)}

def evidence() -> Requirements:
  Requirements{card_opens_details, working_keeps_facets, linked_conversation_control, unlinked_has_no_conversation, failed_generation_is_observed, actual_card_errors, missing_card_is_unavailable, archived_has_no_archive_drop, agent_row_observes_profile}
