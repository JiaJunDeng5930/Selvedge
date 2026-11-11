From Selvedge.Foundation Require TextMetrics Utf8.
From Selvedge.Interaction.Submission Require Observation.
From Selvedge.Browser Require Application.

(* Evaluate the same pure projection at most once per prepared state. A
   snapshot can install a different state before asking to see its scene. *)
Extract Constant Selvedge.Browser.Application.defer_scene => "
  (fun project ->
    let result = lazy (project ()) in
    fun () -> Lazy.force result)".

(* Both validators accept exactly UTF-8 encodings of Unicode scalar values.
   The native validator scans bytes without copying each remaining suffix. *)
Extract Constant Selvedge.Foundation.Utf8.well_formed => "Stdlib.String.is_valid_utf_8".

(* The prepared browser runtime retains the same immutable JSON list across
   view and input observations. Keep one decoded catalog, keyed by that list. *)
Extract Constant Selvedge.Interaction.Submission.Observation.reuse_catalog_decoder => "
  (fun decode ->
    let previous = ref None in
    fun rows ->
      match !previous with
      | Some (same_rows, catalog) when rows == same_rows -> catalog
      | _ ->
          let catalog = decode rows in
          previous := Some (rows, catalog);
          catalog)".

(* Counting a cumulative stream through extracted string constructors copies
   suffixes. Decode each scalar in place with the standard library. The UTF-16
   unit count cannot exceed the native string's byte length. *)
Extract Constant Selvedge.Foundation.TextMetrics.utf16_units => "
  (fun source ->
    let length = Stdlib.String.length source in
    let rec count offset units =
      if offset = length then Some (Big_int_Z.big_int_of_int units)
      else
        let decoded = Stdlib.String.get_utf_8_uchar source offset in
        if Stdlib.Uchar.utf_decode_is_valid decoded then
          let scalar = Stdlib.Uchar.utf_decode_uchar decoded in
          let width = Stdlib.Uchar.utf_16_byte_length scalar / 2 in
          count (offset + Stdlib.Uchar.utf_decode_length decoded) (units + width)
        else None
    in
    count 0 0)".
