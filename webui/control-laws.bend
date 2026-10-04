import Base
import ./space.bend as Space
import ./typography.bend as T
import ../core/interface.bend as UI
import ../core/SYSTEM.bend as Core
import ../core/user-input.bend as User
import ../core/user-experience.bend as Experience
import ../core/ui-world.bend as View
import ../core/client-services.bend as Services
import ../core/form-fields.bend as Forms
import ../core/code-block.bend as Code
import ../bendlib/domain.bend as Domain
import ./controls.bend as Controls
import ./design.bend as Design
import ./appearance.bend as Appearance

type BoundNode is Data:
  BoundNode{key: String, binding: UI.Meaning, children: +List<BoundNode>}

type Bindings is Data:
  Bindings{base: +List<BoundNode>, overlays: +List<BoundNode>}

def source_binding(+meaning: UI.Meaning) -> UI.Meaning:
  match meaning:
    case UI.PageRegion{region, position}: UI.Region{}
    case UI.Region{}: UI.Region{}
    case UI.LayerRegion{dismiss, outside, escape}: UI.Region{}
    case UI.PanelToggle{expanded, input, availability}: UI.Activate{input, availability}
    case UI.ProjectGroup{project, selected, expanded}: UI.Region{}
    case UI.TaskRow{task, status, selected}: UI.Region{}
    case UI.ProjectChooser{selected}: UI.Region{}
    case UI.DirectoryRow{path, primary}: UI.Region{}
    case UI.ContextSummary{observation}: UI.Region{}
    case UI.ChoiceGroup{}: UI.Region{}
    case UI.ComposerAction{subject, input, availability}: UI.Activate{input, availability}
    case UI.Choice{selected, description, input, availability}: UI.Activate{input, availability}
    case UI.BoardLane{stage, count}: UI.Region{}
    case UI.CardArchive{count}: UI.Region{}
    case UI.BoardGroup{grouping}: UI.Region{}
    case UI.ReadOnly{text}: UI.Region{}
    case UI.TaskFacts{details}: UI.Region{}
    case UI.CodeFacts{view}: UI.Region{}
    case UI.ActivityContent{expanded, audit}: UI.Region{}
    case UI.PageContext{conversation}: UI.Region{}
    case UI.Edit{editor, field, Forms.DirectoryCollection{}, value, choices}: UI.Region{}
    case UI.Edit{editor, field, Forms.FileCollection{}, value, choices}: UI.Region{}
    case _: meaning

def binding(representation: Controls.Representation) -> UI.Meaning:
  match representation:
    case Controls.NoControl{}: UI.Region{}
    case Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}:
      UI.Activate{input, availability}
    case Controls.Input{meaning, name, widget, label, availability}: meaning
    case Controls.Movable{destinations, face, name, handle, geometry, help}: UI.MovableCard{destinations, face}

def action_retains_binding(+key: String, +input: Core.Input, +availability: View.Availability,
  label: String, role: UI.Role, context: Controls.Context) ->
  {binding(Controls.make_action(key, input, availability, label, role, context)) ==
    UI.Activate{input, availability} : UI.Meaning}:
  match context:
    case Controls.Context{area, selection, code, appearance, access, open, layers, execution, source_family}: {==}

def panel_toggle_fields_retains_binding(+expanded: Bool, value: Controls.Representation) ->
  {binding(Controls.panel_toggle_fields(expanded, value)) == binding(value) : UI.Meaning}:
  match value:
    case Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}: {==}
    case Controls.NoControl{}: {==}
    case Controls.Input{meaning, name, widget, label, availability}: {==}
    case Controls.Movable{destinations, face, name, handle, geometry, help}: {==}

def panel_toggle_retains_binding(+key: String, expanded: Bool, +input: Core.Input, +availability: View.Availability,
  label: String, role: UI.Role, context: Controls.Context) ->
  {binding(Controls.make_panel_toggle(key, expanded, input, availability, label, role, context)) == UI.Activate{input, availability} : UI.Meaning}:
  match context:
    case Controls.Context{area, selection, code, appearance, access, open, layers, execution, source_family}: {==}

