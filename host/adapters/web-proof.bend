import Base
import ../../bendlib/json.bend as J
import ../../bendlib/categories.bend as Categories
import ./MODEL.bend as Model
import ./WEB.bend as Web

def Web.messages_correspondence():
  source => {==}

def Web.tools_correspondence():
  source => {==}

def Web.resource_correspondence():
  source => {==}

def Web.failure_correspondence():
  source => {==}

def Web.event_correspondence():
  source => {==}

def Web.store_identify_correspondence():
  source => {==}

def Web.store_finish_correspondence():
  source => {==}

def Web.store_reject_correspondence():
  source => {==}

def Web.store_retire_correspondence():
  source => {==}

def Web.store_prepare_correspondence():
  source => {==}

def Web.retire_existing_correspondence():
  source => {==}

def Web.continuation_correspondence():
  source => {==}

def Web.receipt_correspondence():
  source => {==}

def Web.sse_step_correspondence():
  source => {==}

def Web.http_correspondence():
  source => {==}

def Web.commit_correspondence():
  source => {==}

def Web.request_bounds_correspondence():
  source => {==}

def Web.owner_correspondence():
  source => {==}

def Web.headers_correspondence():
  source => {==}

def Web.recovery_correspondence():
  source => {==}

def Web.recovery_result_correspondence():
  source => {==}

def Web.retained_correspondence():
  source => {==}

def Web.decode_correspondence():
  source => {==}

def Web.settle_correspondence():
  source => {==}

def Web.cancel_owner_correspondence():
  source => {==}

def Web.position_correspondence():
  source => {==}

def Web.contract_correspondence():
  source => {==}

def Web.store_metadata_correspondence():
  source => {==}

def Web.frame_correspondence():
  source => {==}

def Web.event_header_correspondence():
  source => {==}

def Web.recovery_shape_correspondence():
  source => {==}

def Web.recovery_connection_correspondence():
  source => {==}

def Web.options_correspondence():
  source => {==}

def Web.invocation_correspondence():
  source => {==}

def Web.immutable_body_refusal():
  source => {==}

def Web.retired_is_retained():
  source => {==}

def Web.predecessor_is_retained():
  source => {==}

def Web.identity_refusal():
  source => {==}

def Web.committed_resource_refusal():
  source => {==}

def Web.incomplete_batch_refusal():
  {==}

def continuation_batch_membership_at(member: Categories.Membership<J.Json, Web.continuation_batch_category()>) ->
  {Web.continuation_batch_matches(Web.continuation_batch_source(member)) == True{} : Bool}:
  match member:
    case Categories.Membership{source, Categories.Intersection{matches, complete}}: matches

def Web.continuation_batch_membership():
  member => continuation_batch_membership_at(member)

def continuation_batch_cardinality_at(member: Categories.Membership<J.Json, Web.continuation_batch_category()>) ->
  {Web.continuation_batch_complete(Web.continuation_batch_source(member)) == True{} : Bool}:
  match member:
    case Categories.Membership{source, Categories.Intersection{matches, complete}}: complete

def Web.continuation_batch_cardinality():
  member => continuation_batch_cardinality_at(member)

def Web.connection_refusal():
  source => {==}

def Web.history_span_refusal():
  source => {==}

def Web.output_without_commit_refusal():
  source => {==}

def Web.admitted_response_cannot_reject():
  {==}

def Web.terminal_agreement_refusal():
  resource => source => {==}

def resource_owned_source_at(member: Categories.Membership<J.Json, Web.resource_category()>) -> {Web.resource_owned(member) == Model.success(Web.get(Web.resource_source(member), "value")) : J.Json}:
  match member:
    case Categories.Membership{source, evidence}: {==}
def Web.resource_owned_source():
  member => resource_owned_source_at(member)
def resource_membership_identity_at(member: Categories.Membership<J.Json, Web.resource_category()>) -> {Web.resource_identity(Web.resource_source(member)) == True{} : Bool}:
  match member:
    case Categories.Membership{source, Categories.Intersection{identity, rest}}: identity
def Web.resource_membership_identity():
  member => resource_membership_identity_at(member)
