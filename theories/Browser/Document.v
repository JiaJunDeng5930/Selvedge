From Stdlib Require Import String List Bool Arith NArith ZArith.
From Selvedge.Foundation Require Import Json TextJson Numbers.
From Selvedge.Browser Require Import DOM Focus Layout Appearance ControlPurpose ControlContent SemanticAppearance InteractiveAppearance Observation.
From Selvedge.Interaction Require Import CodeSource CodeBlock DocumentPublication Graphics Audit Identity.
From Selvedge.Interaction Require Appearance.
From Selvedge.Interaction.Submission Require Fields Parameters.
From Selvedge.Features Require BoardFilter.
From Selvedge.Interaction.Interactive Require Expand Vocabulary Presentation Local.
From Selvedge.Interaction.Presentation Require Roles Information Composition Gesture Model Surface.
Module NativeAppearance := Selvedge.Browser.Appearance.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Module S := Surface.
Module IP := Selvedge.Interaction.Interactive.Presentation.
Module UX := Selvedge.Interaction.Experience.Model.
Definition text_number n := show_natural n.
Definition flag (value:bool) := if value then "true" else "false".
Definition empty := JObject [].
Definition event key generation name kind gesture :=
 DOM.Binding name kind (DOM.ElementTarget key (Gesture.gesture_name gesture) generation).
Definition disabled (flag:bool) := if flag then [] else [("disabled","disabled")].
Definition control_help {A} (action:Model.control A) :=
 match Model.control_availability action with
 | Model.Unavailable reason => reason
 | _ => Model.control_label action
 end.
Fixpoint attribute_value (name:string) (attributes:list(string*string)) :=
 match attributes with
 | [] => None
 | (key,value)::rest => if String.eqb name key then Some value else attribute_value name rest
 end.
Definition without_attribute (name:string) (attributes:list(string*string)) :=
 filter (fun attribute=>negb(String.eqb name (fst attribute))) attributes.
Definition native_field_properties (kind:string) : list(string*string) :=
 [("appearance",if String.eqb kind "range" then "auto" else "none")].
Definition set_style (name value:string) (styles:list(string*string)) :=
 (name,value)::without_attribute name styles.
Definition help_describedby key (help:bool) (attributes:list(string*string)) :=
 if help then
   let described:=attribute_value "aria-describedby" attributes in
   let references:=String.append (String.append key "/help")
     (match described with Some ids=>if String.eqb ids "" then "" else String.append " " ids|None=>"" end) in
   ("aria-describedby",references)::without_attribute "aria-describedby" attributes
 else attributes.
Definition control_attributes {A} (focusable help:bool) (action:Model.control A) :=
 let available:=Model.available(Model.control_availability action) in
 [("aria-label",Model.control_label action)] ++
 (if available then [] else if focusable then [("aria-disabled","true");("tabindex","-1")] else disabled false) ++
 (if help then let description:=control_help action in
   [("data-help",description)] else []).
Definition artwork name := match NativeAppearance.find_symbol name with None=>[]|Some symbol=>
 [DOM.Element "" "svg" [("viewBox","0 0 20 20");("width","16");("height","16");("aria-hidden","true")]
 [("flex","none");("inline-size","var(--control-icon-size,16px)");("block-size","var(--control-icon-size,16px)")] [] empty [DOM.Element "" "path"
 ([("d",NativeAppearance.symbol_path symbol);("stroke-linecap","round");("stroke-linejoin","round")] ++
 match NativeAppearance.symbol_paint symbol with NativeAppearance.Filled=>[("fill","currentColor")]
 |NativeAppearance.Outline=>[("fill","none");("stroke","currentColor");("stroke-width","1.4")]end) [] [] empty []]] end.
Definition glyph name := if String.eqb name "spinner" then
 [DOM.Element "" "span" [("data-interactive-motion-glyph","");("aria-hidden","true")]
 [("inline-size","16px");("block-size","16px");("flex","none")] [] empty (artwork name)] else artwork name.
Definition checkbox_target (env : Layout.environment) key (field:DOM.node) :=
 let target:=Typography.px Layout.base_motor_minimum in
 match field with
 |DOM.Element field_key tag attributes styles events metadata children=>
  let checked:=match attribute_value "checked" attributes with Some _=>true|None=>false end in
  let inactive:=match attribute_value "disabled" attributes with Some _=>true|None=>false end in
  DOM.Element (String.append key "/checkbox-target") "span" [("data-control-target","checkbox")]
   [("display","grid");("place-items","center");("position","relative");
    ("inline-size",target);("min-inline-size",target);("block-size",target);
    ("min-block-size",target);("flex","none");("cursor",if inactive then "default"else"pointer")]
   [] empty
   [DOM.Element field_key tag attributes
     (styles++[("position","absolute");("inset","0");("inline-size","100%");("block-size","100%");
       ("min-block-size","0");("margin","0");("padding","0");("border","0");("background","transparent")])
     events metadata children;
    DOM.Element (String.append key "/checkbox-visual") "span" [("aria-hidden","true")]
     (styles++[("display","grid");("place-items","center");("inline-size","16px");("block-size","16px");
       ("min-inline-size","16px");("min-block-size","16px");("padding","0");
       ("pointer-events","none");("opacity",if inactive then "var(--control-disabled-opacity,0.4)"else"1");
       ("--control-icon-size","14px")]) [] empty (if checked then glyph "check" else [])]
 | _=>field end.
Definition interactive_status env (activity : bool) key attribute message :=
  let tier := if activity then Typography.ActivityPrimary else Typography.Body in
  DOM.Element key "output" [(attribute,"");("role","status");("title",message)]
    [("display","block");("block-size",Typography.px (Typography.line_height (Layout.root_font_size_milli env) tier));
     ("flex","none");("min-inline-size","0");("white-space","nowrap");
     ("overflow","hidden");("text-overflow","ellipsis")]
    [] empty [DOM.Text message].
Definition table_properties : list (string * string) :=
  [("display","table");("table-layout","auto");("border-collapse","collapse");
   ("inline-size","max-content");("max-inline-size","none")].
Definition table_cell_properties : list (string * string) :=
  [("min-inline-size","100px");("inline-size","auto");("max-inline-size","240px");
   ("overflow-wrap","anywhere");("vertical-align","top")].
Definition control_children {A} (action:Model.control A) (children:list DOM.node) :=
 match children with []=>[DOM.Text (Model.control_label action)]|_=>children end.
Definition common key semantic label role := [("id",key);("data-logical-key",semantic);("data-semantic-key",semantic);
 ("data-surface-role",Roles.role_name role)] ++
 (match role with Roles.Main|Roles.Heading|Roles.Dialog|Roles.Menu=>[("tabindex","-1")]|_=>[]end) ++
 (if String.eqb label "" then [] else [("aria-label",label)]).
(* Local navigation and dialog headings must not introduce page banner landmarks. *)
Definition role_tag role := match role with
 | Roles.GlobalNavigation _ | Roles.Navigation => "nav"
 | Roles.CompactHeader => "header"
 | Roles.NavigationHeader | Roles.DialogHeader => "div"
 | Roles.Main => "main" | Roles.Heading => "h2"
 | Roles.Section | Roles.Activity | Roles.Approval => "section"
  | Roles.Dialog => "dialog" | Roles.DialogActions => "footer" | _ => "div" end.
Definition text_tag role := match role with
 | Information.IntroductionTitle => "h1" | Information.SurfaceTitle=>"h2"
 | Information.GroupTitle=>"h3" | Information.Status=>"output" | _=>"span" end.
Definition native_string value := match value with
 | JString value=>value | JNull=>"" | value=>render_json value end.
Definition native_checked value := match value with JBool value=>value|_=>false end.
Definition physical_markdown env tier kind wrapper_key markdown_key text complete metadata : DOM.node :=
 DOM.Element wrapper_key "div" [("class","physical-markdown")]
  (NativeAppearance.markdown_properties env tier kind) [] (JObject [])
  [DOM.Markdown markdown_key text complete metadata].
Definition selection_json (value:option(N*N*bool)) := match value with
 | None=>JNull | Some (start,stop,backward)=>JObject [("start",JNumber (text_number start));
 ("end",JNumber (text_number stop));("direction",JString (if backward then "backward" else "forward"))] end.
(* The renderer retains option nodes globally; each select owns its choices. *)
Definition choices parent selected values := map (fun value => DOM.Element
 (Identity.key_part parent ("option/" ++ Fields.choice_value_of value)) "option"
 ([("value",Fields.choice_value_of value)] ++
 if String.eqb selected (Fields.choice_value_of value) then [("selected","selected")] else [])
 [] [] empty [DOM.Text (Fields.choice_label value)]) values.
Definition descriptions {A}(children:list(S.node A)) := String.concat " "
 (map S.node_key (filter(fun child=>match S.node_meaning child with
 |S.InformationText Information.FieldValue|S.InformationText Information.Description=>true|_=>false end)children)).
Definition fact_content {A} (values:list(S.node A)) :=
 match values with
 |[value]=>match S.node_meaning value with S.ReadOnly _|S.Fact _=>true|_=>false end
 |[label;value]=>match S.node_meaning label,S.node_meaning value with
   |S.InformationText Information.FieldLabel,S.ReadOnly _
   |S.InformationText Information.FieldLabel,S.Fact _=>true|_,_=>false end
 |_=>false end.
Definition editor_border_width (field:Fields.field) :=
 match field with Fields.MessageText|Fields.CardTitle|Fields.CardDescription=>0|_=>1 end.
Definition editor_insets (activity:bool) (field:Fields.field) :=
 match field with Fields.MessageText=>Enclosure.Insets 0 0
 |_=>let insets:=Enclosure.spacing Enclosure.Field in
   Enclosure.Insets (Enclosure.inline_inset insets) (if activity then 0 else Enclosure.block_inset insets) end.
Definition editor_content_edges activity field :=
 2*(Enclosure.block_inset(editor_insets activity field)+editor_border_width field).
