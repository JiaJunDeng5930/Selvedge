From Selvedge.Interaction.Submission Require Observation.

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
