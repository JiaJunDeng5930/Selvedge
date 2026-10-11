import Base
import ../../bendlib/json.bend as J
import ./EVALUATOR.bend as E
import ../../bendlib/categories.bend as Categories

def E.complete_correspondence():
  arg0 => arg1 => {==}

def E.context_selection_complete():
  arg0 => {==}

def E.context_finish_complete():
  arg0 => {==}

def E.budget_plan_complete():
  arg0 => {==}

def E.budget_finish_complete():
  arg0 => {==}

def E.preview_start_complete():
  arg0 => {==}

def E.preview_step_complete():
  arg0 => {==}

def E.request_complete():
  arg0 => {==}

def E.decision_complete():
  arg0 => {==}

def E.request_admission_complete():
  arg0 => {==}

def E.retry_complete():
  arg0 => {==}

def E.paired_call_identity():
  arg0 => arg1 => arg2 => arg3 => {==}

def E.paired_call_coordinate():
  arg0 => arg1 => arg2 => arg3 => {==}

def E.preview_original_tokens():
  arg0 => arg1 => arg2 => {==}

def E.preview_sent_tokens():
  arg0 => arg1 => arg2 => {==}

def E.preview_budget_tokens():
  arg0 => arg1 => arg2 => {==}

def E.preview_tokenizer():
  arg0 => arg1 => arg2 => {==}

def E.preview_decode_keep():
  arg0 => arg1 => arg2 => {==}

def E.preview_decode_head():
  arg0 => arg1 => arg2 => {==}

def E.preview_decode_tail():
  arg0 => arg1 => arg2 => {==}

def E.retry_next_attempt():
  arg0 => arg1 => {==}

def E.retry_delay():
  arg0 => arg1 => {==}

def E.http_failure_cancel_first():
  arg0 => {==}

def configured_model_case(vercel: Bool, openrouter: Bool, +source: J.Json) ->
  {J.get(E.request_route_choices(vercel, openrouter, E.request_base(source)), "model") == J.get(J.get(source, "evaluator"), "model") : J.Json}:
  match vercel openrouter:
    case True{} True{}: {==}
    case True{} False{}: {==}
    case False{} True{}: {==}
    case False{} False{}: {==}

def E.configured_request_model():
  +source => configured_model_case(E.equal(J.get(J.get(source, "evaluator"), "provider"), "vercel"), E.equal(J.get(J.get(source, "evaluator"), "provider"), "openrouter"), source)

def context_production_source_apply(-value: Categories.Construction<J.Json, J.Json>, inclusion: Categories.Inclusion<Categories.Construction<J.Json, J.Json>, E.public_context_admission, E.public_context_request>, evidence: E.public_context_admission(value)) -> E.public_context_request(value):
  Categories.Inclusion{apply} = inclusion
  apply(value, evidence)

def context_production_source_member(member: Categories.Membership<Categories.Construction<J.Json, J.Json>, E.public_context_admission>) -> E.public_context_request(E.context_construction(member)):
  Categories.Membership{value, evidence} = member
  context_production_source_apply(value, E.public_context_requirements(), evidence)

def E.context_production_source():
  member => context_production_source_member(member)

def context_production_result_apply(-value: Categories.Construction<J.Json, J.Json>, inclusion: Categories.Inclusion<Categories.Construction<J.Json, J.Json>, E.public_context_admission, E.public_context_result>, evidence: E.public_context_admission(value)) -> E.public_context_result(value):
  Categories.Inclusion{apply} = inclusion
  apply(value, evidence)

def context_production_result_member(member: Categories.Membership<Categories.Construction<J.Json, J.Json>, E.public_context_admission>) -> E.public_context_result(E.context_construction(member)):
  Categories.Membership{value, evidence} = member
  context_production_result_apply(value, E.public_context_correspondence(), evidence)

def E.context_production_result():
  member => context_production_result_member(member)

def request_production_tokens_apply(-value: J.Json, inclusion: Categories.Inclusion<J.Json, E.request_budget, E.request_token_budget>, evidence: E.request_budget(value)) -> E.request_token_budget(value):
  Categories.Inclusion{apply} = inclusion
  apply(value, evidence)

