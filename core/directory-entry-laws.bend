import Base
import ./ui-identity.bend as Identity
import ./client-services.bend as Services
import ../MODEL.bend as M
import ../bendlib/domain.bend as D
import ./user-context.bend as Context
import ./user-input.bend as U
import ./user-experience.bend as E
import ./interface.bend as UI
import ./SYSTEM.bend as Core
import ./ui-world.bend as V

type Requirements is Type:
  Requirements{
    typing: @+revision:Nat -> @+body:U.Body -> @feedback:U.Feedback -> @old:String -> @+path:String -> @world:M.World() ->
      {U.edit_draft(U.WriteDirectory{path}, U.Draft{revision, body, feedback, old}, world) == Done{U.Draft{(revision + 1n : Nat), body, U.Editing{}, path}} : Result<&2, &2, String, U.Draft>},
    literal_entry: @revision:Nat -> @body:U.Body -> @feedback:U.Feedback -> @+path:String ->
      {UI.draft_directory(Some{U.Draft{revision, body, feedback, path}}) == path : String},
    browse_primary: @roots:+List<String> -> @+path:String ->
      {UI.browse_workspace(Some{D.Workspace{roots, Some{path}}}) == path : String},
    browse_no_primary: @roots:+List<String> ->
      {UI.browse_workspace(Some{D.Workspace{roots, None{}}}) == "" : String},
    browse_unobserved: {UI.browse_workspace(None{}) == "" : String},
    confirmed: @+revision:Nat -> @+body:U.Body -> @feedback:U.Feedback -> @+path:String -> @+world:M.World() ->
      @admitted:{U.can_confirm_directory(U.Draft{revision, body, feedback, path}) == True{} : Bool} ->
      {U.edit_draft(U.ConfirmDirectory{}, U.Draft{revision, body, feedback, path}, world) == U.edited_body(U.apply_edit(U.EditWorkspace{Context.AddRoot{path}}, body, world), revision, "") : Result<&2, &2, String, U.Draft>},
    unconfirmed: @+draft:U.Draft -> @+world:M.World() -> @denied:{U.can_confirm_directory(draft) == False{} : Bool} ->
      {U.edit_draft(U.ConfirmDirectory{}, draft, world) == Done{draft} : Result<&2, &2, String, U.Draft>},
    model_entry: @revision:Nat -> @+text:U.Text -> @old_profile:String -> @old_reasoning:String -> @+context:Context.Configuration -> @feedback:U.Feedback -> @+entry:String -> @+profile:String -> @+reasoning:String -> @world:M.World() ->
      {U.edit_draft(U.ChooseModel{profile, reasoning}, U.Draft{revision, U.NewTask{text, old_profile, old_reasoning, context}, feedback, entry}, world) == Done{U.Draft{(revision + 1n : Nat), U.NewTask{text, profile, reasoning, context}, U.Editing{}, entry}} : Result<&2, &2, String, U.Draft>},
    project_entry: @revision:Nat -> @+text:U.Text -> @+profile:String -> @+reasoning:String -> @+context:Context.Configuration -> @feedback:U.Feedback -> @+entry:String -> @+origin:Context.Origin -> @world:M.World() ->
      {U.edit_draft(U.ConfigureContext{Context.ChooseOrigin{origin}}, U.Draft{revision, U.NewTask{text, profile, reasoning, context}, feedback, entry}, world) ==
        Done{U.Draft{(revision + 1n : Nat), U.NewTask{text, profile, reasoning, Context.edit(context, Context.ChooseOrigin{origin})}, U.Editing{}, entry}} : Result<&2, &2, String, U.Draft>},
    empty_entry: @revision:Nat -> @body:U.Body -> @feedback:U.Feedback -> @+world:M.World() -> @+session:E.Session ->
      {E.edit_existing(U.ConfirmDirectory{}, U.Draft{revision, body, feedback, ""}, world, session) == E.unchanged(E.Application{world, session}) : E.Decision},
    unsupported_entry: @revision:Nat -> @+body:U.Body -> @feedback:U.Feedback -> @+entry:String -> @+world:M.World() -> @+session:E.Session -> @unsupported:{U.workspace_capable(body) == False{} : Bool} ->
      {E.edit_existing(U.ConfirmDirectory{}, U.Draft{revision, body, feedback, entry}, world, session) == E.unchanged(E.Application{world, session}) : E.Decision},
    selected_project_entry: @+revision:Nat -> @+text:U.Text -> @+profile:String -> @+reasoning:String -> @+context:Context.Configuration -> @feedback:U.Feedback -> @+entry:String -> @+origin:Context.Origin -> @+world:M.World() -> @+session:E.Session ->
      {E.begin_existing(Some{U.Draft{revision, U.NewTask{text, profile, reasoning, context}, feedback, entry}}, origin, E.Application{world, session}) ==
        E.navigate_with_attention(U.Start{}, "composer/" ++ U.editor_key(U.NewTaskEditor{}), E.Application{world, E.with_draft(session, U.Draft{(revision + 1n : Nat), U.NewTask{text, profile, reasoning, Context.edit(context, Context.ChooseOrigin{origin})}, U.Editing{}, entry})}) : E.Decision},
    production_noop: @+draft:U.Draft -> @+world:M.World() -> @+session:E.Session -> @denied:{U.can_confirm_directory(draft) == False{} : Bool} ->
      {E.edit_existing(U.ConfirmDirectory{}, draft, world, session) == E.unchanged(E.Application{world, session}) : E.Decision},
    input_binding: @+editor:U.Editor -> @text:String -> @+path:String ->
      {UI.bind(UI.EnterDirectory{editor, text}, UI.Directory{path}) == Some{Core.ApplicationInput{E.UserInput{U.EditDraft{editor, U.WriteDirectory{path}}}}} : Maybe<&2, Core.Input>},
    button_declaration: @+editor:U.Editor -> @+parent: Identity.Key -> @+state:Core.State ->
      {UI.directory_confirm(editor, parent, state) == UI.declared(parent, V.ControlDeclaration{"workspace/confirm", "Add folder", V.Secondary{}, U.EditDraft{editor, U.ConfirmDirectory{}}, UI.availability(UI.directory_ready(state, editor))}, state) : UI.Node},
    button_activation: @+editor:U.Editor ->
      {UI.bind(UI.Activate{Core.ApplicationInput{E.UserInput{U.EditDraft{editor, U.ConfirmDirectory{}}}}, V.Available{}}, UI.Press{}) == Some{Core.ApplicationInput{E.UserInput{U.EditDraft{editor, U.ConfirmDirectory{}}}}} : Maybe<&2, Core.Input>},
    confirm_binding: @+editor:U.Editor -> @text:String ->
      {UI.bind(UI.EnterDirectory{editor, text}, UI.ConfirmDirectory{}) == Some{Core.ApplicationInput{E.UserInput{U.EditDraft{editor, U.ConfirmDirectory{}}}}} : Maybe<&2, Core.Input>}
  }