def choice_retains_binding(+key: String, selected: Bool, description: String, +input: Core.Input, +availability: View.Availability,
  label: String, role: UI.Role, context: Controls.Context) ->
  {binding(Controls.make_choice(key, selected, description, input, availability, label, role, context)) ==
    UI.Activate{input, availability} : UI.Meaning}:
  match context:
    case Controls.Context{area, selection, code, appearance, access, open, layers, execution, source_family}: {==}

def composer_action_retains_binding(+key: String, subject: View.ComposerSubject, +input: Core.Input,
  +availability: View.Availability, label: String, role: UI.Role, context: Controls.Context) ->
  {binding(Controls.make_composer_action(key, subject, input, availability, label, role, context)) ==
    UI.Activate{input, availability} : UI.Meaning}:
  match context:
    case Controls.Context{area, selection, code, appearance, access, open, layers, execution, source_family}: {==}

def presented_action_retains_binding(input: Core.Input, availability: View.Availability, name: String, projection: Controls.ActionPresentation, placement: Controls.Placement, help: Controls.Help, feedback: Controls.Feedback) ->
  {binding(Controls.presented_action(input, availability, name, projection, placement, help, feedback)) == UI.Activate{input, availability} : UI.Meaning}:
  match projection:
    case Controls.ActionPresentation{face, behavior, geometry}: {==}

def source_action_retains_binding(area: Controls.Area, family: Controls.SourceFamily, +value: Controls.Representation) ->
  {binding(Controls.source_action(area, family, value)) == binding(value) : UI.Meaning}:
  match value:
    case Controls.Action{+input, availability, +name, face, behavior, geometry, placement, help, feedback}:
      presented_action_retains_binding(input, availability, name, Controls.source_presentation(area, family, input, name, face, behavior, geometry), placement, help, feedback)
    case Controls.NoControl{}: {==}
    case Controls.Input{meaning, name, widget, label, availability}: {==}
    case Controls.Movable{destinations, face, name, handle, geometry, help}: {==}

def represented_action_retains_binding(+key: String, +input: Core.Input, +availability: View.Availability,
  +label: String, +role: UI.Role, +context: Controls.Context) ->
  {binding(Controls.represent_action(key, input, availability, label, role, context)) == UI.Activate{input, availability} : UI.Meaning}:
  Controls.Context{+area, selection, code, appearance, access, open, layers, execution, +family} = context
  Equal.trans(UI.Meaning,
    binding(Controls.represent_action(key, input, availability, label, role, context)),
    binding(Controls.make_action(key, input, availability, label, role, context)), UI.Activate{input, availability},
    source_action_retains_binding(area, family, Controls.make_action(key, input, availability, label, role, context)),
    action_retains_binding(key, input, availability, label, role, context))

def representation_retains_binding(+key: String, +meaning: UI.Meaning, label: String,
  role: UI.Role, context: Controls.Context) ->
  {binding(Controls.represent(key, meaning, label, role, context)) == source_binding(meaning) : UI.Meaning}:
  match meaning:
    case UI.ComposerAction{subject, input, availability}: composer_action_retains_binding(key, subject, input, availability, label, role, context)
    case UI.Activate{input, availability}: represented_action_retains_binding(key, input, availability, label, role, context)
    case UI.PanelToggle{expanded, input, availability}: panel_toggle_retains_binding(key, expanded, input, availability, label, role, context)
    case UI.Choice{selected, description, input, availability}: choice_retains_binding(key, selected, description, input, availability, label, role, context)
    case UI.ProjectGroup{project, selected, expanded}: {==}
    case UI.TaskRow{task, status, selected}: {==}
    case UI.ProjectChooser{selected}: {==}
    case UI.DirectoryRow{path, primary}: {==}
    case UI.ContextSummary{observation}: {==}
    case UI.ChoiceGroup{}: {==}

    case UI.Edit{editor, field, entry, value, choices}:
      match entry:
        case Forms.DisplayOnly{}: {==}
        case Forms.SingleLine{}: {==}
        case Forms.Multiline{}: {==}
        case Forms.Choice{}: {==}
        case Forms.MultipleChoices{}: {==}
        case Forms.PositiveInteger{}: {==}
        case Forms.DirectoryCollection{}: {==}
        case Forms.FileCollection{}: {==}
    case UI.SearchChoices{query}: {==}
    case UI.EnterCredential{entered}: {==}
    case UI.BoardSearch{filter}: {==}
    case UI.ReceiveFile{editor, enabled}: {==}
    case UI.EnterDirectory{editor, text}: {==}
    case UI.DirectoryBrowserLocation{value}: {==}
    case UI.BoardProfile{automatic, selected, choices, enabled}: {==}
    case UI.MovableCard{destinations, face}: {==}
    case UI.BoardLane{stage, count}: {==}
    case UI.CardArchive{count}: {==}
    case UI.BoardGroup{grouping}: {==}
    case UI.PageRegion{region, position}: {==}
    case UI.Region{}: {==}
    case UI.LayerRegion{dismiss, outside, escape}: {==}
    case UI.ReadOnly{text}: {==}
    case UI.TaskFacts{details}: {==}
    case UI.CodeFacts{view}: {==}
    case UI.ActivityContent{expanded, audit}: {==}
    case UI.PageContext{conversation}: {==}

