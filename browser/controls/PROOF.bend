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
