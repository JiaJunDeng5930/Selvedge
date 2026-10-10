import Base
import ../../bendlib/categories.bend as Categories
import ../controls/BUTTONS.bend as Buttons
import ../../interaction/IDENTITY.bend as Identity
import ../document/SOURCE.bend as Source
import ../controls/SHELL.bend as Shell
import ../controls/authored-primitives.bend as Factory
import ../controls/CONTROLS.bend as AuthoredControls
import ../controls/PROGRAM.bend as Controls
import ../appearance/MODEL.bend as Appearance
import ../layout/physical-space.bend as Space
import ../layout/GEOMETRY.bend as Spatial
import ../appearance/TYPOGRAPHY.bend as T
import ../document/MODEL.bend as Doc

type Purpose is Data:
  Preparing{}
  Recovery{message: String}

def message(purpose: Purpose) -> String:
  match purpose:
    case Preparing{}: "Preparing interface…"
    case Recovery{message}: message

def root_key() -> Identity.Key: Identity.place("@browser/utility")

def retry_key() -> Identity.Key: Identity.part(root_key(), "retry")

def owned(node: Source.Node) -> Bool:
  Identity.same(Source.key_of(node), root_key())

def retry_style(+font: T.Presentation) -> Source.Style:
  +face: Controls.Face = Controls.IconFace{Controls.Refresh{}}
  +visual = Appearance.action_style(Appearance.ordinary_button(font), face,
    Controls.geometry_for(Controls.NamedAction{}, face, Controls.PageArea{}))
  Factory.style(visual, Space.NaturalSize{}, Space.NaturalSize{}, Space.Confined{})

type RecoveryButton is Data:
  RecoveryButton{font: T.Presentation, reason: String}

def recovery_source(request: RecoveryButton) -> Source.Node:
  RecoveryButton{+font, +reason} = request
  Source.Control{retry_key(), Source.Button{}, retry_style(font),
    [Source.DataAttribute{"native-key", Identity.encode(retry_key())}, Source.TitleAttribute{"Retry rendering: " ++ reason}], "Retry rendering: " ++ reason,
    True{}, Doc.Activate{"@browser/retry"}, Nil{},
    [AuthoredControls.glyph(Identity.part(retry_key(), "icon"), Controls.Refresh{}, Appearance.ordinary_button(font), 16n)]}


def retry(+font: T.Presentation, +reason: String) -> Source.Node:
  recovery_source(RecoveryButton{font, reason})

type RecoveryObservation is Data:
  RecoveryObservation{request: RecoveryButton, node: Source.Node}

type RecoveryProtocol is Data:
  RecoveryProtocol{key: Identity.Key, attributes: +List<Source.Attribute>, name: String,
    enabled: Bool, first: Doc.DOMEvent, remaining: +List<Doc.DOMEvent>}

def recovery_protocol_fields(node: Source.Node) -> Maybe<&2, RecoveryProtocol>:
  match node:
    case Source.Control{key, tag, style, attributes, name, enabled, first, remaining, children}:
      Some{RecoveryProtocol{key, attributes, name, enabled, first, remaining}}
    case _: None{}

def recovery_expected_protocol(request: RecoveryButton) -> Maybe<&2, RecoveryProtocol>:
  RecoveryButton{font, +reason} = request
  Some{RecoveryProtocol{retry_key(),
    [Source.DataAttribute{"native-key", Identity.encode(retry_key())}, Source.TitleAttribute{"Retry rendering: " ++ reason}],
    "Retry rendering: " ++ reason, True{}, Doc.Activate{"@browser/retry"}, Nil{}}}

def recovery_native(observation: RecoveryObservation) -> Type:
  RecoveryObservation{request, node} = observation
  {Buttons.native_tag(node) == Some{Source.Button{}} : Maybe<&2, Source.ControlTag>}

