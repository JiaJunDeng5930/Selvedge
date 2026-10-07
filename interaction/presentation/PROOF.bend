import Base
import ../../harness/DOMAIN.bend as D
import ../submission/FIELDS.bend as Forms
import ../STATE.bend as Core
import ./CONTRACT.bend as Rule
import ./PROGRAM.bend as Model
import ./MODEL.bend as V
import ../session/MODEL.bend as E
import ../IDENTITY.bend as Identity
import ../services/MODEL.bend as Services
import ../../features/board/STATE.bend as Board
import ../../bendlib/json.bend as J
import ./board-capability-laws.bend as RuleBoardCapabilityLaws
import ../INPUT.bend as U
import ../../features/board/MODEL.bend as B
import ../../harness/MODEL.bend as M
import ./board-presentation-laws.bend as RuleBoardPresentationLaws
import ../../harness/features/MODEL.bend as F
import ../../harness/workspace/PROJECTS.bend as Projects
import ../../bendlib/association-map.bend as Finite
import ../../features/board/filter.bend as Filter
import ../../harness/workspace/WORKSPACE.bend as W
import ../conversation/CODE.bend as Code
import ../conversation/OUTPUT.bend as Live
import ../services/CONTEXT.bend as Context
import ./boundary-laws.bend as RuleBoundaryLaws
import ./choice-rules.bend as RuleChoiceRules
import ../../harness/transport/schema.bend as Schema
import ./page-region-laws.bend as RulePageRegionLaws
import ./COMPOSITION.bend as Composition
import ../conversation/MODEL.bend as Conversation
import ../../harness/COMMANDS.bend as Commands
import ../../harness/tasks/PROGRAM.bend as Tasks
import ../../harness/conversation/PROGRAM.bend as ConversationProgram
import ./project-interaction-laws.bend as RuleProjectInteractionLaws
import ../../bendlib/stdlib.bend as Std
import ./surface-laws.bend as RuleSurfaceLaws
import ../MODEL.bend as ProductUI
import ./directory-entry-laws.bend as RuleDirectoryEntryLaws
import ../submission/PROOF.bend as SubmissionProof
import ./composition-laws.bend as RuleCompositionLaws

def Rule.composer_tree_present_agreement(identity, revision, message, footer, context, submit, feedback, pending, parent, state):
  match footer:
    case Nil{}: {==}
    case Con{first, rest}: {==}

def Rule.composer_tree_agreement(view, parent, state):
  match view:
    case None{}: {==}
    case Some{V.ComposerScene{+identity, revision, message, footer, context, submit, feedback, pending}}:
      Rule.composer_tree_present_agreement(identity, revision, message, footer, context, submit, feedback, pending, parent, state)

def Rule.relocated_valid_content(valid, node, scene, base, overlays):
  match valid:
    case False{}: {==}
    case True{}:
      Model.Node{key, semantic, label, role, meaning, children} = node
      {==}

def Rule.relocated_found_content(found, target, scene, base, overlays):
  match found:
    case None{}: {==}
    case Some{Model.Node{key, semantic, label, role, +meaning, children}}:
      Rule.relocated_valid_content(Model.persistent_trigger_source(meaning, target),
        Model.Node{key, semantic, label, role, meaning, children}, scene, base, overlays)

def Rule.relocated_key_content(found, target, scene, base, overlays):
  match found:
    case None{}: {==}
    case Some{key}: Rule.relocated_found_content(Model.find_node(base, key), target, scene, base, overlays)

def Rule.relocated_content(trigger, scene, base, overlays):
  match trigger:
    case None{}: {==}
    case Some{Model.PersistentTrigger{target, requested}}: Rule.relocated_key_content(Model.matching_focus(base, requested), target, scene, base, overlays)

def Rule.assembled_content(scene, state):
  Core.Scene{V.Scene{nav, main, views, arrangement, attention}, preferences, transfers, attachment, code, folder_picker} = scene
  {==}


def Rule.placement_destination_authority(key, semantic, label, role, destinations, face, children, target, surface):
  {==}

def Rule.placement_filtered_destination_accepted(key, semantic, label, role, destinations, face, children, target, surface, input, hidden, accepted):
  accepted

def Rule.placement_rejected_destination(key, semantic, label, role, destinations, face, children, target, surface, rejected):
  rejected


def Rule.fixed_reasoning_catalogue_entry(key, provider, name, options):
  {==}

def Rule.fixed_reasoning_open_entry(key, provider, name):
  {==}

def Rule.retained_profile_effort(profile, previous, permitted):
  Equal.cong(Bool, String, accepted => Forms.selected_profile_effort(accepted, previous, profile),
    D.profile_permitted(profile, previous), True{}, permitted)

def Rule.reset_profile_effort(profile, previous, denied):
  Equal.cong(Bool, String, accepted => Forms.selected_profile_effort(accepted, previous, profile),
    D.profile_permitted(profile, previous), False{}, denied)

def Rule.rejected_reasoning_edit(profile, reasoning):
  {==}

def Rule.accepted_reasoning_edit(profile, reasoning):
  {==}

def Rule.selected_model_permission(profile, reasoning):
  {==}

def Rule.rejected_profile_choice():
  {==}


def Rule.new_task_model_permission(message, profile, reasoning, context, world):
  {==}

def Rule.agent_model_permission(agent, revision, name, profile, reasoning, instructions, context, concurrency, world):
  {==}


def Rule.modal_navigation_preserved(nav, state): {==}

def Rule.overlay_navigation_scope(key, semantic, label, meaning, children, rest): {==}

def Rule.dialog_actions_region(parent, children):
  {==}

def Rule.editor_submit_region(identity, revision, groups, structure, submit, feedback, pending, parent, state):
  {==}

def Rule.confirmation_actions_region(title, confirm, cancel, parent, state):
  {==}

def Rule.card_ordered_movement(view, parent, state):
  V.CardScene{id, value, open, actions, linked, destinations, candidates} = view
  Core.State{E.Application{world, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code, next_layer}}, services} = state
  {==}

def Rule.card_surface_placement(key, semantic, label, face, children, target): {==}
def Rule.card_movement_placement(key, semantic, label, face, destinations, target): {==}


def Rule.project_fact_structure(key, label, value): {==}

def card_opens_details(+id: Nat, card: B.Card, route: U.Route, now: U32, world: M.World()) ->
  {RuleBoardCapabilityLaws.opening(V.card_scene(id, card, route, now, world)) ==
    U.Activate{U.OpenPanel{U.CardDetails{id}, "card/" ++ Nat.show(id)}} : U.Input}:
  B.Card{revision, draft, task, archived, created, updated, enrichment, error, pinned} = card
  {==}

def actual_card_errors(+card: B.Card, +parent: Identity.Key) ->
  {Model.card_error_observations(card, parent) ==
        [Model.project_fact(Identity.Part{parent, "enrichment"}, "生成", Model.enrichment_observation(B.enrichment(card))),
         Model.project_fact(Identity.Part{parent, "start-error"}, "启动错误", B.start_error(card))] : +List<Model.Node>}:
  B.Card{revision, draft, task, archived, created, updated, enrichment, error, pinned} = card
  {==}

def agent_row_observes_profile(+agent: B.AgentProfile, +id: Nat, +edit: V.ControlDeclaration, +parent: Identity.Key, +world: M.World(), +session: E.Session, +services: Services.State) ->
  {Model.agent_observation(id, agent, edit, parent, Core.from_application(E.from_program(world, session), services)) ==
        Model.Node{Identity.Entity{parent, "agent", Nat.show(id)}, "agent/" ++ Nat.show(id), B.agent_name(agent), Model.Section{}, Model.Region{}, [Model.project_fact(Identity.Part{Identity.Entity{parent, "agent", Nat.show(id)}, "profile"}, "模型", B.agent_profile(agent)),
           Model.project_fact(Identity.Part{Identity.Entity{parent, "agent", Nat.show(id)}, "reasoning"}, "推理", B.agent_reasoning(agent)),
           Model.project_fact(Identity.Part{Identity.Entity{parent, "agent", Nat.show(id)}, "instructions"}, "指令", B.agent_instructions(agent)),
           Model.project_fact(Identity.Part{Identity.Entity{parent, "agent", Nat.show(id)}, "concurrency"}, "并发上限", Nat.show(B.agent_concurrency(agent))),
           Model.project_fact(Identity.Part{Identity.Entity{parent, "agent", Nat.show(id)}, "active"}, "工作中", Nat.show(Board.active_for(B.cards(Board.registry(world)), B.Agent{id}, world))),
           Model.declared(Identity.Entity{parent, "agent", Nat.show(id)}, edit, Core.from_application(E.from_program(world, session), services)),
           Model.more(U.AgentSubject{id}, Identity.Entity{parent, "agent", Nat.show(id)}, Core.from_application(E.from_program(world, session), services))]} : Model.Node}:
  B.AgentProfile{revision, name, profile, reasoning, instructions, settings, concurrency} = agent
  {==}

def RuleBoardCapabilityLaws.evidence():
  RuleBoardCapabilityLaws.Requirements{
    card_opens_details,
    +view => +search => +status => +priority => +date => +assignee => +creator => +project => +labels => +parent => +state => {==},
    +id => +title => +status => +selected => +open => +parent => +state => {==},
    parent => state => {==},
    +reason => {==},
    actual_card_errors,
    +parent => state => {==},
    id => revision => state => {==},
    agent_row_observes_profile}

def card_title_is_preserved(+id: Nat, +card: B.Card, +now: U32, +world: M.World()) ->
  {RuleBoardPresentationLaws.face_title(V.card_face(id, card, now, world)) == B.title(B.draft(card)) : String}:
  {==}

def card_description_is_preserved(+id: Nat, +card: B.Card, +now: U32, +world: M.World()) ->
  {RuleBoardPresentationLaws.face_description(V.card_face(id, card, now, world)) == B.description(B.draft(card)) : String}:
  {==}

def card_priority_is_preserved(+id: Nat, +card: B.Card, +now: U32, +world: M.World()) ->
  {RuleBoardPresentationLaws.face_priority(V.card_face(id, card, now, world)) == B.card_priority(B.draft(card)) : B.Priority}:
  {==}

def card_pin_is_preserved(+id: Nat, +card: B.Card, +now: U32, +world: M.World()) ->
  {RuleBoardPresentationLaws.face_pinned(V.card_face(id, card, now, world)) == B.pinned(card) : Bool}:
  {==}

def card_status_is_observed(+id: Nat, +card: B.Card, +now: U32, +world: M.World()) ->
  {RuleBoardPresentationLaws.face_status(V.card_face(id, card, now, world)) == Board.activity_label(Board.activity(card, world)) : String}:
  {==}

def card_project_is_resolved(+id: Nat, +card: B.Card, +now: U32, +world: M.World()) ->
  {RuleBoardPresentationLaws.face_project(V.card_face(id, card, now, world)) == V.face_project(B.project(B.draft(card)), world) : String}:
  {==}

def card_labels_are_preserved(+id: Nat, +card: B.Card, +now: U32, +world: M.World()) ->
  {RuleBoardPresentationLaws.face_labels(V.card_face(id, card, now, world)) == B.labels(B.draft(card)) : +List<String>}:
  {==}

def card_owner_is_resolved(+id: Nat, +card: B.Card, +now: U32, +world: M.World()) ->
  {RuleBoardPresentationLaws.face_owner(V.card_face(id, card, now, world)) == V.face_owner(B.card_owner(B.draft(card)), world) : String}:
  {==}

def card_updated_uses_elapsed_clock(+id: Nat, +card: B.Card, +now: U32, +world: M.World()) ->
  {RuleBoardPresentationLaws.face_updated(V.card_face(id, card, now, world)) == V.elapsed_label(Filter.elapsed(now, B.updated(card))) : String}:
  {==}

def card_scene_ids_cons(head: V.CardScene, +rest: +List<V.CardScene>) ->
  {RuleBoardPresentationLaws.card_scene_ids(head <> rest) == RuleBoardPresentationLaws.card_scene_identity(head) <> RuleBoardPresentationLaws.card_scene_ids(rest) : +List<Nat>}:
  V.CardScene{id, value, open, actions, linked, destinations, candidates} = head
  {==}

