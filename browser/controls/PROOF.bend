import Base
import ../../features/board/filter.bend as Filter
import ../../interaction/IDENTITY.bend as UIIdentity
import ./CONTRACT.bend as Rule
import ../layout/SPACE.bend as Space
import ../appearance/TYPOGRAPHY.bend as T
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/STATE.bend as Core
import ../../interaction/INPUT.bend as User
import ../../interaction/presentation/MODEL.bend as View
import ../../interaction/services/MODEL.bend as Services
import ../../interaction/submission/FIELDS.bend as Forms
import ../../interaction/conversation/CODE.bend as Code
import ../../harness/DOMAIN.bend as Domain
import ./PROGRAM.bend as Controls
import ../appearance/DESIGN.bend as Design
import ../appearance/MODEL.bend as Appearance
import ../../interaction/conversation/MODEL.bend as Conversation
import ./MODEL.bend as Authored
import ../document/SOURCE.bend as Source
import ../reading/MODEL.bend as Reading
import ../layout/enclosure.bend as Enclosure
import ../layout/physical-space.bend as Model
import ../document/MODEL.bend as Doc
import ../layout/RENDERER.bend as Renderer
import ./authored-primitives.bend as Factory
import ./authored-containment-rules.bend as RuleAuthoredContainmentRules
import ./choice-rules.bend as RuleChoiceRules
import ./CONTROLS.bend as A
import ../appearance/ICONS.bend as I
import ../../features/board/MODEL.bend as Board
import ../../interaction/submission/field-options.bend as Fields
import ../layout/GEOMETRY.bend as SpatialModel
import ./control-content-laws.bend as RuleControlContentLaws
import ../layout/enclosure-laws.bend as EnclosureLaws
import ../../bendlib/logic-proof.bend as Logic
import ../../bendlib/stdlib.bend as Std
import ./dialog-content-rules.bend as RuleDialogContentRules
import ../editor/MODEL.bend as EditorLayout
import ./dialog-spatial-laws.bend as RuleDialogSpatialLaws
import ./form-input-laws.bend as RuleFormInputLaws
import ../../bendlib/equality-proof.bend as EqualityProof
import ../../interaction/session/MODEL.bend as E
import ./persistent-trigger-laws.bend as RulePersistentTriggerLaws
import ./SURFACES.bend as Surfaces
import ./surface-laws.bend as RuleSurfaceLaws
import ../../interaction/presentation/COMPOSITION.bend as Composition
import ./SHELL.bend as Shell
import ./authored-shell-rules.bend as RuleAuthoredShellRules
import ../layout/space-laws.bend as SpaceRules
import ../layout/physical-space-rules.bend as PhysicalRules
import ../layout/PROOF.bend as Order
import ../../bendlib/algebra-proof.bend as Alg
import ../../interaction/presentation/directory-entry-laws.bend as CoreDirectory
import ../runtime/SEMANTICS.bend as Browser
import ./directory-entry-laws.bend as RuleDirectoryEntryLaws
import ./context-control-laws.bend as RuleContextControlLaws
import ../../interaction/services/CONTEXT.bend as Context

def action_retains_binding(+key: UIIdentity.Key, +input: Core.Input, +availability: View.Availability,
  label: String, role: InterfaceView.Role, context: Controls.Context) ->
  {Rule.binding(Controls.make_action(key, input, availability, label, role, context)) ==
    InterfaceView.Activate{input, availability} : InterfaceView.Meaning}:
  match context:
    case Controls.Context{area, selection, code, appearance, access, open, layers, execution, source_family}: {==}

def panel_toggle_retains_binding(+key: UIIdentity.Key, expanded: Bool, +input: Core.Input, +availability: View.Availability,
  label: String, role: InterfaceView.Role, context: Controls.Context) ->
  {Rule.binding(Controls.make_panel_toggle(key, expanded, input, availability, label, role, context)) == InterfaceView.Activate{input, availability} : InterfaceView.Meaning}:
  match context:
    case Controls.Context{area, selection, code, appearance, access, open, layers, execution, source_family}: {==}

def choice_retains_binding(+key: UIIdentity.Key, kind: InterfaceView.ChoiceKind, icon: Maybe<&2, Filter.Classification>, selected: Bool, description: String, +input: Core.Input, +availability: View.Availability,
  label: String, role: InterfaceView.Role, context: Controls.Context) ->
  {Rule.binding(Controls.make_choice(key, kind, icon, selected, description, input, availability, label, role, context)) ==
    InterfaceView.Activate{input, availability} : InterfaceView.Meaning}:
  match context:
    case Controls.Context{area, selection, code, appearance, access, open, layers, execution, source_family}: {==}

def composer_action_retains_binding(+key: UIIdentity.Key, subject: View.ComposerSubject, +input: Core.Input,
  +availability: View.Availability, label: String, role: InterfaceView.Role, context: Controls.Context) ->
  {Rule.binding(Controls.make_composer_action(key, subject, input, availability, label, role, context)) ==
    InterfaceView.Activate{input, availability} : InterfaceView.Meaning}:
  match context:
    case Controls.Context{area, selection, code, appearance, access, open, layers, execution, source_family}: {==}

def presented_action_retains_binding(input: Core.Input, availability: View.Availability, name: String, projection: Controls.ActionPresentation, placement: Controls.Placement, help: Controls.Help, feedback: Controls.Feedback) ->
  {Rule.binding(Controls.presented_action(input, availability, name, projection, placement, help, feedback)) == InterfaceView.Activate{input, availability} : InterfaceView.Meaning}:
  match projection:
    case Controls.ActionPresentation{face, behavior, geometry}: {==}

def source_action_retains_binding(area: Controls.Area, family: Controls.SourceFamily, +value: Controls.Representation) ->
  {Rule.binding(Controls.source_action(area, family, value)) == Rule.binding(value) : InterfaceView.Meaning}:
  match value:
    case Controls.Action{+input, availability, +name, face, behavior, geometry, placement, help, feedback}:
      presented_action_retains_binding(input, availability, name, Controls.source_presentation(area, family, input, name, face, behavior, geometry), placement, help, feedback)
    case Controls.NoControl{}: {==}
    case Controls.Input{meaning, name, widget, label, availability}: {==}
    case Controls.Movable{destinations, face, name, handle, geometry, help}: {==}

def represented_action_retains_binding(+key: UIIdentity.Key, +input: Core.Input, +availability: View.Availability,
  +label: String, +role: InterfaceView.Role, +context: Controls.Context) ->
  {Rule.binding(Controls.represent_action(key, input, availability, label, role, context)) == InterfaceView.Activate{input, availability} : InterfaceView.Meaning}:
  Controls.Context{+area, selection, code, appearance, access, open, layers, execution, +family} = context
  Equal.trans(InterfaceView.Meaning,
    Rule.binding(Controls.represent_action(key, input, availability, label, role, context)),
    Rule.binding(Controls.make_action(key, input, availability, label, role, context)), InterfaceView.Activate{input, availability},
    source_action_retains_binding(area, family, Controls.make_action(key, input, availability, label, role, context)),
    action_retains_binding(key, input, availability, label, role, context))

def representation_retains_binding(+key: UIIdentity.Key, +meaning: InterfaceView.Meaning, label: String,
  role: InterfaceView.Role, context: Controls.Context) ->
  {Rule.binding(Controls.represent(key, meaning, label, role, context)) == Rule.source_binding(meaning) : InterfaceView.Meaning}:
  match meaning:
    case InterfaceView.ComposerAction{subject, input, availability}: composer_action_retains_binding(key, subject, input, availability, label, role, context)
    case InterfaceView.Activate{input, availability}: represented_action_retains_binding(key, input, availability, label, role, context)
    case InterfaceView.PanelToggle{expanded, input, availability}: panel_toggle_retains_binding(key, expanded, input, availability, label, role, context)
    case InterfaceView.Choice{kind, icon, selected, description, input, availability}: choice_retains_binding(key, kind, icon, selected, description, input, availability, label, role, context)
    case InterfaceView.ProjectGroup{project, selected, expanded}: {==}
    case InterfaceView.TaskRow{task, status, selected}: {==}
    case InterfaceView.ProjectChooser{selected}: {==}
    case InterfaceView.DirectoryRow{path, primary}: {==}
    case InterfaceView.ContextSummary{observation}: {==}
    case InterfaceView.ChoiceGroup{}: {==}

    case InterfaceView.Edit{editor, field, entry, value, choices}:
      match entry:
        case Forms.DisplayOnly{}: {==}
        case Forms.SingleLine{}: {==}
        case Forms.Multiline{}: {==}
        case Forms.Choice{}: {==}
        case Forms.MultipleChoices{}: {==}
        case Forms.PositiveInteger{}: {==}
        case Forms.DirectoryCollection{}: {==}
        case Forms.FileCollection{}: {==}
    case InterfaceView.SearchChoices{query}: {==}
    case InterfaceView.EnterCredential{entered}: {==}
    case InterfaceView.BoardSearch{filter}: {==}
    case InterfaceView.ReceiveFile{editor, enabled}: {==}
    case InterfaceView.EnterDirectory{editor, text}: {==}
    case InterfaceView.DirectoryBrowserLocation{value}: {==}
    case InterfaceView.BoardProfile{automatic, selected, choices, enabled}: {==}
    case InterfaceView.CardContent{face}: {==}
    case InterfaceView.MovableCard{destinations, face}: {==}
    case InterfaceView.BoardLane{stage, count}: {==}
    case InterfaceView.CardArchive{count}: {==}
    case InterfaceView.BoardGroup{grouping}: {==}
    case InterfaceView.PageRegion{region, position}: {==}
    case InterfaceView.Region{}: {==}
    case InterfaceView.LayerRegion{dismiss, outside, escape}: {==}
    case InterfaceView.ReadOnly{text}: {==}
    case InterfaceView.Fact{value}: {==}
    case InterfaceView.RichText{source, value}: {==}
    case InterfaceView.TaskFacts{details}: {==}
    case InterfaceView.CodeFacts{view}: {==}
    case InterfaceView.ActivityContent{expanded, audit}: {==}
    case InterfaceView.PageContext{conversation}: {==}

def nodes_retain_bindings(values: +List<InterfaceView.Node>, +context: Controls.Context, +typography: T.Presentation, +in_main: Bool, +start: Bool) ->
  {Rule.presented_nodes(Appearance.nodes_at(values, context, typography, in_main, start)) == Rule.source_nodes(values) : +List<Rule.BoundNode>}:
  match values:
    case Nil{}: {==}
    case Con{InterfaceView.Node{+key, +semantic, +label, +role, +meaning, +children}, +rest}:
      +local = Controls.enter(InterfaceView.Node{key, semantic, label, role, meaning, children}, context)
      +inside = Appearance.enters_main(role, in_main)
      +inherited_text = Appearance.information_role(role, meaning, typography, inside, start)
      +child_text = Design.style_text(Appearance.prepared_style(key, semantic, role, meaning, local,
        Controls.represent(key, meaning, label, role, local), inherited_text))
      +meaning_step = Equal.cong(InterfaceView.Meaning, +List<Rule.BoundNode>,
        (bound => Con{Rule.BoundNode{key, bound, Rule.presented_nodes(Appearance.nodes_at(children, local, child_text, inside, start))},
          Rule.presented_nodes(Appearance.nodes_at(rest, context, typography, in_main, start))}),
        Rule.binding(Controls.represent(key, meaning, label, role, local)), Rule.source_binding(meaning),
        representation_retains_binding(key, meaning, label, role, local))
      +child_step = Equal.cong(+List<Rule.BoundNode>, +List<Rule.BoundNode>,
        (bound_children => Con{Rule.BoundNode{key, Rule.source_binding(meaning), bound_children},
          Rule.presented_nodes(Appearance.nodes_at(rest, context, typography, in_main, start))}),
        Rule.presented_nodes(Appearance.nodes_at(children, local, child_text, inside, start)), Rule.source_nodes(children),
        nodes_retain_bindings(children, local, child_text, inside, start))
      +rest_step = Equal.cong(+List<Rule.BoundNode>, +List<Rule.BoundNode>,
        (bound_rest => Con{Rule.BoundNode{key, Rule.source_binding(meaning), Rule.source_nodes(children)}, bound_rest}),
        Rule.presented_nodes(Appearance.nodes_at(rest, context, typography, in_main, start)), Rule.source_nodes(rest),
        nodes_retain_bindings(rest, context, typography, in_main, start))
      +head_steps = Equal.trans(+List<Rule.BoundNode>,
        Con{Rule.BoundNode{key, Rule.binding(Controls.represent(key, meaning, label, role, local)),
          Rule.presented_nodes(Appearance.nodes_at(children, local, child_text, inside, start))}, Rule.presented_nodes(Appearance.nodes_at(rest, context, typography, in_main, start))},
        Con{Rule.BoundNode{key, Rule.source_binding(meaning), Rule.presented_nodes(Appearance.nodes_at(children, local, child_text, inside, start))},
          Rule.presented_nodes(Appearance.nodes_at(rest, context, typography, in_main, start))},
        Con{Rule.BoundNode{key, Rule.source_binding(meaning), Rule.source_nodes(children)},
          Rule.presented_nodes(Appearance.nodes_at(rest, context, typography, in_main, start))}, meaning_step, child_step)
      +steps = Equal.trans(+List<Rule.BoundNode>,
        Con{Rule.BoundNode{key, Rule.binding(Controls.represent(key, meaning, label, role, local)),
          Rule.presented_nodes(Appearance.nodes_at(children, local, child_text, inside, start))}, Rule.presented_nodes(Appearance.nodes_at(rest, context, typography, in_main, start))},
        Con{Rule.BoundNode{key, Rule.source_binding(meaning), Rule.source_nodes(children)},
          Rule.presented_nodes(Appearance.nodes_at(rest, context, typography, in_main, start))},
        Con{Rule.BoundNode{key, Rule.source_binding(meaning), Rule.source_nodes(children)}, Rule.source_nodes(rest)}, head_steps, rest_step)
      Equal.trans(+List<Rule.BoundNode>,
        Rule.presented_nodes(Appearance.nodes_at(Con{InterfaceView.Node{key, semantic, label, role, meaning, children}, rest}, context, typography, in_main, start)),
        Con{Rule.BoundNode{key, Rule.binding(Controls.represent(key, meaning, label, role, local)),
          Rule.presented_nodes(Appearance.nodes_at(children, local, child_text, inside, start))}, Rule.presented_nodes(Appearance.nodes_at(rest, context, typography, in_main, start))},
        Con{Rule.BoundNode{key, Rule.source_binding(meaning), Rule.source_nodes(children)}, Rule.source_nodes(rest)}, {==}, steps)

