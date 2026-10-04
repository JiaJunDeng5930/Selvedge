import Base
import ../typography.bend as T
import ../../bendlib/stdlib.bend as Std
import ../document.bend as Doc
import ../design.bend as Design
import ../appearance.bend as Appearance
import ../controls.bend as Controls
import ../editor-layout.bend as EditorLayout
import ../renderer.bend as Render
import ../../core/interface.bend as UI
import ../../core/form-fields.bend as Forms
import ../dialog-spatial-laws.bend as Rule

def prepend_recombines(kind: EditorLayout.SectionKind, +node: Doc.Node,
  suffix: EditorLayout.Suffix) ->
  {Rule.recombine(EditorLayout.prepend(kind, node, suffix)) == node <> Rule.recombine(suffix) : +List<Doc.Node>}:
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
  {Rule.recombine(EditorLayout.split(nodes, kinds)) == nodes : +List<Doc.Node>}:
  match nodes kinds:
    case Con{+node, +rest} Con{+kind, +remaining}:
      Equal.trans(+List<Doc.Node>,
        Rule.recombine(EditorLayout.prepend(kind, node, EditorLayout.split(rest, remaining))),
        node <> Rule.recombine(EditorLayout.split(rest, remaining)), node <> rest,
        prepend_recombines(kind, node, EditorLayout.split(rest, remaining)),
        Equal.cong(+List<Doc.Node>, +List<Doc.Node>, (tail => node <> tail),
          Rule.recombine(EditorLayout.split(rest, remaining)), rest, split_recombines(rest, remaining)))
    case Nil{} _: {==}
    case Con{+node, +rest} Nil{}: Std.app_nil_r(Doc.Node, node <> rest)




def footer_items_preserve(+owner: String, +values: +List<Doc.Node>) ->
  {Rule.footer_originals(Render.dialog_footer_items(owner, values)) == values : +List<Doc.Node>}:
  match values:
    case Nil{}: {==}
    case Con{node, Nil{}}: {==}
    case Con{node, Con{next, Nil{}}}: {==}
    case Con{+node, Con{+next, Con{+third, +remaining}}}:
      Equal.cong(+List<Doc.Node>, +List<Doc.Node>, (tail => node <> tail),
        Rule.footer_originals(Render.dialog_footer_items(owner, next <> third <> remaining)), next <> third <> remaining,
        footer_items_preserve(owner, next <> third <> remaining))


def suffix_observation(+key: String, +label: String, +visual: Design.Style,
  +header: +List<Doc.Node>, suffix: EditorLayout.Suffix, +typography: T.Presentation) ->
  {Rule.original_children(Render.dialog_region_suffix(key, label, visual, header, suffix, typography)) ==
    Rule.recombine(suffix) : +List<Doc.Node>}:
  match suffix:
    case EditorLayout.Suffix{+body, Nil{}}: {==}
    case EditorLayout.Suffix{+body, Con{+item, +remaining}}:
      Equal.cong(+List<Doc.Node>, +List<Doc.Node>,
        (tail => List.append(&2, Doc.Node, body, tail)),
        Rule.footer_originals(Render.dialog_footer_items(key, item <> remaining)), item <> remaining,
        footer_items_preserve(key, item <> remaining))


def region_original_children(+key: String, +label: String, +visual: Design.Style,
  parts: Render.DialogParts, +typography: T.Presentation) ->
  {Rule.original_children(Render.dialog_region_parts(key, label, visual, parts, typography)) ==
    Render.dialog_body_projection(parts) : +List<Doc.Node>}:
  match parts:
    case Render.DialogParts{+header, +body, +layouts}:
      Equal.trans(+List<Doc.Node>,
        Rule.original_children(Render.dialog_region_suffix(key, label, visual, header, EditorLayout.split(body, layouts), typography)),
        Rule.recombine(EditorLayout.split(body, layouts)), body,
        suffix_observation(key, label, visual, header, EditorLayout.split(body, layouts), typography),
        split_recombines(body, layouts))


def toggle_value_and_events(+key: String, +name: String, +enabled: Bool, choices: +List<Forms.ChoiceValue>, +typography: T.Presentation) -> Rule.toggle_value_and_events_law(key, name, enabled, choices, typography):
  match enabled:
    case False{}: {==}
    case True{}: {==}


















def Rule.evidence():
  Rule.Requirements{
    +key => +profiles => {==},
    +key => +profiles => {==},
    +key => +enabled => +selected => +profiles => {==},
    +typography => editor => +field => +entry => +value => choices => toggle =>
      Equal.cong(Controls.Widget, Design.Style,
        (widget => Appearance.normalize_field(EditorLayout.field_kind(UI.Edit{editor, field, entry, value, choices}),
          widget, Appearance.widget_field_style(widget, entry, typography))),
        Controls.widget_for(entry, field, value), Controls.ToggleInput{}, toggle),
    +typography => +key => +name => +enabled => choices => {==},
    +typography => +key => +name => +enabled => choices => toggle_value_and_events(key, name, enabled, choices, typography),
    +key => +name => input => {==},
    +typography => {==},
    {==},
    nodes => kinds => split_recombines(nodes, kinds),
    +typography => key => label => visual => parts => region_original_children(key, label, visual, parts, typography),
    +card => +field => +entry => +value => choices => {==},
    +key => +tag => +attributes => +styles => +events => +children => +name => {==},
    +key => +tag => +attributes => +styles => +events => +children => +name => {==},
    {==}, {==},
    +key => +name => input => {==},
    +typography => +owner => +name => {==},
    key => {==},
    +node => {==},
    +capture => +submit => {==},
    +node => {==}}
