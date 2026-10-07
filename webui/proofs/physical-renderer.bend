import Base
import ../physical-renderer-rules.bend as Rule
import ../physical-renderer.bend as Renderer
import ../physical-content.bend as Content
import ../physical-allocation.bend as Allocation
import ../source.bend as Source
import ../document.bend as Doc
import ../typography.bend as T
import ../paint-rules.bend as PaintRule
import ../physical-space.bend as Model
import ../../core/ui-identity.bend as Identity

def rich_parent(+capacity: Nat, +font: T.Presentation, policy: Source.RichPolicy) ->
  {Rule.text_properties(Renderer.rich_styles_at(capacity, font, policy)) == PaintRule.text_style(T.resolve_presentation(capacity, font)) : (String & (String & (String & String)))}:
  match policy:
    case Source.RichPolicy{Source.CodeSurface{frame, surface}, toolbar, gap, indent, code, wrap}: {==}

def admitted_world(+snapshot: Content.Snapshot, +tree: Allocation.AllocatedTree<Content.Value, Doc.Event>, +roots: +List<Content.AllocatedNative>, +policies: +List<Content.NativePolicy>, valid: {Renderer.native_roots_valid(roots, tree) && Renderer.native_policies_valid(policies, tree) == True{} : Bool}) ->
  {Renderer.nodes(Content.AllocatedWorld{snapshot, tree, roots, policies}) == (Renderer.root_theme(snapshot) <> Renderer.emit_world(tree, roots, policies, True{})) : +List<Doc.Node>}:
  Equal.cong(Bool, +List<Doc.Node>, (valid => Renderer.projected_world(snapshot, tree, roots, policies, valid)), Renderer.native_roots_valid(roots, tree) && Renderer.native_policies_valid(policies, tree), True{}, valid)

def rejected_world(+snapshot: Content.Snapshot, +tree: Allocation.AllocatedTree<Content.Value, Doc.Event>, +roots: +List<Content.AllocatedNative>, +policies: +List<Content.NativePolicy>, invalid: {Renderer.native_roots_valid(roots, tree) && Renderer.native_policies_valid(policies, tree) == False{} : Bool}) ->
  {Renderer.nodes(Content.AllocatedWorld{snapshot, tree, roots, policies}) == Renderer.emit_world(tree, roots, policies, False{}) : +List<Doc.Node>}:
  Equal.cong(Bool, +List<Doc.Node>, (valid => Renderer.projected_world(snapshot, tree, roots, policies, valid)), Renderer.native_roots_valid(roots, tree) && Renderer.native_policies_valid(policies, tree), False{}, invalid)

def reading_box(+capacity: Nat, +key: Identity.Key, +tag: Source.BoxTag, +style: Source.Style,
  +attrs: +List<Source.Attribute>, +original: +List<Source.Node>, +font: T.Presentation,
  interaction: Model.Interaction<Doc.Event>, +styles: +List<Doc.Property>, children: +List<Doc.Node>, native: Bool, +content: Bool,
  recognized: {Renderer.reading_content(attrs) == content : Bool}) ->
  Rule.reading_box_claim(capacity, key, tag, style, attrs, original, font, interaction, styles, children, native, content):
  Equal.cong(Bool, +List<Doc.Property>,
    (is_content => Renderer.reading_styles(is_content, Renderer.properties(styles, Renderer.properties(Renderer.primitive_styles_at(capacity, Content.Value{Source.Box{key, tag, style, attrs, original}, font}), Renderer.visual(style))))),
    Renderer.reading_content(attrs), content, recognized)

def Rule.evidence():
  Rule.Requirements{reading_box, styles => {==}, styles => {==}, rich_parent, generation => key => tag => style => children => font => theme => {==}, admitted_world, rejected_world}
