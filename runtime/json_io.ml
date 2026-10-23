module type Model = sig
  type json =
    | JNull
    | JBool of bool
    | JNumber of string
    | JString of string
    | JArray of json list
    | JObject of (string * json) list
  val selvedge_parse_json : string -> json option
  val selvedge_render_json : json -> string
  val selvedge_input_nesting : Big_int_Z.big_int
  val selvedge_input_nesting_error : string
  val selvedge_consume_input_nesting : Big_int_Z.big_int -> Big_int_Z.big_int option
end

module Make (M : Model) = struct
  let raise_input_exn name message =
    let module Js = Js_of_ocaml.Js in
    let error : Js.error Js.t = Js.Unsafe.new_obj
      (Js.Unsafe.get Js.Unsafe.global name) [| Js.Unsafe.inject (Js.string message) |] in
    Js.Js_error.raise_ (Js.Js_error.of_error error)

  let parse text =
    match M.selvedge_parse_json text with
    | Some value -> value
    (* DEFENSE: Public callers can supply malformed JSON text. The Gallina
       decoder decides admission; this boundary reports its rejection. *)
    | None -> raise_input_exn "TypeError" "Invalid domain JSON input"
  let stringify = M.selvedge_render_json

  (* Canonical JavaScript JSON values cross through constructors, never through
     the extracted runtime's private representation. Raw text still uses parse. *)
  let string_of_js_exn value =
    (* DEFENSE: JavaScript permits lone UTF-16 surrogates; conversion to UTF-8
       would otherwise replace a value that the Gallina JSON parser rejects. *)
    if Js_of_ocaml.Js.to_bool
         (Js_of_ocaml.Js.Unsafe.meth_call value "isWellFormed" [||])
    then Js_of_ocaml.Js.to_string value
    else raise_input_exn "TypeError" "Invalid domain JSON input"

  let number_of_text_exn text =
    (* DEFENSE: A structured caller may provide a malformed number token;
       the existing Gallina parser remains its lexical authority. *)
    match M.selvedge_parse_json (Js_of_ocaml.Js.to_string text) with
    | Some (M.JNumber _ as number) -> number
    | _ -> raise_input_exn "TypeError" "Invalid domain JSON input"

  let rec of_js_at_exn nesting value ~number_text =
    let child_nesting = match M.selvedge_consume_input_nesting nesting with
      | Some remaining -> remaining
      (* DEFENSE: Public structured callers can supply a value deeper than the admitted input budget. *)
      | None -> raise_input_exn "RangeError" M.selvedge_input_nesting_error in
    let module Js = Js_of_ocaml.Js in
    match Js.to_string (Js.typeof value) with
    | "string" -> M.JString (string_of_js_exn (Js.Unsafe.coerce value))
    | "boolean" -> M.JBool (Js.to_bool (Js.Unsafe.coerce value))
    | "number" ->
      (match Js.Optdef.to_option (number_text value) with
       | Some text -> number_of_text_exn text
       | None -> raise_input_exn "TypeError" "Invalid domain JSON input")
    | "object" ->
      if Js.Unsafe.strict_equals value Js.null then M.JNull
      else
        (match Js.Optdef.to_option (number_text value) with
         | Some text -> number_of_text_exn text
         | None ->
           if Js.to_bool (Js.Unsafe.fun_call
               (Js.Unsafe.pure_js_expr "Array.isArray") [| value |]) then
             M.JArray (Array.fold_right (fun item items ->
               of_js_at_exn child_nesting item ~number_text :: items)
               (Js.to_array (Js.Unsafe.coerce value)) [])
           else
             M.JObject (Array.fold_right (fun key fields ->
               let name = string_of_js_exn key in
               (name, of_js_at_exn child_nesting (Js.Unsafe.get value key) ~number_text) :: fields)
               (Js.to_array (Js.object_keys (Js.Unsafe.coerce value))) []))
    (* DEFENSE: Public structured calls can contain undefined, functions or
       symbols; none is a JSON value after the shared codec canonicalizes it. *)
    | _ -> raise_input_exn "TypeError" "Invalid domain JSON input"
  let of_js_exn value ~number_text =
    of_js_at_exn M.selvedge_input_nesting value ~number_text
end
