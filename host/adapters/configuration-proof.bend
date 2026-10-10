import Base
import ../../bendlib/json.bend as J
import ../../bendlib/categories.bend as Categories
import ./MODEL.bend as Model
import ./CONFIGURATION.bend as Configuration

# The factory binds each actual operation to its complete observed source,
# including references, UTF-16 units and external parser/byte observations.
def production_correspondence(+operation: String, +source: J.Json) ->
  {Configuration.run(operation, source) == Configuration.meaning(operation, source) : J.Json}:
  {==}

def adaptive_effort_inclusion() -> Categories.Inclusion<J.Json,
  (source => Categories.intersection(J.Json, Categories.holds(J.Json, (candidate => Configuration.config_effort_requirements(candidate))),
    Categories.holds(J.Json, (candidate => Configuration.config_lease_requirements(candidate))), source)),
  Categories.holds(J.Json, (candidate => Configuration.config_effort_requirements(candidate)))>:
  Categories.intersection_first(J.Json, Categories.holds(J.Json, (candidate => Configuration.config_effort_requirements(candidate))),
    Categories.holds(J.Json, (candidate => Configuration.config_lease_requirements(candidate))))

def adaptive_lease_inclusion() -> Categories.Inclusion<J.Json,
  (source => Categories.intersection(J.Json, Categories.holds(J.Json, (candidate => Configuration.config_effort_requirements(candidate))),
    Categories.holds(J.Json, (candidate => Configuration.config_lease_requirements(candidate))), source)),
  Categories.holds(J.Json, (candidate => Configuration.config_lease_requirements(candidate)))>:
  Categories.intersection_second(J.Json, Categories.holds(J.Json, (candidate => Configuration.config_effort_requirements(candidate))),
    Categories.holds(J.Json, (candidate => Configuration.config_lease_requirements(candidate))))

def evaluator_endpoint_inclusion() -> Categories.Inclusion<J.Json,
  (source => Categories.intersection(J.Json, Categories.holds(J.Json, (candidate => Configuration.config_endpoint_requirements(candidate))),
    Categories.holds(J.Json, (candidate => Configuration.config_timing_requirements(candidate))), source)),
  Categories.holds(J.Json, (candidate => Configuration.config_endpoint_requirements(candidate)))>:
  Categories.intersection_first(J.Json, Categories.holds(J.Json, (candidate => Configuration.config_endpoint_requirements(candidate))),
    Categories.holds(J.Json, (candidate => Configuration.config_timing_requirements(candidate))))

def evaluator_timing_inclusion() -> Categories.Inclusion<J.Json,
  (source => Categories.intersection(J.Json, Categories.holds(J.Json, (candidate => Configuration.config_endpoint_requirements(candidate))),
    Categories.holds(J.Json, (candidate => Configuration.config_timing_requirements(candidate))), source)),
  Categories.holds(J.Json, (candidate => Configuration.config_timing_requirements(candidate)))>:
  Categories.intersection_second(J.Json, Categories.holds(J.Json, (candidate => Configuration.config_endpoint_requirements(candidate))),
    Categories.holds(J.Json, (candidate => Configuration.config_timing_requirements(candidate))))

def adaptive_effort_authority(+source: J.Json,
  evidence: Categories.intersection(J.Json, Categories.holds(J.Json, (candidate => Configuration.config_effort_requirements(candidate))),
    Categories.holds(J.Json, (candidate => Configuration.config_lease_requirements(candidate))), source)) ->
  {Configuration.config_effort_requirements(source) == True{} : Bool}:
  Categories.project_intersection_first(J.Json, Categories.holds(J.Json, (candidate => Configuration.config_effort_requirements(candidate))),
    Categories.holds(J.Json, (candidate => Configuration.config_lease_requirements(candidate))), source, evidence)

def adaptive_lease_authority(+source: J.Json,
  evidence: Categories.intersection(J.Json, Categories.holds(J.Json, (candidate => Configuration.config_effort_requirements(candidate))),
    Categories.holds(J.Json, (candidate => Configuration.config_lease_requirements(candidate))), source)) ->
  {Configuration.config_lease_requirements(source) == True{} : Bool}:
  Categories.project_intersection_second(J.Json, Categories.holds(J.Json, (candidate => Configuration.config_effort_requirements(candidate))),
    Categories.holds(J.Json, (candidate => Configuration.config_lease_requirements(candidate))), source, evidence)

