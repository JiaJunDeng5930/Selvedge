import Base
import ../../bendlib/categories.bend as Categories
import ../../bendlib/json.bend as J
import ./EFFECTS.bend as E

def E.complete_correspondence():
  operation => source => {==}
def E.process_exit_code():
  source => {==}
def E.process_signal():
  source => {==}
def E.linux_readonly_binding():
  {==}
def E.linux_writable_binding():
  {==}
def E.denial_is_not_execution_failure():
  {==}

def task_case(+kind: E.CallbackKind, +effect: J.Json, +result: J.Json) ->
  {E.task_coordinate_classified(kind, E.callback_classified(kind, effect, result)) == E.task_coordinate_classified(kind, effect) : J.Json}:
  match kind:
    case E.CallbackChatgptExec{}: {==}
    case E.CallbackBoardText{}: {==}
    case E.CallbackApproval{}: {==}
    case E.CallbackHook{}: {==}
    case E.CallbackAfterHook{}: {==}
    case E.CallbackContext{}: {==}
    case E.CallbackReasoning{}: {==}
    case E.CallbackModel{}: {==}
    case E.CallbackDefaultTool{}: {==}

def E.callback_task():
  +effect => result => task_case(E.classify_callback_kind(J.text(J.get(effect, "kind"))), effect, result)

def ticket_case(+kind: E.CallbackKind, +effect: J.Json, +result: J.Json) ->
  {E.ticket_coordinate_classified(kind, E.callback_classified(kind, effect, result)) == E.ticket_coordinate_classified(kind, effect) : J.Json}:
  match kind:
    case E.CallbackChatgptExec{}: {==}
    case E.CallbackBoardText{}: {==}
    case E.CallbackApproval{}: {==}
    case E.CallbackHook{}: {==}
    case E.CallbackAfterHook{}: {==}
    case E.CallbackContext{}: {==}
    case E.CallbackReasoning{}: {==}
    case E.CallbackModel{}: {==}
    case E.CallbackDefaultTool{}: {==}

def E.callback_ticket():
  +effect => result => ticket_case(E.classify_callback_kind(J.text(J.get(effect, "kind"))), effect, result)

def operation_case(+kind: E.CallbackKind, +effect: J.Json, +result: J.Json) ->
  {E.operation_coordinate_classified(kind, E.callback_classified(kind, effect, result)) == E.operation_coordinate_classified(kind, effect) : J.Json}:
  match kind:
    case E.CallbackChatgptExec{}: {==}
    case E.CallbackBoardText{}: {==}
    case E.CallbackApproval{}: {==}
    case E.CallbackHook{}: {==}
    case E.CallbackAfterHook{}: {==}
    case E.CallbackContext{}: {==}
    case E.CallbackReasoning{}: {==}
    case E.CallbackModel{}: {==}
    case E.CallbackDefaultTool{}: {==}

def E.callback_operation():
  +effect => result => operation_case(E.classify_callback_kind(J.text(J.get(effect, "kind"))), effect, result)

def card_case(+kind: E.CallbackKind, +effect: J.Json, +result: J.Json) ->
  {E.card_coordinate_classified(kind, E.callback_classified(kind, effect, result)) == E.card_coordinate_classified(kind, effect) : J.Json}:
  match kind:
    case E.CallbackChatgptExec{}: {==}
    case E.CallbackBoardText{}: {==}
    case E.CallbackApproval{}: {==}
    case E.CallbackHook{}: {==}
    case E.CallbackAfterHook{}: {==}
    case E.CallbackContext{}: {==}
    case E.CallbackReasoning{}: {==}
    case E.CallbackModel{}: {==}
    case E.CallbackDefaultTool{}: {==}

def E.callback_card():
  +effect => result => card_case(E.classify_callback_kind(J.text(J.get(effect, "kind"))), effect, result)

def E.environment_name_selection():
  source => {==}

def E.environment_override_selection():
  source => {==}

def E.failure_without_context_limit():
  effect => message => {==}
def E.context_limit_model_fields():
  effect => message => {==}

def context_limit_field_case(+context_limit: Bool, +kind: E.CallbackKind, +effect: J.Json, +message: String) ->
  {J.get(E.failure_context_classified(context_limit, kind, effect, message), "failure_kind") == E.failure_context_kind(context_limit, kind) : J.Json}:
  match context_limit:
    case False{}:
      match kind:
        case E.CallbackChatgptExec{}: {==}
        case E.CallbackBoardText{}: {==}
        case E.CallbackContext{}: {==}
        case E.CallbackReasoning{}: {==}
        case E.CallbackHook{}: {==}
        case E.CallbackApproval{}: {==}
        case E.CallbackAfterHook{}: {==}
        case E.CallbackModel{}: {==}
        case E.CallbackDefaultTool{}: {==}
    case True{}:
      match kind:
        case E.CallbackChatgptExec{}: {==}
        case E.CallbackBoardText{}: {==}
        case E.CallbackContext{}: {==}
        case E.CallbackReasoning{}: {==}
        case E.CallbackHook{}: {==}
        case E.CallbackApproval{}: {==}
        case E.CallbackAfterHook{}: {==}
        case E.CallbackModel{}: {==}
        case E.CallbackDefaultTool{}: {==}