def source_nodes(values: +List<UI.Node>) -> +List<BoundNode>:
  match values:
    case Nil{}: Nil{}
    case Con{UI.Node{key, semantic, label, role, meaning, children}, rest}:
      Con{BoundNode{key, source_binding(meaning), source_nodes(children)}, source_nodes(rest)}

def presented_nodes(values: +List<Design.Node>) -> +List<BoundNode>:
  match values:
    case Nil{}: Nil{}
    case Con{Design.Node{key, semantic, label, role, meaning, style, control, children}, rest}:
      Con{BoundNode{key, binding(control), presented_nodes(children)}, presented_nodes(rest)}

def nodes_retain_bindings(values: +List<UI.Node>, +context: Controls.Context, +typography: T.Presentation, +in_main: Bool, +start: Bool) ->
  {presented_nodes(Appearance.nodes_at(values, context, typography, in_main, start)) == source_nodes(values) : +List<BoundNode>}:
  match values:
    case Nil{}: {==}
    case Con{UI.Node{+key, +semantic, +label, +role, +meaning, +children}, +rest}:
      +local = Controls.enter(UI.Node{key, semantic, label, role, meaning, children}, context)
      +inside = Appearance.enters_main(role, in_main)
      +inherited_text = Appearance.information_role(role, meaning, typography, inside, start)
      +child_text = Design.style_text(Appearance.prepared_style(key, semantic, role, meaning, local,
        Controls.represent(key, meaning, label, role, local), inherited_text))
      +meaning_step = Equal.cong(UI.Meaning, +List<BoundNode>,
        (bound => Con{BoundNode{key, bound, presented_nodes(Appearance.nodes_at(children, local, child_text, inside, start))},
          presented_nodes(Appearance.nodes_at(rest, context, typography, in_main, start))}),
        binding(Controls.represent(key, meaning, label, role, local)), source_binding(meaning),
        representation_retains_binding(key, meaning, label, role, local))
      +child_step = Equal.cong(+List<BoundNode>, +List<BoundNode>,
        (bound_children => Con{BoundNode{key, source_binding(meaning), bound_children},
          presented_nodes(Appearance.nodes_at(rest, context, typography, in_main, start))}),
        presented_nodes(Appearance.nodes_at(children, local, child_text, inside, start)), source_nodes(children),
        nodes_retain_bindings(children, local, child_text, inside, start))
      +rest_step = Equal.cong(+List<BoundNode>, +List<BoundNode>,
        (bound_rest => Con{BoundNode{key, source_binding(meaning), source_nodes(children)}, bound_rest}),
        presented_nodes(Appearance.nodes_at(rest, context, typography, in_main, start)), source_nodes(rest),
        nodes_retain_bindings(rest, context, typography, in_main, start))
      +head_steps = Equal.trans(+List<BoundNode>,
        Con{BoundNode{key, binding(Controls.represent(key, meaning, label, role, local)),
          presented_nodes(Appearance.nodes_at(children, local, child_text, inside, start))}, presented_nodes(Appearance.nodes_at(rest, context, typography, in_main, start))},
        Con{BoundNode{key, source_binding(meaning), presented_nodes(Appearance.nodes_at(children, local, child_text, inside, start))},
          presented_nodes(Appearance.nodes_at(rest, context, typography, in_main, start))},
        Con{BoundNode{key, source_binding(meaning), source_nodes(children)},
          presented_nodes(Appearance.nodes_at(rest, context, typography, in_main, start))}, meaning_step, child_step)
      +steps = Equal.trans(+List<BoundNode>,
        Con{BoundNode{key, binding(Controls.represent(key, meaning, label, role, local)),
          presented_nodes(Appearance.nodes_at(children, local, child_text, inside, start))}, presented_nodes(Appearance.nodes_at(rest, context, typography, in_main, start))},
        Con{BoundNode{key, source_binding(meaning), source_nodes(children)},
          presented_nodes(Appearance.nodes_at(rest, context, typography, in_main, start))},
        Con{BoundNode{key, source_binding(meaning), source_nodes(children)}, source_nodes(rest)}, head_steps, rest_step)
      Equal.trans(+List<BoundNode>,
        presented_nodes(Appearance.nodes_at(Con{UI.Node{key, semantic, label, role, meaning, children}, rest}, context, typography, in_main, start)),
        Con{BoundNode{key, binding(Controls.represent(key, meaning, label, role, local)),
          presented_nodes(Appearance.nodes_at(children, local, child_text, inside, start))}, presented_nodes(Appearance.nodes_at(rest, context, typography, in_main, start))},
        Con{BoundNode{key, source_binding(meaning), source_nodes(children)}, source_nodes(rest)}, {==}, steps)