law evidence:
  Requirements

type DirectoryPickerRequirements is Type:
  DirectoryPickerRequirements{
    closed: @+state:Services.State -> {Services.step(Services.CloseDirectoryPicker{}, state) == Services.Decision{Services.replace_directory(state, Services.NoDirectoryPicker{}), Nil{}} : Services.Decision},
    closed_completion: @+ticket:Nat -> @+result:Result<&2, &2, String, Services.DirectoryCatalog> -> @+state:Services.State -> {Services.directory_listed(Services.NoDirectoryPicker{}, ticket, result, state) == Services.Decision{state, Nil{}} : Services.Decision},
    stale: @+current:Nat -> @editor:U.Editor -> @path:String -> @trigger:String -> @+ticket:Nat -> @+result:Result<&2, &2, String, Services.DirectoryCatalog> -> @+state:Services.State -> @stale:{Nat.is_eq(current, ticket) == False{} : Bool} -> {Services.directory_listed(Services.LoadingDirectory{current, editor, path, trigger}, ticket, result, state) == Services.Decision{state, Nil{}} : Services.Decision},
    owned: @ticket:Nat -> @+editor:U.Editor -> @entered:String -> @+trigger:String -> @+path:String -> @+parent:Maybe<&2, String> -> @+entries:+List<Services.DirectoryEntry> -> @+truncated:Bool -> @+state:Services.State -> {Services.finish_directory(True{}, ticket, editor, entered, trigger, Done{Services.DirectoryCatalog{path, parent, entries, truncated}}, state) ==
        Services.Decision{Services.replace_directory(state, Services.ReadyDirectory{ticket, editor, Services.DirectoryCatalog{path, parent, entries, truncated}, path, trigger}), Nil{}} : Services.Decision},
    selected_catalog: @ticket:Nat -> @+editor:U.Editor -> @+path:String -> @parent:Maybe<&2, String> -> @entries:+List<Services.DirectoryEntry> -> @truncated:Bool -> @location:String -> @trigger:String -> @+state:Services.State -> {Services.choose_directory(Services.ReadyDirectory{ticket, editor, Services.DirectoryCatalog{path, parent, entries, truncated}, location, trigger}, state) ==
        Services.Decision{Services.replace_directory(state, Services.NoDirectoryPicker{}), [Services.DirectoryChosen{editor, path}]} : Services.Decision},
    internal: @editor:U.Editor -> @path:String -> {Core.external_effect(Services.DirectoryChosen{editor, path}) == False{} : Bool},
    bridge: @+editor:U.Editor -> @+path:String -> @+application:E.Application -> @rest:+List<Services.Effect> -> {Core.service_effects(Services.DirectoryChosen{editor, path} <> rest, application) == Core.service_effects(rest, Core.directory_chosen(editor, path, application)) : E.Application},
    unavailable: @+editor:U.Editor -> @path:String -> @+application:E.Application -> @unavailable:{Core.accepts_directory(editor, application) == False{} : Bool} -> {Core.directory_chosen(editor, path, application) == application : E.Application},
    draft: @+editor:U.Editor -> @+path:String -> @+application:E.Application -> @accepted:{Core.accepts_directory(editor, application) == True{} : Bool} -> {Core.directory_chosen(editor, path, application) == Core.attached(E.step(E.UserInput{U.EditDraft{editor, U.ConfirmDirectory{}}}, Core.attached(E.step(E.UserInput{U.EditDraft{editor, U.WriteDirectory{path}}}, application)))) : E.Application}}

