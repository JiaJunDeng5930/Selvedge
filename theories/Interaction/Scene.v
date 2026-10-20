From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema.
From Selvedge.Interaction Require Import Graphics.
Import ListNotations.
Open Scope string_scope.

(** Semantic roles are shared by presentation and the browser interpretation. *)
Inductive kind := Group|Header|Heading|Navigation|Main|Aside|Section|Dialog|ListView|Item
|Button|Field|Select|OptionView|Checkbox|Form|Link|Image|Progress|Table|Row|Cell|Code|Icon|Text|Markdown|Portal|Graphic.
Definition kind_name k:=match k with
|Group=>"group"|Header=>"header"|Heading=>"heading"|Navigation=>"nav"|Main=>"main"|Aside=>"aside"|Section=>"section"|Dialog=>"dialog"|ListView=>"list"|Item=>"item"
|Button=>"button"|Field=>"field"|Select=>"select"|OptionView=>"option"|Checkbox=>"checkbox"|Form=>"form"|Link=>"link"|Image=>"image"|Progress=>"progress"|Table=>"table"|Row=>"row"|Cell=>"cell"|Code=>"code"|Icon=>"icon"|Text=>"text"|Markdown=>"markdown"|Portal=>"portal"|Graphic=>"graphic"end.
Definition scene_kinds : list kind := [Group;Header;Heading;Navigation;Main;Aside;Section;Dialog;ListView;Item;Button;Field;Select;OptionView;Checkbox;Form;Link;Image;Progress;Table;Row;Cell;Code;Icon;Text;Markdown;Portal;Graphic].
Definition decode_kind name :=
  find (fun value => String.eqb (kind_name value) name) scene_kinds.
Theorem decode_kind_name value : decode_kind (kind_name value) = Some value.
Proof. destruct value; reflexivity. Qed.