def fields_retain_bindings(content: Core.Scene, +base: +List<InterfaceView.Node>, +overlays: +List<InterfaceView.Node>,
  +context: Controls.Context, system_dark: Bool, active_scope: Maybe<&2, String>, +scale: T.Scale) ->
  {Rule.visual_bindings(Appearance.present_fields(content, base, overlays, context, system_dark, active_scope, scale)) ==
    Rule.Bindings{Rule.source_nodes(base), Rule.source_nodes(overlays)} : Rule.Bindings}:
  match content:
    case Core.Scene{view, settings, transfers, preview, code, directory_picker}:
      match settings:
        case Core.Settings{open, access, entered, appearance, open_action, close_action, connect}:
          +base_step = Equal.cong(+List<Rule.BoundNode>, Rule.Bindings,
            (bound_base => Rule.Bindings{bound_base, Rule.presented_nodes(Appearance.nodes_at(overlays, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, False{}))}),
            Rule.presented_nodes(Appearance.nodes_at(base, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, Appearance.start_page(content))), Rule.source_nodes(base), nodes_retain_bindings(base, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, Appearance.start_page(content)))
          +overlay_step = Equal.cong(+List<Rule.BoundNode>, Rule.Bindings,
            (bound_overlays => Rule.Bindings{Rule.source_nodes(base), bound_overlays}),
            Rule.presented_nodes(Appearance.nodes_at(overlays, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, False{})), Rule.source_nodes(overlays), nodes_retain_bindings(overlays, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, False{}))
          Equal.trans(Rule.Bindings,
            Rule.Bindings{Rule.presented_nodes(Appearance.nodes_at(base, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, Appearance.start_page(content))), Rule.presented_nodes(Appearance.nodes_at(overlays, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, False{}))},
            Rule.Bindings{Rule.source_nodes(base), Rule.presented_nodes(Appearance.nodes_at(overlays, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, False{}))},
            Rule.Bindings{Rule.source_nodes(base), Rule.source_nodes(overlays)}, base_step, overlay_step)

def present_retains_bindings(surface: InterfaceView.Surface, system_dark: Bool, +scale: T.Scale) ->
  {Rule.visual_bindings(Appearance.present(surface, system_dark, scale)) == Rule.surface_bindings(surface) : Rule.Bindings}:
  match surface:
    case InterfaceView.Surface{+content, base, overlays, active_scope}:
      fields_retain_bindings(content, base, overlays, Controls.initial(content), system_dark, active_scope, scale)

def message_uses_arrow(+key: UIIdentity.Key, task: Nat, +availability: View.Availability,
  +label: String, role: InterfaceView.Role, selection: Controls.Selection, code: Maybe<&2, Code.Scene>,
  appearance: Services.Appearance, access: Services.Access, open: Bool, layers: +List<View.Layer>) -> Rule.message_uses_arrow_law(key, task, availability, label, role, selection, code, appearance, access, open, layers):
  match availability:
    case View.Available{}: {==}
    case View.NeedsDirectoryObservation{}: {==}
    case View.Unavailable{reason}: {==}

def creation_uses_arrow(+key: UIIdentity.Key, +availability: View.Availability,
  +label: String, role: InterfaceView.Role, selection: Controls.Selection, code: Maybe<&2, Code.Scene>,
  appearance: Services.Appearance, access: Services.Access, open: Bool, layers: +List<View.Layer>) -> Rule.creation_uses_arrow_law(key, availability, label, role, selection, code, appearance, access, open, layers):
  match availability:
    case View.Available{}: {==}
    case View.NeedsDirectoryObservation{}: {==}
    case View.Unavailable{reason}: {==}

def named_face_has_text(icon: Maybe<&2, Controls.Icon>, +label: String) ->
  {Rule.menu_text(Controls.named_face(icon, label, False{})) == Some{label} : Maybe<&2, String>}:
  match icon:
    case None{}: {==}
    case Some{icon}: {==}

def menu_preserves_labels(+purpose: Controls.Purpose, +label: String) ->
  {Rule.menu_text(Controls.face_for(purpose, label, Controls.MenuArea{})) == Rule.required_menu_text(purpose, label) : Maybe<&2, String>}:
  match purpose:
    case Controls.Dismiss{}: {==}
    case Controls.SelectedOption{checked}: {==}
    case Controls.ChooseValue{expanded}: {==}
    case Controls.ShowActivity{expanded}: {==}
    case Controls.MessageSubmission{}: named_face_has_text(Controls.purpose_icon(Controls.MessageSubmission{}), label)
    case Controls.NamedAction{}: named_face_has_text(Controls.purpose_icon(Controls.NamedAction{}), label)
    case Controls.CreateItem{}: named_face_has_text(Controls.purpose_icon(Controls.CreateItem{}), label)
    case Controls.EditItem{}: named_face_has_text(Controls.purpose_icon(Controls.EditItem{}), label)
    case Controls.ProjectTaskCreation{}: named_face_has_text(Controls.purpose_icon(Controls.ProjectTaskCreation{}), label)
    case Controls.NavigateTo{icon}: named_face_has_text(Controls.purpose_icon(Controls.NavigateTo{icon}), label)
    case Controls.MoreActions{expanded}: named_face_has_text(Controls.purpose_icon(Controls.MoreActions{expanded}), label)
    case Controls.OpenPanel{icon, menu, expanded}: named_face_has_text(Controls.purpose_icon(Controls.OpenPanel{icon, menu, expanded}), label)
    case Controls.WorkspacePicker{expanded}: named_face_has_text(Controls.purpose_icon(Controls.WorkspacePicker{expanded}), label)
    case Controls.StopExecution{}: named_face_has_text(Controls.purpose_icon(Controls.StopExecution{}), label)
    case Controls.PauseExecution{}: named_face_has_text(Controls.purpose_icon(Controls.PauseExecution{}), label)
    case Controls.ResumeExecution{}: named_face_has_text(Controls.purpose_icon(Controls.ResumeExecution{}), label)
    case Controls.InterruptExecution{}: named_face_has_text(Controls.purpose_icon(Controls.InterruptExecution{}), label)
    case Controls.AbortOperation{}: named_face_has_text(Controls.purpose_icon(Controls.AbortOperation{}), label)
    case Controls.ApprovalDecision{allow}: named_face_has_text(Controls.purpose_icon(Controls.ApprovalDecision{allow}), label)
    case Controls.DeleteItem{}: named_face_has_text(Controls.purpose_icon(Controls.DeleteItem{}), label)
    case Controls.ArchiveItem{archived}: named_face_has_text(Controls.purpose_icon(Controls.ArchiveItem{archived}), label)
    case Controls.PinItem{pinned}: named_face_has_text(Controls.purpose_icon(Controls.PinItem{pinned}), label)
    case Controls.AutomaticScheduling{enabled}: named_face_has_text(Controls.purpose_icon(Controls.AutomaticScheduling{enabled}), label)
    case Controls.Regenerate{}: named_face_has_text(Controls.purpose_icon(Controls.Regenerate{}), label)
    case Controls.CopyCode{state}: named_face_has_text(Controls.purpose_icon(Controls.CopyCode{state}), label)
    case Controls.WrapCode{enabled}: named_face_has_text(Controls.purpose_icon(Controls.WrapCode{enabled}), label)
    case Controls.Latest{}: named_face_has_text(Controls.purpose_icon(Controls.Latest{}), label)
    case Controls.ToggleNavigation{expanded}: named_face_has_text(Controls.purpose_icon(Controls.ToggleNavigation{expanded}), label)
    case Controls.ResetDefaults{}: named_face_has_text(Controls.purpose_icon(Controls.ResetDefaults{}), label)
    case Controls.RemoveValue{}: named_face_has_text(Controls.purpose_icon(Controls.RemoveValue{}), label)
    case Controls.RetryTransfer{}: named_face_has_text(Controls.purpose_icon(Controls.RetryTransfer{}), label)
    case Controls.PreviewFile{}: named_face_has_text(Controls.purpose_icon(Controls.PreviewFile{}), label)
    case Controls.DownloadFile{}: named_face_has_text(Controls.purpose_icon(Controls.DownloadFile{}), label)
    case Controls.Connect{access}: named_face_has_text(Controls.purpose_icon(Controls.Connect{access}), label)

def copy_keeps_space(state: Code.CopyState) ->
  {Controls.geometry_for(Controls.CopyCode{state}, Controls.face_for(Controls.CopyCode{state}, "Copy code", Controls.CodeArea{}), Controls.CodeArea{}) ==
    Controls.Geometry{Space.fixed_demand(32n, 32n), 16n, 8n, 0n} : Controls.Geometry}:
  match state:
    case Code.CopyIdle{}: {==}
    case Code.CopyPending{ticket}: {==}
    case Code.CopySucceeded{ticket}: {==}
    case Code.CopyFailed{ticket}: {==}



def directory_removal_uses_cross(+parent: UIIdentity.Key, +editor: User.Editor, +path: String,
  primary: Maybe<&2, String>, state: Core.State, context: Controls.Context) ->
  {Rule.workspace_removal_faces(View.workspace_controls(Domain.Workspace{[path], primary}, editor, None{}),
    parent, state, context) == [Some{Controls.IconFace{Controls.CloseCross{}}}] : +List<Maybe<&2, Controls.Face>>}:
  match state context:
    case Core.State{application, services} Controls.Context{area, selection, code, appearance, access, open, layers, execution, source_family}: {==}

def approval_keeps_label(key: UIIdentity.Key, task: Nat, operation: Nat, allow: Bool, reason: String,
  availability: View.Availability, +label: String, role: InterfaceView.Role, selection: Controls.Selection,
  code: Maybe<&2, Code.Scene>, appearance: Services.Appearance, access: Services.Access, open: Bool,
  layers: +List<View.Layer>) -> Rule.approval_keeps_label_law(key, task, operation, allow, reason, availability, label, role, selection, code, appearance, access, open, layers):
  match allow:
    case True{}: {==}
    case False{}: {==}

def Rule.evidence():
  Rule.Requirements{
    +scale => surface => dark => present_retains_bindings(surface, dark, scale),
    key => task => availability => label => role => selection => code => appearance => access => open => layers =>
      message_uses_arrow(key, task, availability, label, role, selection, code, appearance, access, open, layers),
    key => availability => label => role => selection => code => appearance => access => open => layers =>
      creation_uses_arrow(key, availability, label, role, selection, code, appearance, access, open, layers),
    purpose => label => menu_preserves_labels(purpose, label),
    state => copy_keeps_space(state),
    label => checked => {==},
    +key => editor => +profile => reasoning => +current => +label => role => code => appearance => access => open => layers => {==},
    +key => task => +delivery => +current => +label => role => code => appearance => access => open => layers => {==},
    key => task => operation => allow => reason => availability => label => role => selection => code => appearance => access => open => layers =>
      approval_keeps_label(key, task, operation, allow, reason, availability, label, role, selection, code, appearance, access, open, layers),
    icon => availability => feedback => label => {==},
    value => {==},
    expanded => label => {==},
    expanded => +label => {==},
    parent => editor => path => primary => state => context => directory_removal_uses_cross(parent, editor, path, primary, state, context),
    choices => key => editor => field => value => label => role => context => {==},
    choices => key => editor => field => value => label => role => context => {==}
  }

def Rule.card_content_source_family(key, semantic, label, role, face, children, inherited): {==}
def Rule.card_content_has_no_input(key, face, label, role, context): {==}

def reading_encoding(+task: Nat, +generation: Nat, +part: Reading.Part) -> RuleAuthoredContainmentRules.reading_encoding(task, generation, part):
  {==}

def encoded_sequence(+attribute: Source.Attribute, +rest: +List<Source.Attribute>) -> RuleAuthoredContainmentRules.encoded_sequence(attribute, rest):
  {==}

