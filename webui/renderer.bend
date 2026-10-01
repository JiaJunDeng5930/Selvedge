import Base
import ./document.bend as Doc
import ./MODEL.bend as Web
import ./design.bend as Design
import ./layout.bend as Layout
import ./controls.bend as Controls
import ../core/interface.bend as UI
import ../core/composition.bend as Composition
import ../core/form-fields.bend as Forms
import ../core/ui-world.bend as View
import ../core/code-block.bend as Code
import ../core/user-context.bend as Context
import ../bendlib/domain.bend as Domain
import ../BOARD.bend as Board
import ../core/user-input.bend as User
import ../core/SYSTEM.bend as Core
import ../core/user-conversation.bend as Conversation
import ../REASONING.bend as Reasoning
import ../bendlib/json.bend as Json

type ReadingIdentity is Data:
  ReadingIdentity{task: Nat, generation: Nat}

# Every browser primitive is selected here. Geometry is in viewport coordinates;
# the host must not subtract a parent box or choose controls from product state.
def property(name: String, value: String) -> Doc.Property:
  Doc.Property{name, value}





def px(value: Nat) -> String:
  Nat.show(value) ++ "px"





def paint(value: Design.Paint) -> String:
  match value:
    case Design.Transparent{}: "transparent"
    case Design.ThemeToken{name}: "var(" ++ name ++ ")"





def font(value: Design.Font) -> String:
  match value:
    case Design.InterfaceFont{}: "var(--font-sans, system-ui)"
    case Design.MonospaceFont{}: "var(--font-mono, monospace)"





def icon_path(value: Controls.Icon) -> String:
  match value:
    case Controls.StopSquare{}: "M6 5h8a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1Z"
    case Controls.PauseBars{}: "M7 5v10M13 5v10"
    case Controls.PlayTriangle{}: "m7 4 9 6-9 6Z"
    case Controls.CloseCross{}: "m5 5 10 10M15 5 5 15"
    case Controls.MoreDots{}: "M4 10h.01M10 10h.01M16 10h.01"
    case Controls.Sidebar{}: "M3 4h14v12H3ZM7 4v12"
    case Controls.Folder{}: "M2.5 6V4.5h5l2 2h8V16h-15Z"
    case Controls.Conversation{}: "M3 3.5h14v10H8l-5 3Z"
    case Controls.Columns{}: "M3 3h14v14H3ZM7.7 3v14M12.3 3v14"
    case Controls.Agents{}: "M13 9a3 3 0 1 0-6 0 3 3 0 0 0 6 0ZM4 17v-1a4 4 0 0 1 4-4h4a4 4 0 0 1 4 4v1"
    case Controls.Plus{}: "M10 3v14M3 10h14"
    case Controls.Pencil{}: "m12.5 3 4.5 4.5-9 9-5 1 1-5ZM10.5 5l4.5 4.5"
    case Controls.Branch{}: "M6 4v12M6 11h4a4 4 0 0 0 4-4V4M4 2h4v4H4ZM4 14h4v4H4ZM12 2h4v4h-4Z"
    case Controls.Compact{}: "M3 5h14M3 10h10M3 15h7m3-2 3 3 3-3M16 10v6"
    case Controls.Settings{}: "m8 2-.5 2-2 .9-1.8-.5-1.5 2.5 1.4 1.4v2.4l-1.4 1.4L3.7 15l1.8-.5 2 .9.5 2.1h3l.5-2.1 2-.9 1.8.5 1.5-2.5-1.4-1.4V8.7l1.4-1.4-1.5-2.5-1.8.5-2-.9L11 2Zm4.5 8a2.5 2.5 0 1 1-5 0 2.5 2.5 0 0 1 5 0Z"
    case Controls.Inspector{}: "M3 3h14v14H3ZM12 3v14M5.5 6h4M5.5 10h4M5.5 14h4"
    case Controls.CopySheets{}: "M7 7h10v10H7ZM13 4V3H3v10h1"
    case Controls.WrapLines{}: "M3 5h14M3 10h11a3 3 0 0 1 0 6h-4m2-2-2 2 2 2M3 15h3"
    case Controls.Warning{}: "m10 2 8 15H2ZM10 7v4M10 14h.01"
    case Controls.Spinner{}: "M10 2a8 8 0 1 1-8 8"
    case Controls.Trash{}: "M3 5h14M7 5V3h6v2M5 5l1 12h8l1-12M8 8v6M12 8v6"
    case Controls.ArchiveBox{}: "M3 3h14v4H3ZM4 7v10h12V7M8 10h4"
    case Controls.Restore{}: "M3 4v5h5M3 9a7 7 0 1 1 0 4"
    case Controls.Pin{}: "m7 2 7 3-2 4 1 3-8-3 3-1ZM8 10l-4 7"
    case Controls.Refresh{}: "M16 7a7 7 0 0 0-12-1M16 3v4h-4M4 13a7 7 0 0 0 12 1M4 17v-4h4"
    case Controls.Undo{}: "M7 5 3 9l4 4M3 9h8a5 5 0 0 1 5 5"
    case Controls.Download{}: "M10 2v11m-4-4 4 4 4-4M3 13v4h14v-4"
    case Controls.Preview{}: "M2 10s3-6 8-6 8 6 8 6-3 6-8 6-8-6-8-6Zm10.5 0a2.5 2.5 0 1 1-5 0 2.5 2.5 0 0 1 5 0Z"
    case Controls.Paperclip{}: "m7 10 5-5a3 3 0 0 1 4 4l-8 8a4 4 0 0 1-6-6l8-8m-3 7 5-5"
    case Controls.Grip{}: "M7 4h.01M13 4h.01M7 10h.01M13 10h.01M7 16h.01M13 16h.01"
    case Controls.ArrowUp{}: "M9.33467 16.6663V4.93978L4.6374 9.63704L4.1667 9.16634L3.69599 8.69661L9.52998 2.86263L9.63447 2.77767C9.8925 2.60753 10.2433 2.63564 10.4704 2.86263L16.3034 8.69661L16.3884 8.80111C16.5588 9.05922 16.5306 9.40982 16.3034 9.63704C16.0762 9.86414 15.7255 9.89242 15.4675 9.722L15.363 9.63704L10.6647 4.9388V16.6663C10.6647 17.0336 10.367 17.3314 9.99971 17.3314C9.63259 17.3312 9.33467 17.0335 9.33467 16.6663ZM4.6374 9.63704C4.3777 9.89674 3.95569 9.89674 3.69599 9.63704C3.43657 9.37744 3.43668 8.95628 3.69599 8.69661L4.6374 9.63704Z"
    case Controls.ArrowDown{}: "M9.33467 16.6663V4.93978L4.6374 9.63704L4.1667 9.16634L3.69599 8.69661L9.52998 2.86263L9.63447 2.77767C9.8925 2.60753 10.2433 2.63564 10.4704 2.86263L16.3034 8.69661L16.3884 8.80111C16.5588 9.05922 16.5306 9.40982 16.3034 9.63704C16.0762 9.86414 15.7255 9.89242 15.4675 9.722L15.363 9.63704L10.6647 4.9388V16.6663C10.6647 17.0336 10.367 17.3314 9.99971 17.3314C9.63259 17.3312 9.33467 17.0335 9.33467 16.6663ZM4.6374 9.63704C4.3777 9.89674 3.95569 9.89674 3.69599 9.63704C3.43657 9.37744 3.43668 8.95628 3.69599 8.69661L4.6374 9.63704Z"
    case Controls.Check{}: "m4 10 4 4 8-8"





def choice_mark(value: Bool) -> String:
  match value:
    case True{}: "✓"
    case False{}: " "





def disclosure_mark(value: Bool) -> String:
  match value:
    case True{}: "⌄"
    case False{}: "›"





def boolean(value: Bool) -> String:
  match value:
    case True{}: "true"
    case False{}: "false"





def joined(values: +List<String>) -> String:
  match values:
    case Nil{}: ""
    case Con{value, Nil{}}: value
    case Con{value, rest}: value ++ "\n" ++ joined(rest)





def optional_text(value: Maybe<&2, String>) -> String:
  match value:
    case None{}: ""
    case Some{text}: text





def optional_nat(value: Maybe<&2, Nat>) -> String:
  match value:
    case None{}: ""
    case Some{number}: Nat.show(number)





def widget_tag(value: Controls.Widget) -> String:
  match value:
    case Controls.MessageInput{}: "textarea"
    case Controls.TextArea{}: "textarea"
    case Controls.DirectoryList{}: "textarea"
    case Controls.SelectInput{}: "select"
    case Controls.MultiSelectInput{}: "select"
    case Controls.PlainValue{}: "output"
    case _: "input"





def input_events(key: String, widget: Controls.Widget) -> +List<Doc.Event>:
  match widget:
    case Controls.PlainValue{}: Nil{}
    case Controls.ToggleInput{}: [Doc.EditToggle{key}]
    case Controls.FileChooser{face}: [Doc.SelectFiles{key}]
    case Controls.AttachmentList{}: [Doc.SelectFiles{key}]
    case _: [Doc.EditText{key}]





def tag(role: UI.Role) -> String:
  match role:
    case UI.Navigation{}: "nav"
    case UI.Main{}: "main"
    case UI.Heading{}: "header"
    case UI.Activity{}: "details"
    case UI.Dialog{}: "section"
    case UI.Card{}: "article"
    case UI.UserMessage{}: "article"
    case UI.AssistantMessage{}: "article"
    case _: "div"





