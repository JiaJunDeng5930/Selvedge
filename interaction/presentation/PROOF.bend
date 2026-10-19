import ./surface-proof.bend as SurfaceProof
import ./interaction-proof.bend as InteractionEvidence
import ../experience/PROGRAM.bend as UX
import ../experience/MODEL.bend as Experience
import ../INPUT.bend as U
import Base
import ./CONTRACT.bend as Rule
import ./MODEL.bend as V
import ./SURFACE.bend as SurfaceTypes
import ./PROGRAM.bend as Model
import ../TYPES.bend as InteractionTypes
import ../submission/FIELDS.bend as Forms
import ../../harness/DOMAIN.bend as D
import ../session/MODEL.bend as E
import ../services/CONTEXT.bend as Context
import ../services/MODEL.bend as Services
import ../IDENTITY.bend as Identity
import ../STATE.bend as Core
import ./VIEW.bend as View
import ../../harness/tasks/PROGRAM.bend as T
import ../../harness/COMMANDS.bend as Commands
import ../../harness/MODEL.bend as M
import ../../features/task_graph/MODEL.bend as G
import ../../harness/features/work-state.bend as WorkState

def Rule.global_navigation_entry_retains_actual_command(compact, route, parent, identity, label, prominence, input, availability, state): {==}

def Rule.global_navigation_controls_empty(compact, route, state): {==}

def Rule.global_navigation_controls_preserve_commands_and_order(compact, route, first, rest, state): {==}

def Rule.global_navigation_form_retains_home_destinations_and_single_settings(compact, route, destinations, state): {==}

def Rule.global_navigation_reads_global_destinations(compact, expanded, create, destinations, projects, tasks, toggle, state): {==}

def Rule.global_navigation_is_independent_of_task_visibility(compact, left, right, create, destinations, projects, tasks, toggle, state): {==}

def Rule.task_navigation_contents_are_independent_of_global_destinations(expanded, route, create, left, right, projects, tasks, state):
  match expanded:
    case False{}: {==}
    case True{}: {==}

def Rule.task_navigation_toggle_names_its_visibility():
  ({==}, {==})

def Rule.global_navigation_does_not_own_modal_scope(key, semantic, label, compact, meaning, children, rest): {==}

def Rule.global_navigation_layer_observes_current_route_and_actual_destinations(session, world): {==}

def Rule.global_navigation_layer_uses_existing_modal_dismissal(beside, trigger): ({==}, {==})

def Rule.global_destinations_retain_existing_route_inputs(): {==}

def Rule.global_menu_entry_preserves_command_and_current_route_selection(route, parent, identity, label, prominence, input, availability, state): {==}

def Rule.global_menu_controls_empty(route, parent, state): {==}

def Rule.global_menu_controls_preserve_destinations_and_order(route, first, rest, parent, state): {==}

def Rule.global_navigation_menu_retains_complete_destinations_settings_and_dismissal(route, destinations, parent, state): {==}

def Rule.global_navigation_layer_binds_the_complete_menu(route, destinations, parent, state): {==}

def Rule.compact_task_navigation_toggle_names_its_destination(): ({==}, {==})

def Rule.compact_task_navigation_toggle_preserves_original_authority(expanded, identity, label, prominence, input, availability): {==}

def Rule.work_selection_is_navigation(work): {==}

def Rule.after_navigation_closes_only_the_task_tree(program, session, services, reply, runtime, interaction, service_effects, durable): {==}

def Rule.desktop_navigation_retains_the_complete_decision(decision): {==}

def Rule.compact_work_selection_closes_task_navigation_after_the_actual_decision(details_beside, state, key, work): {==}

def Rule.desktop_work_selection_retains_the_actual_decision(details_beside, state, key, work): {==}

def Rule.compact_work_scope_is_one_native_overview_command(active, title, count, state): {==}

def Rule.compact_header_retains_exactly_three_real_launchers(navigation, state):
  V.Navigation{expanded, create, destinations, projects, tasks, toggle} = navigation
  {==}

def Rule.compact_task_tree_retains_header_grouping_and_original_task_contents(navigation, header, state):
  V.Navigation{expanded, create, destinations, projects, tasks, toggle} = navigation
  {==}

def Rule.compact_modal_moves_the_header_out_of_base(navigation, state): {==}

def Rule.compact_closed_retains_the_header_in_base(navigation, state): {==}

def workspace_navigation_refinement_at(+full:Bool, +placement:V.NavigationPlacement, +navigation:V.Navigation, +state:InteractionTypes.State) ->
  {Model.workspace_navigation(full, V.Arrangement{placement}, navigation, state) == Rule.required_workspace_navigation_at(full, placement, navigation, state) : +List<SurfaceTypes.Node>}:
  match full placement navigation:
    case True{} _ V.Navigation{expanded, create, destinations, projects, tasks, toggle}: {==}
    case False{} V.ModalNavigation{} V.Navigation{expanded, create, destinations, projects, tasks, toggle}: {==}
    case False{} V.LeadingNavigation{} V.Navigation{expanded, create, destinations, projects, tasks, toggle}: {==}
    case False{} V.CollapsedNavigation{} V.Navigation{expanded, create, destinations, projects, tasks, toggle}: {==}

def Rule.workspace_navigation_uses_complete_responsive_construction(full, arrangement, navigation, state):
  V.Arrangement{placement} = arrangement
  workspace_navigation_refinement_at(full, placement, navigation, state)