def page_context(+previous: Maybe<&2, Reading.Context>, +task: Nat, +generation: Nat) -> RuleAuthoredContainmentRules.page_context(previous, task, generation):
  {==}

def cleared_context(+previous: Maybe<&2, Reading.Context>) -> RuleAuthoredContainmentRules.cleared_context(previous):
  {==}

def scoped_node(+key: UIIdentity.Key, +semantic: String, +label: String, +role: InterfaceView.Role, +meaning: InterfaceView.Meaning, +visual: Design.Style, +control: Controls.Representation, +children: +List<Design.Node>, +rest: +List<Design.Node>, +parameters: Design.LayoutParameters, +context: Maybe<&2, Reading.Context>) -> RuleAuthoredContainmentRules.scoped_node(key, semantic, label, role, meaning, visual, control, children, rest, parameters, context):
  {==}

def partition_frame(+key: UIIdentity.Key, +tag: Source.BoxTag, +visual: Design.Style, +direction: Model.Direction, +part: Enclosure.Part, +arrangement: Enclosure.Arrangement, +content: +List<Source.Node>) -> RuleAuthoredContainmentRules.partition_frame(key, tag, visual, direction, part, arrangement, content):
  {==}

def dialog_construction(+key: UIIdentity.Key, +label: String, +meaning: InterfaceView.Meaning, +visual: Design.Style, +control: Controls.Representation, +children: +List<Authored.Child>, +parameters: Design.LayoutParameters) -> RuleAuthoredContainmentRules.dialog_construction(key, label, meaning, visual, control, children, parameters):
  {==}

def timeline_root(+context: Reading.Context, +key: UIIdentity.Key, +tag: Source.BoxTag, +style: Source.Style, +attributes: +List<Source.Attribute>, +children: +List<Source.Node>, +visual: Design.Style) -> RuleAuthoredContainmentRules.timeline_root(context, key, tag, style, attributes, children, visual):
  {==}

def composer_root(+context: Reading.Context, +key: UIIdentity.Key, +tag: Source.BoxTag, +style: Source.Style, +attributes: +List<Source.Attribute>, +children: +List<Source.Node>, +visual: Design.Style) -> RuleAuthoredContainmentRules.composer_root(context, key, tag, style, attributes, children, visual):
  {==}

def bound_construction(+children: +List<Authored.Child>, +key: UIIdentity.Key, +semantic: String, +label: String, +role: InterfaceView.Role, +meaning: InterfaceView.Meaning, +visual: Design.Style, +control: Controls.Representation, +parameters: Design.LayoutParameters, +context: Maybe<&2, Reading.Context>) -> RuleAuthoredContainmentRules.bound_construction(children, key, semantic, label, role, meaning, visual, control, parameters, context):
  {==}

def body_scroll_allocation(+value: Source.Style) ->
  {RuleAuthoredContainmentRules.body_scroll_allocation(Authored.dialog_partition_style(Enclosure.Body{}, value)) == True{} : Bool}:
  Source.Style{layout, font, chrome, states} = value
  Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position} = layout
  {==}

def native_attribute_owner(+key: UIIdentity.Key, +previous: String) -> RuleAuthoredContainmentRules.native_attribute_owner(key, previous):
  {==}

def native_attribute_choice(+owned: Bool, +key: UIIdentity.Key, +name: String, +value: String) -> RuleAuthoredContainmentRules.native_attribute_choice(owned, key, name, value):
  match owned:
    case True{}: {==}
    case False{}: {==}

def native_attribute_data(+key: UIIdentity.Key, +name: String, +value: String) -> RuleAuthoredContainmentRules.native_attribute_data(key, name, value):
  native_attribute_choice(String.eq(name, "native-key"), key, name, value)

def native_attribute_other(+key: UIIdentity.Key, +attribute: Source.Attribute) -> RuleAuthoredContainmentRules.native_attribute_other(key, attribute):
  match attribute:
    case Source.DataAttribute{name, value}: True{}
    case Source.ReadingAttribute{binding}: {==}
    case Source.EditorBindingAttribute{owner}: {==}
    case Source.AriaAttribute{name, value}: {==}
    case Source.RoleAttribute{value}: {==}
    case Source.TitleAttribute{value}: {==}
    case Source.TabIndexAttribute{value}: {==}
    case Source.ValueAttribute{value}: {==}
    case Source.CheckedAttribute{}: {==}
    case Source.OpenAttribute{}: {==}
    case Source.DraggableAttribute{value}: {==}
    case Source.InertAttribute{}: {==}

def native_attributes_nil(+key: UIIdentity.Key) -> RuleAuthoredContainmentRules.native_attributes_nil(key):
  {==}

def native_attributes_cons(+key: UIIdentity.Key, +attribute: Source.Attribute, +rest: +List<Source.Attribute>) -> RuleAuthoredContainmentRules.native_attributes_cons(key, attribute, rest):
  {==}

def native_decoration(+node: Source.Node, +extra: +List<Source.Attribute>) -> RuleAuthoredContainmentRules.native_decoration(node, extra):
  match node:
    case Source.Box{key, tag, style, attrs, children}: {==}
    case Source.Control{key, tag, style, attrs, name, enabled, first, remaining, children}: {==}
    case Source.Field{key, kind, style, attrs, value, placeholder, options, policy, name, enabled, first, remaining}: {==}
    case Source.Text{key, value, font, wrapping}: {==}
    case Source.Glyph{key, drawing, style}: {==}
    case Source.RichText{key, style, content, attachments, native_owner}: {==}
    case Source.NativeAttachment{key, target, attrs, style, children}: {==}

def RuleAuthoredContainmentRules.evidence():
  RuleAuthoredContainmentRules.Requirements{native_attribute_owner, native_attribute_data, native_attribute_other, native_attributes_nil, native_attributes_cons, native_decoration, body_scroll_allocation}

def classification_meaning(+category: Filter.Classification) -> RuleChoiceRules.GlyphMeaning<category, Controls.classification_glyph(category)>:
  match category:
    case Filter.TaskStage{stage}: RuleChoiceRules.TaskStage{stage, {==}, {==}}
    case Filter.TaskPriority{priority}: RuleChoiceRules.TaskPriority{priority, {==}, {==}}
    case Filter.Project{}: RuleChoiceRules.Project{{==}, {==}}
    case Filter.Person{}: RuleChoiceRules.Person{{==}, {==}}
    case Filter.Agent{}: RuleChoiceRules.Agent{{==}, {==}}
    case Filter.Label{}: RuleChoiceRules.Label{{==}, {==}}
    case Filter.Updated{}: RuleChoiceRules.Updated{{==}, {==}}

def selection_roles(+kind: InterfaceView.ChoiceKind, +area: Controls.Area, +selected: Bool) ->
  {A.behavior(Controls.choice_behavior(kind, area, selected)) == [Source.RoleAttribute{RuleChoiceRules.selection_role(kind, area)}, Source.AriaAttribute{"checked", Fields.boolean(selected)}] : +List<Source.Attribute>}:
  match kind area:
    case InterfaceView.SingleChoice{} Controls.MenuArea{}: {==}
    case InterfaceView.SingleChoice{} Controls.PageArea{}: {==}
    case InterfaceView.SingleChoice{} Controls.NavigationArea{}: {==}
    case InterfaceView.SingleChoice{} Controls.ComposerArea{}: {==}
    case InterfaceView.SingleChoice{} Controls.ToolbarArea{}: {==}
    case InterfaceView.SingleChoice{} Controls.CodeArea{}: {==}
    case InterfaceView.SingleChoice{} Controls.ActivityArea{}: {==}
    case InterfaceView.SingleChoice{} Controls.ApprovalArea{}: {==}
    case InterfaceView.SingleChoice{} Controls.DialogArea{}: {==}
    case InterfaceView.SingleChoice{} Controls.CollectionArea{}: {==}
    case InterfaceView.SingleChoice{} Controls.CardArea{}: {==}
    case InterfaceView.SingleChoice{} Controls.BoardViewArea{}: {==}
    case InterfaceView.SingleChoice{} Controls.BoardLaneArea{}: {==}
    case InterfaceView.MultipleChoice{} Controls.MenuArea{}: {==}
    case InterfaceView.MultipleChoice{} Controls.PageArea{}: {==}
    case InterfaceView.MultipleChoice{} Controls.NavigationArea{}: {==}
    case InterfaceView.MultipleChoice{} Controls.ComposerArea{}: {==}
    case InterfaceView.MultipleChoice{} Controls.ToolbarArea{}: {==}
    case InterfaceView.MultipleChoice{} Controls.CodeArea{}: {==}
    case InterfaceView.MultipleChoice{} Controls.ActivityArea{}: {==}
    case InterfaceView.MultipleChoice{} Controls.ApprovalArea{}: {==}
    case InterfaceView.MultipleChoice{} Controls.DialogArea{}: {==}
    case InterfaceView.MultipleChoice{} Controls.CollectionArea{}: {==}
    case InterfaceView.MultipleChoice{} Controls.CardArea{}: {==}
    case InterfaceView.MultipleChoice{} Controls.BoardViewArea{}: {==}
    case InterfaceView.MultipleChoice{} Controls.BoardLaneArea{}: {==}

def semantic_face(+key: UIIdentity.Key, +kind: InterfaceView.ChoiceKind, +classification: Maybe<&2, Filter.Classification>, +selected: Bool, +description: String, +input: Core.Input, +availability: View.Availability, +label: String, +role: InterfaceView.Role, +context: Controls.Context) -> RuleChoiceRules.actual_face_law(key, kind, classification, selected, description, input, availability, label, role, context):
  Controls.Context{area, selection, code, appearance, access, open, layers, execution, source_family} = context
  {==}

def selected_measured_glyph(+text: String, description: Maybe<&2, String>, icon: Maybe<&2, Controls.Icon>, +selected: Bool, +key: UIIdentity.Key, +parent: Design.Style, +geometry: Controls.Geometry) ->
  {RuleChoiceRules.selection_drawing(A.face_members(Controls.ChoiceFace{text, description, icon, selected}, key, parent, geometry)) == RuleChoiceRules.selected_drawing(selected, A.face_icon_size(geometry)) : Maybe<&2, Source.Drawing>}:
  match icon selected:
    case None{} True{}: {==}
    case None{} False{}: {==}
    case Some{symbol} True{}: {==}
    case Some{symbol} False{}: {==}

def RuleChoiceRules.evidence():
  RuleChoiceRules.Requirements{
    classification_meaning,
    selection_roles,
    semantic_face,
    +text => description => +icon => selected => +key => +parent => +geometry => {==},
    selected_measured_glyph}

def appearance_consumes_layout(text: T.Presentation, chrome: Design.Chrome, alignment: SpatialModel.Alignment, flow: SpatialModel.Flow, overflow: SpatialModel.Overflow, content_area: Enclosure.ContentArea, gap: Nat, height: Nat, maximum: Nat, states: Design.ControlStates, face: Controls.Face, size: Controls.Geometry) ->
  {EnclosureLaws.frame_coordinates(Design.style_frame(Appearance.action_style(Design.Style{text, chrome, alignment, flow, overflow, Enclosure.Frame{content_area, Enclosure.EmbeddedContent{gap}}, height, maximum, states}, face, size))) == RuleControlContentLaws.layout_insets(Controls.content_layout(face)) : (Nat & (Nat & Nat))}:
  T.Presentation{tier, emphasis, scale} = text
  Design.Chrome{foreground, background, border, border_width, chrome_radius, shadow} = chrome
  match face size:
    case Controls.IconFace{icon} Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon_size, radius, leading}: {==}
    case Controls.TextFace{text} Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon_size, radius, leading}: {==}
    case Controls.UnbrokenFace{text} Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon_size, radius, leading}: {==}
    case Controls.SingleLineFace{text} Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon_size, radius, leading}: {==}
    case Controls.IconTextFace{icon, text} Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon_size, radius, leading}: {==}
    case Controls.UnbrokenIconTextFace{icon, text} Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon_size, radius, leading}: {==}
    case Controls.PickerFace{leading, text} Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon_size, radius, slot}: {==}
    case Controls.ChoiceFace{text, description, icon, checked} Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon_size, radius, leading}: {==}
    case Controls.DisclosureFace{text, expanded} Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon_size, radius, leading}: {==}
    case Controls.PermissionFace{filesystem, network, approval} Controls.Geometry{Space.Demand{Enclosure.Extent{width, height}, preferred}, icon_size, radius, leading}: {==}

def RuleControlContentLaws.picker_caption_single_line(leading,text): {==}
def RuleControlContentLaws.disclosure_caption_single_line(text,expanded): {==}

def RuleControlContentLaws.picker_face_caption(key,text,parent,leading,geometry):
  match leading:
    case None{}: {==}
    case Some{icon}: {==}

def RuleControlContentLaws.disclosure_face_caption(key,text,parent,expanded,geometry): {==}

def RuleControlContentLaws.evidence():
  RuleControlContentLaws.Requirements{
    +availability => {==},
    text => description => icon => checked => {==},
    {==},
    text => {==},
    +key => +text => +parent => description => icon => checked => {==},
    +key => +text => +parent => {==},
    filesystem => network => approval => {==},
    icon => {==},
    +leading => label => {==},
    appearance_consumes_layout}

