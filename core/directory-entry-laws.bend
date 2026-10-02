import Base
import ../MODEL.bend as M
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

def project_entry(revision: Nat, +text: U.Text, +profile: String, +reasoning: String,
  +context: Context.Configuration, feedback: U.Feedback, +entry: String, +origin: Context.Origin, world: M.World()) ->
  {U.edit_draft(U.ConfigureContext{Context.ChooseOrigin{origin}}, U.Draft{revision, U.NewTask{text, profile, reasoning, context}, feedback, entry}, world) ==
    Done{U.Draft{(revision + 1n : Nat), U.NewTask{text, profile, reasoning, Context.edit(context, Context.ChooseOrigin{origin})}, U.Editing{}, entry}} : Result<&2, &2, String, U.Draft>}:
  {==}


def selected_project_entry(+revision: Nat, +text: U.Text, +profile: String, +reasoning: String,
  +context: Context.Configuration, feedback: U.Feedback, +entry: String, +origin: Context.Origin, +world: M.World(), +session: E.Session) ->
  {E.begin_existing(Some{U.Draft{revision, U.NewTask{text, profile, reasoning, context}, feedback, entry}}, origin, E.Application{world, session}) ==
    E.navigate_with_attention(U.Start{}, "composer/" ++ U.editor_key(U.NewTaskEditor{}), E.Application{world, E.with_draft(session, U.Draft{(revision + 1n : Nat), U.NewTask{text, profile, reasoning, Context.edit(context, Context.ChooseOrigin{origin})}, U.Editing{}, entry})}) : E.Decision}:
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
    confirmed: @+revision:Nat -> @+body:U.Body -> @feedback:U.Feedback -> @+path:String -> @+world:M.World() ->
      @admitted:{U.can_confirm_directory(U.Draft{revision, body, feedback, path}) == True{} : Bool} ->
      {U.edit_draft(U.ConfirmDirectory{}, U.Draft{revision, body, feedback, path}, world) == U.edited_body(U.apply_edit(U.EditWorkspace{Context.AddRoot{path}}, body, world), revision, "") : Result<&2, &2, String, U.Draft>},
    unconfirmed: @+draft:U.Draft -> @+world:M.World() -> @denied:{U.can_confirm_directory(draft) == False{} : Bool} ->
      {U.edit_draft(U.ConfirmDirectory{}, draft, world) == Done{draft} : Result<&2, &2, String, U.Draft>},
    model_entry: @revision:Nat -> @+text:U.Text -> @old_profile:String -> @old_reasoning:String -> @+context:Context.Configuration -> @feedback:U.Feedback -> @+entry:String -> @+profile:String -> @+reasoning:String -> @world:M.World() ->
      {U.edit_draft(U.ChooseModel{profile, reasoning}, U.Draft{revision, U.NewTask{text, old_profile, old_reasoning, context}, feedback, entry}, world) == Done{U.Draft{(revision + 1n : Nat), U.NewTask{text, profile, reasoning, context}, U.Editing{}, entry}} : Result<&2, &2, String, U.Draft>},
    project_entry: @revision:Nat -> @+text:U.Text -> @+profile:String -> @+reasoning:String -> @+context:Context.Configuration -> @feedback:U.Feedback -> @+entry:String -> @+origin:Context.Origin -> @world:M.World() ->
      {U.edit_draft(U.ConfigureContext{Context.ChooseOrigin{origin}}, U.Draft{revision, U.NewTask{text, profile, reasoning, context}, feedback, entry}, world) == Done{U.Draft{(revision + 1n : Nat), U.NewTask{text, profile, reasoning, Context.edit(context, Context.ChooseOrigin{origin})}, U.Editing{}, entry}} : Result<&2, &2, String, U.Draft>},
    empty_entry: @revision:Nat -> @body:U.Body -> @feedback:U.Feedback -> @+world:M.World() -> @+session:E.Session ->
      {E.edit_existing(U.ConfirmDirectory{}, U.Draft{revision, body, feedback, ""}, world, session) == E.unchanged(E.Application{world, session}) : E.Decision},
    unsupported_entry: @revision:Nat -> @+body:U.Body -> @feedback:U.Feedback -> @+entry:String -> @+world:M.World() -> @+session:E.Session -> @unsupported:{U.workspace_capable(body) == False{} : Bool} ->
      {E.edit_existing(U.ConfirmDirectory{}, U.Draft{revision, body, feedback, entry}, world, session) == E.unchanged(E.Application{world, session}) : E.Decision},
    selected_project_entry: @+revision:Nat -> @+text:U.Text -> @+profile:String -> @+reasoning:String -> @+context:Context.Configuration -> @feedback:U.Feedback -> @+entry:String -> @+origin:Context.Origin -> @+world:M.World() -> @+session:E.Session ->
      {E.begin_existing(Some{U.Draft{revision, U.NewTask{text, profile, reasoning, context}, feedback, entry}}, origin, E.Application{world, session}) == E.navigate_with_attention(U.Start{}, "composer/" ++ U.editor_key(U.NewTaskEditor{}), E.Application{world, E.with_draft(session, U.Draft{(revision + 1n : Nat), U.NewTask{text, profile, reasoning, Context.edit(context, Context.ChooseOrigin{origin})}, U.Editing{}, entry})}) : E.Decision},
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
  Requirements{typing, literal_entry, confirmed, unconfirmed, model_entry, project_entry, empty_entry, unsupported_entry, selected_project_entry, production_noop, input_binding, button_declaration, button_activation, confirm_binding}
