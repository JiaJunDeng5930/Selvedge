import Base
import ./composition.bend as Composition
import ./page-region-laws.bend as PageRegions
import ./ui-world.bend as View
import ./interface.bend as Interface
import ./user-experience.bend as Experience
import ./user-conversation.bend as Conversation
import ./user-input.bend as U
import ./SYSTEM.bend as Core
import ../bendlib/domain.bend as D
import ../MODEL.bend as M
import ./user-context.bend as Context
import ./client-services.bend as Services
import ../PROJECTS.bend as Projects
import ../FEATURES.bend as Features
import ../bendlib/board-state.bend as Board

type SpeechProjection is Data:
  SpeechProjection{key: String, semantic: String, label: String, role: Interface.Role, meaning: Interface.Meaning}

type Requirements is Type:
  Requirements{
    production_regions: PageRegions.Requirements,
    observed_page: @navigation:View.Navigation -> @main:View.Page -> @layers:+List<View.Layer> ->
      @placement:View.NavigationPlacement -> @attention:String ->
      {View.scene_page(View.Scene{navigation, main, layers, View.Arrangement{placement}, attention}) ==
        View.page_composition(main) : Composition.Page},
    task_page: @task:View.TaskScene ->
      {Composition.recipe(View.page_composition(View.TaskPage{task})) == expected_task_recipe(task) : Composition.Recipe},
    conversation_recipe: @composer:Bool -> @approvals:Bool -> @return_latest:Bool ->
      conversation_recipe_law(composer, approvals, return_latest),
    unavailable_page: @message:String ->
      {Composition.recipe(View.page_composition(View.MissingObject{message})) ==
        Composition.Recipe{Composition.ReadingMeasure{}, Composition.NoHeading{}, Composition.UnavailableNotice{},
          Composition.NoComposer{}, Composition.NoDecisions{}, Composition.NoLatest{}} : Composition.Recipe},
    action_prominence: @parent:String -> @control:Core.Control ->
      {Interface.action(parent, control) == expected_action(parent, control) : Interface.Node},
    visible_speaker: @+id:Nat -> @speaker:Conversation.Speaker -> @text:String -> @source:D.Message ->
      @+task:Nat -> @+parent:String -> @+state:Core.State ->
      {first_speech_projection(Interface.groups([Conversation.VisibleSpeech{id, speaker, text, source}], task, parent, state)) ==
        Some{SpeechProjection{parent ++ "/message/" ++ Nat.show(id), "message/" ++ Nat.show(id), "Message",
          expected_speaker_role(speaker), Interface.ReadOnly{text}}} : Maybe<&2, SpeechProjection>},
    composer_tree: @view:Maybe<&2, View.ComposerScene> -> @+parent:String -> @+state:Core.State ->
      {Interface.composer(view, parent, state) == Interface.expected_composer(view, parent, state) : +List<Interface.Node>},
    structure_order: @recipe:Composition.Recipe ->
      {Composition.structure(recipe) == expected_structure(recipe) : Composition.Structure},
    creation_structure: @composer:Bool ->
      {Composition.structure(Composition.recipe(Composition.Creation{composer})) ==
        Composition.Structure{Nil{}, Composition.CreationIntroduction{} <> Composition.CreationContext{} <>
          Composition.centered_composer_region(Composition.centered_composer(composer)), Nil{}} : Composition.Structure},
    creation_project: @+context:Maybe<&2, Context.Preview> -> @+world:M.World() ->
      {introduction_project(View.creation_introduction_fields(context, world)) == View.creation_selected_project(context, world) : Maybe<&2, View.ProjectChoice>},
    creation_context: @+identity:U.Editor -> @revision:Nat -> @message:U.Text -> @+footer:+List<View.ComposerControl> ->
      @+context:Maybe<&2, Context.Preview> -> @submit:View.ControlDeclaration -> @feedback:U.Feedback -> @pending:Bool -> @+world:M.World() ->
      {introduction_context(View.creation_introduction(Some{View.ComposerScene{identity, revision, message, footer, View.preview_observation(context), submit, feedback, pending}}, world)) == context : Maybe<&2, Context.Preview>},
    creation_page: @+input:Maybe<&2, View.ComposerScene> -> @+parent:String -> @+world:M.World() ->
      @+session:Experience.Session -> @+services:Services.State ->
      {Interface.page_contents(View.StartPage{input}, parent, Core.State{Experience.Application{world, session}, services}) ==
        List.append(&2, Interface.Node,
          Interface.creation_introduction_nodes(View.creation_introduction(input, world), parent, Core.State{Experience.Application{world, session}, services}),
          Interface.page_composer(input, parent, parent, Core.State{Experience.Application{world, session}, services}, Composition.BodyPosition{})) : +List<Interface.Node>},
    context_admission: @+declaration:View.ControlDeclaration -> @+rest:+List<View.ControlDeclaration> -> @+parent:String -> @+state:Core.State ->
      {Interface.controls(declaration <> rest, parent, state) == Interface.declared(parent, declaration, state) <> Interface.controls(rest, parent, state) : +List<Interface.Node>},
    composer_context: @+message:U.Text -> @+profile:String -> @reasoning:String -> @+context:Context.Configuration -> @+scene:View.EditorScene -> @+world:M.World() ->
      {composer_footer(View.composer_scene(U.NewTask{message, profile, reasoning, context}, scene, world)) ==
        [View.ComposerControl{View.ModelSubject{}, View.control("composer/model", View.profile_label(D.find_profile(Board.profiles(world), profile), profile), U.OpenPanel{U.ModelPicker{U.NewTaskEditor{}}, "composer/model"})},
         View.ComposerControl{View.WorkspaceSubject{}, View.context_control("composer/workspace/new-task", View.observation_workspace(Context.DraftExecution{Context.preview(context, world)}), U.WorkspaceConfiguration{U.NewTaskEditor{}})},
         View.ComposerControl{View.PermissionsSubject{}, View.context_control("composer/permissions/new-task", View.observation_permissions(Context.DraftExecution{Context.preview(context, world)}, Board.profiles(world)), U.PermissionsConfiguration{U.NewTaskEditor{}})}] : +List<View.ComposerControl>},
    model_label: @fallback:String -> {View.profile_label(None{}, fallback) == "Choose model" : String}
  }