def card_scene_identity_is_input(id: Nat, revision: Nat, draft: B.Draft, task: Maybe<&2, Nat>, archived: Bool,
  created: U32, updated: U32, enrichment: B.Enrichment, start_error: String, pinned: Bool,
  route: U.Route, +now: U32, +world: M.World()) ->
  {RuleBoardPresentationLaws.card_scene_identity(V.card_scene(id, B.Card{revision, draft, task, archived, created, updated, enrichment, start_error, pinned}, route, now, world)) == id : Nat}:
  {==}

def card_scenes_keep_ids(+entries: +List<Finite.Entry(B.Card)>, +route: U.Route, +now: U32, +world: M.World()) ->
  {RuleBoardPresentationLaws.card_scene_ids(V.card_scenes(entries, route, now, world)) == RuleBoardPresentationLaws.board_entry_ids(entries) : +List<Nat>}:
  match entries:
    case Nil{}: {==}
    case Con{(+id, +card), +rest}:
      B.Card{revision, draft, task, archived, created, updated, enrichment, start_error, pinned} = card
      +materialized: B.Card = B.Card{revision, draft, task, archived, created, updated, enrichment, start_error, pinned}
      Equal.trans(+List<Nat>,
        RuleBoardPresentationLaws.card_scene_ids(V.card_scene(id, materialized, route, now, world) <> V.card_scenes(rest, route, now, world)),
        RuleBoardPresentationLaws.card_scene_identity(V.card_scene(id, materialized, route, now, world)) <> RuleBoardPresentationLaws.card_scene_ids(V.card_scenes(rest, route, now, world)),
        id <> RuleBoardPresentationLaws.board_entry_ids(rest),
        card_scene_ids_cons(V.card_scene(id, materialized, route, now, world), V.card_scenes(rest, route, now, world)),
        Equal.trans(+List<Nat>,
          RuleBoardPresentationLaws.card_scene_identity(V.card_scene(id, materialized, route, now, world)) <> RuleBoardPresentationLaws.card_scene_ids(V.card_scenes(rest, route, now, world)),
          id <> RuleBoardPresentationLaws.card_scene_ids(V.card_scenes(rest, route, now, world)), id <> RuleBoardPresentationLaws.board_entry_ids(rest),
          Equal.cong(Nat, +List<Nat>, (head_id => head_id <> RuleBoardPresentationLaws.card_scene_ids(V.card_scenes(rest, route, now, world))),
            RuleBoardPresentationLaws.card_scene_identity(V.card_scene(id, materialized, route, now, world)), id,
            card_scene_identity_is_input(id, revision, draft, task, archived, created, updated, enrichment, start_error, pinned, route, now, world)),
          Equal.cong(+List<Nat>, +List<Nat>, (tail => id <> tail), RuleBoardPresentationLaws.card_scene_ids(V.card_scenes(rest, route, now, world)),
            RuleBoardPresentationLaws.board_entry_ids(rest), card_scenes_keep_ids(rest, route, now, world))))

def card_roots_keep_length(+entries: +List<V.CardScene>, +parent: Identity.Key, +state: Core.State) ->
  {List.length(&2, Model.Node, Model.cards(entries, parent, state)) == List.length(&2, V.CardScene, entries) : Nat}:
  match entries:
    case Nil{}: {==}
    case Con{+entry, +rest}:
      Equal.cong(Nat, Nat, (tail => (1n + tail : Nat)),
        List.length(&2, Model.Node, Model.cards(rest, parent, state)),
        List.length(&2, V.CardScene, rest), card_roots_keep_length(rest, parent, state))

def lane_children_are_create_plus_cards(stage: B.Stage, +entries: +List<V.CardScene>, +create: V.ControlDeclaration,
  +parent: Identity.Key, +state: Core.State) ->
  {RuleBoardPresentationLaws.first_lane_child_count(Model.columns([V.BoardColumn{stage, entries, create}], parent, state)) ==
    Some{(1n + List.length(&2, V.CardScene, entries) : Nat)} : Maybe<&2, Nat>}:
  +lane_key: Identity.Key = Identity.Part{parent, B.stage_name(stage)}
  children_count = card_roots_keep_length(entries, lane_key, state)
  Equal.cong(Nat, Maybe<&2, Nat>, (cards => Some{(1n + cards : Nat)}),
    List.length(&2, Model.Node, Model.cards(entries, lane_key, state)),
    List.length(&2, V.CardScene, entries), children_count)

def selected_work_child_identity(selected: Bool, +node: Model.Node, +parent: Identity.Key, rest: +List<Model.Node>) ->
  {RuleBoardPresentationLaws.work_status_child_key(Model.board_group(parent, "work-status", Model.WorkStatus{}, [Model.selected_node(selected, node)]) <> rest) ==
    Some{Model.node_key(node)} : Maybe<&2, String>}:
  match selected:
    case True{}:
      Model.Node{key, semantic, label, role, meaning, children} = node
      {==}
    case False{}:
      Model.Node{key, semantic, label, role, meaning, children} = node
      {==}

def board_toolbar_work_status_identity(+filter: B.Filter, working: Nat, create: V.ControlDeclaration,
  settings: V.ControlDeclaration, filters: V.ControlDeclaration, archive: V.ControlDeclaration,
  +parent: Identity.Key, +state: Core.State) ->
  {RuleBoardPresentationLaws.work_status_child_key(Model.board_toolbar(filter, working, create, settings, filters, archive, parent, state)) ==
    Some{Identity.encode(Identity.Part{Identity.Part{parent, "work-status"}, "view/working"})} : Maybe<&2, String>}:
  B.Filter{+view, search, status, priority, date, assignee, creator, project, labels} = filter
  Core.State{application, services} = state
  selected_work_child_identity(String.eq(view, "working"),
    Model.declared(Identity.Part{parent, "work-status"},
      V.ControlDeclaration{"view/working", "正在运行的任务 " ++ Nat.show(working), V.Secondary{},
        U.FilterBoard{B.Filter{"working", search, status, priority, date, assignee, creator, project, labels}}, V.Available{}},
      Core.State{application, services}), parent,
    [Model.board_group(parent, "secondary-actions", Model.SecondaryActions{},
      [Model.declared(parent, filters, Core.State{application, services}), Model.declared(parent, settings, Core.State{application, services}),
       Model.archive_destination(archive, parent, Core.State{application, services})]),
     Model.board_group(parent, "primary-action", Model.PrimaryAction{}, [Model.declared(parent, create, Core.State{application, services})])])

def navigation_header_keeps_brand(+navigation: V.Navigation, +state: Core.State) ->
  {RuleBoardPresentationLaws.navigation_header_label(Model.navigation(navigation, state)) == Some{"Selvedge"} : Maybe<&2, String>}:
  V.Navigation{expanded, create, destinations, projects, tasks, toggle} = navigation
  Core.State{E.Application{world, E.Session{route, drafts, readers, layers, attention, stored_navigation,
    filter, now, next, pending, previews, code, next_layer}}, services} = state
  {==}

def navigation_header_contains_only_toggle(+navigation: V.Navigation, +state: Core.State) ->
  {RuleBoardPresentationLaws.navigation_header_children(Model.navigation(navigation, state)) ==
    Some{[Model.declared(Identity.Place{"/navigation"}, RuleBoardPresentationLaws.navigation_toggle_control(navigation), state)]} : Maybe<&2, +List<Model.Node>>}:
  V.Navigation{expanded, create, destinations, projects, tasks, toggle} = navigation
  Core.State{E.Application{world, E.Session{route, drafts, readers, layers, attention, stored_navigation,
    filter, now, next, pending, previews, code, next_layer}}, services} = state
  {==}

def display_cards_are_pinned_partition(+board: B.State) ->
  {Board.display_cards(board) == RuleBoardPresentationLaws.pinned_partition(board) : +List<Finite.Entry(B.Card)>}:
  {==}

def board_page_column_ids_match_display(+board: B.State, +filter: B.Filter, +route: U.Route,
  +now: U32, +world: M.World(), target: B.Stage) ->
  {RuleBoardPresentationLaws.board_page_column_ids(V.board_page(board, filter, route, now, world), target) ==
    RuleBoardPresentationLaws.board_entry_ids(Filter.column(Filter.filtered(Board.display_cards(board), filter, now, world), B.stage_name(target))) : +List<Nat>}:
  match target:
    case B.Backlog{}: card_scenes_keep_ids(Filter.column(Filter.filtered(Board.display_cards(board), filter, now, world), B.stage_name(B.Backlog{})), route, now, world)
    case B.Todo{}: card_scenes_keep_ids(Filter.column(Filter.filtered(Board.display_cards(board), filter, now, world), B.stage_name(B.Todo{})), route, now, world)
    case B.InProgress{}: card_scenes_keep_ids(Filter.column(Filter.filtered(Board.display_cards(board), filter, now, world), B.stage_name(B.InProgress{})), route, now, world)
    case B.InReview{}: card_scenes_keep_ids(Filter.column(Filter.filtered(Board.display_cards(board), filter, now, world), B.stage_name(B.InReview{})), route, now, world)
    case B.Completed{}: card_scenes_keep_ids(Filter.column(Filter.filtered(Board.display_cards(board), filter, now, world), B.stage_name(B.Completed{})), route, now, world)
    case B.Blocked{}: card_scenes_keep_ids(Filter.column(Filter.filtered(Board.display_cards(board), filter, now, world), B.stage_name(B.Blocked{})), route, now, world)

def search_change_preserves_filter_facets(+search: String, +filter: B.Filter) ->
  {Model.with_search(search, filter) == RuleBoardPresentationLaws.search_filter(search, filter) : B.Filter}:
  match filter:
    case B.Filter{view, old_search, status, priority, date, assignee, creator, project, label}: {==}

def status_toggle_preserves_other_facets(+value: String, +filter: B.Filter) ->
  {Model.toggle_filter("status", value, filter) == RuleBoardPresentationLaws.toggled_status_filter(value, filter) : B.Filter}:
  match filter:
    case B.Filter{view, search, status, priority, date, assignee, creator, project, label}: {==}

def priority_toggle_preserves_other_facets(+value: String, +filter: B.Filter) ->
  {Model.toggle_filter("priority", value, filter) == RuleBoardPresentationLaws.toggled_priority_filter(value, filter) : B.Filter}:
  match filter:
    case B.Filter{view, search, status, priority, date, assignee, creator, project, label}: {==}

def date_toggle_preserves_other_facets(+value: String, +filter: B.Filter) ->
  {Model.toggle_filter("date", value, filter) == RuleBoardPresentationLaws.toggled_date_filter(value, filter) : B.Filter}:
  match filter:
    case B.Filter{view, search, status, priority, date, assignee, creator, project, label}: {==}

def assignee_toggle_preserves_other_facets(+value: String, +filter: B.Filter) ->
  {Model.toggle_filter("assignee", value, filter) == RuleBoardPresentationLaws.toggled_assignee_filter(value, filter) : B.Filter}:
  match filter:
    case B.Filter{view, search, status, priority, date, assignee, creator, project, label}: {==}

def creator_toggle_preserves_other_facets(+value: String, +filter: B.Filter) ->
  {Model.toggle_filter("creator", value, filter) == RuleBoardPresentationLaws.toggled_creator_filter(value, filter) : B.Filter}:
  match filter:
    case B.Filter{view, search, status, priority, date, assignee, creator, project, label}: {==}

def project_toggle_preserves_other_facets(+value: String, +filter: B.Filter) ->
  {Model.toggle_filter("project", value, filter) == RuleBoardPresentationLaws.toggled_project_filter(value, filter) : B.Filter}:
  match filter:
    case B.Filter{view, search, status, priority, date, assignee, creator, project, label}: {==}

def label_toggle_preserves_other_facets(+value: String, +filter: B.Filter) ->
  {Model.toggle_filter("label", value, filter) == RuleBoardPresentationLaws.toggled_label_filter(value, filter) : B.Filter}:
  match filter:
    case B.Filter{view, search, status, priority, date, assignee, creator, project, label}: {==}

def board_route_selects_board_nav(+world: M.World(), +session: E.Session) ->
  {RuleBoardPresentationLaws.board_navigation_selected(U.TaskBoard{}, world, session) == True{} : Bool}:
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code, next_layer} = session
  {==}

def projects_route_selects_projects_nav(+world: M.World(), +session: E.Session) ->
  {RuleBoardPresentationLaws.projects_navigation_selected(U.ProjectCollection{}, world, session) == True{} : Bool}:
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code, next_layer} = session
  {==}

def agents_route_selects_agents_nav(+world: M.World(), +session: E.Session) ->
  {RuleBoardPresentationLaws.agents_navigation_selected(U.AgentCollection{}, world, session) == True{} : Bool}:
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code, next_layer} = session
  {==}