def E.failure_context_limit_field():
  +effect => message => context_limit => context_limit_field_case(context_limit, E.classify_callback_kind(J.text(J.get(effect, "kind"))), effect, message)

def preserves_kind_case(+context_limit: Bool, +kind: E.CallbackKind, +effect: J.Json, +message: String) ->
  {J.get(E.failure_context_classified(context_limit, kind, effect, message), "kind") == J.get(E.failure_classified(kind, effect, message), "kind") : J.Json}:
  match context_limit:
    case False{}: {==}
    case True{}:
      match kind:
        case E.CallbackChatgptExec{}: {==}
        case E.CallbackBoardText{}: {==}
        case E.CallbackContext{}: {==}
        case E.CallbackReasoning{}: {==}
        case E.CallbackHook{}: {==}
        case E.CallbackApproval{}: {==}
        case E.CallbackAfterHook{}: {==}
        case E.CallbackModel{}: {==}
        case E.CallbackDefaultTool{}: {==}

def E.failure_preserves_kind():
  +effect => message => context_limit => preserves_kind_case(context_limit, E.classify_callback_kind(J.text(J.get(effect, "kind"))), effect, message)

def preserves_task_id_case(+context_limit: Bool, +kind: E.CallbackKind, +effect: J.Json, +message: String) ->
  {J.get(E.failure_context_classified(context_limit, kind, effect, message), "task_id") == J.get(E.failure_classified(kind, effect, message), "task_id") : J.Json}:
  match context_limit:
    case False{}: {==}
    case True{}:
      match kind:
        case E.CallbackChatgptExec{}: {==}
        case E.CallbackBoardText{}: {==}
        case E.CallbackContext{}: {==}
        case E.CallbackReasoning{}: {==}
        case E.CallbackHook{}: {==}
        case E.CallbackApproval{}: {==}
        case E.CallbackAfterHook{}: {==}
        case E.CallbackModel{}: {==}
        case E.CallbackDefaultTool{}: {==}

def E.failure_preserves_task_id():
  +effect => message => context_limit => preserves_task_id_case(context_limit, E.classify_callback_kind(J.text(J.get(effect, "kind"))), effect, message)

def preserves_ticket_case(+context_limit: Bool, +kind: E.CallbackKind, +effect: J.Json, +message: String) ->
  {J.get(E.failure_context_classified(context_limit, kind, effect, message), "ticket") == J.get(E.failure_classified(kind, effect, message), "ticket") : J.Json}:
  match context_limit:
    case False{}: {==}
    case True{}:
      match kind:
        case E.CallbackChatgptExec{}: {==}
        case E.CallbackBoardText{}: {==}
        case E.CallbackContext{}: {==}
        case E.CallbackReasoning{}: {==}
        case E.CallbackHook{}: {==}
        case E.CallbackApproval{}: {==}
        case E.CallbackAfterHook{}: {==}
        case E.CallbackModel{}: {==}
        case E.CallbackDefaultTool{}: {==}

def E.failure_preserves_ticket():
  +effect => message => context_limit => preserves_ticket_case(context_limit, E.classify_callback_kind(J.text(J.get(effect, "kind"))), effect, message)

def preserves_operation_id_case(+context_limit: Bool, +kind: E.CallbackKind, +effect: J.Json, +message: String) ->
  {J.get(E.failure_context_classified(context_limit, kind, effect, message), "operation_id") == J.get(E.failure_classified(kind, effect, message), "operation_id") : J.Json}:
  match context_limit:
    case False{}: {==}
    case True{}:
      match kind:
        case E.CallbackChatgptExec{}: {==}
        case E.CallbackBoardText{}: {==}
        case E.CallbackContext{}: {==}
        case E.CallbackReasoning{}: {==}
        case E.CallbackHook{}: {==}
        case E.CallbackApproval{}: {==}
        case E.CallbackAfterHook{}: {==}
        case E.CallbackModel{}: {==}
        case E.CallbackDefaultTool{}: {==}

def E.failure_preserves_operation_id():
  +effect => message => context_limit => preserves_operation_id_case(context_limit, E.classify_callback_kind(J.text(J.get(effect, "kind"))), effect, message)

