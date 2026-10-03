import Base
import ../core/interface.bend as UI
import ../core/user-context.bend as Context
import ../core/ui-world.bend as View
import ../core/user-input.bend as User
import ../bendlib/domain.bend as Domain
import ./renderer.bend as Render
import ./controls.bend as Controls
import ./document.bend as Doc
import ./design.bend as Design
import ./appearance.bend as Appearance

# These obligations bind the actual semantic dispatch and preserve the Core
# children. Menu placement, dismissal and committed facts keep their existing owners.
def directory_production(+key: String, label: String, role: UI.Role, +path: String, +primary: Bool,
  source: +List<UI.Node>, +children: +List<Doc.Node>, +visual: Design.Style,
  representation: Controls.Representation, appearances: +List<Design.Appearance>) ->
  {Render.match_node(key, label, role, UI.DirectoryRow{path, primary}, source, children, visual, representation, appearances) ==
    Render.directory_row_node(key, path, primary, visual, children) : Doc.Node}:
  {==}

def directory_identity_law(-key: String, -path: String, -primary: Bool, -visual: Design.Style, -children: +List<Doc.Node>) -> Type:
  {Render.directory_row_node(key, path, primary, visual, children) ==
      Doc.Element{key, "div", [Render.property("data-native-key", key), Render.property("aria-label", path), Render.property("data-primary", Render.boolean(primary))],
        List.append(&2, Doc.Property, Render.style(visual),
          [Render.property("flex", "0 0 auto")]), Nil{},
        [Render.directory_path_node(key, path), Doc.Element{key ++ "/controls", "div", Nil{},
          [Render.property("display", "flex"), Render.property("flex", "none"), Render.property("width", "100%"), Render.property("min-width", "0"), Render.property("align-items", "center"), Render.property("gap", "4px")], Nil{}, children}]} : Doc.Node}

def directory_identity(+key: String, +path: String, +primary: Bool, +visual: Design.Style, +children: +List<Doc.Node>) -> directory_identity_law(key, path, primary, visual, children):
  {==}

def directory_full_path_law(-key: String, -path: String) -> Type:
  {Render.directory_path_node(key, path) ==
      Doc.Element{key ++ "/path", "span", [Render.property("title", path)],
        [Render.property("width", "100%"), Render.property("flex", "0 0 auto"), Render.property("min-width", "0"), Render.property("overflow", "hidden"),
         Render.property("text-overflow", "ellipsis"), Render.property("white-space", "nowrap")], Nil{}, [Doc.Text{path}]} : Doc.Node}

def directory_full_path(+key: String, +path: String) -> directory_full_path_law(key, path):
  {==}

def choice_binding_retained_law(-key: String, -tag: String, -attrs: +List<Doc.Property>, -styles: +List<Doc.Property>, -events: +List<Doc.Event>, -children: +List<Doc.Node>, -label: String, -description: String, -selected: Bool) -> Type:
  {Render.choice_face(Doc.Element{key, tag, attrs, styles, events, children}, label, description, selected) ==
      Doc.Element{key, tag, attrs, List.append(&2, Doc.Property, styles,
        [Render.property("width", "100%"), Render.property("min-width", "0"),
         Render.property("height", "auto"), Render.property("flex-shrink", "0")]), events,
         Render.choice_content(key, label, description, selected)} : Doc.Node}

def choice_binding_retained(+key: String, +tag: String, +attrs: +List<Doc.Property>, +styles: +List<Doc.Property>, +events: +List<Doc.Event>,
  children: +List<Doc.Node>, +label: String, +description: String, +selected: Bool) -> choice_binding_retained_law(key, tag, attrs, styles, events, children, label, description, selected):
  {==}

def choice_group_production(+key: String, +label: String, role: UI.Role, source: +List<UI.Node>,
  +children: +List<Doc.Node>, +visual: Design.Style, representation: Controls.Representation, appearances: +List<Design.Appearance>) ->
  {Render.match_node(key, label, role, UI.ChoiceGroup{}, source, children, visual, representation, appearances) ==
    Render.choice_group_node(key, label, visual, children) : Doc.Node}:
  {==}

def summary_production(+key: String, +label: String, +role: UI.Role, +observation: Context.Observation,
  source: +List<UI.Node>, +children: +List<Doc.Node>, +visual: Design.Style,
  representation: Controls.Representation, +appearances: +List<Design.Appearance>) ->
  {Render.match_node(key, label, role, UI.ContextSummary{observation}, source, children, visual, representation, appearances) ==
    Render.context_summary_node(key, label, role, observation, visual, children, appearances) : Doc.Node}:
  {==}