def start_route_selects_create_nav(+world: M.World(), +session: E.Session) ->
  {RuleBoardPresentationLaws.create_navigation_selected(U.Start{}, world, session) == True{} : Bool}:
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code, next_layer} = session
  {==}

def board_route_rejects_other_nav(+world: M.World(), +session: E.Session) ->
  {(RuleBoardPresentationLaws.projects_navigation_selected(U.TaskBoard{}, world, session), RuleBoardPresentationLaws.agents_navigation_selected(U.TaskBoard{}, world, session)) ==
    (False{}, False{}) : Bool & Bool}:
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code, next_layer} = session
  {==}

def projects_route_rejects_other_nav(+world: M.World(), +session: E.Session) ->
  {(RuleBoardPresentationLaws.board_navigation_selected(U.ProjectCollection{}, world, session), RuleBoardPresentationLaws.agents_navigation_selected(U.ProjectCollection{}, world, session)) ==
    (False{}, False{}) : Bool & Bool}:
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code, next_layer} = session
  {==}

def agents_route_rejects_other_nav(+world: M.World(), +session: E.Session) ->
  {(RuleBoardPresentationLaws.board_navigation_selected(U.AgentCollection{}, world, session), RuleBoardPresentationLaws.projects_navigation_selected(U.AgentCollection{}, world, session)) ==
    (False{}, False{}) : Bool & Bool}:
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code, next_layer} = session
  {==}

def start_route_rejects_destination_nav(+world: M.World(), +session: E.Session) ->
  {(RuleBoardPresentationLaws.board_navigation_selected(U.Start{}, world, session), RuleBoardPresentationLaws.projects_navigation_selected(U.Start{}, world, session), RuleBoardPresentationLaws.agents_navigation_selected(U.Start{}, world, session)) ==
    (False{}, (False{}, False{})) : Bool & (Bool & Bool)}:
  E.Session{route, drafts, readers, layers, focus, navigation, filter, now, next, pending, previews, code, next_layer} = session
  {==}

def selected_declaration_role_tracks_predicate(+route: U.Route, +parent: Identity.Key,
  declaration: V.ControlDeclaration, +state: Core.State) ->
  {Model.node_role(Model.selected_declaration(route, parent, declaration, state)) ==
    Model.node_role(Model.selected_node(Model.navigation_action_selected(route, RuleBoardPresentationLaws.declaration_input(declaration)),
      Model.declared(parent, declaration, state))) : Model.Role}:
  match declaration:
    case V.ControlDeclaration{identity, label, prominence, input, availability}:
      {==}

def board_settings_preserve_state(+board: B.State, +world: M.World()) ->
  RuleBoardPresentationLaws.settings_state_law(board, world):
  match board:
    case B.State{cards, next_card, agents, next_agent, automatic, draft_profile}: {==}

def RuleBoardPresentationLaws.evidence():
  RuleBoardPresentationLaws.Requirements{
    +id => +card => +now => +world => {==},
    id => card => now => world =>
      (card_title_is_preserved(id, card, now, world), card_description_is_preserved(id, card, now, world),
       card_priority_is_preserved(id, card, now, world), card_pin_is_preserved(id, card, now, world),
       card_labels_are_preserved(id, card, now, world)),
    id => card => now => world =>
      (card_status_is_observed(id, card, now, world), card_project_is_resolved(id, card, now, world),
       card_owner_is_resolved(id, card, now, world), card_updated_uses_elapsed_clock(id, card, now, world)),
    entries => route => now => world => card_scenes_keep_ids(entries, route, now, world),
    entries => parent => state => card_roots_keep_length(entries, parent, state),
    stage => +entries => +create => +parent => +state => {==},
    stage => entries => create => parent => state => lane_children_are_create_plus_cards(stage, entries, create, parent, state),
    filter => working => create => settings => filters => archive => parent => state =>
      board_toolbar_work_status_identity(filter, working, create, settings, filters, archive, parent, state),
    navigation => state => navigation_header_keeps_brand(navigation, state),
    navigation => state => navigation_header_contains_only_toggle(navigation, state),
    board => display_cards_are_pinned_partition(board),
    +board => +filter => +route => +now => +world => target =>
      Equal.trans(+List<Nat>,
        RuleBoardPresentationLaws.board_page_column_ids(V.board_page(board, filter, route, now, world), target),
        RuleBoardPresentationLaws.board_entry_ids(Filter.column(Filter.filtered(Board.display_cards(board), filter, now, world), B.stage_name(target))),
        RuleBoardPresentationLaws.board_entry_ids(Filter.column(Filter.filtered(RuleBoardPresentationLaws.pinned_partition(board), filter, now, world), B.stage_name(target))),
        board_page_column_ids_match_display(board, filter, route, now, world, target),
        Equal.cong(+List<Finite.Entry(B.Card)>, +List<Nat>,
          (entries => RuleBoardPresentationLaws.board_entry_ids(Filter.column(Filter.filtered(entries, filter, now, world), B.stage_name(target)))),
          Board.display_cards(board), RuleBoardPresentationLaws.pinned_partition(board), display_cards_are_pinned_partition(board)))
    ,
    +world => {==},
    +id => +world => absent =>
      Equal.cong(Maybe<&2, D.Project>, String,
        (found => V.face_project_name(found, id)),
        Projects.find(Projects.registry(F.State(), world), id), None{}, absent)
    ,
    +key => +world => absent =>
      Equal.cong(Maybe<&2, D.Profile>, String,
        (found => V.face_profile_name(found, key)), D.find_profile(Board.profiles(world), key), None{}, absent)
    ,
    id => +world => absent =>
      Equal.cong(Maybe<&2, B.AgentProfile>, String,
        (found => V.face_agent_name(found, id)), B.find_agent(Board.registry(world), id), None{}, absent)
    ,
    search => filter => search_change_preserves_filter_facets(search, filter),
    value => filter => status_toggle_preserves_other_facets(value, filter),
    value => filter => priority_toggle_preserves_other_facets(value, filter),
    value => filter => date_toggle_preserves_other_facets(value, filter),
    value => filter => assignee_toggle_preserves_other_facets(value, filter),
    value => filter => creator_toggle_preserves_other_facets(value, filter),
    value => filter => project_toggle_preserves_other_facets(value, filter),
    value => filter => label_toggle_preserves_other_facets(value, filter),
    board => +filter => +route => +now => +world => {==},
    board => +filter => +route => +now => +world => {==},
    stage => +route => +now => +world => {==},
    stage => +route => +now => +world => {==},
    world => session => board_route_selects_board_nav(world, session),
    world => session => projects_route_selects_projects_nav(world, session),
    world => session => agents_route_selects_agents_nav(world, session),
    world => session => start_route_selects_create_nav(world, session),
    world => session => board_route_rejects_other_nav(world, session),
    world => session => projects_route_rejects_other_nav(world, session),
    world => session => agents_route_rejects_other_nav(world, session),
    world => session => start_route_rejects_destination_nav(world, session),
    route => parent => declaration => state => selected_declaration_role_tracks_predicate(route, parent, declaration, state),
    board => world => board_settings_preserve_state(board, world),
    +session => +world => {==},
    stage => +application => {==},
    stage => {==},
    id => +application => {==}
  }

def settings_fields_without_project(+previous:Maybe<&2, D.Workspace>, +sandbox:Maybe<&2, D.Sandbox>,
  +approval:Maybe<&2, Context.ApprovalChoice>, +workspace:D.Workspace, +guidance:D.ProjectContext) ->
  {RuleBoundaryLaws.settings_fields(Context.observed_settings(Context.Configuration{Context.EnvironmentDefaults{}, previous, sandbox, approval},
      Context.DirectoryObservation{workspace, guidance})) ==
    RuleBoundaryLaws.SettingsFields{D.workspace_json(workspace), D.project_json(guidance),
      J.get(Context.settings(Context.Configuration{Context.EnvironmentDefaults{}, previous, sandbox, approval}), "project_id"),
      J.get(Context.settings(Context.Configuration{Context.EnvironmentDefaults{}, previous, sandbox, approval}), "sandbox"),
      J.get(Context.settings(Context.Configuration{Context.EnvironmentDefaults{}, previous, sandbox, approval}), "approval")} : RuleBoundaryLaws.SettingsFields}:
  match previous sandbox approval:
    case None{} None{} None{}: {==}
    case None{} None{} Some{choice}: {==}
    case None{} Some{sandbox_value} None{}: {==}
    case None{} Some{sandbox_value} Some{choice}: {==}
    case Some{previous_value} None{} None{}: {==}
    case Some{previous_value} None{} Some{choice}: {==}
    case Some{previous_value} Some{sandbox_value} None{}: {==}
    case Some{previous_value} Some{sandbox_value} Some{choice}: {==}

def settings_fields_with_project(project:Nat, +previous:Maybe<&2, D.Workspace>, +sandbox:Maybe<&2, D.Sandbox>,
  +approval:Maybe<&2, Context.ApprovalChoice>, +workspace:D.Workspace, +guidance:D.ProjectContext) ->
  {RuleBoundaryLaws.settings_fields(Context.observed_settings(Context.Configuration{Context.ProjectDefaults{project}, previous, sandbox, approval},
      Context.DirectoryObservation{workspace, guidance})) ==
    RuleBoundaryLaws.SettingsFields{D.workspace_json(workspace), D.project_json(guidance),
      J.get(Context.settings(Context.Configuration{Context.ProjectDefaults{project}, previous, sandbox, approval}), "project_id"),
      J.get(Context.settings(Context.Configuration{Context.ProjectDefaults{project}, previous, sandbox, approval}), "sandbox"),
      J.get(Context.settings(Context.Configuration{Context.ProjectDefaults{project}, previous, sandbox, approval}), "approval")} : RuleBoundaryLaws.SettingsFields}:
  match previous sandbox approval:
    case None{} None{} None{}: {==}
    case None{} None{} Some{choice}: {==}
    case None{} Some{sandbox_value} None{}: {==}
    case None{} Some{sandbox_value} Some{choice}: {==}
    case Some{previous_value} None{} None{}: {==}
    case Some{previous_value} None{} Some{choice}: {==}
    case Some{previous_value} Some{sandbox_value} None{}: {==}
    case Some{previous_value} Some{sandbox_value} Some{choice}: {==}

def settings_projection(+config:Context.Configuration, +workspace:D.Workspace, +guidance:D.ProjectContext) ->
  RuleBoundaryLaws.settings_observations_law(config, workspace, guidance):
  match config:
    case Context.Configuration{Context.EnvironmentDefaults{}, previous, sandbox, approval}:
      settings_fields_without_project(previous, sandbox, approval, workspace, guidance)
    case Context.Configuration{Context.ParentTask{_}, previous, sandbox, approval}:
      settings_fields_without_project(previous, sandbox, approval, workspace, guidance)
    case Context.Configuration{Context.ProjectDefaults{project}, previous, sandbox, approval}:
      settings_fields_with_project(project, previous, sandbox, approval, workspace, guidance)
    case Context.Configuration{Context.ProjectForParent{task, project}, previous, sandbox, approval}:
      settings_fields_with_project(project, previous, sandbox, approval, workspace, guidance)

def stale_code_expiry(+identity: Code.Identity, source: String, +wrap: Bool, +copy: Code.CopyState,
  next: Nat, ticket: Nat, stale: {Code.feedback_ticket(copy, ticket) == False{} : Bool}) ->
  {Code.step(Code.Block{identity, source, Code.CodeView{wrap, copy}, next}, Code.ExpireFeedback{ticket}) ==
    Code.Decision{Code.Block{identity, source, Code.CodeView{wrap, copy}, next}, Nil{}} : Code.Decision}:
  match copy:
    case Code.CopyIdle{}: {==}
    case Code.CopyPending{current}: {==}
    case Code.CopySucceeded{+current}:
      Equal.cong(Bool, Code.Decision,
        owned => Code.expire_code_feedback(owned, Code.Block{identity, source,
          Code.CodeView{wrap, Code.CopySucceeded{current}}, next}),
        Nat.is_eq(current, ticket), False{}, stale)
    case Code.CopyFailed{+current}:
      Equal.cong(Bool, Code.Decision,
        owned => Code.expire_code_feedback(owned, Code.Block{identity, source,
          Code.CodeView{wrap, Code.CopyFailed{current}}, next}),
        Nat.is_eq(current, ticket), False{}, stale)

