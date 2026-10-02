import Base
import ./enclosure.bend as Enclosure
import ../bendlib/stdlib.bend as Std
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

def prepend_recombines(kind: EditorLayout.SectionKind, +node: Doc.Node,
  suffix: EditorLayout.Suffix) ->
  {recombine(EditorLayout.prepend(kind, node, suffix)) == node <> recombine(suffix) : +List<Doc.Node>}:
  match kind suffix:
    case EditorLayout.SubmitAction{} EditorLayout.Suffix{Nil{}, Nil{}}: {==}
    case EditorLayout.CaptureSection{} EditorLayout.Suffix{Nil{}, Con{submit, Nil{}}}: {==}
    case EditorLayout.SubmitAction{} EditorLayout.Suffix{Nil{}, Con{first, remaining}}: {==}
    case EditorLayout.SubmitAction{} EditorLayout.Suffix{Con{first, remaining}, actions}: {==}
    case EditorLayout.CaptureSection{} EditorLayout.Suffix{Nil{}, Nil{}}: {==}
    case EditorLayout.CaptureSection{} EditorLayout.Suffix{Nil{}, Con{first, Con{second, remaining}}}: {==}
    case EditorLayout.CaptureSection{} EditorLayout.Suffix{Con{first, remaining}, actions}: {==}
    case EditorLayout.GenericSection{} EditorLayout.Suffix{content, actions}: {==}
    case EditorLayout.WorkSection{} EditorLayout.Suffix{content, actions}: {==}
    case EditorLayout.MetadataSection{} EditorLayout.Suffix{content, actions}: {==}

def split_recombines(+nodes: +List<Doc.Node>, kinds: +List<EditorLayout.SectionKind>) ->
  {recombine(EditorLayout.split(nodes, kinds)) == nodes : +List<Doc.Node>}:
  match nodes kinds:
    case Con{+node, +rest} Con{+kind, +remaining}:
      Equal.trans(+List<Doc.Node>,
        recombine(EditorLayout.prepend(kind, node, EditorLayout.split(rest, remaining))),
        node <> recombine(EditorLayout.split(rest, remaining)), node <> rest,
        prepend_recombines(kind, node, EditorLayout.split(rest, remaining)),
        Equal.cong(+List<Doc.Node>, +List<Doc.Node>, (tail => node <> tail),
          recombine(EditorLayout.split(rest, remaining)), rest, split_recombines(rest, remaining)))
    case Nil{} _: {==}
    case Con{+node, +rest} Nil{}: Std.app_nil_r(Doc.Node, node <> rest)

def node_children(node: Doc.Node) -> +List<Doc.Node>:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: children
    case _: Nil{}

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
    case Con{node, Nil{}}: node_children(node)
    case Con{node, remaining}: node <> footer_originals(remaining)

def footer_items_preserve(+owner: String, +values: +List<Doc.Node>) ->
  {footer_originals(Render.dialog_footer_items(owner, values)) == values : +List<Doc.Node>}:
  match values:
    case Nil{}: {==}
    case Con{node, Nil{}}: {==}
    case Con{node, Con{next, Nil{}}}: {==}
    case Con{+node, Con{+next, Con{+third, +remaining}}}:
      Equal.cong(+List<Doc.Node>, +List<Doc.Node>, (tail => node <> tail),
        footer_originals(Render.dialog_footer_items(owner, next <> third <> remaining)), next <> third <> remaining,
        footer_items_preserve(owner, next <> third <> remaining))

def observed_footer(node: Doc.Node) -> +List<Doc.Node>:
  footer_originals(node_children(first(rest(rest(node_children(node))))))

def observed_body(node: Doc.Node) -> +List<Doc.Node>:
  node_children(first(node_children(first(rest(node_children(node))))))

def original_children(+node: Doc.Node) -> +List<Doc.Node>:
  List.append(&2, Doc.Node, observed_body(node), observed_footer(node))

