import ./FRAME.bend as Frame
import ./MODEL.bend as Doc
import ../layout/CONTENT.bend as Content
import ../layout/PROGRAM.bend as Allocation
import ../layout/physical-space.bend as Model
import ../layout/GEOMETRY.bend as Spatial
import ../layout/RENDERER.bend as Renderer
import Base
import ./RENDERED.bend as Rendered
import ./SPEC.bend as Spec
import ./SOURCE.bend as Source
import ../controls/GEOMETRY.bend as Geometry
import ../../bendlib/string-equality.bend as SafeText
import ../../bendlib/equality-proof.bend as TextProof
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/presentation/interaction-proof.bend as FenceEvidence
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes
import ../../interaction/presentation/MODEL.bend as View
import ../../interaction/experience/PROGRAM.bend as UX
import ../../interaction/submission/FIELDS.bend as Forms
import ../../interaction/interactive_markdown/TYPES.bend as Interactive
import ../../interaction/IDENTITY.bend as UIIdentity

def source_combine_exposure(+parent: Source.Exposure, +own: Source.Exposure) ->
  {Source.combine_exposure(parent, own) == Spec.combine_exposure(parent, own) : Source.Exposure}:
  match parent:
    case Source.Exposed{}: {==}
    case Source.Concealed{}: {==}

def source_attributes_exposure(+values: +List<Source.Attribute>) ->
  {Source.attributes_exposure(values) == Spec.attributes_exposure(values) : Source.Exposure}:
  match values:
    case Nil{}: {==}
    case Con{Source.ExposureAttribute{+value}, +rest}:
      Equal.trans(Source.Exposure, Source.combine_exposure(value, Source.attributes_exposure(rest)), Spec.combine_exposure(value, Source.attributes_exposure(rest)), Spec.combine_exposure(value, Spec.attributes_exposure(rest)),
        source_combine_exposure(value, Source.attributes_exposure(rest)),
        Equal.cong(Source.Exposure, Source.Exposure, (tail => Spec.combine_exposure(value, tail)), Source.attributes_exposure(rest), Spec.attributes_exposure(rest), source_attributes_exposure(rest)))
    case Con{Source.ReadingAttribute{binding}, +rest}: source_attributes_exposure(rest)
    case Con{Source.EditorBindingAttribute{key}, +rest}: source_attributes_exposure(rest)
    case Con{Source.IdAttribute{value}, +rest}: source_attributes_exposure(rest)
    case Con{Source.DataAttribute{name, value}, +rest}: source_attributes_exposure(rest)
    case Con{Source.AriaAttribute{name, value}, +rest}: source_attributes_exposure(rest)
    case Con{Source.RoleAttribute{value}, +rest}: source_attributes_exposure(rest)
    case Con{Source.TitleAttribute{value}, +rest}: source_attributes_exposure(rest)
    case Con{Source.TabIndexAttribute{value}, +rest}: source_attributes_exposure(rest)
    case Con{Source.ValueAttribute{value}, +rest}: source_attributes_exposure(rest)
    case Con{Source.CheckedAttribute{}, +rest}: source_attributes_exposure(rest)
    case Con{Source.OpenAttribute{}, +rest}: source_attributes_exposure(rest)
    case Con{Source.DraggableAttribute{value}, +rest}: source_attributes_exposure(rest)
    case Con{Source.InertAttribute{}, +rest}: source_attributes_exposure(rest)

def source_attributes_inert(+values: +List<Source.Attribute>) ->
  {Source.attributes_inert(values) == Spec.attributes_inert(values) : Bool}:
  match values:
    case Nil{}: {==}
    case Con{Source.InertAttribute{}, rest}: {==}
    case Con{Source.ExposureAttribute{value}, +rest}: source_attributes_inert(rest)
    case Con{Source.ReadingAttribute{binding}, +rest}: source_attributes_inert(rest)
    case Con{Source.EditorBindingAttribute{key}, +rest}: source_attributes_inert(rest)
    case Con{Source.IdAttribute{value}, +rest}: source_attributes_inert(rest)
    case Con{Source.DataAttribute{name, value}, +rest}: source_attributes_inert(rest)
    case Con{Source.AriaAttribute{name, value}, +rest}: source_attributes_inert(rest)
    case Con{Source.RoleAttribute{value}, +rest}: source_attributes_inert(rest)
    case Con{Source.TitleAttribute{value}, +rest}: source_attributes_inert(rest)
    case Con{Source.TabIndexAttribute{value}, +rest}: source_attributes_inert(rest)
    case Con{Source.ValueAttribute{value}, +rest}: source_attributes_inert(rest)
    case Con{Source.CheckedAttribute{}, +rest}: source_attributes_inert(rest)
    case Con{Source.OpenAttribute{}, +rest}: source_attributes_inert(rest)
    case Con{Source.DraggableAttribute{value}, +rest}: source_attributes_inert(rest)

def source_node_exposure(+node: Source.Node) ->
  {Source.node_exposure(node) == Spec.node_exposure(node) : Source.Exposure}:
  match node:
    case Source.NativeAttachment{key, target, +attrs, style, children}: source_attributes_exposure(attrs)
    case Source.Box{key, tag, style, +attrs, children}: source_attributes_exposure(attrs)
    case Source.Control{key, tag, style, +attrs, name, enabled, first, remaining, children}: source_attributes_exposure(attrs)
    case Source.Field{key, kind, style, +attrs, value, placeholder, options, policy, name, enabled, first, remaining}: source_attributes_exposure(attrs)
    case Source.Text{key, value, font, wrapping}: {==}
    case Source.Glyph{key, drawing, style}: {==}
    case Source.RichText{key, style, content, attachments, native_owner}: {==}

def source_node_inert(+node: Source.Node) ->
  {Source.node_inert(node) == Spec.node_inert(node) : Bool}:
  match node:
    case Source.NativeAttachment{key, target, +attrs, style, children}: source_attributes_inert(attrs)
    case Source.Box{key, tag, style, +attrs, children}: source_attributes_inert(attrs)
    case Source.Control{key, tag, style, +attrs, name, enabled, first, remaining, children}: source_attributes_inert(attrs)
    case Source.Field{key, kind, style, +attrs, value, placeholder, options, policy, name, enabled, first, remaining}: source_attributes_inert(attrs)
    case Source.Text{key, value, font, wrapping}: {==}
    case Source.Glyph{key, drawing, style}: {==}
    case Source.RichText{key, style, content, attachments, native_owner}: {==}

# Private structural evidence for the public, complete frame requirements.
# No cache representation, historical validator or hash result is a premise.
def exposure_choice(+same: Bool, +current: Source.Exposure, +fallback: Source.Exposure) ->
  {Rendered.choose_exposure(same, current, fallback) == Bool.pick(Source.Exposure, same, current, fallback) : Source.Exposure}:
  match same:
    case True{}: {==}
    case False{}: {==}

def first_observation_step(+same: Bool, +element: Rendered.Element, +actual: Maybe<&2, Rendered.Element>, +expected: Maybe<&2, Rendered.Element>, equality: {actual == expected : Maybe<&2, Rendered.Element>}) ->
  {Rendered.find_element_match(same, element, (_ => actual)) == Bool.pick((Maybe<&2, Rendered.Element>), same, Some{element}, expected) : Maybe<&2, Rendered.Element>}:
  match same:
    case True{}: {==}
    case False{}: equality

def first_observation(+elements: +List<Rendered.Element>, +key: String) ->
  {Rendered.find_element(elements, key) == Spec.first_observed_element(elements, key) : Maybe<&2, Rendered.Element>}:
  match elements:
    case Nil{}: {==}
    case Con{Rendered.Element{+observed, +visible, +enabled, +tab, +keyboard, +scroll, +bounds, +hit, +paint}, +rest}:
      %Equal.sym(Bool, SafeText.string_equal(observed, key), String.eq(observed, key), TextProof.public_refines(observed, key)) :
        {Rendered.find_element_match(_, Rendered.Element{observed, visible, enabled, tab, keyboard, scroll, bounds, hit, paint}, (_ => Rendered.find_element(rest, key))) == Spec.first_observed_element(Rendered.Element{observed, visible, enabled, tab, keyboard, scroll, bounds, hit, paint} <> rest, key) : Maybe<&2, Rendered.Element>}
      first_observation_step(String.eq(observed, key), Rendered.Element{observed, visible, enabled, tab, keyboard, scroll, bounds, hit, paint}, Rendered.find_element(rest, key), Spec.first_observed_element(rest, key), first_observation(rest, key))

def tab_stop(+found: Maybe<&2, Rendered.Element>) ->
  {Rendered.tab_stop(found) == Spec.tab_stop(found) : Bool}:
  match found:
    case None{}:
      {==}
    case Some{Rendered.Element{+key, +visible, +enabled, +tab, +keyboard, +scroll, +bounds, +hit, +paint_bounds}}:
      {==}

def own_tab_stop(+eligible: Bool, +elements: +List<Rendered.Element>, +identity: String) ->
  {Rendered.own_tab_stop(eligible, elements, identity) == Spec.own_tab_stop(eligible, elements, identity) : Bool}:
  match eligible:
    case False{}: {==}
    case True{}:
      %Equal.sym((Maybe<&2, Rendered.Element>), Rendered.find_element(elements, identity), Spec.first_observed_element(elements, identity), first_observation(elements, identity)) :
        {Rendered.tab_stop(_) == Spec.tab_stop(Spec.first_observed_element(elements, identity)) : Bool}
      tab_stop(Spec.first_observed_element(elements, identity))


def enabled(+availability: View.Availability) ->
  {Rendered.enabled(availability) == Spec.enabled(availability) : Bool}:
  match availability:
    case View.Unavailable{+reason}:
      {==}
    case View.Available{}: {==}
    case View.NeedsDirectoryObservation{}: {==}

def field_control(+entry: Forms.Entry) ->
  {Rendered.field_control(entry) == Spec.field_control(entry) : Bool}:
  match entry:
    case Forms.DisplayOnly{}:
      {==}
    case Forms.FileCollection{}:
      {==}
    case Forms.DirectoryCollection{}:
      {==}
    case Forms.SingleLine{}: {==}
    case Forms.Multiline{}: {==}
    case Forms.StructuredText{}: {==}
    case Forms.Choice{}: {==}
    case Forms.MultipleChoices{}: {==}
    case Forms.PositiveInteger{}: {==}

def interactive(+meaning: SurfaceTypes.Meaning) ->
  {Rendered.interactive(meaning) == Spec.interactive(meaning) : Bool}:
  match meaning:
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{+identity, +occurrence, +tag, +attrs, Interactive.FieldBinding{+state_id, +schema, +raw, +canonical, +validation, +enabled}, +children}}:
      {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{+identity, +occurrence, +tag, +attrs, Interactive.ActionBinding{+kind, +enabled, +pending}, +children}}:
      {==}
    case SurfaceTypes.InteractiveView{+event, +command, +label, +enabled}:
      {==}
    case SurfaceTypes.SupportingControl{+support, +property, +input, +availability}:
      {==}
    case SurfaceTypes.MovableCard{+destinations, +face}:
      {==}
    case SurfaceTypes.ActionCommit{+assessment, +input, +availability}:
      {==}
    case SurfaceTypes.Activate{+input, +availability}:
      {==}
    case SurfaceTypes.SettingEntry{+subject, +value, +input, +availability}:
      {==}
    case SurfaceTypes.PanelToggle{+expanded, +input, +availability}:
      {==}
    case SurfaceTypes.Choice{+kind, +icon, +selected, +description, +input, +availability}:
      {==}
    case SurfaceTypes.Edit{+editor, +field, +entry, +value, +choices}:
      %Equal.sym(Bool, Rendered.field_control(entry), Spec.field_control(entry), field_control(entry)) :
        {_ == Spec.field_control(entry) : Bool}
      {==}
    case SurfaceTypes.SearchChoices{+query}:
      {==}
    case SurfaceTypes.BoardSearch{+filter}:
      {==}
    case SurfaceTypes.ReceiveFile{+editor, +enabled}:
      {==}
    case SurfaceTypes.EnterDirectory{+editor, +text}:
      {==}
    case SurfaceTypes.DirectoryBrowserLocation{+value}:
      {==}
    case SurfaceTypes.BoardProfile{+automatic, +selected, +choices, +enabled}:
      {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{identity, occurrence, tag, attrs, Interactive.NoBinding{}, children}}: {==}
    case SurfaceTypes.ActivityRow{role}: {==}
    case SurfaceTypes.ActivityGroup{activity, dismiss, outside, escape}: {==}
    case SurfaceTypes.DecisionGroup{decision}: {==}
    case SurfaceTypes.WorkspaceCollection{collection}: {==}
    case SurfaceTypes.WorkspaceMember{collection, path}: {==}
    case SurfaceTypes.ActionUnit{action}: {==}
    case SurfaceTypes.ActionFeedback{feedback}: {==}
    case SurfaceTypes.ActionExplanation{assessment}: {==}
    case SurfaceTypes.ObjectGroup{object}: {==}
    case SurfaceTypes.InformationText{role}: {==}
    case SurfaceTypes.LayerRegion{dismiss, outside, escape}: {==}
    case SurfaceTypes.CardContent{face}: {==}
    case SurfaceTypes.Region{}: {==}
    case SurfaceTypes.PageContext{conversation}: {==}
    case SurfaceTypes.ActivityContent{expanded, audit}: {==}
    case SurfaceTypes.ProjectGroup{project, selected, expanded}: {==}
    case SurfaceTypes.TaskRow{task, status, selected}: {==}
    case SurfaceTypes.TaskChildren{task}: {==}
    case SurfaceTypes.ProjectChooser{selected}: {==}
    case SurfaceTypes.DirectoryRow{path, primary}: {==}
    case SurfaceTypes.ContextSummary{observation}: {==}
    case SurfaceTypes.ChoiceGroup{}: {==}
    case SurfaceTypes.PageRegion{region, position}: {==}
    case SurfaceTypes.BoardLane{stage, count}: {==}
    case SurfaceTypes.CardArchive{count}: {==}
    case SurfaceTypes.BoardGroup{grouping}: {==}
    case SurfaceTypes.ReadOnly{text}: {==}
    case SurfaceTypes.Fact{value}: {==}
    case SurfaceTypes.RichText{source, value}: {==}
    case SurfaceTypes.TaskFacts{details}: {==}
    case SurfaceTypes.CodeFacts{view}: {==}
    case SurfaceTypes.InteractiveRegion{identity, source_visible}: {==}

def required_enabled(+meaning: SurfaceTypes.Meaning) ->
  {Rendered.required_enabled(meaning) == Spec.required_enabled(meaning) : Bool}:
  match meaning:
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{+identity, +occurrence, +tag, +attrs, Interactive.FieldBinding{+state_id, +schema, +raw, +canonical, +validation, +enabled}, +children}}:
      {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{+identity, +occurrence, +tag, +attrs, Interactive.ActionBinding{+kind, +enabled, +pending}, +children}}:
      {==}
    case SurfaceTypes.InteractiveView{+event, +command, +label, +enabled}:
      {==}
    case SurfaceTypes.SupportingControl{+support, +property, +input, +availability}:
      %Equal.sym(Bool, Rendered.enabled(availability), Spec.enabled(availability), enabled(availability)) :
        {UX.support_visible(support) && _ == UX.support_visible(support) && Spec.enabled(availability) : Bool}
      {==}
    case SurfaceTypes.MovableCard{+destinations, +face}:
      {==}
    case SurfaceTypes.ActionCommit{+assessment, +input, +availability}:
      %Equal.sym(Bool, Rendered.enabled(availability), Spec.enabled(availability), enabled(availability)) :
        {UX.assessment_ready(assessment) && _ == UX.assessment_ready(assessment) && Spec.enabled(availability) : Bool}
      {==}
    case SurfaceTypes.Activate{+input, +availability}:
      %Equal.sym(Bool, Rendered.enabled(availability), Spec.enabled(availability), enabled(availability)) :
        {_ == Spec.enabled(availability) : Bool}
      {==}
    case SurfaceTypes.SettingEntry{+subject, +value, +input, +availability}:
      %Equal.sym(Bool, Rendered.enabled(availability), Spec.enabled(availability), enabled(availability)) :
        {_ == Spec.enabled(availability) : Bool}
      {==}
    case SurfaceTypes.PanelToggle{+expanded, +input, +availability}:
      %Equal.sym(Bool, Rendered.enabled(availability), Spec.enabled(availability), enabled(availability)) :
        {_ == Spec.enabled(availability) : Bool}
      {==}
    case SurfaceTypes.Choice{+kind, +icon, +selected, +description, +input, +availability}:
      %Equal.sym(Bool, Rendered.enabled(availability), Spec.enabled(availability), enabled(availability)) :
        {_ == Spec.enabled(availability) : Bool}
      {==}
    case SurfaceTypes.ReceiveFile{+editor, +enabled}:
      {==}
    case SurfaceTypes.BoardProfile{+automatic, +selected, +choices, +enabled}:
      {==}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{identity, occurrence, tag, attrs, Interactive.NoBinding{}, children}}: interactive(SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{identity, occurrence, tag, attrs, Interactive.NoBinding{}, children}})
    case SurfaceTypes.ActivityRow{role}: interactive(SurfaceTypes.ActivityRow{role})
    case SurfaceTypes.ActivityGroup{activity, dismiss, outside, escape}: interactive(SurfaceTypes.ActivityGroup{activity, dismiss, outside, escape})
    case SurfaceTypes.DecisionGroup{decision}: interactive(SurfaceTypes.DecisionGroup{decision})
    case SurfaceTypes.WorkspaceCollection{collection}: interactive(SurfaceTypes.WorkspaceCollection{collection})
    case SurfaceTypes.WorkspaceMember{collection, path}: interactive(SurfaceTypes.WorkspaceMember{collection, path})
    case SurfaceTypes.ActionUnit{action}: interactive(SurfaceTypes.ActionUnit{action})
    case SurfaceTypes.ActionFeedback{feedback}: interactive(SurfaceTypes.ActionFeedback{feedback})
    case SurfaceTypes.ActionExplanation{assessment}: interactive(SurfaceTypes.ActionExplanation{assessment})
    case SurfaceTypes.ObjectGroup{object}: interactive(SurfaceTypes.ObjectGroup{object})
    case SurfaceTypes.InformationText{role}: interactive(SurfaceTypes.InformationText{role})
    case SurfaceTypes.LayerRegion{dismiss, outside, escape}: interactive(SurfaceTypes.LayerRegion{dismiss, outside, escape})
    case SurfaceTypes.DirectoryBrowserLocation{value}: interactive(SurfaceTypes.DirectoryBrowserLocation{value})
    case SurfaceTypes.CardContent{face}: interactive(SurfaceTypes.CardContent{face})
    case SurfaceTypes.Region{}: interactive(SurfaceTypes.Region{})
    case SurfaceTypes.PageContext{conversation}: interactive(SurfaceTypes.PageContext{conversation})
    case SurfaceTypes.ActivityContent{expanded, audit}: interactive(SurfaceTypes.ActivityContent{expanded, audit})
    case SurfaceTypes.ProjectGroup{project, selected, expanded}: interactive(SurfaceTypes.ProjectGroup{project, selected, expanded})
    case SurfaceTypes.TaskRow{task, status, selected}: interactive(SurfaceTypes.TaskRow{task, status, selected})
    case SurfaceTypes.TaskChildren{task}: interactive(SurfaceTypes.TaskChildren{task})
    case SurfaceTypes.ProjectChooser{selected}: interactive(SurfaceTypes.ProjectChooser{selected})
    case SurfaceTypes.DirectoryRow{path, primary}: interactive(SurfaceTypes.DirectoryRow{path, primary})
    case SurfaceTypes.ContextSummary{observation}: interactive(SurfaceTypes.ContextSummary{observation})
    case SurfaceTypes.ChoiceGroup{}: interactive(SurfaceTypes.ChoiceGroup{})
    case SurfaceTypes.PageRegion{region, position}: interactive(SurfaceTypes.PageRegion{region, position})
    case SurfaceTypes.BoardLane{stage, count}: interactive(SurfaceTypes.BoardLane{stage, count})
    case SurfaceTypes.CardArchive{count}: interactive(SurfaceTypes.CardArchive{count})
    case SurfaceTypes.BoardSearch{filter}: interactive(SurfaceTypes.BoardSearch{filter})
    case SurfaceTypes.BoardGroup{grouping}: interactive(SurfaceTypes.BoardGroup{grouping})
    case SurfaceTypes.ReadOnly{text}: interactive(SurfaceTypes.ReadOnly{text})
    case SurfaceTypes.Fact{value}: interactive(SurfaceTypes.Fact{value})
    case SurfaceTypes.RichText{source, value}: interactive(SurfaceTypes.RichText{source, value})
    case SurfaceTypes.TaskFacts{details}: interactive(SurfaceTypes.TaskFacts{details})
    case SurfaceTypes.CodeFacts{view}: interactive(SurfaceTypes.CodeFacts{view})
    case SurfaceTypes.InteractiveRegion{identity, source_visible}: interactive(SurfaceTypes.InteractiveRegion{identity, source_visible})
    case SurfaceTypes.Edit{editor, field, entry, value, choices}: interactive(SurfaceTypes.Edit{editor, field, entry, value, choices})
    case SurfaceTypes.SearchChoices{query}: interactive(SurfaceTypes.SearchChoices{query})
    case SurfaceTypes.EnterDirectory{editor, text}: interactive(SurfaceTypes.EnterDirectory{editor, text})

def persistent(+role: SurfaceTypes.Role) ->
  {Rendered.persistent(role) == Spec.persistent(role) : Bool}:
  match role:
    case SurfaceTypes.Composer{}:
      {==}
    case SurfaceTypes.DialogActions{}:
      {==}
    case SurfaceTypes.Approval{}:
      {==}
    case SurfaceTypes.Toolbar{}:
      {==}
    case SurfaceTypes.GlobalNavigation{compact}: {==}
    case SurfaceTypes.GlobalNavigationEntry{selected, compact}: {==}
    case SurfaceTypes.CompactHeader{}: {==}
    case SurfaceTypes.CompactWorkScope{title, count}: {==}
    case SurfaceTypes.CompactNavigationMenu{}: {==}
    case SurfaceTypes.CompactNavigationEntry{selected}: {==}
    case SurfaceTypes.WorkTabs{}: {==}
    case SurfaceTypes.WorkTab{selected}: {==}
    case SurfaceTypes.WorkTabGroup{}: {==}
    case SurfaceTypes.WorkOverviewButton{count}: {==}
    case SurfaceTypes.WorkChoiceRow{}: {==}
    case SurfaceTypes.Navigation{}: {==}
    case SurfaceTypes.NavigationHeader{}: {==}
    case SurfaceTypes.NavigationEntry{selected}: {==}
    case SurfaceTypes.NavigationCollection{}: {==}
    case SurfaceTypes.NavigationSection{}: {==}
    case SurfaceTypes.Main{}: {==}
    case SurfaceTypes.Heading{}: {==}
    case SurfaceTypes.PrimaryButton{}: {==}
    case SurfaceTypes.DestructiveButton{}: {==}
    case SurfaceTypes.SelectedButton{}: {==}
    case SurfaceTypes.ComposerActions{}: {==}
    case SurfaceTypes.Timeline{}: {==}
    case SurfaceTypes.Activity{}: {==}
    case SurfaceTypes.UserMessage{}: {==}
    case SurfaceTypes.AssistantMessage{}: {==}
    case SurfaceTypes.CodeBlock{}: {==}
    case SurfaceTypes.ApprovalQueue{}: {==}
    case SurfaceTypes.Section{}: {==}
    case SurfaceTypes.Dialog{}: {==}
    case SurfaceTypes.Menu{}: {==}
    case SurfaceTypes.Details{}: {==}
    case SurfaceTypes.Card{}: {==}
    case SurfaceTypes.Button{}: {==}
    case SurfaceTypes.Field{}: {==}
    case SurfaceTypes.Content{}: {==}
    case SurfaceTypes.Alert{}: {==}

def issue(+violated: Bool, +violation: Rendered.Violation) ->
  {Rendered.issue(violated, violation) == Spec.issue(violated, violation) : +List<Rendered.Violation>}:
  match violated:
    case True{}:
      {==}
    case False{}:
      {==}

def declared_exposure(+controls: +List<Rendered.ControlExposure>, +key: String) ->
  {Rendered.declared_exposure(controls, key) == Spec.declared_exposure(controls, key) : Source.Exposure}:
  match controls:
    case Nil{}:
      {==}
    case Con{Rendered.ControlExposure{+owner, +exposure, +command_enabled}, +rest}:
      %Equal.sym(Bool, SafeText.string_equal(owner, key), String.eq(owner, key), TextProof.public_refines(owner, key)) :
        {Rendered.choose_exposure(_, exposure, Rendered.declared_exposure(rest, key)) == Bool.pick(Source.Exposure, String.eq(owner, key), exposure, Spec.declared_exposure(rest, key)) : Source.Exposure}
      %Equal.sym(Source.Exposure, Rendered.declared_exposure(rest, key), Spec.declared_exposure(rest, key), declared_exposure(rest, key)) :
        {Rendered.choose_exposure(String.eq(owner, key), exposure, _) == Bool.pick(Source.Exposure, String.eq(owner, key), exposure, Spec.declared_exposure(rest, key)) : Source.Exposure}
      %Equal.sym(Source.Exposure, Rendered.choose_exposure(String.eq(owner, key), exposure, Spec.declared_exposure(rest, key)), Bool.pick(Source.Exposure, String.eq(owner, key), exposure, Spec.declared_exposure(rest, key)), exposure_choice(String.eq(owner, key), exposure, Spec.declared_exposure(rest, key))) :
        {_ == Bool.pick(Source.Exposure, String.eq(owner, key), exposure, Spec.declared_exposure(rest, key)) : Source.Exposure}
      {==}