Definition editor {A} env (activity:bool) key label generation owner field (value:Model.edit_control A) attributes styles :=
 let styles:=styles++native_field_properties "" in
 let native:=Parameters.native_value field (Model.editing_observation value) in
 let text:=match Model.editing_buffer value with Some raw=>raw|None=>native_string native end in
 let enabled:=Model.available (Model.editing_availability value) in
 let events:=match Model.editing_input value with None=>[]|Some _=>
 [event key generation "input" "value" Gesture.Change] end in
 let metadata:=JObject [("field_session",JObject [("owner",Identity.encode_editor owner);("source",JString text)]);
 ("selection",selection_json (Model.editing_selection value))] in
 let attrs:=attributes ++ [("aria-label",label)] ++
 (match field with
 |Fields.MessageText=>[("placeholder","Ask anything, or describe a task")]
 |Fields.CardLabels=>[("placeholder","每行一个标签")]
 |Fields.CardTitle|Fields.CardDescription=>[("placeholder",label)]
 |_=>[]end) ++ disabled enabled in
 if ControlPurpose.toggle_widget field(Model.editing_observation value) then
 let checked:=Parameters.native_checked field(Model.editing_observation value)in
 checkbox_target env key (DOM.Element key "input"
 (attrs ++ [("type","checkbox")] ++
 match checked with Some true=>[("checked","checked")]|Some false=>[]
 (* DEFENSE: an unavailable context has no observed boolean. The native
    checkbox must not present it as an editable false value. *)
 |None=>[("disabled","disabled");("indeterminate","true")]end)
 styles (match Model.editing_input value with None=>[]|Some _=>[event key generation "change" "checked" Gesture.Change] end) metadata [])
 else match Model.editing_entry value with
 | Fields.Choice=>DOM.Element key "select" (attrs ++ [("value",text)]) styles
 (match Model.editing_input value with None=>[]|Some _=>[event key generation "change" "value" Gesture.Change] end)
 metadata (choices key text (Model.editing_choices value))
 | Fields.Multiline | Fields.StructuredText=>DOM.Element key "textarea"
 (attrs ++ [("value",text);("data-field-entry","multiline")])
 (styles ++ [("field-sizing","content")] ++
 (match field with Fields.MessageText=>[("min-block-size",Typography.px
   (Layout.input_line_height (Layout.parameters env) * Layout.writing_lines))]|_=>[]end) ++
 [("max-block-size",Typography.px (editor_content_edges activity field+
   Layout.input_line_height (Layout.parameters env) *
   (Layout.input_maximum_height (Layout.parameters env) / Layout.input_line_height (Layout.parameters env))))]) events metadata []
 | Fields.PositiveInteger=>DOM.Element key "input"
 (attrs ++ [("type","number");("min","1");("step","1");("value",text)]) styles events metadata []
 | Fields.DisplayOnly=>DOM.Element key "span" attrs styles [] empty [DOM.Text text]
 | Fields.SingleLine=>DOM.Element key "input" (attrs ++ [("type","text");("value",text)]) styles events metadata []
 | Fields.MultipleChoices=>DOM.Element key "select" (attrs++[("multiple","multiple")]) styles
 (match Model.editing_input value with None=>[]|Some _=>[event key generation "change" "values" Gesture.Change]end) metadata
 (map(fun choice=>let choice_value:=Fields.choice_value_of choice in
 DOM.Element (String.append key(String.append "/" choice_value)) "option"
 ([("value",choice_value)]++match native with JArray values=>if existsb(fun value=>match value with JString text=>String.eqb choice_value text|_=>false end)values then[("selected","selected")]else[]|_=>[]end)
 [] [] empty [DOM.Text(Fields.choice_label choice)])(Model.editing_choices value))
 | Fields.DirectoryCollection|Fields.FileCollection=>DOM.Element key "div" attrs styles [] empty []
 end.
Definition interactive_editor {A} env key label generation (component:option IP.component)
 (value:IP.editor A) attrs styles :=
 let properties:=Some(IP.component_properties(IP.editing_component value)) in
 let component_tag:=Vocabulary.component_tag(Expand.description(IP.component_properties(IP.editing_component value))) in
 let styles:=styles++native_field_properties (if String.eqb component_tag "slider" then "range" else "") in
 let text:=match IP.editing_raw value with Some raw=>raw|None=>native_string (IP.editing_value value) end in
 let enabled:=IP.editing_enabled value in
 let attrs:=attrs ++ [("aria-label",label)] ++ disabled enabled ++
 (match IP.editing_validation value with Some _=>[("aria-invalid","true");("aria-describedby",String.append key "/validation")]|None=>[] end) in
 let events name kind:=match IP.editing_receive value with None=>[]|Some _=>[event key generation name kind Gesture.Change] end in
 let schema:=Local.shape_json(IP.editing_shape value) in
 let constraints:=fold_right (fun name rest=>match field name schema with
 |Some JNull|None=>rest|Some value=>(name,native_string value)::rest end) [] ["min";"max";"step"] in
 let identity:=JObject (Selvedge.Interaction.Interactive.Types.event_fields
     (IP.component_event (IP.editing_component value)) ++
   [("state",JString (match IP.component_binding (IP.editing_component value) with Expand.FieldLink id _=>id|_=>"" end));
    ("schema",schema); ("tag",JString component_tag)]) in
 let metadata:=JObject [("field_session",JObject [("owner",identity);("source",JString text)])] in
 if String.eqb component_tag "checkbox" then checkbox_target env key (DOM.Element key "input"
 (attrs ++ [("type","checkbox")] ++ if native_checked (IP.editing_value value) then [("checked","checked")] else [])
 (styles ++ SemanticAppearance.toggle_properties env) (events "change" "checked") metadata [])
 else if String.eqb component_tag "select" then
 let options:=match array_field "options" schema with Some values=>values|None=>[] end in
 DOM.Element key "select" (attrs ++ [("value",text)]) styles (events "change" "value") metadata
 (map (fun option=>let label:=match string_field "label" option with Some s=>s|None=>native_string option end in
 let option_value:=match field "value" option with Some v=>native_string v|None=>native_string option end in
 DOM.Element (key++"/"++option_value)%string "option" [("value",option_value)] [] [] empty [DOM.Text label]) options)
 else if String.eqb component_tag "textarea" then DOM.Element key "textarea"
 (attrs ++ [("value",text);("data-field-entry","multiline")])
 (styles++[("block-size",Typography.px (16+6*Layout.input_line_height(Layout.parameters env)));
 ("min-block-size",Typography.px (16+6*Layout.input_line_height(Layout.parameters env)));
 ("max-block-size",Typography.px (16+6*Layout.input_line_height(Layout.parameters env)))]) (events "input" "value") metadata []
 else DOM.Element key "input" (attrs ++ [("type",if String.eqb component_tag "slider" then "range" else "text");("value",text)] ++
 (if String.eqb component_tag "number-input" then ("inputmode","decimal")::map(fun property=>(String.append "data-number-" (fst property),snd property))constraints else constraints))
 styles (events "input" "value") metadata [].
Definition label_field env activity key label (beside:bool) (field:DOM.node) :=
 DOM.Element (String.append key "/field-wrapper") (if beside then "label"else"div") []
 (Layout.member_properties env activity false ++[("display","flex");
 ("flex-direction",if beside then "row"else"column");
 ("inline-size","100%");("max-inline-size","100%")]) [] empty
 [DOM.Element (String.append key "/field-label") "span" []
 (NativeAppearance.information_properties env activity Information.FieldLabel) [] empty [DOM.Text label];field].
Definition graphic_tone color := ("var(--color-token-" ++ match color with
 |Graphics.Neutral=>"text-primary"|Graphics.Accent=>"icon-accent"|Graphics.Success=>"text-success"
 |Graphics.Warning=>"text-warning"|Graphics.Danger=>"text-danger"|Graphics.Muted=>"text-secondary" end ++ ")")%string.
Definition graphic_primitive {A} generation (value:Graphics.primitive A) :=
 let element key tag attrs events children:=DOM.Element key tag attrs [] events empty children in
 let position x y:=[("x",show_integer x);("y",show_integer y)] in
 match value with
 |Graphics.Line x y u v color=>element "" "line" [("x1",show_integer x);("y1",show_integer y);("x2",show_integer u);("y2",show_integer v);("stroke",graphic_tone color)] [] []
 |Graphics.CubicCurve x y c1x c1y c2x c2y u v arrow color=>element "" "path"
 [("d",Graphics.curve_path x y c1x c1y c2x c2y u v arrow);("fill","none");("stroke",graphic_tone color);("stroke-width","1.5")] [] []
 |Graphics.StrokePath data color=>element "" "path" [("d",data);("fill","none");("stroke",graphic_tone color);("stroke-width","2")] [] []
 |Graphics.FilledPath data color=>element "" "path" [("d",data);("fill",graphic_tone color)] [] []
 |Graphics.Rectangle x y w h color=>element "" "rect" (position x y ++ [("width",text_number w);("height",text_number h);("fill",graphic_tone color)]) [] []
 |Graphics.Circle x y radius color=>element "" "circle" [("cx",show_integer x);("cy",show_integer y);("r",text_number radius);("fill",graphic_tone color)] [] []
 |Graphics.Label x y text color=>element "" "text" (position x y ++ [("fill",graphic_tone color)]) [] [DOM.Text text]
 |Graphics.Hitbox key x y w h label _=>element key "rect" (position x y ++ [("width",text_number w);("height",text_number h);("fill","transparent");("tabindex","0");("role","button");("aria-label",label)]) [event key generation "click" "activate" Gesture.Press;event key generation "keydown" "press_key" Gesture.Press] []
 end.
Definition layer_metadata {A} key (behavior:Model.layer_behavior A) :=
 JObject [("layer",JObject [("modal",JBool (Model.modal_layer behavior));
 ("identity",JString key);("occurrence",JNumber (text_number(Model.layer_occurrence behavior)));
 ("initial",JString (Model.layer_initial_attention behavior));
 ("return",JString (Model.layer_return_attention behavior));
 ("fallback",JString (Model.layer_fallback_attention behavior));
 ("outside",JBool (Model.layer_outside behavior));("escape",JBool (Model.layer_escape behavior))])].