def suffix_observation(+key: String, +label: String, +visual: Design.Style,
  +header: +List<Doc.Node>, suffix: EditorLayout.Suffix) ->
  {original_children(Render.dialog_region_suffix(key, label, visual, header, suffix)) ==
    recombine(suffix) : +List<Doc.Node>}:
  match suffix:
    case EditorLayout.Suffix{+body, Nil{}}: {==}
    case EditorLayout.Suffix{+body, Con{+item, +remaining}}:
      Equal.cong(+List<Doc.Node>, +List<Doc.Node>,
        (tail => List.append(&2, Doc.Node, body, tail)),
        footer_originals(Render.dialog_footer_items(key, item <> remaining)), item <> remaining,
        footer_items_preserve(key, item <> remaining))

def region_original_children(+key: String, +label: String, +visual: Design.Style,
  parts: Render.DialogParts) ->
  {original_children(Render.dialog_region_parts(key, label, visual, parts)) ==
    Render.dialog_body_projection(parts) : +List<Doc.Node>}:
  match parts:
    case Render.DialogParts{+header, +body, +layouts}:
      Equal.trans(+List<Doc.Node>,
        original_children(Render.dialog_region_suffix(key, label, visual, header, EditorLayout.split(body, layouts))),
        recombine(EditorLayout.split(body, layouts)), body,
        suffix_observation(key, label, visual, header, EditorLayout.split(body, layouts)),
        split_recombines(body, layouts))

def node_key(node: Doc.Node) -> String:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: key
    case _: ""

def node_attributes(node: Doc.Node) -> +List<Doc.Property>:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: attrs
    case _: Nil{}

def node_events(node: Doc.Node) -> +List<Doc.Event>:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: events
    case _: Nil{}

def node_styles(node: Doc.Node) -> +List<Doc.Property>:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: styles
    case _: Nil{}

def field_layout_binding(+card: Maybe<&2, Nat>, +field: Forms.Field, +entry: Forms.Entry,
  +value: Forms.Observed) ->
  {EditorLayout.field_kind(UI.Edit{User.CardEditor{card}, field, entry, value}) ==
    EditorLayout.card_field(field) : EditorLayout.FieldKind}:
  {==}

def title_identity(+key: String, +tag: String, +attributes: +List<Doc.Property>,
  +styles: +List<Doc.Property>, +events: +List<Doc.Event>, +children: +List<Doc.Node>,
  +name: String) ->
  {(node_key(Render.editor_field(EditorLayout.WorkTitle{}, Controls.AboveInput{}, key, name,
      Doc.Element{key, tag, attributes, styles, events, children})),
    (node_attributes(Render.editor_field(EditorLayout.WorkTitle{}, Controls.AboveInput{}, key, name,
      Doc.Element{key, tag, attributes, styles, events, children})),
     node_events(Render.editor_field(EditorLayout.WorkTitle{}, Controls.AboveInput{}, key, name,
      Doc.Element{key, tag, attributes, styles, events, children})))) ==
   (key, (attributes, events)) : (String & (+List<Doc.Property> & +List<Doc.Event>))}:
  {==}

def description_identity(+key: String, +tag: String, +attributes: +List<Doc.Property>,
  +styles: +List<Doc.Property>, +events: +List<Doc.Event>, +children: +List<Doc.Node>,
  +name: String) ->
  {(node_key(Render.editor_field(EditorLayout.WorkDescription{}, Controls.AboveInput{}, key, name,
      Doc.Element{key, tag, attributes, styles, events, children})),
    (node_attributes(Render.editor_field(EditorLayout.WorkDescription{}, Controls.AboveInput{}, key, name,
      Doc.Element{key, tag, attributes, styles, events, children})),
     node_events(Render.editor_field(EditorLayout.WorkDescription{}, Controls.AboveInput{}, key, name,
      Doc.Element{key, tag, attributes, styles, events, children})))) ==
   (key, (attributes, events)) : (String & (+List<Doc.Property> & +List<Doc.Event>))}:
  {==}