def enabled_geometry(+required: Bool, +key: String, +visible: Bool, +keyboard: Bool, +scroll: Bool, +bounds: Geometry.Rect, +hit: String, +must_be_visible: Bool, +viewport: Geometry.Rect) ->
  {Rendered.enabled_geometry(required, key, visible, keyboard, scroll, bounds, hit, must_be_visible, viewport) == Spec.enabled_geometry(required, key, visible, keyboard, scroll, bounds, hit, must_be_visible, viewport) : +List<Rendered.Violation>}:
  match required:
    case False{}:
      {==}
    case True{}:
      %Equal.sym(Bool, SafeText.string_equal(key, hit), String.eq(key, hit), TextProof.public_refines(key, hit)) :
        {List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(keyboard && (visible || scroll)) || (must_be_visible && Bool.not(visible && Geometry.contains(viewport, bounds))), Rendered.UnreachableControl{key}), Rendered.issue(visible && Bool.not(_), Rendered.OccludedControl{key})) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(keyboard && (visible || scroll)) || (must_be_visible && Bool.not(visible && Geometry.contains(viewport, bounds))), Rendered.UnreachableControl{key}), Spec.issue(visible && Bool.not(String.eq(key, hit)), Rendered.OccludedControl{key})) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Rendered.issue(visible && Bool.not(String.eq(key, hit)), Rendered.OccludedControl{key}), Spec.issue(visible && Bool.not(String.eq(key, hit)), Rendered.OccludedControl{key}), issue(visible && Bool.not(String.eq(key, hit)), Rendered.OccludedControl{key})) :
        {List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(keyboard && (visible || scroll)) || (must_be_visible && Bool.not(visible && Geometry.contains(viewport, bounds))), Rendered.UnreachableControl{key}), _) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(keyboard && (visible || scroll)) || (must_be_visible && Bool.not(visible && Geometry.contains(viewport, bounds))), Rendered.UnreachableControl{key}), Spec.issue(visible && Bool.not(String.eq(key, hit)), Rendered.OccludedControl{key})) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Rendered.issue(Bool.not(keyboard && (visible || scroll)) || (must_be_visible && Bool.not(visible && Geometry.contains(viewport, bounds))), Rendered.UnreachableControl{key}), Spec.issue(Bool.not(keyboard && (visible || scroll)) || (must_be_visible && Bool.not(visible && Geometry.contains(viewport, bounds))), Rendered.UnreachableControl{key}), issue(Bool.not(keyboard && (visible || scroll)) || (must_be_visible && Bool.not(visible && Geometry.contains(viewport, bounds))), Rendered.UnreachableControl{key})) :
        {List.append(&2, Rendered.Violation, _, Spec.issue(visible && Bool.not(String.eq(key, hit)), Rendered.OccludedControl{key})) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(keyboard && (visible || scroll)) || (must_be_visible && Bool.not(visible && Geometry.contains(viewport, bounds))), Rendered.UnreachableControl{key}), Spec.issue(visible && Bool.not(String.eq(key, hit)), Rendered.OccludedControl{key})) : +List<Rendered.Violation>}
      {==}

def control_geometry(+required: Bool, +key: String, +found: Maybe<&2, Rendered.Element>, +must_be_visible: Bool, +viewport: Geometry.Rect) ->
  {Rendered.control_geometry(required, key, found, must_be_visible, viewport) == Spec.control_geometry(required, key, found, must_be_visible, viewport) : +List<Rendered.Violation>}:
  match found:
    case None{}:
      {==}
    case Some{Rendered.Element{+observed, +visible, +enabled, +tab, +keyboard, +scroll, +bounds, +hit, +paint_bounds}}:
      %Equal.sym(+List<Rendered.Violation>, Rendered.enabled_geometry(required, key, visible, keyboard, scroll, bounds, hit, must_be_visible, viewport), Spec.enabled_geometry(required, key, visible, keyboard, scroll, bounds, hit, must_be_visible, viewport), enabled_geometry(required, key, visible, keyboard, scroll, bounds, hit, must_be_visible, viewport)) :
        {List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(((required && enabled) || (Bool.not(required) && Bool.not(enabled)))), Rendered.DisabledAppearance{key}), _) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(((required && enabled) || (Bool.not(required) && Bool.not(enabled)))), Rendered.DisabledAppearance{key}), Spec.enabled_geometry(required, key, visible, keyboard, scroll, bounds, hit, must_be_visible, viewport)) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Rendered.issue(Bool.not(((required && enabled) || (Bool.not(required) && Bool.not(enabled)))), Rendered.DisabledAppearance{key}), Spec.issue(Bool.not(((required && enabled) || (Bool.not(required) && Bool.not(enabled)))), Rendered.DisabledAppearance{key}), issue(Bool.not(((required && enabled) || (Bool.not(required) && Bool.not(enabled)))), Rendered.DisabledAppearance{key})) :
        {List.append(&2, Rendered.Violation, _, Spec.enabled_geometry(required, key, visible, keyboard, scroll, bounds, hit, must_be_visible, viewport)) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(((required && enabled) || (Bool.not(required) && Bool.not(enabled)))), Rendered.DisabledAppearance{key}), Spec.enabled_geometry(required, key, visible, keyboard, scroll, bounds, hit, must_be_visible, viewport)) : +List<Rendered.Violation>}
      {==}

def bounded_dialog(+key: String, +found: Maybe<&2, Rendered.Element>, +viewport: Geometry.Rect) ->
  {Rendered.bounded_dialog(key, found, viewport) == Spec.bounded_dialog(key, found, viewport) : +List<Rendered.Violation>}:
  match found:
    case None{}:
      {==}
    case Some{Rendered.Element{+id, +visible, +enabled, +tab, +keyboard, +scroll, +bounds, +hit, +paint_bounds}}:
      %Equal.sym(+List<Rendered.Violation>, Rendered.issue(Bool.not(visible && Geometry.contains(viewport, bounds)), Rendered.EscapedDialog{key}), Spec.issue(Bool.not(visible && Geometry.contains(viewport, bounds)), Rendered.EscapedDialog{key}), issue(Bool.not(visible && Geometry.contains(viewport, bounds)), Rendered.EscapedDialog{key})) :
        {_ == Spec.issue(Bool.not(visible && Geometry.contains(viewport, bounds)), Rendered.EscapedDialog{key}) : +List<Rendered.Violation>}
      {==}

def dialog_geometry(+role: SurfaceTypes.Role, +key: String, +found: Maybe<&2, Rendered.Element>, +viewport: Geometry.Rect) ->
  {Rendered.dialog_geometry(role, key, found, viewport) == Spec.dialog_geometry(role, key, found, viewport) : +List<Rendered.Violation>}:
  match role:
    case SurfaceTypes.Dialog{}:
      %Equal.sym(+List<Rendered.Violation>, Rendered.bounded_dialog(key, found, viewport), Spec.bounded_dialog(key, found, viewport), bounded_dialog(key, found, viewport)) :
        {_ == Spec.bounded_dialog(key, found, viewport) : +List<Rendered.Violation>}
      {==}
    case SurfaceTypes.Menu{}:
      %Equal.sym(+List<Rendered.Violation>, Rendered.bounded_dialog(key, found, viewport), Spec.bounded_dialog(key, found, viewport), bounded_dialog(key, found, viewport)) :
        {_ == Spec.bounded_dialog(key, found, viewport) : +List<Rendered.Violation>}
      {==}
    case SurfaceTypes.GlobalNavigation{compact}: {==}
    case SurfaceTypes.GlobalNavigationEntry{selected, compact}: {==}
    case SurfaceTypes.CompactHeader{}: {==}
    case SurfaceTypes.CompactWorkScope{title, count}: {==}
    case SurfaceTypes.CompactNavigationMenu{}: {==}
    case SurfaceTypes.CompactNavigationEntry{selected}: {==}
    case SurfaceTypes.WorkTabs{}: {==}
    case SurfaceTypes.WorkTab{selected}: {==}
    case SurfaceTypes.WorkTabGroup{}: {==}
    case SurfaceTypes.WorkOverviewButton{count}: {==}
    case SurfaceTypes.WorkChoiceRow{}: {==}
    case SurfaceTypes.Navigation{}: {==}
    case SurfaceTypes.NavigationHeader{}: {==}
    case SurfaceTypes.NavigationEntry{selected}: {==}
    case SurfaceTypes.NavigationCollection{}: {==}
    case SurfaceTypes.NavigationSection{}: {==}
    case SurfaceTypes.Main{}: {==}
    case SurfaceTypes.Heading{}: {==}
    case SurfaceTypes.PrimaryButton{}: {==}
    case SurfaceTypes.DestructiveButton{}: {==}
    case SurfaceTypes.SelectedButton{}: {==}
    case SurfaceTypes.ComposerActions{}: {==}
    case SurfaceTypes.DialogActions{}: {==}
    case SurfaceTypes.Timeline{}: {==}
    case SurfaceTypes.Activity{}: {==}
    case SurfaceTypes.UserMessage{}: {==}
    case SurfaceTypes.AssistantMessage{}: {==}
    case SurfaceTypes.Composer{}: {==}
    case SurfaceTypes.Approval{}: {==}
    case SurfaceTypes.Toolbar{}: {==}
    case SurfaceTypes.CodeBlock{}: {==}
    case SurfaceTypes.ApprovalQueue{}: {==}
    case SurfaceTypes.Section{}: {==}
    case SurfaceTypes.Details{}: {==}
    case SurfaceTypes.Card{}: {==}
    case SurfaceTypes.Button{}: {==}
    case SurfaceTypes.Field{}: {==}
    case SurfaceTypes.Content{}: {==}
    case SurfaceTypes.Alert{}: {==}

def concealed_control(+required: Bool, +key: String, +found: Maybe<&2, Rendered.Element>) ->
  {Rendered.concealed_control(required, key, found) == Spec.concealed_control(required, key, found) : +List<Rendered.Violation>}:
  match found:
    case None{}:
      {==}
    case Some{Rendered.Element{+observed, +visible, +enabled, +tab, +keyboard, +scroll, +bounds, +hit, +paint}}:
      %Equal.sym(+List<Rendered.Violation>, Rendered.issue(visible || tab || keyboard || Bool.not(String.eq(hit, "")), Rendered.UnreachableControl{key}), Spec.issue(visible || tab || keyboard || Bool.not(String.eq(hit, "")), Rendered.UnreachableControl{key}), issue(visible || tab || keyboard || Bool.not(String.eq(hit, "")), Rendered.UnreachableControl{key})) :
        {List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(((required && enabled) || (Bool.not(required) && Bool.not(enabled)))), Rendered.DisabledAppearance{key}), _) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(((required && enabled) || (Bool.not(required) && Bool.not(enabled)))), Rendered.DisabledAppearance{key}), Spec.issue(visible || tab || keyboard || Bool.not(String.eq(hit, "")), Rendered.UnreachableControl{key})) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Rendered.issue(Bool.not(((required && enabled) || (Bool.not(required) && Bool.not(enabled)))), Rendered.DisabledAppearance{key}), Spec.issue(Bool.not(((required && enabled) || (Bool.not(required) && Bool.not(enabled)))), Rendered.DisabledAppearance{key}), issue(Bool.not(((required && enabled) || (Bool.not(required) && Bool.not(enabled)))), Rendered.DisabledAppearance{key})) :
        {List.append(&2, Rendered.Violation, _, Spec.issue(visible || tab || keyboard || Bool.not(String.eq(hit, "")), Rendered.UnreachableControl{key})) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(((required && enabled) || (Bool.not(required) && Bool.not(enabled)))), Rendered.DisabledAppearance{key}), Spec.issue(visible || tab || keyboard || Bool.not(String.eq(hit, "")), Rendered.UnreachableControl{key})) : +List<Rendered.Violation>}
      {==}

def exposed_control(+exposure: Source.Exposure, +meaning: SurfaceTypes.Meaning, +key: String, +found: Maybe<&2, Rendered.Element>, +persistent: Bool, +viewport: Geometry.Rect) ->
  {Rendered.exposed_control(exposure, meaning, key, found, persistent, viewport) == Spec.exposed_control(exposure, meaning, key, found, persistent, viewport) : +List<Rendered.Violation>}:
  match exposure:
    case Source.Exposed{}:
      %Equal.sym(Bool, Rendered.required_enabled(meaning), Spec.required_enabled(meaning), required_enabled(meaning)) :
        {Rendered.control_geometry(_, key, found, persistent, viewport) == Spec.control_geometry(Spec.required_enabled(meaning), key, found, persistent, viewport) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Rendered.control_geometry(Spec.required_enabled(meaning), key, found, persistent, viewport), Spec.control_geometry(Spec.required_enabled(meaning), key, found, persistent, viewport), control_geometry(Spec.required_enabled(meaning), key, found, persistent, viewport)) :
        {_ == Spec.control_geometry(Spec.required_enabled(meaning), key, found, persistent, viewport) : +List<Rendered.Violation>}
      {==}
    case Source.Concealed{}:
      %Equal.sym(Bool, Rendered.required_enabled(meaning), Spec.required_enabled(meaning), required_enabled(meaning)) :
        {Rendered.concealed_control(_, key, found) == Spec.concealed_control(Spec.required_enabled(meaning), key, found) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Rendered.concealed_control(Spec.required_enabled(meaning), key, found), Spec.concealed_control(Spec.required_enabled(meaning), key, found), concealed_control(Spec.required_enabled(meaning), key, found)) :
        {_ == Spec.concealed_control(Spec.required_enabled(meaning), key, found) : +List<Rendered.Violation>}
      {==}

def node_controls_with(+is_control: Bool, +meaning: SurfaceTypes.Meaning, +key: String, +found: Maybe<&2, Rendered.Element>, +persistent: Bool, +viewport: Geometry.Rect, +controls: +List<Rendered.ControlExposure>) ->
  {Rendered.node_controls_with(is_control, meaning, key, found, persistent, viewport, controls) == Spec.node_controls_with(is_control, meaning, key, found, persistent, viewport, controls) : +List<Rendered.Violation>}:
  match is_control:
    case False{}:
      {==}
    case True{}:
      %Equal.sym(Source.Exposure, Rendered.declared_exposure(controls, key), Spec.declared_exposure(controls, key), declared_exposure(controls, key)) :
        {Rendered.exposed_control(_, meaning, key, found, persistent, viewport) == Spec.exposed_control(Spec.declared_exposure(controls, key), meaning, key, found, persistent, viewport) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Rendered.exposed_control(Spec.declared_exposure(controls, key), meaning, key, found, persistent, viewport), Spec.exposed_control(Spec.declared_exposure(controls, key), meaning, key, found, persistent, viewport), exposed_control(Spec.declared_exposure(controls, key), meaning, key, found, persistent, viewport)) :
        {_ == Spec.exposed_control(Spec.declared_exposure(controls, key), meaning, key, found, persistent, viewport) : +List<Rendered.Violation>}
      {==}

def reachable_toolbar(+key: String, +found: Maybe<&2, Rendered.Element>) ->
  {Rendered.reachable_toolbar(key, found) == Spec.reachable_toolbar(key, found) : +List<Rendered.Violation>}:
  match found:
    case None{}:
      {==}
    case Some{Rendered.Element{+id, +visible, +enabled, +tab, +keyboard, +scroll, +bounds, +hit, +paint_bounds}}:
      %Equal.sym(+List<Rendered.Violation>, Rendered.issue(Bool.not(visible || scroll), Rendered.EscapedDialog{key}), Spec.issue(Bool.not(visible || scroll), Rendered.EscapedDialog{key}), issue(Bool.not(visible || scroll), Rendered.EscapedDialog{key})) :
        {_ == Spec.issue(Bool.not(visible || scroll), Rendered.EscapedDialog{key}) : +List<Rendered.Violation>}
      {==}

def region_geometry(+role: SurfaceTypes.Role, +key: String, +found: Maybe<&2, Rendered.Element>, +viewport: Geometry.Rect) ->
  {Rendered.region_geometry(role, key, found, viewport) == Spec.region_geometry(role, key, found, viewport) : +List<Rendered.Violation>}:
  match role:
    case SurfaceTypes.GlobalNavigation{compact}:
      %Equal.sym(+List<Rendered.Violation>, Rendered.bounded_dialog(key, found, viewport), Spec.bounded_dialog(key, found, viewport), bounded_dialog(key, found, viewport)) :
        {_ == Spec.bounded_dialog(key, found, viewport) : +List<Rendered.Violation>}
      {==}
    case SurfaceTypes.GlobalNavigationEntry{selected, compact}:
      {==}
    case SurfaceTypes.CompactHeader{}:
      %Equal.sym(+List<Rendered.Violation>, Rendered.bounded_dialog(key, found, viewport), Spec.bounded_dialog(key, found, viewport), bounded_dialog(key, found, viewport)) :
        {_ == Spec.bounded_dialog(key, found, viewport) : +List<Rendered.Violation>}
      {==}
    case SurfaceTypes.CompactWorkScope{title, count}:
      {==}
    case SurfaceTypes.CompactNavigationMenu{}:
      {==}
    case SurfaceTypes.CompactNavigationEntry{selected}:
      {==}
    case SurfaceTypes.WorkTabs{}:
      %Equal.sym(+List<Rendered.Violation>, Rendered.bounded_dialog(key, found, viewport), Spec.bounded_dialog(key, found, viewport), bounded_dialog(key, found, viewport)) :
        {_ == Spec.bounded_dialog(key, found, viewport) : +List<Rendered.Violation>}
      {==}
    case SurfaceTypes.WorkTab{selected}:
      {==}
    case SurfaceTypes.WorkTabGroup{}:
      {==}
    case SurfaceTypes.WorkOverviewButton{count}:
      {==}
    case SurfaceTypes.WorkChoiceRow{}:
      {==}
    case SurfaceTypes.Navigation{}:
      %Equal.sym(+List<Rendered.Violation>, Rendered.bounded_dialog(key, found, viewport), Spec.bounded_dialog(key, found, viewport), bounded_dialog(key, found, viewport)) :
        {_ == Spec.bounded_dialog(key, found, viewport) : +List<Rendered.Violation>}
      {==}
    case SurfaceTypes.NavigationEntry{+selected}:
      {==}
    case SurfaceTypes.NavigationCollection{}:
      {==}
    case SurfaceTypes.NavigationSection{}:
      {==}
    case SurfaceTypes.NavigationHeader{}:
      %Equal.sym(+List<Rendered.Violation>, Rendered.bounded_dialog(key, found, viewport), Spec.bounded_dialog(key, found, viewport), bounded_dialog(key, found, viewport)) :
        {_ == Spec.bounded_dialog(key, found, viewport) : +List<Rendered.Violation>}
      {==}
    case SurfaceTypes.Main{}:
      %Equal.sym(+List<Rendered.Violation>, Rendered.bounded_dialog(key, found, viewport), Spec.bounded_dialog(key, found, viewport), bounded_dialog(key, found, viewport)) :
        {_ == Spec.bounded_dialog(key, found, viewport) : +List<Rendered.Violation>}
      {==}
    case SurfaceTypes.Composer{}:
      %Equal.sym(+List<Rendered.Violation>, Rendered.bounded_dialog(key, found, viewport), Spec.bounded_dialog(key, found, viewport), bounded_dialog(key, found, viewport)) :
        {_ == Spec.bounded_dialog(key, found, viewport) : +List<Rendered.Violation>}
      {==}
    case SurfaceTypes.DialogActions{}:
      %Equal.sym(+List<Rendered.Violation>, Rendered.bounded_dialog(key, found, viewport), Spec.bounded_dialog(key, found, viewport), bounded_dialog(key, found, viewport)) :
        {_ == Spec.bounded_dialog(key, found, viewport) : +List<Rendered.Violation>}
      {==}
    case SurfaceTypes.Toolbar{}:
      %Equal.sym(+List<Rendered.Violation>, Rendered.reachable_toolbar(key, found), Spec.reachable_toolbar(key, found), reachable_toolbar(key, found)) :
        {_ == Spec.reachable_toolbar(key, found) : +List<Rendered.Violation>}
      {==}
    case SurfaceTypes.ApprovalQueue{}:
      %Equal.sym(+List<Rendered.Violation>, Rendered.bounded_dialog(key, found, viewport), Spec.bounded_dialog(key, found, viewport), bounded_dialog(key, found, viewport)) :
        {_ == Spec.bounded_dialog(key, found, viewport) : +List<Rendered.Violation>}
      {==}
    case SurfaceTypes.Heading{}: dialog_geometry(SurfaceTypes.Heading{}, key, found, viewport)
    case SurfaceTypes.PrimaryButton{}: dialog_geometry(SurfaceTypes.PrimaryButton{}, key, found, viewport)
    case SurfaceTypes.DestructiveButton{}: dialog_geometry(SurfaceTypes.DestructiveButton{}, key, found, viewport)
    case SurfaceTypes.SelectedButton{}: dialog_geometry(SurfaceTypes.SelectedButton{}, key, found, viewport)
    case SurfaceTypes.ComposerActions{}: dialog_geometry(SurfaceTypes.ComposerActions{}, key, found, viewport)
    case SurfaceTypes.Timeline{}: dialog_geometry(SurfaceTypes.Timeline{}, key, found, viewport)
    case SurfaceTypes.Activity{}: dialog_geometry(SurfaceTypes.Activity{}, key, found, viewport)
    case SurfaceTypes.UserMessage{}: dialog_geometry(SurfaceTypes.UserMessage{}, key, found, viewport)
    case SurfaceTypes.AssistantMessage{}: dialog_geometry(SurfaceTypes.AssistantMessage{}, key, found, viewport)
    case SurfaceTypes.Approval{}: dialog_geometry(SurfaceTypes.Approval{}, key, found, viewport)
    case SurfaceTypes.CodeBlock{}: dialog_geometry(SurfaceTypes.CodeBlock{}, key, found, viewport)
    case SurfaceTypes.Section{}: dialog_geometry(SurfaceTypes.Section{}, key, found, viewport)
    case SurfaceTypes.Dialog{}: dialog_geometry(SurfaceTypes.Dialog{}, key, found, viewport)
    case SurfaceTypes.Menu{}: dialog_geometry(SurfaceTypes.Menu{}, key, found, viewport)
    case SurfaceTypes.Details{}: dialog_geometry(SurfaceTypes.Details{}, key, found, viewport)
    case SurfaceTypes.Card{}: dialog_geometry(SurfaceTypes.Card{}, key, found, viewport)
    case SurfaceTypes.Button{}: dialog_geometry(SurfaceTypes.Button{}, key, found, viewport)
    case SurfaceTypes.Field{}: dialog_geometry(SurfaceTypes.Field{}, key, found, viewport)
    case SurfaceTypes.Content{}: dialog_geometry(SurfaceTypes.Content{}, key, found, viewport)
    case SurfaceTypes.Alert{}: dialog_geometry(SurfaceTypes.Alert{}, key, found, viewport)

def overlaps(+first: Geometry.Rect, +second: Geometry.Rect) ->
  {Rendered.overlaps(first, second) == Spec.overlaps(first, second) : Bool}:
  Geometry.Rect{+left, +top, +right, +bottom} = first
  Geometry.Rect{+other_left, +other_top, +other_right, +other_bottom} = second
  {==}

def code_in_view(+role: SurfaceTypes.Role, +found: Maybe<&2, Rendered.Element>, +viewport: Geometry.Rect) ->
  {Rendered.code_in_view(role, found, viewport) == Spec.code_in_view(role, found, viewport) : Bool}:
  match role found:
    case SurfaceTypes.CodeBlock{} Some{Rendered.Element{+key, +visible, +enabled, +tab, +keyboard, +scroll, +bounds, +hit, +paint_bounds}}:
      %Equal.sym(Bool, Rendered.overlaps(paint_bounds, viewport), Spec.overlaps(paint_bounds, viewport), overlaps(paint_bounds, viewport)) :
        {visible && _ == visible && Spec.overlaps(paint_bounds, viewport) : Bool}
      {==}
    case SurfaceTypes.CodeBlock{} None{}: {==}
    case SurfaceTypes.GlobalNavigation{compact} _: {==}
    case SurfaceTypes.GlobalNavigationEntry{selected, compact} _: {==}
    case SurfaceTypes.CompactHeader{} _: {==}
    case SurfaceTypes.CompactWorkScope{title, count} _: {==}
    case SurfaceTypes.CompactNavigationMenu{} _: {==}
    case SurfaceTypes.CompactNavigationEntry{selected} _: {==}
    case SurfaceTypes.WorkTabs{} _: {==}
    case SurfaceTypes.WorkTab{selected} _: {==}
    case SurfaceTypes.WorkTabGroup{} _: {==}
    case SurfaceTypes.WorkOverviewButton{count} _: {==}
    case SurfaceTypes.WorkChoiceRow{} _: {==}
    case SurfaceTypes.Navigation{} _: {==}
    case SurfaceTypes.NavigationHeader{} _: {==}
    case SurfaceTypes.NavigationEntry{selected} _: {==}
    case SurfaceTypes.NavigationCollection{} _: {==}
    case SurfaceTypes.NavigationSection{} _: {==}
    case SurfaceTypes.Main{} _: {==}
    case SurfaceTypes.Heading{} _: {==}
    case SurfaceTypes.PrimaryButton{} _: {==}
    case SurfaceTypes.DestructiveButton{} _: {==}
    case SurfaceTypes.SelectedButton{} _: {==}
    case SurfaceTypes.ComposerActions{} _: {==}
    case SurfaceTypes.DialogActions{} _: {==}
    case SurfaceTypes.Timeline{} _: {==}
    case SurfaceTypes.Activity{} _: {==}
    case SurfaceTypes.UserMessage{} _: {==}
    case SurfaceTypes.AssistantMessage{} _: {==}
    case SurfaceTypes.Composer{} _: {==}
    case SurfaceTypes.Approval{} _: {==}
    case SurfaceTypes.Toolbar{} _: {==}
    case SurfaceTypes.ApprovalQueue{} _: {==}
    case SurfaceTypes.Section{} _: {==}
    case SurfaceTypes.Dialog{} _: {==}
    case SurfaceTypes.Menu{} _: {==}
    case SurfaceTypes.Details{} _: {==}
    case SurfaceTypes.Card{} _: {==}
    case SurfaceTypes.Button{} _: {==}
    case SurfaceTypes.Field{} _: {==}
    case SurfaceTypes.Content{} _: {==}
    case SurfaceTypes.Alert{} _: {==}

def node_geometry_with(+found: Maybe<&2, Rendered.Element>, +meaning: SurfaceTypes.Meaning, +role: SurfaceTypes.Role, +key: String, +persistent: Bool, +viewport: Geometry.Rect, +controls: +List<Rendered.ControlExposure>) ->
  {Rendered.node_geometry_with(found, meaning, role, key, persistent, viewport, controls) == Spec.node_geometry_with(found, meaning, role, key, persistent, viewport, controls) : +List<Rendered.Violation>}:
  match found:
    case None{}:
      {==}
    case Some{+element}:
      %Equal.sym(Bool, Rendered.interactive(meaning), Spec.interactive(meaning), interactive(meaning)) :
        {List.append(&2, Rendered.Violation, Rendered.node_controls_with(_, meaning, key, Some{element}, persistent, viewport, controls), Rendered.region_geometry(role, key, Some{element}, viewport)) == List.append(&2, Rendered.Violation, Spec.node_controls_with(Spec.interactive(meaning), meaning, key, Some{element}, persistent, viewport, controls), Spec.region_geometry(role, key, Some{element}, viewport)) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Rendered.region_geometry(role, key, Some{element}, viewport), Spec.region_geometry(role, key, Some{element}, viewport), region_geometry(role, key, Some{element}, viewport)) :
        {List.append(&2, Rendered.Violation, Rendered.node_controls_with(Spec.interactive(meaning), meaning, key, Some{element}, persistent, viewport, controls), _) == List.append(&2, Rendered.Violation, Spec.node_controls_with(Spec.interactive(meaning), meaning, key, Some{element}, persistent, viewport, controls), Spec.region_geometry(role, key, Some{element}, viewport)) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Rendered.node_controls_with(Spec.interactive(meaning), meaning, key, Some{element}, persistent, viewport, controls), Spec.node_controls_with(Spec.interactive(meaning), meaning, key, Some{element}, persistent, viewport, controls), node_controls_with(Spec.interactive(meaning), meaning, key, Some{element}, persistent, viewport, controls)) :
        {List.append(&2, Rendered.Violation, _, Spec.region_geometry(role, key, Some{element}, viewport)) == List.append(&2, Rendered.Violation, Spec.node_controls_with(Spec.interactive(meaning), meaning, key, Some{element}, persistent, viewport, controls), Spec.region_geometry(role, key, Some{element}, viewport)) : +List<Rendered.Violation>}
      {==}


