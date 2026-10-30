From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json TextJson JsonObjects.
From Selvedge.Foundation Require ArgumentDeclaration DeclarationFields.
From Selvedge.Adapters Require Import Common.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Module D := ArgumentDeclaration.
Module F := DeclarationFields.

Definition checked (valid : bool) value code message := if valid then success value else failure code message.
Definition omission := String (Ascii.ascii_of_nat 10) "[Tool output preview: middle omitted]" ++ String (Ascii.ascii_of_nat 10) "".
Definition tool_output_tokens : N := 1000.
Definition response_bytes : N := 65536.
Definition request_bytes : N := 2100000.
Definition request_tokens : N := 28000.
Definition contract := JObject [("tool_output_tokens",number tool_output_tokens);("response_bytes",number response_bytes);
  ("request_bytes",number request_bytes);("request_tokens",number request_tokens);("omission",JString omission)].
Definition action name := JObject [("action",JString name)].
Definition ends source suffix := starts (substring (String.length source - String.length suffix) (String.length suffix) source) suffix &&
  Nat.leb (String.length suffix) (String.length source).
Definition bounded value maximum := canonical_natural value && (nat_value value <=? maximum).
Definition token_cost := D.Natural 0 9007199254740991.
Definition costs_of source := option_map (map (@proj1_sig _ _)) (D.decode (D.Array token_cost) (get source "costs")).
Definition cost_sum costs := fold_left N.add costs 0.
Fixpoint indexed_costs (costs : list N) index := match costs with [] => [] | cost::rest =>
 (index,cost)::indexed_costs rest (index+1) end.
Fixpoint insert_cost (entry : N * N) entries := match entries with [] => [entry] | first::rest =>
 if snd entry <=? snd first then entry::first::rest else first::insert_cost entry rest end.
Fixpoint positive_order (entries : list (N * N)) := match entries with [] => [] | first::rest =>
 let tail := positive_order rest in if 0 <? snd first then insert_cost first tail else tail end.
Fixpoint allocate (entries : list (N * N)) remaining count := match entries with [] => [] | entry::rest =>
 let budget := N.min (snd entry) (remaining / count) in
 (fst entry,budget)::allocate rest (remaining-budget) (count-1) end.
Definition allocation_for allocations index := match find (fun a => N.eqb (fst a) index) allocations with
 | Some allocation => snd allocation | None => 0 end.
Definition allocation_values costs := if cost_sum costs <=? tool_output_tokens then costs else
 let entries := indexed_costs costs 0 in let ordered := positive_order entries in
 let values := allocate ordered tool_output_tokens (N.of_nat (List.length ordered)) in
 map (fun entry => allocation_for values (fst entry)) entries.
Definition allocation_actions costs budgets := map (fun pair => let '(cost,budget) := pair in
 JObject [("budget",number budget);("action",JString (if cost <=? budget then "original" else "preview"))]) (combine costs budgets).
Definition budget_plan source := match costs_of source with
 | Some costs => success (JArray (allocation_actions costs (allocation_values costs)))
 | None => range_error "Invalid evaluator tool-output budget" end.

(** A preview program owns its selected text. The host supplies tokenizer
    observations, never an independent result, source copy or completion proof. *)
Inductive selection := Original | Elided | Excerpt (text : string) (tokens : N).
Inductive preview_state := Decoding (keep head tail : N) | Counting (keep : N) (head tail : string).
Inductive preview_command := Finished (selected : selection) | MeasureMarker | EncodeText | Continue (state : preview_state).
Record preview_observations := PreviewObservations {
 marker_cost : option N; token_count : option N;
 current_state : option (list (string * json)); observed_fields : option (list (string * json))
}.
Definition observation_fields := [F.optional "marker_cost" token_cost;F.optional "token_count" token_cost;
 F.optional "state" D.RawObject;F.optional "observation" D.RawObject].
Definition observations_of_values (fields : F.values observation_fields) :=
 let '(marker,(tokens,(state,(observed,_)))) := fields in
 PreviewObservations (option_map (@proj1_sig _ _) marker) (option_map (@proj1_sig _ _) tokens) state observed.
Definition preview_keep keep marker := if keep =? 0 then Finished (Excerpt omission marker) else
 let head := (3*keep+3)/4 in Continue (Decoding keep head (keep-head)).
Definition preview_start budget cost observations :=
 if cost <=? budget then Finished Original else
 match marker_cost observations with None => MeasureMarker | Some marker =>
 if budget <? marker then Finished Elided else
 match token_count observations with None => EncodeText
 | Some count => preview_keep (N.min count budget) marker end end.
Definition decode_fields := [F.required "keep" (D.Natural 1 tool_output_tokens);
 F.required "head_count" (D.Natural 0 tool_output_tokens);F.required "tail_count" (D.Natural 0 tool_output_tokens)].
Definition count_fields := [F.required "keep" (D.Natural 1 tool_output_tokens);
 F.required "head" D.text;F.required "tail" D.text].