def partition_inset(+properties: +List<Doc.Property>) -> String:
  Render.attr(properties, "padding-block") ++ " " ++ Render.attr(properties, "padding-inline")

def region_owned_insets() ->
  {(partition_inset(Render.dialog_header_styles()),
    (partition_inset(Render.dialog_body_styles()),
     (partition_inset(Render.dialog_footer_styles()),
      (Render.attr(Render.dialog_header_styles(), "flex"),
       Render.attr(Render.dialog_footer_styles(), "flex"))))) ==
   ("14px " ++ Render.px(Appearance.dialog_inline_inset()), ("20px " ++ Render.px(Appearance.dialog_inline_inset()), ("12px " ++ Render.px(Appearance.dialog_inline_inset()), ("0 0 auto", "0 0 auto")))) :
   (String & (String & (String & (String & String))))}:
  {==}

def shared_inline_inset() -> {Appearance.dialog_inline_inset() == 24n : Nat}:
  {==}

def above_input_margin(+key: String, +name: String, input: Doc.Node) ->
  {Render.attr(node_styles(Render.label_input(Controls.AboveInput{}, key, name, input)), "margin") == "0" : String}:
  {==}

def section_heading_margin(+owner: String, +name: String) ->
  {Render.attr(node_styles(first(Render.section_label(owner, False{}, name))), "margin") == "0" : String}:
  {==}

def absent_footer(key: String) ->
  {Render.dialog_footer(key, Nil{}) == Nil{} : +List<Doc.Node>}:
  {==}

def terminal_submit(+node: Doc.Node) ->
  {EditorLayout.split([node], [EditorLayout.SubmitAction{}]) == EditorLayout.Suffix{Nil{}, [node]} : EditorLayout.Suffix}:
  {==}

def terminal_capture(+capture: Doc.Node, +submit: Doc.Node) ->
  {EditorLayout.split([capture, submit], [EditorLayout.CaptureSection{}, EditorLayout.SubmitAction{}]) ==
    EditorLayout.Suffix{Nil{}, [capture, submit]} : EditorLayout.Suffix}:
  {==}

def generic_body(+node: Doc.Node) ->
  {EditorLayout.split([node], [EditorLayout.GenericSection{}]) == EditorLayout.Suffix{[node], Nil{}} : EditorLayout.Suffix}:
  {==}

def concrete_field_kinds() ->
  {[EditorLayout.card_field(Forms.CardTitle{}), EditorLayout.card_field(Forms.CardDescription{}),
    EditorLayout.card_field(Forms.CardStage{}), EditorLayout.card_field(Forms.CardPriority{}),
    EditorLayout.card_field(Forms.CardProject{}), EditorLayout.card_field(Forms.CardOwner{}),
    EditorLayout.card_field(Forms.CardLabels{}), EditorLayout.card_field(Forms.ContinueCapture{}),
    EditorLayout.card_field(Forms.AssistedCapture{}), EditorLayout.card_field(Forms.AssistanceProfile{})] ==
   [EditorLayout.WorkTitle{}, EditorLayout.WorkDescription{}, EditorLayout.MetadataFlexible{},
    EditorLayout.MetadataFlexible{}, EditorLayout.MetadataFlexible{}, EditorLayout.MetadataWide{},
    EditorLayout.MetadataWide{}, EditorLayout.CaptureOption{}, EditorLayout.CaptureOption{},
    EditorLayout.CaptureOption{}] : +List<EditorLayout.FieldKind>}:
  {==}

def style_insets(value: Design.Style) -> (Nat & (Nat & Nat)):
  Design.Style{text, chrome, alignment, flow, overflow, +content_frame, minimum, maximum, states} = value
  (Enclosure.inline(Enclosure.frame_content(content_frame)), (Enclosure.block(Enclosure.frame_content(content_frame)), Enclosure.frame_gap(content_frame)))