def RuleControlContentLaws.unbroken_caption(text): {==}
def RuleControlContentLaws.unbroken_face_caption(key,text,parent,geometry): {==}

def RuleControlContentLaws.unbroken_icon_caption(icon,text): {==}
def RuleControlContentLaws.unbroken_icon_face_caption(key,icon,text,parent,geometry): {==}
def RuleControlContentLaws.named_text_caption(text,compact):
  match compact:
    case False{}: {==}
    case True{}: {==}
def RuleControlContentLaws.named_icon_caption(icon,text): {==}

def dialog_prepend_trailing_reading(+operation: Bool, +nodes: +List<Source.Node>, +actions: +List<Source.Node>) ->
  {Authored.append(Authored.dialog_part_body(Authored.dialog_prepend_trailing(operation, nodes, actions)),
    Authored.dialog_part_actions(Authored.dialog_prepend_trailing(operation, nodes, actions))) ==
    Authored.append(Authored.ordinary(nodes), actions) : +List<Source.Node>}:
  match operation:
    case True{}: {==}
    case False{}: {==}

# Match the original tail partition rather than a computed classification, so
# the proof retains the exact boundary chosen by the production recursion.
def dialog_prepend_reading(+operation: Bool, +nodes: +List<Source.Node>, +parts: Authored.DialogParts) ->
  {Authored.append(Authored.dialog_part_body(Authored.dialog_prepend(operation, nodes, parts)),
    Authored.dialog_part_actions(Authored.dialog_prepend(operation, nodes, parts))) ==
    Authored.append(Authored.ordinary(nodes), Authored.append(Authored.dialog_part_body(parts),
      Authored.dialog_part_actions(parts))) : +List<Source.Node>}:
  match parts:
    case Authored.TrailingActions{actions}:
      dialog_prepend_trailing_reading(operation, nodes, actions)
    case Authored.BodyAndActions{body, actions}:
      Equal.sym(+List<Source.Node>,
        Authored.append(Authored.ordinary(nodes), Authored.append(body, actions)),
        Authored.append(Authored.append(Authored.ordinary(nodes), body), actions),
        Std.app_assoc(Source.Node, Authored.ordinary(nodes), body, actions))

def dialog_reading_order(+children: +List<Authored.Child>) -> RuleDialogContentRules.dialog_reading_order(children):
  match children:
    case Nil{}: {==}
    case Con{Authored.Child{key, role, meaning, control, nodes}, rest}:
      +parts = Authored.dialog_parts(rest)
      tail_evidence = dialog_reading_order(rest)
      Equal.trans(+List<Source.Node>,
        Authored.append(Authored.dialog_body(Authored.Child{key, role, meaning, control, nodes} <> rest),
          Authored.dialog_actions(Authored.Child{key, role, meaning, control, nodes} <> rest)),
        Authored.append(Authored.ordinary(nodes), Authored.append(Authored.dialog_part_body(parts),
          Authored.dialog_part_actions(parts))),
        Authored.append(Authored.ordinary(nodes), RuleDialogContentRules.dialog_reading_content(rest)),
        dialog_prepend_reading(Authored.dialog_operation(role), nodes, parts),
        Equal.cong(+List<Source.Node>, +List<Source.Node>,
          (tail => Authored.append(Authored.ordinary(nodes), tail)),
          Authored.append(Authored.dialog_body(rest), Authored.dialog_actions(rest)),
          RuleDialogContentRules.dialog_reading_content(rest), tail_evidence))

def RuleDialogContentRules.choice_content(kind, classification, selected, description, input, availability):
  {==}

def RuleDialogContentRules.choice_group_content():
  {==}

def RuleDialogContentRules.choice_group_partition(key, control, choices, action_key, action_control, actions, input, availability):
  Equal.cong(+List<Source.Node>, Authored.DialogParts,
    (tail => Authored.BodyAndActions{Authored.ordinary(choices), tail}),
    List.append(&2, Source.Node, Authored.ordinary(actions), Nil{}), Authored.ordinary(actions), Std.app_nil_r(Source.Node, Authored.ordinary(actions)))

def action_suffix_head(first: Bool, following: Bool, evidence: {first && following == True{} : Bool}) ->
  {first == True{} : Bool} & {following == True{} : Bool}:
  match first following:
    case True{} True{}: ({==}, {==})
    case False{} True{}: Logic.impossible({False{} == True{} : Bool} & {True{} == True{} : Bool}, evidence)
    case True{} False{}: Logic.impossible({True{} == True{} : Bool} & {False{} == True{} : Bool}, evidence)
    case False{} False{}: Logic.impossible({False{} == True{} : Bool} & {False{} == True{} : Bool}, evidence)

def action_suffix_first(first: Bool, following: Bool, evidence: {first == True{} : Bool} & {following == True{} : Bool}) ->
  {first == True{} : Bool}:
  (head, tail) = evidence
  head

def action_suffix_following(first: Bool, following: Bool, evidence: {first == True{} : Bool} & {following == True{} : Bool}) ->
  {following == True{} : Bool}:
  (head, tail) = evidence
  tail

# The suffix premise constrains the same role classifier used by production.
def action_suffix_parts(+children: +List<Authored.Child>, +evidence: {Authored.dialog_only_actions(children) == True{} : Bool}) ->
  {Authored.dialog_parts(children) == Authored.TrailingActions{RuleDialogContentRules.dialog_reading_content(children)} : Authored.DialogParts}:
  match children:
    case Nil{}: {==}
    case Con{Authored.Child{key, role, meaning, control, nodes}, rest}:
      head = action_suffix_first(Authored.dialog_operation(role), Authored.dialog_only_actions(rest), action_suffix_head(Authored.dialog_operation(role), Authored.dialog_only_actions(rest), evidence))
      tail = action_suffix_following(Authored.dialog_operation(role), Authored.dialog_only_actions(rest), action_suffix_head(Authored.dialog_operation(role), Authored.dialog_only_actions(rest), evidence))
      Equal.trans(Authored.DialogParts,
        Authored.dialog_prepend(Authored.dialog_operation(role), nodes, Authored.dialog_parts(rest)),
        Authored.dialog_prepend(True{}, nodes, Authored.dialog_parts(rest)),
        Authored.TrailingActions{Authored.append(Authored.ordinary(nodes), RuleDialogContentRules.dialog_reading_content(rest))},
        Equal.cong(Bool, Authored.DialogParts, operation => Authored.dialog_prepend(operation, nodes, Authored.dialog_parts(rest)),
          Authored.dialog_operation(role), True{}, head),
        Equal.cong(Authored.DialogParts, Authored.DialogParts, parts => Authored.dialog_prepend(True{}, nodes, parts),
          Authored.dialog_parts(rest), Authored.TrailingActions{RuleDialogContentRules.dialog_reading_content(rest)}, action_suffix_parts(rest, tail)))

def RuleDialogContentRules.dialog_action_region():
  {==}

def RuleDialogContentRules.dialog_action_footer(key, meaning, control, nodes, rest, ordered):
  Equal.cong(Authored.DialogParts, Authored.DialogParts, parts => Authored.dialog_prepend(True{}, nodes, parts),
    Authored.dialog_parts(rest), Authored.TrailingActions{RuleDialogContentRules.dialog_reading_content(rest)}, action_suffix_parts(rest, ordered))

def ordinary_prepend(+nodes: +List<Source.Node>, +parts: Authored.DialogParts) ->
  {Authored.dialog_prepend(False{}, nodes, parts) == Authored.BodyAndActions{Authored.append(Authored.ordinary(nodes), Authored.dialog_part_body(parts)), Authored.dialog_part_actions(parts)} : Authored.DialogParts}:
  match parts:
    case Authored.TrailingActions{actions}:
      Equal.cong(+List<Source.Node>, Authored.DialogParts, body => Authored.BodyAndActions{body, actions},
        Authored.ordinary(nodes), Authored.append(Authored.ordinary(nodes), Nil{}),
        Equal.sym(+List<Source.Node>, Authored.append(Authored.ordinary(nodes), Nil{}), Authored.ordinary(nodes), Std.app_nil_r(Source.Node, Authored.ordinary(nodes))))
    case Authored.BodyAndActions{body, actions}: {==}

def RuleDialogContentRules.dialog_ordinary_activation(key, role, input, availability, control, nodes, rest, ordinary):
  Equal.trans(Authored.DialogParts,
    Authored.dialog_prepend(Authored.dialog_operation(role), nodes, Authored.dialog_parts(rest)),
    Authored.dialog_prepend(False{}, nodes, Authored.dialog_parts(rest)),
    Authored.BodyAndActions{Authored.append(Authored.ordinary(nodes), Authored.dialog_body(rest)), Authored.dialog_actions(rest)},
    Equal.cong(Bool, Authored.DialogParts, operation => Authored.dialog_prepend(operation, nodes, Authored.dialog_parts(rest)),
      Authored.dialog_operation(role), False{}, ordinary), ordinary_prepend(nodes, Authored.dialog_parts(rest)))

def RuleDialogContentRules.dialog_rejects_invalid_order(key, label, meaning, visual, control, children, parameters, invalid):
  Equal.cong(Bool, Authored.Authorship,
    ordered => Authored.authored_node_ordered(ordered, key, label, InterfaceView.Dialog{}, meaning, visual, control, children, parameters),
    Authored.dialog_ordered(children), False{}, invalid)

def RuleDialogSpatialLaws.evidence():
  RuleDialogSpatialLaws.Requirements{
    +typography => editor => +field => +entry => +value => choices => toggle =>
      Equal.cong(Controls.Widget, Design.Style,
        (widget => Appearance.normalize_field(EditorLayout.field_kind(InterfaceView.Edit{editor, field, entry, value, choices}),
          widget, Appearance.widget_field_style(widget, entry, typography))),
        Controls.widget_for(entry, field, value), Controls.ToggleInput{}, toggle),
    +typography => {==},
    {==},
    +card => +field => +entry => +value => choices => {==},
    {==}}

def Rule.dock_evidence():
  Rule.DockRequirements{
    extent => viewport => +intent => +bookmark => reduced => {==}}

def Rule.fact_content_evidence():
  Rule.FactContentRequirements{
    {==}}

def RuleFormInputLaws.evidence():
  RuleFormInputLaws.Requirements{
    id => revision => draft => assist => profile => keep_open => {==},
    editor => value => +text => state => {==},
    values => title => description => stage => priority => owner => project => previous => attachments => {==},
    values => {==},
    choices => key => editor => values => label => role => context => {==},
    values => {==},
    choices => key => editor => enabled => profile => label => role => context => {==},
    choices => key => editor => enabled => profile => label => role => context => {==},
    choices => key => semantic => label => role => editor => previous => profile => children => enabled => {==},
    enabled => selected => previous => profile => {==},
    enabled => selected => previous => profile => {==},
    stage => rest => {==},
    priority => rest => {==},
    value => {==},
    value => {==}}

def removed_step(same: Bool, +current: UIIdentity.Key, +semantic: String, +label: String,
  +role: InterfaceView.Role, +meaning: InterfaceView.Meaning, +children: +List<InterfaceView.Node>, +rest: +List<InterfaceView.Node>, +key: String,
  same_key: {String.eq(UIIdentity.encode(current), key) == same : Bool},
  children_removed: {RulePersistentTriggerLaws.occurrences(InterfaceView.without_node(children, key), key) == 0n : Nat},
  rest_removed: {RulePersistentTriggerLaws.occurrences(InterfaceView.without_node(rest, key), key) == 0n : Nat}) ->
  {RulePersistentTriggerLaws.occurrences(InterfaceView.retain_node(Bool.not(same),
    InterfaceView.Node{current, semantic, label, role, meaning, InterfaceView.without_node(children, key)}, InterfaceView.without_node(rest, key)), key) == 0n : Nat}:
  match same:
    case True{}: rest_removed
    case False{}:
      Equal.trans(Nat,
        Nat.add(RulePersistentTriggerLaws.bit(String.eq(UIIdentity.encode(current), key)), Nat.add(RulePersistentTriggerLaws.occurrences(InterfaceView.without_node(children, key), key), RulePersistentTriggerLaws.occurrences(InterfaceView.without_node(rest, key), key))),
        Nat.add(0n, Nat.add(RulePersistentTriggerLaws.occurrences(InterfaceView.without_node(children, key), key), RulePersistentTriggerLaws.occurrences(InterfaceView.without_node(rest, key), key))), 0n,
        Equal.cong(Bool, Nat, (value => Nat.add(RulePersistentTriggerLaws.bit(value), Nat.add(RulePersistentTriggerLaws.occurrences(InterfaceView.without_node(children, key), key), RulePersistentTriggerLaws.occurrences(InterfaceView.without_node(rest, key), key)))),
          String.eq(UIIdentity.encode(current), key), False{}, same_key),
      Equal.trans(Nat,
        Nat.add(0n, Nat.add(RulePersistentTriggerLaws.occurrences(InterfaceView.without_node(children, key), key), RulePersistentTriggerLaws.occurrences(InterfaceView.without_node(rest, key), key))),
        Nat.add(0n, Nat.add(0n, RulePersistentTriggerLaws.occurrences(InterfaceView.without_node(rest, key), key))), 0n,
        Equal.cong(Nat, Nat, (count => Nat.add(0n, Nat.add(count, RulePersistentTriggerLaws.occurrences(InterfaceView.without_node(rest, key), key)))),
          RulePersistentTriggerLaws.occurrences(InterfaceView.without_node(children, key), key), 0n, children_removed),
        Equal.cong(Nat, Nat, (count => Nat.add(0n, Nat.add(0n, count))),
          RulePersistentTriggerLaws.occurrences(InterfaceView.without_node(rest, key), key), 0n, rest_removed)))