Module C := ControlPurpose.
Inductive area := OutsideArea|PageArea|CreationArea|ComposerArea|ToolbarArea|DialogArea|MenuArea|NavigationArea|WorkStripArea|WorkCollectionArea
 |TouchNavigationArea|BoardLaneArea|BoardViewArea|CardArea|CollectionArea|CodeArea|ChoiceGroupArea.
Definition area_for {A} inherited role (meaning:S.meaning A) := match meaning with
 |S.BoardLane _ _=>BoardLaneArea|S.WorkspaceCollection _ _=>CollectionArea|S.CodeFacts _=>CodeArea
 |S.PageBody (Composition.Creation _)=>CreationArea
 |S.PageBody _=>PageArea
 |S.NavigationRegion Identity.TasksDrawer _=>TouchNavigationArea
 |S.ActionUnit _ _=>ComposerArea
 |S.ChoiceGroup|S.DecisionGroup _ _=>ChoiceGroupArea
 |S.BoardGroup S.ViewChoices=>BoardViewArea
 |S.BoardGroup S.SecondaryActions|S.BoardGroup S.PrimaryAction=>ToolbarArea
 |_=>match role with Roles.Composer|Roles.ComposerActions=>ComposerArea
 |Roles.Main=>PageArea|Roles.CodeBlock=>CodeArea|Roles.Field=>CollectionArea
 |Roles.Toolbar=>match inherited with ComposerArea=>ComposerArea|_=>ToolbarArea end
 |Roles.Dialog|Roles.DialogActions|Roles.Details=>DialogArea|Roles.Menu=>MenuArea
 |Roles.GlobalNavigation _=>NavigationArea
 |Roles.Navigation=>match inherited with TouchNavigationArea=>TouchNavigationArea|_=>NavigationArea end
 |Roles.WorkTabs=>WorkStripArea|Roles.WorkTabGroup=>WorkCollectionArea
 |Roles.CompactHeader|Roles.CompactNavigationMenu|Roles.CompactNavigationEntry _=>TouchNavigationArea
 |Roles.Card=>CardArea|_=>inherited end end.
Definition heading_properties env (activity:bool) context :=
 Typography.properties (Layout.root_font_size_milli env)
  (if activity then Typography.ActivityPrimary else match context with
    |CreationArea=>Typography.Display|PageArea=>Typography.Title|_=>Typography.Section end)
  Typography.Medium.
Definition purpose_icon purpose := match purpose with
 |C.MessageSubmission=>Some "arrow-up"|C.CreateItem|C.ProjectTaskCreation=>Some "plus"
 |C.WorkCreation=>Some "plus"|C.EditItem=>Some "pencil"|C.NavigateTo icon|C.OpenPanel icon _ _=>Some icon
 |C.ApplicationSettings _=>Some "settings"|C.GlobalDestinations=>Some "menu-lines"
 |C.MoreActions _=>Some "more-dots"|C.WorkspacePicker _=>Some "folder"
 |C.Dismiss|C.AbortOperation=>Some "close-cross"
 |C.StopExecution|C.InterruptExecution=>Some "stop-square"|C.PauseExecution=>Some "pause-bars"
 |C.ResumeExecution=>Some "play-triangle"|C.ApprovalDecision true=>Some "check"
 |C.ApprovalDecision false|C.RemoveValue=>Some "close-cross"|C.DeleteItem=>Some "trash"
 |C.ArchiveItem true=>Some "restore"|C.ArchiveItem false=>Some "archive-box"
 |C.PinItem _=>Some "pin"|C.Regenerate|C.RetryTransfer=>Some "refresh"
 |C.CopyCode state=>Some(match state with CodeBlock.Idle=>"copy-sheets"|CodeBlock.Pending _=>"spinner"
 |CodeBlock.Feedback _ true=>"check"|CodeBlock.Feedback _ false=>"warning"end)
 |C.WrapCode _=>Some "wrap-lines"|C.Latest=>Some "arrow-down"
 |C.ToggleNavigation expanded=>Some(if expanded then "sidebar-close" else "sidebar")
 |C.ResetDefaults=>Some "undo"|C.PreviewFile=>Some "preview"|C.DownloadFile=>Some "download"
 |C.Connect true=>Some "spinner"|_=>None end.
Definition icon_only purpose area := match purpose,area with
 |C.WorkCreation,DialogArea|C.WorkCreation,TouchNavigationArea=>false
 |C.WorkCreation,_|C.EditItem,NavigationArea|C.EditItem,TouchNavigationArea
 |C.MessageSubmission,ComposerArea|C.Dismiss,_|C.MoreActions _,_|C.Latest,_|C.ToggleNavigation _,_
 |C.ProjectTaskCreation,NavigationArea|C.ProjectTaskCreation,TouchNavigationArea|C.CreateItem,BoardLaneArea
 |C.OpenPanel "inspector" _ _,ToolbarArea|C.OpenPanel "settings" _ _,_|C.ApplicationSettings _,_|C.GlobalDestinations,_|C.OpenPanel "filter-funnel" _ _,_
 |C.OpenPanel "archive-box" _ _,ToolbarArea|C.CopyCode _,CodeArea|C.WrapCode _,CodeArea
 |C.RemoveValue,CollectionArea|C.StopExecution,ToolbarArea|C.PauseExecution,ToolbarArea
 |C.ResumeExecution,ToolbarArea|C.InterruptExecution,ToolbarArea=>true|_,_=>false end.

Record control_geometry := ControlGeometry {
  target_width : nat; target_height : nat; control_radius : nat;
  control_insets : Enclosure.insets; control_gap : nat
}.
Definition geometry_for purpose area (icon choice supporting : bool) :=
  if choice then ControlGeometry 0 28 6 (Enclosure.spacing Enclosure.OptionControl) 8 else
  if supporting then ControlGeometry 0 32 6 (Enclosure.Insets 8 0) 8 else
  if icon then match purpose, area with
  | C.MessageSubmission, ComposerArea => ControlGeometry 32 32 16 (Enclosure.spacing Enclosure.IconControl) 0
  | C.ProjectTaskCreation, NavigationArea => ControlGeometry 24 24 6 (Enclosure.spacing Enclosure.IconControl) 0
  | _, _ => ControlGeometry 32 32 8 (Enclosure.spacing Enclosure.IconControl) 0 end
  else match purpose, area with
  | C.ChooseValue _, ComposerArea | C.WorkspacePicker _, ComposerArea =>
      ControlGeometry 0 28 6 (Enclosure.spacing Enclosure.TextControl) 6
  | _, MenuArea => ControlGeometry 0 28 6 (Enclosure.spacing Enclosure.TextControl) 6
  | _, NavigationArea => ControlGeometry 0 29 6 (Enclosure.spacing Enclosure.NavigationRow) 6
  | _, _ => ControlGeometry 0 32 8 (Enclosure.spacing Enclosure.TextControl) 6 end.
Definition navigation_target env role area :=
  let compact := match Layout.observe_capacity env with Some (false, _) => true | _ => false end in
  match area, role with
  | TouchNavigationArea, _ | _, Roles.CompactNavigationEntry _
  | _, Roles.GlobalNavigationEntry _ true => true
  | NavigationArea, _ => compact
  | _, _ => false end.
Definition control_geometry_properties env (activity : bool) role area purpose icon choice supporting :=
  let value := geometry_for purpose area icon choice supporting in
  let scale := fun amount => if activity then match amount with
    | 0 => 0 | S _ => Typography.scaled (Layout.root_font_size_milli env) amount end else amount in
  let motor := if activity then Layout.motor_minimum env else Layout.base_motor_minimum in
  let touch := navigation_target env role area in
  let height := Nat.max (if touch then 44 else motor)
    (if activity then Nat.max motor (target_height value)
     else scale (target_height value)) in
  let edges := if activity then
    (if icon then Enclosure.Insets 0 0 else Enclosure.Insets 8 6)
    else control_insets value in
  [("min-inline-size",Typography.px motor);
   ("min-block-size",Typography.px height);
   ("border-radius",Typography.px (scale (control_radius value)));
   ("padding-inline",Typography.px (scale (Enclosure.inline_inset edges)));
   ("padding-block",Typography.px (scale (Enclosure.block_inset edges)));
   ("gap",Typography.px (scale (if activity && negb icon then 8 else control_gap value)));
   ("align-items",if activity && choice then "flex-start"else"center");
   ("justify-content",if icon then "center" else "flex-start");
   ("--control-icon-size",Typography.px (scale 16))] ++
  if icon then
    let width := Nat.max (if touch then 44 else motor)
      (if activity then Nat.max motor (target_width value)
       else scale (target_width value)) in
    [("inline-size",Typography.px width); ("block-size",Typography.px height); ("flex","none")]
  else [].
Definition meaning_geometry {A} (describe : A -> C.purpose) env activity role area (meaning:S.meaning A) :=
  let properties action choice supporting :=
    let purpose := describe (Model.control_input action) in
    let activity := activity || supporting || match role with
      | Roles.GlobalNavigationEntry _ _ | Roles.CompactNavigationEntry _
      | Roles.CompactWorkScope _ _ | Roles.NavigationEntry _ | Roles.WorkOverviewButton _ => true
      | _ => false end in
    control_geometry_properties env activity role area purpose (icon_only purpose area) choice supporting in
  match role, meaning with
  | Roles.WorkTab _, _ | _, S.WorkChoice _ _ _ =>
      [("min-inline-size",Typography.px Layout.base_motor_minimum)]
  | _, S.Activate action | _, S.SettingEntry _ _ action | _, S.ActionCommit _ _ action
  | _, S.PanelToggle _ action | _, S.SkillSuggestion _ action => properties action false false
  | _, S.SupportingControl _ _ _ action => properties action false true
  | _, S.Choice _ _ _ action => properties action
      (match area with BoardViewArea=>false|_=>true end) false
  | _, _ => [] end.
