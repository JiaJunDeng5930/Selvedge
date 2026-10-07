import Base
import ../../interaction/STATE.bend as Core
import ../../interaction/INPUT.bend as U
import ../../interaction/session/MODEL.bend as E
import ../runtime/SEMANTICS.bend as Browser
import ./dismissal-laws.bend as Rule

def toggle_absent(+application: E.Application, +panel: U.Panel, +trigger: String,
  absent: {E.panel_present(Rule.application_layers(application), E.panel_target(panel)) == False{} : Bool}) ->
  {E.toggle_panel(panel, trigger, application) == E.open_panel(panel, trigger, application) : E.Decision}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
  +current: E.Application = E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}}
  Equal.cong(Bool, E.Decision, (present => E.toggle_panel_selected(present, panel, trigger, current)),
    E.panel_present(layers, E.panel_target(panel)), False{}, absent)

def toggle_present(+application: E.Application, +panel: U.Panel, +trigger: String,
  present: {E.panel_present(Rule.application_layers(application), E.panel_target(panel)) == True{} : Bool}) ->
  {E.toggle_panel(panel, trigger, application) == Rule.closed_application(application, panel, trigger) : E.Decision}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
  +current: E.Application = E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}}
  Equal.cong(Bool, E.Decision, (owned => E.toggle_panel_selected(owned, panel, trigger, current)),
    E.panel_present(layers, E.panel_target(panel)), True{}, present)

def outside_false(+identity: String, same: Bool, input: Core.Input, +state: Browser.State) ->
  {Browser.outside_permitted((same && False{}) && Browser.outside_layer_owned(identity, Browser.current_layer_key(state)), input, state) == Browser.OutsideDecision{False{}, Browser.Decision{state, Nil{}}} : Browser.OutsideDecision}:
  match same:
    case True{}: {==}
    case False{}: {==}

def Rule.evidence():
  Rule.Requirements{
    toggle_absent,
    toggle_present,
    task => trigger => {==},
    action => {==},
    action => {==},
    +kind => +content => +initial => restore => dismissal => +state => {==},
    +key => semantic => label => role => +input => +outside => +escape => children => rest => {==},
    +identity => +state => {==},
    +identity => +key => input => escape => +state => outside_false(identity, String.eq(identity, key), input, state),
    +identity => +key => +input => +outside => escape => +state => stale => Equal.cong(Bool, Browser.OutsideDecision, (same => Browser.outside_permitted((same && outside) && Browser.outside_layer_owned(identity, Browser.current_layer_key(state)), input, state)), String.eq(identity, key), False{}, stale),
    key => input => outside => +state => {==},
    key => +input => outside => +state => {==},
    +identity => +key => +input => escape => +state => owned => Equal.cong(Bool, Browser.OutsideDecision, (same => Browser.outside_permitted((same && True{}) && Browser.outside_layer_owned(identity, Browser.current_layer_key(state)), input, state)), String.eq(identity, key), True{}, owned),
    +identity => +state => {==},
    +identity => +key => +input => +outside => escape => +state => {==},
    input => +state => {==},
    +identity => initial => restore => occurrence => +input => +state => {==},
    +identity => +candidate => +state => closed => Equal.cong(Bool, Browser.OutsideDecision, (allowed => Browser.outside_completed(allowed, candidate, state)), Browser.outside_closed(identity, candidate), True{}, closed),
    +identity => +candidate => +state => retained => Equal.cong(Bool, Browser.OutsideDecision, (allowed => Browser.outside_completed(allowed, candidate, state)), Browser.outside_closed(identity, candidate), False{}, retained),
    +candidate => state => {==},
    candidate => +state => {==},
    {==},
    {==},
    {==},
    {==}}

def Rule.all_panel_policies(panel, trigger):
  match panel:
    case U.ProjectPicker{}: {==}
    case U.ObjectActions{subject}: {==}
    case U.ArchivedCards{}: {==}
    case U.BoardSettings{}: {==}
    case U.BoardFilters{}: {==}
    case U.CardDetails{card}: {==}
    case U.EditObject{editor}: {==}
    case U.TaskDetails{task}: {==}
    case U.WorkspaceConfiguration{editor}: {==}
    case U.PermissionsConfiguration{editor}: {==}
    case U.TaskContext{task}: {==}
    case U.ModelPicker{editor}: {==}
    case U.DeliveryPicker{task}: {==}
    case U.Confirm{command, title, destination}: {==}
