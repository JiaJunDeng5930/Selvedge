import Base
import ../core/ui-identity.bend as UIIdentity
import ./physical-plan.bend as Plan
import ./physical-content.bend as Content
import ./physical-renderer.bend as Renderer
import ./source.bend as Source
import ./document.bend as Doc
import ./paint.bend as Paint

def purpose_name(purpose: Content.Purpose) -> String:
  match purpose:
    case Content.Natural{}: "natural"
    case Content.AtWidth{width}: "at-width"

def mode_name(mode: Plan.ProbeMode) -> String:
  match mode:
    case Plan.Measure{}: "measure"
    case Plan.TargetsOnly{}: "targets-only"

def metadata(generation: Nat, +key: String, +purpose: Content.Purpose, mode: Plan.ProbeMode) -> +List<Doc.Property>:
  [Paint.property("data-probe-generation", Nat.show(generation)), Paint.property("data-probe-key", key),
   Paint.property("data-probe-purpose", purpose_name(purpose)), Paint.property("data-probe-mode", mode_name(mode)),
   Paint.property("aria-hidden", "true"), Paint.property("inert", "")]

# Visibility preserves intrinsic browser layout while this subtree receives no input.
def hidden_styles() -> +List<Doc.Property>:
  [Paint.property("position", "fixed"), Paint.property("left", "-100000px"), Paint.property("top", "0"),
   Paint.property("visibility", "hidden"), Paint.property("pointer-events", "none"),
   Paint.property("display", "inline-block"), Paint.property("margin", "0"),
   Paint.property("padding", "0"), Paint.property("border", "0")]

def field_width(purpose: Content.Purpose) -> +List<Doc.Property>:
  match purpose:
    case Content.Natural{}: Nil{}
    case Content.AtWidth{width}: [Paint.property("width", "100%")]

def field_content_attributes_match(textarea: Bool) -> +List<Doc.Property>:
  match textarea:
    case True{}: [Paint.property("data-physical-field-content", "")]
    case False{}: Nil{}
def field_content_attributes(kind: Source.NativeFieldKind) -> +List<Doc.Property>:
  field_content_attributes_match(String.eq(Renderer.field_tag(kind), "textarea"))

def field_content_styles_match(textarea: Bool) -> +List<Doc.Property>:
  match textarea:
    case True{}:
      # The native scroll area owns text height, independently of default rows.
      [Paint.property("height", "0px"), Paint.property("min-height", "0px"),
       Paint.property("overflow", "hidden"), Paint.property("resize", "none")]
    case False{}: Nil{}

def field_content_styles(kind: Source.NativeFieldKind) -> +List<Doc.Property>:
  field_content_styles_match(String.eq(Renderer.field_tag(kind), "textarea"))

def field_target_styles(kind: Source.NativeFieldKind) -> +List<Doc.Property>:
  match kind:
    case Source.ToggleField{}:
      +size = Source.toggle_target_size(Source.native_toggle_geometry())
      [Paint.property("width", Paint.px(size)), Paint.property("height", Paint.px(size))]
    case _: Nil{}

def field_box_styles(+kind: Source.NativeFieldKind) -> +List<Doc.Property>:
  Renderer.properties([Paint.property("display", "block"), Paint.property("margin", "0"), Paint.property("border", "0"),
   Paint.property("padding", "0"), Paint.property("appearance", Source.native_field_appearance(kind)), Paint.property("box-sizing", "border-box")], field_target_styles(kind))

def disabled(enabled: Bool) -> +List<Doc.Property>:
  match enabled:
    case True{}: Nil{}
    case False{}: [Paint.property("disabled", "")]

def root_styles(value: Content.Value) -> +List<Doc.Property>:
  Renderer.properties(hidden_styles(), Renderer.primitive_styles(value))

def unsupported(key: String, +kind: String, attributes: +List<Doc.Property>, styles: +List<Doc.Property>) -> Doc.Node:
  Doc.Element{key, "div", Paint.property("data-probe-error", "unsupported-primitive:" ++ kind) <> attributes,
    styles, Nil{}, [Doc.Text{"Unsupported physical measurement primitive: " ++ kind}]}