def preserves_card_id_case(+context_limit: Bool, +kind: E.CallbackKind, +effect: J.Json, +message: String) ->
  {J.get(E.failure_context_classified(context_limit, kind, effect, message), "card_id") == J.get(E.failure_classified(kind, effect, message), "card_id") : J.Json}:
  match context_limit:
    case False{}: {==}
    case True{}:
      match kind:
        case E.CallbackChatgptExec{}: {==}
        case E.CallbackBoardText{}: {==}
        case E.CallbackContext{}: {==}
        case E.CallbackReasoning{}: {==}
        case E.CallbackHook{}: {==}
        case E.CallbackApproval{}: {==}
        case E.CallbackAfterHook{}: {==}
        case E.CallbackModel{}: {==}
        case E.CallbackDefaultTool{}: {==}

def E.failure_preserves_card_id():
  +effect => message => context_limit => preserves_card_id_case(context_limit, E.classify_callback_kind(J.text(J.get(effect, "kind"))), effect, message)

def preserves_ok_case(+context_limit: Bool, +kind: E.CallbackKind, +effect: J.Json, +message: String) ->
  {J.get(E.failure_context_classified(context_limit, kind, effect, message), "ok") == J.get(E.failure_classified(kind, effect, message), "ok") : J.Json}:
  match context_limit:
    case False{}: {==}
    case True{}:
      match kind:
        case E.CallbackChatgptExec{}: {==}
        case E.CallbackBoardText{}: {==}
        case E.CallbackContext{}: {==}
        case E.CallbackReasoning{}: {==}
        case E.CallbackHook{}: {==}
        case E.CallbackApproval{}: {==}
        case E.CallbackAfterHook{}: {==}
        case E.CallbackModel{}: {==}
        case E.CallbackDefaultTool{}: {==}

def E.failure_preserves_ok():
  +effect => message => context_limit => preserves_ok_case(context_limit, E.classify_callback_kind(J.text(J.get(effect, "kind"))), effect, message)

def preserves_message_case(+context_limit: Bool, +kind: E.CallbackKind, +effect: J.Json, +message: String) ->
  {J.get(E.failure_context_classified(context_limit, kind, effect, message), "message") == J.get(E.failure_classified(kind, effect, message), "message") : J.Json}:
  match context_limit:
    case False{}: {==}
    case True{}:
      match kind:
        case E.CallbackChatgptExec{}: {==}
        case E.CallbackBoardText{}: {==}
        case E.CallbackContext{}: {==}
        case E.CallbackReasoning{}: {==}
        case E.CallbackHook{}: {==}
        case E.CallbackApproval{}: {==}
        case E.CallbackAfterHook{}: {==}
        case E.CallbackModel{}: {==}
        case E.CallbackDefaultTool{}: {==}

def E.failure_preserves_message():
  +effect => message => context_limit => preserves_message_case(context_limit, E.classify_callback_kind(J.text(J.get(effect, "kind"))), effect, message)


def E.unrestricted_launch_complete():
  source => {==}
def E.unrestricted_launch_cwd_projection():
  cwd => {==}
def E.unrestricted_launch_file_projection():
  cwd => {==}
def E.unrestricted_launch_prefix_projection():
  cwd => {==}
def E.unrestricted_launch_owned_workspace():
  source => evidence => {==}
def E.unrestricted_launch_plan_failure():
  source => result => evidence => {==}
def E.unrestricted_launch_workspace_failure():
  source => plan_evidence => result => evidence => {==}

def unrestricted_plan_axis_evidence(+source: J.Json, evidence: E.unrestricted_category(source),
  inclusion: Categories.Inclusion<J.Json, E.unrestricted_category, Categories.holds(J.Json, (source => E.unrestricted_plan_accepted(source)))>) ->
  {E.unrestricted_plan_accepted(source) == True{} : Bool}:
  Categories.Inclusion{project} = inclusion
  project(source, evidence)

def E.unrestricted_plan_authority():
  source => evidence => unrestricted_plan_axis_evidence(source, evidence, E.unrestricted_plan_axis())

def unrestricted_workspace_axis_evidence(+source: J.Json, evidence: E.unrestricted_category(source),
  inclusion: Categories.Inclusion<J.Json, E.unrestricted_category, Categories.holds(J.Json, (source => E.unrestricted_workspace_accepted(source)))>) ->
  {E.unrestricted_workspace_accepted(source) == True{} : Bool}:
  Categories.Inclusion{project} = inclusion
  project(source, evidence)

