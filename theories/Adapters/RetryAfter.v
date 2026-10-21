From Stdlib Require Import String List Bool NArith Ascii.
From Selvedge.Foundation Require Import Json Numbers Utf8.
From Selvedge.Adapters Require Import Common.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Record decimal_delay := DecimalDelay { delay_numerator : N; delay_precision : nat }.
Definition decimal_denominator value := N.pow 10 (N.of_nat value.(delay_precision)).
Definition integer_delay value := DecimalDelay value 0.
Fixpoint split_at_character separator source current := match source with
  | EmptyString => [current]
  | String first rest => if Ascii.eqb first separator then current :: split_at_character separator rest ""
    else split_at_character separator rest (current ++ String first "") end.
Definition split_text separator source := split_at_character separator source "".
Fixpoint drop_spaces (values : list (N * string)) := match values with [] => [] | (code,bytes) :: rest =>
  if Utf8.whitespace code then drop_spaces rest else values end.
Definition trim source := match Utf8.chunks source with None => source | Some chunks =>
  String.concat "" (map snd (rev (drop_spaces (rev (drop_spaces chunks))))) end.
Definition nonempty_digits source := match parse_natural source with Some _ => true | None => false end.
Definition seconds_delay source : option decimal_delay :=
  match split_text "." source with
  | [whole] => if nonempty_digits whole then option_map (fun n => DecimalDelay (1000*n) 0) (parse_natural whole) else None
  | [whole;fraction] => if nonempty_digits whole && nonempty_digits fraction then
    option_map (fun n => DecimalDelay (1000*n) (String.length fraction)) (parse_natural (whole ++ fraction)) else None
  | _ => None end.
Definition delay_exceeds_integer value integer := integer * decimal_denominator value <? value.(delay_numerator).
Definition maximum_delay base proposed := if delay_exceeds_integer proposed base then proposed else integer_delay base.
Definition month_number name := match name with
  | "Jan" => Some 1 | "Feb" => Some 2 | "Mar" => Some 3 | "Apr" => Some 4
  | "May" => Some 5 | "Jun" => Some 6 | "Jul" => Some 7 | "Aug" => Some 8
  | "Sep" => Some 9 | "Oct" => Some 10 | "Nov" => Some 11 | "Dec" => Some 12 | _ => None end.
Definition leap year := N.eqb (year mod 4) 0 && (negb (N.eqb (year mod 100) 0) || N.eqb (year mod 400) 0).
Definition month_days year month := if N.eqb month 2 then if leap year then 29 else 28
  else if existsb (N.eqb month) [4;6;9;11] then 30 else 31.
Definition days_before_year year := let previous := year - 1 in
  365 * previous + previous / 4 - previous / 100 + previous / 400.
Definition days_before_month year month := fold_left (fun sum m => sum + month_days year m)
  (filter (fun m => m <? month) [1;2;3;4;5;6;7;8;9;10;11;12]) 0.
Definition timestamp year month day hour minute second :=
  ((days_before_year year - days_before_year 1970 + days_before_month year month + day - 1) * 24 + hour) *
    3600000 + minute * 60000 + second * 1000.
Definition date_parts day month year time : option N :=
  match parse_natural day,month_number month,parse_natural year,split_text ":"%char time with
  | Some day,Some month,Some year,[hour_text;minute_text;second_text] =>
    match parse_natural hour_text,parse_natural minute_text,parse_natural second_text with
    | Some hour,Some minute,Some second =>
      (* DEFENSE: Invalid calendar and clock fields in a Retry-After date do not authorize a delay. *)
      if (0 <? day) && (day <=? month_days year month) && (hour <? 24) && (minute <? 60) && (second <? 60)
      then Some (if year <? 1970 then 0 else timestamp year month day hour minute second) else None
    | _,_,_ => None end
  | _,_,_,_ => None end.
Definition short_weekday value := existsb (String.eqb value) ["Mon,";"Tue,";"Wed,";"Thu,";"Fri,";"Sat,";"Sun,"].
Definition long_weekday value := existsb (String.eqb value)
  ["Monday,";"Tuesday,";"Wednesday,";"Thursday,";"Friday,";"Saturday,";"Sunday,"].
(* KNOWN LIMITATION: Obsolete two-digit years retain the existing 1950--2049
   window rather than RFC 9110's receipt-time-dependent 50-year window. Modern
   four-digit HTTP dates do not depend on this historical interpretation. *)
Definition http_date source : option N :=
  (* RFC 9110 section 5.6.7 requires recipients to admit IMF-fixdate and the
     two historical HTTP-date forms; unrelated Date.parse extensions are excluded. *)
  match filter (fun value => negb (String.eqb value "")) (split_text " "%char source) with
  | [weekday;day;month;year;time;zone] =>
    if short_weekday weekday && String.eqb zone "GMT" && Nat.eqb (String.length year) 4
    then date_parts day month year time else None
  | [weekday;date;time;zone] =>
    if long_weekday weekday && String.eqb zone "GMT" then
      match split_text "-"%char date with [day;month;year] =>
        match parse_natural year with Some year =>
          date_parts day month (decimal ((if year <? 50 then 2000 else 1900) + year)) time
        | None => None end | _ => None end else None
  | [weekday;month;day;time;year] =>
    if existsb (String.eqb weekday) ["Mon";"Tue";"Wed";"Thu";"Fri";"Sat";"Sun"]
    then date_parts day month year time else None
  | _ => None end.
Definition parse_retry_after (header : string) (now : N) : option decimal_delay :=
  let header := trim header in
  match seconds_delay header with
  | Some value => Some value
  | None => option_map (fun date => integer_delay (date - now)) (http_date header)
  end.
Definition timer_milliseconds value : N :=
  let denominator := decimal_denominator value in
  (value.(delay_numerator) + denominator - 1) / denominator.
