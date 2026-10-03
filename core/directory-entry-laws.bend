import Base
import ./client-services.bend as Services
import ../MODEL.bend as M
import ../bendlib/domain.bend as D
import ../bendlib/json.bend as J
import ./user-context.bend as Context
import ./user-input.bend as U
import ./user-experience.bend as E
import ./interface.bend as UI
import ./SYSTEM.bend as Core
import ./ui-world.bend as V
import ./submission-laws.bend as Submission

# Draft text is separate from the selected workspace; only confirmation changes it.
def typing(+revision: Nat, +body: U.Body, feedback: U.Feedback, old: String, +path: String, world: M.World()) ->
  {U.edit_draft(U.WriteDirectory{path}, U.Draft{revision, body, feedback, old}, world) ==
    Done{U.Draft{(revision + 1n : Nat), body, U.Editing{}, path}} : Result<&2, &2, String, U.Draft>}:
  {==}

def literal_entry(revision: Nat, body: U.Body, feedback: U.Feedback, +path: String) ->
  {UI.draft_directory(Some{U.Draft{revision, body, feedback, path}}) == path : String}:
  {==}

def browse_primary(roots: +List<String>, +path: String) ->
  {UI.browse_workspace(Some{D.Workspace{roots, Some{path}}}) == path : String}:
  {==}

def browse_no_primary(roots: +List<String>) ->
  {UI.browse_workspace(Some{D.Workspace{roots, None{}}}) == "" : String}:
  {==}

def browse_unobserved() ->
  {UI.browse_workspace(None{}) == "" : String}:
  {==}

def confirmed(+revision: Nat, +body: U.Body, feedback: U.Feedback, +path: String, +world: M.World(),
  admitted: {U.can_confirm_directory(U.Draft{revision, body, feedback, path}) == True{} : Bool}) ->
  {U.edit_draft(U.ConfirmDirectory{}, U.Draft{revision, body, feedback, path}, world) ==
    U.edited_body(U.apply_edit(U.EditWorkspace{Context.AddRoot{path}}, body, world), revision, "") : Result<&2, &2, String, U.Draft>}:
  Equal.cong(Bool, Result<&2, &2, String, U.Draft>,
    accepted => U.confirm_directory(accepted, U.Draft{revision, body, feedback, path}, world),
    U.can_confirm_directory(U.Draft{revision, body, feedback, path}), True{}, admitted)

def unconfirmed(+draft: U.Draft, +world: M.World(),
  denied: {U.can_confirm_directory(draft) == False{} : Bool}) ->
  {U.edit_draft(U.ConfirmDirectory{}, draft, world) == Done{draft} : Result<&2, &2, String, U.Draft>}:
  Equal.cong(Bool, Result<&2, &2, String, U.Draft>, accepted => U.confirm_directory(accepted, draft, world),
    U.can_confirm_directory(draft), False{}, denied)

def model_entry(revision: Nat, +text: U.Text, old_profile: String, old_reasoning: String,
  +context: Context.Configuration, feedback: U.Feedback, +entry: String, +profile: String, +reasoning: String, world: M.World()) ->
  {U.edit_draft(U.ChooseModel{profile, reasoning}, U.Draft{revision, U.NewTask{text, old_profile, old_reasoning, context}, feedback, entry}, world) ==
    Done{U.Draft{(revision + 1n : Nat), U.NewTask{text, profile, reasoning, context}, U.Editing{}, entry}} : Result<&2, &2, String, U.Draft>}:
  {==}

def project_entry_law(-revision: Nat, -text: U.Text, -profile: String, -reasoning: String,
  -context: Context.Configuration, -feedback: U.Feedback, -entry: String, -origin: Context.Origin,
  -world: M.World()) -> Type:
  {U.edit_draft(U.ConfigureContext{Context.ChooseOrigin{origin}}, U.Draft{revision, U.NewTask{text, profile, reasoning, context}, feedback, entry}, world) ==
    Done{U.Draft{(revision + 1n : Nat), U.NewTask{text, profile, reasoning, Context.edit(context, Context.ChooseOrigin{origin})}, U.Editing{}, entry}} : Result<&2, &2, String, U.Draft>}