Definition purpose_attributes purpose := match purpose with
 |C.MoreActions expanded|C.OpenPanel _ _ expanded|C.ChooseValue expanded
 |C.WorkspacePicker expanded|C.ShowActivity expanded|C.ToggleNavigation expanded=>[("aria-expanded",flag expanded)]
 |C.ApplicationSettings expanded=>[("aria-expanded",flag expanded);("data-focus-alias","settings-return")]
 |C.GlobalDestinations=>[("aria-expanded","false");("data-focus-alias","settings-return")]
 |C.Connect true|C.CopyCode(CodeBlock.Pending _)=>[("data-interactive-motion","spin")]
 |C.SelectedOption checked=>[("aria-checked",flag checked)]
 |C.PinItem pinned|C.AutomaticScheduling pinned|C.WrapCode pinned=>[("aria-pressed",flag pinned)]
 |_=>[]end.
Definition control_styles purpose role := match purpose,role with
 |C.OpenPanel icon _ _,Roles.GlobalNavigationEntry _ _=>
 if String.eqb icon "settings" then [("margin-block-start","auto")]else[]
 |C.ApplicationSettings _,Roles.GlobalNavigationEntry _ _=>[("margin-block-start","auto")]
 |_,_=>[]end.
Definition face_children purpose area role label children :=
 let text:=match children with []=>[DOM.Text label]|_=>children end in
 let icon:=match purpose_icon purpose with Some name=>glyph name|None=>[]end in
 match role with
 |Roles.WorkTab _=>text
 |Roles.WorkOverviewButton count=>artwork "columns"++[DOM.Text(text_number count)]
 |Roles.CompactWorkScope title count=>
   [DOM.Element "" "span" (ControlContent.single_line_attributes title)
     (ControlContent.single_line_properties++[("flex","1 1 0%")]) [] empty [DOM.Text title];
    DOM.Element "" "span" [] [("flex","none")] [] empty [DOM.Text(text_number count)]]
 |Roles.GlobalNavigationEntry _ compact=>if compact then icon else icon++text
 |Roles.CompactNavigationEntry _=>icon++text
 |_=>match purpose with
 |C.ChooseValue _|C.WorkspacePicker _=>icon++text++artwork "chevron-down"
 |C.ShowActivity expanded=>text++artwork(if expanded then "chevron-down"else "chevron-right")
 |C.SelectedOption checked=>text++if checked then artwork "check"else[]
 |C.NavigateTo _=>icon++match role with Roles.GlobalNavigationEntry _ true=>[]|_=>text end
 |_=>if icon_only purpose area then icon else icon++text end end.
Definition choice_content env (activity : bool) key (selected : bool) (leading content : list DOM.node) :=
 let scale amount:=if activity then Typography.scaled(Layout.root_font_size_milli env)amount else amount in
 leading ++
 [DOM.Element (key++"/choice-text")%string "span" []
   [("display","flex");("flex-direction","column");("gap",Typography.px(scale 2));
    ("flex","1 1 0%");("min-inline-size","0");("text-align","start")] [] empty content;
  DOM.Element (key++"/choice-mark")%string "span" [("aria-hidden","true")]
   [("display","flex");("align-items","center");("justify-content","center");
    ("inline-size",Typography.px(scale 20));("block-size",Typography.px(scale 20));
    ("--control-icon-size",Typography.px(scale 16));("flex","none")]
   [] empty (if selected then glyph "check" else [])].
Fixpoint commit_key {A} (value:S.node A) : option string :=
 match S.node_meaning value with S.ActionCommit _ _ _=>Some (S.node_key value)
 | _=>(fix search (nodes:list(S.node A)):=match nodes with []=>None|head::tail=>
 match commit_key head with Some key=>Some key|None=>search tail end end) (S.node_children value) end.
Definition component_context {A} (current:option IP.component) (meaning:S.meaning A) :=
 match meaning with S.InteractiveNode value=>Some value|_=>current end.
Definition source_context {A} (current:S.meaning A) (meaning:S.meaning A) :=
 match meaning with
 | S.ActivityRow _ | S.ActivityGroup _ _ _ _ | S.LayerRegion _ | S.NavigationRegion _ _ => meaning
 | S.Region | S.InformationText _ => current
 | _ => match current with S.ActivityRow S.SupportingRow => current | _ => meaning end end.
Definition available_placements {A} (values:list(S.placement A)) :=
 filter(fun value=>Model.available(Model.control_availability(S.placement_control value)))values.
Definition card_movement {A} (values:list(S.node A)) :=
 fold_right(fun value rest=>match S.node_meaning value with
 |S.MovableCard _ placements=>Some(S.node_key value,available_placements placements)|_=>rest end)None values.
Definition card_drag {A} generation (movement:option(string*list(S.placement A))) :=
 JObject[("placements",JArray(match movement with None=>[]|Some(key,placements)=>
 map(fun destination=>JObject[("target",JString(S.placement_target destination));
 ("action",DOM.input_json(DOM.ElementTarget key(Gesture.gesture_name Gesture.Place)generation))])placements end))].
Definition card_part {A} (describe:A->C.purpose) (more:bool) (values:list(S.node A*DOM.node)) :=
 fold_right(fun pair rest=>let '(original,native):=pair in
 match S.node_meaning original with S.MovableCard _ _=>rest|meaning=>
 let selected:=match meaning with S.Activate control=>match describe(Model.control_input control)with C.MoreActions _=>true|_=>false end|_=>false end in
 if Bool.eqb selected more then native::rest else rest end)[]values.
Definition task_status_symbol status (working:bool) :=
 if String.eqb status "active"then if working then "play-triangle"else"idle-circle"
 else if String.eqb status "frozen"then"pause-bars"
 else if String.eqb status "stopped"then"stop-square"else"archive-box".
Definition native_field_stretches {A} (meaning:S.meaning A) :=
 match meaning with
 | S.Edit _ subject control =>
   negb (ControlPurpose.toggle_widget (UX.subject_declaration subject)
     (Model.editing_observation control))
 | S.InteractiveEdit _ _ control =>
   match IP.editing_shape control with Local.Boolean=>false|_=>true end
 | S.HistorySearchQuery _ _ _ | S.HistorySearchScope _ _ _ _
 | S.SearchChoices _ _ | S.BoardSearch _ _ | S.BoardProfile _ _ _ _ _
 | S.ReceiveFile _ _ _ | S.EnterDirectory _ _ _ _ => true
 | _ => false end.
Definition native_field_width {A} env (activity:bool) (meaning:S.meaning A) :=
 let inline_edges:=match meaning with S.Edit _ subject _=>
   let field:=UX.subject_declaration subject in
   2*(Enclosure.inline_inset(editor_insets false field)+editor_border_width field)
 |_=>2*(Enclosure.inline_inset(Enclosure.spacing Enclosure.Field)+1) end in
 if negb activity && native_field_stretches meaning then
   [("inline-size","100%");("min-inline-size",Typography.px
      (Layout.metric_advance(Layout.body_metric(Layout.font_metrics env))+inline_edges));("align-self","stretch")]
 else [].
(* Content alignment belongs to the container. Intrinsic controls retain their
   own width when that container stretches its other children. *)
Definition native_node_dimensions {A} role current_area (meaning:S.meaning A) :=
 let intrinsic := match meaning with
 | S.Activate _ | S.ActionCommit _ _ _ | S.PanelToggle _ _
 | S.SupportingControl _ _ _ _ | S.SkillSuggestion _ _
 | S.InformationText _ | S.Fact _ | S.ReadOnly _ => true
 | S.Choice _ _ _ _ => match current_area with BoardViewArea=>true|_=>false end
 | _ => match role with Roles.UserMessage=>true|_=>false end end in
 [("inline-size",if intrinsic then "fit-content"else"100%");("block-size","fit-content")] ++
 match role with Roles.UserMessage=>[("align-self","flex-end")]|_=>[]end.
Definition navigation_child_properties {A} (source:S.meaning A) role : list(string*string) :=
 match source with
 |S.NavigationRegion Identity.TasksDrawer _=>match role with
   |Roles.DialogHeader=>[("padding","0");("gap","0")]
   |Roles.DialogBody=>[("padding","0");("gap","0");("min-block-size","0");("overflow","hidden")]
   |Roles.Navigation=>[("inline-size","100%");("block-size","100%");
     ("min-block-size","0");("flex","1 1 auto")]
   |_=>[]end
 |_=>[]end.
Definition node_styles {A} (describe:A->C.purpose) env activity (source:S.meaning A) role
    (meaning:S.meaning A) current_area (supporting responsive:bool) :=