def replace_styles(node: Doc.Node, extra: +List<Doc.Property>) -> Doc.Node:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: Doc.Element{key, tag, attrs, List.append(&2, Doc.Property, styles, extra), events, children}
    case other: other





def node_role(value: UI.Node) -> UI.Role:
  UI.Node{key, semantic, label, role, meaning, children} = value
  role





def code_wrap(value: Bool) -> String:
  match value:
    case True{}: "pre-wrap"
    case False{}: "pre"





def role_name(value: UI.Role) -> String:
  match value:
    case UI.Heading{}: "heading"
    case UI.Timeline{}: "timeline"
    case UI.Composer{}: "composer"
    case UI.ComposerActions{}: "composer-actions"
    case UI.ApprovalQueue{}: "approvals"
    case UI.UserMessage{}: "user-message"
    case UI.AssistantMessage{}: "agent-message"
    case UI.Activity{}: "activity"
    case UI.Navigation{}: "navigation"
    case UI.Main{}: "main"
    case UI.Section{}: "section"
    case _: "content"





def attr_found(found: Bool, value: String, fallback: String) -> String:
  match found:
    case True{}: value
    case False{}: fallback







def box_left(value: Design.Box) -> Nat:
  Design.Box{left, top, width, height} = value
  left





def markdown_source(values: +List<UI.Node>) -> Maybe<&2, Code.Source>:
  match values:
    case Nil{}: None{}
    case Con{UI.Node{key, semantic, label, role, UI.CodeFacts{Code.Scene{Code.Identity{source, ordinal}, literal, wrap, copy, enabled, controls}}, children}, rest}: Some{source}
    case Con{other, rest}: markdown_source(rest)





def delivery_name(value: User.Delivery) -> String:
  match value:
    case User.Send{}: "send"
    case User.Steer{}: "steer"





def filter_name(value: Board.Filter) -> String:
  match value:
    case Board.Filter{view, search, status, priority, date, assignee, creator, project, label}: view





def workspace_roots(value: Context.WorkspaceValue) -> +List<String>:
  match value:
    case Context.InheritedWorkspace{Domain.Workspace{roots, primary}}: roots
    case Context.EnteredWorkspace{Domain.Workspace{roots, primary}}: roots





def sandbox_text(value: Context.SandboxValue) -> String:
  match value:
    case Context.InheritedSandbox{Domain.Sandbox{mode, network}}: Domain.sandbox_mode_name(mode)
    case Context.ChosenSandbox{Domain.Sandbox{mode, network}}: Domain.sandbox_mode_name(mode)





def origin_text(value: Context.Origin) -> String:
  match value:
    case Context.EnvironmentDefaults{}: "environment"
    case Context.ProjectDefaults{project}: "project/" ++ Nat.show(project)
    case Context.ParentTask{task}: "parent/" ++ Nat.show(task)
    case Context.ProjectForParent{task, project}: "project-for-parent/" ++ Nat.show(task) ++ "/" ++ Nat.show(project)





def approval_text(value: Context.ApprovalValue) -> String:
  match value:
    case Context.InheritedApproval{policy}: Domain.approval_name(policy)
    case Context.ChosenApproval{Context.Ask{}}: "ask"
    case Context.ChosenApproval{Context.Unrestricted{}}: "full-access"
    case Context.ChosenApproval{Context.AutomaticReview{profile}}: "automatic"





def reading_identity(value: Core.Scene) -> Maybe<&2, ReadingIdentity>:
  Core.Scene{View.Scene{navigation, page, layers, arrangement, attention}, settings, transfers, preview, code} = value
  match page:
    case View.TaskPage{View.TaskScene{task, title, status, context, Conversation.Timeline{id, generation, groups, operations, decisions, reading, latest}, previews, composer, details, actions}}: Some{ReadingIdentity{task, generation}}
    case _: None{}





def frame_input(value: Design.MainFrame) -> Maybe<&2, Design.InputMetrics>:
  match value:
    case Design.CreationFrame{heading, canvas, band, input, flow}: input
    case Design.ConversationFrame{heading, viewport, reading, Some{Design.Dock{band, bottom, maximum, regions, input, reservation}}}: input
    case _: None{}





def keep_section(keep: Bool, value: Doc.Node) -> +List<Doc.Node>:
  match keep:
    case True{}: [value]
    case False{}: Nil{}





def css_characters(value: String) -> String:
  match value:
    case SNil{}: ""
    case SCon{head, rest}: "-" ++ U32.show(Char.to_u32(head)) ++ css_characters(rest)







def content_groups(value: View.LayerContent) -> +List<View.InputGroup>:
  match value:
    case View.ObjectEditor{Some{View.EditorScene{identity, revision, groups, sections, submit, feedback, pending}}}: groups
    case View.ExecutionSettings{editor, groups}: groups
    case View.ModelSelection{editor, query, groups}: groups
    case View.DeliverySelection{editor, groups}: groups
    case _: Nil{}





def prefer_options(first: +List<Doc.Node>, second: +List<Doc.Node>) -> +List<Doc.Node>:
  match first:
    case Nil{}: second
    case Con{value, rest}: value <> rest





def scene_activities(value: Core.Scene) -> +List<Conversation.VisibleGroup>:
  Core.Scene{View.Scene{navigation, page, layers, arrangement, attention}, settings, transfers, preview, code} = value
  match page:
    case View.TaskPage{View.TaskScene{task, title, status, context, Conversation.Timeline{id, generation, groups, operations, decisions, reading, latest}, previews, composer, details, actions}}: groups
    case _: Nil{}





def rendered_json(value: Result<&2, &2, String, String>) -> String:
  match value:
    case Done{text}: text
    case Fail{reason}: reason





def theme_name(value: Design.Theme) -> String:
  match value:
    case Design.Light{}: "light"
    case Design.Dark{}: "dark"

def theme_class(value: Design.Theme) -> String:
  match value:
    case Design.Light{}: "native-application light"
    case Design.Dark{}: "native-application dark"





def first_node(values: +List<Doc.Node>) -> Doc.Node:
  match values:
    case Nil{}: Doc.Text{""}
    case Con{value, rest}: value






def generated_identity(owner: String, part: String) -> String:
  owner ++ "/@" ++ part

def activity_summary(owner: String, label: String, values: +List<Doc.Node>) -> +List<Doc.Node>:
  match values:
    case Con{Doc.Element{key, tag, attrs, styles, events, children}, rest}:
      Doc.Element{key, "summary", attrs, styles, events, List.append(&2, Doc.Node, children, [Doc.Text{" " ++ label}])} <> rest
    case Nil{}: [Doc.Element{generated_identity(owner, "summary"), "summary", Nil{}, Nil{}, Nil{}, [Doc.Text{label}]}]
    case Con{other, rest}: other <> rest

def bounds(box: Design.Box) -> +List<Doc.Property>:
  Design.Box{left, top, width, height} = box
  [property("position", "fixed"), property("left", px(left)), property("top", px(top)),
   property("width", px(width)), property("height", px(height)), property("box-sizing", "border-box")]





def flow(value: Design.Flow) -> +List<Doc.Property>:
  match value:
    case Design.BlockFlow{}: [property("display", "block")]
    case Design.ColumnFlow{}: [property("display", "flex"), property("flex-direction", "column")]
    case Design.RowFlow{}: [property("display", "flex"), property("align-items", "center")]
    case Design.SplitRowFlow{}: [property("display", "flex"), property("align-items", "center"), property("justify-content", "space-between")]
    case Design.WrapFlow{}: [property("display", "flex"), property("flex-wrap", "wrap")]





def overflow_style(value: Design.Overflow) -> +List<Doc.Property>:
  match value:
    case Design.ContentFlow{}: Nil{}
    case Design.ScrollFlow{}: [property("overflow", "auto")]
    case Design.CodeOverflow{}: [property("overflow", "auto")]





def icon(+key: String, value: Controls.Icon) -> Doc.Node:
  Doc.Element{key ++ "/icon", "svg", [property("viewBox", "0 0 20 20"), property("aria-hidden", "true"), property("fill", "none"), property("stroke", "currentColor"), property("stroke-width", "1.4"), property("stroke-linecap", "round"), property("stroke-linejoin", "round")],
    [property("width", "var(--native-icon-size,16px)"), property("height", "var(--native-icon-size,16px)"), property("flex-shrink", "0")], Nil{},
    [Doc.Element{key ++ "/icon/path", "path", [property("d", icon_path(value))], Nil{}, Nil{}, Nil{}}]}





def unavailable(value: View.Availability) -> +List<Doc.Property>:
  match value:
    case View.Available{}: Nil{}
    case View.NeedsDirectoryObservation{}: Nil{}
    case View.Unavailable{reason}: [property("disabled", ""), property("title", reason), property("aria-disabled", "true")]





def help(value: Controls.Help) -> +List<Doc.Property>:
  match value:
    case Controls.NoHelp{}: Nil{}
    case Controls.Tooltip{text, delay, pointer, keyboard, focus}: [property("title", text)]





