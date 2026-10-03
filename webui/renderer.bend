import Base
import ./enclosure.bend as Enclosure
import ../bendlib/stdlib.bend as Std
import ./document.bend as Doc
import ./MODEL.bend as Web
import ./design.bend as Design
import ./typography.bend as T
import ./surfaces.bend as Surfaces
import ./appearance.bend as Appearance
import ./layout.bend as Layout
import ./controls.bend as Controls
import ./editor-layout.bend as EditorLayout
import ../core/interface.bend as UI
import ../core/composition.bend as Composition
import ../core/form-fields.bend as Forms
import ../core/field-options.bend as FieldOptions
import ../core/ui-world.bend as View
import ../core/code-block.bend as Code
import ../core/user-context.bend as Context
import ../bendlib/domain.bend as Domain
import ../BOARD.bend as Board
import ../core/user-input.bend as User
import ../core/user-experience.bend as Experience
import ../core/SYSTEM.bend as Core
import ../core/user-conversation.bend as Conversation
import ../REASONING.bend as Reasoning

# NOTE: Bend requires layout helpers to be filled before structural lowering;
# each child result carries its source metadata into those nonrecursive helpers.
type Child is Data:
  Child{source: Design.Node, document: Doc.Node}

def documents(values: +List<Child>) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Child{source, document}, rest}: document <> documents(rest)

def sources(values: +List<Child>) -> +List<Design.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Child{source, document}, rest}: source <> sources(rest)


type DialogParts is Data:
  DialogParts{header: +List<Doc.Node>, body: +List<Doc.Node>, layouts: +List<EditorLayout.SectionKind>}

# Every browser primitive is selected here. Geometry is in viewport coordinates;
# the host must not subtract a parent box or choose controls from product state.
def property(name: String, value: String) -> Doc.Property:
  Doc.Property{name, value}


def px(value: Nat) -> String:
  Nat.show(value) ++ "px"


def surface_color(value: Surfaces.Color) -> String:
  match value:
    case Surfaces.Clear{}: "transparent"
    case Surfaces.Token{name}: "var(" ++ name ++ ")"
    case Surfaces.Blend{foreground, percent, background}:
      "color-mix(in srgb, var(" ++ foreground ++ ") " ++ Nat.show(percent) ++ "%, var(" ++ background ++ "))"

def surface_background(role: Surfaces.Role, phase: Surfaces.Phase) -> String:
  surface_color(Surfaces.background(role, phase))

def paint(value: Design.Paint) -> String:
  match value:
    case Design.Transparent{}: "transparent"
    case Design.ThemeToken{name}: "var(" ++ name ++ ")"
    case Design.SurfacePaint{role, phase}: surface_background(role, phase)
    case Design.SurfaceForeground{role}: surface_color(Surfaces.foreground(role))




def resolved_font(value: T.TextStyle) -> T.Font:
  T.TextStyle{family, size, line_height, weight} = value
  family

def resolved_size(value: T.TextStyle) -> Nat:
  T.TextStyle{family, size, line_height, weight} = value
  size

def resolved_leading(value: T.TextStyle) -> Nat:
  T.TextStyle{family, size, line_height, weight} = value
  line_height

def resolved_weight(value: T.TextStyle) -> Nat:
  T.TextStyle{family, size, line_height, weight} = value
  weight

def text_properties(+value: T.TextStyle) -> +List<Doc.Property>:
  [property("font-family", T.font_family(resolved_font(value))), property("font-size", px(resolved_size(value))),
   property("line-height", px(resolved_leading(value))), property("font-weight", Nat.show(resolved_weight(value)))]

def text_presentation(value: T.Presentation) -> +List<Doc.Property>:
  text_properties(T.resolved(value))

def part_text(+parent: T.Presentation, tier: T.Tier, emphasis: T.Emphasis) -> +List<Doc.Property>:
  text_presentation(T.with_emphasis(T.with_tier(parent, tier), emphasis))

def rich_resolved(+prefix: String, +value: T.TextStyle) -> +List<Doc.Property>:
  [property(prefix ++ "-size", px(resolved_size(value))), property(prefix ++ "-line", px(resolved_leading(value))),
   property(prefix ++ "-weight", Nat.show(resolved_weight(value))), property(prefix ++ "-font", T.font_family(resolved_font(value)))]

def rich_role(prefix: String, parent: T.Presentation, tier: T.Tier, emphasis: T.Emphasis) -> +List<Doc.Property>:
  rich_resolved(prefix, T.resolved(T.with_emphasis(T.with_tier(parent, tier), emphasis)))

def rich_properties(+parent: T.Presentation) -> +List<Doc.Property>:
  List.append(&2, Doc.Property, rich_role("--rich-title", parent, T.Title{}, T.Strong{}),
    List.append(&2, Doc.Property, rich_role("--rich-section", parent, T.Section{}, T.Medium{}),
      List.append(&2, Doc.Property, rich_role("--rich-body", parent, T.Body{}, T.Regular{}),
        List.append(&2, Doc.Property, rich_role("--rich-support", parent, T.Support{}, T.Medium{}),
          List.append(&2, Doc.Property, rich_role("--rich-code", parent, T.CodeBody{}, T.Regular{}),
            rich_role("--rich-body-strong", parent, T.Body{}, T.Strong{}))))))

def icon_path(value: Controls.Icon) -> String:
  match value:
    case Controls.Hand{}: "M12.6683 4.16699C12.6683 3.84391 12.4065 3.58203 12.0834 3.58203C11.7603 3.58203 11.4984 3.84391 11.4984 4.16699V7.91699L11.4847 8.05078C11.4227 8.35375 11.1547 8.58203 10.8334 8.58203C10.4662 8.58203 10.1685 8.28411 10.1683 7.91699V3.75C10.1683 3.42691 9.90646 3.16504 9.58337 3.16504C9.26029 3.16504 8.99841 3.42691 8.99841 3.75V7.91699C8.99824 8.28411 8.70053 8.58203 8.33337 8.58203C7.96621 8.58203 7.66851 8.28411 7.66833 7.91699V5C7.66833 4.67691 7.40646 4.41504 7.08337 4.41504C6.76029 4.41504 6.49841 4.67691 6.49841 5V9.30371C6.53326 9.3429 6.56715 9.38359 6.59998 9.42578L8.02478 11.2588C8.25005 11.5486 8.19821 11.9659 7.90857 12.1914C7.6187 12.4169 7.20048 12.365 6.97498 12.0752L5.55017 10.2432C5.15812 9.7391 4.41813 9.73637 4.01501 10.1924C4.04396 10.426 4.11486 10.8323 4.25525 11.3486C4.44664 12.0525 4.75404 12.9113 5.21619 13.7383C6.14103 15.3931 7.62465 16.835 10.0004 16.835C12.8545 16.8348 15.1682 14.5211 15.1683 11.667V6.25C15.1683 5.92691 14.9065 5.66504 14.5834 5.66504C14.2603 5.66504 13.9984 5.92691 13.9984 6.25V9.16699C13.9982 9.53411 13.7005 9.83203 13.3334 9.83203C12.9662 9.83203 12.6685 9.53411 12.6683 9.16699V4.16699ZM13.9984 4.42578C14.1828 4.36671 14.3794 4.33496 14.5834 4.33496C15.641 4.33496 16.4984 5.19237 16.4984 6.25V11.667C16.4982 15.2557 13.589 18.1649 10.0004 18.165C6.95953 18.165 5.10939 16.2734 4.05505 14.3867C3.52774 13.4431 3.1843 12.4787 2.97205 11.6982C2.76447 10.9349 2.66834 10.2954 2.66833 10C2.66833 9.87959 2.70117 9.76148 2.76306 9.6582C3.28988 8.78018 4.26555 8.40372 5.16833 8.56152V5C5.16833 3.94237 6.02575 3.08496 7.08337 3.08496C7.31706 3.08496 7.54039 3.12845 7.74744 3.20508C7.98218 2.41297 8.7151 1.83496 9.58337 1.83496C10.1836 1.83496 10.7186 2.11176 11.0697 2.54395C11.3639 2.35978 11.7107 2.25195 12.0834 2.25195C13.141 2.25195 13.9984 3.10937 13.9984 4.16699V4.42578Z"
    case Controls.ShieldCode{}: "M9.06543 1.95123C9.66107 1.69076 10.3389 1.69071 10.9346 1.95123L15.9346 4.13873C16.7832 4.51008 17.3311 5.34917 17.3311 6.27545V10.5528C17.3309 14.6017 14.0489 17.8847 10 17.8848C5.95108 17.8846 2.66813 14.6017 2.66797 10.5528V6.27545C2.66797 5.34924 3.21695 4.51012 4.06543 4.13873L9.06543 1.95123ZM10.4014 3.16998C10.1456 3.05814 9.85444 3.05819 9.59863 3.16998L4.59863 5.35748C4.23427 5.51708 3.99805 5.87764 3.99805 6.27545V10.5528C3.99821 13.8671 6.68563 16.5546 10 16.5547C13.3144 16.5546 16.0008 13.8671 16.001 10.5528V6.27545C16.001 5.87756 15.7658 5.51703 15.4014 5.35748L10.4014 3.16998Z M13.4678 11.4318L13.333 11.4182H10.833C10.466 11.4183 10.1682 11.7162 10.168 12.0832C10.168 12.4504 10.4659 12.7481 10.833 12.7482H13.333L13.4678 12.7346C13.7706 12.6724 13.9981 12.4044 13.9981 12.0832C13.9979 11.7621 13.7706 11.494 13.4678 11.4318Z M7.65336 12.426C7.46431 12.7406 7.05607 12.8424 6.74125 12.6535C6.42646 12.4646 6.32395 12.0563 6.51274 11.7414L7.55668 10.0002L6.51274 8.25899C6.32395 7.94412 6.42646 7.53583 6.74125 7.34688C7.05607 7.15799 7.46431 7.25975 7.65336 7.57442L8.90336 9.6584C9.0296 9.86893 9.0296 10.1315 8.90336 10.342L7.65336 12.426Z"
    case Controls.Shield{}: "M9.06543 1.95123C9.66107 1.69076 10.3389 1.69071 10.9346 1.95123L15.9346 4.13873C16.7832 4.51008 17.3311 5.34917 17.3311 6.27545V10.5528C17.3309 14.6017 14.0489 17.8847 10 17.8848C5.95108 17.8846 2.66813 14.6017 2.66797 10.5528V6.27545C2.66797 5.34924 3.21695 4.51012 4.06543 4.13873L9.06543 1.95123ZM10.4014 3.16998C10.1456 3.05814 9.85444 3.05819 9.59863 3.16998L4.59863 5.35748C4.23427 5.51708 3.99805 5.87764 3.99805 6.27545V10.5528C3.99821 13.8671 6.68563 16.5546 10 16.5547C13.3144 16.5546 16.0008 13.8671 16.001 10.5528V6.27545C16.001 5.87756 15.7658 5.51703 15.4014 5.35748L10.4014 3.16998Z M10.8883 13.1116C10.8883 13.6025 10.4903 14.0005 9.99936 14.0005C9.50844 14.0005 9.11047 13.6025 9.11047 13.1116C9.11047 12.6207 9.50844 12.2227 9.99936 12.2227C10.4903 12.2227 10.8883 12.6207 10.8883 13.1116Z M10.5169 10.8949L11.1135 7.31519C11.2283 6.62672 10.6974 6 9.99941 6C9.30145 6 8.77053 6.62672 8.88528 7.31519L9.4819 10.8949C9.52406 11.1479 9.74294 11.3333 9.99941 11.3333C10.2559 11.3333 10.4748 11.1479 10.5169 10.8949Z"
    case Controls.Eye{}: "M 1.71833 10.29 a 0.833333 0.833333 0 0 1 0 -0.58 8.95833 8.95833 0 0 1 16.5633 0 0.833333 0.833333 0 0 1 0 0.58 8.95833 8.95833 0 0 1 -16.5633 0 M12.5 10a2.5 2.5 0 1 0-5 0a2.5 2.5 0 1 0 5 0"
    case Controls.Globe{}: "M18.3333 10a8.3333 8.3333 0 1 0-16.6666 0a8.3333 8.3333 0 1 0 16.6666 0 M 10 1.66667 a 12.0833 12.0833 0 0 0 0 16.6667 12.0833 12.0833 0 0 0 0 -16.6667 M 1.66667 10 h 16.6667"
    case Controls.GlobeOff{}: "M18.3333 10a8.3333 8.3333 0 1 0-16.6666 0a8.3333 8.3333 0 1 0 16.6666 0 M 10 1.66667 a 12.0833 12.0833 0 0 0 0 16.6667 12.0833 12.0833 0 0 0 0 -16.6667 M 1.66667 10 h 16.6667 M3 3L17 17"
    case Controls.ChevronRight{}: "M7.5 4.5 L13 10 L7.5 15.5"
    case Controls.ChevronDown{}: "M4.5 7.5 L10 13 L15.5 7.5"
    case Controls.StopSquare{}: "M6 5h8a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1Z"
    case Controls.PauseBars{}: "M7 5v10M13 5v10"
    case Controls.PlayTriangle{}: "m7 4 9 6-9 6Z"
    case Controls.CloseCross{}: "m5 5 10 10M15 5 5 15"
    case Controls.MoreDots{}: "M4 10h.01M10 10h.01M16 10h.01"
    case Controls.Sidebar{}: "M3 4h14v12H3ZM7 4v12"
    case Controls.SidebarClose{}: "M3 4h14v12H3ZM7 4v12 M13 7l-3 3 3 3"
    case Controls.Folder{}: "M2.5 6V4.5h5l2 2h8V16h-15Z"
    case Controls.Conversation{}: "M3 3.5h14v10H8l-5 3Z"
    case Controls.Columns{}: "M3 3h14v14H3ZM7.7 3v14M12.3 3v14"
    case Controls.Agents{}: "M13 9a3 3 0 1 0-6 0 3 3 0 0 0 6 0ZM4 17v-1a4 4 0 0 1 4-4h4a4 4 0 0 1 4 4v1"
    case Controls.Plus{}: "M10 3v14M3 10h14"
    case Controls.Pencil{}: "m12.5 3 4.5 4.5-9 9-5 1 1-5ZM10.5 5l4.5 4.5"
    case Controls.Branch{}: "M6 4v12M6 11h4a4 4 0 0 0 4-4V4M4 2h4v4H4ZM4 14h4v4H4ZM12 2h4v4h-4Z"
    case Controls.Compact{}: "M3 5h14M3 10h10M3 15h7m3-2 3 3 3-3M16 10v6"
    case Controls.Settings{}: "m8 2-.5 2-2 .9-1.8-.5-1.5 2.5 1.4 1.4v2.4l-1.4 1.4L3.7 15l1.8-.5 2 .9.5 2.1h3l.5-2.1 2-.9 1.8.5 1.5-2.5-1.4-1.4V8.7l1.4-1.4-1.5-2.5-1.8.5-2-.9L11 2Zm4.5 8a2.5 2.5 0 1 1-5 0 2.5 2.5 0 0 1 5 0Z"
    case Controls.FilterFunnel{}: "M3 4h14l-5.3 6.1v5.1l-3.4 1.8v-6.9L3 4Z"
    case Controls.Inspector{}: "M3 3h14v14H3ZM12 3v14M5.5 6h4M5.5 10h4M5.5 14h4"
    case Controls.InspectorClose{}: "M3 3h14v14H3ZM12 3v14M5.5 6h4M5.5 10h4M5.5 14h4 M7 7l3 3-3 3"
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