def visual_bindings(visuals: Design.Surface) -> Bindings:
  Design.Surface{content, theme, base, overlays, active_scope} = visuals
  Bindings{presented_nodes(base), presented_nodes(overlays)}

def surface_bindings(surface: UI.Surface) -> Bindings:
  UI.Surface{content, base, overlays, active_scope} = surface
  Bindings{source_nodes(base), source_nodes(overlays)}

def fields_retain_bindings(content: Core.Scene, +base: +List<UI.Node>, +overlays: +List<UI.Node>,
  +context: Controls.Context, system_dark: Bool, active_scope: Maybe<&2, String>, +scale: T.Scale) ->
  {visual_bindings(Appearance.present_fields(content, base, overlays, context, system_dark, active_scope, scale)) ==
    Bindings{source_nodes(base), source_nodes(overlays)} : Bindings}:
  match content:
    case Core.Scene{view, settings, transfers, preview, code, directory_picker}:
      match settings:
        case Core.Settings{open, access, entered, appearance, open_action, close_action, connect}:
          +base_step = Equal.cong(+List<BoundNode>, Bindings,
            (bound_base => Bindings{bound_base, presented_nodes(Appearance.nodes_at(overlays, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, False{}))}),
            presented_nodes(Appearance.nodes_at(base, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, Appearance.start_page(content))), source_nodes(base), nodes_retain_bindings(base, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, Appearance.start_page(content)))
          +overlay_step = Equal.cong(+List<BoundNode>, Bindings,
            (bound_overlays => Bindings{source_nodes(base), bound_overlays}),
            presented_nodes(Appearance.nodes_at(overlays, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, False{})), source_nodes(overlays), nodes_retain_bindings(overlays, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, False{}))
          Equal.trans(Bindings,
            Bindings{presented_nodes(Appearance.nodes_at(base, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, Appearance.start_page(content))), presented_nodes(Appearance.nodes_at(overlays, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, False{}))},
            Bindings{source_nodes(base), presented_nodes(Appearance.nodes_at(overlays, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, False{}))},
            Bindings{source_nodes(base), source_nodes(overlays)}, base_step, overlay_step)