def behavior(value: Controls.Behavior) -> +List<Doc.Property>:
  match value:
    case Controls.Push{}: Nil{}
    case Controls.Toggle{pressed}: [property("aria-pressed", boolean(pressed))]
    case Controls.Radio{checked}: [property("role", "menuitemradio"), property("aria-checked", boolean(checked))]
    case Controls.Disclosure{expanded}: [property("aria-expanded", boolean(expanded))]
    case Controls.Popup{menu, expanded}: [property("aria-haspopup", "true"), property("aria-expanded", boolean(expanded))]
    case Controls.Destination{current}: [property("aria-current", boolean(current))]





def geometry(value: Controls.Geometry) -> +List<Doc.Property>:
  Controls.Geometry{width, height, icon_size, radius, leading} = value
  [property("min-width", px(width)), property("min-height", px(height)), property("border-radius", px(radius)),
   property("display", "inline-flex"), property("align-items", "center"), property("gap", "6px"), property("--native-icon-size", px(icon_size)), property("--native-leading-slot", px(leading))]





def widget_properties(value: Controls.Widget) -> +List<Doc.Property>:
  match value:
    case Controls.MessageInput{}: [property("placeholder", "Ask anything, or describe a task")]
    case Controls.ToggleInput{}: [property("type", "checkbox")]
    case Controls.NumberInput{minimum}: [property("type", "number"), property("min", Nat.show(minimum))]
    case Controls.SecretInput{}: [property("type", "password")]
    case Controls.SearchInput{}: [property("type", "search")]
    case Controls.FileChooser{face}: [property("type", "file")]
    case Controls.AttachmentList{}: [property("type", "file"), property("multiple", "")]
    case Controls.MultiSelectInput{}: [property("multiple", "")]
    case _: Nil{}





def section_label(owner: String, empty: Bool, text: String) -> +List<Doc.Node>:
  match empty:
    case True{}: Nil{}
    case False{}: [Doc.Element{generated_identity(owner, "title"), "h2", Nil{}, [property("font-size", "13px")], Nil{}, [Doc.Text{text}]}]

def region_label(owner: String, role: UI.Role, +text: String) -> +List<Doc.Node>:
  match role:
    case UI.Heading{}: [Doc.Text{text}]
    case UI.Section{}: section_label(owner, String.is_empty(text), text)
    case UI.Dialog{}: [Doc.Element{generated_identity(owner, "title"), "h2", Nil{}, Nil{}, Nil{}, [Doc.Text{text}]}]
    case UI.Activity{}: [Doc.Element{generated_identity(owner, "summary"), "summary", Nil{}, Nil{}, Nil{}, [Doc.Text{text}]}]
    case _: Nil{}





def region_styles(value: String) -> +List<Doc.Property>:
  match value:
    case "user-message": [property("width", "fit-content"), property("margin-left", "auto")]
    case "agent-message": [property("width", "100%")]
    case "navigation": [property("height", "100%")]
    case _: Nil{}

def attr(values: +List<Doc.Property>, +name: String) -> String:
  match values:
    case Nil{}: ""
    case Con{Doc.Property{key, value}, rest}: attr_found(String.eq(key, name), value, attr(rest, name))





def composer_styles(value: Design.MainFrame) -> +List<Doc.Property>:
  match value:
    case Design.CreationFrame{heading, canvas, band, input, flow}:
      [property("width", "100%"), property("flex-shrink", "0")]
    case Design.ConversationFrame{heading, viewport, reading, Some{Design.Dock{Design.Band{left, width}, bottom, maximum, regions, input, reservation}}}:
      [property("position", "relative"), property("width", "100%"), property("max-height", px(maximum)), property("min-width", "0")]
    case _: Nil{}





def input_style(value: Controls.Widget) -> +List<Doc.Property>:
  match value:
    case Controls.MessageInput{}: [property("width", "100%"), property("min-height", "44px"), property("max-height", "240px"), property("line-height", "20px"), property("resize", "none"), property("border", "none"), property("outline", "none"), property("background", "transparent"), property("field-sizing", "content")]
    case _: [property("width", "100%")]





def workspace_text(value: Context.WorkspaceValue) -> String:
  match value:
    case Context.InheritedWorkspace{Domain.Workspace{roots, primary}}: joined(roots)
    case Context.EnteredWorkspace{Domain.Workspace{roots, primary}}: joined(roots)





def workspace_primary(value: Context.WorkspaceValue) -> String:
  match value:
    case Context.InheritedWorkspace{Domain.Workspace{roots, primary}}: optional_text(primary)
    case Context.EnteredWorkspace{Domain.Workspace{roots, primary}}: optional_text(primary)





def network_text(value: Context.SandboxValue) -> String:
  match value:
    case Context.InheritedSandbox{Domain.Sandbox{mode, network}}: boolean(network)
    case Context.ChosenSandbox{Domain.Sandbox{mode, network}}: boolean(network)





def workspace_field_text(field: Forms.Field, roots: +List<String>, primary: Maybe<&2, String>) -> String:
  match field:
    case Forms.WorkspacePrimary{}: optional_text(primary)
    case _: joined(roots)





def option(+key: String, +value: String, label: String) -> Doc.Node:
  Doc.Element{key ++ "/option/" ++ value, "option", [property("value", value)], Nil{}, Nil{}, [Doc.Text{label}]}





def primary_choices(value: Forms.Observed) -> +List<String>:
  match value:
    case Forms.WorkspaceValue{Domain.Workspace{roots, primary}}: roots
    case Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}: workspace_roots(workspace)
    case _: Nil{}





def fact(+key: String, label: String, value: String) -> Doc.Node:
  Doc.Element{key, "div", Nil{}, [property("margin-block", "8px")], Nil{},
    [Doc.Element{key ++ "/label", "strong", Nil{}, Nil{}, Nil{}, [Doc.Text{label}]}, Doc.Text{value}]}





def editor_properties(key: String, widget: Controls.Widget) -> +List<Doc.Property>:
  match widget:
    case Controls.MessageInput{}: [property("data-native-editor-key", key)]
    case _: Nil{}





def reading_anchor(role: String, key: String) -> +List<Doc.Property>:
  match role:
    case "user-message": [property("data-reading-key", key)]
    case "agent-message": [property("data-reading-key", key)]
    case "activity": [property("data-reading-key", key)]
    case _: Nil{}





def reading_element(region: String, +key: String, tag: String, attrs: +List<Doc.Property>, styles: +List<Doc.Property>, events: +List<Doc.Event>, children: +List<Doc.Node>, identity: Maybe<&2, ReadingIdentity>) -> Doc.Node:
  match region identity:
    case "conversation-body" Some{ReadingIdentity{+task, generation}}:
      +body_key = "conversation/" ++ Nat.show(task) ++ "/body"
      Doc.Element{body_key, tag, List.append(&2, Doc.Property, attrs, [property("data-reading-scroll", ""), property("data-reading-task", Nat.show(task)), property("data-reading-generation", Nat.show(generation))]), styles, events,
        [Doc.Element{body_key ++ "/reading-content", "div", [property("data-reading-content", ""), property("data-reading-task", Nat.show(task))], [property("display", "flex"), property("flex-direction", "column"), property("gap", "16px")], Nil{}, children}]}
    case "dock" Some{ReadingIdentity{task, generation}}:
      Doc.Element{key, tag, List.append(&2, Doc.Property, attrs, [property("data-reading-dock", ""), property("data-reading-task", Nat.show(task))]), styles, events, children}
    case _ _: Doc.Element{key, tag, attrs, styles, events, children}





def label_input(placement: Controls.LabelPlacement, +key: String, name: String, input: Doc.Node) -> Doc.Node:
  match placement:
    case Controls.AccessibleOnly{}: input
    case Controls.AboveInput{}: Doc.Element{key ++ "/field", "label", Nil{}, [property("display", "flex"), property("min-width", "0"), property("max-width", "100%"), property("flex-direction", "column"), property("gap", "6px"), property("margin-block", "8px")], Nil{}, [Doc.Text{name}, input]}
    case Controls.BesideInput{}: Doc.Element{key ++ "/field", "label", Nil{}, [property("display", "flex"), property("min-width", "0"), property("max-width", "100%"), property("align-items", "center"), property("gap", "8px")], Nil{}, [input, Doc.Text{name}]}





def checked_property(value: Bool) -> +List<Doc.Property>:
  match value:
    case True{}: [property("checked", "")]
    case False{}: Nil{}





def measured_input_present(present: Bool, metrics: Maybe<&2, Design.InputMetrics>) -> +List<Doc.Property>:
  match present metrics:
    case True{} Some{Design.InputMetrics{minimum, maximum, line_height, inline, gap, footer}}: [property("min-height", px(minimum)), property("max-height", px(maximum)), property("line-height", px(line_height)), property("padding-inline", px(inline))]
    case _ _: Nil{}







def board_columns(values: +List<Doc.Node>, +width: Nat) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: replace_styles(value, [property("width", px(width)), property("min-width", px(width)), property("flex", "0 0 auto"), property("display", "flex"), property("flex-direction", "column"), property("gap", "12px")]) <> board_columns(rest, width)







def css_anchor(key: String) -> String:
  "--native" ++ css_characters(key)





def background_properties(active: Maybe<&2, String>) -> +List<Doc.Property>:
  match active:
    case Some{current}: [property("inert", "true"), property("aria-hidden", "true")]
    case None{}: Nil{}