Definition standard_kind := { role:kind | role<>Graphic }.
Definition Group_role :standard_kind:=exist (fun role:kind=>role<>Graphic) Group ltac:(discriminate).
Definition Header_role :standard_kind:=exist (fun role:kind=>role<>Graphic) Header ltac:(discriminate).
Definition Heading_role :standard_kind:=exist (fun role:kind=>role<>Graphic) Heading ltac:(discriminate).
Definition Navigation_role :standard_kind:=exist (fun role:kind=>role<>Graphic) Navigation ltac:(discriminate).
Definition Main_role :standard_kind:=exist (fun role:kind=>role<>Graphic) Main ltac:(discriminate).
Definition Aside_role :standard_kind:=exist (fun role:kind=>role<>Graphic) Aside ltac:(discriminate).
Definition Section_role :standard_kind:=exist (fun role:kind=>role<>Graphic) Section ltac:(discriminate).
Definition Dialog_role :standard_kind:=exist (fun role:kind=>role<>Graphic) Dialog ltac:(discriminate).
Definition ListView_role :standard_kind:=exist (fun role:kind=>role<>Graphic) ListView ltac:(discriminate).
Definition Item_role :standard_kind:=exist (fun role:kind=>role<>Graphic) Item ltac:(discriminate).
Definition Button_role :standard_kind:=exist (fun role:kind=>role<>Graphic) Button ltac:(discriminate).
Definition Field_role :standard_kind:=exist (fun role:kind=>role<>Graphic) Field ltac:(discriminate).
Definition Select_role :standard_kind:=exist (fun role:kind=>role<>Graphic) Select ltac:(discriminate).
Definition OptionView_role :standard_kind:=exist (fun role:kind=>role<>Graphic) OptionView ltac:(discriminate).
Definition Checkbox_role :standard_kind:=exist (fun role:kind=>role<>Graphic) Checkbox ltac:(discriminate).
Definition Form_role :standard_kind:=exist (fun role:kind=>role<>Graphic) Form ltac:(discriminate).
Definition Link_role :standard_kind:=exist (fun role:kind=>role<>Graphic) Link ltac:(discriminate).
Definition Image_role :standard_kind:=exist (fun role:kind=>role<>Graphic) Image ltac:(discriminate).
Definition Progress_role :standard_kind:=exist (fun role:kind=>role<>Graphic) Progress ltac:(discriminate).
Definition Table_role :standard_kind:=exist (fun role:kind=>role<>Graphic) Table ltac:(discriminate).
Definition Row_role :standard_kind:=exist (fun role:kind=>role<>Graphic) Row ltac:(discriminate).
Definition Cell_role :standard_kind:=exist (fun role:kind=>role<>Graphic) Cell ltac:(discriminate).
Definition Code_role :standard_kind:=exist (fun role:kind=>role<>Graphic) Code ltac:(discriminate).
Definition Icon_role :standard_kind:=exist (fun role:kind=>role<>Graphic) Icon ltac:(discriminate).
Definition Text_role :standard_kind:=exist (fun role:kind=>role<>Graphic) Text ltac:(discriminate).
Definition Markdown_role :standard_kind:=exist (fun role:kind=>role<>Graphic) Markdown ltac:(discriminate).
Definition Portal_role :standard_kind:=exist (fun role:kind=>role<>Graphic) Portal ltac:(discriminate).
Inductive container_kind := CGroup|CHeader|CNavigation|CMain|CAside|CSection|CDialog|CList|CItem|CTable|CRow|CCell|CPortal.
Definition container_role k:=match k with CGroup=>Group|CHeader=>Header|CNavigation=>Navigation|CMain=>Main|CAside=>Aside|CSection=>Section|CDialog=>Dialog|CList=>ListView|CItem=>Item|CTable=>Table|CRow=>Row|CCell=>Cell|CPortal=>Portal end.
Inductive content_kind := CHeading|CText|CMarkdown|CCode|CIcon|CImage|CLink|COption|CProgress.
Definition content_role k:=match k with CHeading=>Heading|CText=>Text|CMarkdown=>Markdown|CCode=>Code|CIcon=>Icon|CImage=>Image|CLink=>Link|COption=>OptionView|CProgress=>Progress end.
Inductive field_kind := InputField|SelectField|CheckboxField.
Definition field_role k:=match k with InputField=>Field|SelectField=>Select|CheckboxField=>Checkbox end.
Inductive injection := ValueInjection | FileInjection | InteractiveValueInjection.
Inductive binding (Action:Type) := Activate(action:Action)|Supply(inject:injection)(action:Action).
Arguments Activate {Action}.
Arguments Supply {Action}.
Inductive data_key := Label|Value|Attributes|Disabled|Checked|Multiline|Options|Help|Invalid|Role|ValueKind|Url|Complete|Origin|DocumentKey|Epoch|Revision|Ending|Appearance|Layout|Target.
Definition data_name key:=match key with Label=>"label"|Value=>"value"|Attributes=>"attrs"|Disabled=>"disabled"|Checked=>"checked"|Multiline=>"multiline"|Options=>"options"|Help=>"help"|Invalid=>"invalid"|Role=>"role"|ValueKind=>"value_kind"|Url=>"url"|Complete=>"complete"|Origin=>"origin"|DocumentKey=>"document_key"|Epoch=>"epoch"|Revision=>"revision"|Ending=>"ending"|Appearance=>"appearance"|Layout=>"layout"|Target=>"target"end.
Definition key_eq_dec : forall(a b:data_key),{a=b}+{a<>b}. Proof. decide equality. Defined.
Inductive property (Action:Type) := Data(key:data_key)(value:json)|Bind(value:binding Action)|Dismiss(action:Action)|Files(action:Action)|Specification(field:field_spec)|KeyActions(values:list(string*Action)).
Arguments Data {Action}.
Arguments Bind {Action}.
Arguments Dismiss {Action}.
Arguments Files {Action}.
Arguments Specification {Action}.
Arguments KeyActions {Action}.
Fixpoint data_property {A} key (props:list(property A)) : option json :=match props with []=>None|Data k value::rest=>if key_eq_dec key k then Some value else data_property key rest|_::rest=>data_property key rest end.
Fixpoint binding_property {A}(props:list(property A)):option(binding A):=match props with []=>None|Bind value::_=>Some value|_::rest=>binding_property rest end.
Fixpoint dismiss_property {A}(props:list(property A)):option A:=match props with []=>None|Dismiss action::_=>Some action|_::rest=>dismiss_property rest end.
Fixpoint files_property {A}(props:list(property A)):option A:=match props with []=>None|Files action::_=>Some action|_::rest=>files_property rest end.
Fixpoint field_property {A}(props:list(property A)):field_spec:=match props with []=>Schema.Field "value" KText|Specification spec::_=>spec|_::rest=>field_property rest end.
Fixpoint keys_property {A}(props:list(property A)):list(string*A):=match props with []=>[]|KeyActions values::_=>values|_::rest=>keys_property rest end.
Definition data_properties {A}(props:list(property A)):=flat_map(fun p=>match p with Data key value=>[(data_name key,value)]|_=>[]end)props.
Definition activate_property {A}(props:list(property A)):option A:=match binding_property props with Some(Activate a)=>Some a|_=>None end.
Definition supply_property {A}(props:list(property A)):option(injection*A):=match binding_property props with Some(Supply kind a)=>Some(kind,a)|_=>None end.
Inductive rendered_value (k:Schema.kind) := Canonical(value:denote k)|Raw(text:string).
Arguments Canonical {k}.
Arguments Raw {k}.
Definition input_value {A}(props:list(property A)):rendered_value(Schema.field_kind(field_property props)):=
  let spec:=field_property props in
  let value:=match data_property Value props with Some value=>value|None=>JString ""end in
  match decode_value(Schema.field_kind spec)value with
  |Some value=>Canonical value|None=>Raw(match value with JString text=>text|_=>""end)end.

