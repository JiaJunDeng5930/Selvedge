From Stdlib Require Import String List Bool.
Import ListNotations.
Open Scope string_scope.

Inductive page :=
| SharedInterface | Creation (composer : bool)
| Conversation (composer approvals : bool)
| ProjectOverview | ProjectCollection | TaskBoard | TaskGraphCollection
| HistorySearchCollection | Unavailable.

Inductive measure := ReadingMeasure | OverviewMeasure | AvailableMeasure.
Inductive heading := NoHeading | ConversationHeading | PageHeading.
Inductive body :=
| SharedInterfaceBody | CenteredCreation | ChronologicalReading
| ProjectSections | ProjectRows | StageColumns | TaskGraphRows | HistoryResultRows
| UnavailableNotice.
Inductive composer_position := NoComposer | CenteredInput | BottomInput.
Inductive decision_position := NoDecisions | BeforeComposer.

Record page_recipe := Recipe {
  reading_measure : measure;
  heading_kind : heading;
  body_kind : body;
  composer_kind : composer_position;
  decisions_kind : decision_position
}.

Definition recipe value :=
  match value with
  | SharedInterface => Recipe OverviewMeasure PageHeading SharedInterfaceBody
      NoComposer NoDecisions
  | Creation composer => Recipe ReadingMeasure NoHeading CenteredCreation
      (if composer then CenteredInput else NoComposer) NoDecisions
  | Conversation composer approvals =>
      Recipe ReadingMeasure ConversationHeading ChronologicalReading
        (if composer then BottomInput else NoComposer)
        (if approvals then BeforeComposer else NoDecisions)
  | ProjectOverview => Recipe OverviewMeasure PageHeading ProjectSections
      NoComposer NoDecisions
  | ProjectCollection => Recipe OverviewMeasure PageHeading ProjectRows
      NoComposer NoDecisions
  | TaskBoard => Recipe AvailableMeasure PageHeading StageColumns
      NoComposer NoDecisions
  | TaskGraphCollection => Recipe OverviewMeasure PageHeading TaskGraphRows
      NoComposer NoDecisions
  | HistorySearchCollection => Recipe OverviewMeasure PageHeading HistoryResultRows
      NoComposer NoDecisions
  | Unavailable => Recipe ReadingMeasure NoHeading UnavailableNotice
      NoComposer NoDecisions
  end.

Inductive region :=
| SharedTitle | SharedContent | ConversationHeader | ConversationTitle | TaskActions
| TimelineContent | LatestAction | ApprovalDecisions
| CreationIntroduction | ComposerInput
| ProjectTitle | ProjectActions | DefaultWorkspace | ProjectGuidance | ProjectTasks
| CollectionTitle | CollectionActions | ProjectEntries | HistoryResults
| BoardTitle | BoardControls | BoardStages | TaskGraphEntries
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
  | CreationIntroduction => "creation-introduction"
  | ComposerInput => "composer-input"
  | ProjectTitle => "project-title" | ProjectActions => "project-actions"
  | DefaultWorkspace => "default-workspace" | ProjectGuidance => "project-guidance"
  | ProjectTasks => "project-tasks" | CollectionTitle => "collection-title"
  | CollectionActions => "collection-actions" | ProjectEntries => "project-entries"
  | HistoryResults => "history-results"
  | BoardTitle => "board-title" | BoardControls => "board-controls"
  | BoardStages => "board-stages"
  | TaskGraphEntries => "task-graph-entries" | UnavailableMessage => "unavailable-message"
  end.

Definition structure_for plan :=
  match body_kind plan with
  | CenteredCreation => Structure []
      (CreationIntroduction ::
        match composer_kind plan with CenteredInput => [ComposerInput] | _ => [] end) []
  | ChronologicalReading => Structure [ConversationHeader] [TimelineContent]
      (List.app (match decisions_kind plan with BeforeComposer => [ApprovalDecisions] | _ => [] end)
       (match composer_kind plan with BottomInput => [ComposerInput] | _ => [] end))
  | ProjectSections => Structure [ProjectTitle; ProjectActions]
      [DefaultWorkspace; ProjectGuidance; ProjectTasks] []
  | ProjectRows => Structure [CollectionTitle; CollectionActions] [ProjectEntries] []
  | HistoryResultRows => Structure [CollectionTitle; CollectionActions] [HistoryResults] []
  | StageColumns => Structure [BoardTitle; BoardControls] [BoardStages] []
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