def widget_tag(value: Controls.Widget) -> String:
  match value:
    case Controls.MessageInput{}: "textarea"
    case Controls.TextArea{}: "textarea"
    case Controls.DirectoryList{}: "textarea"
    case Controls.SelectInput{}: "select"
    case Controls.MultiSelectInput{}: "select"
    case Controls.PlainValue{}: "output"
    case _: "input"


def input_events(+key: String, widget: Controls.Widget) -> +List<Doc.Event>:
  match widget:
    case Controls.PlainValue{}: Nil{}
    case Controls.ToggleInput{}: [Doc.EditToggle{key}]
    case Controls.DirectoryChooser{face}: [Doc.EditText{key}, Doc.ConfirmText{key}]
    case Controls.FileChooser{face}: [Doc.SelectFiles{key}]
    case Controls.AttachmentList{}: [Doc.SelectFiles{key}]
    case _: [Doc.EditText{key}]


def tag(role: UI.Role) -> String:
  match role:
    case UI.Navigation{}: "nav"
    case UI.NavigationHeader{}: "header"
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


def code_wrap(value: Bool) -> String:
  match value:
    case True{}: "pre-wrap"
    case False{}: "pre"


def role_name(value: UI.Role) -> String:
  match value:
    case UI.NavigationHeader{}: "navigation-header"
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


def markdown_source(values: +List<Child>) -> Maybe<&2, Code.Source>:
  match values:
    case Nil{}: None{}
    case Con{Child{Design.Node{key, semantic, label, role, UI.CodeFacts{Code.Scene{Code.Identity{source, ordinal}, literal, wrap, copy, enabled, controls}}, visual, representation, children}, document}, rest}: Some{source}
    case Con{other, rest}: markdown_source(rest)


def filter_search(value: Board.Filter) -> String:
  match value:
    case Board.Filter{view, search, status, priority, date, assignee, creator, project, label}: search


def origin_text(value: Context.Origin) -> String:
  match value:
    case Context.EnvironmentDefaults{}: "environment"
    case Context.ProjectDefaults{project}: "project/" ++ Nat.show(project)
    case Context.ParentTask{task}: "parent/" ++ Nat.show(task)
    case Context.ProjectForParent{task, project}: "project-for-parent/" ++ Nat.show(task) ++ "/" ++ Nat.show(project)


def approval_text(value: Context.ApprovalValue) -> String:
  Context.approval_option(Context.observed_approval(value))


def frame_input(value: Design.MainFrame) -> Maybe<&2, Design.InputMetrics>:
  match value:
    case Design.CreationFrame{heading, canvas, band, input, flow}: input
    case Design.ConversationFrame{heading, viewport, reading, Some{Design.Dock{band, bottom, maximum, regions, input, reservation}}}: input
    case _: None{}


def css_characters(value: String) -> String:
  match value:
    case SNil{}: ""
    case SCon{head, rest}: "-" ++ U32.show(Char.to_u32(head)) ++ css_characters(rest)


def theme_name(value: Design.Theme) -> String:
  match value:
    case Design.Light{}: "light"
    case Design.Dark{}: "dark"

def theme_class(value: Design.Theme) -> String:
  match value:
    case Design.Light{}: "native-application light"
    case Design.Dark{}: "native-application dark"


def generated_identity(owner: String, part: String) -> String:
  owner ++ "/@" ++ part

def activity_summary(owner: String, label: String, values: +List<Doc.Node>) -> +List<Doc.Node>:
  match values:
    case Con{Doc.Element{key, tag, attrs, styles, events, children}, rest}:
      Doc.Element{key, "summary", attrs, styles, events, List.append(&2, Doc.Node, children, [Doc.Text{" " ++ label}])} <> rest
    case Nil{}: [Doc.Element{generated_identity(owner, "summary"), "summary", Nil{}, Nil{}, Nil{}, [Doc.Text{label}]}]
    case Con{other, rest}: other <> rest

def content_area_properties(+area: Enclosure.ContentArea) -> +List<Doc.Property>:
  [property("padding-inline", px(Enclosure.inline(area))),
   property("padding-block", px(Enclosure.block(area))), property("box-sizing", "border-box")]

def bounds(box: Design.Box) -> +List<Doc.Property>:
  Design.Box{left, top, width, height} = box
  [property("position", "fixed"), property("left", px(left)), property("top", px(top)),
   property("width", px(width)), property("height", px(height)), property("box-sizing", "border-box")]


def content_alignment(value: Controls.ContentAlignment) -> String:
  match value:
    case Controls.CenterContents{}: "center"
    case Controls.LeadingContents{}: "flex-start"

def flow(value: Design.Flow) -> +List<Doc.Property>:
  match value:
    case Design.BlockFlow{}: [property("display", "block")]
    case Design.ColumnFlow{}: [property("display", "flex"), property("flex-direction", "column")]
    case Design.RowFlow{}: [property("display", "flex"), property("align-items", "center")]
    case Design.SplitRowFlow{}: [property("display", "flex"), property("align-items", "center"), property("justify-content", "space-between")]
    case Design.WrapFlow{}: [property("display", "flex"), property("flex-wrap", "wrap")]
    case Design.InlineControlFlow{alignment}: [property("display", "inline-flex"), property("flex-direction", "row"), property("align-items", "center"), property("justify-content", content_alignment(alignment))]
    case Design.ChoiceFlow{}: [property("display", "flex"), property("flex-direction", "row"), property("align-items", "center"), property("justify-content", "space-between")]


def overflow_style(value: Design.Overflow) -> +List<Doc.Property>:
  match value:
    case Design.SingleLineOverflow{}: [property("overflow", "hidden"), property("text-overflow", "ellipsis"), property("white-space", "nowrap")]
    case Design.ContentFlow{}: Nil{}
    case Design.ScrollFlow{}: [property("overflow", "auto")]
    case Design.CodeOverflow{}: [property("overflow", "auto")]


def icon_paint_properties(value: Controls.IconPaint) -> +List<Doc.Property>:
  match value:
    case Controls.FilledIcon{}: [property("fill", "currentColor"), property("stroke", "none")]
    case Controls.StrokedIcon{}: [property("fill", "none"), property("stroke", "currentColor"), property("stroke-width", "1.4"), property("stroke-linecap", "round"), property("stroke-linejoin", "round")]