def workspace_modal_navigation_refinement_at(+full:Bool, +placement:V.NavigationPlacement, +navigation:V.Navigation, +state:InteractionTypes.State) ->
  {Model.workspace_modal_navigation(full, V.Arrangement{placement}, navigation, state) == Rule.required_workspace_modal_navigation_at(full, placement, navigation, state) : +List<SurfaceTypes.Node>}:
  match full placement navigation:
    case True{} _ V.Navigation{expanded, create, destinations, projects, tasks, toggle}: {==}
    case False{} V.ModalNavigation{} V.Navigation{expanded, create, destinations, projects, tasks, toggle}: {==}
    case False{} V.LeadingNavigation{} V.Navigation{expanded, create, destinations, projects, tasks, toggle}: {==}
    case False{} V.CollapsedNavigation{} V.Navigation{expanded, create, destinations, projects, tasks, toggle}: {==}

def Rule.workspace_modal_navigation_uses_complete_responsive_construction(full, arrangement, navigation, state):
  V.Arrangement{placement} = arrangement
  workspace_modal_navigation_refinement_at(full, placement, navigation, state)

def task_visibility_transition_refinement(+expanded: Bool, +program: M.World(), +session: E.Session, +services: Services.State) ->
  {Core.step(InteractionTypes.ApplicationInput{E.UserInput{U.SetNavigation{expanded}}}, Core.from_application(E.from_program(program, session), services)) ==
    Core.application_result(E.local(program, E.with_navigation(E.advance_navigation_selection(E.set_navigation(expanded, E.navigation(session))), E.with_attention(E.navigation_focus(expanded), session)),
      [E.Attend{E.navigation_focus(expanded)}]), services) : InteractionTypes.Decision}:
  E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code, next_layer, preference, manual, workspace_git, interactive} = session
  {==}

def Rule.task_visibility_transition_changes_only_task_navigation_and_attention(expanded, program, session, services):
  task_visibility_transition_refinement(expanded, program, session, services)

def task_visibility_context_preservation(+expanded: Bool, +state: InteractionTypes.State) ->
  {Rule.global_work_context(Rule.task_visibility_result(expanded, state)) == Rule.global_work_context(state) : Rule.GlobalWorkContext}:
  InteractionTypes.State{E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code, next_layer, preference, manual, workspace_git, interactive}}, services} = state
  E.NavigationState{intent, collapsed, work, visits, generation} = navigation
  {==}

def Rule.task_visibility_transition_preserves_global_work_context(expanded, state):
  task_visibility_context_preservation(expanded, state)

def Rule.work_tab_retains_scope_and_selection(work, label, active, state): {==}

def Rule.work_tabs_preserve_all_tasks_and_creation(state): {==}

def Rule.work_tabs_consume_responsive_form(full, state): {==}

def Rule.compact_work_tabs_keep_current_scope_and_overview(active, values, world, state, count): {==}

def Rule.compact_work_tabs_count_all_tasks_and_works(state): {==}

def Rule.work_tab_form_counts_global_entry(full, active, values, world, state): {==}

def Rule.work_overview_trigger_retains_count_and_binding(count, state): {==}

def Rule.work_overview_choice_retains_scope_name_and_selection(work, name, description, selected, parent, state): {==}

def Rule.picker_factory_retains_complete_single_choice(key, label, prominence, input, availability, selected, description, parent): {==}

def Rule.work_choice_rows_empty(selected, parent, state, index): {==}

def Rule.work_choice_rows_pair_preserves_both_positions(first, second, rest, selected, parent, state, index): {==}

def Rule.work_choice_rows_odd_preserves_empty_second_position(last, selected, parent, state, index): {==}

def Rule.work_overview_retains_choice_group_and_terminal_actions(selected, works, parent, state): {==}

def Rule.work_overview_scene_retains_all_tasks_first(session, world): {==}

def Rule.work_overview_choices_preserve_registry_order(work, value, rest, world): {==}

def Rule.work_overview_choices_do_not_invent_entries(world): {==}

def Rule.work_overview_choice_observes_actual_member_tasks(work, name, world): {==}

def Rule.work_overview_preview_retains_task_count_title_and_status(task, rest, count, world): {==}

def Rule.empty_work_overview_preview_is_explicit(count, world): {==}

def Rule.work_tab_entries_preserve_registry_order(id, value, rest, active, state): {==}

def Rule.work_tab_entries_do_not_invent_entries(active, state): {==}

def Rule.all_tasks_has_no_work_settings(state): {==}

def Rule.work_settings_renames_actual_owner(work, state): {==}

def Rule.work_editor_names_its_actual_operation(work): {==}

def Rule.new_work_graph_draft_has_its_own_editor(work, declaration, parsed): {==}

def Rule.independent_graph_draft_retains_global_editor(declaration, parsed): {==}

def Rule.existing_graph_draft_retains_graph_identity(graph, declaration, parsed, work):
  match work:
    case None{}: {==}
    case Some{owner}: {==}

def Rule.all_tasks_retains_every_task(tasks, world): {==}

def Rule.work_task_filter_uses_recorded_ownership(task, rest, work, world): {==}

def Rule.all_tasks_retains_every_project(projects, tasks, route, selected, navigation): {==}

