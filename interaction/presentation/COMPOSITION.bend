import Base
import ../../bendlib/categories.bend as Categories

type Page is Data:
  Creation{composer: Bool}
  Conversation{composer: Bool, approvals: Bool, return_latest: Bool}
  ProjectOverview{}
  ProjectCollection{}
  TaskBoard{}
  AgentCollection{}
  TaskGraphCollection{}
  Unavailable{}

type Measure is Data:
  ReadingMeasure{}
  OverviewMeasure{}
  AvailableMeasure{}

type Heading is Data:
  NoHeading{}
  ConversationHeading{}
  PageHeading{}

type Body is Data:
  CenteredCreation{}
  ChronologicalReading{}
  ProjectSections{}
  ProjectRows{}
  StageColumns{}
  AgentRows{}
  TaskGraphRows{}
  UnavailableNotice{}

type Composer is Data:
  NoComposer{}
  CenteredInput{}
  BottomInput{}

type Decisions is Data:
  NoDecisions{}
  BeforeComposer{}

type Latest is Data:
  NoLatest{}
  AboveComposer{}

type Recipe is Data:
  Recipe{measure: Measure, heading: Heading, body: Body, composer: Composer,
    decisions: Decisions, latest: Latest}

type Region is Data:
  ConversationTitle{}
  TaskActions{}
  TimelineContent{}
  LatestAction{}
  ApprovalDecisions{}
  CreationIntroduction{}
  ComposerInput{}
  ProjectTitle{}
  ProjectActions{}
  DefaultWorkspace{}
  ProjectGuidance{}
  ProjectTasks{}
  CollectionTitle{}
  CollectionActions{}
  ProjectEntries{}
  BoardTitle{}
  BoardControls{}
  BoardStages{}
  AgentEntries{}
  TaskGraphEntries{}
  UnavailableMessage{}

type Structure is Data:
  Structure{heading: +List<Region>, body: +List<Region>, dock: +List<Region>}

type Position is Data:
  HeadingPosition{}
  BodyPosition{}
  DockPosition{}

def region_name(region: Region) -> String:
  match region:
    case ConversationTitle{}: "conversation-title"
    case TaskActions{}: "task-actions"
    case TimelineContent{}: "timeline-content"
    case LatestAction{}: "latest-action"
    case ApprovalDecisions{}: "approval-decisions"
    case CreationIntroduction{}: "creation-introduction"
    case ComposerInput{}: "composer-input"
    case ProjectTitle{}: "project-title"
    case ProjectActions{}: "project-actions"
    case DefaultWorkspace{}: "default-workspace"
    case ProjectGuidance{}: "project-guidance"
    case ProjectTasks{}: "project-tasks"
    case CollectionTitle{}: "collection-title"
    case CollectionActions{}: "collection-actions"
    case ProjectEntries{}: "project-entries"
    case BoardTitle{}: "board-title"
    case BoardControls{}: "board-controls"
    case BoardStages{}: "board-stages"
    case AgentEntries{}: "agent-entries"
    case TaskGraphEntries{}: "task-graph-entries"
    case UnavailableMessage{}: "unavailable-message"

def centered_composer(present: Bool) -> Composer:
  match present:
    case True{}: CenteredInput{}
    case False{}: NoComposer{}

def bottom_composer(present: Bool) -> Composer:
  match present:
    case True{}: BottomInput{}
    case False{}: NoComposer{}

def decisions(present: Bool) -> Decisions:
  match present:
    case True{}: BeforeComposer{}
    case False{}: NoDecisions{}

def latest(present: Bool) -> Latest:
  match present:
    case True{}: AboveComposer{}
    case False{}: NoLatest{}

type OverviewContent is Data:
  Sections{}
  Rows{}
  Agents{}
  TaskGraphs{}

type Intent is Data:
  Centered{composer: Bool}
  Chronological{composer: Bool, approvals: Bool, return_latest: Bool}
  Overview{content: OverviewContent}
  BoardContent{}
  UnavailableContent{}

type Observation is Data:
  Observation{intent: Intent, value: Recipe}

def recipe_measure(value: Recipe) -> Measure:
  Recipe{measure, heading, body, composer, decisions, latest} = value
  measure

def recipe_heading(value: Recipe) -> Heading:
  Recipe{measure, heading, body, composer, decisions, latest} = value
  heading

def recipe_body(value: Recipe) -> Body:
  Recipe{measure, heading, body, composer, decisions, latest} = value
  body

def recipe_composer(value: Recipe) -> Composer:
  Recipe{measure, heading, body, composer, decisions, latest} = value
  composer