(** A field can only request input injection; a button and form can only activate
    a complete action. The constructors cannot exchange those responsibilities. *)
Inductive scene (Action:Type) :=
| GraphicView(key:string)(properties:list(string*json))(drawing:Graphics.plot Action)
| Container(kind:container_kind)(key:string)(properties:list(string*json))(dismiss:option Action)(children:list(scene Action))
| Content(kind:content_kind)(key:string)(properties:list(string*json))(children:list(scene Action))
| ActionButton(key:string)(properties:list(string*json))(action:option Action)(disabled:bool)(children:list(scene Action))
| FormView(key:string)(properties:list(string*json))(submit:option Action)(children:list(scene Action))
| FieldView(kind:field_kind)(key:string)(spec:field_spec)(value:rendered_value(Schema.field_kind spec))
    (properties:list(string*json))(input:option(injection*Action))(keys:list(string*Action))(children:list(scene Action))
| FieldWithFiles(key:string)(spec:field_spec)(value:rendered_value(Schema.field_kind spec))
    (properties:list(string*json))(input:option(injection*Action))(files:Action)(keys:list(string*Action))(children:list(scene Action)).
Arguments GraphicView {Action}.
Arguments Container {Action}.
Arguments Content {Action}.
Arguments ActionButton {Action}.
Arguments FormView {Action}.
Arguments FieldView {Action}.
Arguments FieldWithFiles {Action}.
Definition make {A}(selected:standard_kind)(key:string)(props:list(property A))(children:list(scene A)):scene A:=
  let data:=data_properties props in
  let role:=proj1_sig selected in
  match role as selected_role return selected_role<>Graphic->scene A with
  |Button=>fun _=>ActionButton key data(activate_property props)(match data_property Disabled props with Some(JBool b)=>b|_=>false end)children
  |Form=>fun _=>FormView key data(activate_property props)children
  |Field=>fun _=>match files_property props with
    |None=>FieldView InputField key(field_property props)(input_value props)data(supply_property props)(keys_property props)children
    |Some files=>FieldWithFiles key(field_property props)(input_value props)data(supply_property props)files(keys_property props)children end
  |Select=>fun _=>FieldView SelectField key(field_property props)(input_value props)data(supply_property props)(keys_property props)children
  |Checkbox=>fun _=>FieldView CheckboxField key(field_property props)(input_value props)data(supply_property props)(keys_property props)children
  |Heading=>fun _=>Content CHeading key data children
  |Text=>fun _=>Content CText key data children|Markdown=>fun _=>Content CMarkdown key data children|Code=>fun _=>Content CCode key data children|Icon=>fun _=>Content CIcon key data children|Image=>fun _=>Content CImage key data children|Link=>fun _=>Content CLink key data children|OptionView=>fun _=>Content COption key data children|Progress=>fun _=>Content CProgress key data children
  |Graphic=>fun impossible=>False_rect _ (impossible eq_refl)
  |_=>fun _=>Container(match role with Header=>CHeader|Navigation=>CNavigation|Main=>CMain|Aside=>CAside|Section=>CSection|Dialog=>CDialog|ListView=>CList|Item=>CItem|Table=>CTable|Row=>CRow|Cell=>CCell|Portal=>CPortal|_=>CGroup end)key data(dismiss_property props)children end (proj2_sig selected).
