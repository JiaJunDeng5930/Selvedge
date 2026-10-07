import Base
import ../../harness/COMMANDS.bend as Commands
import ../../harness/MODEL.bend as M
import ../../harness/DOMAIN.bend as D
import ../../harness/reasoning/MODEL.bend as Reasoning
import ../submission/FIELDS.bend as Forms
import ../IDENTITY.bend as Identity
import ../STATE.bend as Core
import ./PROGRAM.bend as Model
import ./MODEL.bend as V
import ../services/CONTEXT.bend as Context
import ../INPUT.bend as U
import ../session/MODEL.bend as E
import ../../features/board/MODEL.bend as B

law composer_tree_present_agreement:
  for +identity: U.Editor
  for revision: Nat
  for message: U.Text
  for footer: +List<V.ComposerControl>
  for context: Maybe<&2, Context.Observation>
  for submit: V.ControlDeclaration
  for feedback: U.Feedback
  for pending: Bool
  for +parent: Identity.Key
  for +state: Core.State
  {Model.composer(Some{V.ComposerScene{identity, revision, message, footer, context, submit, feedback, pending}}, parent, state) ==
      Model.expected_composer(Some{V.ComposerScene{identity, revision, message, footer, context, submit, feedback, pending}}, parent, state) : +List<Model.Node>}


law composer_tree_agreement:
  for view: Maybe<&2, V.ComposerScene>
  for +parent: Identity.Key
  for +state: Core.State
  {Model.composer(view, parent, state) == Model.expected_composer(view, parent, state) : +List<Model.Node>}


law relocated_valid_content:
  for valid: Bool
  for +node: Model.Node
  for +scene: Core.Scene
  for +base: +List<Model.Node>
  for +overlays: +List<Model.Node>
  {Model.content(Model.relocate_valid_trigger(valid, node, scene, base, overlays)) == scene : Core.Scene}


law relocated_found_content:
  for found: Maybe<&2, Model.Node>
  for +target: Nat
  for +scene: Core.Scene
  for +base: +List<Model.Node>
  for +overlays: +List<Model.Node>
  {Model.content(Model.relocate_found_trigger(found, target, scene, base, overlays)) == scene : Core.Scene}


law relocated_key_content:
  for found: Maybe<&2, String>
  for +target: Nat
  for +scene: Core.Scene
  for +base: +List<Model.Node>
  for +overlays: +List<Model.Node>
  {Model.content(Model.relocate_trigger_key(found, target, scene, base, overlays)) == scene : Core.Scene}


law relocated_content:
  for trigger: Maybe<&2, Model.PersistentTrigger>
  for +scene: Core.Scene
  for +base: +List<Model.Node>
  for +overlays: +List<Model.Node>
  {Model.content(Model.relocate_persistent_trigger(trigger, scene, base, overlays)) == scene : Core.Scene}


law assembled_content:
  for +scene: Core.Scene
  for +state: Core.State
  {Model.content(Model.assemble(scene, state)) == scene : Core.Scene}


law placement_destination_authority:
  for +key: Identity.Key
  for +semantic: String
  for +label: String
  for +role: Model.Role
  for +destinations: +List<Model.Placement>
  for +face: V.CardFace
  for +children: +List<Model.Node>
  for +target: String
  for +surface: Model.Surface
  {Model.resolve_present(Model.Node{key, semantic, label, role, Model.MovableCard{destinations, face}, children}, Model.Place{target}, surface) == Model.placement_input(destinations, target) : Maybe<&2, Core.Input>}


law placement_filtered_destination_accepted:
  for +key: Identity.Key
  for +semantic: String
  for +label: String
  for +role: Model.Role
  for +destinations: +List<Model.Placement>
  for +face: V.CardFace
  for +children: +List<Model.Node>
  for +target: String
  for +surface: Model.Surface
  for +input: Core.Input
  for hidden: {Model.find_node(Model.active_nodes(surface), target) == None{} : Maybe<&2, Model.Node>}
  for accepted: {Model.placement_input(destinations, target) == Some{input} : Maybe<&2, Core.Input>}
  {Model.resolve_present(Model.Node{key, semantic, label, role, Model.MovableCard{destinations, face}, children}, Model.Place{target}, surface) == Some{input} : Maybe<&2, Core.Input>}


