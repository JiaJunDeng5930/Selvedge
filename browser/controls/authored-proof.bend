import Base
import ./CONTROLS.bend as A
import ../../bendlib/categories.bend as Categories
import ./PROGRAM.bend as Controls
import ../appearance/DESIGN.bend as Design
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes
import ../../interaction/IDENTITY.bend as UIIdentity
import ../../interaction/presentation/MODEL.bend as View

def request_binding_projection(+label: Controls.LabelPlacement, +key: UIIdentity.Key, +name: String, +visual: Design.Style, +request: A.InputFieldRequest) -> {A.observed_binding(A.selected_field(label, A.interpret_input_field(label, key, name, visual, request))) == Some{A.request_binding(request)} : Maybe<&2, A.FieldBinding>}:
  match label:
    case Controls.AboveInput{}:
      A.InputFieldRequest{binding, content, protocol} = request
      A.FieldBinding{field_key, attributes} = binding
      A.FieldContent{kind, style, value, placeholder, options, policy, field_name} = content
      A.FieldProtocol{enabled, first, remaining} = protocol
      {==}
    case Controls.AccessibleOnly{}:
      A.InputFieldRequest{binding, content, protocol} = request
      A.FieldBinding{field_key, attributes} = binding
      A.FieldContent{kind, style, value, placeholder, options, policy, field_name} = content
      A.FieldProtocol{enabled, first, remaining} = protocol
      {==}
    case Controls.BesideInput{}:
      A.InputFieldRequest{binding, content, protocol} = request
      A.FieldBinding{field_key, attributes} = binding
      A.FieldContent{kind, style, value, placeholder, options, policy, field_name} = content
      A.FieldProtocol{enabled, first, remaining} = protocol
      {==}

def request_content_projection(+label: Controls.LabelPlacement, +key: UIIdentity.Key, +name: String, +visual: Design.Style, +request: A.InputFieldRequest) -> {A.observed_content(A.selected_field(label, A.interpret_input_field(label, key, name, visual, request))) == Some{A.request_content(request)} : Maybe<&2, A.FieldContent>}:
  match label:
    case Controls.AboveInput{}:
      A.InputFieldRequest{binding, content, protocol} = request
      A.FieldBinding{field_key, attributes} = binding
      A.FieldContent{kind, style, value, placeholder, options, policy, field_name} = content
      A.FieldProtocol{enabled, first, remaining} = protocol
      {==}
    case Controls.AccessibleOnly{}:
      A.InputFieldRequest{binding, content, protocol} = request
      A.FieldBinding{field_key, attributes} = binding
      A.FieldContent{kind, style, value, placeholder, options, policy, field_name} = content
      A.FieldProtocol{enabled, first, remaining} = protocol
      {==}
    case Controls.BesideInput{}:
      A.InputFieldRequest{binding, content, protocol} = request
      A.FieldBinding{field_key, attributes} = binding
      A.FieldContent{kind, style, value, placeholder, options, policy, field_name} = content
      A.FieldProtocol{enabled, first, remaining} = protocol
      {==}

def request_protocol_projection(+label: Controls.LabelPlacement, +key: UIIdentity.Key, +name: String, +visual: Design.Style, +request: A.InputFieldRequest) -> {A.observed_protocol(A.selected_field(label, A.interpret_input_field(label, key, name, visual, request))) == Some{A.request_protocol(request)} : Maybe<&2, A.FieldProtocol>}:
  match label:
    case Controls.AboveInput{}:
      A.InputFieldRequest{binding, content, protocol} = request
      A.FieldBinding{field_key, attributes} = binding
      A.FieldContent{kind, style, value, placeholder, options, policy, field_name} = content
      A.FieldProtocol{enabled, first, remaining} = protocol
      {==}
    case Controls.AccessibleOnly{}:
      A.InputFieldRequest{binding, content, protocol} = request
      A.FieldBinding{field_key, attributes} = binding
      A.FieldContent{kind, style, value, placeholder, options, policy, field_name} = content
      A.FieldProtocol{enabled, first, remaining} = protocol
      {==}
    case Controls.BesideInput{}:
      A.InputFieldRequest{binding, content, protocol} = request
      A.FieldBinding{field_key, attributes} = binding
      A.FieldContent{kind, style, value, placeholder, options, policy, field_name} = content
      A.FieldProtocol{enabled, first, remaining} = protocol
      {==}

