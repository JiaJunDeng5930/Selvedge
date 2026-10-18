import Base
import ../../bendlib/json.bend as J
import ./PLUGINS.bend as P
import ../../bendlib/categories.bend as Categories

def P.complete_correspondence():
  operation => source => {==}

def P.trusted_exec_authority():
  connection => arguments => {==}

def P.retained_request_identity():
  connection => arguments => {==}

def P.committed_callback_ticket():
  effect => {==}

def P.committed_callback_operation():
  effect => {==}

def P.committed_call_arguments():
  effect => {==}

def P.committed_call_identity():
  effect => {==}

def P.read_operation_annotation():
  {==}

def P.execution_is_destructive():
  {==}

def P.forgotten_receipt_ends_idempotence():
  {==}

def P.project_route_authority():
  connection => fields => {==}

def P.callback_preserves_result():
  effect => {==}

def P.mcp_call_preserves_arguments():
  source => {==}

def P.enqueue_preserves_event():
  source => next_bytes => {==}

def P.enqueue_append_order():
  source => next_bytes => {==}

def P.enqueue_byte_update():
  source => next_bytes => {==}

def P.enqueue_count_update():
  source => next_bytes => {==}

def P.enqueue_rejection_preserves_bytes():
  source => {==}

def P.enqueue_rejection_preserves_queue():
  source => {==}

def P.malformed_reply_observation():
  source => reason => {==}

def P.successful_reply_requires_result():
  tool => {==}

def P.duplicate_reply_status_rejected():
  {==}

def P.enqueue_diagnostic_sequence():
  source => {==}

def P.enqueue_diagnostic_ordinal():
  source => {==}


def command_value_route_selected(+exec: Bool, +connection: J.Json, +tool: String, +arguments: J.Json) ->
  {J.get(P.command_value_selected(exec, connection, tool, arguments), "op") == J.Text{P.route(tool)} : J.Json}:
  match exec:
    case True{}: {==}
    case False{}: {==}

def command_route_equation_all(+connection: J.Json, +tool: String, +arguments: J.Json) ->
  {J.get(P.command_value(connection, tool, arguments), "op") == J.Text{P.route(tool)} : J.Json}:
  command_value_route_selected(String.eq(tool, "exec"), connection, tool, arguments)

def P.command_route_equation(connection, tool, arguments):
  command_route_equation_all(connection, tool, arguments)

def P.definition_route_classification():
  tool => title => description => {==}

def P.definition_annotation_equation():
  tool => title => description => {==}

def P.connection_config_correspondence():
  source => {==}

def P.connection_grants_correspondence():
  source => {==}

def P.credential_plan_correspondence():
  source => {==}

def P.client_settings_correspondence():
  source => {==}

def P.settings_file_correspondence():
  source => {==}


def P.missing_failure_rejected():
  source => {==}

def P.scalar_failure_rejected():
  source => error => {==}

def P.admitted_reply_projection():
  tool => reply => evidence => {==}

def P.malformed_reply_rejected():
  tool => {==}

def P.receipt_reply_error_preserved():
  error => value => {==}

def P.admitted_reply_payload():
  tool => reply => evidence => Categories.project_intersection_second(J.Json, P.ReplySyntax(), P.ReplyPayload(tool), reply, evidence)