def tab_entry(+included: Bool, +key: String, +rest: +List<String>) ->
  {Rendered.tab_entry(included, key, rest) == Spec.tab_entry(included, key, rest) : +List<String>}:
  match included:
    case True{}:
      {==}
    case False{}:
      {==}

def native_member(+entries: +List<Rendered.NativeFocus>, +identity: String) ->
  {Rendered.native_member(entries, identity) == Spec.native_member(entries, identity) : Bool}:
  match entries:
    case Nil{}:
      {==}
    case Con{Rendered.NativeFocus{+key, +owner}, +rest}:
      %Equal.sym(Bool, SafeText.string_equal(key, identity), String.eq(key, identity), TextProof.public_refines(key, identity)) :
        {_ || Rendered.native_member(rest, identity) == String.eq(key, identity) || Spec.native_member(rest, identity) : Bool}
      %Equal.sym(Bool, Rendered.native_member(rest, identity), Spec.native_member(rest, identity), native_member(rest, identity)) :
        {String.eq(key, identity) || _ == String.eq(key, identity) || Spec.native_member(rest, identity) : Bool}
      {==}

def read_only(+found: Maybe<&2, SurfaceTypes.Node>) ->
  {Rendered.read_only(found) == Spec.read_only(found) : Bool}:
  match found:
    case None{}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{identity, occurrence, +tag, attrs, binding, original}}, children}}:
      TextProof.public_refines(tag, "markdown")
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.SettingEntry{meaning_subject, meaning_value, meaning_input, meaning_availability}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ActivityRow{meaning_role}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ActivityGroup{meaning_activity, meaning_dismiss, meaning_outside, meaning_escape}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.DecisionGroup{meaning_decision}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.WorkspaceCollection{meaning_collection}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.WorkspaceMember{meaning_collection, meaning_path}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ActionUnit{meaning_action}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ActionFeedback{meaning_feedback}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ActionExplanation{meaning_assessment}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ActionCommit{meaning_assessment, meaning_input, meaning_availability}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ObjectGroup{meaning_object}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.SupportingControl{meaning_support, meaning_property, meaning_input, meaning_availability}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.InformationText{meaning_role}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.LayerRegion{meaning_dismiss, meaning_outside, meaning_escape}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.DirectoryBrowserLocation{meaning_value}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.PanelToggle{meaning_expanded, meaning_input, meaning_availability}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.CardContent{meaning_face}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.MovableCard{meaning_destinations, meaning_face}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.Region{}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.PageContext{meaning_conversation}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ActivityContent{meaning_expanded, meaning_audit}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ProjectGroup{meaning_project, meaning_selected, meaning_expanded}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.TaskRow{meaning_task, meaning_status, meaning_selected}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.TaskChildren{meaning_task}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ProjectChooser{meaning_selected}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.DirectoryRow{meaning_path, meaning_primary}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ContextSummary{meaning_observation}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ChoiceGroup{}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.Choice{meaning_kind, meaning_classification, meaning_selected, meaning_description, meaning_input, meaning_availability}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.PageRegion{meaning_region, meaning_position}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.BoardLane{meaning_stage, meaning_count}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.CardArchive{meaning_count}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.BoardSearch{meaning_filter}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.BoardGroup{meaning_grouping}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ReadOnly{meaning_text}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.Fact{meaning_value}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.RichText{meaning_source, meaning_value}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.TaskFacts{meaning_details}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.CodeFacts{meaning_view}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.InteractiveRegion{meaning_identity, meaning_source_visible}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.InteractiveView{meaning_event, meaning_command, meaning_label, meaning_enabled}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.Activate{meaning_input, meaning_availability}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.Edit{meaning_editor, meaning_field, meaning_entry, meaning_value, meaning_choices}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.SearchChoices{meaning_query}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ReceiveFile{meaning_editor, meaning_enabled}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.EnterDirectory{meaning_editor, meaning_text}, children}}: {==}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.BoardProfile{meaning_automatic, meaning_selected, meaning_choices, meaning_enabled}, children}}: {==}

def native_element(+found: Maybe<&2, Rendered.Element>) ->
  {Rendered.native_element(found) == Spec.native_element(found) : Bool}:
  match found:
    case Some{Rendered.Element{+key, +visible, +enabled, +tab, +keyboard, +scroll, +bounds, +hit, +paint_bounds}}:
      {==}
    case None{}:
      {==}

def exists(+found: Maybe<&2, SurfaceTypes.Node>) ->
  {Rendered.exists(found) == Spec.exists(found) : Bool}:
  match found:
    case None{}:
      {==}
    case Some{+node}:
      {==}

def native_valid(+entries: +List<Rendered.NativeFocus>, +active: +List<SurfaceTypes.Node>, +elements: +List<Rendered.Element>) ->
  {Rendered.native_valid(entries, active, elements) == Spec.native_valid(entries, active, elements) : Bool}:
  match entries:
    case Nil{}:
      {==}
    case Con{Rendered.NativeFocus{+identity, +owner}, +rest}:
      %Equal.sym(Maybe<&2, SurfaceTypes.Node>, InterfaceView.find_node(active, owner), Spec.find_node(active, owner), FenceEvidence.complete_node_lookup(active, owner)) :
        {Rendered.read_only(_) && Bool.not(Rendered.exists(InterfaceView.find_node(active, identity))) && Rendered.native_element(Rendered.find_element(elements, identity)) && Bool.not(Rendered.native_member(rest, identity)) && Rendered.native_valid(rest, active, elements) == Spec.read_only(Spec.find_node(active, owner)) && Bool.not(Spec.exists(Spec.find_node(active, identity))) && Spec.native_element(Spec.first_observed_element(elements, identity)) && Bool.not(Spec.native_member(rest, identity)) && Spec.native_valid(rest, active, elements) : Bool}
      %Equal.sym(Bool, Rendered.native_member(rest, identity), Spec.native_member(rest, identity), native_member(rest, identity)) :
        {Rendered.read_only(Spec.find_node(active, owner)) && Bool.not(Rendered.exists(InterfaceView.find_node(active, identity))) && Rendered.native_element(Rendered.find_element(elements, identity)) && Bool.not(_) && Rendered.native_valid(rest, active, elements) == Spec.read_only(Spec.find_node(active, owner)) && Bool.not(Spec.exists(Spec.find_node(active, identity))) && Spec.native_element(Spec.first_observed_element(elements, identity)) && Bool.not(Spec.native_member(rest, identity)) && Spec.native_valid(rest, active, elements) : Bool}
      %Equal.sym(Maybe<&2, SurfaceTypes.Node>, InterfaceView.find_node(active, identity), Spec.find_node(active, identity), FenceEvidence.complete_node_lookup(active, identity)) :
        {Rendered.read_only(Spec.find_node(active, owner)) && Bool.not(Rendered.exists(_)) && Rendered.native_element(Rendered.find_element(elements, identity)) && Bool.not(Spec.native_member(rest, identity)) && Rendered.native_valid(rest, active, elements) == Spec.read_only(Spec.find_node(active, owner)) && Bool.not(Spec.exists(Spec.find_node(active, identity))) && Spec.native_element(Spec.first_observed_element(elements, identity)) && Bool.not(Spec.native_member(rest, identity)) && Spec.native_valid(rest, active, elements) : Bool}
      %Equal.sym(Maybe<&2, Rendered.Element>, Rendered.find_element(elements, identity), Spec.first_observed_element(elements, identity), first_observation(elements, identity)) :
        {Rendered.read_only(Spec.find_node(active, owner)) && Bool.not(Rendered.exists(Spec.find_node(active, identity))) && Rendered.native_element(_) && Bool.not(Spec.native_member(rest, identity)) && Rendered.native_valid(rest, active, elements) == Spec.read_only(Spec.find_node(active, owner)) && Bool.not(Spec.exists(Spec.find_node(active, identity))) && Spec.native_element(Spec.first_observed_element(elements, identity)) && Bool.not(Spec.native_member(rest, identity)) && Spec.native_valid(rest, active, elements) : Bool}
      %Equal.sym(Bool, Rendered.native_valid(rest, active, elements), Spec.native_valid(rest, active, elements), native_valid(rest, active, elements)) :
        {Rendered.read_only(Spec.find_node(active, owner)) && Bool.not(Rendered.exists(Spec.find_node(active, identity))) && Rendered.native_element(Spec.first_observed_element(elements, identity)) && Bool.not(Spec.native_member(rest, identity)) && _ == Spec.read_only(Spec.find_node(active, owner)) && Bool.not(Spec.exists(Spec.find_node(active, identity))) && Spec.native_element(Spec.first_observed_element(elements, identity)) && Bool.not(Spec.native_member(rest, identity)) && Spec.native_valid(rest, active, elements) : Bool}
      %Equal.sym(Bool, Rendered.read_only(Spec.find_node(active, owner)), Spec.read_only(Spec.find_node(active, owner)), read_only(Spec.find_node(active, owner))) :
        {_ && Bool.not(Rendered.exists(Spec.find_node(active, identity))) && Rendered.native_element(Spec.first_observed_element(elements, identity)) && Bool.not(Spec.native_member(rest, identity)) && Spec.native_valid(rest, active, elements) == Spec.read_only(Spec.find_node(active, owner)) && Bool.not(Spec.exists(Spec.find_node(active, identity))) && Spec.native_element(Spec.first_observed_element(elements, identity)) && Bool.not(Spec.native_member(rest, identity)) && Spec.native_valid(rest, active, elements) : Bool}
      %Equal.sym(Bool, Rendered.exists(Spec.find_node(active, identity)), Spec.exists(Spec.find_node(active, identity)), exists(Spec.find_node(active, identity))) :
        {Spec.read_only(Spec.find_node(active, owner)) && Bool.not(_) && Rendered.native_element(Spec.first_observed_element(elements, identity)) && Bool.not(Spec.native_member(rest, identity)) && Spec.native_valid(rest, active, elements) == Spec.read_only(Spec.find_node(active, owner)) && Bool.not(Spec.exists(Spec.find_node(active, identity))) && Spec.native_element(Spec.first_observed_element(elements, identity)) && Bool.not(Spec.native_member(rest, identity)) && Spec.native_valid(rest, active, elements) : Bool}
      %Equal.sym(Bool, Rendered.native_element(Spec.first_observed_element(elements, identity)), Spec.native_element(Spec.first_observed_element(elements, identity)), native_element(Spec.first_observed_element(elements, identity))) :
        {Spec.read_only(Spec.find_node(active, owner)) && Bool.not(Spec.exists(Spec.find_node(active, identity))) && _ && Bool.not(Spec.native_member(rest, identity)) && Spec.native_valid(rest, active, elements) == Spec.read_only(Spec.find_node(active, owner)) && Bool.not(Spec.exists(Spec.find_node(active, identity))) && Spec.native_element(Spec.first_observed_element(elements, identity)) && Bool.not(Spec.native_member(rest, identity)) && Spec.native_valid(rest, active, elements) : Bool}
      {==}

def native_owned(+entries: +List<Rendered.NativeFocus>, +active: +List<SurfaceTypes.Node>, +elements: +List<Rendered.Element>, +key: String) ->
  {Rendered.native_owned(entries, active, elements, key) == Spec.native_owned(entries, active, elements, key) : Bool}:
  %Equal.sym(Bool, Rendered.native_member(entries, key), Spec.native_member(entries, key), native_member(entries, key)) :
    {Rendered.native_valid(entries, active, elements) && _ == Spec.native_valid(entries, active, elements) && Spec.native_member(entries, key) : Bool}
  %Equal.sym(Bool, Rendered.native_valid(entries, active, elements), Spec.native_valid(entries, active, elements), native_valid(entries, active, elements)) :
    {_ && Spec.native_member(entries, key) == Spec.native_valid(entries, active, elements) && Spec.native_member(entries, key) : Bool}
  {==}

def owner_tabs(+entries: +List<Rendered.NativeFocus>, +owner: String) ->
  {Rendered.owner_tabs(entries, owner) == Spec.owner_tabs(entries, owner) : +List<String>}:
  match entries:
    case Nil{}:
      {==}
    case Con{Rendered.NativeFocus{+identity, +parent}, +rest}:
      %Equal.sym(+List<String>, Rendered.owner_tabs(rest, owner), Spec.owner_tabs(rest, owner), owner_tabs(rest, owner)) :
        {Rendered.tab_entry(SafeText.string_equal(parent, owner), identity, _) == Spec.tab_entry(String.eq(parent, owner), identity, Spec.owner_tabs(rest, owner)) : +List<String>}
      %Equal.sym(Bool, SafeText.string_equal(parent, owner), String.eq(parent, owner), TextProof.public_refines(parent, owner)) :
        {Rendered.tab_entry(_, identity, Spec.owner_tabs(rest, owner)) == Spec.tab_entry(String.eq(parent, owner), identity, Spec.owner_tabs(rest, owner)) : +List<String>}
      %Equal.sym(+List<String>, Rendered.tab_entry(String.eq(parent, owner), identity, Spec.owner_tabs(rest, owner)), Spec.tab_entry(String.eq(parent, owner), identity, Spec.owner_tabs(rest, owner)), tab_entry(String.eq(parent, owner), identity, Spec.owner_tabs(rest, owner))) :
        {_ == Spec.tab_entry(String.eq(parent, owner), identity, Spec.owner_tabs(rest, owner)) : +List<String>}
      {==}

def content_tabs_admitted(+admitted: Bool, +entries: +List<Rendered.NativeFocus>, +key: String) ->
  {Rendered.content_tabs_admitted(admitted, entries, key) == Bool.pick((+List<String>), admitted, Spec.owner_tabs(entries, key), Nil{}) : +List<String>}:
  match admitted:
    case False{}: {==}
    case True{}: owner_tabs(entries, key)

def content_tabs(+meaning: SurfaceTypes.Meaning, +entries: +List<Rendered.NativeFocus>, +key: String) ->
  {Rendered.content_tabs(meaning, entries, key) == Spec.content_tabs(meaning, entries, key) : +List<String>}:
  match meaning:
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{identity, occurrence, +tag, attrs, binding, children}}:
      %Equal.sym(Bool, SafeText.string_equal(tag, "markdown"), String.eq(tag, "markdown"), TextProof.public_refines(tag, "markdown")) :
        {Rendered.content_tabs_admitted(_, entries, key) == Bool.pick((+List<String>), String.eq(tag, "markdown"), Spec.owner_tabs(entries, key), Nil{}) : +List<String>}
      content_tabs_admitted(String.eq(tag, "markdown"), entries, key)
    case SurfaceTypes.InformationText{+role}:
      %Equal.sym(+List<String>, Rendered.owner_tabs(entries, key), Spec.owner_tabs(entries, key), owner_tabs(entries, key)) :
        {_ == Spec.owner_tabs(entries, key) : +List<String>}
      {==}
    case SurfaceTypes.ReadOnly{+text}:
      %Equal.sym(+List<String>, Rendered.owner_tabs(entries, key), Spec.owner_tabs(entries, key), owner_tabs(entries, key)) :
        {_ == Spec.owner_tabs(entries, key) : +List<String>}
      {==}
    case SurfaceTypes.RichText{+source, +value}:
      %Equal.sym(+List<String>, Rendered.owner_tabs(entries, key), Spec.owner_tabs(entries, key), owner_tabs(entries, key)) :
        {_ == Spec.owner_tabs(entries, key) : +List<String>}
      {==}
    case SurfaceTypes.SettingEntry{meaning_subject, meaning_value, meaning_input, meaning_availability}: {==}
    case SurfaceTypes.ActivityRow{meaning_role}: {==}
    case SurfaceTypes.ActivityGroup{meaning_activity, meaning_dismiss, meaning_outside, meaning_escape}: {==}
    case SurfaceTypes.DecisionGroup{meaning_decision}: {==}
    case SurfaceTypes.WorkspaceCollection{meaning_collection}: {==}
    case SurfaceTypes.WorkspaceMember{meaning_collection, meaning_path}: {==}
    case SurfaceTypes.ActionUnit{meaning_action}: {==}
    case SurfaceTypes.ActionFeedback{meaning_feedback}: {==}
    case SurfaceTypes.ActionExplanation{meaning_assessment}: {==}
    case SurfaceTypes.ActionCommit{meaning_assessment, meaning_input, meaning_availability}: {==}
    case SurfaceTypes.ObjectGroup{meaning_object}: {==}
    case SurfaceTypes.SupportingControl{meaning_support, meaning_property, meaning_input, meaning_availability}: {==}
    case SurfaceTypes.LayerRegion{meaning_dismiss, meaning_outside, meaning_escape}: {==}
    case SurfaceTypes.DirectoryBrowserLocation{meaning_value}: {==}
    case SurfaceTypes.PanelToggle{meaning_expanded, meaning_input, meaning_availability}: {==}
    case SurfaceTypes.CardContent{meaning_face}: {==}
    case SurfaceTypes.MovableCard{meaning_destinations, meaning_face}: {==}
    case SurfaceTypes.Region{}: {==}
    case SurfaceTypes.PageContext{meaning_conversation}: {==}
    case SurfaceTypes.ActivityContent{meaning_expanded, meaning_audit}: {==}
    case SurfaceTypes.ProjectGroup{meaning_project, meaning_selected, meaning_expanded}: {==}
    case SurfaceTypes.TaskRow{meaning_task, meaning_status, meaning_selected}: {==}
    case SurfaceTypes.TaskChildren{meaning_task}: {==}
    case SurfaceTypes.ProjectChooser{meaning_selected}: {==}
    case SurfaceTypes.DirectoryRow{meaning_path, meaning_primary}: {==}
    case SurfaceTypes.ContextSummary{meaning_observation}: {==}
    case SurfaceTypes.ChoiceGroup{}: {==}
    case SurfaceTypes.Choice{meaning_kind, meaning_classification, meaning_selected, meaning_description, meaning_input, meaning_availability}: {==}
    case SurfaceTypes.PageRegion{meaning_region, meaning_position}: {==}
    case SurfaceTypes.BoardLane{meaning_stage, meaning_count}: {==}
    case SurfaceTypes.CardArchive{meaning_count}: {==}
    case SurfaceTypes.BoardSearch{meaning_filter}: {==}
    case SurfaceTypes.BoardGroup{meaning_grouping}: {==}
    case SurfaceTypes.Fact{meaning_value}: {==}
    case SurfaceTypes.TaskFacts{meaning_details}: {==}
    case SurfaceTypes.CodeFacts{meaning_view}: {==}
    case SurfaceTypes.InteractiveRegion{meaning_identity, meaning_source_visible}: {==}
    case SurfaceTypes.InteractiveView{meaning_event, meaning_command, meaning_label, meaning_enabled}: {==}
    case SurfaceTypes.Activate{meaning_input, meaning_availability}: {==}
    case SurfaceTypes.Edit{meaning_editor, meaning_field, meaning_entry, meaning_value, meaning_choices}: {==}
    case SurfaceTypes.SearchChoices{meaning_query}: {==}
    case SurfaceTypes.ReceiveFile{meaning_editor, meaning_enabled}: {==}
    case SurfaceTypes.EnterDirectory{meaning_editor, meaning_text}: {==}
    case SurfaceTypes.BoardProfile{meaning_automatic, meaning_selected, meaning_choices, meaning_enabled}: {==}

def same_order(+expected: +List<String>, +actual: +List<String>) ->
  {Rendered.same_order(expected, actual) == Spec.same_order(expected, actual) : Bool}:
  match expected actual:
    case Nil{} Nil{}:
      {==}
    case Con{+left, +ls} Con{+right, +rs}:
      %Equal.sym(Bool, Rendered.same_order(ls, rs), Spec.same_order(ls, rs), same_order(ls, rs)) :
        {SafeText.string_equal(left, right) && _ == String.eq(left, right) && Spec.same_order(ls, rs) : Bool}
      %Equal.sym(Bool, SafeText.string_equal(left, right), String.eq(left, right), TextProof.public_refines(left, right)) :
        {_ && Spec.same_order(ls, rs) == String.eq(left, right) && Spec.same_order(ls, rs) : Bool}
      {==}
    case Nil{} Con{right, rest}: {==}
    case Con{left, rest} Nil{}: {==}

def focus_visible(+found: Maybe<&2, Rendered.Element>, +viewport: Geometry.Rect) ->
  {Rendered.focus_visible(found, viewport) == Spec.focus_visible(found, viewport) : Bool}:
  match found:
    case None{}:
      {==}
    case Some{Rendered.Element{+key, +visible, +enabled, +tab, +keyboard, +scroll, +bounds, +hit, +paint_bounds}}:
      {==}

def focus_owned(+nodes: +List<SurfaceTypes.Node>, +elements: +List<Rendered.Element>, +native_focus: +List<Rendered.NativeFocus>, +key: String) ->
  {Rendered.focus_owned(nodes, elements, native_focus, key) == Spec.focus_owned(nodes, elements, native_focus, key) : Bool}:
  %Equal.sym(Maybe<&2, SurfaceTypes.Node>, InterfaceView.find_node(nodes, key), Spec.find_node(nodes, key), FenceEvidence.complete_node_lookup(nodes, key)) :
    {Rendered.exists(_) || Rendered.native_owned(native_focus, nodes, elements, key) == Spec.exists(Spec.find_node(nodes, key)) || Spec.native_owned(native_focus, nodes, elements, key) : Bool}
  %Equal.sym(Bool, Rendered.exists(Spec.find_node(nodes, key)), Spec.exists(Spec.find_node(nodes, key)), exists(Spec.find_node(nodes, key))) :
    {_ || Rendered.native_owned(native_focus, nodes, elements, key) == Spec.exists(Spec.find_node(nodes, key)) || Spec.native_owned(native_focus, nodes, elements, key) : Bool}
  %Equal.sym(Bool, Rendered.native_owned(native_focus, nodes, elements, key), Spec.native_owned(native_focus, nodes, elements, key), native_owned(native_focus, nodes, elements, key)) :
    {Spec.exists(Spec.find_node(nodes, key)) || _ == Spec.exists(Spec.find_node(nodes, key)) || Spec.native_owned(native_focus, nodes, elements, key) : Bool}
  {==}

def focus_checks(+focus: Maybe<&2, String>, +nodes: +List<SurfaceTypes.Node>, +elements: +List<Rendered.Element>, +viewport: Geometry.Rect, +native_focus: +List<Rendered.NativeFocus>) ->
  {Rendered.focus_checks(focus, nodes, elements, viewport, native_focus) == Spec.focus_checks(focus, nodes, elements, viewport, native_focus) : +List<Rendered.Violation>}:
  match focus:
    case None{}:
      {==}
    case Some{+key}:
      %Equal.sym(Maybe<&2, Rendered.Element>, Rendered.find_element(elements, key), Spec.first_observed_element(elements, key), first_observation(elements, key)) :
        {List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Rendered.focus_visible(_, viewport)), Rendered.InvisibleFocus{}), Rendered.issue(Bool.not(Rendered.focus_owned(nodes, elements, native_focus, key)), Rendered.FocusOutsideScope{})) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.focus_visible(Spec.first_observed_element(elements, key), viewport)), Rendered.InvisibleFocus{}), Spec.issue(Bool.not(Spec.focus_owned(nodes, elements, native_focus, key)), Rendered.FocusOutsideScope{})) : +List<Rendered.Violation>}
      %Equal.sym(Bool, Rendered.focus_owned(nodes, elements, native_focus, key), Spec.focus_owned(nodes, elements, native_focus, key), focus_owned(nodes, elements, native_focus, key)) :
        {List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Rendered.focus_visible(Spec.first_observed_element(elements, key), viewport)), Rendered.InvisibleFocus{}), Rendered.issue(Bool.not(_), Rendered.FocusOutsideScope{})) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.focus_visible(Spec.first_observed_element(elements, key), viewport)), Rendered.InvisibleFocus{}), Spec.issue(Bool.not(Spec.focus_owned(nodes, elements, native_focus, key)), Rendered.FocusOutsideScope{})) : +List<Rendered.Violation>}
      %Equal.sym(Bool, Rendered.focus_visible(Spec.first_observed_element(elements, key), viewport), Spec.focus_visible(Spec.first_observed_element(elements, key), viewport), focus_visible(Spec.first_observed_element(elements, key), viewport)) :
        {List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(_), Rendered.InvisibleFocus{}), Rendered.issue(Bool.not(Spec.focus_owned(nodes, elements, native_focus, key)), Rendered.FocusOutsideScope{})) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.focus_visible(Spec.first_observed_element(elements, key), viewport)), Rendered.InvisibleFocus{}), Spec.issue(Bool.not(Spec.focus_owned(nodes, elements, native_focus, key)), Rendered.FocusOutsideScope{})) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Rendered.issue(Bool.not(Spec.focus_owned(nodes, elements, native_focus, key)), Rendered.FocusOutsideScope{}), Spec.issue(Bool.not(Spec.focus_owned(nodes, elements, native_focus, key)), Rendered.FocusOutsideScope{}), issue(Bool.not(Spec.focus_owned(nodes, elements, native_focus, key)), Rendered.FocusOutsideScope{})) :
        {List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Spec.focus_visible(Spec.first_observed_element(elements, key), viewport)), Rendered.InvisibleFocus{}), _) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.focus_visible(Spec.first_observed_element(elements, key), viewport)), Rendered.InvisibleFocus{}), Spec.issue(Bool.not(Spec.focus_owned(nodes, elements, native_focus, key)), Rendered.FocusOutsideScope{})) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Rendered.issue(Bool.not(Spec.focus_visible(Spec.first_observed_element(elements, key), viewport)), Rendered.InvisibleFocus{}), Spec.issue(Bool.not(Spec.focus_visible(Spec.first_observed_element(elements, key), viewport)), Rendered.InvisibleFocus{}), issue(Bool.not(Spec.focus_visible(Spec.first_observed_element(elements, key), viewport)), Rendered.InvisibleFocus{})) :
        {List.append(&2, Rendered.Violation, _, Spec.issue(Bool.not(Spec.focus_owned(nodes, elements, native_focus, key)), Rendered.FocusOutsideScope{})) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.focus_visible(Spec.first_observed_element(elements, key), viewport)), Rendered.InvisibleFocus{}), Spec.issue(Bool.not(Spec.focus_owned(nodes, elements, native_focus, key)), Rendered.FocusOutsideScope{})) : +List<Rendered.Violation>}
      {==}