law placement_rejected_destination:
  for +key: Identity.Key
  for +semantic: String
  for +label: String
  for +role: Model.Role
  for +destinations: +List<Model.Placement>
  for +face: V.CardFace
  for +children: +List<Model.Node>
  for +target: String
  for +surface: Model.Surface
  for rejected: {Model.placement_input(destinations, target) == None{} : Maybe<&2, Core.Input>}
  {Model.resolve_present(Model.Node{key, semantic, label, role, Model.MovableCard{destinations, face}, children}, Model.Place{target}, surface) == None{} : Maybe<&2, Core.Input>}


law fixed_reasoning_catalogue_entry:
  for key: String
  for provider: String
  for name: String
  for options: D.ReasoningOptions
  {Model.profile_effort_entry(D.Profile{key, provider, name, Reasoning.Fixed{}, Some{options}}) == Forms.Choice{} : Forms.Entry}

law fixed_reasoning_open_entry:
  for key: String
  for provider: String
  for name: String
  {Model.profile_effort_entry(D.Profile{key, provider, name, Reasoning.Fixed{}, None{}}) == Forms.SingleLine{} : Forms.Entry}

law retained_profile_effort:
  for +profile: D.Profile
  for +previous: String
  for permitted: {D.profile_permitted(profile, previous) == True{} : Bool}
  {Forms.selected_profile_effort(D.profile_permitted(profile, previous), previous, profile) == previous : String}

law reset_profile_effort:
  for +profile: D.Profile
  for +previous: String
  for denied: {D.profile_permitted(profile, previous) == False{} : Bool}
  {Forms.selected_profile_effort(D.profile_permitted(profile, previous), previous, profile) == D.profile_default(profile) : String}

law rejected_reasoning_edit:
  for +profile: String
  for +reasoning: String
  {Forms.permitted_model_edit(False{}, profile, reasoning) == None{} : Maybe<&2, U.Edit>}

law accepted_reasoning_edit:
  for +profile: String
  for +reasoning: String
  {Forms.permitted_model_edit(True{}, profile, reasoning) == Some{U.ChooseModel{profile, reasoning}} : Maybe<&2, U.Edit>}

law selected_model_permission:
  for +profile: D.Profile
  for reasoning: String
  {U.selected_model_permitted(Some{profile}, reasoning) == D.profile_permitted(profile, D.profile_selection(reasoning, profile)) : Bool}

law rejected_profile_choice:
  {Model.model_choice_availability(False{}) == V.Unavailable{"The model has no permitted reasoning selection"} : V.Availability}


law new_task_model_permission:
  for message: U.Text
  for +profile: String
  for reasoning: String
  for context: Context.Configuration
  for world: M.World()
  {U.model_permitted(U.NewTask{message, profile, reasoning, context}, world) == U.selected_model_permitted(D.find_profile(Commands.configured(Commands.settings(world)), profile), reasoning) : Bool}

law agent_model_permission:
  for agent: Maybe<&2, Nat>
  for revision: Nat
  for name: String
  for +profile: String
  for reasoning: String
  for instructions: String
  for context: Context.Configuration
  for concurrency: Nat
  for world: M.World()
  {U.model_permitted(U.Agent{agent, revision, name, profile, reasoning, instructions, context, concurrency}, world) == U.selected_model_permitted(D.find_profile(Commands.configured(Commands.settings(world)), profile), reasoning) : Bool}


law modal_navigation_preserved:
  for +nav: V.Navigation
  for +state: Core.State
  {Model.modal_navigation_at(V.ModalNavigation{}, nav, state) == [Model.navigation(nav, state)] : +List<Model.Node>}

law overlay_navigation_scope:
  for +key: Identity.Key
  for semantic: String
  for label: String
  for meaning: Model.Meaning
  for children: +List<Model.Node>
  for rest: +List<Model.Node>
  {Model.active_scope(Model.Node{key, semantic, label, Model.Navigation{}, meaning, children} <> rest) == Some{Identity.encode(key)} : Maybe<&2, String>}

