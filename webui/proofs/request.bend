import Base
import ../request.bend as Request
import ../browser.bend as Browser
import ../../MODEL.bend as M
import ../../core/user-experience.bend as E
import ../../core/user-input.bend as U
import ../../bendlib/json.bend as J
import ../../bendlib/domain.bend as D
import ../../bendlib/command-codec.bend as Codec













import ../request-laws.bend as Rule
import ./browser.bend as Proof_browser

def update_payload(id: Nat, +selected_name: Maybe<&2, String>, +selected_workspace: J.Json, guidance: +List<J.Field>) ->
  {Browser.request_payload(M.UpdateProject{id, selected_name, selected_workspace, J.Object{guidance}}) ==
    Codec.command_json(M.UpdateProject{id, selected_name, selected_workspace, J.Null{}}) : J.Json}:
  match selected_name:
    case None{}:
      match selected_workspace:
        case J.Null{}: {==}
        case J.Boolean{value}: {==}
        case J.Number{lexeme}: {==}
        case J.Text{text}: {==}
        case J.Array{items}: {==}
        case J.Object{fields}: {==}
    case Some{selected}:
      match selected_workspace:
        case J.Null{}: {==}
        case J.Boolean{value}: {==}
        case J.Number{lexeme}: {==}
        case J.Text{text}: {==}
        case J.Array{items}: {==}
        case J.Object{fields}: {==}















def unrelated_pending(+entry: Browser.Pending, +rest: +List<Browser.Pending>, +ticket: Nat,
  distinct: {Nat.is_eq(Browser.ticket_of(entry), ticket) == False{} : Bool}) ->
  {Browser.remove(entry <> rest, ticket) == entry <> Browser.remove(rest, ticket) : +List<Browser.Pending>}:
  Browser.Pending{current, completion, command, origin, status} = entry
  Equal.cong(Bool, +List<Browser.Pending>,
    (hit => Browser.choose_removed(hit, Browser.Pending{current, completion, command, origin, status}, Browser.remove(rest, ticket))),
    Nat.is_eq(current, ticket), False{}, distinct)







def confirmation_failed_world(owned: Bool, reason: String, destination: U.Route, +program: M.World(), session: E.Session) ->
  {Rule.decision_world(E.complete_confirmation(owned, D.failure("command_not_submitted", reason), destination,
    E.Application{program, session})) == program : M.World()}:
  match owned:
    case False{}: {==}
    case True{}: {==}

def rejected_world(completion: E.Completion, reason: String, +program: M.World(), +session: E.Session) ->
  {Rule.decision_world(E.complete_command(program, D.failure("command_not_submitted", reason), completion,
    E.Application{program, session})) == program : M.World()}:
  match completion:
    case E.DirectCompletion{}: {==}
    case E.DraftCompletion{draft}: {==}
    case E.ConfirmationCompletion{command, trigger, destination, occurrence}:
      E.Session{route, drafts, readers, +layers, attention, navigation, filter, now, next, pending, +previews, code, next_layer} = session
      confirmation_failed_world(E.confirmation_owned(layers, command, trigger, occurrence), reason, destination, program,
        E.retain_previews(E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code, next_layer}, program))

def omission_step(+same: Bool, +name: String, +value: J.Json, +rest: +List<J.Field>,
  matching: {String.eq(name, "guidance") == same : Bool},
  absent: {J.find(rest, "guidance") == J.Null{} : J.Json}) ->
  {J.find(Request.kept_field(same, J.Field{name, value}, rest), "guidance") == J.Null{} : J.Json}:
  match same:
    case True{}: absent
    case False{}:
      Equal.trans(J.Json,
        J.choose_field(String.eq(name, "guidance"), value, J.find(rest, "guidance")),
        J.choose_field(False{}, value, J.find(rest, "guidance")), J.Null{},
        Equal.cong(Bool, J.Json, (hit => J.choose_field(hit, value, J.find(rest, "guidance"))),
          String.eq(name, "guidance"), False{}, matching), absent)

def owned_field_absent(+fields: +List<J.Field>) ->
  {J.find(Request.without_guidance(fields), "guidance") == J.Null{} : J.Json}:
  match fields:
    case Nil{}: {==}
    case Con{J.Field{+name, +value}, +rest}:
      omission_step(String.eq(name, "guidance"), name, value, Request.without_guidance(rest), {==}, owned_field_absent(rest))

def Rule.evidence():
  Rule.Requirements{rejected_world, owned_field_absent, profile => reasoning => message => fields => {==}, id => count => messages => fields => {==}, name => workspace => guidance => {==}, update_payload, id => revision => name => profile => reasoning => instructions => fields => concurrency => {==}, +name => +value => +rest => unrelated =>
      Equal.cong(Bool, +List<J.Field>,
        (owned => Request.kept_field(owned, J.Field{name, value}, Request.without_guidance(rest))),
        String.eq(name, "guidance"), False{}, unrelated)
    ,
    ticket => completion => command => origin => status => reason => web => sequence => next => pending => {==}, +ticket => reason => +pending => web => sequence => next => stale =>
      Equal.cong(Maybe<&2, Browser.Pending>, Browser.Decision,
        (found => Browser.rejected_pending(found, reason, Browser.State{web, sequence, next, pending, None{}})),
        Browser.find(pending, ticket), None{}, stale)
    , +pending => +ticket => Proof_browser.consumed_ticket(pending, ticket), unrelated_pending, revision => body => feedback => directory_entry => submitted => reason => {==}, ticket => reason => web => sequence => next => pending => {==}, id => message => {==}}