Definition state_of source :=
 if String.eqb (str source "action") "decode" then
   match F.observe decode_fields source with Some (keep,(head,(tail,_))) =>
     Some (Decoding (proj1_sig keep) (proj1_sig head) (proj1_sig tail)) | None => None end
 else if String.eqb (str source "action") "count" then
   match F.observe count_fields source with Some (keep,(head,(tail,_))) =>
     Some (Counting (proj1_sig keep) (proj1_sig head) (proj1_sig tail)) | None => None end
 else None.
Definition preview_state_valid text budget count state := match state with
 | Decoding keep head tail => (keep <=? N.min budget count) && (head+tail <=? keep)
 | Counting keep head tail => (keep <=? N.min budget count) && starts text head && ends text tail end.
Definition decoded_fields := [F.required "head" D.text;F.required "tail" D.text].
Definition counted_fields := [F.required "cost" token_cost].
Definition preview_step text budget observations state observed :=
 match token_count observations,marker_cost observations with Some count,Some marker =>
 match D.admit (preview_state_valid text budget count) state with None => None | Some admitted =>
 match proj1_sig admitted with
 | Decoding keep head tail => match F.decode decoded_fields observed with
   | Some (first,(last,_)) => let first := proj1_sig first in let last := proj1_sig last in
     if ((0 <? head) || String.eqb first "") && ((0 <? tail) || String.eqb last "") then
       Some (if (0 <? head) && negb (starts text first) then Continue (Decoding keep (head-1) tail)
         else if (0 <? tail) && negb (ends text last) then Continue (Decoding keep head (tail-1))
         else Continue (Counting keep first last)) else None
   | None => None end
 | Counting keep head tail => match F.decode counted_fields observed with
   | Some (cost,_) => let cost := proj1_sig cost in
     Some (if cost <=? budget then Finished (Excerpt (head ++ omission ++ tail) cost)
       else preview_keep (keep - (cost-budget)) marker)
   | None => None end
 end end | _,_ => None end.
Definition preview_command_for text budget cost observations := match current_state observations with
 | None => Some (preview_start budget cost observations)
 | Some state => match state_of (JObject state),observed_fields observations with
   | Some state,Some observed => preview_step text budget observations state (JObject observed)
   | _,_ => None end end.
Definition command_json command := match command with
 | Finished _ => action "done"
 | MeasureMarker => JObject [("action",JString "marker");("text",JString omission)]
 | EncodeText => action "encode"
 | Continue (Decoding keep head tail) => JObject [("action",JString "decode");("keep",number keep);
     ("head_count",number head);("tail_count",number tail)]
 | Continue (Counting keep head tail) => JObject [("action",JString "count");("keep",number keep);
     ("head",JString head);("tail",JString tail);("text",JString (head ++ omission ++ tail))] end.
Definition preview_fields := List.app [F.required "text" D.text;F.required "budget" (D.Natural 0 tool_output_tokens);
 F.required "original_cost" token_cost] observation_fields.
Definition preview source := match F.decode preview_fields source with
 | Some (text,(budget,(cost,observations))) =>
   match preview_command_for (proj1_sig text) (proj1_sig budget) (proj1_sig cost) (observations_of_values observations) with
   | Some command => success (command_json command) | None => type_error "Invalid evaluator preview observation" end
 | None => type_error "Invalid evaluator preview observation" end.
Module Type BudgetedOutputs.
 Parameter t : Set.
 Parameter text : t -> option string.
 Parameter metadata : t -> json.
 Parameter finish : list string -> json -> option (list t).
End BudgetedOutputs.
Module Budgeted : BudgetedOutputs.
Record output_preview := OutputPreview { selected_text : option string; original_tokens : N;
 sent_tokens : N; budget_tokens : N; truncated : bool }.
Definition t := output_preview.
Definition text (value : t) := selected_text value.
Definition selected_preview text cost budget selected := match selected with
 | Original => OutputPreview (Some text) cost cost budget false
 | Elided => OutputPreview None cost 0 budget true
 | Excerpt excerpt sent => OutputPreview (Some excerpt) cost sent budget (negb (String.eqb text excerpt)) end.
Definition metadata value := JObject [("truncated",JBool (truncated value));
 ("original_tokens",number (original_tokens value));("sent_tokens",number (sent_tokens value));
 ("budget_tokens",number (budget_tokens value));("tokenizer",JString "o200k_base")].
Fixpoint finish_entries texts costs budgets observations := match texts,costs,budgets,observations with
 | [],[],[],[] => Some []
 | text::texts,cost::costs,budget::budgets,observed::observations =>
   let selected := if cost <=? budget then Some Original else
     match F.decode observation_fields observed with Some fields =>
       match preview_command_for text budget cost (observations_of_values fields) with
       | Some (Finished selected) => Some selected | _ => None end | None => None end in
   match selected,finish_entries texts costs budgets observations with
   | Some selected,Some rest => Some (selected_preview text cost budget selected :: rest) | _,_ => None end
 | _,_,_,_ => None end.
Definition finish texts source := match costs_of source,get source "previews" with
 | Some costs,JArray observations => finish_entries texts costs (allocation_values costs) observations
 | _,_ => None end.
End Budgeted.