def recipe_decisions(value: Recipe) -> Decisions:
  Recipe{measure, heading, body, composer, decisions, latest} = value
  decisions

def recipe_latest(value: Recipe) -> Latest:
  Recipe{measure, heading, body, composer, decisions, latest} = value
  latest

def overview_body(content: OverviewContent) -> Body:
  match content:
    case Sections{}: ProjectSections{}
    case Rows{}: ProjectRows{}
    case Agents{}: AgentRows{}
    case TaskGraphs{}: TaskGraphRows{}

def intent_measure(intent: Intent) -> Measure:
  match intent:
    case Centered{composer}: ReadingMeasure{}
    case Chronological{composer, approvals, return_latest}: ReadingMeasure{}
    case Overview{content}: OverviewMeasure{}
    case BoardContent{}: AvailableMeasure{}
    case UnavailableContent{}: ReadingMeasure{}

def intent_heading(intent: Intent) -> Heading:
  match intent:
    case Centered{composer}: NoHeading{}
    case Chronological{composer, approvals, return_latest}: ConversationHeading{}
    case Overview{content}: PageHeading{}
    case BoardContent{}: PageHeading{}
    case UnavailableContent{}: NoHeading{}

def intent_body(intent: Intent) -> Body:
  match intent:
    case Centered{composer}: CenteredCreation{}
    case Chronological{composer, approvals, return_latest}: ChronologicalReading{}
    case Overview{content}: overview_body(content)
    case BoardContent{}: StageColumns{}
    case UnavailableContent{}: UnavailableNotice{}

def intent_composer(intent: Intent) -> Composer:
  match intent:
    case Centered{composer}: centered_composer(composer)
    case Chronological{composer, approvals, return_latest}: bottom_composer(composer)
    case Overview{content}: NoComposer{}
    case BoardContent{}: NoComposer{}
    case UnavailableContent{}: NoComposer{}

def intent_decisions(intent: Intent) -> Decisions:
  match intent:
    case Centered{composer}: NoDecisions{}
    case Chronological{composer, approvals, return_latest}: decisions(approvals)
    case Overview{content}: NoDecisions{}
    case BoardContent{}: NoDecisions{}
    case UnavailableContent{}: NoDecisions{}

def intent_latest(intent: Intent) -> Latest:
  match intent:
    case Centered{composer}: NoLatest{}
    case Chronological{composer, approvals, return_latest}: latest(return_latest)
    case Overview{content}: NoLatest{}
    case BoardContent{}: NoLatest{}
    case UnavailableContent{}: NoLatest{}

def SpecifiedMeasure(observation: Observation) -> Type:
  Observation{intent, value} = observation
  {recipe_measure(value) == intent_measure(intent) : Measure}

def SpecifiedHeading(observation: Observation) -> Type:
  Observation{intent, value} = observation
  {recipe_heading(value) == intent_heading(intent) : Heading}

def SpecifiedBody(observation: Observation) -> Type:
  Observation{intent, value} = observation
  {recipe_body(value) == intent_body(intent) : Body}

def SpecifiedComposer(observation: Observation) -> Type:
  Observation{intent, value} = observation
  {recipe_composer(value) == intent_composer(intent) : Composer}

def SpecifiedDecisions(observation: Observation) -> Type:
  Observation{intent, value} = observation
  {recipe_decisions(value) == intent_decisions(intent) : Decisions}

def SpecifiedLatest(observation: Observation) -> Type:
  Observation{intent, value} = observation
  {recipe_latest(value) == intent_latest(intent) : Latest}

def SpecifiedDecisionsLatest(observation: Observation) -> Type:
  Categories.intersection(Observation, SpecifiedDecisions, SpecifiedLatest, observation)

def SpecifiedComposerDecisionsLatest(observation: Observation) -> Type:
  Categories.intersection(Observation, SpecifiedComposer, SpecifiedDecisionsLatest, observation)

def SpecifiedBodyComposerDecisionsLatest(observation: Observation) -> Type:
  Categories.intersection(Observation, SpecifiedBody, SpecifiedComposerDecisionsLatest, observation)

def SpecifiedHeadingBodyComposerDecisionsLatest(observation: Observation) -> Type:
  Categories.intersection(Observation, SpecifiedHeading, SpecifiedBodyComposerDecisionsLatest, observation)

def AuthoredRecipe(observation: Observation) -> Type:
  Categories.intersection(Observation, SpecifiedMeasure, SpecifiedHeadingBodyComposerDecisionsLatest, observation)