let styles:=NativeAppearance.role_properties_at env activity role ++
 native_node_dimensions role current_area meaning ++
 (match meaning with S.LayerRegion behavior|S.NavigationRegion _ behavior|S.ActivityGroup _ _ _ behavior=>match Model.layer_presentation behavior with
 |Model.AnchoredMenu=>[("position","fixed");("inset","auto");
  ("--layer-clearance",Typography.px(Layout.layer_clearance env));
  ("--layer-gap",Typography.px(Layout.layer_unit env));
  ("position-area","bottom span-right");("position-try-fallbacks","flip-block, --native-menu-confined");
  ("position-try-order","normal");("align-self","start");("justify-self","start");
  ("top","calc(var(--layer-gap) - var(--layer-clearance))");
  ("left","calc(0px - var(--layer-clearance))");
  ("margin",Typography.px(Layout.layer_clearance env));("block-size","fit-content")]
 |Model.TrailingDetails=>if Model.layer_beside behavior then [("inline-size",Typography.px(Layout.details_width(Layout.parameters env)));("flex","none")] else []
 |Model.ModalDialog=>[]end|_=>[]end) ++ SemanticAppearance.meaning_properties env activity meaning ++
 meaning_geometry describe env activity role current_area meaning ++ SemanticAppearance.source_properties env source meaning ++
 (match meaning,current_area with
  |S.Choice _ selected _ _,BoardViewArea=>
    NativeAppearance.style_properties env (NativeAppearance.button_style(NativeAppearance.ChoicePaint selected)) ++
    [("min-inline-size",Typography.px Layout.base_motor_minimum);("justify-content","center")]
  |S.Choice _ true _ _,MenuArea=>[]
  |S.Choice _ true _ _,_=>[("--control-rest-background","transparent")]
  |_,_=>[]end) ++
 (match role with
 |Roles.WorkTabs=>[("display","flex");("flex-direction","row");("align-items","flex-end");
  ("padding-block-start",Typography.px(Typography.scaled(Layout.root_font_size_milli env)4));
  ("block-size",Typography.px(Typography.scaled(Layout.root_font_size_milli env)44));
  ("min-block-size",Typography.px(Typography.scaled(Layout.root_font_size_milli env)44));("flex","none");("overflow","hidden")]
 |Roles.WorkTabGroup=>[("display","flex");("flex-direction","row");("flex","1");("min-inline-size","0");("overflow-x","auto")]
 |Roles.WorkTab selected=>[("position","relative");("flex",match current_area with WorkCollectionArea=>"1 0 auto"|_=>"0 1 auto"end);
 ("min-inline-size",Typography.px(Typography.scaled(Layout.root_font_size_milli env)96));
 ("max-inline-size",Typography.px(Typography.scaled(Layout.root_font_size_milli env)
   (match current_area with WorkCollectionArea=>232|_=>152 end)));
 ("block-size",Typography.px(Typography.scaled(Layout.root_font_size_milli env)40))] ++
 (if selected then [("border-end-start-radius","0");("border-end-end-radius","0")] else [])
 |Roles.WorkOverviewButton _=>[("margin-inline-start","auto")]
 |Roles.CompactWorkScope _ _=>[("flex","1");("min-inline-size","0");("justify-content","space-between")]
 |Roles.GlobalNavigationEntry _ compact=>[("display","flex");("flex-direction",if compact then "row" else "column");("align-items","center");("justify-content","center");("inline-size","100%")]
 |Roles.GlobalNavigation compact=>[("inline-size",Typography.px(Typography.scaled(Layout.root_font_size_milli env)(if compact then 48 else 84)));("block-size","100%");("min-block-size","0");("flex","none")]|Roles.Navigation=>[("inline-size",Typography.px(Layout.navigation_width(Layout.parameters env)));("block-size","100%");("min-block-size","0");("flex","none")]|Roles.Main=>[("flex","1");("min-inline-size","0")]|_=>[] end) ++
 (match meaning with S.SummaryList=>[("list-style","none");("padding","0");("margin","0")]|S.InteractiveNode c=>InteractiveAppearance.component_properties env c
 |S.InteractivePlacement p=>InteractiveAppearance.placement_properties env p|_=>[] end) ++
 native_field_width env activity meaning ++
 ControlContent.node_properties env activity role meaning ++
 (match role,current_area with
  |Roles.Toolbar,ComposerArea=>[("align-self","flex-start");("gap",Typography.px Layout.composer_clearance)]
  |Roles.ComposerActions,_=>[("inline-size","100%")]
  |_,_=>[]end) ++
 (if supporting then ControlContent.support_row_properties
  else if responsive then Layout.row_properties Layout.Vertical ++
    [("inline-size","100%");("min-inline-size","0")] else []) in
 let styles:=match meaning with
 |S.LayerRegion behavior|S.NavigationRegion _ behavior|S.ActivityGroup _ _ _ behavior=>
   if Model.modal_layer behavior then
    let clearance:=match meaning with S.NavigationRegion Identity.WorkOverview _=>Layout.work_overview_clearance|_=>Layout.layer_clearance env end in
    let viewport_width:=Nat.sub(Layout.viewport_width env)(2*clearance) in
    let reading_width:=match meaning with S.ActivityGroup _ _ _ _=>
      SemanticAppearance.surface_maximum_width env|S.NavigationRegion Identity.WorkOverview _=>
      2*Layout.reading_maximum_width(Layout.parameters env)|_=>Layout.dialog_reading_width env end in
    let maximum_width:=Nat.min reading_width viewport_width in
    let maximum_height:=Nat.sub(Layout.viewport_height env)(2*clearance) in
    match Model.layer_presentation behavior with
    |Model.AnchoredMenu=>
     (* The position area is the available side of the trigger; constrain a tall
        menu to that area so every action remains reachable by scrolling. *)
     set_style "max-block-size" (Typography.px maximum_height)
      (set_style "max-inline-size" (Typography.px maximum_width)
       (set_style "overflow" "auto" styles))
    |_=>set_style "max-block-size" (Typography.px maximum_height)
      (set_style "max-inline-size" (Typography.px maximum_width)
       (set_style "overflow" "hidden" styles)) end
   else styles
 |_=>styles end in
 let styles:=match meaning with S.NavigationRegion Identity.WorkOverview _=>
   set_style "inline-size" (Typography.px(Layout.work_overview_width env))
    (set_style "block-size" (Typography.px(Layout.work_overview_height env)) styles)
 |S.NavigationRegion Identity.TasksDrawer _=>styles++Layout.modal_navigation_properties env++
   [("background",NativeAppearance.background NativeAppearance.NavigationPaint NativeAppearance.Rest)]
 |_=>styles end in
 styles ++ navigation_child_properties source role ++ match role,meaning with
 |Roles.Heading,S.InformationText Information.NavigationCaption=>[]
 |Roles.Heading,_=>heading_properties env activity current_area
 |Roles.Alert,_=>
   match meaning with S.InformationText _=>NativeAppearance.alert_color_properties
   |_=>NativeAppearance.alert_properties env end
 |_,_=>[]end.