def removed_occurrences(nodes: +List<InterfaceView.Node>, +key: String) ->
  {RulePersistentTriggerLaws.occurrences(InterfaceView.without_node(nodes, key), key) == 0n : Nat}:
  match nodes:
    case Nil{}: {==}
    case Con{InterfaceView.Node{+current, semantic, label, role, meaning, +children}, +rest}:
      removed_step(String.eq(UIIdentity.encode(current), key), current, semantic, label, role, meaning, children, rest, key, {==}, removed_occurrences(children, key), removed_occurrences(rest, key))

def actual_relocation(+scene: Core.Scene, +base: +List<InterfaceView.Node>, +overlays: +List<InterfaceView.Node>,
  +key: String, +node: InterfaceView.Node, +target: Nat,
  found: {InterfaceView.find_node(base, key) == Some{node} : Maybe<&2, InterfaceView.Node>}) ->
  {InterfaceView.relocate_trigger_key(Some{key}, target, scene, base, overlays) == InterfaceView.relocate_found_trigger(Some{node}, target, scene, base, overlays) : InterfaceView.Surface}:
  Equal.cong(Maybe<&2, InterfaceView.Node>, InterfaceView.Surface,
    (value => InterfaceView.relocate_found_trigger(value, target, scene, base, overlays)), InterfaceView.find_node(base, key), Some{node}, found)

def valid_exactly_once(+scene: Core.Scene, +base: +List<InterfaceView.Node>, +key: UIIdentity.Key, +semantic: String,
  +label: String, +role: InterfaceView.Role, +meaning: InterfaceView.Meaning, +owner: UIIdentity.Key, +layer_semantic: String,
  +title: String, +policy: InterfaceView.Meaning, +body: +List<InterfaceView.Node>, +rest: +List<InterfaceView.Node>,
  distinct: {String.eq(UIIdentity.encode(owner), UIIdentity.encode(key)) == False{} : Bool},
  fresh: {Nat.add(RulePersistentTriggerLaws.occurrences(body, UIIdentity.encode(key)), RulePersistentTriggerLaws.occurrences(rest, UIIdentity.encode(key))) == 0n : Nat}) ->
  {RulePersistentTriggerLaws.surface_occurrences(InterfaceView.relocate_valid_trigger(True{}, InterfaceView.Node{key, semantic, label, role, meaning, Nil{}},
    scene, base, InterfaceView.Node{owner, layer_semantic, title, InterfaceView.Dialog{}, policy, body} <> rest), UIIdentity.encode(key)) == 1n : Nat}:
  Equal.trans(Nat,
    Nat.add(RulePersistentTriggerLaws.occurrences(InterfaceView.without_node(base, UIIdentity.encode(key)), UIIdentity.encode(key)),
      Nat.add(RulePersistentTriggerLaws.bit(String.eq(UIIdentity.encode(owner), UIIdentity.encode(key))), Nat.add(Nat.add(RulePersistentTriggerLaws.bit(String.eq(UIIdentity.encode(key), UIIdentity.encode(key))), RulePersistentTriggerLaws.occurrences(body, UIIdentity.encode(key))), RulePersistentTriggerLaws.occurrences(rest, UIIdentity.encode(key))))),
    Nat.add(0n, Nat.add(RulePersistentTriggerLaws.bit(String.eq(UIIdentity.encode(owner), UIIdentity.encode(key))), Nat.add(Nat.add(RulePersistentTriggerLaws.bit(String.eq(UIIdentity.encode(key), UIIdentity.encode(key))), RulePersistentTriggerLaws.occurrences(body, UIIdentity.encode(key))), RulePersistentTriggerLaws.occurrences(rest, UIIdentity.encode(key))))), 1n,
    Equal.cong(Nat, Nat, (count => Nat.add(count,
      Nat.add(RulePersistentTriggerLaws.bit(String.eq(UIIdentity.encode(owner), UIIdentity.encode(key))), Nat.add(Nat.add(RulePersistentTriggerLaws.bit(String.eq(UIIdentity.encode(key), UIIdentity.encode(key))), RulePersistentTriggerLaws.occurrences(body, UIIdentity.encode(key))), RulePersistentTriggerLaws.occurrences(rest, UIIdentity.encode(key)))))),
      RulePersistentTriggerLaws.occurrences(InterfaceView.without_node(base, UIIdentity.encode(key)), UIIdentity.encode(key)), 0n, removed_occurrences(base, UIIdentity.encode(key))),
    Equal.trans(Nat,
      Nat.add(0n, Nat.add(RulePersistentTriggerLaws.bit(String.eq(UIIdentity.encode(owner), UIIdentity.encode(key))), Nat.add(Nat.add(RulePersistentTriggerLaws.bit(String.eq(UIIdentity.encode(key), UIIdentity.encode(key))), RulePersistentTriggerLaws.occurrences(body, UIIdentity.encode(key))), RulePersistentTriggerLaws.occurrences(rest, UIIdentity.encode(key))))),
      Nat.add(0n, Nat.add(0n, Nat.add(Nat.add(RulePersistentTriggerLaws.bit(String.eq(UIIdentity.encode(key), UIIdentity.encode(key))), RulePersistentTriggerLaws.occurrences(body, UIIdentity.encode(key))), RulePersistentTriggerLaws.occurrences(rest, UIIdentity.encode(key))))), 1n,
      Equal.cong(Bool, Nat, (same => Nat.add(0n, Nat.add(RulePersistentTriggerLaws.bit(same), Nat.add(Nat.add(RulePersistentTriggerLaws.bit(String.eq(UIIdentity.encode(key), UIIdentity.encode(key))), RulePersistentTriggerLaws.occurrences(body, UIIdentity.encode(key))), RulePersistentTriggerLaws.occurrences(rest, UIIdentity.encode(key)))))),
        String.eq(UIIdentity.encode(owner), UIIdentity.encode(key)), False{}, distinct),
      Equal.trans(Nat,
        Nat.add(0n, Nat.add(0n, Nat.add(Nat.add(RulePersistentTriggerLaws.bit(String.eq(UIIdentity.encode(key), UIIdentity.encode(key))), RulePersistentTriggerLaws.occurrences(body, UIIdentity.encode(key))), RulePersistentTriggerLaws.occurrences(rest, UIIdentity.encode(key))))),
        Nat.add(1n, Nat.add(RulePersistentTriggerLaws.occurrences(body, UIIdentity.encode(key)), RulePersistentTriggerLaws.occurrences(rest, UIIdentity.encode(key)))), 1n,
        Equal.cong(Bool, Nat, (same => Nat.add(0n, Nat.add(0n, Nat.add(Nat.add(RulePersistentTriggerLaws.bit(same), RulePersistentTriggerLaws.occurrences(body, UIIdentity.encode(key))), RulePersistentTriggerLaws.occurrences(rest, UIIdentity.encode(key)))))),
          String.eq(UIIdentity.encode(key), UIIdentity.encode(key)), True{}, EqualityProof.same_string(UIIdentity.encode(key))),
        Equal.cong(Nat, Nat, (count => Nat.add(1n, count)),
          Nat.add(RulePersistentTriggerLaws.occurrences(body, UIIdentity.encode(key)), RulePersistentTriggerLaws.occurrences(rest, UIIdentity.encode(key))), 0n, fresh))))

def accepted_same_node(+scene: Core.Scene, +base: +List<InterfaceView.Node>, +overlays: +List<InterfaceView.Node>,
  +key: UIIdentity.Key, +semantic: String, +label: String, +role: InterfaceView.Role, +meaning: InterfaceView.Meaning,
  +children: +List<InterfaceView.Node>, +target: Nat,
  accepted: {InterfaceView.persistent_trigger_source(meaning, target) == True{} : Bool}) ->
  {InterfaceView.relocate_found_trigger(Some{InterfaceView.Node{key, semantic, label, role, meaning, children}}, target, scene, base, overlays) ==
    InterfaceView.relocate_valid_trigger(True{}, InterfaceView.Node{key, semantic, label, role, meaning, children}, scene, base, overlays) : InterfaceView.Surface}:
  Equal.cong(Bool, InterfaceView.Surface,
    (valid => InterfaceView.relocate_valid_trigger(valid, InterfaceView.Node{key, semantic, label, role, meaning, children}, scene, base, overlays)),
    InterfaceView.persistent_trigger_source(meaning, target), True{}, accepted)

def rejected_source_stays(+scene: Core.Scene, +base: +List<InterfaceView.Node>, +overlays: +List<InterfaceView.Node>,
  +key: UIIdentity.Key, +semantic: String, +label: String, +role: InterfaceView.Role, +meaning: InterfaceView.Meaning,
  +children: +List<InterfaceView.Node>, +target: Nat,
  rejected: {InterfaceView.persistent_trigger_source(meaning, target) == False{} : Bool}) ->
  {InterfaceView.relocate_found_trigger(Some{InterfaceView.Node{key, semantic, label, role, meaning, children}}, target, scene, base, overlays) ==
    InterfaceView.finish(scene, base, overlays) : InterfaceView.Surface}:
  Equal.cong(Bool, InterfaceView.Surface,
    (valid => InterfaceView.relocate_valid_trigger(valid, InterfaceView.Node{key, semantic, label, role, meaning, children}, scene, base, overlays)),
    InterfaceView.persistent_trigger_source(meaning, target), False{}, rejected)

def RulePersistentTriggerLaws.evidence():
  RulePersistentTriggerLaws.Requirements{removed_occurrences, +scene => +base => +overlays => +trigger => +key => +node => +target => persistent => resolved => found =>
      Equal.trans(InterfaceView.Surface, InterfaceView.finish_reachable(scene, base, overlays),
        InterfaceView.relocate_persistent_trigger(Some{InterfaceView.PersistentTrigger{target, trigger}}, scene, base, overlays),
        InterfaceView.relocate_found_trigger(Some{node}, target, scene, base, overlays),
        Equal.cong(Maybe<&2, InterfaceView.PersistentTrigger>, InterfaceView.Surface,
          (value => InterfaceView.relocate_persistent_trigger(value, scene, base, overlays)),
          InterfaceView.persistent_details_trigger(overlays), Some{InterfaceView.PersistentTrigger{target, trigger}}, persistent),
        Equal.trans(InterfaceView.Surface, InterfaceView.relocate_persistent_trigger(Some{InterfaceView.PersistentTrigger{target, trigger}}, scene, base, overlays),
          InterfaceView.relocate_trigger_key(Some{key}, target, scene, base, overlays),
          InterfaceView.relocate_found_trigger(Some{node}, target, scene, base, overlays),
          Equal.cong(Maybe<&2, String>, InterfaceView.Surface,
            (value => InterfaceView.relocate_trigger_key(value, target, scene, base, overlays)),
            InterfaceView.matching_focus(base, trigger), Some{key}, resolved),
          actual_relocation(scene, base, overlays, key, node, target, found)))
    , +scene => +base => +key => +semantic => +label => +role => +meaning => +owner => +layer_semantic => +title => +policy => +body => +rest => +target => accepted => distinct => fresh =>
      Equal.trans(Nat,
        RulePersistentTriggerLaws.surface_occurrences(InterfaceView.relocate_found_trigger(Some{InterfaceView.Node{key, semantic, label, role, meaning, Nil{}}}, target,
          scene, base, InterfaceView.Node{owner, layer_semantic, title, InterfaceView.Dialog{}, policy, body} <> rest), UIIdentity.encode(key)),
        RulePersistentTriggerLaws.surface_occurrences(InterfaceView.relocate_valid_trigger(True{}, InterfaceView.Node{key, semantic, label, role, meaning, Nil{}},
          scene, base, InterfaceView.Node{owner, layer_semantic, title, InterfaceView.Dialog{}, policy, body} <> rest), UIIdentity.encode(key)), 1n,
        Equal.cong(InterfaceView.Surface, Nat, (surface => RulePersistentTriggerLaws.surface_occurrences(surface, UIIdentity.encode(key))),
          InterfaceView.relocate_found_trigger(Some{InterfaceView.Node{key, semantic, label, role, meaning, Nil{}}}, target, scene, base, InterfaceView.Node{owner, layer_semantic, title, InterfaceView.Dialog{}, policy, body} <> rest),
          InterfaceView.relocate_valid_trigger(True{}, InterfaceView.Node{key, semantic, label, role, meaning, Nil{}}, scene, base, InterfaceView.Node{owner, layer_semantic, title, InterfaceView.Dialog{}, policy, body} <> rest),
          accepted_same_node(scene, base, InterfaceView.Node{owner, layer_semantic, title, InterfaceView.Dialog{}, policy, body} <> rest,
            key, semantic, label, role, meaning, Nil{}, target, accepted)),
        valid_exactly_once(scene, base, key, semantic, label, role, meaning, owner, layer_semantic, title, policy, body, rest, distinct, fresh))
    , +task => +trigger => +content => +initial => +state => {==}, +scene => +base => +overlays => +key => +semantic => +label => +role => +expanded => +source => +trigger => +availability => +children => +target => distinct =>
      rejected_source_stays(scene, base, overlays, key, semantic, label, role,
        InterfaceView.PanelToggle{expanded, Core.ApplicationInput{E.UserInput{User.Activate{User.TogglePanel{User.TaskDetails{source}, trigger}}}}, availability}, children, target, distinct)
    , +scene => +base => +overlays => +key => +semantic => +label => +role => +expanded => +service => +availability => +children => +target => {==}, +scene => +nav => +reachable => +settings => +scope => {==}, rejected_source_stays, accepted_same_node}