def restore_preview(value: Services.Preview, state: Services.State) -> Services.State:
  Services.State{access, credential, settings_open, appearance, next, transfers, preview, directory_picker} = state
  Services.State{access, credential, settings_open, appearance, next, transfers, value, directory_picker}

def restore_directory_picker(value: Services.DirectoryPicker, state: Services.State) -> Services.State:
  Services.State{access, credential, settings_open, appearance, next, transfers, preview, directory_picker} = state
  Services.State{access, credential, settings_open, appearance, next, transfers, preview, value}

def encapsulated_stale_preview(+state: Services.State, current: Nat, +file: B.Attachment, trigger: String, ticket: Nat, +result: Result<&2, &2, String, String>, observed_preview: {Services.preview(state) == Services.LoadingPreview{current, file, trigger} : Services.Preview}, observed_directory_picker: {Services.directory_picker(state) == Services.NoDirectoryPicker{} : Services.DirectoryPicker}, different: {Nat.is_eq(current, ticket) == False{} : Bool}) ->
  {Services.step(Services.Previewed{ticket, result}, state) ==
        Services.Decision{state, Nil{}} : Services.Decision}:
  Services.State{+access, +credential, +settings_open, +appearance, +next, +transfers, +stored_preview, +stored_directory_picker} = state
  backwards_preview = Equal.sym(Services.State, state, restore_preview(Services.LoadingPreview{current, file, trigger}, state),
    Equal.cong(Services.Preview, Services.State, value => restore_preview(value, state), Services.preview(state), Services.LoadingPreview{current, file, trigger}, observed_preview))
  %backwards_preview : {Services.step(Services.Previewed{ticket, result}, _) ==
        Services.Decision{_, Nil{}} : Services.Decision}
  backwards_directory_picker = Equal.sym(Services.State, restore_preview(Services.LoadingPreview{current, file, trigger}, state), restore_directory_picker(Services.NoDirectoryPicker{}, restore_preview(Services.LoadingPreview{current, file, trigger}, state)),
    Equal.cong(Services.DirectoryPicker, Services.State, value => restore_directory_picker(value, restore_preview(Services.LoadingPreview{current, file, trigger}, state)), Services.directory_picker(restore_preview(Services.LoadingPreview{current, file, trigger}, state)), Services.NoDirectoryPicker{}, observed_directory_picker))
  %backwards_directory_picker : {Services.step(Services.Previewed{ticket, result}, _) ==
        Services.Decision{_, Nil{}} : Services.Decision}
  Equal.cong(Bool, Services.Decision,
          owned => Services.finish_preview(owned,
            Services.State{access, credential, settings_open, appearance, next, transfers,
              Services.LoadingPreview{current, file, trigger}, Services.NoDirectoryPicker{}}, file, trigger, result),
          Nat.is_eq(current, ticket), False{}, different)

def encapsulated_closed_preview(+state: Services.State, ticket: Nat, +result: Result<&2, &2, String, String>, observed_preview: {Services.preview(state) == Services.NoPreview{} : Services.Preview}, observed_directory_picker: {Services.directory_picker(state) == Services.NoDirectoryPicker{} : Services.DirectoryPicker}) ->
  {Services.step(Services.Previewed{ticket, result}, state) ==
        Services.Decision{state, Nil{}} : Services.Decision}:
  Services.State{+access, +credential, +settings_open, +appearance, +next, +transfers, +stored_preview, +stored_directory_picker} = state
  backwards_preview = Equal.sym(Services.State, state, restore_preview(Services.NoPreview{}, state),
    Equal.cong(Services.Preview, Services.State, value => restore_preview(value, state), Services.preview(state), Services.NoPreview{}, observed_preview))
  %backwards_preview : {Services.step(Services.Previewed{ticket, result}, _) ==
        Services.Decision{_, Nil{}} : Services.Decision}
  backwards_directory_picker = Equal.sym(Services.State, restore_preview(Services.NoPreview{}, state), restore_directory_picker(Services.NoDirectoryPicker{}, restore_preview(Services.NoPreview{}, state)),
    Equal.cong(Services.DirectoryPicker, Services.State, value => restore_directory_picker(value, restore_preview(Services.NoPreview{}, state)), Services.directory_picker(restore_preview(Services.NoPreview{}, state)), Services.NoDirectoryPicker{}, observed_directory_picker))
  %backwards_directory_picker : {Services.step(Services.Previewed{ticket, result}, _) ==
        Services.Decision{_, Nil{}} : Services.Decision}
  {==}

def encapsulated_upload_destination(+state: Services.State, ticket: Nat, +editor: U.Editor, +file: Services.SelectedFile, +attachment: B.Attachment, observed_directory_picker: {Services.directory_picker(state) == Services.NoDirectoryPicker{} : Services.DirectoryPicker}, found: {Finite.find(~Services.Transfer, Services.transfers(state), ticket) ==
        Some{Services.Uploading{editor, file}} : Maybe<&2, Services.Transfer>}) ->
  {Services.step(Services.Uploaded{ticket, Done{attachment}}, state) ==
        Services.Decision{Services.with_transfers(Finite.remove(~Services.Transfer, Services.transfers(state), ticket), state),
          [Services.AttachToDraft{editor, attachment}]} : Services.Decision}:
  Services.State{+access, +credential, +settings_open, +appearance, +next, +transfers, +preview, +stored_directory_picker} = state
  backwards_directory_picker = Equal.sym(Services.State, state, restore_directory_picker(Services.NoDirectoryPicker{}, state),
    Equal.cong(Services.DirectoryPicker, Services.State, value => restore_directory_picker(value, state), Services.directory_picker(state), Services.NoDirectoryPicker{}, observed_directory_picker))
  %backwards_directory_picker : {Services.step(Services.Uploaded{ticket, Done{attachment}}, _) ==
        Services.Decision{Services.with_transfers(Finite.remove(~Services.Transfer, Services.transfers(_), ticket), _),
          [Services.AttachToDraft{editor, attachment}]} : Services.Decision}
  Equal.trans(Services.Decision,
          Services.step(Services.Uploaded{ticket, Done{attachment}},
            Services.State{access, credential, settings_open, appearance, next, transfers, preview, Services.NoDirectoryPicker{}}),
          Services.upload_finished(Some{Services.Uploading{editor, file}},
            Services.State{access, credential, settings_open, appearance, next, transfers, preview, Services.NoDirectoryPicker{}},
            ticket, Done{attachment}),
          Services.Decision{Services.State{access, credential, settings_open, appearance, next,
            Finite.remove(~Services.Transfer, transfers, ticket), preview, Services.NoDirectoryPicker{}},
            [Services.AttachToDraft{editor, attachment}]},
          Equal.cong(Maybe<&2, Services.Transfer>, Services.Decision,
            found => Services.upload_finished(found,
              Services.State{access, credential, settings_open, appearance, next, transfers, preview, Services.NoDirectoryPicker{}},
              ticket, Done{attachment}),
            Finite.find(~Services.Transfer, transfers, ticket),
            Some{Services.Uploading{editor, file}}, found),
          {==})

def encapsulated_missing_upload(+state: Services.State, ticket: Nat, +result: Result<&2, &2, String, B.Attachment>, observed_directory_picker: {Services.directory_picker(state) == Services.NoDirectoryPicker{} : Services.DirectoryPicker}, missing: {Finite.find(~Services.Transfer, Services.transfers(state), ticket) == None{} : Maybe<&2, Services.Transfer>}) ->
  {Services.step(Services.Uploaded{ticket, result}, state) ==
        Services.Decision{state, Nil{}} : Services.Decision}:
  Services.State{+access, +credential, +settings_open, +appearance, +next, +transfers, +preview, +stored_directory_picker} = state
  backwards_directory_picker = Equal.sym(Services.State, state, restore_directory_picker(Services.NoDirectoryPicker{}, state),
    Equal.cong(Services.DirectoryPicker, Services.State, value => restore_directory_picker(value, state), Services.directory_picker(state), Services.NoDirectoryPicker{}, observed_directory_picker))
  %backwards_directory_picker : {Services.step(Services.Uploaded{ticket, result}, _) ==
        Services.Decision{_, Nil{}} : Services.Decision}
  Equal.cong(Maybe<&2, Services.Transfer>, Services.Decision,
          found => Services.upload_finished(found,
            Services.State{access, credential, settings_open, appearance, next, transfers, preview, Services.NoDirectoryPicker{}}, ticket, result),
          Finite.find(~Services.Transfer, transfers, ticket), None{}, missing)

def encapsulated_stale_auth(+state: Services.State, ticket: Nat, +result: Result<&2, &2, String, Unit>, observed_directory_picker: {Services.directory_picker(state) == Services.NoDirectoryPicker{} : Services.DirectoryPicker}, stale: {Services.expected_access(Services.access(state), ticket) == False{} : Bool}) ->
  {Services.step(Services.Authenticated{ticket, result}, state) ==
        Services.Decision{state, Nil{}} : Services.Decision}:
  Services.State{+access, +credential, +settings_open, +appearance, +next, +transfers, +preview, +stored_directory_picker} = state
  backwards_directory_picker = Equal.sym(Services.State, state, restore_directory_picker(Services.NoDirectoryPicker{}, state),
    Equal.cong(Services.DirectoryPicker, Services.State, value => restore_directory_picker(value, state), Services.directory_picker(state), Services.NoDirectoryPicker{}, observed_directory_picker))
  %backwards_directory_picker : {Services.step(Services.Authenticated{ticket, result}, _) ==
        Services.Decision{_, Nil{}} : Services.Decision}
  Equal.cong(Bool, Services.Decision,
          owned => Services.authentication(owned,
            Services.State{access, credential, settings_open, appearance, next, transfers, preview, Services.NoDirectoryPicker{}}, result),
          Services.expected_access(access, ticket), False{}, stale)

def encapsulated_failed_auth_no_attention(+state: Services.State, reason: String, application: E.Application) ->
  {Core.service_result(Services.authentication(True{}, state, Fail{reason}), application) ==
        Core.application_result_with_services(E.unchanged(application), Services.with_settings_open(True{}, Services.with_credential("", Services.with_access(Services.CredentialRejected{reason}, state))), Nil{}) : Core.Decision}:
  Services.State{+access, +credential, +settings_open, +appearance, +next, +transfers, +preview, +picker} = state
  {==}

def encapsulated_readiness_attention(+state: Services.State, +application: E.Application) ->
  {Core.service_result(Services.authentication(True{}, state, Done{Unit{}}), application) ==
        Core.Decision{Core.from_application(application, Services.with_settings_open(False{}, Services.with_credential("", Services.with_access(Services.Connected{}, state)))), D.success(J.Null{}), Nil{}, [E.Attend{Core.session_attention(application)}], Nil{}, False{}} : Core.Decision}:
  Services.State{+access, +credential, +settings_open, +appearance, +next, +transfers, +preview, +picker} = state
  {==}

def encapsulated_failed_auth(+state: Services.State, reason: String) ->
  {Services.authentication(True{}, state, Fail{reason}) ==
        Services.Decision{Services.with_settings_open(True{}, Services.with_credential("", Services.with_access(Services.CredentialRejected{reason}, state))), Nil{}} : Services.Decision}:
  Services.State{+access, +credential, +settings_open, +appearance, +next, +transfers, +preview, +picker} = state
  {==}

def encapsulated_accepted_auth(+state: Services.State, ticket: Nat, owned: {Services.expected_access(Services.access(state), ticket) == True{} : Bool}) ->
  {Services.step(Services.Authenticated{ticket, Done{Unit{}}}, state) ==
        Services.Decision{Services.with_settings_open(False{}, Services.with_credential("", Services.with_access(Services.Connected{}, state))), [Services.SessionReady{}]} : Services.Decision}:
  Services.State{+access, +credential, +settings_open, +appearance, +next, +transfers, +preview, +picker} = state
  Equal.cong(Bool, Services.Decision, owned => Services.authentication(owned, Services.State{access, credential, settings_open, appearance, next, transfers, preview, picker}, Done{Unit{}}), Services.expected_access(access, ticket), True{}, owned)