def has_composer(composer: Maybe<&2, View.ComposerScene>) -> Bool:
  match composer:
    case None{}: False{}
    case Some{scene}: True{}

def expected_bottom_composer(present: Bool) -> Composition.Composer:
  match present:
    case True{}: Composition.BottomInput{}
    case False{}: Composition.NoComposer{}

def expected_decisions(present: Bool) -> Composition.Decisions:
  match present:
    case True{}: Composition.BeforeComposer{}
    case False{}: Composition.NoDecisions{}

def expected_latest(present: Bool) -> Composition.Latest:
  match present:
    case True{}: Composition.AboveComposer{}
    case False{}: Composition.NoLatest{}

def conversation_recipe_law(-composer: Bool, -approvals: Bool, -return_latest: Bool) -> Type:
  {Composition.recipe(Composition.Conversation{composer, approvals, return_latest}) ==
      Composition.Recipe{Composition.ReadingMeasure{}, Composition.ConversationHeading{}, Composition.ChronologicalReading{},
        expected_bottom_composer(composer), expected_decisions(approvals), expected_latest(return_latest)} : Composition.Recipe}

def conversation_recipe_evidence(composer: Bool, approvals: Bool, return_latest: Bool)
  -> conversation_recipe_law(composer, approvals, return_latest):
  match composer approvals return_latest:
    case False{} False{} False{}: {==}
    case False{} False{} True{}: {==}
    case False{} True{} False{}: {==}
    case False{} True{} True{}: {==}
    case True{} False{} False{}: {==}
    case True{} False{} True{}: {==}
    case True{} True{} False{}: {==}
    case True{} True{} True{}: {==}

def expected_task_recipe(task: View.TaskScene) -> Composition.Recipe:
  View.TaskScene{id, title, status, context, timeline, previews, composer, details, actions} = task
  Conversation.Timeline{task_id, generation, groups, operations, approvals, reading, return_to_latest} = timeline
  Composition.Recipe{Composition.ReadingMeasure{}, Composition.ConversationHeading{}, Composition.ChronologicalReading{},
    expected_bottom_composer(has_composer(composer)), expected_decisions(View.has_decisions(approvals)), expected_latest(View.has_return_latest(return_to_latest))}

def task_recipe_components_evidence(composer: Maybe<&2, View.ComposerScene>, approvals: +List<Conversation.DecisionRequest>, return_latest: Maybe<&2, U.Input>)
  -> {Composition.Recipe{Composition.ReadingMeasure{}, Composition.ConversationHeading{}, Composition.ChronologicalReading{},
        Composition.bottom_composer(View.has_composer(composer)), Composition.decisions(View.has_decisions(approvals)), Composition.latest(View.has_return_latest(return_latest))} ==
      Composition.Recipe{Composition.ReadingMeasure{}, Composition.ConversationHeading{}, Composition.ChronologicalReading{},
        expected_bottom_composer(has_composer(composer)), expected_decisions(View.has_decisions(approvals)), expected_latest(View.has_return_latest(return_latest))} : Composition.Recipe}:
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
  -> {Composition.recipe(View.page_composition(View.TaskPage{task})) == expected_task_recipe(task) : Composition.Recipe}:
  View.TaskScene{task_id, title, status, context, timeline, previews, composer, details, actions} = task
  Conversation.Timeline{task_id, generation, groups, operations, approvals, reading, return_to_latest} = timeline
  task_recipe_components_evidence(composer, approvals, return_to_latest)

