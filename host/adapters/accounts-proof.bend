import Base
import ../../bendlib/categories.bend as Categories
import ../../bendlib/json.bend as J
import ./MODEL.bend as Model
import ./ACCOUNTS.bend as Accounts

# The native constructor captures the complete caller source, including raw
# arguments and the observations at the clock/parser/crypto boundary.
def production_correspondence(+operation: String, +source: J.Json) ->
  {Accounts.run(operation, source) == Accounts.meaning(operation, source) : J.Json}:
  {==}

def credential_authority(+source: J.Json,
  evidence: Categories.intersection(J.Json,
    Categories.holds(J.Json, (candidate => Accounts.credential_binding(candidate))),
    Categories.holds(J.Json, (candidate => Accounts.credential_requirements(candidate))), source)) ->
  {Accounts.credential_binding(source) == True{} : Bool}:
  Categories.project_intersection_first(J.Json,
    Categories.holds(J.Json, (candidate => Accounts.credential_binding(candidate))),
    Categories.holds(J.Json, (candidate => Accounts.credential_requirements(candidate))), source, evidence)

def credential_current_format_and_content(+source: J.Json,
  evidence: Categories.intersection(J.Json,
    Categories.holds(J.Json, (candidate => Accounts.credential_binding(candidate))),
    Categories.holds(J.Json, (candidate => Accounts.credential_requirements(candidate))), source)) ->
  {Accounts.credential_requirements(source) == True{} : Bool}:
  Categories.project_intersection_second(J.Json,
    Categories.holds(J.Json, (candidate => Accounts.credential_binding(candidate))),
    Categories.holds(J.Json, (candidate => Accounts.credential_requirements(candidate))), source, evidence)

def registered_issuer_authority(+source: J.Json,
  evidence: Categories.intersection(J.Json,
    Categories.holds(J.Json, (candidate => Accounts.registration_binding(candidate))),
    Categories.holds(J.Json, (candidate => Accounts.registration_shape(candidate))), source)) ->
  {Accounts.registration_binding(source) == True{} : Bool}:
  Categories.project_intersection_first(J.Json,
    Categories.holds(J.Json, (candidate => Accounts.registration_binding(candidate))),
    Categories.holds(J.Json, (candidate => Accounts.registration_shape(candidate))), source, evidence)

def registered_current_format(+source: J.Json,
  evidence: Categories.intersection(J.Json,
    Categories.holds(J.Json, (candidate => Accounts.registration_binding(candidate))),
    Categories.holds(J.Json, (candidate => Accounts.registration_shape(candidate))), source)) ->
  {Accounts.registration_shape(source) == True{} : Bool}:
  Categories.project_intersection_second(J.Json,
    Categories.holds(J.Json, (candidate => Accounts.registration_binding(candidate))),
    Categories.holds(J.Json, (candidate => Accounts.registration_shape(candidate))), source, evidence)

def absent_credential_rejects() ->
  {Accounts.credential_admitted(None{}) == Model.failure("Invalid current-format ChatGPT credential; sign in again") : J.Json}:
  {==}

def absent_registration_rejects() ->
  {Accounts.registration_admitted(None{}) == Model.failure("Invalid ChatGPT client registration; sign in again") : J.Json}:
  {==}

# This branch is called before opening the registration file; an unrelated
# issuer cannot reach its registration or refresh action.
def unrelated_issuer_rejects(+source: J.Json) ->
  {Accounts.issuer_admission_check(False{}, source) == Model.failure("ChatGPT credential belongs to a different issuer; sign in again") : J.Json}:
  {==}

def invalid_claims_reject(+source: J.Json) ->
  {Accounts.token_subject_claims(False{}, source) == Model.failure("ChatGPT identity verification failed; sign in again") : J.Json}:
  {==}

def invalid_cache_is_disposable(+source: J.Json) ->
  {Accounts.cache_valid(False{}, source) == Model.success(J.Null{}) : J.Json}:
  {==}

def invalid_expiration_is_range_error() ->
  {Accounts.token_expiration_decision(False{}) == Model.failure_code("RangeError", "Invalid time value") : J.Json}:
  {==}

# Each actual descriptor projection consumes this semantic membership, indexed
# by the original descriptor and all preceding slugs from its catalog.
def descriptor_authority(+seen: +List<String>, +model: J.Json,
  evidence: Categories.holds(J.Json, (model => Accounts.descriptor_valid(model, seen)), model)) ->
  {Accounts.descriptor_valid(model, seen) == True{} : Bool}:
  evidence

def absent_descriptor_rejects(+seen: +List<String>, +rest: J.Json) ->
  {Accounts.catalog_descriptor_seen(seen, None{}, rest) == Model.failure("ChatGPT returned an invalid model descriptor") : J.Json}:
  {==}

def unrelated_registration_rejects() ->
  {Accounts.refresh_registration_decision(False{}) == Model.failure("ChatGPT credential does not match its registered identity") : J.Json}:
  {==}

def admitted_credential_returns_original(+source: J.Json,
  evidence: Categories.intersection(J.Json,
    Categories.holds(J.Json, (candidate => Accounts.credential_binding(candidate))),
    Categories.holds(J.Json, (candidate => Accounts.credential_requirements(candidate))), source)) ->
  {Accounts.credential_admitted(Some{Categories.Membership{source, evidence}}) == Model.success(J.get(source, "value")) : J.Json}:
  {==}

def admitted_registration_returns_original(+source: J.Json,
  evidence: Categories.intersection(J.Json,
    Categories.holds(J.Json, (candidate => Accounts.registration_binding(candidate))),
    Categories.holds(J.Json, (candidate => Accounts.registration_shape(candidate))), source)) ->
  {Accounts.registration_admitted(Some{Categories.Membership{source, evidence}}) == Model.success(J.get(source, "value")) : J.Json}:
  {==}

# The candidate filesystem observation decides only whether this same selected
# candidate advances; failures retain the original external exception in host.
def readable_candidate_is_accepted(+source: J.Json) ->
  {Accounts.candidate_read_observed(True{}, source) == Accounts.candidate_read_action("accept", source) : J.Json}:
  {==}

def missing_candidate_is_skipped(+source: J.Json) ->
  {Accounts.candidate_read_error(True{}, source) == Accounts.candidate_read_action("skip", source) : J.Json}:
  {==}

def other_candidate_failure_is_propagated(+source: J.Json) ->
  {Accounts.candidate_read_error(False{}, source) == Accounts.candidate_read_action("fail", source) : J.Json}:
  {==}
