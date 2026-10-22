From Stdlib Require Import String List Arith Bool.
From Selvedge.Browser Require Import Typography Enclosure.
From Selvedge.Interaction.Presentation Require Import Composition.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

(* Zero metrics are not font observations. The constructor stores their positive predecessors. *)
Record metric := Metric { height_extra : nat; advance_extra : nat }.
Definition metric_height value := S (height_extra value).
Definition metric_advance value := S (advance_extra value).
Definition admit_metric height advance :=
  match height, advance with S h, S a => Some (Metric h a) | _, _ => None end.
Record font_measurements := FontMeasurements {
  body_metric : metric; primary_metric : metric; support_metric : metric
}.
Record environment := Environment {
  viewport_width : nat; viewport_height : nat; root_font_size_milli : nat;
  font_metrics : font_measurements;
  workspace_inner_width : option nat; main_inner_width : option nat;
  system_dark : bool; reduced_motion : bool
}.

Record layout_parameters := Parameters {
  navigation_width : nat; main_minimum_width : nat; details_width : nat;
  reading_maximum_width : nat; overview_maximum_width : nat; toolbar_height : nat;
  input_minimum_height : nat; input_maximum_height : nat; input_line_height : nat;
  creation_balanced_minimum_height : nat; lane_minimum_width : nat;
  navigation_minimum_width : nat; activity_primary_advance : nat; activity_support_advance : nat
}.
Definition parameters env :=
  let root := root_font_size_milli env in
  let scale := Typography.scaled root in
  let metrics := font_metrics env in
  let advance := metric_advance (body_metric metrics) in
  let leading := Nat.max (Typography.line_height root Typography.Body)
    (metric_height (body_metric metrics)) in
  let toolbar := Nat.max (scale 46) (leading + scale 26) in
  let input_minimum := Nat.max (scale 44) (leading + 2 * scale 12) in
  let balanced := toolbar + 2 * (Typography.line_height root Typography.Display +
    input_minimum + scale 32 + 3 * scale 16) in
  Parameters (scale 240) (Nat.max (scale 360) (advance * 40 + 2 * scale 16))
    (scale 360) (advance * 96) (advance * 144) toolbar input_minimum
    (Nat.max (scale 240) input_minimum) leading balanced (advance * 32 + 2 * scale 8)
    (scale 224) (metric_advance (primary_metric metrics)) (metric_advance (support_metric metrics)).

Definition reading_minimum env :=
  metric_advance (body_metric (font_metrics env)) * 64 +
    2 * Typography.scaled (root_font_size_milli env) 16.
Definition global_navigation_width env := Typography.scaled (root_font_size_milli env) 84.
Definition navigation_requirement env :=
  let p := parameters env in navigation_width p + main_minimum_width p.
Definition details_requirement env := reading_minimum env + details_width (parameters env).
Definition observe_capacity env : option (bool * bool) :=
  match workspace_inner_width env, main_inner_width env with
  | Some workspace, Some main =>
      Some (Nat.leb (global_navigation_width env + navigation_requirement env) (viewport_width env),
        Nat.leb (details_requirement env) main)
  | _, _ => None
  end.

Definition base_motor_minimum := 32%nat.
Definition motor_minimum env := Nat.max base_motor_minimum
  (Typography.scaled (root_font_size_milli env) base_motor_minimum).
Definition writing_lines := 2%nat.
Definition clearance env := Typography.scaled (root_font_size_milli env) 12.
Record hierarchy := Hierarchy {
  hierarchy_member_gap : nat; hierarchy_heading_extra : nat;
  hierarchy_group_extra : nat; hierarchy_nesting_extra : nat
}.
Definition hierarchy_for env (activity : bool) :=
  if activity then
    let scale := Typography.scaled (root_font_size_milli env) in
    let member := scale 4 in let heading := scale 8 in
    Hierarchy member (heading - member - 1) (scale 16 - heading - 1) (scale 12 - 1)
  else Hierarchy 4 3 7 11.
Definition member_gap value := hierarchy_member_gap value.
Definition heading_gap value := hierarchy_member_gap value + S (hierarchy_heading_extra value).
Definition group_gap value := heading_gap value + S (hierarchy_group_extra value).
Definition nesting_inset value := S (hierarchy_nesting_extra value).
Definition member_properties env (activity nested : bool) : list (string * string) :=
  let grammar := hierarchy_for env activity in
  [("display","flex"); ("flex-direction","column");
   ("gap",Typography.px (member_gap grammar));
   ("padding-inline-start",Typography.px (if nested then nesting_inset grammar else 0))].