def scoped_project_entry_matches(+members: +List<D.Task>, +id: Nat, +project: D.Project, +tasks: +List<D.Task>, +route: U.Route, +selected: Maybe<&2, Nat>, +navigation: E.NavigationState, +remaining: +List<V.ProjectEntry>) ->
  {View.keep_project_entry(View.project_has_tasks(members), View.project_entry(id, project, tasks, route, selected, navigation), remaining) ==
    Rule.scoped_project_entry(members, id, project, tasks, route, selected, navigation, remaining) : +List<V.ProjectEntry>}:
  match members:
    case Nil{}: {==}
    case Con{first, rest}: {==}

def Rule.work_project_filter_uses_visible_members(id, project, rest, tasks, route, selected, navigation, work):
  scoped_project_entry_matches(View.project_tasks(tasks, Some{id}), id, project, tasks, route, selected, navigation,
    View.navigation_projects(rest, tasks, route, selected, navigation, Some{work}))

def Rule.all_tasks_retains_every_graph(graphs, route, world): {==}

def scoped_graph_scene_matches(+owned: Bool, +id: Nat, +graph: G.Graph, +route: U.Route, +world: M.World(), +rest: +List<V.TaskGraphScene>) ->
  {View.keep_graph_scene(owned, View.task_graph_scene(id, graph, route, world), rest) ==
    Rule.scoped_graph_scene(owned, id, graph, route, world, rest) : +List<V.TaskGraphScene>}:
  match owned:
    case False{}: {==}
    case True{}: {==}

def Rule.work_graph_filter_uses_recorded_ownership(id, graph, rest, route, world, work):
  scoped_graph_scene_matches(E.same_work(WorkState.graph_owner(id, world), Some{work}), id, graph, route, world,
    View.work_graph_scenes(rest, route, world, Some{work}))

def Rule.start_page_uses_current_work_draft(session, world): {==}

def Rule.graph_page_uses_current_work(session, world): {==}

def Rule.desktop_assembled_surface_keeps_work_tabs_after_global_navigation(scene, state):
  InteractionTypes.Scene{V.Scene{nav, main, views, arrangement, attention}, preferences, transfers, attachment, code, folder_picker} = scene
  {==}

def Rule.desktop_assembled_surface_starts_with_global_navigation(scene, state):
  InteractionTypes.Scene{V.Scene{nav, main, views, arrangement, attention}, preferences, transfers, attachment, code, folder_picker} = scene
  {==}

def Rule.assembled_workspace_base_retains_global_rail_work_tabs_and_task_navigation(full, scene, state):
  match full scene:
    case True{} InteractionTypes.Scene{V.Scene{V.Navigation{expanded, create, destinations, projects, tasks, toggle}, main, views, V.Arrangement{placement}, attention}, preferences, transfers, attachment, code, folder_picker}: {==}
    case False{} InteractionTypes.Scene{V.Scene{V.Navigation{expanded, create, destinations, projects, tasks, toggle}, main, views, V.Arrangement{V.ModalNavigation{}}, attention}, preferences, transfers, attachment, code, folder_picker}: {==}
    case False{} InteractionTypes.Scene{V.Scene{V.Navigation{expanded, create, destinations, projects, tasks, toggle}, main, views, V.Arrangement{V.LeadingNavigation{}}, attention}, preferences, transfers, attachment, code, folder_picker}: {==}
    case False{} InteractionTypes.Scene{V.Scene{V.Navigation{expanded, create, destinations, projects, tasks, toggle}, main, views, V.Arrangement{V.CollapsedNavigation{}}, attention}, preferences, transfers, attachment, code, folder_picker}: {==}

def Rule.assembled_workspace_retains_complete_base_overlays_and_active_scope(full, scene, state):
  match full scene:
    case True{} InteractionTypes.Scene{V.Scene{V.Navigation{expanded, create, destinations, projects, tasks, toggle}, main, views, V.Arrangement{placement}, attention}, preferences, transfers, attachment, code, folder_picker}: {==}
    case False{} InteractionTypes.Scene{V.Scene{V.Navigation{expanded, create, destinations, projects, tasks, toggle}, main, views, V.Arrangement{V.ModalNavigation{}}, attention}, preferences, transfers, attachment, code, folder_picker}: {==}
    case False{} InteractionTypes.Scene{V.Scene{V.Navigation{expanded, create, destinations, projects, tasks, toggle}, main, views, V.Arrangement{V.LeadingNavigation{}}, attention}, preferences, transfers, attachment, code, folder_picker}: {==}
    case False{} InteractionTypes.Scene{V.Scene{V.Navigation{expanded, create, destinations, projects, tasks, toggle}, main, views, V.Arrangement{V.CollapsedNavigation{}}, attention}, preferences, transfers, attachment, code, folder_picker}: {==}

def Rule.workspace_navigation_adds_no_second_settings_control(scene, navigation, reachable, scope): {==}

