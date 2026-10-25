open Js_of_ocaml
module Model = KernelModel
module Json = Json_io.Make(Model)

(* World values stay opaque inside this worker; only domain JSON crosses IO. *)
let initial () = Model.selvedge_kernel_initial
let input_error name message =
  Js.Unsafe.obj [| "inputError", Js.Unsafe.inject (Js.Unsafe.obj [|
    "name", Js.Unsafe.inject (Js.string name);
    "message", Js.Unsafe.inject (Js.string message)
  |]) |]
let with_input source apply =
  match Model.selvedge_parse_input_json (Js.to_string source) with
  | TextJson.InputAccepted value -> apply value
  | TextJson.InputInvalid -> input_error "TypeError" "Invalid domain JSON input"
  | TextJson.InputNestingExceeded -> input_error "RangeError" Model.selvedge_input_nesting_error
let packet source world = with_input source (fun input ->
  let world, envelope = Model.selvedge_kernel_packet input world in
  Js.Unsafe.obj [|
    "world", Js.Unsafe.inject world;
    "envelope", Js.Unsafe.inject (Js.string (Json.stringify envelope))
  |])
let observe world = Js.string (Json.stringify (Model.selvedge_kernel_world_json world))
let assess source world = with_input source (fun input ->
  Js.Unsafe.obj [| "envelope", Js.Unsafe.inject
    (Js.string (Json.stringify (Model.selvedge_kernel_assess input world))) |])
let () = Js.Unsafe.set Js.Unsafe.global "__selvedgeKernel" (Js.Unsafe.obj [|
  "initial", Js.Unsafe.inject (Js.wrap_callback initial);
  "packet", Js.Unsafe.inject (Js.wrap_callback packet);
  "observe", Js.Unsafe.inject (Js.wrap_callback observe);
  "assess", Js.Unsafe.inject (Js.wrap_callback assess)
|])