law directory_picker_requirements:
  DirectoryPickerRequirements


def spatial_identity(node: UI.Node) -> Identity.Key:
  UI.Node{key, semantic, label, role, meaning, children} = node
  key

def first_spatial_identity(nodes: +List<UI.Node>) -> Identity.Key:
  match nodes:
    case Nil{}: Identity.Place{""}
    case Con{node, rest}: spatial_identity(node)

type DirectoryIdentityRequirements is Type:
  DirectoryIdentityRequirements{
    row: @+path:String -> @primary:Bool -> @choose:V.ControlDeclaration -> @remove:V.ControlDeclaration -> @+parent:Identity.Key -> @state:Core.State ->
      {spatial_identity(UI.directory_node(V.WorkspaceRoot{path, primary, choose, remove}, parent, state)) == Identity.Entity{parent, "directory", path} : Identity.Key},
    primary: @+path:String -> @control:V.ControlDeclaration -> @+parent:Identity.Key -> @state:Core.State ->
      {first_spatial_identity(UI.directory_primary_controls(True{}, control, Identity.Entity{parent, "directory", path}, state)) == Identity.Part{Identity.Entity{parent, "directory", path}, "primary"} : Identity.Key},
    slot_not_directory: @path:String -> @primary:Bool -> @choose:V.ControlDeclaration -> @remove:V.ControlDeclaration -> @+parent:Identity.Key -> @state:Core.State -> @other:String -> @name:String ->
      {Identity.same(Identity.Part{spatial_identity(UI.directory_node(V.WorkspaceRoot{path, primary, choose, remove}, parent, state)), name}, Identity.Entity{parent, "directory", other}) == False{} : Bool},
    directory_not_slot: @path:String -> @primary:Bool -> @choose:V.ControlDeclaration -> @remove:V.ControlDeclaration -> @+parent:Identity.Key -> @state:Core.State -> @other:String -> @name:String ->
      {Identity.same(Identity.Entity{parent, "directory", other}, Identity.Part{spatial_identity(UI.directory_node(V.WorkspaceRoot{path, primary, choose, remove}, parent, state)), name}) == False{} : Bool}}

law directory_identity_requirements:
  DirectoryIdentityRequirements