def required_focus(+scope: Maybe<&2, String>, +focused: Maybe<&2, String>) ->
  {Rendered.required_focus(scope, focused) == Spec.required_focus(scope, focused) : +List<Rendered.Violation>}:
  match scope:
    case None{}:
      {==}
    case Some{+scope}:
      match focused:
        case None{}:
          {==}
        case Some{+key}:
          {==}

def include_element(+included: Bool, +found: Maybe<&2, Rendered.Element>, +rest: +List<Rendered.Element>) ->
  {Rendered.include_element(included, found, rest) == Spec.include_element(included, found, rest) : +List<Rendered.Element>}:
  match included found:
    case True{} Some{Rendered.Element{+key, True{}, +enabled, +tab, +keyboard, +scroll, +bounds, +hit, +paint_bounds}}:
      {==}
    case False{} _: {==}
    case True{} None{}: {==}
    case True{} Some{Rendered.Element{key, False{}, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds}}: {==}

def against(+first: Rendered.Element, +rest: +List<Rendered.Element>) ->
  {Rendered.against(first, rest) == Spec.against(first, rest) : +List<Rendered.Violation>}:
  Rendered.Element{+key, +visible, +enabled, +tab, +keyboard, +scroll, +bounds, +hit, +paint_bounds} = first
  match rest:
    case Nil{}:
      {==}
    case Con{Rendered.Element{+other, +v, +e, +t, +k, +s, +other_bounds, +h, +other_paint_bounds}, +tail}:
      %Equal.sym(Bool, Rendered.overlaps(paint_bounds, other_paint_bounds), Spec.overlaps(paint_bounds, other_paint_bounds), overlaps(paint_bounds, other_paint_bounds)) :
        {List.append(&2, Rendered.Violation, Rendered.issue(_, Rendered.OverlappingControls{key, other}), Rendered.against(Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds}, tail)) == List.append(&2, Rendered.Violation, Spec.issue(Spec.overlaps(paint_bounds, other_paint_bounds), Rendered.OverlappingControls{key, other}), Spec.against(Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds}, tail)) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Rendered.issue(Spec.overlaps(paint_bounds, other_paint_bounds), Rendered.OverlappingControls{key, other}), Spec.issue(Spec.overlaps(paint_bounds, other_paint_bounds), Rendered.OverlappingControls{key, other}), issue(Spec.overlaps(paint_bounds, other_paint_bounds), Rendered.OverlappingControls{key, other})) :
        {List.append(&2, Rendered.Violation, _, Rendered.against(Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds}, tail)) == List.append(&2, Rendered.Violation, Spec.issue(Spec.overlaps(paint_bounds, other_paint_bounds), Rendered.OverlappingControls{key, other}), Spec.against(Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds}, tail)) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Rendered.against(Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds}, tail), Spec.against(Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds}, tail), against(Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds}, tail)) :
        {List.append(&2, Rendered.Violation, Spec.issue(Spec.overlaps(paint_bounds, other_paint_bounds), Rendered.OverlappingControls{key, other}), _) == List.append(&2, Rendered.Violation, Spec.issue(Spec.overlaps(paint_bounds, other_paint_bounds), Rendered.OverlappingControls{key, other}), Spec.against(Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds}, tail)) : +List<Rendered.Violation>}
      {==}

def independent_targets(+elements: +List<Rendered.Element>) ->
  {Rendered.independent_targets(elements) == Spec.independent_targets(elements) : +List<Rendered.Violation>}:
  match elements:
    case Nil{}:
      {==}
    case Con{+first, +rest}:
      %Equal.sym(+List<Rendered.Violation>, Rendered.against(first, rest), Spec.against(first, rest), against(first, rest)) :
        {List.append(&2, Rendered.Violation, _, Rendered.independent_targets(rest)) == List.append(&2, Rendered.Violation, Spec.against(first, rest), Spec.independent_targets(rest)) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Rendered.independent_targets(rest), Spec.independent_targets(rest), independent_targets(rest)) :
        {List.append(&2, Rendered.Violation, Spec.against(first, rest), _) == List.append(&2, Rendered.Violation, Spec.against(first, rest), Spec.independent_targets(rest)) : +List<Rendered.Violation>}
      {==}

def paint_geometry_valid(+visible: Bool, +bounds: Geometry.Rect, +paint_bounds: Geometry.Rect, +viewport: Geometry.Rect) ->
  {Rendered.paint_geometry_valid(visible, bounds, paint_bounds, viewport) == Spec.paint_geometry_valid(visible, bounds, paint_bounds, viewport) : Bool}:
  match visible:
    case False{}:
      {==}
    case True{}:
      {==}

def paint_geometry(+elements: +List<Rendered.Element>, +viewport: Geometry.Rect) ->
  {Rendered.paint_geometry(elements, viewport) == Spec.paint_geometry(elements, viewport) : +List<Rendered.Violation>}:
  match elements:
    case Nil{}:
      {==}
    case Con{Rendered.Element{+key, +visible, +enabled, +tab, +keyboard, +scroll, +bounds, +hit, +paint_bounds}, +rest}:
      %Equal.sym(+List<Rendered.Violation>, Rendered.paint_geometry(rest, viewport), Spec.paint_geometry(rest, viewport), paint_geometry(rest, viewport)) :
        {List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Rendered.paint_geometry_valid(visible, bounds, paint_bounds, viewport)), Rendered.InvalidPaintGeometry{key}), _) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.paint_geometry_valid(visible, bounds, paint_bounds, viewport)), Rendered.InvalidPaintGeometry{key}), Spec.paint_geometry(rest, viewport)) : +List<Rendered.Violation>}
      %Equal.sym(Bool, Rendered.paint_geometry_valid(visible, bounds, paint_bounds, viewport), Spec.paint_geometry_valid(visible, bounds, paint_bounds, viewport), paint_geometry_valid(visible, bounds, paint_bounds, viewport)) :
        {List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(_), Rendered.InvalidPaintGeometry{key}), Spec.paint_geometry(rest, viewport)) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.paint_geometry_valid(visible, bounds, paint_bounds, viewport)), Rendered.InvalidPaintGeometry{key}), Spec.paint_geometry(rest, viewport)) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Rendered.issue(Bool.not(Spec.paint_geometry_valid(visible, bounds, paint_bounds, viewport)), Rendered.InvalidPaintGeometry{key}), Spec.issue(Bool.not(Spec.paint_geometry_valid(visible, bounds, paint_bounds, viewport)), Rendered.InvalidPaintGeometry{key}), issue(Bool.not(Spec.paint_geometry_valid(visible, bounds, paint_bounds, viewport)), Rendered.InvalidPaintGeometry{key})) :
        {List.append(&2, Rendered.Violation, _, Spec.paint_geometry(rest, viewport)) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.paint_geometry_valid(visible, bounds, paint_bounds, viewport)), Rendered.InvalidPaintGeometry{key}), Spec.paint_geometry(rest, viewport)) : +List<Rendered.Violation>}
      {==}

def enabled_expectation(+expected: Maybe<&2, Bool>, +actual: Bool) ->
  {Rendered.enabled_expectation(expected, actual) == Spec.enabled_expectation(expected, actual) : Bool}:
  match expected:
    case None{}:
      {==}
    case Some{+value}:
      {==}

def source_concealment(+exposure: Source.Exposure, +key: String, +command_enabled: Maybe<&2, Bool>, +found: Maybe<&2, Rendered.Element>) ->
  {Rendered.source_concealment(exposure, key, command_enabled, found) == Spec.source_concealment(exposure, key, command_enabled, found) : +List<Rendered.Violation>}:
  match exposure found:
    case Source.Exposed{} _:
      {==}
    case Source.Concealed{} None{}:
      {==}
    case Source.Concealed{} Some{Rendered.Element{+observed, +visible, +enabled, +tab, +keyboard, +scroll, +bounds, +hit, +paint}}:
      %Equal.sym(Bool, Rendered.enabled_expectation(command_enabled, enabled), Spec.enabled_expectation(command_enabled, enabled), enabled_expectation(command_enabled, enabled)) :
        {List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(_), Rendered.DisabledAppearance{key}), Rendered.issue(visible || tab || keyboard || Bool.not(String.eq(hit, "")), Rendered.UnreachableControl{key})) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.enabled_expectation(command_enabled, enabled)), Rendered.DisabledAppearance{key}), Spec.issue(visible || tab || keyboard || Bool.not(String.eq(hit, "")), Rendered.UnreachableControl{key})) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Rendered.issue(visible || tab || keyboard || Bool.not(String.eq(hit, "")), Rendered.UnreachableControl{key}), Spec.issue(visible || tab || keyboard || Bool.not(String.eq(hit, "")), Rendered.UnreachableControl{key}), issue(visible || tab || keyboard || Bool.not(String.eq(hit, "")), Rendered.UnreachableControl{key})) :
        {List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Spec.enabled_expectation(command_enabled, enabled)), Rendered.DisabledAppearance{key}), _) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.enabled_expectation(command_enabled, enabled)), Rendered.DisabledAppearance{key}), Spec.issue(visible || tab || keyboard || Bool.not(String.eq(hit, "")), Rendered.UnreachableControl{key})) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Rendered.issue(Bool.not(Spec.enabled_expectation(command_enabled, enabled)), Rendered.DisabledAppearance{key}), Spec.issue(Bool.not(Spec.enabled_expectation(command_enabled, enabled)), Rendered.DisabledAppearance{key}), issue(Bool.not(Spec.enabled_expectation(command_enabled, enabled)), Rendered.DisabledAppearance{key})) :
        {List.append(&2, Rendered.Violation, _, Spec.issue(visible || tab || keyboard || Bool.not(String.eq(hit, "")), Rendered.UnreachableControl{key})) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.enabled_expectation(command_enabled, enabled)), Rendered.DisabledAppearance{key}), Spec.issue(visible || tab || keyboard || Bool.not(String.eq(hit, "")), Rendered.UnreachableControl{key})) : +List<Rendered.Violation>}
      {==}

def source_exposure_checks(+controls: +List<Rendered.ControlExposure>, +elements: +List<Rendered.Element>) ->
  {Rendered.source_exposure_checks(controls, elements) == Spec.source_exposure_checks(controls, elements) : +List<Rendered.Violation>}:
  match controls:
    case Nil{}:
      {==}
    case Con{Rendered.ControlExposure{+key, +exposure, +enabled}, +rest}:
      %Equal.sym(Maybe<&2, Rendered.Element>, Rendered.find_element(elements, key), Spec.first_observed_element(elements, key), first_observation(elements, key)) :
        {List.append(&2, Rendered.Violation, Rendered.source_concealment(exposure, key, enabled, _), Rendered.source_exposure_checks(rest, elements)) == List.append(&2, Rendered.Violation, Spec.source_concealment(exposure, key, enabled, Spec.first_observed_element(elements, key)), Spec.source_exposure_checks(rest, elements)) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Rendered.source_exposure_checks(rest, elements), Spec.source_exposure_checks(rest, elements), source_exposure_checks(rest, elements)) :
        {List.append(&2, Rendered.Violation, Rendered.source_concealment(exposure, key, enabled, Spec.first_observed_element(elements, key)), _) == List.append(&2, Rendered.Violation, Spec.source_concealment(exposure, key, enabled, Spec.first_observed_element(elements, key)), Spec.source_exposure_checks(rest, elements)) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Rendered.source_concealment(exposure, key, enabled, Spec.first_observed_element(elements, key)), Spec.source_concealment(exposure, key, enabled, Spec.first_observed_element(elements, key)), source_concealment(exposure, key, enabled, Spec.first_observed_element(elements, key))) :
        {List.append(&2, Rendered.Violation, _, Spec.source_exposure_checks(rest, elements)) == List.append(&2, Rendered.Violation, Spec.source_concealment(exposure, key, enabled, Spec.first_observed_element(elements, key)), Spec.source_exposure_checks(rest, elements)) : +List<Rendered.Violation>}
      {==}

def expected_tabs(+nodes: +List<SurfaceTypes.Node>, +elements: +List<Rendered.Element>, +native_focus: +List<Rendered.NativeFocus>) ->
  {Rendered.expected_tabs(nodes, elements, native_focus) == Spec.expected_tabs(nodes, elements, native_focus) : +List<String>}:
  match nodes:
    case Nil{}:
      {==}
    case Con{+node, +rest}:
      SurfaceTypes.Node{+key, +semantic, +label, +role, +meaning, +children} = node
      +identity = InterfaceView.node_key(node)
      %Equal.sym(Bool, Rendered.interactive(meaning), Spec.interactive(meaning), interactive(meaning)) :
        {Rendered.tab_entry(Rendered.own_tab_stop(_ && Rendered.required_enabled(meaning), elements, identity), identity, List.append(&2, String, Rendered.content_tabs(meaning, native_focus, identity), List.append(&2, String, Rendered.expected_tabs(children, elements, native_focus), Rendered.expected_tabs(rest, elements, native_focus)))) == Spec.tab_entry(Spec.own_tab_stop(Spec.interactive(meaning) && Spec.required_enabled(meaning), elements, identity), identity, List.append(&2, String, Spec.content_tabs(meaning, native_focus, identity), List.append(&2, String, Spec.expected_tabs(children, elements, native_focus), Spec.expected_tabs(rest, elements, native_focus)))) : +List<String>}
      %Equal.sym(Bool, Rendered.required_enabled(meaning), Spec.required_enabled(meaning), required_enabled(meaning)) :
        {Rendered.tab_entry(Rendered.own_tab_stop(Spec.interactive(meaning) && _, elements, identity), identity, List.append(&2, String, Rendered.content_tabs(meaning, native_focus, identity), List.append(&2, String, Rendered.expected_tabs(children, elements, native_focus), Rendered.expected_tabs(rest, elements, native_focus)))) == Spec.tab_entry(Spec.own_tab_stop(Spec.interactive(meaning) && Spec.required_enabled(meaning), elements, identity), identity, List.append(&2, String, Spec.content_tabs(meaning, native_focus, identity), List.append(&2, String, Spec.expected_tabs(children, elements, native_focus), Spec.expected_tabs(rest, elements, native_focus)))) : +List<String>}
      %Equal.sym(+List<String>, Rendered.expected_tabs(rest, elements, native_focus), Spec.expected_tabs(rest, elements, native_focus), expected_tabs(rest, elements, native_focus)) :
        {Rendered.tab_entry(Rendered.own_tab_stop(Spec.interactive(meaning) && Spec.required_enabled(meaning), elements, identity), identity, List.append(&2, String, Rendered.content_tabs(meaning, native_focus, identity), List.append(&2, String, Rendered.expected_tabs(children, elements, native_focus), _))) == Spec.tab_entry(Spec.own_tab_stop(Spec.interactive(meaning) && Spec.required_enabled(meaning), elements, identity), identity, List.append(&2, String, Spec.content_tabs(meaning, native_focus, identity), List.append(&2, String, Spec.expected_tabs(children, elements, native_focus), Spec.expected_tabs(rest, elements, native_focus)))) : +List<String>}
      %Equal.sym(+List<String>, Rendered.content_tabs(meaning, native_focus, identity), Spec.content_tabs(meaning, native_focus, identity), content_tabs(meaning, native_focus, identity)) :
        {Rendered.tab_entry(Rendered.own_tab_stop(Spec.interactive(meaning) && Spec.required_enabled(meaning), elements, identity), identity, List.append(&2, String, _, List.append(&2, String, Rendered.expected_tabs(children, elements, native_focus), Spec.expected_tabs(rest, elements, native_focus)))) == Spec.tab_entry(Spec.own_tab_stop(Spec.interactive(meaning) && Spec.required_enabled(meaning), elements, identity), identity, List.append(&2, String, Spec.content_tabs(meaning, native_focus, identity), List.append(&2, String, Spec.expected_tabs(children, elements, native_focus), Spec.expected_tabs(rest, elements, native_focus)))) : +List<String>}
      %Equal.sym(+List<String>, Rendered.expected_tabs(children, elements, native_focus), Spec.expected_tabs(children, elements, native_focus), expected_tabs(children, elements, native_focus)) :
        {Rendered.tab_entry(Rendered.own_tab_stop(Spec.interactive(meaning) && Spec.required_enabled(meaning), elements, identity), identity, List.append(&2, String, Spec.content_tabs(meaning, native_focus, identity), List.append(&2, String, _, Spec.expected_tabs(rest, elements, native_focus)))) == Spec.tab_entry(Spec.own_tab_stop(Spec.interactive(meaning) && Spec.required_enabled(meaning), elements, identity), identity, List.append(&2, String, Spec.content_tabs(meaning, native_focus, identity), List.append(&2, String, Spec.expected_tabs(children, elements, native_focus), Spec.expected_tabs(rest, elements, native_focus)))) : +List<String>}
      %Equal.sym(Bool, Rendered.own_tab_stop(Spec.interactive(meaning) && Spec.required_enabled(meaning), elements, identity), Spec.own_tab_stop(Spec.interactive(meaning) && Spec.required_enabled(meaning), elements, identity), own_tab_stop(Spec.interactive(meaning) && Spec.required_enabled(meaning), elements, identity)) :
        {Rendered.tab_entry(_, identity, List.append(&2, String, Spec.content_tabs(meaning, native_focus, identity), List.append(&2, String, Spec.expected_tabs(children, elements, native_focus), Spec.expected_tabs(rest, elements, native_focus)))) == Spec.tab_entry(Spec.own_tab_stop(Spec.interactive(meaning) && Spec.required_enabled(meaning), elements, identity), identity, List.append(&2, String, Spec.content_tabs(meaning, native_focus, identity), List.append(&2, String, Spec.expected_tabs(children, elements, native_focus), Spec.expected_tabs(rest, elements, native_focus)))) : +List<String>}
      %Equal.sym(+List<String>, Rendered.tab_entry(Spec.own_tab_stop(Spec.interactive(meaning) && Spec.required_enabled(meaning), elements, identity), identity, List.append(&2, String, Spec.content_tabs(meaning, native_focus, identity), List.append(&2, String, Spec.expected_tabs(children, elements, native_focus), Spec.expected_tabs(rest, elements, native_focus)))), Spec.tab_entry(Spec.own_tab_stop(Spec.interactive(meaning) && Spec.required_enabled(meaning), elements, identity), identity, List.append(&2, String, Spec.content_tabs(meaning, native_focus, identity), List.append(&2, String, Spec.expected_tabs(children, elements, native_focus), Spec.expected_tabs(rest, elements, native_focus)))), tab_entry(Spec.own_tab_stop(Spec.interactive(meaning) && Spec.required_enabled(meaning), elements, identity), identity, List.append(&2, String, Spec.content_tabs(meaning, native_focus, identity), List.append(&2, String, Spec.expected_tabs(children, elements, native_focus), Spec.expected_tabs(rest, elements, native_focus))))) :
        {_ == Spec.tab_entry(Spec.own_tab_stop(Spec.interactive(meaning) && Spec.required_enabled(meaning), elements, identity), identity, List.append(&2, String, Spec.content_tabs(meaning, native_focus, identity), List.append(&2, String, Spec.expected_tabs(children, elements, native_focus), Spec.expected_tabs(rest, elements, native_focus)))) : +List<String>}
      {==}

def allocated_authored_key_step(+same: Bool, +key: String, +actual: String, +expected: String, equality: {actual == expected : String}) ->
  {Renderer.authored_observation_key_match(same, key, (_ => actual)) == Bool.pick(String, same, key, expected) : String}:
  match same:
    case True{}: {==}
    case False{}: equality

def allocated_authored_key(+values: +List<Source.Attribute>, +fallback: String) ->
  {Renderer.authored_observation_key(values, fallback) == Spec.allocated_authored_key(values, fallback) : String}:
  match values:
    case Nil{}: {==}
    case Con{Source.DataAttribute{+name, +key}, +rest}:
      %Equal.sym(Bool, SafeText.string_equal(name, "native-key"), String.eq(name, "native-key"), TextProof.public_refines(name, "native-key")) :
        {Renderer.authored_observation_key_match(_, key, (_ => Renderer.authored_observation_key(rest, fallback))) == Bool.pick(String, String.eq(name, "native-key"), key, Spec.allocated_authored_key(rest, fallback)) : String}
      allocated_authored_key_step(String.eq(name, "native-key"), key, Renderer.authored_observation_key(rest, fallback), Spec.allocated_authored_key(rest, fallback), allocated_authored_key(rest, fallback))
    case Con{Source.ExposureAttribute{attr_value}, +rest}: allocated_authored_key(rest, fallback)
    case Con{Source.ReadingAttribute{attr_binding}, +rest}: allocated_authored_key(rest, fallback)
    case Con{Source.EditorBindingAttribute{attr_key}, +rest}: allocated_authored_key(rest, fallback)
    case Con{Source.IdAttribute{attr_value}, +rest}: allocated_authored_key(rest, fallback)
    case Con{Source.AriaAttribute{attr_name, attr_value}, +rest}: allocated_authored_key(rest, fallback)
    case Con{Source.RoleAttribute{attr_value}, +rest}: allocated_authored_key(rest, fallback)
    case Con{Source.TitleAttribute{attr_value}, +rest}: allocated_authored_key(rest, fallback)
    case Con{Source.TabIndexAttribute{attr_value}, +rest}: allocated_authored_key(rest, fallback)
    case Con{Source.ValueAttribute{attr_value}, +rest}: allocated_authored_key(rest, fallback)
    case Con{Source.CheckedAttribute{}, +rest}: allocated_authored_key(rest, fallback)
    case Con{Source.OpenAttribute{}, +rest}: allocated_authored_key(rest, fallback)
    case Con{Source.DraggableAttribute{attr_value}, +rest}: allocated_authored_key(rest, fallback)
    case Con{Source.InertAttribute{}, +rest}: allocated_authored_key(rest, fallback)

def allocated_observation_key(+value: Content.Value) ->
  {Renderer.observation_key(value) == Spec.allocated_observation_key(value) : String}:
  match value:
    case Content.Value{Source.Text{+key, +text, +choice, +wrap}, +font}:
      {==}
    case Content.Value{Source.Glyph{+key, +picture, +style}, +font}:
      {==}
    case Content.Value{Source.Box{+key, +tag, +style, +attrs, +children}, +font}:
      %Equal.sym(String, Renderer.authored_observation_key(attrs, UIIdentity.encode(key)), Spec.allocated_authored_key(attrs, UIIdentity.encode(key)), allocated_authored_key(attrs, UIIdentity.encode(key))) :
        {_ == Spec.allocated_authored_key(attrs, UIIdentity.encode(key)) : String}
      {==}
    case Content.Value{Source.Control{+key, +tag, +style, +attrs, +name, +enabled, +first, +remaining, +children}, +font}:
      %Equal.sym(String, Renderer.authored_observation_key(attrs, UIIdentity.encode(key)), Spec.allocated_authored_key(attrs, UIIdentity.encode(key)), allocated_authored_key(attrs, UIIdentity.encode(key))) :
        {_ == Spec.allocated_authored_key(attrs, UIIdentity.encode(key)) : String}
      {==}
    case Content.Value{Source.Field{+key, +kind, +style, +attrs, +text, +placeholder, +options, +policy, +name, +enabled, +first, +remaining}, +font}:
      %Equal.sym(String, Renderer.authored_observation_key(attrs, UIIdentity.encode(key)), Spec.allocated_authored_key(attrs, UIIdentity.encode(key)), allocated_authored_key(attrs, UIIdentity.encode(key))) :
        {_ == Spec.allocated_authored_key(attrs, UIIdentity.encode(key)) : String}
      {==}
    case Content.Value{Source.RichText{+key, +style, +content, +attachments, +native_owner}, +font}:
      {==}
    case Content.Value{Source.NativeAttachment{+key, +target, +attrs, +style, +children}, +font}:
      %Equal.sym(String, Renderer.authored_observation_key(attrs, UIIdentity.encode(key)), Spec.allocated_authored_key(attrs, UIIdentity.encode(key)), allocated_authored_key(attrs, UIIdentity.encode(key))) :
        {_ == Spec.allocated_authored_key(attrs, UIIdentity.encode(key)) : String}
      {==}

def allocated_rectangle(+box: Spatial.Box) ->
  {Frame.rectangle(box) == Spec.allocated_rectangle(box) : Geometry.Rect}:
  Spatial.Box{+left, +top, +width, +height} = box
  {==}

def allocated_ordinary(+value: Content.Value) ->
  {Frame.ordinary(value) == Spec.allocated_ordinary(value) : Bool}:
  Content.Value{+node, +font} = value
  match node:
    case Source.NativeAttachment{+key, +target, +attrs, +style, +children}:
      {==}
    case Source.Box{key, tag, style, attributes, children}: {==}
    case Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: {==}
    case Source.Text{key, value, font, wrapping}: {==}
    case Source.Glyph{key, drawing, style}: {==}
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: {==}
    case Source.RichText{key, style, content, attachments, native_owner}: {==}

def allocated_value_exposure(+parent: Source.Exposure, +value: Content.Value) ->
  {Frame.value_exposure(parent, value) == Spec.allocated_value_exposure(parent, value) : Source.Exposure}:
  Content.Value{+node, font} = value
  %Equal.sym(Source.Exposure, Source.node_exposure(node), Spec.node_exposure(node), source_node_exposure(node)) :
    {Source.combine_exposure(parent, _) == Spec.combine_exposure(parent, Spec.node_exposure(node)) : Source.Exposure}
  source_combine_exposure(parent, Spec.node_exposure(node))

def allocated_entry_if(+ordinary: Bool, +value: Content.Value, +bounds: Spatial.Box, +interaction: Model.Interaction<Doc.DOMEvent>, +exposure: Source.Exposure, +rest: +List<Frame.Expected>) ->
  {Frame.entry_if(ordinary, value, bounds, interaction, exposure, rest) == Spec.allocated_entry_if(ordinary, value, bounds, interaction, exposure, rest) : +List<Frame.Expected>}:
  match ordinary:
    case True{}:
      %Equal.sym(String, Renderer.observation_key(value), Spec.allocated_observation_key(value), allocated_observation_key(value)) :
        {Frame.Expected{_, bounds, interaction, exposure} <> rest == Frame.Expected{Spec.allocated_observation_key(value), bounds, interaction, exposure} <> rest : +List<Frame.Expected>}
      {==}
    case False{}:
      {==}