def expected_action_role(prominence: View.Prominence) -> Interface.Role:
  match prominence:
    case View.Primary{}: Interface.PrimaryButton{}
    case View.Destructive{}: Interface.DestructiveButton{}
    case View.Secondary{}: Interface.Button{}

def expected_action(parent: String, control: Core.Control) -> Interface.Node:
  Core.Control{+identity, label, prominence, input, availability} = control
  Interface.Node{parent ++ "/" ++ identity, identity, label, expected_action_role(prominence),
    Interface.Activate{input, availability}, Nil{}}

def action_evidence(parent: String, control: Core.Control)
  -> {Interface.action(parent, control) == expected_action(parent, control) : Interface.Node}:
  match control:
    case Core.Control{+identity, label, View.Primary{}, input, availability}: {==}
    case Core.Control{+identity, label, View.Destructive{}, input, availability}: {==}
    case Core.Control{+identity, label, View.Secondary{}, input, availability}: {==}

def expected_speaker_role(speaker: Conversation.Speaker) -> Interface.Role:
  match speaker:
    case Conversation.UserSpeech{}: Interface.UserMessage{}
    case Conversation.AssistantSpeech{}: Interface.AssistantMessage{}

def first_speech_projection(nodes: +List<Interface.Node>) -> Maybe<&2, SpeechProjection>:
  match nodes:
    case Nil{}: None{}
    case Con{Interface.Node{key, semantic, label, role, meaning, children}, rest}:
      Some{SpeechProjection{key, semantic, label, role, meaning}}

def visible_speaker_evidence(+id: Nat, speaker: Conversation.Speaker, +text: String, +source: D.Message,
    +task: Nat, +parent: String, +state: Core.State)
  -> {first_speech_projection(Interface.groups([Conversation.VisibleSpeech{id, speaker, text, source}], task, parent, state)) ==
      Some{SpeechProjection{parent ++ "/message/" ++ Nat.show(id), "message/" ++ Nat.show(id), "Message",
        expected_speaker_role(speaker), Interface.ReadOnly{text}}} : Maybe<&2, SpeechProjection>}:
  match speaker:
    case Conversation.UserSpeech{}: {==}
    case Conversation.AssistantSpeech{}: {==}

def expected_structure(recipe: Composition.Recipe) -> Composition.Structure:
  match recipe:
    case Composition.Recipe{measure, heading, Composition.CenteredCreation{}, composer, decisions, latest}:
      Composition.Structure{Nil{}, Composition.CreationIntroduction{} <> Composition.CreationContext{} <> Composition.centered_composer_region(composer), Nil{}}
    case Composition.Recipe{measure, heading, Composition.ChronologicalReading{}, composer, decisions, latest}:
      Composition.Structure{[Composition.ConversationTitle{}, Composition.TaskActions{}],
        [Composition.TimelineContent{}, Composition.StreamingOutput{}],
        List.append(&2, Composition.Region, Composition.latest_region(latest),
          List.append(&2, Composition.Region, Composition.decisions_region(decisions), Composition.bottom_composer_region(composer)))}
    case Composition.Recipe{measure, heading, Composition.ProjectSections{}, composer, decisions, latest}:
      Composition.Structure{[Composition.ProjectTitle{}, Composition.ProjectActions{}],
        [Composition.DefaultWorkspace{}, Composition.ProjectGuidance{}, Composition.ProjectTasks{}], Nil{}}
    case Composition.Recipe{measure, heading, Composition.ProjectRows{}, composer, decisions, latest}:
      Composition.Structure{[Composition.CollectionTitle{}, Composition.CollectionActions{}], [Composition.ProjectEntries{}], Nil{}}
    case Composition.Recipe{measure, heading, Composition.StageColumns{}, composer, decisions, latest}:
      Composition.Structure{[Composition.BoardTitle{}, Composition.BoardControls{}], [Composition.BoardStages{}], Nil{}}
    case Composition.Recipe{measure, heading, Composition.AgentRows{}, composer, decisions, latest}:
      Composition.Structure{[Composition.CollectionTitle{}, Composition.CollectionActions{}], [Composition.AgentEntries{}], Nil{}}
    case Composition.Recipe{measure, heading, Composition.UnavailableNotice{}, composer, decisions, latest}:
      Composition.Structure{Nil{}, [Composition.UnavailableMessage{}], Nil{}}

