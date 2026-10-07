import Base
import ./directory-entry-laws.bend as Rule
import ../services/MODEL.bend as Services
import ../../harness/MODEL.bend as M
import ../INPUT.bend as U
import ../session/MODEL.bend as E
import ../STATE.bend as Core
import ../submission/submission-proof.bend as SubmissionProof

def production_noop(+draft: U.Draft, +world: M.World(), +session: E.Session,
  denied: {U.can_confirm_directory(draft) == False{} : Bool}) ->
  {E.edit_existing(U.ConfirmDirectory{}, draft, world, session) == E.unchanged(E.Application{world, session}) : E.Decision}:
  Equal.cong(Bool, E.Decision, admitted => E.confirm_found(admitted, draft, world, session),
    U.can_confirm_directory(draft), False{}, denied)

def Rule.evidence():
  Rule.Requirements{+revision => +body => feedback => old => +path => world => {==}, revision => body => feedback => +path => {==}, roots => +path => {==}, roots => {==}, {==}, +revision => +body => feedback => +path => +world => admitted =>
      Equal.cong(Bool, Result<&2, &2, String, U.Draft>,
        accepted => U.confirm_directory(accepted, U.Draft{revision, body, feedback, path}, world),
        U.can_confirm_directory(U.Draft{revision, body, feedback, path}), True{}, admitted)
    , +draft => +world => denied =>
      Equal.cong(Bool, Result<&2, &2, String, U.Draft>, accepted => U.confirm_directory(accepted, draft, world),
        U.can_confirm_directory(draft), False{}, denied)
    , revision => +text => old_profile => old_reasoning => +context => feedback => +entry => +profile => +reasoning => world => {==}, revision => +text => +profile => +reasoning => +context => feedback => +entry => +origin => world => {==}, revision => body => feedback => +world => +session => {==}, revision => +body => feedback => +entry => +world => +session => unsupported =>
      production_noop(U.Draft{revision, body, feedback, entry}, world, session,
        SubmissionProof.conjunction_right_false(Bool.not(String.eq(entry, "")), U.workspace_capable(body), unsupported))
    , +revision => +text => +profile => +reasoning => +context => feedback => +entry => +origin => +world => +session => {==}, production_noop, +editor => text => +path => {==}, +editor => +parent => +state => {==}, +editor => {==}, +editor => text => {==}}

# Service completion ownership and selection use the actual production functions.

def picker_closed(+state: Services.State) ->
  {Services.step(Services.CloseDirectoryPicker{}, state) == Services.Decision{Services.replace_directory(state, Services.NoDirectoryPicker{}), Nil{}} : Services.Decision}:
  Services.State{access, credential, settings, appearance, next, transfers, preview, picker} = state
  {==}

def Rule.directory_picker_requirements():
  Rule.DirectoryPickerRequirements{picker_closed, +ticket => +result => +state => {==}, +current => editor => path => trigger => +ticket => +result => +state => stale =>
      Equal.cong(Bool, Services.Decision, (owned => Services.finish_directory(owned, current, editor, path, trigger, result, state)),
        Nat.is_eq(current, ticket), False{}, stale)
    , ticket => +editor => entered => +trigger => +path => +parent => +entries => +truncated => +state => {==}, ticket => +editor => +path => parent => entries => truncated => location => trigger => +state => {==}, editor => path => {==}, +editor => +path => +application => rest => {==}, +editor => path => +application => unavailable =>
      Equal.cong(Bool, E.Application,
        (accepted => Core.directory_chosen_accepted(accepted, editor, path, application)),
        Core.accepts_directory(editor, application), False{}, unavailable)
    , +editor => +path => +application => accepted =>
      Equal.cong(Bool, E.Application,
        (allowed => Core.directory_chosen_accepted(allowed, editor, path, application)),
        Core.accepts_directory(editor, application), True{}, accepted)
    }


def Rule.directory_identity_requirements():
  Rule.DirectoryIdentityRequirements{
    +path => primary => choose => remove => +parent => state => {==},
    +path => control => +parent => state => {==},
    path => primary => choose => remove => +parent => state => other => name => {==},
    path => primary => choose => remove => +parent => state => other => name => {==}}

def Rule.directory_ready_regions(ticket, editor, path, parent, entries, truncated, location, trigger):
  {==}

def Rule.directory_location_navigation_regions(ticket, editor, path, parent, entries, truncated, location, trigger):
  {==}