def allocated_entry(+value: Content.Value, +bounds: Spatial.Box, +interaction: Model.Interaction<Doc.DOMEvent>, +rest: +List<Frame.Expected>) ->
  {Frame.entry(value, bounds, interaction, rest) == Spec.allocated_entry(value, bounds, interaction, rest) : +List<Frame.Expected>}:
  %Equal.sym(Bool, Frame.ordinary(value), Spec.allocated_ordinary(value), allocated_ordinary(value)) :
    {Frame.entry_if(_, value, bounds, interaction, Frame.value_exposure(Source.Exposed{}, value), rest) == Spec.allocated_entry_if(Spec.allocated_ordinary(value), value, bounds, interaction, Spec.allocated_value_exposure(Source.Exposed{}, value), rest) : +List<Frame.Expected>}
  %Equal.sym(Source.Exposure, Frame.value_exposure(Source.Exposed{}, value), Spec.allocated_value_exposure(Source.Exposed{}, value), allocated_value_exposure(Source.Exposed{}, value)) :
    {Frame.entry_if(Spec.allocated_ordinary(value), value, bounds, interaction, _, rest) == Spec.allocated_entry_if(Spec.allocated_ordinary(value), value, bounds, interaction, Spec.allocated_value_exposure(Source.Exposed{}, value), rest) : +List<Frame.Expected>}
  %Equal.sym(+List<Frame.Expected>, Frame.entry_if(Spec.allocated_ordinary(value), value, bounds, interaction, Spec.allocated_value_exposure(Source.Exposed{}, value), rest), Spec.allocated_entry_if(Spec.allocated_ordinary(value), value, bounds, interaction, Spec.allocated_value_exposure(Source.Exposed{}, value), rest), allocated_entry_if(Spec.allocated_ordinary(value), value, bounds, interaction, Spec.allocated_value_exposure(Source.Exposed{}, value), rest)) :
    {_ == Spec.allocated_entry_if(Spec.allocated_ordinary(value), value, bounds, interaction, Spec.allocated_value_exposure(Source.Exposed{}, value), rest) : +List<Frame.Expected>}
  {==}

def allocated_forest_with(+trees: +List<Allocation.AllocatedTree<Content.Value, Doc.DOMEvent>>, +parent: Source.Exposure) ->
  {Frame.forest_with(trees, parent) == Spec.allocated_forest_with(trees, parent) : +List<Frame.Expected>}:
  match trees:
    case Nil{}:
      {==}
    case Con{Allocation.AllocatedLeaf{+physical, +value, +interaction, +rule, +demand, +height, +bounds, +canvas}, +rest}:
      %Equal.sym(Bool, Frame.ordinary(value), Spec.allocated_ordinary(value), allocated_ordinary(value)) :
        {Frame.entry_if(_, value, bounds, interaction, Frame.value_exposure(parent, value), Frame.forest_with(rest, parent)) == Spec.allocated_entry_if(Spec.allocated_ordinary(value), value, bounds, interaction, Spec.allocated_value_exposure(parent, value), Spec.allocated_forest_with(rest, parent)) : +List<Frame.Expected>}
      %Equal.sym(+List<Frame.Expected>, Frame.forest_with(rest, parent), Spec.allocated_forest_with(rest, parent), allocated_forest_with(rest, parent)) :
        {Frame.entry_if(Spec.allocated_ordinary(value), value, bounds, interaction, Frame.value_exposure(parent, value), _) == Spec.allocated_entry_if(Spec.allocated_ordinary(value), value, bounds, interaction, Spec.allocated_value_exposure(parent, value), Spec.allocated_forest_with(rest, parent)) : +List<Frame.Expected>}
      %Equal.sym(Source.Exposure, Frame.value_exposure(parent, value), Spec.allocated_value_exposure(parent, value), allocated_value_exposure(parent, value)) :
        {Frame.entry_if(Spec.allocated_ordinary(value), value, bounds, interaction, _, Spec.allocated_forest_with(rest, parent)) == Spec.allocated_entry_if(Spec.allocated_ordinary(value), value, bounds, interaction, Spec.allocated_value_exposure(parent, value), Spec.allocated_forest_with(rest, parent)) : +List<Frame.Expected>}
      %Equal.sym(+List<Frame.Expected>, Frame.entry_if(Spec.allocated_ordinary(value), value, bounds, interaction, Spec.allocated_value_exposure(parent, value), Spec.allocated_forest_with(rest, parent)), Spec.allocated_entry_if(Spec.allocated_ordinary(value), value, bounds, interaction, Spec.allocated_value_exposure(parent, value), Spec.allocated_forest_with(rest, parent)), allocated_entry_if(Spec.allocated_ordinary(value), value, bounds, interaction, Spec.allocated_value_exposure(parent, value), Spec.allocated_forest_with(rest, parent))) :
        {_ == Spec.allocated_entry_if(Spec.allocated_ordinary(value), value, bounds, interaction, Spec.allocated_value_exposure(parent, value), Spec.allocated_forest_with(rest, parent)) : +List<Frame.Expected>}
      {==}
    case Con{Allocation.AllocatedContainer{+physical, +value, +interaction, +rule, +bounds, +canvas, +direction, +children}, +rest}:
      %Equal.sym(Bool, Frame.ordinary(value), Spec.allocated_ordinary(value), allocated_ordinary(value)) :
        {Frame.entry_if(_, value, bounds, interaction, (Frame.value_exposure(parent, value)), List.append(&2, Frame.Expected, Frame.forest_with(children, (Frame.value_exposure(parent, value))), Frame.forest_with(rest, parent))) == Spec.allocated_entry_if(Spec.allocated_ordinary(value), value, bounds, interaction, (Spec.allocated_value_exposure(parent, value)), List.append(&2, Frame.Expected, Spec.allocated_forest_with(children, (Spec.allocated_value_exposure(parent, value))), Spec.allocated_forest_with(rest, parent))) : +List<Frame.Expected>}
      %Equal.sym(+List<Frame.Expected>, Frame.forest_with(rest, parent), Spec.allocated_forest_with(rest, parent), allocated_forest_with(rest, parent)) :
        {Frame.entry_if(Spec.allocated_ordinary(value), value, bounds, interaction, (Frame.value_exposure(parent, value)), List.append(&2, Frame.Expected, Frame.forest_with(children, (Frame.value_exposure(parent, value))), _)) == Spec.allocated_entry_if(Spec.allocated_ordinary(value), value, bounds, interaction, (Spec.allocated_value_exposure(parent, value)), List.append(&2, Frame.Expected, Spec.allocated_forest_with(children, (Spec.allocated_value_exposure(parent, value))), Spec.allocated_forest_with(rest, parent))) : +List<Frame.Expected>}
      %Equal.sym(Source.Exposure, Frame.value_exposure(parent, value), Spec.allocated_value_exposure(parent, value), allocated_value_exposure(parent, value)) :
        {Frame.entry_if(Spec.allocated_ordinary(value), value, bounds, interaction, (_), List.append(&2, Frame.Expected, Frame.forest_with(children, (Frame.value_exposure(parent, value))), Spec.allocated_forest_with(rest, parent))) == Spec.allocated_entry_if(Spec.allocated_ordinary(value), value, bounds, interaction, (Spec.allocated_value_exposure(parent, value)), List.append(&2, Frame.Expected, Spec.allocated_forest_with(children, (Spec.allocated_value_exposure(parent, value))), Spec.allocated_forest_with(rest, parent))) : +List<Frame.Expected>}
      %Equal.sym(Source.Exposure, Frame.value_exposure(parent, value), Spec.allocated_value_exposure(parent, value), allocated_value_exposure(parent, value)) :
        {Frame.entry_if(Spec.allocated_ordinary(value), value, bounds, interaction, (Spec.allocated_value_exposure(parent, value)), List.append(&2, Frame.Expected, Frame.forest_with(children, (_)), Spec.allocated_forest_with(rest, parent))) == Spec.allocated_entry_if(Spec.allocated_ordinary(value), value, bounds, interaction, (Spec.allocated_value_exposure(parent, value)), List.append(&2, Frame.Expected, Spec.allocated_forest_with(children, (Spec.allocated_value_exposure(parent, value))), Spec.allocated_forest_with(rest, parent))) : +List<Frame.Expected>}
      %Equal.sym(+List<Frame.Expected>, Frame.forest_with(children, (Spec.allocated_value_exposure(parent, value))), Spec.allocated_forest_with(children, (Spec.allocated_value_exposure(parent, value))), allocated_forest_with(children, (Spec.allocated_value_exposure(parent, value)))) :
        {Frame.entry_if(Spec.allocated_ordinary(value), value, bounds, interaction, (Spec.allocated_value_exposure(parent, value)), List.append(&2, Frame.Expected, _, Spec.allocated_forest_with(rest, parent))) == Spec.allocated_entry_if(Spec.allocated_ordinary(value), value, bounds, interaction, (Spec.allocated_value_exposure(parent, value)), List.append(&2, Frame.Expected, Spec.allocated_forest_with(children, (Spec.allocated_value_exposure(parent, value))), Spec.allocated_forest_with(rest, parent))) : +List<Frame.Expected>}
      %Equal.sym(+List<Frame.Expected>, Frame.entry_if(Spec.allocated_ordinary(value), value, bounds, interaction, (Spec.allocated_value_exposure(parent, value)), List.append(&2, Frame.Expected, Spec.allocated_forest_with(children, (Spec.allocated_value_exposure(parent, value))), Spec.allocated_forest_with(rest, parent))), Spec.allocated_entry_if(Spec.allocated_ordinary(value), value, bounds, interaction, (Spec.allocated_value_exposure(parent, value)), List.append(&2, Frame.Expected, Spec.allocated_forest_with(children, (Spec.allocated_value_exposure(parent, value))), Spec.allocated_forest_with(rest, parent))), allocated_entry_if(Spec.allocated_ordinary(value), value, bounds, interaction, (Spec.allocated_value_exposure(parent, value)), List.append(&2, Frame.Expected, Spec.allocated_forest_with(children, (Spec.allocated_value_exposure(parent, value))), Spec.allocated_forest_with(rest, parent)))) :
        {_ == Spec.allocated_entry_if(Spec.allocated_ordinary(value), value, bounds, interaction, (Spec.allocated_value_exposure(parent, value)), List.append(&2, Frame.Expected, Spec.allocated_forest_with(children, (Spec.allocated_value_exposure(parent, value))), Spec.allocated_forest_with(rest, parent))) : +List<Frame.Expected>}
      {==}

def allocated_forest(+trees: +List<Allocation.AllocatedTree<Content.Value, Doc.DOMEvent>>) ->
  {Frame.forest(trees) == Spec.allocated_forest(trees) : +List<Frame.Expected>}:
  %Equal.sym(+List<Frame.Expected>, Frame.forest_with(trees, Source.Exposed{}), Spec.allocated_forest_with(trees, Source.Exposed{}), allocated_forest_with(trees, Source.Exposed{})) :
    {_ == Spec.allocated_forest_with(trees, Source.Exposed{}) : +List<Frame.Expected>}
  {==}

def allocated_expected(+world: Content.AllocatedWorld) ->
  {Frame.expected(world) == Spec.allocated_expected(world) : +List<Frame.Expected>}:
  Content.AllocatedWorld{+snapshot, +tree, +roots, +policies} = world
  %Equal.sym(+List<Frame.Expected>, Frame.forest([tree]), Spec.allocated_forest([tree]), allocated_forest([tree])) :
    {_ == Spec.allocated_forest([tree]) : +List<Frame.Expected>}
  {==}

def allocated_add_occurrence(+same: Bool, +count: Nat) ->
  {Frame.add_occurrence(same, count) == Spec.allocated_add_occurrence(same, count) : Nat}:
  match same:
    case True{}:
      {==}
    case False{}:
      {==}

def allocated_occurrences(+elements: +List<Rendered.Element>, +key: String) ->
  {Frame.occurrences(elements, key) == Spec.allocated_occurrences(elements, key) : Nat}:
  match elements:
    case Nil{}:
      {==}
    case Con{Rendered.Element{+observed, +visible, +enabled, +tab, +keyboard, +scroll, +bounds, +hit, +paint}, +rest}:
      %Equal.sym(Nat, Frame.occurrences(rest, key), Spec.allocated_occurrences(rest, key), allocated_occurrences(rest, key)) :
        {Frame.add_occurrence(SafeText.string_equal(observed, key), _) == Spec.allocated_add_occurrence(String.eq(observed, key), Spec.allocated_occurrences(rest, key)) : Nat}
      %Equal.sym(Bool, SafeText.string_equal(observed, key), String.eq(observed, key), TextProof.public_refines(observed, key)) :
        {Frame.add_occurrence(_, Spec.allocated_occurrences(rest, key)) == Spec.allocated_add_occurrence(String.eq(observed, key), Spec.allocated_occurrences(rest, key)) : Nat}
      %Equal.sym(Nat, Frame.add_occurrence(String.eq(observed, key), Spec.allocated_occurrences(rest, key)), Spec.allocated_add_occurrence(String.eq(observed, key), Spec.allocated_occurrences(rest, key)), allocated_add_occurrence(String.eq(observed, key), Spec.allocated_occurrences(rest, key))) :
        {_ == Spec.allocated_add_occurrence(String.eq(observed, key), Spec.allocated_occurrences(rest, key)) : Nat}
      {==}

def allocated_same_rectangle(+first: Geometry.Rect, +second: Geometry.Rect) ->
  {Frame.same_rectangle(first, second) == Spec.allocated_same_rectangle(first, second) : Bool}:
  Geometry.Rect{+left, +top, +right, +bottom} = first
  Geometry.Rect{+other_left, +other_top, +other_right, +other_bottom} = second
  {==}

def allocated_interactive(+interaction: Model.Interaction<Doc.DOMEvent>) ->
  {Frame.interactive(interaction) == Spec.allocated_interactive(interaction) : Bool}:
  match interaction:
    case Model.DisplayOnly{}:
      {==}
    case Model.Operable{+first, +remaining, +enabled}:
      {==}

def allocated_operable_exposure(+exposure: Source.Exposure, +enabled: Bool, +key: String, +element: Rendered.Element, +viewport: Geometry.Rect) ->
  {Frame.operable_exposure(exposure, enabled, key, element, viewport) == Spec.allocated_operable_exposure(exposure, enabled, key, element, viewport) : +List<Rendered.Violation>}:
  match exposure:
    case Source.Concealed{}:
      Rendered.Element{+observed, +visible, +observed_enabled, +tab, +keyboard, +scroll, +bounds, +hit, +paint} = element
      %Equal.sym(+List<Rendered.Violation>, Rendered.issue(Bool.not(((enabled && observed_enabled) || (Bool.not(enabled) && Bool.not(observed_enabled)))), Rendered.UnreachableControl{key}), Spec.issue(Bool.not(((enabled && observed_enabled) || (Bool.not(enabled) && Bool.not(observed_enabled)))), Rendered.UnreachableControl{key}), issue(Bool.not(((enabled && observed_enabled) || (Bool.not(enabled) && Bool.not(observed_enabled)))), Rendered.UnreachableControl{key})) :
        {_ == Spec.issue(Bool.not(((enabled && observed_enabled) || (Bool.not(enabled) && Bool.not(observed_enabled)))), Rendered.UnreachableControl{key}) : +List<Rendered.Violation>}
      {==}
    case Source.Exposed{}:
      Rendered.Element{+observed, +visible, +observed_enabled, +tab, +keyboard, +scroll, +bounds, +hit, +paint} = element
      %Equal.sym(+List<Rendered.Violation>, Rendered.issue(Bool.not(((enabled && tab) || (Bool.not(enabled) && Bool.not(tab)))), Rendered.UnreachableControl{key}), Spec.issue(Bool.not(((enabled && tab) || (Bool.not(enabled) && Bool.not(tab)))), Rendered.UnreachableControl{key}), issue(Bool.not(((enabled && tab) || (Bool.not(enabled) && Bool.not(tab)))), Rendered.UnreachableControl{key})) :
        {List.append(&2, Rendered.Violation, _, Rendered.control_geometry(enabled, key, Some{Rendered.Element{observed, visible, observed_enabled, tab, keyboard, scroll, bounds, hit, paint}}, True{}, viewport)) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(((enabled && tab) || (Bool.not(enabled) && Bool.not(tab)))), Rendered.UnreachableControl{key}), Spec.control_geometry(enabled, key, Some{Rendered.Element{observed, visible, observed_enabled, tab, keyboard, scroll, bounds, hit, paint}}, True{}, viewport)) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Rendered.control_geometry(enabled, key, Some{Rendered.Element{observed, visible, observed_enabled, tab, keyboard, scroll, bounds, hit, paint}}, True{}, viewport), Spec.control_geometry(enabled, key, Some{Rendered.Element{observed, visible, observed_enabled, tab, keyboard, scroll, bounds, hit, paint}}, True{}, viewport), control_geometry(enabled, key, Some{Rendered.Element{observed, visible, observed_enabled, tab, keyboard, scroll, bounds, hit, paint}}, True{}, viewport)) :
        {List.append(&2, Rendered.Violation, Spec.issue(Bool.not(((enabled && tab) || (Bool.not(enabled) && Bool.not(tab)))), Rendered.UnreachableControl{key}), _) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(((enabled && tab) || (Bool.not(enabled) && Bool.not(tab)))), Rendered.UnreachableControl{key}), Spec.control_geometry(enabled, key, Some{Rendered.Element{observed, visible, observed_enabled, tab, keyboard, scroll, bounds, hit, paint}}, True{}, viewport)) : +List<Rendered.Violation>}
      {==}

def allocated_operable_geometry(+exposure: Source.Exposure, +interaction: Model.Interaction<Doc.DOMEvent>, +key: String, +element: Rendered.Element, +viewport: Geometry.Rect) ->
  {Frame.operable_geometry(exposure, interaction, key, element, viewport) == Spec.allocated_operable_geometry(exposure, interaction, key, element, viewport) : +List<Rendered.Violation>}:
  match interaction:
    case Model.DisplayOnly{}:
      {==}
    case Model.Operable{+first, +remaining, +enabled}:
      %Equal.sym(+List<Rendered.Violation>, Frame.operable_exposure(exposure, enabled, key, element, viewport), Spec.allocated_operable_exposure(exposure, enabled, key, element, viewport), allocated_operable_exposure(exposure, enabled, key, element, viewport)) :
        {_ == Spec.allocated_operable_exposure(exposure, enabled, key, element, viewport) : +List<Rendered.Violation>}
      {==}

def allocated_exposure_geometry(+exposure: Source.Exposure, +visible: Bool, +tab: Bool, +keyboard: Bool, +hit: String, +bounds: Geometry.Rect, +paint: Geometry.Rect, +viewport: Geometry.Rect) ->
  {Frame.exposure_geometry(exposure, visible, tab, keyboard, hit, bounds, paint, viewport) == Spec.allocated_exposure_geometry(exposure, visible, tab, keyboard, hit, bounds, paint, viewport) : Bool}:
  match exposure:
    case Source.Exposed{}:
      %Equal.sym(Bool, Rendered.paint_geometry_valid(visible, bounds, paint, viewport), Spec.paint_geometry_valid(visible, bounds, paint, viewport), paint_geometry_valid(visible, bounds, paint, viewport)) :
        {visible && _ == visible && Spec.paint_geometry_valid(visible, bounds, paint, viewport) : Bool}
      {==}
    case Source.Concealed{}:
      {==}

def allocated_node_geometry(+exposure: Source.Exposure, +key: String, +bounds: Spatial.Box, +interaction: Model.Interaction<Doc.DOMEvent>, +found: Maybe<&2, Rendered.Element>, +viewport: Geometry.Rect) ->
  {Frame.node_geometry(exposure, key, bounds, interaction, found, viewport) == Spec.allocated_node_geometry(exposure, key, bounds, interaction, found, viewport) : +List<Rendered.Violation>}:
  match found:
    case None{}:
      {==}
    case Some{+element}:
      Rendered.Element{+observed, +visible, +enabled, +tab, +keyboard, +scroll, +measured, +hit, +paint} = element
      %Equal.sym(Geometry.Rect, Frame.rectangle(bounds), Spec.allocated_rectangle(bounds), allocated_rectangle(bounds)) :
        {List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Frame.same_rectangle(_, measured) && Geometry.contains(viewport, measured) && Frame.exposure_geometry(exposure, visible, tab, keyboard, hit, measured, paint, viewport)), Rendered.InvalidPaintGeometry{key}), Frame.operable_geometry(exposure, interaction, key, element, viewport)) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.allocated_same_rectangle(Spec.allocated_rectangle(bounds), measured) && Geometry.contains(viewport, measured) && Spec.allocated_exposure_geometry(exposure, visible, tab, keyboard, hit, measured, paint, viewport)), Rendered.InvalidPaintGeometry{key}), Spec.allocated_operable_geometry(exposure, interaction, key, element, viewport)) : +List<Rendered.Violation>}
      %Equal.sym(Bool, Frame.same_rectangle(Spec.allocated_rectangle(bounds), measured), Spec.allocated_same_rectangle(Spec.allocated_rectangle(bounds), measured), allocated_same_rectangle(Spec.allocated_rectangle(bounds), measured)) :
        {List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(_ && Geometry.contains(viewport, measured) && Frame.exposure_geometry(exposure, visible, tab, keyboard, hit, measured, paint, viewport)), Rendered.InvalidPaintGeometry{key}), Frame.operable_geometry(exposure, interaction, key, element, viewport)) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.allocated_same_rectangle(Spec.allocated_rectangle(bounds), measured) && Geometry.contains(viewport, measured) && Spec.allocated_exposure_geometry(exposure, visible, tab, keyboard, hit, measured, paint, viewport)), Rendered.InvalidPaintGeometry{key}), Spec.allocated_operable_geometry(exposure, interaction, key, element, viewport)) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Frame.operable_geometry(exposure, interaction, key, element, viewport), Spec.allocated_operable_geometry(exposure, interaction, key, element, viewport), allocated_operable_geometry(exposure, interaction, key, element, viewport)) :
        {List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Spec.allocated_same_rectangle(Spec.allocated_rectangle(bounds), measured) && Geometry.contains(viewport, measured) && Frame.exposure_geometry(exposure, visible, tab, keyboard, hit, measured, paint, viewport)), Rendered.InvalidPaintGeometry{key}), _) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.allocated_same_rectangle(Spec.allocated_rectangle(bounds), measured) && Geometry.contains(viewport, measured) && Spec.allocated_exposure_geometry(exposure, visible, tab, keyboard, hit, measured, paint, viewport)), Rendered.InvalidPaintGeometry{key}), Spec.allocated_operable_geometry(exposure, interaction, key, element, viewport)) : +List<Rendered.Violation>}
      %Equal.sym(Bool, Frame.exposure_geometry(exposure, visible, tab, keyboard, hit, measured, paint, viewport), Spec.allocated_exposure_geometry(exposure, visible, tab, keyboard, hit, measured, paint, viewport), allocated_exposure_geometry(exposure, visible, tab, keyboard, hit, measured, paint, viewport)) :
        {List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Spec.allocated_same_rectangle(Spec.allocated_rectangle(bounds), measured) && Geometry.contains(viewport, measured) && _), Rendered.InvalidPaintGeometry{key}), Spec.allocated_operable_geometry(exposure, interaction, key, element, viewport)) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.allocated_same_rectangle(Spec.allocated_rectangle(bounds), measured) && Geometry.contains(viewport, measured) && Spec.allocated_exposure_geometry(exposure, visible, tab, keyboard, hit, measured, paint, viewport)), Rendered.InvalidPaintGeometry{key}), Spec.allocated_operable_geometry(exposure, interaction, key, element, viewport)) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Rendered.issue(Bool.not(Spec.allocated_same_rectangle(Spec.allocated_rectangle(bounds), measured) && Geometry.contains(viewport, measured) && Spec.allocated_exposure_geometry(exposure, visible, tab, keyboard, hit, measured, paint, viewport)), Rendered.InvalidPaintGeometry{key}), Spec.issue(Bool.not(Spec.allocated_same_rectangle(Spec.allocated_rectangle(bounds), measured) && Geometry.contains(viewport, measured) && Spec.allocated_exposure_geometry(exposure, visible, tab, keyboard, hit, measured, paint, viewport)), Rendered.InvalidPaintGeometry{key}), issue(Bool.not(Spec.allocated_same_rectangle(Spec.allocated_rectangle(bounds), measured) && Geometry.contains(viewport, measured) && Spec.allocated_exposure_geometry(exposure, visible, tab, keyboard, hit, measured, paint, viewport)), Rendered.InvalidPaintGeometry{key})) :
        {List.append(&2, Rendered.Violation, _, Spec.allocated_operable_geometry(exposure, interaction, key, element, viewport)) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.allocated_same_rectangle(Spec.allocated_rectangle(bounds), measured) && Geometry.contains(viewport, measured) && Spec.allocated_exposure_geometry(exposure, visible, tab, keyboard, hit, measured, paint, viewport)), Rendered.InvalidPaintGeometry{key}), Spec.allocated_operable_geometry(exposure, interaction, key, element, viewport)) : +List<Rendered.Violation>}
      {==}

