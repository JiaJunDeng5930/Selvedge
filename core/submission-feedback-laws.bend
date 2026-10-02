import Base
import ./interface.bend as Interface
import ./user-input.bend as U
import ./ui-world.bend as View
import ./SYSTEM.bend as Core
import ./user-context.bend as Context
import ./form-fields.bend as Forms
import ../bendlib/json.bend as J

def rejected_feedback(+parent: String, revision: Nat, +reason: String) ->
  {Interface.feedback_nodes(parent, U.Rejected{revision, reason}) ==
    [Interface.Node{parent ++ "/feedback", "submission-feedback", "Submission failed", Interface.Alert{}, Interface.ReadOnly{reason}, Nil{}}] : +List<Interface.Node>}:
  {==}

def editing_no_stale(parent: String) ->
  {Interface.feedback_nodes(parent, U.Editing{}) == Nil{} : +List<Interface.Node>}:
  {==}

def accepted_no_stale(parent: String, revision: Nat, reply: J.Json) ->
  {Interface.feedback_nodes(parent, U.Accepted{revision, reply}) == Nil{} : +List<Interface.Node>}:
  {==}

def editor_rejected_visible(+identity: U.Editor, revision: Nat, groups: +List<View.InputGroup>, +structure: +List<Forms.Section>,
  +submit: View.ControlDeclaration, submitted: Nat, +reason: String, pending: Bool, +parent: String, +state: Core.State) ->
  {Interface.editor(Some{View.EditorScene{identity, revision, groups, structure, submit, U.Rejected{submitted, reason}, pending}}, parent, state) ==
    List.append(&2, Interface.Node, Interface.sections(structure, identity, parent, 0n, state),
      [Interface.Node{parent ++ "/feedback", "submission-feedback", "Submission failed", Interface.Alert{}, Interface.ReadOnly{reason}, Nil{}}, Interface.declared(parent, submit, state)]) : +List<Interface.Node>}:
  {==}

def composer_rejected_visible(+identity: U.Editor, revision: Nat, message: U.Text, +footer: +List<View.ComposerControl>,
  context: Maybe<&2, Context.Observation>, +submit: View.ControlDeclaration, submitted: Nat, +reason: String, pending: Bool, +parent: String, +state: Core.State) ->
  {Interface.composer(Some{View.ComposerScene{identity, revision, message, footer, context, submit, U.Rejected{submitted, reason}, pending}}, parent, state) ==
    [Interface.Node{parent ++ "/composer/" ++ U.editor_key(identity), "composer/" ++ U.editor_key(identity), "Message", Interface.Composer{}, Interface.Region{},
      Interface.field_node(Forms.FieldScene{Forms.MessageText{}, "Message", Forms.Multiline{}}, identity, parent ++ "/composer/" ++ U.editor_key(identity), state) <>
        [Interface.Node{(parent ++ "/composer/" ++ U.editor_key(identity)) ++ "/feedback", "submission-feedback", "Submission failed", Interface.Alert{}, Interface.ReadOnly{reason}, Nil{}},
         Interface.composer_actions(footer, submit, parent ++ "/composer/" ++ U.editor_key(identity), state)]}] : +List<Interface.Node>}:
  {==}

type Requirements is Type:
  Requirements{
    rejected_feedback: @+parent:String -> @revision:Nat -> @+reason:String ->
      {Interface.feedback_nodes(parent, U.Rejected{revision, reason}) ==
    [Interface.Node{parent ++ "/feedback", "submission-feedback", "Submission failed", Interface.Alert{}, Interface.ReadOnly{reason}, Nil{}}] : +List<Interface.Node>},
    editing_no_stale: @parent:String ->
      {Interface.feedback_nodes(parent, U.Editing{}) == Nil{} : +List<Interface.Node>},
    accepted_no_stale: @parent:String -> @revision:Nat -> @reply:J.Json ->
      {Interface.feedback_nodes(parent, U.Accepted{revision, reply}) == Nil{} : +List<Interface.Node>},
    editor_rejected_visible: @+identity:U.Editor -> @revision:Nat -> @groups:+List<View.InputGroup> -> @+structure:+List<Forms.Section> -> @+submit:View.ControlDeclaration -> @submitted:Nat -> @+reason:String -> @pending:Bool -> @+parent:String -> @+state:Core.State ->
      {Interface.editor(Some{View.EditorScene{identity, revision, groups, structure, submit, U.Rejected{submitted, reason}, pending}}, parent, state) ==
    List.append(&2, Interface.Node, Interface.sections(structure, identity, parent, 0n, state),
      [Interface.Node{parent ++ "/feedback", "submission-feedback", "Submission failed", Interface.Alert{}, Interface.ReadOnly{reason}, Nil{}}, Interface.declared(parent, submit, state)]) : +List<Interface.Node>},
    composer_rejected_visible: @+identity:U.Editor -> @revision:Nat -> @message:U.Text -> @+footer:+List<View.ComposerControl> -> @context:Maybe<&2, Context.Observation> -> @+submit:View.ControlDeclaration -> @submitted:Nat -> @+reason:String -> @pending:Bool -> @+parent:String -> @+state:Core.State ->
      {Interface.composer(Some{View.ComposerScene{identity, revision, message, footer, context, submit, U.Rejected{submitted, reason}, pending}}, parent, state) ==
    [Interface.Node{parent ++ "/composer/" ++ U.editor_key(identity), "composer/" ++ U.editor_key(identity), "Message", Interface.Composer{}, Interface.Region{},
      Interface.field_node(Forms.FieldScene{Forms.MessageText{}, "Message", Forms.Multiline{}}, identity, parent ++ "/composer/" ++ U.editor_key(identity), state) <>
        [Interface.Node{(parent ++ "/composer/" ++ U.editor_key(identity)) ++ "/feedback", "submission-feedback", "Submission failed", Interface.Alert{}, Interface.ReadOnly{reason}, Nil{}},
         Interface.composer_actions(footer, submit, parent ++ "/composer/" ++ U.editor_key(identity), state)]}] : +List<Interface.Node>}}

def evidence() -> Requirements:
  Requirements{
    parent => revision => reason => rejected_feedback(parent, revision, reason),
    parent => editing_no_stale(parent),
    parent => revision => reply => accepted_no_stale(parent, revision, reply),
    identity => revision => groups => structure => submit => submitted => reason => pending => parent => state => editor_rejected_visible(identity, revision, groups, structure, submit, submitted, reason, pending, parent, state),
    identity => revision => message => footer => context => submit => submitted => reason => pending => parent => state => composer_rejected_visible(identity, revision, message, footer, context, submit, submitted, reason, pending, parent, state)}