def E.unrestricted_workspace_authority():
  source => evidence => unrestricted_workspace_axis_evidence(source, evidence, E.unrestricted_workspace_axis())

def unrestricted_access_axis_evidence(+source: J.Json, evidence: E.unrestricted_category(source),
  inclusion: Categories.Inclusion<J.Json, E.unrestricted_category, Categories.holds(J.Json, (source => E.unrestricted_access(source)))>) ->
  {E.unrestricted_access(source) == True{} : Bool}:
  Categories.Inclusion{project} = inclusion
  project(source, evidence)

def E.unrestricted_access_authority():
  source => evidence => unrestricted_access_axis_evidence(source, evidence, E.unrestricted_access_axis())
def unrestricted_checked_cwd_projection(valid: Bool, +cwd: J.Json) ->
  {J.get(J.get(E.unrestricted_launch_cwd_checked(valid, cwd), "value"), "cwd") == E.unrestricted_launch_result_cwd(valid, cwd) : J.Json}:
  match valid:
    case False{}: {==}
    case True{}: {==}

def E.unrestricted_launch_checked_cwd():
  valid => cwd => unrestricted_checked_cwd_projection(valid, cwd)
def E.unrestricted_launch_owned_cwd():
  +source => evidence => unrestricted_checked_cwd_projection(
    E.unrestricted_cwd_matches(source, E.unrestricted_workspace_cwd(source)), E.unrestricted_workspace_cwd(source))

def E.sandbox_launch_complete():
  source => {==}
def E.sandbox_prepare_complete():
  source => {==}
def E.sandbox_launch_owned_decision():
  source => evidence => {==}
def sandbox_plan_axis_evidence(+source: J.Json, evidence: E.sandbox_launch_category(source),
  inclusion: Categories.Inclusion<J.Json, E.sandbox_launch_category, Categories.holds(J.Json, (source => E.unrestricted_plan_accepted(source)))>) ->
  {E.unrestricted_plan_accepted(source) == True{} : Bool}:
  Categories.Inclusion{project} = inclusion
  project(source, evidence)
def E.sandbox_launch_plan_authority():
  source => evidence => sandbox_plan_axis_evidence(source, evidence, E.sandbox_launch_plan_axis())
def sandbox_workspace_axis_evidence(+source: J.Json, evidence: E.sandbox_launch_category(source),
  inclusion: Categories.Inclusion<J.Json, E.sandbox_launch_category, Categories.holds(J.Json, (source => E.unrestricted_workspace_accepted(source)))>) ->
  {E.unrestricted_workspace_accepted(source) == True{} : Bool}:
  Categories.Inclusion{project} = inclusion
  project(source, evidence)
def E.sandbox_launch_workspace_authority():
  source => evidence => sandbox_workspace_axis_evidence(source, evidence, E.sandbox_launch_workspace_axis())
def sandbox_security_axis_evidence(+source: J.Json, evidence: E.sandbox_launch_category(source),
  inclusion: Categories.Inclusion<J.Json, E.sandbox_launch_category, Categories.holds(J.Json, (source => E.sandbox_security_accepted(source)))>) ->
  {E.sandbox_security_accepted(source) == True{} : Bool}:
  Categories.Inclusion{project} = inclusion
  project(source, evidence)
def E.sandbox_launch_security_authority():
  source => evidence => sandbox_security_axis_evidence(source, evidence, E.sandbox_launch_security_axis())
def E.sandbox_launch_context_cwd():
  source => {==}
def E.sandbox_launch_context_writes():
  source => {==}
def E.sandbox_launch_context_scope():
  source => {==}
def managed_without_root(+roots: List<&2, J.Json>, +separator: String) ->
  {E.managed_writable_items(roots, J.Null{}, separator) == Nil{} : List<&2, J.Json>}:
  match roots:
    case Nil{}: {==}
    case Con{root, rest}: managed_without_root(rest, separator)
def E.sandbox_without_managed_root():
  roots => separator => managed_without_root(roots, separator)
def E.sandbox_readonly_managed_roots():
  workspace => root => separator => {==}
def E.sandbox_managed_binding_order():
  source => {==}
def E.sandbox_launch_descriptor_coordinates():
  source => {==}
def E.sandbox_launch_binding_head():
  entry => rest => descriptor => {==}
def E.sandbox_launch_linux_policy():
  source => {==}
def E.sandbox_launch_darwin_policy():
  source => {==}
def E.sandbox_launch_value_cwd():
  prefix => cwd => {==}
def E.sandbox_launch_value_prefix():
  prefix => cwd => {==}

def E.context_callback_observations():
  effect => result => {==}
def E.context_callback_kind():
  effect => result => {==}
def E.context_failure_kind():
  effect => message => {==}