def allocated_nodes(+entries: +List<Frame.Expected>, +elements: +List<Rendered.Element>, +viewport: Geometry.Rect) ->
  {Frame.nodes(entries, elements, viewport) == Spec.allocated_nodes(entries, elements, viewport) : +List<Rendered.Violation>}:
  match entries:
    case Nil{}:
      {==}
    case Con{Frame.Expected{+key, +bounds, +interaction, +exposure}, +rest}:
      %Equal.sym(Nat, Frame.occurrences(elements, key), Spec.allocated_occurrences(elements, key), allocated_occurrences(elements, key)) :
        {List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Nat.is_eq(_, 1n)), Rendered.MissingElement{key}), List.append(&2, Rendered.Violation, Frame.node_geometry(exposure, key, bounds, interaction, Rendered.find_element(elements, key), viewport), Frame.nodes(rest, elements, viewport))) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Nat.is_eq(Spec.allocated_occurrences(elements, key), 1n)), Rendered.MissingElement{key}), List.append(&2, Rendered.Violation, Spec.allocated_node_geometry(exposure, key, bounds, interaction, Spec.first_observed_element(elements, key), viewport), Spec.allocated_nodes(rest, elements, viewport))) : +List<Rendered.Violation>}
      %Equal.sym(Maybe<&2, Rendered.Element>, Rendered.find_element(elements, key), Spec.first_observed_element(elements, key), first_observation(elements, key)) :
        {List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Nat.is_eq(Spec.allocated_occurrences(elements, key), 1n)), Rendered.MissingElement{key}), List.append(&2, Rendered.Violation, Frame.node_geometry(exposure, key, bounds, interaction, _, viewport), Frame.nodes(rest, elements, viewport))) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Nat.is_eq(Spec.allocated_occurrences(elements, key), 1n)), Rendered.MissingElement{key}), List.append(&2, Rendered.Violation, Spec.allocated_node_geometry(exposure, key, bounds, interaction, Spec.first_observed_element(elements, key), viewport), Spec.allocated_nodes(rest, elements, viewport))) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Frame.nodes(rest, elements, viewport), Spec.allocated_nodes(rest, elements, viewport), allocated_nodes(rest, elements, viewport)) :
        {List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Nat.is_eq(Spec.allocated_occurrences(elements, key), 1n)), Rendered.MissingElement{key}), List.append(&2, Rendered.Violation, Frame.node_geometry(exposure, key, bounds, interaction, Spec.first_observed_element(elements, key), viewport), _)) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Nat.is_eq(Spec.allocated_occurrences(elements, key), 1n)), Rendered.MissingElement{key}), List.append(&2, Rendered.Violation, Spec.allocated_node_geometry(exposure, key, bounds, interaction, Spec.first_observed_element(elements, key), viewport), Spec.allocated_nodes(rest, elements, viewport))) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Frame.node_geometry(exposure, key, bounds, interaction, Spec.first_observed_element(elements, key), viewport), Spec.allocated_node_geometry(exposure, key, bounds, interaction, Spec.first_observed_element(elements, key), viewport), allocated_node_geometry(exposure, key, bounds, interaction, Spec.first_observed_element(elements, key), viewport)) :
        {List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Nat.is_eq(Spec.allocated_occurrences(elements, key), 1n)), Rendered.MissingElement{key}), List.append(&2, Rendered.Violation, _, Spec.allocated_nodes(rest, elements, viewport))) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Nat.is_eq(Spec.allocated_occurrences(elements, key), 1n)), Rendered.MissingElement{key}), List.append(&2, Rendered.Violation, Spec.allocated_node_geometry(exposure, key, bounds, interaction, Spec.first_observed_element(elements, key), viewport), Spec.allocated_nodes(rest, elements, viewport))) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Rendered.issue(Bool.not(Nat.is_eq(Spec.allocated_occurrences(elements, key), 1n)), Rendered.MissingElement{key}), Spec.issue(Bool.not(Nat.is_eq(Spec.allocated_occurrences(elements, key), 1n)), Rendered.MissingElement{key}), issue(Bool.not(Nat.is_eq(Spec.allocated_occurrences(elements, key), 1n)), Rendered.MissingElement{key})) :
        {List.append(&2, Rendered.Violation, _, List.append(&2, Rendered.Violation, Spec.allocated_node_geometry(exposure, key, bounds, interaction, Spec.first_observed_element(elements, key), viewport), Spec.allocated_nodes(rest, elements, viewport))) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Nat.is_eq(Spec.allocated_occurrences(elements, key), 1n)), Rendered.MissingElement{key}), List.append(&2, Rendered.Violation, Spec.allocated_node_geometry(exposure, key, bounds, interaction, Spec.first_observed_element(elements, key), viewport), Spec.allocated_nodes(rest, elements, viewport))) : +List<Rendered.Violation>}
      {==}

def source_exposed(+exposure: Source.Exposure) ->
  {Source.exposed(exposure) == Spec.exposed(exposure) : Bool}:
  match exposure:
    case Source.Exposed{}: {==}
    case Source.Concealed{}: {==}

def allocated_tabs(+entries: +List<Frame.Expected>) ->
  {Frame.tabs(entries) == Spec.allocated_tabs(entries) : +List<String>}:
  match entries:
    case Nil{}:
      {==}
    case Con{Frame.Expected{+key, +bounds, +interaction, +exposure}, +rest}:
      %source_exposed(exposure) :
        {Rendered.tab_entry(Source.exposed(exposure) && Frame.interactive(interaction), key, Frame.tabs(rest)) == Spec.tab_entry(_ && Spec.allocated_interactive(interaction), key, Spec.allocated_tabs(rest)) : +List<String>}
      %Equal.sym(+List<String>, Frame.tabs(rest), Spec.allocated_tabs(rest), allocated_tabs(rest)) :
        {Rendered.tab_entry(Source.exposed(exposure) && Frame.interactive(interaction), key, _) == Spec.tab_entry(Source.exposed(exposure) && Spec.allocated_interactive(interaction), key, Spec.allocated_tabs(rest)) : +List<String>}
      %Equal.sym(Bool, Frame.interactive(interaction), Spec.allocated_interactive(interaction), allocated_interactive(interaction)) :
        {Rendered.tab_entry(Source.exposed(exposure) && _, key, Spec.allocated_tabs(rest)) == Spec.tab_entry(Source.exposed(exposure) && Spec.allocated_interactive(interaction), key, Spec.allocated_tabs(rest)) : +List<String>}
      %Equal.sym(+List<String>, Rendered.tab_entry(Source.exposed(exposure) && Spec.allocated_interactive(interaction), key, Spec.allocated_tabs(rest)), Spec.tab_entry(Source.exposed(exposure) && Spec.allocated_interactive(interaction), key, Spec.allocated_tabs(rest)), tab_entry(Source.exposed(exposure) && Spec.allocated_interactive(interaction), key, Spec.allocated_tabs(rest))) :
        {_ == Spec.tab_entry(Source.exposed(exposure) && Spec.allocated_interactive(interaction), key, Spec.allocated_tabs(rest)) : +List<String>}
      {==}

def allocated_controls(+entries: +List<Frame.Expected>, +elements: +List<Rendered.Element>) ->
  {Frame.controls(entries, elements) == Spec.allocated_controls(entries, elements) : +List<Rendered.Element>}:
  match entries:
    case Nil{}:
      {==}
    case Con{Frame.Expected{+key, +bounds, +interaction, +exposure}, +rest}:
      %source_exposed(exposure) :
        {Rendered.include_element(Source.exposed(exposure) && Frame.interactive(interaction), Rendered.find_element(elements, key), Frame.controls(rest, elements)) == Spec.include_element(_ && Spec.allocated_interactive(interaction), Spec.first_observed_element(elements, key), Spec.allocated_controls(rest, elements)) : +List<Rendered.Element>}
      %Equal.sym(Bool, Frame.interactive(interaction), Spec.allocated_interactive(interaction), allocated_interactive(interaction)) :
        {Rendered.include_element(Source.exposed(exposure) && _, Rendered.find_element(elements, key), Frame.controls(rest, elements)) == Spec.include_element(Source.exposed(exposure) && Spec.allocated_interactive(interaction), Spec.first_observed_element(elements, key), Spec.allocated_controls(rest, elements)) : +List<Rendered.Element>}
      %Equal.sym(+List<Rendered.Element>, Frame.controls(rest, elements), Spec.allocated_controls(rest, elements), allocated_controls(rest, elements)) :
        {Rendered.include_element(Source.exposed(exposure) && Spec.allocated_interactive(interaction), Rendered.find_element(elements, key), _) == Spec.include_element(Source.exposed(exposure) && Spec.allocated_interactive(interaction), Spec.first_observed_element(elements, key), Spec.allocated_controls(rest, elements)) : +List<Rendered.Element>}
      %Equal.sym(Maybe<&2, Rendered.Element>, Rendered.find_element(elements, key), Spec.first_observed_element(elements, key), first_observation(elements, key)) :
        {Rendered.include_element(Source.exposed(exposure) && Spec.allocated_interactive(interaction), _, Spec.allocated_controls(rest, elements)) == Spec.include_element(Source.exposed(exposure) && Spec.allocated_interactive(interaction), Spec.first_observed_element(elements, key), Spec.allocated_controls(rest, elements)) : +List<Rendered.Element>}
      %Equal.sym(+List<Rendered.Element>, Rendered.include_element(Source.exposed(exposure) && Spec.allocated_interactive(interaction), Spec.first_observed_element(elements, key), Spec.allocated_controls(rest, elements)), Spec.include_element(Source.exposed(exposure) && Spec.allocated_interactive(interaction), Spec.first_observed_element(elements, key), Spec.allocated_controls(rest, elements)), include_element(Source.exposed(exposure) && Spec.allocated_interactive(interaction), Spec.first_observed_element(elements, key), Spec.allocated_controls(rest, elements))) :
        {_ == Spec.include_element(Source.exposed(exposure) && Spec.allocated_interactive(interaction), Spec.first_observed_element(elements, key), Spec.allocated_controls(rest, elements)) : +List<Rendered.Element>}
      {==}

def contains_exact_key(+keys: +List<String>, +key: String) ->
  {List.contains(String, (first => second => SafeText.string_equal(first, second)), keys, key) == List.contains(String, (first => second => String.eq(first, second)), keys, key) : Bool}:
  match keys:
    case Nil{}: {==}
    case Con{+head, +rest}:
      %Equal.sym(Bool, SafeText.string_equal(head, key), String.eq(head, key), TextProof.public_refines(head, key)) :
        {(_ || List.contains(String, (first => second => SafeText.string_equal(first, second)), rest, key)) == List.contains(String, (first => second => String.eq(first, second)), head <> rest, key) : Bool}
      Equal.cong(Bool, Bool, (tail => String.eq(head, key) || tail),
        List.contains(String, (first => second => SafeText.string_equal(first, second)), rest, key), List.contains(String, (first => second => String.eq(first, second)), rest, key), contains_exact_key(rest, key))

def allocated_focused_owned(+focused: Maybe<&2, String>, +entries: +List<Frame.Expected>) ->
  {Frame.focused_owned(focused, entries) == Spec.allocated_focused_owned(focused, entries) : Bool}:
  match focused:
    case None{}: {==}
    case Some{+key}:
      %Equal.sym((+List<String>), Frame.tabs(entries), Spec.allocated_tabs(entries), allocated_tabs(entries)) :
        {List.contains(String, (first => second => SafeText.string_equal(first, second)), _, key) == List.contains(String, (first => second => String.eq(first, second)), Spec.allocated_tabs(entries), key) : Bool}
      contains_exact_key(Spec.allocated_tabs(entries), key)

def allocated_no_native(+world: Content.AllocatedWorld) ->
  {Frame.no_native(world) == Spec.allocated_no_native(world) : Bool}:
  Content.AllocatedWorld{+snapshot, +tree, +roots, +policies} = world
  match roots policies:
    case Nil{} Nil{}:
      {==}
    case Nil{} Con{policy, rest}: {==}
    case Con{root, rest} _: {==}

def allocated_focus_geometry(+focused: Maybe<&2, String>, +elements: +List<Rendered.Element>, +viewport: Geometry.Rect) ->
  {Frame.focus_geometry(focused, elements, viewport) == Spec.allocated_focus_geometry(focused, elements, viewport) : +List<Rendered.Violation>}:
  match focused:
    case None{}:
      {==}
    case Some{+key}:
      %Equal.sym(Maybe<&2, Rendered.Element>, Rendered.find_element(elements, key), Spec.first_observed_element(elements, key), first_observation(elements, key)) :
        {Rendered.issue(Bool.not(Rendered.focus_visible(_, viewport)), Rendered.InvisibleFocus{}) == Spec.issue(Bool.not(Spec.focus_visible(Spec.first_observed_element(elements, key), viewport)), Rendered.InvisibleFocus{}) : +List<Rendered.Violation>}
      %Equal.sym(Bool, Rendered.focus_visible(Spec.first_observed_element(elements, key), viewport), Spec.focus_visible(Spec.first_observed_element(elements, key), viewport), focus_visible(Spec.first_observed_element(elements, key), viewport)) :
        {Rendered.issue(Bool.not(_), Rendered.InvisibleFocus{}) == Spec.issue(Bool.not(Spec.focus_visible(Spec.first_observed_element(elements, key), viewport)), Rendered.InvisibleFocus{}) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Rendered.issue(Bool.not(Spec.focus_visible(Spec.first_observed_element(elements, key), viewport)), Rendered.InvisibleFocus{}), Spec.issue(Bool.not(Spec.focus_visible(Spec.first_observed_element(elements, key), viewport)), Rendered.InvisibleFocus{}), issue(Bool.not(Spec.focus_visible(Spec.first_observed_element(elements, key), viewport)), Rendered.InvisibleFocus{})) :
        {_ == Spec.issue(Bool.not(Spec.focus_visible(Spec.first_observed_element(elements, key), viewport)), Rendered.InvisibleFocus{}) : +List<Rendered.Violation>}
      {==}

def allocated_native_free(+entries: +List<Rendered.NativeFocus>) ->
  {Frame.native_free(entries) == Spec.allocated_native_free(entries) : Bool}:
  match entries:
    case Nil{}:
      {==}
    case Con{+first, +rest}:
      {==}

def allocated_focus_checks(+focused: Maybe<&2, String>, +entries: +List<Frame.Expected>, +elements: +List<Rendered.Element>, +viewport: Geometry.Rect) ->
  {Frame.focus_checks(focused, entries, elements, viewport) == Spec.allocated_focus_checks(focused, entries, elements, viewport) : +List<Rendered.Violation>}:
  %Equal.sym(Bool, Frame.focused_owned(focused, entries), Spec.allocated_focused_owned(focused, entries), allocated_focused_owned(focused, entries)) :
    {List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(_), Rendered.FocusOutsideScope{}), Frame.focus_geometry(focused, elements, viewport)) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.allocated_focused_owned(focused, entries)), Rendered.FocusOutsideScope{}), Spec.allocated_focus_geometry(focused, elements, viewport)) : +List<Rendered.Violation>}
  %Equal.sym(+List<Rendered.Violation>, Frame.focus_geometry(focused, elements, viewport), Spec.allocated_focus_geometry(focused, elements, viewport), allocated_focus_geometry(focused, elements, viewport)) :
    {List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Spec.allocated_focused_owned(focused, entries)), Rendered.FocusOutsideScope{}), _) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.allocated_focused_owned(focused, entries)), Rendered.FocusOutsideScope{}), Spec.allocated_focus_geometry(focused, elements, viewport)) : +List<Rendered.Violation>}
  %Equal.sym(+List<Rendered.Violation>, Rendered.issue(Bool.not(Spec.allocated_focused_owned(focused, entries)), Rendered.FocusOutsideScope{}), Spec.issue(Bool.not(Spec.allocated_focused_owned(focused, entries)), Rendered.FocusOutsideScope{}), issue(Bool.not(Spec.allocated_focused_owned(focused, entries)), Rendered.FocusOutsideScope{})) :
    {List.append(&2, Rendered.Violation, _, Spec.allocated_focus_geometry(focused, elements, viewport)) == List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.allocated_focused_owned(focused, entries)), Rendered.FocusOutsideScope{}), Spec.allocated_focus_geometry(focused, elements, viewport)) : +List<Rendered.Violation>}
  {==}

def allocated_check(+world: Content.AllocatedWorld, +frame: Rendered.Frame) ->
  {Frame.check(world, frame) == Spec.allocated_frame_diagnostics(world, frame) : +List<Rendered.Violation>}:
  Rendered.Frame{+viewport, +elements, +focused, +tab_order, +native_focus} = frame
  +entries = Frame.expected(world)
  %allocated_expected(world) :
    {Frame.check(world, Rendered.Frame{viewport, elements, focused, tab_order, native_focus}) ==
      List.append(&2, Rendered.Violation, Spec.allocated_nodes(_, elements, viewport),
        List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.same_order(Spec.allocated_tabs(_), tab_order)), Rendered.WrongTabOrder{}),
          List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.allocated_no_native(world) && Spec.allocated_native_free(native_focus)), Rendered.FocusOutsideScope{}),
            List.append(&2, Rendered.Violation, Spec.allocated_focus_checks(focused, _, elements, viewport),
              Spec.independent_targets(Spec.allocated_controls(_, elements)))))) : +List<Rendered.Violation>}
  %Equal.sym(+List<String>, Frame.tabs(entries), Spec.allocated_tabs(entries), allocated_tabs(entries)) :
    {List.append(&2, Rendered.Violation, Frame.nodes(entries, elements, viewport), List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Rendered.same_order(_, tab_order)), Rendered.WrongTabOrder{}), List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Frame.no_native(world) && Frame.native_free(native_focus)), Rendered.FocusOutsideScope{}), List.append(&2, Rendered.Violation, Frame.focus_checks(focused, entries, elements, viewport), Rendered.independent_targets(Frame.controls(entries, elements)))))) == List.append(&2, Rendered.Violation, Spec.allocated_nodes(entries, elements, viewport), List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.same_order(Spec.allocated_tabs(entries), tab_order)), Rendered.WrongTabOrder{}), List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.allocated_no_native(world) && Spec.allocated_native_free(native_focus)), Rendered.FocusOutsideScope{}), List.append(&2, Rendered.Violation, Spec.allocated_focus_checks(focused, entries, elements, viewport), Spec.independent_targets(Spec.allocated_controls(entries, elements)))))) : +List<Rendered.Violation>}
  %Equal.sym(Bool, Frame.no_native(world), Spec.allocated_no_native(world), allocated_no_native(world)) :
    {List.append(&2, Rendered.Violation, Frame.nodes(entries, elements, viewport), List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Rendered.same_order(Spec.allocated_tabs(entries), tab_order)), Rendered.WrongTabOrder{}), List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(_ && Frame.native_free(native_focus)), Rendered.FocusOutsideScope{}), List.append(&2, Rendered.Violation, Frame.focus_checks(focused, entries, elements, viewport), Rendered.independent_targets(Frame.controls(entries, elements)))))) == List.append(&2, Rendered.Violation, Spec.allocated_nodes(entries, elements, viewport), List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.same_order(Spec.allocated_tabs(entries), tab_order)), Rendered.WrongTabOrder{}), List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.allocated_no_native(world) && Spec.allocated_native_free(native_focus)), Rendered.FocusOutsideScope{}), List.append(&2, Rendered.Violation, Spec.allocated_focus_checks(focused, entries, elements, viewport), Spec.independent_targets(Spec.allocated_controls(entries, elements)))))) : +List<Rendered.Violation>}
  %Equal.sym(Bool, Frame.native_free(native_focus), Spec.allocated_native_free(native_focus), allocated_native_free(native_focus)) :
    {List.append(&2, Rendered.Violation, Frame.nodes(entries, elements, viewport), List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Rendered.same_order(Spec.allocated_tabs(entries), tab_order)), Rendered.WrongTabOrder{}), List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Spec.allocated_no_native(world) && _), Rendered.FocusOutsideScope{}), List.append(&2, Rendered.Violation, Frame.focus_checks(focused, entries, elements, viewport), Rendered.independent_targets(Frame.controls(entries, elements)))))) == List.append(&2, Rendered.Violation, Spec.allocated_nodes(entries, elements, viewport), List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.same_order(Spec.allocated_tabs(entries), tab_order)), Rendered.WrongTabOrder{}), List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.allocated_no_native(world) && Spec.allocated_native_free(native_focus)), Rendered.FocusOutsideScope{}), List.append(&2, Rendered.Violation, Spec.allocated_focus_checks(focused, entries, elements, viewport), Spec.independent_targets(Spec.allocated_controls(entries, elements)))))) : +List<Rendered.Violation>}
  %Equal.sym(+List<Rendered.Element>, Frame.controls(entries, elements), Spec.allocated_controls(entries, elements), allocated_controls(entries, elements)) :
    {List.append(&2, Rendered.Violation, Frame.nodes(entries, elements, viewport), List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Rendered.same_order(Spec.allocated_tabs(entries), tab_order)), Rendered.WrongTabOrder{}), List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Spec.allocated_no_native(world) && Spec.allocated_native_free(native_focus)), Rendered.FocusOutsideScope{}), List.append(&2, Rendered.Violation, Frame.focus_checks(focused, entries, elements, viewport), Rendered.independent_targets(_))))) == List.append(&2, Rendered.Violation, Spec.allocated_nodes(entries, elements, viewport), List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.same_order(Spec.allocated_tabs(entries), tab_order)), Rendered.WrongTabOrder{}), List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.allocated_no_native(world) && Spec.allocated_native_free(native_focus)), Rendered.FocusOutsideScope{}), List.append(&2, Rendered.Violation, Spec.allocated_focus_checks(focused, entries, elements, viewport), Spec.independent_targets(Spec.allocated_controls(entries, elements)))))) : +List<Rendered.Violation>}
  %Equal.sym(+List<Rendered.Violation>, Frame.nodes(entries, elements, viewport), Spec.allocated_nodes(entries, elements, viewport), allocated_nodes(entries, elements, viewport)) :
    {List.append(&2, Rendered.Violation, _, List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Rendered.same_order(Spec.allocated_tabs(entries), tab_order)), Rendered.WrongTabOrder{}), List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Spec.allocated_no_native(world) && Spec.allocated_native_free(native_focus)), Rendered.FocusOutsideScope{}), List.append(&2, Rendered.Violation, Frame.focus_checks(focused, entries, elements, viewport), Rendered.independent_targets(Spec.allocated_controls(entries, elements)))))) == List.append(&2, Rendered.Violation, Spec.allocated_nodes(entries, elements, viewport), List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.same_order(Spec.allocated_tabs(entries), tab_order)), Rendered.WrongTabOrder{}), List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.allocated_no_native(world) && Spec.allocated_native_free(native_focus)), Rendered.FocusOutsideScope{}), List.append(&2, Rendered.Violation, Spec.allocated_focus_checks(focused, entries, elements, viewport), Spec.independent_targets(Spec.allocated_controls(entries, elements)))))) : +List<Rendered.Violation>}
  %Equal.sym(+List<Rendered.Violation>, Frame.focus_checks(focused, entries, elements, viewport), Spec.allocated_focus_checks(focused, entries, elements, viewport), allocated_focus_checks(focused, entries, elements, viewport)) :
    {List.append(&2, Rendered.Violation, Spec.allocated_nodes(entries, elements, viewport), List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Rendered.same_order(Spec.allocated_tabs(entries), tab_order)), Rendered.WrongTabOrder{}), List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Spec.allocated_no_native(world) && Spec.allocated_native_free(native_focus)), Rendered.FocusOutsideScope{}), List.append(&2, Rendered.Violation, _, Rendered.independent_targets(Spec.allocated_controls(entries, elements)))))) == List.append(&2, Rendered.Violation, Spec.allocated_nodes(entries, elements, viewport), List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.same_order(Spec.allocated_tabs(entries), tab_order)), Rendered.WrongTabOrder{}), List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.allocated_no_native(world) && Spec.allocated_native_free(native_focus)), Rendered.FocusOutsideScope{}), List.append(&2, Rendered.Violation, Spec.allocated_focus_checks(focused, entries, elements, viewport), Spec.independent_targets(Spec.allocated_controls(entries, elements)))))) : +List<Rendered.Violation>}
  %Equal.sym(Bool, Rendered.same_order(Spec.allocated_tabs(entries), tab_order), Spec.same_order(Spec.allocated_tabs(entries), tab_order), same_order(Spec.allocated_tabs(entries), tab_order)) :
    {List.append(&2, Rendered.Violation, Spec.allocated_nodes(entries, elements, viewport), List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(_), Rendered.WrongTabOrder{}), List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Spec.allocated_no_native(world) && Spec.allocated_native_free(native_focus)), Rendered.FocusOutsideScope{}), List.append(&2, Rendered.Violation, Spec.allocated_focus_checks(focused, entries, elements, viewport), Rendered.independent_targets(Spec.allocated_controls(entries, elements)))))) == List.append(&2, Rendered.Violation, Spec.allocated_nodes(entries, elements, viewport), List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.same_order(Spec.allocated_tabs(entries), tab_order)), Rendered.WrongTabOrder{}), List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.allocated_no_native(world) && Spec.allocated_native_free(native_focus)), Rendered.FocusOutsideScope{}), List.append(&2, Rendered.Violation, Spec.allocated_focus_checks(focused, entries, elements, viewport), Spec.independent_targets(Spec.allocated_controls(entries, elements)))))) : +List<Rendered.Violation>}
  %Equal.sym(+List<Rendered.Violation>, Rendered.independent_targets(Spec.allocated_controls(entries, elements)), Spec.independent_targets(Spec.allocated_controls(entries, elements)), independent_targets(Spec.allocated_controls(entries, elements))) :
    {List.append(&2, Rendered.Violation, Spec.allocated_nodes(entries, elements, viewport), List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Spec.same_order(Spec.allocated_tabs(entries), tab_order)), Rendered.WrongTabOrder{}), List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Spec.allocated_no_native(world) && Spec.allocated_native_free(native_focus)), Rendered.FocusOutsideScope{}), List.append(&2, Rendered.Violation, Spec.allocated_focus_checks(focused, entries, elements, viewport), _)))) == List.append(&2, Rendered.Violation, Spec.allocated_nodes(entries, elements, viewport), List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.same_order(Spec.allocated_tabs(entries), tab_order)), Rendered.WrongTabOrder{}), List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.allocated_no_native(world) && Spec.allocated_native_free(native_focus)), Rendered.FocusOutsideScope{}), List.append(&2, Rendered.Violation, Spec.allocated_focus_checks(focused, entries, elements, viewport), Spec.independent_targets(Spec.allocated_controls(entries, elements)))))) : +List<Rendered.Violation>}
  %Equal.sym(+List<Rendered.Violation>, Rendered.issue(Bool.not(Spec.same_order(Spec.allocated_tabs(entries), tab_order)), Rendered.WrongTabOrder{}), Spec.issue(Bool.not(Spec.same_order(Spec.allocated_tabs(entries), tab_order)), Rendered.WrongTabOrder{}), issue(Bool.not(Spec.same_order(Spec.allocated_tabs(entries), tab_order)), Rendered.WrongTabOrder{})) :
    {List.append(&2, Rendered.Violation, Spec.allocated_nodes(entries, elements, viewport), List.append(&2, Rendered.Violation, _, List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Spec.allocated_no_native(world) && Spec.allocated_native_free(native_focus)), Rendered.FocusOutsideScope{}), List.append(&2, Rendered.Violation, Spec.allocated_focus_checks(focused, entries, elements, viewport), Spec.independent_targets(Spec.allocated_controls(entries, elements)))))) == List.append(&2, Rendered.Violation, Spec.allocated_nodes(entries, elements, viewport), List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.same_order(Spec.allocated_tabs(entries), tab_order)), Rendered.WrongTabOrder{}), List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.allocated_no_native(world) && Spec.allocated_native_free(native_focus)), Rendered.FocusOutsideScope{}), List.append(&2, Rendered.Violation, Spec.allocated_focus_checks(focused, entries, elements, viewport), Spec.independent_targets(Spec.allocated_controls(entries, elements)))))) : +List<Rendered.Violation>}
  %Equal.sym(+List<Rendered.Violation>, Rendered.issue(Bool.not(Spec.allocated_no_native(world) && Spec.allocated_native_free(native_focus)), Rendered.FocusOutsideScope{}), Spec.issue(Bool.not(Spec.allocated_no_native(world) && Spec.allocated_native_free(native_focus)), Rendered.FocusOutsideScope{}), issue(Bool.not(Spec.allocated_no_native(world) && Spec.allocated_native_free(native_focus)), Rendered.FocusOutsideScope{})) :
    {List.append(&2, Rendered.Violation, Spec.allocated_nodes(entries, elements, viewport), List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.same_order(Spec.allocated_tabs(entries), tab_order)), Rendered.WrongTabOrder{}), List.append(&2, Rendered.Violation, _, List.append(&2, Rendered.Violation, Spec.allocated_focus_checks(focused, entries, elements, viewport), Spec.independent_targets(Spec.allocated_controls(entries, elements)))))) == List.append(&2, Rendered.Violation, Spec.allocated_nodes(entries, elements, viewport), List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.same_order(Spec.allocated_tabs(entries), tab_order)), Rendered.WrongTabOrder{}), List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.allocated_no_native(world) && Spec.allocated_native_free(native_focus)), Rendered.FocusOutsideScope{}), List.append(&2, Rendered.Violation, Spec.allocated_focus_checks(focused, entries, elements, viewport), Spec.independent_targets(Spec.allocated_controls(entries, elements)))))) : +List<Rendered.Violation>}
  {==}