def present_retains_bindings(surface: UI.Surface, system_dark: Bool, +scale: T.Scale) ->
  {visual_bindings(Appearance.present(surface, system_dark, scale)) == surface_bindings(surface) : Bindings}:
  match surface:
    case UI.Surface{+content, base, overlays, active_scope}:
      fields_retain_bindings(content, base, overlays, Controls.initial(content), system_dark, active_scope, scale)

def expected_icon_help(availability: View.Availability, label: String) -> Controls.Help:
  match availability:
    case View.Available{}: Controls.Tooltip{label, 300n, True{}, True{}, False{}}
    case View.NeedsDirectoryObservation{}: Controls.Tooltip{label, 300n, True{}, True{}, False{}}
    case View.Unavailable{reason}: Controls.Tooltip{reason, 300n, True{}, True{}, False{}}

# Message editors share the arrow form across Send/Steer. The action identity,
# name, availability, and disabled explanation remain those of that observation.
def expected_message(+editor: User.Editor, +availability: View.Availability, +label: String) -> Controls.Representation:
  Controls.Action{Core.ApplicationInput{Experience.UserInput{User.Activate{User.Submit{editor}}}},
    availability, label, Controls.IconFace{Controls.ArrowUp{}}, Controls.Push{},
    Controls.Geometry{Space.fixed_demand(32n, 32n), 16n, 16n, 0n}, Controls.ComposerEnd{},
    expected_icon_help(availability, label), Controls.Quiet{}}

def message_uses_arrow_law(-key: String, -task: Nat, -availability: View.Availability, -label: String, -role: UI.Role, -selection: Controls.Selection, -code: Maybe<&2, Code.Scene>, -appearance: Services.Appearance, -access: Services.Access, -open: Bool, -layers: +List<View.Layer>) -> Type:
  {Controls.represent(key, UI.Activate{Core.ApplicationInput{Experience.UserInput{User.Activate{User.Submit{User.MessageEditor{task}}}}}, availability},
      label, role, Controls.Context{Controls.ComposerArea{}, selection, code, appearance, access, open, layers, None{}, Controls.Unscoped{}}) ==
      expected_message(User.MessageEditor{task}, availability, label) : Controls.Representation}

def message_uses_arrow(+key: String, task: Nat, +availability: View.Availability,
  +label: String, role: UI.Role, selection: Controls.Selection, code: Maybe<&2, Code.Scene>,
  appearance: Services.Appearance, access: Services.Access, open: Bool, layers: +List<View.Layer>) -> message_uses_arrow_law(key, task, availability, label, role, selection, code, appearance, access, open, layers):
  match availability:
    case View.Available{}: {==}
    case View.NeedsDirectoryObservation{}: {==}
    case View.Unavailable{reason}: {==}

def creation_uses_arrow_law(-key: String, -availability: View.Availability, -label: String, -role: UI.Role, -selection: Controls.Selection, -code: Maybe<&2, Code.Scene>, -appearance: Services.Appearance, -access: Services.Access, -open: Bool, -layers: +List<View.Layer>) -> Type:
  {Controls.represent(key, UI.Activate{Core.ApplicationInput{Experience.UserInput{User.Activate{User.Submit{User.NewTaskEditor{}}}}}, availability},
      label, role, Controls.Context{Controls.ComposerArea{}, selection, code, appearance, access, open, layers, None{}, Controls.Unscoped{}}) ==
      expected_message(User.NewTaskEditor{}, availability, label) : Controls.Representation}

def creation_uses_arrow(+key: String, +availability: View.Availability,
  +label: String, role: UI.Role, selection: Controls.Selection, code: Maybe<&2, Code.Scene>,
  appearance: Services.Appearance, access: Services.Access, open: Bool, layers: +List<View.Layer>) -> creation_uses_arrow_law(key, availability, label, role, selection, code, appearance, access, open, layers):
  match availability:
    case View.Available{}: {==}
    case View.NeedsDirectoryObservation{}: {==}
    case View.Unavailable{reason}: {==}