def RuleBoundaryLaws.evidence():
  RuleBoundaryLaws.Requirements{
    encapsulated_accepted_auth,
    encapsulated_failed_auth,
    +state => result => {==},
    encapsulated_readiness_attention,
    encapsulated_failed_auth_no_attention,
    state => result => application => {==},
    {==},
    encapsulated_stale_auth,
    encapsulated_missing_upload,
    encapsulated_upload_destination,
    encapsulated_closed_preview,
    encapsulated_stale_preview,
    identity => source => wrap => copy => next => ticket => success => stale =>
      Equal.cong(Bool, Code.Decision,
        owned => Code.copy_result(owned, ticket, success, Code.Block{identity, source,
          Code.CodeView{wrap, copy}, next}),
        Code.same_ticket(copy, ticket), False{}, stale),
    identity => source => wrap => copy => next => ticket => stale =>
      stale_code_expiry(identity, source, wrap, copy, next, ticket, stale),
    identity => source => wrap => copy => next => can_copy =>
      Equal.cong(Bool, Code.Decision,
        allowed => Code.begin(allowed, Code.Block{identity, source,
          Code.CodeView{wrap, copy}, next}),
        Code.code_can_copy(Code.CodeView{wrap, copy}), True{}, can_copy),
    identity => source => wrap => copy => next => {==},
    model => tools => max_fork => max_descendants => plugins => context => task => {==},
    origin => workspace => sandbox => approval => project => guidance => entered_workspace => entered_sandbox => entered_approval => {==},
    project => name => old_workspace => workspace => guidance => now => {==},
    name => workspace => guidance => {==},
    project => name => workspace => guidance => {==},
    text => profile => reasoning => config => observation => now => {==},
    config => workspace => guidance => settings_projection(config, workspace, guidance),
    task => operation => parts => outputs => world => inactive =>
      Equal.cong(Bool, +List<Live.Output>,
        allowed => Live.keep(allowed, Live.Output{task, operation, parts},
          Live.remove(outputs, task, operation)),
        Live.active(Live.Output{task, operation, parts}, world), False{}, inactive),
    task => operation => parts => outputs => world => active =>
      Equal.cong(Bool, +List<Live.Output>,
        allowed => Live.keep(allowed, Live.Output{task, operation, parts},
          Live.remove(outputs, task, operation)),
        Live.active(Live.Output{task, operation, parts}, world), True{}, active)
  }

# Selection changes the node's role, never its bound choice payload.
def finite_choice_payload(+kind: Model.ChoiceKind, +classification: Maybe<&2,Filter.Classification>, +selected: Bool, +description: String, +control: Core.Control, parent: Identity.Key) ->
  {RuleChoiceRules.meaning(Model.finite_choice_control(kind, classification, selected, description, control, parent)) ==
    Model.Choice{kind, classification, selected, description, RuleChoiceRules.control_input(control), RuleChoiceRules.control_availability(control)} : Model.Meaning}:
  match selected:
    case True{}:
      Core.Control{identity, label, prominence, input, availability} = control
      {==}
    case False{}:
      Core.Control{identity, label, prominence, input, availability} = control
      {==}

def filter_payload(+choice: Filter.Choice, +category: String, +filter: B.Filter, parent: Identity.Key, +state: Core.State) ->
  {RuleChoiceRules.meaning(Model.filter_option_node(choice, category, filter, parent, state)) ==
    Model.Choice{Model.MultipleChoice{}, Some{RuleChoiceRules.filter_classification(choice)},
      Schema.contains(Filter.values(category, filter), RuleChoiceRules.filter_value(choice)), "",
      RuleChoiceRules.control_input(Core.control(state, Model.filter_option_declaration(choice, category, filter))),
      RuleChoiceRules.control_availability(Core.control(state, Model.filter_option_declaration(choice, category, filter)))} : Model.Meaning}:
  Filter.Choice{+value, label, classification} = choice
  finite_choice_payload(Model.MultipleChoice{}, Some{classification},
    Schema.contains(Filter.values(category, filter), value), "",
    Core.control(state, Model.filter_option_declaration(choice, category, filter)), Identity.Entity{parent, "filter-option", value})

def RuleChoiceRules.evidence():
  RuleChoiceRules.Requirements{
    kind => classification => selected => description => +input => +availability => {==},
    kind => classification => selected => description => input => +availability => {==},
    choice => category => filter => parent => state => filter_payload(choice, category, filter, parent, state),
    +owner => world => {==},
    +owner => +world => {==},
    value => projects => stages => priorities => +owners => {==},
    value => projects => stages => +priorities => owners => {==}}

# Only direct page regions participate; an entry's ordinary heading is never promoted.
def page_sequence(+page: V.Page, +parent: Identity.Key, +state: Core.State) ->
  {RulePageRegionLaws.observed_regions(Model.page_contents(page, parent, state)) == RulePageRegionLaws.required_regions(page) : +List<Composition.PositionedRegion>}:
  match page:
    case V.StartPage{None{}}:
      Core.State{E.Application{world, session}, services} = state
      {==}
    case V.StartPage{Some{scene}}:
      Core.State{E.Application{world, session}, services} = state
      {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Nil{}, reading, None{}}, previews, None{}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Nil{}, reading, Some{input}}, previews, None{}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Con{first, rest}, reading, None{}}, previews, None{}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Con{first, rest}, reading, Some{input}}, previews, None{}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Nil{}, reading, None{}}, previews, Some{scene}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Nil{}, reading, Some{input}}, previews, Some{scene}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Con{first, rest}, reading, None{}}, previews, Some{scene}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Con{first, rest}, reading, Some{input}}, previews, Some{scene}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.ProjectPage{V.ProjectScene{id, name, D.Workspace{roots, primary}, guidance, tasks, actions}}: {==}
    case V.ProjectsPage{projects, create}: {==}
    case V.BoardPage{filter, columns, create, working, settings, filters, archive}: {==}
    case V.AgentsPage{agents, create}: {==}
    case V.MissingObject{message}: {==}

def page_only_regions(+page: V.Page, +parent: Identity.Key, +state: Core.State) ->
  {RulePageRegionLaws.only_regions(Model.page_contents(page, parent, state)) == True{} : Bool}:
  match page:
    case V.StartPage{None{}}:
      Core.State{E.Application{world, session}, services} = state
      {==}
    case V.StartPage{Some{scene}}:
      Core.State{E.Application{world, session}, services} = state
      {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Nil{}, reading, None{}}, previews, None{}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Nil{}, reading, Some{input}}, previews, None{}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Con{first, rest}, reading, None{}}, previews, None{}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Con{first, rest}, reading, Some{input}}, previews, None{}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Nil{}, reading, None{}}, previews, Some{scene}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Nil{}, reading, Some{input}}, previews, Some{scene}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Con{first, rest}, reading, None{}}, previews, Some{scene}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, Con{first, rest}, reading, Some{input}}, previews, Some{scene}, details, V.TaskActions{detail, overflow}}}: {==}
    case V.ProjectPage{V.ProjectScene{id, name, D.Workspace{roots, primary}, guidance, tasks, actions}}: {==}
    case V.ProjectsPage{projects, create}: {==}
    case V.BoardPage{filter, columns, create, working, settings, filters, archive}: {==}
    case V.AgentsPage{agents, create}: {==}
    case V.MissingObject{message}: {==}

def task_reading(+value: V.TaskScene, +parent: Identity.Key, +state: Core.State) -> RulePageRegionLaws.task_reading(value, parent, state):
  V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, live, decisions, reading, return_latest}, previews, input, details, V.TaskActions{detail, overflow}} = value
  {==}

def task_title(+value: V.TaskScene, +parent: Identity.Key, +state: Core.State) ->
  {RulePageRegionLaws.find_region(Model.page_contents(V.TaskPage{value}, parent, state), Composition.ConversationTitle{}) ==
    Some{[Model.region(RulePageRegionLaws.task_title_key(value, parent), "heading", RulePageRegionLaws.task_title_text(value), Model.Heading{}, Nil{})]} : Maybe<&2, +List<Model.Node>>}:
  match value:
    case V.TaskScene{id, title, status, context, Conversation.Timeline{task, generation, groups, operations, approvals, reading, latest}, previews, composer, details, V.TaskActions{detail, overflow}}: {==}

def project_title(+value: V.ProjectScene, +parent: Identity.Key, +state: Core.State) ->
  {RulePageRegionLaws.find_region(Model.page_contents(V.ProjectPage{value}, parent, state), Composition.ProjectTitle{}) ==
    Some{[Model.region(parent, "heading", RulePageRegionLaws.project_title_text(value), Model.Heading{}, Nil{})]} : Maybe<&2, +List<Model.Node>>}:
  match value:
    case V.ProjectScene{id, name, D.Workspace{roots, primary}, guidance, tasks, actions}: {==}

def layer_title_evidence() -> RulePageRegionLaws.LayerTitleRequirements:
  RulePageRegionLaws.LayerTitleRequirements{
    {==},
    task => {==},
    {==},
    id => {==},
    {==},
    id => {==},
    {==},
    id => {==},
    task => {==},
    task => {==},
    actions => {==},
    cards => {==},
    automatic => selected => profiles => automation => {==},
    filter => {==},
    {==},
    identity => revision => groups => sections => submit => feedback => pending => {==},
    editor => fields => {==},
    editor => fields => {==},
    context => {==},
    editor => query => fields => {==},
    editor => fields => {==},
    task => {==},
    title => confirm => cancel => {==}}

def collapsed_assembly(+content: Core.Scene, +state: Core.State,
  collapsed: {RulePageRegionLaws.content_navigation_placement(content) == V.CollapsedNavigation{} : V.NavigationPlacement}) ->
  {RulePageRegionLaws.navigation_head(RulePageRegionLaws.surface_base(Model.assemble(content, state))) ==
    RulePageRegionLaws.navigation_head(Model.collapsed_navigation_toggle(RulePageRegionLaws.content_navigation(content), state)) : Model.Node}:
  match content:
    case Core.Scene{V.Scene{V.Navigation{+expanded, +create, +destinations, +projects, +tasks, +toggle}, +main, +layers, V.Arrangement{+placement}, +attention}, +settings, +transfers, +preview, +code, directory_picker}:
      +nav: V.Navigation = V.Navigation{expanded, create, destinations, projects, tasks, toggle}
      Equal.cong(V.NavigationPlacement, Model.Node,
        (position => RulePageRegionLaws.navigation_head(RulePageRegionLaws.surface_base(Model.assemble(Core.Scene{V.Scene{nav, main, layers,
          V.Arrangement{position}, attention}, settings, transfers, preview, code, directory_picker}, state)))),
        placement, V.CollapsedNavigation{}, collapsed)

def page_payload(+page: V.Page, +state: Core.State) ->
  {Model.page(page, state) == Model.Node{Identity.Place{"/main"}, "main", "Content", Model.Main{}, Model.PageContext{RulePageRegionLaws.owned_page_context(page)}, Model.page_contents(page, Identity.Place{"/main"}, state)} : Model.Node}:
  match page:
    case V.StartPage{composer}: {==}
    case V.TaskPage{V.TaskScene{id, title, status, context, timeline, previews, input, details, actions}}: {==}
    case V.ProjectPage{project}: {==}
    case V.ProjectsPage{projects, create}: {==}
    case V.BoardPage{filter, columns, create, working, settings, filters, archive}: {==}
    case V.AgentsPage{agents, create}: {==}
    case V.MissingObject{message}: {==}

def RulePageRegionLaws.evidence():
  RulePageRegionLaws.Requirements{page => state => page_payload(page, state), +toggle => expanded => create => destinations => projects => tasks => +state => {==}, collapsed_assembly,
    layer_title_evidence(),
    +kind => +content => +initial => +restore => +close => +state => {==},
    +kind => +content => +first => +second => +restore => +close => +state => {==},
    +kind => +content => +initial => +restore => +close => +state => {==},
    page => parent => state => page_sequence(page, parent, state),
    page => parent => state => page_only_regions(page, parent, state),
    +projects => +create => +parent => +state => {==},
    +agents => +create => +parent => +state => {==},
    +filter => +columns => +create => working => +settings => +filters => +archive => +parent => +state => {==},
    +heading => +summary => +context => +project => +choose => +parent => +state => {==},
    task_reading,
    value => parent => state => task_title(value, parent, state),
    value => parent => state => project_title(value, parent, state),
    region => position => gesture => {==},
    +parent => +region => +position => +children => {==},
    +parent => +region => +position => +children => {==}}

def Rule.interface_input(input, state):
  {==}

def Rule.interface_evidence():
  Rule.InterfaceRequirements{Rule.interface_input}

