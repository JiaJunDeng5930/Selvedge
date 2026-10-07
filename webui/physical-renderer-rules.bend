import Base
import ./physical-renderer.bend as Renderer
import ./physical-content.bend as Content
import ./physical-allocation.bend as Allocation
import ./source.bend as Source
import ./document.bend as Doc
import ./typography.bend as T
import ./paint.bend as Paint
import ./paint-rules.bend as PaintRule
import ./authored-shell.bend as Shell
import ./design.bend as Design
import ./appearance.bend as Appearance
import ./physical-space.bend as Model
import ../core/ui-identity.bend as Identity

def text_properties(+values: +List<Doc.Property>) -> (String & (String & (String & String))):
  (PaintRule.property_value(values, "font-family"), (PaintRule.property_value(values, "font-size"),
    (PaintRule.property_value(values, "line-height"), PaintRule.property_value(values, "font-weight"))))

def node_styles(node: Doc.Node) -> +List<Doc.Property>:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: styles
    case _: Nil{}

def reading_box_claim(+capacity: Nat, +key: Identity.Key, +tag: Source.BoxTag, +style: Source.Style,
  +attrs: +List<Source.Attribute>, +original: +List<Source.Node>, +font: T.Presentation,
  interaction: Model.Interaction<Doc.Event>, +styles: +List<Doc.Property>, children: +List<Doc.Node>, native: Bool, +content: Bool) -> Type:
  {node_styles(Renderer.container_at(capacity, Content.Value{Source.Box{key, tag, style, attrs, original}, font}, interaction, styles, children, native)) ==
    Renderer.reading_styles(content, Renderer.properties(styles, Renderer.properties(Renderer.primitive_styles_at(capacity, Content.Value{Source.Box{key, tag, style, attrs, original}, font}), Renderer.visual(style)))) : +List<Doc.Property>}

type Requirements is Type:
  Requirements{
    reading_box: @+capacity:Nat -> @+key:Identity.Key -> @+tag:Source.BoxTag -> @+style:Source.Style ->
      @+attrs:+List<Source.Attribute> -> @+original:+List<Source.Node> -> @+font:T.Presentation ->
      @interaction:Model.Interaction<Doc.Event> -> @+styles:+List<Doc.Property> -> @children:+List<Doc.Node> -> @native:Bool ->
      @+content:Bool -> @recognized:{Renderer.reading_content(attrs) == content : Bool} ->
      reading_box_claim(capacity, key, tag, style, attrs, original, font, interaction, styles, children, native, content),
    reading_content: @styles:+List<Doc.Property> ->
      {Renderer.reading_styles(True{}, styles) == Renderer.properties(styles, [Paint.property("padding-bottom", "var(--reading-composer-reserve, 0px)")]) : +List<Doc.Property>},
    reading_noncontent: @styles:+List<Doc.Property> -> {Renderer.reading_styles(False{}, styles) == styles : +List<Doc.Property>},
    rich_parent: @+capacity:Nat -> @+font:T.Presentation -> @policy:Source.RichPolicy ->
      {text_properties(Renderer.rich_styles_at(capacity, font, policy)) == PaintRule.text_style(T.resolve_presentation(capacity, font)) : (String & (String & (String & String)))},
    root_theme: @generation:Nat -> @key:Identity.Key -> @tag:Source.BoxTag -> @style:Source.Style -> @children:+List<Source.Node> -> @font:T.Presentation -> @theme:Design.Theme ->
      {Renderer.root_theme(Content.Snapshot{generation, Source.Box{key, tag, style, [Source.DataAttribute{"theme", Shell.theme_name(theme)}], children}, font}) ==
        Doc.TargetProperties{"@browser/root-theme", "@document/root", [Doc.Property{"data-theme", Shell.theme_name(theme)}], Paint.focus_indicator_style(Appearance.default_focus_indicator())} : Doc.Node},
    admitted_world: @+snapshot:Content.Snapshot -> @+tree:Allocation.AllocatedTree<Content.Value, Doc.Event> -> @+roots:+List<Content.AllocatedNative> -> @+policies:+List<Content.NativePolicy> ->
      @valid:{Renderer.native_roots_valid(roots, tree) && Renderer.native_policies_valid(policies, tree) == True{} : Bool} ->
      {Renderer.nodes(Content.AllocatedWorld{snapshot, tree, roots, policies}) ==
        (Renderer.root_theme(snapshot) <> Renderer.emit_world(tree, roots, policies, True{})) : +List<Doc.Node>},
    rejected_world: @+snapshot:Content.Snapshot -> @+tree:Allocation.AllocatedTree<Content.Value, Doc.Event> -> @+roots:+List<Content.AllocatedNative> -> @+policies:+List<Content.NativePolicy> ->
      @invalid:{Renderer.native_roots_valid(roots, tree) && Renderer.native_policies_valid(policies, tree) == False{} : Bool} ->
      {Renderer.nodes(Content.AllocatedWorld{snapshot, tree, roots, policies}) == Renderer.emit_world(tree, roots, policies, False{}) : +List<Doc.Node>}}

law evidence:
  Requirements
