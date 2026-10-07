import Base
import ../../interaction/IDENTITY.bend as Identity
import ../document/SOURCE.bend as Source
import ../controls/SHELL.bend as Shell
import ../controls/authored-primitives.bend as Factory
import ../controls/CONTROLS.bend as AuthoredControls
import ../controls/PROGRAM.bend as Controls
import ../appearance/MODEL.bend as Appearance
import ../appearance/DESIGN.bend as Design
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

def retry(+font: T.Presentation, +reason: String) -> Source.Node:
  Source.Control{retry_key(), Source.Button{}, retry_style(font),
    [Source.DataAttribute{"native-key", Identity.encode(retry_key())}, Source.TitleAttribute{"Retry rendering: " ++ reason}], "Retry rendering: " ++ reason,
    True{}, Doc.Activate{"@browser/retry"}, Nil{},
    [AuthoredControls.glyph(Identity.part(retry_key(), "icon"), Controls.Refresh{}, Appearance.ordinary_button(font), 16n)]}

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
