import Base
import ../core/interface.bend as UI
import ../core/user-input.bend as U
import ./browser.bend as Browser
import ./renderer.bend as Renderer
import ./controls.bend as Controls
import ./document.bend as Doc

def events(+key: String, face: Controls.Face) ->
  {Renderer.input_events(key, Controls.DirectoryChooser{face}) == [Doc.EditText{key}, Doc.ConfirmText{key}] : +List<Doc.Event>}:
  {==}


def independent_editor(key: String, face: Controls.Face) ->
  {Renderer.editor_properties(key, Controls.DirectoryChooser{face}) == Nil{} : +List<Doc.Property>}:
  {==}

def observed_value(editor: U.Editor, +text: String) ->
  {Renderer.node_value(UI.EnterDirectory{editor, text}) == text : String}:
  {==}

def enter_key() ->
  {Browser.confirmation_key("Enter", False{}, False{}, False{}, False{}, False{}) == True{} : Bool}:
  {==}

def composing_condition(enter: Bool, control: Bool, alt: Bool, shift: Bool, meta: Bool) ->
  {enter && False{} && Bool.not(control) && Bool.not(alt) && Bool.not(shift) && Bool.not(meta) == False{} : Bool}:
  match enter:
    case True{}: {==}
    case False{}: {==}

def composing_key(keyboard: String, control: Bool, alt: Bool, shift: Bool, meta: Bool) ->
  {Browser.confirmation_key(keyboard, True{}, control, alt, shift, meta) == False{} : Bool}:
  composing_condition(String.eq(keyboard, "Enter"), control, alt, shift, meta)

def denied_gesture(found: Maybe<&2, UI.Node>) ->
  {Browser.confirm_gesture(found, False{}) == None{} : Maybe<&2, UI.Gesture>}:
  {==}

def directory_gesture(key: String, semantic: String, label: String, role: UI.Role, editor: U.Editor, text: String, children: +List<UI.Node>) ->
  {Browser.confirm_gesture(Some{UI.Node{key, semantic, label, role, UI.EnterDirectory{editor, text}, children}}, True{}) == Some{UI.ConfirmDirectory{}} : Maybe<&2, UI.Gesture>}:
  {==}

def rejected_confirmation(+key: String, keyboard: String, composing: Bool, control: Bool, alt: Bool, shift: Bool, meta: Bool, +state: Browser.State,
  denied: {Browser.confirmation_key(keyboard, composing, control, alt, shift, meta) == False{} : Bool}) ->
  {Browser.confirm_text(key, keyboard, composing, control, alt, shift, meta, state) == Browser.Decision{state, Nil{}} : Browser.Decision}:
  Equal.cong(Bool, Browser.Decision,
    admitted => Browser.apply_gesture(Browser.confirm_gesture(Browser.found_node(key, state), admitted), key, state),
    Browser.confirmation_key(keyboard, composing, control, alt, shift, meta), False{}, denied)


def absent_gesture(+found: Maybe<&2, UI.Node>, admitted: Bool,
  absent: {Browser.confirm_source(found) == None{} : Maybe<&2, UI.Gesture>}) ->
  {Browser.confirm_gesture(found, admitted) == None{} : Maybe<&2, UI.Gesture>}:
  match admitted:
    case True{}: absent
    case False{}: {==}

def unmatched_confirmation(+key: String, keyboard: String, composing: Bool, control: Bool, alt: Bool, shift: Bool, meta: Bool, +state: Browser.State,
  absent: {Browser.confirm_source(Browser.found_node(key, state)) == None{} : Maybe<&2, UI.Gesture>}) ->
  {Browser.confirm_text(key, keyboard, composing, control, alt, shift, meta, state) == Browser.Decision{state, Nil{}} : Browser.Decision}:
  Equal.cong(Maybe<&2, UI.Gesture>, Browser.Decision, gesture => Browser.apply_gesture(gesture, key, state),
    Browser.confirm_gesture(Browser.found_node(key, state), Browser.confirmation_key(keyboard, composing, control, alt, shift, meta)), None{},
    absent_gesture(Browser.found_node(key, state), Browser.confirmation_key(keyboard, composing, control, alt, shift, meta), absent))

type Requirements is Type:
  Requirements{
    events: @+key:String -> @face:Controls.Face ->
      {Renderer.input_events(key, Controls.DirectoryChooser{face}) == [Doc.EditText{key}, Doc.ConfirmText{key}] : +List<Doc.Event>},
    independent_editor: @key:String -> @face:Controls.Face ->
      {Renderer.editor_properties(key, Controls.DirectoryChooser{face}) == Nil{} : +List<Doc.Property>},
    observed_value: @editor:U.Editor -> @+text:String -> {Renderer.node_value(UI.EnterDirectory{editor, text}) == text : String},
    enter_key: {Browser.confirmation_key("Enter", False{}, False{}, False{}, False{}, False{}) == True{} : Bool},
    composing_key: @keyboard:String -> @control:Bool -> @alt:Bool -> @shift:Bool -> @meta:Bool ->
      {Browser.confirmation_key(keyboard, True{}, control, alt, shift, meta) == False{} : Bool},
    denied_gesture: @found:Maybe<&2, UI.Node> -> {Browser.confirm_gesture(found, False{}) == None{} : Maybe<&2, UI.Gesture>},
    directory_gesture: @key:String -> @semantic:String -> @label:String -> @role:UI.Role -> @editor:U.Editor -> @text:String -> @children:+List<UI.Node> ->
      {Browser.confirm_gesture(Some{UI.Node{key, semantic, label, role, UI.EnterDirectory{editor, text}, children}}, True{}) == Some{UI.ConfirmDirectory{}} : Maybe<&2, UI.Gesture>},
    unmatched_confirmation: @+key:String -> @keyboard:String -> @composing:Bool -> @control:Bool -> @alt:Bool -> @shift:Bool -> @meta:Bool -> @+state:Browser.State ->
      @absent:{Browser.confirm_source(Browser.found_node(key, state)) == None{} : Maybe<&2, UI.Gesture>} ->
      {Browser.confirm_text(key, keyboard, composing, control, alt, shift, meta, state) == Browser.Decision{state, Nil{}} : Browser.Decision},
    rejected_confirmation: @+key:String -> @keyboard:String -> @composing:Bool -> @control:Bool -> @alt:Bool -> @shift:Bool -> @meta:Bool -> @+state:Browser.State ->
      @denied:{Browser.confirmation_key(keyboard, composing, control, alt, shift, meta) == False{} : Bool} ->
      {Browser.confirm_text(key, keyboard, composing, control, alt, shift, meta, state) == Browser.Decision{state, Nil{}} : Browser.Decision}
  }

def evidence() -> Requirements:
  Requirements{events, independent_editor, observed_value, enter_key(), composing_key, denied_gesture, directory_gesture, unmatched_confirmation, rejected_confirmation}