def authored_measure_inclusion() -> Categories.Inclusion<Observation, AuthoredRecipe, SpecifiedMeasure>:
  Categories.intersection_first(Observation, SpecifiedMeasure, SpecifiedHeadingBodyComposerDecisionsLatest)

def authored_heading_inclusion() -> Categories.Inclusion<Observation, AuthoredRecipe, SpecifiedHeading>:
  Categories.inclusion_compose(Observation, AuthoredRecipe, SpecifiedHeadingBodyComposerDecisionsLatest, SpecifiedHeading,
    Categories.intersection_second(Observation, SpecifiedMeasure, SpecifiedHeadingBodyComposerDecisionsLatest),
    Categories.intersection_first(Observation, SpecifiedHeading, SpecifiedBodyComposerDecisionsLatest))

def authored_body_inclusion() -> Categories.Inclusion<Observation, AuthoredRecipe, SpecifiedBody>:
  Categories.inclusion_compose(Observation, AuthoredRecipe, SpecifiedHeadingBodyComposerDecisionsLatest, SpecifiedBody,
    Categories.intersection_second(Observation, SpecifiedMeasure, SpecifiedHeadingBodyComposerDecisionsLatest),
    Categories.inclusion_compose(Observation, SpecifiedHeadingBodyComposerDecisionsLatest, SpecifiedBodyComposerDecisionsLatest, SpecifiedBody,
    Categories.intersection_second(Observation, SpecifiedHeading, SpecifiedBodyComposerDecisionsLatest),
    Categories.intersection_first(Observation, SpecifiedBody, SpecifiedComposerDecisionsLatest)))

def authored_composer_inclusion() -> Categories.Inclusion<Observation, AuthoredRecipe, SpecifiedComposer>:
  Categories.inclusion_compose(Observation, AuthoredRecipe, SpecifiedHeadingBodyComposerDecisionsLatest, SpecifiedComposer,
    Categories.intersection_second(Observation, SpecifiedMeasure, SpecifiedHeadingBodyComposerDecisionsLatest),
    Categories.inclusion_compose(Observation, SpecifiedHeadingBodyComposerDecisionsLatest, SpecifiedBodyComposerDecisionsLatest, SpecifiedComposer,
    Categories.intersection_second(Observation, SpecifiedHeading, SpecifiedBodyComposerDecisionsLatest),
    Categories.inclusion_compose(Observation, SpecifiedBodyComposerDecisionsLatest, SpecifiedComposerDecisionsLatest, SpecifiedComposer,
    Categories.intersection_second(Observation, SpecifiedBody, SpecifiedComposerDecisionsLatest),
    Categories.intersection_first(Observation, SpecifiedComposer, SpecifiedDecisionsLatest))))

def authored_decisions_inclusion() -> Categories.Inclusion<Observation, AuthoredRecipe, SpecifiedDecisions>:
  Categories.inclusion_compose(Observation, AuthoredRecipe, SpecifiedHeadingBodyComposerDecisionsLatest, SpecifiedDecisions,
    Categories.intersection_second(Observation, SpecifiedMeasure, SpecifiedHeadingBodyComposerDecisionsLatest),
    Categories.inclusion_compose(Observation, SpecifiedHeadingBodyComposerDecisionsLatest, SpecifiedBodyComposerDecisionsLatest, SpecifiedDecisions,
    Categories.intersection_second(Observation, SpecifiedHeading, SpecifiedBodyComposerDecisionsLatest),
    Categories.inclusion_compose(Observation, SpecifiedBodyComposerDecisionsLatest, SpecifiedComposerDecisionsLatest, SpecifiedDecisions,
    Categories.intersection_second(Observation, SpecifiedBody, SpecifiedComposerDecisionsLatest),
    Categories.inclusion_compose(Observation, SpecifiedComposerDecisionsLatest, SpecifiedDecisionsLatest, SpecifiedDecisions,
    Categories.intersection_second(Observation, SpecifiedComposer, SpecifiedDecisionsLatest),
    Categories.intersection_first(Observation, SpecifiedDecisions, SpecifiedLatest)))))

