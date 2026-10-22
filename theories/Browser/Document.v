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
Definition control_attributes {A} (action:Model.control A) :=
 [("aria-label",Model.control_label action)] ++ disabled (Model.available (Model.control_availability action)).
Definition control_children {A} (action:Model.control A) (children:list DOM.node) :=
 match children with []=>[DOM.Text (Model.control_label action)]|_=>children end.
Definition common key semantic label role := [("id",key);("data-logical-key",semantic);("data-semantic-key",semantic);
 ("data-surface-role",Roles.role_name role)] ++
 (match role with Roles.Main|Roles.Heading|Roles.Dialog|Roles.Menu=>[("tabindex","-1")]|_=>[]end) ++
 (if String.eqb label "" then [] else [("aria-label",label)]).
Definition role_tag role := match role with
 | Roles.GlobalNavigation _ | Roles.Navigation => "nav"
 | Roles.CompactHeader | Roles.NavigationHeader => "header"
 | Roles.Main => "main" | Roles.Heading => "h2"
 | Roles.Section | Roles.Activity | Roles.Approval => "section"
 | Roles.Dialog => "dialog" | _ => "div" end.
Definition text_tag role := match role with
 | Information.IntroductionTitle => "h1" | Information.SurfaceTitle=>"h2"
 | Information.GroupTitle=>"h3" | Information.Status=>"output" | _=>"span" end.
Definition native_string value := match value with
 | JString value=>value | JNull=>"" | value=>render_json value end.
Definition native_checked value := match value with JBool value=>value|_=>false end.
Definition physical_markdown wrapper_key markdown_key text complete metadata : DOM.node :=
 DOM.Element wrapper_key "div" [("class","physical-markdown")] [] [] (JObject [])
  [DOM.Markdown markdown_key text complete metadata].
Definition selection_json (value:option(N*N*bool)) := match value with
 | None=>JNull | Some (start,stop,backward)=>JObject [("start",JNumber (text_number start));
 ("end",JNumber (text_number stop));("direction",JString (if backward then "backward" else "forward"))] end.
Definition choices selected values := map (fun value => DOM.Element
 ("option/" ++ Fields.choice_value_of value)%string "option"
 ([("value",Fields.choice_value_of value)] ++
 if String.eqb selected (Fields.choice_value_of value) then [("selected","selected")] else [])
 [] [] empty [DOM.Text (Fields.choice_label value)]) values.
Definition descriptions {A}(children:list(S.node A)) := String.concat " "
 (map S.node_key (filter(fun child=>match S.node_meaning child with
 |S.InformationText Information.FieldValue|S.InformationText Information.Description=>true|_=>false end)children)).