def modal_active_properties(owns_focus: Bool) -> +List<Doc.Property>:
  match owns_focus:
    case True{}: [property("role", "dialog"), property("aria-modal", "true")]
    case False{}: [property("inert", "true"), property("aria-hidden", "true")]

def modal_properties(active: Maybe<&2, String>, key: String) -> +List<Doc.Property>:
  match active:
    case Some{current}: modal_active_properties(String.eq(current, key))
    case None{}: Nil{}

def base_scope(active: Maybe<&2, String>, children: +List<Doc.Node>) -> Doc.Node:
  Doc.Element{"application-base", "div", background_properties(active),
    [property("display", "contents")], Nil{}, children}

def meaning_properties(value: UI.Meaning) -> +List<Doc.Property>:
  match value:
    case UI.Edit{editor, field, entry, observed_value}: [property("data-field", Forms.key(field))]
    case _: Nil{}





def layer_groups(values: +List<View.Layer>) -> +List<View.InputGroup>:
  match values:
    case Nil{}: Nil{}
    case Con{View.Layer{kind, content, initial, return_attention, close}, rest}: List.append(&2, View.InputGroup, content_groups(content), layer_groups(rest))





def opened(value: Bool) -> +List<Doc.Property>:
  match value:
    case True{}: [property("open", "")]
    case False{}: Nil{}





def json_text(value: Json.Json) -> String:
  rendered_json(Json.show(value))





def shadow_style(value: Bool) -> +List<Doc.Property>:
  match value:
    case True{}: [property("box-shadow", "var(--shadow-sm)")]
    case False{}: Nil{}





def alignment_style(value: Design.Alignment) -> +List<Doc.Property>:
  match value:
    case Design.Stretch{}: [property("align-self", "stretch")]
    case Design.Leading{}: [property("align-self", "flex-start")]
    case Design.Trailing{}: [property("align-self", "flex-end")]
    case Design.Centered{}: [property("align-self", "center"), property("text-align", "center")]





def states_style(value: Design.ControlStates) -> +List<Doc.Property>:
  match value:
    case Design.Passive{}: Nil{}
    case Design.Interactive{Design.Chrome{hfg, hbg, hborder, hwidth, hradius, hshadow}, Design.Chrome{pfg, pbg, pborder, pwidth, pradius, pshadow}, opacity, ring, width, offset}:
      [property("--native-hover-background", paint(hbg)), property("--native-hover-color", paint(hfg)), property("--native-pressed-background", paint(pbg)), property("--native-pressed-color", paint(pfg)),
       property("--native-disabled-opacity", Nat.show(opacity) ++ "%"), property("--native-focus-ring", paint(ring)), property("--native-focus-width", px(width)), property("--native-focus-offset", px(offset))]





def placement_styles(value: Controls.Placement) -> +List<Doc.Property>:
  match value:
    case Controls.ComposerEnd{}: [property("margin-left", "auto")]
    case Controls.PanelHeaderEnd{}: [property("margin-left", "auto")]
    case Controls.GroupHeadingEnd{}: [property("margin-left", "auto")]
    case _: Nil{}





def optional_icon(key: String, value: Maybe<&2, Controls.Icon>) -> +List<Doc.Node>:
  match value:
    case None{}: Nil{}
    case Some{value}: [icon(key, value)]





def context_text(value: Context.Preview) -> String:
  match value:
    case Context.ContextUnavailable{reason}: reason
    case Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}: workspace_text(workspace) ++ "\n" ++ sandbox_text(sandbox)





def navigation_styles(value: Design.Navigation) -> +List<Doc.Property>:
  match value:
    case Design.HiddenNavigation{}: [property("display", "none")]
    case Design.BesideNavigation{box}: List.append(&2, Doc.Property, bounds(box), [property("padding-bottom", "56px"), property("box-sizing", "border-box")])
    case Design.OverlayNavigation{box}: List.append(&2, Doc.Property, bounds(box), [property("z-index", "30"), property("padding-bottom", "56px"), property("box-sizing", "border-box")])





def overlay_styles(value: Design.OverlayPlacement) -> +List<Doc.Property>:
  match value:
    case Design.CenteredDialog{available, maximum}:
      Design.Box{left, top, +width, +height} = available
      [property("position", "fixed"), property("left", px(Nat.add(left, Nat.div(width, 2n)))), property("top", px(Nat.add(top, Nat.div(height, 2n)))),
       property("transform", "translate(-50%, -50%)"), property("width", px(Nat.min(width, maximum))), property("max-height", px(height)), property("overflow", "auto")]
    case Design.AnchoredPopover{anchor, available, maximum_width, maximum_height, gap}:
      Design.Box{left, top, +width, +height} = available
      [property("position", "fixed"), property("position-anchor", css_anchor(anchor)), property("position-area", "bottom span-left"), property("position-try-fallbacks", "flip-block, flip-inline"), property("margin", px(gap)), property("max-width", px(Nat.min(width, maximum_width))),
       property("max-height", px(Nat.min(height, maximum_height))), property("overflow", "auto")]
    case Design.TrailingPane{box}: bounds(box)
    case Design.NavigationDrawer{box}: bounds(box)





def decorate(+role: String, semantic: String, node: Doc.Node) -> Doc.Node:
  match node:
    case Doc.Element{+key, tag, attrs, styles, events, children}:
      Doc.Element{key, tag, List.append(&2, Doc.Property, attrs, List.append(&2, Doc.Property, [property("data-region", role), property("data-semantic", semantic)], reading_anchor(role, key))),
        List.append(&2, Doc.Property, styles, region_styles(role)), events, children}
    case other: other





def timeline_styles(value: Design.MainFrame) -> +List<Doc.Property>:
  match value:
    case Design.ConversationFrame{heading, +viewport, Design.Band{left, width}, dock}:
      List.append(&2, Doc.Property, bounds(viewport), [property("overflow-y", "auto"), property("padding-inline", px(Nat.sub(left, box_left(viewport)))), property("gap", "16px"), property("padding-top", "24px"), property("display", "flex"), property("flex-direction", "column")])
    case _: Nil{}





def context_field_text(field: Forms.Field, origin: Context.Origin, workspace: Context.WorkspaceValue, sandbox: Context.SandboxValue, approval: Context.ApprovalValue) -> String:
  match field:
    case Forms.ContextOrigin{}: origin_text(origin)
    case Forms.WorkspaceDirectories{}: workspace_text(workspace)
    case Forms.WorkspacePrimary{}: workspace_primary(workspace)
    case Forms.SandboxMode{}: sandbox_text(sandbox)
    case Forms.NetworkAccess{}: network_text(sandbox)
    case Forms.ApprovalPolicy{}: approval_text(approval)
    case _: ""





def options(values: +List<String>, +key: String) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}: option(key, value, value) <> options(rest, key)





def profile_options(values: +List<Domain.Profile>, +key: String) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Domain.Profile{id, provider, name, policy}, rest}: option(key, id, name) <> profile_options(rest, key)





def task_details(+owner: String, value: View.TaskDetails) -> +List<Doc.Node>:
  View.TaskDetails{Context.EffectiveContext{task, Domain.TaskContext{Domain.Workspace{roots, primary}, Domain.Sandbox{mode, network}, approval, project}, guidance, access}, Domain.Model{Domain.Profile{id, provider, name, policy}, reasoning, model_guidance}, tools, lineage, queued, status, phase} = value
  [fact(generated_identity(owner, "workspace"), "Working directories", joined(roots)), fact(generated_identity(owner, "primary"), "Primary directory", optional_text(primary)),
   fact(generated_identity(owner, "sandbox"), "Filesystem access", Domain.sandbox_mode_name(mode)), fact(generated_identity(owner, "network"), "Network access", boolean(network)),
   fact(generated_identity(owner, "approval"), "Approval policy", Domain.approval_name(approval)), fact(generated_identity(owner, "model"), "Model", name), fact(generated_identity(owner, "reasoning"), "Reasoning", reasoning),
   fact(generated_identity(owner, "messages"), "Queued messages", joined(queued))]





def reading_nodes(values: +List<Doc.Node>, +identity: Maybe<&2, ReadingIdentity>) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Doc.Element{+key, tag, +attrs, styles, events, children}, rest}:
      reading_element(attr(attrs, "data-region"), key, tag, attrs, styles, events, reading_nodes(children, identity), identity) <> reading_nodes(rest, identity)
    case Con{other, rest}: other <> reading_nodes(rest, identity)





def origin_option_values(+key: String, origin: Context.Origin) -> +List<Doc.Node>:
  match origin:
    case Context.EnvironmentDefaults{}: [option(key, "environment", "Environment defaults")]
    case Context.ProjectDefaults{project}: [option(key, "environment", "Environment defaults"), option(key, "project/" ++ Nat.show(project), "Project defaults")]
    case Context.ParentTask{task}: [option(key, "environment", "Environment defaults"), option(key, "parent/" ++ Nat.show(task), "Parent task")]
    case Context.ProjectForParent{+task, project}: [option(key, "environment", "Environment defaults"), option(key, "parent/" ++ Nat.show(task), "Parent task"), option(key, "project-for-parent/" ++ Nat.show(task) ++ "/" ++ Nat.show(project), "Project defaults")]