def project_entry(revision: Nat, +text: U.Text, +profile: String, +reasoning: String,
  +context: Context.Configuration, feedback: U.Feedback, +entry: String, +origin: Context.Origin, world: M.World()) ->
  project_entry_law(revision, text, profile, reasoning, context, feedback, entry, origin, world):
  {==}


def selected_project_entry_law(-revision: Nat, -text: U.Text, -profile: String, -reasoning: String,
  -context: Context.Configuration, -feedback: U.Feedback, -entry: String, -origin: Context.Origin,
  -world: M.World(), -session: E.Session) -> Type:
  {E.begin_existing(Some{U.Draft{revision, U.NewTask{text, profile, reasoning, context}, feedback, entry}}, origin, E.Application{world, session}) ==
    E.navigate_with_attention(U.Start{}, "composer/" ++ U.editor_key(U.NewTaskEditor{}), E.Application{world, E.with_draft(session, U.Draft{(revision + 1n : Nat), U.NewTask{text, profile, reasoning, Context.edit(context, Context.ChooseOrigin{origin})}, U.Editing{}, entry})}) : E.Decision}

def selected_project_entry(+revision: Nat, +text: U.Text, +profile: String, +reasoning: String,
  +context: Context.Configuration, feedback: U.Feedback, +entry: String, +origin: Context.Origin, +world: M.World(), +session: E.Session) ->
  selected_project_entry_law(revision, text, profile, reasoning, context, feedback, entry, origin, world, session):
  {==}

def input_binding(+editor: U.Editor, text: String, +path: String) ->
  {UI.bind(UI.EnterDirectory{editor, text}, UI.Directory{path}) ==
    Some{Core.ApplicationInput{E.UserInput{U.EditDraft{editor, U.WriteDirectory{path}}}}} : Maybe<&2, Core.Input>}:
  {==}

def confirm_binding(+editor: U.Editor, text: String) ->
  {UI.bind(UI.EnterDirectory{editor, text}, UI.ConfirmDirectory{}) ==
    Some{Core.ApplicationInput{E.UserInput{U.EditDraft{editor, U.ConfirmDirectory{}}}}} : Maybe<&2, Core.Input>}:
  {==}


def button_declaration(+editor: U.Editor, +parent: String, +state: Core.State) ->
  {UI.directory_confirm(editor, parent, state) ==
    UI.declared(parent, V.ControlDeclaration{"workspace/confirm", "Add folder", V.Secondary{}, U.EditDraft{editor, U.ConfirmDirectory{}}, UI.availability(UI.directory_ready(state, editor))}, state) : UI.Node}:
  {==}

def button_activation(+editor: U.Editor) ->
  {UI.bind(UI.Activate{Core.ApplicationInput{E.UserInput{U.EditDraft{editor, U.ConfirmDirectory{}}}}, V.Available{}}, UI.Press{}) ==
    Some{Core.ApplicationInput{E.UserInput{U.EditDraft{editor, U.ConfirmDirectory{}}}}} : Maybe<&2, Core.Input>}:
  {==}


def production_noop(+draft: U.Draft, +world: M.World(), +session: E.Session,
  denied: {U.can_confirm_directory(draft) == False{} : Bool}) ->
  {E.edit_existing(U.ConfirmDirectory{}, draft, world, session) == E.unchanged(E.Application{world, session}) : E.Decision}:
  Equal.cong(Bool, E.Decision, admitted => E.confirm_found(admitted, draft, world, session),
    U.can_confirm_directory(draft), False{}, denied)


def empty_entry(revision: Nat, body: U.Body, feedback: U.Feedback, +world: M.World(), +session: E.Session) ->
  {E.edit_existing(U.ConfirmDirectory{}, U.Draft{revision, body, feedback, ""}, world, session) == E.unchanged(E.Application{world, session}) : E.Decision}:
  {==}