def dialog_outer_inset() ->
  {style_insets(Appearance.style(UI.Dialog{}, UI.Region{})) == (0n, (0n, 0n)) : (Nat & (Nat & Nat))}:
  {==}

def field_style_widget_binding(editor: User.Editor, +field: Forms.Field, +entry: Forms.Entry,
  +value: Forms.Observed,
  toggle: {Controls.widget_for(entry, field, value) == Controls.ToggleInput{} : Controls.Widget}) ->
  {Appearance.field_style(UI.Edit{editor, field, entry, value}) == Appearance.toggle_field() : Design.Style}:
  Equal.cong(Controls.Widget, Design.Style, (widget => Appearance.widget_field_style(widget, entry)),
    Controls.widget_for(entry, field, value), Controls.ToggleInput{}, toggle)

def toggle_geometry(+properties: +List<Doc.Property>) ->
  (String & (String & (String & (String & (String & (String & (String & String))))))):
  (Render.attr(properties, "width"), (Render.attr(properties, "height"),
    (Render.attr(properties, "min-height"), (Render.attr(properties, "padding-inline"),
      (Render.attr(properties, "padding-block"), (Render.attr(properties, "align-self"),
        (Render.attr(properties, "margin"), Render.attr(properties, "flex"))))))))

def rendered_toggle_geometry(+key: String, +name: String, +enabled: Bool) ->
  {toggle_geometry(node_styles(first(node_children(Render.input(key,
    UI.Edit{User.CardEditor{None{}}, Forms.ContinueCapture{}, Forms.Choice{}, Forms.ToggleValue{enabled}},
    Controls.Input{UI.Edit{User.CardEditor{None{}}, Forms.ContinueCapture{}, Forms.Choice{}, Forms.ToggleValue{enabled}},
      name, Controls.ToggleInput{}, Controls.BesideInput{}, View.Available{}},
    Appearance.field_style(UI.Edit{User.CardEditor{None{}}, Forms.ContinueCapture{}, Forms.Choice{}, Forms.ToggleValue{enabled}})))))) ==
   ("16px", ("16px", ("16px", ("0px", ("0px", ("center", ("0", "none"))))))) :
   (String & (String & (String & (String & (String & (String & (String & String)))))))}:
  {==}

def toggle_value_and_events(+key: String, +name: String, +enabled: Bool) ->
  {(Render.attr(node_attributes(first(node_children(Render.input(key,
      UI.Edit{User.CardEditor{None{}}, Forms.ContinueCapture{}, Forms.Choice{}, Forms.ToggleValue{enabled}},
      Controls.Input{UI.Edit{User.CardEditor{None{}}, Forms.ContinueCapture{}, Forms.Choice{}, Forms.ToggleValue{enabled}},
        name, Controls.ToggleInput{}, Controls.BesideInput{}, View.Available{}}, Appearance.toggle_field())))), "value"),
    node_events(first(node_children(Render.input(key,
      UI.Edit{User.CardEditor{None{}}, Forms.ContinueCapture{}, Forms.Choice{}, Forms.ToggleValue{enabled}},
      Controls.Input{UI.Edit{User.CardEditor{None{}}, Forms.ContinueCapture{}, Forms.Choice{}, Forms.ToggleValue{enabled}},
        name, Controls.ToggleInput{}, Controls.BesideInput{}, View.Available{}}, Appearance.toggle_field()))))) ==
   (Render.boolean(enabled), [Doc.EditToggle{key}]) : (String & +List<Doc.Event>)}:
  match enabled:
    case False{}: {==}
    case True{}: {==}

def capture_toggle_target(+key: String, +name: String, input: Doc.Node) ->
  {(Render.attr(node_styles(Render.editor_field_presented(EditorLayout.CaptureOption{}, Controls.BesideInput{}, key, name, input)), "min-height"),
    Render.attr(node_styles(Render.editor_field_presented(EditorLayout.CaptureOption{}, Controls.BesideInput{}, key, name, input)), "flex")) ==
   ("32px", "1 1 200px") : (String & String)}:
  {==}