def evaluator_endpoint_authority(+source: J.Json,
  evidence: Categories.intersection(J.Json, Categories.holds(J.Json, (candidate => Configuration.config_endpoint_requirements(candidate))),
    Categories.holds(J.Json, (candidate => Configuration.config_timing_requirements(candidate))), source)) ->
  {Configuration.config_endpoint_requirements(source) == True{} : Bool}:
  Categories.project_intersection_first(J.Json, Categories.holds(J.Json, (candidate => Configuration.config_endpoint_requirements(candidate))),
    Categories.holds(J.Json, (candidate => Configuration.config_timing_requirements(candidate))), source, evidence)

def evaluator_timing_authority(+source: J.Json,
  evidence: Categories.intersection(J.Json, Categories.holds(J.Json, (candidate => Configuration.config_endpoint_requirements(candidate))),
    Categories.holds(J.Json, (candidate => Configuration.config_timing_requirements(candidate))), source)) ->
  {Configuration.config_timing_requirements(source) == True{} : Bool}:
  Categories.project_intersection_second(J.Json, Categories.holds(J.Json, (candidate => Configuration.config_endpoint_requirements(candidate))),
    Categories.holds(J.Json, (candidate => Configuration.config_timing_requirements(candidate))), source, evidence)

# The admitted producer uses the exact candidate from the membership. No
# normalized subset can stand in for the original complete observation.
def evaluator_admitted_projection(+source: J.Json,
  evidence: Categories.intersection(J.Json, Categories.holds(J.Json, (candidate => Configuration.config_endpoint_requirements(candidate))),
    Categories.holds(J.Json, (candidate => Configuration.config_timing_requirements(candidate))), source)) ->
  {Configuration.config_evaluator_admitted(Some{Categories.Membership{source, evidence}}) == Configuration.config_literal(J.Null{}) : J.Json}:
  {==}

def evaluator_rejected_projection() ->
  {Configuration.config_evaluator_admitted(None{}) == Configuration.config_failure("Invalid evaluator deadline or same-provider retry bound") : J.Json}:
  {==}

def adaptive_admitted_projection(+source: J.Json,
  evidence: Categories.intersection(J.Json, Categories.holds(J.Json, (candidate => Configuration.config_effort_requirements(candidate))),
    Categories.holds(J.Json, (candidate => Configuration.config_lease_requirements(candidate))), source)) ->
  {Configuration.config_adaptive_admitted(Some{Categories.Membership{source, evidence}}) == Configuration.config_adaptive_projection(source) : J.Json}:
  {==}

def adaptive_rejected_projection() ->
  {Configuration.config_adaptive_admitted(None{}) == Configuration.config_failure("Adaptive reasoning requires an evaluator, distinct actual efforts, a supported baseline, transport, and a lease bound of 1..10") : J.Json}:
  {==}

def defaults_production(+source: J.Json) ->
  {Configuration.run("config.defaults", source) == Model.success(Configuration.config_defaults(source)) : J.Json}:
  {==}

def configuration_head_production(+source: J.Json) ->
  {Configuration.run("config.configuration_head", source) == Model.success(Configuration.config_configuration_head(source)) : J.Json}:
  {==}

def configuration_transport_production(+source: J.Json) ->
  {Configuration.run("config.configuration_transport", source) == Model.success(Configuration.config_configuration_transport(source)) : J.Json}:
  {==}

def configuration_extensions_production(+source: J.Json) ->
  {Configuration.run("config.configuration_extensions", source) == Model.success(Configuration.config_configuration_extensions(source)) : J.Json}:
  {==}

def evaluators_production(+source: J.Json) ->
  {Configuration.run("config.evaluators", source) == Model.success(Configuration.config_evaluators(source)) : J.Json}:
  {==}

def evaluator_plan_production(+source: J.Json) ->
  {Configuration.run("config.evaluator_plan", source) == Model.success(Configuration.config_evaluator_plan(source)) : J.Json}:
  {==}

def evaluator_entry_production(+source: J.Json) ->
  {Configuration.run("config.evaluator_entry", source) == Model.success(Configuration.config_evaluator_entry(source)) : J.Json}:
  {==}

def adaptive_policy_production(+source: J.Json) ->
  {Configuration.run("config.adaptive_policy", source) == Model.success(Configuration.config_adaptive_policy(source)) : J.Json}:
  {==}

def auto_preset_production(+source: J.Json) ->
  {Configuration.run("config.auto_preset", source) == Model.success(Configuration.config_auto_preset(source)) : J.Json}:
  {==}