def icon(+key: String, +value: Controls.Icon) -> Doc.Node:
  Doc.Element{key ++ "/icon", "svg", List.append(&2, Doc.Property,
    [property("viewBox", "0 0 20 20"), property("aria-hidden", "true")], icon_paint_properties(Controls.icon_paint(value))),
    [property("width", "var(--native-icon-size,16px)"), property("height", "var(--native-icon-size,16px)"), property("flex-shrink", "0"), property("display", "block")], Nil{},
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
    case Controls.Toggle{pressed}: [property("aria-pressed", FieldOptions.boolean(pressed))]
    case Controls.Radio{checked}: [property("role", "menuitemradio"), property("aria-checked", FieldOptions.boolean(checked))]
    case Controls.ChoiceRadio{checked}: [property("role", "radio"), property("aria-checked", FieldOptions.boolean(checked))]
    case Controls.Disclosure{expanded}: [property("aria-expanded", FieldOptions.boolean(expanded))]
    case Controls.Popup{menu, expanded}: [property("aria-haspopup", "true"), property("aria-expanded", FieldOptions.boolean(expanded))]
    case Controls.Destination{current}: [property("aria-current", FieldOptions.boolean(current))]


def geometry(value: Controls.Geometry) -> +List<Doc.Property>:
  Controls.Geometry{width, height, icon_size, radius, leading} = value
  [property("min-width", px(width)), property("min-height", px(height)), property("border-radius", px(radius)),
   property("display", "inline-flex"), property("align-items", "center"), property("--native-icon-size", px(icon_size)), property("--native-leading-slot", px(leading))]


def action_geometry(size: Controls.Geometry, visual: Design.Style) -> +List<Doc.Property>:
  Controls.Geometry{width, height, icon_size, radius, leading} = size
  [property("min-width", px(width)), property("--native-icon-size", px(icon_size)), property("--native-leading-slot", px(leading))]

def greater_extent(less: Bool, width: Nat, height: Nat) -> Nat:
  match less:
    case True{}: height
    case False{}: width

def square_extent(+width: Nat, +height: Nat) -> Nat:
  greater_extent(Nat.is_lt(width, height), width, height)

def icon_content_extent(size: Controls.Geometry) -> +List<Doc.Property>:
  Controls.Geometry{+width, +height, icon_size, radius, leading} = size
  [property("width", px(square_extent(width, height))), property("height", px(square_extent(width, height))), property("flex-shrink", "0"), property("box-sizing", "border-box")]

def content_extent(face: Controls.Face, size: Controls.Geometry) -> +List<Doc.Property>:
  match face:
    case Controls.IconFace{icon}: icon_content_extent(size)
    case Controls.ChoiceFace{text, description, checked}: [property("width", "100%"), property("min-width", "0"), property("height", "auto"), property("flex-shrink", "0")]
    case Controls.SingleLineFace{text}: [property("flex", "1 1 0"), property("width", "auto"), property("text-align", "start")]
    case _: [property("min-width", "0"), property("max-width", "100%"), property("text-align", "left")]

def content_geometry_layout(face: Controls.Face, size: Controls.Geometry, layout: Controls.ContentLayout) -> +List<Doc.Property>:
  content_extent(face, size)

def content_geometry(+face: Controls.Face, size: Controls.Geometry) -> +List<Doc.Property>:
  content_geometry_layout(face, size, Controls.content_layout(face))

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


def section_label(owner: String, empty: Bool, text: String, +typography: T.Presentation) -> +List<Doc.Node>:
  match empty:
    case True{}: Nil{}
    case False{}: [Doc.Element{generated_identity(owner, "title"), "h2", Nil{}, List.append(&2, Doc.Property, part_text(typography, T.Body{}, T.Medium{}), [property("margin", "0")]), Nil{}, [Doc.Text{text}]}]

def region_label(owner: String, role: UI.Role, +text: String, +typography: T.Presentation) -> +List<Doc.Node>:
  match role:
    case UI.NavigationHeader{}:
      [Doc.Element{generated_identity(owner, "brand"), "span", [property("data-navigation-brand", "")],
        List.append(&2, Doc.Property, part_text(typography, T.Section{}, T.Medium{}), [property("letter-spacing", "-0.01em")]), Nil{}, [Doc.Text{text}]}]
    case UI.Heading{}: [Doc.Text{text}]
    case UI.Section{}: section_label(owner, String.is_empty(text), text, typography)
    case UI.Dialog{}: [Doc.Element{generated_identity(owner, "title"), "h2", Nil{}, Nil{}, Nil{}, [Doc.Text{text}]}]
    case UI.Activity{}: [Doc.Element{generated_identity(owner, "summary"), "summary", Nil{}, Nil{}, Nil{}, [Doc.Text{text}]}]
    case _: Nil{}


def region_styles(value: String) -> +List<Doc.Property>:
  match value:
    case "user-message": [property("width", "fit-content"), property("margin-left", "auto")]
    case "agent-message": [property("width", "100%")]
    case "navigation": [property("height", "100%")]
    case "navigation-header": [property("flex-shrink", "0"), property("padding-bottom", "8px"), property("border-bottom", "1px solid var(--color-token-border-light)")]
    case _: Nil{}

def attr_last(values: +List<Doc.Property>, +name: String, previous: String) -> String:
  match values:
    case Nil{}: previous
    case Con{Doc.Property{key, value}, rest}: attr_last(rest, name, attr_found(String.eq(key, name), value, previous))

def attr(values: +List<Doc.Property>, name: String) -> String:
  attr_last(values, name, "")


def composer_styles(value: Design.MainFrame) -> +List<Doc.Property>:
  match value:
    case Design.CreationFrame{heading, canvas, band, input, flow}:
      [property("width", "100%"), property("flex-shrink", "0")]
    case Design.ConversationFrame{heading, viewport, reading, Some{Design.Dock{Design.Band{left, width}, bottom, maximum, regions, input, reservation}}}:
      [property("position", "relative"), property("width", "100%"), property("max-height", px(maximum)), property("min-width", "0")]
    case _: Nil{}


def input_style(value: Controls.Widget) -> +List<Doc.Property>:
  match value:
    case Controls.MessageInput{}: [property("width", "100%"), property("resize", "none"), property("outline", "none"), property("field-sizing", "content")]
    case Controls.ToggleInput{}:
      [property("width", px(Appearance.toggle_extent())), property("height", px(Appearance.toggle_extent())),
       property("margin", "0"), property("flex", "none")]
    case _: [property("width", "100%")]

def input_style_for(meaning: UI.Meaning, widget: Controls.Widget) -> +List<Doc.Property>:
  match meaning:
    case UI.BoardSearch{filter}: Nil{}
    case _: input_style(widget)


def workspace_primary(value: Context.WorkspaceValue) -> String:
  match value:
    case Context.InheritedWorkspace{Domain.Workspace{roots, primary}}: FieldOptions.optional_text(primary)
    case Context.EnteredWorkspace{Domain.Workspace{roots, primary}}: FieldOptions.optional_text(primary)


def network_text(value: Context.SandboxValue) -> String:
  match value:
    case Context.InheritedSandbox{Domain.Sandbox{mode, network}}: FieldOptions.boolean(network)
    case Context.ChosenSandbox{Domain.Sandbox{mode, network}}: FieldOptions.boolean(network)


def workspace_field_text(field: Forms.Field, roots: +List<String>, primary: Maybe<&2, String>) -> String:
  match field:
    case Forms.WorkspacePrimary{}: FieldOptions.optional_text(primary)
    case _: FieldOptions.joined(roots)


def option(+key: String, +value: String, label: String) -> Doc.Node:
  Doc.Element{key ++ "/option/" ++ value, "option", [property("value", value)], Nil{}, Nil{}, [Doc.Text{label}]}


def fact_content_styles() -> +List<Doc.Property>:
  [property("min-width", "0"), property("overflow-wrap", "anywhere")]

def fact_frame_styles(frame: Enclosure.Frame) -> +List<Doc.Property>:
  [property("display", "flex"), property("flex-direction", "column"),
    property("gap", px(Enclosure.frame_gap(frame))), property("min-width", "0")]

def fact(+key: String, label: String, value: String) -> Doc.Node:
  Doc.Element{key, "div", Nil{}, fact_frame_styles(Design.fact_frame()), Nil{},
    [Doc.Element{key ++ "/label", "strong", Nil{}, fact_content_styles(), Nil{}, [Doc.Text{label}]},
     Doc.Element{key ++ "/value", "span", Nil{}, fact_content_styles(), Nil{}, [Doc.Text{value}]}]}


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


def reading_element(region: String, +key: String, tag: String, attrs: +List<Doc.Property>, styles: +List<Doc.Property>, events: +List<Doc.Event>, children: +List<Doc.Node>, identity: Maybe<&2, Conversation.Identity>) -> Doc.Node:
  match region identity:
    case "conversation-body" Some{Conversation.Identity{+task, generation}}:
      +body_key = "conversation/" ++ Nat.show(task) ++ "/body"
      Doc.Element{body_key, tag, List.append(&2, Doc.Property, attrs, [property("data-reading-scroll", ""), property("data-reading-task", Nat.show(task)), property("data-reading-generation", Nat.show(generation))]), styles, events,
        [Doc.Element{body_key ++ "/reading-content", "div", [property("data-reading-content", ""), property("data-reading-task", Nat.show(task))], [property("display", "flex"), property("flex-direction", "column"), property("gap", "16px")], Nil{}, children}]}
    case "dock" Some{Conversation.Identity{task, generation}}:
      Doc.Element{key, tag, List.append(&2, Doc.Property, attrs, [property("data-reading-dock", ""), property("data-reading-task", Nat.show(task))]), styles, events, children}
    case _ _: Doc.Element{key, tag, attrs, styles, events, children}


def label_input(placement: Controls.LabelPlacement, +key: String, +name: String, input: Doc.Node) -> Doc.Node:
  match placement:
    case Controls.AccessibleOnly{}: input
    case Controls.AboveInput{}: Doc.Element{key ++ "/field", "label", Nil{}, [property("display", "flex"), property("min-width", "0"), property("max-width", "100%"), property("flex-direction", "column"), property("gap", "6px"), property("margin", "0")], Nil{}, [Doc.Text{name}, input]}
    case Controls.BesideInput{}: Doc.Element{key ++ "/field", "label", Nil{}, [property("display", "flex"), property("min-width", "0"), property("max-width", "100%"), property("align-items", "center"), property("gap", "8px"), property("min-height", "32px")], Nil{}, [input, Doc.Text{name}]}


def checked_property(value: Bool) -> +List<Doc.Property>:
  match value:
    case True{}: [property("checked", "")]
    case False{}: Nil{}


def measured_input_present(present: Bool, metrics: Maybe<&2, Design.InputMetrics>) -> +List<Doc.Property>:
  match present metrics:
    case True{} Some{Design.InputMetrics{minimum, maximum, line_height, inline, gap, footer}}: [property("min-height", px(minimum)), property("max-height", px(maximum)), property("padding-inline", px(inline))]
    case _ _: Nil{}


def board_columns(values: +List<Doc.Node>, +width: Nat) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: replace_styles(value, [property("width", px(width)), property("min-width", px(width)), property("flex", "0 0 auto"), property("height", "100%"), property("max-height", "100%"), property("min-height", "0"), property("align-self", "stretch")]) <> board_columns(rest, width)

def board_group_name(value: UI.BoardGrouping) -> String:
  match value:
    case UI.ViewChoices{}: "view-choices"
    case UI.SearchArea{}: "search"
    case UI.WorkStatus{}: "work-status"
    case UI.SecondaryActions{}: "secondary-actions"
    case UI.PrimaryAction{}: "primary-action"

def board_group_label(value: UI.BoardGrouping) -> String:
  match value:
    case UI.ViewChoices{}: "看板视图"
    case UI.SearchArea{}: "任务搜索"
    case UI.WorkStatus{}: "当前工作状态"
    case UI.SecondaryActions{}: "看板筛选和设置"
    case UI.PrimaryAction{}: "主要操作"

def board_group_styles(value: UI.BoardGrouping, +typography: T.Presentation) -> +List<Doc.Property>:
  match value:
    case UI.ViewChoices{}:
      [property("display", "flex"), property("align-items", "center"), property("gap", "4px"), property("min-width", "0"), property("flex", "0 0 auto")]
    case UI.SearchArea{}:
      [property("display", "flex"), property("align-items", "center"), property("min-width", "0"), property("flex", "0 1 168px")]
    case UI.WorkStatus{}:
      List.append(&2, Doc.Property, part_text(typography, T.Body{}, T.Medium{}), [property("display", "flex"), property("align-items", "center"), property("min-width", "0"), property("color", "var(--color-token-text-secondary)"), property("white-space", "nowrap")])
    case UI.SecondaryActions{}:
      [property("display", "flex"), property("align-items", "center"), property("gap", "4px"), property("min-width", "0"), property("flex", "0 0 auto"), property("margin-inline-start", "auto")]
    case UI.PrimaryAction{}:
      [property("display", "flex"), property("align-items", "center"), property("min-width", "0"), property("flex", "0 0 auto")]

def board_group_node(+key: String, +grouping: UI.BoardGrouping, children: +List<Doc.Node>, +typography: T.Presentation) -> Doc.Node:
  Doc.Element{key, "div", [property("data-native-key", key), property("data-board-group", board_group_name(grouping)),
    property("role", "group"), property("aria-label", board_group_label(grouping))], board_group_styles(grouping, typography), Nil{}, children}

def stage_surface_tone(stage: Board.Stage) -> Surfaces.Tone:
  match stage:
    case Board.InProgress{}: Surfaces.Warning{}
    case Board.InReview{}: Surfaces.Success{}
    case Board.Completed{}: Surfaces.Info{}
    case Board.Blocked{}: Surfaces.Danger{}
    case _: Surfaces.Neutral{}

def stage_tone(stage: Board.Stage) -> String:
  surface_color(Surfaces.tone(stage_surface_tone(stage)))

def stage_surface(stage: Board.Stage) -> String:
  surface_background(Surfaces.Lane{stage_surface_tone(stage)}, Surfaces.Rest{})

def board_lane_styles(stage: Board.Stage) -> +List<Doc.Property>:
  List.append(&2, Doc.Property, [property("display", "flex"), property("flex-direction", "column"), property("gap", "8px"),
   property("min-height", "0"), property("overflow", "hidden"),
   property("border-radius", "12px"),
   property("background", stage_surface(stage)), property("box-sizing", "border-box")], content_area_properties(Enclosure.area(Enclosure.Lane{})))

def lane_mark(+owner: String, +stage: Board.Stage) -> Doc.Node:
  Doc.Element{generated_identity(owner, "stage-mark"), "span", [property("data-board-stage-mark", Board.stage_name(stage)), property("aria-hidden", "true")],
    [property("width", "8px"), property("height", "8px"), property("flex", "0 0 8px"), property("border-radius", "50%"), property("background", stage_tone(stage))], Nil{}, Nil{}}

def lane_count(+owner: String, +count: Nat, +typography: T.Presentation) -> Doc.Node:
  Doc.Element{generated_identity(owner, "count"), "span", [property("data-board-count", Nat.show(count)), property("aria-label", Nat.show(count) ++ " 个任务")],
    List.append(&2, Doc.Property, part_text(typography, T.Support{}, T.Regular{}), [property("color", "var(--color-token-text-secondary)"), property("font-variant-numeric", "tabular-nums"), property("margin-inline-start", "2px")]), Nil{}, [Doc.Text{Nat.show(count)}]}

def lane_heading_leading(+owner: String, label: String, stage: Board.Stage, count: Nat, +typography: T.Presentation) -> Doc.Node:
  Doc.Element{generated_identity(owner, "heading-leading"), "div", Nil{},
    [property("display", "flex"), property("align-items", "center"), property("gap", "7px"), property("min-width", "0")], Nil{},
    [lane_mark(owner, stage),
      Doc.Element{generated_identity(owner, "title"), "h2", Nil{},
        List.append(&2, Doc.Property, part_text(typography, T.Support{}, T.Medium{}), [property("margin", "0"), property("min-width", "0"), property("overflow", "hidden"), property("text-overflow", "ellipsis"), property("white-space", "nowrap")]), Nil{}, [Doc.Text{label}]},
      lane_count(owner, count, typography)]}

def lane_heading_trailing(+owner: String, create: +List<Doc.Node>) -> Doc.Node:
  Doc.Element{generated_identity(owner, "heading-trailing"), "div", Nil{},
    [property("display", "flex"), property("align-items", "center"), property("margin-inline-start", "auto"), property("flex", "0 0 auto")], Nil{}, create}

def lane_heading_node(+owner: String, label: String, stage: Board.Stage, count: Nat,
  +create: +List<Doc.Node>, +typography: T.Presentation) -> Doc.Node:
  Doc.Element{generated_identity(owner, "heading"), "header", [property("data-board-lane-heading", "")],
    [property("display", "flex"), property("align-items", "center"), property("gap", "7px"), property("min-height", "36px"),
     property("padding", "0 2px 8px"), property("flex", "none")], Nil{},
    [lane_heading_leading(owner, label, stage, count, typography), lane_heading_trailing(owner, create)]}

def same_stage(left: Board.Stage, right: Board.Stage) -> Bool:
  String.eq(Board.stage_name(left), Board.stage_name(right))

def lane_create_matches(stage: Board.Stage, meaning: UI.Meaning) -> Bool:
  match meaning:
    case UI.ComposerAction{composer_subject, Core.ApplicationInput{Experience.UserInput{User.Activate{User.NewCard{requested}}}}, availability}:
      same_stage(stage, requested)
    case UI.Activate{Core.ApplicationInput{Experience.UserInput{User.Activate{User.NewCard{requested}}}}, availability}:
      same_stage(stage, requested)
    case _: False{}

def lane_prepared_child(selected: Bool, belongs: Bool, +node: Doc.Node, +tail: +List<Doc.Node>) -> +List<Doc.Node>:
  match selected belongs:
    case True{} True{}: node <> tail
    case False{} False{}: node <> tail
    case _ _: tail

def lane_children(+selected: Bool, +stage: Board.Stage, source: +List<Child>) -> +List<Doc.Node>:
  match source:
    case Nil{}: Nil{}
    case Con{Child{Design.Node{key, semantic, label, role, meaning, visual, representation, children}, document}, rest}:
      lane_prepared_child(selected, lane_create_matches(stage, meaning), document, lane_children(selected, stage, rest))


def empty_lane_when(is_empty: Bool, +owner: String, +typography: T.Presentation) -> +List<Doc.Node>:
  match is_empty:
    case True{}: [Doc.Element{generated_identity(owner, "empty"), "p", [property("data-board-empty", "")],
      List.append(&2, Doc.Property, part_text(typography, T.Support{}, T.Regular{}), [property("margin", "4px 2px"), property("color", "var(--color-token-text-secondary)"), property("text-align", "center")]), Nil{}, [Doc.Text{"暂无任务"}]}]
    case False{}: Nil{}

def empty_lane(count: Nat, owner: String, +typography: T.Presentation) -> +List<Doc.Node>:
  empty_lane_when(Nat.is_eq(count, 0n), owner, typography)

def board_lane_node(+key: String, +label: String, +stage: Board.Stage, +count: Nat,
  +source: +List<Child>, +typography: T.Presentation) -> Doc.Node:
  +create = lane_children(True{}, stage, source)
  +cards = lane_children(False{}, stage, source)
  Doc.Element{key, "section", [property("data-native-key", key), property("data-board-stage", Board.stage_name(stage)),
    property("data-board-count", Nat.show(count)), property("aria-label", label)], board_lane_styles(stage),
    [Doc.DropCard{key}], List.append(&2, Doc.Node, [lane_heading_node(key, label, stage, count, create, typography)],
    [Doc.Element{generated_identity(key, "cards"), "div", [property("data-board-cards", "")],
      [property("display", "flex"), property("flex", "1"), property("flex-direction", "column"), property("gap", px(Enclosure.separation(Enclosure.Cards{}))),
       property("min-height", "0"), property("overflow-x", "hidden"), property("overflow-y", "auto"),
       property("overscroll-behavior", "contain"), property("padding", "4px 2px 6px")], Nil{},
      List.append(&2, Doc.Node, empty_lane(count, key, typography), cards)}])}

def card_chip(key: String, kind: String, text: String, +tone: Surfaces.Tone, +typography: T.Presentation) -> Doc.Node:
  Doc.Element{key, "span", [property("data-card-chip", kind)],
    List.append(&2, Doc.Property, part_text(typography, T.Support{}, T.Medium{}), [property("display", "inline-flex"), property("align-items", "center"), property("max-width", "100%"),
     property("padding", "2px 6px"), property("border-radius", "4px"), property("background", surface_background(Surfaces.Chip{tone}, Surfaces.Rest{})),
     property("color", surface_color(Surfaces.tone(tone))), property("white-space", "nowrap"),
     property("overflow", "hidden"), property("text-overflow", "ellipsis")]), Nil{}, [Doc.Text{text}]}

def priority_tone(priority: Board.Priority) -> Surfaces.Tone:
  match priority:
    case Board.Urgent{}: Surfaces.Danger{}
    case Board.High{}: Surfaces.Warning{}
    case _: Surfaces.Neutral{}

def card_pin_chip(found: Bool, owner: String, +typography: T.Presentation) -> +List<Doc.Node>:
  match found:
    case True{}: [card_chip(generated_identity(owner, "pin"), "pin", "已置顶", Surfaces.Warning{}, typography)]
    case False{}: Nil{}

def card_status_chip_when(empty: Bool, +status: String, +owner: String, +typography: T.Presentation) -> +List<Doc.Node>:
  match empty:
    case True{}: Nil{}
    case False{}: [card_chip(generated_identity(owner, "status"), "status", status, Surfaces.Neutral{}, typography)]

def card_metadata(+card_key: String, face: View.CardFace, status_empty: Bool, +typography: T.Presentation) -> Doc.Node:
  View.CardFace{id, title, description, +priority, pinned, status, project, labels, owner, updated} = face
  Doc.Element{generated_identity(card_key, "metadata"), "div", [property("data-card-metadata", "")],
    List.append(&2, Doc.Property, part_text(typography, T.Support{}, T.Regular{}), [property("display", "flex"), property("align-items", "center"), property("flex-wrap", "wrap"), property("gap", "5px"),
     property("min-width", "0"), property("color", "var(--color-token-text-secondary)")]), Nil{},
    List.append(&2, Doc.Node,
      [card_chip(generated_identity(card_key, "reference"), "reference", "SV-" ++ Nat.show(id), Surfaces.Neutral{}, typography),
       card_chip(generated_identity(card_key, "priority"), "priority", Board.priority_label(priority), priority_tone(priority), typography)],
      List.append(&2, Doc.Node, card_pin_chip(pinned, card_key, typography), card_status_chip_when(status_empty, status, card_key, typography)))}

def card_more_action(meaning: UI.Meaning) -> Bool:
  match meaning:
    case UI.ComposerAction{composer_subject, Core.ApplicationInput{Experience.UserInput{User.Activate{User.OpenPanel{User.ObjectActions{subject}, trigger}}}}, availability}: True{}
    case UI.Activate{Core.ApplicationInput{Experience.UserInput{User.Activate{User.OpenPanel{User.ObjectActions{subject}, trigger}}}}, availability}: True{}
    case _: False{}

def card_action_selected(+want_more: Bool, meaning: UI.Meaning) -> Bool:
  match want_more:
    case True{}: card_more_action(meaning)
    case False{}: Bool.not(card_more_action(meaning))

def card_title_styles(+typography: T.Presentation) -> +List<Doc.Property>:
  List.append(&2, Doc.Property,
    List.append(&2, Doc.Property, part_text(typography, T.Body{}, T.Strong{}), [property("width", "100%"), property("min-width", "0"), property("display", "block"),
     property("text-align", "start"), property("white-space", "normal"),
     property("overflow-wrap", "anywhere"), property("min-height", "32px")]), content_area_properties(Enclosure.area(Enclosure.TextControl{})))

def card_title_control(+title: String, node: Doc.Node, +typography: T.Presentation) -> Doc.Node:
  match node:
    case Doc.Element{key, "button", attrs, styles, events, children}:
      Doc.Element{key, "button", attrs,
        List.append(&2, Doc.Property, styles, card_title_styles(typography)), events, [Doc.Text{title}]}
    case other: other

def card_prepared_action(include: Bool, node: Doc.Node, +tail: +List<Doc.Node>) -> +List<Doc.Node>:
  match include:
    case True{}: node <> tail
    case False{}: tail

def card_action_nodes(+want_more: Bool, source: +List<Child>) -> +List<Doc.Node>:
  match source:
    case Nil{}: Nil{}
    case Con{Child{Design.Node{key, semantic, label, role, meaning, visual, representation, children}, document}, rest}:
      card_prepared_action(card_action_selected(want_more, meaning), document, card_action_nodes(want_more, rest))


def card_title_actions(+title: String, actions: +List<Doc.Node>, +typography: T.Presentation) -> +List<Doc.Node>:
  match actions:
    case Nil{}: Nil{}
    case Con{node, rest}: card_title_control(title, node, typography) <> card_title_actions(title, rest, typography)

def card_title_nodes(owner: String, +title: String, +actions: +List<Doc.Node>, +typography: T.Presentation) -> +List<Doc.Node>:
  match actions:
    case Nil{}:
      [Doc.Element{generated_identity(owner, "title"), "h3", [property("data-card-title", "")],
        List.append(&2, Doc.Property, part_text(typography, T.Body{}, T.Strong{}), [property("margin", "0"), property("overflow-wrap", "anywhere")]), Nil{}, [Doc.Text{title}]}]
    case _:
      [Doc.Element{generated_identity(owner, "open-actions"), "div", [property("data-card-open", "")],
        [property("flex", "1"), property("min-width", "0"), property("display", "flex"), property("align-items", "center")], Nil{}, card_title_actions(title, actions, typography)}]

def card_more_nodes(owner: String, +actions: +List<Doc.Node>) -> +List<Doc.Node>:
  match actions:
    case Nil{}: Nil{}
    case _:
      [Doc.Element{generated_identity(owner, "more-actions"), "div", [property("data-card-more", "")],
        [property("display", "flex"), property("align-items", "center"), property("flex", "0 0 auto")], Nil{}, actions}]

def card_action_row(+owner: String, title: String, +open: +List<Doc.Node>, +more: +List<Doc.Node>, +typography: T.Presentation) -> Doc.Node:
  Doc.Element{generated_identity(owner, "actions"), "div", [property("data-card-actions", "")],
    [property("display", "flex"), property("align-items", "center"), property("gap", px(Enclosure.separation(Enclosure.InlineControls{}))), property("min-width", "0")], Nil{},
    List.append(&2, Doc.Node, card_title_nodes(owner, title, open, typography), card_more_nodes(owner, more))}

def card_description_when(empty: Bool, owner: String, +description: String, +typography: T.Presentation) -> +List<Doc.Node>:
  match empty:
    case True{}: Nil{}
    case False{}:
      [Doc.Element{generated_identity(owner, "description"), "p", [property("data-card-description", "")],
        List.append(&2, Doc.Property, part_text(typography, T.Support{}, T.Regular{}), [property("display", "-webkit-box"), property("-webkit-box-orient", "vertical"), property("-webkit-line-clamp", "3"),
         property("margin", "0"), property("overflow", "hidden"), property("color", "var(--color-token-text-secondary)"),
         property("white-space", "pre-wrap"), property("overflow-wrap", "anywhere")]), Nil{}, [Doc.Text{description}]}]

def card_description(+owner: String, +description: String, +typography: T.Presentation) -> +List<Doc.Node>:
  card_description_when(String.is_empty(description), owner, description, typography)

def card_label_nodes(+owner: String, +values: +List<String>, +index: Nat, +typography: T.Presentation) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      card_chip(generated_identity(owner, "label/" ++ Nat.show(index)), "label", value, Surfaces.Neutral{}, typography) <>
      card_label_nodes(owner, rest, Nat.add(index, 1n), typography)

def card_project_nodes_when(empty: Bool, +owner: String, +project: String, +typography: T.Presentation) -> +List<Doc.Node>:
  match empty:
    case True{}: Nil{}
    case False{}: [card_chip(generated_identity(owner, "project"), "project", project, Surfaces.Neutral{}, typography)]

def card_project_nodes(+owner: String, +project: String, +typography: T.Presentation) -> +List<Doc.Node>:
  card_project_nodes_when(String.is_empty(project), owner, project, typography)

def card_context_with_chips(+owner: String, chips: +List<Doc.Node>) -> +List<Doc.Node>:
  match chips:
    case Nil{}: Nil{}
    case _:
      [Doc.Element{generated_identity(owner, "context"), "div", [property("data-card-context", "")],
        [property("display", "flex"), property("flex-wrap", "wrap"), property("gap", "4px"), property("min-width", "0")], Nil{}, chips}]

def card_context_nodes(+owner: String, project: String, +labels: +List<String>, +typography: T.Presentation) -> +List<Doc.Node>:
  card_context_with_chips(owner, List.append(&2, Doc.Node, card_project_nodes(owner, project, typography), card_label_nodes(owner, labels, 0n, typography)))

def card_footer_item_when(empty: Bool, owner: String, part: String, kind: String, +value: String) -> +List<Doc.Node>:
  match empty:
    case True{}: Nil{}
    case False{}:
      [Doc.Element{generated_identity(owner, part), "span", [property("data-card-footer", kind)],
        [property("min-width", "0"), property("overflow", "hidden"), property("text-overflow", "ellipsis"), property("white-space", "nowrap")], Nil{}, [Doc.Text{value}]}]

def card_footer_item(owner: String, part: String, kind: String, +value: String) -> +List<Doc.Node>:
  card_footer_item_when(String.is_empty(value), owner, part, kind, value)

def card_footer_with_items(+card_key: String, items: +List<Doc.Node>, +typography: T.Presentation) -> +List<Doc.Node>:
  match items:
    case Nil{}: Nil{}
    case _:
      [Doc.Element{generated_identity(card_key, "footer"), "footer", [property("data-card-footer", "")],
        List.append(&2, Doc.Property, part_text(typography, T.Support{}, T.Regular{}), [property("display", "flex"), property("align-items", "center"), property("justify-content", "space-between"),
         property("gap", "8px"), property("margin-top", "2px"), property("color", "var(--color-token-text-secondary)"),
         property("min-width", "0")]), Nil{}, items}]

def card_timestamp_styles() -> +List<Doc.Property>:
  [property("flex", "none")]

def card_timestamp_items(items: +List<Doc.Node>) -> +List<Doc.Node>:
  match items:
    case Nil{}: Nil{}
    case Con{node, rest}: replace_styles(node, card_timestamp_styles()) <> card_timestamp_items(rest)

def card_footer(+card_key: String, face: View.CardFace, +typography: T.Presentation) -> +List<Doc.Node>:
  View.CardFace{id, title, description, priority, pinned, status, project, labels, card_owner, updated} = face
  card_footer_with_items(card_key, List.append(&2, Doc.Node,
    card_footer_item(card_key, "owner", "owner", card_owner),
    card_timestamp_items(card_footer_item(card_key, "updated", "updated", updated))), typography)

def card_children(+card_key: String, +face: View.CardFace, +source: +List<Child>, +typography: T.Presentation) -> +List<Doc.Node>:
  View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated} = face
  +open = card_action_nodes(False{}, source)
  +more = card_action_nodes(True{}, source)
  List.append(&2, Doc.Node, [card_metadata(card_key, face, String.is_empty(status), typography), card_action_row(card_key, title, open, more, typography)],
    List.append(&2, Doc.Node, card_description(card_key, description, typography),
      List.append(&2, Doc.Node, card_context_nodes(card_key, project, labels, typography), card_footer(card_key, face, typography))))

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
    case UI.Edit{editor, field, entry, observed_value, choices}: [property("data-field", Forms.key(field))]
    case _: Nil{}