def option_label(node: Doc.Node) -> String:
  match node:
    case Doc.Text{value}: value
    case _: ""

def assistance_default_option(+key: String, +profiles: +List<Domain.Profile>) ->
  {(node_key(first(Render.assistance_options(key, Forms.key(Forms.AssistanceProfile{}), profiles))),
    (Render.attr(node_attributes(first(Render.assistance_options(key, Forms.key(Forms.AssistanceProfile{}), profiles))), "value"),
     option_label(first(node_children(first(Render.assistance_options(key, Forms.key(Forms.AssistanceProfile{}), profiles))))))) ==
   (key ++ "/option/", ("", "使用看板默认模型")) : (String & (String & String))}:
  {==}

def assistance_remaining_profiles(+key: String, +profiles: +List<Domain.Profile>) ->
  {rest(Render.assistance_options(key, Forms.key(Forms.AssistanceProfile{}), profiles)) ==
    Render.profile_options(profiles, key) : +List<Doc.Node>}:
  {==}

def assistance_field_options(+key: String, +enabled: Bool, +selected: String, +profiles: +List<Domain.Profile>) ->
  {node_children(Render.enriched_element(key, "select",
      [Doc.Property{"data-field", Forms.key(Forms.AssistanceProfile{})}, Doc.Property{"value", selected}],
      Nil{}, Nil{}, Nil{}, [View.CardAssistanceInput{enabled, selected, profiles}], Nil{})) ==
    Render.option(key, "", "使用看板默认模型") <> Render.profile_options(profiles, key) : +List<Doc.Node>}:
  {==}