def summary_passive_facts_law(-key: String, -label: String, -role: UI.Role, -observation: Context.Observation, -visual: Design.Style, -children: +List<Doc.Node>, -appearances: +List<Design.Appearance>) -> Type:
  {Render.context_summary_node(key, label, role, observation, visual, children, appearances) ==
      Doc.Element{key, "div", [Render.property("data-native-key", key), Render.property("aria-label", label),
        Render.property("data-context-kind", Render.context_observation_kind(observation))], List.append(&2, Doc.Property, Render.style(visual),
        [Render.property("flex", "0 0 auto")]), Nil{},
        Doc.Element{key ++ "/provenance", "div", Nil{}, [Render.property("font-size", "12px"),
          Render.property("color", "var(--color-token-text-secondary)")], Nil{}, [Doc.Text{label}]} <> children} : Doc.Node}

def summary_passive_facts(+key: String, +label: String, role: UI.Role, +observation: Context.Observation,
  +visual: Design.Style, +children: +List<Doc.Node>, appearances: +List<Design.Appearance>) -> summary_passive_facts_law(key, label, role, observation, visual, children, appearances):
  {==}

def committed_provenance(context: Context.EffectiveContext) ->
  {Render.context_observation_kind(Context.CommittedExecution{context}) == "committed" : String}:
  {==}

def unavailable_provenance(reason: String) ->
  {Render.context_observation_kind(Context.DraftExecution{Context.ContextUnavailable{reason}}) == "unavailable" : String}:
  {==}

def inherited_provenance(origin: Context.Origin, project: Maybe<&2, Nat>, workspace: Domain.Workspace,
  sandbox: Domain.Sandbox, approval: Domain.ApprovalPolicy, guidance: Context.GuidancePreview) ->
  {Render.context_observation_kind(Context.DraftExecution{Context.ProspectiveContext{origin, project,
    Context.InheritedWorkspace{workspace}, Context.InheritedSandbox{sandbox}, Context.InheritedApproval{approval}, guidance}}) == "inherited" : String}:
  {==}

def workspace_label(+label: String, expanded: Bool) ->
  {Controls.face_for(Controls.WorkspacePicker{expanded}, label, Controls.ComposerArea{}) == Controls.PickerFace{Some{Controls.Folder{}}, label} : Controls.Face}:
  {==}

def permissions_label(+label: String, current: Controls.Face, +execution: Maybe<&2, Context.Observation>) ->
  {Controls.composer_face(View.PermissionsSubject{}, label, current, execution) == Controls.permission_face(execution) : Controls.Face}:
  {==}

def approval_canonical(+value: Context.ApprovalValue) ->
  {Render.approval_text(value) == Context.approval_option(Context.observed_approval(value)) : String}:
  {==}


def choice_content_projection_law(-key: String, -label: String, -description: String, -selected: Bool) -> Type:
  {Render.choice_content(key, label, description, selected) ==
      [Doc.Element{key ++ "/content", "span", Nil{}, [Render.property("display", "flex"), Render.property("flex-direction", "column"),
        Render.property("flex", "1 1 0"), Render.property("min-width", "0"), Render.property("text-align", "start"), Render.property("gap", "2px")], Nil{},
        [Doc.Text{label}, Doc.Element{key ++ "/description", "span", Nil{},
          [Render.property("font-size", "12px"), Render.property("color", "var(--color-token-text-secondary)"),
           Render.property("white-space", "normal")], Nil{}, [Doc.Text{description}]}]},
       Render.choice_mark(key, selected, 20n, 16n)] : +List<Doc.Node>}

def choice_content_projection(+key: String, +label: String, +description: String, +selected: Bool) -> choice_content_projection_law(key, label, description, selected):
  {==}

def choice_group_native_law(-key: String, -label: String, -visual: Design.Style, -children: +List<Doc.Node>) -> Type:
  {Render.choice_group_node(key, label, visual, children) ==
      Doc.Element{key, "section", [Render.property("data-native-key", key), Render.property("role", "radiogroup"), Render.property("aria-label", label)],
        List.append(&2, Doc.Property, Render.style(visual), [Render.property("flex-shrink", "0"), Render.property("height", "auto")]), Nil{},
        Doc.Element{key ++ "/label", "div", Nil{}, [Render.property("font-size", "12px"),
          Render.property("color", "var(--color-token-text-secondary)"), Render.property("padding-inline", Render.px(Appearance.popup_content_inset()))], Nil{}, [Doc.Text{label}]} <> children} : Doc.Node}

def choice_group_native(+key: String, +label: String, +visual: Design.Style, +children: +List<Doc.Node>) -> choice_group_native_law(key, label, visual, children):
  {==}

def custom_workspace_provenance(workspace: Domain.Workspace, sandbox: Context.SandboxValue, approval: Context.ApprovalValue) ->
  {Render.context_draft_kind(Context.EnteredWorkspace{workspace}, sandbox, approval) == "custom" : String}:
  {==}