def Rule.feedback_evidence():
  Rule.FeedbackRequirements{
    +reason => {==}}

def input_phase(phase: Surfaces.Phase, +typography: T.Presentation) ->
  {Appearance.phase_background(Appearance.editable_field(typography), phase) == Design.SurfacePaint{Surfaces.Field{}, phase} : Design.Paint}:
  match phase:
    case Surfaces.Rest{}: {==}
    case Surfaces.Hovered{}: {==}
    case Surfaces.Pressed{}: {==}

def message_phase(entry: Forms.Entry, phase: Surfaces.Phase, +typography: T.Presentation) ->
  {Appearance.phase_background(Appearance.widget_field_style(Controls.MessageInput{}, entry, typography), phase) == Design.SurfacePaint{Surfaces.EmbeddedField{}, phase} : Design.Paint}:
  match phase:
    case Surfaces.Rest{}: {==}
    case Surfaces.Hovered{}: {==}
    case Surfaces.Pressed{}: {==}

def selected_control_phase(value: Design.Style, phase: Surfaces.Phase, +typography: T.Presentation) ->
  {Appearance.phase_background(Appearance.selection_style(value, Controls.Radio{True{}}, typography), phase) == Design.SurfacePaint{Surfaces.Choice{True{}}, phase} : Design.Paint}:
  match phase:
    case Surfaces.Rest{}: {==}
    case Surfaces.Hovered{}: {==}
    case Surfaces.Pressed{}: {==}

def toggle_control_phase(value: Design.Style, phase: Surfaces.Phase, +typography: T.Presentation) ->
  {Appearance.phase_background(Appearance.selection_style(value, Controls.Toggle{True{}}, typography), phase) == Design.SurfacePaint{Surfaces.Choice{True{}}, phase} : Design.Paint}:
  match phase:
    case Surfaces.Rest{}: {==}
    case Surfaces.Hovered{}: {==}
    case Surfaces.Pressed{}: {==}

def menu_choice_phase(value: Design.Style, phase: Surfaces.Phase, +typography: T.Presentation) ->
  {Appearance.phase_background(Appearance.selection_style(value, Controls.ChoiceRadio{True{}}, typography), phase) == Design.SurfacePaint{Surfaces.Choice{True{}}, phase} : Design.Paint}:
  match phase:
    case Surfaces.Rest{}: {==}
    case Surfaces.Hovered{}: {==}
    case Surfaces.Pressed{}: {==}

def RuleSurfaceLaws.evidence():
  RuleSurfaceLaws.Requirements{{==}, {==}, {==}, selected => {==}, {==}, {==}, {==},

    phase => {==},
    phase => {==},
    phase => {==},
    {==},
    {==},
    {==},
    {==},
    {==},
    {==},
    {==},
    +typography => meaning => {==},
    +typography => meaning => {==},
    +typography => meaning => {==},
    +typography => meaning => {==},
    +typography => meaning => {==},
    +typography => meaning => {==},
    +typography => phase => input_phase(phase, typography),
    +typography => entry => phase => message_phase(entry, phase, typography),
    +typography => filter => {==},
    +typography => value => phase => selected_control_phase(value, phase, typography),
    +typography => value => phase => toggle_control_phase(value, phase, typography),
    +typography => value => phase => menu_choice_phase(value, phase, typography)}

def events(+node: Source.Node, +layout: Source.Layout) -> RuleAuthoredShellRules.reframing_events(node, layout):
  match node:
    case Source.NativeAttachment{key, target, attributes, style, children}: {==}
    case Source.Box{key, tag, style, attributes, children}: {==}
    case Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: {==}
    case Source.Glyph{key, drawing, style}: {==}
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: {==}
    case Source.RichText{key, style, content, attachments, native_owner}: {==}
    case Source.Text{key, value, font, wrapping}: {==}

def interaction(+node: Source.Node, +layout: Source.Layout) -> RuleAuthoredShellRules.reframing_interaction(node, layout):
  match node:
    case Source.NativeAttachment{key, target, attributes, style, children}: {==}
    case Source.Box{key, tag, style, attributes, children}: {==}
    case Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: {==}
    case Source.Glyph{key, drawing, style}: {==}
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: {==}
    case Source.RichText{key, style, content, attachments, native_owner}: {==}
    case Source.Text{key, value, font, wrapping}: {==}

def children(+node: Source.Node, +layout: Source.Layout) -> RuleAuthoredShellRules.reframing_children(node, layout):
  match node:
    case Source.NativeAttachment{key, target, attributes, style, children}: {==}
    case Source.Box{key, tag, style, attributes, children}: {==}
    case Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: {==}
    case Source.Glyph{key, drawing, style}: {==}
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: {==}
    case Source.RichText{key, style, content, attachments, native_owner}: {==}
    case Source.Text{key, value, font, wrapping}: {==}

def wrapper(key: UIIdentity.Key, style: Source.Style, +children: +List<Source.Node>) -> RuleAuthoredShellRules.wrapper_children(key, style, children):
  {==}

def no_wrapper_events(key: UIIdentity.Key, style: Source.Style, children: +List<Source.Node>) -> RuleAuthoredShellRules.wrapper_events(key, style, children):
  {==}

def footer(key: UIIdentity.Key, tag: Source.BoxTag, style: Source.Style, attributes: +List<Source.Attribute>, +children: +List<Source.Node>, +settings: +List<Source.Node>, +font: T.Presentation) -> RuleAuthoredShellRules.footer_children(key, tag, style, attributes, children, settings, font):
  {==}


def reading_policy(+width: Model.AxisSize, maximum: Nat) -> RuleAuthoredShellRules.reading_policy(width, maximum):
  match width:
    case Model.NaturalSize{}: {==}
    case Model.StretchSize{}: {==}
    case Model.CappedStretchSize{cap}: {==}
    case Model.ExactSize{extent}: {==}
    case Model.LimitedSize{minimum, preferred, maximum_extra}: {==}
    case Model.PercentSize{percent}: {==}
    case Model.CappedNaturalSize{percent}: {==}
    case Model.AdaptiveNaturalSize{percent}: {==}

def reading_layout(+layout: Source.Layout, maximum: Nat) -> RuleAuthoredShellRules.reading_layout(layout, maximum):
  Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position} = layout
  {==}

def reading_stretch_width(direction: Model.Direction, main: SpatialModel.Alignment, cross: SpatialModel.Alignment, frame: Enclosure.Frame, height: Model.AxisSize, floor: Enclosure.Extent, scroll: Model.Scroll, position: SpatialModel.Position, +maximum: Nat, +minimum: Nat, preferred: Nat, offered: Nat, +room: Nat,
  +fits: {Nat.is_le(minimum, maximum) == True{} : Bool}, room_fits: {Nat.is_le(minimum, room) == True{} : Bool}) ->
  {PhysicalRules.allocated_width(RuleAuthoredShellRules.reading_stretch_dimension(direction, main, cross, frame, height, floor, scroll, position, maximum, minimum, preferred, offered), room) == Some{Nat.min(room, maximum)} : Maybe<&2, Nat>}:
  Order.capped_stretch_width(minimum, preferred, offered, maximum, room, fits, room_fits)

def reframing_key(+node: Source.Node, layout: Source.Layout) -> {Source.key_of(Shell.reframe(node, layout)) == Source.key_of(node) : UIIdentity.Key}:
  match node:
    case Source.NativeAttachment{key, target, attributes, style, children}: {==}
    case Source.Box{key, tag, style, attributes, children}: {==}
    case Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: {==}
    case Source.Glyph{key, drawing, style}: {==}
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: {==}
    case Source.RichText{key, style, content, attachments, native_owner}: {==}
    case Source.Text{key, value, font, wrapping}: {==}

def creation_population(+children: +List<Source.Node>, +maximum: Nat) -> RuleAuthoredShellRules.creation_population(children, maximum):
  match children:
    case Nil{}: {==}
    case Con{+node, +rest}:
      Equal.trans(+List<UIIdentity.Key>, Source.key_of(Shell.reframe(node, Shell.creation_layout(Shell.layout_of(node), maximum))) <> RuleAuthoredShellRules.keys(Shell.creation_children(rest, maximum)),
        Source.key_of(node) <> RuleAuthoredShellRules.keys(Shell.creation_children(rest, maximum)), Source.key_of(node) <> RuleAuthoredShellRules.keys(rest),
        Equal.cong(UIIdentity.Key, +List<UIIdentity.Key>, (key => key <> RuleAuthoredShellRules.keys(Shell.creation_children(rest, maximum))), Source.key_of(Shell.reframe(node, Shell.creation_layout(Shell.layout_of(node), maximum))), Source.key_of(node), reframing_key(node, Shell.creation_layout(Shell.layout_of(node), maximum))),
        Equal.cong(+List<UIIdentity.Key>, +List<UIIdentity.Key>, (keys => Source.key_of(node) <> keys), RuleAuthoredShellRules.keys(Shell.creation_children(rest, maximum)), RuleAuthoredShellRules.keys(rest), creation_population(rest, maximum)))

def creation_group(key: UIIdentity.Key, font: Source.FontChoice, +maximum: Nat, children: +List<Source.Node>) -> RuleAuthoredShellRules.creation_group(key, font, maximum, children):
  {==}

def creation_group_spacing(key: UIIdentity.Key, font: Source.FontChoice, maximum: Nat, children: +List<Source.Node>) -> RuleAuthoredShellRules.creation_group_spacing(key, font, maximum, children):
  {==}

def creation_reading_width(+parameters: Design.LayoutParameters) -> RuleAuthoredShellRules.creation_reading_width(parameters):
  {==}

def creation_assembly(+content: Core.Scene, +theme: Design.Theme, +base: +List<Design.Node>, +overlays: +List<Design.Node>, scope: Maybe<&2, String>, +base_nodes: +List<Source.Node>, +overlay_nodes: +List<Source.Node>, +capacity: View.Capacity, +parameters: Design.LayoutParameters, +layers: +List<View.Layer>, +anchors: +List<Shell.Anchor>, +font: T.Presentation,
  created: {Shell.scene_structure(content) == Design.MainStructure{Composition.ReadingMeasure{}, Composition.NoHeading{}, Composition.CenteredCreation{}} : Design.MainStructure}) -> RuleAuthoredShellRules.creation_assembly(content, theme, base, overlays, scope, base_nodes, overlay_nodes, capacity, parameters, layers, anchors, font):
  Equal.cong(Design.MainStructure, Shell.ShellAuthorship,
    (structure => Shell.assembled_parts(Shell.split_overlays(overlay_nodes, capacity, Shell.scene_navigation_placement(content), parameters, layers, base, overlays, anchors), structure, Shell.structure_reading_width(structure, parameters), base_nodes, base, Shell.scene_navigation_placement(content), parameters, font, theme)), Shell.scene_structure(content), Design.MainStructure{Composition.ReadingMeasure{}, Composition.NoHeading{}, Composition.CenteredCreation{}}, created)

def creation_child_layout(+layout: Source.Layout, maximum: Nat) -> RuleAuthoredShellRules.creation_child_layout(layout, maximum):
  Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position} = layout
  {==}

def creation_main(+key: UIIdentity.Key, tag: Source.BoxTag, +style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, +maximum: Nat) -> RuleAuthoredShellRules.creation_main(key, tag, style, attributes, children, maximum):
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = style
  {==}

def other_main_fields(+measure: Composition.Measure, +heading: Composition.Heading, +organization: Composition.Body, +key: UIIdentity.Key, tag: Source.BoxTag,
  direction: Model.Direction, main: SpatialModel.Alignment, cross: SpatialModel.Alignment, frame: Enclosure.Frame, width: Model.AxisSize, height: Model.AxisSize, minimum: Enclosure.Extent, scroll: Model.Scroll, position: SpatialModel.Position, font: Source.FontChoice, chrome: Design.Chrome, states: Design.ControlStates,
  attributes: +List<Source.Attribute>, children: +List<Source.Node>, +maximum: Nat,
  other: {RuleAuthoredShellRules.other_organization(organization) == True{} : Bool}) -> RuleAuthoredShellRules.other_main(Design.MainStructure{measure, heading, organization}, key, tag,
    Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states}, attributes, children, maximum):
  match organization:
    case Composition.CenteredCreation{}: Logic.impossible(RuleAuthoredShellRules.other_main(Design.MainStructure{measure, heading, Composition.CenteredCreation{}}, key, tag, Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states}, attributes, children, maximum), other)
    case Composition.ChronologicalReading{}: {==}
    case Composition.ProjectSections{}: {==}
    case Composition.ProjectRows{}: {==}
    case Composition.AgentRows{}: {==}
    case Composition.StageColumns{}: {==}
    case Composition.UnavailableNotice{}: {==}