Definition editor {A} env key label generation field (value:Model.edit_control A) attributes styles :=
 let native:=Parameters.native_value field (Model.editing_observation value) in
 let text:=match Model.editing_buffer value with Some raw=>raw|None=>native_string native end in
 let enabled:=Model.available (Model.editing_availability value) in
 let events:=match Model.editing_input value with None=>[]|Some _=>
 [event key generation "input" "value" Gesture.Change] end in
 let metadata:=JObject [("field_session",JObject [("owner",JString key);("source",JString text)]);
 ("selection",selection_json (Model.editing_selection value))] in
 let attrs:=attributes ++ [("aria-label",label)] ++ disabled enabled in
 if ControlPurpose.toggle_widget field(Model.editing_observation value) then
 let checked:=Parameters.native_checked field(Model.editing_observation value)in
 DOM.Element key "input"
 (attrs ++ [("type","checkbox")] ++
 match checked with Some true=>[("checked","checked")]|Some false=>[]
 (* DEFENSE: an unavailable context has no observed boolean. The native
    checkbox must not present it as an editable false value. *)
 |None=>[("disabled","disabled");("indeterminate","true")]end)
 styles (match Model.editing_input value with None=>[]|Some _=>[event key generation "change" "checked" Gesture.Change] end) metadata []
 else match Model.editing_entry value with
 | Fields.Choice=>DOM.Element key "select" (attrs ++ [("value",text)]) styles
 (match Model.editing_input value with None=>[]|Some _=>[event key generation "change" "value" Gesture.Change] end)
 metadata (choices text (Model.editing_choices value))
 | Fields.Multiline | Fields.StructuredText=>DOM.Element key "textarea"
 (attrs ++ [("value",text);("data-field-entry","multiline")])
 (styles ++ [("field-sizing","content")] ++
 (match field with Fields.MessageText=>[("min-block-size",Typography.px (Nat.max (Layout.input_minimum_height(Layout.parameters env))
   (Layout.input_line_height (Layout.parameters env) * Layout.writing_lines)))]|_=>[]end) ++
 [("max-block-size",Typography.px (Layout.input_line_height (Layout.parameters env) *
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
 let text:=match IP.editing_raw value with Some raw=>raw|None=>native_string (IP.editing_value value) end in
 let enabled:=IP.editing_enabled value in
 let attrs:=attrs ++ [("aria-label",label)] ++ disabled enabled ++
 (match IP.editing_validation value with Some _=>[("aria-invalid","true");("aria-describedby",String.append key "/validation")]|None=>[] end) in
 let events name kind:=match IP.editing_receive value with None=>[]|Some _=>[event key generation name kind Gesture.Change] end in
 let schema:=Local.shape_json(IP.editing_shape value) in
 let constraints:=fold_right (fun name rest=>match field name schema with
 |Some JNull|None=>rest|Some value=>(name,native_string value)::rest end) [] ["min";"max";"step"] in
 let metadata:=JObject [("field_session",JObject [("owner",JString key);("source",JString text)])] in
 if String.eqb component_tag "checkbox" then DOM.Element key "input"
 (attrs ++ [("type","checkbox")] ++ if native_checked (IP.editing_value value) then [("checked","checked")] else []) styles (events "change" "checked") metadata []
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
 ("flex-direction",if beside then "row"else"column")]) [] empty
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
Definition artwork name := match NativeAppearance.find_symbol name with None=>[]|Some symbol=>
 [DOM.Element "" "svg" [("viewBox","0 0 20 20");("width","16");("height","16");("aria-hidden","true")]
 [("flex","none")] [] empty [DOM.Element "" "path"
 ([("d",NativeAppearance.symbol_path symbol);("stroke-linecap","round");("stroke-linejoin","round")] ++
 match NativeAppearance.symbol_paint symbol with NativeAppearance.Filled=>[("fill","currentColor")]
 |NativeAppearance.Outline=>[("fill","none");("stroke","currentColor");("stroke-width","1.5")]end) [] [] empty []]] end.
Definition glyph name := if String.eqb name "spinner" then
 [DOM.Element "" "span" [("data-interactive-motion-glyph","");("aria-hidden","true")]
 [("inline-size","16px");("block-size","16px");("flex","none")] [] empty (artwork name)] else artwork name.
Module C := ControlPurpose.
Inductive area := PageArea|ComposerArea|ToolbarArea|DialogArea|MenuArea|NavigationArea
 |TouchNavigationArea|BoardLaneArea|CardArea|CollectionArea|CodeArea.
Definition area_for {A} inherited role (meaning:S.meaning A) := match meaning with
 |S.BoardLane _ _=>BoardLaneArea|S.WorkspaceCollection _ _=>CollectionArea|S.CodeFacts _=>CodeArea
 |_=>match role with Roles.Composer=>ComposerArea|Roles.Toolbar=>ToolbarArea
 |Roles.Dialog|Roles.DialogActions=>DialogArea|Roles.Menu=>MenuArea
 |Roles.GlobalNavigation _|Roles.Navigation=>NavigationArea
 |Roles.CompactHeader|Roles.CompactNavigationMenu|Roles.CompactNavigationEntry _=>TouchNavigationArea
 |Roles.Card=>CardArea|_=>inherited end end.
Definition purpose_icon purpose := match purpose with
 |C.MessageSubmission=>Some "arrow-up"|C.CreateItem|C.ProjectTaskCreation=>Some "plus"
 |C.WorkCreation=>Some "plus"|C.EditItem=>Some "pencil"|C.NavigateTo icon|C.OpenPanel icon _ _=>Some icon
 |C.MoreActions _=>Some "more-dots"|C.WorkspacePicker _=>Some "folder"
 |C.Dismiss|C.AbortOperation=>Some "close-cross"
 |C.StopExecution|C.InterruptExecution=>Some "stop-square"|C.PauseExecution=>Some "pause-bars"
 |C.ResumeExecution=>Some "play-triangle"|C.ApprovalDecision true=>Some "check"
 |C.ApprovalDecision false=>Some "close-cross"|C.DeleteItem|C.RemoveValue=>Some "trash"
 |C.ArchiveItem true=>Some "archive-box"|C.ArchiveItem false=>Some "restore"
 |C.PinItem _=>Some "pin"|C.Regenerate|C.RetryTransfer=>Some "refresh"
 |C.CopyCode state=>Some(match state with CodeBlock.Idle=>"copy-sheets"|CodeBlock.Pending _=>"spinner"
 |CodeBlock.Feedback _ true=>"check"|CodeBlock.Feedback _ false=>"warning"end)
 |C.WrapCode _=>Some "wrap-lines"|C.Latest=>Some "arrow-down"
 |C.ToggleNavigation expanded=>Some(if expanded then "sidebar-close" else "sidebar")
 |C.ResetDefaults=>Some "undo"|C.PreviewFile=>Some "preview"|C.DownloadFile=>Some "download"
 |C.Connect true=>Some "spinner"|_=>None end.
Definition icon_only purpose area := match purpose,area with
 |C.WorkCreation,ToolbarArea|C.MessageSubmission,ComposerArea|C.Dismiss,_|C.MoreActions _,_|C.Latest,_|C.ToggleNavigation _,_
 |C.ProjectTaskCreation,NavigationArea|C.CreateItem,BoardLaneArea
 |C.OpenPanel "inspector" _ _,ToolbarArea|C.OpenPanel "settings" _ _,_|C.OpenPanel "filter-funnel" _ _,_
 |C.OpenPanel "archive-box" _ _,ToolbarArea|C.CopyCode _,CodeArea|C.WrapCode _,CodeArea
 |C.RemoveValue,CollectionArea|C.StopExecution,ToolbarArea|C.PauseExecution,ToolbarArea
 |C.ResumeExecution,ToolbarArea|C.InterruptExecution,ToolbarArea=>true|_,_=>false end.
Definition purpose_attributes purpose := match purpose with
 |C.MoreActions expanded|C.OpenPanel _ _ expanded|C.ChooseValue expanded
 |C.WorkspacePicker expanded|C.ShowActivity expanded|C.ToggleNavigation expanded=>[("aria-expanded",flag expanded)]
 |C.Connect true|C.CopyCode(CodeBlock.Pending _)=>[("data-interactive-motion","spin")]
 |C.SelectedOption checked=>[("aria-checked",flag checked)]
 |C.PinItem pinned|C.AutomaticScheduling pinned|C.WrapCode pinned=>[("aria-pressed",flag pinned)]
 |_=>[]end.
Definition control_styles purpose role := match purpose,role with
 |C.OpenPanel icon _ _,Roles.GlobalNavigationEntry _ _=>
 if String.eqb icon "settings" then [("margin-block-start","auto")]else[]
 |_,_=>[]end.
Definition face_children purpose area role label children :=
 let text:=match children with []=>[DOM.Text label]|_=>children end in
 let icon:=match purpose_icon purpose with Some name=>glyph name|None=>[]end in
 match role with
 |Roles.WorkTab _=>text
 |Roles.WorkOverviewButton count=>artwork "columns"++[DOM.Text(text_number count)]
 |Roles.CompactWorkScope title count=>text++[DOM.Text(text_number count)]
 |Roles.GlobalNavigationEntry _ compact=>if compact then icon else icon++text
 |Roles.CompactNavigationEntry _=>icon++text
 |_=>match purpose with
 |C.ChooseValue _|C.WorkspacePicker _=>icon++text++artwork "chevron-down"
 |C.ShowActivity expanded=>text++artwork(if expanded then "chevron-down"else "chevron-right")
 |C.SelectedOption checked=>text++if checked then artwork "check"else[]
 |C.NavigateTo _=>icon++match role with Roles.GlobalNavigationEntry _ true=>[]|_=>text end
 |_=>if icon_only purpose area then icon else icon++text end end.
Fixpoint commit_key {A} (value:S.node A) : option string :=
 match S.node_meaning value with S.ActionCommit _ _ _=>Some (S.node_key value)
 | _=>(fix search (nodes:list(S.node A)):=match nodes with []=>None|head::tail=>
 match commit_key head with Some key=>Some key|None=>search tail end end) (S.node_children value) end.
Definition component_context {A} (current:option IP.component) (meaning:S.meaning A) :=
 match meaning with S.InteractiveNode value=>Some value|_=>current end.
Definition source_context {A} (current:S.meaning A) (meaning:S.meaning A) :=
 match meaning with S.Region|S.InformationText _=>current|_=>meaning end.
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
Fixpoint compile_node {A} (describe:A->C.purpose) env generation inherited_area activity (source:S.meaning A) view component (value:S.node A) : DOM.node :=
 let key:=S.node_key value in let label:=S.node_label value in
 let meaning:=S.node_meaning value in let role:=S.node_role value in
 let current_area:=area_for inherited_area role meaning in
 let children:=map (compile_node describe env generation current_area
 (match meaning with S.ActivityGroup _ _ _ _=>true|_=>activity end)
 (source_context source meaning) (match meaning with S.PageContext current=>current|_=>view end) (component_context component meaning)) (S.node_children value) in
 let children:=match ControlContent.container_content describe glyph env key label role meaning (S.node_children value) children with Some content=>content|None=>children end in
 let supporting:=match role with Roles.Toolbar=>ControlContent.support_row(S.node_children value)|_=>false end in
 let attrs:=common key (S.semantic_key value) label role ++
 NativeAppearance.overflow_attributes (NativeAppearance.style_overflow (NativeAppearance.role_style role)) label ++
 (match role with Roles.Timeline=>[("tabindex","0")]|Roles.UserMessage|Roles.AssistantMessage=>[("data-reading-anchor","true")]|Roles.Composer=>[("data-composer-dock","true")]|_=>[] end) ++
 (if supporting then ControlContent.support_row_attributes key else []) in
 let styles:=NativeAppearance.role_properties env role ++
 (match meaning with S.LayerRegion behavior|S.ActivityGroup _ _ _ behavior=>match Model.layer_presentation behavior with
 |Model.AnchoredMenu=>[("position","fixed");("inset","auto");("top","anchor(bottom)");("left","anchor(left)");("margin","0") ]
 |Model.TrailingDetails=>if Model.layer_beside behavior then [("inline-size",Typography.px(Layout.details_width(Layout.parameters env)));("flex","none")] else []
 |Model.ModalDialog=>[]end|_=>[]end) ++ SemanticAppearance.meaning_properties env activity meaning ++ SemanticAppearance.source_properties env source meaning ++
 (match role with
 |Roles.WorkTabs=>[("display","flex");("flex-direction","row");("align-items","center");("min-block-size",Typography.px(Layout.toolbar_height(Layout.parameters env)));("flex","none");("overflow","hidden")]
 |Roles.WorkTabGroup=>[("display","flex");("flex-direction","row");("flex","1");("min-inline-size","0");("overflow-x","auto")]
 |Roles.WorkTab selected=>[("flex","1 0 auto");("min-inline-size",Typography.px(Typography.scaled(Layout.root_font_size_milli env)96));("block-size",Typography.px(Typography.scaled(Layout.root_font_size_milli env)40));
 ("border-block-end",if selected then "2px solid currentColor" else "1px solid transparent")]
 |Roles.CompactWorkScope _ _=>[("flex","1");("min-inline-size","0");("justify-content","space-between")]
 |Roles.GlobalNavigationEntry _ compact=>[("display","flex");("flex-direction",if compact then "row" else "column");("align-items","center");("justify-content","center");("inline-size","100%")]
 |Roles.GlobalNavigation compact=>[("inline-size",Typography.px(Typography.scaled(Layout.root_font_size_milli env)(if compact then 48 else 84)));("flex","none")]|Roles.Navigation=>[("inline-size",Typography.px(Layout.navigation_width(Layout.parameters env)));("flex","none")]|Roles.Main=>[("flex","1");("min-inline-size","0")]|_=>[] end) ++
 (match meaning with S.SummaryList=>[("list-style","none");("padding","0");("margin","0")]|S.InteractiveNode c=>InteractiveAppearance.component_properties env c
 |S.InteractivePlacement p=>InteractiveAppearance.placement_properties env p|_=>[] end) ++
 ControlContent.node_properties env role meaning ++
 (if supporting then ControlContent.support_row_properties else []) in
 let element tag extra events metadata content:=DOM.Element key tag (attrs++extra) styles events metadata content in
 let button (submit:bool) action extra:=
 let purpose:=describe(Model.control_input action)in
 DOM.Element key "button" (attrs++[("type",if submit then "submit" else "button")] ++control_attributes action++purpose_attributes purpose++extra)
 (styles++control_styles purpose role++
 (match source with S.TaskRow _ _ _ _ _=>[("display","flex");("flex-direction","row");("align-items","center");("inline-size","100%");("min-inline-size","0");("padding","0");("gap",Typography.px(ControlContent.navigation_following env))]|_=>[]end)++match source,purpose with S.CardContent _,C.OpenCardDetails _=>
 [("background","transparent");("border","0");("padding","0");("text-align","left");("font-weight","600");("white-space","normal")]|_,_=>[]end)
 [event key generation "click" "activate" Gesture.Press] empty
 (match ControlContent.face_content env key glyph meaning (S.node_children value) with Some content=>content|None=>
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
 |_,_=>face_children purpose current_area role(Model.control_label action)children end end)in
 match meaning with
 |S.InformationText info=>element (text_tag info) ([("tabindex","-1")] ++
   match info with Information.Status=>[("role","status")]|_=>[]end) [] empty [DOM.Text label]
 |S.ReadOnly text|S.Fact text=>element "span" [] [] empty [DOM.Text text]
 |S.ActionFeedback _ _ message=>element "p" [("role","status")] [] empty [DOM.Text message]
 |S.DirectoryBrowserLocation path=>element "p" [] [] empty [DOM.Text path]
 |S.PublishedText document=>element "div" [] [] empty
 (physical_markdown (String.append key "/@physical-markdown") (String.append key "/markdown")
 (DocumentPublication.published_text document)
 (match DocumentPublication.published_ending document with
 Selvedge.Interaction.Interactive.Types.Open=>false|_=>true end)
 (match DocumentPublication.encode_document document with JObject fields=>JObject(("view",Observation.encode_view view)::fields)|metadata=>metadata end)::children)
 |S.RichText provenance text=>element "div" [] [] empty
 (physical_markdown (String.append key "/@physical-markdown") (String.append key "/markdown") text
 (match provenance with CodeSource.Generated _ _ _ complete=>complete|_=>true end)
 (JObject [("source",CodeSource.encode_source provenance);("view",Observation.encode_view view)])::children)
 |S.EmbeddedMarkdown text=>physical_markdown (String.append key "/@physical-markdown") key text true empty
 |S.CodeFacts facts=>
 let who:=CodeBlock.presented_identity facts in
 let target part:=Observation.physical_target view (DocumentPublication.target_key who part) in
 element "div" [("data-code-owner",CodeSource.key who)] []
 (JObject[("code",JObject[("identity",CodeSource.encode_identity who);("view",Observation.encode_view view);("text",JString(CodeBlock.presented_literal facts))])])
 [DOM.Element (target DocumentPublication.Frame) "div" [("data-code-frame","true")] [] [] empty
 [DOM.Element (target DocumentPublication.Toolbar) "div" [] [] [] empty [];
 DOM.Element (target DocumentPublication.Source) "pre" [] [] [] empty
 [DOM.Element (target DocumentPublication.Body) "code" [] [] [] empty [DOM.Text(CodeBlock.presented_literal facts)]]]]
 |S.InteractiveRegion policy=>DOM.Mount (Observation.physical_target view (DocumentPublication.target_key (DocumentPublication.fence_identity policy) DocumentPublication.Preview)) children
 |S.Activate action=>button false action []
 |S.SettingEntry _ _ action|S.SupportingControl _ _ _ action=>button false action
 (let described:=descriptions(S.node_children value)in if String.eqb described ""then[]else[("aria-describedby",described)])
 |S.ActionCommit _ _ action=>button true action []
 |S.WorkChoice _ selected action=>button false action [("aria-pressed",flag selected)]
 |S.Choice kind selected description action=>button false action
 [("role",match kind with S.SingleChoice=>"radio"|S.MultipleChoice=>"checkbox" end);("aria-checked",flag selected)]
 |S.PanelToggle expanded action=>button false action [("aria-expanded",flag expanded)]
 |S.Edit owner subject value=>
 let native:=match editor env key label generation (UX.subject_declaration subject) value attrs styles with
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
 |S.HistorySearchQuery query _=>element "input" [("type","search");("value",query)] [event key generation "input" "value" Gesture.Change] empty []
 |S.HistorySearchScope project selected values _=>element "select" [("value",match selected with None=>""|Some n=>text_number n end)]
 [event key generation "change" "value" Gesture.Change] empty (choices (match selected with None=>""|Some n=>text_number n end) values)
 |S.BoardSearch selection _=>element "input" [("type","search");("value",BoardFilter.filter_query selection)] [event key generation "input" "value" Gesture.Search] empty []
 |S.SearchChoices query _=>element "input" [("type","search");("value",query)] [event key generation "input" "value" Gesture.Search] empty []
 |S.ReceiveFile _ enabled _=>element "input" ([("type","file");("multiple","multiple")]++disabled enabled)
 [event key generation "change" "files" Gesture.Attach] empty []
 |S.EnterDirectory _ text _ confirm=>element "input" [("type","text");("value",text)]
 ([event key generation "input" "value" Gesture.Directory] ++match confirm with Some _=>[event key generation "keydown" "confirm" Gesture.ConfirmDirectory]|None=>[] end) empty []
 |S.BoardProfile automatic selected values enabled _=>element "select"
 ([("value",selected);("data-automatic",flag automatic)]++disabled enabled)
 [event key generation "change" "value" Gesture.SelectBoardProfile] empty (choices selected values)
 |S.ActionUnit _ _=>element "form" [("novalidate","novalidate")]
 (match commit_key value with Some key=>[event key generation "submit" "submit" Gesture.Press]|None=>[] end) empty children
 |S.LayerRegion behavior|S.ActivityGroup _ _ _ behavior=>
 element (if Model.modal_layer behavior then "dialog" else "aside")
 ([("role",if Model.modal_layer behavior then "dialog" else "complementary");("aria-modal",flag (Model.modal_layer behavior))] ++
 match Model.layer_presentation behavior with Model.AnchoredMenu=>[("data-anchor",Model.layer_anchor behavior)]|_=>[]end)
 [event key generation "cancel" "dismiss" Gesture.Dismiss] (layer_metadata key behavior) children
 |S.Graphic plot=>DOM.Element key "svg" (attrs++[("viewBox",("0 0 "++text_number (Npos (Graphics.width plot))++" "++text_number (Npos (Graphics.height plot)))%string);("role","img");
 ("width",text_number(Npos(Graphics.width plot)));("height",text_number(Npos(Graphics.height plot)))])
 (styles++[("max-inline-size","none");("flex","none")]) [] empty (map (graphic_primitive generation) (Graphics.primitives plot))
 |S.Image src alternative=>element "img" [("src",src);("alt",alternative)] [] empty []
 |S.Table caption headings rows=>element "table" [] [] empty
 ([DOM.Element (key++"/caption")%string "caption" [] [] [] empty [DOM.Text caption];
 DOM.Element (key++"/head")%string "thead" [] [] [] empty [DOM.Element "" "tr" [] [] [] empty
 (map(fun text=>DOM.Element "" "th" [("scope","col")] [] [] empty [DOM.Text text])headings)];
 DOM.Element (key++"/body")%string "tbody" [] [] [] empty
 (map(fun row=>DOM.Element "" "tr" [] [] [] empty (map(fun text=>DOM.Element "" "td" [] [] [] empty [DOM.Text text])row))rows)])
 |S.InteractivePlacement placement=>element "div" [] [] empty children
 |S.ReadingTimeline task_view reader_generation=>element "section"
 [("data-reading-root","true");("data-task-id",text_number(Identity.task_view_task task_view));("data-reader-generation",text_number reader_generation)] [] empty children
 |S.PageBody page=>DOM.Element key (role_tag role) attrs (styles++Layout.page_properties env page) [] empty children
 |S.PageRegion region position=>element (role_tag role) [("data-page-region",Composition.region_name region)] [] empty children
 |S.MovableCard face destinations=>
 let offered:=available_placements destinations in
 DOM.Element key "select" (attrs++[("value","")]++disabled(match offered with []=>false|_=>true end))
 (styles++NativeAppearance.role_properties env Roles.Field)
 [event key generation "change" "value" Gesture.Place] empty
 (DOM.Element "" "option" [("value","");("selected","selected")] [] [] empty [DOM.Text "Move to…"]::
 map(fun destination=>DOM.Element "" "option" [("value",S.placement_target destination)] [] [] empty
 [DOM.Text(Model.control_label(S.placement_control destination))])offered)
 |S.InteractiveNode c=>
 let properties:=IP.component_properties c in
 let motion:=Expand.property_text "motion" properties in
 let common:=[("data-interactive-component",Vocabulary.component_tag(Expand.description properties));
 ("data-interactive-key",key);("data-interactive-transition",Expand.property_text "transition" properties)] in
 let native:=element (role_tag role)
 (common ++ if String.eqb(Vocabulary.component_tag(Expand.description properties))"row-layout"
 then [("data-native-responsive-row",key)] else []) [] empty children in
 if String.eqb motion "spin" then
 DOM.Element (String.append key "/motion") "div" [("data-interactive-motion",motion)]
 [("display","flex");("flex-direction","row");("gap","6px");("align-items","center");("min-inline-size","0")]
 [] empty (glyph "spinner"++[native])
 else match native with DOM.Element key tag attrs styles events metadata children=>
 DOM.Element key tag (("data-interactive-motion",motion)::attrs) styles events metadata children|other=>other end
 |S.InteractiveTable table=>element "table" [] [] empty
 [DOM.Element (key++"/caption")%string "caption" [] [] [] empty [DOM.Text(IP.table_caption table)];
 DOM.Element (key++"/head")%string "thead" [] [] [] empty [DOM.Element "" "tr" [] [] [] empty
 (map(fun column=>let identity:=IP.column_key key column in DOM.Element identity "th"
 [("scope","col");("aria-sort",match IP.column_order column with None=>"none"|Some true=>"descending"|Some false=>"ascending" end)] [] [] empty
 (match IP.column_sort column with None=>[DOM.Text(IP.column_heading column)]|Some _=>
 [DOM.Element (identity++"/control")%string "button" ([("type","button")]++disabled(IP.column_enabled column))
 (NativeAppearance.role_properties env Roles.Button) [event identity generation "click" "activate" Gesture.Press] empty [DOM.Text(IP.column_heading column)]]end)) (IP.table_columns table))];
 DOM.Element (key++"/body")%string "tbody" [] [] [] empty (map(fun row=>DOM.Element "" "tr" [] [] [] empty
 (map(fun text=>DOM.Element "" "td" [] [] [] empty [DOM.Text text])row))(IP.table_rows table))]
 |S.ActivityContent expanded audit=>element "section" [("data-expanded",flag expanded)] [] empty
 (children ++ if expanded then map(fun face=>
 let face_key:=String.append key (String.append "/audit/" (text_number(Audit.face_occurrence face))) in
 DOM.Element face_key "section" [] [] [] empty
 [DOM.Element "" "h4" [] [] [] empty [DOM.Text(Audit.face_title face)];
  physical_markdown (String.append face_key "/@physical-markdown") ""
   (Audit.detail(Audit.face_source face)) true (JObject [])])audit else [])
 |S.SummaryList=>element "ul" [("role","list")]
 [] empty (map(fun child=>DOM.Element "" "li" [] [] [] empty [child])children)
 |S.SkillSuggestions field active=>DOM.Element key "div"
 (attrs++[("role","listbox");("data-anchor",field)])
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
 ("aria-selected",flag selected);("data-retain-focus","true");("data-reveal-on-layout",flag selected)]++control_attributes action)
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
 |S.TaskChildren task=>element "div"[("role","group");("data-task-parent",text_number task)][]empty children
 |S.BoardGroup _|S.ActivityRow _|S.WorkspaceCollection _ _|S.WorkspaceMember _ _ _
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
Fixpoint target_updates {A} view (value:S.node A) : list DOM.target_update :=
 let current_view:=match S.node_meaning value with S.PageContext current=>current|_=>view end in
 let children:=flat_map (target_updates current_view) (S.node_children value) in
 match S.node_meaning value with
 |S.SkillSuggestions field active=>DOM.UpdateTarget field
 [("role","combobox");("aria-autocomplete","list");("aria-expanded","true");
 ("aria-controls",S.node_key value);("aria-activedescendant",match active with Some key=>key|None=>""end)] []::children
 |S.InteractiveRegion policy=>
 DOM.UpdateTarget (Observation.physical_target current_view (DocumentPublication.target_key (DocumentPublication.fence_identity policy) DocumentPublication.Source))
 [] (DocumentPublication.source_properties policy)::
 DOM.UpdateTarget (Observation.physical_target current_view (DocumentPublication.target_key (DocumentPublication.fence_identity policy) DocumentPublication.Frame))
 (if DocumentPublication.preview_active policy then [("data-interactive-active","true")] else [])
 (DocumentPublication.frame_properties policy)::children
 |_=>children end.
