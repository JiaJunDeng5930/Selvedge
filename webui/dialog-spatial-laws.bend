import Base
import ./typography.bend as T
import ../core/field-options.bend as FieldOptions
import ./enclosure-laws.bend as EnclosureLaws
import ./enclosure.bend as Enclosure
import ./document.bend as Doc
import ./design.bend as Design
import ./appearance.bend as Appearance
import ./controls.bend as Controls
import ./editor-layout.bend as EditorLayout
import ./renderer.bend as Render
import ../core/interface.bend as UI
import ../core/form-fields.bend as Forms
import ../core/user-input.bend as User
import ../core/ui-world.bend as View
import ../bendlib/domain.bend as Domain

def recombine(value: EditorLayout.Suffix) -> +List<Doc.Node>:
  EditorLayout.Suffix{+body, +footer} = value
  List.append(&2, Doc.Node, body, footer)


def first(values: +List<Doc.Node>) -> Doc.Node:
  match values:
    case Con{node, rest}: node
    case Nil{}: Doc.Text{""}


def rest(values: +List<Doc.Node>) -> +List<Doc.Node>:
  match values:
    case Con{node, remaining}: remaining
    case Nil{}: Nil{}


def footer_originals(values: +List<Doc.Node>) -> +List<Doc.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{node, Nil{}}: Doc.element_children(node)
    case Con{node, remaining}: node <> footer_originals(remaining)


def observed_footer(node: Doc.Node) -> +List<Doc.Node>:
  footer_originals(Doc.element_children(first(rest(rest(Doc.element_children(node))))))


def observed_body(node: Doc.Node) -> +List<Doc.Node>:
  Doc.element_children(first(Doc.element_children(first(rest(Doc.element_children(node))))))


def original_children(+node: Doc.Node) -> +List<Doc.Node>:
  List.append(&2, Doc.Node, observed_body(node), observed_footer(node))


def node_key(node: Doc.Node) -> String:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: key
    case _: ""














def partition_inset(+properties: +List<Doc.Property>) -> String:
  Render.attr(properties, "padding-block") ++ " " ++ Render.attr(properties, "padding-inline")




























def toggle_geometry(+properties: +List<Doc.Property>) ->
  (String & (String & (String & (String & (String & (String & (String & String))))))):
  (Render.attr(properties, "width"), (Render.attr(properties, "height"),
    (Render.attr(properties, "min-height"), (Render.attr(properties, "padding-inline"),
      (Render.attr(properties, "padding-block"), (Render.attr(properties, "align-self"),
        (Render.attr(properties, "margin"), Render.attr(properties, "flex"))))))))






def toggle_value_and_events_law(-key: String, -name: String, -enabled: Bool, -choices: +List<Forms.ChoiceValue>, +typography: T.Presentation) -> Type:
  {(Render.attr(Doc.element_attributes(first(Doc.element_children(Render.input(key,
        UI.Edit{User.CardEditor{None{}}, Forms.ContinueCapture{}, Forms.Choice{}, Forms.ToggleValue{enabled}, choices},
        Controls.Input{UI.Edit{User.CardEditor{None{}}, Forms.ContinueCapture{}, Forms.Choice{}, Forms.ToggleValue{enabled}, choices},
          name, Controls.ToggleInput{}, Controls.BesideInput{}, View.Available{}}, Appearance.toggle_field(typography))))), "value"),
      Doc.element_events(first(Doc.element_children(Render.input(key,
        UI.Edit{User.CardEditor{None{}}, Forms.ContinueCapture{}, Forms.Choice{}, Forms.ToggleValue{enabled}, choices},
        Controls.Input{UI.Edit{User.CardEditor{None{}}, Forms.ContinueCapture{}, Forms.Choice{}, Forms.ToggleValue{enabled}, choices},
          name, Controls.ToggleInput{}, Controls.BesideInput{}, View.Available{}}, Appearance.toggle_field(typography)))))) ==
     (FieldOptions.boolean(enabled), [Doc.EditToggle{key}]) : (String & +List<Doc.Event>)}