type Requirements is Type:
  Requirements{
    directory_production: @+key: String -> @label: String -> @role: UI.Role -> @+path: String -> @+primary: Bool -> @source: +List<UI.Node> -> @+children: +List<Doc.Node> -> @+visual: Design.Style -> @representation: Controls.Representation -> @appearances: +List<Design.Appearance> ->
      {Render.match_node(key, label, role, UI.DirectoryRow{path, primary}, source, children, visual, representation, appearances) ==
    Render.directory_row_node(key, path, primary, visual, children) : Doc.Node},
    directory_identity: @+key: String -> @+path: String -> @+primary: Bool -> @+visual: Design.Style -> @+children: +List<Doc.Node> ->
      directory_identity_law(key, path, primary, visual, children),
    directory_full_path: @+key: String -> @+path: String ->
      directory_full_path_law(key, path),
    choice_binding_retained: @+key: String -> @+tag: String -> @+attrs: +List<Doc.Property> -> @+styles: +List<Doc.Property> -> @+events: +List<Doc.Event> -> @children: +List<Doc.Node> -> @+label: String -> @+description: String -> @+selected: Bool ->
      choice_binding_retained_law(key, tag, attrs, styles, events, children, label, description, selected),
    choice_group_production: @+key: String -> @+label: String -> @role: UI.Role -> @source: +List<UI.Node> -> @+children: +List<Doc.Node> -> @+visual: Design.Style -> @representation: Controls.Representation -> @appearances: +List<Design.Appearance> ->
      {Render.match_node(key, label, role, UI.ChoiceGroup{}, source, children, visual, representation, appearances) ==
    Render.choice_group_node(key, label, visual, children) : Doc.Node},
    summary_production: @+key: String -> @+label: String -> @+role: UI.Role -> @+observation: Context.Observation -> @source: +List<UI.Node> -> @+children: +List<Doc.Node> -> @+visual: Design.Style -> @representation: Controls.Representation -> @+appearances: +List<Design.Appearance> ->
      {Render.match_node(key, label, role, UI.ContextSummary{observation}, source, children, visual, representation, appearances) ==
    Render.context_summary_node(key, label, role, observation, visual, children, appearances) : Doc.Node},
    summary_passive_facts: @+key: String -> @+label: String -> @role: UI.Role -> @+observation: Context.Observation -> @+visual: Design.Style -> @+children: +List<Doc.Node> -> @appearances: +List<Design.Appearance> ->
      summary_passive_facts_law(key, label, role, observation, visual, children, appearances),
    committed_provenance: @context: Context.EffectiveContext ->
      {Render.context_observation_kind(Context.CommittedExecution{context}) == "committed" : String},
    unavailable_provenance: @reason: String ->
      {Render.context_observation_kind(Context.DraftExecution{Context.ContextUnavailable{reason}}) == "unavailable" : String},
    inherited_provenance: @origin: Context.Origin -> @project: Maybe<&2, Nat> -> @workspace: Domain.Workspace -> @sandbox: Domain.Sandbox -> @approval: Domain.ApprovalPolicy -> @guidance: Context.GuidancePreview ->
      {Render.context_observation_kind(Context.DraftExecution{Context.ProspectiveContext{origin, project,
    Context.InheritedWorkspace{workspace}, Context.InheritedSandbox{sandbox}, Context.InheritedApproval{approval}, guidance}}) == "inherited" : String},
    workspace_label: @+label: String -> @expanded: Bool ->
      {Controls.face_for(Controls.WorkspacePicker{expanded}, label, Controls.ComposerArea{}) == Controls.PickerFace{Some{Controls.Folder{}}, label} : Controls.Face},
    permissions_label: @+label: String -> @current: Controls.Face -> @+execution: Maybe<&2, Context.Observation> ->
      {Controls.composer_face(View.PermissionsSubject{}, label, current, execution) == Controls.permission_face(execution) : Controls.Face},
    approval_canonical: @+value: Context.ApprovalValue ->
      {Render.approval_text(value) == Context.approval_option(Context.observed_approval(value)) : String},
    choice_content_projection: @+key: String -> @+label: String -> @+description: String -> @+selected: Bool ->
      choice_content_projection_law(key, label, description, selected),
    choice_group_native: @+key: String -> @+label: String -> @+visual: Design.Style -> @+children: +List<Doc.Node> ->
      choice_group_native_law(key, label, visual, children),
    custom_workspace_provenance: @workspace: Domain.Workspace -> @sandbox: Context.SandboxValue -> @approval: Context.ApprovalValue ->
      {Render.context_draft_kind(Context.EnteredWorkspace{workspace}, sandbox, approval) == "custom" : String}}

def evidence() -> Requirements:
  Requirements{directory_production, directory_identity, directory_full_path, choice_binding_retained, choice_group_production, summary_production, summary_passive_facts, committed_provenance, unavailable_provenance, inherited_provenance, workspace_label, permissions_label, approval_canonical, choice_content_projection, choice_group_native, custom_workspace_provenance}