def unsupported_entry(revision: Nat, +body: U.Body, feedback: U.Feedback, +entry: String, +world: M.World(), +session: E.Session,
  unsupported: {U.workspace_capable(body) == False{} : Bool}) ->
  {E.edit_existing(U.ConfirmDirectory{}, U.Draft{revision, body, feedback, entry}, world, session) == E.unchanged(E.Application{world, session}) : E.Decision}:
  production_noop(U.Draft{revision, body, feedback, entry}, world, session,
    Submission.conjunction_right_false(Bool.not(String.eq(entry, "")), U.workspace_capable(body), unsupported))

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
      project_entry_law(revision, text, profile, reasoning, context, feedback, entry, origin, world),
    empty_entry: @revision:Nat -> @body:U.Body -> @feedback:U.Feedback -> @+world:M.World() -> @+session:E.Session ->
      {E.edit_existing(U.ConfirmDirectory{}, U.Draft{revision, body, feedback, ""}, world, session) == E.unchanged(E.Application{world, session}) : E.Decision},
    unsupported_entry: @revision:Nat -> @+body:U.Body -> @feedback:U.Feedback -> @+entry:String -> @+world:M.World() -> @+session:E.Session -> @unsupported:{U.workspace_capable(body) == False{} : Bool} ->
      {E.edit_existing(U.ConfirmDirectory{}, U.Draft{revision, body, feedback, entry}, world, session) == E.unchanged(E.Application{world, session}) : E.Decision},
    selected_project_entry: @+revision:Nat -> @+text:U.Text -> @+profile:String -> @+reasoning:String -> @+context:Context.Configuration -> @feedback:U.Feedback -> @+entry:String -> @+origin:Context.Origin -> @+world:M.World() -> @+session:E.Session ->
      selected_project_entry_law(revision, text, profile, reasoning, context, feedback, entry, origin, world, session),
    production_noop: @+draft:U.Draft -> @+world:M.World() -> @+session:E.Session -> @denied:{U.can_confirm_directory(draft) == False{} : Bool} ->
      {E.edit_existing(U.ConfirmDirectory{}, draft, world, session) == E.unchanged(E.Application{world, session}) : E.Decision},
    input_binding: @+editor:U.Editor -> @text:String -> @+path:String ->
      {UI.bind(UI.EnterDirectory{editor, text}, UI.Directory{path}) == Some{Core.ApplicationInput{E.UserInput{U.EditDraft{editor, U.WriteDirectory{path}}}}} : Maybe<&2, Core.Input>},
    button_declaration: @+editor:U.Editor -> @+parent:String -> @+state:Core.State ->
      {UI.directory_confirm(editor, parent, state) == UI.declared(parent, V.ControlDeclaration{"workspace/confirm", "Add folder", V.Secondary{}, U.EditDraft{editor, U.ConfirmDirectory{}}, UI.availability(UI.directory_ready(state, editor))}, state) : UI.Node},
    button_activation: @+editor:U.Editor ->
      {UI.bind(UI.Activate{Core.ApplicationInput{E.UserInput{U.EditDraft{editor, U.ConfirmDirectory{}}}}, V.Available{}}, UI.Press{}) == Some{Core.ApplicationInput{E.UserInput{U.EditDraft{editor, U.ConfirmDirectory{}}}}} : Maybe<&2, Core.Input>},
    confirm_binding: @+editor:U.Editor -> @text:String ->
      {UI.bind(UI.EnterDirectory{editor, text}, UI.ConfirmDirectory{}) == Some{Core.ApplicationInput{E.UserInput{U.EditDraft{editor, U.ConfirmDirectory{}}}}} : Maybe<&2, Core.Input>}
  }

def evidence() -> Requirements:
  Requirements{typing, literal_entry, browse_primary, browse_no_primary, browse_unobserved(), confirmed, unconfirmed, model_entry, project_entry, empty_entry, unsupported_entry, selected_project_entry, production_noop, input_binding, button_declaration, button_activation, confirm_binding}