type Requirements is Type:
  Requirements{
    assistance_default_option: @+key:String -> @+profiles:+List<Domain.Profile> ->   {(node_key(first(Render.field_options(key, FieldOptions.assistance_options(Forms.key(Forms.AssistanceProfile{}), profiles)))),
          (Render.attr(Doc.element_attributes(first(Render.field_options(key, FieldOptions.assistance_options(Forms.key(Forms.AssistanceProfile{}), profiles)))), "value"),
           Doc.direct_text(first(Doc.element_children(first(Render.field_options(key, FieldOptions.assistance_options(Forms.key(Forms.AssistanceProfile{}), profiles)))))))) ==
         (key ++ "/option/", ("", "使用看板默认模型")) : (String & (String & String))},
    assistance_remaining_profiles: @+key:String -> @+profiles:+List<Domain.Profile> ->   {rest(Render.field_options(key, FieldOptions.assistance_options(Forms.key(Forms.AssistanceProfile{}), profiles))) ==
    Render.field_options(key, FieldOptions.profile_options(profiles)) : +List<Doc.Node>},
    assistance_field_options: @+key:String -> @+enabled:Bool -> @+selected:String -> @+profiles:+List<Domain.Profile> ->
      {Render.input_children(key,
          UI.Edit{User.CardEditor{None{}}, Forms.AssistanceProfile{}, Forms.Choice{}, Forms.TextValue{selected},
            FieldOptions.assistance_options(Forms.key(Forms.AssistanceProfile{}), profiles)}, Controls.SelectInput{}) ==
        Render.option(key, "", "使用看板默认模型") <> Render.field_options(key, FieldOptions.profile_options(profiles)) : +List<Doc.Node>},
    field_style_widget_binding: @+typography:T.Presentation -> @editor:User.Editor -> @+field:Forms.Field -> @+entry:Forms.Entry -> @+value:Forms.Observed ->
      @choices:+List<Forms.ChoiceValue> ->
      @toggle:{Controls.widget_for(entry, field, value) == Controls.ToggleInput{} : Controls.Widget} ->
      {Appearance.field_style(UI.Edit{editor, field, entry, value, choices}, typography) == Appearance.toggle_field(typography) : Design.Style},
    rendered_toggle_geometry: @+typography:T.Presentation -> @+key:String -> @+name:String -> @+enabled:Bool ->   @choices:+List<Forms.ChoiceValue> ->
      {toggle_geometry(Doc.element_styles(first(Doc.element_children(Render.input(key,
          UI.Edit{User.CardEditor{None{}}, Forms.ContinueCapture{}, Forms.Choice{}, Forms.ToggleValue{enabled}, choices},
          Controls.Input{UI.Edit{User.CardEditor{None{}}, Forms.ContinueCapture{}, Forms.Choice{}, Forms.ToggleValue{enabled}, choices},
            name, Controls.ToggleInput{}, Controls.BesideInput{}, View.Available{}},
          Appearance.field_style(UI.Edit{User.CardEditor{None{}}, Forms.ContinueCapture{}, Forms.Choice{}, Forms.ToggleValue{enabled}, choices}, typography)))))) ==
         ("16px", ("16px", ("16px", ("0px", ("0px", ("center", ("0", "none"))))))) :
         (String & (String & (String & (String & (String & (String & (String & String)))))))},
    toggle_value_and_events: @+typography:T.Presentation -> @+key:String -> @+name:String -> @+enabled:Bool -> @choices:+List<Forms.ChoiceValue> -> toggle_value_and_events_law(key, name, enabled, choices, typography),
    capture_toggle_target: @+key:String -> @+name:String -> @input:Doc.Node ->   {(Render.attr(Doc.element_styles(Render.editor_field_presented(EditorLayout.CaptureOption{}, Controls.BesideInput{}, key, name, input)), "min-height"),
          Render.attr(Doc.element_styles(Render.editor_field_presented(EditorLayout.CaptureOption{}, Controls.BesideInput{}, key, name, input)), "flex")) ==
         ("32px", "1 1 200px") : (String & String)},
    dialog_outer_inset: @+typography:T.Presentation -> {EnclosureLaws.frame_coordinates(Design.style_frame(Appearance.style(UI.Dialog{}, UI.Region{}, typography))) == (0n, (0n, 0n)) : (Nat & (Nat & Nat))},
    concrete_field_kinds:   {[EditorLayout.card_field(Forms.CardTitle{}), EditorLayout.card_field(Forms.CardDescription{}),
          EditorLayout.card_field(Forms.CardStage{}), EditorLayout.card_field(Forms.CardPriority{}),
          EditorLayout.card_field(Forms.CardProject{}), EditorLayout.card_field(Forms.CardOwner{}),
          EditorLayout.card_field(Forms.CardLabels{}), EditorLayout.card_field(Forms.ContinueCapture{}),
          EditorLayout.card_field(Forms.AssistedCapture{}), EditorLayout.card_field(Forms.AssistanceProfile{})] ==
         [EditorLayout.WorkTitle{}, EditorLayout.WorkDescription{}, EditorLayout.MetadataFlexible{},
          EditorLayout.MetadataFlexible{}, EditorLayout.MetadataFlexible{}, EditorLayout.MetadataWide{},
          EditorLayout.MetadataWide{}, EditorLayout.CaptureOption{}, EditorLayout.CaptureOption{},
          EditorLayout.CaptureOption{}] : +List<EditorLayout.FieldKind>},
    suffix_recombination: @nodes:+List<Doc.Node> -> @kinds:+List<EditorLayout.SectionKind> ->
      {recombine(EditorLayout.split(nodes, kinds)) == nodes : +List<Doc.Node>},
    original_dialog_order: @+typography:T.Presentation -> @key:String -> @label:String -> @visual:Design.Style -> @parts:Render.DialogParts ->
      {original_children(Render.dialog_region_parts(key, label, visual, parts, typography)) ==
        Render.dialog_body_projection(parts) : +List<Doc.Node>},
    field_layout_binding: @card:Maybe<&2, Nat> -> @field:Forms.Field -> @entry:Forms.Entry -> @value:Forms.Observed ->
      @choices:+List<Forms.ChoiceValue> ->
      {EditorLayout.field_kind(UI.Edit{User.CardEditor{card}, field, entry, value, choices}) ==
        EditorLayout.card_field(field) : EditorLayout.FieldKind},
    title_identity: @key:String -> @tag:String -> @attributes:+List<Doc.Property> -> @styles:+List<Doc.Property> ->
      @events:+List<Doc.Event> -> @children:+List<Doc.Node> -> @name:String ->
      {(node_key(Render.editor_field(EditorLayout.WorkTitle{}, Controls.AboveInput{}, key, name,
          Doc.Element{key, tag, attributes, styles, events, children})),
        (Doc.element_attributes(Render.editor_field(EditorLayout.WorkTitle{}, Controls.AboveInput{}, key, name,
          Doc.Element{key, tag, attributes, styles, events, children})),
         Doc.element_events(Render.editor_field(EditorLayout.WorkTitle{}, Controls.AboveInput{}, key, name,
          Doc.Element{key, tag, attributes, styles, events, children})))) ==
       (key, (attributes, events)) : (String & (+List<Doc.Property> & +List<Doc.Event>))},
    description_identity: @key:String -> @tag:String -> @attributes:+List<Doc.Property> -> @styles:+List<Doc.Property> ->
      @events:+List<Doc.Event> -> @children:+List<Doc.Node> -> @name:String ->
      {(node_key(Render.editor_field(EditorLayout.WorkDescription{}, Controls.AboveInput{}, key, name,
          Doc.Element{key, tag, attributes, styles, events, children})),
        (Doc.element_attributes(Render.editor_field(EditorLayout.WorkDescription{}, Controls.AboveInput{}, key, name,
          Doc.Element{key, tag, attributes, styles, events, children})),
         Doc.element_events(Render.editor_field(EditorLayout.WorkDescription{}, Controls.AboveInput{}, key, name,
          Doc.Element{key, tag, attributes, styles, events, children})))) ==
       (key, (attributes, events)) : (String & (+List<Doc.Property> & +List<Doc.Event>))},
    shared_inline_inset: {Enclosure.partition_inline() == 24n : Nat},
    region_owned_insets: {(partition_inset(Render.dialog_header_styles()),
          (partition_inset(Render.dialog_body_styles()),
           (partition_inset(Render.dialog_footer_styles()),
            (Render.attr(Render.dialog_header_styles(), "flex"),
             Render.attr(Render.dialog_footer_styles(), "flex"))))) ==
         ("14px " ++ Render.px(Enclosure.partition_inline()), ("20px " ++ Render.px(Enclosure.partition_inline()), ("12px " ++ Render.px(Enclosure.partition_inline()), ("0 0 auto", "0 0 auto")))) :
         (String & (String & (String & (String & String))))},
    above_input_margin: @key:String -> @name:String -> @input:Doc.Node ->
      {Render.attr(Doc.element_styles(Render.label_input(Controls.AboveInput{}, key, name, input)), "margin") == "0" : String},
    section_heading_margin: @+typography:T.Presentation -> @owner:String -> @name:String ->
      {Render.attr(Doc.element_styles(first(Render.section_label(owner, False{}, name, typography))), "margin") == "0" : String},
    absent_footer: @key:String -> {Render.dialog_footer(key, Nil{}) == Nil{} : +List<Doc.Node>},
    terminal_submit: @node:Doc.Node ->
      {EditorLayout.split([node], [EditorLayout.SubmitAction{}]) == EditorLayout.Suffix{Nil{}, [node]} : EditorLayout.Suffix},
    terminal_capture: @capture:Doc.Node -> @submit:Doc.Node ->
      {EditorLayout.split([capture, submit], [EditorLayout.CaptureSection{}, EditorLayout.SubmitAction{}]) ==
        EditorLayout.Suffix{Nil{}, [capture, submit]} : EditorLayout.Suffix},
    generic_body: @node:Doc.Node ->
      {EditorLayout.split([node], [EditorLayout.GenericSection{}]) == EditorLayout.Suffix{[node], Nil{}} : EditorLayout.Suffix}}


law evidence:
  Requirements
