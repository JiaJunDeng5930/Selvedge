module type Model = sig
  type json
  val selvedge_parse_json : string -> json option
  val selvedge_render_json : json -> string
end

module Make (M : Model) = struct
  let parse text =
    match M.selvedge_parse_json text with
    | Some value -> value
    (* DEFENSE: Public callers can supply malformed JSON text. The Gallina
       decoder decides admission; this boundary reports its rejection. *)
    | None -> invalid_arg "Invalid domain JSON input"
  let stringify = M.selvedge_render_json
end