# Service completion ownership and selection use the actual production functions.
def picker_closed(+state: Services.State) ->
  {Services.step(Services.CloseDirectoryPicker{}, state) == Services.Decision{Services.replace_directory(state, Services.NoDirectoryPicker{}), Nil{}} : Services.Decision}:
  Services.State{access, credential, settings, appearance, next, transfers, preview, picker} = state
  {==}

def picker_closed_completion(+ticket: Nat, +result: Result<&2, &2, String, Services.DirectoryCatalog>, +state: Services.State) ->
  {Services.directory_listed(Services.NoDirectoryPicker{}, ticket, result, state) == Services.Decision{state, Nil{}} : Services.Decision}:
  {==}

def picker_stale(+current: Nat, editor: U.Editor, path: String, trigger: String, +ticket: Nat,
  +result: Result<&2, &2, String, Services.DirectoryCatalog>, +state: Services.State,
  stale: {Nat.is_eq(current, ticket) == False{} : Bool}) ->
  {Services.directory_listed(Services.LoadingDirectory{current, editor, path, trigger}, ticket, result, state) == Services.Decision{state, Nil{}} : Services.Decision}:
  Equal.cong(Bool, Services.Decision, (owned => Services.finish_directory(owned, current, editor, path, trigger, result, state)),
    Nat.is_eq(current, ticket), False{}, stale)

def owned_law(-ticket: Nat, -editor: U.Editor, -entered: String, -trigger: String, -path: String,
  -parent: Maybe<&2, String>, -entries: +List<Services.DirectoryEntry>, -truncated: Bool,
  -state: Services.State) -> Type:
  {Services.finish_directory(True{}, ticket, editor, entered, trigger, Done{Services.DirectoryCatalog{path, parent, entries, truncated}}, state) ==
    Services.Decision{Services.replace_directory(state, Services.ReadyDirectory{ticket, editor, Services.DirectoryCatalog{path, parent, entries, truncated}, path, trigger}), Nil{}} : Services.Decision}

def picker_owned(ticket: Nat, +editor: U.Editor, entered: String, +trigger: String, +path: String,
  +parent: Maybe<&2, String>, +entries: +List<Services.DirectoryEntry>, +truncated: Bool, +state: Services.State) ->
  owned_law(ticket, editor, entered, trigger, path, parent, entries, truncated, state):
  {==}

def selected_catalog_law(-ticket: Nat, -editor: U.Editor, -path: String, -parent: Maybe<&2, String>,
  -entries: +List<Services.DirectoryEntry>, -truncated: Bool, -location: String, -trigger: String,
  -state: Services.State) -> Type:
  {Services.choose_directory(Services.ReadyDirectory{ticket, editor, Services.DirectoryCatalog{path, parent, entries, truncated}, location, trigger}, state) ==
    Services.Decision{Services.replace_directory(state, Services.NoDirectoryPicker{}), [Services.DirectoryChosen{editor, path}]} : Services.Decision}

def picker_catalog_selection(ticket: Nat, +editor: U.Editor, +path: String, parent: Maybe<&2, String>,
  entries: +List<Services.DirectoryEntry>, truncated: Bool, location: String, trigger: String, +state: Services.State) ->
  selected_catalog_law(ticket, editor, path, parent, entries, truncated, location, trigger, state):
  {==}

def picker_internal(editor: U.Editor, path: String) ->
  {Core.external_effect(Services.DirectoryChosen{editor, path}) == False{} : Bool}:
  {==}

def picker_bridge(+editor: U.Editor, +path: String, +application: E.Application, rest: +List<Services.Effect>) ->
  {Core.service_effects(Services.DirectoryChosen{editor, path} <> rest, application) ==
    Core.service_effects(rest, Core.directory_chosen(editor, path, application)) : E.Application}:
  {==}

def picker_unavailable(+editor: U.Editor, path: String, +application: E.Application,
  unavailable: {Core.accepts_directory(editor, application) == False{} : Bool}) ->
  {Core.directory_chosen(editor, path, application) == application : E.Application}:
  Equal.cong(Bool, E.Application,
    (accepted => Core.directory_chosen_accepted(accepted, editor, path, application)),
    Core.accepts_directory(editor, application), False{}, unavailable)

