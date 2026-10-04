import Base
import ../../core/directory-entry-laws.bend as CoreDirectory
import ../../core/form-fields.bend as Forms
import ../../core/interface.bend as UI
import ../browser.bend as Browser
import ../renderer.bend as Renderer
import ../controls.bend as Controls
import ../document.bend as Doc
import ../directory-entry-laws.bend as Rule

def events(+key: String, face: Controls.Face) ->
  {Renderer.input_events(key, Controls.DirectoryChooser{face}) == [Doc.EditText{key}, Doc.ConfirmText{key}] : +List<Doc.Event>}:
  {==}

def composing_condition(enter: Bool, control: Bool, alt: Bool, shift: Bool, meta: Bool) ->
  {enter && False{} && Bool.not(control) && Bool.not(alt) && Bool.not(shift) && Bool.not(meta) == False{} : Bool}:
  match enter:
    case True{}: {==}
    case False{}: {==}

def absent_gesture(+found: Maybe<&2, UI.Node>, admitted: Bool,
  absent: {Browser.confirm_source(found) == None{} : Maybe<&2, UI.Gesture>}) ->
  {Browser.confirm_gesture(found, admitted) == None{} : Maybe<&2, UI.Gesture>}:
  match admitted:
    case True{}: absent
    case False{}: {==}

def Rule.evidence():
  Rule.Requirements{events, key => face => {==}, editor => +text => {==}, {==}, keyboard => control => alt => shift => meta => composing_condition(String.eq(keyboard, "Enter"), control, alt, shift, meta), found => {==}, key => semantic => label => role => editor => text => children => {==}, +key => keyboard => composing => control => alt => shift => meta => +state => absent =>
      Equal.cong(Maybe<&2, UI.Gesture>, Browser.Decision, gesture => Browser.apply_gesture(gesture, key, state),
        Browser.confirm_gesture(Browser.found_node(key, state), Browser.confirmation_key(keyboard, composing, control, alt, shift, meta)), None{},
        absent_gesture(Browser.found_node(key, state), Browser.confirmation_key(keyboard, composing, control, alt, shift, meta), absent))
    , +key => keyboard => composing => control => alt => shift => meta => +state => denied =>
      Equal.cong(Bool, Browser.Decision,
        admitted => Browser.apply_gesture(Browser.confirm_gesture(Browser.found_node(key, state), admitted), key, state),
        Browser.confirmation_key(keyboard, composing, control, alt, shift, meta), False{}, denied)
    }

def ordinary_choice(value: Forms.Observed) ->
  {Rule.selection_widget(Controls.value_widget(value, Forms.Choice{})) == True{} : Bool}:
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
  {Rule.selection_widget(Controls.widget_for(Forms.Choice{}, field, value)) == True{} : Bool}:
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

def Rule.picker_requirements():
  Rule.PickerRequirements{CoreDirectory.directory_picker_requirements(), +editor => +parent => +state => {==}, finite_choice, value => +path => {==}, +editor => +parent => +state => {==}}