law dialog_actions_region:
  for +parent: Identity.Key
  for +children: +List<Model.Node>
  {Model.dialog_actions(parent, children) == Model.Node{Identity.Part{parent, "@actions"}, "@actions", "Actions", Model.DialogActions{}, Model.Region{}, children} : Model.Node}

law editor_submit_region:
  for identity: U.Editor
  for revision: Nat
  for groups: +List<V.InputGroup>
  for structure: +List<Forms.Section>
  for submit: V.ControlDeclaration
  for feedback: U.Feedback
  for pending: Bool
  for +parent: Identity.Key
  for +state: Core.State
  {Model.editor(Some{V.EditorScene{identity, revision, groups, structure, submit, feedback, pending}}, parent, state) ==
    List.append(&2, Model.Node, Model.sections(structure, identity, parent, 0n, state, groups),
      List.append(&2, Model.Node, Model.feedback_nodes(parent, feedback), [Model.dialog_actions(parent, [Model.declared(parent, submit, state)])])) : +List<Model.Node>}

law confirmation_actions_region:
  for title: String
  for confirm: V.ControlDeclaration
  for cancel: V.ControlDeclaration
  for +parent: Identity.Key
  for +state: Core.State
  {Model.layer_content(V.Confirmation{title, confirm, cancel}, parent, state) ==
    [Model.dialog_actions(parent, [Model.declared(parent, confirm, state), Model.declared(parent, cancel, state)])] : +List<Model.Node>}

def expected_card(view: V.CardScene, +parent: Identity.Key, +state: Core.State) -> Model.Node:
  V.CardScene{+id, +value, open, actions, linked, destinations, candidates} = view
  +observed_application = Core.application(state)
  world = E.program(observed_application)
  +observed_session = E.session(observed_application)
  +now = E.now(observed_session)
  +key : Identity.Key = Identity.Entity{parent, "card", Nat.show(id)}
  +face : V.CardFace = V.card_face(id, value, now, world)
  +offered : +List<Model.Placement> = List.append(&2, Model.Placement, Model.placements(destinations, id, B.revision(value), state), Model.archive_placement(B.archived(value), id, B.revision(value), state))
  Model.Node{key, "card/" ++ Nat.show(id), B.title(B.draft(value)), Model.Card{}, Model.CardContent{face},
    [Model.declared(key, open, state), Model.more(U.CardSubject{id}, key, state),
      Model.Node{Identity.part(key, "movement"), "card/" ++ Nat.show(id) ++ "/movement", "Move " ++ B.title(B.draft(value)), Model.Field{}, Model.MovableCard{offered, face}, Nil{}}]}

law card_ordered_movement:
  for +view: V.CardScene
  for +parent: Identity.Key
  for +state: Core.State
  {Model.card(view, parent, state) == expected_card(view, parent, state) : Model.Node}

law card_surface_placement:
  for +key: Identity.Key
  for semantic: String
  for label: String
  for +face: V.CardFace
  for +children: +List<Model.Node>
  for target: String
  {Model.placement_source(Model.Node{key, semantic, label, Model.Card{}, Model.CardContent{face}, children}, target) == Model.placement_input(Model.card_placements(children), target) : Maybe<&2, Core.Input>}

law card_movement_placement:
  for +key: Identity.Key
  for semantic: String
  for label: String
  for +face: V.CardFace
  for +destinations: +List<Model.Placement>
  for target: String
  {Model.placement_source(Model.Node{key, semantic, label, Model.Field{}, Model.MovableCard{destinations, face}, Nil{}}, target) == Model.placement_input(destinations, target) : Maybe<&2, Core.Input>}


law project_fact_structure:
  for +key: Identity.Key
  for +label: String
  for value: String
  {Model.project_fact(key, label, value) == Model.Node{key, Identity.encode(key), label, Model.Content{}, Model.Fact{value}, Nil{}} : Model.Node}
