import Base
import ../core/ui-identity.bend as UIIdentity
import ../core/form-fields.bend as Forms
import ../core/field-options.bend as Options
import ../core/interface.bend as InterfaceView
import ../core/user-input.bend as User
import ../BOARD.bend as Board
import ./controls.bend as Controls
import ./browser.bend as Browser

def labels_in_fields(values: +List<Forms.FieldScene>) -> Maybe<&2, Forms.Entry>:
  match values:
    case Nil{}: None{}
    case Con{Forms.FieldScene{Forms.CardLabels{}, label, entry}, rest}: Some{entry}
    case Con{other, rest}: labels_in_fields(rest)

def labels_or_rest(found: Maybe<&2, Forms.Entry>, rest: Maybe<&2, Forms.Entry>) -> Maybe<&2, Forms.Entry>:
  match found:
    case Some{entry}: Some{entry}
    case None{}: rest

def labels_in_sections(values: +List<Forms.Section>) -> Maybe<&2, Forms.Entry>:
  match values:
    case Nil{}: None{}
    case Con{Forms.Section{label, fields}, rest}: labels_or_rest(labels_in_fields(fields), labels_in_sections(rest))

type Requirements is Type:
  Requirements{
    labels_structure: @id:Maybe<&2, Nat> -> @revision:Nat -> @draft:Board.Draft -> @assist:Bool -> @profile:String -> @keep_open:Bool ->
      {labels_in_sections(Forms.structure(User.Card{id, revision, draft, assist, profile, keep_open})) == Some{Forms.Multiline{}} : Maybe<&2, Forms.Entry>},
    labels_text_edit: @editor:User.Editor -> @value:Forms.Observed -> @text:String -> @state:Browser.State ->
      {Browser.field_text(editor, Forms.CardLabels{}, Forms.Multiline{}, value, text, state) ==
    Some{InterfaceView.Change{Forms.Strings{String.split(text, Chr{10})}}} : Maybe<&2, InterfaceView.Gesture>},
    labels_update: @values:+List<String> -> @title:String -> @description:String -> @stage:Board.Stage -> @priority:Board.Priority -> @owner:Board.Owner -> @project:Maybe<&2, Nat> -> @previous:+List<String> -> @attachments:+List<Board.Attachment> ->
      {User.patch_card(Board.Patch{None{}, None{}, None{}, None{}, None{}, None{}, Some{values}, None{}},
          Board.Draft{title, description, stage, priority, owner, project, previous, attachments}) ==
          Board.Draft{title, description, stage, priority, owner, project, values, attachments} : Board.Draft},
    labels_edit: @values:+List<String> ->
      {Forms.edit(Forms.CardLabels{}, Forms.Strings{values}) ==
    Some{User.WriteCard{Board.Patch{None{}, None{}, None{}, None{}, None{}, None{}, Some{values}, None{}}}} : Maybe<&2, User.Edit>},
    labels_representation: @choices:+List<Forms.ChoiceValue> -> @key:UIIdentity.Key -> @editor:User.Editor -> @values:+List<String> -> @label:String -> @role:InterfaceView.Role -> @context:Controls.Context ->
      {Controls.represent(key, InterfaceView.Edit{editor, Forms.CardLabels{}, Forms.Multiline{}, Forms.TextsValue{values}, choices}, label, role, context) ==
          Controls.Input{InterfaceView.Edit{editor, Forms.CardLabels{}, Forms.Multiline{}, Forms.TextsValue{values}, choices}, label,
            Controls.TextArea{}, Controls.AboveInput{}, Controls.field_availability(Forms.Multiline{})} : Controls.Representation},
    labels_observation: @values:+List<String> ->
      {Options.observed(Forms.TextsValue{values}) == Options.joined(values) : String},
    assistance_representation: @choices:+List<Forms.ChoiceValue> -> @key:UIIdentity.Key -> @editor:User.Editor -> @enabled:Bool -> @profile:String -> @label:String -> @role:InterfaceView.Role -> @context:Controls.Context ->
      {Controls.represent(key, InterfaceView.Edit{editor, Forms.AssistedCapture{}, Forms.Choice{}, Forms.AssistanceValue{enabled, profile}, choices}, label, role, context) ==
          Controls.Input{InterfaceView.Edit{editor, Forms.AssistedCapture{}, Forms.Choice{}, Forms.AssistanceValue{enabled, profile}, choices}, label,
            Controls.ToggleInput{}, Controls.BesideInput{}, Controls.field_availability(Forms.Choice{})} : Controls.Representation},
    assistance_profile_representation: @choices:+List<Forms.ChoiceValue> -> @key:UIIdentity.Key -> @editor:User.Editor -> @enabled:Bool -> @profile:String -> @label:String -> @role:InterfaceView.Role -> @context:Controls.Context ->
      {Controls.represent(key, InterfaceView.Edit{editor, Forms.AssistanceProfile{}, Forms.Choice{}, Forms.AssistanceValue{enabled, profile}, choices}, label, role, context) ==
          Controls.Input{InterfaceView.Edit{editor, Forms.AssistanceProfile{}, Forms.Choice{}, Forms.AssistanceValue{enabled, profile}, choices}, label,
            Controls.SelectInput{}, Controls.AboveInput{}, Controls.field_availability(Forms.Choice{})} : Controls.Representation},
    assistance_gesture: @choices:+List<Forms.ChoiceValue> -> @key:UIIdentity.Key -> @semantic:String -> @label:String -> @role:InterfaceView.Role -> @editor:User.Editor -> @previous:Bool -> @profile:String -> @children:+List<InterfaceView.Node> -> @enabled:Bool ->
      {Browser.toggle_gesture(Some{InterfaceView.Node{key, semantic, label, role,
          InterfaceView.Edit{editor, Forms.AssistedCapture{}, Forms.Choice{}, Forms.AssistanceValue{previous, profile}, choices}, children}}, enabled) ==
          Some{InterfaceView.Change{Forms.Assistance{enabled, profile}}} : Maybe<&2, InterfaceView.Gesture>},
    assistance_preserves_profile: @enabled:Bool -> @selected:String -> @previous:Bool -> @profile:String ->
      {Forms.card_edit(Forms.AssistedCapture{}, Forms.Assistance{enabled, selected}, previous, profile) ==
    Some{User.ConfigureCardAssistance{enabled, profile}} : Maybe<&2, User.Edit>},
    profile_preserves_assistance: @enabled:Bool -> @selected:String -> @previous:Bool -> @profile:String ->
      {Forms.card_edit(Forms.AssistanceProfile{}, Forms.Assistance{enabled, selected}, previous, profile) ==
    Some{User.ConfigureCardAssistance{previous, selected}} : Maybe<&2, User.Edit>},
    stage_choices: @stage:Board.Stage -> @rest:+List<Board.Stage> ->
      {Options.stage_options(Con{stage, rest}) ==
        Forms.ChoiceValue{Board.stage_name(stage), Board.stage_label(stage)} <> Options.stage_options(rest) : +List<Forms.ChoiceValue>},
    priority_choices: @priority:Board.Priority -> @rest:+List<Board.Priority> ->
      {Options.priority_options(Con{priority, rest}) ==
        Forms.ChoiceValue{Board.priority_name(priority), Board.priority_label(priority)} <> Options.priority_options(rest) : +List<Forms.ChoiceValue>},
    stage_choices_binding: @value:Forms.Observed ->
      {Options.field_options(Forms.CardStage{}, value) == Options.stage_options(Board.stages()) : +List<Forms.ChoiceValue>},
    priority_choices_binding: @value:Forms.Observed ->
      {Options.field_options(Forms.CardPriority{}, value) ==
        Options.priority_options(Board.priorities()) : +List<Forms.ChoiceValue>}}

law evidence:
  Requirements
