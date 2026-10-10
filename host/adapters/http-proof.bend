import Base
import ../../bendlib/json.bend as J
import ../../bendlib/categories.bend as Categories
import ./HTTP.bend as H

def H.complete_correspondence():
  operation => source => {==}

def H.admitted_original_source():
  predicate => source => evidence => reject => accept => {==}

def H.rejected_admission_plan():
  predicate => reject => accept => {==}

def H.stopping_precedes_host_observation():
  {==}

def H.open_server_requests_host_observation():
  {==}

def H.host_rejection_precedes_url():
  {==}

def H.admitted_host_requests_url():
  {==}

def H.asset_precedes_authorization():
  source => {==}

def H.connection_requests_only_connection_secret():
  {==}

def H.local_requests_only_local_secret():
  {==}

def H.rejected_connection_authorization():
  {==}

def H.rejected_local_authorization():
  {==}

def H.authorized_connection_requests_method_origin():
  {==}

def H.authorized_local_requests_origin():
  {==}

def H.connection_origin_rejection():
  {==}

def H.admitted_connection_requests_content_type():
  {==}

def H.preflight_factory_admission():
  source => {==}

def H.authorization_factory_admission():
  source => connection => {==}

def H.method_precedes_connection_origin():
  source => {==}

def H.local_origin_precedes_route():
  source => {==}

def H.upload_query_precedes_size():
  source => {==}

def H.upload_size_precedes_stream():
  source => {==}

def H.content_type_precedes_body():
  source => {==}

def H.raw_body_and_current_shape_required():
  source => {==}

def H.body_factory_admission():
  source => {==}

def H.successful_reply_status():
  {==}

def H.failed_reply_status():
  {==}

def H.reply_status_full_result():
  source => {==}

def H.admitted_local_original_source():
  source => evidence => {==}

def H.admitted_connection_original_source():
  source => evidence => {==}

def H.admitted_upload_original_source():
  source => evidence => {==}

def H.admitted_body_payload():
  Request => source => evidence => {==}

def H.admitted_body_original_source():
  Request => source => evidence => {==}

def project_local_open(-source: J.Json, evidence: H.LocalRequest(source)) -> H.Open(source):
  Categories.Intersection{Categories.Intersection{open, host}, Categories.Intersection{authorization, Categories.Intersection{path, origin}}} = evidence
  open

def project_local_host(-source: J.Json, evidence: H.LocalRequest(source)) -> H.Host(source):
  Categories.Intersection{Categories.Intersection{open, host}, Categories.Intersection{authorization, Categories.Intersection{path, origin}}} = evidence
  host

def project_local_authorization(-source: J.Json, evidence: H.LocalRequest(source)) -> H.Authorization(source):
  Categories.Intersection{Categories.Intersection{open, host}, Categories.Intersection{authorization, Categories.Intersection{path, origin}}} = evidence
  authorization

def project_local_path(-source: J.Json, evidence: H.LocalRequest(source)) -> H.LocalPath(source):
  Categories.Intersection{Categories.Intersection{open, host}, Categories.Intersection{authorization, Categories.Intersection{path, origin}}} = evidence
  path

def project_local_origin(-source: J.Json, evidence: H.LocalRequest(source)) -> H.LocalOrigin(source):
  Categories.Intersection{Categories.Intersection{open, host}, Categories.Intersection{authorization, Categories.Intersection{path, origin}}} = evidence
  origin

def project_connection_open(-source: J.Json, evidence: H.ConnectionRequest(source)) -> H.Open(source):
  Categories.Intersection{Categories.Intersection{open, host}, Categories.Intersection{authorization, Categories.Intersection{path, Categories.Intersection{method, origin}}}} = evidence
  open

def project_connection_host(-source: J.Json, evidence: H.ConnectionRequest(source)) -> H.Host(source):
  Categories.Intersection{Categories.Intersection{open, host}, Categories.Intersection{authorization, Categories.Intersection{path, Categories.Intersection{method, origin}}}} = evidence
  host

def project_connection_authorization(-source: J.Json, evidence: H.ConnectionRequest(source)) -> H.Authorization(source):
  Categories.Intersection{Categories.Intersection{open, host}, Categories.Intersection{authorization, Categories.Intersection{path, Categories.Intersection{method, origin}}}} = evidence
  authorization