def resource_membership_request_at(member: Categories.Membership<J.Json, Web.resource_category()>) -> {Web.same_model_request(Web.resource_source(member)) == True{} : Bool}:
  match member:
    case Categories.Membership{source, Categories.Intersection{identity, Categories.Intersection{request, rest}}}: request
def Web.resource_membership_request():
  member => resource_membership_request_at(member)
def resource_membership_authority_at(member: Categories.Membership<J.Json, Web.resource_category()>) -> {Web.authoritative_resource(Web.resource_source(member)) == True{} : Bool}:
  match member:
    case Categories.Membership{source, Categories.Intersection{identity, Categories.Intersection{request, Categories.Intersection{authority, batch}}}}: authority
def Web.resource_membership_authority():
  member => resource_membership_authority_at(member)
def resource_membership_batch_at(member: Categories.Membership<J.Json, Web.resource_category()>) -> {Web.declared_unique_tool_batch(Web.resource_source(member)) == True{} : Bool}:
  match member:
    case Categories.Membership{source, Categories.Intersection{identity, Categories.Intersection{request, Categories.Intersection{authority, batch}}}}: batch
def Web.resource_membership_batch():
  member => resource_membership_batch_at(member)
def receipt_input_count_at(member: Categories.Membership<J.Json, Web.source_category("receipt")>) ->
  {Web.get(Web.get(Web.owned_receipt(member), "value"), "input_count") == J.nat(Web.count(Web.receipt_history(member))) : J.Json}:
  match member:
    case Categories.Membership{source, evidence}: {==}
def Web.receipt_input_count():
  member => receipt_input_count_at(member)
def receipt_owner_binding_at(member: Categories.Membership<J.Json, Web.source_category("receipt")>) -> {Web.get(Web.get(Web.owned_receipt(member), "value"), "task_id") == Web.receipt_bound_task(member) : J.Json}:
  match member:
    case Categories.Membership{source, evidence}: {==}
def Web.receipt_owner_binding():
  member => receipt_owner_binding_at(member)
def receipt_connection_binding_at(member: Categories.Membership<J.Json, Web.source_category("receipt")>) -> {Web.get(Web.get(Web.owned_receipt(member), "value"), "binding") == Web.receipt_bound_connection(member) : J.Json}:
  match member:
    case Categories.Membership{source, evidence}: {==}
def Web.receipt_connection_binding():
  member => receipt_connection_binding_at(member)
def receipt_response_binding_at(member: Categories.Membership<J.Json, Web.source_category("receipt")>) -> {Web.get(Web.get(Web.owned_receipt(member), "value"), "response_id") == Web.receipt_bound_response(member) : J.Json}:
  match member:
    case Categories.Membership{source, evidence}: {==}
def Web.receipt_response_binding():
  member => receipt_response_binding_at(member)
def Web.frame_event_projection_payload():
  value => source => {==}
def Web.frame_event_projection_frame():
  value => source => {==}
def Web.frame_event_decoded_value():
  value => header => source => {==}
def Web.frame_event_decode_failure():
  error => header => source => {==}
def Web.frame_event_raw_failure():
  result => header => source => {==}
def Web.frame_event_done_bypass():
  header => source => {==}
def frame_event_membership_coordinates_at(member: Categories.Membership<J.Json, Web.frame_event_category()>) -> {Web.frame_event_coordinates(Web.frame_event_member_source(member)) == True{} : Bool}:
  match member:
    case Categories.Membership{source, Categories.Intersection{coordinates, shape}}: coordinates
def Web.frame_event_membership_coordinates():
  member => frame_event_membership_coordinates_at(member)
def frame_event_membership_shape_at(member: Categories.Membership<J.Json, Web.frame_event_category()>) -> {Web.frame_event_shape(Web.frame_event_member_source(member)) == True{} : Bool}:
  match member:
    case Categories.Membership{source, Categories.Intersection{coordinates, shape}}: shape
def Web.frame_event_membership_shape():
  member => frame_event_membership_shape_at(member)
def Web.header_conflict_refusal():
  source => {==}
def Web.header_identifies_before_semantics():
  source => {==}

def Web.cancellation_correspondence():
  source => {==}