def checked_properties(value: UI.Meaning) -> +List<Doc.Property>:
  match value:
    case UI.Edit{editor, field, entry, Forms.ToggleValue{enabled}}: checked_property(enabled)
    case UI.Edit{editor, Forms.NetworkAccess{}, entry, Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, Context.InheritedSandbox{Domain.Sandbox{mode, enabled}}, approval, guidance}}}: checked_property(enabled)
    case UI.Edit{editor, Forms.NetworkAccess{}, entry, Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, Context.ChosenSandbox{Domain.Sandbox{mode, enabled}}, approval, guidance}}}: checked_property(enabled)
    case _: Nil{}





def measured_input_styles(key: String, frame: Design.MainFrame) -> +List<Doc.Property>:
  measured_input_present(Bool.not(String.is_empty(key)), frame_input(frame))







def frame_region(key: String, +region: String, box: Design.Box, children: +List<Doc.Node>) -> Doc.Node:
  Doc.Element{key, "div", [property("data-region", region)], bounds(box), Nil{}, children}











def modal_scope(+key: String, active: Maybe<&2, String>, value: Doc.Node) -> Doc.Node:
  match value:
    case Doc.Element{identity, tag, attrs, styles, events, children}:
      Doc.Element{identity, tag, List.append(&2, Doc.Property, attrs, modal_properties(active, key)), styles, events, children}
    case other: other







def scene_groups(value: Core.Scene) -> +List<View.InputGroup>:
  Core.Scene{View.Scene{navigation, page, layers, arrangement, attention}, settings, transfers, preview, code} = value
  layer_groups(layers)





def project_origin_options(+key: String, values: +List<View.ProjectChoice>) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{View.ProjectChoice{id, name, workspace}, rest}: option(key, "project/" ++ Nat.show(id), name) <> project_origin_options(key, rest)





def reviewer_options(+key: String, values: +List<Domain.Profile>) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Domain.Profile{id, provider, name, policy}, rest}: option(key, "automatic/" ++ id, "Automatic review: " ++ name) <> reviewer_options(key, rest)





def project_options(+key: String, values: +List<View.ProjectChoice>) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{View.ProjectChoice{id, name, workspace}, rest}: option(key, Nat.show(id), name) <> project_options(key, rest)





def owner_options(+key: String, values: +List<Board.Owner>) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}: option(key, Board.owner_name(value), Board.owner_name(value)) <> owner_options(key, rest)





def RenderField(attrs: +List<Doc.Property>) -> String:
  attr(attrs, "data-field")





def audit_text(value: Domain.Message) -> String:
  Conversation.audit_detail(value)

def style_details(shadow: Bool, alignment: Design.Alignment, states: Design.ControlStates) -> +List<Doc.Property>:
  List.append(&2, Doc.Property, shadow_style(shadow), List.append(&2, Doc.Property, alignment_style(alignment), states_style(states)))





def placement_buttons(+key: String, values: +List<UI.Placement>) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{UI.Placement{+target, input, availability}, rest}:
      Doc.Element{key ++ "/move/" ++ target, "button", List.append(&2, Doc.Property, [property("type", "button"), property("aria-label", "Move to " ++ target)], unavailable(availability)),
        [property("font-size", "12px"), property("padding", "4px 8px")], [Doc.PlaceCard{key, target}], [Doc.Text{"Move to " ++ target}]} <> placement_buttons(key, rest)







def region_children(owner: String, role: UI.Role, label: String, children: +List<Doc.Node>) -> +List<Doc.Node>:
  match role:
    case UI.Activity{}: activity_summary(owner, label, children)
    case other: List.append(&2, Doc.Node, region_label(owner, other, label), children)


def style(value: Design.Style) -> +List<Doc.Property>:
  Design.Style{Design.TextStyle{family, size, line_height, weight},
    Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment,
    direction, overflow, inline, block, gap, minimum, maximum, states} = value
  List.append(&2, Doc.Property,
    [property("font-family", font(family)), property("font-size", px(size)), property("line-height", px(line_height)),
     property("font-weight", Nat.show(weight)), property("color", paint(foreground)), property("background", paint(background)),
     property("border-color", paint(border)), property("border-width", px(border_width)), property("border-style", "solid"),
     property("border-radius", px(radius)), property("padding-inline", px(inline)), property("padding-block", px(block)),
     property("gap", px(gap)), property("min-height", px(minimum)), property("max-width", Nat.show(maximum) ++ "%"),
     property("box-sizing", "border-box"), property("min-width", "0")],
    List.append(&2, Doc.Property, flow(direction), List.append(&2, Doc.Property, overflow_style(overflow), style_details(shadow, alignment, states))))





def face(+key: String, value: Controls.Face) -> +List<Doc.Node>:
  match value:
    case Controls.IconFace{value}: [icon(key, value)]
    case Controls.TextFace{text}: [Doc.Text{text}]
    case Controls.IconTextFace{value, text}: [icon(key, value), Doc.Text{text}]
    case Controls.PickerFace{leading, text}: List.append(&2, Doc.Node, optional_icon(key, leading), [Doc.Text{text}, Doc.Text{"⌄"}])
    case Controls.ChoiceFace{text, checked}: [Doc.Element{key ++ "/check-slot", "span", Nil{}, [property("width", "var(--native-leading-slot,20px)"), property("flex-shrink", "0")], Nil{}, [Doc.Text{choice_mark(checked)}]}, Doc.Text{text}]
    case Controls.DisclosureFace{text, expanded}: [Doc.Text{disclosure_mark(expanded)}, Doc.Text{text}]





def observed(value: Forms.Observed) -> String:
  match value:
    case Forms.TextValue{text}: text
    case Forms.CountValue{count}: Nat.show(count)
    case Forms.TextsValue{values}: joined(values)
    case Forms.ToggleValue{enabled}: boolean(enabled)
    case Forms.WorkspaceValue{Domain.Workspace{roots, primary}}: joined(roots)
    case Forms.ContextValue{preview}: context_text(preview)
    case Forms.ModelValue{profile, reasoning}: profile
    case Forms.DeliveryValue{delivery}: delivery_name(delivery)
    case Forms.StageValue{stage}: Board.stage_name(stage)
    case Forms.PriorityValue{priority}: Board.priority_name(priority)
    case Forms.OwnerValue{owner}: Board.owner_name(owner)
    case Forms.ProjectValue{project}: optional_nat(project)
    case Forms.AttachmentsValue{files}: ""
    case Forms.AssistanceValue{enabled, profile}: profile
    case Forms.OptionalTextValue{text}: optional_text(text)
    case Forms.NotApplicable{}: ""





def render_base(role: UI.Role, value: Doc.Node, navigation: Design.Navigation, main: Design.Box, details: Maybe<&2, Design.Box>) -> Doc.Node:
  match role:
    case UI.Navigation{}: replace_styles(value, navigation_styles(navigation))
    case UI.Main{}: replace_styles(value, bounds(main))
    case _: value





def frame_styles(region: String, +frame: Design.MainFrame) -> +List<Doc.Property>:
  match region:
    case "composer": composer_styles(frame)
    case _: Nil{}

def origin_options(+key: String, value: Forms.Observed) -> +List<Doc.Node>:
  match value:
    case Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}: origin_option_values(key, origin)
    case _: [option(key, "environment", "Environment defaults")]







def policy_options(+key: String, policy: Reasoning.Policy) -> +List<Doc.Node>:
  match policy:
    case Reasoning.Fixed{}: options(["low", "medium", "high", "xhigh", "max"], key)
    case Reasoning.Adaptive{evaluator, efforts, baseline, transport, maximum}: [option(key, "auto", "Automatic")]





def assistance_options(key: String, field: String, profiles: +List<Domain.Profile>) -> +List<Doc.Node>:
  match field:
    case "assistance-profile": profile_options(profiles, key)
    case _: Nil{}





def card_options(+key: String, field: String, projects: +List<View.ProjectChoice>, owners: +List<Board.Owner>) -> +List<Doc.Node>:
  match field:
    case "card-project": option(key, "", "No project") <> project_options(key, projects)
    case "card-owner": owner_options(key, owners)
    case _: Nil{}





def audit_nodes(+key: String, values: +List<Conversation.AuditFace>) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Conversation.AuditFace{+id, kind, title, source}, rest}:
      Doc.Element{key ++ "/audit/" ++ Nat.show(id), "section", Nil{}, [property("padding", "8px 12px"), property("border-left", "1px solid var(--color-token-border-default)")], Nil{},
        [Doc.Element{key ++ "/audit-title/" ++ Nat.show(id), "strong", Nil{}, Nil{}, Nil{}, [Doc.Text{title}]}, Doc.Markdown{key ++ "/audit-body/" ++ Nat.show(id), None{}, audit_text(source)}]} <> audit_nodes(key, rest)





def movement_menu(+key: String, values: +List<UI.Placement>) -> Doc.Node:
  Doc.Element{key ++ "/movement", "details", Nil{}, [property("font-size", "12px")], Nil{},
    Doc.Element{key ++ "/movement-summary", "summary", [property("aria-label", "Move card")], [property("display", "flex"), property("align-items", "center"), property("gap", "4px")], Nil{}, [icon(key ++ "/grip", Controls.Grip{}), Doc.Text{"Move card"}]} <> placement_buttons(key, values)}