def picker_draft_bridge(+editor: U.Editor, +path: String, +application: E.Application,
  accepted: {Core.accepts_directory(editor, application) == True{} : Bool}) ->
  {Core.directory_chosen(editor, path, application) ==
    Core.attached(E.step(E.UserInput{U.EditDraft{editor, U.ConfirmDirectory{}}}, Core.attached(E.step(E.UserInput{U.EditDraft{editor, U.WriteDirectory{path}}}, application)))) : E.Application}:
  Equal.cong(Bool, E.Application,
    (allowed => Core.directory_chosen_accepted(allowed, editor, path, application)),
    Core.accepts_directory(editor, application), True{}, accepted)

type DirectoryPickerRequirements is Type:
  DirectoryPickerRequirements{
    closed: @+state:Services.State -> {Services.step(Services.CloseDirectoryPicker{}, state) == Services.Decision{Services.replace_directory(state, Services.NoDirectoryPicker{}), Nil{}} : Services.Decision},
    closed_completion: @+ticket:Nat -> @+result:Result<&2, &2, String, Services.DirectoryCatalog> -> @+state:Services.State -> {Services.directory_listed(Services.NoDirectoryPicker{}, ticket, result, state) == Services.Decision{state, Nil{}} : Services.Decision},
    stale: @+current:Nat -> @editor:U.Editor -> @path:String -> @trigger:String -> @+ticket:Nat -> @+result:Result<&2, &2, String, Services.DirectoryCatalog> -> @+state:Services.State -> @stale:{Nat.is_eq(current, ticket) == False{} : Bool} -> {Services.directory_listed(Services.LoadingDirectory{current, editor, path, trigger}, ticket, result, state) == Services.Decision{state, Nil{}} : Services.Decision},
    owned: @ticket:Nat -> @+editor:U.Editor -> @entered:String -> @+trigger:String -> @+path:String -> @+parent:Maybe<&2, String> -> @+entries:+List<Services.DirectoryEntry> -> @+truncated:Bool -> @+state:Services.State -> owned_law(ticket, editor, entered, trigger, path, parent, entries, truncated, state),
    selected_catalog: @ticket:Nat -> @+editor:U.Editor -> @+path:String -> @parent:Maybe<&2, String> -> @entries:+List<Services.DirectoryEntry> -> @truncated:Bool -> @location:String -> @trigger:String -> @+state:Services.State -> selected_catalog_law(ticket, editor, path, parent, entries, truncated, location, trigger, state),
    internal: @editor:U.Editor -> @path:String -> {Core.external_effect(Services.DirectoryChosen{editor, path}) == False{} : Bool},
    bridge: @+editor:U.Editor -> @+path:String -> @+application:E.Application -> @rest:+List<Services.Effect> -> {Core.service_effects(Services.DirectoryChosen{editor, path} <> rest, application) == Core.service_effects(rest, Core.directory_chosen(editor, path, application)) : E.Application},
    unavailable: @+editor:U.Editor -> @path:String -> @+application:E.Application -> @unavailable:{Core.accepts_directory(editor, application) == False{} : Bool} -> {Core.directory_chosen(editor, path, application) == application : E.Application},
    draft: @+editor:U.Editor -> @+path:String -> @+application:E.Application -> @accepted:{Core.accepts_directory(editor, application) == True{} : Bool} -> {Core.directory_chosen(editor, path, application) == Core.attached(E.step(E.UserInput{U.EditDraft{editor, U.ConfirmDirectory{}}}, Core.attached(E.step(E.UserInput{U.EditDraft{editor, U.WriteDirectory{path}}}, application)))) : E.Application}}

def directory_picker_requirements() -> DirectoryPickerRequirements:
  DirectoryPickerRequirements{picker_closed, picker_closed_completion, picker_stale, picker_owned, picker_catalog_selection, picker_internal, picker_bridge, picker_unavailable, picker_draft_bridge}