def compact_overview_action_role(+role: SurfaceTypes.Role, +action: U.Action, +availability: V.Availability) ->
  {Model.compact_navigation_action_role(role, SurfaceTypes.Activate{InteractionTypes.ApplicationInput{E.UserInput{U.Activate{action}}}, availability}) == Rule.required_compact_overview_action_role(role, SurfaceTypes.Activate{InteractionTypes.ApplicationInput{E.UserInput{U.Activate{action}}}, availability}) : SurfaceTypes.Role}:
  match action:
    case U.SelectWork{p0}: {==}
    case U.CreateWork{}: {==}
    case U.RenameWork{p0}: {==}
    case U.Navigate{p0}: {==}
    case U.SelectProject{p0}: {==}
    case U.ToggleProjectGroup{p0}: {==}
    case U.BeginTask{p0}: {==}
    case U.EditProject{p0}: {==}
    case U.NewCard{p0}: {==}
    case U.EditCard{p0}: {==}
    case U.EditAgent{p0}: {==}
    case U.EditTaskGraph{p0}: {==}
    case U.EditTitlePrompts{}: {==}
    case U.DeleteTaskGraph{p0}: {==}
    case U.ForkTask{p0}: {==}
    case U.BeginSideConversation{p0}: {==}
    case U.ShowSideConversation{p0}: {==}
    case U.ReturnSideConversation{p0}: {==}
    case U.CompactTask{p0}: {==}
    case U.Submit{p0}: {==}
    case U.RetryWorkspace{p0}: {==}
    case U.RetryWorktreeArchive{p0}: {==}
    case U.ControlTask{p0, p1}: {==}
    case U.CancelOperation{p0, p1}: {==}
    case U.ReviewApproval{p0, p1, p2, p3}: {==}
    case U.DeleteProject{p0}: {==}
    case U.BoardCommand{p0}: {==}
    case U.OpenPanel{p0, p1}: {==}
    case U.TogglePanel{p0, p1}: {==}
    case U.ClosePanel{}: {==}
    case U.ConfirmAction{}: {==}

def compact_overview_user_input_role(+role: SurfaceTypes.Role, +input: U.Input, +availability: V.Availability) ->
  {Model.compact_navigation_action_role(role, SurfaceTypes.Activate{InteractionTypes.ApplicationInput{E.UserInput{input}}, availability}) == Rule.required_compact_overview_action_role(role, SurfaceTypes.Activate{InteractionTypes.ApplicationInput{E.UserInput{input}}, availability}) : SurfaceTypes.Role}:
  match input:
    case U.WriteDecisionParameter{p0, p1}: {==}
    case U.CompleteDecisionParameter{p0}: {==}
    case U.EnterDecision{p0, p1}: {==}
    case U.LeaveDecision{p0}: {==}
    case U.TogglePropertySource{p0}: {==}
    case U.Activate{p0}: compact_overview_action_role(role, p0, availability)
    case U.EditDraft{p0, p1}: {==}
    case U.ReadTimeline{p0, p1, p2}: {==}
    case U.SetDisclosure{p0, p1, p2, p3}: {==}
    case U.SetNavigation{p0}: {==}
    case U.SearchChoices{p0}: {==}
    case U.FilterBoard{p0}: {==}

def compact_overview_session_input_role(+role: SurfaceTypes.Role, +input: E.Input, +availability: V.Availability) ->
  {Model.compact_navigation_action_role(role, SurfaceTypes.Activate{InteractionTypes.ApplicationInput{input}, availability}) == Rule.required_compact_overview_action_role(role, SurfaceTypes.Activate{InteractionTypes.ApplicationInput{input}, availability}) : SurfaceTypes.Role}:
  match input:
    case E.ContentInput{p0, p1}: {==}
    case E.PreviewObserved{p0}: {==}
    case E.UserInput{p0}: compact_overview_user_input_role(role, p0, availability)
    case E.RuntimeInput{p0}: {==}
    case E.ProgramObserved{p0}: {==}
    case E.CommandCompleted{p0, p1, p2}: {==}
    case E.DirectoriesObserved{p0, p1}: {==}
    case E.ClockObserved{p0}: {==}
    case E.ModelPreferenceRestored{p0, p1}: {==}
    case E.InteractiveInput{p0}: {==}
    case E.InteractiveEnvironmentObserved{p0, p1, p2, p3}: {==}
    case E.InteractiveFenceObserved{p0}: {==}
    case E.InteractiveSynchronize{}: {==}
    case E.ToggleInteractiveSource{p0}: {==}
    case E.DismissRetained{p0}: {==}
    case E.ToggleArchived{p0}: {==}
    case E.ClearDiscarded{p0}: {==}
    case E.WorkspaceGitObserved{p0, p1}: {==}

def compact_overview_input_role(+role: SurfaceTypes.Role, +input: InteractionTypes.Input, +availability: V.Availability) ->
  {Model.compact_navigation_action_role(role, SurfaceTypes.Activate{input, availability}) == Rule.required_compact_overview_action_role(role, SurfaceTypes.Activate{input, availability}) : SurfaceTypes.Role}:
  match input:
    case InteractionTypes.Interactive{p0}: {==}
    case InteractionTypes.ApplicationInput{p0}: compact_overview_session_input_role(role, p0, availability)
    case InteractionTypes.ServiceInput{p0}: {==}
    case InteractionTypes.EditField{p0, p1, p2}: {==}
    case InteractionTypes.RemoveAttachment{p0, p1}: {==}