def action(+key: String, +appearance: Design.Appearance, value: Controls.Representation) -> Doc.Node:
  Design.Appearance{identity, visual, representation, children} = appearance
  match value:
    case Controls.Action{input, availability, name, face_value, response, size, placement, hint, feedback}:
      Doc.Element{key, "button", List.append(&2, Doc.Property, [property("type", "button"), property("class", "native-control"), property("aria-label", name), property("data-native-key", key)],
        List.append(&2, Doc.Property, unavailable(availability), List.append(&2, Doc.Property, behavior(response), help(hint)))),
        List.append(&2, Doc.Property, style(visual), List.append(&2, Doc.Property, geometry(size), List.append(&2, Doc.Property, placement_styles(placement), [property("anchor-name", css_anchor(key))]))), [Doc.Activate{key}], face(key, face_value)}
    case _: Doc.Element{key, "span", Nil{}, style(visual), Nil{}, Nil{}}





def render_shell(role: UI.Role, value: Doc.Node, shell: Design.Shell) -> Doc.Node:
  Design.Shell{navigation, main, details} = shell
  render_base(role, value, navigation, main, details)





def field_text(field: Forms.Field, value: Forms.Observed) -> String:
  match value:
    case Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}: context_field_text(field, origin, workspace, sandbox, approval)
    case Forms.WorkspaceValue{Domain.Workspace{roots, primary}}: workspace_field_text(field, roots, primary)
    case other: observed(other)





def field_options(+key: String, field: Forms.Field, value: Forms.Observed) -> +List<Doc.Node>:
  match field:
    case Forms.SandboxMode{}: [option(key, "workspace-write", "Workspace write"), option(key, "read-only", "Read only")]
    case Forms.ContextOrigin{}: origin_options(key, value)
    case Forms.ApprovalPolicy{}: [option(key, "ask", "Ask for approval"), option(key, "full-access", "Full access"), option(key, "automatic", "Automatic review")]
    case Forms.WorkspacePrimary{}: options(primary_choices(value), key)
    case Forms.CardStage{}: options(["backlog", "todo", "in_progress", "in_review", "done", "blocked"], key)
    case Forms.CardPriority{}: options(["none", "low", "medium", "high", "urgent"], key)
    case Forms.DeliveryIntent{}: [option(key, "send", "Send"), option(key, "steer", "Steer")]
    case _: [option(key, observed(value), "Current value")]





def creation_group_margin(flow: Design.CreationFlow) -> String:
  match flow:
    case Design.Balanced{}: "auto"
    case Design.Compact{}: "0"

def creation_bottom_padding(flow: Design.CreationFlow) -> String:
  match flow:
    case Design.Balanced{}: "80px"
    case Design.Compact{}: "24px"

def creation_group(band: Design.Band, flow: Design.CreationFlow, children: +List<Doc.Node>) -> Doc.Node:
  Design.Band{left, width} = band
  Doc.Element{"creation-group", "div", [property("data-region", "creation-group")],
    [property("width", px(width)), property("max-width", "100%"), property("display", "flex"),
      property("flex-direction", "column"), property("gap", "24px"), property("flex-shrink", "0"),
      property("margin-block", creation_group_margin(flow))], Nil{}, children}

def creation_canvas_nodes(canvas: Design.Box, band: Design.Band, +flow: Design.CreationFlow, children: +List<Doc.Node>) -> +List<Doc.Node>:
  [replace_styles(frame_region("creation-canvas", "creation", canvas, [creation_group(band, flow, children)]),
    [property("display", "flex"), property("flex-direction", "column"), property("align-items", "center"),
      property("overflow-y", "auto"), property("padding-top", "24px"), property("padding-bottom", creation_bottom_padding(flow))])]

# A page region owns its populated children. Ordinary nested sections and
# headings never participate in page placement.
def page_position(position: Composition.Position) -> String:
  match position:
    case Composition.HeadingPosition{}: "heading"
    case Composition.BodyPosition{}: "body"
    case Composition.DockPosition{}: "dock"

def page_region_attributes(+key: String, region: Composition.Region, position: Composition.Position) -> +List<Doc.Property>:
  [property("data-page-position", page_position(position)),
    property("data-page-region", Composition.region_name(region)), property("data-native-key", key)]

def page_region_styles(region: Composition.Region) -> +List<Doc.Property>:
  match region:
    case Composition.BoardControls{}:
      [property("display", "flex"), property("flex-wrap", "wrap"), property("align-items", "center"), property("gap", "8px"), property("min-width", "0"), property("max-width", "100%")]
    case Composition.ProjectActions{}:
      [property("display", "flex"), property("flex-wrap", "wrap"), property("gap", "8px"), property("min-width", "0")]
    case Composition.TaskActions{}:
      [property("display", "flex"), property("gap", "8px"), property("flex-shrink", "0")]
    case _:
      [property("display", "flex"), property("flex-direction", "column"), property("min-width", "0")]

def page_region(+key: String, +region: Composition.Region, position: Composition.Position, children: +List<Doc.Node>) -> Doc.Node:
  Doc.Element{key, "div", page_region_attributes(key, region, position), page_region_styles(region), Nil{}, children}

def at_page_position(position: String, node: Doc.Node) -> Bool:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: String.eq(attr(attrs, "data-page-position"), position)
    case _: False{}

def page_nodes(+children: +List<Doc.Node>, +position: String) -> +List<Doc.Node>:
  match position:
    case "heading": List.filter(~Doc.Node, (node => at_page_position("heading", node)), children)
    case "body": List.filter(~Doc.Node, (node => at_page_position("body", node)), children)
    case "dock": List.filter(~Doc.Node, (node => at_page_position("dock", node)), children)
    case _: Nil{}

def page_group(key: String, position: String, styles: +List<Doc.Property>, children: +List<Doc.Node>) -> Doc.Node:
  Doc.Element{key, "div", [property("data-page-group", position)], styles, Nil{}, children}

def intrinsic_heading_styles() -> +List<Doc.Property>:
  [property("display", "flex"), property("flex-wrap", "wrap"), property("align-items", "center"), property("justify-content", "space-between"), property("gap", "16px"), property("flex", "none"), property("min-width", "0")]

def remaining_body_styles() -> +List<Doc.Property>:
  [property("flex", "1"), property("min-height", "0"), property("min-width", "0"), property("overflow", "auto"), property("display", "flex"), property("flex-direction", "column"), property("gap", "16px")]

def page_shell_styles(+canvas: Design.Box) -> +List<Doc.Property>:
  List.append(&2, Doc.Property, bounds(canvas),
    [property("display", "flex"), property("flex-direction", "column"), property("gap", "24px"), property("min-height", "0"), property("box-sizing", "border-box")])

def overview_organization(organization: Composition.Body) -> String:
  match organization:
    case Composition.ProjectSections{}: "project-sections"
    case Composition.ProjectRows{}: "project-rows"
    case Composition.AgentRows{}: "agent-rows"
    case _: "overview"

def overview_body_styles(organization: Composition.Body) -> +List<Doc.Property>:
  match organization:
    case Composition.ProjectSections{}:
      List.append(&2, Doc.Property, remaining_body_styles(), [property("gap", "24px")])
    case Composition.ProjectRows{}:
      List.append(&2, Doc.Property, remaining_body_styles(), [property("gap", "12px")])
    case Composition.AgentRows{}:
      List.append(&2, Doc.Property, remaining_body_styles(), [property("gap", "12px")])
    case _: remaining_body_styles()

def overview_children(+children: +List<Doc.Node>, +organization: Composition.Body) -> +List<Doc.Node>:
  [page_group("overview-heading", "heading", intrinsic_heading_styles(), page_nodes(children, "heading")),
    Doc.Element{"overview-body", "div", [property("data-page-group", "body"), property("data-overview-organization", overview_organization(organization))],
      overview_body_styles(organization), Nil{}, page_nodes(children, "body")},
    page_group("overview-dock", "dock", [property("flex", "none")], page_nodes(children, "dock"))]

def overview_shell(+canvas: Design.Box, band: Design.Band, organization: Composition.Body, children: +List<Doc.Node>) -> Doc.Node:
  Design.Box{left, top, width, height} = canvas
  Design.Band{band_left, band_width} = band
  replace_styles(frame_region("overview-shell", "overview", canvas, overview_children(children, organization)),
    List.append(&2, Doc.Property, page_shell_styles(canvas),
      [property("padding-inline", px(Nat.sub(band_left, left))), property("padding-top", "24px")]))

def board_stage_region(value: Doc.Node, +width: Nat, +gap: Nat, +inset: Nat) -> Doc.Node:
  match value:
    case Doc.Element{key, tag, attrs, styles, events, children}:
      Doc.Element{key, tag, attrs,
        [property("display", "flex"), property("flex-direction", "row"), property("gap", px(gap)), property("padding", px(inset)), property("min-height", "0")], events, board_columns(children, width)}
    case other: other

def board_body_nodes(values: +List<Doc.Node>, +width: Nat, +gap: Nat, +inset: Nat) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: board_stage_region(value, width, gap, inset) <> board_body_nodes(rest, width, gap, inset)

def board_children(+children: +List<Doc.Node>, +width: Nat, +gap: Nat, +inset: Nat) -> +List<Doc.Node>:
  [page_group("board-heading", "heading", intrinsic_heading_styles(), page_nodes(children, "heading")),
    page_group("board-body", "body", remaining_body_styles(), board_body_nodes(page_nodes(children, "body"), width, gap, inset)),
    page_group("board-dock", "dock", [property("flex", "none")], page_nodes(children, "dock"))]