def authored_latest_inclusion() -> Categories.Inclusion<Observation, AuthoredRecipe, SpecifiedLatest>:
  Categories.inclusion_compose(Observation, AuthoredRecipe, SpecifiedHeadingBodyComposerDecisionsLatest, SpecifiedLatest,
    Categories.intersection_second(Observation, SpecifiedMeasure, SpecifiedHeadingBodyComposerDecisionsLatest),
    Categories.inclusion_compose(Observation, SpecifiedHeadingBodyComposerDecisionsLatest, SpecifiedBodyComposerDecisionsLatest, SpecifiedLatest,
    Categories.intersection_second(Observation, SpecifiedHeading, SpecifiedBodyComposerDecisionsLatest),
    Categories.inclusion_compose(Observation, SpecifiedBodyComposerDecisionsLatest, SpecifiedComposerDecisionsLatest, SpecifiedLatest,
    Categories.intersection_second(Observation, SpecifiedBody, SpecifiedComposerDecisionsLatest),
    Categories.inclusion_compose(Observation, SpecifiedComposerDecisionsLatest, SpecifiedDecisionsLatest, SpecifiedLatest,
    Categories.intersection_second(Observation, SpecifiedComposer, SpecifiedDecisionsLatest),
    Categories.intersection_second(Observation, SpecifiedDecisions, SpecifiedLatest)))))

# Field rules describe the actual semantic composition, independently of page identity.
def source(+intent: Intent) -> Recipe:
  Recipe{intent_measure(intent), intent_heading(intent), intent_body(intent),
    intent_composer(intent), intent_decisions(intent), intent_latest(intent)}

def construct(+intent: Intent) -> Categories.Membership<Observation, AuthoredRecipe>:
  +value = source(intent)
  Categories.Membership{Observation{intent, value},
    Categories.Intersection{{==}, Categories.Intersection{{==}, Categories.Intersection{{==},
      Categories.Intersection{{==}, Categories.Intersection{{==}, {==}}}}}}}

def constructed_recipe(member: Categories.Membership<Observation, AuthoredRecipe>) -> Recipe:
  Categories.Membership{Observation{intent, value}, evidence} = member
  value

def AuthoredFor(intent: Intent) -> Recipe -> Type:
  value => AuthoredRecipe(Observation{intent, value})

def ReadingCategory(value: Recipe) -> Type:
  {recipe_measure(value) == ReadingMeasure{} : Measure}

def OverviewMeasureCategory(value: Recipe) -> Type:
  {recipe_measure(value) == OverviewMeasure{} : Measure}

def PageHeadingCategory(value: Recipe) -> Type:
  {recipe_heading(value) == PageHeading{} : Heading}

def ConversationHeadingCategory(value: Recipe) -> Type:
  {recipe_heading(value) == ConversationHeading{} : Heading}

def ChronologicalBodyCategory(value: Recipe) -> Type:
  {recipe_body(value) == ChronologicalReading{} : Body}

def OverviewCategory(value: Recipe) -> Type:
  Categories.intersection(Recipe, OverviewMeasureCategory, PageHeadingCategory, value)

def ConversationHeadingBodyCategory(value: Recipe) -> Type:
  Categories.intersection(Recipe, ConversationHeadingCategory, ChronologicalBodyCategory, value)

def ChronologicalReadingCategory(value: Recipe) -> Type:
  Categories.intersection(Recipe, ReadingCategory, ConversationHeadingBodyCategory, value)

def centered_reading_evidence(-composer: Bool, -value: Recipe, evidence: AuthoredRecipe(Observation{Centered{composer}, value})) -> ReadingCategory(value):
  Categories.Intersection{measure, remaining} = evidence
  measure

def centered_reading_inclusion(composer: Bool) -> Categories.Inclusion<Recipe, AuthoredFor(Centered{composer}), ReadingCategory>:
  Categories.Inclusion{value => evidence => centered_reading_evidence(composer, value, evidence)}

def chronological_reading_evidence(-composer: Bool, -approvals: Bool, -return_latest: Bool, -value: Recipe, evidence: AuthoredRecipe(Observation{Chronological{composer, approvals, return_latest}, value})) -> ChronologicalReadingCategory(value):
  Categories.Intersection{measure, heading_rest} = evidence
  Categories.Intersection{heading, body_rest} = heading_rest
  Categories.Intersection{body, remaining} = body_rest
  Categories.Intersection{measure, Categories.Intersection{heading, body}}

def chronological_reading_inclusion(composer: Bool, approvals: Bool, return_latest: Bool) -> Categories.Inclusion<Recipe, AuthoredFor(Chronological{composer, approvals, return_latest}), ChronologicalReadingCategory>:
  Categories.Inclusion{value => evidence => chronological_reading_evidence(composer, approvals, return_latest, value, evidence)}

def overview_evidence(-content: OverviewContent, -value: Recipe, evidence: AuthoredRecipe(Observation{Overview{content}, value})) -> OverviewCategory(value):
  Categories.Intersection{measure, heading_rest} = evidence
  Categories.Intersection{heading, body_rest} = heading_rest
  Categories.Intersection{measure, heading}