def Rule.compact_overview_action_roles_preserve_other_commands(role, meaning):
  match meaning:
    case SurfaceTypes.SettingEntry{p0, p1, p2, p3}: {==}
    case SurfaceTypes.ActivityRow{p0}: {==}
    case SurfaceTypes.ActivityGroup{p0, p1, p2, p3}: {==}
    case SurfaceTypes.DecisionGroup{p0}: {==}
    case SurfaceTypes.WorkspaceCollection{p0}: {==}
    case SurfaceTypes.WorkspaceMember{p0, p1}: {==}
    case SurfaceTypes.ActionUnit{p0}: {==}
    case SurfaceTypes.ActionFeedback{p0}: {==}
    case SurfaceTypes.ActionExplanation{p0}: {==}
    case SurfaceTypes.ActionCommit{p0, p1, p2}: {==}
    case SurfaceTypes.ObjectGroup{p0}: {==}
    case SurfaceTypes.SupportingControl{p0, p1, p2, p3}: {==}
    case SurfaceTypes.InformationText{p0}: {==}
    case SurfaceTypes.LayerRegion{p0, p1, p2}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{p0}: {==}
    case SurfaceTypes.PanelToggle{p0, p1, p2}: {==}
    case SurfaceTypes.CardContent{p0}: {==}
    case SurfaceTypes.MovableCard{p0, p1}: {==}
    case SurfaceTypes.Region{}: {==}
    case SurfaceTypes.PageContext{p0}: {==}
    case SurfaceTypes.ActivityContent{p0, p1}: {==}
    case SurfaceTypes.ProjectGroup{p0, p1, p2}: {==}
    case SurfaceTypes.TaskRow{p0, p1, p2}: {==}
    case SurfaceTypes.TaskChildren{p0}: {==}
    case SurfaceTypes.ProjectChooser{p0}: {==}
    case SurfaceTypes.DirectoryRow{p0, p1}: {==}
    case SurfaceTypes.ContextSummary{p0}: {==}
    case SurfaceTypes.ChoiceGroup{}: {==}
    case SurfaceTypes.Choice{p0, p1, p2, p3, p4, p5}: {==}
    case SurfaceTypes.PageRegion{p0, p1}: {==}
    case SurfaceTypes.BoardLane{p0, p1}: {==}
    case SurfaceTypes.CardArchive{p0}: {==}
    case SurfaceTypes.BoardSearch{p0}: {==}
    case SurfaceTypes.BoardGroup{p0}: {==}
    case SurfaceTypes.ReadOnly{p0}: {==}
    case SurfaceTypes.Fact{p0}: {==}
    case SurfaceTypes.RichText{p0, p1}: {==}
    case SurfaceTypes.TaskFacts{p0}: {==}
    case SurfaceTypes.CodeFacts{p0}: {==}
    case SurfaceTypes.InteractiveRegion{p0, p1}: {==}
    case SurfaceTypes.InteractiveNode{p0}: {==}
    case SurfaceTypes.InteractiveView{p0, p1, p2, p3}: {==}
    case SurfaceTypes.Activate{p0, p1}: compact_overview_input_role(role, p0, p1)
    case SurfaceTypes.Edit{p0, p1, p2, p3, p4}: {==}
    case SurfaceTypes.SearchChoices{p0}: {==}
    case SurfaceTypes.ReceiveFile{p0, p1}: {==}
    case SurfaceTypes.EnterDirectory{p0, p1}: {==}
    case SurfaceTypes.BoardProfile{p0, p1, p2, p3}: {==}

def Rule.compact_overview_actions_empty(): {==}

def Rule.compact_overview_actions_retain_every_node_field_and_tree_position(key, semantic, label, role, meaning, children, rest):
  Equal.cong(SurfaceTypes.Role, +List<SurfaceTypes.Node>,
    (observed_role => SurfaceTypes.Node{key, semantic, label, observed_role, meaning, Model.compact_overview_actions(children)} <> Model.compact_overview_actions(rest)),
    Model.compact_navigation_action_role(role, meaning), Rule.required_compact_overview_action_role(role, meaning),
    Rule.compact_overview_action_roles_preserve_other_commands(role, meaning))

def Rule.compact_overview_unselected_layer_is_unchanged(node): {==}

def Rule.compact_overview_selected_layer_retains_its_own_fields(key, semantic, label, role, meaning, children): {==}

def Rule.compact_overview_layers_empty(): {==}

def Rule.compact_overview_layers_gate_only_the_actual_work_overview_key(key, semantic, label, role, meaning, children, rest): {==}

def Rule.desktop_navigation_layers_are_unchanged(values): {==}

def Rule.compact_navigation_layers_use_the_keyed_work_overview_adaptation(values): {==}

def Rule.relocated_valid_content(valid, node, scene, base, overlays):
  match valid:
    case False{}: {==}
    case True{}:
      SurfaceTypes.Node{key, semantic, label, role, meaning, children} = node
      {==}

def Rule.relocated_found_content(found, target, scene, base, overlays):
  match found:
    case None{}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, +meaning, children}}:
      Rule.relocated_valid_content(Model.persistent_trigger_source(meaning, target),
        SurfaceTypes.Node{key, semantic, label, role, meaning, children}, scene, base, overlays)

def Rule.relocated_key_content(found, target, scene, base, overlays):
  match found:
    case None{}: {==}
    case Some{key}: Rule.relocated_found_content(Model.find_node(base, key), target, scene, base, overlays)

def Rule.relocated_content(trigger, scene, base, overlays):
  match trigger:
    case None{}: {==}
    case Some{SurfaceTypes.PersistentTrigger{target, requested}}: Rule.relocated_key_content(Model.matching_focus(base, requested), target, scene, base, overlays)