Definition encode_rendered {k}(v:rendered_value k):=match v with Canonical value=>encode_value k value|Raw text=>JString text end.
Definition injection_name i:=match i with ValueInjection=>"value"|FileInjection=>"file"|InteractiveValueInjection=>"input.value"end.
Definition field_properties {A}(encode_action:A->json)(spec:field_spec)
  (value:rendered_value(Schema.field_kind spec))(props:list(string*json))
  (input:option(injection*A))(keys:list(string*A)) :=
  ("meta",JObject[("key_actions",JObject(map(fun p=>(fst p,encode_action(snd p)))keys))])::
  ("value",encode_rendered value)::match input with
  |None=>remove_field "value" props
  |Some(inject,a)=>("injection",JString(injection_name inject))::("action",encode_action a)::remove_field "value" props end.
Fixpoint encode {A}(encode_action:A->json)(value:scene A):json:=
  let pack role key props children:=JObject(("kind",JString(kind_name role))::("key",JString key)::("children",JArray(map(encode encode_action)children))::props)in
  match value with
  |GraphicView key props drawing=>JObject(("kind",JString "graphic")::("key",JString key)::("plot",Graphics.encode encode_action drawing)::props)
  |Container role key props dismiss children=>pack(container_role role)key
      (match dismiss with None=>props|Some a=>("dismiss_action",encode_action a)::props end)children
  |Content role key props children=>pack(content_role role)key props children
  |ActionButton key props action disabled children=>pack Button key
      (("disabled",JBool(disabled||match action with None=>true|Some _=>false end))::
       match action with None=>remove_field "disabled" props|Some a=>("action",encode_action a)::remove_field "disabled" props end)children
  |FormView key props submit children=>pack Form key(match submit with None=>props|Some a=>("action",encode_action a)::props end)children
  |FieldView role key spec value props input keys children=>pack(field_role role)key
      (field_properties encode_action spec value props input keys)children
  |FieldWithFiles key spec value props input files keys children=>pack Field key
      (("file_action",encode_action files)::field_properties encode_action spec value props input keys)children end.
Fixpoint map_actions {A B}(f:A->B)(value:scene A):scene B:=match value with
|GraphicView key props drawing=>GraphicView key props(Graphics.map_actions f drawing)
|Container role key props dismiss children=>Container role key props(option_map f dismiss)(map(map_actions f)children)
|Content role key props children=>Content role key props(map(map_actions f)children)
|ActionButton key props action disabled children=>ActionButton key props(option_map f action)disabled(map(map_actions f)children)
|FormView key props submit children=>FormView key props(option_map f submit)(map(map_actions f)children)
|FieldView role key spec value props input keys children=>FieldView role key spec value props(option_map(fun '(i,a)=>(i,f a))input)(map(fun p=>(fst p,f(snd p)))keys)(map(map_actions f)children)
|FieldWithFiles key spec value props input files keys children=>FieldWithFiles key spec value props
 (option_map(fun '(i,a)=>(i,f a))input)(f files)(map(fun p=>(fst p,f(snd p)))keys)(map(map_actions f)children)end.
