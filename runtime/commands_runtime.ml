open Js_of_ocaml
module Model = CommandsModel
module Json = Json_io.Make(Model)

(* Developer inspection uses the very decoder and encoder called by the kernel. *)
let decode source =
  match Model.selvedge_commands_decode (Json.parse (Js.to_string source)) with
  | None -> Js.null
  | Some command -> Js.some (Js.string (Json.stringify (Model.selvedge_commands_encode command)))
let () = Js.Unsafe.set Js.Unsafe.global "__selvedgeCommands" (Js.Unsafe.obj [|
  "decode", Js.Unsafe.inject (Js.wrap_callback decode)
|])