def registered_choices_complete(+entries: +List<Finite.Entry(D.Project)>) ->
  {List.length(&2, V.ProjectChoice, V.project_choices(entries)) == List.length(&2, Finite.Entry(D.Project), entries) : Nat}:
  match entries:
    case Nil{}: {==}
    case Con{(id, D.Project{name, workspace, guidance}), +rest}:
      Equal.cong(Nat, Nat, (n => (1n + n : Nat)), List.length(&2, V.ProjectChoice, V.project_choices(rest)), List.length(&2, Finite.Entry(D.Project), rest), registered_choices_complete(rest))

def nat_same(+value: Nat) -> {Nat.is_eq(value, value) == True{} : Bool}:
  match value:
    case 0n: {==}
    case 1n+rest: nat_same(rest)

def deletion_retains_head(+other: Nat, +id: Nat, +tail: +List<Nat>, distinct: {Nat.is_eq(id, other) == False{} : Bool}) ->
  {List.contains(~Nat, ~Nat.is_eq, E.without_collapsed_project(other <> tail, id), other) == True{} : Bool}:
  backwards = Equal.sym(Bool, Nat.is_eq(id, other), False{}, distinct)
  %backwards : {List.contains(~Nat, ~Nat.is_eq, Std.map(~Finite.Entry(Nat), ~Nat, ~(entry => E.project_disclosure_value(entry)),
    Finite.keep(~Nat, Bool.not(_), other, 0n, Finite.remove(~Nat, Std.map(~Nat, ~Finite.Entry(Nat), ~(current => (current, 0n)), tail), id))), other) == True{} : Bool}
  same = Equal.sym(Bool, Nat.is_eq(other, other), True{}, nat_same(other))
  %same : {Bool.or(_, List.contains(~Nat, ~Nat.is_eq, E.without_collapsed_project(tail, id), other)) == True{} : Bool}
  {==}

def deletion_retains_step(hit: Bool, +head: Nat, +tail: +List<Nat>, +id: Nat, +other: Nat,
  observed: {Nat.is_eq(id, head) == hit : Bool},
  induction: {List.contains(~Nat, ~Nat.is_eq, E.without_collapsed_project(tail, id), other) == True{} : Bool}) ->
  {List.contains(~Nat, ~Nat.is_eq, E.without_collapsed_project(head <> tail, id), other) == True{} : Bool}:
  match hit:
    case True{}:
      backwards = Equal.sym(Bool, Nat.is_eq(id, head), True{}, observed)
      %backwards : {List.contains(~Nat, ~Nat.is_eq, Std.map(~Finite.Entry(Nat), ~Nat, ~(entry => E.project_disclosure_value(entry)),
        Finite.keep(~Nat, Bool.not(_), head, 0n, Finite.remove(~Nat, Std.map(~Nat, ~Finite.Entry(Nat), ~(current => (current, 0n)), tail), id))), other) == True{} : Bool}
      induction
    case False{}:
      backwards = Equal.sym(Bool, Nat.is_eq(id, head), False{}, observed)
      %backwards : {List.contains(~Nat, ~Nat.is_eq, Std.map(~Finite.Entry(Nat), ~Nat, ~(entry => E.project_disclosure_value(entry)),
        Finite.keep(~Nat, Bool.not(_), head, 0n, Finite.remove(~Nat, Std.map(~Nat, ~Finite.Entry(Nat), ~(current => (current, 0n)), tail), id))), other) == True{} : Bool}
      prior = Equal.sym(Bool, List.contains(~Nat, ~Nat.is_eq, E.without_collapsed_project(tail, id), other), True{}, induction)
      %prior : {Bool.or(Nat.is_eq(head, other), _) == True{} : Bool}
      Std.orb_true_r(Nat.is_eq(head, other))

def deletion_retains_other(+prefix: +List<Nat>, +other: Nat, +suffix: +List<Nat>, +id: Nat,
  distinct: {Nat.is_eq(id, other) == False{} : Bool}) ->
  {List.contains(~Nat, ~Nat.is_eq, E.without_collapsed_project(List.append(&2, Nat, prefix, other <> suffix), id), other) == True{} : Bool}:
  match prefix:
    case Nil{}: deletion_retains_head(other, id, suffix, distinct)
    case Con{+head, +rest}: deletion_retains_step(Nat.is_eq(id, head), head, List.append(&2, Nat, rest, other <> suffix), id, other, {==}, deletion_retains_other(rest, other, suffix, id, distinct))

def existing_other_head(+other: Nat, +suffix: +List<Nat>) ->
  {List.contains(~Nat, ~Nat.is_eq, other <> suffix, other) == True{} : Bool}:
  backwards = Equal.sym(Bool, Nat.is_eq(other, other), True{}, nat_same(other))
  %backwards : {Bool.or(_, List.contains(~Nat, ~Nat.is_eq, suffix, other)) == True{} : Bool}
  {==}

def existing_other(+prefix: +List<Nat>, +other: Nat, +suffix: +List<Nat>) ->
  {List.contains(~Nat, ~Nat.is_eq, List.append(&2, Nat, prefix, other <> suffix), other) == True{} : Bool}:
  match prefix:
    case Nil{}: existing_other_head(other, suffix)
    case Con{+head, +rest}:
      backwards = Equal.sym(Bool, List.contains(~Nat, ~Nat.is_eq, List.append(&2, Nat, rest, other <> suffix), other), True{}, existing_other(rest, other, suffix))
      %backwards : {Bool.or(Nat.is_eq(head, other), _) == True{} : Bool}
      Std.orb_true_r(Nat.is_eq(head, other))

def toggle_retains_case(hit: Bool, +prefix: +List<Nat>, +other: Nat, +suffix: +List<Nat>, +id: Nat,
  distinct: {Nat.is_eq(id, other) == False{} : Bool}) ->
  {List.contains(~Nat, ~Nat.is_eq, E.toggle_collapsed(hit, id, List.append(&2, Nat, prefix, other <> suffix)), other) == True{} : Bool}:
  match hit:
    case True{}: deletion_retains_other(prefix, other, suffix, id, distinct)
    case False{}:
      backwards = Equal.sym(Bool, List.contains(~Nat, ~Nat.is_eq, List.append(&2, Nat, prefix, other <> suffix), other), True{}, existing_other(prefix, other, suffix))
      %backwards : {Bool.or(Nat.is_eq(id, other), _) == True{} : Bool}
      Std.orb_true_r(Nat.is_eq(id, other))

def picker_complete_nodes(+values: +List<V.ProjectChoice>, +selected: Maybe<&2, Nat>, +parent: Identity.Key, +state: Core.State) -> RuleProjectInteractionLaws.picker_nodes(values, selected, parent, state):
  {==}

def encapsulated_missing_draft_focus(+session: E.Session, +project: Maybe<&2, Nat>, +world: M.World(), observed_drafts: {E.drafts(session) == Nil{} : +List<U.Draft>}) ->
  {E.activate_selected(U.SelectProject{project}, E.from_program(world, session)) ==
        E.local(world, E.with_navigation(E.navigation_after_visit(E.navigation(session)), E.with_attention("composer/" ++ U.editor_key(U.NewTaskEditor{}), E.with_layers(Nil{}, E.with_route(U.Start{}, session)))),
          [E.Attend{"composer/" ++ U.editor_key(U.NewTaskEditor{})}]) : E.Decision}:
  E.Session{+route, +stored_drafts, +readers, +layers, +attention, +navigation, +filter, +now, +next, +pending, +previews, +code, +next_layer} = session
  backwards_drafts = Equal.sym(E.Session, session, E.with_drafts(Nil{}, session),
    Equal.cong(+List<U.Draft>, E.Session, value => E.with_drafts(value, session), E.drafts(session), Nil{}, observed_drafts))
  %backwards_drafts : {E.activate_selected(U.SelectProject{project}, E.from_program(world, _)) ==
        E.local(world, E.with_navigation(E.navigation_after_visit(E.navigation(_)), E.with_attention("composer/" ++ U.editor_key(U.NewTaskEditor{}), E.with_layers(Nil{}, E.with_route(U.Start{}, _)))),
          [E.Attend{"composer/" ++ U.editor_key(U.NewTaskEditor{})}]) : E.Decision}
  {==}

def encapsulated_select_focus_and_input(+session: E.Session, +project: Maybe<&2, Nat>, +world: M.World(), +revision: Nat, +message: U.Text, +profile: String, +reasoning: String, +old: Context.Origin, +workspace: Maybe<&2, D.Workspace>, +sandbox: Maybe<&2, D.Sandbox>, +approval: Maybe<&2, Context.ApprovalChoice>, +feedback: U.Feedback, +directory_entry: String, +rest: +List<U.Draft>, observed_drafts: {E.drafts(session) == U.Draft{revision, U.NewTask{message, profile, reasoning, Context.Configuration{old, workspace, sandbox, approval}}, feedback, directory_entry} <> rest : +List<U.Draft>}) ->
  {E.activate_selected(U.SelectProject{project}, E.from_program(world, session)) ==
        E.local(world, E.with_navigation(E.navigation_after_visit(E.navigation(session)), E.with_attention("composer/" ++ U.editor_key(U.NewTaskEditor{}), E.with_layers(Nil{}, E.with_drafts(E.put_draft(U.Draft{(revision + 1n : Nat), U.NewTask{message, profile, reasoning, Context.Configuration{E.context_project(project), workspace, sandbox, approval}}, U.Editing{}, directory_entry},
            U.Draft{revision, U.NewTask{message, profile, reasoning, Context.Configuration{old, workspace, sandbox, approval}}, feedback, directory_entry} <> rest), E.with_route(U.Start{}, session))))),
          [E.Attend{"composer/" ++ U.editor_key(U.NewTaskEditor{})}]) : E.Decision}:
  E.Session{+route, +stored_drafts, +readers, +layers, +attention, +navigation, +filter, +now, +next, +pending, +previews, +code, +next_layer} = session
  backwards_drafts = Equal.sym(E.Session, session, E.with_drafts(U.Draft{revision, U.NewTask{message, profile, reasoning, Context.Configuration{old, workspace, sandbox, approval}}, feedback, directory_entry} <> rest, session),
    Equal.cong(+List<U.Draft>, E.Session, value => E.with_drafts(value, session), E.drafts(session), U.Draft{revision, U.NewTask{message, profile, reasoning, Context.Configuration{old, workspace, sandbox, approval}}, feedback, directory_entry} <> rest, observed_drafts))
  %backwards_drafts : {E.activate_selected(U.SelectProject{project}, E.from_program(world, _)) ==
        E.local(world, E.with_navigation(E.navigation_after_visit(E.navigation(_)), E.with_attention("composer/" ++ U.editor_key(U.NewTaskEditor{}), E.with_layers(Nil{}, E.with_drafts(E.put_draft(U.Draft{(revision + 1n : Nat), U.NewTask{message, profile, reasoning, Context.Configuration{E.context_project(project), workspace, sandbox, approval}}, U.Editing{}, directory_entry},
            U.Draft{revision, U.NewTask{message, profile, reasoning, Context.Configuration{old, workspace, sandbox, approval}}, feedback, directory_entry} <> rest), E.with_route(U.Start{}, _))))),
          [E.Attend{"composer/" ++ U.editor_key(U.NewTaskEditor{})}]) : E.Decision}
  {==}

def encapsulated_picker_search_preserves_session(+session: E.Session, +query: String, +world: M.World(), +trigger: String, +initial: String, previous: String, +layer_occurrence: Nat, +rest: +List<E.Layer>, observed_layers: {E.layers(session) == E.Layer{U.ProjectPicker{}, trigger, initial, previous, layer_occurrence} <> rest : +List<E.Layer>}) ->
  {E.search_choices(query, E.from_program(world, session)) ==
        E.local(world, E.with_layers(E.Layer{U.ProjectPicker{}, trigger, initial, query, layer_occurrence} <> rest, session), Nil{}) : E.Decision}:
  E.Session{+route, +drafts, +readers, +stored_layers, +attention, +navigation, +filter, +now, +next, +pending, +previews, +code, +next_layer} = session
  backwards_layers = Equal.sym(E.Session, session, E.with_layers(E.Layer{U.ProjectPicker{}, trigger, initial, previous, layer_occurrence} <> rest, session),
    Equal.cong(+List<E.Layer>, E.Session, value => E.with_layers(value, session), E.layers(session), E.Layer{U.ProjectPicker{}, trigger, initial, previous, layer_occurrence} <> rest, observed_layers))
  %backwards_layers : {E.search_choices(query, E.from_program(world, _)) ==
        E.local(world, E.with_layers(E.Layer{U.ProjectPicker{}, trigger, initial, query, layer_occurrence} <> rest, _), Nil{}) : E.Decision}
  {==}