def structure_evidence(recipe: Composition.Recipe)
  -> {Composition.structure(recipe) == expected_structure(recipe) : Composition.Structure}:
  match recipe:
    case Composition.Recipe{measure, heading, Composition.CenteredCreation{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.ChronologicalReading{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.ProjectSections{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.ProjectRows{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.StageColumns{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.AgentRows{}, composer, decisions, latest}: {==}
    case Composition.Recipe{measure, heading, Composition.UnavailableNotice{}, composer, decisions, latest}: {==}





def introduction_context(value: View.CreationIntroduction) -> Maybe<&2, Context.Preview>:
  View.CreationIntroduction{heading, summary, context, project, choose} = value
  context

def introduction_project(value: View.CreationIntroduction) -> Maybe<&2, View.ProjectChoice>:
  View.CreationIntroduction{heading, summary, context, project, choose} = value
  project

def current_composer_context(+identity: U.Editor, revision: Nat, message: U.Text,
  +footer: +List<View.ComposerControl>, +context: Maybe<&2, Context.Preview>, submit: View.ControlDeclaration,
  feedback: U.Feedback, pending: Bool, +world: M.World()) ->
  {introduction_context(View.creation_introduction(Some{View.ComposerScene{identity, revision, message, footer, View.preview_observation(context), submit, feedback, pending}}, world)) == context : Maybe<&2, Context.Preview>}:
  match context:
    case None{}: {==}
    case Some{preview}: {==}



def selected_project_registry(origin: Context.Origin, +id: Nat, workspace: Context.WorkspaceValue,
  sandbox: Context.SandboxValue, approval: Context.ApprovalValue, guidance: Context.GuidancePreview, +world: M.World()) ->
  {View.creation_selected_project(Some{Context.ProspectiveContext{origin, Some{id}, workspace, sandbox, approval, guidance}}, world) ==
    View.creation_project(Projects.find(Projects.registry(Features.State(), world), id), id) : Maybe<&2, View.ProjectChoice>}:
  {==}







def composer_footer(view: Maybe<&2, View.ComposerScene>) -> +List<View.ComposerControl>:
  match view:
    case None{}: Nil{}
    case Some{View.ComposerScene{identity, revision, message, footer, context, submit, feedback, pending}}: footer

def composer_has_context(+message: U.Text, +profile: String, reasoning: String, +context: Context.Configuration,
  scene: View.EditorScene, +world: M.World()) ->
  {composer_footer(View.composer_scene(U.NewTask{message, profile, reasoning, context}, scene, world)) ==
    [View.ComposerControl{View.ModelSubject{}, View.control("composer/model", View.profile_label(D.find_profile(Board.profiles(world), profile), profile), U.OpenPanel{U.ModelPicker{U.NewTaskEditor{}}, "composer/model"})},
     View.ComposerControl{View.WorkspaceSubject{}, View.context_control("composer/workspace/new-task", View.observation_workspace(Context.DraftExecution{Context.preview(context, world)}), U.WorkspaceConfiguration{U.NewTaskEditor{}})},
         View.ComposerControl{View.PermissionsSubject{}, View.context_control("composer/permissions/new-task", View.observation_permissions(Context.DraftExecution{Context.preview(context, world)}, Board.profiles(world)), U.PermissionsConfiguration{U.NewTaskEditor{}})}] : +List<View.ComposerControl>}:
  View.EditorScene{identity, revision, groups, sections, submit, feedback, pending} = scene
  {==}



def evidence() -> Requirements:
  Requirements{
    PageRegions.evidence(),
    navigation => main => layers => placement => attention => {==},
    task => task_recipe_evidence(task),
    composer => approvals => return_latest => conversation_recipe_evidence(composer, approvals, return_latest),
    message => {==},
    parent => control => action_evidence(parent, control),
    id => speaker => text => source => task => parent => state => visible_speaker_evidence(id, speaker, text, source, task, parent, state),
    view => parent => state => Interface.composer_tree_agreement(view, parent, state),
    recipe => structure_evidence(recipe),
    composer => {==},
    +context => +world => {==},
    identity => revision => message => footer => context => submit => feedback => pending => world => current_composer_context(identity, revision, message, footer, context, submit, feedback, pending, world),
    +input => +parent => +world => +session => +services => {==},
    +declaration => +rest => +parent => +state => {==},
    message => profile => reasoning => context => scene => world => composer_has_context(message, profile, reasoning, context, scene, world),
    fallback => {==}}
