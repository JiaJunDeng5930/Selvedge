From Stdlib Require Import String Ascii List Bool Arith.
From Selvedge.Foundation Require Import Json Numbers.
Import ListNotations.
Open Scope string_scope.

Record skill := Skill { skill_name : string; skill_description : string; skill_path : string }.
Record trigger := Trigger { trigger_start : nat; trigger_end : nat; query : string }.
Inductive markup := Prose | InlineCode | BacktickFence | TildeFence.
Definition whitespace (char : ascii) :=
  Ascii.eqb char " " || Ascii.eqb char "009" || Ascii.eqb char "010" || Ascii.eqb char "013".
Definition boundary (char : ascii) := whitespace char || Ascii.eqb char "(" || Ascii.eqb char "[" || Ascii.eqb char "{".
Definition extend (found : option trigger) (char : ascii) (offset : nat) :=
  match found with
  | None => None
  | Some item => if String.eqb (query item) "" && whitespace char then None
      else Some (Trigger (trigger_start item) offset (query item ++ String char ""))
  end.

Fixpoint scan (text : string) (offset : nat) (previous_boundary : bool)
    (mode : markup) (found : option trigger) : option trigger :=
  match text with
  | EmptyString => found
  | String "`" (String "`" (String "`" rest)) =>
      scan rest (offset + 3) false
        (match mode with BacktickFence => Prose | TildeFence => TildeFence | _ => BacktickFence end) None
  | String "~" (String "~" (String "~" rest)) =>
      scan rest (offset + 3) false
        (match mode with TildeFence => Prose | BacktickFence => BacktickFence | _ => TildeFence end) None
  | String char rest =>
      if Ascii.eqb char "`" then
        scan rest (S offset) false
          (match mode with Prose => InlineCode | InlineCode => Prose | _ => mode end) None
      else if Ascii.eqb char "010" || Ascii.eqb char "013" then
        scan rest (S offset) true
          (match mode with InlineCode => Prose | _ => mode end) None
      else if Ascii.eqb char "@" then
        scan rest (S offset) false mode
          (match mode with Prose => if previous_boundary then Some (Trigger offset (S offset) "") else None | _ => None end)
      else scan rest (S offset) (boundary char) mode
        (match mode with Prose => extend found char (S offset) | _ => None end)
  end.
Definition detect (text : string) (start finish : nat) (composing : bool) :=
  if composing || negb (Nat.eqb start finish) || negb (Nat.leb start (String.length text)) then None
  else scan (substring O start text) O true Prose None.

Definition lower_ascii (char : ascii) :=
  let code := nat_of_ascii char in
  if (65 <=? code)%nat && (code <=? 90)%nat then ascii_of_nat (code + 32) else char.
Fixpoint lower (text : string) :=
  match text with EmptyString => EmptyString | String char rest => String (lower_ascii char) (lower rest) end.
Fixpoint contains (needle haystack : string) :=
  if prefix needle haystack then true else
    match haystack with EmptyString => false | String _ rest => contains needle rest end.
Fixpoint trim_left (text : string) :=
  match text with EmptyString => EmptyString | String char rest =>
    if whitespace char then trim_left rest else text end.
Fixpoint trim_right (text : string) :=
  match text with EmptyString => EmptyString | String char rest =>
    let tail := trim_right rest in
    if whitespace char && String.eqb tail "" then "" else String char tail end.
Definition trim (text : string) := trim_right (trim_left text).
Definition candidates (search : string) (skills : list skill) :=
  filter (fun value => contains (lower (trim search)) (lower (skill_name value ++ " " ++ skill_description value))) skills.
Definition move_index (backward : bool) (selected count : nat) :=
  match count with
  | O => O
  | S _ =>
      (* DEFENSE: Refreshing a filtered catalog can shorten it while an older highlighted index is retained. *)
      let current := selected mod count in
      if backward then if Nat.eqb current O then pred count else pred current
      else if Nat.ltb (S current) count then S current else O
  end.
Definition decode_skill (value : json) :=
  match string_field "name" value, string_field "description" value, string_field "path" value with
  | Some name, Some description, Some path => Some (Skill name description path)
  | _, _, _ => None end.
Definition encode_skill (value : skill) := JObject
  [("name", JString (skill_name value)); ("description", JString (skill_description value)); ("path", JString (skill_path value))].
Definition encode_trigger (value : trigger) := JObject
  [("start", JNumber (show_nat (trigger_start value))); ("end", JNumber (show_nat (trigger_end value))); ("query", JString (query value))].