def opened(value: Bool) -> +List<Doc.Property>:
  match value:
    case True{}: [property("open", "")]
    case False{}: Nil{}


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
    case Design.SurfaceFeedback{Design.PhasePaint{hfg, hbg}, Design.PhasePaint{pfg, pbg}}:
      [property("--native-hover-background", paint(hbg)), property("--native-hover-color", paint(hfg)), property("--native-pressed-background", paint(pbg)), property("--native-pressed-color", paint(pfg))]
    case Design.Interactive{Design.PhasePaint{hfg, hbg}, Design.PhasePaint{pfg, pbg}, opacity, ring, width, offset}:
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
       property("transform", "translate(-50%, -50%)"), property("width", px(Nat.min(width, maximum))), property("max-height", px(height)), property("overflow", "hidden")]
    case Design.AnchoredPopover{anchor, available, maximum_width, maximum_height, gap}:
      Design.Box{left, top, +width, +height} = available
      [property("position", "fixed"), property("position-anchor", css_anchor(anchor)), property("position-area", "bottom span-left"), property("position-try-fallbacks", "flip-block, flip-inline, flip-block flip-inline"), property("position-try-order", "most-block-size"), property("align-self", "normal"), property("height", "max-content"), property("margin", px(gap)), property("max-width", px(Nat.min(width, maximum_width))),
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
    case Forms.WorkspaceDirectories{}: FieldOptions.workspace_text(workspace)
    case Forms.WorkspacePrimary{}: workspace_primary(workspace)
    case Forms.SandboxMode{}: FieldOptions.sandbox_text(sandbox)
    case Forms.NetworkAccess{}: network_text(sandbox)
    case Forms.ApprovalPolicy{}: approval_text(approval)
    case _: ""


def task_details(+owner: String, value: View.TaskDetails) -> +List<Doc.Node>:
  View.TaskDetails{Context.EffectiveContext{task, Domain.TaskContext{Domain.Workspace{roots, primary}, Domain.Sandbox{mode, network}, approval, project}, guidance, access}, Domain.Model{Domain.Profile{id, provider, name, policy}, reasoning, model_guidance}, tools, lineage, queued, status, phase} = value
  [Doc.Element{generated_identity(owner, "facts"), "div", Nil{}, fact_frame_styles(Design.facts_frame()), Nil{},
  [fact(generated_identity(owner, "workspace"), "Working directories", FieldOptions.joined(roots)), fact(generated_identity(owner, "primary"), "Primary directory", FieldOptions.optional_text(primary)),
   fact(generated_identity(owner, "sandbox"), "Filesystem access", Domain.sandbox_mode_name(mode)), fact(generated_identity(owner, "network"), "Network access", FieldOptions.boolean(network)),
   fact(generated_identity(owner, "approval"), "Approval policy", Domain.approval_name(approval)), fact(generated_identity(owner, "model"), "Model", name), fact(generated_identity(owner, "reasoning"), "Reasoning", reasoning),
   fact(generated_identity(owner, "messages"), "Queued messages", FieldOptions.joined(queued))]}]


def field_hint(value: UI.Meaning) -> +List<Doc.Property>:
  match value:
    case UI.BoardSearch{filter}: [property("placeholder", "搜索任务")]
    case UI.Edit{editor, Forms.CardLabels{}, entry, observed, choices}: [property("placeholder", "每行一个标签")]
    case _: Nil{}

def checked_properties(value: UI.Meaning) -> +List<Doc.Property>:
  match value:
    case UI.Edit{editor, field, entry, Forms.ToggleValue{enabled}, choices}: checked_property(enabled)
    case UI.Edit{editor, Forms.AssistedCapture{}, entry, Forms.AssistanceValue{enabled, profile}, choices}: checked_property(enabled)
    case UI.Edit{editor, Forms.NetworkAccess{}, entry, Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, Context.InheritedSandbox{Domain.Sandbox{mode, enabled}}, approval, guidance}}, choices}: checked_property(enabled)
    case UI.Edit{editor, Forms.NetworkAccess{}, entry, Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, Context.ChosenSandbox{Domain.Sandbox{mode, enabled}}, approval, guidance}}, choices}: checked_property(enabled)
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