def request_production_tokens_member(member: Categories.Membership<J.Json, E.request_budget>) -> E.request_token_budget(E.request_budget_source(member)):
  Categories.Membership{value, evidence} = member
  request_production_tokens_apply(value, E.admitted_request_tokens(), evidence)

def E.request_production_tokens():
  member => request_production_tokens_member(member)

def request_production_bytes_apply(-value: J.Json, inclusion: Categories.Inclusion<J.Json, E.request_budget, E.request_byte_budget>, evidence: E.request_budget(value)) -> E.request_byte_budget(value):
  Categories.Inclusion{apply} = inclusion
  apply(value, evidence)

def request_production_bytes_member(member: Categories.Membership<J.Json, E.request_budget>) -> E.request_byte_budget(E.request_budget_source(member)):
  Categories.Membership{value, evidence} = member
  request_production_bytes_apply(value, E.admitted_request_bytes(), evidence)

def E.request_production_bytes():
  member => request_production_bytes_member(member)

def decision_production_configuration_apply(-value: E.DecisionSource, inclusion: Categories.Inclusion<E.DecisionSource, E.decision_admission, E.configured_effort_and_lease>, evidence: E.decision_admission(value)) -> E.configured_effort_and_lease(value):
  Categories.Inclusion{apply} = inclusion
  apply(value, evidence)

def decision_production_configuration_member(member: Categories.Membership<E.DecisionSource, E.decision_admission>) -> E.configured_effort_and_lease(E.decision_member_source(member)):
  Categories.Membership{value, evidence} = member
  decision_production_configuration_apply(value, E.admitted_decision_configuration(), evidence)

def E.decision_production_configuration():
  member => decision_production_configuration_member(member)

def decision_production_identity_apply(-value: E.DecisionSource, inclusion: Categories.Inclusion<E.DecisionSource, E.decision_admission, E.identity_routing>, evidence: E.decision_admission(value)) -> E.identity_routing(value):
  Categories.Inclusion{apply} = inclusion
  apply(value, evidence)

def decision_production_identity_member(member: Categories.Membership<E.DecisionSource, E.decision_admission>) -> E.identity_routing(E.decision_member_source(member)):
  Categories.Membership{value, evidence} = member
  decision_production_identity_apply(value, E.admitted_decision_identity(), evidence)

def E.decision_production_identity():
  member => decision_production_identity_member(member)

def retry_production_identity_apply(-value: J.Json, inclusion: Categories.Inclusion<J.Json, E.same_provider_retry, E.same_provider>, evidence: E.same_provider_retry(value)) -> E.same_provider(value):
  Categories.Inclusion{apply} = inclusion
  apply(value, evidence)

def retry_production_identity_member(member: Categories.Membership<J.Json, E.same_provider_retry>) -> E.same_provider(E.retry_source(member)):
  Categories.Membership{value, evidence} = member
  retry_production_identity_apply(value, E.retry_identity(), evidence)

def E.retry_production_identity():
  member => retry_production_identity_member(member)

def retry_production_bound_apply(-value: J.Json, inclusion: Categories.Inclusion<J.Json, E.same_provider_retry, E.bounded_retry>, evidence: E.same_provider_retry(value)) -> E.bounded_retry(value):
  Categories.Inclusion{apply} = inclusion
  apply(value, evidence)

def retry_production_bound_member(member: Categories.Membership<J.Json, E.same_provider_retry>) -> E.bounded_retry(E.retry_source(member)):
  Categories.Membership{value, evidence} = member
  retry_production_bound_apply(value, E.retry_bound(), evidence)

def E.retry_production_bound():
  member => retry_production_bound_member(member)

def E.decision_original_coordinate():
  original => reply => {==}

def E.decision_reply_coordinate():
  original => reply => {==}

def E.decision_parsed_authority():
  original => reply => {==}

def E.context_member_result():
  member => {==}

def E.decision_member_result():
  member => {==}

def E.retry_member_result():
  member => {==}
