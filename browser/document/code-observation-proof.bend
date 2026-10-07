import Base
import ../../interaction/conversation/CODE.bend as Code
import ./code-observation.bend as Observation
import ./code-observation-rules.bend as Rule
import ../runtime/MODEL.bend as Browser
import ../layout/CONTENT.bend as Content
import ../runtime/SEMANTICS.bend as Legacy
import ../MODEL.bend as Web
import ./SOURCE.bend as Source

def Rule.published_qualification(generation, observations, state):
  match state:
    case Browser.State{legacy, serial, anchors, lifecycle, displayed}:
      match displayed:
        case None{}: {==}
        case Some{Browser.Published{world, semantic, scope, basis, frame}}:
          match world:
            case Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}: {==}

def Rule.rejected_batch(generation, observations, state, rejected):
  Equal.cong(Bool, Browser.Decision,
    (qualified => Browser.code_sources_if_qualified(qualified, observations, state)),
    Browser.code_batch_qualified(generation, observations, state), False{}, rejected)

def Rule.qualified_batch(generation, observations, state, qualified):
  Equal.cong(Bool, Browser.Decision,
    (admitted => Browser.code_sources_if_qualified(admitted, observations, state)),
    Browser.code_batch_qualified(generation, observations, state), True{}, qualified)

def Rule.empty_batch(generation, state):
  match state:
    case Browser.State{legacy, serial, anchors, lifecycle, displayed}:
      match displayed:
        case None{}: {==}
        case Some{Browser.Published{world, semantic, scope, basis, frame}}:
          match world:
            case Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}: {==}

def Rule.invalid_published_batch(generation, observations, state, invalid):
  match state:
    case Browser.State{legacy, serial, anchors, lifecycle, displayed}:
      match displayed:
        case None{}: {==}
        case Some{Browser.Published{world, semantic, scope, basis, frame}}:
          match world:
            case Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}:
              Equal.cong(Bool, Browser.Decision,
                (owned => Browser.code_sources_if_qualified(owned, observations, state)),
                Browser.code_batch_owned(observations, source), False{}, invalid)

def Rule.stale_batch(generation, observations, state, stale):
  Rule.invalid_published_batch(generation, observations, state, stale)

def Rule.unowned_entry(identity, text, source_value, rest, source, unowned):
  Equal.cong(Bool, Bool,
    (owned => owned && Browser.code_observations_owned(rest, source)),
    Browser.code_source_owned(source, identity, source_value), False{}, unowned)

def unowned_tail_result(+owned: Bool, +rest: +List<Observation.Observation>, +source: Source.Node,
    invalid: {Browser.code_observations_owned(rest, source) == False{} : Bool}) ->
    {owned && Browser.code_observations_owned(rest, source) == False{} : Bool}:
  match owned:
    case False{}: {==}
    case True{}: invalid

def Rule.unowned_tail(observation, rest, source, invalid):
  match observation:
    case Observation.Observation{identity, text, source_value}:
      unowned_tail_result(Browser.code_source_owned(source, identity, source_value), rest, source, invalid)

def Rule.fold_empty(decision): {==}
def Rule.fold_order(source, ordinal, text, source_value, rest, state, effects): {==}
def Rule.native_batch(generation, observations, state): {==}
def Rule.raw_source_rejected(identity, text, state): {==}
def Rule.raw_content_rejected(identity, text, state): {==}
def Rule.direct_web_rejected(generation, observations, state):
  match state:
    case Web.State{application, serial, realization, environment, font}: {==}

def Rule.missing_publication(generation, observations, state):
  match state:
    case Browser.State{legacy, serial, anchors, lifecycle, displayed}: {==}
def Rule.all_entries(identity, text, source_value, rest, source): {==}

def Rule.declared_content(owner, identity, value, source_value, policy):
  match identity:
    case Code.Identity{source, ordinal}: {==}
def Rule.undeclared_content(identity, value, source_value, policy):
  match identity:
    case Code.Identity{source, ordinal}: {==}
def Rule.generation_independent(first, second, observations, state):
  match state:
    case Browser.State{legacy, serial, anchors, lifecycle, displayed}:
      match displayed:
        case None{}: {==}
        case Some{Browser.Published{world, semantic, scope, basis, frame}}:
          match world:
            case Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}: {==}

def Rule.authored_source(key, value, visual, code_visual, owner, attachments, native_owner, identity, source_value):
  match identity:
    case Code.Identity{source, ordinal}: {==}
def Rule.stream_source(task, operation, index, text, parent, state): {==}
