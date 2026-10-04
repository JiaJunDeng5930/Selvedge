import Base
import ./interface.bend as Interface
import ./user-input.bend as U
import ./ui-world.bend as View
import ./SYSTEM.bend as Core
import ./user-context.bend as Context
import ./form-fields.bend as Forms
import ./field-options.bend as Options
import ../bendlib/json.bend as J

def expected_choices(entry: Forms.Entry, field: Forms.Field, value: Forms.Observed, groups: +List<View.InputGroup>) -> +List<Forms.ChoiceValue>:
  match entry:
    case Forms.Choice{}: Options.choices(field, value, groups)
    case Forms.MultipleChoices{}: Options.choices(field, value, groups)
    case _: Nil{}

type Requirements is Type:
  Requirements{
    field_payload: @+field:Forms.Field -> @label:String -> @+entry:Forms.Entry -> @+editor:U.Editor -> @+parent:String -> @+state:Core.State -> @+groups:+List<View.InputGroup> ->
      {Interface.field_node(Forms.FieldScene{field, label, entry}, editor, parent, state, groups) ==
        Interface.Node{parent ++ "/" ++ Forms.key(field), Forms.key(field), label, Interface.Field{},
          Interface.Edit{editor, field, Interface.actual_entry(field, entry, Interface.field_value(state, editor, field), state), Interface.field_value(state, editor, field),
            expected_choices(Interface.actual_entry(field, entry, Interface.field_value(state, editor, field), state), field, Interface.field_value(state, editor, field), groups)},
          Interface.field_children(field, editor, parent ++ "/" ++ Forms.key(field), state)} : Interface.Node},
    rejected_feedback: @+parent:String -> @revision:Nat -> @+reason:String ->
      {Interface.feedback_nodes(parent, U.Rejected{revision, reason}) ==
    [Interface.Node{parent ++ "/feedback", "submission-feedback", "Submission failed", Interface.Alert{}, Interface.ReadOnly{reason}, Nil{}}] : +List<Interface.Node>},
    editing_no_stale: @parent:String ->
      {Interface.feedback_nodes(parent, U.Editing{}) == Nil{} : +List<Interface.Node>},
    accepted_no_stale: @parent:String -> @revision:Nat -> @reply:J.Json ->
      {Interface.feedback_nodes(parent, U.Accepted{revision, reply}) == Nil{} : +List<Interface.Node>},
    editor_rejected_visible: @+identity:U.Editor -> @revision:Nat -> @groups:+List<View.InputGroup> -> @+structure:+List<Forms.Section> -> @+submit:View.ControlDeclaration -> @submitted:Nat -> @+reason:String -> @pending:Bool -> @+parent:String -> @+state:Core.State ->
      {Interface.editor(Some{View.EditorScene{identity, revision, groups, structure, submit, U.Rejected{submitted, reason}, pending}}, parent, state) ==
        List.append(&2, Interface.Node, Interface.sections(structure, identity, parent, 0n, state, groups),
          [Interface.Node{parent ++ "/feedback", "submission-feedback", "Submission failed", Interface.Alert{}, Interface.ReadOnly{reason}, Nil{}}, Interface.declared(parent, submit, state)]) : +List<Interface.Node>},
    composer_rejected_visible: @+identity:U.Editor -> @revision:Nat -> @message:U.Text -> @+footer:+List<View.ComposerControl> -> @context:Maybe<&2, Context.Observation> -> @+submit:View.ControlDeclaration -> @submitted:Nat -> @+reason:String -> @pending:Bool -> @+parent:String -> @+state:Core.State ->
      {Interface.composer(Some{View.ComposerScene{identity, revision, message, footer, context, submit, U.Rejected{submitted, reason}, pending}}, parent, state) ==
        [Interface.Node{parent ++ "/composer/" ++ U.editor_key(identity), "composer/" ++ U.editor_key(identity), "Message", Interface.Composer{}, Interface.Region{},
          Interface.field_node(Forms.FieldScene{Forms.MessageText{}, "Message", Forms.Multiline{}}, identity, parent ++ "/composer/" ++ U.editor_key(identity), state, Nil{}) <>
            [Interface.Node{(parent ++ "/composer/" ++ U.editor_key(identity)) ++ "/feedback", "submission-feedback", "Submission failed", Interface.Alert{}, Interface.ReadOnly{reason}, Nil{}},
             Interface.composer_actions(footer, submit, parent ++ "/composer/" ++ U.editor_key(identity), state)]}] : +List<Interface.Node>}}

law evidence:
  Requirements
