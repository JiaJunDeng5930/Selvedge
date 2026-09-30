import Base
import ./composition.bend as Composition
import ./ui-world.bend as View
import ./interface.bend as Interface
import ./user-experience.bend as Experience
import ./user-conversation.bend as Conversation
import ./user-input.bend as U
import ./SYSTEM.bend as Core
import ../bendlib/domain.bend as D

type SpeechProjection is Data:
  SpeechProjection{key: String, semantic: String, label: String, role: Interface.Role, meaning: Interface.Meaning}

type Requirements is Type:
  Requirements{
    observed_page: @capacity:View.Capacity -> @application:Experience.Application ->
      {View.observed_main_page(View.observe(capacity, application)) == View.observed_arrangement_page(View.observe(capacity, application)) : Composition.Page},
    task_page: @task:View.TaskScene ->
      {Composition.recipe(View.page_composition(View.TaskPage{task})) == expected_task_recipe(task) : Composition.Recipe},
    conversation_recipe: @composer:Bool -> @approvals:Bool -> @return_latest:Bool ->
      {Composition.recipe(Composition.Conversation{composer, approvals, return_latest}) ==
        Composition.Recipe{Composition.ReadingMeasure{}, Composition.ConversationHeading{}, Composition.ChronologicalReading{},
          expected_bottom_composer(composer), expected_decisions(approvals), expected_latest(return_latest)} : Composition.Recipe},
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
      {Composition.structure(recipe) == expected_structure(recipe) : Composition.Structure}
  }

def has_composer(composer: Maybe<&2, View.ComposerScene>) -> Bool:
  match composer:
    case None{}: False{}
    case Some{scene}: True{}

def has_decisions(decisions: +List<Conversation.DecisionRequest>) -> Bool:
  match decisions:
    case Nil{}: False{}
    case Con{decision, rest}: True{}

def has_return_latest(action: Maybe<&2, U.Input>) -> Bool:
  match action:
    case None{}: False{}
    case Some{input}: True{}

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

def conversation_recipe_evidence(composer: Bool, approvals: Bool, return_latest: Bool)
  -> {Composition.recipe(Composition.Conversation{composer, approvals, return_latest}) ==
      Composition.Recipe{Composition.ReadingMeasure{}, Composition.ConversationHeading{}, Composition.ChronologicalReading{},
        expected_bottom_composer(composer), expected_decisions(approvals), expected_latest(return_latest)} : Composition.Recipe}:
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
    expected_bottom_composer(has_composer(composer)), expected_decisions(has_decisions(approvals)), expected_latest(has_return_latest(return_to_latest))}

def task_recipe_components_evidence(composer: Maybe<&2, View.ComposerScene>, approvals: +List<Conversation.DecisionRequest>, return_latest: Maybe<&2, U.Input>)
  -> {Composition.Recipe{Composition.ReadingMeasure{}, Composition.ConversationHeading{}, Composition.ChronologicalReading{},
        Composition.bottom_composer(View.has_composer(composer)), Composition.decisions(View.has_decisions(approvals)), Composition.latest(View.has_return_latest(return_latest))} ==
      Composition.Recipe{Composition.ReadingMeasure{}, Composition.ConversationHeading{}, Composition.ChronologicalReading{},
        expected_bottom_composer(has_composer(composer)), expected_decisions(has_decisions(approvals)), expected_latest(has_return_latest(return_latest))} : Composition.Recipe}:
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
      Composition.Structure{Nil{}, Composition.centered_composer_region(composer), Nil{}}
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

def evidence() -> Requirements:
  Requirements{
    capacity => application => View.observed_page_agreement(capacity, application),
    task => task_recipe_evidence(task),
    composer => approvals => return_latest => conversation_recipe_evidence(composer, approvals, return_latest),
    message => {==},
    parent => control => action_evidence(parent, control),
    id => speaker => text => source => task => parent => state => visible_speaker_evidence(id, speaker, text, source, task, parent, state),
    view => parent => state => Interface.composer_tree_agreement(view, parent, state),
    recipe => structure_evidence(recipe)}
