From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Interaction Require Import Codec.
From Selvedge.Interaction Require ServiceConfiguration.
From Selvedge.Programming Require Import Resource.
Import ListNotations.
Open Scope string_scope.
Module Config := ServiceConfiguration.

Record draft := Draft { draft_path : list string; draft_input : string }.
Record state := State {
  catalog : resource unit Config.snapshot;
  current_draft : option draft;
  writing : resource unit unit
}.

Definition initial := State Dormant None Dormant.
Definition pending s := match writing s with Loading _ _ => true | _ => false end.
Definition reading s := match catalog s with Loading _ _ => true | _ => false end.
Definition available s := match catalog s with Loaded _ _ value => Some value | _ => None end.
Definition editing s :=
  current <- available s ;;
  draft <- current_draft s ;;
  entry <- Config.find_setting (draft_path draft) current ;;
  Some (current, draft, entry).

Definition matches_path path draft :=
  String.eqb (Config.setting_key path) (Config.setting_key (draft_path draft)).
Definition dirty s :=
  match editing s with
  | Some (_, draft, entry) => negb (String.eqb (draft_input draft) (Config.initial_input entry))
  | None => false
  end.
Definition can_select path s :=
  negb (pending s) &&
  match current_draft s with
  | Some draft => matches_path path draft || negb (dirty s)
  | None => true
  end.
Definition select path s :=
  let already_selected := match current_draft s with
    | Some draft => matches_path path draft
    | None => false
    end in
  if already_selected || negb (can_select path s) then s else
  match bind (available s) (Config.find_setting path) with
  | Some entry => State (catalog s) (Some (Draft path (Config.initial_input entry))) Dormant
  | None => s
  end.
Definition write_input raw s :=
  if pending s then s else
  match current_draft s with
  | Some draft => State (catalog s) (Some (Draft (draft_path draft) raw)) Dormant
  | None => s
  end.
Definition write_input_at path raw s :=
  let selected := select path s in
  match current_draft selected with
  | Some draft => if matches_path path draft then write_input raw selected else s
  | None => s
  end.
Definition cancel s :=
  if pending s then s else State (catalog s) None Dormant.
Definition begin_read ticket := State (Loading ticket tt) None Dormant.
Definition read_finished ticket outcome s :=
  State (settle ticket outcome (catalog s)) (current_draft s) (writing s).
Definition begin_write ticket s := State (catalog s) (current_draft s) (Loading ticket tt).
Definition write_finished ticket outcome s :=
  match writing s with
  | Loading current _ => if N.eqb current ticket then
      match outcome with
      | inl reason => State (catalog s) (current_draft s) (Failed ticket tt reason)
      | inr snapshot =>
          let retained := bind (current_draft s) (fun draft =>
            option_map (fun entry => Draft (draft_path draft) (Config.initial_input entry))
              (Config.find_setting (draft_path draft) snapshot)) in
          State (Loaded ticket tt snapshot) retained (Loaded ticket tt tt)
      end else s
  | _ => s
  end.

Definition encode_unit (_ : unit) := JNull.
Definition decode_unit j := match j with JNull => Some tt | _ => None end.
Definition encode_draft value := JObject
  [("path", Config.encode_path (draft_path value)); ("input", JString (draft_input value))].
Definition decode_draft j :=
  path <- list_field as_string "path" j ;;
  raw <- string_field "input" j ;;
  Some (Draft path raw).
Definition encode s := JObject
  [("catalog", encode_resource encode_unit Config.encode_snapshot (catalog s));
   ("draft", match current_draft s with None => JNull | Some value => encode_draft value end);
   ("writing", encode_resource encode_unit encode_unit (writing s))].
Definition decode j :=
  source <- bind (field "catalog" j) (decode_resource decode_unit Config.decode_snapshot) ;;
  draft <- bind (field "draft" j) (fun raw => match raw with
    | JNull => Some None | _ => option_map (@Some draft) (decode_draft raw)
    end) ;;
  write <- bind (field "writing" j) (decode_resource decode_unit decode_unit) ;;
  Some (State source draft write).
