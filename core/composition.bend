import Base

type Page is Data:
  Creation{composer: Bool}
  Conversation{composer: Bool, approvals: Bool, return_latest: Bool}
  ProjectOverview{}
  ProjectCollection{}
  TaskBoard{}
  AgentCollection{}
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
  StreamingOutput{}
  LatestAction{}
  ApprovalDecisions{}
  CreationIntroduction{}
  CreationContext{}
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
    case StreamingOutput{}: "streaming-output"
    case LatestAction{}: "latest-action"
    case ApprovalDecisions{}: "approval-decisions"
    case CreationIntroduction{}: "creation-introduction"
    case CreationContext{}: "creation-context"
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

def recipe(page: Page) -> Recipe:
  match page:
    case Creation{composer}: Recipe{ReadingMeasure{}, NoHeading{}, CenteredCreation{}, centered_composer(composer), NoDecisions{}, NoLatest{}}
    case Conversation{composer, approvals, return_latest}:
      Recipe{ReadingMeasure{}, ConversationHeading{}, ChronologicalReading{}, bottom_composer(composer), decisions(approvals), latest(return_latest)}
    case ProjectOverview{}: Recipe{OverviewMeasure{}, PageHeading{}, ProjectSections{}, NoComposer{}, NoDecisions{}, NoLatest{}}
    case ProjectCollection{}: Recipe{OverviewMeasure{}, PageHeading{}, ProjectRows{}, NoComposer{}, NoDecisions{}, NoLatest{}}
    case TaskBoard{}: Recipe{AvailableMeasure{}, PageHeading{}, StageColumns{}, NoComposer{}, NoDecisions{}, NoLatest{}}
    case AgentCollection{}: Recipe{OverviewMeasure{}, PageHeading{}, AgentRows{}, NoComposer{}, NoDecisions{}, NoLatest{}}
    case Unavailable{}: Recipe{ReadingMeasure{}, NoHeading{}, UnavailableNotice{}, NoComposer{}, NoDecisions{}, NoLatest{}}

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
      Structure{Nil{}, CreationIntroduction{} <> CreationContext{} <> centered_composer_region(composer), Nil{}}
    case Recipe{measure, heading, ChronologicalReading{}, composer, decisions, latest}:
      Structure{[ConversationTitle{}, TaskActions{}], [TimelineContent{}, StreamingOutput{}],
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
