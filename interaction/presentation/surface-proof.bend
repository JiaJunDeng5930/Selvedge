import Base
import ./SURFACE.bend as Surface
import ../TYPES.bend as Interaction
import ../experience/ACTIVITY.bend as Activity

def layer_region_agreement(+meaning: Surface.Meaning) ->
  {Surface.layer_region(meaning) == Surface.layer_region_meaning(meaning) : Maybe<&2, Surface.LayerBehavior>}:
  match meaning:
    case Surface.ActivityGroup{activity, dismiss, outside, escape}: {==}
    case Surface.DecisionGroup{decision}: {==}
    case Surface.WorkspaceCollection{collection}: {==}
    case Surface.WorkspaceMember{collection, path}: {==}
    case Surface.ActionUnit{action}: {==}
    case Surface.ActionFeedback{feedback}: {==}
    case Surface.ActionExplanation{assessment}: {==}
    case Surface.ActionCommit{assessment, input, availability}: {==}
    case Surface.ObjectGroup{object}: {==}
    case Surface.SupportingControl{support, property, input, availability}: {==}
    case Surface.InformationText{role}: {==}
    case Surface.LayerRegion{dismiss, outside, escape}: {==}
    case Surface.DirectoryBrowserLocation{value}: {==}
    case Surface.PanelToggle{expanded, input, availability}: {==}
    case Surface.CardContent{face}: {==}
    case Surface.MovableCard{destinations, face}: {==}
    case Surface.Region{}: {==}
    case Surface.PageContext{conversation}: {==}
    case Surface.ActivityContent{expanded, audit}: {==}
    case Surface.ProjectGroup{project, selected, expanded}: {==}
    case Surface.TaskRow{task, status, selected}: {==}
    case Surface.ProjectChooser{selected}: {==}
    case Surface.DirectoryRow{path, primary}: {==}
    case Surface.ContextSummary{observation}: {==}
    case Surface.ChoiceGroup{}: {==}
    case Surface.Choice{kind, classification, selected, description, input, availability}: {==}
    case Surface.PageRegion{region, position}: {==}
    case Surface.BoardLane{stage, count}: {==}
    case Surface.CardArchive{count}: {==}
    case Surface.BoardSearch{filter}: {==}
    case Surface.BoardGroup{grouping}: {==}
    case Surface.ReadOnly{text}: {==}
    case Surface.Fact{value}: {==}
    case Surface.RichText{source, value}: {==}
    case Surface.TaskFacts{details}: {==}
    case Surface.CodeFacts{view}: {==}
    case Surface.Activate{input, availability}: {==}
    case Surface.Edit{editor, field, entry, value, choices}: {==}
    case Surface.SearchChoices{query}: {==}
    case Surface.ReceiveFile{editor, enabled}: {==}
    case Surface.EnterDirectory{editor, text}: {==}
    case Surface.BoardProfile{automatic, selected, choices, enabled}: {==}

def Surface.layer_region_evidence():
  Surface.LayerRegionRequirements{
    meaning => layer_region_agreement(meaning),
    dismiss => outside => escape => {==},
    activity => dismiss => outside => escape => {==}}
