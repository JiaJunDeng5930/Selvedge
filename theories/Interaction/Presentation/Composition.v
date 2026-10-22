From Stdlib Require Import String List Bool.
Import ListNotations.
Open Scope string_scope.

Inductive page :=
| SharedInterface | Creation (composer : bool)
| Conversation (composer approvals return_latest : bool)
| ProjectOverview | ProjectCollection | TaskBoard
| AgentCollection | TaskGraphCollection | Unavailable.

Inductive measure := ReadingMeasure | OverviewMeasure | AvailableMeasure.
Inductive heading := NoHeading | ConversationHeading | PageHeading.
Inductive body :=
| SharedInterfaceBody | CenteredCreation | ChronologicalReading
| ProjectSections | ProjectRows | StageColumns | AgentRows | TaskGraphRows
| UnavailableNotice.
Inductive composer_position := NoComposer | CenteredInput | BottomInput.
Inductive decision_position := NoDecisions | BeforeComposer.
Inductive latest_position := NoLatest | AboveComposer.

Record page_recipe := Recipe {
  reading_measure : measure;
  heading_kind : heading;
  body_kind : body;
  composer_kind : composer_position;
  decisions_kind : decision_position;
  latest_kind : latest_position
}.

Definition recipe value :=
  match value with
  | SharedInterface => Recipe OverviewMeasure PageHeading SharedInterfaceBody
      NoComposer NoDecisions NoLatest
  | Creation composer => Recipe ReadingMeasure NoHeading CenteredCreation
      (if composer then CenteredInput else NoComposer) NoDecisions NoLatest
  | Conversation composer approvals return_latest =>
      Recipe ReadingMeasure ConversationHeading ChronologicalReading
        (if composer then BottomInput else NoComposer)
        (if approvals then BeforeComposer else NoDecisions)
        (if return_latest then AboveComposer else NoLatest)
  | ProjectOverview => Recipe OverviewMeasure PageHeading ProjectSections
      NoComposer NoDecisions NoLatest
  | ProjectCollection => Recipe OverviewMeasure PageHeading ProjectRows
      NoComposer NoDecisions NoLatest
  | TaskBoard => Recipe AvailableMeasure PageHeading StageColumns
      NoComposer NoDecisions NoLatest
  | AgentCollection => Recipe OverviewMeasure PageHeading AgentRows
      NoComposer NoDecisions NoLatest
  | TaskGraphCollection => Recipe OverviewMeasure PageHeading TaskGraphRows
      NoComposer NoDecisions NoLatest
  | Unavailable => Recipe ReadingMeasure NoHeading UnavailableNotice
      NoComposer NoDecisions NoLatest
  end.

Inductive region :=
| SharedTitle | SharedContent | ConversationHeader | ConversationTitle | TaskActions
| TimelineContent | LatestAction | ApprovalDecisions
| CreationIntroduction | ComposerInput
| ProjectTitle | ProjectActions | DefaultWorkspace | ProjectGuidance | ProjectTasks
| CollectionTitle | CollectionActions | ProjectEntries
| BoardTitle | BoardControls | BoardStages | AgentEntries | TaskGraphEntries
| UnavailableMessage.

Inductive position := HeadingPosition | BodyPosition | DockPosition.

Record structure := Structure {
  heading_regions : list region;
  body_regions : list region;
  dock_regions : list region
}.

Definition region_name value :=
  match value with
  | SharedTitle => "shared-ui-title" | SharedContent => "shared-ui-content"
  | ConversationHeader => "conversation-header"
  | ConversationTitle => "conversation-title" | TaskActions => "task-actions"
  | TimelineContent => "timeline-content" | LatestAction => "latest-action"
  | ApprovalDecisions => "approval-decisions"
  | CreationIntroduction => "creation-introduction" | ComposerInput => "composer-input"
  | ProjectTitle => "project-title" | ProjectActions => "project-actions"
  | DefaultWorkspace => "default-workspace" | ProjectGuidance => "project-guidance"
  | ProjectTasks => "project-tasks" | CollectionTitle => "collection-title"
  | CollectionActions => "collection-actions" | ProjectEntries => "project-entries"
  | BoardTitle => "board-title" | BoardControls => "board-controls"
  | BoardStages => "board-stages" | AgentEntries => "agent-entries"
  | TaskGraphEntries => "task-graph-entries" | UnavailableMessage => "unavailable-message"
  end.

Definition structure_for plan :=
  match body_kind plan with
  | CenteredCreation => Structure []
      (CreationIntroduction ::
        match composer_kind plan with CenteredInput => [ComposerInput] | _ => [] end) []
  | ChronologicalReading => Structure [ConversationHeader] [TimelineContent]
      (List.app (match latest_kind plan with AboveComposer => [LatestAction] | _ => [] end)
       (List.app (match decisions_kind plan with BeforeComposer => [ApprovalDecisions] | _ => [] end)
       (match composer_kind plan with BottomInput => [ComposerInput] | _ => [] end)))
  | ProjectSections => Structure [ProjectTitle; ProjectActions]
      [DefaultWorkspace; ProjectGuidance; ProjectTasks] []
  | ProjectRows => Structure [CollectionTitle; CollectionActions] [ProjectEntries] []
  | StageColumns => Structure [BoardTitle; BoardControls] [BoardStages] []
  | AgentRows => Structure [CollectionTitle; CollectionActions] [AgentEntries] []
  | SharedInterfaceBody => Structure [SharedTitle] [SharedContent] []
  | TaskGraphRows => Structure [CollectionTitle; CollectionActions] [TaskGraphEntries] []
  | UnavailableNotice => Structure [] [UnavailableMessage] []
  end.

Definition page_structure value := structure_for (recipe value).

Definition ordered_regions value :=
  let regions := page_structure value in
  List.app (map (fun region => (HeadingPosition, region)) (heading_regions regions))
    (List.app (map (fun region => (BodyPosition, region)) (body_regions regions))
      (map (fun region => (DockPosition, region)) (dock_regions regions))).
