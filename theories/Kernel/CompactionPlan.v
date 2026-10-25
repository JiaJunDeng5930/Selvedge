From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Utf8 TextJson Sequence.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Numbers Codec Compaction ContextSelection.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition scalar_fragments (source : string) := option_map
 (fun values => List.rev_append (fold_left (fun reversed value => snd value :: reversed) values []) []) (Utf8.chunks source).
Definition portable_source (value : source) : option source :=
 match value with
 | PortableSource fragments => Some (PortableSource fragments)
 | NativeSource _ raw => option_map PortableSource (scalar_fragments (TextJson.render_json raw)) end.
Definition to_portable (value : compaction_state) :=
 option_map (fun source => set compaction_source (fun _ => source) value) (portable_source (compaction_source value)).
Fixpoint contains_image (value : json) : bool :=
 match value with
 | JArray values => existsb contains_image values
 | JObject fields => existsb (fun entry =>
   (String.eqb (fst entry) "type" && (Json.equal (snd entry) (JString "image") || Json.equal (snd entry) (JString "input_image"))) ||
   contains_image (snd entry)) fields
 | _ => false end.
Definition start_with_images (has_images : bool) (history raw : json) (provider : string) (method : method) (input_tokens window reserve : N) :=
 let value := CompactionState (NativeSource history raw) 0 "" window window reserve in
 if negb has_images && String.eqb provider "chatgpt" &&
    (match method with Automatic => true | Summary => false end) && (input_tokens + reserve <=? window)
 then Some value else to_portable value.
Definition chunk (value : compaction_state) :=
 match compaction_source value with NativeSource _ _ => []
 | PortableSource unread => Sequence.take (N.to_nat (compaction_chunk_chars value)) unread end.
Definition plan_json (value : compaction_state) :=
 JObject ([("method", JString (match compaction_source value with NativeSource _ _ => "native" | _ => "portable" end));
   ("window_tokens", number (compaction_window_tokens value));
   ("output_reserve_tokens", number (compaction_output_reserve value))] ++
   match compaction_source value with
   | NativeSource history _ => [("history", history)]
   | PortableSource _ => [("chunk", JString (String.concat "" (chunk value)));
       ("carry", JString (compaction_carry value)); ("prompt", JString summary_prompt)] end)%list.
Definition plan_bytes (value : compaction_state) := N.of_nat (String.length (TextJson.render_json (plan_json value))).
Definition with_width (width : N) (value : compaction_state) := set compaction_chunk_chars (fun _ => width) value.
Definition has_transport_work (value : compaction_state) :=
 match compaction_source value with NativeSource _ _ => true
 | PortableSource [] => true | PortableSource (_ :: _) => 0 <? compaction_chunk_chars value end.
Definition transport_fits (value : compaction_state) (budget : N) := has_transport_work value && (plan_bytes value <=? budget).
Definition rebase_note (value : compaction_state) :=
 match compaction_source value with
 | NativeSource _ _ => None
 | PortableSource unread =>
   match scalar_fragments ("Prior continuation note:" ++ String (Ascii.ascii_of_nat 10) (compaction_carry value) ++
       String (Ascii.ascii_of_nat 10) "Unread task history:" ++ String (Ascii.ascii_of_nat 10) "") with
   | None => None
   | Some prefix => Some (set compaction_carry (fun _ => "")
       (set compaction_source (fun _ => PortableSource (List.rev_append (List.rev_append prefix []) unread)) value)) end end.
Definition fitted_width (value : compaction_state) (budget : N) :=
 with_width (N.min (compaction_chunk_chars value) ((budget - plan_bytes (with_width 0 value)) / 6)) value.
Definition fit_portable (value : compaction_state) (budget : N) :=
 if plan_bytes (with_width 0 value) + 6 <=? budget then Some (fitted_width value budget)
 else option_map (fun rebased => fitted_width rebased budget) (rebase_note value).
Definition fit_transport (value : compaction_state) (budget : N) :=
 match compaction_source value with
 | PortableSource _ => fit_portable value budget
 | NativeSource _ _ => if transport_fits value budget then Some value
   else match to_portable value with Some value => fit_portable value budget | None => None end end.

Inductive step := Next (state : compaction_state) | Compacted (candidate : artifact) | Failed (reason : string).
Definition receive_source (value : compaction_state) (result : json) :=
 match compaction_source value with
 | NativeSource _ _ => match decode_artifact result with
   | Some (NativeArtifact head tail first rest usage) => Compacted (NativeArtifact head tail first rest usage)
   | _ => Failed "The native compactor returned an invalid replacement window" end
 | PortableSource unread => match string_field "summary_text" result with
   | Some (String head tail) =>
     let summary := String head tail in
     match skipn (N.to_nat (compaction_chunk_chars value)) unread with
     | [] => Compacted (PortableArtifact (PortableMessage PortableAssistant summary) [] (value_or_null "usage" result))
     | remaining => Next (CompactionState (PortableSource remaining)
       (compaction_cursor value + N.of_nat (List.length (chunk value))) summary
       (compaction_chunk_chars value) (compaction_window_tokens value) (compaction_output_reserve value)) end
   | _ => Failed "The compactor returned an empty continuation note" end end.
Definition resize (value : compaction_state) :=
 if 1 <? compaction_chunk_chars value then match to_portable value with
 | Some converted => Next (with_width (compaction_chunk_chars value / 2) converted)
 | None => Failed "Compaction history is not valid UTF-8" end
 else Failed "Compaction request exceeds the configured model window".
Definition receive (value : compaction_state) (result : json) :=
 match string_field "action" result with
 | Some "resize" => resize value
 | Some "native_unavailable" => match compaction_source value with
   | NativeSource _ _ => match to_portable value with Some converted => Next converted | None => Failed "Compaction history is not valid UTF-8" end
   | _ => receive_source value result end
 | _ => receive_source value result end.
