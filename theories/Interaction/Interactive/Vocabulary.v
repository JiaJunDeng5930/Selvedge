From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema SchemaJson TextJson.
From Selvedge.Interaction.Interactive Require Import Bounds Builtins.
Import ListNotations.
Open Scope string_scope.
Open Scope nat_scope.
Inductive role:=Layout|TextLeaf|MarkdownLeaf|MetricLeaf|Field|Action|Table|Column|Chart|Condition|Repeat|Resource|Graph|Task|Template.
Record component_spec:=Component{component_tag:string;component_role:role;component_fields:schema;container:bool}.
Definition required_field name kind:=Schema.Field name kind.
Definition optional_field name kind:=Schema.Field name(KOptional kind).
Definition common_fields:schema:=[required_field "id"KText;optional_field "visible"KBool;optional_field "enabled"KBool;
 optional_field "tone"(KEnum "neutral"["accent";"success";"warning";"danger";"muted"]);
 optional_field "motion"(KEnum "none"["pulse";"spin"]);optional_field "transition"(KEnum "none"["status"])].
Definition gap:=optional_field "gap"(KEnum "md"["none";"sm";"lg"]).
Definition label:=required_field "label"KText.
Definition format:=optional_field "format"(KEnum (Builtins.format_name Builtins.DecimalFormat)
 (map Builtins.format_name (tl Builtins.formats))).
Definition field_component name:=Component name Field[label;required_field "bind"KText]false.
Definition chart_component name:=Component name Chart[required_field "data"(KArray KJson);required_field "row-key"KText;
 required_field "x"KText;required_field "y"KText;optional_field "label"KText;optional_field "x-label"KText;optional_field "y-label"KText]false.
Definition components:list component_spec:=[
 Component "stack"Layout[gap]true;Component "row-layout"Layout[gap]true;
 Component "grid"Layout[gap;required_field "columns"KNatural]true;Component "card"Layout[gap;optional_field "label"KText]true;
 Component "text"TextLeaf[label]false;Component "markdown"MarkdownLeaf[required_field "value"KText]false;
 Component "metric"MetricLeaf[label;required_field "value"KJson;format]false;Component "badge"TextLeaf[label]false;
 field_component "slider";field_component "number-input";field_component "text-input";field_component "textarea";field_component "checkbox";field_component "select";
 Component "button"Action[label;required_field "action"(KEnum "set"["reset";"draft";"submit";"copy";"openUrl"]);
 optional_field "target"KText;optional_field "value"KJson;optional_field "message"KText;optional_field "url"KText]false;
 Component "table"Table[required_field "rows"(KArray KJson);required_field "row-key"KText;optional_field "sortable"KBool;optional_field "label"KText]true;
 Component "column"Column[required_field "field"KText;label;format]false;
 chart_component "line-chart";chart_component "bar-chart";
 Component "when"Condition[required_field "test"KBool]true;
 Component "each"Repeat[required_field "items"(KArray KJson);required_field "item"KText;required_field "key"KText]true;
 Component "resource-view"Resource[required_field "source"KText;required_field "let"KText]true;
 Component "graph-view"Graph[required_field "nodes"(KArray KJson);required_field "edges"(KArray KJson);
 required_field "node-key"(KEnum "identity"[]);required_field "layout"(KEnum "stable"[]);optional_field "select"KText;optional_field "label"KText]true;
 Component "task-node"Task[required_field "task"KJson;label]false;
 Component "node-template"Template[required_field "item"KText]true].
Definition component tag:=find(fun spec=>String.eqb tag spec.(component_tag))components.
Definition full_schema spec:=List.app (match spec.(component_role)with Template=>[]|_=>common_fields end) spec.(component_fields).
Definition provided_types_valid description source:=forallb(fun spec=>
 match lookup spec.(field_name)source,spec.(field_kind)with
 | Some value,KOptional kind=>match decode_value kind value with Some _=>true|None=>false end
 | _,_=>true end)description.
Definition component_values(spec:component_spec)(source:list(string*json)):option(fields(full_schema spec)):=
 if provided_types_valid(full_schema spec)source then Schema.decode(full_schema spec)(JObject source)else None.
Definition role_name value:=match value with
 |Layout=>"layout"|TextLeaf=>"text"|MarkdownLeaf=>"markdown"|MetricLeaf=>"metric"
 |Field=>"input"|Action=>"action"|Table=>"table"|Column=>"table column"|Chart=>"chart"
 |Condition=>"condition"|Repeat=>"repeat"|Resource=>"resource"|Graph=>"graph"|Task=>"task"|Template=>"node template"end.
Definition described_fields:=SchemaJson.schema_fields_with
 (fun kind=>SchemaJson.kind_schema(SchemaJson.present_kind kind)).
Definition registry_text:=
 "Common fields (all components except node templates): "++
 TextJson.render_json(JObject(described_fields common_fields))++"
Required labels must be nonempty. Metric values must be scalar. Grid columns must be 1.."++Numbers.show_nat Bounds.grid_columns++".
"++String.concat "
"(map(fun spec=>spec.(component_tag)++" ["++role_name spec.(component_role)++", "++
 (if spec.(container)then "container"else "leaf")++"] "++
 TextJson.render_json(JObject(described_fields spec.(component_fields))))components).

Inductive declaration_kind:=StateDeclaration|DerivedDeclaration|SourceDeclaration|DatasetDeclaration|RowDeclaration.
Record declaration_spec:=Declaration{declaration_name:string;declaration_role:declaration_kind;declaration_fields:list string}.
Definition declaration_specs:list declaration_spec:=[
 Declaration "state"StateDeclaration["id";"type";"initial";"min";"max";"step";"options";"max-length"];
 Declaration "derive"DerivedDeclaration["id";"value"];
 Declaration "source"SourceDeclaration["id";"kind";"graph-id";"mode"];
 Declaration "dataset"DatasetDeclaration["id";"columns"];
 Declaration "row"RowDeclaration["dataset";"key";"value"]].
Definition declaration_specification tag:=find(fun value=>String.eqb tag value.(declaration_name))declaration_specs.
Definition is_declaration tag:=match declaration_specification tag with Some _=>true|None=>false end.
Definition declaration_attributes tag:=match declaration_specification tag with Some spec=>spec.(declaration_fields)|None=>[]end.
Definition leaf_tag tag:=is_declaration tag||match component tag with Some spec=>negb spec.(container)|None=>false end.
Definition declarations_text:=String.concat "; "(map(fun spec=>spec.(declaration_name)++"("++String.concat ","spec.(declaration_fields)++")")declaration_specs).
Definition limits_text:=Bounds.text.
Definition builtin_text:=Builtins.text.