def overview_inclusion(content: OverviewContent) -> Categories.Inclusion<Recipe, AuthoredFor(Overview{content}), OverviewCategory>:
  Categories.Inclusion{value => evidence => overview_evidence(content, value, evidence)}

def unavailable_reading_evidence(-value: Recipe, evidence: AuthoredRecipe(Observation{UnavailableContent{}, value})) -> ReadingCategory(value):
  Categories.Intersection{measure, remaining} = evidence
  measure

def unavailable_reading_inclusion() -> Categories.Inclusion<Recipe, AuthoredFor(UnavailableContent{}), ReadingCategory>:
  Categories.Inclusion{value => evidence => unavailable_reading_evidence(value, evidence)}

def page_intent(page: Page) -> Intent:
  match page:
    case Creation{composer}: Centered{composer}
    case Conversation{composer, approvals, return_latest}: Chronological{composer, approvals, return_latest}
    case ProjectOverview{}: Overview{Sections{}}
    case ProjectCollection{}: Overview{Rows{}}
    case TaskBoard{}: BoardContent{}
    case AgentCollection{}: Overview{Agents{}}
    case TaskGraphCollection{}: Overview{TaskGraphs{}}
    case Unavailable{}: UnavailableContent{}

def recipe(page: Page) -> Recipe:
  constructed_recipe(construct(page_intent(page)))

def centered_composer_region(composer: Composer) -> +List<Region>:
  match composer:
    case CenteredInput{}: [ComposerInput{}]
    case _: Nil{}

def latest_region(position: Latest) -> +List<Region>:
  match position:
    case AboveComposer{}: [LatestAction{}]
    case NoLatest{}: Nil{}

def decisions_region(position: Decisions) -> +List<Region>:
  match position:
    case BeforeComposer{}: [ApprovalDecisions{}]
    case NoDecisions{}: Nil{}

def bottom_composer_region(composer: Composer) -> +List<Region>:
  match composer:
    case BottomInput{}: [ComposerInput{}]
    case _: Nil{}

def structure(recipe: Recipe) -> Structure:
  match recipe:
    case Recipe{measure, heading, CenteredCreation{}, composer, decisions, latest}:
      Structure{Nil{}, CreationIntroduction{} <> centered_composer_region(composer), Nil{}}
    case Recipe{measure, heading, ChronologicalReading{}, composer, decisions, latest}:
      Structure{[ConversationTitle{}, TaskActions{}], [TimelineContent{}],
        List.append(&2, Region, latest_region(latest),
          List.append(&2, Region, decisions_region(decisions), bottom_composer_region(composer)))}
    case Recipe{measure, heading, ProjectSections{}, composer, decisions, latest}:
      Structure{[ProjectTitle{}, ProjectActions{}], [DefaultWorkspace{}, ProjectGuidance{}, ProjectTasks{}], Nil{}}
    case Recipe{measure, heading, ProjectRows{}, composer, decisions, latest}:
      Structure{[CollectionTitle{}, CollectionActions{}], [ProjectEntries{}], Nil{}}
    case Recipe{measure, heading, StageColumns{}, composer, decisions, latest}:
      Structure{[BoardTitle{}, BoardControls{}], [BoardStages{}], Nil{}}
    case Recipe{measure, heading, AgentRows{}, composer, decisions, latest}:
      Structure{[CollectionTitle{}, CollectionActions{}], [AgentEntries{}], Nil{}}
    case Recipe{measure, heading, TaskGraphRows{}, composer, decisions, latest}:
      Structure{[CollectionTitle{}, CollectionActions{}], [TaskGraphEntries{}], Nil{}}
    case Recipe{measure, heading, UnavailableNotice{}, composer, decisions, latest}:
      Structure{Nil{}, [UnavailableMessage{}], Nil{}}

type PositionedRegion is Data:
  PositionedRegion{position: Position, region: Region}

def positioned_regions(regions: +List<Region>, +position: Position) -> +List<PositionedRegion>:
  match regions:
    case Nil{}: Nil{}
    case Con{region, rest}: PositionedRegion{position, region} <> positioned_regions(rest, position)

def ordered_regions(structure: Structure) -> +List<PositionedRegion>:
  Structure{heading, body, dock} = structure
  List.append(&2, PositionedRegion, positioned_regions(heading, HeadingPosition{}),
    List.append(&2, PositionedRegion, positioned_regions(body, BodyPosition{}), positioned_regions(dock, DockPosition{})))