def encapsulated_toggle_keeps_location(+session: E.Session, +project: Nat, +world: M.World()) ->
  {E.toggle_project(project, E.from_program(world, session)) ==
        E.local(world, E.with_navigation(E.toggle_project_navigation(project, E.navigation(session)), session), Nil{}) : E.Decision}:
  E.Session{+route, +drafts, +readers, +layers, +attention, +navigation, +filter, +now, +next, +pending, +previews, +code, +next_layer} = session
  {==}

def RuleProjectInteractionLaws.evidence():
  RuleProjectInteractionLaws.Requirements{
    +origin => +message => +profile => +reasoning => +old => +workspace => +sandbox => +approval => world => {==},
    +project => +application => {==},
    expanded => intent => +collapsed => {==},
    intent => +collapsed => {==},
    encapsulated_toggle_keeps_location,
    +id => drafts => +world => {==},
    +drafts => +world => {==},
    entries => registered_choices_complete(entries),
    +query => +selected => +projects => {==},
    +id => +name => +workspace => guidance => +tasks => +route => +selected => +navigation => {==},
    +id => +now => +world => {==},
    +id => +name => +workspace => {==},
    +id => title => +status => +selected => +open => +parent => +state => {==},
    prefix => other => suffix => id => distinct => deletion_retains_other(prefix, other, suffix, id, distinct),
    +intent => +prefix => +other => +suffix => +id => distinct => toggle_retains_case(E.project_collapsed(E.NavigationState{intent, List.append(&2, Nat, prefix, other <> suffix)}, id), prefix, other, suffix, id, distinct),
    +id => +intent => collapsed => {==},
    picker_complete_nodes,
    +context => +world => {==},
    encapsulated_picker_search_preserves_session,
    +id => name => workspace => +selected => +expanded => +tasks => +open => +create => +toggle => +more => +parent => +state => {==},
    context => {==},
    +parent => state => {==},
    +first => +rest => +parent => +state => {==},
    encapsulated_select_focus_and_input,
    encapsulated_missing_draft_focus,
    +task => {==},
    +lifecycle => +working => {==},
    +task => {==}
  }

def absent_input_is_quiet(+state: Core.State) ->
  {Model.apply_input(None{}, state) == RuleSurfaceLaws.quiet_decision(state) : Core.Decision}:
  Core.State{application, services} = state
  {==}

def resolve_absent(+surface: Model.Surface, +key: String, +gesture: Model.Gesture,
  absent: {Model.find_node(Model.active_nodes(surface), key) == None{} : Maybe<&2, Model.Node>}) ->
  {Model.resolve(surface, key, gesture) == None{} : Maybe<&2, Core.Input>}:
  Equal.cong(Maybe<&2, Model.Node>, Maybe<&2, Core.Input>,
    source => Model.resolve_source(source, gesture, surface),
    Model.find_node(Model.active_nodes(surface), key), None{}, absent)

def resolve_unavailable(+surface: Model.Surface, +key: String, +input: Core.Input, +reason: String,
  +node_key: Identity.Key, +semantic: String, +label: String, +role: Model.Role,
  +children: +List<Model.Node>,
  found: {Model.find_node(Model.active_nodes(surface), key) ==
    Some{Model.Node{node_key, semantic, label, role, Model.Activate{input, V.Unavailable{reason}}, children}} : Maybe<&2, Model.Node>}) ->
  {Model.resolve(surface, key, Model.Press{}) == None{} : Maybe<&2, Core.Input>}:
  Equal.trans(Maybe<&2, Core.Input>,
    Model.resolve(surface, key, Model.Press{}),
    Model.resolve_source(Some{Model.Node{node_key, semantic, label, role,
      Model.Activate{input, V.Unavailable{reason}}, children}}, Model.Press{}, surface),
    None{},
    Equal.cong(Maybe<&2, Model.Node>, Maybe<&2, Core.Input>,
      source => Model.resolve_source(source, Model.Press{}, surface),
      Model.find_node(Model.active_nodes(surface), key),
      Some{Model.Node{node_key, semantic, label, role,
        Model.Activate{input, V.Unavailable{reason}}, children}}, found),
    {==})

def resolve_available(+surface: Model.Surface, +key: String, +input: Core.Input,
  +node_key: Identity.Key, +semantic: String, +label: String, +role: Model.Role,
  +children: +List<Model.Node>,
  found: {Model.find_node(Model.active_nodes(surface), key) ==
    Some{Model.Node{node_key, semantic, label, role, Model.Activate{input, V.Available{}}, children}} : Maybe<&2, Model.Node>}) ->
  {Model.resolve(surface, key, Model.Press{}) == Some{input} : Maybe<&2, Core.Input>}:
  Equal.trans(Maybe<&2, Core.Input>,
    Model.resolve(surface, key, Model.Press{}),
    Model.resolve_source(Some{Model.Node{node_key, semantic, label, role,
      Model.Activate{input, V.Available{}}, children}}, Model.Press{}, surface),
    Some{input},
    Equal.cong(Maybe<&2, Model.Node>, Maybe<&2, Core.Input>,
      source => Model.resolve_source(source, Model.Press{}, surface),
      Model.find_node(Model.active_nodes(surface), key),
      Some{Model.Node{node_key, semantic, label, role,
        Model.Activate{input, V.Available{}}, children}}, found),
    {==})

def element_without_resolution(+capacity: V.Capacity, +state: Core.State, +key: String,
  +gesture: Model.Gesture,
  unresolved: {Model.resolve(ProductUI.observe(capacity, state), key, gesture) == None{} : Maybe<&2, Core.Input>}) ->
  {ProductUI.step(ProductUI.Element{capacity, key, gesture}, state) == RuleSurfaceLaws.quiet_decision(state) : Core.Decision}:
  Equal.trans(Core.Decision,
    ProductUI.step(ProductUI.Element{capacity, key, gesture}, state),
    Model.perform(capacity, state, key, None{}),
    RuleSurfaceLaws.quiet_decision(state),
    Equal.cong(Maybe<&2, Core.Input>, Core.Decision,
      input => Model.perform(capacity, state, key, input),
      Model.resolve(ProductUI.observe(capacity, state), key, gesture), None{}, unresolved),
    Equal.trans(Core.Decision,
      Model.perform(capacity, state, key, None{}),
      Model.apply_input(None{}, state),
      RuleSurfaceLaws.quiet_decision(state),
      {==}, absent_input_is_quiet(state)))

def receipt_source(+decision: Core.Decision, previous: +List<E.Layer>, origin: String) ->
  {RuleSurfaceLaws.receipt(Model.source_decision(decision, previous, origin)) == RuleSurfaceLaws.receipt(decision) : RuleSurfaceLaws.Receipt}:
  Core.Decision{Core.State{E.Application{program, session}, services}, reply, runtime, interaction, service_effects, durable} = decision
  {==}

def receipt_record_source(+before: Core.State, key: String, +decision: Core.Decision) ->
  {RuleSurfaceLaws.receipt(Model.record_source(before, key, decision)) == RuleSurfaceLaws.receipt(decision) : RuleSurfaceLaws.Receipt}:
  Core.State{E.Application{program, E.Session{route, drafts, readers, +layers, attention,
    navigation, filter, now, next, pending, previews, code, next_layer}}, services} = before
  receipt_source(decision, layers, Model.origin(layers, key))

def receipt_navigation_closed(+decision: Core.Decision) ->
  {RuleSurfaceLaws.receipt(Model.navigation_closed(decision)) == RuleSurfaceLaws.receipt(decision) : RuleSurfaceLaws.Receipt}:
  Core.Decision{Core.State{E.Application{program, session}, services}, reply, runtime, interaction, service_effects, durable} = decision
  {==}

def receipt_after_navigation(dismiss: Bool, +decision: Core.Decision) ->
  {RuleSurfaceLaws.receipt(Model.after_navigation(dismiss, decision)) == RuleSurfaceLaws.receipt(decision) : RuleSurfaceLaws.Receipt}:
  match dismiss:
    case False{}: {==}
    case True{}: receipt_navigation_closed(decision)

def receipt_perform_present(+capacity: V.Capacity, +state: Core.State, +key: String,
  +input: Maybe<&2, Core.Input>) ->
  {RuleSurfaceLaws.receipt(Model.perform_present(capacity, state, key, input)) == RuleSurfaceLaws.receipt(Model.apply_input(input, state)) : RuleSurfaceLaws.Receipt}:
  V.Capacity{navigation_beside, details_beside} = capacity
  Equal.trans(RuleSurfaceLaws.Receipt,
    RuleSurfaceLaws.receipt(Model.perform_present(capacity, state, key, input)),
    RuleSurfaceLaws.receipt(Model.record_source(state, key, Model.apply_input(input, state))),
    RuleSurfaceLaws.receipt(Model.apply_input(input, state)),
    receipt_after_navigation(Bool.not(navigation_beside) && Model.navigates(input),
      Model.record_source(state, key, Model.apply_input(input, state))),
    receipt_record_source(state, key, Model.apply_input(input, state)))

def receipt_perform_input(+input: Maybe<&2, Core.Input>, +capacity: V.Capacity,
  +state: Core.State, +key: String) ->
  {RuleSurfaceLaws.receipt(Model.perform_input(input, capacity, state, key)) == RuleSurfaceLaws.receipt(Model.apply_input(input, state)) : RuleSurfaceLaws.Receipt}:
  match input:
    case None{}: {==}
    case Some{value}: receipt_perform_present(capacity, state, key, Some{value})

def receipt_perform(+capacity: V.Capacity, +state: Core.State, +key: String,
  +input: Maybe<&2, Core.Input>) ->
  {RuleSurfaceLaws.receipt(Model.perform(capacity, state, key, input)) == RuleSurfaceLaws.receipt(Model.apply_input(input, state)) : RuleSurfaceLaws.Receipt}:
  receipt_perform_input(input, capacity, state, key)

def element_receipt(+capacity: V.Capacity, +state: Core.State, +key: String,
  +gesture: Model.Gesture) ->
  {RuleSurfaceLaws.receipt(ProductUI.step(ProductUI.Element{capacity, key, gesture}, state)) ==
    RuleSurfaceLaws.receipt(Model.apply_input(Model.resolve(ProductUI.observe(capacity, state), key, gesture), state)) : RuleSurfaceLaws.Receipt}:
  receipt_perform(capacity, state, key, Model.resolve(ProductUI.observe(capacity, state), key, gesture))

def RuleSurfaceLaws.evidence():
  RuleSurfaceLaws.Requirements{
    +capacity => +state => +key => +gesture => absent =>
      element_without_resolution(capacity, state, key, gesture,
        resolve_absent(ProductUI.observe(capacity, state), key, gesture, absent))
    ,
    +capacity => +state => +key => +input => +reason => +node_key => +semantic => +label => +role => +children => found =>
      element_without_resolution(capacity, state, key, Model.Press{},
        resolve_unavailable(ProductUI.observe(capacity, state), key, input, reason, node_key, semantic, label, role, children, found))
    ,
    +capacity => +state => +editor => absent =>
      Equal.trans(Core.Decision,
        ProductUI.step(ProductUI.SubmitComposer{capacity, editor}, state),
        Model.submit_found(None{}, capacity, state),
        RuleSurfaceLaws.quiet_decision(state),
        Equal.cong(Maybe<&2, Model.Node>, Core.Decision,
          found => Model.submit_found(found, capacity, state),
          Model.submission(Model.active_nodes(ProductUI.observe(capacity, state)), editor), None{}, absent),
        absent_input_is_quiet(state))
    ,
    capacity => state => key => gesture => element_receipt(capacity, state, key, gesture),
    +capacity => +state => +key => +input => +node_key => +semantic => +label => +role => +children => found =>
      Equal.trans(RuleSurfaceLaws.Receipt,
        RuleSurfaceLaws.receipt(ProductUI.step(ProductUI.Element{capacity, key, Model.Press{}}, state)),
        RuleSurfaceLaws.receipt(Model.apply_input(Model.resolve(ProductUI.observe(capacity, state), key, Model.Press{}), state)),
        RuleSurfaceLaws.receipt(Core.step(input, state)),
        element_receipt(capacity, state, key, Model.Press{}),
        Equal.cong(Maybe<&2, Core.Input>, RuleSurfaceLaws.Receipt,
          resolved => RuleSurfaceLaws.receipt(Model.apply_input(resolved, state)),
          Model.resolve(ProductUI.observe(capacity, state), key, Model.Press{}), Some{input},
          resolve_available(ProductUI.observe(capacity, state), key, input, node_key, semantic, label, role, children, found)))
    ,
    +previous => origin => +panel => trigger => initial_attention => query => +layer_occurrence => +rest => present =>
      Equal.cong(Bool, +List<E.Layer>,
        unchanged => E.Layer{panel, Model.layer_trigger(unchanged, trigger, origin), initial_attention, query, layer_occurrence} <> rest,
        Model.layer_present(previous, E.panel_target(panel)), True{}, present)
    ,
    +previous => origin => +panel => trigger => initial_attention => query => +layer_occurrence => +rest => absent =>
      Equal.cong(Bool, +List<E.Layer>,
        unchanged => E.Layer{panel, Model.layer_trigger(unchanged, trigger, origin), initial_attention, query, layer_occurrence} <> rest,
        Model.layer_present(previous, E.panel_target(panel)), False{}, absent)
    }