def recovery_protocol(observation: RecoveryObservation) -> Type:
  RecoveryObservation{request, node} = observation
  {recovery_protocol_fields(node) == recovery_expected_protocol(request) : Maybe<&2, RecoveryProtocol>}

def recovery_centered(observation: RecoveryObservation) -> Type:
  RecoveryObservation{request, node} = observation
  {Buttons.centered_glyph_children(Source.children_of(node)) == True{} : Bool}

def recovery_protocol_centered(observation: RecoveryObservation) -> Type:
  Categories.intersection(RecoveryObservation, recovery_protocol, recovery_centered, observation)

def authored_recovery(observation: RecoveryObservation) -> Type:
  Categories.intersection(RecoveryObservation, recovery_native, recovery_protocol_centered, observation)

def authored_recovery_native() -> Categories.Inclusion<RecoveryObservation, authored_recovery, recovery_native>:
  Categories.intersection_first(RecoveryObservation, recovery_native, recovery_protocol_centered)

def authored_recovery_protocol() -> Categories.Inclusion<RecoveryObservation, authored_recovery, recovery_protocol>:
  Categories.inclusion_compose(RecoveryObservation, authored_recovery, recovery_protocol_centered, recovery_protocol,
    Categories.intersection_second(RecoveryObservation, recovery_native, recovery_protocol_centered),
    Categories.intersection_first(RecoveryObservation, recovery_protocol, recovery_centered))

def authored_recovery_centered() -> Categories.Inclusion<RecoveryObservation, authored_recovery, recovery_centered>:
  Categories.inclusion_compose(RecoveryObservation, authored_recovery, recovery_protocol_centered, recovery_centered,
    Categories.intersection_second(RecoveryObservation, recovery_native, recovery_protocol_centered),
    Categories.intersection_second(RecoveryObservation, recovery_protocol, recovery_centered))

law recovery_evidence:
  @+request: RecoveryButton -> authored_recovery(RecoveryObservation{request, recovery_source(request)})

law construct_recovery:
  @+request: RecoveryButton -> Categories.Membership<RecoveryObservation, authored_recovery>

def recovery_children(purpose: Purpose, +font: T.Presentation) -> +List<Source.Node>:
  match purpose:
    case Preparing{}: Nil{}
    case Recovery{reason}: [retry(font, reason)]

def diagnostic(purpose: Purpose, +font: T.Presentation, glyph_only: Bool) -> Source.Node:
  match glyph_only:
    case False{}: Factory.text(Identity.part(root_key(), "message"), message(purpose), Source.ExplicitFont{font}, T.WrapWords{})
    case True{}: AuthoredControls.glyph(Identity.part(root_key(), "message"), Controls.Warning{}, Appearance.base_style(font), 16n)

def source(+purpose: Purpose, +font: T.Presentation, glyph_only: Bool) -> Source.Node:
  Source.Box{root_key(), Source.Section{},
    Shell.neutral(font, Space.Vertical{}, Space.StretchSize{}, Space.NaturalSize{}, Spatial.Leading{}),
    [Source.RoleAttribute{"status"}, Source.AriaAttribute{"label", message(purpose)}, Source.TitleAttribute{message(purpose)}],
    diagnostic(purpose, font, glyph_only) <> recovery_children(purpose, font)}

def supported_forest(nodes: +List<Source.Node>) -> Bool:
  match nodes:
    case Nil{}: True{}
    case Con{Source.Box{key, tag, style, attrs, children}, rest}: supported_forest(children) && supported_forest(rest)
    case Con{Source.Control{key, tag, style, attrs, name, enabled, first, remaining, children}, rest}: supported_forest(children) && supported_forest(rest)
    case Con{Source.Text{key, text, font, wrap}, rest}: supported_forest(rest)
    case Con{Source.Glyph{key, drawing, style}, rest}: supported_forest(rest)
    case Con{node, rest}: False{}

def supported(node: Source.Node) -> Bool:
  supported_forest([node])
