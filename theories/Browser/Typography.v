From Stdlib Require Import String List Arith.
From Selvedge.Foundation Require Import Numbers.
From Selvedge.Interaction.Presentation Require Import Information.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Inductive tier := Display | Title | Section | Body | Support
| CodeBody | CodeSupport | ActivityPrimary | ActivitySupport.
Inductive emphasis := Regular | Medium | Strong.

(* These are the original typography calibration, not estimates from a body font. *)
Definition root_scale (root_font_size_milli : nat) :=
  Nat.max 1000 (root_font_size_milli / 16).
Definition scaled root_font_size_milli nominal :=
  Nat.max 1 (nominal * root_scale root_font_size_milli / 1000).
Definition support_size root := scaled root 12.
Definition body_size root := Nat.max (S (support_size root)) (scaled root 13).
Definition section_size root := Nat.max (S (body_size root)) (scaled root 14).
Definition title_size root := Nat.max (S (section_size root)) (scaled root 20).
Definition display_size root := Nat.max (S (title_size root)) (scaled root 28).
Definition size root value :=
  match value with
  | Display => display_size root | Title => title_size root
  | Section => section_size root | Body | CodeBody => body_size root
  | Support | CodeSupport | ActivitySupport => support_size root
  | ActivityPrimary => scaled root 14
  end.
Definition nominal_leading value :=
  match value with
  | Display => 36 | Title => 28
  | Support | CodeSupport | ActivitySupport => 18
  | _ => 20
  end.
Definition line_height root value :=
  Nat.max (S (size root value)) (scaled root (nominal_leading value)).
Definition font_family value :=
  match value with
  | CodeBody | CodeSupport => "var(--font-mono, monospace)"
  | _ => "var(--font-sans, system-ui)"
  end.
Definition weight value := match value with Regular => 400 | Medium => 500 | Strong => 600 end.

Definition information_tier (activity : bool) value :=
  let ordinary := match value with
    | Information.IntroductionTitle => Display | Information.SurfaceTitle => Title
    | Information.GroupTitle => Section | Information.NavigationCaption => Support
    | Information.Description | Information.Status => Support
    | Information.FieldLabel | Information.FieldValue | Information.OptionLabel => Body
    end in
  if activity then
    match ordinary with Support | CodeSupport => ActivitySupport | _ => ActivityPrimary end
  else ordinary.
Definition information_emphasis value :=
  match value with
  | Information.IntroductionTitle | Information.GroupTitle => Strong
  | Information.SurfaceTitle | Information.FieldLabel | Information.OptionLabel => Medium
  | _ => Regular
  end.

Definition px value := String.append (Numbers.show_nat value) "px".
Definition properties root value strength : list (string * string) :=
  [("font-family",font_family value); ("font-size",px (size root value));
   ("line-height",px (line_height root value)); ("font-weight",Numbers.show_nat (weight strength))].

Record measurement_spec := MeasurementSpec {
  measurement_key : string; measurement_tier : tier; measurement_sample : string
}.
Definition measurement_specs : list measurement_spec :=
  [MeasurementSpec "@font/body" Body "0";
   MeasurementSpec "@font/activity-primary" ActivityPrimary "0";
   MeasurementSpec "@font/activity-support" ActivitySupport "0"].
Definition specification_properties root value := properties root (measurement_tier value) Regular.