def production_noop(+draft: U.Draft, +world: M.World(), +session: E.Session,
  denied: {U.can_confirm_directory(draft) == False{} : Bool}) ->
  {E.edit_existing(U.ConfirmDirectory{}, draft, world, session) == E.unchanged(E.Application{world, session}) : E.Decision}:
  Equal.cong(Bool, E.Decision, admitted => E.confirm_found(admitted, draft, world, session),
    U.can_confirm_directory(draft), False{}, denied)

def RuleDirectoryEntryLaws.evidence():
  RuleDirectoryEntryLaws.Requirements{+revision => +body => feedback => old => +path => world => {==}, revision => body => feedback => +path => {==}, roots => +path => {==}, roots => {==}, {==}, +revision => +body => feedback => +path => +world => admitted =>
      Equal.cong(Bool, Result<&2, &2, String, U.Draft>,
        accepted => U.confirm_directory(accepted, U.Draft{revision, body, feedback, path}, world),
        U.can_confirm_directory(U.Draft{revision, body, feedback, path}), True{}, admitted)
    , +draft => +world => denied =>
      Equal.cong(Bool, Result<&2, &2, String, U.Draft>, accepted => U.confirm_directory(accepted, draft, world),
        U.can_confirm_directory(draft), False{}, denied)
    , revision => +text => old_profile => old_reasoning => +context => feedback => +entry => +profile => +reasoning => world => {==}, revision => +text => +profile => +reasoning => +context => feedback => +entry => +origin => world => {==}, revision => body => feedback => +world => +session => {==}, revision => +body => feedback => +entry => +world => +session => unsupported =>
      production_noop(U.Draft{revision, body, feedback, entry}, world, session,
        SubmissionProof.conjunction_right_false(Bool.not(String.eq(entry, "")), U.workspace_capable(body), unsupported))
    , +revision => +text => +profile => +reasoning => +context => feedback => +entry => +origin => +world => +session => {==}, production_noop, +editor => text => +path => {==}, +editor => +parent => +state => {==}, +editor => {==}, +editor => text => {==}}

# Service completion ownership and selection use the actual production functions.

def picker_closed(+state: Services.State) ->
  {Services.step(Services.CloseDirectoryPicker{}, state) == Services.Decision{Services.replace_directory(state, Services.NoDirectoryPicker{}), Nil{}} : Services.Decision}:
  Services.State{access, credential, settings, appearance, next, transfers, preview, picker} = state
  {==}

def RuleDirectoryEntryLaws.directory_picker_requirements():
  RuleDirectoryEntryLaws.DirectoryPickerRequirements{picker_closed, +ticket => +result => +state => {==}, +current => editor => path => trigger => +ticket => +result => +state => stale =>
      Equal.cong(Bool, Services.Decision, (owned => Services.finish_directory(owned, current, editor, path, trigger, result, state)),
        Nat.is_eq(current, ticket), False{}, stale)
    , ticket => +editor => entered => +trigger => +path => +parent => +entries => +truncated => +state => {==}, ticket => +editor => +path => parent => entries => truncated => location => trigger => +state => {==}, editor => path => {==}, +editor => +path => +application => rest => {==}, +editor => path => +application => unavailable =>
      Equal.cong(Bool, E.Application,
        (accepted => Core.directory_chosen_accepted(accepted, editor, path, application)),
        Core.accepts_directory(editor, application), False{}, unavailable)
    , +editor => +path => +application => accepted =>
      Equal.cong(Bool, E.Application,
        (allowed => Core.directory_chosen_accepted(allowed, editor, path, application)),
        Core.accepts_directory(editor, application), True{}, accepted)
    }


def RuleDirectoryEntryLaws.directory_identity_requirements():
  RuleDirectoryEntryLaws.DirectoryIdentityRequirements{
    +path => primary => choose => remove => +parent => state => {==},
    +path => control => +parent => state => {==},
    path => primary => choose => remove => +parent => state => other => name => {==},
    path => primary => choose => remove => +parent => state => other => name => {==}}

def RuleDirectoryEntryLaws.directory_ready_regions(ticket, editor, path, parent, entries, truncated, location, trigger):
  {==}

def RuleDirectoryEntryLaws.directory_location_navigation_regions(ticket, editor, path, parent, entries, truncated, location, trigger):
  {==}

def conversation_recipe_evidence(composer: Bool, approvals: Bool, return_latest: Bool)
  -> RuleCompositionLaws.conversation_recipe_law(composer, approvals, return_latest):
  match composer approvals return_latest:
    case False{} False{} False{}: {==}
    case False{} False{} True{}: {==}
    case False{} True{} False{}: {==}
    case False{} True{} True{}: {==}
    case True{} False{} False{}: {==}
    case True{} False{} True{}: {==}
    case True{} True{} False{}: {==}
    case True{} True{} True{}: {==}

def task_recipe_components_evidence(composer: Maybe<&2, V.ComposerScene>, approvals: +List<Conversation.DecisionRequest>, return_latest: Maybe<&2, U.Input>)
  -> {Composition.Recipe{Composition.ReadingMeasure{}, Composition.ConversationHeading{}, Composition.ChronologicalReading{},
        Composition.bottom_composer(V.has_composer(composer)), Composition.decisions(V.has_decisions(approvals)), Composition.latest(V.has_return_latest(return_latest))} ==
      Composition.Recipe{Composition.ReadingMeasure{}, Composition.ConversationHeading{}, Composition.ChronologicalReading{},
        RuleCompositionLaws.expected_bottom_composer(RuleCompositionLaws.has_composer(composer)), RuleCompositionLaws.expected_decisions(V.has_decisions(approvals)), RuleCompositionLaws.expected_latest(V.has_return_latest(return_latest))} : Composition.Recipe}:
  match composer approvals return_latest:
    case None{} Nil{} None{}: {==}
    case None{} Nil{} Some{input}: {==}
    case None{} Con{decision, rest} None{}: {==}
    case None{} Con{decision, rest} Some{input}: {==}
    case Some{scene} Nil{} None{}: {==}
    case Some{scene} Nil{} Some{input}: {==}
    case Some{scene} Con{decision, rest} None{}: {==}
    case Some{scene} Con{decision, rest} Some{input}: {==}

def task_recipe_evidence(task: V.TaskScene)
  -> {Composition.recipe(V.page_composition(V.TaskPage{task})) == RuleCompositionLaws.expected_task_recipe(task) : Composition.Recipe}:
  V.TaskScene{task_id, title, status, context, timeline, previews, composer, details, actions} = task
  Conversation.Timeline{task_id, generation, groups, operations, approvals, reading, return_to_latest} = timeline
  task_recipe_components_evidence(composer, approvals, return_to_latest)

def action_evidence(parent: Identity.Key, control: Core.Control)
  -> {Model.action(parent, control) == RuleCompositionLaws.expected_action(parent, control) : Model.Node}:
  match control:
    case Core.Control{+identity, label, V.Primary{}, input, availability}: {==}
    case Core.Control{+identity, label, V.Destructive{}, input, availability}: {==}
    case Core.Control{+identity, label, V.Secondary{}, input, availability}: {==}

def visible_speaker_evidence(+id: Nat, speaker: Conversation.Speaker, +text: String, +source: D.Message,
    +task: Nat, +parent: Identity.Key, +state: Core.State)
  -> {RuleCompositionLaws.first_speech_projection(Model.groups([Conversation.VisibleSpeech{id, speaker, text, source}], task, parent, state)) ==
      Some{RuleCompositionLaws.SpeechProjection{Identity.Entity{parent, "message", Nat.show(id)}, "message/" ++ Nat.show(id), "Message",
        RuleCompositionLaws.expected_speaker_role(speaker), Model.RichText{Code.Message{task, id}, text}}} : Maybe<&2, RuleCompositionLaws.SpeechProjection>}:
  match speaker:
    case Conversation.UserSpeech{}: {==}
    case Conversation.AssistantSpeech{}: {==}

def structure_evidence(recipe: Composition.Recipe)
  -> {Composition.structure(recipe) == RuleCompositionLaws.expected_structure(recipe) : Composition.Structure}:
  match recipe:
    case Composition.Recipe{measure, heading, Composition.CenteredCreation{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.ChronologicalReading{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.ProjectSections{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.ProjectRows{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.StageColumns{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.AgentRows{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.UnavailableNotice{}, composer, decisions, latest}: {==}

def current_composer_context(+identity: U.Editor, revision: Nat, message: U.Text,
  +footer: +List<V.ComposerControl>, +context: Maybe<&2, Context.Preview>, submit: V.ControlDeclaration,
  feedback: U.Feedback, pending: Bool, +world: M.World()) ->
  {RuleCompositionLaws.introduction_context(V.creation_introduction(Some{V.ComposerScene{identity, revision, message, footer, V.preview_observation(context), submit, feedback, pending}}, world)) == context : Maybe<&2, Context.Preview>}:
  match context:
    case None{}: {==}
    case Some{preview}: {==}

def composer_has_context(+message: U.Text, +profile: String, reasoning: String, +context: Context.Configuration,
  scene: V.EditorScene, +world: M.World()) ->
  {RuleCompositionLaws.composer_footer(V.composer_scene(U.NewTask{message, profile, reasoning, context}, scene, world)) ==
    [V.ComposerControl{V.ModelSubject{}, V.control("composer/model", V.profile_label(D.find_profile(Board.profiles(world), profile), profile), U.OpenPanel{U.ModelPicker{U.NewTaskEditor{}}, "composer/model"})},
     V.ComposerControl{V.WorkspaceSubject{}, V.context_control("composer/workspace/new-task", V.observation_workspace(Context.DraftExecution{Context.preview(context, world)}), U.WorkspaceConfiguration{U.NewTaskEditor{}})},
         V.ComposerControl{V.PermissionsSubject{}, V.context_control("composer/permissions/new-task", V.observation_permissions(Context.DraftExecution{Context.preview(context, world)}, Board.profiles(world)), U.PermissionsConfiguration{U.NewTaskEditor{}})}] : +List<V.ComposerControl>}:
  V.EditorScene{identity, revision, groups, sections, submit, feedback, pending} = scene
  {==}

def RuleCompositionLaws.evidence():
  RuleCompositionLaws.Requirements{
    RulePageRegionLaws.evidence(),
    navigation => main => layers => placement => attention => {==},
    task => task_recipe_evidence(task),
    composer => approvals => return_latest => conversation_recipe_evidence(composer, approvals, return_latest),
    message => {==},
    parent => control => action_evidence(parent, control),
    id => speaker => text => source => task => parent => state => visible_speaker_evidence(id, speaker, text, source, task, parent, state),
    +id => attention => +expanded => summary => audit => expand => collapse => +task => +parent => +state => {==},
    view => parent => state => Rule.composer_tree_agreement(view, parent, state),
    recipe => structure_evidence(recipe),
    +context => +world => {==},
    identity => revision => message => footer => context => submit => feedback => pending => world => current_composer_context(identity, revision, message, footer, context, submit, feedback, pending, world),
    +input => +parent => +world => +session => +services => {==},
    +declaration => +rest => +parent => +state => {==},
    message => profile => reasoning => context => scene => world => composer_has_context(message, profile, reasoning, context, scene, world),
    fallback => {==}}