def other_main_style(+measure: Composition.Measure, +heading: Composition.Heading, +organization: Composition.Body, +key: UIIdentity.Key, tag: Source.BoxTag, +style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, +maximum: Nat,
  other: {RuleAuthoredShellRules.other_organization(organization) == True{} : Bool}) -> RuleAuthoredShellRules.other_main(Design.MainStructure{measure, heading, organization}, key, tag, style, attributes, children, maximum):
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = style
  other_main_fields(measure, heading, organization, key, tag, direction, main, cross, frame, width, height, minimum, scroll, position, font, chrome, states, attributes, children, maximum, other)

def other_main(+structure: Design.MainStructure, +key: UIIdentity.Key, tag: Source.BoxTag, +style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, +maximum: Nat,
  other: {RuleAuthoredShellRules.other_structure(structure) == True{} : Bool}) -> RuleAuthoredShellRules.other_main(structure, key, tag, style, attributes, children, maximum):
  Design.MainStructure{measure, heading, organization} = structure
  other_main_style(measure, heading, organization, key, tag, style, attributes, children, maximum, other)

def navigation_box(key: UIIdentity.Key, tag: Source.BoxTag, +style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, rest: +List<Source.Node>, +width: Nat) -> RuleAuthoredShellRules.navigation_box(key, tag, style, attributes, children, rest, width):
  Source.Style{Source.Layout{direction, main, cross, frame, old_width, height, minimum, scroll, position}, font, chrome, states} = style
  {==}

def settings_identified(+node: Source.Node,
  identified: {Source.key_of(node) == UIIdentity.part(UIIdentity.place(""), "settings/open") : UIIdentity.Key}) ->
  {UIIdentity.same(Source.key_of(node), UIIdentity.part(UIIdentity.place(""), "settings/open")) == True{} : Bool}:
  Equal.cong(UIIdentity.Key, Bool, (key => UIIdentity.same(key, UIIdentity.part(UIIdentity.place(""), "settings/open"))),
    Source.key_of(node), UIIdentity.part(UIIdentity.place(""), "settings/open"), identified)

def settings_group_found(+node: Source.Node, +navigation: +List<Source.Node>, +main: +List<Source.Node>, +settings: +List<Source.Node>, +other: +List<Source.Node>,
  identified: {Source.key_of(node) == UIIdentity.part(UIIdentity.place(""), "settings/open") : UIIdentity.Key}) ->
  {Shell.split_base_settings(UIIdentity.same(Source.key_of(node), UIIdentity.part(UIIdentity.place(""), "settings/open")), node, Shell.BaseParts{navigation, main, settings, other}) == Shell.BaseParts{navigation, main, node <> settings, other} : Shell.BaseParts}:
  Equal.cong(Bool, Shell.BaseParts, (found => Shell.split_base_settings(found, node, Shell.BaseParts{navigation, main, settings, other})),
    UIIdentity.same(Source.key_of(node), UIIdentity.part(UIIdentity.place(""), "settings/open")), True{}, settings_identified(node, identified))