Definition call (source : json) :=
  match string_field "text" source, number_field "start" source, number_field "end" source with
  | Some text, Some start, Some finish =>
      match parse_nat start, parse_nat finish with
      | Some start, Some finish =>
          let composing := match bool_field "composing" source with Some value => value | None => false end in
          match detect text start finish composing with
          | None => success (JObject [("trigger", JNull); ("candidates", JArray [])])
          | Some trigger =>
            let skills := match array_field "skills" source with
              Some values => flat_map (fun value => match decode_skill value with Some skill => [skill] | None => [] end) values
              | None => [] end in
            success (JObject [("trigger", encode_trigger trigger);
              ("candidates", JArray (map encode_skill (candidates (query trigger) skills)))])
          end
      | _, _ => failure "TypeError" "Mention selection requires byte offsets" end
  | _, _, _ => failure "TypeError" "Mention observation requires text and selection" end.


(** The visibility constructor owns the trigger and highlighted index together. *)
Inductive mention_state := Inactive | Suggesting (value : trigger) (selected : nat)
  | Dismissed (value : trigger).
Definition same_trigger (left right : trigger) :=
  Nat.eqb (trigger_start left) (trigger_start right) &&
  Nat.eqb (trigger_end left) (trigger_end right) && String.eqb (query left) (query right).
Definition observe_mention text start finish composing state :=
  match detect text start finish composing with
  | None => Inactive
  | Some value =>
      match state with
      | Suggesting previous selected =>
          if same_trigger value previous then Suggesting value selected else Suggesting value O
      | Dismissed previous =>
          if same_trigger value previous then Dismissed value else Suggesting value O
      | Inactive => Suggesting value O
      end
  end.
Definition dismiss_mention state :=
  match state with Suggesting value _ => Dismissed value | _ => state end.
Definition mention_candidates skills state :=
  match state with Suggesting value _ => candidates (query value) skills | _ => [] end.
Definition move_mention backward skills state :=
  match state with
  | Suggesting value selected => Suggesting value
      (move_index backward selected (List.length (candidates (query value) skills)))
  | _ => state end.
Definition highlighted_choice skills state :=
  match state with
  | Suggesting value selected =>
      let matches := candidates (query value) skills in
      let index := selected mod List.length matches in
      option_map (fun skill => (index, skill)) (nth_error matches index)
  | _ => None end.
Definition highlighted skills state := option_map snd (highlighted_choice skills state).
Definition choose_mention index skills state :=
  match state with
  | Suggesting value _ => option_map (fun chosen => (value, chosen))
      (nth_error (candidates (query value) skills) index)
  | _ => None end.
Definition encode_mention state :=
  match state with
  | Inactive => JObject [("state", JString "inactive")]
  | Dismissed value => JObject [("state", JString "dismissed"); ("trigger", encode_trigger value)]
  | Suggesting value selected => JObject [("state", JString "suggesting");
      ("trigger", encode_trigger value); ("selected", JNumber (show_nat selected))]
  end.
Definition decode_trigger value :=
  match number_field "start" value, number_field "end" value, string_field "query" value with
  | Some start, Some finish, Some query =>
      match parse_nat start, parse_nat finish with
      | Some start, Some finish => Some (Trigger start finish query) | _, _ => None end
  | _, _, _ => None end.
Definition decode_mention value :=
  match string_field "state" value with
  | Some "inactive" => Some Inactive
  | Some "dismissed" => match field "trigger" value with
      Some value => option_map Dismissed (decode_trigger value) | None => None end
  | Some "suggesting" => match field "trigger" value, number_field "selected" value with
      Some value, Some selected => match decode_trigger value, parse_nat selected with
        Some value, Some selected => Some (Suggesting value selected) | _, _ => None end
      | _, _ => None end
  | _ => None end.

(** Skill references are explicit Markdown paths; inserting one never loads its body. *)
Fixpoint escape_reference (reserved : list ascii) (text : string) : string :=
  match text with
  | EmptyString => EmptyString
  | String char rest =>
      (if existsb (Ascii.eqb char) reserved then String (ascii_of_nat 92) EmptyString else EmptyString) ++
      String char (escape_reference reserved rest)
  end.
Definition reference (value : skill) : string :=
  let path := skill_path value in
  let escaped := escape_reference [ascii_of_nat 92; "("%char; ")"%char; "<"%char; ">"%char] path in
  let destination := if contains " " path || contains (String "009" EmptyString) path then "<" ++ escaped ++ ">" else escaped in
  "[$" ++ escape_reference [ascii_of_nat 92; "["%char; "]"%char] (skill_name value) ++ "](" ++ destination ++ ")".
Definition replacement (value : skill) (suffix : string) : string :=
  reference value ++ match suffix with
    | EmptyString => " "
    | String char _ => if whitespace char then "" else " "
    end.

Record insertion := Insertion { insertion_text : string; insertion_caret : nat }.
Definition insert (source : string) (found : trigger) (value : skill) : insertion :=
  let prefix := substring 0 (trigger_start found) source in
  let suffix := substring (trigger_end found) (String.length source) source in
  let inserted := replacement value suffix in
  Insertion (prefix ++ inserted ++ suffix) (trigger_start found + String.length inserted).