def input_widget_evidence(+key: UIIdentity.Key, +meaning: SurfaceTypes.Meaning, +name: String, +widget: Controls.Widget, +label: Controls.LabelPlacement, +availability: View.Availability, +visual: Design.Style, +parameters: Design.LayoutParameters, +request: A.InputFieldRequest, requested: A.input_requested(A.InputObservation{key, Controls.FormInput{meaning, name, widget, label, availability}, visual, parameters, request, A.input_source_request(key, Controls.FormInput{meaning, name, widget, label, availability}, visual, request)})) -> A.authored_input(A.InputObservation{key, Controls.FormInput{meaning, name, widget, label, availability}, visual, parameters, request, A.input_source_request(key, Controls.FormInput{meaning, name, widget, label, availability}, visual, request)}):
  match widget:
    case Controls.PlainValue{}:
      Categories.Intersection{requested, Categories.Intersection{{==}, Categories.Intersection{{==}, {==}}}}
    case Controls.TextInput{}:
      Categories.Intersection{requested, Categories.Intersection{request_binding_projection(label, key, name, visual, request), Categories.Intersection{request_content_projection(label, key, name, visual, request), request_protocol_projection(label, key, name, visual, request)}}}
    case Controls.TextArea{}:
      Categories.Intersection{requested, Categories.Intersection{request_binding_projection(label, key, name, visual, request), Categories.Intersection{request_content_projection(label, key, name, visual, request), request_protocol_projection(label, key, name, visual, request)}}}
    case Controls.NumberInput{minimum}:
      Categories.Intersection{requested, Categories.Intersection{request_binding_projection(label, key, name, visual, request), Categories.Intersection{request_content_projection(label, key, name, visual, request), request_protocol_projection(label, key, name, visual, request)}}}
    case Controls.ToggleInput{}:
      Categories.Intersection{requested, Categories.Intersection{request_binding_projection(label, key, name, visual, request), Categories.Intersection{request_content_projection(label, key, name, visual, request), request_protocol_projection(label, key, name, visual, request)}}}
    case Controls.SelectInput{}:
      Categories.Intersection{requested, Categories.Intersection{request_binding_projection(label, key, name, visual, request), Categories.Intersection{request_content_projection(label, key, name, visual, request), request_protocol_projection(label, key, name, visual, request)}}}
    case Controls.AttachmentList{}:
      Categories.Intersection{requested, Categories.Intersection{request_binding_projection(label, key, name, visual, request), Categories.Intersection{request_content_projection(label, key, name, visual, request), request_protocol_projection(label, key, name, visual, request)}}}
    case Controls.SearchInput{}:
      Categories.Intersection{requested, Categories.Intersection{request_binding_projection(label, key, name, visual, request), Categories.Intersection{request_content_projection(label, key, name, visual, request), request_protocol_projection(label, key, name, visual, request)}}}
    case Controls.SecretInput{}:
      Categories.Intersection{requested, Categories.Intersection{request_binding_projection(label, key, name, visual, request), Categories.Intersection{request_content_projection(label, key, name, visual, request), request_protocol_projection(label, key, name, visual, request)}}}
    case Controls.MessageInput{}:
      Categories.Intersection{requested, Categories.Intersection{request_binding_projection(label, key, name, visual, request), Categories.Intersection{request_content_projection(label, key, name, visual, request), request_protocol_projection(label, key, name, visual, request)}}}
    case Controls.MultiSelectInput{}:
      Categories.Intersection{requested, Categories.Intersection{request_binding_projection(label, key, name, visual, request), Categories.Intersection{request_content_projection(label, key, name, visual, request), request_protocol_projection(label, key, name, visual, request)}}}
    case Controls.DirectoryList{}:
      Categories.Intersection{requested, Categories.Intersection{request_binding_projection(label, key, name, visual, request), Categories.Intersection{request_content_projection(label, key, name, visual, request), request_protocol_projection(label, key, name, visual, request)}}}
    case Controls.FileChooser{face}:
      Categories.Intersection{requested, Categories.Intersection{request_binding_projection(label, key, name, visual, request), Categories.Intersection{request_content_projection(label, key, name, visual, request), request_protocol_projection(label, key, name, visual, request)}}}
    case Controls.DirectoryChooser{face}:
      Categories.Intersection{requested, Categories.Intersection{request_binding_projection(label, key, name, visual, request), Categories.Intersection{request_content_projection(label, key, name, visual, request), request_protocol_projection(label, key, name, visual, request)}}}