def Rule.assembled_content(full, scene, state):
  InteractionTypes.Scene{V.Scene{nav, main, views, arrangement, attention}, preferences, transfers, attachment, code, folder_picker} = scene
  {==}

def observed_content_refinement(+capacity: V.Capacity, +state: InteractionTypes.State) ->
  {Model.content(Model.observe(capacity, state)) == Core.observe(capacity, state) : InteractionTypes.Scene}:
  V.Capacity{+navigation_beside, +details_beside} = capacity
  Rule.assembled_content(navigation_beside, Core.observe(V.Capacity{navigation_beside, details_beside}, state), state)

def Rule.observed_content(capacity, state):
  observed_content_refinement(capacity, state)

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

def Rule.new_task_model_permission(message, profile, reasoning, context, work, create_worktree, world):
  {==}

def Rule.agent_model_permission(agent, revision, name, profile, reasoning, instructions, context, concurrency, world):
  {==}

def Rule.modal_navigation_preserved(nav, state): {==}

def Rule.overlay_navigation_scope(key, semantic, label, meaning, children, rest): {==}

def Rule.dialog_actions_region(parent, children):
  {==}

def Rule.editor_submit_region(identity, revision, groups, structure, assessment, submit, feedback, pending, parent, state):
  {==}

def Rule.confirmation_actions_region(title, confirm, cancel, parent, state):
  {==}

def Rule.card_ordered_movement(view, parent, state):
  V.CardScene{id, value, open, actions, linked, destinations, candidates} = view
  InteractionTypes.State{E.Application{world, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code, next_layer, model_preference, draft_model_manual, workspace_git, interactive}}, services} = state
  {==}

def Rule.card_surface_placement(key, semantic, label, face, children, target): {==}

def Rule.card_movement_placement(key, semantic, label, face, destinations, target): {==}

def Rule.project_fact_structure(key, label, value): {==}

def Rule.interface_input(input, state):
  {==}

def Rule.interface_evidence():
  Rule.InterfaceRequirements{Rule.interface_input}

def supporting_binding_agreement(+support: Experience.Support, +property: Experience.Property, +input: InteractionTypes.Input, +availability: V.Availability, +gesture: SurfaceTypes.Gesture) ->
  {Model.bind(SurfaceTypes.SupportingControl{support, property, input, availability}, gesture) == Rule.expected_supporting_binding(support, input, availability, gesture) : Maybe<&2, InteractionTypes.Input>}:
  match gesture:
    case SurfaceTypes.Place{target}: {==}
    case SurfaceTypes.Press{}: {==}
    case SurfaceTypes.Change{value}: {==}
    case SurfaceTypes.Search{query}: {==}
    case SurfaceTypes.Filter{value}: {==}
    case SurfaceTypes.Attach{file}: {==}
    case SurfaceTypes.Directory{path}: {==}
    case SurfaceTypes.ConfirmDirectory{}: {==}
    case SurfaceTypes.SelectBoardProfile{profile}: {==}