def audit_text(value: Domain.Message) -> String:
  Conversation.audit_detail(value)

def style_details(shadow: Bool, alignment: Design.Alignment, states: Design.ControlStates) -> +List<Doc.Property>:
  List.append(&2, Doc.Property, shadow_style(shadow), List.append(&2, Doc.Property, alignment_style(alignment), states_style(states)))


def region_children(owner: String, role: UI.Role, label: String, children: +List<Doc.Node>, +typography: T.Presentation) -> +List<Doc.Node>:
  match role:
    case UI.Activity{}: activity_summary(owner, label, children)
    case other: List.append(&2, Doc.Node, region_label(owner, other, label, typography), children)

def style_rest(value: Design.Style) -> +List<Doc.Property>:
  Design.Style{+typography, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, direction, overflow, +content_frame, minimum, maximum, states} = value
  List.append(&2, Doc.Property, rich_properties(typography),
    List.append(&2, Doc.Property,
    [property("color", paint(foreground)), property("background", paint(background)),
     property("border-color", paint(border)), property("border-width", px(border_width)), property("border-style", "solid"),
     property("border-radius", px(radius)), property("padding-inline", px(Enclosure.inline(Enclosure.frame_content(content_frame)))), property("padding-block", px(Enclosure.block(Enclosure.frame_content(content_frame)))),
     property("gap", px(Enclosure.frame_gap(content_frame))), property("min-height", px(minimum)), property("max-width", Nat.show(maximum) ++ "%"),
     property("box-sizing", "border-box"), property("min-width", "0")],
    List.append(&2, Doc.Property, flow(direction), List.append(&2, Doc.Property, overflow_style(overflow), style_details(shadow, alignment, states)))))

def style(+value: Design.Style) -> +List<Doc.Property>:
  List.append(&2, Doc.Property, style_rest(value), text_presentation(Appearance.style_text(value)))

def dialog_partition_child_by_header(+child: Doc.Node, is_header: Bool,
  +header: +List<Doc.Node>, +body: +List<Doc.Node>, +layouts: +List<EditorLayout.SectionKind>,
  kind: EditorLayout.SectionKind) -> DialogParts:
  match is_header:
    case True{}: DialogParts{child <> header, body, layouts}
    case False{}: DialogParts{header, child <> body, kind <> layouts}

def persistent_details_header(representation: Controls.Representation) -> Bool:
  match representation:
    case Controls.Action{Core.ApplicationInput{Experience.UserInput{User.Activate{User.TogglePanel{User.TaskDetails{task}, trigger}}}},
      availability, name, face, Controls.Disclosure{True{}}, geometry, placement, help, feedback}: True{}
    case _: False{}

def dialog_partition_child(+appearance: Child,
  +header: +List<Doc.Node>, +body: +List<Doc.Node>, +layouts: +List<EditorLayout.SectionKind>) -> DialogParts:
  Child{+source, document} = appearance
  Design.Node{identity, semantic, label, role, meaning, visual, representation, children} = source
  dialog_partition_child_by_header(document, Controls.panel_header(representation) || persistent_details_header(representation), header, body, layouts,
    EditorLayout.appearance_kind(source))

def dialog_partition_prepend(appearance: Child,
  parts: DialogParts) -> DialogParts:
  DialogParts{+header, +body, +layouts} = parts
  dialog_partition_child(appearance, header, body, layouts)

def dialog_partition(children: +List<Child>) -> DialogParts:
  match children:
    case Nil{}: DialogParts{Nil{}, Nil{}, Nil{}}
    case Con{child, rest}: dialog_partition_prepend(child, dialog_partition(rest))

def dialog_header_projection(parts: DialogParts) -> +List<Doc.Node>:
  DialogParts{+header, +body, layouts} = parts
  header

def dialog_body_projection(parts: DialogParts) -> +List<Doc.Node>:
  DialogParts{+header, +body, layouts} = parts
  body

def dialog_header_children(children: +List<Child>) -> +List<Doc.Node>:
  dialog_header_projection(dialog_partition(children))

def dialog_body_children(children: +List<Child>) -> +List<Doc.Node>:
  dialog_body_projection(dialog_partition(children))

def dialog_header_styles() -> +List<Doc.Property>:
  List.append(&2, Doc.Property,
    [property("display", "flex"), property("flex", "0 0 auto"), property("align-items", "center"), property("gap", "12px"),
     property("border-bottom", "1px solid var(--color-token-border-default)")], content_area_properties(Enclosure.partition(Enclosure.Header{})))

def dialog_header_title(+owner: String, +label: String, +typography: T.Presentation) -> Doc.Node:
  Doc.Element{generated_identity(owner, "title"), "h2", Nil{},
    List.append(&2, Doc.Property, part_text(typography, T.Body{}, T.Medium{}), [property("margin", "0"),
     property("min-width", "0"), property("flex", "1"), property("overflow-wrap", "anywhere")]), Nil{}, [Doc.Text{label}]}

def dialog_body_styles() -> +List<Doc.Property>:
  List.append(&2, Doc.Property,
    [property("display", "flex"), property("flex-direction", "column"), property("flex", "1 1 auto"),
     property("min-height", "0"), property("overflow", "auto")], content_area_properties(Enclosure.partition(Enclosure.Body{})))

def dialog_content_styles() -> +List<Doc.Property>:
  [property("display", "flex"), property("flex-direction", "column"),
   property("flex", "0 0 auto"), property("gap", px(Enclosure.separation(Enclosure.DialogSections{})))]

def dialog_footer_styles() -> +List<Doc.Property>:
  List.append(&2, Doc.Property,
    [property("display", "flex"), property("flex-wrap", "wrap"), property("align-items", "center"),
     property("flex", "0 0 auto"), property("gap", px(Enclosure.separation(Enclosure.DialogActions{}))), property("border-top", "1px solid var(--color-token-border-default)")],
    content_area_properties(Enclosure.partition(Enclosure.Footer{})))

def dialog_footer_items(owner: String, values: +List<Doc.Node>) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{+submit, Nil{}}:
      [Doc.Element{generated_identity(owner, "dialog-submit"), "div", Nil{},
        [property("flex", "0 0 auto"), property("margin-left", "auto")], Nil{}, [submit]}]
    case Con{+option, rest}: option <> dialog_footer_items(owner, rest)

def dialog_footer(+owner: String, values: +List<Doc.Node>) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{first, rest}:
      [Doc.Element{generated_identity(owner, "dialog-footer"), "footer", Nil{}, dialog_footer_styles(), Nil{},
        dialog_footer_items(owner, first <> rest)}]

def dialog_region_suffix(+key: String, +label: String, visual: Design.Style,
  +header: +List<Doc.Node>, suffix: EditorLayout.Suffix, +typography: T.Presentation) -> Doc.Node:
  EditorLayout.Suffix{+body, +footer} = suffix
  +header_node: Doc.Node = Doc.Element{generated_identity(key, "dialog-header"), "header", Nil{},
    dialog_header_styles(), Nil{}, List.append(&2, Doc.Node, [dialog_header_title(key, label, typography)], header)}
  +content_node: Doc.Node = Doc.Element{generated_identity(key, "dialog-content"), "div", Nil{}, dialog_content_styles(), Nil{}, body}
  +body_node: Doc.Node = Doc.Element{generated_identity(key, "dialog-body"), "div", Nil{}, dialog_body_styles(), Nil{}, [content_node]}
  Doc.Element{key, "section", [property("aria-label", label), property("data-native-key", key)],
    List.append(&2, Doc.Property, style(visual), [property("overflow", "hidden")]), Nil{},
    List.append(&2, Doc.Node, [header_node, body_node], dialog_footer(key, footer))}

def dialog_region_parts(+key: String, +label: String, visual: Design.Style,
  parts: DialogParts, +typography: T.Presentation) -> Doc.Node:
  DialogParts{+header, +body, layouts} = parts
  dialog_region_suffix(key, label, visual, header, EditorLayout.split(body, layouts), typography)

def dialog_region(+key: String, +label: String, visual: Design.Style,
  children: +List<Child>, +typography: T.Presentation) -> Doc.Node:
  dialog_region_parts(key, label, visual, dialog_partition(children), typography)

def editor_section(+key: String, +label: String, visual: Design.Style,
  +children: +List<Doc.Node>, kind: EditorLayout.SectionKind, +typography: T.Presentation) -> Doc.Node:
  match kind:
    case EditorLayout.WorkSection{}: Doc.Element{key, "section", [property("aria-label", label), property("data-native-key", key)], style(visual), Nil{}, children}
    case EditorLayout.MetadataSection{}:
      Doc.Element{key, "section", [property("aria-label", label), property("data-native-key", key)], List.append(&2, Doc.Property, style(visual),
        [property("flex-direction", "row"), property("flex-wrap", "wrap"), property("gap", "12px")]), Nil{}, children}
    case EditorLayout.CaptureSection{}:
      Doc.Element{key, "section", [property("aria-label", label), property("data-native-key", key)], List.append(&2, Doc.Property, style(visual),
        [property("flex-direction", "row"), property("flex-wrap", "wrap"), property("gap", "12px"),
         property("flex", "1 1 0"), property("min-width", "0")]), Nil{}, children}
    case _: Doc.Element{key, "section", [property("aria-label", label), property("data-native-key", key)], style(visual), Nil{}, region_children(key, UI.Section{}, label, children, typography)}

def region_node(+key: String, +label: String, role: UI.Role, visual: Design.Style,
  +children: +List<Child>, +typography: T.Presentation) -> Doc.Node:
  match role:
    case UI.Dialog{}: dialog_region(key, label, visual, children, typography)
    case UI.Section{}: editor_section(key, label, visual, documents(children), EditorLayout.section_kind(sources(children)), typography)
    case +other: Doc.Element{key, tag(other), [property("aria-label", label), property("data-native-key", key)],
      style(visual), Nil{}, region_children(key, other, label, documents(children), typography)}


def layer_region_properties(+key: String, outside: Bool, value: Doc.Node) -> Doc.Node:
  match value:
    case Doc.Element{identity, tag, attrs, styles, events, children}:
      Doc.Element{identity, tag, List.append(&2, Doc.Property, attrs,
        [property("data-layer-key", key), property("data-layer-outside", FieldOptions.boolean(outside)), property("tabindex", "-1")]), styles, events, children}
    case other: other

def layer_region_node(+key: String, label: String, role: UI.Role, +outside: Bool, visual: Design.Style,
  children: +List<Child>, +typography: T.Presentation) -> Doc.Node:
  layer_region_properties(key, outside, region_node(key, label, role, visual, children, typography))

def face_label(+key: String, text: String) -> Doc.Node:
  Doc.Element{key ++ "/label", "span", Nil{},
    [property("min-width", "0"), property("overflow-wrap", "anywhere")], Nil{}, [Doc.Text{text}]}

def selected_check(+key: String, checked: Bool) -> +List<Doc.Node>:
  match checked:
    case True{}: [icon(key ++ "/check", Controls.Check{})]
    case False{}: Nil{}

def choice_mark(+key: String, checked: Bool, extent: Nat, icon_extent: Nat) -> Doc.Node:
  Doc.Element{key ++ "/check-slot", "span", [property("aria-hidden", "true")],
    [property("width", px(extent)), property("height", px(icon_extent)), property("flex-shrink", "0"), property("display", "inline-flex"), property("align-items", "center"), property("justify-content", "center")], Nil{}, selected_check(key, checked)}

def check_slot(+key: String, checked: Bool) -> Doc.Node:
  Doc.Element{key ++ "/check-slot", "span", [property("aria-hidden", "true")],
    [property("width", "var(--native-leading-slot,20px)"), property("height", "var(--native-icon-size,16px)"), property("flex-shrink", "0"), property("display", "inline-flex"), property("align-items", "center"), property("justify-content", "center")], Nil{}, selected_check(key, checked)}

def disclosure_icon(expanded: Bool) -> Controls.Icon:
  match expanded:
    case True{}: Controls.ChevronDown{}
    case False{}: Controls.ChevronRight{}

def choice_text_content(+key: String, label: String, description: Maybe<&2, String>, text_gap: Nat, +typography: T.Presentation) -> Doc.Node:
  match description:
    case None{}:
      Doc.Element{key ++ "/content", "span", Nil{}, [property("display", "flex"), property("flex-direction", "column"), property("flex", "1 1 0"), property("min-width", "0"), property("text-align", "start")], Nil{}, [Doc.Text{label}]}
    case Some{description}:
      Doc.Element{key ++ "/content", "span", Nil{}, [property("display", "flex"), property("flex-direction", "column"), property("flex", "1 1 0"), property("min-width", "0"), property("text-align", "start"), property("gap", px(text_gap))], Nil{},
        [Doc.Text{label}, Doc.Element{key ++ "/description", "span", Nil{},
          List.append(&2, Doc.Property, part_text(typography, T.Support{}, T.Regular{}), [property("color", "var(--color-token-text-secondary)"), property("white-space", "normal")]), Nil{}, [Doc.Text{description}]}]}

def choice_content_layout(+key: String, label: String, description: Maybe<&2, String>, selected: Bool, layout: Controls.ChoiceContentLayout, +typography: T.Presentation) -> +List<Doc.Node>:
  Controls.ChoiceContentLayout{text_gap, mark_extent, mark_icon_extent} = layout
  [choice_text_content(key, label, description, text_gap, typography), choice_mark(key, selected, mark_extent, mark_icon_extent)]