def input_evidence(+key: UIIdentity.Key, +syntax: Controls.FormInput, +visual: Design.Style, +parameters: Design.LayoutParameters, +request: A.InputFieldRequest, requested: A.input_requested(A.InputObservation{key, syntax, visual, parameters, request, A.input_source_request(key, syntax, visual, request)})) -> A.authored_input(A.InputObservation{key, syntax, visual, parameters, request, A.input_source_request(key, syntax, visual, request)}):
  Controls.FormInput{meaning, name, widget, label, availability} = syntax
  input_widget_evidence(key, meaning, name, widget, label, availability, visual, parameters, request, requested)

def A.input_evidence(): input_evidence

def movable_evidence(+key: UIIdentity.Key, +syntax: Controls.MovableControl, +visual: Design.Style, +parameters: Design.LayoutParameters) -> A.authored_movable(A.MovableObservation{key, syntax, visual, parameters, A.movable_choices(key, syntax, visual, parameters)}):
  Controls.MovableControl{destinations, face, name, handle, geometry} = syntax
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum_height, maximum_width_percent, states} = visual
  Categories.Intersection{{==}, A.MovableProtocol{{==}, {==}, {==}}}

def A.movable_evidence(): movable_evidence

def construct_requested_input(+key: UIIdentity.Key, +syntax: Controls.FormInput, +visual: Design.Style, +parameters: Design.LayoutParameters, +request: A.InputFieldRequest, requested: A.input_requested(A.InputObservation{key, syntax, visual, parameters, request, A.input_source_request(key, syntax, visual, request)})) -> Categories.Membership<A.InputObservation, A.authored_input>:
  Categories.Membership{A.InputObservation{key, syntax, visual, parameters, request, A.input_source_request(key, syntax, visual, request)}, input_evidence(key, syntax, visual, parameters, request, requested)}

def construct_input(+key: UIIdentity.Key, +syntax: Controls.FormInput, +visual: Design.Style, +parameters: Design.LayoutParameters) -> Categories.Membership<A.InputObservation, A.authored_input>:
  construct_requested_input(key, syntax, visual, parameters, A.native_input_request(key, syntax, visual, parameters), {==})

def A.construct_input(): construct_input

def construct_movable(+key: UIIdentity.Key, +syntax: Controls.MovableControl, +visual: Design.Style, +parameters: Design.LayoutParameters) -> Categories.Membership<A.MovableObservation, A.authored_movable>:
  Categories.Membership{A.MovableObservation{key, syntax, visual, parameters, A.movable_choices(key, syntax, visual, parameters)}, movable_evidence(key, syntax, visual, parameters)}

def A.construct_movable(): construct_movable

def A.input_constructor_correspondence():
  +key => +syntax => +visual => +parameters => {==}

def A.movable_constructor_correspondence():
  +key => +syntax => +visual => +parameters => {==}