def board_shell(+canvas: Design.Box, width: Nat, gap: Nat, inset: Nat, children: +List<Doc.Node>) -> Doc.Node:
  replace_styles(frame_region("board-shell", "board", canvas, board_children(children, width, gap, inset)), page_shell_styles(canvas))

def conversation_heading_styles(+heading: Design.Box) -> +List<Doc.Property>:
  List.append(&2, Doc.Property, bounds(heading), [property("display", "flex"), property("align-items", "center"), property("justify-content", "space-between"), property("gap", "16px"), property("padding", "0 16px"), property("padding-right", "56px"), property("box-sizing", "border-box"), property("z-index", "5")])

def conversation_dock_styles(dock: Maybe<&2, Design.Dock>) -> +List<Doc.Property>:
  match dock:
    case None{}: [property("display", "none")]
    case Some{Design.Dock{Design.Band{left, width}, bottom, maximum, regions, input, reservation}}:
      [property("position", "fixed"), property("left", px(left)), property("bottom", px(bottom)), property("width", px(width)), property("max-height", px(maximum)), property("display", "flex"), property("flex-direction", "column"), property("gap", "8px"), property("z-index", "10")]

def conversation_children(+children: +List<Doc.Node>, +heading: Design.Box, +viewport: Design.Box, +reading: Design.Band, +dock: Maybe<&2, Design.Dock>) -> +List<Doc.Node>:
  [page_group("conversation-heading", "heading", conversation_heading_styles(heading), page_nodes(children, "heading")),
    Doc.Element{"conversation-body", "div", [property("data-region", "conversation-body"), property("data-page-group", "body")],
      timeline_styles(Design.ConversationFrame{heading, viewport, reading, dock}), Nil{}, page_nodes(children, "body")},
    Doc.Element{"conversation-dock", "div", [property("data-region", "dock"), property("data-page-group", "dock")],
      conversation_dock_styles(dock), Nil{}, page_nodes(children, "dock")}]


def main_children(+children: +List<Doc.Node>, frame: Design.MainFrame) -> +List<Doc.Node>:
  match frame:
    case Design.CreationFrame{heading, canvas, band, input, flow}:
      creation_canvas_nodes(canvas, band, flow, children)
    case Design.UnavailableFrame{heading, canvas, band}:
      [frame_region("unavailable-canvas", "unavailable", canvas, children)]
    case Design.ConversationFrame{heading, viewport, reading, dock}:
      conversation_children(children, heading, viewport, reading, dock)
    case Design.OverviewFrame{canvas, band, organization}:
      [overview_shell(canvas, band, organization, children)]
    case Design.BoardFrame{canvas, width, gap, inset}:
      [board_shell(canvas, width, gap, inset, children)]

def selected_reasoning(found: Bool, key: String, policy: Reasoning.Policy, fallback: +List<Doc.Node>) -> +List<Doc.Node>:
  match found:
    case True{}: policy_options(key, policy)
    case False{}: fallback





def execution_options(+key: String, field: String, configuration: Context.Configuration, preview: Context.Preview, projects: +List<View.ProjectChoice>, reviewers: +List<Domain.Profile>) -> +List<Doc.Node>:
  match field:
    case "context-origin": List.append(&2, Doc.Node, origin_options(key, Forms.ContextValue{preview}), project_origin_options(key, projects))
    case "approval-policy": List.append(&2, Doc.Node, [option(key, "ask", "Ask for approval"), option(key, "full-access", "Full access")], reviewer_options(key, reviewers))
    case _: Nil{}





def activity_found(found: Bool, +key: String, attrs: +List<Doc.Property>, styles: +List<Doc.Property>, events: +List<Doc.Event>, children: +List<Doc.Node>, expanded: Bool, audit: +List<Conversation.AuditFace>, fallback: Doc.Node) -> Doc.Node:
  match found:
    case True{}: Doc.Element{key, "details", List.append(&2, Doc.Property, attrs, opened(expanded)), styles, events, List.append(&2, Doc.Node, children, audit_nodes(key, audit))}
    case False{}: fallback





def node_value(value: UI.Meaning) -> String:
  match value:
    case UI.Edit{editor, field, entry, observed_value}: field_text(field, observed_value)
    case UI.BoardFilter{value}: filter_name(value)
    case UI.SearchChoices{query}: query
    case UI.BoardProfile{automatic, selected, choices, enabled}: selected
    case _: ""





def choice_options(+key: String, meaning: UI.Meaning) -> +List<Doc.Node>:
  match meaning:
    case UI.BoardProfile{automatic, selected, choices, enabled}: profile_options(choices, key)
    case UI.BoardFilter{value}: options(["all", "unlinked", "linked"], key)
    case UI.Edit{editor, field, entry, value}: field_options(key, field, value)
    case _: Nil{}





def action_leading(values: +List<Doc.Node>) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{last, Nil{}}: Nil{}
    case Con{value, rest}: value <> action_leading(rest)

def action_trailing(values: +List<Doc.Node>) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{last, Nil{}}: [last]
    case Con{value, rest}: action_trailing(rest)

def composer_action_groups(+key: String, +children: +List<Doc.Node>) -> +List<Doc.Node>:
  [Doc.Element{key ++ "/leading", "div", Nil{},
    [property("display", "flex"), property("align-items", "center"), property("flex-wrap", "wrap"), property("gap", "4px"), property("min-width", "0")], Nil{}, action_leading(children)},
   Doc.Element{key ++ "/trailing", "div", Nil{}, [property("display", "flex"), property("flex-shrink", "0")], Nil{}, action_trailing(children)}]

def board_input_styles() -> +List<Doc.Property>:
  [property("width", "auto"), property("max-width", "100%"), property("min-width", "0")]

def board_input(node: Doc.Node) -> Doc.Node:
  match node:
    case Doc.Element{key, +tag, attrs, styles, events, children}:
      match tag:
        case "select": Doc.Element{key, tag, attrs, List.append(&2, Doc.Property, styles, board_input_styles()), events, children}
        case "input": Doc.Element{key, tag, attrs, List.append(&2, Doc.Property, styles, board_input_styles()), events, children}
        case _: Doc.Element{key, tag, attrs, styles, events, children}
    case other: other

def board_labeled_inputs(values: +List<Doc.Node>) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{node, rest}: board_input(node) <> board_labeled_inputs(rest)

def board_control(node: Doc.Node) -> Doc.Node:
  match node:
    case Doc.Element{key, +tag, attrs, styles, events, children}:
      match tag:
        case "label": Doc.Element{key, tag, attrs, styles, events, board_labeled_inputs(children)}
        case _: board_input(Doc.Element{key, tag, attrs, styles, events, children})
    case other: other

def board_controls(values: +List<Doc.Node>) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{node, rest}: board_control(node) <> board_controls(rest)

def positioned_page_children_found(found: Bool, children: +List<Doc.Node>) -> +List<Doc.Node>:
  match found:
    case True{}: board_controls(children)
    case False{}: children

def positioned_page_children(region: String, children: +List<Doc.Node>) -> +List<Doc.Node>:
  positioned_page_children_found(String.eq(region, Composition.region_name(Composition.BoardControls{})), children)

def positioned_children(key: String, region: String, children: +List<Doc.Node>, frame: Design.MainFrame) -> +List<Doc.Node>:
  match region:
    case "main": main_children(children, frame)
    case "composer-actions": composer_action_groups(key, children)
    case _: children





def reasoning_options(+key: String, +profile: String, values: +List<Domain.Profile>) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Domain.Profile{id, provider, name, policy}, rest}: selected_reasoning(String.eq(id, profile), key, policy, reasoning_options(key, profile, rest))





def enriched_activity(+key: String, +attrs: +List<Doc.Property>, +styles: +List<Doc.Property>, +events: +List<Doc.Event>, +children: +List<Doc.Node>, values: +List<Conversation.VisibleGroup>) -> Doc.Node:
  match values:
    case Nil{}: Doc.Element{key, "details", attrs, styles, events, children}
    case Con{Conversation.VisibleActivity{id, attention, expanded, summary, audit, expand, collapse}, rest}:
      activity_found(String.eq(attr(attrs, "data-semantic"), "activity/" ++ Nat.show(id)), key, attrs, styles, events, children, expanded, audit, enriched_activity(key, attrs, styles, events, children, rest))
    case Con{other, rest}: enriched_activity(key, attrs, styles, events, children, rest)





def position_main(values: +List<Doc.Node>, +frame: Design.MainFrame) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Doc.Element{+key, tag, +attrs, styles, events, children}, rest}:
      Doc.Element{key, tag, attrs, List.append(&2, Doc.Property, styles, List.append(&2, Doc.Property, frame_styles(attr(attrs, "data-region"), frame), measured_input_styles(attr(attrs, "data-native-editor-key"), frame))), events, positioned_page_children(attr(attrs, "data-page-region"), positioned_children(key, attr(attrs, "data-region"), position_main(children, frame), frame))} <> position_main(rest, frame)
    case Con{other, rest}: other <> position_main(rest, frame)





