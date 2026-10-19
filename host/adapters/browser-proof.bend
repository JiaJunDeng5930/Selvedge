import Base
import ../../bendlib/json.bend as J
import ../../bendlib/categories.bend as Categories
import ./BROWSER.bend as Browser
import ./MODEL.bend as Model

def Browser.admitted_navigation_original_source():
  source => evidence => {==}

def navigation_raw_projection(source: J.Json, evidence: Browser.navigation(source),
    inclusion: Categories.Inclusion<J.Json, Browser.navigation, Browser.raw_category()>) ->
    {Browser.raw_valid(source) == True{} : Bool}:
  Categories.Inclusion{project} = inclusion
  project(source, evidence)

def navigation_protocol_projection(+source: J.Json, evidence: Browser.navigation(source),
    outer: Categories.Inclusion<J.Json, Browser.navigation,
      (value => Categories.intersection(J.Json, Browser.protocol_category(), Browser.normalized_category(), value))>,
    inner: Categories.Inclusion<J.Json,
      (value => Categories.intersection(J.Json, Browser.protocol_category(), Browser.normalized_category(), value)), Browser.protocol_category()>) ->
    {Browser.protocol_allowed(source) == True{} : Bool}:
  Categories.Inclusion{project} = outer
  Categories.Inclusion{protocol} = inner
  protocol(source, project(source, evidence))

def navigation_normalized_projection(+source: J.Json, evidence: Browser.navigation(source),
    outer: Categories.Inclusion<J.Json, Browser.navigation,
      (value => Categories.intersection(J.Json, Browser.protocol_category(), Browser.normalized_category(), value))>,
    inner: Categories.Inclusion<J.Json,
      (value => Categories.intersection(J.Json, Browser.protocol_category(), Browser.normalized_category(), value)), Browser.normalized_category()>) ->
    {Browser.normalized_target(source) == True{} : Bool}:
  Categories.Inclusion{project} = outer
  Categories.Inclusion{normalized} = inner
  normalized(source, project(source, evidence))

def Browser.admitted_navigation_raw():
  source => evidence => navigation_raw_projection(source, evidence, Browser.navigation_raw())

def Browser.admitted_navigation_protocol():
  source => evidence => navigation_protocol_projection(source, evidence,
    Browser.navigation_protocol_normalized(),
    Categories.intersection_first(J.Json, Browser.protocol_category(), Browser.normalized_category()))

def Browser.admitted_navigation_normalized():
  source => evidence => navigation_normalized_projection(source, evidence,
    Browser.navigation_protocol_normalized(),
    Categories.intersection_second(J.Json, Browser.protocol_category(), Browser.normalized_category()))

def Browser.admitted_navigation_result():
  source => evidence => {==}

def Browser.link_correspondence():
  source => {==}

def Browser.stream_correspondence():
  source => {==}

def Browser.update_rejected():
  entry => parts => index => text => {==}

def Browser.update_committed():
  entry => parts => index => text => {==}

def Browser.removal_owned():
  entry => rest => notice => {==}

def Browser.removal_unrelated():
  entry => rest => notice => {==}

def Browser.limit_correspondence():
  parts => found => text => {==}

def Browser.host_stream_correspondence():
  source => {==}

def Browser.host_unlimited():
  parts => found => text => {==}

def Browser.update_first_hit():
  bounded => entry => rest => notice => tail => {==}

def Browser.update_policy_unrelated():
  bounded => entry => rest => notice => tail => {==}

def Browser.end_policy_removal():
  bounded => state => notice => {==}

def host_stream_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Browser.run_host_stream(selected, operation, source) == Browser.meaning_host_stream(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Browser.host_stream_correspondence()(source)
    case False{}: {==}

def stream_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Browser.run_stream(selected, operation, source) == Browser.meaning_stream(selected, operation, source) : J.Json}:
  match selected:
    case True{}: Browser.stream_correspondence()(source)
    case False{}: host_stream_dispatch(String.eq(operation, "browser.host_stream_step"), operation, source)

def link_dispatch(selected: Bool, +operation: String, +source: J.Json) ->
    {Browser.run_link(selected, operation, source) == Browser.meaning_link(selected, operation, source) : J.Json}:
  match selected:
    case True{}:
      Equal.cong(J.Json, J.Json, (value => Model.success(value)),
        Browser.link(source), Browser.link_calculation(source), Browser.link_correspondence()(source))
    case False{}: stream_dispatch(String.eq(operation, "browser.stream_step"), operation, source)

def complete_dispatch(+operation: String, +source: J.Json) ->
    {Browser.run(operation, source) == Browser.meaning(operation, source) : J.Json}:
  link_dispatch(String.eq(operation, "browser.link"), operation, source)

def Browser.complete_correspondence():
  operation => source => complete_dispatch(operation, source)