Definition compile_element {A} (describe:A->C.purpose) env generation inherited_area activity (source:S.meaning A) view component (value:S.node A) (children:list DOM.node) : DOM.node :=
 let key:=S.node_key value in let label:=S.node_label value in
 let meaning:=S.node_meaning value in let role:=S.node_role value in
 let current_area:=area_for inherited_area role meaning in
 let activity:=match meaning with S.ActivityGroup _ _ _ _|S.ActivityRow _=>true
  |_=>match role with Roles.Button|Roles.SelectedButton=>match current_area with
      |NavigationArea|TouchNavigationArea=>true|_=>activity end
     |_=>activity end end in
 let authored_children:=children in
 let children:=match ControlContent.container_content describe glyph env key label role meaning (S.node_children value) children with Some content=>content|None=>children end in
 let supporting:=match meaning with S.PageRegion Composition.CreationContext _=>false
  |_=>match role with Roles.Toolbar=>ControlContent.support_row(S.node_children value)|_=>false end end in
 let responsive:=SemanticAppearance.responsive_row activity source role meaning in
 let attrs:=common key (S.semantic_key value) label role ++
 (match source,meaning with
  |S.PageRegion Composition.ConversationTitle _,S.InformationText _
  |S.WorkChoice _ _ _,S.InformationText _=>ControlContent.single_line_attributes label
  |_,S.InformationText Information.NavigationCaption=>ControlContent.single_line_attributes label
  |_,_=>[]end) ++
 NativeAppearance.overflow_attributes (NativeAppearance.style_overflow (NativeAppearance.role_style role)) label ++
 (match role with Roles.Timeline=>[("tabindex","0")]|Roles.UserMessage|Roles.AssistantMessage=>[("data-reading-anchor","true")]|Roles.Composer=>[("data-composer-dock","true");("data-focus-owner","aggregate")]|_=>[] end) ++
 (if supporting then ControlContent.support_row_attributes key
  else if responsive then [("data-native-responsive-row",key);("data-native-row-direction","column")] else []) in
 let styles:=node_styles describe env activity source role meaning current_area supporting responsive in
 let collection_field:=match meaning with S.WorkspaceCollection _ _=>true
  |S.Region=>existsb(fun child=>match S.node_meaning child with
      S.ReceiveFile _ _ _=>true|_=>false end)(S.node_children value)
  |_=>false end in
 let styles:=if collection_field then styles++[("gap","8px")]else styles in
 let styles:=match role with
 |Roles.WorkTabGroup=>styles++[("max-inline-size",Typography.px
   (List.length(S.node_children value)*Typography.scaled(Layout.root_font_size_milli env)232))]
 |_=>styles end in
 let styles:=match role,meaning with
 |Roles.Content,S.Region=>if fact_content(S.node_children value)then
   styles++[("display","flex");("flex-direction","column");("gap","4px")]else styles
 |_,_=>styles end in
 let element tag extra events metadata content:=
 let field_styles:=if String.eqb tag "input" || String.eqb tag "textarea" || String.eqb tag "select"
   then native_field_properties (match attribute_value "type" extra with Some kind=>kind|None=>"" end)
   else [] in
 DOM.Element key tag (attrs++extra) (styles++field_styles) events metadata content in
 let button (submit:bool) action extra:=
 let purpose:=describe(Model.control_input action)in
 let focusable:=andb (icon_only purpose current_area) (match role with Roles.NavigationEntry _=>false|_=>true end) in
 let available:=Model.available(Model.control_availability action) in
 let property_help:=match meaning with S.SettingEntry _ property _|S.SupportingControl _ _ property _=>Some(UX.property_help property)|_=>None end in
 let description:=match Model.control_availability action with Model.Unavailable reason=>reason
 | _=>match property_help with Some text=>text|None=>control_help action end end in
 let help:=focusable || negb available || match property_help with Some _=>true|None=>match role with Roles.NavigationEntry _=>true|_=>false end end in
 let type_:=(if andb submit available then "submit" else "button") in
 let events:=if available then [event key generation "click" "activate" Gesture.Press] else [] in
 DOM.Element key "button" (attrs++[("type",type_)] ++control_attributes (focusable || negb available) help action++
 (match property_help with Some _=>[("title",description)]|None=>[]end)++
 (if help then [("data-help",description)]else[])++purpose_attributes purpose++help_describedby key help extra)
 (styles++control_styles purpose role++
 (match source with S.TaskRow _ _ _ _ _=>[("display","flex");("flex-direction","row");("align-items","center");("inline-size","100%");("min-inline-size",Typography.px(Layout.motor_minimum env));("padding","0");("gap",Typography.px(ControlContent.navigation_following env))]|_=>[]end)++match source,purpose with S.CardContent _,C.OpenCardDetails _=>
 [("background","transparent");("border","0");("padding","0");("text-align","left");("font-weight","600");("white-space","normal")]|_,_=>[]end)
 events empty
 ((match ControlContent.face_content env key glyph meaning (S.node_children value) with Some content=>content|None=>
 match source,purpose with S.CardContent face,C.OpenCardDetails card=>
 if N.eqb card(Model.card_identity face)then[DOM.Text(Model.card_title face)]
 else face_children purpose current_area role(Model.control_label action)children
 |S.TaskRow _ status caption working _,C.NavigateTo icon=>
 [DOM.Element(key++"/identity-slot")%string "span" [("data-navigation-slot","identity")]
 [("display","flex");("align-items","center");("justify-content","center");("inline-size",Typography.px(Nat.max(ControlContent.navigation_rail env)(ControlContent.navigation_target env)));("block-size",Typography.px(ControlContent.navigation_target env));("flex","none")] [] empty(glyph icon);
 DOM.Element(key++"/title-slot")%string "span" ([("data-navigation-slot","title")] ++
 NativeAppearance.overflow_attributes NativeAppearance.SingleLineOverflow (Model.control_label action))
 [("flex","1 1 0%");("min-inline-size","0");("overflow","hidden");("text-overflow","ellipsis");("white-space","nowrap");("text-align","start")] [] empty
 (match children with []=>[DOM.Text(Model.control_label action)]|_=>children end);
 DOM.Element(key++"/status-slot")%string "span"[("data-navigation-slot","status");("role","img");("aria-label",caption);("title",caption)]
 [("display","flex");("align-items","center");("justify-content","center");("inline-size","16px");("block-size","16px");("flex","none")][]empty(glyph(task_status_symbol status working))]
 |_,_=>match meaning with
   |S.Choice _ selected _ _=>match current_area with
    |BoardViewArea=>face_children purpose current_area role(Model.control_label action)authored_children
    |_=>choice_content env activity key selected
      (match purpose with C.BoardFilterChoice category value=>
        match ControlContent.board_filter_glyph category value with Some name=>glyph name|None=>[]end|_=>[]end)
      (match authored_children with []=>[DOM.Text(Model.control_label action)]|_=>authored_children end)end
   |S.WorkChoice _ selected _=>choice_content env activity key selected []
      (match authored_children with []=>[DOM.Text(Model.control_label action)]|_=>authored_children end)
   |_=>face_children purpose current_area role(Model.control_label action)children end end end) ++
 (match role with Roles.WorkTab false=>
  [DOM.Element(key++"/separator")%string "span" [("aria-hidden","true")]
   [("position","absolute");("inset-inline-end","0");("inset-block-start","50%");
    ("transform","translateY(-50%)");("inline-size","1px");
    ("block-size",Typography.px(Typography.scaled(Layout.root_font_size_milli env)18));
    ("background",NativeAppearance.token "--color-token-border-default");("pointer-events","none")] [] empty []]
  |_=>[]end) ++
 (if help then [DOM.Element (String.append key "/help") "span"
   [("id",String.append key "/help");("class","visually-hidden")] [] [] empty
   [DOM.Text description]] else []))in
 match meaning with
 |S.InformationText info=>element (text_tag info) ([("tabindex","-1")] ++
   match info with Information.Status=>[("role","status")]|_=>[]end) [] empty [DOM.Text label]
 |S.ReadOnly text=>element "span"
 (match role with Roles.Alert=>[("role","alert")]|_=>[]end) [] empty [DOM.Text text]
 |S.Fact text=>element "span"
 (match role with Roles.Alert=>[("role","alert")]|_=>[]end) [] empty
 [DOM.Text(if String.eqb text ""then "—"else text)]
 |S.ActionFeedback _ _ message=>element "p"
 (match role with Roles.Alert=>[("role","alert");("aria-live","assertive")]|_=>[("role","status")]end)
 [] empty [DOM.Text message]
 |S.DirectoryBrowserLocation path=>element "p" [] [] empty [DOM.Text path]
 |S.PublishedText document=>element "div" [] [] empty
 (physical_markdown env (if activity then Typography.ActivityPrimary else Typography.Body) NativeAppearance.PublishedMarkdown
 (String.append key "/@physical-markdown") (String.append key "/markdown")
 (DocumentPublication.published_text document)
 (match DocumentPublication.published_ending document with
 Selvedge.Interaction.Interactive.Types.Open=>false|_=>true end)
 (match DocumentPublication.encode_document document with JObject fields=>JObject(("view",Observation.encode_view view)::fields)|metadata=>metadata end)::children)
 |S.RichText provenance text=>element "div" [] [] empty
 (physical_markdown env (if activity then Typography.ActivityPrimary else Typography.Body) NativeAppearance.PublishedMarkdown
 (String.append key "/@physical-markdown") (String.append key "/markdown") text
 (match provenance with CodeSource.Generated _ _ _ complete=>complete|_=>true end)
 (JObject [("source",CodeSource.encode_source provenance);("view",Observation.encode_view view)])::children)
 |S.EmbeddedMarkdown text=>physical_markdown env (if activity then Typography.ActivityPrimary else Typography.Body) NativeAppearance.EmbeddedMarkdown
 (String.append key "/@physical-markdown") key text true empty
 |S.CodeFacts facts=>
 let who:=CodeBlock.presented_identity facts in
 let target part:=Observation.physical_target view (DocumentPublication.target_key who part) in
 element "div" [("data-code-owner",CodeSource.key who)] []
 (JObject[("code",JObject[("identity",CodeSource.encode_identity who);("view",Observation.encode_view view);("text",JString(CodeBlock.presented_literal facts))])])
 [DOM.Element (target DocumentPublication.Frame) "div" [("data-code-frame","true")] [] [] empty
 [DOM.Element (target DocumentPublication.Toolbar) "div" [] [] [] empty [];
 DOM.Element (target DocumentPublication.Source) "pre" [] [] [] empty
 [DOM.Element (target DocumentPublication.Body) "code" [] [] [] empty [DOM.Text(CodeBlock.presented_literal facts)]]]]
 |S.InteractiveRegion policy=>DOM.Mount (Observation.physical_target view (DocumentPublication.target_key (DocumentPublication.fence_identity policy) DocumentPublication.Preview))
   (interactive_status env activity (String.append key "/@pending") "data-interactive-pending" "正在更新显示" :: children)
 |S.Activate action=>button false action []
 |S.SettingEntry _ _ action|S.SupportingControl _ _ _ action=>button false action
 (let described:=descriptions(S.node_children value)in if String.eqb described ""then[]else[("aria-describedby",described)])
 |S.ActionCommit _ _ action=>button true action []
 |S.WorkChoice _ selected action=>button false action [("aria-pressed",flag selected)]
 |S.Choice kind selected description action=>button false action
 ((match current_area with BoardViewArea=>[("aria-pressed",flag selected)]
   |_=>[("role",match kind with S.SingleChoice=>"radio"|S.MultipleChoice=>"checkbox" end);("aria-checked",flag selected)]end) ++
 let described:=descriptions(S.node_children value)in if String.eqb described ""then[]else[("aria-describedby",described)])
 |S.PanelToggle expanded action=>button false action [("aria-expanded",flag expanded)]
 |S.Edit owner subject value=>
 let field_attrs:=attrs ++ match current_area,UX.subject_declaration subject with
 |ComposerArea,Fields.MessageText=>[("data-focus-owner","embedded")]|_,_=>[]end in
 let native:=match editor env activity key label generation owner (UX.subject_declaration subject) value field_attrs styles with
 |DOM.Element key tag attrs styles events (JObject fields) content=>DOM.Element key tag attrs styles events
 (JObject(("key_input",JBool(match Model.editing_key_input value with Some _=>true|None=>false end))::("editor",Identity.encode_editor owner)::("selection_enabled",JBool(match Model.editing_selection_input value with Some _=>true|None=>false end))::fields)) content|native=>native end in
 match UX.subject_declaration subject,Model.editing_entry value with
 |Fields.MessageText,Fields.Multiline=>native
 |_,_=>label_field env activity key label
 (ControlPurpose.toggle_widget(UX.subject_declaration subject)(Model.editing_observation value)) native end
 |S.InteractiveEdit _ _ value=>DOM.Element (String.append key "/enclosure") "div" []
 [("display","flex");("flex-direction","column");("gap","6px")] [] empty
 (label_field env activity key label (match IP.editing_shape value with Local.Boolean=>true|_=>false end)
 (interactive_editor env key label generation component value attrs styles) ::
 match IP.editing_validation value with None=>[]|Some message=>
 [DOM.Element (String.append key "/validation") "output" [("id",String.append key "/validation");("role","status")]
 [("color",NativeAppearance.token "--interactive-tone-danger")] [] empty [DOM.Text message]]end)
 |S.HistorySearchQuery query _ confirm=>element "input" [("type","search");("value",query);("placeholder",label)]
 ([event key generation "input" "value" Gesture.Change] ++
  if Model.available(Model.control_availability confirm)
  then [event key generation "keydown" "confirm" Gesture.Press] else []) empty []
 |S.HistorySearchScope project selected values _=>element "select" [("value",match selected with None=>""|Some n=>text_number n end)]
 [event key generation "change" "value" Gesture.Change] empty (choices key (match selected with None=>""|Some n=>text_number n end) values)
 |S.BoardSearch selection _=>element "input" [("type","search");("value",BoardFilter.filter_query selection);("placeholder",label)] [event key generation "input" "value" Gesture.Search] empty []
 |S.SearchChoices query _=>element "input" [("type","search");("value",query);("placeholder",label)] [event key generation "input" "value" Gesture.Search] empty []
 |S.ReceiveFile _ enabled _=>element "input" ([("type","file")]++disabled enabled)
 [event key generation "change" "files" Gesture.Attach] empty []
 |S.EnterDirectory _ text _ confirm=>element "input" [("type","text");("value",text)]
 ([event key generation "input" "value" Gesture.Directory] ++match confirm with Some _=>[event key generation "keydown" "confirm" Gesture.ConfirmDirectory]|None=>[] end) empty []
 |S.BoardProfile automatic selected values enabled _=>element "select"
 ([("value",selected);("data-automatic",flag automatic)]++disabled enabled)
 [event key generation "change" "value" Gesture.SelectBoardProfile] empty (choices key selected values)
 |S.ActionUnit _ _=>element "form" [("novalidate","novalidate")]
 (match commit_key value with Some key=>[event key generation "submit" "submit" Gesture.Press]|None=>[] end) empty children
 |S.LayerRegion behavior|S.NavigationRegion _ behavior|S.ActivityGroup _ _ _ behavior=>
 element (if Model.modal_layer behavior then "dialog" else "aside")
 ([("role",if Model.modal_layer behavior then "dialog" else "complementary");("aria-modal",flag (Model.modal_layer behavior))] ++
 match Model.layer_presentation behavior with Model.AnchoredMenu=>[("data-anchor",Model.layer_anchor behavior);("data-native-layer","menu")]|_=>[]end)
 [event key generation "cancel" "dismiss" Gesture.Dismiss] (layer_metadata key behavior) children
 |S.Graphic plot=>DOM.Element key "svg" (attrs++[("viewBox",("0 0 "++text_number (Npos (Graphics.width plot))++" "++text_number (Npos (Graphics.height plot)))%string);("role","img");
 ("width",text_number(Npos(Graphics.width plot)));("height",text_number(Npos(Graphics.height plot)))])
 (styles++[("max-inline-size","none");("flex","none")]) [] empty (map (graphic_primitive generation) (Graphics.primitives plot))
 |S.Image src alternative=>element "img" [("src",src);("alt",alternative)] [] empty []
 |S.Table caption headings rows=>DOM.Element key "table" attrs (styles++table_properties) [] empty
 ([DOM.Element (key++"/caption")%string "caption" [] [] [] empty [DOM.Text caption];
 DOM.Element (key++"/head")%string "thead" [] [] [] empty [DOM.Element "" "tr" [] [] [] empty
 (map(fun text=>DOM.Element "" "th" [("scope","col")] table_cell_properties [] empty [DOM.Text text])headings)];
 DOM.Element (key++"/body")%string "tbody" [] [] [] empty
 (map(fun row=>DOM.Element "" "tr" [] [] [] empty (map(fun text=>DOM.Element "" "td" [] table_cell_properties [] empty [DOM.Text text])row))rows)])
 |S.InteractivePlacement placement=>element "div" [] [] empty children
 |S.ReadingTimeline task_view reader_generation=>element "section"
 [("data-reading-root","true");("data-task-id",text_number(Identity.task_view_task task_view));("data-reader-generation",text_number reader_generation)] [] empty children
 |S.PageBody page=>DOM.Element key (role_tag role) attrs (styles++Layout.page_properties env page) [] empty children
 |S.PageRegion region position=>element (role_tag role) [("data-page-region",Composition.region_name region)] [] empty children
 |S.BoardGroup grouping=>element "div" (ControlContent.board_group_attributes grouping) [] empty children
 |S.MovableCard face destinations=>
 let offered:=available_placements destinations in
 DOM.Element key "select" (attrs++[("value","")]++disabled(match offered with []=>false|_=>true end))
 (styles++NativeAppearance.role_properties env Roles.Field++native_field_properties "")
 [event key generation "change" "value" Gesture.Place] empty
 (DOM.Element "" "option" [("value","");("selected","selected");("disabled","disabled")] [] [] empty [DOM.Text "Move to…"]::
 map(fun destination=>DOM.Element "" "option" [("value",S.placement_target destination)] [] [] empty
 [DOM.Text(Model.control_label(S.placement_control destination))])offered)
 |S.InteractiveNode c=>
 let properties:=IP.component_properties c in
 let motion:=Expand.property_text "motion" properties in
 let common:=[("data-interactive-component",Vocabulary.component_tag(Expand.description properties));
 ("data-interactive-key",key);("data-interactive-transition",Expand.property_text "transition" properties)] in
 let children:=if String.eqb(Vocabulary.component_tag(Expand.description properties))"resource-view"
   then interactive_status env activity (String.append key "/@stale") "data-interactive-stale" "连接已断开，显示上次同步状态"::children
   else children in
 let native:=element (role_tag role)
 (common ++ if String.eqb(Vocabulary.component_tag(Expand.description properties))"row-layout"
 then [("data-native-responsive-row",key)] else []) [] empty children in
 if String.eqb motion "spin" then
 DOM.Element (String.append key "/motion") "div" [("data-interactive-motion",motion)]
 [("display","flex");("flex-direction","row");("gap","6px");("align-items","center");("min-inline-size","0")]
 [] empty (glyph "spinner"++[native])
 else match native with DOM.Element key tag attrs styles events metadata children=>
 DOM.Element key tag (("data-interactive-motion",motion)::attrs) styles events metadata children|other=>other end
 |S.InteractiveTable table=>DOM.Element key "table" attrs (styles++table_properties) [] empty
 [DOM.Element (key++"/caption")%string "caption" [] [] [] empty [DOM.Text(IP.table_caption table)];
 DOM.Element (key++"/head")%string "thead" [] [] [] empty [DOM.Element "" "tr" [] [] [] empty
 (map(fun column=>let identity:=IP.column_key key column in DOM.Element identity "th"
 [("scope","col");("aria-sort",match IP.column_order column with None=>"none"|Some true=>"descending"|Some false=>"ascending" end)] table_cell_properties [] empty
 (match IP.column_sort column with None=>[DOM.Text(IP.column_heading column)]|Some _=>
 [DOM.Element (identity++"/control")%string "button" ([("type","button")]++disabled(IP.column_enabled column))
 (NativeAppearance.role_properties env Roles.Button) [event identity generation "click" "activate" Gesture.Press] empty [DOM.Text(IP.column_heading column)]]end)) (IP.table_columns table))];
 DOM.Element (key++"/body")%string "tbody" [] [] [] empty
 (map(fun row=>let row_key:=Identity.key_part key(IP.row_identity row) in
  DOM.Element row_key "tr" [] [] [] empty
   (map(fun '(column,text)=>DOM.Element(IP.column_key row_key column)"td" []
     table_cell_properties [] empty [DOM.Text text])
    (combine(IP.table_columns table)(IP.row_values row))))(IP.table_rows table))]
 |S.ActivityContent expanded audit=>element "section" [("data-expanded",flag expanded)] [] empty
 ((if expanded then [] else [DOM.Element (String.append key "/summary") "p"
 [("data-activity-summary","true")] [("margin","0")] [] empty [DOM.Text label]]) ++
 children ++ if expanded then map(fun face=>
 let face_key:=String.append key (String.append "/audit/" (text_number(Audit.face_occurrence face))) in
 DOM.Element face_key "section" [] [] [] empty
 [DOM.Element "" "h4" [] [] [] empty [DOM.Text(Audit.face_title face)];
  physical_markdown env Typography.Support NativeAppearance.PublishedMarkdown (String.append face_key "/@physical-markdown") ""
   (Audit.detail(Audit.face_source face)) true (JObject [])])audit else [])
 |S.SummaryList=>element "ul" [("role","list")]
 [] empty (map(fun child=>DOM.Element "" "li" [] [] [] empty [child])children)
 |S.SkillSuggestions field expanded active=>DOM.Element key "div"
 (attrs++[("role","listbox");("data-anchor",field)]++if expanded then[]else[("hidden","")])
 (styles++[("position","fixed");("position-try-fallbacks","flip-block");
 ("left","anchor(left, 16px)");("bottom","anchor(top, 96px)");("margin-bottom","6px");
 ("inline-size","anchor-size(width, min(32rem, calc(100vw - 32px)))");
 ("max-inline-size","calc(100vw - 24px)");("max-block-size","min(18rem, 45vh)");
 ("overflow-y","auto");("padding","4px");("z-index","1000");
 ("border","1px solid var(--color-token-border-light)");("border-radius","10px");
 ("background","var(--color-token-main-surface-primary)");("color","var(--color-token-text-primary)");
 ("box-shadow","0 6px 24px #0002")]) [] empty children
 |S.SkillSuggestion selected action=>DOM.Element key "button"
 (attrs++[("type","button");("role","option");("tabindex","-1");
 ("aria-selected",flag selected);("data-retain-focus","true");("data-reveal-on-layout",flag selected)]++control_attributes false false action)
 (styles++[("display","flex");("flex-direction","column");("gap","2px");("inline-size","100%");
 ("padding","8px 12px");("text-align","left");("border","0");("border-radius","6px");
 ("background",if selected then "var(--color-token-main-surface-tertiary)"else"transparent");("cursor","pointer")])
 [event key generation "click" "activate" Gesture.Press] empty children
 |S.DecisionGroup _ decision=>element "section" [("role","radiogroup");("aria-label",UX.decision_question decision)] [] empty children
 |S.ChoiceGroup=>element "section" [("role","radiogroup")] [] empty children
 |S.PageContext conversation=>element (role_tag role) [("data-view",match conversation with Some v=>Identity.task_view_scope v|None=>"" end)] [] empty children
 |S.ProjectGroup project selected expanded=>element (role_tag role) [("data-project-id",text_number project);("data-expanded",flag expanded)] [] empty children
 |S.TaskRow task status caption working selected=>
 let paired:=combine(S.node_children value)children in
 let nested (pair:S.node A*DOM.node):=match S.node_meaning(fst pair)with S.TaskChildren _=>true|_=>false end in
 element "div" [("data-task-id",text_number task);("data-task-status",status);("aria-current",flag selected)] [] empty
 (map snd(filter(fun pair=>negb(nested pair))paired)++map snd(filter nested paired))
 |S.BoardLane stage count=>element (role_tag role) [("data-board-stage",stage);("data-drop-target",key)] [] empty children
 |S.CardArchive count=>element (role_tag role) [("data-card-archive",text_number count);("data-drop-target",key)] [] empty children
 |S.TaskChildren task=>element "div"[("role","group");("aria-label",label);("data-task-parent",text_number task)][]empty children
 |S.ActivityRow _|S.WorkspaceCollection _ _|S.WorkspaceMember _ _ _
 |S.ActionExplanation _ _|S.ObjectGroup _|S.Region|S.ProjectChooser _|S.DirectoryRow _ _
 |S.ContextSummary _=>element (role_tag role) [] [] empty children
 |S.CardContent face=>
 let movement:=card_movement(S.node_children value)in
 let movable:=match movement with Some(_, _::_)=>true|_=>false end in
 let text part value:=DOM.Element (key++"/"++part)%string "span" []
 (NativeAppearance.information_properties env false Information.Description) [] empty [DOM.Text value]in
 let optional part value:=if String.eqb value ""then[]else[text part value]in
 let row part (responsive:bool) content:=DOM.Element(key++"/"++part)%string "div"
 (if responsive then[("data-native-responsive-row",(key++"/"++part)%string)]else[])
 (Layout.row_properties(if responsive then Layout.Vertical else Layout.Horizontal)++[("gap",Typography.px(Typography.scaled(Layout.root_font_size_milli env)12));("min-inline-size","0")]) [] empty content in
 let paired:=combine(S.node_children value)children in
 let opened:=card_part describe false paired in
 let movement_nodes:=map snd(filter(fun pair=>match S.node_meaning(fst pair)with S.MovableCard _ _=>true|_=>false end)paired)in
 DOM.Element key "article" (attrs++[("data-card-id",text_number(Model.card_identity face));("data-card-title",Model.card_title face);
 ("draggable",flag movable);("data-drop-target",key)]) styles [] (card_drag generation movement)
 (glyph "grip"++[row "metadata" true
 ([text "reference"(Model.card_reference face);text "priority"(Selvedge.Features.Domain.priority_label(Model.card_priority face))]++
 (if Model.card_pinned face then[text "pinned" "置顶"]else[])++optional "status"(Model.card_status face));
 row "actions" false [DOM.Element(key++"/open-group")%string "div" [][("flex","1");("min-inline-size","0")][]empty
 (match opened with []=>[DOM.Text(Model.card_title face)]|_=>opened end);
 row "more-group" false(card_part describe true paired)]]++optional "description"(Model.card_description face)++
 [row "context" true(optional "project"(Model.card_project face)++map(fun label=>DOM.Element "" "span" [] (NativeAppearance.information_properties env false Information.Description) [] empty [DOM.Text label])(Model.card_labels face));
 DOM.Element(key++"/movement-group")%string "div" [][("display","flex");("flex-direction","column")][]empty movement_nodes;
 DOM.Element(key++"/footer")%string "footer"[("data-card-footer","")]
 (Layout.row_properties Layout.Horizontal++[("gap","12px")])[]empty
 (optional "owner"(Model.card_owner face)++optional "updated"(Model.card_updated face))])
 end.
