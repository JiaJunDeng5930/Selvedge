import Base
import ../IDENTITY.bend as Identity
import ../presentation/PROGRAM.bend as Interface
import ../INPUT.bend as U
import ../presentation/MODEL.bend as View
import ../STATE.bend as Core
import ./FIELDS.bend as Forms
import ./feedback-laws.bend as Rule

def choices_agreement(+entry: Forms.Entry, +field: Forms.Field, +value: Forms.Observed, +groups: +List<View.InputGroup>) ->
  {Interface.entry_choices(entry, field, value, groups) == Rule.expected_choices(entry, field, value, groups) : +List<Forms.ChoiceValue>}:
  match entry:
    case Forms.SingleLine{}: {==}
    case Forms.Multiline{}: {==}
    case Forms.Choice{}: {==}
    case Forms.MultipleChoices{}: {==}
    case Forms.DisplayOnly{}: {==}
    case Forms.PositiveInteger{}: {==}
    case Forms.DirectoryCollection{}: {==}
    case Forms.FileCollection{}: {==}

def field_payload(+field: Forms.Field, label: String, +entry: Forms.Entry, +editor: U.Editor, +parent: Identity.Key, +state: Core.State, +groups: +List<View.InputGroup>) ->
  {Interface.field_node(Forms.FieldScene{field, label, entry}, editor, parent, state, groups) ==
    Interface.Node{Identity.Part{parent, Forms.key(field)}, Forms.key(field), label, Interface.Field{},
      Interface.Edit{editor, field, Interface.actual_entry(field, entry, Interface.field_value(state, editor, field), state), Interface.field_value(state, editor, field),
        Rule.expected_choices(Interface.actual_entry(field, entry, Interface.field_value(state, editor, field), state), field, Interface.field_value(state, editor, field), groups)},
      Interface.field_children(field, editor, Identity.Part{parent, Forms.key(field)}, state)} : Interface.Node}:
  Equal.cong(+List<Forms.ChoiceValue>, Interface.Node,
    choices => Interface.Node{Identity.Part{parent, Forms.key(field)}, Forms.key(field), label, Interface.Field{},
      Interface.Edit{editor, field, Interface.actual_entry(field, entry, Interface.field_value(state, editor, field), state), Interface.field_value(state, editor, field), choices},
      Interface.field_children(field, editor, Identity.Part{parent, Forms.key(field)}, state)},
    Interface.entry_choices(Interface.actual_entry(field, entry, Interface.field_value(state, editor, field), state), field, Interface.field_value(state, editor, field), groups),
    Rule.expected_choices(Interface.actual_entry(field, entry, Interface.field_value(state, editor, field), state), field, Interface.field_value(state, editor, field), groups),
    choices_agreement(Interface.actual_entry(field, entry, Interface.field_value(state, editor, field), state), field, Interface.field_value(state, editor, field), groups))

def Rule.evidence():
  Rule.Requirements{
    field => label => entry => editor => parent => state => groups => field_payload(field, label, entry, editor, parent, state, groups),
    +parent => revision => +reason => {==},
    parent => {==},
    parent => revision => reply => {==},
    +identity => revision => groups => +structure => +submit => submitted => +reason => pending => +parent => +state => {==},
    +identity => revision => message => +footer => context => +submit => submitted => +reason => pending => +parent => +state => {==}}