def project_connection_path(-source: J.Json, evidence: H.ConnectionRequest(source)) -> H.ConnectionPath(source):
  Categories.Intersection{Categories.Intersection{open, host}, Categories.Intersection{authorization, Categories.Intersection{path, Categories.Intersection{method, origin}}}} = evidence
  path

def project_connection_method(-source: J.Json, evidence: H.ConnectionRequest(source)) -> H.ConnectionMethod(source):
  Categories.Intersection{Categories.Intersection{open, host}, Categories.Intersection{authorization, Categories.Intersection{path, Categories.Intersection{method, origin}}}} = evidence
  method

def project_connection_origin(-source: J.Json, evidence: H.ConnectionRequest(source)) -> H.ConnectionOrigin(source):
  Categories.Intersection{Categories.Intersection{open, host}, Categories.Intersection{authorization, Categories.Intersection{path, Categories.Intersection{method, origin}}}} = evidence
  origin

def project_upload_request(-source: J.Json, evidence: H.LocalUpload(source)) -> H.LocalRequest(source):
  Categories.Intersection{request, Categories.Intersection{route, upload}} = evidence
  request

def project_upload_route(-source: J.Json, evidence: H.LocalUpload(source)) -> H.UploadRoute(source):
  Categories.Intersection{request, Categories.Intersection{route, upload}} = evidence
  route

def project_upload_requirements(-source: J.Json, evidence: H.LocalUpload(source)) -> H.Upload(source):
  Categories.Intersection{request, Categories.Intersection{route, upload}} = evidence
  upload

def project_body_request(-Request: J.Json -> Type, -source: J.Json, evidence: H.BodyRequest(Request, source)) -> Request(source):
  Categories.Intersection{Categories.Intersection{request, Categories.Intersection{route, content}}, body} = evidence
  request

def project_body_route(-Request: J.Json -> Type, -source: J.Json, evidence: H.BodyRequest(Request, source)) -> H.BodyRoute(source):
  Categories.Intersection{Categories.Intersection{request, Categories.Intersection{route, content}}, body} = evidence
  route

def project_body_content(-Request: J.Json -> Type, -source: J.Json, evidence: H.BodyRequest(Request, source)) -> H.ContentType(source):
  Categories.Intersection{Categories.Intersection{request, Categories.Intersection{route, content}}, body} = evidence
  content

def project_body_body(-Request: J.Json -> Type, -source: J.Json, evidence: H.BodyRequest(Request, source)) -> H.CurrentBody(source):
  Categories.Intersection{Categories.Intersection{request, Categories.Intersection{route, content}}, body} = evidence
  body

def H.admitted_local_open_evidence():
  source => evidence => project_local_open(source, evidence)

def H.admitted_local_host_evidence():
  source => evidence => project_local_host(source, evidence)

def H.admitted_local_authorization_evidence():
  source => evidence => project_local_authorization(source, evidence)

def H.admitted_local_path_evidence():
  source => evidence => project_local_path(source, evidence)

def H.admitted_local_origin_evidence():
  source => evidence => project_local_origin(source, evidence)

def H.admitted_connection_open_evidence():
  source => evidence => project_connection_open(source, evidence)

def H.admitted_connection_host_evidence():
  source => evidence => project_connection_host(source, evidence)

def H.admitted_connection_authorization_evidence():
  source => evidence => project_connection_authorization(source, evidence)

def H.admitted_connection_path_evidence():
  source => evidence => project_connection_path(source, evidence)

def H.admitted_connection_method_evidence():
  source => evidence => project_connection_method(source, evidence)

def H.admitted_connection_origin_evidence():
  source => evidence => project_connection_origin(source, evidence)

def H.admitted_upload_request_evidence():
  source => evidence => project_upload_request(source, evidence)

def H.admitted_upload_route_evidence():
  source => evidence => project_upload_route(source, evidence)

def H.admitted_upload_requirements_evidence():
  source => evidence => project_upload_requirements(source, evidence)

def H.admitted_body_request_evidence():
  Request => source => evidence => project_body_request(Request, source, evidence)

def H.admitted_body_route_evidence():
  Request => source => evidence => project_body_route(Request, source, evidence)

def H.admitted_body_content_evidence():
  Request => source => evidence => project_body_content(Request, source, evidence)

def H.admitted_body_body_evidence():
  Request => source => evidence => project_body_body(Request, source, evidence)


def H.admitted_content_route_target():
  Request => source => evidence => {==}

def H.admitted_body_route_target():
  Request => source => evidence => {==}