Fixpoint compile_node {A} (describe:A->C.purpose) env generation inherited_area activity (source:S.meaning A) view component (value:S.node A) : DOM.node :=
 compile_element describe env generation inherited_area activity source view component value
  (map (compile_node describe env generation
    (area_for inherited_area (S.node_role value) (S.node_meaning value))
    (match S.node_meaning value with S.ActivityGroup _ _ _ _|S.ActivityRow _=>true|_=>activity end)
    (source_context source (S.node_meaning value))
    (match S.node_meaning value with S.PageContext current=>current|_=>view end)
    (component_context component (S.node_meaning value))) (S.node_children value)).
Fixpoint target_updates {A} view (value:S.node A) : list DOM.target_update :=
 let current_view:=match S.node_meaning value with S.PageContext current=>current|_=>view end in
 let children:=flat_map (target_updates current_view) (S.node_children value) in
 match S.node_meaning value with
 |S.SkillSuggestions field expanded active=>DOM.UpdateTarget field
 [("aria-autocomplete","list");("aria-haspopup","listbox");
 ("aria-controls",if expanded then S.node_key value else "");
 ("aria-activedescendant",if expanded then match active with Some key=>key|None=>""end else "")] []::children
 |S.InteractiveRegion policy=>
 DOM.UpdateTarget (Observation.physical_target current_view (DocumentPublication.target_key (DocumentPublication.fence_identity policy) DocumentPublication.Source))
 [] (DocumentPublication.source_properties policy)::
 DOM.UpdateTarget (Observation.physical_target current_view (DocumentPublication.target_key (DocumentPublication.fence_identity policy) DocumentPublication.Frame))
 (if DocumentPublication.preview_active policy then [("data-interactive-active","true")] else [])
 (DocumentPublication.frame_properties policy)::children
 |_=>children end.