type Requirements is Type:
  Requirements{
    assistance_default_option: @+key:String -> @+profiles:+List<Domain.Profile> ->   {(node_key(first(Render.assistance_options(key, Forms.key(Forms.AssistanceProfile{}), profiles))),
    (Render.attr(node_attributes(first(Render.assistance_options(key, Forms.key(Forms.AssistanceProfile{}), profiles))), "value"),
     option_label(first(node_children(first(Render.assistance_options(key, Forms.key(Forms.AssistanceProfile{}), profiles))))))) ==
   (key ++ "/option/", ("", "使用看板默认模型")) : (String & (String & String))},
    assistance_remaining_profiles: @+key:String -> @+profiles:+List<Domain.Profile> ->   {rest(Render.assistance_options(key, Forms.key(Forms.AssistanceProfile{}), profiles)) ==
    Render.profile_options(profiles, key) : +List<Doc.Node>},
    assistance_field_options: @+key:String -> @+enabled:Bool -> @+selected:String -> @+profiles:+List<Domain.Profile> ->   {node_children(Render.enriched_element(key, "select",
      [Doc.Property{"data-field", Forms.key(Forms.AssistanceProfile{})}, Doc.Property{"value", selected}],
      Nil{}, Nil{}, Nil{}, [View.CardAssistanceInput{enabled, selected, profiles}], Nil{})) ==
    Render.option(key, "", "使用看板默认模型") <> Render.profile_options(profiles, key) : +List<Doc.Node>},
    field_style_widget_binding: @editor:User.Editor -> @+field:Forms.Field -> @+entry:Forms.Entry -> @+value:Forms.Observed ->
      @toggle:{Controls.widget_for(entry, field, value) == Controls.ToggleInput{} : Controls.Widget} ->
      {Appearance.field_style(UI.Edit{editor, field, entry, value}) == Appearance.toggle_field() : Design.Style},
    rendered_toggle_geometry: @+key:String -> @+name:String -> @+enabled:Bool ->   {toggle_geometry(node_styles(first(node_children(Render.input(key,
    UI.Edit{User.CardEditor{None{}}, Forms.ContinueCapture{}, Forms.Choice{}, Forms.ToggleValue{enabled}},
    Controls.Input{UI.Edit{User.CardEditor{None{}}, Forms.ContinueCapture{}, Forms.Choice{}, Forms.ToggleValue{enabled}},
      name, Controls.ToggleInput{}, Controls.BesideInput{}, View.Available{}},
    Appearance.field_style(UI.Edit{User.CardEditor{None{}}, Forms.ContinueCapture{}, Forms.Choice{}, Forms.ToggleValue{enabled}})))))) ==
   ("16px", ("16px", ("16px", ("0px", ("0px", ("center", ("0", "none"))))))) :
   (String & (String & (String & (String & (String & (String & (String & String)))))))},
    toggle_value_and_events: @+key:String -> @+name:String -> @+enabled:Bool ->   {(Render.attr(node_attributes(first(node_children(Render.input(key,
      UI.Edit{User.CardEditor{None{}}, Forms.ContinueCapture{}, Forms.Choice{}, Forms.ToggleValue{enabled}},
      Controls.Input{UI.Edit{User.CardEditor{None{}}, Forms.ContinueCapture{}, Forms.Choice{}, Forms.ToggleValue{enabled}},
        name, Controls.ToggleInput{}, Controls.BesideInput{}, View.Available{}}, Appearance.toggle_field())))), "value"),
    node_events(first(node_children(Render.input(key,
      UI.Edit{User.CardEditor{None{}}, Forms.ContinueCapture{}, Forms.Choice{}, Forms.ToggleValue{enabled}},
      Controls.Input{UI.Edit{User.CardEditor{None{}}, Forms.ContinueCapture{}, Forms.Choice{}, Forms.ToggleValue{enabled}},
        name, Controls.ToggleInput{}, Controls.BesideInput{}, View.Available{}}, Appearance.toggle_field()))))) ==
   (Render.boolean(enabled), [Doc.EditToggle{key}]) : (String & +List<Doc.Event>)},
    capture_toggle_target: @+key:String -> @+name:String -> @input:Doc.Node ->   {(Render.attr(node_styles(Render.editor_field_presented(EditorLayout.CaptureOption{}, Controls.BesideInput{}, key, name, input)), "min-height"),
    Render.attr(node_styles(Render.editor_field_presented(EditorLayout.CaptureOption{}, Controls.BesideInput{}, key, name, input)), "flex")) ==
   ("32px", "1 1 200px") : (String & String)},
    dialog_outer_inset: {style_insets(Appearance.style(UI.Dialog{}, UI.Region{})) == (0n, (0n, 0n)) : (Nat & (Nat & Nat))},
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
    original_dialog_order: @key:String -> @label:String -> @visual:Design.Style -> @parts:Render.DialogParts ->
      {original_children(Render.dialog_region_parts(key, label, visual, parts)) ==
        Render.dialog_body_projection(parts) : +List<Doc.Node>},
    field_layout_binding: @card:Maybe<&2, Nat> -> @field:Forms.Field -> @entry:Forms.Entry -> @value:Forms.Observed ->
      {EditorLayout.field_kind(UI.Edit{User.CardEditor{card}, field, entry, value}) ==
        EditorLayout.card_field(field) : EditorLayout.FieldKind},
    title_identity: @key:String -> @tag:String -> @attributes:+List<Doc.Property> -> @styles:+List<Doc.Property> ->
      @events:+List<Doc.Event> -> @children:+List<Doc.Node> -> @name:String ->
      {(node_key(Render.editor_field(EditorLayout.WorkTitle{}, Controls.AboveInput{}, key, name,
          Doc.Element{key, tag, attributes, styles, events, children})),
        (node_attributes(Render.editor_field(EditorLayout.WorkTitle{}, Controls.AboveInput{}, key, name,
          Doc.Element{key, tag, attributes, styles, events, children})),
         node_events(Render.editor_field(EditorLayout.WorkTitle{}, Controls.AboveInput{}, key, name,
          Doc.Element{key, tag, attributes, styles, events, children})))) ==
       (key, (attributes, events)) : (String & (+List<Doc.Property> & +List<Doc.Event>))},
    description_identity: @key:String -> @tag:String -> @attributes:+List<Doc.Property> -> @styles:+List<Doc.Property> ->
      @events:+List<Doc.Event> -> @children:+List<Doc.Node> -> @name:String ->
      {(node_key(Render.editor_field(EditorLayout.WorkDescription{}, Controls.AboveInput{}, key, name,
          Doc.Element{key, tag, attributes, styles, events, children})),
        (node_attributes(Render.editor_field(EditorLayout.WorkDescription{}, Controls.AboveInput{}, key, name,
          Doc.Element{key, tag, attributes, styles, events, children})),
         node_events(Render.editor_field(EditorLayout.WorkDescription{}, Controls.AboveInput{}, key, name,
          Doc.Element{key, tag, attributes, styles, events, children})))) ==
       (key, (attributes, events)) : (String & (+List<Doc.Property> & +List<Doc.Event>))},
    shared_inline_inset: {Appearance.dialog_inline_inset() == 24n : Nat},
    region_owned_insets: {(partition_inset(Render.dialog_header_styles()),
      (partition_inset(Render.dialog_body_styles()),
       (partition_inset(Render.dialog_footer_styles()),
        (Render.attr(Render.dialog_header_styles(), "flex"), Render.attr(Render.dialog_footer_styles(), "flex"))))) ==
      ("14px " ++ Render.px(Appearance.dialog_inline_inset()), ("20px " ++ Render.px(Appearance.dialog_inline_inset()), ("12px " ++ Render.px(Appearance.dialog_inline_inset()), ("0 0 auto", "0 0 auto")))) :
      (String & (String & (String & (String & String))))},
    above_input_margin: @key:String -> @name:String -> @input:Doc.Node ->
      {Render.attr(node_styles(Render.label_input(Controls.AboveInput{}, key, name, input)), "margin") == "0" : String},
    section_heading_margin: @owner:String -> @name:String ->
      {Render.attr(node_styles(first(Render.section_label(owner, False{}, name))), "margin") == "0" : String},
    absent_footer: @key:String -> {Render.dialog_footer(key, Nil{}) == Nil{} : +List<Doc.Node>},
    terminal_submit: @node:Doc.Node ->
      {EditorLayout.split([node], [EditorLayout.SubmitAction{}]) == EditorLayout.Suffix{Nil{}, [node]} : EditorLayout.Suffix},
    terminal_capture: @capture:Doc.Node -> @submit:Doc.Node ->
      {EditorLayout.split([capture, submit], [EditorLayout.CaptureSection{}, EditorLayout.SubmitAction{}]) ==
        EditorLayout.Suffix{Nil{}, [capture, submit]} : EditorLayout.Suffix},
    generic_body: @node:Doc.Node ->
      {EditorLayout.split([node], [EditorLayout.GenericSection{}]) == EditorLayout.Suffix{[node], Nil{}} : EditorLayout.Suffix}}

def evidence() -> Requirements:
  Requirements{
    assistance_default_option,
    assistance_remaining_profiles,
    assistance_field_options,
    field_style_widget_binding,
    rendered_toggle_geometry,
    toggle_value_and_events,
    capture_toggle_target,
    dialog_outer_inset(),
    concrete_field_kinds(),
    nodes => kinds => split_recombines(nodes, kinds),
    key => label => visual => parts => region_original_children(key, label, visual, parts),
    card => field => entry => value => field_layout_binding(card, field, entry, value),
    key => tag => attributes => styles => events => children => name => title_identity(key, tag, attributes, styles, events, children, name),
    key => tag => attributes => styles => events => children => name => description_identity(key, tag, attributes, styles, events, children, name),
    shared_inline_inset(), region_owned_insets(),
    key => name => input => above_input_margin(key, name, input),
    owner => name => section_heading_margin(owner, name),
    key => absent_footer(key),
    node => terminal_submit(node),
    capture => submit => terminal_capture(capture, submit),
    node => generic_body(node)}