def face(+key: String, value: Controls.Face, +typography: T.Presentation, geometry: Controls.Geometry) -> +List<Doc.Node>:
  match value:
    case Controls.IconFace{value}: [icon(key, value)]
    case Controls.TextFace{text}: [face_label(key, text)]
    case Controls.SingleLineFace{text}: [Doc.Text{text}]
    case Controls.IconTextFace{value, text}: [icon(key ++ "/leading", value), face_label(key, text)]
    case Controls.PickerFace{leading, text}: List.append(&2, Doc.Node, optional_icon(key ++ "/leading", leading), [face_label(key, text), icon(key ++ "/disclosure", Controls.ChevronDown{})])
    case Controls.ChoiceFace{text, description, checked}: choice_content_layout(key, text, description, checked, Controls.choice_content_layout(geometry), typography)
    case Controls.DisclosureFace{text, expanded}: [icon(key ++ "/disclosure", disclosure_icon(expanded)), face_label(key, text)]
    case Controls.PermissionFace{filesystem, network, approval}: [icon(key ++ "/filesystem", filesystem), icon(key ++ "/network", network), icon(key ++ "/approval", approval)]


def render_base_role(role: UI.Role, value: Doc.Node, navigation: Design.Navigation, main: Design.Box, details: Maybe<&2, Design.Box>) -> Doc.Node:
  match role:
    case UI.Navigation{}: replace_styles(value, navigation_styles(navigation))
    case UI.Main{}: replace_styles(value, bounds(main))
    case _: value

def render_navigation_toggle(+parameters: Design.LayoutParameters, role: UI.Role, value: Doc.Node, +navigation: Design.Navigation,
  +main: Design.Box, +details: Maybe<&2, Design.Box>) -> Doc.Node:
  match navigation:
    case Design.HiddenNavigation{}:
      replace_styles(value, List.append(&2, Doc.Property,
        bounds(Layout.navigation_toggle_bounds(parameters, Design.Shell{navigation, main, details})), [property("z-index", "6")]))
    case _: render_base_role(role, value, navigation, main, details)

def render_base(+parameters: Design.LayoutParameters, role: UI.Role, meaning: UI.Meaning, value: Doc.Node,
  navigation: Design.Navigation, main: Design.Box, details: Maybe<&2, Design.Box>) -> Doc.Node:
  match meaning:
    case UI.ComposerAction{composer_subject, Core.ApplicationInput{Experience.UserInput{User.SetNavigation{expanded}}}, availability}:
      render_navigation_toggle(parameters, role, value, navigation, main, details)
    case UI.Activate{Core.ApplicationInput{Experience.UserInput{User.SetNavigation{expanded}}}, availability}:
      render_navigation_toggle(parameters, role, value, navigation, main, details)
    case _: render_base_role(role, value, navigation, main, details)


def frame_styles(region: String, +frame: Design.MainFrame) -> +List<Doc.Property>:
  match region:
    case "composer": composer_styles(frame)
    case _: Nil{}


def audit_nodes(+key: String, values: +List<Conversation.AuditFace>) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Conversation.AuditFace{+id, kind, title, source}, rest}:
      Doc.Element{key ++ "/audit/" ++ Nat.show(id), "section", Nil{}, [property("padding", "8px 12px"), property("border-left", "1px solid var(--color-token-border-default)")], Nil{},
        [Doc.Element{key ++ "/audit-title/" ++ Nat.show(id), "strong", Nil{}, Nil{}, Nil{}, [Doc.Text{title}]}, Doc.Markdown{key ++ "/audit-body/" ++ Nat.show(id), None{}, audit_text(source)}]} <> audit_nodes(key, rest)


def card_archive_node(+key: String, label: String, count: Nat, children: +List<Doc.Node>) -> Doc.Node:
  Doc.Element{key, "div", [property("data-native-key", key), property("data-card-archive", Nat.show(count)), property("aria-label", label)],
    List.append(&2, Doc.Property, [property("display", "flex"), property("align-items", "center"),
      property("border", "1px solid var(--color-token-border-default)"), property("border-radius", "7px")], content_area_properties(Enclosure.area(Enclosure.ArchiveGroup{}))),
    [Doc.DropCard{key}], children}

def card_node(+key: String, +face: View.CardFace, destinations: +List<UI.Placement>,
  +source: +List<Child>, visual: Design.Style, +typography: T.Presentation) -> Doc.Node:
  View.CardFace{id, +title, description, priority, pinned, status, project, labels, owner, updated} = face
  Doc.Element{key, "article", [property("data-native-key", key), property("data-card-id", Nat.show(id)),
    property("data-card-title", title), property("aria-label", title), property("draggable", "true")],
    style(visual),
    [Doc.DragCard{key}, Doc.DropCard{key}], card_children(key, face, source, typography)}


def pointer_property(name: String, value: String) -> Doc.Property:
  match name:
    case "background": property("--native-rest-background", value)
    case "color": property("--native-rest-color", value)
    case other: property(other, value)

def pointer_styles(values: +List<Doc.Property>) -> +List<Doc.Property>:
  match values:
    case Nil{}: Nil{}
    case Con{Doc.Property{name, value}, rest}: pointer_property(name, value) <> pointer_styles(rest)

def action(+key: String, +visual: Design.Style, value: Controls.Representation) -> Doc.Node:
  match value:
    case Controls.Action{input, availability, name, +face_value, response, +size, placement, hint, feedback}:
      Doc.Element{key, "button", List.append(&2, Doc.Property, [property("type", "button"), property("class", "native-control"), property("aria-label", name), property("data-native-key", key)],
        List.append(&2, Doc.Property, unavailable(availability), List.append(&2, Doc.Property, behavior(response), help(hint)))),
        pointer_styles(List.append(&2, Doc.Property, style(visual), List.append(&2, Doc.Property, action_geometry(size, visual), List.append(&2, Doc.Property, placement_styles(placement), List.append(&2, Doc.Property, [property("anchor-name", css_anchor(key))], content_geometry(face_value, size)))))), [Doc.Activate{key}], face(key, face_value, Appearance.style_text(visual), size)}
    case _: Doc.Element{key, "span", Nil{}, style(visual), Nil{}, Nil{}}


def render_shell(+parameters: Design.LayoutParameters, role: UI.Role, meaning: UI.Meaning, value: Doc.Node, shell: Design.Shell) -> Doc.Node:
  Design.Shell{navigation, main, details} = shell
  render_base(parameters, role, meaning, value, navigation, main, details)


def field_text(field: Forms.Field, value: Forms.Observed) -> String:
  match value:
    case Forms.ContextValue{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}: context_field_text(field, origin, workspace, sandbox, approval)
    case Forms.WorkspaceValue{Domain.Workspace{roots, primary}}: workspace_field_text(field, roots, primary)
    case other: FieldOptions.observed(other)


type CreationParts is Data:
  CreationParts{hero: +List<Doc.Node>, footer: +List<Doc.Node>}

def creation_footer_start(node: Doc.Node) -> Bool:
  match node:
    case Doc.Element{key, tag, +attrs, styles, events, children}:
      Bool.or(String.eq(attr(attrs, "data-page-region"), Composition.region_name(Composition.CreationContext{})),
        String.eq(attr(attrs, "data-page-region"), Composition.region_name(Composition.ComposerInput{})))
    case _: False{}

def creation_prepend(child: Doc.Node, parts: CreationParts) -> CreationParts:
  CreationParts{hero, footer} = parts
  CreationParts{child <> hero, footer}

def creation_partition_step(starts_footer: Bool, child: Doc.Node, rest: +List<Doc.Node>, parts: CreationParts) -> CreationParts:
  match starts_footer:
    case True{}: CreationParts{Nil{}, child <> rest}
    case False{}: creation_prepend(child, parts)

# Split only at the first semantic footer boundary. Additional children stay
# on their original side of that boundary, preserving the source order.
def creation_partition(children: +List<Doc.Node>) -> CreationParts:
  match children:
    case Nil{}: CreationParts{Nil{}, Nil{}}
    case Con{+child, +rest}: creation_partition_step(creation_footer_start(child), child, rest, creation_partition(rest))

def creation_recombine(parts: CreationParts) -> +List<Doc.Node>:
  CreationParts{hero, footer} = parts
  List.append(&2, Doc.Node, hero, footer)

def creation_block_margin(value: Design.BlockMargin) -> String:
  match value:
    case Design.AutomaticMargin{}: "auto"
    case Design.NoMargin{}: "0"

def creation_band_styles(band: Design.Band) -> +List<Doc.Property>:
  Design.Band{left, width} = band
  [property("width", px(width)), property("max-width", "100%"), property("min-width", "0"),
    property("display", "flex"), property("flex-direction", "column")]

def creation_group_styles_with_arrangement(band: Design.Band, arrangement: Design.CreationArrangement) -> +List<Doc.Property>:
  Design.CreationArrangement{inset, gap, footer_gap, alignment, margin} = arrangement
  List.append(&2, Doc.Property, creation_band_styles(band),
    [property("flex", "0 0 auto"), property("gap", px(gap)), property("margin-block", creation_block_margin(margin))])

def creation_group_styles(band: Design.Band, flow: Design.CreationFlow) -> +List<Doc.Property>:
  creation_group_styles_with_arrangement(band, Layout.creation_arrangement(flow))

def creation_regions_with_footer_gap(+band: Design.Band, footer_gap: Nat, parts: CreationParts) -> +List<Doc.Node>:
  CreationParts{hero, footer} = parts
  [Doc.Element{"creation-hero", "div", [property("data-region", "creation-hero")],
    List.append(&2, Doc.Property, creation_band_styles(band),
      [property("flex", "0 0 auto"), property("min-height", "min-content")]), Nil{}, hero},
   Doc.Element{"creation-footer", "div", [property("data-region", "creation-footer")],
    List.append(&2, Doc.Property, creation_band_styles(band), [property("flex", "0 0 auto"), property("gap", px(footer_gap))]), Nil{}, footer}]

def creation_regions_with_arrangement(+band: Design.Band, arrangement: Design.CreationArrangement, parts: CreationParts) -> +List<Doc.Node>:
  Design.CreationArrangement{inset, gap, footer_gap, alignment, margin} = arrangement
  creation_regions_with_footer_gap(band, footer_gap, parts)

def creation_regions(+band: Design.Band, flow: Design.CreationFlow, parts: CreationParts) -> +List<Doc.Node>:
  creation_regions_with_arrangement(band, Layout.creation_arrangement(flow), parts)

def creation_group(+band: Design.Band, +flow: Design.CreationFlow, children: +List<Doc.Node>) -> Doc.Node:
  Doc.Element{"creation-group", "div", [property("data-region", "creation-group")],
    creation_group_styles(band, flow), Nil{}, creation_regions(band, flow, creation_partition(children))}

def creation_canvas_with_arrangement(canvas: Design.Box, band: Design.Band, flow: Design.CreationFlow, children: +List<Doc.Node>, arrangement: Design.CreationArrangement) -> +List<Doc.Node>:
  Design.CreationArrangement{inset, gap, footer_gap, alignment, margin} = arrangement
  [replace_styles(frame_region("creation-canvas", "creation", canvas, [creation_group(band, flow, children)]),
    [property("display", "flex"), property("flex-direction", "column"), property("align-items", "center"),
      property("overflow-y", "auto"), property("padding-block", px(inset))])]

def creation_canvas_nodes(canvas: Design.Box, band: Design.Band, +flow: Design.CreationFlow, children: +List<Doc.Node>) -> +List<Doc.Node>:
  creation_canvas_with_arrangement(canvas, band, flow, children, Layout.creation_arrangement(flow))

def creation_introduction_alignment(value: Design.Alignment) -> +List<Doc.Property>:
  match value:
    case Design.Centered{}: [property("justify-content", "center"), property("text-align", "center")]
    case _: Nil{}

def creation_introduction_with_arrangement(arrangement: Design.CreationArrangement) -> +List<Doc.Property>:
  Design.CreationArrangement{inset, gap, footer_gap, alignment, margin} = arrangement
  List.append(&2, Doc.Property,
    [property("display", "flex"), property("flex-direction", "row"), property("flex-wrap", "wrap"), property("align-items", "center"), property("gap", "6px"), property("min-width", "0")],
    creation_introduction_alignment(alignment))

def creation_introduction_styles() -> +List<Doc.Property>:
  creation_introduction_with_arrangement(Layout.creation_arrangement(Design.Balanced{}))

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
    case Composition.CreationIntroduction{}:
      creation_introduction_styles()
    case Composition.BoardControls{}:
      [property("display", "flex"), property("flex", "1 1 560px"), property("flex-wrap", "wrap"), property("align-items", "center"), property("gap", "8px"), property("min-width", "0"), property("max-width", "100%")]
    case Composition.BoardTitle{}:
      [property("display", "flex"), property("flex", "0 0 auto"), property("min-width", "0")]
    case Composition.ProjectActions{}:
      [property("display", "flex"), property("flex-wrap", "wrap"), property("gap", "8px"), property("min-width", "0")]
    case Composition.ConversationTitle{}:
      [property("display", "flex"), property("flex-direction", "column"), property("flex", "1"), property("min-width", "0")]
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

def board_shell_styles(+canvas: Design.Box) -> +List<Doc.Property>:
  List.append(&2, Doc.Property, page_shell_styles(canvas),
    [property("gap", "0"), property("min-width", "0"), property("overflow", "hidden")])

def board_heading_styles(+inset: Nat) -> +List<Doc.Property>:
  [property("display", "flex"), property("flex-wrap", "wrap"), property("align-items", "center"),
   property("justify-content", "flex-start"), property("gap", "8px 16px"), property("flex", "none"),
   property("min-width", "0"), property("padding", "8px " ++ px(inset) ++ " 4px"), property("box-sizing", "border-box")]

def board_body_styles() -> +List<Doc.Property>:
  [property("flex", "1"), property("min-height", "0"), property("min-width", "0"), property("overflow", "hidden"),
   property("display", "flex"), property("flex-direction", "column")]

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
        [property("display", "flex"), property("flex-direction", "row"), property("align-items", "stretch"),
         property("gap", px(gap)), property("padding", "0 " ++ px(inset) ++ " " ++ px(inset)),
         property("flex", "1"), property("min-height", "0"), property("min-width", "0"),
         property("overflow-x", "auto"), property("overflow-y", "hidden"), property("overscroll-behavior", "contain"),
         property("scrollbar-gutter", "stable"), property("box-sizing", "border-box")], events, board_columns(children, width)}
    case other: other