Definition surface_scopes {A}(values:list(S.node A)) : list Focus.scope :=
 flat_map(fun node=>match S.node_meaning node with
 |S.LayerRegion behavior|S.NavigationRegion _ behavior|S.ActivityGroup _ _ _ behavior=>
 if Model.modal_layer behavior then [Focus.Temporary (S.node_key node)
 (Model.layer_initial_attention behavior) (Model.layer_return_attention behavior)
 (Model.layer_fallback_attention behavior) (Some(Model.layer_occurrence behavior))]else[]
 |_=>[]end)values.
Definition is_global {A}(value:S.node A) := match S.node_role value with Roles.GlobalNavigation _=>true|_=>false end.
Definition is_navigation {A}(describe:A->C.purpose)(value:S.node A) :=
 match S.node_role value with Roles.Navigation=>true|_=>
  match S.node_meaning value with S.Activate control=>
   match describe(Model.control_input control)with C.ToggleNavigation false=>true|_=>false end
  |_=>false end end.
Definition is_header {A}(value:S.node A) := match S.node_role value with Roles.WorkTabs|Roles.CompactHeader=>true|_=>false end.
Definition beside_layer {A}(value:S.node A) := match S.node_meaning value with
 |S.LayerRegion behavior|S.NavigationRegion _ behavior|S.ActivityGroup _ _ _ behavior=>negb(Model.modal_layer behavior)|_=>false end.
Definition compile {A} (describe:A->C.purpose) env generation (surface:S.surface A) : json :=
 let all:=S.base surface ++ S.overlays surface in
 let compile:=compile_node describe env generation OutsideArea false S.Region None None in
 let base:=S.base surface in
 let global:=filter is_global base in let headers:=filter is_header base in
 let navigation:=filter (is_navigation describe) base in
 let main:=filter(fun value=>negb(is_global value || is_header value || is_navigation describe value))base in
 let beside:=filter beside_layer (S.overlays surface) in
 let layers:=filter(fun value=>negb(beside_layer value))(S.overlays surface) in
 let p:=Layout.parameters env in
 let theme:=NativeAppearance.theme_name (S.surface_appearance surface) (Layout.system_dark env) in
 DOM.encode (DOM.Document
 (DOM.Element "selvedge" "div" [("data-selvedge-root","true")]
 (NativeAppearance.root_properties env ++ [("display","flex");("flex-direction","row");("block-size","100%");("min-block-size","0")]) [] empty
 (map compile global ++
 [DOM.Element (S.workspace_key surface) "div" [("data-measure-region","workspace")]
 [("display","flex");("flex-direction","column");("flex","1");("min-inline-size","0");("min-block-size","0")] [] empty
 (map compile headers ++ [DOM.Element "workspace-body" "div" []
 [("display","flex");("flex-direction","row");("flex","1");("min-inline-size","0");("min-block-size","0")] [] empty
 (map compile navigation ++ [DOM.Element "main-layout" "div" [("data-measure-region","main")]
 [("display","flex");("flex-direction","row");("flex","1");("min-inline-size","0");("min-block-size","0")]
 [] empty (map compile main ++ map compile beside)])]);
 DOM.Element (String.append(S.workspace_key surface)"/overlays") "div" [("data-layer-stack","true")]
 [] [] empty (map compile layers)]))
 "Selvedge" generation false
 (DOM.UpdateTarget "@document/root" [("data-theme",theme)] [("color-scheme",theme)]::flat_map (target_updates None) all) (surface_scopes(S.modal_nodes surface))).
Definition bootstrap env generation := DOM.encode (DOM.Document
 (DOM.Element "selvedge-measurement" "div" []
 (NativeAppearance.root_properties env) [] empty
 [DOM.Element "@browser/utility" "section"[("role","status");("aria-label","Preparing interface…");("title","Preparing interface…")]
 [] [] empty [DOM.Text "Preparing interface…"];
 DOM.Element "workspace-probe" "div" [("data-measure-region","workspace");("inert","");("aria-hidden","true")]
 [("inline-size","100%");("display","flex") ] [] empty
 [DOM.Element "main-probe" "main" [("data-measure-region","main")]
 [("flex","1");("min-inline-size","0")] [] empty []]])
 "Selvedge" generation true [] []).
Definition recovery root generation reason := DOM.encode(DOM.Document
 (DOM.Element "@browser/utility" "section"[("role","status");("aria-label",reason);("title",reason)]
 (Typography.properties root Typography.Body Typography.Regular++
 [("display","flex");("flex-direction","column");("gap","12px");("padding","16px");
 ("color","var(--color-token-text-primary)");("background","var(--color-token-bg-primary)")]) [] empty
 [DOM.Element "@browser/utility/message" "p"[][][]empty[DOM.Text reason];
 DOM.Element "@browser/utility/retry" "button"
 [("type","button");("aria-label",("Retry rendering: "++reason)%string);("title",("Retry rendering: "++reason)%string)]
 [("display","inline-flex");("align-items","center");("justify-content","center");
  ("min-inline-size","32px");("min-block-size","32px");("align-self","flex-start")]
 [DOM.Binding "click" "retry_render" DOM.RetryRendering] empty(glyph "refresh")])
 "Selvedge" generation true [] []).