def allocated_command_enabled(+interaction: Model.Interaction<Doc.DOMEvent>) ->
  {Frame.command_enabled(interaction) == Spec.allocated_command_enabled(interaction) : Maybe<&2, Bool>}:
  match interaction:
    case Model.DisplayOnly{}:
      {==}
    case Model.Operable{+first, +remaining, +enabled}:
      {==}

def allocated_value_inert(+value: Content.Value) ->
  {Frame.value_inert(value) == Spec.allocated_value_inert(value) : Bool}:
  Content.Value{+node, font} = value
  source_node_inert(node)

def allocated_exposure_entry(+inert: Bool, +ordinary: Bool, +value: Content.Value, +interaction: Model.Interaction<Doc.DOMEvent>, +exposure: Source.Exposure) ->
  {Frame.exposure_entry(inert, ordinary, value, interaction, exposure) == Spec.allocated_exposure_entry(inert, ordinary, value, interaction, exposure) : +List<Rendered.ControlExposure>}:
  match inert ordinary:
    case False{} True{}:
      %Equal.sym(String, Renderer.observation_key(value), Spec.allocated_observation_key(value), allocated_observation_key(value)) :
        {[Rendered.ControlExposure{_, exposure, Frame.command_enabled(interaction)}] == [Rendered.ControlExposure{Spec.allocated_observation_key(value), exposure, Spec.allocated_command_enabled(interaction)}] : +List<Rendered.ControlExposure>}
      %Equal.sym(Maybe<&2, Bool>, Frame.command_enabled(interaction), Spec.allocated_command_enabled(interaction), allocated_command_enabled(interaction)) :
        {[Rendered.ControlExposure{Spec.allocated_observation_key(value), exposure, _}] == [Rendered.ControlExposure{Spec.allocated_observation_key(value), exposure, Spec.allocated_command_enabled(interaction)}] : +List<Rendered.ControlExposure>}
      {==}
    case False{} False{}: {==}
    case True{} False{}: {==}
    case True{} True{}: {==}

def allocated_retain_exposure(+inert: Bool, +own: +List<Rendered.ControlExposure>, +rest: +List<Rendered.ControlExposure>) ->
  {Frame.retain_exposure(inert, own, rest) == Spec.allocated_retain_exposure(inert, own, rest) : +List<Rendered.ControlExposure>}:
  match inert:
    case True{}:
      {==}
    case False{}:
      {==}

def allocated_exposure_forest(+trees: +List<Allocation.AllocatedTree<Content.Value, Doc.DOMEvent>>, +parent: Source.Exposure) ->
  {Frame.exposure_forest(trees, parent) == Spec.allocated_exposure_forest(trees, parent) : +List<Rendered.ControlExposure>}:
  match trees:
    case Nil{}:
      {==}
    case Con{Allocation.AllocatedLeaf{+physical, +value, +interaction, +rule, +demand, +height, +bounds, +canvas}, +rest}:
      %Equal.sym(Bool, Frame.ordinary(value), Spec.allocated_ordinary(value), allocated_ordinary(value)) :
        {List.append(&2, Rendered.ControlExposure, Frame.exposure_entry(Frame.value_inert(value), _, value, interaction, Frame.value_exposure(parent, value)), Frame.exposure_forest(rest, parent)) == List.append(&2, Rendered.ControlExposure, Spec.allocated_exposure_entry(Spec.allocated_value_inert(value), Spec.allocated_ordinary(value), value, interaction, Spec.allocated_value_exposure(parent, value)), Spec.allocated_exposure_forest(rest, parent)) : +List<Rendered.ControlExposure>}
      %Equal.sym(Bool, Frame.value_inert(value), Spec.allocated_value_inert(value), allocated_value_inert(value)) :
        {List.append(&2, Rendered.ControlExposure, Frame.exposure_entry(_, Spec.allocated_ordinary(value), value, interaction, Frame.value_exposure(parent, value)), Frame.exposure_forest(rest, parent)) == List.append(&2, Rendered.ControlExposure, Spec.allocated_exposure_entry(Spec.allocated_value_inert(value), Spec.allocated_ordinary(value), value, interaction, Spec.allocated_value_exposure(parent, value)), Spec.allocated_exposure_forest(rest, parent)) : +List<Rendered.ControlExposure>}
      %Equal.sym(Source.Exposure, Frame.value_exposure(parent, value), Spec.allocated_value_exposure(parent, value), allocated_value_exposure(parent, value)) :
        {List.append(&2, Rendered.ControlExposure, Frame.exposure_entry(Spec.allocated_value_inert(value), Spec.allocated_ordinary(value), value, interaction, _), Frame.exposure_forest(rest, parent)) == List.append(&2, Rendered.ControlExposure, Spec.allocated_exposure_entry(Spec.allocated_value_inert(value), Spec.allocated_ordinary(value), value, interaction, Spec.allocated_value_exposure(parent, value)), Spec.allocated_exposure_forest(rest, parent)) : +List<Rendered.ControlExposure>}
      %Equal.sym(+List<Rendered.ControlExposure>, Frame.exposure_forest(rest, parent), Spec.allocated_exposure_forest(rest, parent), allocated_exposure_forest(rest, parent)) :
        {List.append(&2, Rendered.ControlExposure, Frame.exposure_entry(Spec.allocated_value_inert(value), Spec.allocated_ordinary(value), value, interaction, Spec.allocated_value_exposure(parent, value)), _) == List.append(&2, Rendered.ControlExposure, Spec.allocated_exposure_entry(Spec.allocated_value_inert(value), Spec.allocated_ordinary(value), value, interaction, Spec.allocated_value_exposure(parent, value)), Spec.allocated_exposure_forest(rest, parent)) : +List<Rendered.ControlExposure>}
      %Equal.sym(+List<Rendered.ControlExposure>, Frame.exposure_entry(Spec.allocated_value_inert(value), Spec.allocated_ordinary(value), value, interaction, Spec.allocated_value_exposure(parent, value)), Spec.allocated_exposure_entry(Spec.allocated_value_inert(value), Spec.allocated_ordinary(value), value, interaction, Spec.allocated_value_exposure(parent, value)), allocated_exposure_entry(Spec.allocated_value_inert(value), Spec.allocated_ordinary(value), value, interaction, Spec.allocated_value_exposure(parent, value))) :
        {List.append(&2, Rendered.ControlExposure, _, Spec.allocated_exposure_forest(rest, parent)) == List.append(&2, Rendered.ControlExposure, Spec.allocated_exposure_entry(Spec.allocated_value_inert(value), Spec.allocated_ordinary(value), value, interaction, Spec.allocated_value_exposure(parent, value)), Spec.allocated_exposure_forest(rest, parent)) : +List<Rendered.ControlExposure>}
      {==}
    case Con{Allocation.AllocatedContainer{+physical, +value, +interaction, +rule, +bounds, +canvas, +direction, +children}, +rest}:
      %Equal.sym(Bool, Frame.ordinary(value), Spec.allocated_ordinary(value), allocated_ordinary(value)) :
        {Frame.retain_exposure(Frame.value_inert(value), List.append(&2, Rendered.ControlExposure, Frame.exposure_entry(False{}, _, value, interaction, (Frame.value_exposure(parent, value))), Frame.exposure_forest(children, (Frame.value_exposure(parent, value)))), Frame.exposure_forest(rest, parent)) == Spec.allocated_retain_exposure(Spec.allocated_value_inert(value), List.append(&2, Rendered.ControlExposure, Spec.allocated_exposure_entry(False{}, Spec.allocated_ordinary(value), value, interaction, (Spec.allocated_value_exposure(parent, value))), Spec.allocated_exposure_forest(children, (Spec.allocated_value_exposure(parent, value)))), Spec.allocated_exposure_forest(rest, parent)) : +List<Rendered.ControlExposure>}
      %Equal.sym(Bool, Frame.value_inert(value), Spec.allocated_value_inert(value), allocated_value_inert(value)) :
        {Frame.retain_exposure(_, List.append(&2, Rendered.ControlExposure, Frame.exposure_entry(False{}, Spec.allocated_ordinary(value), value, interaction, (Frame.value_exposure(parent, value))), Frame.exposure_forest(children, (Frame.value_exposure(parent, value)))), Frame.exposure_forest(rest, parent)) == Spec.allocated_retain_exposure(Spec.allocated_value_inert(value), List.append(&2, Rendered.ControlExposure, Spec.allocated_exposure_entry(False{}, Spec.allocated_ordinary(value), value, interaction, (Spec.allocated_value_exposure(parent, value))), Spec.allocated_exposure_forest(children, (Spec.allocated_value_exposure(parent, value)))), Spec.allocated_exposure_forest(rest, parent)) : +List<Rendered.ControlExposure>}
      %Equal.sym(Source.Exposure, Frame.value_exposure(parent, value), Spec.allocated_value_exposure(parent, value), allocated_value_exposure(parent, value)) :
        {Frame.retain_exposure(Spec.allocated_value_inert(value), List.append(&2, Rendered.ControlExposure, Frame.exposure_entry(False{}, Spec.allocated_ordinary(value), value, interaction, (_)), Frame.exposure_forest(children, (Frame.value_exposure(parent, value)))), Frame.exposure_forest(rest, parent)) == Spec.allocated_retain_exposure(Spec.allocated_value_inert(value), List.append(&2, Rendered.ControlExposure, Spec.allocated_exposure_entry(False{}, Spec.allocated_ordinary(value), value, interaction, (Spec.allocated_value_exposure(parent, value))), Spec.allocated_exposure_forest(children, (Spec.allocated_value_exposure(parent, value)))), Spec.allocated_exposure_forest(rest, parent)) : +List<Rendered.ControlExposure>}
      %Equal.sym(Source.Exposure, Frame.value_exposure(parent, value), Spec.allocated_value_exposure(parent, value), allocated_value_exposure(parent, value)) :
        {Frame.retain_exposure(Spec.allocated_value_inert(value), List.append(&2, Rendered.ControlExposure, Frame.exposure_entry(False{}, Spec.allocated_ordinary(value), value, interaction, (Spec.allocated_value_exposure(parent, value))), Frame.exposure_forest(children, (_))), Frame.exposure_forest(rest, parent)) == Spec.allocated_retain_exposure(Spec.allocated_value_inert(value), List.append(&2, Rendered.ControlExposure, Spec.allocated_exposure_entry(False{}, Spec.allocated_ordinary(value), value, interaction, (Spec.allocated_value_exposure(parent, value))), Spec.allocated_exposure_forest(children, (Spec.allocated_value_exposure(parent, value)))), Spec.allocated_exposure_forest(rest, parent)) : +List<Rendered.ControlExposure>}
      %Equal.sym(+List<Rendered.ControlExposure>, Frame.exposure_forest(rest, parent), Spec.allocated_exposure_forest(rest, parent), allocated_exposure_forest(rest, parent)) :
        {Frame.retain_exposure(Spec.allocated_value_inert(value), List.append(&2, Rendered.ControlExposure, Frame.exposure_entry(False{}, Spec.allocated_ordinary(value), value, interaction, (Spec.allocated_value_exposure(parent, value))), Frame.exposure_forest(children, (Spec.allocated_value_exposure(parent, value)))), _) == Spec.allocated_retain_exposure(Spec.allocated_value_inert(value), List.append(&2, Rendered.ControlExposure, Spec.allocated_exposure_entry(False{}, Spec.allocated_ordinary(value), value, interaction, (Spec.allocated_value_exposure(parent, value))), Spec.allocated_exposure_forest(children, (Spec.allocated_value_exposure(parent, value)))), Spec.allocated_exposure_forest(rest, parent)) : +List<Rendered.ControlExposure>}
      %Equal.sym(+List<Rendered.ControlExposure>, Frame.exposure_forest(children, (Spec.allocated_value_exposure(parent, value))), Spec.allocated_exposure_forest(children, (Spec.allocated_value_exposure(parent, value))), allocated_exposure_forest(children, (Spec.allocated_value_exposure(parent, value)))) :
        {Frame.retain_exposure(Spec.allocated_value_inert(value), List.append(&2, Rendered.ControlExposure, Frame.exposure_entry(False{}, Spec.allocated_ordinary(value), value, interaction, (Spec.allocated_value_exposure(parent, value))), _), Spec.allocated_exposure_forest(rest, parent)) == Spec.allocated_retain_exposure(Spec.allocated_value_inert(value), List.append(&2, Rendered.ControlExposure, Spec.allocated_exposure_entry(False{}, Spec.allocated_ordinary(value), value, interaction, (Spec.allocated_value_exposure(parent, value))), Spec.allocated_exposure_forest(children, (Spec.allocated_value_exposure(parent, value)))), Spec.allocated_exposure_forest(rest, parent)) : +List<Rendered.ControlExposure>}
      %Equal.sym(+List<Rendered.ControlExposure>, Frame.exposure_entry(False{}, Spec.allocated_ordinary(value), value, interaction, (Spec.allocated_value_exposure(parent, value))), Spec.allocated_exposure_entry(False{}, Spec.allocated_ordinary(value), value, interaction, (Spec.allocated_value_exposure(parent, value))), allocated_exposure_entry(False{}, Spec.allocated_ordinary(value), value, interaction, (Spec.allocated_value_exposure(parent, value)))) :
        {Frame.retain_exposure(Spec.allocated_value_inert(value), List.append(&2, Rendered.ControlExposure, _, Spec.allocated_exposure_forest(children, (Spec.allocated_value_exposure(parent, value)))), Spec.allocated_exposure_forest(rest, parent)) == Spec.allocated_retain_exposure(Spec.allocated_value_inert(value), List.append(&2, Rendered.ControlExposure, Spec.allocated_exposure_entry(False{}, Spec.allocated_ordinary(value), value, interaction, (Spec.allocated_value_exposure(parent, value))), Spec.allocated_exposure_forest(children, (Spec.allocated_value_exposure(parent, value)))), Spec.allocated_exposure_forest(rest, parent)) : +List<Rendered.ControlExposure>}
      %Equal.sym(+List<Rendered.ControlExposure>, Frame.retain_exposure(Spec.allocated_value_inert(value), List.append(&2, Rendered.ControlExposure, Spec.allocated_exposure_entry(False{}, Spec.allocated_ordinary(value), value, interaction, (Spec.allocated_value_exposure(parent, value))), Spec.allocated_exposure_forest(children, (Spec.allocated_value_exposure(parent, value)))), Spec.allocated_exposure_forest(rest, parent)), Spec.allocated_retain_exposure(Spec.allocated_value_inert(value), List.append(&2, Rendered.ControlExposure, Spec.allocated_exposure_entry(False{}, Spec.allocated_ordinary(value), value, interaction, (Spec.allocated_value_exposure(parent, value))), Spec.allocated_exposure_forest(children, (Spec.allocated_value_exposure(parent, value)))), Spec.allocated_exposure_forest(rest, parent)), allocated_retain_exposure(Spec.allocated_value_inert(value), List.append(&2, Rendered.ControlExposure, Spec.allocated_exposure_entry(False{}, Spec.allocated_ordinary(value), value, interaction, (Spec.allocated_value_exposure(parent, value))), Spec.allocated_exposure_forest(children, (Spec.allocated_value_exposure(parent, value)))), Spec.allocated_exposure_forest(rest, parent))) :
        {_ == Spec.allocated_retain_exposure(Spec.allocated_value_inert(value), List.append(&2, Rendered.ControlExposure, Spec.allocated_exposure_entry(False{}, Spec.allocated_ordinary(value), value, interaction, (Spec.allocated_value_exposure(parent, value))), Spec.allocated_exposure_forest(children, (Spec.allocated_value_exposure(parent, value)))), Spec.allocated_exposure_forest(rest, parent)) : +List<Rendered.ControlExposure>}
      {==}

def allocated_expectations(+world: Content.AllocatedWorld, +frame: Rendered.Frame) ->
  {Frame.expectations(world, frame) == Spec.allocated_expectations(world, frame) : Rendered.FrameExpectations}:
  Content.AllocatedWorld{+snapshot, +tree, +roots, +policies} = world
  %Equal.sym(+List<Rendered.ControlExposure>, Frame.exposure_forest([tree], Source.Exposed{}), Spec.allocated_exposure_forest([tree], Source.Exposed{}), allocated_exposure_forest([tree], Source.Exposed{})) :
    {Rendered.FrameExpectations{_} == Rendered.FrameExpectations{Spec.allocated_exposure_forest([tree], Source.Exposed{})} : Rendered.FrameExpectations}
  {==}


def observed_nodes(nodes: +List<SurfaceTypes.Node>, +elements: +List<Rendered.Element>) -> +List<Rendered.ResolvedNode>:
  match nodes:
    case Nil{}: Nil{}
    case Con{+node, +rest}:
      SurfaceTypes.Node{+key, +semantic, +label, +role, +meaning, +children} = node
      +identity = UIIdentity.encode(key)
      Rendered.ResolvedNode{node, identity, Spec.first_observed_element(elements, identity), observed_nodes(children, elements)} <> observed_nodes(rest, elements)

def resolved_diagnostics_fields(+nodes: +List<SurfaceTypes.Node>, +inherited: Bool, +elements: +List<Rendered.Element>, +viewport: Geometry.Rect, +controls: +List<Rendered.ControlExposure>) ->
  {Rendered.resolved_diagnostics(observed_nodes(nodes, elements), inherited, viewport, controls) == Spec.node_diagnostics(nodes, inherited, elements, viewport, controls) : +List<Rendered.Violation>}:
  match nodes:
    case Nil{}:
      {==}
    case Con{SurfaceTypes.Node{+key, +semantic, +label, +role, +meaning, +children}, +rest}:
      %Equal.sym(Bool, Rendered.persistent(role), Spec.persistent(role), persistent(role)) :
        {List.append(&2, Rendered.Violation, Rendered.node_geometry_with((Spec.first_observed_element(elements, (UIIdentity.encode(key)))), meaning, role, (UIIdentity.encode(key)), inherited || _, viewport, controls), List.append(&2, Rendered.Violation, Rendered.resolved_diagnostics(observed_nodes(children, elements), inherited || Rendered.persistent(role) || Rendered.code_in_view(role, (Spec.first_observed_element(elements, (UIIdentity.encode(key)))), viewport), viewport, controls), Rendered.resolved_diagnostics(observed_nodes(rest, elements), inherited, viewport, controls))) == List.append(&2, Rendered.Violation, Spec.node_geometry_with((Spec.first_observed_element(elements, (UIIdentity.encode(key)))), meaning, role, (UIIdentity.encode(key)), inherited || Spec.persistent(role), viewport, controls), List.append(&2, Rendered.Violation, Spec.node_diagnostics(children, inherited || Spec.persistent(role) || Spec.code_in_view(role, (Spec.first_observed_element(elements, (UIIdentity.encode(key)))), viewport), elements, viewport, controls), Spec.node_diagnostics(rest, inherited, elements, viewport, controls))) : +List<Rendered.Violation>}
      %Equal.sym(Bool, Rendered.persistent(role), Spec.persistent(role), persistent(role)) :
        {List.append(&2, Rendered.Violation, Rendered.node_geometry_with((Spec.first_observed_element(elements, (UIIdentity.encode(key)))), meaning, role, (UIIdentity.encode(key)), inherited || Spec.persistent(role), viewport, controls), List.append(&2, Rendered.Violation, Rendered.resolved_diagnostics(observed_nodes(children, elements), inherited || _ || Rendered.code_in_view(role, (Spec.first_observed_element(elements, (UIIdentity.encode(key)))), viewport), viewport, controls), Rendered.resolved_diagnostics(observed_nodes(rest, elements), inherited, viewport, controls))) == List.append(&2, Rendered.Violation, Spec.node_geometry_with((Spec.first_observed_element(elements, (UIIdentity.encode(key)))), meaning, role, (UIIdentity.encode(key)), inherited || Spec.persistent(role), viewport, controls), List.append(&2, Rendered.Violation, Spec.node_diagnostics(children, inherited || Spec.persistent(role) || Spec.code_in_view(role, (Spec.first_observed_element(elements, (UIIdentity.encode(key)))), viewport), elements, viewport, controls), Spec.node_diagnostics(rest, inherited, elements, viewport, controls))) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Rendered.resolved_diagnostics(observed_nodes(rest, elements), inherited, viewport, controls), Spec.node_diagnostics(rest, inherited, elements, viewport, controls), resolved_diagnostics_fields(rest, inherited, elements, viewport, controls)) :
        {List.append(&2, Rendered.Violation, Rendered.node_geometry_with((Spec.first_observed_element(elements, (UIIdentity.encode(key)))), meaning, role, (UIIdentity.encode(key)), inherited || Spec.persistent(role), viewport, controls), List.append(&2, Rendered.Violation, Rendered.resolved_diagnostics(observed_nodes(children, elements), inherited || Spec.persistent(role) || Rendered.code_in_view(role, (Spec.first_observed_element(elements, (UIIdentity.encode(key)))), viewport), viewport, controls), _)) == List.append(&2, Rendered.Violation, Spec.node_geometry_with((Spec.first_observed_element(elements, (UIIdentity.encode(key)))), meaning, role, (UIIdentity.encode(key)), inherited || Spec.persistent(role), viewport, controls), List.append(&2, Rendered.Violation, Spec.node_diagnostics(children, inherited || Spec.persistent(role) || Spec.code_in_view(role, (Spec.first_observed_element(elements, (UIIdentity.encode(key)))), viewport), elements, viewport, controls), Spec.node_diagnostics(rest, inherited, elements, viewport, controls))) : +List<Rendered.Violation>}
      %Equal.sym(Bool, Rendered.code_in_view(role, (Spec.first_observed_element(elements, (UIIdentity.encode(key)))), viewport), Spec.code_in_view(role, (Spec.first_observed_element(elements, (UIIdentity.encode(key)))), viewport), code_in_view(role, (Spec.first_observed_element(elements, (UIIdentity.encode(key)))), viewport)) :
        {List.append(&2, Rendered.Violation, Rendered.node_geometry_with((Spec.first_observed_element(elements, (UIIdentity.encode(key)))), meaning, role, (UIIdentity.encode(key)), inherited || Spec.persistent(role), viewport, controls), List.append(&2, Rendered.Violation, Rendered.resolved_diagnostics(observed_nodes(children, elements), inherited || Spec.persistent(role) || _, viewport, controls), Spec.node_diagnostics(rest, inherited, elements, viewport, controls))) == List.append(&2, Rendered.Violation, Spec.node_geometry_with((Spec.first_observed_element(elements, (UIIdentity.encode(key)))), meaning, role, (UIIdentity.encode(key)), inherited || Spec.persistent(role), viewport, controls), List.append(&2, Rendered.Violation, Spec.node_diagnostics(children, inherited || Spec.persistent(role) || Spec.code_in_view(role, (Spec.first_observed_element(elements, (UIIdentity.encode(key)))), viewport), elements, viewport, controls), Spec.node_diagnostics(rest, inherited, elements, viewport, controls))) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Rendered.node_geometry_with((Spec.first_observed_element(elements, (UIIdentity.encode(key)))), meaning, role, (UIIdentity.encode(key)), inherited || Spec.persistent(role), viewport, controls), Spec.node_geometry_with((Spec.first_observed_element(elements, (UIIdentity.encode(key)))), meaning, role, (UIIdentity.encode(key)), inherited || Spec.persistent(role), viewport, controls), node_geometry_with((Spec.first_observed_element(elements, (UIIdentity.encode(key)))), meaning, role, (UIIdentity.encode(key)), inherited || Spec.persistent(role), viewport, controls)) :
        {List.append(&2, Rendered.Violation, _, List.append(&2, Rendered.Violation, Rendered.resolved_diagnostics(observed_nodes(children, elements), inherited || Spec.persistent(role) || Spec.code_in_view(role, (Spec.first_observed_element(elements, (UIIdentity.encode(key)))), viewport), viewport, controls), Spec.node_diagnostics(rest, inherited, elements, viewport, controls))) == List.append(&2, Rendered.Violation, Spec.node_geometry_with((Spec.first_observed_element(elements, (UIIdentity.encode(key)))), meaning, role, (UIIdentity.encode(key)), inherited || Spec.persistent(role), viewport, controls), List.append(&2, Rendered.Violation, Spec.node_diagnostics(children, inherited || Spec.persistent(role) || Spec.code_in_view(role, (Spec.first_observed_element(elements, (UIIdentity.encode(key)))), viewport), elements, viewport, controls), Spec.node_diagnostics(rest, inherited, elements, viewport, controls))) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Rendered.resolved_diagnostics(observed_nodes(children, elements), inherited || Spec.persistent(role) || Spec.code_in_view(role, (Spec.first_observed_element(elements, (UIIdentity.encode(key)))), viewport), viewport, controls), Spec.node_diagnostics(children, inherited || Spec.persistent(role) || Spec.code_in_view(role, (Spec.first_observed_element(elements, (UIIdentity.encode(key)))), viewport), elements, viewport, controls), resolved_diagnostics_fields(children, inherited || Spec.persistent(role) || Spec.code_in_view(role, (Spec.first_observed_element(elements, (UIIdentity.encode(key)))), viewport), elements, viewport, controls)) :
        {List.append(&2, Rendered.Violation, Spec.node_geometry_with((Spec.first_observed_element(elements, (UIIdentity.encode(key)))), meaning, role, (UIIdentity.encode(key)), inherited || Spec.persistent(role), viewport, controls), List.append(&2, Rendered.Violation, _, Spec.node_diagnostics(rest, inherited, elements, viewport, controls))) == List.append(&2, Rendered.Violation, Spec.node_geometry_with((Spec.first_observed_element(elements, (UIIdentity.encode(key)))), meaning, role, (UIIdentity.encode(key)), inherited || Spec.persistent(role), viewport, controls), List.append(&2, Rendered.Violation, Spec.node_diagnostics(children, inherited || Spec.persistent(role) || Spec.code_in_view(role, (Spec.first_observed_element(elements, (UIIdentity.encode(key)))), viewport), elements, viewport, controls), Spec.node_diagnostics(rest, inherited, elements, viewport, controls))) : +List<Rendered.Violation>}
      {==}