def board_body_nodes(values: +List<Doc.Node>, +width: Nat, +gap: Nat, +inset: Nat) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: board_stage_region(value, width, gap, inset) <> board_body_nodes(rest, width, gap, inset)

def board_children(+children: +List<Doc.Node>, +width: Nat, +gap: Nat, +inset: Nat) -> +List<Doc.Node>:
  [page_group("board-heading", "heading", board_heading_styles(inset), page_nodes(children, "heading")),
    page_group("board-body", "body", board_body_styles(), board_body_nodes(page_nodes(children, "body"), width, gap, inset)),
    page_group("board-dock", "dock", [property("flex", "none")], page_nodes(children, "dock"))]

def board_shell(+canvas: Design.Box, width: Nat, gap: Nat, inset: Nat, children: +List<Doc.Node>) -> Doc.Node:
  replace_styles(frame_region("board-shell", "board", canvas, board_children(children, width, gap, inset)), board_shell_styles(canvas))

def conversation_title_styles() -> +List<Doc.Property>:
  [property("display", "block"), property("min-height", "0"), property("min-width", "0"), property("width", "100%"), property("overflow", "hidden"),
    property("text-overflow", "ellipsis"), property("white-space", "nowrap")]

def conversation_title_node(node: Doc.Node) -> Doc.Node:
  replace_styles(node, conversation_title_styles())

def conversation_heading_region_by_title(is_title: Bool, key: String, tag: String, attrs: +List<Doc.Property>,
  styles: +List<Doc.Property>, events: +List<Doc.Event>, children: +List<Doc.Node>) -> Doc.Node:
  match is_title:
    case True{}: Doc.Element{key, tag, attrs, styles, events, Std.map(~Doc.Node, ~Doc.Node, ~conversation_title_node, children)}
    case False{}: Doc.Element{key, tag, attrs, styles, events, children}

def conversation_heading_region(node: Doc.Node) -> Doc.Node:
  match node:
    case Doc.Element{key, tag, +attrs, styles, events, children}:
      conversation_heading_region_by_title(String.eq(attr(attrs, "data-page-region"), Composition.region_name(Composition.ConversationTitle{})),
        key, tag, attrs, styles, events, children)
    case other: other

def conversation_heading_nodes(children: +List<Doc.Node>) -> +List<Doc.Node>:
  Std.map(~Doc.Node, ~Doc.Node, ~conversation_heading_region, page_nodes(children, "heading"))

def conversation_heading_styles(+heading: Design.Box) -> +List<Doc.Property>:
  List.append(&2, Doc.Property, bounds(heading), [property("display", "flex"), property("align-items", "center"), property("justify-content", "space-between"), property("gap", "16px"), property("padding", "0 16px"), property("padding-right", "56px"), property("box-sizing", "border-box"), property("z-index", "5")])

def conversation_dock_styles(dock: Maybe<&2, Design.Dock>) -> +List<Doc.Property>:
  match dock:
    case None{}: [property("display", "none")]
    case Some{Design.Dock{Design.Band{left, width}, bottom, maximum, regions, input, reservation}}:
      [property("position", "fixed"), property("left", px(left)), property("bottom", px(bottom)), property("width", px(width)), property("max-height", px(maximum)), property("display", "flex"), property("flex-direction", "column"), property("gap", "8px"), property("overflow", "hidden"), property("z-index", "10")]

# The original queue key owns the bounded scroll viewport; only its intrinsic
# content gets a new wrapper, so geometry continues to observe the queue itself.
def dock_approval_content(+key: String, children: +List<Doc.Node>) -> Doc.Node:
  Doc.Element{generated_identity(key, "intrinsic-content"), "div", Nil{},
    [property("display", "flex"), property("flex-direction", "column"),
     property("gap", "8px"), property("flex", "0 0 auto"), property("min-height", "min-content")],
    Nil{}, children}

def dock_approval_queue(node: Doc.Node) -> Doc.Node:
  match node:
    case Doc.Element{+key, tag, attrs, styles, events, children}:
      Doc.Element{key, tag, attrs,
        List.append(&2, Doc.Property, styles, [property("flex", "1 1 auto"), property("min-height", "0"), property("overflow", "auto")]),
        events, [dock_approval_content(key, children)]}
    case other: other

def dock_region_children(approval: Bool, children: +List<Doc.Node>) -> +List<Doc.Node>:
  match approval:
    case True{}: Std.map(~Doc.Node, ~Doc.Node, ~dock_approval_queue, children)
    case False{}: children

def dock_region_styles(approval: Bool) -> +List<Doc.Property>:
  match approval:
    case True{}: [property("flex", "1 1 auto"), property("min-height", "0"), property("overflow", "hidden")]
    case False{}: [property("flex", "0 0 auto")]

def dock_region_element(+approval: Bool, key: String, tag: String, attrs: +List<Doc.Property>,
  styles: +List<Doc.Property>, events: +List<Doc.Event>, children: +List<Doc.Node>) -> Doc.Node:
  Doc.Element{key, tag, attrs, List.append(&2, Doc.Property, styles, dock_region_styles(approval)), events,
    dock_region_children(approval, children)}

def conversation_dock_region(node: Doc.Node) -> Doc.Node:
  match node:
    case Doc.Element{key, tag, +attrs, styles, events, children}:
      dock_region_element(String.eq(attr(attrs, "data-page-region"), Composition.region_name(Composition.ApprovalDecisions{})),
        key, tag, attrs, styles, events, children)
    case other: other

def conversation_dock_regions(children: +List<Doc.Node>) -> +List<Doc.Node>:
  Std.map(~Doc.Node, ~Doc.Node, ~conversation_dock_region, children)

def conversation_children(+children: +List<Doc.Node>, +heading: Design.Box, +viewport: Design.Box, +reading: Design.Band, +dock: Maybe<&2, Design.Dock>, +identity: Maybe<&2, Conversation.Identity>) -> +List<Doc.Node>:
  [page_group("conversation-heading", "heading", conversation_heading_styles(heading), conversation_heading_nodes(children)),
    reading_element("conversation-body", "conversation-body", "div", [property("data-region", "conversation-body"), property("data-page-group", "body")],
      timeline_styles(Design.ConversationFrame{heading, viewport, reading, dock}), Nil{}, page_nodes(children, "body"), identity),
    reading_element("dock", "conversation-dock", "div", [property("data-region", "dock"), property("data-page-group", "dock")],
      conversation_dock_styles(dock), Nil{}, conversation_dock_regions(page_nodes(children, "dock")), identity)]


def main_children(+children: +List<Doc.Node>, frame: Design.MainFrame, +identity: Maybe<&2, Conversation.Identity>) -> +List<Doc.Node>:
  match frame:
    case Design.CreationFrame{heading, canvas, band, input, flow}:
      creation_canvas_nodes(canvas, band, flow, children)
    case Design.UnavailableFrame{heading, canvas, band}:
      [frame_region("unavailable-canvas", "unavailable", canvas, children)]
    case Design.ConversationFrame{heading, viewport, reading, dock}:
      conversation_children(children, heading, viewport, reading, dock, identity)
    case Design.OverviewFrame{canvas, band, organization}:
      [overview_shell(canvas, band, organization, children)]
    case Design.BoardFrame{canvas, width, gap, inset}:
      [board_shell(canvas, width, gap, inset, children)]


def node_value(value: UI.Meaning) -> String:
  match value:
    case UI.Edit{editor, field, entry, observed_value, choices}: field_text(field, observed_value)
    case UI.BoardSearch{filter}: filter_search(filter)
    case UI.SearchChoices{query}: query
    case UI.EnterDirectory{editor, text}: text
    case UI.DirectoryBrowserLocation{value}: value
    case UI.BoardProfile{automatic, selected, choices, enabled}: selected
    case _: ""


def field_options(+key: String, values: +List<Forms.ChoiceValue>) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Forms.ChoiceValue{value, label}, rest}: option(key, value, label) <> field_options(key, rest)

def choice_options(+key: String, meaning: UI.Meaning) -> +List<Doc.Node>:
  match meaning:
    case UI.BoardProfile{automatic, selected, choices, enabled}: field_options(key, FieldOptions.profile_options(choices))
    case UI.Edit{editor, field, entry, value, choices}: field_options(key, choices)
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
    [property("display", "flex"), property("align-items", "center"), property("flex-wrap", "wrap"), property("gap", px(Enclosure.separation(Enclosure.ComposerControls{}))), property("min-width", "0")], Nil{}, action_leading(children)},
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

def positioned_children(key: String, region: String, children: +List<Doc.Node>, frame: Design.MainFrame, +identity: Maybe<&2, Conversation.Identity>) -> +List<Doc.Node>:
  match region:
    case "main": main_children(children, frame, identity)
    case "composer-actions": composer_action_groups(key, children)
    case _: children


def position_main(values: +List<Doc.Node>, +frame: Design.MainFrame, +identity: Maybe<&2, Conversation.Identity>) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Doc.Element{+key, tag, +attrs, styles, events, children}, rest}:
      Doc.Element{key, tag, attrs, List.append(&2, Doc.Property, styles, List.append(&2, Doc.Property, frame_styles(attr(attrs, "data-region"), frame), measured_input_styles(attr(attrs, "data-native-editor-key"), frame))), events, positioned_page_children(attr(attrs, "data-page-region"), positioned_children(key, attr(attrs, "data-region"), position_main(children, frame, identity), frame, identity))} <> position_main(rest, frame, identity)
    case Con{other, rest}: other <> position_main(rest, frame, identity)


def input_children(+key: String, meaning: UI.Meaning, widget: Controls.Widget) -> +List<Doc.Node>:
  match widget:
    case Controls.SelectInput{}: choice_options(key, meaning)
    case Controls.MultiSelectInput{}: choice_options(key, meaning)
    case Controls.PlainValue{}: [Doc.Text{node_value(meaning)}]
    case _: Nil{}


def editor_placeholder(kind: EditorLayout.FieldKind, name: String) -> +List<Doc.Property>:
  match kind:
    case EditorLayout.WorkTitle{}: [property("placeholder", name)]
    case EditorLayout.WorkDescription{}: [property("placeholder", name)]
    case _: Nil{}

def capture_field(placement: Controls.LabelPlacement, +key: String, name: String,
  presented: Doc.Node) -> Doc.Node:
  match placement:
    case Controls.BesideInput{}:
      replace_styles(label_input(Controls.BesideInput{}, key, name, presented),
        [property("flex", "1 1 200px"), property("min-width", "0")])
    case other:
      replace_styles(label_input(other, key, name, presented),
        [property("flex", "1 1 140px"), property("min-width", "0")])

def editor_field_presented(kind: EditorLayout.FieldKind, placement: Controls.LabelPlacement,
  +key: String, name: String, presented: Doc.Node) -> Doc.Node:
  match kind:
    case EditorLayout.WorkTitle{}: presented
    case EditorLayout.WorkDescription{}: presented
    case EditorLayout.MetadataFlexible{}:
      replace_styles(label_input(placement, key, name, presented),
        [property("flex", "1 1 140px"), property("min-width", "0")])
    case EditorLayout.MetadataWide{}:
      replace_styles(label_input(placement, key, name, presented),
        [property("flex", "1 1 100%"), property("min-width", "0")])
    case EditorLayout.CaptureOption{}: capture_field(placement, key, name, presented)
    case _: label_input(placement, key, name, presented)

def editor_field(+kind: EditorLayout.FieldKind, placement: Controls.LabelPlacement,
  +key: String, +name: String, input: Doc.Node) -> Doc.Node:
  editor_field_presented(kind, placement, key, name, input)

def input(+key: String, +meaning: UI.Meaning, representation: Controls.Representation, visual: Design.Style) -> Doc.Node:
  match representation:
    case Controls.Input{+binding, +name, +widget, placement, availability}:
      editor_field(EditorLayout.field_kind(binding), placement, key, name, Doc.Element{key, widget_tag(widget), List.append(&2, Doc.Property,
        List.append(&2, Doc.Property, [property("aria-label", name), property("data-native-key", key), property("value", node_value(meaning))], List.append(&2, Doc.Property, editor_placeholder(EditorLayout.field_kind(binding), name), List.append(&2, Doc.Property, checked_properties(meaning), field_hint(meaning)))),
        List.append(&2, Doc.Property, widget_properties(widget), List.append(&2, Doc.Property, editor_properties(key, widget), List.append(&2, Doc.Property, meaning_properties(meaning), unavailable(availability))))),
        List.append(&2, Doc.Property, style(visual), input_style_for(meaning, widget)), input_events(key, widget), input_children(key, meaning, widget)})
    case _: Doc.Element{key, "output", Nil{}, style(visual), Nil{}, [Doc.Text{node_value(meaning)}]}


def compound_field(+key: String, label: String, field: Forms.Field,
  visual: Design.Style, children: +List<Doc.Node>) -> Doc.Node:
  Doc.Element{key, "section", [property("data-native-key", key), property("aria-label", label),
    property("data-field", Forms.key(field)), property("tabindex", "-1")], style(visual), Nil{}, children}

def directory_path_node(+key: String, +path: String) -> Doc.Node:
  Doc.Element{key ++ "/path", "span", [property("title", path)],
    [property("width", "100%"), property("flex", "0 0 auto"), property("min-width", "0"), property("overflow", "hidden"),
     property("text-overflow", "ellipsis"), property("white-space", "nowrap")], Nil{}, [Doc.Text{path}]}

def directory_row_node(+key: String, +path: String, primary: Bool, visual: Design.Style,
  children: +List<Doc.Node>) -> Doc.Node:
  Doc.Element{key, "div", [property("data-native-key", key), property("aria-label", path),
    property("data-primary", FieldOptions.boolean(primary))], List.append(&2, Doc.Property, style(visual),
    [property("flex", "0 0 auto")]), Nil{},
    [directory_path_node(key, path), Doc.Element{key ++ "/controls", "div", Nil{},
      [property("display", "flex"), property("flex", "none"), property("width", "100%"), property("min-width", "0"), property("align-items", "center"),
       property("gap", "4px")], Nil{}, children}]}