def Web.store_latest_correspondence():
  source => {==}

def Web.exchange_start_correspondence():
  source => {==}

def Web.exchange_result_correspondence():
  source => {==}

def Web.catch_correspondence():
  source => {==}

def Web.http_json_correspondence():
  source => {==}
def Web.successful_http_json_parse_failure():
  {==}
def Web.unsuccessful_http_json_parse_failure():
  {==}
def Web.decoded_http_json_value():
  value => source => {==}

def route_http_json_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_http_json(selected, operation, source) == Web.meaning_route_http_json(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.http_json_correspondence()(source)
    case False{}: {==}

def route_catch_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_catch(selected, operation, source) == Web.meaning_route_catch(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.catch_correspondence()(source)
    case False{}: route_http_json_dispatch(String.eq(operation, "web.http_json"), operation, source)

def route_exchange_result_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_exchange_result(selected, operation, source) == Web.meaning_route_exchange_result(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.exchange_result_correspondence()(source)
    case False{}: route_catch_dispatch(String.eq(operation, "web.catch"), operation, source)

def route_exchange_start_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_exchange_start(selected, operation, source) == Web.meaning_route_exchange_start(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.exchange_start_correspondence()(source)
    case False{}: route_exchange_result_dispatch(String.eq(operation, "web.exchange_result"), operation, source)

def route_store_latest_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_store_latest(selected, operation, source) == Web.meaning_route_store_latest(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.store_latest_correspondence()(source)
    case False{}: route_exchange_start_dispatch(String.eq(operation, "web.exchange_start"), operation, source)

def route_cancellation_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_cancellation(selected, operation, source) == Web.meaning_route_cancellation(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.cancellation_correspondence()(source)
    case False{}: route_store_latest_dispatch(String.eq(operation, "web.store_latest"), operation, source)

def route_33_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_33(selected, operation, source) == Web.meaning_route_33(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.invocation_correspondence()(source)
    case False{}: route_cancellation_dispatch(String.eq(operation, "web.cancellation"), operation, source)

def route_32_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_32(selected, operation, source) == Web.meaning_route_32(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.options_correspondence()(source)
    case False{}: route_33_dispatch(String.eq(operation, "web.invocation"), operation, source)

def route_31_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_31(selected, operation, source) == Web.meaning_route_31(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.recovery_connection_correspondence()(source)
    case False{}: route_32_dispatch(String.eq(operation, "web.options"), operation, source)

def route_30_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_30(selected, operation, source) == Web.meaning_route_30(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.recovery_shape_correspondence()(source)
    case False{}: route_31_dispatch(String.eq(operation, "web.recovery_connection"), operation, source)

def route_29_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_29(selected, operation, source) == Web.meaning_route_29(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.event_header_correspondence()(source)
    case False{}: route_30_dispatch(String.eq(operation, "web.recovery_shape"), operation, source)

def route_28_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_28(selected, operation, source) == Web.meaning_route_28(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.frame_correspondence()(source)
    case False{}: route_29_dispatch(String.eq(operation, "web.event_header"), operation, source)

def route_27_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_27(selected, operation, source) == Web.meaning_route_27(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.store_metadata_correspondence()(source)
    case False{}: route_28_dispatch(String.eq(operation, "web.frame"), operation, source)

def route_26_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_26(selected, operation, source) == Web.meaning_route_26(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.contract_correspondence()(source)
    case False{}: route_27_dispatch(String.eq(operation, "web.store_metadata"), operation, source)

def route_25_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_25(selected, operation, source) == Web.meaning_route_25(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.position_correspondence()(source)
    case False{}: route_26_dispatch(String.eq(operation, "web.contract"), operation, source)

def route_24_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_24(selected, operation, source) == Web.meaning_route_24(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.cancel_owner_correspondence()(source)
    case False{}: route_25_dispatch(String.eq(operation, "web.position"), operation, source)

def route_23_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_23(selected, operation, source) == Web.meaning_route_23(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.settle_correspondence()(source)
    case False{}: route_24_dispatch(String.eq(operation, "web.cancel_owner"), operation, source)

def route_22_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_22(selected, operation, source) == Web.meaning_route_22(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.decode_correspondence()(source)
    case False{}: route_23_dispatch(String.eq(operation, "web.settle"), operation, source)

def route_21_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_21(selected, operation, source) == Web.meaning_route_21(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.retained_correspondence()(source)
    case False{}: route_22_dispatch(String.eq(operation, "web.decode"), operation, source)

def route_20_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_20(selected, operation, source) == Web.meaning_route_20(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.recovery_result_correspondence()(source)
    case False{}: route_21_dispatch(String.eq(operation, "web.retained"), operation, source)

def route_19_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_19(selected, operation, source) == Web.meaning_route_19(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.recovery_correspondence()(source)
    case False{}: route_20_dispatch(String.eq(operation, "web.recovery_result"), operation, source)

def route_18_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_18(selected, operation, source) == Web.meaning_route_18(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.headers_correspondence()(source)
    case False{}: route_19_dispatch(String.eq(operation, "web.recovery"), operation, source)

def route_17_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_17(selected, operation, source) == Web.meaning_route_17(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.owner_correspondence()(source)
    case False{}: route_18_dispatch(String.eq(operation, "web.headers"), operation, source)

def route_16_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_16(selected, operation, source) == Web.meaning_route_16(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.request_bounds_correspondence()(source)
    case False{}: route_17_dispatch(String.eq(operation, "web.owner"), operation, source)

def route_15_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_15(selected, operation, source) == Web.meaning_route_15(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.commit_correspondence()(source)
    case False{}: route_16_dispatch(String.eq(operation, "web.request_bounds"), operation, source)

def route_14_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_14(selected, operation, source) == Web.meaning_route_14(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.http_correspondence()(source)
    case False{}: route_15_dispatch(String.eq(operation, "web.commit"), operation, source)

def route_13_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_13(selected, operation, source) == Web.meaning_route_13(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.sse_step_correspondence()(source)
    case False{}: route_14_dispatch(String.eq(operation, "web.http"), operation, source)

def route_12_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_12(selected, operation, source) == Web.meaning_route_12(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.receipt_correspondence()(source)
    case False{}: route_13_dispatch(String.eq(operation, "web.sse_step"), operation, source)

def route_11_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_11(selected, operation, source) == Web.meaning_route_11(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.continuation_correspondence()(source)
    case False{}: route_12_dispatch(String.eq(operation, "web.receipt"), operation, source)

def route_10_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_10(selected, operation, source) == Web.meaning_route_10(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.retire_existing_correspondence()(source)
    case False{}: route_11_dispatch(String.eq(operation, "web.continuation"), operation, source)

def route_9_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_9(selected, operation, source) == Web.meaning_route_9(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.store_prepare_correspondence()(source)
    case False{}: route_10_dispatch(String.eq(operation, "web.retire_existing"), operation, source)

def route_8_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_8(selected, operation, source) == Web.meaning_route_8(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.store_retire_correspondence()(source)
    case False{}: route_9_dispatch(String.eq(operation, "web.store_prepare"), operation, source)

def route_7_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_7(selected, operation, source) == Web.meaning_route_7(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.store_reject_correspondence()(source)
    case False{}: route_8_dispatch(String.eq(operation, "web.store_retire"), operation, source)

def route_6_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_6(selected, operation, source) == Web.meaning_route_6(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.store_finish_correspondence()(source)
    case False{}: route_7_dispatch(String.eq(operation, "web.store_reject"), operation, source)

def route_5_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_5(selected, operation, source) == Web.meaning_route_5(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.store_identify_correspondence()(source)
    case False{}: route_6_dispatch(String.eq(operation, "web.store_finish"), operation, source)

def route_4_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_4(selected, operation, source) == Web.meaning_route_4(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.event_correspondence()(source)
    case False{}: route_5_dispatch(String.eq(operation, "web.store_identify"), operation, source)

def route_3_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_3(selected, operation, source) == Web.meaning_route_3(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.failure_correspondence()(source)
    case False{}: route_4_dispatch(String.eq(operation, "web.event"), operation, source)

def route_2_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_2(selected, operation, source) == Web.meaning_route_2(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.resource_correspondence()(source)
    case False{}: route_3_dispatch(String.eq(operation, "web.failure"), operation, source)

def route_1_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_1(selected, operation, source) == Web.meaning_route_1(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.tools_correspondence()(source)
    case False{}: route_2_dispatch(String.eq(operation, "web.resource"), operation, source)

def route_0_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Web.route_0(selected, operation, source) == Web.meaning_route_0(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.messages_correspondence()(source)
    case False{}: route_1_dispatch(String.eq(operation, "web.tools"), operation, source)

def legacy_dispatch(+operation: String, +source: J.Json) ->
    {Web.route_0(String.eq(operation, "web.messages"), operation, source) == Web.meaning_route_0(String.eq(operation, "web.messages"), operation, source) : J.Json}:
  route_0_dispatch(String.eq(operation, "web.messages"), operation, source)

def Web.reset_session_correspondence():
  source => {==}
def Web.reset_write_scope():
  record => rest => {==}
def Web.reset_write_reason():
  record => rest => {==}

def reset_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
  {Web.route_reset(selected, operation, source) == Web.meaning_route_reset(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Web.reset_session_correspondence()(source)
    case False{}: legacy_dispatch(operation, source)

def complete_dispatch(+operation: String, +source: J.Json) ->
  {Web.run(operation, source) == Web.meaning(operation, source) : J.Json}:
  reset_dispatch(String.eq(operation, "web.reset_session"), operation, source)

def Web.complete_correspondence():
  operation => source => complete_dispatch(operation, source)

def Web.new_store_metadata_initialization():
  identity => {==}
def Web.existing_empty_store_metadata_rejection():
  identity => {==}
def Web.singleton_store_metadata_validation():
  row => identity => created => {==}
def Web.multiple_store_metadata_rejection():
  first => second => rest => identity => created => {==}
def Web.retirement_metadata_gate():
  source => {==}
def Web.retirement_metadata_rejection():
  error => source => {==}
def Web.retirement_admitted_metadata_writes():
  metadata => source => {==}

def Web.continuation_preserves_page_reset_policy():
  body => deferred => source => {==}
def Web.context_change_encoding():
  item => {==}

def Web.tool_receipt_history_success():
  item => {==}
def Web.tool_receipt_history_data():
  item => {==}

def Web.after_record_history_success():
  item => {==}
def Web.after_record_history_data():
  item => {==}

def Web.approval_record_history_success():
  item => {==}
def Web.approval_record_history_data():
  item => {==}

def utf8_acc_concat(+first: String, +second: String, +total: Nat) ->
  {J.utf8_length_acc(first ++ second, total) == J.utf8_length_acc(second, J.utf8_length_acc(first, total)) : Nat}:
  match first:
    case SNil{}: {==}
    case SCon{Chr{+code}, rest}: utf8_acc_concat(rest, second, Nat.add(total, J.char_width(U32.is_lt(code, 128), U32.is_lt(code, 2048), U32.is_lt(code, 65536))))

def sse_pending_projection(+work: Web.SseWork, +maximum: Nat, allowed: Bool, observed: {Web.sse_line_within(work, maximum) == allowed : Bool}) ->
  {Web.sse_pending_admission(work, maximum, Categories.admit_checked(Web.SseWork, (work => Web.sse_line_within(work, maximum)), work, allowed, observed)) == Web.sse_work_limit(allowed, work) : Web.SseWork}:
  match allowed:
    case True{}: {==}
    case False{}: {==}

def sse_limit_measured(allowed: Bool, +work: Web.SseWork) ->
  {Web.sse_counted(Web.sse_work_limit(allowed, work)) == Web.SseCounted{Web.sse_work_limit(allowed, work), Web.sse_pending_bytes(work)} : Web.SseCounted}:
  match allowed work:
    case True{} _: {==}
    case False{} Web.SseWork{Web.SseState{pending, data, size, name}, frames, error}: {==}

def sse_budget_refinement(+work: Web.SseWork, +maximum: Nat) ->
  {Web.sse_counted_budget(Web.sse_counted(work), maximum) == Web.sse_counted(Web.sse_pending_budget(work, maximum)) : Web.SseCounted}:
  Web.SseWork{Web.SseState{pending, data, size, name}, frames, error} = work
  +allowed = Web.sse_line_within(work, maximum)
  +limited = Web.sse_work_limit(allowed, work)
  +admitted = Web.sse_pending_budget(work, maximum)
  +cached = Web.sse_counted_budget(Web.sse_counted(work), maximum)
  Equal.trans(Web.SseCounted, cached, Web.sse_counted(limited), Web.sse_counted(admitted),
    Equal.sym(Web.SseCounted, Web.sse_counted(limited), cached, sse_limit_measured(allowed, work)),
    Equal.cong(Web.SseWork, Web.SseCounted, work => Web.sse_counted(work), limited, admitted,
      Equal.sym(Web.SseWork, admitted, limited, sse_pending_projection(work, maximum, allowed, {==}))))

def sse_appended_bytes(+character: Char, +pending: String) ->
  {J.utf8_length(pending ++ SCon{character, SNil{}}) == Nat.add(J.utf8_length(pending), Web.sse_character_bytes(character)) : Nat}:
  match character:
    case Chr{+code}: utf8_acc_concat(pending, SCon{Chr{code}, SNil{}}, 0n)

def sse_selected_refinement(newline: Bool, +character: Char, +work: Web.SseWork, +maximum: Nat) ->
  {Web.sse_counted_selected(newline, character, Web.sse_counted(work), maximum) == Web.sse_counted(Web.sse_character_selected(newline, character, work, maximum)) : Web.SseCounted}:
  match newline:
    case True{}: {==}
    case False{}:
      Web.SseWork{Web.SseState{+pending, data, size, name}, frames, error} = work
      +measured = J.utf8_length(pending ++ SCon{character, SNil{}})
      +counted = Nat.add(J.utf8_length(pending), Web.sse_character_bytes(character))
      Equal.cong(Nat, Web.SseCounted, bytes => Web.SseCounted{Web.sse_work_character(character, work), bytes}, counted, measured,
        Equal.sym(Nat, measured, counted, sse_appended_bytes(character, pending)))

def sse_action_refinement(+character: Char, +work: Web.SseWork, maximum: Nat) ->
  {Web.sse_counted_action(character, Web.sse_counted(work), maximum) == Web.sse_counted(Web.sse_character_action(character, work, maximum)) : Web.SseCounted}:
  sse_selected_refinement(Web.sse_newline(character), character, work, maximum)

def sse_character_refinement(+character: Char, +work: Web.SseWork, +maximum: Nat) ->
  {Web.sse_counted_character(character, Web.sse_counted(work), maximum) == Web.sse_counted(Web.sse_character(character, work, maximum)) : Web.SseCounted}:
  match work:
    case Web.SseWork{state, frames, SCon{first, rest}}: {==}
    case Web.SseWork{state, frames, SNil{}}:
      +action = Web.sse_character_action(character, work, maximum)
      +cached = Web.sse_counted_action(character, Web.sse_counted(work), maximum)
      Equal.trans(Web.SseCounted,
        Web.sse_counted_budget(cached, maximum),
        Web.sse_counted_budget(Web.sse_counted(action), maximum),
        Web.sse_counted(Web.sse_pending_budget(action, maximum)),
        Equal.cong(Web.SseCounted, Web.SseCounted, counted => Web.sse_counted_budget(counted, maximum), cached, Web.sse_counted(action), sse_action_refinement(character, work, maximum)),
        sse_budget_refinement(action, maximum))

def sse_counted_scan_refinement(chunk: String, +work: Web.SseWork, +maximum: Nat) ->
  {Web.sse_counted_scan(chunk, Web.sse_counted(work), maximum) == Web.sse_counted(Web.sse_required_scan(chunk, work, maximum)) : Web.SseCounted}:
  match chunk:
    case SNil{}: {==}
    case SCon{+character, +rest}:
      +next = Web.sse_character(character, work, maximum)
      +cached = Web.sse_counted_character(character, Web.sse_counted(work), maximum)
      Equal.trans(Web.SseCounted,
        Web.sse_counted_scan(rest, cached, maximum),
        Web.sse_counted_scan(rest, Web.sse_counted(next), maximum),
        Web.sse_counted(Web.sse_required_scan(rest, next, maximum)),
        Equal.cong(Web.SseCounted, Web.SseCounted, counted => Web.sse_counted_scan(rest, counted, maximum), cached, Web.sse_counted(next), sse_character_refinement(character, work, maximum)),
        sse_counted_scan_refinement(rest, next, maximum))

def sse_scan_refinement(+chunk: String, +work: Web.SseWork, +maximum: Nat) ->
  {Web.sse_scan(chunk, work, maximum) == Web.sse_required_scan(chunk, Web.sse_pending_budget(work, maximum), maximum) : Web.SseWork}:
  +admitted = Web.sse_pending_budget(work, maximum)
  +cached = Web.sse_counted_budget(Web.sse_counted(work), maximum)
  Equal.cong(Web.SseCounted, Web.SseWork, counted => Web.sse_counted_work(counted),
    Web.sse_counted_scan(chunk, cached, maximum),
    Web.sse_counted(Web.sse_required_scan(chunk, admitted, maximum)),
    Equal.trans(Web.SseCounted,
      Web.sse_counted_scan(chunk, cached, maximum),
      Web.sse_counted_scan(chunk, Web.sse_counted(admitted), maximum),
      Web.sse_counted(Web.sse_required_scan(chunk, admitted, maximum)),
      Equal.cong(Web.SseCounted, Web.SseCounted, counted => Web.sse_counted_scan(chunk, counted, maximum), cached, Web.sse_counted(admitted), sse_budget_refinement(work, maximum)),
      sse_counted_scan_refinement(chunk, admitted, maximum)))

def sse_required_chunks(+first: String, second: String, work: Web.SseWork, +maximum: Nat) ->
  {Web.sse_required_scan(first ++ second, work, maximum) == Web.sse_required_scan(second, Web.sse_required_scan(first, work, maximum), maximum) : Web.SseWork}:
  match first:
    case SNil{}: {==}
    case SCon{character, rest}: sse_required_chunks(rest, second, Web.sse_character(character, work, maximum), maximum)

def sse_pending_admission_bound(+work: Web.SseWork, +maximum: Nat, candidate: Maybe<&1, Categories.Membership<Web.SseWork, Web.SseLineWithin(maximum)>>) ->
  {Web.sse_line_within(Web.sse_pending_admission(work, maximum, candidate), maximum) == True{} : Bool}:
  match work candidate:
    case Web.SseWork{state, frames, error} None{}: {==}
    case _ Some{Categories.Membership{selected, evidence}}: evidence

def Web.sse_pending_budget_line_bound():
  +work => +maximum => sse_pending_admission_bound(work, maximum, Categories.admit(Web.SseWork, (work => Web.sse_line_within(work, maximum)), work))

def sse_character_line_bound_all(+character: Char, +work: Web.SseWork, +maximum: Nat) ->
  {Web.sse_line_within(Web.sse_character(character, work, maximum), maximum) == True{} : Bool}:
  match work:
    case Web.SseWork{state, frames, SCon{first, rest}}: {==}
    case Web.SseWork{state, frames, SNil{}}: Web.sse_pending_budget_line_bound()(Web.sse_character_action(character, work, maximum), maximum)

def Web.sse_character_line_bound():
  character => work => maximum => sse_character_line_bound_all(character, work, maximum)

def sse_required_line_bound(chunk: String, +work: Web.SseWork, +maximum: Nat, initial: {Web.sse_line_within(work, maximum) == True{} : Bool}) ->
  {Web.sse_line_within(Web.sse_required_scan(chunk, work, maximum), maximum) == True{} : Bool}:
  match chunk:
    case SNil{}: initial
    case SCon{+character, rest}: sse_required_line_bound(rest, Web.sse_character(character, work, maximum), maximum, Web.sse_character_line_bound()(character, work, maximum))

def sse_scan_bound(+chunk: String, +work: Web.SseWork, +maximum: Nat) ->
  {Web.sse_line_within(Web.sse_scan(chunk, work, maximum), maximum) == True{} : Bool}:
  +actual = Web.sse_scan(chunk, work, maximum)
  +required = Web.sse_required_scan(chunk, Web.sse_pending_budget(work, maximum), maximum)
  Equal.trans(Bool, Web.sse_line_within(actual, maximum), Web.sse_line_within(required, maximum), True{},
    Equal.cong(Web.SseWork, Bool, work => Web.sse_line_within(work, maximum), actual, required, sse_scan_refinement(chunk, work, maximum)),
    sse_required_line_bound(chunk, Web.sse_pending_budget(work, maximum), maximum, Web.sse_pending_budget_line_bound()(work, maximum)))

def Web.sse_scan_line_bound():
  chunk => work => maximum => sse_scan_bound(chunk, work, maximum)

def sse_pending_identity(+work: Web.SseWork, +maximum: Nat, evidence: {Web.sse_line_within(work, maximum) == True{} : Bool}) ->
  {Web.sse_pending_budget(work, maximum) == work : Web.SseWork}:
  +admitted = Web.sse_pending_budget(work, maximum)
  +allowed = Web.sse_line_within(work, maximum)
  Equal.trans(Web.SseWork, admitted, Web.sse_work_limit(allowed, work), work,
    sse_pending_projection(work, maximum, allowed, {==}),
    Equal.cong(Bool, Web.SseWork, allowed => Web.sse_work_limit(allowed, work), allowed, True{}, evidence))

def sse_second_refinement(+first: String, +second: String, +work: Web.SseWork, +maximum: Nat) ->
  {Web.sse_scan(second, Web.sse_scan(first, work, maximum), maximum) == Web.sse_required_scan(second, Web.sse_required_scan(first, Web.sse_pending_budget(work, maximum), maximum), maximum) : Web.SseWork}:
  +actual_first = Web.sse_scan(first, work, maximum)
  +required_first = Web.sse_required_scan(first, Web.sse_pending_budget(work, maximum), maximum)
  +admitted_first = Web.sse_pending_budget(actual_first, maximum)
  Equal.trans(Web.SseWork,
    Web.sse_scan(second, actual_first, maximum),
    Web.sse_required_scan(second, admitted_first, maximum),
    Web.sse_required_scan(second, required_first, maximum),
    sse_scan_refinement(second, actual_first, maximum),
    Equal.cong(Web.SseWork, Web.SseWork, work => Web.sse_required_scan(second, work, maximum), admitted_first, required_first,
      Equal.trans(Web.SseWork, admitted_first, actual_first, required_first,
        sse_pending_identity(actual_first, maximum, sse_scan_bound(first, work, maximum)),
        sse_scan_refinement(first, work, maximum))))

def sse_chunk_composition_all(+first: String, +second: String, +work: Web.SseWork, +maximum: Nat) ->
  {Web.sse_scan(first ++ second, work, maximum) == Web.sse_scan(second, Web.sse_scan(first, work, maximum), maximum) : Web.SseWork}:
  +admitted = Web.sse_pending_budget(work, maximum)
  +joined = Web.sse_required_scan(first ++ second, admitted, maximum)
  +required = Web.sse_required_scan(second, Web.sse_required_scan(first, admitted, maximum), maximum)
  +actual_joined = Web.sse_scan(first ++ second, work, maximum)
  +actual_split = Web.sse_scan(second, Web.sse_scan(first, work, maximum), maximum)
  Equal.trans(Web.SseWork, actual_joined, required, actual_split,
    Equal.trans(Web.SseWork, actual_joined, joined, required,
      sse_scan_refinement(first ++ second, work, maximum),
      sse_required_chunks(first, second, admitted, maximum)),
    Equal.sym(Web.SseWork, actual_split, required, sse_second_refinement(first, second, work, maximum)))

def Web.sse_chunk_composition():
  first => second => work => maximum => sse_chunk_composition_all(first, second, work, maximum)

def Web.sse_unfinished_line_rejected():
  head => rest => data => size => name => chunk => {==}

def Web.sse_unfinished_data_rejected():
  first => rest => size => name => {==}

def Web.sse_complete_eof():
  size => name => {==}