def menu_text(face: Controls.Face) -> Maybe<&2, String>:
  match face:
    case Controls.IconFace{icon}: None{}
    case Controls.TextFace{text}: Some{text}
    case Controls.SingleLineFace{text}: Some{text}
    case Controls.IconTextFace{icon, text}: Some{text}
    case Controls.PickerFace{icon, text}: Some{text}
    case Controls.ChoiceFace{text, description, checked}: Some{text}
    case Controls.DisclosureFace{text, expanded}: Some{text}
    case Controls.PermissionFace{filesystem, network, approval}: None{}

def required_menu_text(purpose: Controls.Purpose, label: String) -> Maybe<&2, String>:
  match purpose:
    case Controls.Dismiss{}: None{}
    case _: Some{label}

def named_face_has_text(icon: Maybe<&2, Controls.Icon>, +label: String) ->
  {menu_text(Controls.named_face(icon, label, False{})) == Some{label} : Maybe<&2, String>}:
  match icon:
    case None{}: {==}
    case Some{icon}: {==}

def menu_preserves_labels(+purpose: Controls.Purpose, +label: String) ->
  {menu_text(Controls.face_for(purpose, label, Controls.MenuArea{})) == required_menu_text(purpose, label) : Maybe<&2, String>}:
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
    case Code.CopyPending{}: {==}
    case Code.CopySucceeded{}: {==}
    case Code.CopyFailed{}: {==}



type Choice is Data:
  Choice{face: Controls.Face, behavior: Controls.Behavior}

def choice(representation: Controls.Representation) -> Maybe<&2, Choice>:
  match representation:
    case Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}:
      Some{Choice{face, behavior}}
    case _: None{}









def action_text(representation: Controls.Representation) -> Maybe<&2, String>:
  match representation:
    case Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}: menu_text(face)
    case _: None{}

def action_face(representation: Controls.Representation) -> Maybe<&2, Controls.Face>:
  match representation:
    case Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}: Some{face}
    case _: None{}

def declared_action_face(node: UI.Node, context: Controls.Context) -> Maybe<&2, Controls.Face>:
  UI.Node{key, semantic, label, role, meaning, children} = node
  action_face(Controls.represent(key, meaning, label, role, context))

def root_removal_faces(roots: +List<View.WorkspaceRoot>, +parent: String, +state: Core.State,
  +context: Controls.Context) -> +List<Maybe<&2, Controls.Face>>:
  match roots:
    case Nil{}: Nil{}
    case Con{View.WorkspaceRoot{path, primary, choose, remove}, rest}:
      declared_action_face(UI.declared(parent, remove, state), context) <> root_removal_faces(rest, parent, state, context)

def workspace_removal_faces(workspace: View.WorkspaceControls, parent: String, state: Core.State,
  context: Controls.Context) -> +List<Maybe<&2, Controls.Face>>:
  View.WorkspaceControls{editor, roots, inherit} = workspace
  root_removal_faces(roots, parent, state, context)

def directory_removal_uses_cross(+parent: String, +editor: User.Editor, +path: String,
  primary: Maybe<&2, String>, state: Core.State, context: Controls.Context) ->
  {workspace_removal_faces(View.workspace_controls(Domain.Workspace{[path], primary}, editor, None{}),
    parent, state, context) == [Some{Controls.IconFace{Controls.CloseCross{}}}] : +List<Maybe<&2, Controls.Face>>}:
  match state context:
    case Core.State{application, services} Controls.Context{area, selection, code, appearance, access, open, layers, execution, source_family}: {==}

def approval_keeps_label_law(-key: String, -task: Nat, -operation: Nat, -allow: Bool, -reason: String, -availability: View.Availability, -label: String, -role: UI.Role, -selection: Controls.Selection, -code: Maybe<&2, Code.Scene>, -appearance: Services.Appearance, -access: Services.Access, -open: Bool, -layers: +List<View.Layer>) -> Type:
  {action_text(Controls.represent(key, UI.Activate{Core.ApplicationInput{Experience.UserInput{
      User.Activate{User.ReviewApproval{task, operation, allow, reason}}}}, availability}, label, role,
      Controls.Context{Controls.ApprovalArea{}, selection, code, appearance, access, open, layers, None{}, Controls.Unscoped{}})) ==
      Some{label} : Maybe<&2, String>}