def settings_classification(+node: Source.Node, +role: InterfaceView.Role, +navigation: +List<Source.Node>, +main: +List<Source.Node>, +settings: +List<Source.Node>, +other: +List<Source.Node>,
  identified: {Source.key_of(node) == UIIdentity.part(UIIdentity.place(""), "settings/open") : UIIdentity.Key}, belongs: {RuleAuthoredShellRules.settings_role(role) == True{} : Bool}) -> RuleAuthoredShellRules.settings_classification(node, role, navigation, main, settings, other):
  match role:
    case InterfaceView.Main{}: Logic.impossible(RuleAuthoredShellRules.settings_classification(node, InterfaceView.Main{}, navigation, main, settings, other), belongs)
    case InterfaceView.Navigation{}: Logic.impossible(RuleAuthoredShellRules.settings_classification(node, InterfaceView.Navigation{}, navigation, main, settings, other), belongs)
    case InterfaceView.NavigationHeader{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.Heading{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.PrimaryButton{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.DestructiveButton{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.SelectedButton{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.ComposerActions{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.DialogActions{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.Timeline{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.Activity{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.UserMessage{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.AssistantMessage{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.Composer{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.Approval{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.Toolbar{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.CodeBlock{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.ApprovalQueue{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.Section{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.Dialog{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.Menu{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.Details{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.Card{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.Button{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.Field{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.Content{}: settings_group_found(node, navigation, main, settings, other, identified)
    case InterfaceView.Alert{}: settings_group_found(node, navigation, main, settings, other, identified)


def reverse_layer_accumulator(+remaining: +List<Source.Node>, +acc: +List<Source.Node>, +behind: +List<Source.Node>) ->
  {List.reverse.go(&2, Source.Node, remaining, List.append(&2, Source.Node, acc, behind)) == List.append(&2, Source.Node, List.reverse.go(&2, Source.Node, remaining, acc), behind) : +List<Source.Node>}:
  Std.list_ind(~Source.Node,
    ~(layers => @+accumulator:+List<Source.Node> -> @+background:+List<Source.Node> ->
      {List.reverse.go(&2, Source.Node, layers, List.append(&2, Source.Node, accumulator, background)) == List.append(&2, Source.Node, List.reverse.go(&2, Source.Node, layers, accumulator), background) : +List<Source.Node>}),
    ~(+accumulator => +background => {==}),
    ~(+front => +rest => hypothesis => +accumulator => +background => hypothesis(front <> accumulator, background)), remaining)(acc, behind)

def front_layer_last(+first: Source.Node, +rest: +List<Source.Node>) -> RuleAuthoredShellRules.front_layer_last(first, rest):
  reverse_layer_accumulator(rest, Nil{}, first <> Nil{})

def recipe_structure(recipe: Composition.Recipe) -> RuleAuthoredShellRules.recipe_structure(recipe):
  Composition.Recipe{measure, heading, organization, composer, decisions, latest} = recipe
  {==}

def available_children(children: +List<Source.Node>, maximum: Nat) -> RuleAuthoredShellRules.available_children(children, maximum): {==}

def page_frame(previous: Enclosure.Frame) -> RuleAuthoredShellRules.page_frame(previous): {==}

def measure_width(parameters: Design.LayoutParameters, heading: Composition.Heading, organization: Composition.Body) -> RuleAuthoredShellRules.measure_width(parameters, heading, organization): {==}

def beside_main_style(style: Source.Style, +required: Nat) -> RuleAuthoredShellRules.beside_main_style(style, required):
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, Enclosure.Extent{minimum_width, minimum_height}, scroll, position}, font, chrome, states} = style
  {==}

def compact_main_style(style: Source.Style, required: Nat) -> RuleAuthoredShellRules.compact_main_style(style, required): {==}

def main_population(key: UIIdentity.Key, tag: Source.BoxTag, style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, rest: +List<Source.Node>, structure: Design.MainStructure, maximum: Nat, beside: Bool, required: Nat) -> RuleAuthoredShellRules.main_population(key, tag, style, attributes, children, rest, structure, maximum, beside, required): {==}

def main_placement_input(placement: View.NavigationPlacement, parameters: Design.LayoutParameters, structure: Design.MainStructure, reading_width: Nat, navigation: +List<Source.Node>, main: +List<Source.Node>, settings: +List<Source.Node>, other: +List<Source.Node>, docked: +List<Source.Node>, font: T.Presentation) -> RuleAuthoredShellRules.main_placement_input(placement, parameters, structure, reading_width, navigation, main, settings, other, docked, font):
  match placement:
    case View.LeadingNavigation{}: {==}
    case View.ModalNavigation{}: {==}
    case View.CollapsedNavigation{}: {==}


def beside_floor_fields(measure: Composition.Measure, heading: Composition.Heading, organization: Composition.Body, key: UIIdentity.Key, tag: Source.BoxTag, direction: Model.Direction, main: SpatialModel.Alignment, cross: SpatialModel.Alignment, frame: Enclosure.Frame, width: Model.AxisSize, height: Model.AxisSize, minimum_width: Nat, minimum_height: Nat, scroll: Model.Scroll, position: SpatialModel.Position, font: Source.FontChoice, chrome: Design.Chrome, states: Design.ControlStates, attributes: +List<Source.Attribute>, children: +List<Source.Node>, maximum: Nat, +required: Nat) -> RuleAuthoredShellRules.beside_box_floor(Design.MainStructure{measure, heading, organization}, key, tag, Source.Style{Source.Layout{direction, main, cross, frame, width, height, Enclosure.Extent{minimum_width, minimum_height}, scroll, position}, font, chrome, states}, attributes, children, maximum, required):
  match organization:
    case Composition.CenteredCreation{}: {==}
    case Composition.ChronologicalReading{}: {==}
    case Composition.ProjectSections{}: {==}
    case Composition.ProjectRows{}: {==}
    case Composition.AgentRows{}: {==}
    case Composition.StageColumns{}: {==}
    case Composition.UnavailableNotice{}: {==}

def beside_floor_style(measure: Composition.Measure, heading: Composition.Heading, organization: Composition.Body, key: UIIdentity.Key, tag: Source.BoxTag, style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, maximum: Nat, +required: Nat) -> RuleAuthoredShellRules.beside_box_floor(Design.MainStructure{measure, heading, organization}, key, tag, style, attributes, children, maximum, required):
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, Enclosure.Extent{minimum_width, minimum_height}, scroll, position}, font, chrome, states} = style
  beside_floor_fields(measure, heading, organization, key, tag, direction, main, cross, frame, width, height, minimum_width, minimum_height, scroll, position, font, chrome, states, attributes, children, maximum, required)

def beside_box_floor(structure: Design.MainStructure, key: UIIdentity.Key, tag: Source.BoxTag, style: Source.Style, attributes: +List<Source.Attribute>, children: +List<Source.Node>, maximum: Nat, +required: Nat) -> RuleAuthoredShellRules.beside_box_floor(structure, key, tag, style, attributes, children, maximum, required):
  Design.MainStructure{measure, heading, organization} = structure
  beside_floor_style(measure, heading, organization, key, tag, style, attributes, children, maximum, required)

def RuleAuthoredShellRules.base_shared_classification(node, role, parts): {==}

def RuleAuthoredShellRules.base_group_navigation(node, navigation, main, settings, other): {==}

def RuleAuthoredShellRules.base_group_main(node, navigation, main, settings, other): {==}

def RuleAuthoredShellRules.base_group_footer(node, navigation, main, settings, other): {==}

def RuleAuthoredShellRules.base_group_other(node, navigation, main, settings, other): {==}

def navigation_projection(content: Core.Scene) -> RuleAuthoredShellRules.navigation_projection(content):
  Core.Scene{View.Scene{navigation, main, layers, View.Arrangement{placement}, attention}, settings, transfers, preview, code, directory_picker} = content
  {==}

def assembly_placement(+content: Core.Scene, +theme: Design.Theme, +base: +List<Design.Node>, +overlays: +List<Design.Node>, scope: Maybe<&2, String>, +base_nodes: +List<Source.Node>, +overlay_nodes: +List<Source.Node>, +capacity: View.Capacity, +parameters: Design.LayoutParameters, +layers: +List<View.Layer>, +anchors: +List<Shell.Anchor>, +font: T.Presentation, placement: View.NavigationPlacement,
  projected: {Shell.scene_navigation_placement(content) == placement : View.NavigationPlacement}) -> RuleAuthoredShellRules.assembly_placement(content, theme, base, overlays, scope, base_nodes, overlay_nodes, capacity, parameters, layers, anchors, font, placement):
  Equal.cong(View.NavigationPlacement, Shell.ShellAuthorship,
    (selected => Shell.assembled_parts(Shell.split_overlays(overlay_nodes, capacity, selected, parameters, layers, base, overlays, anchors), Shell.scene_structure(content), Shell.structure_reading_width(Shell.scene_structure(content), parameters), base_nodes, base, selected, parameters, font, theme)), Shell.scene_navigation_placement(content), placement, projected)

def chronological_main_frame(frame: Enclosure.Frame) -> RuleAuthoredShellRules.chronological_main_frame(frame): {==}

def chronological_main_cross() -> RuleAuthoredShellRules.chronological_main_cross(): {==}

def chronological_main_leading(previous: SpatialModel.Alignment) -> RuleAuthoredShellRules.chronological_main_leading(previous): {==}

def chronological_reading_width(+parameters: Design.LayoutParameters) -> RuleAuthoredShellRules.chronological_reading_width(parameters):
  Design.LayoutParameters{navigation_width, main_minimum_width, details_width, reading_width, overview_width, toolbar_height, input_minimum_height, input_maximum_height, line_height, creation_height, lane_width} = parameters
  {==}

def conversation_title_font(+font: Source.FontChoice) -> RuleAuthoredShellRules.conversation_title_font(font):
  match font:
    case Source.InheritFont{}: {==}
    case Source.ExplicitFont{presentation}: {==}

def conversation_title_style(+style: Source.Style) -> RuleAuthoredShellRules.conversation_title_style(style):
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = style
  match direction:
    case Model.Vertical{}: {==}
    case Model.Horizontal{}: {==}
    case Model.ResponsiveHorizontal{}: {==}
    case Model.Layered{}: {==}

def conversation_title_text(+key: UIIdentity.Key, +value: String, +font: Source.FontChoice, wrapping: T.Wrapping) -> RuleAuthoredShellRules.conversation_title_text(key, value, font, wrapping): {==}

def conversation_title_box(+key: UIIdentity.Key, +tag: Source.BoxTag, +style: Source.Style, +attributes: +List<Source.Attribute>, +children: +List<Source.Node>) -> RuleAuthoredShellRules.conversation_title_box(key, tag, style, attributes, children): {==}

def conversation_title_children(+values: +List<Source.Node>) -> RuleAuthoredShellRules.conversation_title_children(values):
  match values:
    case Nil{}: {==}
    case Con{Source.NativeAttachment{key, target, attributes, style, children}, rest}: {==}
    case Con{Source.Box{key, tag, style, attributes, children}, rest}: {==}
    case Con{Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}, rest}: {==}
    case Con{Source.Glyph{key, drawing, style}, rest}: {==}
    case Con{Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}, rest}: {==}
    case Con{Source.RichText{key, style, content, attachments, native_owner}, rest}: {==}
    case Con{Source.Text{key, value, font, wrapping}, rest}: {==}

def conversation_title_other(+node: Source.Node) -> RuleAuthoredShellRules.conversation_title_other(node):
  match node:
    case Source.NativeAttachment{key, target, attributes, style, children}: {==}
    case Source.Box{key, tag, style, attributes, children}: Unit{}
    case Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: {==}
    case Source.Glyph{key, drawing, style}: {==}
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: {==}
    case Source.RichText{key, style, content, attachments, native_owner}: {==}
    case Source.Text{key, value, font, wrapping}: Unit{}

def other_heading_children(+heading: Composition.Heading, key: UIIdentity.Key, style: Source.Style, +children: +List<Source.Node>) -> RuleAuthoredShellRules.other_heading_children(heading, key, style, children):
  match heading:
    case Composition.NoHeading{}: {==}
    case Composition.PageHeading{}: {==}
    case Composition.ConversationHeading{}: Unit{}

def conversation_header_frame(+key: UIIdentity.Key, +style: Source.Style, title: Source.Node, actions: Source.Node) -> RuleAuthoredShellRules.conversation_header_frame(key, style, title, actions):
  Source.Style{layout, font, chrome, states} = style
  {==}

def conversation_main(+measure: Composition.Measure, +key: UIIdentity.Key, tag: Source.BoxTag, +style: Source.Style, attributes: +List<Source.Attribute>, title: Source.Node, actions: Source.Node, remaining: +List<Source.Node>, +maximum: Nat) -> RuleAuthoredShellRules.conversation_main(measure, key, tag, style, attributes, title, actions, remaining, maximum):
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = style
  {==}

def conversation_header(+key: UIIdentity.Key, +style: Source.Style, title: Source.Node, actions: Source.Node) -> RuleAuthoredShellRules.conversation_header(key, style, title, actions):
  Source.Style{layout, font, chrome, states} = style
  {==}

def task_action_flow(+visual: Design.Style, position: Composition.Position) -> RuleAuthoredShellRules.task_action_flow(visual, position): {==}

def RuleAuthoredShellRules.evidence():
  RuleAuthoredShellRules.Requirements{conversation_title_font, conversation_title_style, conversation_title_text, conversation_title_box, conversation_title_children, conversation_title_other, other_heading_children, chronological_main_frame, chronological_main_cross(), chronological_main_leading, chronological_reading_width, conversation_header_frame, conversation_main, conversation_header, task_action_flow, navigation_projection, assembly_placement, beside_box_floor, beside_main_style, compact_main_style, main_population, main_placement_input, measure_width, recipe_structure, available_children, page_frame, front_layer_last, events, interaction, children, wrapper, no_wrapper_events, reading_policy, reading_layout, reading_stretch_width, creation_population, creation_group, creation_group_spacing, creation_reading_width, creation_assembly, creation_child_layout, creation_main, other_main, navigation_box, settings_classification, footer}


def RuleAuthoredShellRules.modal_navigation_geometry(node, capacity, parameters, layers, base, overlays, anchors, docked, floating):
  View.Capacity{navigation_beside, details_beside} = capacity
  Design.LayoutParameters{navigation_width, main_minimum_width, details_width, reading_width, overview_width, toolbar_height, input_minimum_height, input_maximum_height, line_height, creation_height, lane_width} = parameters
  {==}


def RuleAuthoredShellRules.modal_navigation_population(key, tag, style, attributes, children, rest, capacity, parameters, layers, base, overlays, anchors, identified):
  Equal.cong(InterfaceView.Role, Shell.OverlayParts,
    (role => Shell.split_overlay_node(Source.Box{key, tag, style, attributes, children}, role, capacity, View.ModalNavigation{}, parameters, layers, base, overlays, anchors,
      Shell.split_overlays(rest, capacity, View.ModalNavigation{}, parameters, layers, base, overlays, anchors))),
    Shell.base_role(key, overlays), InterfaceView.Navigation{}, identified)

def RuleAuthoredShellRules.modal_navigation_box_preserved(key, tag, direction, main, cross, frame, width, height, minimum, scroll, position, font, chrome, states, attributes, children, capacity, parameters, layers, base, overlays, anchors, docked, floating):
  View.Capacity{navigation_beside, details_beside} = capacity
  Design.LayoutParameters{navigation_width, main_minimum_width, details_width, reading_width, overview_width, toolbar_height, input_minimum_height, input_maximum_height, line_height, creation_height, lane_width} = parameters
  {==}


def RuleAuthoredShellRules.dialog_reading_span(navigation_width, main_minimum_width, details_width, reading_width, overview_width, toolbar_height, input_minimum_height, input_maximum_height, line_height, creation_height, lane_width): {==}

def RuleAuthoredShellRules.dialog_floating_geometry(node, parameters, layers, base, overlays, anchors, docked, floating):
  Design.LayoutParameters{navigation_width, main_minimum_width, details_width, reading_width, overview_width, toolbar_height, input_minimum_height, input_maximum_height, line_height, creation_height, lane_width} = parameters
  {==}


def RuleAuthoredShellRules.dialog_floating_box_preserved(key, tag, direction, main, cross, frame, width, height, minimum, scroll, position, font, chrome, states, attributes, children, parameters, layers, base, overlays, anchors, docked, floating):
  Design.LayoutParameters{navigation_width, main_minimum_width, details_width, reading_width, overview_width, toolbar_height, input_minimum_height, input_maximum_height, line_height, creation_height, lane_width} = parameters
  {==}

def composing_condition(enter: Bool, control: Bool, alt: Bool, shift: Bool, meta: Bool) ->
  {enter && False{} && Bool.not(control) && Bool.not(alt) && Bool.not(shift) && Bool.not(meta) == False{} : Bool}:
  match enter:
    case True{}: {==}
    case False{}: {==}

def absent_gesture(+found: Maybe<&2, InterfaceView.Node>, admitted: Bool,
  absent: {Browser.confirm_source(found) == None{} : Maybe<&2, InterfaceView.Gesture>}) ->
  {Browser.confirm_gesture(found, admitted) == None{} : Maybe<&2, InterfaceView.Gesture>}:
  match admitted:
    case True{}: absent
    case False{}: {==}

def RuleDirectoryEntryLaws.evidence():
  RuleDirectoryEntryLaws.Requirements{
    {==},
    keyboard => control => alt => shift => meta => composing_condition(String.eq(keyboard, "Enter"), control, alt, shift, meta),
    found => {==},
    key => semantic => label => role => editor => text => children => {==},
    +key => keyboard => composing => control => alt => shift => meta => +state => absent =>
      Equal.cong(Maybe<&2, InterfaceView.Gesture>, Browser.Decision, gesture => Browser.apply_gesture(gesture, key, state),
        Browser.confirm_gesture(Browser.found_node(key, state), Browser.confirmation_key(keyboard, composing, control, alt, shift, meta)), None{},
        absent_gesture(Browser.found_node(key, state), Browser.confirmation_key(keyboard, composing, control, alt, shift, meta), absent)),
    +key => keyboard => composing => control => alt => shift => meta => +state => denied =>
      Equal.cong(Bool, Browser.Decision,
        admitted => Browser.apply_gesture(Browser.confirm_gesture(Browser.found_node(key, state), admitted), key, state),
        Browser.confirmation_key(keyboard, composing, control, alt, shift, meta), False{}, denied)}

def ordinary_choice(value: Forms.Observed) ->
  {RuleDirectoryEntryLaws.selection_widget(Controls.value_widget(value, Forms.Choice{})) == True{} : Bool}:
  match value:
    case Forms.ToggleValue{enabled}: {==}
    case Forms.TextValue{text}: {==}
    case Forms.CountValue{count}: {==}
    case Forms.TextsValue{values}: {==}
    case Forms.WorkspaceValue{workspace}: {==}
    case Forms.ContextValue{preview}: {==}
    case Forms.ModelValue{profile, reasoning}: {==}
    case Forms.DeliveryValue{delivery}: {==}
    case Forms.StageValue{stage}: {==}
    case Forms.PriorityValue{priority}: {==}
    case Forms.OwnerValue{owner}: {==}
    case Forms.ProjectValue{project}: {==}
    case Forms.AttachmentsValue{files}: {==}
    case Forms.AssistanceValue{enabled, profile}: {==}
    case Forms.OptionalTextValue{text}: {==}
    case Forms.NotApplicable{}: {==}

def finite_choice(+field: Forms.Field, +value: Forms.Observed) ->
  {RuleDirectoryEntryLaws.selection_widget(Controls.widget_for(Forms.Choice{}, field, value)) == True{} : Bool}:
  match field:
    case Forms.MessageText{}: ordinary_choice(value)
    case Forms.ProjectName{}: ordinary_choice(value)
    case Forms.WorkspaceDirectories{}: ordinary_choice(value)
    case Forms.WorkspacePrimary{}: ordinary_choice(value)
    case Forms.ContextOrigin{}: ordinary_choice(value)
    case Forms.SandboxMode{}: ordinary_choice(value)
    case Forms.NetworkAccess{}: {==}
    case Forms.ApprovalPolicy{}: ordinary_choice(value)
    case Forms.ModelProfile{}: ordinary_choice(value)
    case Forms.ReasoningEffort{}: ordinary_choice(value)
    case Forms.DeliveryIntent{}: ordinary_choice(value)
    case Forms.CardTitle{}: ordinary_choice(value)
    case Forms.CardDescription{}: ordinary_choice(value)
    case Forms.CardStage{}: ordinary_choice(value)
    case Forms.CardPriority{}: ordinary_choice(value)
    case Forms.CardOwner{}: ordinary_choice(value)
    case Forms.CardProject{}: ordinary_choice(value)
    case Forms.CardLabels{}: ordinary_choice(value)
    case Forms.CardAttachments{}: ordinary_choice(value)
    case Forms.ContinueCapture{}: ordinary_choice(value)
    case Forms.AssistedCapture{}: {==}
    case Forms.AssistanceProfile{}: ordinary_choice(value)
    case Forms.AgentName{}: ordinary_choice(value)
    case Forms.AgentInstructions{}: ordinary_choice(value)
    case Forms.AgentConcurrency{}: ordinary_choice(value)
    case Forms.ForkCount{}: ordinary_choice(value)
    case Forms.ForkMessages{}: ordinary_choice(value)
    case Forms.CompactionSummary{}: ordinary_choice(value)

def RuleDirectoryEntryLaws.picker_requirements():
  RuleDirectoryEntryLaws.PickerRequirements{CoreDirectory.directory_picker_requirements(), +editor => +parent => +state => {==}, finite_choice, value => +path => {==}, +editor => +parent => +state => {==}}

def initial_execution(+content: Core.Scene) ->
  {RuleContextControlLaws.execution_observation(Controls.initial(content)) == RuleContextControlLaws.page_observation(content) : Maybe<&2, Context.Observation>}:
  Core.Scene{View.Scene{navigation, main, layers, arrangement, attention}, settings, transfers, preview, code, directory_picker} = content
  Core.Settings{open, access, entered, appearance, open_action, close_action, connect} = settings
  {==}

def RuleContextControlLaws.evidence():
  RuleContextControlLaws.Requirements{
    +key => kind => icon => +selected => description => +input => +availability => +label => role => context => choice_retains_binding(key, kind, icon, selected, description, input, availability, label, role, context),
    kind => icon => +selected => description => +input => +availability => {==},
    kind => icon => +selected => description => +input => +availability => {==},
    +key => semantic => +label => role => kind => icon => +selected => description => +input => +availability => +elements => +native_focus => {==},
    +label => expanded => {==},
    +label => current => +execution => {==},
    initial_execution,
    +origin => +project => +workspace => +sandbox => +approval => +guidance => {==},
    +task => +workspace => +sandbox => +approval => +project => +guidance => +access => {==},
    +reason => {==},
    +label => {==},
    +filesystem => +network => +approval => +name => {==},
    +label => current => execution => {==},
    +label => current => execution => {==},
    {==},
    {==},
    {==},
    {==},
    {==},
    {==},
    +profile => {==}}