def context_draft_kind(workspace: Context.WorkspaceValue, sandbox: Context.SandboxValue,
  approval: Context.ApprovalValue) -> String:
  match workspace sandbox approval:
    case Context.InheritedWorkspace{value} Context.InheritedSandbox{permissions} Context.InheritedApproval{policy}: "inherited"
    case _ _ _: "custom"

def context_observation_kind(observation: Context.Observation) -> String:
  match observation:
    case Context.DraftExecution{Context.ContextUnavailable{reason}}: "unavailable"
    case Context.DraftExecution{Context.ProspectiveContext{origin, project, workspace, sandbox, approval, guidance}}:
      context_draft_kind(workspace, sandbox, approval)
    case Context.CommittedExecution{context}: "committed"

def context_summary_node(+key: String, +label: String, role: UI.Role, observation: Context.Observation,
  visual: Design.Style, children: +List<Child>, +typography: T.Presentation) -> Doc.Node:
  Doc.Element{key, "div", [property("data-native-key", key), property("aria-label", label),
    property("data-context-kind", context_observation_kind(observation))], List.append(&2, Doc.Property, style(visual),
    [property("flex", "0 0 auto")]), Nil{},
    Doc.Element{key ++ "/provenance", "div", Nil{},
      List.append(&2, Doc.Property, part_text(typography, T.Support{}, T.Regular{}), [property("color", "var(--color-token-text-secondary)")]), Nil{}, [Doc.Text{label}]} <> documents(children)}

def choice_group_node(+key: String, +label: String, visual: Design.Style, children: +List<Doc.Node>, +typography: T.Presentation) -> Doc.Node:
  Doc.Element{key, "section", [property("data-native-key", key), property("role", "radiogroup"), property("aria-label", label)],
    List.append(&2, Doc.Property, style(visual), [property("flex-shrink", "0"), property("height", "auto")]), Nil{},
    Doc.Element{key ++ "/label", "div", Nil{}, List.append(&2, Doc.Property, part_text(typography, T.Support{}, T.Regular{}), [property("color", "var(--color-token-text-secondary)"), property("padding-inline", px(Appearance.popup_content_inset()))]), Nil{}, [Doc.Text{label}]} <> children}

def project_header_node(node: Doc.Node) -> Doc.Node:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}:
      Doc.Element{key, tag, List.append(&2, Doc.Property, attrs, [property("class", "native-surface")]), pointer_styles(styles), events, children}
    case other: other

def project_child(header: Bool, node: Doc.Node) -> Doc.Node:
  match header:
    case True{}: project_header_node(node)
    case False{}: replace_styles(node, [property("margin-inline-start", "20px")])

def project_group_children(+owner: String, values: +List<Child>, +selected: Bool, +expanded: Bool) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Child{Design.Node{+key, semantic, label, role, meaning, visual, representation, children}, document}, rest}:
      project_child(String.eq(key, owner ++ "/actions"), document) <> project_group_children(owner, rest, selected, expanded)

def project_group_node(+key: String, project: Nat, selected: Bool, +expanded: Bool, visual: Design.Style, children: +List<Child>) -> Doc.Node:
  Doc.Element{key, "div", [property("data-native-key", key), property("data-project", Nat.show(project)), property("data-expanded", FieldOptions.boolean(expanded))],
    style(visual), Nil{}, project_group_children(key, children, selected, expanded)}

def task_status_tone(status: String) -> String:
  match status:
    case "Working": "var(--color-text-info)"
    case "Paused": "var(--color-text-warning)"
    case _: "var(--color-text-secondary)"

def task_status_node(node: Doc.Node, +status: String, +typography: T.Presentation) -> Doc.Node:
  match node:
    case Doc.Element{+key, tag, attrs, styles, events, children}:
      Doc.Element{key, "span", List.append(&2, Doc.Property, attrs, [property("aria-label", status), property("title", status)]),
        List.append(&2, Doc.Property, part_text(typography, T.Support{}, T.Medium{}), [property("display", "inline-flex"), property("flex", "0 0 auto"), property("align-items", "center"), property("gap", "4px"),
         property("order", "-1"), property("color", task_status_tone(status)), property("white-space", "nowrap")]), events,
        [Doc.Element{key ++ "/indicator", "span", [property("aria-hidden", "true")], Nil{}, Nil{}, [Doc.Text{"●"}]}, Doc.Text{status}]}
    case other: other

def task_row_control(node: Doc.Node, representation: Controls.Representation, status: String, +typography: T.Presentation) -> Doc.Node:
  match representation:
    case Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}: node
    case _: task_status_node(node, status, typography)

def task_row_children(values: +List<Child>, +status: String, +typography: T.Presentation) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Child{Design.Node{key, semantic, label, role, meaning, visual, representation, children}, document}, rest}:
      task_row_control(document, representation, status, typography) <> task_row_children(rest, status, typography)

def task_row_node(+key: String, task: Nat, +status: String, +selected: Bool, visual: Design.Style, children: +List<Child>, +typography: T.Presentation) -> Doc.Node:
  Doc.Element{key, "div", [property("data-native-key", key), property("data-task", Nat.show(task)), property("data-status", status), property("class", "native-surface")],
    pointer_styles(style(visual)), Nil{}, task_row_children(children, status, typography)}

def project_chooser_node(+key: String, selected: Maybe<&2, Nat>, visual: Design.Style, children: +List<Child>) -> Doc.Node:
  Doc.Element{key, "div", [property("data-native-key", key)], style(visual), Nil{}, documents(children)}

def submission_alert_styles(+typography: T.Presentation) -> +List<Doc.Property>:
  List.append(&2, Doc.Property, part_text(typography, T.Body{}, T.Regular{}), [property("color", "var(--color-text-danger)"), property("white-space", "pre-wrap"), property("overflow-wrap", "anywhere"), property("min-width", "0"), property("flex", "0 0 auto")])

def read_only_node(+key: String, role: UI.Role, label: String, text: String, visual: Design.Style, +source: +List<Child>, +typography: T.Presentation) -> Doc.Node:
  match role:
    case UI.Alert{}:
      Doc.Element{key, "div", [property("data-native-key", key), property("role", "alert"), property("aria-label", label)],
        List.append(&2, Doc.Property, style(visual), submission_alert_styles(typography)), Nil{}, Doc.Text{text} <> documents(source)}
    case +other:
      Doc.Element{key, tag(other), [property("data-native-key", key)], style(visual), Nil{}, Doc.Markdown{key ++ "/markdown", markdown_source(source), text} <> documents(source)}

def activity_node(+key: String, +label: String, visual: Design.Style, children: +List<Child>, expanded: Bool, audit: +List<Conversation.AuditFace>) -> Doc.Node:
  Doc.Element{key, "details", List.append(&2, Doc.Property, [property("aria-label", label), property("data-native-key", key)], opened(expanded)),
    style(visual), Nil{}, List.append(&2, Doc.Node, activity_summary(key, label, documents(children)), audit_nodes(key, audit))}

def match_node(+value: Design.Node, +children: +List<Child>) -> Doc.Node:
  Design.Node{+key, semantic, +label, +role, meaning, +visual, +representation, nested} = value
  match meaning:
    case UI.Edit{editor, field, Forms.DirectoryCollection{}, value, choices}: compound_field(key, label, field, visual, documents(children))
    case UI.Edit{editor, field, Forms.FileCollection{}, value, choices}: compound_field(key, label, field, visual, documents(children))
    case UI.ComposerAction{subject, input_value, availability}: action(key, visual, representation)
    case UI.PanelToggle{expanded, input_value, availability}: action(key, visual, representation)
    case UI.LayerRegion{dismiss, outside, escape}: layer_region_node(key, label, role, outside, visual, children, Appearance.style_text(visual))
    case UI.Activate{input_value, availability}: action(key, visual, representation)
    case UI.Choice{selected, description, input, availability}: action(key, visual, representation)
    case UI.ProjectGroup{project, selected, expanded}: project_group_node(key, project, selected, expanded, visual, children)
    case UI.TaskRow{task, status, selected}: task_row_node(key, task, status, selected, visual, children, Appearance.style_text(visual))
    case UI.ProjectChooser{selected}: project_chooser_node(key, selected, visual, children)
    case UI.DirectoryRow{path, primary}: directory_row_node(key, path, primary, visual, documents(children))
    case UI.ContextSummary{observation}: context_summary_node(key, label, role, observation, visual, children, Appearance.style_text(visual))
    case UI.ChoiceGroup{}: choice_group_node(key, label, visual, documents(children), Appearance.style_text(visual))
    case UI.PageRegion{region, position}: page_region(key, region, position, documents(children))
    case UI.BoardGroup{grouping}: board_group_node(key, grouping, documents(children), Appearance.style_text(visual))
    case UI.BoardLane{stage, count}: board_lane_node(key, label, stage, count, children, Appearance.style_text(visual))
    case UI.PageContext{conversation}: region_node(key, label, role, visual, children, Appearance.style_text(visual))
    case UI.ActivityContent{expanded, audit}: activity_node(key, label, visual, children, expanded, audit)
    case UI.Region{}: region_node(key, label, role, visual, children, Appearance.style_text(visual))
    case UI.ReadOnly{text}: read_only_node(key, role, label, text, visual, children, Appearance.style_text(visual))
    case UI.CodeFacts{Code.Scene{+identity, literal, wrap, copy, enabled, controls}}:
      Doc.Element{key, "div", Nil{}, [property("display", "contents")], Nil{}, [
        Doc.Portal{key ++ "/toolbar", Code.key(identity) ++ "/toolbar", documents(children)},
        Doc.TargetProperties{key ++ "/toolbar-observation", Code.key(identity) ++ "/toolbar", [property("data-native-key", key)], Nil{}},
        Doc.TargetProperties{key ++ "/wrap", Code.key(identity) ++ "/code", Nil{}, [property("white-space", code_wrap(wrap)), property("overflow-wrap", "anywhere")]}]}
    case UI.TaskFacts{details}: Doc.Element{key, "section", [property("data-native-key", key)], style(visual), Nil{}, task_details(key, details)}
    case UI.CardArchive{count}: card_archive_node(key, label, count, documents(children))
    case UI.MovableCard{destinations, face}: card_node(key, face, destinations, children, visual, Appearance.style_text(visual))
    case other: input(key, other, representation, visual)


def render_children(values: +List<Design.Node>) -> +List<Child>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      Design.Node{key, semantic, label, +role, meaning, visual, representation, children} = value
      Child{value, decorate(role_name(role), semantic, match_node(value, render_children(children)))} <> render_children(rest)

def render_nodes(values: +List<Design.Node>) -> +List<Doc.Node>:
  documents(render_children(values))


def render_node(+value: Design.Node) -> Doc.Node:
  Design.Node{key, semantic, label, role, meaning, style, control, children} = value
  match_node(value, render_children(children))


def render_base_shell_node(+parameters: Design.LayoutParameters, +value: Design.Node, +shell: Design.Shell) -> Doc.Node:
  Design.Node{key, semantic, label, role, meaning, visual, representation, children} = value
  match semantic:
    case "settings/open":
      Design.Shell{navigation, main, details} = shell
      replace_styles(render_node(value), List.append(&2, Doc.Property,
        bounds(Layout.settings_bounds(parameters, navigation, main)), [property("z-index", "6")]))
    case _: render_shell(parameters, role, meaning, render_node(value), shell)

def positioned_root(value: Doc.Node, +frame: Design.MainFrame, +identity: Maybe<&2, Conversation.Identity>) -> Doc.Node:
  match value:
    case Doc.Element{+key, tag, +attrs, styles, events, children}:
      Doc.Element{key, tag, attrs, List.append(&2, Doc.Property, styles, List.append(&2, Doc.Property, frame_styles(attr(attrs, "data-region"), frame), measured_input_styles(attr(attrs, "data-native-editor-key"), frame))), events,
        positioned_page_children(attr(attrs, "data-page-region"), positioned_children(key, attr(attrs, "data-region"), position_main(children, frame, identity), frame, identity))}
    case other: other

def render_base_node(+parameters: Design.LayoutParameters, +value: Design.Node, shell: Design.Shell, main: Design.MainFrame) -> Doc.Node:
  Design.Node{key, semantic, label, role, meaning, visual, representation, children} = value
  match meaning:
    case UI.PageContext{conversation}: positioned_root(render_base_shell_node(parameters, value, shell), main, conversation)
    case _: positioned_root(render_base_shell_node(parameters, value, shell), main, None{})

def base_nodes(+parameters: Design.LayoutParameters, values: +List<Design.Node>, +shell: Design.Shell, +main: Design.MainFrame) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: render_base_node(parameters, value, shell, main) <> base_nodes(parameters, rest, shell, main)

def overlays(values: +List<Design.Node>, placements: +List<Design.Overlay>, +active: Maybe<&2, String>) -> +List<Doc.Node>:
  match values placements:
    case Con{value, rest} Con{Design.Overlay{key, level, placement}, remaining}:
      replace_styles(modal_scope(key, active, render_node(value)), List.append(&2, Doc.Property, overlay_styles(placement), [property("z-index", Nat.show(Nat.add(50n, level)))])) <>
        overlays(rest, remaining, active)
    case _ _: Nil{}

def document_theme(+theme: Design.Theme) -> Doc.Node:
  Doc.TargetProperties{"document-theme", "@document/root",
    [property("data-theme", theme_name(theme))], [property("color-scheme", theme_name(theme))]}

def render(scene: Web.Scene) -> Doc.Document:
  Web.Scene{Design.Surface{+content, +theme, base, overlays_value, +active}, platform, generation, realization,
    Design.Layout{Design.Viewport{width, height}, shell, main, placements, +parameters}} = scene
  Doc.Document{Doc.Element{"application", "div", [property("data-document", "application"), property("class", theme_class(theme))],
    [property("position", "fixed"), property("inset", "0"), property("overflow", "hidden"), property("background", surface_background(Surfaces.Canvas{}, Surfaces.Rest{})), property("color", "var(--color-token-text-primary)")], Nil{},
    document_theme(theme) <> List.append(&2, Doc.Node, [base_scope(active, base_nodes(parameters, base, shell, main))], overlays(overlays_value, placements, active))}, "Selvedge"}
