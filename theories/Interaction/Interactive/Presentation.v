From Stdlib Require Import String List Bool NArith ZArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Interaction.Interactive Require Import Types Expand Local.

(** This is the existing component language's admitted description and binding.
    It is not a collection of native HTML attributes. *)
Record component := Component {
 component_event : Types.event;
 component_properties : Expand.properties;
 component_binding : Expand.binding
}.

(** Interactive fields are governed by their declared state/schema, including
    decimal and temporarily invalid raw text. They are not business-form fields. *)
Record editor (Action : Type) := Editor {
 editing_component : component;
 editing_shape : Local.shape;
 editing_validation : option string;
 editing_value : json;
 editing_raw : option string;
 editing_enabled : bool;
 editing_receive : option (json -> option Action)
}.
Arguments Editor {Action}.
Arguments editing_component {Action}.
Arguments editing_shape {Action}.
Arguments editing_validation {Action}.
Arguments editing_value {Action}.
Arguments editing_raw {Action}.
Arguments editing_enabled {Action}.
Arguments editing_receive {Action}.
Definition map_editor {A B} (f : A -> B) (value : editor A) : editor B :=
 Editor (editing_component value) (editing_shape value) (editing_validation value) (editing_value value) (editing_raw value) (editing_enabled value)
  (option_map (fun receive input=>option_map f (receive input)) (editing_receive value)).

(** Graph geometry positions node templates without scaling their controls. *)
Inductive placement :=
| GraphViewport
| ChartViewport
| GraphCanvas (width height : N)
| GraphEdges
| GraphNode (x y : Z) (width height : N) (selected : bool).

(** Header actions stay in their real table cells, with one identity used by
    semantic event resolution and native compilation. *)
Record table_column (Action:Type) := TableColumn {
 column_identity:string; column_heading:string; column_sort:option Action;
 column_enabled:bool; column_order:option bool
}.
Arguments TableColumn {Action}.
Arguments column_identity {Action}.
Arguments column_heading {Action}.
Arguments column_sort {Action}.
Arguments column_enabled {Action}.
Arguments column_order {Action}.
Record table_row := TableRow {
 row_identity:string;
 row_values:list string
}.
Record table (Action:Type) := DataTable {
 table_caption:string; table_columns:list(table_column Action);
 table_rows:list table_row
}.
Arguments DataTable {Action}.
Arguments table_caption {Action}.
Arguments table_columns {Action}.
Arguments table_rows {Action}.
Definition column_key {A} (table_key:string) (column:table_column A) :=
 String.append table_key (String.append "/column/" (column_identity column)).
Definition map_column {A B} (f:A->B) (column:table_column A) : table_column B :=
 TableColumn (column_identity column) (column_heading column)
  (option_map f (column_sort column)) (column_enabled column) (column_order column).
Definition map_table {A B} (f:A->B) (value:table A) : table B :=
 DataTable (table_caption value) (map (map_column f) (table_columns value)) (table_rows value).
