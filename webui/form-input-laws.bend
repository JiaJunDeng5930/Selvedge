import Base
import ../core/form-fields.bend as Forms
import ../core/interface.bend as UI
import ../core/user-input.bend as User
import ../core/user-context.bend as Context
import ../MODEL.bend as Model
import ../BOARD.bend as Board
import ./controls.bend as Controls
import ./renderer.bend as Renderer
import ./browser.bend as Browser
import ./document.bend as Doc

# Locate the actual labels field within the production form sections.
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
    Some{UI.Change{Forms.Strings{String.split(text, Chr{10})}}} : Maybe<&2, UI.Gesture>},
    labels_update: @values:+List<String> -> @title:String -> @description:String -> @stage:Board.Stage -> @priority:Board.Priority -> @owner:Board.Owner -> @project:Maybe<&2, Nat> -> @previous:+List<String> -> @attachments:+List<Board.Attachment> ->
      {User.patch_card(Board.Patch{None{}, None{}, None{}, None{}, None{}, None{}, Some{values}, None{}},
          Board.Draft{title, description, stage, priority, owner, project, previous, attachments}) ==
          Board.Draft{title, description, stage, priority, owner, project, values, attachments} : Board.Draft},
    labels_edit: @values:+List<String> ->
      {Forms.edit(Forms.CardLabels{}, Forms.Strings{values}) ==
    Some{User.WriteCard{Board.Patch{None{}, None{}, None{}, None{}, None{}, None{}, Some{values}, None{}}}} : Maybe<&2, User.Edit>},
    labels_representation: @key:String -> @editor:User.Editor -> @values:+List<String> -> @label:String -> @role:UI.Role -> @context:Controls.Context ->
      {Controls.represent(key, UI.Edit{editor, Forms.CardLabels{}, Forms.Multiline{}, Forms.TextsValue{values}}, label, role, context) ==
          Controls.Input{UI.Edit{editor, Forms.CardLabels{}, Forms.Multiline{}, Forms.TextsValue{values}}, label,
            Controls.TextArea{}, Controls.AboveInput{}, Controls.field_availability(Forms.Multiline{})} : Controls.Representation},
    labels_observation: @values:+List<String> ->
      {Renderer.observed(Forms.TextsValue{values}) == Renderer.joined(values) : String},
    assistance_representation: @key:String -> @editor:User.Editor -> @enabled:Bool -> @profile:String -> @label:String -> @role:UI.Role -> @context:Controls.Context ->
      {Controls.represent(key, UI.Edit{editor, Forms.AssistedCapture{}, Forms.Choice{}, Forms.AssistanceValue{enabled, profile}}, label, role, context) ==
          Controls.Input{UI.Edit{editor, Forms.AssistedCapture{}, Forms.Choice{}, Forms.AssistanceValue{enabled, profile}}, label,
            Controls.ToggleInput{}, Controls.BesideInput{}, Controls.field_availability(Forms.Choice{})} : Controls.Representation},
    assistance_profile_representation: @key:String -> @editor:User.Editor -> @enabled:Bool -> @profile:String -> @label:String -> @role:UI.Role -> @context:Controls.Context ->
      {Controls.represent(key, UI.Edit{editor, Forms.AssistanceProfile{}, Forms.Choice{}, Forms.AssistanceValue{enabled, profile}}, label, role, context) ==
          Controls.Input{UI.Edit{editor, Forms.AssistanceProfile{}, Forms.Choice{}, Forms.AssistanceValue{enabled, profile}}, label,
            Controls.SelectInput{}, Controls.AboveInput{}, Controls.field_availability(Forms.Choice{})} : Controls.Representation},
    assistance_checked: @editor:User.Editor -> @enabled:Bool -> @profile:String ->
      {Renderer.checked_properties(UI.Edit{editor, Forms.AssistedCapture{}, Forms.Choice{}, Forms.AssistanceValue{enabled, profile}}) ==
    Renderer.checked_property(enabled) : +List<Doc.Property>},
    assistance_event: @key:String ->
      {Renderer.input_events(key, Controls.ToggleInput{}) == [Doc.EditToggle{key}] : +List<Doc.Event>},
    assistance_gesture: @key:String -> @semantic:String -> @label:String -> @role:UI.Role -> @editor:User.Editor -> @previous:Bool -> @profile:String -> @children:+List<UI.Node> -> @enabled:Bool ->
      {Browser.toggle_gesture(Some{UI.Node{key, semantic, label, role,
          UI.Edit{editor, Forms.AssistedCapture{}, Forms.Choice{}, Forms.AssistanceValue{previous, profile}}, children}}, enabled) ==
          Some{UI.Change{Forms.Assistance{enabled, profile}}} : Maybe<&2, UI.Gesture>},
    assistance_preserves_profile: @enabled:Bool -> @selected:String -> @previous:Bool -> @profile:String ->
      {Forms.card_edit(Forms.AssistedCapture{}, Forms.Assistance{enabled, selected}, previous, profile) ==
    Some{User.ConfigureCardAssistance{enabled, profile}} : Maybe<&2, User.Edit>},
    profile_preserves_assistance: @enabled:Bool -> @selected:String -> @previous:Bool -> @profile:String ->
      {Forms.card_edit(Forms.AssistanceProfile{}, Forms.Assistance{enabled, selected}, previous, profile) ==
    Some{User.ConfigureCardAssistance{previous, selected}} : Maybe<&2, User.Edit>},
    stage_option: @key:String -> @stage:Board.Stage -> @rest:+List<Board.Stage> ->
      {Renderer.stage_options(key, Con{stage, rest}) ==
    Renderer.option(key, Board.stage_name(stage), Board.stage_label(stage)) <> Renderer.stage_options(key, rest) : +List<Doc.Node>},
    priority_option: @key:String -> @priority:Board.Priority -> @rest:+List<Board.Priority> ->
      {Renderer.priority_options(key, Con{priority, rest}) ==
    Renderer.option(key, Board.priority_name(priority), Board.priority_label(priority)) <> Renderer.priority_options(key, rest) : +List<Doc.Node>},
    stage_options_binding: @key:String -> @value:Forms.Observed ->
      {Renderer.field_options(key, Forms.CardStage{}, value) == Renderer.stage_options(key, Board.stages()) : +List<Doc.Node>},
    priority_options_binding: @key:String -> @value:Forms.Observed ->
      {Renderer.field_options(key, Forms.CardPriority{}, value) ==
    Renderer.priority_options(key, [Board.NoPriority{}, Board.Low{}, Board.Medium{}, Board.High{}, Board.Urgent{}]) : +List<Doc.Node>}}

def evidence() -> Requirements:
  Requirements{
    id => revision => draft => assist => profile => keep_open => {==},
    editor => value => +text => state => {==},
    values => title => description => stage => priority => owner => project => previous => attachments => {==},
    values => {==},
    key => editor => values => label => role => context => {==},
    values => {==},
    key => editor => enabled => profile => label => role => context => {==},
    key => editor => enabled => profile => label => role => context => {==},
    editor => enabled => profile => {==},
    key => {==},
    key => semantic => label => role => editor => previous => profile => children => enabled => {==},
    enabled => selected => previous => profile => {==},
    enabled => selected => previous => profile => {==},
    key => stage => rest => {==},
    key => priority => rest => {==},
    key => value => {==},
    key => value => {==}}
