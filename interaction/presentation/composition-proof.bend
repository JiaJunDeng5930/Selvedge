import ./composition-laws.bend as Rule
import ./CONTRACT.bend as InterfaceRules
import Base
import ../conversation/CODE.bend as Code
import ../IDENTITY.bend as Identity
import ./COMPOSITION.bend as Composition
import ./page-region-laws.bend as PageRegions
import ./MODEL.bend as View
import ./PROGRAM.bend as Interface
import ../conversation/MODEL.bend as Conversation
import ../INPUT.bend as U
import ../STATE.bend as Core
import ../../harness/DOMAIN.bend as D
import ../../harness/MODEL.bend as M
import ../services/CONTEXT.bend as Context
import ../../features/board/STATE.bend as Board

def conversation_recipe_evidence(composer: Bool, approvals: Bool, return_latest: Bool)
  -> Rule.conversation_recipe_law(composer, approvals, return_latest):
  match composer approvals return_latest:
    case False{} False{} False{}: {==}
    case False{} False{} True{}: {==}
    case False{} True{} False{}: {==}
    case False{} True{} True{}: {==}
    case True{} False{} False{}: {==}
    case True{} False{} True{}: {==}
    case True{} True{} False{}: {==}
    case True{} True{} True{}: {==}

def task_recipe_components_evidence(composer: Maybe<&2, View.ComposerScene>, approvals: +List<Conversation.DecisionRequest>, return_latest: Maybe<&2, U.Input>)
  -> {Composition.Recipe{Composition.ReadingMeasure{}, Composition.ConversationHeading{}, Composition.ChronologicalReading{},
        Composition.bottom_composer(View.has_composer(composer)), Composition.decisions(View.has_decisions(approvals)), Composition.latest(View.has_return_latest(return_latest))} ==
      Composition.Recipe{Composition.ReadingMeasure{}, Composition.ConversationHeading{}, Composition.ChronologicalReading{},
        Rule.expected_bottom_composer(Rule.has_composer(composer)), Rule.expected_decisions(View.has_decisions(approvals)), Rule.expected_latest(View.has_return_latest(return_latest))} : Composition.Recipe}:
  match composer approvals return_latest:
    case None{} Nil{} None{}: {==}
    case None{} Nil{} Some{input}: {==}
    case None{} Con{decision, rest} None{}: {==}
    case None{} Con{decision, rest} Some{input}: {==}
    case Some{scene} Nil{} None{}: {==}
    case Some{scene} Nil{} Some{input}: {==}
    case Some{scene} Con{decision, rest} None{}: {==}
    case Some{scene} Con{decision, rest} Some{input}: {==}

def task_recipe_evidence(task: View.TaskScene)
  -> {Composition.recipe(View.page_composition(View.TaskPage{task})) == Rule.expected_task_recipe(task) : Composition.Recipe}:
  View.TaskScene{task_id, title, status, context, timeline, previews, composer, details, actions} = task
  Conversation.Timeline{task_id, generation, groups, operations, approvals, reading, return_to_latest} = timeline
  task_recipe_components_evidence(composer, approvals, return_to_latest)

def action_evidence(parent: Identity.Key, control: Core.Control)
  -> {Interface.action(parent, control) == Rule.expected_action(parent, control) : Interface.Node}:
  match control:
    case Core.Control{+identity, label, View.Primary{}, input, availability}: {==}
    case Core.Control{+identity, label, View.Destructive{}, input, availability}: {==}
    case Core.Control{+identity, label, View.Secondary{}, input, availability}: {==}

def visible_speaker_evidence(+id: Nat, speaker: Conversation.Speaker, +text: String, +source: D.Message,
    +task: Nat, +parent: Identity.Key, +state: Core.State)
  -> {Rule.first_speech_projection(Interface.groups([Conversation.VisibleSpeech{id, speaker, text, source}], task, parent, state)) ==
      Some{Rule.SpeechProjection{Identity.Entity{parent, "message", Nat.show(id)}, "message/" ++ Nat.show(id), "Message",
        Rule.expected_speaker_role(speaker), Interface.RichText{Code.Message{task, id}, text}}} : Maybe<&2, Rule.SpeechProjection>}:
  match speaker:
    case Conversation.UserSpeech{}: {==}
    case Conversation.AssistantSpeech{}: {==}

def structure_evidence(recipe: Composition.Recipe)
  -> {Composition.structure(recipe) == Rule.expected_structure(recipe) : Composition.Structure}:
  match recipe:
    case Composition.Recipe{measure, heading, Composition.CenteredCreation{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.ChronologicalReading{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.ProjectSections{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.ProjectRows{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.StageColumns{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.AgentRows{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.UnavailableNotice{}, composer, decisions, latest}: {==}

def current_composer_context(+identity: U.Editor, revision: Nat, message: U.Text,
  +footer: +List<View.ComposerControl>, +context: Maybe<&2, Context.Preview>, submit: View.ControlDeclaration,
  feedback: U.Feedback, pending: Bool, +world: M.World()) ->
  {Rule.introduction_context(View.creation_introduction(Some{View.ComposerScene{identity, revision, message, footer, View.preview_observation(context), submit, feedback, pending}}, world)) == context : Maybe<&2, Context.Preview>}:
  match context:
    case None{}: {==}
    case Some{preview}: {==}

def composer_has_context(+message: U.Text, +profile: String, reasoning: String, +context: Context.Configuration,
  scene: View.EditorScene, +world: M.World()) ->
  {Rule.composer_footer(View.composer_scene(U.NewTask{message, profile, reasoning, context}, scene, world)) ==
    [View.ComposerControl{View.ModelSubject{}, View.control("composer/model", View.profile_label(D.find_profile(Board.profiles(world), profile), profile), U.OpenPanel{U.ModelPicker{U.NewTaskEditor{}}, "composer/model"})},
     View.ComposerControl{View.WorkspaceSubject{}, View.context_control("composer/workspace/new-task", View.observation_workspace(Context.DraftExecution{Context.preview(context, world)}), U.WorkspaceConfiguration{U.NewTaskEditor{}})},
         View.ComposerControl{View.PermissionsSubject{}, View.context_control("composer/permissions/new-task", View.observation_permissions(Context.DraftExecution{Context.preview(context, world)}, Board.profiles(world)), U.PermissionsConfiguration{U.NewTaskEditor{}})}] : +List<View.ComposerControl>}:
  View.EditorScene{identity, revision, groups, sections, submit, feedback, pending} = scene
  {==}

def Rule.evidence():
  Rule.Requirements{
    PageRegions.evidence(),
    navigation => main => layers => placement => attention => {==},
    task => task_recipe_evidence(task),
    composer => approvals => return_latest => conversation_recipe_evidence(composer, approvals, return_latest),
    message => {==},
    parent => control => action_evidence(parent, control),
    id => speaker => text => source => task => parent => state => visible_speaker_evidence(id, speaker, text, source, task, parent, state),
    +id => attention => +expanded => summary => audit => expand => collapse => +task => +parent => +state => {==},
    view => parent => state => InterfaceRules.composer_tree_agreement(view, parent, state),
    recipe => structure_evidence(recipe),
    +context => +world => {==},
    identity => revision => message => footer => context => submit => feedback => pending => world => current_composer_context(identity, revision, message, footer, context, submit, feedback, pending, world),
    +input => +parent => +world => +session => +services => {==},
    +declaration => +rest => +parent => +state => {==},
    message => profile => reasoning => context => scene => world => composer_has_context(message, profile, reasoning, context, scene, world),
    fallback => {==}}