def supporting_submission_agreement(+support: Experience.Support, +property: Experience.Property, +input: InteractionTypes.Input, +availability: V.Availability, +editor: U.Editor) ->
  {Model.submits(SurfaceTypes.SupportingControl{support, property, input, availability}, editor) == Rule.expected_supporting_submission(support, input, availability, editor) : Bool}:
  match input:
    case InteractionTypes.Interactive{input}: {==}
    case InteractionTypes.ApplicationInput{E.InteractiveInput{input}}: {==}
    case InteractionTypes.ApplicationInput{E.InteractiveEnvironmentObserved{namespace, sequence, fresh, allowed}}: {==}
    case InteractionTypes.ApplicationInput{E.InteractiveFenceObserved{observation}}: {==}
    case InteractionTypes.ApplicationInput{E.InteractiveSynchronize{}}: {==}
    case InteractionTypes.ApplicationInput{E.ToggleInteractiveSource{identity}}: {==}
    case InteractionTypes.ApplicationInput{E.DismissRetained{key}}: {==}
    case InteractionTypes.ApplicationInput{E.ToggleArchived{key}}: {==}
    case InteractionTypes.ApplicationInput{E.ClearDiscarded{task}}: {==}
    case InteractionTypes.ApplicationInput{E.ContentInput{p0, p1}}: {==}
    case InteractionTypes.ApplicationInput{E.PreviewObserved{p0}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.Navigate{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.SelectWork{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.CreateWork{}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.RenameWork{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.SelectProject{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.ToggleProjectGroup{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.BeginTask{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.EditProject{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.NewCard{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.EditCard{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.EditAgent{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.EditTaskGraph{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.EditTitlePrompts{}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.DeleteTaskGraph{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.ForkTask{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.BeginSideConversation{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.ShowSideConversation{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.ReturnSideConversation{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.CompactTask{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.Submit{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.RetryWorkspace{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.RetryWorktreeArchive{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.ControlTask{p0, p1}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.CancelOperation{p0, p1}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.ReviewApproval{p0, p1, p2, p3}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.DeleteProject{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.BoardCommand{p0}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.OpenPanel{p0, p1}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.TogglePanel{p0, p1}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.ClosePanel{}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.Activate{U.ConfirmAction{}}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.EditDraft{p0, p1}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.ReadTimeline{p0, p1, p2}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.SetDisclosure{p0, p1, p2, p3}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.SetNavigation{p0}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.SearchChoices{p0}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.TogglePropertySource{p0}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.EnterDecision{p0, p1}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.LeaveDecision{p0}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.WriteDecisionParameter{p0, p1}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.CompleteDecisionParameter{p0}}}: {==}
    case InteractionTypes.ApplicationInput{E.UserInput{U.FilterBoard{p0}}}: {==}
    case InteractionTypes.ApplicationInput{E.RuntimeInput{p0}}: {==}
    case InteractionTypes.ApplicationInput{E.ProgramObserved{p0}}: {==}
    case InteractionTypes.ApplicationInput{E.CommandCompleted{p0, p1, p2}}: {==}
    case InteractionTypes.ApplicationInput{E.DirectoriesObserved{p0, p1}}: {==}
    case InteractionTypes.ApplicationInput{E.ClockObserved{p0}}: {==}
    case InteractionTypes.ApplicationInput{E.ModelPreferenceRestored{p0, p1}}: {==}
    case InteractionTypes.ApplicationInput{E.WorkspaceGitObserved{p0, p1}}: {==}
    case InteractionTypes.ServiceInput{p0}: {==}
    case InteractionTypes.EditField{p0, p1, p2}: {==}
    case InteractionTypes.RemoveAttachment{p0, p1}: {==}

def effort_entry_surface_agreement(+entry: Forms.Entry, +observation: Forms.Observed, +editor: U.Editor, +parent: Identity.Key, +state: InteractionTypes.State, +groups: +List<V.InputGroup>) ->
  {Model.model_effort_surface(entry, observation, editor, parent, state, groups) == Rule.expected_model_effort_surface(entry, observation, editor, parent, state, groups) : SurfaceTypes.Node}:
  match entry:
    case Forms.Choice{}: {==}
    case Forms.SingleLine{}: {==}
    case Forms.DisplayOnly{}: {==}
    case Forms.Multiline{}: {==}
    case Forms.StructuredText{}: {==}
    case Forms.MultipleChoices{}: {==}
    case Forms.PositiveInteger{}: {==}
    case Forms.DirectoryCollection{}: {==}
    case Forms.FileCollection{}: {==}

def canonical_commit_agreement(+action: Experience.ActionUnit, +assessment: Experience.Assessment, +identity: String, +label: String, +prominence: V.Prominence, input: U.Input, +availability: V.Availability, +parent: Identity.Key, +state: InteractionTypes.State) ->
  {Model.canonical_commit(action, assessment, V.ControlDeclaration{identity, label, prominence, input, availability}, parent, state) == Rule.expected_action_commit(assessment, parent, Core.control(state, V.ControlDeclaration{identity, label, prominence, UX.commit(action), availability})) : SurfaceTypes.Node}:
  InteractionTypes.State{application, services} = state
  {==}

def Rule.experience_evidence():
  Rule.ExperienceRequirements{
    entry => observation => editor => parent => state => groups => effort_entry_surface_agreement(entry, observation, editor, parent, state, groups),
    profile => reasoning => choices => editor => parent => state => groups => {==},
    controls => action => assessment => submit => parent => state => {==},
    support => property => input => availability => gesture => supporting_binding_agreement(support, property, input, availability, gesture),
    support => property => input => availability => {==},
    support => property => input => availability => editor => supporting_submission_agreement(support, property, input, availability, editor),
    subject => observed => {==},
    profile => reasoning => choices => rest => editor => parent => state => {==},
    title => entries => rest => editor => parent => ordinal => state => groups => {==},
    property => declaration => rest => action => parent => state => {==},
    subject => observed => profile => rest => {==},
    decision => parent => state => {==},
    decision => label => explanation => value => input => parent => state => {==},
    collection => path => parent => state => {==},
    action => assessment => identity => label => prominence => input => availability => parent => state => canonical_commit_agreement(action, assessment, identity, label, prominence, input, availability, parent, state),
    editor => revision => reason => parent => {==},
    support => property => parent => identity => label => prominence => input => availability => {==}}

def Rule.assessed_editor_scene(revision, body, feedback, entry, pending, now, world): {==}

def Rule.available_assessment_preserved(assessment): {==}
def Rule.directory_assessment_preserved(assessment): {==}
def Rule.unavailable_assessment_uses_actual_reason(assessment, reason): {==}
def Rule.duplicate_assessment_reason_preserved(assessment, reason): {==}
def Rule.distinct_assessment_reason_retained(assessment, reason): {==}
def Rule.commit_explanation_observes_same_assessment(assessment, parent, identity, label, prominence, input, availability): {==}


def Rule.context_permission_facts(observation): {==}
def Rule.context_summary_labels(observation, parent, state): {==}

def Rule.model_search_retains_complete_catalog(editor, old, groups, query):
  {==}

def Rule.model_layer_uses_actual_activity(editor, query, groups, parent, state):
  {==}

def Rule.policy_layer_uses_actual_activity(editor, groups, parent, state):
  {==}

def Rule.object_editor_uses_actual_editing_activity(scene, parent, state):
  {==}

def Rule.activity_layer_preserves_outside_and_escape(activity, action):
  {==}

def Rule.activity_layer_preserves_trigger_dismissal(activity, action):
  {==}

def Rule.activity_interpreter_consumes_actual_relation_fold(activity, query, parent, state):
  {==}

def Rule.persistent_details_trigger_uses_actual_layer_behavior(found, task, trigger, key, semantic, label, children):
  match found:
    case None{}: {==}
    case Some{activity}: {==}

def Rule.activity_row_preserves_actual_descendant(role, key, semantic, label, original_role, meaning, children):
  {==}

def Rule.hidden_activity_relation_retains_child_traversal(view, children, activity, current, query, parent, state):
  {==}

def Rule.selected_subject_uses_actual_canonical_candidates(subject, decision, activity, query, parent, state):
  {==}

def Rule.required_activity_property_consumes_subject_coverage(activity, property, query, parent, state):
  {==}

def Rule.principal_choice_has_no_independent_commit(title, editor, parent, state):
  {==}

def Rule.requested_open_parameter_writes_only_buffer(editor, profile, reasoning, input):
  {==}

def Rule.readonly_parameter_has_no_apply_action(editor, parent, state):
  {==}

def Rule.activity_projection_consumes_completion(activity, query, parent, state):
  {==}


def Rule.activity_layer_label_consumes_actual_goal(activity, fallback, state):
  {==}

def Rule.choosing_goal_does_not_repeat_owner_title(fallback):
  {==}

def Rule.inspection_goal_does_not_repeat_owner_title(fallback):
  {==}

def Rule.compound_goal_preserves_actual_activity_title(fallback):
  {==}

def Rule.original_identity_remains_supporting_saved_context(name, workspace, guidance, parent):
  {==}

def Rule.new_object_has_no_fabricated_original_identity(parent):
  {==}


def Rule.readonly_activity_field_retains_subject_caption_and_value(editor, field, value, parent):
  {==}

def Rule.readonly_activity_fact_cannot_mutate_its_observation(editor, field, value, next):
  {==}

def Rule.requested_choice_names_actual_subject(subject, parent):
  {==}

def Rule.principal_choice_adds_no_requested_caption(subject, parent):
  {==}

def Rule.owned_collection_actions_do_not_terminate_activity(editor, parent, state):
  {==}

def Rule.compound_terminal_retains_actual_commit_and_discard(action, assessment, submit, parent, state):
  {==}

def Rule.compound_action_uses_actual_completion_boundary(activity, current, action, assessment, children, query, parent, state):
  {==}

def Rule.returning_inspection_has_no_compound_commit(action, assessment, parent, state):
  {==}

def Rule.returning_inspection_has_no_parameter_apply(editor, parent, state):
  {==}

def Rule.open_parameter_terminal_retains_whole_value_completion(editor, parent, state):
  {==}

def Rule.activity_expression_consumes_information_requirement(expression, activity, query, parent, state):
  {==}

def Rule.not_applicable_information_has_no_mutation_control(reason, expression, activity, query, parent, state):
  {==}

def Rule.setting_entry_retains_subject_value_and_input(editor, field, value, parent, state):
  {==}

def Rule.setting_entry_activates_its_original_input(subject, value, input):
  {==}

def Rule.setting_entry_respects_unavailability(subject, value, input, reason):
  {==}

def Rule.returning_view_constructs_navigation_and_current_identity(title, editor, parent, state):
  {==}

def Rule.dependent_view_identity_comes_from_actual_subject(subject, property):
  {==}

def Rule.inspection_view_identity_comes_from_actual_property(property):
  {==}

def Rule.settings_inspection_keeps_source_details_requested(property, parent, state):
  {==}

def Rule.source_entry_retains_actual_owner_panel(origin, parent, state):
  {==}

def Rule.source_subactivity_uses_stack_return_and_owner_observation(origin, parent, state):
  {==}

def Rule.source_subactivity_names_actual_request(origin):
  {==}

def Rule.source_subactivity_reads_the_same_owner_activity(activity, parent):
  {==}

def Rule.workspace_source_uses_actual_execution_observation(config, preview, controls, projects, reviewers, rest, editor, state):
  {==}

def Rule.workspace_layer_source_preserves_observation_owner(editor, fields, state):
  {==}

def Rule.activity_layer_source_preserves_property_observation(activity):
  {==}

def Rule.source_child_preserves_owner_view_observation(origin, trigger, initial, query, occurrence, expanded, field, buffer, rest):
  {==}

def Rule.source_projection_replaces_only_its_real_owner(origin, owner, trigger, initial, query, occurrence, expanded, field, buffer, rest, shown):
  {==}

def Rule.source_projection_keeps_return_parent_out_of_the_visible_stack(owner, rest):
  {==}

def Rule.source_projection_reuses_owning_visible_anchor(owner, original):
  {==}

def Rule.inspection_readonly_dependency_uses_its_actual_relation(owner, subject, profile, children, activity, current, query, parent, state):
  {==}

def Rule.inspection_root_precedes_its_retained_dependencies(decision, actual, children, activity, current, query, parent, state):
  {==}

def Rule.side_window_adapts_to_available_details_space(task):
  ({==}, {==})

def Rule.side_window_closes_without_returning_content(task, trigger): {==}
def Rule.side_window_uses_its_task_and_explicit_return_control(task, session, world): {==}
def Rule.side_conversation_has_its_own_reading_and_composer_context(id, title, status, context, task, generation, groups, live, decisions, reading, latest, previews, input, details, actions, parent, state): {==}