def approval_keeps_label(key: String, task: Nat, operation: Nat, allow: Bool, reason: String,
  availability: View.Availability, +label: String, role: UI.Role, selection: Controls.Selection,
  code: Maybe<&2, Code.Scene>, appearance: Services.Appearance, access: Services.Access, open: Bool,
  layers: +List<View.Layer>) -> approval_keeps_label_law(key, task, operation, allow, reason, availability, label, role, selection, code, appearance, access, open, layers):
  match allow:
    case True{}: {==}
    case False{}: {==}

type HelpAccess is Data:
  HelpAccess{pointer: Bool, keyboard: Bool, takes_focus: Bool}

def help_access(help: Controls.Help) -> HelpAccess:
  match help:
    case Controls.NoHelp{}: HelpAccess{False{}, False{}, False{}}
    case Controls.Tooltip{text, delay, pointer, keyboard, takes_focus}:
      HelpAccess{pointer, keyboard, takes_focus}













type Requirements is Type:
  Requirements{
    present_retains_bindings: @+scale:T.Scale -> @surface:UI.Surface -> @system_dark:Bool ->
      {visual_bindings(Appearance.present(surface, system_dark, scale)) == surface_bindings(surface) : Bindings},
    message_uses_arrow: @+key:String -> @task:Nat -> @+availability:View.Availability -> @+label:String -> @role:UI.Role ->
      @selection:Controls.Selection -> @code:Maybe<&2, Code.Scene> -> @appearance:Services.Appearance ->
      @access:Services.Access -> @open:Bool -> @layers:+List<View.Layer> ->
      message_uses_arrow_law(key, task, availability, label, role, selection, code, appearance, access, open, layers),
    creation_uses_arrow: @+key:String -> @+availability:View.Availability -> @+label:String -> @role:UI.Role ->
      @selection:Controls.Selection -> @code:Maybe<&2, Code.Scene> -> @appearance:Services.Appearance ->
      @access:Services.Access -> @open:Bool -> @layers:+List<View.Layer> ->
      creation_uses_arrow_law(key, availability, label, role, selection, code, appearance, access, open, layers),
    menu_preserves_labels: @+purpose:Controls.Purpose -> @+label:String ->
      {menu_text(Controls.face_for(purpose, label, Controls.MenuArea{})) == required_menu_text(purpose, label) : Maybe<&2, String>},
    copy_keeps_space: @state:Code.CopyState ->
      {Controls.geometry_for(Controls.CopyCode{state}, Controls.face_for(Controls.CopyCode{state}, "Copy code", Controls.CodeArea{}), Controls.CodeArea{}) ==
        Controls.Geometry{Space.fixed_demand(32n, 32n), 16n, 8n, 0n} : Controls.Geometry},
    radio_reserves_check: @label:String -> @checked:Bool ->
      {Controls.geometry_for(Controls.SelectedOption{checked}, Controls.ChoiceFace{label, None{}, checked}, Controls.MenuArea{}) ==
        Controls.Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 20n} : Controls.Geometry},
    model_option_marks_current: @+key:String -> @editor:User.Editor -> @+profile:String -> @reasoning:String ->
      @+current:String -> @+label:String -> @role:UI.Role -> @code:Maybe<&2, Code.Scene> ->
      @appearance:Services.Appearance -> @access:Services.Access -> @open:Bool -> @layers:+List<View.Layer> ->
      {choice(Controls.represent(key, UI.Activate{Core.ApplicationInput{Experience.UserInput{
          User.EditDraft{editor, User.ChooseModel{profile, reasoning}}}}, View.Available{}}, label, role,
          Controls.Context{Controls.MenuArea{}, Controls.ModelSelection{current}, code, appearance, access, open, layers, None{}, Controls.Unscoped{}})) ==
          Some{Choice{Controls.ChoiceFace{label, None{}, String.eq(profile, current)}, Controls.Radio{String.eq(profile, current)}}} : Maybe<&2, Choice>},
    delivery_option_marks_current: @+key:String -> @task:Nat -> @+delivery:User.Delivery -> @+current:User.Delivery ->
      @+label:String -> @role:UI.Role -> @code:Maybe<&2, Code.Scene> -> @appearance:Services.Appearance ->
      @access:Services.Access -> @open:Bool -> @layers:+List<View.Layer> ->
      {choice(Controls.represent(key, UI.Activate{Core.ApplicationInput{Experience.UserInput{
          User.EditDraft{User.MessageEditor{task}, User.ChooseDelivery{delivery}}}}, View.Available{}}, label, role,
          Controls.Context{Controls.MenuArea{}, Controls.DeliverySelection{current}, code, appearance, access, open, layers, None{}, Controls.Unscoped{}})) ==
          Some{Choice{Controls.ChoiceFace{label, None{}, Controls.same_delivery(delivery, current)},
            Controls.Radio{Controls.same_delivery(delivery, current)}}} : Maybe<&2, Choice>},
    approval_keeps_label: @key:String -> @task:Nat -> @operation:Nat -> @allow:Bool -> @reason:String ->
      @availability:View.Availability -> @+label:String -> @role:UI.Role -> @selection:Controls.Selection ->
      @code:Maybe<&2, Code.Scene> -> @appearance:Services.Appearance -> @access:Services.Access -> @open:Bool -> @layers:+List<View.Layer> ->
      approval_keeps_label_law(key, task, operation, allow, reason, availability, label, role, selection, code, appearance, access, open, layers),
    icon_help_supports_focus: @icon:Controls.Icon -> @availability:View.Availability -> @feedback:Controls.Feedback -> @label:String ->
      {help_access(Controls.help_for(Controls.IconFace{icon}, availability, feedback, label)) ==
        HelpAccess{True{}, True{}, False{}} : HelpAccess},
    input_label_is_accessible_only: @value:Forms.Observed ->
      {Controls.label_placement(Controls.widget_for(Forms.Multiline{}, Forms.MessageText{}, value)) ==
        Controls.AccessibleOnly{} : Controls.LabelPlacement},
    settings_uses_gear: @expanded:Bool -> @label:String ->
      {Controls.face_for(Controls.OpenPanel{Controls.Settings{}, False{}, expanded}, label, Controls.PageArea{}) == Controls.IconFace{Controls.Settings{}} : Controls.Face},
    introduction_uses_context_label: @expanded:Bool -> @+label:String ->
      {Controls.face_for(Controls.WorkspacePicker{expanded}, label, Controls.ComposerArea{}) == Controls.PickerFace{Some{Controls.Folder{}}, label} : Controls.Face},
    directory_removal_uses_cross: @+parent:String -> @+editor:User.Editor -> @+path:String ->
      @primary:Maybe<&2, String> -> @state:Core.State -> @context:Controls.Context ->
      {workspace_removal_faces(View.workspace_controls(Domain.Workspace{[path], primary}, editor, None{}),
        parent, state, context) == [Some{Controls.IconFace{Controls.CloseCross{}}}] : +List<Maybe<&2, Controls.Face>>},
    directory_parent_has_no_control: @choices:+List<Forms.ChoiceValue> -> @key:String -> @editor:User.Editor -> @field:Forms.Field -> @value:Forms.Observed -> @label:String -> @role:UI.Role -> @context:Controls.Context ->
      {Controls.represent(key, UI.Edit{editor, field, Forms.DirectoryCollection{}, value, choices}, label, role, context) == Controls.NoControl{} : Controls.Representation},
    file_parent_has_no_control: @choices:+List<Forms.ChoiceValue> -> @key:String -> @editor:User.Editor -> @field:Forms.Field -> @value:Forms.Observed -> @label:String -> @role:UI.Role -> @context:Controls.Context ->
      {Controls.represent(key, UI.Edit{editor, field, Forms.FileCollection{}, value, choices}, label, role, context) == Controls.NoControl{} : Controls.Representation}
  }

def evidence() -> Requirements:
  Requirements{
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