def input_children(+key: String, meaning: UI.Meaning, widget: Controls.Widget) -> +List<Doc.Node>:
  match widget:
    case Controls.SelectInput{}: choice_options(key, meaning)
    case Controls.MultiSelectInput{}: choice_options(key, meaning)
    case Controls.PlainValue{}: [Doc.Text{node_value(meaning)}]
    case _: Nil{}





def model_group_options(+key: String, field: String, profile: String, choices: +List<Domain.Profile>) -> +List<Doc.Node>:
  match field:
    case "model-profile": profile_options(choices, key)
    case "reasoning-effort": reasoning_options(key, profile, choices)
    case _: Nil{}





def input(+key: String, +meaning: UI.Meaning, representation: Controls.Representation, visual: Design.Style) -> Doc.Node:
  match representation:
    case Controls.Input{binding, +name, +widget, placement, availability}:
      label_input(placement, key, name, Doc.Element{key, widget_tag(widget), List.append(&2, Doc.Property,
        List.append(&2, Doc.Property, [property("aria-label", name), property("data-native-key", key), property("value", node_value(meaning))], checked_properties(meaning)),
        List.append(&2, Doc.Property, widget_properties(widget), List.append(&2, Doc.Property, editor_properties(key, widget), List.append(&2, Doc.Property, meaning_properties(meaning), unavailable(availability))))),
        List.append(&2, Doc.Property, style(visual), input_style(widget)), input_events(key, widget), input_children(key, meaning, widget)})
    case _: Doc.Element{key, "output", Nil{}, style(visual), Nil{}, [Doc.Text{node_value(meaning)}]}





def group_options(+key: String, field: String, value: View.InputGroup) -> +List<Doc.Node>:
  match value:
    case View.ModelInput{profile, reasoning, choices}: model_group_options(key, field, profile, choices)
    case View.CardAssistanceInput{enabled, profile, choices}: assistance_options(key, field, choices)
    case View.ExecutionInput{configuration, preview, workspace, projects, reviewers}: execution_options(key, field, configuration, preview, projects, reviewers)
    case View.CardContentInput{value, projects, agents, stages, priorities, owners}: card_options(key, field, projects, owners)
    case _: Nil{}





def compound_field(+key: String, label: String, field: Forms.Field,
  visual: Design.Style, children: +List<Doc.Node>) -> Doc.Node:
  Doc.Element{key, "section", [property("data-native-key", key), property("aria-label", label),
    property("data-field", Forms.key(field)), property("tabindex", "-1")], style(visual), Nil{}, children}

def match_node(+key: String, +label: String, +role: UI.Role, meaning: UI.Meaning, +children: +List<UI.Node>, +rendered_children: +List<Doc.Node>, +visual: Design.Style, +representation: Controls.Representation, visual_children: +List<Design.Appearance>) -> Doc.Node:
  match meaning:
    case UI.Edit{editor, field, Forms.DirectoryCollection{}, value}: compound_field(key, label, field, visual, rendered_children)
    case UI.Edit{editor, field, Forms.FileCollection{}, value}: compound_field(key, label, field, visual, rendered_children)
    case UI.Activate{input_value, availability}: action(key, Design.Appearance{key, visual, representation, visual_children}, representation)
    case UI.PageRegion{region, position}: page_region(key, region, position, rendered_children)
    case UI.Region{}: Doc.Element{key, tag(role), [property("aria-label", label), property("data-native-key", key)], style(visual), Nil{},
      region_children(key, role, label, rendered_children)}
    case UI.ReadOnly{text}: Doc.Element{key, tag(role), [property("data-native-key", key)], style(visual), Nil{},
      Doc.Markdown{key ++ "/markdown", markdown_source(children), text} <> rendered_children}
    case UI.CodeFacts{Code.Scene{+identity, literal, wrap, copy, enabled, controls}}:
      Doc.Element{key, "div", Nil{}, [property("display", "contents")], Nil{}, [
        Doc.Portal{key ++ "/toolbar", Code.key(identity) ++ "/toolbar", rendered_children},
        Doc.TargetProperties{key ++ "/toolbar-observation", Code.key(identity) ++ "/toolbar", [property("data-native-key", key)], Nil{}},
        Doc.TargetProperties{key ++ "/wrap", Code.key(identity) ++ "/code", Nil{}, [property("white-space", code_wrap(wrap)), property("overflow-wrap", "anywhere")]}]}
    case UI.TaskFacts{details}: Doc.Element{key, "section", [property("data-native-key", key)], style(visual), Nil{}, task_details(key, details)}
    case UI.MovableCard{destinations}: Doc.Element{key, "article", [property("data-native-key", key), property("draggable", "true"), property("tabindex", "0")], style(visual), [Doc.DragCard{key}, Doc.DropCard{key}], Doc.Text{label} <> List.append(&2, Doc.Node, rendered_children, [movement_menu(key, destinations)])}
    case other: input(key, other, representation, visual)





def enriched_options(+key: String, +field: String, values: +List<View.InputGroup>) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: prefer_options(group_options(key, field, value), enriched_options(key, field, rest))





def render_nodes(values: +List<UI.Node>, appearances: +List<Design.Appearance>) -> +List<Doc.Node>:
  match values appearances:
    case Con{UI.Node{key, semantic, label, +role, meaning, +children}, rest} Con{Design.Appearance{identity, visual, representation, visual_children}, tail}:
      decorate(role_name(role), semantic, match_node(key, label, role, meaning, children, render_nodes(children, visual_children), visual, representation, Nil{})) <> render_nodes(rest, tail)
    case _ _: Nil{}





def enriched_element(+key: String, tag: String, +attrs: +List<Doc.Property>, styles: +List<Doc.Property>, events: +List<Doc.Event>, children: +List<Doc.Node>, groups: +List<View.InputGroup>, activities: +List<Conversation.VisibleGroup>) -> Doc.Node:
  match tag:
    case "select": Doc.Element{key, "select", attrs, styles, events, prefer_options(enriched_options(key, RenderField(attrs), groups), children)}
    case "details": enriched_activity(key, attrs, styles, events, children, activities)
    case other: Doc.Element{key, other, attrs, styles, events, children}





def render_node(value: UI.Node, appearance: Design.Appearance) -> Doc.Node:
  first_node(render_nodes([value], [appearance]))





def enrich_nodes(values: +List<Doc.Node>, +groups: +List<View.InputGroup>, +activities: +List<Conversation.VisibleGroup>) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Doc.Element{+key, +tag, +attrs, styles, events, children}, rest}:
      enriched_element(key, tag, attrs, styles, events, enrich_nodes(children, groups, activities), groups, activities) <> enrich_nodes(rest, groups, activities)
    case Con{other, rest}: other <> enrich_nodes(rest, groups, activities)





def render_base_node(+value: UI.Node, appearance: Design.Appearance, +shell: Design.Shell) -> Doc.Node:
  UI.Node{key, semantic, label, role, meaning, children} = value
  match semantic:
    case "settings/open":
      Design.Shell{navigation, main, details} = shell
      replace_styles(render_node(value, appearance), List.append(&2, Doc.Property,
        bounds(Layout.settings_bounds(navigation, main)), [property("z-index", "6")]))
    case _: render_shell(role, render_node(value, appearance), shell)

def base_nodes(values: +List<UI.Node>, appearances: +List<Design.Appearance>, +shell: Design.Shell) -> +List<Doc.Node>:
  match values appearances:
    case Con{+value, rest} Con{appearance, tail}:
      render_base_node(value, appearance, shell) <> base_nodes(rest, tail, shell)
    case _ _: Nil{}





def overlays(values: +List<UI.Node>, appearances: +List<Design.Appearance>, placements: +List<Design.Overlay>, +active: Maybe<&2, String>) -> +List<Doc.Node>:
  match values appearances placements:
    case Con{value, rest} Con{appearance, tail} Con{Design.Overlay{key, level, placement}, remaining}:
      replace_styles(modal_scope(key, active, render_node(value, appearance)), List.append(&2, Doc.Property, overlay_styles(placement), [property("z-index", Nat.show(Nat.add(50n, level)))])) <>
        overlays(rest, tail, remaining, active)
    case _ _ _: Nil{}





# Semantic token aliases are computed at the document root. The host resolves
# this physical target; the theme decision remains the Bend presentation value.
def document_theme(+theme: Design.Theme) -> Doc.Node:
  Doc.TargetProperties{"document-theme", "@document/root",
    [property("data-theme", theme_name(theme))], [property("color-scheme", theme_name(theme))]}

def render(scene: Web.Scene) -> Doc.Document:
  Web.Scene{UI.Surface{+content, base, overlays_value, +active}, platform, generation, realization,
    Design.Presentation{Design.Layout{Design.Viewport{width, height}, shell, main, placements},
    Design.Visuals{+theme, rhythm, base_appearance, overlay_appearance}}} = scene
  Doc.Document{Doc.Element{"application", "div", [property("data-document", "application"), property("class", theme_class(theme))],
    [property("position", "fixed"), property("inset", "0"), property("overflow", "hidden"), property("background", "var(--color-token-main-surface-primary)"), property("color", "var(--color-token-text-primary)")], Nil{},
    document_theme(theme) <> enrich_nodes(List.append(&2, Doc.Node, [base_scope(active, reading_nodes(position_main(base_nodes(base, base_appearance, shell), main), reading_identity(content)))], overlays(overlays_value, overlay_appearance, placements, active)), scene_groups(content), scene_activities(content))}, "Selvedge"}
