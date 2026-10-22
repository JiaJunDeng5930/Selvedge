From Stdlib Require Import String List Bool Arith NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Interaction Require Import Codec Identity.
From Selvedge.Browser Require Import Layout.
Import ListNotations.
Open Scope string_scope.

(* Font and region observations belong to the document generation measured. *)
Definition current_measurement (measured current : N) := N.eqb measured current.
Definition measurement_failure (measured current : N) (reason : string) :=
  if current_measurement measured current then Some reason else None.

Definition pixel_field name source := match number_field name source with
 |Some text=>parse_nat text|None=>None end.
Definition metric_observation source : option metric :=
  height <- pixel_field "height" source;;
  advance <- pixel_field "advance" source;;
  admit_metric height advance.
Definition named_observation (key : string) (source : json) : bool :=
  match string_field "key" source with
  | Some observed => String.eqb key observed
  | None => false
  end.
Definition valid_metric (source : json) : bool :=
  match metric_observation source with Some _ => true | None => false end.
Definition valid_region (source : json) : bool :=
  match pixel_field "width" source, pixel_field "height" source with
  | Some _, Some _ => true
  | _, _ => false
  end.
Definition first_valid_observation (valid : json -> bool) (key : string)
    (observations : list json) : option json :=
  find (fun value => named_observation key value && valid value) observations.
Definition font_observations source : option font_measurements :=
  body <- field "body" source;; primary <- field "primary" source;;
  support <- field "support" source;;
  body <- metric_observation body;; primary <- metric_observation primary;;
  support <- metric_observation support;;
  Some (FontMeasurements body primary support).
Definition region_observation name source : option (option nat) :=
  value <- field name source;;
  match value with JNull => Some None
  | JNumber spelling => option_map (@Some nat) (parse_nat spelling)
  | _ => None end.

(** Absence of an allocated region is an explicit pending observation. It is
    never replaced with zero or a width inferred from another region. *)
Definition decode_environment source : option environment :=
  width <- pixel_field "viewport_width" source;;
  height <- pixel_field "viewport_height" source;;
  root <- pixel_field "root_font_size_milli" source;;
  fonts <- field "font_metrics" source;; fonts <- font_observations fonts;;
  workspace <- region_observation "workspace_inner_width" source;;
  main <- region_observation "main_inner_width" source;;
  dark <- bool_field "system_dark" source;;
  reduced <- bool_field "reduced_motion" source;;
  if Nat.eqb root 0 then None
  else Some (Environment width height root fonts workspace main dark reduced).

Definition encode_view view := match view with
 |None=>JNull
 |Some(Identity.PrimaryTask task)=>JObject[("kind",JString "primary");("task",JNumber(show_natural task))]
 |Some(Identity.SideTask task)=>JObject[("kind",JString "side");("task",JNumber(show_natural task))] end.
Definition decode_view source : option(option Identity.task_view) := match source with
 |JNull=>Some None
 |_=>kind <- string_field "kind" source;;task <- Codec.natural_field "task" source;;
 match kind with "primary"=>Some(Some(Identity.PrimaryTask task))|"side"=>Some(Some(Identity.SideTask task))|_=>None end end.
Definition physical_target view logical := match view with
 |None=>logical|Some view=>Identity.task_view_key view logical end.