Definition heading_properties env activity : list (string * string) :=
  [("display","flex"); ("flex-direction","column");
   ("gap",Typography.px (heading_gap (hierarchy_for env activity)))].
Definition group_properties env activity : list (string * string) :=
  [("display","flex"); ("flex-direction","column");
   ("gap",Typography.px (group_gap (hierarchy_for env activity)))].

Definition page_properties env page : list (string * string) :=
  let p := parameters env in
  let recipe := Composition.recipe page in
  let area := Enclosure.spacing Enclosure.PageContent in
  let edges := 2 * Enclosure.inline_inset area in
  [("display","flex"); ("flex-direction","column"); ("min-inline-size","0");
   ("min-block-size","0"); ("block-size","100%");
   ("padding-inline",Typography.px (Enclosure.inline_inset area));
   ("padding-block",Typography.px (Enclosure.block_inset area));
   ("gap",Typography.px (Enclosure.separation Enclosure.Sections));
   ("inline-size","100%"); ("margin-inline","auto");
   ("max-inline-size",match Composition.reading_measure recipe with
      | Composition.ReadingMeasure => Typography.px (reading_maximum_width p + edges)
      | Composition.OverviewMeasure => Typography.px (overview_maximum_width p + edges)
      | Composition.AvailableMeasure => "none" end)] ++
  match Composition.body_kind recipe with
  | Composition.CenteredCreation => [("justify-content","safe center")]
  | _ => [] end.

Definition region_properties env (region : Composition.region) (position : Composition.position)
    : list (string * string) :=
  let p := parameters env in
  [("min-inline-size","0")] ++
  (match position with
   | Composition.HeadingPosition => [("flex","none")]
   | Composition.BodyPosition => []
   | Composition.DockPosition => [("flex","none"); ("position","relative")]
   end) ++
  match region with
  | Composition.ConversationHeader => [("display","flex"); ("flex-direction","row");
      ("flex-wrap","nowrap"); ("align-items","center"); ("gap",Typography.px (Enclosure.separation Enclosure.ComposerControls))]
  | Composition.ConversationTitle => [("flex","1 1 auto"); ("overflow","hidden"); ("white-space","nowrap")]
  | Composition.TaskActions => [("display","flex"); ("flex-direction","row"); ("flex-wrap","nowrap");
      ("align-items","center"); ("gap",Typography.px (Enclosure.separation Enclosure.InlineControls)); ("flex","none")]
  | Composition.TimelineContent => [("flex","1 1 auto"); ("min-block-size","0"); ("overflow-y","auto")]
  | Composition.ComposerInput => [("inline-size","100%"); ("max-inline-size",Typography.px (reading_maximum_width p));
      ("align-self","center")]
  | Composition.CreationIntroduction => [("text-align","center")]
  | Composition.BoardStages => [("display","flex"); ("gap",Typography.px (Enclosure.separation Enclosure.BoardColumns));
      ("overflow-x","auto"); ("min-block-size","0"); ("flex","1 1 auto")]
  | _ => [] end.

Definition workspace_properties env (navigation_visible supporting_visible : bool) : list (string * string) :=
  let p := parameters env in
  [("display","grid"); ("min-inline-size","0"); ("min-block-size","0");
   ("inline-size","100%"); ("block-size","100%");
   ("grid-template-rows","auto minmax(0,1fr)");
   ("grid-template-columns",
     String.append (if navigation_visible then String.append (Typography.px (navigation_width p)) " " else "")
       (String.append "minmax(0,1fr)" (if supporting_visible then String.append " " (Typography.px (details_width p)) else "")))].

(** A responsive row changes as a whole; individual children never wrap independently. *)
Inductive native_direction := Horizontal | Vertical.
Definition row_flow available minimum :=
  if Nat.leb minimum available then Horizontal else Vertical.
Definition row_properties direction : list (string * string) :=
  [("display","flex"); ("flex-wrap","nowrap");
   ("flex-direction",match direction with Horizontal => "row" | Vertical => "column" end)].