Definition surface_scopes {A}(values:list(S.node A)) : list Focus.scope :=
 flat_map(fun node=>match S.node_meaning node with
 |S.LayerRegion behavior|S.ActivityGroup _ _ _ behavior=>
 if Model.modal_layer behavior then [Focus.Temporary (S.node_key node)
 (Model.layer_initial_attention behavior) (Model.layer_return_attention behavior)
 (Model.layer_fallback_attention behavior) (Some(Model.layer_occurrence behavior))]else[]
 |_=>[]end)values.
Definition is_global {A}(value:S.node A) := match S.node_role value with Roles.GlobalNavigation _=>true|_=>false end.
Definition is_navigation {A}(value:S.node A) := match S.node_role value with Roles.Navigation=>true|_=>false end.
Definition is_header {A}(value:S.node A) := match S.node_role value with Roles.WorkTabs|Roles.CompactHeader=>true|_=>false end.
Definition beside_layer {A}(value:S.node A) := match S.node_meaning value with
 |S.LayerRegion behavior|S.ActivityGroup _ _ _ behavior=>negb(Model.modal_layer behavior)|_=>false end.
Definition compile {A} (describe:A->C.purpose) env generation (surface:S.surface A) : json :=
 let all:=S.base surface ++ S.overlays surface in
 let compile:=compile_node describe env generation PageArea false S.Region None None in
 let base:=S.base surface in
 let global:=filter is_global base in let headers:=filter is_header base in
 let navigation:=filter is_navigation base in
 let main:=filter(fun value=>negb(is_global value || is_header value || is_navigation value))base in
 let beside:=filter beside_layer (S.overlays surface) in
 let layers:=filter(fun value=>negb(beside_layer value))(S.overlays surface) in
 let p:=Layout.parameters env in
 let dark:=match S.surface_appearance surface with
 |Selvedge.Interaction.Appearance.SystemAppearance=>Layout.system_dark env
 |Selvedge.Interaction.Appearance.LightAppearance=>false
 |Selvedge.Interaction.Appearance.DarkAppearance=>true end in
 let theme:=if dark then "dark" else "light" in
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
 [DOM.Element "@browser/utility" "section"[("role","status");("aria-label","Preparing interface…")]
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
 [("min-inline-size","32px");("min-block-size","32px");("align-self","flex-start")]
 [DOM.Binding "click" "retry_render" DOM.RetryRendering] empty(glyph "refresh")])
 "Selvedge" generation true [] []).