def primitive_value(+value: Content.Value, +key: String, +purpose: Content.Purpose, +roots: +List<Content.AllocatedNative>, +policies: +List<Content.NativePolicy>, +attributes: +List<Doc.Property>) -> Doc.Node:
  match value:
    case Content.Value{Source.Text{source_key, +text, choice, wrap}, font}:
      Doc.Element{key, "div", attributes, root_styles(value), Nil{},
        [Doc.Element{UIIdentity.encode(UIIdentity.part(source_key, "text")), "span", Nil{}, Nil{}, Nil{}, [Doc.Text{text}]}]}
    case Content.Value{Source.Field{source_key, +kind, style, +attrs, +text, +placeholder, +options, policy, +name, +enabled, first, remaining}, font}:
      Doc.Element{key, "div", attributes, root_styles(value), Nil{},
        [Doc.Element{UIIdentity.encode(UIIdentity.part(source_key, "field")), Renderer.field_tag(kind),
          Renderer.properties(field_content_attributes(kind), Renderer.properties(Renderer.field_authored(kind, attrs), Renderer.properties(Renderer.field_attributes(kind, text),
            Renderer.properties([Paint.property("class", "native-control"), Paint.property("placeholder", placeholder),
              Paint.property("aria-label", name), Paint.property("tabindex", "-1")], disabled(enabled))))),
          Renderer.properties(field_content_styles(kind), Renderer.properties(Renderer.primitive_styles(value), Renderer.properties(field_width(purpose),
            field_box_styles(kind)))),
          Nil{}, Renderer.choices(options, UIIdentity.part(source_key, "field"))}]}
    case Content.Value{Source.RichText{source_key, style, Source.RichContent{+source, +text, policy}, attachments, native_owner}, font}:
      # Original Code.Source gives parser targets and native portals the same owner.
      Doc.Element{key, "div", Paint.property("class", "physical-markdown") <> attributes, root_styles(value), Nil{},
        Doc.Markdown{UIIdentity.encode(UIIdentity.part(source_key, "markdown")), source, text, native_owner} <> Renderer.native_documents(roots, policies)}
    case Content.Value{Source.Glyph{source_key, drawing, style}, font}:
      unsupported(key, "glyph", attributes, root_styles(value))
    case Content.Value{Source.Box{source_key, tag, style, attrs, children}, font}:
      unsupported(key, "box", attributes, root_styles(value))
    case Content.Value{Source.Control{source_key, tag, style, attrs, name, enabled, first, remaining, children}, font}:
      unsupported(key, "control", attributes, root_styles(value))
    case Content.Value{Source.NativeAttachment{source_key, target, attrs, style, children}, font}:
      unsupported(key, "native-attachment", attributes, root_styles(value))

def primitive(+request: Content.Request, +roots: +List<Content.AllocatedNative>, mode: Plan.ProbeMode) -> Doc.Node:
  Content.Request{generation, +key, +value, +purpose, native_roots, +policies} = request
  primitive_value(value, key, purpose, roots, policies, metadata(generation, key, purpose, mode))

def document(job: Plan.Job) -> Doc.Document:
  Plan.Job{request, roots, mode} = job
  Doc.Document{primitive(request, roots, mode), "Physical content measurement"}

def root_target_keys(values: +List<Content.NativeRoot>) -> +List<String>:
  match values:
    case Nil{}: Nil{}
    case Con{Content.NativeRoot{owner, target, tree, attrs, style}, rest}:
      Source.target_key(target) <> root_target_keys(rest)

def policy_target_keys(values: +List<Content.NativePolicy>) -> +List<String>:
  match values:
    case Nil{}: Nil{}
    case Con{Content.NativePolicy{owner, target, attrs, style}, rest}:
      Source.target_key(target) <> policy_target_keys(rest)

def request_declared_target_keys(request: Content.Request) -> +List<String>:
  Content.Request{generation, key, value, purpose, roots, policies} = request
  List.append(&2, String, root_target_keys(roots), policy_target_keys(policies))


def target_keys(job: Plan.Job) -> +List<String>:
  match job:
    case Plan.Job{request, roots, Plan.TargetsOnly{}}: request_declared_target_keys(request)
    case Plan.Job{request, roots, Plan.Measure{}}: Nil{}