def resolved_actionables_fields(+nodes: +List<SurfaceTypes.Node>, +elements: +List<Rendered.Element>) ->
  {Rendered.resolved_actionable_elements(observed_nodes(nodes, elements)) == Spec.actionable_elements(nodes, elements) : +List<Rendered.Element>}:
  match nodes:
    case Nil{}:
      {==}
    case Con{SurfaceTypes.Node{+key, +semantic, +label, +role, +meaning, +children}, +rest}:
      %Equal.sym(Bool, Rendered.interactive(meaning), Spec.interactive(meaning), interactive(meaning)) :
        {Rendered.include_element(_ && Rendered.required_enabled(meaning), Spec.first_observed_element(elements, (UIIdentity.encode(key))), List.append(&2, Rendered.Element, Rendered.resolved_actionable_elements(observed_nodes(children, elements)), Rendered.resolved_actionable_elements(observed_nodes(rest, elements)))) == Spec.include_element(Spec.interactive(meaning) && Spec.required_enabled(meaning), Spec.first_observed_element(elements, (UIIdentity.encode(key))), List.append(&2, Rendered.Element, Spec.actionable_elements(children, elements), Spec.actionable_elements(rest, elements))) : +List<Rendered.Element>}
      %Equal.sym(Bool, Rendered.required_enabled(meaning), Spec.required_enabled(meaning), required_enabled(meaning)) :
        {Rendered.include_element(Spec.interactive(meaning) && _, Spec.first_observed_element(elements, (UIIdentity.encode(key))), List.append(&2, Rendered.Element, Rendered.resolved_actionable_elements(observed_nodes(children, elements)), Rendered.resolved_actionable_elements(observed_nodes(rest, elements)))) == Spec.include_element(Spec.interactive(meaning) && Spec.required_enabled(meaning), Spec.first_observed_element(elements, (UIIdentity.encode(key))), List.append(&2, Rendered.Element, Spec.actionable_elements(children, elements), Spec.actionable_elements(rest, elements))) : +List<Rendered.Element>}
      %Equal.sym(+List<Rendered.Element>, Rendered.resolved_actionable_elements(observed_nodes(rest, elements)), Spec.actionable_elements(rest, elements), resolved_actionables_fields(rest, elements)) :
        {Rendered.include_element(Spec.interactive(meaning) && Spec.required_enabled(meaning), Spec.first_observed_element(elements, (UIIdentity.encode(key))), List.append(&2, Rendered.Element, Rendered.resolved_actionable_elements(observed_nodes(children, elements)), _)) == Spec.include_element(Spec.interactive(meaning) && Spec.required_enabled(meaning), Spec.first_observed_element(elements, (UIIdentity.encode(key))), List.append(&2, Rendered.Element, Spec.actionable_elements(children, elements), Spec.actionable_elements(rest, elements))) : +List<Rendered.Element>}
      %Equal.sym(+List<Rendered.Element>, Rendered.resolved_actionable_elements(observed_nodes(children, elements)), Spec.actionable_elements(children, elements), resolved_actionables_fields(children, elements)) :
        {Rendered.include_element(Spec.interactive(meaning) && Spec.required_enabled(meaning), Spec.first_observed_element(elements, (UIIdentity.encode(key))), List.append(&2, Rendered.Element, _, Spec.actionable_elements(rest, elements))) == Spec.include_element(Spec.interactive(meaning) && Spec.required_enabled(meaning), Spec.first_observed_element(elements, (UIIdentity.encode(key))), List.append(&2, Rendered.Element, Spec.actionable_elements(children, elements), Spec.actionable_elements(rest, elements))) : +List<Rendered.Element>}
      %Equal.sym(+List<Rendered.Element>, Rendered.include_element(Spec.interactive(meaning) && Spec.required_enabled(meaning), Spec.first_observed_element(elements, (UIIdentity.encode(key))), List.append(&2, Rendered.Element, Spec.actionable_elements(children, elements), Spec.actionable_elements(rest, elements))), Spec.include_element(Spec.interactive(meaning) && Spec.required_enabled(meaning), Spec.first_observed_element(elements, (UIIdentity.encode(key))), List.append(&2, Rendered.Element, Spec.actionable_elements(children, elements), Spec.actionable_elements(rest, elements))), include_element(Spec.interactive(meaning) && Spec.required_enabled(meaning), Spec.first_observed_element(elements, (UIIdentity.encode(key))), List.append(&2, Rendered.Element, Spec.actionable_elements(children, elements), Spec.actionable_elements(rest, elements)))) :
        {_ == Spec.include_element(Spec.interactive(meaning) && Spec.required_enabled(meaning), Spec.first_observed_element(elements, (UIIdentity.encode(key))), List.append(&2, Rendered.Element, Spec.actionable_elements(children, elements), Spec.actionable_elements(rest, elements))) : +List<Rendered.Element>}
      {==}

def resolved_tabs_fields(+nodes: +List<SurfaceTypes.Node>, +elements: +List<Rendered.Element>, +native_focus: +List<Rendered.NativeFocus>) ->
  {Rendered.resolved_tabs(observed_nodes(nodes, elements), native_focus) == Spec.expected_tabs(nodes, elements, native_focus) : +List<String>}:
  match nodes:
    case Nil{}:
      {==}
    case Con{SurfaceTypes.Node{+key, +semantic, +label, +role, +meaning, +children}, +rest}:
      %Equal.sym(Bool, Rendered.interactive(meaning), Spec.interactive(meaning), interactive(meaning)) :
        {Rendered.tab_entry(_ && Rendered.required_enabled(meaning) && Rendered.tab_stop(Spec.first_observed_element(elements, (UIIdentity.encode(key)))), (UIIdentity.encode(key)), List.append(&2, String, Rendered.content_tabs(meaning, native_focus, (UIIdentity.encode(key))), List.append(&2, String, Rendered.resolved_tabs(observed_nodes(children, elements), native_focus), Rendered.resolved_tabs(observed_nodes(rest, elements), native_focus)))) == Spec.tab_entry(Spec.interactive(meaning) && Spec.required_enabled(meaning) && Spec.tab_stop(Spec.first_observed_element(elements, (UIIdentity.encode(key)))), (UIIdentity.encode(key)), List.append(&2, String, Spec.content_tabs(meaning, native_focus, (UIIdentity.encode(key))), List.append(&2, String, Spec.expected_tabs(children, elements, native_focus), Spec.expected_tabs(rest, elements, native_focus)))) : +List<String>}
      %Equal.sym(Bool, Rendered.required_enabled(meaning), Spec.required_enabled(meaning), required_enabled(meaning)) :
        {Rendered.tab_entry(Spec.interactive(meaning) && _ && Rendered.tab_stop(Spec.first_observed_element(elements, (UIIdentity.encode(key)))), (UIIdentity.encode(key)), List.append(&2, String, Rendered.content_tabs(meaning, native_focus, (UIIdentity.encode(key))), List.append(&2, String, Rendered.resolved_tabs(observed_nodes(children, elements), native_focus), Rendered.resolved_tabs(observed_nodes(rest, elements), native_focus)))) == Spec.tab_entry(Spec.interactive(meaning) && Spec.required_enabled(meaning) && Spec.tab_stop(Spec.first_observed_element(elements, (UIIdentity.encode(key)))), (UIIdentity.encode(key)), List.append(&2, String, Spec.content_tabs(meaning, native_focus, (UIIdentity.encode(key))), List.append(&2, String, Spec.expected_tabs(children, elements, native_focus), Spec.expected_tabs(rest, elements, native_focus)))) : +List<String>}
      %Equal.sym(+List<String>, Rendered.resolved_tabs(observed_nodes(rest, elements), native_focus), Spec.expected_tabs(rest, elements, native_focus), resolved_tabs_fields(rest, elements, native_focus)) :
        {Rendered.tab_entry(Spec.interactive(meaning) && Spec.required_enabled(meaning) && Rendered.tab_stop(Spec.first_observed_element(elements, (UIIdentity.encode(key)))), (UIIdentity.encode(key)), List.append(&2, String, Rendered.content_tabs(meaning, native_focus, (UIIdentity.encode(key))), List.append(&2, String, Rendered.resolved_tabs(observed_nodes(children, elements), native_focus), _))) == Spec.tab_entry(Spec.interactive(meaning) && Spec.required_enabled(meaning) && Spec.tab_stop(Spec.first_observed_element(elements, (UIIdentity.encode(key)))), (UIIdentity.encode(key)), List.append(&2, String, Spec.content_tabs(meaning, native_focus, (UIIdentity.encode(key))), List.append(&2, String, Spec.expected_tabs(children, elements, native_focus), Spec.expected_tabs(rest, elements, native_focus)))) : +List<String>}
      %Equal.sym(+List<String>, Rendered.content_tabs(meaning, native_focus, (UIIdentity.encode(key))), Spec.content_tabs(meaning, native_focus, (UIIdentity.encode(key))), content_tabs(meaning, native_focus, (UIIdentity.encode(key)))) :
        {Rendered.tab_entry(Spec.interactive(meaning) && Spec.required_enabled(meaning) && Rendered.tab_stop(Spec.first_observed_element(elements, (UIIdentity.encode(key)))), (UIIdentity.encode(key)), List.append(&2, String, _, List.append(&2, String, Rendered.resolved_tabs(observed_nodes(children, elements), native_focus), Spec.expected_tabs(rest, elements, native_focus)))) == Spec.tab_entry(Spec.interactive(meaning) && Spec.required_enabled(meaning) && Spec.tab_stop(Spec.first_observed_element(elements, (UIIdentity.encode(key)))), (UIIdentity.encode(key)), List.append(&2, String, Spec.content_tabs(meaning, native_focus, (UIIdentity.encode(key))), List.append(&2, String, Spec.expected_tabs(children, elements, native_focus), Spec.expected_tabs(rest, elements, native_focus)))) : +List<String>}
      %Equal.sym(+List<String>, Rendered.resolved_tabs(observed_nodes(children, elements), native_focus), Spec.expected_tabs(children, elements, native_focus), resolved_tabs_fields(children, elements, native_focus)) :
        {Rendered.tab_entry(Spec.interactive(meaning) && Spec.required_enabled(meaning) && Rendered.tab_stop(Spec.first_observed_element(elements, (UIIdentity.encode(key)))), (UIIdentity.encode(key)), List.append(&2, String, Spec.content_tabs(meaning, native_focus, (UIIdentity.encode(key))), List.append(&2, String, _, Spec.expected_tabs(rest, elements, native_focus)))) == Spec.tab_entry(Spec.interactive(meaning) && Spec.required_enabled(meaning) && Spec.tab_stop(Spec.first_observed_element(elements, (UIIdentity.encode(key)))), (UIIdentity.encode(key)), List.append(&2, String, Spec.content_tabs(meaning, native_focus, (UIIdentity.encode(key))), List.append(&2, String, Spec.expected_tabs(children, elements, native_focus), Spec.expected_tabs(rest, elements, native_focus)))) : +List<String>}
      %Equal.sym(Bool, Rendered.tab_stop(Spec.first_observed_element(elements, (UIIdentity.encode(key)))), Spec.tab_stop(Spec.first_observed_element(elements, (UIIdentity.encode(key)))), tab_stop(Spec.first_observed_element(elements, (UIIdentity.encode(key))))) :
        {Rendered.tab_entry(Spec.interactive(meaning) && Spec.required_enabled(meaning) && _, (UIIdentity.encode(key)), List.append(&2, String, Spec.content_tabs(meaning, native_focus, (UIIdentity.encode(key))), List.append(&2, String, Spec.expected_tabs(children, elements, native_focus), Spec.expected_tabs(rest, elements, native_focus)))) == Spec.tab_entry(Spec.interactive(meaning) && Spec.required_enabled(meaning) && Spec.tab_stop(Spec.first_observed_element(elements, (UIIdentity.encode(key)))), (UIIdentity.encode(key)), List.append(&2, String, Spec.content_tabs(meaning, native_focus, (UIIdentity.encode(key))), List.append(&2, String, Spec.expected_tabs(children, elements, native_focus), Spec.expected_tabs(rest, elements, native_focus)))) : +List<String>}
      %Equal.sym(+List<String>, Rendered.tab_entry(Spec.interactive(meaning) && Spec.required_enabled(meaning) && Spec.tab_stop(Spec.first_observed_element(elements, (UIIdentity.encode(key)))), (UIIdentity.encode(key)), List.append(&2, String, Spec.content_tabs(meaning, native_focus, (UIIdentity.encode(key))), List.append(&2, String, Spec.expected_tabs(children, elements, native_focus), Spec.expected_tabs(rest, elements, native_focus)))), Spec.tab_entry(Spec.interactive(meaning) && Spec.required_enabled(meaning) && Spec.tab_stop(Spec.first_observed_element(elements, (UIIdentity.encode(key)))), (UIIdentity.encode(key)), List.append(&2, String, Spec.content_tabs(meaning, native_focus, (UIIdentity.encode(key))), List.append(&2, String, Spec.expected_tabs(children, elements, native_focus), Spec.expected_tabs(rest, elements, native_focus)))), tab_entry(Spec.interactive(meaning) && Spec.required_enabled(meaning) && Spec.tab_stop(Spec.first_observed_element(elements, (UIIdentity.encode(key)))), (UIIdentity.encode(key)), List.append(&2, String, Spec.content_tabs(meaning, native_focus, (UIIdentity.encode(key))), List.append(&2, String, Spec.expected_tabs(children, elements, native_focus), Spec.expected_tabs(rest, elements, native_focus))))) :
        {_ == Spec.tab_entry(Spec.interactive(meaning) && Spec.required_enabled(meaning) && Spec.tab_stop(Spec.first_observed_element(elements, (UIIdentity.encode(key)))), (UIIdentity.encode(key)), List.append(&2, String, Spec.content_tabs(meaning, native_focus, (UIIdentity.encode(key))), List.append(&2, String, Spec.expected_tabs(children, elements, native_focus), Spec.expected_tabs(rest, elements, native_focus)))) : +List<String>}
      {==}


def validation_terms(+resolved: +List<Rendered.ResolvedNode>, +active: +List<SurfaceTypes.Node>, frame: Rendered.Frame, +controls: +List<Rendered.ControlExposure>) -> +List<Rendered.Violation>:
  Rendered.Frame{+viewport, +elements, +focused, +tab_order, +native_focus} = frame
  List.append(&2, Rendered.Violation, Rendered.resolved_diagnostics(resolved, False{}, viewport, controls),
    List.append(&2, Rendered.Violation, Rendered.focus_checks(focused, active, elements, viewport, native_focus),
      List.append(&2, Rendered.Violation,
        Rendered.issue(Bool.not(Rendered.native_valid(native_focus, active, elements) && Rendered.same_order(Rendered.resolved_tabs(resolved, native_focus), tab_order)), Rendered.WrongTabOrder{}),
        Rendered.independent_targets(Rendered.resolved_actionable_elements(resolved)))))

def frame_elements(frame: Rendered.Frame) -> +List<Rendered.Element>:
  Rendered.Frame{+viewport, +elements, +focused, +tab_order, +native_focus} = frame
  elements

def validation_terms_requirement(+active: +List<SurfaceTypes.Node>, +frame: Rendered.Frame, +controls: +List<Rendered.ControlExposure>) ->
  {validation_terms(observed_nodes(active, frame_elements(frame)), active, frame, controls) == Spec.layout_diagnostics(active, frame, controls) : +List<Rendered.Violation>}:
  match frame:
    case Rendered.Frame{+viewport, +elements, +focused, +tab_order, +native_focus}:
      %Equal.sym(Bool, Rendered.native_valid(native_focus, active, elements), Spec.native_valid(native_focus, active, elements), native_valid(native_focus, active, elements)) :
        {List.append(&2, Rendered.Violation, Rendered.resolved_diagnostics(observed_nodes(active, elements), False{}, viewport, controls), List.append(&2, Rendered.Violation, Rendered.focus_checks(focused, active, elements, viewport, native_focus), List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(_ && Rendered.same_order(Rendered.resolved_tabs(observed_nodes(active, elements), native_focus), tab_order)), Rendered.WrongTabOrder{}), Rendered.independent_targets(Rendered.resolved_actionable_elements(observed_nodes(active, elements)))))) == List.append(&2, Rendered.Violation, Spec.node_diagnostics(active, False{}, elements, viewport, controls), List.append(&2, Rendered.Violation, Spec.focus_checks(focused, active, elements, viewport, native_focus), List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.native_valid(native_focus, active, elements) && Spec.same_order(Spec.expected_tabs(active, elements, native_focus), tab_order)), Rendered.WrongTabOrder{}), Spec.independent_targets(Spec.actionable_elements(active, elements))))) : +List<Rendered.Violation>}
      %Equal.sym(+List<String>, Rendered.resolved_tabs(observed_nodes(active, elements), native_focus), Spec.expected_tabs(active, elements, native_focus), resolved_tabs_fields(active, elements, native_focus)) :
        {List.append(&2, Rendered.Violation, Rendered.resolved_diagnostics(observed_nodes(active, elements), False{}, viewport, controls), List.append(&2, Rendered.Violation, Rendered.focus_checks(focused, active, elements, viewport, native_focus), List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Spec.native_valid(native_focus, active, elements) && Rendered.same_order(_, tab_order)), Rendered.WrongTabOrder{}), Rendered.independent_targets(Rendered.resolved_actionable_elements(observed_nodes(active, elements)))))) == List.append(&2, Rendered.Violation, Spec.node_diagnostics(active, False{}, elements, viewport, controls), List.append(&2, Rendered.Violation, Spec.focus_checks(focused, active, elements, viewport, native_focus), List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.native_valid(native_focus, active, elements) && Spec.same_order(Spec.expected_tabs(active, elements, native_focus), tab_order)), Rendered.WrongTabOrder{}), Spec.independent_targets(Spec.actionable_elements(active, elements))))) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Element>, Rendered.resolved_actionable_elements(observed_nodes(active, elements)), Spec.actionable_elements(active, elements), resolved_actionables_fields(active, elements)) :
        {List.append(&2, Rendered.Violation, Rendered.resolved_diagnostics(observed_nodes(active, elements), False{}, viewport, controls), List.append(&2, Rendered.Violation, Rendered.focus_checks(focused, active, elements, viewport, native_focus), List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Spec.native_valid(native_focus, active, elements) && Rendered.same_order(Spec.expected_tabs(active, elements, native_focus), tab_order)), Rendered.WrongTabOrder{}), Rendered.independent_targets(_)))) == List.append(&2, Rendered.Violation, Spec.node_diagnostics(active, False{}, elements, viewport, controls), List.append(&2, Rendered.Violation, Spec.focus_checks(focused, active, elements, viewport, native_focus), List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.native_valid(native_focus, active, elements) && Spec.same_order(Spec.expected_tabs(active, elements, native_focus), tab_order)), Rendered.WrongTabOrder{}), Spec.independent_targets(Spec.actionable_elements(active, elements))))) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Rendered.focus_checks(focused, active, elements, viewport, native_focus), Spec.focus_checks(focused, active, elements, viewport, native_focus), focus_checks(focused, active, elements, viewport, native_focus)) :
        {List.append(&2, Rendered.Violation, Rendered.resolved_diagnostics(observed_nodes(active, elements), False{}, viewport, controls), List.append(&2, Rendered.Violation, _, List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Spec.native_valid(native_focus, active, elements) && Rendered.same_order(Spec.expected_tabs(active, elements, native_focus), tab_order)), Rendered.WrongTabOrder{}), Rendered.independent_targets(Spec.actionable_elements(active, elements))))) == List.append(&2, Rendered.Violation, Spec.node_diagnostics(active, False{}, elements, viewport, controls), List.append(&2, Rendered.Violation, Spec.focus_checks(focused, active, elements, viewport, native_focus), List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.native_valid(native_focus, active, elements) && Spec.same_order(Spec.expected_tabs(active, elements, native_focus), tab_order)), Rendered.WrongTabOrder{}), Spec.independent_targets(Spec.actionable_elements(active, elements))))) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Rendered.independent_targets(Spec.actionable_elements(active, elements)), Spec.independent_targets(Spec.actionable_elements(active, elements)), independent_targets(Spec.actionable_elements(active, elements))) :
        {List.append(&2, Rendered.Violation, Rendered.resolved_diagnostics(observed_nodes(active, elements), False{}, viewport, controls), List.append(&2, Rendered.Violation, Spec.focus_checks(focused, active, elements, viewport, native_focus), List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Spec.native_valid(native_focus, active, elements) && Rendered.same_order(Spec.expected_tabs(active, elements, native_focus), tab_order)), Rendered.WrongTabOrder{}), _))) == List.append(&2, Rendered.Violation, Spec.node_diagnostics(active, False{}, elements, viewport, controls), List.append(&2, Rendered.Violation, Spec.focus_checks(focused, active, elements, viewport, native_focus), List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.native_valid(native_focus, active, elements) && Spec.same_order(Spec.expected_tabs(active, elements, native_focus), tab_order)), Rendered.WrongTabOrder{}), Spec.independent_targets(Spec.actionable_elements(active, elements))))) : +List<Rendered.Violation>}
      %Equal.sym(Bool, Rendered.same_order(Spec.expected_tabs(active, elements, native_focus), tab_order), Spec.same_order(Spec.expected_tabs(active, elements, native_focus), tab_order), same_order(Spec.expected_tabs(active, elements, native_focus), tab_order)) :
        {List.append(&2, Rendered.Violation, Rendered.resolved_diagnostics(observed_nodes(active, elements), False{}, viewport, controls), List.append(&2, Rendered.Violation, Spec.focus_checks(focused, active, elements, viewport, native_focus), List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Spec.native_valid(native_focus, active, elements) && _), Rendered.WrongTabOrder{}), Spec.independent_targets(Spec.actionable_elements(active, elements))))) == List.append(&2, Rendered.Violation, Spec.node_diagnostics(active, False{}, elements, viewport, controls), List.append(&2, Rendered.Violation, Spec.focus_checks(focused, active, elements, viewport, native_focus), List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.native_valid(native_focus, active, elements) && Spec.same_order(Spec.expected_tabs(active, elements, native_focus), tab_order)), Rendered.WrongTabOrder{}), Spec.independent_targets(Spec.actionable_elements(active, elements))))) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Rendered.resolved_diagnostics(observed_nodes(active, elements), False{}, viewport, controls), Spec.node_diagnostics(active, False{}, elements, viewport, controls), resolved_diagnostics_fields(active, False{}, elements, viewport, controls)) :
        {List.append(&2, Rendered.Violation, _, List.append(&2, Rendered.Violation, Spec.focus_checks(focused, active, elements, viewport, native_focus), List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Spec.native_valid(native_focus, active, elements) && Spec.same_order(Spec.expected_tabs(active, elements, native_focus), tab_order)), Rendered.WrongTabOrder{}), Spec.independent_targets(Spec.actionable_elements(active, elements))))) == List.append(&2, Rendered.Violation, Spec.node_diagnostics(active, False{}, elements, viewport, controls), List.append(&2, Rendered.Violation, Spec.focus_checks(focused, active, elements, viewport, native_focus), List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.native_valid(native_focus, active, elements) && Spec.same_order(Spec.expected_tabs(active, elements, native_focus), tab_order)), Rendered.WrongTabOrder{}), Spec.independent_targets(Spec.actionable_elements(active, elements))))) : +List<Rendered.Violation>}
      %Equal.sym(+List<Rendered.Violation>, Rendered.issue(Bool.not(Spec.native_valid(native_focus, active, elements) && Spec.same_order(Spec.expected_tabs(active, elements, native_focus), tab_order)), Rendered.WrongTabOrder{}), Spec.issue(Bool.not(Spec.native_valid(native_focus, active, elements) && Spec.same_order(Spec.expected_tabs(active, elements, native_focus), tab_order)), Rendered.WrongTabOrder{}), issue(Bool.not(Spec.native_valid(native_focus, active, elements) && Spec.same_order(Spec.expected_tabs(active, elements, native_focus), tab_order)), Rendered.WrongTabOrder{})) :
        {List.append(&2, Rendered.Violation, Spec.node_diagnostics(active, False{}, elements, viewport, controls), List.append(&2, Rendered.Violation, Spec.focus_checks(focused, active, elements, viewport, native_focus), List.append(&2, Rendered.Violation, _, Spec.independent_targets(Spec.actionable_elements(active, elements))))) == List.append(&2, Rendered.Violation, Spec.node_diagnostics(active, False{}, elements, viewport, controls), List.append(&2, Rendered.Violation, Spec.focus_checks(focused, active, elements, viewport, native_focus), List.append(&2, Rendered.Violation, Spec.issue(Bool.not(Spec.native_valid(native_focus, active, elements) && Spec.same_order(Spec.expected_tabs(active, elements, native_focus), tab_order)), Rendered.WrongTabOrder{}), Spec.independent_targets(Spec.actionable_elements(active, elements))))) : +List<Rendered.Violation>}
      {==}


def scoped_node(+found: Maybe<&2, SurfaceTypes.Node>) ->
  {InterfaceView.scope_node(found) == Spec.scoped_node(found) : +List<SurfaceTypes.Node>}:
  match found:
    case None{}: {==}
    case Some{node}: {==}

def scoped_nodes(+scope: Maybe<&2, String>, +base: +List<SurfaceTypes.Node>, +overlays: +List<SurfaceTypes.Node>) ->
  {InterfaceView.select_scope(scope, base, overlays) == Spec.scoped_nodes(scope, base, overlays) : +List<SurfaceTypes.Node>}:
  match scope:
    case None{}: {==}
    case Some{+key}:
      Equal.trans((+List<SurfaceTypes.Node>), InterfaceView.scope_node(InterfaceView.find_node(overlays, key)), InterfaceView.scope_node(Spec.find_node(overlays, key)), Spec.scoped_nodes(Some{key}, base, overlays),
        Equal.cong((Maybe<&2, SurfaceTypes.Node>), (+List<SurfaceTypes.Node>), InterfaceView.scope_node, InterfaceView.find_node(overlays, key), Spec.find_node(overlays, key), FenceEvidence.complete_node_lookup(overlays, key)),
        scoped_node(Spec.find_node(overlays, key)))

def active_nodes(+surface: SurfaceTypes.Surface) ->
  {InterfaceView.active_nodes(surface) == Spec.active_nodes(surface) : +List<SurfaceTypes.Node>}:
  SurfaceTypes.Surface{content, +base, +overlays, +scope} = surface
  scoped_nodes(scope, base, overlays)
